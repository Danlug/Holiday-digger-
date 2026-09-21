#!/usr/bin/env python3
"""import_robert.py — нарезка авторского листа садовника Роберта.

Лист (art/_source/robert_sheet.png, 1024×312, серый фон ~#979797): портрет
слева и два ряда справа — "IDLE ANIMATION SEQUENCE" и "TALKING ANIMATION
SEQUENCE". Подписи над рядами утверждают "8 FRAMES", но пронумерованы с
повтором (1,2,3,4,4,5,6,7,8 — числа считаны с самого листа, не выдуманы):
считаем реальные фигуры разбором связных компонент, а не по подписи —
их по ДЕВЯТЬ в каждом ряду (см. отчёт задачи). Ничего страшного: и
CutscenePlayer, и character_view делят ширину листа на CHAR_FRAME сами,
им всё равно, восемь кадров или девять.

Формат результата — тот же, что читает CutscenePlayer._show_actor и что
режут остальные листы актёров (art/character/<dir>/<pose>.png, кадр
48×48 логических = 144×144 текстурных, CHAR_FRAME в cutscene_player.gd):
art/character/robert/idle.png, art/character/robert/talk.png. Портрет —
art/character/robert/portrait.png, крупнее, для карточки реплики (сейчас
в диалоговой коробке нет слота под портрет — файл просто лежит про запас).

Приёмы — те же, что в import_art.py/import_drill.py:
  1. фон вычитается заливкой от краёв (серый ~(151,151,151), не белый и не
     чёрный — обычный порог по цвету срезал бы светлую рубашку или тёмные
     сапоги вместе с фоном);
  2. tone_match приводит лист к общему эталону (свой у Роберта — сравнивать
     не с чем, лист один, но функция всё равно приводит яркость/насыщенность
     к тому же REF_LUM/REF_SAT, чтобы Роберт не выделялся рядом с дедом и
     бабкой тоном);
  3. масштаб — по росту деда (art/character/grandpa/idle.png): Роберт
     взрослый садовник, не мельче и не крупнее хозяина дома.

Раскладка колонок кадров найдена в два прохода (лист даёт мелкие зазоры
между соседними шляпами при поиске по всей высоте фигуры — они сливаются в
один кусок): сначала колонки ищутся по УЗКОЙ полосе на уровне торса (там
зазоры между кадрами широкие и чистые), а затем бокс кадра достраивается по
ПОЛНОЙ высоте ряда в уже найденных границах X.

Запуск:  python3 tools/import_robert.py art/_source/robert_sheet.png
"""

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import (ART_SCALE, FOOT_PAD, FRAME_H, FRAME_W,  # noqa: E402
                        shrink, tone_match)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BG_RGB = (151, 151, 151)
BG_TOL = 16

# Полосы по Y (без подписей и заголовков — найдены разбором листа, см. отчёт).
IDLE_BODY_BAND = (60, 171)     # фигуры ряда idle (ниже заголовка листа,
                                # подписи "IDLE ANIMATION SEQUENCE" и цифр "1".."8")
IDLE_TORSO_BAND = (100, 150)   # узкая полоса для поиска ГРАНИЦ кадров (широкие зазоры)
TALK_BODY_BAND = (197, 303)    # фигуры ряда talk

FRAMES = 9   # реальных фигур в каждом ряду (не 8 — см. шапку файла)
COL_X0, COL_X1 = 190, 1024     # часть листа с рядами (портрет — левее)

PORTRAIT_BOX = (35, 34, 148, 288)

GROUND_Y = FRAME_H - FOOT_PAD
ANCHOR_BAND = 14   # высота полосы для якоря по голове/шляпе, px исходника


def background_mask(im):
    px = im.load()
    w, h = im.size
    mask = bytearray(w * h)
    seen = bytearray(w * h)
    stack = []
    for x in range(w):
        stack.append((0, x)); stack.append((h - 1, x))
    for y in range(h):
        stack.append((y, 0)); stack.append((y, w - 1))
    while stack:
        y, x = stack.pop()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        r, g, b = px[x, y]
        if abs(r - g) > 8 or abs(g - b) > 8 or abs(r - BG_RGB[0]) > BG_TOL:
            continue
        mask[i] = 1
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    return mask


def frame_columns(mask, w, y0, y1, x0, x1, nframes):
    used = [any(not mask[y * w + x] for y in range(y0, y1 + 1)) for x in range(x0, x1)]
    runs, start = [], None
    for i, u in enumerate(used):
        if u and start is None:
            start = i
        elif not u and start is not None:
            runs.append([start, i - 1]); start = None
    if start is not None:
        runs.append([start, len(used) - 1])
    gaps = sorted(((runs[i + 1][0] - runs[i][1] - 1, i) for i in range(len(runs) - 1)), reverse=True)
    cuts = sorted(i for _, i in gaps[:nframes - 1])
    out, s = [], 0
    for c in cuts:
        out.append((runs[s][0] + x0, runs[c][1] + x0)); s = c + 1
    out.append((runs[s][0] + x0, runs[-1][1] + x0))
    if len(out) != nframes:
        raise SystemExit(f"ожидалось {nframes} кадров, нашлось {len(out)}: {out}")
    return out


def content_bbox(mask, w, x0, x1, y0, y1):
    xs, ys = [], []
    for y in range(y0, y1 + 1):
        row = y * w
        for x in range(x0, x1 + 1):
            if not mask[row + x]:
                xs.append(x); ys.append(y)
    if not xs:
        raise SystemExit(f"пусто в колонке {x0}-{x1}, строках {y0}-{y1}")
    return min(xs), min(ys), max(xs), max(ys)


def cut(im, mask, box):
    x0, y0, x1, y1 = box
    w = im.size[0]
    out = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
    src, dst = im.load(), out.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if not mask[y * w + x]:
                dst[x - x0, y - y0] = src[x, y] + (255,)
    return out


def anchor_x(mask, w, box):
    """Центр масс верхней полосы содержимого (шляпа/голова) — тот же приём,
    что anchor_x в import_drill.py: рамка кадра гуляет из-за жестов рукой на
    talk-кадрах, шляпа — нет."""
    x0, y0, x1, _ = box
    xs = [x for y in range(y0, min(y0 + ANCHOR_BAND, box[3]))
          for x in range(x0, x1 + 1) if not mask[y * w + x]]
    return sum(xs) / float(len(xs)) if xs else (x0 + x1) / 2.0


def build_sheet(sheet, mask, w, boxes, k, ground, colors=30):
    out = Image.new("RGBA", (FRAME_W * len(boxes), FRAME_H), (0, 0, 0, 0))
    for i, b in enumerate(boxes):
        piece = cut(sheet, mask, b)
        ax = anchor_x(mask, w, b)
        tw = max(1, round(piece.size[0] * k))
        th = max(1, round(piece.size[1] * k))
        small = shrink(piece, (tw, th), colors=colors)
        # центр кадра — якорь (голова), а не геометрическая середина бокса:
        # так фигура не гуляет вбок между кадрами с разным жестом руки.
        dx = round(FRAME_W / 2.0 - (ax - b[0]) * k)
        dy = round(GROUND_Y - (ground - b[1] + 1) * k)
        out.alpha_composite(small, (i * FRAME_W + dx, dy))
    return out


def main(path):
    sheet = Image.open(path).convert("RGB")
    w, h = sheet.size
    print("лист:", sheet.size)
    mask = background_mask(sheet)
    before = _avg_tone(sheet, mask)
    sheet = tone_match(sheet, mask)
    after = _avg_tone(sheet, mask)
    print(f"тон: было {before}, стало {after}")

    # 1. границы кадров по узкой торс-полосе (широкие чистые зазоры)
    idle_cols = frame_columns(mask, w, *IDLE_TORSO_BAND, COL_X0, COL_X1, FRAMES)
    talk_cols = frame_columns(mask, w, *TALK_BODY_BAND, COL_X0, COL_X1, FRAMES)
    print("idle колонки:", idle_cols)
    print("talk колонки:", talk_cols)

    # 2. полный бокс кадра (шляпа-сапоги) в уже найденных границах X
    idle_boxes = [content_bbox(mask, w, x0, x1, *IDLE_BODY_BAND) for x0, x1 in idle_cols]
    talk_boxes = [content_bbox(mask, w, x0, x1, *TALK_BODY_BAND) for x0, x1 in talk_cols]

    # 3. масштаб — рост Роберта как у деда (BODY_H = рост героя, тот же
    #    целевой рост используют все взрослые персонажи, см. import_art.py).
    #    Опорный кадр — первая поза idle (прямая стойка).
    ref = idle_boxes[0]
    src_h = ref[3] - ref[1]
    from import_art import BODY_H
    k = BODY_H / src_h
    print(f"рост Роберта: {src_h} px исходника -> {BODY_H} px, масштаб {k:.4f}")

    ground_idle = max(b[3] for b in idle_boxes)
    ground_talk = max(b[3] for b in talk_boxes)

    out_dir = os.path.join(ROOT, "art", "character", "robert")
    os.makedirs(out_dir, exist_ok=True)

    idle_sheet = build_sheet(sheet, mask, w, idle_boxes, k, ground_idle)
    idle_sheet.save(os.path.join(out_dir, "idle.png"))
    print("записано", os.path.join(out_dir, "idle.png"), idle_sheet.size)

    talk_sheet = build_sheet(sheet, mask, w, talk_boxes, k, ground_talk)
    talk_sheet.save(os.path.join(out_dir, "talk.png"))
    print("записано", os.path.join(out_dir, "talk.png"), talk_sheet.size)

    portrait = cut(sheet, mask, PORTRAIT_BOX)
    pk = min(1.0, 220.0 / portrait.size[0])
    portrait = shrink(portrait, (max(1, round(portrait.size[0] * pk)),
                                  max(1, round(portrait.size[1] * pk))), colors=40)
    portrait.save(os.path.join(out_dir, "portrait.png"))
    print("записано", os.path.join(out_dir, "portrait.png"), portrait.size)


def _avg_tone(sheet, mask):
    """Для печати — средний цвет фигуры (не фона), просто чтобы видеть эффект
    tone_match в консоли, как у остальных импортёров."""
    w, h = sheet.size
    px = sheet.load()
    xs = [(x, y) for y in range(43, 170) for x in range(COL_X0, COL_X1)
          if not mask[y * w + x]]
    if not xs:
        return (0, 0, 0)
    r = sum(px[x, y][0] for x, y in xs) / len(xs)
    g = sum(px[x, y][1] for x, y in xs) / len(xs)
    b = sum(px[x, y][2] for x, y in xs) / len(xs)
    return (round(r, 1), round(g, 1), round(b, 1))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("укажи путь к листу: python3 tools/import_robert.py sheet.png")
    main(sys.argv[1])

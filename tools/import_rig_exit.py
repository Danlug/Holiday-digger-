#!/usr/bin/env python3
"""import_rig_exit.py — нарезка авторского листа выхода из бурмобиля.

Лист (art/_source/rig_exit_sheet.jpg, 1836×560): семь КЛЮЧЕВЫХ поз, не кадры
покадровой анимации. Художник прислал ключи и подписал под каждым, сколько
кадров держится переход к нему ("FRAME 1-8" и т.п.) — это фазы будущей
анимации, между ключами без интерполяции (пиксель-арт, см. art/PALETTE.md).

Верхний ряд (ключи 1-4) — купол кабины: закрыт и едет, начинает открываться,
открыт и герой сидит, герой встаёт в кабине. Нижний ряд (ключи 5-7) — герой
уже вне машины: прыжок из кабины назад, приземление на корточки, стоит рядом
с машиной. Раскладка и длительности фаз даны владельцем (см. отчёт задачи).

Отличия от import_drill.py (тот же лист-стиль, но там кадры одного набора —
здесь семь РАЗНЫХ ключевых поз, и в последних трёх герой отдельная фигура,
а не часть машины):

  1. Фон вычитается заливкой от краёв (тёмно-серый ~#22292d, не чёрный) — тот
     же приём, что в import_drill.py.
  2. Подписи "FRAME N-M" вырезаются по КОНКРЕТНЫМ прямоугольникам (найдены
     разбором связных компонент), а не по общей полосе: в ключах 5-7 подпись
     по высоте перекрывается с мачтой открытого купола — общая полоса срезала
     бы мачту вместе с текстом.
  3. Масштаб машины — тот же коэффициент, что у dig_rig_side.png: сравниваем
     ширину корпуса (с буром, включая остриё — та же условность, что в
     import_drill.boxes) на ключе 1 (машина едет, купол закрыт — поза,
     сравнимая с "рабочим" кадром drill_sheet.jpg) с шириной корпуса на
     drill_sheet.jpg и целимся в тот же RIG_WIDTH_CELLS*TILE.
  4. В ключах 1-4 герой сидит В кабине — масштаб машины и герой в кабине
     ОДНИМ изображением (так же, как в dig_rig_side/down.png: перерисовывать
     героя внутри кабины отдельным масштабом означало бы разъехаться с
     рукой на руле и куполом над головой). В ключах 5-7 герой уже снаружи —
     вырезается ОТДЕЛЬНО от машины (по наиболее узкой колонке — острие бура
     сходит на нет, герой начинается за ним) и масштабируется как остальные
     листы героя (BODY_H), чтобы после ключа 7 не было скачка размера при
     переходе на обычный idle/walk.

Запуск:  python3 tools/import_rig_exit.py art/_source/rig_exit_sheet.jpg
"""

import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import ART_SCALE, BODY_H, TILE, shrink, tone_match  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BG_RGB = (34, 42, 45)
BG_TOL = 40

# Колонки ключей на листе (x0, x1) — найдены разбором связных компонент по
# полосе содержимого без подписей. Ряд 1 (купол): ключи 1-4. Ряд 2 (герой
# снаружи): ключи 5-7.
KEY_COLS = {
    1: (67, 294), 2: (381, 611), 3: (681, 936), 4: (1007, 1303),
    5: (474, 810), 6: (955, 1263), 7: (1397, 1721),
}
# Полный диапазон по высоте, где может быть содержимое ключа (без заголовка
# листа сверху) — уже, чем весь лист, чтобы случайная пыль по краям не
# попала в бокс.
KEY_ROWS = {1: (70, 310), 2: (70, 310), 3: (70, 310), 4: (70, 310),
            5: (310, 540), 6: (310, 540), 7: (310, 540)}

# Прямоугольники подписей "FRAME N-M" — исключаются из бокса содержимого
# точечно (не целой полосой): у ключей 5-7 подпись по Y пересекается с
# мачтой поднятого купола, и полоса срезала бы её вместе с текстом.
CAPTION_RECTS = {
    1: (85, 84, 221, 109), 2: (398, 84, 534, 109),
    3: (772, 84, 907, 109), 4: (1130, 84, 1267, 109),
    5: (589, 319, 673, 344), 6: (1053, 319, 1191, 344),
    7: (1510, 319, 1646, 344),
}

# Длительности фаз в кадрах (при ANIM_FPS катсцены/character_view — см.
# rig_exit.json ниже), подписаны художником под каждым ключом: "FRAME 1-8" у
# первых трёх и у последнего, "1-4", "1-6", "1-7" у промежуточных.
PHASE_FRAMES = [8, 8, 8, 4, 6, 7, 8]
ANIM_FPS = 7.0  # тот же темп, что CutscenePlayer.ANIM_FPS — единый язык кадра

# Кадр итогового листа: машина (RIG_FRAME_W-совместимая ширина) плюс герой
# рядом (ключ 7) — считано так, чтобы оба поместились с запасом (см. шапку).
# 96 логических не хватило: герой в ключах 5-7 стоит достаточно далеко от
# машины (прыгнул назад через весь её габарит) и на 96 обрезался о правый
# край кадра — печать импортёра (bx+btw) показала перехлёст, отсюда 116.
FRAME_W = 116 * ART_SCALE
FRAME_H = 56 * ART_SCALE
GROUND_Y = 50 * ART_SCALE  # линия земли — та же, что у dig_rig_*.png (RIG_GROUND_Y)

RIG_WIDTH_CELLS = 2  # ГДД п.5 — машина 2×1, как в import_drill.py


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
        if (abs(r - BG_RGB[0]) + abs(g - BG_RGB[1]) + abs(b - BG_RGB[2])) > BG_TOL:
            continue
        mask[i] = 1
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    return mask


def in_rect(x, y, rect):
    x0, y0, x1, y1 = rect
    return x0 <= x <= x1 and y0 <= y <= y1


def content_bbox(mask, w, x0, x1, y0, y1, exclude=None):
    xs, ys = [], []
    for y in range(y0, y1 + 1):
        row = y * w
        for x in range(x0, x1 + 1):
            if exclude is not None and in_rect(x, y, exclude):
                continue
            if not mask[row + x]:
                xs.append(x); ys.append(y)
    if not xs:
        raise SystemExit(f"ключ в колонке {x0}-{x1}: содержимое не найдено")
    return min(xs), min(ys), max(xs), max(ys)


def cut(im, mask, box, exclude=None):
    x0, y0, x1, y1 = box
    w = im.size[0]
    out = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
    src, dst = im.load(), out.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if exclude is not None and in_rect(x, y, exclude):
                continue  # подпись "FRAME N-M" — не часть рисунка
            if not mask[y * w + x]:
                dst[x - x0, y - y0] = src[x, y] + (255,)
    return out


## Колонка, где машина (её остриё бура) отделяется от героя в ключах 5-7:
## минимум занятости столбца в правой части ключа — остриё сходит на нет
## до тонкой линии, герой сразу за ним снова толще.
def split_x(mask, w, x0, x1, y0, y1, exclude=None, search_from_frac=0.5, end_margin=20):
    # Ищем ровно ту точку, где остриё бура сходит на нет: минимум занятости
    # столбца, но не у самого правого края ключа — там снова редеет собственный
    # контур героя (нога на отлёте, край силуэта), и слепой глобальный минимум
    # уезжал в него, а не в перехват между машиной и героем.
    search_x0 = x0 + int((x1 - x0) * search_from_frac)
    search_x1 = x1 - end_margin
    best_x, best_c = None, None
    for x in range(search_x0, search_x1 + 1):
        c = sum(1 for y in range(y0, y1 + 1)
                if not mask[y * w + x] and not (exclude is not None and in_rect(x, y, exclude)))
        if best_c is None or c <= best_c:
            best_c, best_x = c, x
    return best_x


def main(path):
    sheet = Image.open(path).convert("RGB")
    w, h = sheet.size
    print("лист:", sheet.size)
    mask = background_mask(sheet)
    sheet = tone_match(sheet, mask)

    # 1. бокс содержимого каждого ключа (без подписи)
    boxes = {}
    for k, (x0, x1) in KEY_COLS.items():
        y0, y1 = KEY_ROWS[k]
        boxes[k] = content_bbox(mask, w, x0, x1, y0, y1, exclude=CAPTION_RECTS[k])
        print(f"ключ {k}: бокс {boxes[k]}, {boxes[k][2]-boxes[k][0]}×{boxes[k][3]-boxes[k][1]}")

    # 2. масштаб машины — ширина корпуса на ключе 1 (едет, купол закрыт,
    #    сравнимо с рабочим кадром drill_sheet.jpg) -> RIG_WIDTH_CELLS клеток.
    rig_src_w = boxes[1][2] - boxes[1][0]
    k_rig = RIG_WIDTH_CELLS * TILE / rig_src_w
    print(f"машина: {rig_src_w} px исходника -> {RIG_WIDTH_CELLS * TILE} px, масштаб {k_rig:.4f}")

    # 3. масштаб героя, когда он отдельная фигура (ключи 5-7) — по росту на
    #    ключе 7 (стоит прямо, поза сравнима с idle.png).
    sx7 = split_x(mask, w, *KEY_COLS[7], *KEY_ROWS[7], exclude=CAPTION_RECTS[7])
    boy7_box = content_bbox(mask, w, sx7 + 1, KEY_COLS[7][1], *KEY_ROWS[7])
    boy_src_h = boy7_box[3] - boy7_box[1]
    k_hero = BODY_H / boy_src_h
    print(f"герой (ключ 7): {boy_src_h} px исходника -> {BODY_H} px, масштаб {k_hero:.4f}")

    ground = boxes[1][3]  # линия земли — низ ключа 1 (машина на ходу, без прыжка)

    out_dir = os.path.join(ROOT, "art", "character")
    os.makedirs(out_dir, exist_ok=True)
    env_dir = os.path.join(ROOT, "art", "env")
    os.makedirs(env_dir, exist_ok=True)

    sheet_out = Image.new("RGBA", (FRAME_W * 7, FRAME_H), (0, 0, 0, 0))
    stand_dx = 0.0  # где стоит герой в ключе 7 относительно центра машины (лог. px)

    for idx in range(1, 8):
        b = boxes[idx]
        if idx in (1, 2, 3, 4):
            # машина + герой в кабине — одно изображение, масштаб машины.
            piece = cut(sheet, mask, b, exclude=CAPTION_RECTS[idx]).crop((0, 0, b[2] - b[0] + 1, b[3] - b[1] + 1))
            tw = max(1, round(piece.size[0] * k_rig))
            th = max(1, round(piece.size[1] * k_rig))
            small = shrink(piece, (tw, th), colors=32)
            dx = round(FRAME_W / 2.0 - (b[2] - b[0] + 1) * k_rig / 2.0)
            dy = round(GROUND_Y - (ground - b[1] + 1) * k_rig)
            sheet_out.alpha_composite(small, ((idx - 1) * FRAME_W + dx, dy))
        else:
            sx = split_x(mask, w, *KEY_COLS[idx], *KEY_ROWS[idx], exclude=CAPTION_RECTS[idx])
            car_box = content_bbox(mask, w, KEY_COLS[idx][0], sx, *KEY_ROWS[idx])
            boy_box = content_bbox(mask, w, sx + 1, KEY_COLS[idx][1], *KEY_ROWS[idx])

            car_piece = cut(sheet, mask, car_box, exclude=CAPTION_RECTS[idx])
            ctw = max(1, round(car_piece.size[0] * k_rig))
            cth = max(1, round(car_piece.size[1] * k_rig))
            car_small = shrink(car_piece, (ctw, cth), colors=32)
            # Машина центрируется в СВОЁМ кадре — так же, как в ключах 1-4
            # (там центровка тоже по собственной ширине кадра, а не привязана
            # к соседям). Ключи 1-4 и 5-7 лежат в РАЗНЫХ строках исходного
            # листа — сравнивать их абсолютные пиксельные координаты нельзя,
            # только величины ВНУТРИ одного ключа (car_box и boy_box одного
            # idx — один и тот же кусок листа, поделённый пополам).
            cx = round(FRAME_W / 2.0 - (car_box[2] - car_box[0] + 1) * k_rig / 2.0)
            cy = round(GROUND_Y - (car_box[3] - car_box[1] + 1) * k_rig)
            frame_x0 = (idx - 1) * FRAME_W
            sheet_out.alpha_composite(car_small, (frame_x0 + cx, cy))

            boy_piece = cut(sheet, mask, boy_box, exclude=CAPTION_RECTS[idx])
            btw = max(1, round(boy_piece.size[0] * k_hero))
            bth = max(1, round(boy_piece.size[1] * k_hero))
            boy_small = shrink(boy_piece, (btw, bth), colors=28)
            bx = round(cx + (boy_box[0] - car_box[0]) * k_rig)
            by = round(GROUND_Y - (ground - boy_box[1] + 1) * k_hero)
            # Ноги героя привязаны к его СОБСТВЕННОЙ линии земли (низ его
            # бокса), а не к линии земли машины: он на корточках/в прыжке —
            # его "низ" не всегда стоит на земле, но в ключе 7 (стоит) это
            # ровно то же самое место.
            by = round(GROUND_Y - (boy_box[3] - boy_box[1] + 1) * k_hero)
            sheet_out.alpha_composite(boy_small, (frame_x0 + bx, by))

            if idx == 7:
                # Точка, где стоит герой в последнем ключе — для character_view:
                # смещение центра героя относительно центра кадра машины
                # (той же точки, что берёт world_view для машины на парковке).
                boy_center_local = bx + btw / 2.0
                car_center_local = round(FRAME_W / 2.0)
                stand_dx = (boy_center_local - car_center_local) / ART_SCALE

    sheet_out.save(os.path.join(out_dir, "rig_exit.png"))
    print("записано art/character/rig_exit.png,", sheet_out.size)

    # Машина без героя — вырезаем корпус ключа 7 (купол открыт, за рулём
    # никого) тем же car_box/масштабом, что уже посчитан выше в последней
    # итерации цикла (idx==7) — пересчитываем явно для ясности.
    sx7 = split_x(mask, w, *KEY_COLS[7], *KEY_ROWS[7], exclude=CAPTION_RECTS[7])
    car_box7 = content_bbox(mask, w, KEY_COLS[7][0], sx7, *KEY_ROWS[7])
    car_piece7 = cut(sheet, mask, car_box7, exclude=CAPTION_RECTS[7])
    ctw7 = max(1, round(car_piece7.size[0] * k_rig))
    cth7 = max(1, round(car_piece7.size[1] * k_rig))
    parked = shrink(car_piece7, (ctw7, cth7), colors=32)
    parked.save(os.path.join(env_dir, "drill_mobile_parked.png"))
    print("записано art/env/drill_mobile_parked.png,", parked.size)

    meta = {
        "_comment": "Выход/посадка в бурмобиль на поверхности (см. player.gd, "
                    "character_view.gd). Ключи 1..7 — купол закрыт-едет -> "
                    "открывается -> открыт -> герой встаёт -> прыжок назад -> "
                    "присел за машиной -> стоит рядом. Посадка — та же "
                    "последовательность ключей в обратном порядке (7..1).",
        "fps": ANIM_FPS,
        "phase_frames": PHASE_FRAMES,
        "frame_w": FRAME_W,
        "frame_h": FRAME_H,
        "ground_y": GROUND_Y,
        "art_scale": ART_SCALE,
        # Где стоит герой в ключе 7 (стоя рядом с припаркованной машиной) —
        # смещение от центра машины по X, в ЛОГИЧЕСКИХ px. Используется,
        # чтобы после анимации выхода поставить героя ровно на это место
        # относительно припаркованной машины (GameState.rig_parked_at).
        "stand_dx": round(stand_dx, 2),
    }
    with open(os.path.join(out_dir, "rig_exit.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("записано art/character/rig_exit.json:", meta)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("укажи путь к листу: python3 tools/import_rig_exit.py sheet.jpg")
    main(sys.argv[1])

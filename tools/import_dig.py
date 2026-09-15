#!/usr/bin/env python3
"""import_dig.py — нарезка авторского листа анимаций копки.

Лист: три ряда по восемь кадров — работа стальной киркой, лопатой и
дедовой ржавой киркой. Раньше эти анимации собирались из одной стоячей позы
(см. import_art.anim_dig): рука разбиралась на звенья и крутилась вокруг
плеча. Нарисованные кадры лучше во всём, поэтому процедурная сборка для
копки больше не нужна.

Два момента, которые здесь важнее обычной нарезки:

  1. ОБЩИЙ масштаб и ОБЩАЯ линия земли на весь лист. Кадры нарисованы
     каждый в своей позе, и если выравнивать по собственной рамке кадра,
     герой прыгает внутри клетки. Опора — рост в спокойной позе (ряд 3,
     кадр 1) и низ содержимого ряда, то есть земля под ногами.

  2. Фон вычитается заливкой от краёв, а не по порогу яркости: у персонажа
     чёрная обводка, и порог выел бы её вместе с фоном.

Реквизит (куча земли, камни) с кадров НЕ убирается: в игре герой копает
соседний тайл, и нарисованный обломок ложится ровно на него — это та
обратная связь, которой в копке не хватало.

Запуск:  python3 tools/import_dig.py art/_source/dig_sheet.jpg
"""

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import BODY_H, FOOT_PAD, FRAME_H, FRAME_W, shrink  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CELL_W = 128
FRAMES = 8

# Полосы рядов на листе: подписи «1-8» и заголовки в них не попадают.
ROWS = [
    ((30, 177), "dig_pick"),         # стальная кирка
    ((206, 338), "dig_shovel"),      # лопата
    ((357, 504), "dig_pick_rusty"),  # ржавая кирка деда
]

# Спокойная поза, по которой берётся рост: ряд 3, кадр 1.
REF = (2, 0)


def background_mask(im):
    """True там, где фон. Заливка от краёв: чёрная обводка персонажа цела."""
    px = im.load()
    w, h = im.size
    lim = 110

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
        if r + g + b > lim:
            continue
        mask[i] = 1
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    return mask


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


SLIVER_W = 14   # уже этого и с касанием края клетки — чужой кадр, не свой


def drop_slivers(img):
    """Убрать обрезки соседнего кадра.

    Кадры на листе стоят вплотную, и содержимое иногда переходит через
    границу клетки: у правого края появляется вертикальный обрывок чужой
    кирки. Выбрасываем связные куски, которые касаются левого или правого
    края клетки и при этом узкие. Широкие — свои (куча земли, камни у края),
    а мелкие крошки внутри кадра не трогаем: это разлетающаяся порода.
    """
    w, h = img.size
    px = img.load()
    seen = bytearray(w * h)
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or not px[sx, sy][3]:
                continue
            comp = []
            stack = [(sy, sx)]
            seen[sy * w + sx] = 1
            x0 = x1 = sx
            while stack:
                y, x = stack.pop()
                comp.append((x, y))
                if x < x0: x0 = x
                if x > x1: x1 = x
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and not seen[ny * w + nx] \
                                and px[nx, ny][3]:
                            seen[ny * w + nx] = 1
                            stack.append((ny, nx))
            if (x0 == 0 or x1 == w - 1) and (x1 - x0 + 1) < SLIVER_W:
                for x, y in comp:
                    px[x, y] = (0, 0, 0, 0)
    return img


def content_box(img):
    return img.getbbox()


def main(path):
    sheet = Image.open(path).convert("RGB")
    print("лист:", sheet.size)
    mask = background_mask(sheet)

    # 1. вырезаем все 24 кадра как есть
    cells = {}
    for r, ((y0, y1), _) in enumerate(ROWS):
        for i in range(FRAMES):
            img = cut(sheet, mask, (i * CELL_W, y0, (i + 1) * CELL_W - 1, y1))
            cells[(r, i)] = drop_slivers(img)

    # 2. рост в спокойной позе задаёт масштаб для ВСЕГО листа
    ref = content_box(cells[REF])
    ref_h = ref[3] - ref[1]
    k = BODY_H / ref_h
    print(f"рост в спокойной позе: {ref_h} px исходника -> {BODY_H} px, масштаб {k:.4f}")

    for r, ((y0, y1), name) in enumerate(ROWS):
        # 3. земля ряда — самый низ содержимого по всем кадрам ряда
        ground = max(content_box(cells[(r, i)])[3] for i in range(FRAMES))
        sheet_out = Image.new("RGBA", (FRAME_W * FRAMES, FRAME_H), (0, 0, 0, 0))

        for i in range(FRAMES):
            cell = cells[(r, i)]
            b = content_box(cell)
            if b is None:
                continue
            piece = cell.crop(b)
            tw = max(1, round(piece.size[0] * k))
            th = max(1, round(piece.size[1] * k))
            small = shrink(piece, (tw, th), colors=28)

            # якорь: середина клетки по X, земля ряда по Y
            dx = round((b[0] - CELL_W / 2.0) * k) + FRAME_W // 2
            dy = FRAME_H - FOOT_PAD - round((ground - b[1]) * k)
            sheet_out.alpha_composite(small, (i * FRAME_W + dx, dy))

        out = os.path.join(ROOT, "art", "character", "boy", name + ".png")
        sheet_out.save(out)
        print(f"  {name:16s} <- ряд {r + 1}, земля y={ground}")

    # герой ищется рендерерами в art/character/
    for _, name in ROWS:
        src = os.path.join(ROOT, "art", "character", "boy", name + ".png")
        Image.open(src).save(os.path.join(ROOT, "art", "character", name + ".png"))
    print("готово")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("укажи путь к листу: python3 tools/import_dig.py sheet.jpg")
    main(sys.argv[1])

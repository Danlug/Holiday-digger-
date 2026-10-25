#!/usr/bin/env python3
"""contact_sheet.py — контрольный лист для проверки нарезанных кадров.

Берёт горизонтальный лист кадров (как в art/character/*.png — кадр за
кадром слева направо) и кладёт его на непрозрачный фон с подписанными
номерами кадров и границами клеток — так проще смотреть на PNG глазами
(через Read), чем прикидывать альфу на прозрачном фоне.

Запуск:  python3 tools/contact_sheet.py art/character/dig_pick.png 144 out.png
Дополнительно можно указать высоту клетки четвёртым аргументом (иначе — вся
высота листа).
"""

import os
import sys

from PIL import Image, ImageDraw

BG = (40, 44, 52)
GRID = (90, 96, 108)
LABEL = (240, 210, 90)
PAD = 24
LABEL_H = 18


def main(path, frame_w, out, frame_h=None):
    frame_w = int(frame_w)
    sheet = Image.open(path).convert("RGBA")
    w, h = sheet.size
    frame_h = int(frame_h) if frame_h else h
    n = w // frame_w

    cw = frame_w + PAD
    ch = frame_h + PAD + LABEL_H
    out_img = Image.new("RGBA", (cw * n, ch), BG + (255,))
    draw = ImageDraw.Draw(out_img)

    for i in range(n):
        cell = sheet.crop((i * frame_w, 0, (i + 1) * frame_w, frame_h))
        x0 = i * cw + PAD // 2
        y0 = LABEL_H + PAD // 2
        out_img.alpha_composite(cell, (x0, y0))
        draw.rectangle([i * cw, LABEL_H, i * cw + cw - 1, ch - 1], outline=GRID)
        draw.text((i * cw + 4, 2), f"{i + 1}", fill=LABEL)

    out_img.convert("RGB").save(out)
    print(f"{path}: {n} кадров {frame_w}x{frame_h} -> {out}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit("укажи: tools/contact_sheet.py <png> <frame_w> <out> [frame_h]")
    main(*sys.argv[1:])

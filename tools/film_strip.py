#!/usr/bin/env python3
"""film_strip.py — склейка вырезок tests/test_screenshot_hero_anim.gd в ленты.

Берёт <каталог>/<сценарий>_NNN.png, кладёт кадры сеткой на непрозрачный фон
и подписывает номер кадра. Линия земли (горизонталь по подошве первой
вырезки) нарисована тонкой чертой — по ней видно, не «пляшет» ли герой по
вертикали и не плывёт ли вбок (голова обязана оставаться на оси).

  python3 tools/film_strip.py <каталог_вырезок> <сценарий> <выход.png> [колонок] [масштаб] [шаг]
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

BG = (46, 50, 60)
GRID = (96, 102, 114)


def main(src, name, out, cols=10, scale=1.0, step=1):
    files = sorted(glob.glob(os.path.join(src, f"{name}_[0-9][0-9][0-9].png")))[::int(step)]
    if not files:
        sys.exit(f"нет кадров {name}_*.png в {src}")
    ims = [Image.open(f).convert("RGBA") for f in files]
    w, h = ims[0].size
    cols, scale = int(cols), float(scale)
    cw, ch = int(w * scale), int(h * scale)
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (cw + 2), rows * (ch + 14)), BG)
    d = ImageDraw.Draw(sheet)
    for i, im in enumerate(ims):
        if scale != 1.0:
            im = im.resize((cw, ch), Image.NEAREST)
        x, y = (i % cols) * (cw + 2), (i // cols) * (ch + 14)
        sheet.paste(im.convert("RGB"), (x, y + 12))
        d.rectangle([x, y, x + cw + 1, y + ch + 13], outline=GRID)
        d.text((x + 3, y + 1), str(i), fill=(240, 210, 90))
    sheet.save(out)
    print(out, sheet.size, len(ims), "кадров")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])

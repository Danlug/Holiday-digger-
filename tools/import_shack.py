#!/usr/bin/env python3
"""import_shack.py — стартовая лачуга деда, из art/_source/shack.jpg в
art/env/shack.png.

В отличие от house_rich.jpg (tools/import_house.py), тут фон РОВНЫЙ серый
(~146,146,146) со всех четырёх сторон — художник не рисовал ни неба, ни
мостовой в трёхчетвертной проекции. Поэтому и резать проще: заливка фона от
краёв, обрезка по содержимому, никакого BOTTOM_FRACTION не нужно.

Важно: владелец уже один раз ругался, что дом обрезали — здесь НИЧЕГО не
отрезается сверху/снизу по высоте кроме однородного фона: антенна, труба с
дымом, дрова, ящики, фонарь, топор, верёвка перед домом остаются в кадре
целиком. Единственная обрезка — это сама рамка непрозрачного содержимого
после вычитания фона.

Сцена (intro_grandpa) показывает лачугу как реквизит ДО того, как в игре
появляется богатый дом бабки (art/env/house_rich.png, ГДД: "за высоким
забором бабка живёт в роскоши"): используется только во времена деда.

Запуск:  python3 tools/import_shack.py
"""

import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_move import background_mask, cut  # noqa: E402 — своя заливка/вырезка, серый фон

SRC = os.path.join(ROOT, "art", "_source", "shack.jpg")
OUT = os.path.join(ROOT, "art", "env", "shack.png")

BG = (146, 146, 146)
BG_TOL = 18

# Итоговая высота спрайта. Реквизит показывается на сцене катсцены (не на
# игровой сетке), поэтому число подобрано по глазу — так, чтобы дом на сцене
# занимал примерно ту же долю ширины, что и art/env/house_rich.png на своей
# сцене после смены века (не крупнее и не мельче богатого дома, иначе смена
# заметна не по факту домов, а по масштабу спрайта).
TARGET_H = 210


def main() -> None:
    im = Image.open(SRC).convert("RGB")
    w, h = im.size
    print("лист:", im.size)

    mask = background_mask(im, bg=BG, tol=BG_TOL)
    full = cut(im, mask, (0, 0, w - 1, h - 1))

    box = full.getbbox()
    if box is None:
        sys.exit("не нашлось непрозрачных пикселей — проверь BG/BG_TOL")
    content = full.crop(box)
    print("содержимое:", content.size, "box=", box)

    k = TARGET_H / content.size[1]
    target_w = max(1, round(content.size[0] * k))
    out = content.resize((target_w, TARGET_H), Image.LANCZOS)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)
    print(f"{os.path.relpath(OUT, ROOT)}: {out.size}")


if __name__ == "__main__":
    main()

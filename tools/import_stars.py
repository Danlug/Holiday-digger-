#!/usr/bin/env python3
"""import_stars.py — вырезает звёзды с зелёной подложки в атлас для неба.

Лист (art/_source/stars_sheet.jpg, 1024×559) — россыпь ~20 звёзд (белые,
голубые, жёлтые; кресты, 4-лучевые ромбы, мелкие точки) на ровном зелёном
фоне (~76,152,55). Хромакей по евклидову расстоянию до фона: гистограмма
расстояний на этом листе резко распадается на два кластера — фон/JPEG-шум
держится ниже ~10, сами звёзды выше ~200 — поэтому порог с небольшим
линейным рэмпом (T_LOW..T_HIGH) даёт чистый край без ручной подгонки под
конкретный кадр.

На линейном рэмпе (частично прозрачные пиксели) цвет деконтаминируется от
зелёной подложки по формуле unpremultiply: color = (observed - (1-a)*bg)/a,
иначе на полупрозрачном краю звезды проступает зелёный ободок.

Сегментация — связные компоненты (8-связность), как в import_garden.py:
проще и устойчивее, чем вручную обводить ~20 фигур разной формы.

Каждая звезда уменьшается (см. import_art.shrink — та же LANCZOS-логика с
премультиплеенной альфой) до случайного размера 3–7 логических px по
большей стороне (ART_SCALE=3 → 9–21 текстурных px, см. задание владельца
"мелкие"), сид детерминирован — повторный запуск даёт тот же атлас.

Результат — один атлас art/env/stars.png (звёзды в ряд с прозрачными
промежутками) плюс art/env/stars.json с регионами
{"regions": [{"x":.., "y":.., "w":.., "h":..}, ...]} — так SkyView не должен
грузить десятки отдельных файлов текстур.

Запуск:  python3 tools/import_stars.py
"""

import json
import os
import random
import sys
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_art import ART_SCALE, shrink  # noqa: E402

SRC = os.path.join(ROOT, "art", "_source", "stars_sheet.jpg")
OUT_PNG = os.path.join(ROOT, "art", "env", "stars.png")
OUT_JSON = os.path.join(ROOT, "art", "env", "stars.json")

BG = (76, 152, 55)
# Гистограмма расстояний до фона на этом листе распадается на два чётких
# кластера: фон/JPEG-шум держится ниже ~10, сами звёзды — выше ~200 (см.
# докстринг). Поэтому порог почти бинарный: T_LOW..T_HIGH — узкий рэмп
# ТОЛЬКО для честного антиалиасинга кромки, а не для растянутой JPEG-дымки,
# на которой unpremultiply-деконтаминация (a→0) взрывается шумом и красит
# край в ядовито-зелёный/лаймовый ободок — она была на первой версии этого
# скрипта, отчего и правится здесь.
T_LOW = 30.0
T_HIGH = 45.0
AREA_MIN = 6   # компоненты мельче — шум JPEG у кромки фона

# "мелкие" (задание владельца): 3-7 логических px по большей стороне.
MIN_LOGICAL_PX = 3
MAX_LOGICAL_PX = 7
SEED = 20260921  # дата задачи — детерминирует случайный целевой размер


def _dist(px, bg):
    r, g, b = px
    return ((r - bg[0]) ** 2 + (g - bg[1]) ** 2 + (b - bg[2]) ** 2) ** 0.5


def _alpha_and_color(im):
    """Строит RGBA-изображение: почти бинарная альфа (см. T_LOW/T_HIGH выше)
    с узким рэмпом честного края, плюс лёгкое подавление зелёного отсвета
    (spill suppression: G не выше max(R,B) — у палитры звёзд, бело-голубой/
    жёлтой, так по построению и должно быть, значит это безопасно и не
    портит настоящий цвет) БЕЗ деления на альфу, которое на редких шумных
    пикселях листа улетает в перенасыщенный цвет."""
    w, h = im.size
    src = im.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dst = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = src[x, y]
            d = _dist((r, g, b), BG)
            if d <= T_LOW:
                continue
            a = 255 if d >= T_HIGH else round(255 * (d - T_LOW) / (T_HIGH - T_LOW))
            g = min(g, max(r, b))
            dst[x, y] = (r, g, b, a)
    return out


def _label(rgba):
    """Связные компоненты (8-связность) по пикселям с ненулевой альфой.
    Возвращает labels-массив и список {"box": (x0,y0,x1,y1), "area": int} в
    растровом порядке первого вхождения — детерминировано между запусками."""
    w, h = rgba.size
    a = rgba.getchannel("A")
    ap = a.load()
    labels = [0] * (w * h)
    comps = []
    next_id = 1
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if ap[x, y] == 0 or labels[i]:
                continue
            cid = next_id
            next_id += 1
            q = deque([(x, y)])
            labels[i] = cid
            area = 0
            x0 = x1 = x
            y0 = y1 = y
            while q:
                cx, cy = q.popleft()
                area += 1
                x0, x1 = min(x0, cx), max(x1, cx)
                y0, y1 = min(y0, cy), max(y1, cy)
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if dx == 0 and dy == 0:
                            continue
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h:
                            j = ny * w + nx
                            if ap[nx, ny] != 0 and not labels[j]:
                                labels[j] = cid
                                q.append((nx, ny))
            comps.append({"id": cid, "box": (x0, y0, x1, y1), "area": area})
    comps = [c for c in comps if c["area"] >= AREA_MIN]
    return labels, comps


def _cut(rgba, labels, w, comp_id, box):
    x0, y0, x1, y1 = box
    out = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
    src = rgba.load()
    dst = out.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if labels[y * w + x] == comp_id:
                dst[x - x0, y - y0] = src[x, y]
    return out


def main():
    sheet = Image.open(SRC).convert("RGB")
    w, h = sheet.size
    print("лист:", sheet.size)

    rgba = _alpha_and_color(sheet)
    labels, comps = _label(rgba)
    print(f"звёзд найдено (area>={AREA_MIN}): {len(comps)}")

    rng = random.Random(SEED)
    small = []
    for c in comps:
        cut = _cut(rgba, labels, w, c["id"], c["box"])
        target_logical = rng.uniform(MIN_LOGICAL_PX, MAX_LOGICAL_PX)
        target_px = max(2, round(target_logical * ART_SCALE))
        # большая сторона -> target_px, вторая сохраняет пропорцию исходника
        cw, ch = cut.size
        if cw >= ch:
            tw, th = target_px, max(1, round(ch * target_px / cw))
        else:
            th, tw = target_px, max(1, round(cw * target_px / ch))
        img = shrink(cut, (tw, th))
        small.append(img)

    # Атлас: звёзды в ряд слева направо с 1px зазором, высота — максимум.
    # Одна строка достаточно короткого атласа (макс. 21px * ~20 = ~450px по
    # ширине) — сложность 2D-упаковки здесь не нужна.
    gap = 1
    atlas_h = max(im.size[1] for im in small)
    atlas_w = sum(im.size[0] for im in small) + gap * (len(small) - 1)
    atlas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))
    regions = []
    x = 0
    for img in small:
        iw, ih = img.size
        atlas.paste(img, (x, 0), img)
        regions.append({"x": x, "y": 0, "w": iw, "h": ih})
        x += iw + gap

    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    atlas.save(OUT_PNG)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump({
            "source": "art/_source/stars_sheet.jpg",
            "art_scale": ART_SCALE,
            "count": len(regions),
            "regions": regions,
        }, f, ensure_ascii=False, indent=2)

    print(f"атлас: {atlas.size}, регионов: {len(regions)}")
    print(" ", os.path.relpath(OUT_PNG, ROOT))
    print(" ", os.path.relpath(OUT_JSON, ROOT))


if __name__ == "__main__":
    main()

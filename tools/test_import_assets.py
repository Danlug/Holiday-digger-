#!/usr/bin/env python3
"""test_import_assets.py — проверки нарезки нового арта (не Godot-тест, а
дополнение к нему: числа, которые бессмысленно проверять внутри движка —
количество вырезанных объектов, метрика бесшовности травы).

Не входит в обязательный набор `godot --headless --script tests/*` — тот
проверяет, что игра ВИДИТ файлы и они не ломают сцену/мир. Этот скрипт
проверяет, что сама НАРЕЗКА не деградировала (склеились/распались объекты,
разошёлся шов травы), до того как результат попадёт в движок.

Запуск:  python3 tools/test_import_assets.py
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

failures = []


def check(label, ok):
    print(("[OK] " if ok else "[FAIL] ") + label)
    if not ok:
        failures.append(label)


def test_garden_objects():
    from import_garden import GROUPS
    check("import_garden: в GROUPS ровно 22 объекта (20 предметов + 2 пучка травы)",
          len(GROUPS) == 22)
    d = os.path.join(ROOT, "art", "env", "garden")
    files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    check("art/env/garden: 22 файла на диске", len(files) == 22)
    for name in GROUPS:
        p = os.path.join(d, name + ".png")
        check(f"art/env/garden/{name}.png существует и не пустой",
              os.path.exists(p) and Image.open(p).getbbox() is not None)


def test_grass_seamless():
    d = os.path.join(ROOT, "art", "tiles")
    for name in ("grass_1", "grass_2"):
        p = os.path.join(d, name + ".png")
        check(f"art/tiles/{name}.png существует", os.path.exists(p))
        im = Image.open(p).convert("RGB")
        check(f"{name}: размер 96×96 (TILE*ART_SCALE)", im.size == (96, 96))
        a = np.asarray(im).astype(float)
        # шов: разница между последним и первым столбцом (после укладки тайлов
        # подряд именно эти столбцы становятся соседями)
        seam = np.mean((a[:, -1, :] - a[:, 0, :]) ** 2)
        neighbor = np.mean((a[:, 1:, :] - a[:, :-1, :]) ** 2)
        ratio = seam / max(1.0, neighbor)
        # ratio считается по одному столбцу (шумно), поэтому порог мягкий —
        # проверяем ПОРЯДОК величины, а не точное совпадение с отчётом
        check(f"{name}: шов не в разы заметнее обычного перехода (ratio={ratio:.2f} < 6)",
              ratio < 6.0)


def test_shack():
    p = os.path.join(ROOT, "art", "env", "shack.png")
    im = Image.open(p)
    check("art/env/shack.png существует", os.path.exists(p))
    check("shack.png имеет альфа-канал (фон вычтен)", im.mode == "RGBA")
    box = im.getbbox()
    check("shack.png: содержимое занимает почти весь кадр (ничего не обрезано мимо)",
          box is not None and box[2] - box[0] > im.width * 0.9)


def test_ages():
    d = os.path.join(ROOT, "art", "character", "boy")
    ages = [8, 9, 10, 11, 12, 15]
    sizes = set()
    heights = []
    for a in ages:
        p = os.path.join(d, f"age_{a}.png")
        check(f"age_{a}.png существует", os.path.exists(p))
        im = Image.open(p)
        sizes.add(im.size)
        box = im.getbbox()
        heights.append(box[3] - box[1] if box else 0)
    check("все возрасты на холсте одного размера (общая линия земли)", len(sizes) == 1)
    check("возраст 15 заметно выше возраста 8 (рост читается)",
          heights[-1] > heights[0] * 1.15)


## Выход/посадка в бурмобиль (tools/import_rig_exit.py): семь ключевых поз в
## одном листе плюс отдельная припаркованная машина без героя.
def test_rig_exit():
    p = os.path.join(ROOT, "art", "character", "rig_exit.png")
    check("art/character/rig_exit.png существует", os.path.exists(p))
    im = Image.open(p)
    import json as _json
    jp = os.path.join(ROOT, "art", "character", "rig_exit.json")
    check("art/character/rig_exit.json существует", os.path.exists(jp))
    meta = _json.load(open(jp, encoding="utf-8"))
    frames = 7
    fw = int(meta.get("frame_w", 0))
    check("rig_exit.png: ширина листа кратна семи кадрам", fw > 0 and im.size[0] == fw * frames)
    check("rig_exit.png: высота кадра совпадает с метаданными", im.size[1] == int(meta.get("frame_h", 0)))
    check("rig_exit.json: семь длительностей фаз", len(meta.get("phase_frames", [])) == frames)
    check("rig_exit.json: длительности фаз положительные",
          all(int(n) > 0 for n in meta.get("phase_frames", [])))
    check("rig_exit.json: есть точка, где стоит герой у машины (stand_dx)",
          "stand_dx" in meta)
    for i in range(frames):
        crop = im.crop((i * fw, 0, (i + 1) * fw, im.size[1]))
        check(f"rig_exit.png: кадр {i + 1} не пустой", crop.getbbox() is not None)

    parked = os.path.join(ROOT, "art", "env", "drill_mobile_parked.png")
    check("art/env/drill_mobile_parked.png существует", os.path.exists(parked))
    if os.path.exists(parked):
        pim = Image.open(parked)
        check("drill_mobile_parked.png не пустой", pim.getbbox() is not None)


## Роберт (tools/import_robert.py): idle/talk по девять кадров, портрет.
def test_robert():
    d = os.path.join(ROOT, "art", "character", "robert")
    for pose in ("idle", "talk"):
        p = os.path.join(d, pose + ".png")
        check(f"art/character/robert/{pose}.png существует", os.path.exists(p))
        if not os.path.exists(p):
            continue
        im = Image.open(p)
        check(f"{pose}.png: кадр 144×144 (CHAR_FRAME)", im.size[1] == 144 and im.size[0] % 144 == 0)
        frames = im.size[0] // 144
        check(f"{pose}.png: девять кадров (реальных фигур на листе, не восемь по подписи)",
              frames == 9)
        for i in range(frames):
            crop = im.crop((i * 144, 0, (i + 1) * 144, 144))
            check(f"{pose}.png: кадр {i + 1} не пустой", crop.getbbox() is not None)
    portrait = os.path.join(d, "portrait.png")
    check("art/character/robert/portrait.png существует", os.path.exists(portrait))
    if os.path.exists(portrait):
        check("portrait.png не пустой", Image.open(portrait).getbbox() is not None)


def main():
    test_garden_objects()
    test_grass_seamless()
    test_shack()
    test_ages()
    test_rig_exit()
    test_robert()
    print(f"\n=== Итог: {'OK' if not failures else str(len(failures)) + ' провалов'} ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

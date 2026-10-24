#!/usr/bin/env python3
"""test_cutout.py — авторская графика без светлой каймы (в стиле test_import_assets.py).

Не Godot-тест: проверяет сами PNG, до движка. Три вещи:

  1. доля каймы (tools/check_fringe.py) у каждого чищеного файла реестра —
     не выше FRINGE_MAX; у светлого по рисунку — не выше своего предела
     (LIGHT_BY_NATURE: метрика не отличает лепесток или снег от каймы);
  2. defringe по файлу ничего не меняет — файл в «неподвижной точке», то
     есть чистка применена, и переимпорт без неё (старым скриптом) или
     замена PNG на грязный сразу видны;
  3. импортёры авторских листов зовут defringe перед записью.

Запуск:  python3 tools/test_cutout.py        (≈15 с)
         python3 tools/test_cutout.py --fast  (без пункта 2)
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_fringe import AUTHORED, FRINGE_MAX, ROOT, measure  # noqa: E402
from defringe import defringe, params_for  # noqa: E402

# Светлое по рисунку на кромке — предел свой (было до чистки → после).
LIGHT_BY_NATURE = {
    "art/env/sun.png": 0.10,                       # 96 % → 8: голубые карманы между лучами
    "art/env/shack.png": 0.10,                     # 15 → 8: светлые кончики тростника
    "art/env/garden/daisies.png": 0.10,            # лепестки ромашек
    "art/env/garden/flowers_dragonfly.png": 0.13,  # белые крылья стрекоз
    "art/env/garden/stone_1.png": 0.10,            # кончики травы у камня
    "art/env/garden/grass_weeds_1.png": 0.10,      # светлые колоски
    "art/items/drill_rig_icon_titanium.png": 0.08,  # блик на стеклянном куполе
    "art/items/drill_rig_icon_platinum.png": 0.08,
}
# облака: белое тело там, где тёмный контур прерван, — та же «светлая кромка»
CLOUD_LIMIT = 0.20

IMPORTERS = ("import_art.py", "import_pickaxes.py", "import_rig_icon.py", "import_rig_exit.py",
             "import_house.py", "import_shack.py", "import_clouds.py", "import_garden.py",
             "rig_drill_recolor.py")

failures = []


def check(label, ok):
    print(("[OK] " if ok else "[FAIL] ") + label)
    if not ok:
        failures.append(label)


def cleaned():
    return [rel for rel in AUTHORED if params_for(rel) is not None]


def test_fringe_share():
    for rel in cleaned():
        limit = LIGHT_BY_NATURE.get(rel, CLOUD_LIMIT if "/clouds/" in rel else FRINGE_MAX)
        frac = measure(os.path.join(ROOT, rel))["frac"]
        check(f"{rel}: кайма {frac * 100:.1f}% ≤ {limit * 100:.0f}%", frac <= limit)


def test_fixed_point():
    for rel in cleaned():
        img = Image.open(os.path.join(ROOT, rel)).convert("RGBA")
        out = defringe(img, **params_for(rel))
        diff = int((np.asarray(out) != np.asarray(img)).any(-1).sum())
        check(f"{rel}: defringe ничего не меняет (изменилось бы {diff} px)", diff == 0)


def test_registry():
    for rel in AUTHORED:
        check(f"реестр: {rel} существует", os.path.exists(os.path.join(ROOT, rel)))
    check("реестр не пуст и без art/character/** (зона героя)",
          len(AUTHORED) > 50 and not any(r.startswith("art/character/") for r in AUTHORED))


def test_importers_call_defringe():
    for name in IMPORTERS:
        with open(os.path.join(ROOT, "tools", name), encoding="utf-8") as f:
            src = f.read()
        check(f"tools/{name} зовёт defringe перед записью", "defringe(" in src)


if __name__ == "__main__":
    test_registry()
    test_importers_call_defringe()
    test_fringe_share()
    if "--fast" not in sys.argv:
        test_fixed_point()
    print(f"=== Итог: {len(failures)} провалов ===")
    sys.exit(1 if failures else 0)

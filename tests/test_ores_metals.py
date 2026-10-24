#!/usr/bin/env python3
"""Тест спрайтов металлов и топлива (tools/ores_metals.py), без Godot.

  python3 tests/test_ores_metals.py

Проверяет: каждый спрайт 32x32 и непустой, с контуром (непрозрачные пиксели граничат с пустыми), занимает разумную
долю клетки; для всех своих ресурсов есть значок; среди СВОИХ ресурсов нет похожих пар и невидимых на грунте
(check_ores.py целиком учитывает ещё и ресурсы второй ветки — они здесь не участвуют).
"""

import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import check_ores as co  # noqa: E402
import ores_metals as om  # noqa: E402

TILE_NAMES = ["ore_iron", "ore_lead", "ore_silver", "ore_copper", "ore_aluminium", "ore_nickel", "ore_platinum",
              "ore_titanium", "ore_lithium", "ore_mercury", "ore_gold", "ore_scrap", "ore_peat", "ore_coal", "ore_uranium"]
ICON_IDS = ["iron_ore", "lead", "silver", "copper", "aluminium", "nickel", "platinum", "titanium", "lithium", "mercury",
            "gold", "scrap", "peat", "coal", "uranium", "bronze", "fuel_block", "fuel_block_coal"]

checks = 0
fails = 0


def check(name, ok):
    global checks, fails
    checks += 1
    if not ok:
        fails += 1
        print("ПРОВАЛ:", name)


def has_outline(alpha):
    solid = alpha > 127
    pad = np.pad(solid, 1)
    border = solid & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    return border.sum() >= 12


for n in TILE_NAMES:
    check(f"тайл {n} зарегистрирован", n in om.TILES)
    if n not in om.TILES:
        continue
    img = om.TILES[n]().img
    a = np.array(img)[..., 3]
    check(f"{n}: 32x32", img.size == (32, 32))
    share = (a > 127).mean()
    check(f"{n}: заполняет 15..60% клетки ({share:.2f})", 0.15 <= share <= 0.60)
    check(f"{n}: есть контур", has_outline(a))
    check(f"{n}: углы клетки свободны (грунт виден)", (a[:2, :2] > 127).sum() == 0 and (a[-2:, -2:] > 127).sum() == 0)

for i in ICON_IDS:
    check(f"значок {i} зарегистрирован или есть тайл", i in om.ICONS or ("ore_" + i) in om.TILES)
    if i not in om.ICONS:
        continue
    img = om.ICONS[i]().icon()
    a = np.array(img)[..., 3]
    check(f"значок {i}: 32x32", img.size == (32, 32))
    share = (a > 127).mean()
    check(f"значок {i}: заполняет 20..80% ({share:.2f})", 0.20 <= share <= 0.80)
    check(f"значок {i}: есть контур", has_outline(a))

data, soils = co.collect()
mine = [n for n in TILE_NAMES if n in data]
check("все свои тайлы видны сборщику check_ores", len(mine) == len(TILE_NAMES))
for k, a in enumerate(mine):
    check(f"{a}: перерисован спрайтом", data[a]["src"] == "спрайт")
    check(f"{a}: виден на грунте всех поясов (ΔE {co.contrast(data[a], soils):.1f} >= {co.MIN_CONTRAST})",
          co.contrast(data[a], soils) >= co.MIN_CONTRAST)
    for b in mine[k + 1:]:
        de, shape, _ = co.pair_metrics(data[a], data[b])
        check(f"{a} / {b} не слишком похожи (ΔE {de:.1f}, форма {shape:.2f})", not co.too_similar(de, shape))

print(f"=== Итог: {checks} проверок, {fails} провалов ===")
sys.exit(0 if fails == 0 else 1)

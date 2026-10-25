#!/usr/bin/env python3
"""test_ores_gems.py — проверки графики ветки «ores-gems» без Godot: спрайты самоцветов, глубинных руд и добычи монстров.

Что проверяем: каждый спрайт 32x32 и непустой; у залежи (тайл) края и углы остаются грунту, а тело занимает разумную
долю клетки; у значка есть тёмный/светлый контур по краю и он стоит по центру; для каждого id есть значок, он записан
на диск и совпадает с тем, что рисует генератор (иначе забыли python3 tools/gen_ore_icons.py); id значков существуют в
data/minerals.json; tools/check_ores.py по этим тайлам говорит «OK».

Запуск:  python3 tests/test_ores_gems.py
"""
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import ores_gems  # noqa: E402

TILES = [
    "ore_diamond", "ore_ruby", "ore_emerald", "ore_geocrystal", "ore_ancient_metal", "ore_obsidian",
    "ore_hellstone", "ore_dark_matter", "ore_universalium", "ore_angelstone", "ore_divine_heart",
]
MONSTER_ICONS = ["cinder_ash", "moth_dust", "hopper_fang", "mimic_geode", "spark_core", "warden_plate", "abyss_core", "idol_shard"]
TILE_TO_ID = {"ore_universalium": "universum"}

failures = []


def check(label, ok):
    print(("[OK] " if ok else "[FAIL] ") + label)
    if not ok:
        failures.append(label)


def solid(img, thr=200):
    return np.array(img)[..., 3] >= thr


def main():
    check("реестр TILES содержит все 11 залежей", set(TILES) <= set(ores_gems.TILES))
    ids = [TILE_TO_ID.get(t, t[4:]) for t in TILES] + MONSTER_ICONS
    check("реестр ICONS содержит значок для каждого из 19 id", set(ids) <= set(ores_gems.ICONS))

    for name in TILES:
        spr = ores_gems.TILES[name]()
        img = spr.img
        check(f"{name}: спрайт 32x32 RGBA", img.size == (32, 32) and img.mode == "RGBA")
        m = solid(img)
        cover = m.mean()
        check(f"{name}: тело занимает 12..70% клетки ({cover:.0%})", 0.12 <= cover <= 0.70)
        corners = [m[:4, :4], m[:4, -4:], m[-4:, :4], m[-4:, -4:]]
        check(f"{name}: углы клетки оставлены грунту", all(c.sum() <= 2 for c in corners))
        border = np.concatenate([m[0], m[-1], m[:, 0], m[:, -1]])
        check(f"{name}: край клетки в основном свободен ({border.mean():.0%} занято)", border.mean() <= 0.3)
        a = np.array(img)
        edge = m & ~(np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1))
        lum = a[..., :3].astype(float) @ np.array([0.2126, 0.7152, 0.0722])
        body = m & ~edge
        # контур: кромка заметно отличается по яркости от тела (тёмная обводка или светлый ободок на тёмном теле)
        check(f"{name}: у залежи есть контур по кромке", edge.sum() >= 20 and abs(lum[edge].mean() - lum[body].mean()) >= 6)

    for rid in ids:
        spr = ores_gems.ICONS[rid]()
        img = spr.icon()
        m = solid(img)
        ys, xs = np.nonzero(m)
        check(f"значок {rid}: 32x32, не пуст", img.size == (32, 32) and m.sum() >= 120)
        check(f"значок {rid}: по центру ({xs.mean():.1f},{ys.mean():.1f})", abs(xs.mean() - 16) <= 4.5 and abs(ys.mean() - 16) <= 4.5)
        path = os.path.join(ROOT, "art", "ui", "shop", f"item_{rid}.png")
        ok = os.path.exists(path)
        if ok:
            ok = np.array_equal(np.array(Image.open(path).convert("RGBA")), np.array(img))
        check(f"значок {rid}: записан в art/ui/shop/item_{rid}.png и свежий (python3 tools/gen_ore_icons.py)", ok)
        mat = os.path.join(ROOT, "art", "gear", f"mat_{rid}.png")
        if os.path.exists(mat):
            check(f"значок {rid}: art/gear/mat_{rid}.png свежий", np.array_equal(np.array(Image.open(mat).convert("RGBA")), np.array(img)))

    minerals = json.load(open(os.path.join(ROOT, "data", "minerals.json"), encoding="utf-8"))["minerals"]
    known = {m["id"] for m in minerals}
    check("id значков есть в data/minerals.json", all(i in known for i in ids))

    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "check_ores.py"), "--only", ",".join(TILES), "--quiet"],
                       capture_output=True, text=True)
    print(r.stdout.strip())
    check("check_ores по залежам ветки: похожих пар и невидимых нет", r.returncode == 0)

    print(f"=== Итог: {len(failures)} провалов ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

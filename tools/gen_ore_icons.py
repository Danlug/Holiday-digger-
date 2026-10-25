#!/usr/bin/env python3
"""gen_ore_icons.py — значки ресурсов 32x32 из реестров tools/ores_metals.py и tools/ores_gems.py.

Пишет art/ui/shop/item_<id>.png (их берёт ShopArt.item_icon для рюкзака, склада, магазина, наград) и,
если такой файл уже есть, art/gear/mat_<id>.png (материалы боя). Значок ресурса из TILES без записи в ICONS —
сам спрайт тайла (та же сетка 32x32).

  python3 tools/gen_ore_icons.py
"""

import importlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOP = os.path.join(ROOT, "art", "ui", "shop")
GEAR = os.path.join(ROOT, "art", "gear")
TILE_TO_ID = {"ore_iron": "iron_ore", "ore_universalium": "universum"}


def mineral_id(tile_name):
    return TILE_TO_ID.get(tile_name, tile_name[4:] if tile_name.startswith("ore_") else tile_name)


def main():
    icons = {}
    for mod_name in ("ores_metals", "ores_gems"):
        try:
            m = importlib.import_module(mod_name)
        except ModuleNotFoundError as e:
            if e.name != mod_name:
                raise
            continue
        for tile, fn in getattr(m, "TILES", {}).items():
            icons[mineral_id(tile)] = fn
        icons.update(getattr(m, "ICONS", {}))
    os.makedirs(SHOP, exist_ok=True)
    for rid, fn in sorted(icons.items()):
        img = fn().icon()
        img.save(os.path.join(SHOP, f"item_{rid}.png"), optimize=True)
        mat = os.path.join(GEAR, f"mat_{rid}.png")
        if os.path.exists(mat):
            img.save(mat, optimize=True)
    print(f"значков записано: {len(icons)}  ({', '.join(sorted(icons))})")


if __name__ == "__main__":
    main()

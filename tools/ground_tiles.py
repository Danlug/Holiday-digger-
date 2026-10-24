#!/usr/bin/env python3
"""ground_tiles.py — перерисованные тайлы ЗЕМЛИ и КАМНЯ пояса 0 (ветка «ground»).

Контракт (читает tools/gen_tiles_deep.py при запуске, tools/import_tiles.py их не затирает):

  GROUND = {"dirt_1": fn, ..., "dirt_8": fn, "stone": fn}
      fn() -> numpy float64 (96, 96, 3), RGB 0..255: тайл 96x96 (сетка 32 x3), БЕСШОВНЫЙ по обоим краям (при мощении
      любой с любым соседом по сторонам не даёт шва), без рамки и без запечённой тёмной каймы.
  Земля — варианты ОДНОЙ светлоты (ГДД §15.1: разные по тону грунты в случайной раскладке дают лоскутное одеяло).

gen_tiles_deep.py пишет их в art/tiles/<имя>.png, затем собирает пояса 1..7 (тон пояса поверх, руды сверху).
После правки: python3 tools/gen_tiles_deep.py && python3 tools/gen_world_atlas.py && godot --headless --path . --import.
"""

GROUND = {}

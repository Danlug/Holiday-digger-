#!/usr/bin/env python3
"""ores_metals.py — спрайты металлов, топлива и «земляных» ресурсов (ветка «ores-metals»).

Контракт реестра (его читают tools/gen_tiles_deep.py, tools/gen_ore_icons.py, tools/check_ores.py):

  TILES = {"ore_iron": fn, ...}   # имя тайла -> fn() -> sprite_kit.Sprite: ЗАЛЕЖЬ на сетке 32x32 с альфой,
                                  # без грунта (грунт пояса подкладывает генератор: ore_<имя>.png для пояса 0
                                  # и ячейки атласов поясов 1..7).
  ICONS = {"iron_ore": fn, ...}   # id минерала из data/minerals.json -> fn() -> Sprite: значок ПРЕДМЕТА 32x32
                                  # (один предмет/кучка без грунта) -> art/ui/shop/item_<id>.png.
                                  # Для ресурса из TILES без записи в ICONS значком станет сам спрайт тайла.

Ресурсы этой ветки (тайл + значок): ore_iron, ore_lead, ore_silver, ore_copper, ore_aluminium, ore_nickel,
ore_platinum, ore_titanium, ore_lithium, ore_mercury, ore_gold, ore_scrap, ore_peat, ore_coal, ore_uranium.
Только значки: bronze, fuel_block, fuel_block_coal.
Соответствие имя тайла -> id минерала: ore_iron -> iron_ore, ore_universalium -> universum, остальные — без префикса ore_.
"""

TILES = {}
ICONS = {}

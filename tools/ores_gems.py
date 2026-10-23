#!/usr/bin/env python3
"""ores_gems.py — спрайты самоцветов, глубинных руд и добычи с монстров (ветка «ores-gems»).

Контракт реестра (его читают tools/gen_tiles_deep.py, tools/gen_ore_icons.py, tools/check_ores.py):

  TILES = {"ore_diamond": fn, ...}   # имя тайла -> fn() -> sprite_kit.Sprite: ЗАЛЕЖЬ на сетке 32x32 с альфой,
                                     # без грунта (грунт пояса подкладывает генератор).
  ICONS = {"diamond": fn, ...}       # id минерала/предмета -> fn() -> Sprite: значок ПРЕДМЕТА 32x32 без грунта
                                     # -> art/ui/shop/item_<id>.png (и art/gear/mat_<id>.png, если такой файл есть).
                                     # Для ресурса из TILES без записи в ICONS значком станет сам спрайт тайла.

Ресурсы этой ветки (тайл + значок): ore_diamond, ore_ruby, ore_emerald, ore_geocrystal, ore_ancient_metal,
ore_obsidian, ore_hellstone, ore_dark_matter, ore_universalium, ore_angelstone, ore_divine_heart.
Только значки (добыча монстров): cinder_ash, moth_dust, hopper_fang, mimic_geode, spark_core, warden_plate,
abyss_core, idol_shard.
Соответствие имя тайла -> id минерала: ore_universalium -> universum, остальные — без префикса ore_.
Восемь глубинных руд (geocrystal … divine_heart) сейчас рисуют функции sprite_* в tools/gen_tiles_deep.py:
переписывай их здесь (запись в TILES перекрывает старую), в gen_tiles_deep.py их не правь.
"""

TILES = {}
ICONS = {}

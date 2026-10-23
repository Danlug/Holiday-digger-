class_name UiIcons
extends RefCounted
## UiIcons — единая точка загрузки иконок интерфейса.
##
## Новые иконки лежат в art/ui/icons/<имя>.png (их рисует tools/gen_ui_icons.py),
## старые — в art/ui/icon_<имя>.png (hp, hunger, coin, backpack…). Вызывающему
## всё равно, где именно: UiIcons.tex("gear"), UiIcons.tex("coin"). Нет файла —
## null, и кнопка остаётся без картинки, а не падает.

const DIR := "res://art/ui/icons/%s.png"
const LEGACY := "res://art/ui/icon_%s.png"

static var _cache: Dictionary = {}


static func tex(icon_name: String) -> Texture2D:
	if _cache.has(icon_name):
		return _cache[icon_name]
	var t: Texture2D = null
	for pattern: String in [DIR, LEGACY]:
		var path := pattern % icon_name
		if ResourceLoader.exists(path):
			t = load(path)
			break
	_cache[icon_name] = t
	return t


## Иконка предмета рюкзака: у руд — тайл из мира, у еды и топлива — свои
## значки, остальное — общая звезда «находка».
static func item(id: String) -> Texture2D:
	var t := TileArt.texture_for(MineralMap.tile_type_for(id), 0, 0) if MineralMap.tile_type_for(id) >= 0 else null
	if t != null:
		return t
	# материалы боя (детали монстров и руды глубже 4000, у которых нет тайла)
	var combat_icon := CombatData.icon(id)
	if combat_icon != null:
		return combat_icon
	if HouseConfig.is_food(id):
		return tex("eat")
	if id == "fuel_block":
		return tex("fuel")
	return tex("star")

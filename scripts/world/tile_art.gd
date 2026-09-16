class_name TileArt
extends RefCounted
## Сопоставление TileTypes.Type <-> файл спрайта в art/tiles/.
## Портировано из web/world_dump.json (поле "art"), расширено на все типы,
## для которых есть графика. Типов без графики (материалы глубже 2000, см.
## GDD раздел 4) в словаре нет — рендерер рисует их плейсхолдером-заливкой,
## как и веб-демо для отсутствующих спрайтов.

const DIR := "res://art/tiles/"

static var _tile_to_file: Dictionary = {
	TileTypes.Type.EMPTY: "empty",
	TileTypes.Type.STONE: "stone",
	TileTypes.Type.FOUNDATION: "foundation",
	# Стены тоннеля Роберта — тот же железобетон, что и фундамент, и рисуются
	# тем же тайлом: отдельная графика не нужна, а общий вид как раз читается
	# правильно — «продолжение фундамента вверх».
	TileTypes.Type.REINFORCED: "foundation",
	TileTypes.Type.SCRAP_METAL: "ore_scrap",
	TileTypes.Type.IRON_ORE: "ore_iron",
	TileTypes.Type.LEAD_ORE: "ore_lead",
	TileTypes.Type.SILVER_ORE: "ore_silver",
	TileTypes.Type.COPPER_ORE: "ore_copper",
	TileTypes.Type.ALUMINIUM_ORE: "ore_aluminium",
	TileTypes.Type.GOLD_ORE: "ore_gold",
	TileTypes.Type.DIAMOND: "ore_diamond",
	TileTypes.Type.PEAT: "ore_peat",
	TileTypes.Type.COAL: "ore_coal",
	TileTypes.Type.NICKEL_ORE: "ore_nickel",
	TileTypes.Type.MERCURY_ORE: "ore_mercury",
	TileTypes.Type.PLATINUM_ORE: "ore_platinum",
	TileTypes.Type.TITANIUM_ORE: "ore_titanium",
	TileTypes.Type.LITHIUM_ORE: "ore_lithium",
	TileTypes.Type.URANIUM_ORE: "ore_uranium",
	TileTypes.Type.RUBY: "ore_ruby",
	TileTypes.Type.EMERALD: "ore_emerald",
	# DIRT рисуется отдельно — варианты по мировым координатам (см. ниже)
}

## Восемь вариантов земли: четыре разных грунта с листа, сведённых к одному
## тону (см. tools/import_tiles.py), и поворот каждого на 180°. Столько же
## должно грузиться в web/index.html — там список свой.
const DIRT_FILES := ["dirt_1", "dirt_2", "dirt_3", "dirt_4",
		"dirt_5", "dirt_6", "dirt_7", "dirt_8"]

static var _cache: Dictionary = {}

## Вариант земли по МИРОВЫМ координатам клетки (не экранным — иначе текстура
## "дрожит" при скролле, см. комментарий в web/index.html:drawTile).
static func dirt_variant(wx: int, wy: int) -> int:
	var a: int = (wx * 73856093) & 0xFFFFFFFF
	var b: int = (wy * 19349663) & 0xFFFFFFFF
	var h: int = (a ^ b) & 0xFFFFFFFF
	return h % DIRT_FILES.size()


## Текстура клетки по типу и мировым координатам (для варианта земли).
## Возвращает null, если графики для этого типа нет — рендерер должен
## нарисовать плейсхолдер-заливку.
static func texture_for(type: int, wx: int, wy: int) -> Texture2D:
	var file: String
	if type == TileTypes.Type.DIRT:
		file = DIRT_FILES[dirt_variant(wx, wy)]
	else:
		file = String(_tile_to_file.get(type, ""))
	if file.is_empty():
		return null
	return _load(file)


static func _load(file: String) -> Texture2D:
	if _cache.has(file):
		return _cache[file]
	var path := DIR + file + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_cache[file] = tex
	return tex

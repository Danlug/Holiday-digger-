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

## Два варианта тайла травы (tools/import_grass.py — один измеренный период
## бесшовного повтора, два сдвига разреза). Полоса из одного варианта на весь
## экран читалась бы штампом, поэтому вариант, как и у земли, зависит от
## мировой координаты.
const GRASS_FILES := ["grass_1", "grass_2"]
const DIR_GARDEN := "res://art/env/garden/"

static var _cache: Dictionary = {}

## Вариант земли по МИРОВЫМ координатам клетки (не экранным — иначе текстура
## "дрожит" при скролле, см. комментарий в web/index.html:drawTile).
static func dirt_variant(wx: int, wy: int) -> int:
	var a: int = (wx * 73856093) & 0xFFFFFFFF
	var b: int = (wy * 19349663) & 0xFFFFFFFF
	var h: int = (a ^ b) & 0xFFFFFFFF
	return h % DIRT_FILES.size()


## Тайл травы для клетки поверхности (y=0) по мировому x.
static func grass_texture(wx: int) -> Texture2D:
	var h: int = (wx * 2654435761) & 0xFFFFFFFF
	return _load(GRASS_FILES[h % GRASS_FILES.size()])


## Спрайт объекта огорода (art/env/garden/<name>.png) по имени из
## WorldGen.garden_decor_at(). Свой кеш-путь — файлы лежат в другой папке,
## чем тайлы шахты.
static func garden_texture(name: String) -> Texture2D:
	if name.is_empty():
		return null
	var key := "garden/" + name
	if _cache.has(key):
		return _cache[key]
	var path := DIR_GARDEN + name + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[key] = tex
	return tex


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

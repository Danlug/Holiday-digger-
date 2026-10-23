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
	# Нерушимая лестница у дома — тот же приём (владелец, 2026-09-21: «она
	# должна быть сделана из текстуры фундамента»): своей графики нет, и не
	# нужно — читается как та же несокрушимая порода.
	TileTypes.Type.STAIRCASE: "foundation",
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
	# материалы глубже 3000 и кладка руин (tools/gen_tiles_deep.py)
	TileTypes.Type.GEOCRYSTAL: "ore_geocrystal",
	TileTypes.Type.ANCIENT_METAL: "ore_ancient_metal",
	TileTypes.Type.OBSIDIAN: "ore_obsidian",
	TileTypes.Type.HELLSTONE: "ore_hellstone",
	TileTypes.Type.DARK_MATTER: "ore_dark_matter",
	TileTypes.Type.UNIVERSALIUM: "ore_universalium",
	TileTypes.Type.ANGEL_STONE: "ore_angelstone",
	TileTypes.Type.DIVINE_HEART: "ore_divine_heart",
	TileTypes.Type.RUIN_BRICK: "ruin_brick",
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
const DIR_DEEP := "res://art/tiles/deep/"

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


## Текстура клетки по типу и мировым координатам (для варианта земли и пояса).
## Возвращает null, если графики для этого типа нет — рендерер должен
## нарисовать плейсхолдер-заливку.
##
## Пояс 0 («Корни», до глубины 1000) — прежние отдельные файлы. Глубже — вырезка
## из атласа пояса (art/tiles/deep/belt_<i>.png, tools/gen_tiles_deep.py): земля
## и руды пересведены к тону пояса, чтобы руда не читалась заплаткой на фоне.
static func texture_for(type: int, wx: int, wy: int) -> Texture2D:
	var file: String
	if type == TileTypes.Type.DIRT:
		file = DIRT_FILES[dirt_variant(wx, wy)]
	else:
		file = String(_tile_to_file.get(type, ""))
	if file.is_empty():
		return null
	if wy >= 1000:
		var belt := Biomes.index_at_cell(wx, wy)
		if belt > 0:
			var t := _belt_tile(belt, file)
			if t != null:
				return t
	return _load(file)


## Поясная вырезка из атласа или null (атласа нет / такого имени нет — вызывающий
## откатится на тайл пояса 0). Ключ кэша — число, а не строка: зовут на каждую клетку
## экрана каждый кадр.
static func _belt_tile(belt: int, file: String) -> Texture2D:
	if _atlas_meta.is_empty():
		_load_atlas_meta()
	var idx: int = _atlas_idx.get(file, -1)
	if idx < 0:
		return null
	var key := belt * 256 + idx
	if _belt_cache.has(key):
		return _belt_cache[key]
	var tex: Texture2D = null
	var atlas := _belt_atlas(belt)
	if atlas != null:
		var cell := int(_atlas_meta.get("cell", 96))
		var pad := int(_atlas_meta.get("pad", 2))
		var cols := int(_atlas_meta.get("cols", 7))
		var stride := cell + 2 * pad
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2((idx % cols) * stride + pad, (idx / cols) * stride + pad, cell, cell)
		at.filter_clip = true
		tex = at
	_belt_cache[key] = tex
	return tex


static var _atlas_meta: Dictionary = {}
static var _atlas_idx: Dictionary = {}
static var _belt_cache: Dictionary = {}
static var _atlases: Dictionary = {}


static func _load_atlas_meta() -> void:
	var path := DIR_DEEP + "atlas.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_atlas_meta = parsed
	if _atlas_meta.is_empty():
		_atlas_meta = {"names": []}
	var names: Array = _atlas_meta.get("names", [])
	for i in range(names.size()):
		_atlas_idx[String(names[i])] = i


static func _belt_atlas(belt: int) -> Texture2D:
	if _atlases.has(belt):
		return _atlases[belt]
	var path := "%sbelt_%d.png" % [DIR_DEEP, belt]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_atlases[belt] = tex
	return tex


static func _load(file: String) -> Texture2D:
	if _cache.has(file):
		return _cache[file]
	var path := DIR + file + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_cache[file] = tex
	return tex

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
static var _small: Dictionary = {}
const OUTLINE := Color(0.07, 0.05, 0.04, 0.95)


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
## значки, остальное — общий камешек.
static func item(id: String) -> Texture2D:
	# нарисованный значок предмета (art/ui/shop/item_<id>.png, tools/gen_ore_icons.py) важнее плитки мира с грунтом
	var drawn := ShopArt.tex("item_" + id)
	if drawn != null:
		return drawn
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
	return tex("chunk")


## Значок предмета для мелких мест (цена, тост, ряд материалов: 12–24 единицы).
## Рисунок 32 px, показанный в 14–16, «нарезался» ближайшим соседом: контур
## выпадал, светлые металлы (алюминий, ртуть) растворялись на тёмной плашке.
## Здесь — честное сжатие до нужного размера и тёмный ободок в один пиксель
## вокруг силуэта, как у остальных значков интерфейса.
static func item_small(id: String, px: int = 16) -> Texture2D:
	var key := "%s@%d" % [id, px]
	if _small.has(key):
		return _small[key]
	var src := item(id)
	var out: Texture2D = src
	if src != null:
		var img := src.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			if img.get_width() != px or img.get_height() != px:
				img.resize(px, px, Image.INTERPOLATE_LANCZOS)
			out = ImageTexture.create_from_image(_outlined(img))
	_small[key] = out
	return out


static func _outlined(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var res := img.duplicate() as Image
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.25:
				continue
			var near := false
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = x + dx
					var ny: int = y + dy
					if nx >= 0 and ny >= 0 and nx < w and ny < h and img.get_pixel(nx, ny).a > 0.6:
						near = true
			if near:
				res.set_pixel(x, y, OUTLINE)
	return res

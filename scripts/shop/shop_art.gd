class_name ShopArt
extends RefCounted
## ShopArt — картинки и форматирование чисел для витрины. Графика лежит в
## art/ui/shop/ (tools/gen_shop_icons.py), общие значки — в art/ui/.
## Чего нет на диске — того нет: вызывающий получает null и решает сам, а не
## подсовывает чужую картинку.

const DIR := "res://art/ui/shop/"
const UI_DIR := "res://art/ui/"

## Цвета рамок по ступени/редкости: серый, зелёный, синий, фиолетовый, золотой,
## красный. Рамка — серый девятизонник, его красят модуляцией.
const TIER_COLORS := [
	Color8(0x9A, 0x9A, 0xAA), Color8(0x6F, 0xD0, 0x6F), Color8(0x5C, 0x9B, 0xE8),
	Color8(0xB0, 0x70, 0xE8), Color8(0xF0, 0xB8, 0x30), Color8(0xFF, 0x62, 0x4A),
]

const COL_GOLD := Color8(0xFF, 0xD8, 0x5A)
const COL_GOOD := Color8(0x6F, 0xE0, 0x8A)
const COL_BAD := Color8(0xFF, 0x6B, 0x6B)

static var _cache: Dictionary = {}


## Картинка магазина по имени файла без расширения: "tab_food", "glyph_check".
static func tex(name: String) -> Texture2D:
	return load_path(DIR + name + ".png")


## Общий значок из art/ui/: "icon_coin", "icon_dollar".
static func ui(name: String) -> Texture2D:
	return load_path(UI_DIR + name + ".png")


static func load_path(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_cache[path] = t
	return t


## Значок предмета рюкзака или товара по id: сначала нарисованный для магазина,
## потом плитка руды из мира, потом «булыжник».
static func item_icon(id: String) -> Texture2D:
	var t := tex("item_" + id)
	if t != null:
		return t
	var type := MineralMap.tile_type_for(id)
	if type >= 0:
		var tile := TileArt.texture_for(type, 0, 0)
		if tile != null:
			return tile
	return tex("item_unknown")


## Картинка нужного размера. expand_mode обязан стоять ДО size: иначе размер
## зажмётся до размера текстуры и значок 11×11 вырастет до 32×32.
static func rect(texture: Texture2D, pos: Vector2, sz: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture = texture
	t.position = pos
	t.size = sz
	return t


## Подпись с обводкой. Кегль и цвет — через LabelSettings, а не через
## add_theme_*_override: вне дерева Label запоминает минимальный размер по
## кеглю темы (16) и выходит вдвое выше и шире, чем нарисован.
## Сетка плиток на всю ширину (магазин, склад): колонок столько, сколько влезает
## (не меньше трёх), остаток ширины уходит в зазоры — справа не остаётся дыры.
static func tile_grid(cell: float = 64.0, gap: int = 8) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", gap)
	grid.add_theme_constant_override("v_separation", gap)
	grid.resized.connect(func() -> void:
		var cols := maxi(3, int((grid.size.x + gap) / (cell + gap)))
		grid.columns = cols
		grid.add_theme_constant_override("h_separation", maxi(gap, int((grid.size.x - cols * cell) / (cols - 1)))))
	return grid


static func label(text: String, font_size: int, color: Color = Color.WHITE,
		outline: Color = Color(0.05, 0.04, 0.08), outline_size: int = 3) -> Label:
	var ls := LabelSettings.new()
	ls.font_size = font_size
	ls.font_color = color
	ls.outline_color = outline
	ls.outline_size = outline_size
	var l := Label.new()
	l.label_settings = ls
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func tier_color(tier: int) -> Color:
	return TIER_COLORS[clampi(tier, 0, TIER_COLORS.size() - 1)]


## Ступень рамки для i-й позиции из n в линейке: растягиваем на все шесть цветов.
static func tier_for(i: int, n: int) -> int:
	if n <= 1:
		return 0
	return int(round(float(i) * 5.0 / float(n - 1)))

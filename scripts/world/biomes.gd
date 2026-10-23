class_name Biomes
extends RefCounted
## Пояса глубины (ГДД §4.2): какой пояс на какой глубине, их цвета, ambient и
## фон-стена. Данные — data/world_layers.json -> biomes; здесь только чтение и
## выбор. Чистые статические функции без автозагрузок (работают в --script).

const PATH := "res://data/world_layers.json"

static var _list: Array = []
static var _transition: int = 70
static var _colors: Dictionary = {}


static func _ensure() -> void:
	if not _list.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		var b: Dictionary = parsed.get("biomes", {})
		_transition = int(b.get("transition", 70))
		_list = b.get("list", [])
	if _list.is_empty():
		# запасной единственный пояс: игра не должна падать без данных
		_list = [{"id": "roots", "name_ru": "Корни", "y_from": 1, "y_to": 10000, "ambient": "dust_drip", "wall": "roots"}]


static func count() -> int:
	_ensure()
	return _list.size()


static func get_biome(i: int) -> Dictionary:
	_ensure()
	return _list[clampi(i, 0, _list.size() - 1)]


static func transition() -> int:
	_ensure()
	return _transition


## Пояс по глубине без перемешивания (для звука, ambient, подсказок).
static func index_at(y: int) -> int:
	_ensure()
	var n := _list.size()
	for i in range(n - 1, 0, -1):
		if y >= int(_list[i].get("y_from", 0)):
			return i
	return 0


## Пояс для КЛЕТКИ: у границы тайлы двух поясов перемешиваются по хешу клетки,
## чтобы граница не была линейкой. Вне зоны перехода — то же, что index_at.
static func index_at_cell(x: int, y: int) -> int:
	_ensure()
	var i := index_at(y)
	# граница сверху (i -> i+1)
	if i + 1 < _list.size():
		var yb := int(_list[i + 1].get("y_from", 0))
		var d := y - (yb - _transition)
		if d > 0 and cell_hash(x, y) * float(2 * _transition) < float(d):
			return i + 1
		return i
	return i


## Плавная смесь для фона/эффектов: {a: пояс, b: соседний, t: доля b 0..1}.
## Крайние полосы шириной transition вокруг границы кроссфейдят, остальное — чистый пояс.
static func blend_at(y: float) -> Dictionary:
	_ensure()
	var i := index_at(int(floor(y)))
	var t := 0.0
	var b := i
	if i + 1 < _list.size():
		var yb := float(_list[i + 1].get("y_from", 0))
		var span := float(_transition)
		if y > yb - span:
			b = i + 1
			t = clampf((y - (yb - span)) / (2.0 * span), 0.0, 1.0)
	if t == 0.0 and i > 0:
		var yb2 := float(_list[i].get("y_from", 0))
		if y < yb2 + float(_transition):
			b = i
			i -= 1
			t = clampf((y - (yb2 - float(_transition))) / (2.0 * float(_transition)), 0.0, 1.0)
	return {"a": i, "b": b, "t": t}


static func color_of(i: int, key: String, fallback: Color = Color.WHITE) -> Color:
	var b := get_biome(i)
	var ck := "%d/%s" % [i, key]
	if _colors.has(ck):
		return _colors[ck]
	var c := fallback
	var hex := String(b.get(key, ""))
	if not hex.is_empty():
		c = Color.html(hex)
	_colors[ck] = c
	return c


static func name_at(y: int) -> String:
	return String(get_biome(index_at(y)).get("name_ru", ""))


## Дешёвый хеш клетки в [0, 1). Не связан с сидом мира: пояса — вид, а не геология.
static func cell_hash(x: int, y: int) -> float:
	var h: int = ((x * 73856093) ^ (y * 19349663)) & 0x7FFFFFFF
	h = (h ^ (h >> 13)) * 1274126177 & 0x7FFFFFFF
	return float(h % 10007) / 10007.0

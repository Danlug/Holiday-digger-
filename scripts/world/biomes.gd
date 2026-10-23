class_name Biomes
extends RefCounted
## Пояса глубины (ГДД §4.2): какой пояс на какой глубине, их цвета, ambient и
## фон-стена. Данные — data/world_layers.json -> biomes; здесь только чтение и
## выбор. Чистые статические функции без автозагрузок (работают в --script).

const PATH := "res://data/world_layers.json"

static var _list: Array = []
static var _froms: PackedInt32Array = PackedInt32Array()
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
	_froms.resize(_list.size())
	for i in range(_list.size()):
		_froms[i] = int(_list[i].get("y_from", 0))


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
	for i in range(_froms.size() - 1, 0, -1):
		if y >= _froms[i]:
			return i
	return 0


## Пояс для КЛЕТКИ: вокруг границы (±transition) тайлы двух поясов перемешиваются
## по хешу клетки, чтобы граница не была линейкой; доля нижнего пояса растёт от 0
## до 1 поперёк зоны. Вне зоны перехода — то же, что index_at.
static func index_at_cell(x: int, y: int) -> int:
	_ensure()
	var lo := index_at(y - _transition)
	if lo + 1 < _froms.size():
		var d := y - (_froms[lo + 1] - _transition)
		if d > 0:
			return lo + 1 if cell_hash(x, y) * float(2 * _transition) < float(d) else lo
	return lo


## Плавная смесь для фона/эффектов: {a: пояс, b: соседний, t: доля b 0..1}.
## Поперёк зоны перехода кроссфейдит, вне зоны — чистый пояс (t = 0).
static func blend_at(y: float) -> Dictionary:
	_ensure()
	var lo := index_at(int(floor(y)) - _transition)
	if lo + 1 < _froms.size():
		var d := y - float(_froms[lo + 1] - _transition)
		if d > 0.0:
			return {"a": lo, "b": lo + 1, "t": clampf(d / float(2 * _transition), 0.0, 1.0)}
	return {"a": lo, "b": lo, "t": 0.0}


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

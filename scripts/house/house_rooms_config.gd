class_name HouseRoomsConfig
extends RefCounted
## HouseRoomsConfig — геометрия комнат дома как пространств (data/rooms.json).
##
## Дом перестал быть меню карточек (решение владельца, 2026-09-16): герой
## физически ходит по комнате, а кнопки-хотспоты всплывают над ним, когда он
## подошёл к нужному месту. Все доли и точки — в данных, а не в коде: когда
## художник положит настоящий фон (art/env/room_<id>.png) и, возможно, свою
## сверенную разметку (room_<id>.json рядом), править придётся файл, а не
## скрипт.
##
## Точка хранит только 'x' (доля 0..1 по ширине комнаты) — герой ходит вдоль
## одной линии пола, вторая координата ему не нужна. Кнопка хотспота всегда
## рисуется НАД ГЕРОЕМ (его текущим положением), а не над самой точкой на
## фоне, поэтому 'y' точки для отображения кнопки тоже не нужен.

const PATH := "res://data/rooms.json"
const IMAGE_META_FMT := "res://art/env/room_%s.json"
const BG_FMT := "res://art/env/room_%s.png"

const ROOM_IDS := ["hall", "bedroom", "workshop"]

static var _cache: Dictionary = {}
static var _loaded := false


## Читает произвольный JSON-файл в словарь. {} — файла нет, он битый, или это
## не объект. Общий хелпер: им же house_view.gd читает json рядом со
## спрайт-листом сна (art/anim/sleep_sheet.json).
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw


static func _load() -> void:
	_loaded = true
	var raw := read_json(PATH)
	var out := {}
	for id in ROOM_IDS:
		if raw.has(id) and typeof(raw[id]) == TYPE_DICTIONARY:
			out[id] = raw[id]
	_cache = out


## Комната по id: {width, height, floor_y, spawn_x, points}. Пустой словарь,
## если комнаты нет в data/rooms.json вовсе — вызывающий код (house_view.gd)
## обязан пережить это запасными числами, а не упасть: дом не имеет права
## запирать игрока из-за потерянного файла данных.
static func room(id: String) -> Dictionary:
	if not _loaded:
		_load()
	var base: Dictionary = (_cache.get(id, {}) as Dictionary).duplicate(true)
	_merge_image_overrides(id, base)
	return base


## Художник кладёт рядом с готовой картинкой room_<id>.json с теми же ключами
## точек ('x') и полем floor_y — его цифры сняты с настоящего фона и точнее
## прикидки этого агента по эскизу. Оба файла необязательны: нет ни одного —
## комната всё равно открывается плашкой-заглушкой с этими же долями.
static func _merge_image_overrides(id: String, base: Dictionary) -> void:
	var raw := read_json(IMAGE_META_FMT % id)
	if raw.is_empty():
		return
	if raw.has("floor_y"):
		base["floor_y"] = float(raw["floor_y"])
	if raw.has("spawn_x"):
		base["spawn_x"] = float(raw["spawn_x"])
	var points: Dictionary = base.get("points", {})
	for key in points.keys():
		if raw.has(key) and typeof(raw[key]) == TYPE_DICTIONARY and raw[key].has("x"):
			points[key]["x"] = float(raw[key]["x"])
	base["points"] = points


static func bg_path(id: String) -> String:
	return BG_FMT % id


static func floor_y(id: String) -> float:
	return float(room(id).get("floor_y", 0.86))


static func spawn_x(id: String) -> float:
	return float(room(id).get("spawn_x", 0.5))


static func points(id: String) -> Dictionary:
	return room(id).get("points", {})


## Ширина/высота заявленные в данных — используются, пока настоящей текстуры
## нет: плашка-заглушка рисуется в тех же пропорциях, что и будущий фон,
## чтобы доли точек совпали и после того, как картинку подвезут.
static func declared_size(id: String) -> Vector2:
	var r := room(id)
	return Vector2(float(r.get("width", 800)), float(r.get("height", 448)))

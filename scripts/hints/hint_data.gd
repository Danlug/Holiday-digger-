class_name HintData
extends RefCounted
## Правила и тайминги подсказок из data/hints.json. Читаем файл сами (как TechData):
## автозагрузок в --script-тестах нет, а числа нужны и там.

const PATH := "res://data/hints.json"

static var _data: Dictionary = {}
static var _loaded: bool = false


static func data() -> Dictionary:
	if not _loaded:
		reload()
	return _data


static func reload() -> void:
	_loaded = true
	_data = {}
	if not FileAccess.file_exists(PATH):
		push_error("HintData: нет файла %s" % PATH)
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("HintData: %s не разобран" % PATH)
		return
	_data = raw


## {value, proposed, note} -> value.
static func v(node, default = null):
	if node == null:
		return default
	if typeof(node) == TYPE_DICTIONARY and node.has("value"):
		return node["value"]
	return node


static func timing(key: String, default: float) -> float:
	return float(v(data().get("timing", {}).get(key, null), default))


static func rules() -> Array:
	return data().get("rules", [])


static func rule(id: String) -> Dictionary:
	for r: Dictionary in rules():
		if String(r.get("id", "")) == id:
			return r
	return {}


## Пункты меню, которым положен ярлык «new», пока их не открыли.
static func menu_new_entries() -> Array:
	return data().get("menu_new", {}).get("entries", [])

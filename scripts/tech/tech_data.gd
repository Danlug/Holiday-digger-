class_name TechData
extends RefCounted
## Данные ветки «Техника» (data/tech.json) и немного данных из balance.json,
## которые принадлежат не нам (расход блоков на клетку, лава владельца).
##
## Читаем файлы сами, а не через автозагрузку Balance: лава спрашивается из
## генератора мира, а тот проверяется headless-тестом в режиме --script, где
## автозагрузок нет вовсе.

const PATH := "res://data/tech.json"
const BALANCE_PATH := "res://data/balance.json"

static var _data: Dictionary = {}
static var _balance: Dictionary = {}


static func reload() -> void:
	_data = _read(PATH)
	_balance = _read(BALANCE_PATH)


static func data() -> Dictionary:
	if _data.is_empty():
		reload()
	return _data


static func balance() -> Dictionary:
	if _balance.is_empty():
		reload()
	return _balance


## Разворачивает {value, proposed, note} в value (то же, что Balance.unwrap).
static func v(node):
	if typeof(node) == TYPE_DICTIONARY and node.has("value"):
		return node["value"]
	return node


static func fuel() -> Dictionary:
	return data().get("fuel", {})


static func heat() -> Dictionary:
	return data().get("heat", {})


static func well() -> Dictionary:
	return data().get("well", {})


## Число из balance.json по пути ключей; запасное, если пути нет.
static func bal(path: Array, fallback):
	var node = balance()
	for key in path:
		if typeof(node) != TYPE_DICTIONARY or not node.has(key):
			return fallback
		node = node[key]
	return v(node)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("TechData: нет файла %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

class_name StoryText
extends RefCounted
## Таблица игровых текстов сюжета и обучения.
##
## Реплики лежат отдельно от режиссуры (data/story_<локаль>.json против
## data/story.json) по двум причинам сразу: сценарист переписывает текст, не
## рискуя развалить порядок сцен, а переводчику достаётся плоский список
## "ключ — строка" без единого куска логики. Поэтому в коде НЕТ ни одной
## русской реплики: всё, что герой произносит, приходит отсюда по ключу.
##
## Если ключа нет — возвращается сам ключ, а не пустая строка: пропущенную
## реплику надо видеть на экране, а не гадать, почему сцена молчит.

const DIR := "res://data/"
const DEFAULT_LOCALE := "ru"

static var _table: Dictionary = {}
static var _locale: String = ""


## Загружает таблицу выбранной локали. Если файла нет — откатывается на
## DEFAULT_LOCALE: лучше русский текст в английской сборке, чем голые ключи.
static func load_locale(locale: String = DEFAULT_LOCALE) -> void:
	var path := DIR + "story_" + locale + ".json"
	if not FileAccess.file_exists(path):
		if locale != DEFAULT_LOCALE:
			push_warning("StoryText: нет %s, беру %s" % [path, DEFAULT_LOCALE])
			load_locale(DEFAULT_LOCALE)
			return
		push_error("StoryText: не найден %s" % path)
		_table = {}
		_locale = locale
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("StoryText: %s повреждён" % path)
		_table = {}
	else:
		_table = raw
	_locale = locale


static func ensure_loaded() -> void:
	if _locale.is_empty():
		load_locale(DEFAULT_LOCALE)


static func locale() -> String:
	ensure_loaded()
	return _locale


static func get_text(key: String) -> String:
	if key.is_empty():
		return ""
	ensure_loaded()
	return String(_table.get(key, key))


static func has_key(key: String) -> bool:
	ensure_loaded()
	return _table.has(key)


## Только для тестов: сбрасывает кэш, чтобы следующий вызов перечитал файл.
static func _reset_for_tests() -> void:
	_table = {}
	_locale = ""

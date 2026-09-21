class_name StoryData
extends RefCounted
## Разбор data/story.json — режиссура катсцен без единой строки текста.
##
## Сцена описана данными, а не кодом, потому что порядок и состав реплик
## меняются каждым прогоном сценария: подвинуть кадр должно быть правкой
## JSON, а не правкой GDScript с последующей пересборкой.

const PATH := "res://data/story.json"

static var _doc: Dictionary = {}
static var _scenes_by_id: Dictionary = {}


static func ensure_loaded() -> void:
	if not _doc.is_empty():
		return
	if not FileAccess.file_exists(PATH):
		push_error("StoryData: не найден %s" % PATH)
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("StoryData: %s повреждён" % PATH)
		return
	_doc = raw
	_scenes_by_id.clear()
	for scene in _doc.get("scenes", []):
		_scenes_by_id[String(scene.get("id", ""))] = scene


static func scene(id: String) -> Dictionary:
	ensure_loaded()
	return _scenes_by_id.get(id, {})


static func has_scene(id: String) -> bool:
	ensure_loaded()
	return _scenes_by_id.has(id)


static func scene_ids() -> Array:
	ensure_loaded()
	return _scenes_by_id.keys()


static func beats(scene_id: String) -> Array:
	return scene(scene_id).get("beats", [])


## Сцена режима "мир" (scenes[].world == true в data/story.json) — играет
## поверх живой карты через CutscenePlayer.play(id, {"world": true}), а не в
## собственной декорации. См. cutscene_player.gd:world_mode.
static func is_world_scene(scene_id: String) -> bool:
	return bool(scene(scene_id).get("world", false))


static func effects(scene_id: String) -> Array:
	return scene(scene_id).get("effects", [])


static func mood(id: String) -> Dictionary:
	ensure_loaded()
	return _doc.get("moods", {}).get(id, {})


static func prop(id: String) -> Dictionary:
	ensure_loaded()
	return _doc.get("props", {}).get(id, {})


static func actor(id: String) -> Dictionary:
	ensure_loaded()
	return _doc.get("actors", {}).get(id, {})


## Путь к листу кадров актёра. У Роберта и родителей спрайтов ещё нет
## (см. отчёт — заказ художнику), у них пустая папка: сцена тогда идёт
## голосом за кадром, а не падает.
static func actor_sheet_path(actor_id: String, pose: String) -> String:
	var a := actor(actor_id)
	var dir := String(a.get("dir", ""))
	if dir.is_empty() or pose.is_empty():
		return ""
	return "res://art/character/%s/%s.png" % [dir, pose]


static func actor_speaker_key(actor_id: String) -> String:
	return String(actor(actor_id).get("speaker", ""))


## Только для тестов: следующий вызов перечитает файл.
static func _reset_for_tests() -> void:
	_doc = {}
	_scenes_by_id.clear()

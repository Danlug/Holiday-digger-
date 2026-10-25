class_name StoryState
extends RefCounted
## Сюжетная память: какие сцены просмотрены, какие ждут показа, какие флаги
## сюжета выставлены. Живёт в GameState (блок "--- сюжет ---"), чтобы чужие
## системы — дом, магазин, игрок — читали её одной строкой, и дублируется на
## диск в user://story.json.
##
## Почему отдельный файл, а не поля в user://save.json: сюжет пишется в
## момент, когда игрок нажал "дальше" в катсцене, а общий сейв кладётся раз в
## минуту автосейвом. Если бы просмотренность жила только в общем сейве,
## выход из игры через полминуты после интро показал бы интро заново. Плюс
## save.json правят параллельно ещё две системы, и лишняя точка конфликта
## сюжету не нужна.
##
## Очередь story_queue — ответ на "игрок вышел посреди катсцены": сцена
## попадает в очередь в момент срабатывания триггера и покидает её только
## после показа. Триггер мог быть мгновенным (удар лопатой о фундамент) и
## второй раз не сработать — очередь помнит за него.

const PATH := "user://story.json"
const SCHEMA_VERSION := 1


static func flags() -> Dictionary:
	return GameState.story_flags


static func has_flag(id: String) -> bool:
	return GameState.story_flags.get(id, false) == true


static func set_flag(id: String, value: bool = true) -> void:
	if id.is_empty():
		return
	GameState.story_flags[id] = value
	save()


static func is_seen(scene_id: String) -> bool:
	return GameState.story_seen.has(scene_id)


static func mark_seen(scene_id: String) -> void:
	if not GameState.story_seen.has(scene_id):
		GameState.story_seen.append(scene_id)
	GameState.story_queue.erase(scene_id)
	save()


## Ставит сцену в очередь показа. Повторно не ставит — ни уже показанную, ни
## уже стоящую в очереди, иначе обучение зациклится на первом же триггере,
## который срабатывает каждый кадр.
static func enqueue(scene_id: String) -> bool:
	if scene_id.is_empty() or is_seen(scene_id) or GameState.story_queue.has(scene_id):
		return false
	GameState.story_queue.append(scene_id)
	save()
	return true


static func next_queued() -> String:
	if GameState.story_queue.is_empty():
		return ""
	return String(GameState.story_queue[0])


static func clear_all() -> void:
	GameState.story_flags.clear()
	GameState.story_seen.clear()
	GameState.story_queue.clear()
	save()


static func save() -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("StoryState: не удалось открыть %s на запись" % PATH)
		return false
	f.store_string(JSON.stringify({
		"version": SCHEMA_VERSION,
		"flags": GameState.story_flags,
		"seen": GameState.story_seen,
		"queue": GameState.story_queue,
	}, "\t"))
	f.close()
	return true


static func load_from_disk() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return false
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("StoryState: %s повреждён — начинаем сюжет заново" % PATH)
		return false
	GameState.story_flags = raw.get("flags", {})
	GameState.story_seen = raw.get("seen", [])
	GameState.story_queue = raw.get("queue", [])
	return true


static func delete_from_disk() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove(PATH.get_file())

class_name MetaData
extends RefCounted
## Данные мета-слоя: data/quests.json, achievements.json, daily_rewards.json.
## Читаются один раз и кэшируются; числа там помечены proposed (см. легенды).

const QUESTS := "res://data/quests.json"
const ACHIEVEMENTS := "res://data/achievements.json"
const DAILY := "res://data/daily_rewards.json"

static var _cache: Dictionary = {}
static var _ach_index: Dictionary = {}


static func _load(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var out: Dictionary = {}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			out = parsed
	if out.is_empty():
		push_error("MetaData: не удалось прочитать %s" % path)
	_cache[path] = out
	return out


static func quests() -> Dictionary:
	return _load(QUESTS)


static func achievements_file() -> Dictionary:
	return _load(ACHIEVEMENTS)


static func daily() -> Dictionary:
	return _load(DAILY)


static func achievements() -> Array:
	return achievements_file().get("achievements", [])


static func achievement(id: String) -> Dictionary:
	if _ach_index.is_empty():
		for a in achievements():
			_ach_index[String(a["id"])] = a
	return _ach_index.get(id, {})


static func road() -> Array:
	return achievements_file().get("road", [])


static func template(id: String) -> Dictionary:
	for t in quests().get("templates", []):
		if String(t["id"]) == id:
			return t
	return {}


static func points_for_tier(tier: int) -> int:
	var arr: Array = achievements_file().get("points_by_tier", [1, 3, 5])
	return int(arr[clampi(tier - 1, 0, arr.size() - 1)])


static func reset_cache() -> void:
	_cache.clear()
	_ach_index.clear()

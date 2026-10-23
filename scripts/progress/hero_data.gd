class_name HeroData
extends RefCounted
## Сохраняемое состояние области «герой» — ключ "hero" в GameState.ext
## (общий сейв не правим, см. GameState.ext_get/ext_set). Сброс прогресса
## очищает ext целиком, так что эта запись живёт и умирает вместе с сейвом.
##
## Что хранится:
##   finds    {artifact_id: глубина, на которой артефакт найден} — для подсказки
##            музея; у скриптового клада из онбординга записи нет, и музей
##            показывает полосу глубин из data/artifacts.json.
##   seen_branches [номера веток], чей «момент славы» в музее уже показан.

const KEY := "hero"


static func _state() -> Dictionary:
	var s = GameState.ext_get(KEY, {})
	return s if s is Dictionary else {}


static func _save(state: Dictionary) -> void:
	GameState.ext_set(KEY, state)


static func record_find(artifact_id: String, depth: int) -> void:
	var s := _state()
	var finds: Dictionary = s.get("finds", {})
	finds[artifact_id] = depth
	s["finds"] = finds
	_save(s)


## Глубина находки или -1, если она не записана.
static func find_depth(artifact_id: String) -> int:
	var finds: Dictionary = _state().get("finds", {})
	return int(finds.get(artifact_id, -1))


static func is_branch_seen(branch_num: int) -> bool:
	var seen: Array = _state().get("seen_branches", [])
	for v in seen:
		if int(v) == branch_num:
			return true
	return false


static func mark_branch_seen(branch_num: int) -> void:
	if is_branch_seen(branch_num):
		return
	var s := _state()
	var seen: Array = s.get("seen_branches", [])
	seen.append(branch_num)
	s["seen_branches"] = seen
	_save(s)

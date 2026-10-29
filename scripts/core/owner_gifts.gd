class_name OwnerGifts
extends RefCounted
## OwnerGifts — разовые подарки сейвам (владелец 29.10: «добавь мне 500 долларов
## на счёт игры»). Сейв живёт в браузере игрока, правкой файла до него не
## добраться, поэтому подарок едет со сборкой: data/gifts.json.
##
## Подарок приходит при загрузке сейва (SaveSystem.load_game) один раз: id
## забранного пишется в ext.gifts_claimed. Получают его только уже игравшие:
## новая игра (нет сейва или сброс прогресса) сразу помечает все подарки
## забранными (mark_all_claimed).

const DATA_PATH := "res://data/gifts.json"
const CLAIMED_KEY := "gifts_claimed"


static func gifts() -> Array:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var list = parsed.get("gifts", [])
	return list if typeof(list) == TYPE_ARRAY else []


static func _claimed() -> Array:
	var claimed = GameState.ext.get(CLAIMED_KEY, [])
	return claimed if typeof(claimed) == TYPE_ARRAY else []


## Вручает положенные подарки только что загруженному сейву. Возвращает, сколько долларов пришло.
static func apply_on_load() -> int:
	var claimed := _claimed()
	var total := 0
	for g in gifts():
		if typeof(g) != TYPE_DICTIONARY:
			continue
		var id := String(g.get("id", ""))
		if id.is_empty() or claimed.has(id):
			continue
		claimed.append(id)
		total += maxi(0, int(g.get("dollars", 0)))
	GameState.ext[CLAIMED_KEY] = claimed
	if total > 0:
		GameState.add_dollars(total)
	return total


## Новая игра: подарки уже игравшим ей не положены.
static func mark_all_claimed() -> void:
	var claimed := _claimed()
	for g in gifts():
		var id := String(g.get("id", "")) if typeof(g) == TYPE_DICTIONARY else ""
		if not id.is_empty() and not claimed.has(id):
			claimed.append(id)
	GameState.ext[CLAIMED_KEY] = claimed

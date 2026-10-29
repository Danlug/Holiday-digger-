class_name OwnerGifts
extends RefCounted
## OwnerGifts — разовые подарки сейвам (владелец 29.10: «добавь мне 500 долларов
## на счёт игры»). Сейв живёт в браузере игрока, правкой файла до него не
## добраться, поэтому подарок едет со сборкой: data/gifts.json.
##
## Подарок приходит при загрузке сейва (SaveSystem.load_game) один раз: id
## забранного пишется в ext.gifts_claimed. Получают его только сейвы, записанные
## до saved_before (UTC) — уже игравшие; новая игра сейва до этой даты не имеет.

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


## Вручает положенные подарки только что загруженному сейву; save — его словарь
## (нужна дата записи saved_at_utc). Возвращает, сколько долларов пришло.
static func apply_on_load(save: Dictionary) -> int:
	var saved_at := String(save.get("saved_at_utc", ""))
	var claimed = GameState.ext.get(CLAIMED_KEY, [])
	if typeof(claimed) != TYPE_ARRAY:
		claimed = []
	var total := 0
	for g in gifts():
		if typeof(g) != TYPE_DICTIONARY:
			continue
		var id := String(g.get("id", ""))
		if id.is_empty() or claimed.has(id):
			continue
		# Сейв без даты — из старых сборок, то есть заведомо до подарка.
		var before := String(g.get("saved_before", ""))
		if not before.is_empty() and not saved_at.is_empty() and saved_at >= before:
			continue
		claimed.append(id)
		var dollars := int(g.get("dollars", 0))
		if dollars > 0:
			total += dollars
	GameState.ext[CLAIMED_KEY] = claimed
	if total > 0:
		GameState.add_dollars(total)
	return total

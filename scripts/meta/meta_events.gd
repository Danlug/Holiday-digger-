class_name MetaEvents
extends RefCounted
## Вход мета-слоя для событий: и шина GameState.game_event, и сигналы GameState
## (max_depth_changed, leveled_up, died…) сводятся в apply(). Счётчики копятся
## всегда — молча, чтобы достижения «за всё время» не теряли начало игры, —
## а задания и награды включаются только после онбординга (ГДД раздел 9).


## Возвращает {"quests": [закрывшиеся сейчас задания], "ach": [новые достижения]}.
static func apply(ev: StringName, data: Dictionary) -> Dictionary:
	MetaState.sub("events")[String(ev)] = true
	_count(ev, data)

	var done: Array = []
	if MetaState.is_unlocked():
		var queue: Array = QuestEngine.progress(ev, data)
		done.append_array(queue)
		# Закрытое задание — событие шины (звук, сюжет, счётчики соседей). Своё же
		# событие учитываем здесь, а не по шине: сервис такие эхо игнорирует.
		while not queue.is_empty():
			var q: Dictionary = queue.pop_front()
			var qd := {"id": String(q["id"]), "kind": String(q["kind"]), "source": "meta"}
			GameState.emit_event(&"quest_done", qd)
			var more: Array = QuestEngine.progress(&"quest_done", qd)
			done.append_array(more)
			queue.append_array(more)
	return {"quests": done, "ach": Achievements.evaluate()}


static func _count(ev: StringName, data: Dictionary) -> void:
	match String(ev):
		"dug":
			MetaState.bump("dug")
			var tile := int(data.get("tile", -1))
			if tile == TileTypes.Type.DIRT:
				MetaState.bump("dug_dirt")
			elif tile == TileTypes.Type.STONE:
				MetaState.bump("dug_stone")
			if bool(data.get("loot", false)):
				MetaState.bump("dug_ore")
		"picked":
			var n := int(data.get("count", 1))
			MetaState.bump("picked", n)
			var id := String(data.get("item", ""))
			if Achievements.is_kind(id):
				var m := MetaState.sub("minerals")
				m[id] = int(m.get(id, 0)) + n
		"sold":
			MetaState.bump("sales")
			MetaState.bump("sold_coins", int(data.get("coins", 0)))
			MetaState.bump("sold_items", int(data.get("count", 0)))
		"bought":
			MetaState.bump("bought")
		"monster_killed":
			MetaState.bump("monsters")
		"refueled":
			MetaState.bump("refueled")
		"lucky_find":
			MetaState.bump("lucky")
		"story_beat":
			MetaState.bump("story_beats")
		"died":
			MetaState.bump("deaths")

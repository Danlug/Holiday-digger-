class_name QuestEngine
extends RefCounted
## Движок заданий: суточный/недельный сброс, прогресс по событиям шины и
## сигналам GameState, выдача награды. Чистая логика над MetaState — без узлов
## и окон, поэтому проверяется автотестом на подставных событиях.
##
## Задание закрывается (target достигнут) само, награду забирают нажатием:
## так работает ролик «×2» и не теряется сюрприз «ура, получил».

## Не-игровые «события», которыми мета-слой кормит движок из сигналов GameState.
const EV_MAX_DEPTH := &"max_depth_changed"
const EV_LEVELED := &"leveled_up"


## Сменились сутки/неделя — выдаёт новые задания. Возвращает true, если что-то
## сгенерировано. До конца онбординга ничего не делает.
static func refresh() -> bool:
	if not MetaState.is_unlocked():
		return false
	var qs := MetaState.sub("quests")
	var today := MetaState.today()
	var week := MetaClock.week_of(today)
	var seen := MetaState.sub("events")
	var changed := false
	if int(qs["day"]) != today:
		qs["day"] = today
		qs["daily"] = QuestGen.generate("daily", today, GameState.world_seed, GameState.max_depth_reached, seen)
		qs["bonus_claimed"] = false
		qs["perfect"] = false
		changed = true
	if int(qs["week"]) != week:
		qs["week"] = week
		qs["weekly"] = QuestGen.generate("weekly", week, GameState.world_seed, GameState.max_depth_reached, seen)
		changed = true
	if changed:
		MetaState.touch()
	return changed


static func all_quests() -> Array:
	var qs := MetaState.sub("quests")
	return (qs["daily"] as Array) + (qs["weekly"] as Array)


static func find(qid: String) -> Dictionary:
	for q in all_quests():
		if String(q["id"]) == qid:
			return q
	return {}


static func is_done(q: Dictionary) -> bool:
	return int(q["progress"]) >= int(q["target"])


static func is_claimable(q: Dictionary) -> bool:
	return is_done(q) and not bool(q["claimed"])


static func claimable_count() -> int:
	var n := 0
	for q in all_quests():
		if is_claimable(q):
			n += 1
	if bonus_ready():
		n += 1
	return n


static func _depth_of(data: Dictionary) -> int:
	if data.has("depth"):
		return int(data["depth"])
	var c = data.get("cell")
	return int(c.y) if c is Vector2i else 0


static func matches(q: Dictionary, ev: StringName, data: Dictionary) -> bool:
	if String(q["event"]) != String(ev):
		return false
	var f: Dictionary = q["filter"]
	for k in f.keys():
		var want = f[k]
		match String(k):
			"item", "mineral":
				var have := String(data.get("item", data.get("mineral", "")))
				if want is Array:
					if not (want as Array).has(have):
						return false
				elif String(want) != have:
					return false
			"loot":
				if bool(data.get("loot", false)) != bool(want):
					return false
			"kind":
				if ev == &"dug":
					var tile := int(data.get("tile", -1))
					match String(want):
						"stone":
							if tile != TileTypes.Type.STONE:
								return false
						"dirt":
							if tile != TileTypes.Type.DIRT:
								return false
						"ore":
							if not bool(data.get("loot", false)):
								return false
				elif String(data.get("kind", "")) != String(want):
					return false
			"depth_min":
				if _depth_of(data) < int(want):
					return false
			"depth_max":
				if _depth_of(data) > int(want):
					return false
			"currency":
				if String(data.get("currency", "")) != String(want):
					return false
	return true


static func _amount(q: Dictionary, data: Dictionary) -> int:
	var s := String(q["sum"])
	if s == "":
		return 1
	return maxi(0, int(data.get(s, 1)))


## Двигает прогресс заданий. Возвращает задания, которые закрылись ИМЕННО сейчас.
static func progress(ev: StringName, data: Dictionary) -> Array:
	var done_now: Array = []
	if not MetaState.is_unlocked():
		return done_now
	refresh()
	for q in all_quests():
		if bool(q["claimed"]) or is_done(q) or not matches(q, ev, data):
			continue
		var before := int(q["progress"])
		if String(q["mode"]) == "delta":
			q["progress"] = clampi(int(data.get("depth", 0)) - int(q["base"]), before, int(q["target"]))
		else:
			q["progress"] = mini(int(q["target"]), before + _amount(q, data))
		if before < int(q["target"]) and is_done(q):
			done_now.append(q)
	return done_now


## Забрать награду. mult — «×2» за ролик (монеты и опыт; доллары и очки — нет).
static func claim(qid: String, mult: float = 1.0) -> Dictionary:
	var q := find(qid)
	if q.is_empty() or not is_claimable(q):
		return {"ok": false}
	q["claimed"] = true  # до выдачи: повторное нажатие уже ничего не даст
	var granted := MetaRewards.grant(MetaRewards.scaled(q["reward"], mult), true)
	_add_points(int(q["points"]))
	MetaState.bump("quests")
	if String(q["kind"]) == "daily" and _all_daily_claimed():
		var qs := MetaState.sub("quests")
		if not bool(qs.get("perfect", false)):
			qs["perfect"] = true
			MetaState.bump("perfect_days")
	MetaState.touch()
	return {"ok": true, "reward": granted, "points": int(q["points"]), "quest": q}


static func _all_daily_claimed() -> bool:
	var ds: Array = MetaState.sub("quests")["daily"]
	if ds.is_empty():
		return false
	for q in ds:
		if not bool(q["claimed"]):
			return false
	return true


static func bonus_ready() -> bool:
	return _all_daily_claimed() and not bool(MetaState.sub("quests")["bonus_claimed"])


## Награда за «все три ежедневных»: кратна ступени игрока.
static func bonus_reward() -> Dictionary:
	var ds: Array = MetaState.sub("quests")["daily"]
	if ds.is_empty():
		return {}
	var cfg: Dictionary = MetaData.quests()["daily"]
	var b: Dictionary = cfg["bonus_all"]
	var tier := int(ds[0]["tier"])
	var coins: Array = cfg["reward"]["coins"]
	var xp: Array = cfg["reward"]["xp"]
	return {
		"coins": maxi(5, int(round(float(coins[clampi(tier, 0, coins.size() - 1)]) * float(b["coins_x"]) / 5.0)) * 5),
		"xp": maxi(5, int(round(float(xp[clampi(tier, 0, xp.size() - 1)]) * float(b["xp_x"]) / 5.0)) * 5),
	}


static func claim_bonus() -> Dictionary:
	if not bonus_ready():
		return {"ok": false}
	MetaState.sub("quests")["bonus_claimed"] = true
	var granted := MetaRewards.grant(bonus_reward(), true)
	var pts := int(MetaData.quests()["daily"]["bonus_all"]["points"])
	_add_points(pts)
	MetaState.touch()
	return {"ok": true, "reward": granted, "points": pts}


static func _add_points(n: int) -> void:
	var s := MetaState.root()
	s["pts"] = int(s["pts"]) + n

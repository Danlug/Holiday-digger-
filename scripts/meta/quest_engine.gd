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
		qs["rerolls"] = 0
		qs["free_rerolls"] = int(_cfg("reroll").get("free_per_day", 0))
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
	var want_ev = q["event"]
	if want_ev is Array:
		if not (want_ev as Array).has(String(ev)):
			return false
	elif String(want_ev) != String(ev):
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
			_:
				# Прочие поля сравниваются как есть (stored: dir "put").
				if String(data.get(k, "")) != String(want):
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


## Звёзды дня: по одной за каждую забранную ежедневную миссию (владелец, 27.10).
static func stars_today() -> int:
	var n := 0
	for q in daily():
		if bool(q["claimed"]):
			n += 1
	return n


## Сколько звёзд открывают сундук: 10 (владелец), но не больше миссий в наборе
## (старый сейв с пятью заданиями доживает свой день и сундук всё равно видит).
static func stars_needed() -> int:
	return mini(int(QuestGen.num(_cfg("chest").get("stars"), 10)), daily().size())


static func bonus_ready() -> bool:
	var need := stars_needed()
	return need > 0 and stars_today() >= need and not bool(MetaState.sub("quests")["bonus_claimed"])


## Что лежит в сундуке звёзд: главная часть (5 долларов владельца, энергетик и
## прибавка серии монетами и опытом) и «доллар серии» каждого седьмого дня —
## он один идёт в недельный потолок повторяемых долларов. Прибавка серии считается
## от дня, которым станет сегодняшний, если сундук открыть.
static func _bonus_parts() -> Array:
	var ds := daily()
	if ds.is_empty():
		return [{}, {}]
	var b := _cfg("bonus_all")
	var main := {}
	var dollars := int(QuestGen.num(_cfg("chest").get("dollars"), 0))
	if dollars > 0:
		main["dollars"] = dollars
	var it = b.get("item")
	if typeof(it) == TYPE_DICTIONARY:
		main["item"] = (it as Dictionary).duplicate()
	var n := streak_if_claimed()
	var pct := streak_pct(n)
	if pct > 0:
		var rw: Dictionary = MetaData.quests()["daily"]["reward"]
		var tier := int(ds[0]["tier"])
		var k := float(_cfg("streak").get("base_x", 1.5)) * float(pct) / 100.0
		for key in ["coins", "xp"]:
			var arr: Array = rw[key]
			main[key] = maxi(5, int(round(float(arr[clampi(tier, 0, arr.size() - 1)]) * k / 5.0)) * 5)
	var capped := {}
	var every := int(_cfg("streak").get("dollar_every", 0))
	if every > 0 and n > 0 and n % every == 0:
		capped["dollars"] = 1
	return [main, capped]


## Награда сундука для показа: всё вместе (доллары серии — сверху пяти).
static func bonus_reward() -> Dictionary:
	var parts := _bonus_parts()
	var out: Dictionary = (parts[0] as Dictionary).duplicate(true)
	var extra := int((parts[1] as Dictionary).get("dollars", 0))
	if extra > 0:
		out["dollars"] = int(out.get("dollars", 0)) + extra
	return out


static func claim_bonus() -> Dictionary:
	if not bonus_ready():
		return {"ok": false}
	var parts := _bonus_parts()   # до сдвига серии: в награде уже учтён сегодняшний день
	var st := _streak()
	st["n"] = streak_if_claimed()
	st["last"] = MetaState.today()
	st["best"] = maxi(int(st.get("best", 0)), int(st["n"]))
	MetaState.set_max("quest_streak_best", int(st["n"]))
	MetaState.sub("quests")["bonus_claimed"] = true
	# Пять долларов — слово владельца, недельный потолок их не режет; доллар
	# серии — предложенный повторяемый источник, он в потолке.
	var granted := MetaRewards.grant(parts[0], false)
	var extra := MetaRewards.grant(parts[1], true)
	if extra.has("dollars"):
		granted["dollars"] = int(granted.get("dollars", 0)) + int(extra["dollars"])
	var pts := int(_cfg("bonus_all").get("points", 0))
	_add_points(pts)
	MetaState.touch()
	return {"ok": true, "reward": granted, "points": pts, "streak": int(st["n"])}


# ---------------------------------------------------------------------------
# Серия: дней подряд с открытым сундуком
# ---------------------------------------------------------------------------

static func _cfg(key: String) -> Dictionary:
	return MetaData.quests().get("daily", {}).get(key, {})


static func _streak() -> Dictionary:
	var qs := MetaState.sub("quests")
	if typeof(qs.get("streak")) != TYPE_DICTIONARY:
		qs["streak"] = {"n": 0, "last": -1, "best": 0}
	return qs["streak"]


## Серия, какой её видит игрок сейчас: 0, если цепочка уже оборвана пропуском.
static func streak_now() -> int:
	var st := _streak()
	var last := int(st.get("last", -1))
	if last < 0:
		return 0
	var gap := MetaState.today() - last
	return int(st.get("n", 0)) if gap <= 1 + int(_cfg("streak").get("grace_days", 0)) else 0


## Какой станет серия, если открыть сундук сегодня.
static func streak_if_claimed() -> int:
	var st := _streak()
	if int(st.get("last", -1)) == MetaState.today():
		return int(st.get("n", 0))
	return streak_now() + 1


## Прибавка сундука в процентах на n-й день серии (первый день — без прибавки).
static func streak_pct(n: int) -> int:
	var c := _cfg("streak")
	return clampi((n - 1) * int(c.get("pct_per_day", 0)), 0, int(c.get("max_pct", 0)))


# ---------------------------------------------------------------------------
# Прогресс дня и замена задания
# ---------------------------------------------------------------------------

static func daily() -> Array:
	return MetaState.sub("quests")["daily"]


## Доля дня: среднее по заданиям (каждое — не больше 1). Для кольца на кнопке.
static func day_fraction() -> float:
	var ds := daily()
	if ds.is_empty():
		return 0.0
	var sum := 0.0
	for q in ds:
		sum += clampf(float(q["progress"]) / float(maxi(1, int(q["target"]))), 0.0, 1.0)
	return sum / float(ds.size())


static func daily_done_count() -> int:
	var n := 0
	for q in daily():
		if is_done(q):
			n += 1
	return n


## Что готово забрать в окне дня: задания плюс сундук.
static func daily_claimable_count() -> int:
	var n := 0
	for q in daily():
		if is_claimable(q):
			n += 1
	return n + (1 if bonus_ready() else 0)


## Новый набор дня ещё не открывали — кнопка зовёт «загляни».
static func is_new_today() -> bool:
	var qs := MetaState.sub("quests")
	return not daily().is_empty() and int(qs.get("opened", -1)) != int(qs["day"])


static func mark_opened() -> void:
	var qs := MetaState.sub("quests")
	qs["opened"] = int(qs["day"])


static func free_rerolls_left() -> int:
	return maxi(0, int(MetaState.sub("quests").get("free_rerolls", _cfg("reroll").get("free_per_day", 0))))


static func ad_placement_reroll() -> String:
	return String(_cfg("reroll").get("ad_placement", "quest_reroll"))


## Заменить можно невыполненное ежедневное задание, если в его слоте есть другой шаблон.
static func can_reroll(q: Dictionary) -> bool:
	if String(q.get("kind", "")) != "daily" or bool(q["claimed"]) or is_done(q):
		return false
	return QuestGen.can_reroll(q, daily(), MetaState.sub("events"), GameState.max_depth_reached)


## Замена: бесплатная, пока есть, иначе только с via_ad (ролик уже показан —
## это решает вызывающий через MetaAds). Возвращает {ok, quest, free}.
static func reroll(qid: String, via_ad: bool = false) -> Dictionary:
	var q := find(qid)
	if q.is_empty() or not can_reroll(q):
		return {"ok": false}
	var qs := MetaState.sub("quests")
	var free := free_rerolls_left() > 0 and not via_ad
	if not free and not via_ad:
		return {"ok": false}
	var n := int(qs.get("rerolls", 0)) + 1
	var nq := QuestGen.reroll(q, daily(), GameState.world_seed, GameState.max_depth_reached, MetaState.sub("events"), n)
	if nq.is_empty():
		return {"ok": false}
	var ds := daily()
	for i in range(ds.size()):
		if String(ds[i]["id"]) == qid:
			ds[i] = nq
	qs["rerolls"] = n
	if free:
		qs["free_rerolls"] = free_rerolls_left() - 1
	MetaState.touch()
	return {"ok": true, "quest": nq, "free": free}


static func _add_points(n: int) -> void:
	var s := MetaState.root()
	s["pts"] = int(s["pts"]) + n

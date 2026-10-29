extends Node
## test_meta — логика мета-слоя без окна: задания (генерация, прогресс по
## подставным событиям, сброс дня и недели), ежедневная награда (серия, защита
## от повторной выдачи и от часов), достижения, дорога трофеев, лимиты рекламы,
## сохранение через GameState.ext.
##
## Запуск: godot --headless --path . res://tests/test_meta.tscn

var failures := 0
var total := 0

## 2026-10-19 — понедельник; от него считаем сутки в тестах.
const MONDAY := 20745


func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", label])


func _ready() -> void:
	print("=== test_meta ===")
	await get_tree().process_frame
	_test_clock()
	_test_generation()
	_test_gate_and_rollover()
	_test_quest_progress()
	_test_claim_and_caps()
	_test_daily_reward()
	_test_achievements()
	_test_road()
	_test_ads()
	_test_save_roundtrip()
	MetaClock.override_unix = -1
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _fresh(day: int = MONDAY, unlocked: bool = true) -> void:
	GameState.reset_progress()
	GameState.world_seed = 4242
	MetaClock.override_unix = day * MetaClock.DAY + 3600
	MetaState.root()["unlocked"] = unlocked


func _day(d: int) -> void:
	MetaClock.override_unix = d * MetaClock.DAY + 3600


## Подставное задание: событие, фильтр, цель.
func _mk(event: String, filter: Dictionary, target: int, sum: String = "", kind: String = "daily") -> Dictionary:
	return {"id": "t:%s:%d" % [event, randi() % 100000], "tpl": "dig_any", "kind": kind, "slot": 0, "event": event,
		"filter": filter, "sum": sum, "mode": "", "target": target, "progress": 0, "base": 0, "tier": 0,
		"glyph": "dig", "reward": {"coins": 100, "xp": 10}, "points": 1, "claimed": false}


func _put(qs: Array) -> void:
	MetaState.sub("quests")["daily"] = qs


func _test_clock() -> void:
	check("неделя: понедельник и воскресенье одной недели", MetaClock.week_of(MONDAY) == MetaClock.week_of(MONDAY + 6))
	check("неделя: следующий понедельник — новая", MetaClock.week_of(MONDAY + 7) == MetaClock.week_of(MONDAY) + 1)
	check("неделя: воскресенье перед понедельником — старая", MetaClock.week_of(MONDAY - 1) == MetaClock.week_of(MONDAY) - 1)
	check("дата UTC читается", MetaClock.date_str(MONDAY) == "2026-10-19")
	_fresh()
	check("до конца недели в понедельник — 7 суток, в воскресенье — 1",
		MetaClock.days_left_in_week(MONDAY) == 7 and MetaClock.days_left_in_week(MONDAY + 6) == 1)
	_day(MONDAY + 5)
	check("сегодня — настоящие сутки", MetaState.today() == MONDAY + 5)
	_day(MONDAY + 2)
	check("часы отмотали назад — «сегодня» не идёт назад", MetaState.today() == MONDAY + 5)
	_day(MONDAY + 6)
	check("часы пошли вперёд — сутки обновились", MetaState.today() == MONDAY + 6)


func _test_generation() -> void:
	_fresh()
	var seen := {}
	var a := QuestGen.generate("daily", MONDAY, 4242, 120, seen)
	var b := QuestGen.generate("daily", MONDAY, 4242, 120, seen)
	# Было три, потом пять (раунд 3); владелец 27.10: «Ежедневных миссий нужно 13».
	check("13 ежедневных миссий", a.size() == QuestGen.count_of(MetaData.quests()["daily"]) and a.size() == 13)
	check("генерация детерминирована от (дата, сид, ступень)", JSON.stringify(a) == JSON.stringify(b))
	var tpls := {}
	for q in a:
		tpls[String(q["tpl"])] = true
	check("миссии дня все разные", tpls.size() == a.size())
	var differs := false
	for d in range(1, 12):
		if JSON.stringify(QuestGen.generate("daily", MONDAY + d, 4242, 120, seen)) != JSON.stringify(a):
			differs = true
	check("в разные дни — разные наборы", differs)
	check("другой сид — другой набор хотя бы в какой-то из дней", _seed_differs())
	var w := QuestGen.generate("weekly", MetaClock.week_of(MONDAY), 4242, 120, seen)
	check("три недельных задания: второе даёт доллар, третье — ролики", w.size() == 3 and int(w[1]["reward"].get("dollars", 0)) == 1
		and String(w[2]["tpl"]) == "watch_ads")

	var low := QuestGen.generate("daily", MONDAY + 3, 4242, 0, seen)
	var high := QuestGen.generate("daily", MONDAY + 3, 4242, 3000, seen)
	check("ступень растёт с глубиной", QuestGen.tier_for(0) == 0 and QuestGen.tier_for(120) == 2 and QuestGen.tier_for(3000) == 5)
	var low_coins := 0
	var high_coins := 0
	for q in low:
		low_coins += int(q["reward"]["coins"])
	for q in high:
		high_coins += int(q["reward"]["coins"])
	check("награда растёт с прогрессом игрока", high_coins > low_coins * 3)
	var bad_events := false
	for d in range(0, 40):
		for q in QuestGen.generate("daily", MONDAY + d, 7, 10, seen):
			if ["bought", "monster_killed", "refueled"].has(String(q["event"])):
				bad_events = true
	check("задания на ещё не виденные события не выдаются", not bad_events)
	var seen_buy := {"bought": true}
	var got_buy := false
	for d in range(0, 80):
		for q in QuestGen.generate("daily", MONDAY + d, 7, 120, seen_buy):
			if String(q["event"]) == "bought":
				got_buy = true
	check("увидели событие покупки — задание на покупку появляется", got_buy)
	check("целевые значения целые и положительные", _targets_ok())
	check("FNV-сид стабилен", QuestGen.hash_seed("daily|20745|4242") == QuestGen.hash_seed("daily|20745|4242")
		and QuestGen.hash_seed("a") != QuestGen.hash_seed("b"))


func _seed_differs() -> bool:
	for d in range(0, 12):
		if JSON.stringify(QuestGen.generate("daily", MONDAY + d, 1, 120, {})) != JSON.stringify(QuestGen.generate("daily", MONDAY + d, 2, 120, {})):
			return true
	return false


func _targets_ok() -> bool:
	for d in range(0, 30):
		for kind in ["daily", "weekly"]:
			for q in QuestGen.generate(kind, MONDAY + d, 9, 900, {"bought": true}):
				if typeof(q["target"]) != TYPE_INT or int(q["target"]) < 1:
					return false
	return true


func _test_gate_and_rollover() -> void:
	_fresh(MONDAY, false)
	check("до онбординга задания не выдаются", not QuestEngine.refresh() and (MetaState.sub("quests")["daily"] as Array).is_empty())
	MetaEvents.apply(&"dug", {"cell": Vector2i(1, 10), "tile": TileTypes.Type.DIRT, "loot": false})
	check("до онбординга события копятся молча (счётчик)", MetaState.counter("dug") == 1)
	check("до онбординга достижения не выдаются", Achievements.evaluate().is_empty() and GameState.coins == 0)
	check("до онбординга ежедневная награда закрыта", not DailyReward.can_claim())

	MetaState.root()["unlocked"] = true
	check("после онбординга задания выданы", QuestEngine.refresh() and (MetaState.sub("quests")["daily"] as Array).size() == 13
		and (MetaState.sub("quests")["weekly"] as Array).size() == 3)
	var d0 := JSON.stringify(MetaState.sub("quests")["daily"])
	var w0 := JSON.stringify(MetaState.sub("quests")["weekly"])
	check("повторный refresh в тот же день ничего не меняет", not QuestEngine.refresh())

	_day(MONDAY + 1)
	check("новые сутки — новые ежедневные", QuestEngine.refresh() and JSON.stringify(MetaState.sub("quests")["daily"]) != d0)
	check("новые сутки — недельные те же", JSON.stringify(MetaState.sub("quests")["weekly"]) == w0)
	var d1 := JSON.stringify(MetaState.sub("quests")["daily"])

	_day(MONDAY)
	check("часы назад — задания не откатываются и не пересоздаются", not QuestEngine.refresh() and JSON.stringify(MetaState.sub("quests")["daily"]) == d1)

	_day(MONDAY + 6)
	QuestEngine.refresh()
	check("воскресенье — ещё та же неделя", JSON.stringify(MetaState.sub("quests")["weekly"]) == w0)
	_day(MONDAY + 7)
	check("понедельник — новые недельные", QuestEngine.refresh() and JSON.stringify(MetaState.sub("quests")["weekly"]) != w0)

	var before := JSON.stringify(MetaState.sub("quests"))
	GameState.daily_reset.emit()
	QuestEngine.refresh()
	check("сигнал GameState.daily_reset сам по себе задания не трогает", JSON.stringify(MetaState.sub("quests")) == before)


func _test_quest_progress() -> void:
	_fresh()
	var q_any := _mk("dug", {}, 3)
	var q_stone := _mk("dug", {"kind": "stone"}, 2)
	var q_ore := _mk("dug", {"loot": true}, 2)
	var q_deep := _mk("dug", {"depth_min": 50}, 2)
	var q_gold := _mk("picked", {"item": "gold"}, 5, "count")
	var q_coins := _mk("sold", {}, 300, "coins")
	var q_items := _mk("sold", {}, 10, "count")
	var q_rec := _mk("max_depth_changed", {}, 10)
	q_rec["mode"] = "delta"
	q_rec["base"] = 40
	var q_lvl := _mk("leveled_up", {}, 2, "", "weekly")
	var q_dd := _mk("quest_done", {"kind": "daily"}, 2, "", "weekly")
	var q_buy := _mk("bought", {"currency": "dollars"}, 1)
	_put([q_any, q_stone, q_ore, q_deep, q_gold, q_coins, q_items, q_rec, q_buy])
	MetaState.sub("quests")["weekly"] = [q_lvl, q_dd]
	MetaState.sub("quests")["day"] = MetaState.today()
	MetaState.sub("quests")["week"] = MetaClock.week_of(MetaState.today())

	MetaEvents.apply(&"dug", {"cell": Vector2i(3, 10), "tile": TileTypes.Type.DIRT, "mineral": "", "loot": false})
	MetaEvents.apply(&"dug", {"cell": Vector2i(3, 11), "tile": TileTypes.Type.STONE, "mineral": "", "loot": false})
	MetaEvents.apply(&"dug", {"cell": Vector2i(3, 60), "tile": TileTypes.Type.GOLD_ORE, "mineral": "gold", "loot": true})
	check("dug: любая порода считается", int(q_any["progress"]) == 3)
	check("dug: фильтр «камень»", int(q_stone["progress"]) == 1)
	check("dug: фильтр «руда» (loot)", int(q_ore["progress"]) == 1)
	check("dug: фильтр глубины", int(q_deep["progress"]) == 1)
	var extra := MetaEvents.apply(&"dug", {"cell": Vector2i(3, 70), "tile": TileTypes.Type.DIRT, "loot": false})
	check("закрытое задание не идёт выше цели и второй раз не «закрывается»",
		int(q_any["progress"]) == 3 and not extra["quests"].has(q_any))

	MetaEvents.apply(&"picked", {"item": "iron_ore", "count": 4})
	check("picked: чужой предмет не засчитывается", int(q_gold["progress"]) == 0)
	MetaEvents.apply(&"picked", {"item": "gold", "count": 3})
	MetaEvents.apply(&"picked", {"item": "gold", "count": 9})
	check("picked: предмет и сумма count, потолок — цель", int(q_gold["progress"]) == 5)

	var r := MetaEvents.apply(&"sold", {"coins": 120, "count": 4})
	check("sold: суммируются монеты и предметы по полю sum", int(q_coins["progress"]) == 120 and int(q_items["progress"]) == 4)
	r = MetaEvents.apply(&"sold", {"coins": 500, "count": 8})
	check("sold: закрытие возвращается в результате", int(q_coins["progress"]) == 300 and r["quests"].has(q_coins) and r["quests"].has(q_items))

	MetaEvents.apply(&"max_depth_changed", {"depth": 45})
	check("рекорд глубины: прогресс от базы", int(q_rec["progress"]) == 5)
	MetaEvents.apply(&"max_depth_changed", {"depth": 80})
	check("рекорд глубины: потолок — цель", int(q_rec["progress"]) == 10)

	MetaEvents.apply(&"bought", {"id": "x", "currency": "coins"})
	check("bought: фильтр валюты", int(q_buy["progress"]) == 0)
	MetaEvents.apply(&"bought", {"id": "x", "currency": "dollars"})
	check("bought: нужная валюта", int(q_buy["progress"]) == 1)

	MetaEvents.apply(&"leveled_up", {"level": 2})
	check("leveled_up: +1 за уровень", int(q_lvl["progress"]) == 1)
	var dd_before := int(q_dd["progress"])
	MetaEvents.apply(&"quest_done", {"id": "foreign", "kind": ""})
	check("quest_done чужой (без kind) недельное «ежедневные» не двигает", int(q_dd["progress"]) == dd_before)
	check("закрытое ежедневное двигает недельное «выполни N ежедневных»", int(q_dd["progress"]) >= 1)

	var echo := MetaState.counter("quests")
	check("эхо quest_done от мета-слоя не считается как «забрано»", echo == 0)

	MetaEvents.apply(&"story_beat", {"id": "a"})
	MetaEvents.apply(&"refueled", {"amount": 1.0})
	MetaEvents.apply(&"monster_killed", {"id": "m", "depth": 4100})
	check("видимые события запоминаются для requires_seen",
		MetaState.event_seen("story_beat") and MetaState.event_seen("refueled") and MetaState.event_seen("monster_killed"))
	check("счётчики событий: монстры, заправки, сюжет",
		MetaState.counter("monsters") == 1 and MetaState.counter("refueled") == 1 and MetaState.counter("story_beats") == 1)


func _test_claim_and_caps() -> void:
	_fresh()
	var q := _mk("dug", {}, 2)
	q["reward"] = {"coins": 100, "xp": 10, "dollars": 1}
	_put([q])
	MetaState.sub("quests")["day"] = MetaState.today()
	MetaState.sub("quests")["week"] = MetaClock.week_of(MetaState.today())
	check("нельзя забрать незакрытое", not QuestEngine.claim(String(q["id"]))["ok"] and GameState.coins == 0)
	MetaEvents.apply(&"dug", {"cell": Vector2i(1, 6), "tile": TileTypes.Type.DIRT, "loot": false})
	MetaEvents.apply(&"dug", {"cell": Vector2i(1, 7), "tile": TileTypes.Type.DIRT, "loot": false})
	check("закрытое — на бейдже", QuestEngine.claimable_count() == 1)
	var coins_before_claim := GameState.coins  # в нём уже награда «Первый комок» за копку
	var c := QuestEngine.claim(String(q["id"]), 2.0)
	check("«×2»: монеты и опыт удвоены, доллар — нет",
		c["ok"] and GameState.coins - coins_before_claim == 200 and GameState.dollars == 1)
	check("очки дороги за задание начислены", TrophyRoad.points() >= 1)
	var coins_after_claim := GameState.coins
	check("повторно награда не выдаётся",
		not QuestEngine.claim(String(q["id"]))["ok"] and GameState.coins == coins_after_claim and GameState.dollars == 1)
	check("забранное задание уже не на бейдже", not QuestEngine.is_claimable(q))

	# Потолок долларов в неделю для повторяемых источников (premium_cap.per_week = 4).
	var cap := int(MetaData.daily()["premium_cap"]["per_week"])
	var granted := 0
	for i in range(cap + 3):
		granted += int(MetaRewards.grant({"dollars": 1}, true).get("dollars", 0))
	check("недельный потолок долларов держится", granted == cap - 1 or granted == cap)
	var one_off := int(MetaRewards.grant({"dollars": 2}, false).get("dollars", 0))
	check("одноразовые доллары (достижения, дорога) в потолок не входят", one_off == 2)
	_day(MONDAY + 7)
	check("новая неделя — потолок сброшен", MetaRewards.dollars_left_this_week() == cap)

	# Награда-предмет: предмет в рюкзак, не влез — монеты вместо него.
	var coins_before := GameState.coins
	var g := MetaRewards.grant({"item": {"id": "energy_drink", "count": 1}}, false)
	check("предмет-награда ложится в рюкзак", GameState.get_item_count("energy_drink") == 1 and g.has("item"))
	GameState.inventory["energy_drink"] = 99
	var g2 := MetaRewards.grant({"item": {"id": "energy_drink", "count": 2}}, false)
	check("предмет не влез — награда не пропадает, выдаётся монетами",
		GameState.coins == coins_before + 2 * MetaRewards.ITEM_FALLBACK_COINS and not g2.has("item"))

	# Бонус «все три ежедневных».
	_fresh()
	var qs: Array = []
	for i in range(3):
		var qq := _mk("dug", {}, 1)
		qq["id"] = "t:b:%d" % i
		qs.append(qq)
	_put(qs)
	MetaState.sub("quests")["day"] = MetaState.today()
	MetaState.sub("quests")["week"] = MetaClock.week_of(MetaState.today())
	MetaEvents.apply(&"dug", {"cell": Vector2i(1, 6), "tile": TileTypes.Type.DIRT, "loot": false})
	check("бонус дня закрыт, пока не забраны все три", not QuestEngine.bonus_ready())
	for i in range(3):
		QuestEngine.claim("t:b:%d" % i)
	check("забрали все три — «закрыл день» и бонус готов", QuestEngine.bonus_ready() and MetaState.counter("perfect_days") == 1)
	var dollars_b := GameState.dollars
	check("бонус выдаётся один раз (5 долларов)", QuestEngine.claim_bonus()["ok"] and GameState.dollars == dollars_b + 5
		and not QuestEngine.claim_bonus()["ok"])


func _test_daily_reward() -> void:
	_fresh()
	var p := DailyReward.plan()
	check("первый вход: можно, плитка 1, серия 0", p["can_claim"] and p["pos"] == 0 and p["streak"] == 0)
	var r := DailyReward.claim()
	check("день 1: 150 монет", r["ok"] and r["day"] == 1 and GameState.coins == 150)
	check("повторно в те же сутки — нет", not DailyReward.claim()["ok"] and GameState.coins == 150)
	_day(MONDAY - 3)
	check("часы назад — повторной выдачи нет", not DailyReward.claim()["ok"] and GameState.coins == 150)
	_day(MONDAY)
	check("серия после первой награды = 1", int(MetaState.sub("daily")["streak"]) == 1)

	var total_coins := GameState.coins
	var dollars_seen := 0
	for i in range(1, 7):
		_day(MONDAY + i)
		var rr := DailyReward.claim()
		check("день %d серии выдан" % (i + 1), rr["ok"] and rr["day"] == i + 1 and rr["streak"] == i + 1)
		dollars_seen += int(rr["reward"].get("dollars", 0))
		total_coins += int(rr["reward"].get("coins", 0))
		if i == 2:
			check("день 3 даёт предмет (энергетик)", rr["reward"].has("item") and GameState.get_item_count("energy_drink") >= 1)
	check("доллар — только в 7-й день", dollars_seen == 1 and GameState.dollars == 1)
	check("7-й день — крупный приз", int(DailyReward.cycle()[6]["reward"]["coins"]) == 2000 and DailyReward.cycle()[6].get("grand", false))
	check("монеты за неделю сходятся с таблицей", GameState.coins >= total_coins)

	_day(MONDAY + 7)
	var p8 := DailyReward.plan()
	check("после недели цикл с плитки 1, бонус серии +10%", p8["pos"] == 0 and p8["bonus_pct"] == 10 and p8["streak"] == 7)
	var c8 := GameState.coins
	var r8 := DailyReward.claim()
	check("день 8: 150 монет + 10%", r8["ok"] and GameState.coins - c8 == 165)

	_day(MONDAY + 9)
	var pg := DailyReward.plan()
	check("пропущен один день — серия жива (grace)", pg["can_claim"] and not pg["broken"] and pg["streak"] == 8 and pg["pos"] == 1)
	DailyReward.claim()
	_day(MONDAY + 12)
	var pb := DailyReward.plan()
	check("пропущено два дня — цепочка оборвана, цикл с первой плитки", pb["broken"] and pb["pos"] == 0 and pb["streak"] == 0 and pb["bonus_pct"] == 0)
	var rb := DailyReward.claim()
	check("после обрыва день 1 и серия 1", rb["day"] == 1 and rb["streak"] == 1)
	check("лучшая серия помнится", MetaState.counter("streak_best") == 9)

	var rx := DailyReward.reward_for(0, 0, 2.0)
	check("«×2»: монеты и опыт удваиваются, доллары нет", int(rx["coins"]) == 300 and int(DailyReward.reward_for(6, 0, 2.0)["dollars"]) == 1
		and int(DailyReward.reward_for(6, 0, 2.0)["coins"]) == 4000)

	# Выдача, прерванная посреди (запись раньше выдачи): после «рестарта» снова не выдать.
	_fresh()
	DailyReward.claim()
	var snap = JSON.parse_string(JSON.stringify(GameState.ext))
	GameState.ext = snap
	check("после сейва/загрузки награду за сегодня снова не взять", not DailyReward.claim()["ok"])


func _test_achievements() -> void:
	_fresh()
	check("в данных 30–50 достижений", MetaData.achievements().size() >= 30 and MetaData.achievements().size() <= 50)
	check("у каждого достижения есть название, описание, значок и награда", _ach_data_ok())
	check("пустой прогресс — ничего не получено", Achievements.evaluate().is_empty())
	MetaEvents.apply(&"picked", {"item": "gold", "count": 1})
	check("«Первый золотой самородок» получен, награда выдана",
		Achievements.is_done("gold_1") and GameState.coins >= 100)
	var pts := TrophyRoad.points()
	check("очки дороги за достижение", pts == MetaData.points_for_tier(1))
	var coins := GameState.coins
	MetaEvents.apply(&"picked", {"item": "gold", "count": 1})
	check("повторно награда не выдаётся", GameState.coins == coins)
	check("непросмотренное достижение — на бейдже", Achievements.unseen_count() == 1 and Achievements.is_unseen("gold_1"))
	Achievements.mark_all_seen()
	check("просмотрели — бейдж погас", Achievements.unseen_count() == 0)

	GameState.max_depth_reached = 120
	var fresh := Achievements.evaluate()
	var ids: Array = []
	for a in fresh:
		ids.append(a["id"])
	check("глубина берётся живьём из GameState", ids.has("depth_15") and ids.has("depth_50") and ids.has("depth_100") and not ids.has("depth_500"))
	MetaEvents.apply(&"died", {})
	check("«Двоечник пришёл к бабушке» — первая смерть", Achievements.is_done("die_1"))
	MetaEvents.apply(&"sold", {"coins": 1200, "count": 9})
	check("продажи: «Первая выручка» и «Первая тысяча»", Achievements.is_done("sale_1") and Achievements.is_done("sold_1000"))
	for id in ["iron_ore", "lead", "silver", "copper", "aluminium", "gold", "diamond", "nickel"]:
		MetaEvents.apply(&"picked", {"item": id, "count": 1})
	check("«Коллекционер руд»: 8 видов", Achievements.is_done("kinds_8"))
	MetaEvents.apply(&"picked", {"item": "energy_drink", "count": 5})
	check("еда видом добычи не считается", Achievements.value("kinds") == 8)
	var pr := Achievements.progress(MetaData.achievement("picked_1000"))
	check("прогресс «подобрано»: число из тысячи", pr.y == 1000 and pr.x > 0 and pr.x < 1000)
	GameState.level = 6
	Achievements.evaluate()
	check("уровень берётся живьём", Achievements.is_done("level_5") and not Achievements.is_done("level_15"))
	var tiers := {}
	for a in MetaData.achievements():
		tiers[int(a["tier"])] = true
	check("есть бронза, серебро и золото", tiers.size() == 3)


func _ach_data_ok() -> bool:
	for a in MetaData.achievements():
		if String(a.get("name_ru", "")) == "" or String(a.get("desc_ru", "")) == "":
			return false
		if not ResourceLoader.exists("res://art/meta/%s.png" % a["glyph"]):
			return false
		if MetaRewards.normalize(a.get("reward", {})).is_empty():
			return false
	return true


func _test_road() -> void:
	_fresh()
	check("в дороге есть ступени, очки растут", TrophyRoad.steps().size() >= 10 and int(TrophyRoad.steps()[1]["at"]) > int(TrophyRoad.steps()[0]["at"]))
	check("без очков ступени закрыты", TrophyRoad.claimable().is_empty() and TrophyRoad.next_index() == 0)
	MetaState.root()["pts"] = int(TrophyRoad.steps()[1]["at"])
	check("набрали очков на две ступени", TrophyRoad.claimable() == [0, 1])
	var c0 := GameState.coins
	var r := TrophyRoad.claim(0)
	check("ступень 1 выдана", r["ok"] and GameState.coins > c0)
	check("повторно ступень не выдаётся", not TrophyRoad.claim(0)["ok"])
	check("закрытая ступень (недобранные очки) не выдаётся", not TrophyRoad.claim(5)["ok"])
	check("осталась одна к получению, следующая — третья", TrophyRoad.claimable() == [1] and TrophyRoad.next_index() == 2)
	MetaState.root()["pts"] = 100000
	for i in TrophyRoad.claimable():
		TrophyRoad.claim(i)
	check("дорога пройдена", TrophyRoad.next_index() == -1 and TrophyRoad.claimable().is_empty())


func _test_ads() -> void:
	_fresh()
	check("лимит «×2» дня — 1 из наших данных", MetaAds.limit(MetaAds.DAILY) == 1)
	check("лимит «×2» заданий — 4 из наших данных (владелец 26.10)", MetaAds.limit(MetaAds.QUEST) == 4)
	check("существующий лимит из balance.json читается той же схемой", MetaAds.limit("small_coins") == 3)
	var got := [0]
	var cb := func() -> void: got[0] += 1
	check("ролик за ×2 дня: первый раз — награда", MetaAds.request(MetaAds.DAILY, cb) and got[0] == 1)
	check("второй раз за сутки — отказ без выдачи", not MetaAds.request(MetaAds.DAILY, cb) and got[0] == 1)
	for i in range(5):
		MetaAds.request(MetaAds.QUEST, cb)
	check("«×2» заданий — не больше четырёх в сутки", got[0] == 5 and not MetaAds.can(MetaAds.QUEST))
	check("счёт идёт в общие дневные лимиты рекламы GameState", GameState.get_ad_uses_today(MetaAds.QUEST) == 4)
	GameState.ad_daily_counts.clear()
	check("после суточного сброса лимит снова открыт", MetaAds.can(MetaAds.DAILY))
	check("точки показа есть в реестре AdManager", not AdManager.placement(MetaAds.DAILY).is_empty() and not AdManager.placement(MetaAds.QUEST).is_empty())


func _test_save_roundtrip() -> void:
	_fresh()
	QuestEngine.refresh()
	DailyReward.claim()
	MetaEvents.apply(&"picked", {"item": "gold", "count": 7})
	MetaEvents.apply(&"sold", {"coins": 700, "count": 7})
	var q0: Dictionary = MetaState.sub("quests")["daily"][0]
	var p0 := int(q0["progress"])
	var data: Dictionary = SaveSystem._serialize()
	check("мета-состояние попадает в сейв (ext)", data["ext"].has("meta"))
	var round_trip = JSON.parse_string(JSON.stringify(data))
	GameState.ext.clear()
	SaveSystem._apply(round_trip)
	check("мета-состояние восстановлено из сейва", GameState.ext.has("meta"))
	check("счётчики после загрузки читаются как целые", MetaState.counter("picked") == 7 and typeof(MetaState.counter("picked")) == TYPE_INT)
	check("достижение осталось полученным", Achievements.is_done("gold_1") and Achievements.is_done("sale_1"))
	check("прогресс задания сохранился", int(MetaState.sub("quests")["daily"][0]["progress"]) == p0)
	check("серия и «сегодня» сохранились", int(MetaState.sub("daily")["streak"]) == 1 and not DailyReward.can_claim())
	var daily_json := JSON.stringify(MetaState.sub("quests")["daily"])
	QuestEngine.refresh()
	check("после загрузки задания дня не пересоздаются", JSON.stringify(MetaState.sub("quests")["daily"]) == daily_json)
	var bad := Achievements.evaluate()
	check("после загрузки достижения не выдаются заново", bad.is_empty())
	GameState.reset_progress()
	check("reset_progress стирает мета-прогресс", not MetaState.is_unlocked() and Achievements.done_count() == 0)

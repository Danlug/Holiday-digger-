extends Node
## test_daily_tasks — ежедневные задания (заказ владельца, раунд 3) без окна:
## местная полночь на подставных часах и поясе, набор дня из 13 слотов
## (владелец, 27.10) и ориентиры владельца, события «потратил» и «поел»,
## прогресс, награды, сундук звёзд и серия дней, замена задания (бесплатная и за
## ролик), сохранение, кнопка HUD. Звёзды, сундук на 5 долларов и миссии
## «посмотри рекламу» подробно — tests/test_daily13.
##
## Запуск: godot --headless --path . res://tests/test_daily_tasks.tscn

var failures := 0
var total := 0

## 2026-10-19 — понедельник.
const MONDAY := 20745
const H := 3600


func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", label])


func _ready() -> void:
	print("=== test_daily_tasks ===")
	await get_tree().process_frame
	_test_local_midnight()
	_test_generation()
	_test_new_events()
	_test_progress_and_claim()
	_test_chest_and_streak()
	_test_reroll()
	_test_save_roundtrip()
	await _test_button()
	MetaClock.override_unix = -1
	MetaClock.override_tz_sec = MetaClock.TZ_AUTO
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


## Местное время: unix = сутки UTC + час, пояс — смещение в часах.
func _at(day: int, utc_hour: float, tz_hours: float = 3.0) -> void:
	MetaClock.override_unix = day * MetaClock.DAY + int(utc_hour * H)
	MetaClock.override_tz_sec = int(tz_hours * H)


func _fresh(day: int = MONDAY, depth: int = 120) -> void:
	GameState.reset_progress()
	GameState.world_seed = 4242
	GameState.max_depth_reached = depth
	_at(day, 9.0)
	MetaState.root()["unlocked"] = true
	MetaState.sub("events")["bought"] = true
	MetaState.sub("events")["slept"] = true


func _find(tpl: String) -> Dictionary:
	for q in QuestEngine.daily():
		if String(q["tpl"]) == tpl:
			return q
	return {}


## Подменить задание слота заданием нужного шаблона (как при генерации).
func _force(slot: int, tpl: String) -> Dictionary:
	var cfg: Dictionary = MetaData.quests()["daily"]
	var q := QuestGen._make("daily", MetaState.today(), slot, MetaData.template(tpl), cfg["slots"][slot], cfg,
		QuestGen.tier_for(GameState.max_depth_reached), GameState.max_depth_reached)
	QuestEngine.daily()[slot] = q
	return q


# ---------------------------------------------------------------------------

func _test_local_midnight() -> void:
	_at(MONDAY, 22.0, 3.0)
	check("UTC+3, 22:00 UTC — у игрока уже 01:00 следующих суток", MetaClock.local_day() == MONDAY + 1)
	check("до местной полуночи 23 часа", MetaClock.seconds_to_next_day() == 23 * H)
	check("сутки UTC (лимиты рекламы, ShopRemote) — прежние", MetaClock.real_day() == MONDAY)
	_at(MONDAY, 2.0, -5.0)
	check("UTC−5, 02:00 UTC — у игрока ещё 21:00 вчера", MetaClock.local_day() == MONDAY - 1 and MetaClock.seconds_to_next_day() == 3 * H)
	MetaClock.override_tz_sec = MetaClock.TZ_AUTO
	check("подменённые часы без пояса — UTC (тест не зависит от машины)", MetaClock.tz_offset_sec() == 0)
	check("таймер «чч:мм:сс»", MetaClock.hms(3725) == "01:02:05" and MetaClock.hms(-4) == "00:00:00")
	MetaClock.override_unix = -1
	var sys := MetaClock.tz_offset_sec()
	check("пояс системы читается и разумен", sys % 60 == 0 and absi(sys) <= 14 * H)

	_fresh()
	_at(MONDAY, 20.0 + 59.0 / 60.0, 3.0)   # 23:59 у игрока
	GameState.reset_progress()
	GameState.world_seed = 4242
	MetaState.root()["unlocked"] = true
	check("23:59 местного — набор дня выдан (13 миссий)", QuestEngine.refresh() and QuestEngine.daily().size() == 13)
	var d0 := JSON.stringify(QuestEngine.daily())
	_at(MONDAY, 20.99, 3.0)
	check("до полуночи набор тот же", not QuestEngine.refresh() and JSON.stringify(QuestEngine.daily()) == d0)
	_at(MONDAY, 21.0 + 1.0 / H, 3.0)   # 00:00:01 у игрока, а по UTC ещё 21:00
	check("местная полночь — новый набор (по UTC сутки те же)", QuestEngine.refresh() and JSON.stringify(QuestEngine.daily()) != d0
		and MetaClock.real_day() == MONDAY)
	var d1 := JSON.stringify(QuestEngine.daily())
	_at(MONDAY, 22.0, -5.0)   # пояс сменили на запад: местные сутки «назад»
	check("смена пояса на запад не возвращает вчерашний набор", not QuestEngine.refresh() and JSON.stringify(QuestEngine.daily()) == d1)


func _test_generation() -> void:
	_fresh()
	var seen := {"bought": true, "slept": true}
	var pools := []
	for sl in MetaData.quests()["daily"]["slots"]:
		pools.append((sl["pool"] as Dictionary).keys())
	var slots_ok := true
	var dig_any_days := 0
	var anchors := {}
	var unique_ok := true
	var slots: Array = MetaData.quests()["daily"]["slots"]
	for d in range(60):
		var set := QuestGen.generate("daily", MONDAY + d, 4242, 120, seen)
		if set.size() != 13:
			slots_ok = false
		var tpls := {}
		for i in range(set.size()):
			var t := String(set[i]["tpl"])
			# Из пула своего слота — всегда, когда в пуле было что взять (иначе — запасной путь).
			var had := not QuestGen._pool_candidates(slots[i], "daily", 2, 120, seen, tpls).is_empty()
			if had and not (pools[i] as Array).has(t):
				slots_ok = false
			tpls[t] = true
			if ["dig_any", "sell_coins", "spend_coins", "eat"].has(t):
				anchors[t] = int(set[i]["target"])
		if tpls.size() != set.size():
			unique_ok = false
		if String(set[0]["tpl"]) == "dig_any":
			dig_any_days += 1
	check("13 миссий, каждая из пула своего слота, если в нём было что взять", slots_ok)
	check("в наборе нет двух одинаковых заданий", unique_ok)
	check("«прокопай любые клетки» — в большинстве дней (вес 6 из 7)", dig_any_days >= 40)
	check("ориентиры владельца на средней ступени: 500 клеток, 1000 продажи, 500 трат, 3 еды",
		anchors.get("dig_any") == 500 and anchors.get("sell_coins") == 1000 and anchors.get("spend_coins") == 500 and anchors.get("eat") == 3)
	check("ступень средней игры — рекорд 80–249", QuestGen.tier_for(120) == 2 and int(MetaData.quests()["owner_anchor"]["tier"]) == 2)

	var t_low := int(MetaData.template("dig_any")["targets"][QuestGen.tier_for(10)])
	var t_high := int(MetaData.template("dig_any")["targets"][QuestGen.tier_for(3000)])
	check("цель копки растёт со ступенью (новичку меньше, глубинщику больше)", t_low < 500 and t_high > 500)

	var none_unseen := true
	for d in range(60):
		for q in QuestGen.generate("daily", MONDAY + d, 7, 120, {}):
			if ["bought", "slept", "monster_killed", "refueled"].has(String(q["event"])):
				none_unseen = false
	check("без виденных событий нет заданий на покупку, сон, монстров, заправку", none_unseen)
	var got_sleep := false
	for d in range(80):
		for q in QuestGen.generate("daily", MONDAY + d, 7, 120, {"slept": true}):
			if String(q["tpl"]) == "sleep":
				got_sleep = true
	check("сон дома появляется, когда игрок уже спал", got_sleep)

	var set0 := QuestGen.generate("daily", MONDAY, 4242, 120, seen)
	check("копка (трудное) платит больше заботы (лёгкое)", int(set0[0]["reward"]["coins"]) > int(set0[7]["reward"]["coins"]))
	check("генерация детерминирована", JSON.stringify(set0) == JSON.stringify(QuestGen.generate("daily", MONDAY, 4242, 120, seen)))
	var w := QuestGen.generate("weekly", MetaClock.week_of(MONDAY), 4242, 120, seen)
	check("недельных три: второе с долларом, третье — «посмотри рекламу 25 раз»", w.size() == 3
		and int(w[1]["reward"].get("dollars", 0)) == 1 and String(w[2]["tpl"]) == "watch_ads" and int(w[2]["target"]) == 25)
	var wk_dig := QuestGen._make("weekly", 1, 0, MetaData.template("dig_any"), MetaData.quests()["weekly"]["slots"][0],
		MetaData.quests()["weekly"], 2, 120)
	check("недельная копка — несколько дней ежедневной (×4)", int(wk_dig["target"]) == 2000)
	check("ежедневные — без недельных шаблонов (уровни недели, «выполни N»)", _no_weekly_only())


func _no_weekly_only() -> bool:
	for d in range(40):
		for q in QuestGen.generate("daily", MONDAY + d, 11, 900, {"bought": true, "slept": true}):
			if ["level_up", "dailies_done"].has(String(q["tpl"])):
				return false
	return true


func _test_new_events() -> void:
	_fresh()
	var got: Array = []
	var cb := func(id: StringName, data: Dictionary) -> void: got.append([String(id), data])
	GameState.game_event.connect(cb)
	GameState.coins = 1000
	GameState.spend_coins(120)
	GameState.spend_coins(5000)   # не хватило — не списано и не событие
	GameState.dollars = 3
	GameState.spend_dollars(1)
	GameState.debug_free_shop = true
	GameState.spend_coins(70)     # «бесплатно» отладки — не трата
	GameState.debug_free_shop = false
	GameState.hunger = 10.0
	GameState.add_item("food_bar", 1)
	HouseFood.eat("food_bar")
	HouseFood.eat_now("food_buldak")
	GameState.game_event.disconnect(cb)
	var spent: Array = []
	var ate: Array = []
	for e in got:
		if e[0] == "spent":
			spent.append(e[1])
		elif e[0] == "ate":
			ate.append(e[1])
	check("spend_coins шлёт «spent» с суммой", spent.size() == 2 and int(spent[0]["amount"]) == 120 and String(spent[0]["currency"]) == "coins")
	check("spend_dollars — «spent» в долларах", spent.size() == 2 and String(spent[1]["currency"]) == "dollars")
	check("рюкзак и стол дома шлют «ate»", ate.size() == 2 and String(ate[0]["id"]) == "food_bar" and float(ate[0]["hunger"]) > 0.0)


func _test_progress_and_claim() -> void:
	_fresh()
	QuestEngine.refresh()
	var dig := _force(0, "dig_any")
	_force(1, "sell_coins")
	var spend := _force(2, "spend_coins")
	var eat := _force(3, "eat")
	_force(4, "pick_gold")
	for i in range(499):
		MetaEvents.apply(&"dug", {"cell": Vector2i(3, 90), "tile": TileTypes.Type.DIRT, "loot": false})
	check("прогресс копки 499/500 — ещё не готово", int(dig["progress"]) == 499 and not QuestEngine.is_done(dig))
	var res := MetaEvents.apply(&"dug", {"cell": Vector2i(3, 90), "tile": TileTypes.Type.DIRT, "loot": false})
	check("500-я клетка закрывает задание (и тост)", QuestEngine.is_done(dig) and (res["quests"] as Array).has(dig))
	MetaEvents.apply(&"spent", {"currency": "coins", "amount": 300})
	MetaEvents.apply(&"spent", {"currency": "dollars", "amount": 2})
	check("траты: считаются монеты, доллары — нет", int(spend["progress"]) == 300)
	MetaEvents.apply(&"spent", {"currency": "coins", "amount": 900})
	check("перебор упирается в цель", int(spend["progress"]) == 500 and QuestEngine.is_done(spend))
	for i in range(3):
		MetaEvents.apply(&"ate", {"id": "food_bar"})
	check("три еды закрывают «поешь 3 раза»", QuestEngine.is_done(eat))
	# Копка двигает и соседние миссии (земля, глубже N…) — готовых может быть больше трёх.
	check("на кнопке — все готовые к получению", QuestEngine.is_claimable(dig) and QuestEngine.is_claimable(spend)
		and QuestEngine.is_claimable(eat) and QuestEngine.daily_claimable_count() == QuestEngine.daily_done_count())
	check("звёзд пока нет: звезда — за забранную миссию", QuestEngine.stars_today() == 0 and QuestEngine.stars_needed() == 10)
	var coins0 := GameState.coins
	var c := QuestEngine.claim(String(dig["id"]))
	check("забрать: монеты и опыт выданы", bool(c["ok"]) and GameState.coins == coins0 + int(dig["reward"]["coins"]))
	check("второй раз не выдаётся", not bool(QuestEngine.claim(String(dig["id"]))["ok"]))
	check("забранное учтено счётчиком заданий (достижения «задания»)", MetaState.counter("quests") == 1)
	check("забрал — звезда", QuestEngine.stars_today() == 1)


func _complete_day() -> void:
	for q in QuestEngine.daily():
		q["progress"] = int(q["target"])
		QuestEngine.claim(String(q["id"]))


func _test_chest_and_streak() -> void:
	_fresh()
	QuestEngine.refresh()
	check("сундук закрыт, пока звёзд нет", not QuestEngine.bonus_ready())
	var cfg: Dictionary = MetaData.quests()["daily"]
	var base := int(cfg["reward"]["coins"][2])
	_complete_day()
	check("все 13 забраны — сундук готов и на бейдже", QuestEngine.bonus_ready() and QuestEngine.daily_claimable_count() == 1
		and MetaState.counter("perfect_days") == 1)
	var r1 := QuestEngine.bonus_reward()
	check("сундук первого дня: 5 долларов и энергетик, монет нет (прибавки серии ещё нет)", int(r1.get("dollars", 0)) == 5
		and r1.has("item") and not r1.has("coins"))
	var before := GameState.get_item_count("energy_drink")
	var c := QuestEngine.claim_bonus()
	check("сундук открыт: серия 1, предмет в рюкзаке", bool(c["ok"]) and int(c["streak"]) == 1 and QuestEngine.streak_now() == 1
		and GameState.get_item_count("energy_drink") == before + 1)
	check("второй раз сундук не открывается", not bool(QuestEngine.claim_bonus()["ok"]))

	_at(MONDAY + 1, 9.0)
	QuestEngine.refresh()
	check("назавтра серия видна (1) и сундук закрыт", QuestEngine.streak_now() == 1 and not QuestEngine.bonus_ready())
	_complete_day()
	var r2 := QuestEngine.bonus_reward()
	check("второй день серии: +10% от прежнего сундука (1.5 награды) монетами", QuestEngine.streak_if_claimed() == 2
		and int(r2["coins"]) == int(round(base * 1.5 * 0.1 / 5.0)) * 5 and int(r2["dollars"]) == 5)
	QuestEngine.claim_bonus()

	_at(MONDAY + 3, 9.0)   # пропущен один день
	QuestEngine.refresh()
	check("пропуск одного дня серию не рвёт", QuestEngine.streak_now() == 2)
	_complete_day()
	QuestEngine.claim_bonus()
	check("после пропуска серия продолжается: 3", QuestEngine.streak_now() == 3)

	_at(MONDAY + 6, 9.0)   # пропущено два дня
	QuestEngine.refresh()
	check("пропуск двух дней рвёт серию", QuestEngine.streak_now() == 0 and QuestEngine.streak_if_claimed() == 1)
	_complete_day()
	QuestEngine.claim_bonus()
	check("серия начинается заново, рекорд помнится", QuestEngine.streak_now() == 1
		and int(MetaState.sub("quests")["streak"]["best"]) == 3 and MetaState.counter("quest_streak_best") == 3)

	var st: Dictionary = MetaState.sub("quests")["streak"]
	st["n"] = 6
	st["last"] = MONDAY + 6
	_at(MONDAY + 7, 9.0)
	QuestEngine.refresh()
	_complete_day()
	var r7 := QuestEngine.bonus_reward()
	check("седьмой день серии: 5 + 1 доллар и потолок прибавки +50%", int(r7.get("dollars", 0)) == 6 and QuestEngine.streak_pct(7) == 50
		and QuestEngine.streak_pct(30) == 50 and int(r7["coins"]) == int(round(base * 1.5 * 0.5 / 5.0)) * 5)
	var d0 := GameState.dollars
	QuestEngine.claim_bonus()
	check("6 долларов выданы (доллар серии — в недельный потолок)", GameState.dollars == d0 + 6)
	Achievements.evaluate()
	check("достижение «Ни дня без задания» — за 7 дней серии", Achievements.is_done("tasks_streak_7") and not Achievements.is_done("tasks_streak_30"))


func _test_reroll() -> void:
	_fresh()
	QuestEngine.refresh()
	_force(4, "dig_dirt")   # слот «порода»: камень свободен для замены копки
	var q := _force(0, "dig_any")
	q["progress"] = 120
	check("одна бесплатная замена в день", QuestEngine.free_rerolls_left() == 1 and QuestEngine.can_reroll(q))
	var old_tpls := {}
	for x in QuestEngine.daily():
		old_tpls[String(x["tpl"])] = true
	var r := QuestEngine.reroll(String(q["id"]))
	var nq: Dictionary = r.get("quest", {})
	# Из пула слота (камень), а если камень уже в наборе (запасной путь другого слота) — любой новый.
	check("замена: другой шаблон того же слота, прогресс с нуля", bool(r["ok"]) and bool(r["free"])
		and (String(nq["tpl"]) == "dig_stone" or old_tpls.has("dig_stone")) and not old_tpls.has(String(nq["tpl"]))
		and int(nq["progress"]) == 0 and int(nq["slot"]) == 0 and QuestEngine.daily()[0] == nq)
	check("новый id: старый quest больше не найти", QuestEngine.find(String(q["id"])).is_empty() and not QuestEngine.find(String(nq["id"])).is_empty())
	check("бесплатная потрачена", QuestEngine.free_rerolls_left() == 0)
	var sell: Dictionary = QuestEngine.daily()[1]
	check("вторая без ролика — отказ", not bool(QuestEngine.reroll(String(sell["id"]))["ok"]))
	GameState.ad_daily_counts.clear()
	var placement := QuestEngine.ad_placement_reroll()
	check("лимит роликов замены — 2 (наши данные)", MetaAds.limit(placement) == 2)
	var ok_ad := [false]
	var asked := MetaAds.request(placement, func() -> void: ok_ad[0] = bool(QuestEngine.reroll(String(sell["id"]), true)["ok"]))
	check("замена за ролик (сети нет — засчитано сразу)", asked and ok_ad[0] and MetaAds.uses_left(placement) == 1)
	var done: Dictionary = QuestEngine.daily()[3]
	done["progress"] = int(done["target"])
	check("выполненное задание не меняется", not QuestEngine.can_reroll(done) and not bool(QuestEngine.reroll(String(done["id"]), true)["ok"]))
	var a := QuestGen.reroll(QuestEngine.daily()[4], QuestEngine.daily(), 4242, 120, {"bought": true}, 7)
	var b := QuestGen.reroll(QuestEngine.daily()[4], QuestEngine.daily(), 4242, 120, {"bought": true}, 7)
	check("замена детерминирована (переустановка не «перебросит» заново)", JSON.stringify(a) == JSON.stringify(b))
	_at(MONDAY + 1, 9.0)
	QuestEngine.refresh()
	check("новый день — снова одна бесплатная замена", QuestEngine.free_rerolls_left() == 1)


func _test_save_roundtrip() -> void:
	_fresh()
	QuestEngine.refresh()
	var q := _force(0, "dig_any")
	q["progress"] = 312
	QuestEngine.reroll(String(QuestEngine.daily()[4]["id"]))
	var st: Dictionary = MetaState.sub("quests")["streak"]
	st["n"] = 4
	st["last"] = MONDAY - 1
	QuestEngine.mark_opened()
	var data: Dictionary = SaveSystem._serialize()
	var rt = JSON.parse_string(JSON.stringify(data))
	GameState.ext.clear()
	SaveSystem._apply(rt)
	check("прогресс 312/500 пережил сейв", int(QuestEngine.daily()[0]["progress"]) == 312 and int(QuestEngine.daily()[0]["target"]) == 500)
	check("серия и замены пережили сейв", QuestEngine.streak_now() == 4 and QuestEngine.free_rerolls_left() == 0)
	check("«набор открыт» пережил сейв", not QuestEngine.is_new_today())
	var dj := JSON.stringify(QuestEngine.daily())
	check("после загрузки набор дня не пересоздаётся", not QuestEngine.refresh() and JSON.stringify(QuestEngine.daily()) == dj)
	for x in QuestEngine.daily():
		x["progress"] = int(x["target"])
	QuestEngine.claim(String(QuestEngine.daily()[0]["id"]))
	check("забрать после загрузки работает (числа из JSON)", bool(QuestEngine.daily()[0]["claimed"]))
	MetaState.sub("quests").erase("streak")
	MetaState.sub("quests").erase("free_rerolls")
	check("старый сейв без серии и замен читается", QuestEngine.streak_now() == 0 and QuestEngine.free_rerolls_left() == 1)


func _test_button() -> void:
	_fresh()
	QuestEngine.refresh()
	var host := VBoxContainer.new()
	add_child(host)
	var b := DailyTasksButton.mount(host)
	await get_tree().process_frame
	b._sync()
	check("без MetaService кнопки нет (нечего открывать)", not b.visible)
	var svc := MetaService.attach(self)
	await get_tree().process_frame
	MetaState.sub("daily")["last"] = MetaState.today()
	b._sync()
	check("мета включена — кнопка видна, набор новый (звёздочка)", b.visible and b._new_mark.visible)
	var q := _force(0, "dig_any")
	q["progress"] = int(q["target"])
	b._sync()
	var badge := b.button.get_node_or_null(UiBtn.BADGE_NAME) as Control
	check("готовое задание — красный бейдж 1", badge != null and badge.visible and b._claimable == 1)
	b._on_pressed()
	await get_tree().process_frame
	check("нажатие открывает окно заданий и отмечает набор открытым", svc.tasks.is_open() and not QuestEngine.is_new_today())
	check("окно — плиток столько, сколько заданий", svc.tasks._list.get_child_count() == QuestEngine.daily().size())
	svc.tasks.close()
	await get_tree().create_timer(0.4).timeout
	check("окно закрывается", not svc.tasks.is_open())
	MetaState.root()["unlocked"] = false
	b._sync()
	check("до онбординга кнопки нет", not b.visible)
	svc.queue_free()
	host.queue_free()
	await get_tree().process_frame

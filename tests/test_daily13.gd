extends Node
## test_daily13 — слова владельца 27.10: «Ежедневных миссий нужно 13, за каждую
## миссию даётся звёздочка, 10 звёздочек — сундук … Даёт 5 долларов. Доллары за
## рекламу — 5 раз в день. Новая ежедневная миссия — посмотри рекламу 5 раз.
## Новая еженедельная миссия — посмотри рекламу 25 раз.»
##
## Проверяет: 13 разных миссий на любой ступени (и без виденных событий), сумма
## наград дня прежняя, недоступное на ступени не выпадает (монстры до 1500,
## переплавка без лома, тайник на нулевой ступени, события, которых не было);
## звёзды и сундук на 10-й звезде — ровно 5 долларов мимо недельного потолка;
## ролик «доллары» — 5 раз в сутки; миссии «посмотри рекламу» (5 в день, 25 в
## неделю) считают ролики всех точек показа; окно: шкала звёзд и 13 плиток.
##
## Запуск: godot --headless --path . res://tests/test_daily13.tscn

var failures := 0
var total := 0

## 2026-10-19 — понедельник.
const MONDAY := 20745
const DEPTHS := [0, 30, 120, 400, 1000, 3000]
const ALL_SEEN := {"bought": true, "slept": true, "monster_killed": true, "refueled": true, "stored": true,
	"crafted": true, "fuel_refined": true, "chest_opened": true, "lucky_find": true, "fever_started": true,
	"cave_cleared": true}


func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", label])


func _ready() -> void:
	print("=== test_daily13 ===")
	await get_tree().process_frame
	_test_owner_numbers()
	_test_thirteen()
	_test_day_reward()
	_test_tier_gates()
	_test_stars_chest()
	await _test_ads()
	await _test_panel()
	MetaClock.override_unix = -1
	MetaClock.override_tz_sec = MetaClock.TZ_AUTO
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _fresh(depth: int = 120) -> void:
	GameState.reset_progress()
	GameState.world_seed = 4242
	GameState.max_depth_reached = depth
	GameState.ad_daily_counts.clear()
	MetaClock.override_unix = MONDAY * MetaClock.DAY + 9 * 3600
	MetaClock.override_tz_sec = 3 * 3600
	MetaState.root()["unlocked"] = true
	MetaState.sub("events")["bought"] = true
	MetaState.sub("events")["slept"] = true


func _tpls(set: Array) -> Array:
	return set.map(func(q): return String(q["tpl"]))


func _find(set: Array, tpl: String) -> Dictionary:
	for q in set:
		if String(q["tpl"]) == tpl:
			return q
	return {}


# ---------------------------------------------------------------------------

func _test_owner_numbers() -> void:
	var q: Dictionary = MetaData.quests()
	check("13 миссий в день (владелец)", QuestGen.count_of(q["daily"]) == 13 and (q["daily"]["slots"] as Array).size() == 13)
	check("сундук — на 10-й звезде, 5 долларов (владелец, proposed: false)",
		int(QuestGen.num(q["daily"]["chest"]["stars"])) == 10 and int(QuestGen.num(q["daily"]["chest"]["dollars"])) == 5
		and q["daily"]["chest"]["stars"]["proposed"] == false and q["daily"]["chest"]["dollars"]["proposed"] == false)
	check("ролик «доллары» — 5 раз в сутки (владелец)", Balance.get_ad_daily_limit("small_premium_currency") == 5)
	check("ролик «доллары» даёт 5 долларов", int(Balance.unwrap(ShopCatalog.ad_reward("small_premium_currency").get("dollars", 0))) == 5)
	var ads := MetaData.template("watch_ads")
	check("«посмотри рекламу»: 5 в день, 25 в неделю (владелец)", int(QuestGen.num(ads["fixed_target"]["daily"])) == 5
		and int(QuestGen.num(ads["fixed_target"]["weekly"])) == 25 and ads["fixed_target"]["weekly"]["proposed"] == false)


func _test_thirteen() -> void:
	var full_ok := true
	var distinct_ok := true
	var ads_ok := true
	for depth in DEPTHS:
		for seen in [{}, ALL_SEEN]:
			for d in range(30):
				var set := QuestGen.generate("daily", MONDAY + d, 4242 + d, depth, seen)
				if set.size() != 13:
					full_ok = false
					print("  неполный набор: глубина %d, %d миссий: %s" % [depth, set.size(), _tpls(set)])
				var uniq := {}
				for t in _tpls(set):
					uniq[t] = true
				if uniq.size() != set.size():
					distinct_ok = false
				var ad := _find(set, "watch_ads")
				if ad.is_empty() or int(ad["target"]) != 5 or int(ad["slot"]) != 12:
					ads_ok = false
	check("на каждой ступени (0…5), и без виденных событий, — ровно 13 миссий", full_ok)
	check("все 13 миссий дня разные", distinct_ok)
	check("«посмотри рекламу 5 раз» — в наборе каждого дня (последний слот)", ads_ok)
	var w := QuestGen.generate("weekly", MetaClock.week_of(MONDAY), 4242, 3000, ALL_SEEN)
	var wad := _find(w, "watch_ads")
	check("неделя: «посмотри рекламу 25 раз» (масштаб недели и слота цель не трогает)", not wad.is_empty() and int(wad["target"]) == 25)
	var only_once := true
	for d in range(20):
		var ww := QuestGen.generate("weekly", d, 4242, 400, ALL_SEEN)
		if _tpls(ww).count("watch_ads") != 1:
			only_once = false
	check("ролики в неделе — одна миссия, не две (шаблон берётся только из своего слота)", only_once)
	var base := QuestGen.generate("daily", MONDAY, 4242, 120, {})
	var cfg := {"slots": [{"pool": {"eat": 1}, "scale": 1.0, "reward": 1.0}, {"scale": 1.0, "reward": 1.0}], "count": 2,
		"template_kind": "daily", "reward": MetaData.quests()["daily"]["reward"], "points": 1}
	var own := QuestGen.generate("newbie", 3, 4242, 120, {}, cfg)
	check("свой набор слотов тем же генератором (для стрика новичка)", own.size() == 2 and String(own[0]["tpl"]) == "eat"
		and String(own[0]["id"]).begins_with("newbie:3:") and base.size() == 13)


## День по монетам и опыту — прежний: сумма множителей миссий = 5 прежних заданий + сундук ×1.5.
func _test_day_reward() -> void:
	var sum := 0.0
	for sl in MetaData.quests()["daily"]["slots"]:
		sum += float(sl["reward"])
	check("сумма множителей 13 миссий = 6.5 (прежние 5.0 + сундук ×1.5)", absf(sum - 6.5) < 0.001)
	var rw: Dictionary = MetaData.quests()["daily"]["reward"]
	var ok := true
	for t in range(6):
		var set := QuestGen.generate("daily", MONDAY, 4242, int(DEPTHS[t]), ALL_SEEN)
		var coins := 0
		for q in set:
			coins += int(q["reward"]["coins"])
		var want := float(rw["coins"][t]) * 6.5
		if absf(float(coins) - want) > 5.0 * 13.0:
			ok = false
			print("  ступень %d: %d монет за день, ждали ≈ %d" % [t, coins, int(want)])
	check("монеты дня на каждой ступени ≈ 6.5 награды ступени (округление до 5)", ok)
	var r := QuestGen.generate("daily", MONDAY, 4242, 120, ALL_SEEN)
	check("копка платит больше всех миссий дня", int(r[0]["reward"]["coins"]) == r.map(func(q): return int(q["reward"]["coins"])).max())


func _test_tier_gates() -> void:
	var monsters_low := false
	var monsters_hi := false
	var craft_deep := false
	var level_late := false
	var chest_t0 := false
	var unseen := false
	for d in range(60):
		for depth in [400, 1000, 1499]:
			for t in _tpls(QuestGen.generate("daily", MONDAY + d, 7 + d, depth, ALL_SEEN)):
				if t == "kill_monsters" or t == "clear_cave":
					monsters_low = true
		for t in _tpls(QuestGen.generate("daily", MONDAY + d, 7 + d, 1600, ALL_SEEN)):
			if t == "kill_monsters" or t == "clear_cave":
				monsters_hi = true
		for t in _tpls(QuestGen.generate("daily", MONDAY + d, 7 + d, 1000, ALL_SEEN)):
			if t == "craft":
				craft_deep = true
		for t in _tpls(QuestGen.generate("daily", MONDAY + d, 7 + d, 120, ALL_SEEN)):
			if t == "level_up_day":
				level_late = true
		for t in _tpls(QuestGen.generate("daily", MONDAY + d, 7 + d, 10, ALL_SEEN)):
			if t == "open_chest":
				chest_t0 = true
		for t in _tpls(QuestGen.generate("daily", MONDAY + d, 7 + d, 3000, {})):
			if ["kill_monsters", "clear_cave", "craft", "fuel_refine", "refuel", "store_items", "open_chest", "lucky", "fever",
					"buy_any", "sleep"].has(t):
				unseen = true
	check("монстры и полости не выпадают до рекорда 1500 (владелец: «с 1500»)", not monsters_low)
	check("с рекорда 1600 (бой уже был) монстры выпадают", monsters_hi)
	check("переплавка не выпадает глубже ступени 3 (лом лежит до 500)", not craft_deep)
	check("«получи уровень» — только на нулевой ступени", not level_late)
	check("тайник не выпадает на нулевой ступени (тайники с 20-й клетки)", not chest_t0)
	check("события, которых игрок ещё не видел, миссией не становятся", not unseen)
	var rec := MetaData.template("depth_record")
	check("«рекорд +N» не выпадает у дна мира", not QuestGen._eligible(rec, "daily", 5, {}, 9990)
		and QuestGen._eligible(rec, "daily", 5, {}, 3000))


func _claim_n(n: int) -> void:
	var k := 0
	for q in QuestEngine.daily():
		if k >= n:
			return
		if bool(q["claimed"]):
			continue
		q["progress"] = int(q["target"])
		QuestEngine.claim(String(q["id"]))
		k += 1


func _test_stars_chest() -> void:
	_fresh()
	QuestEngine.refresh()
	check("набор дня — 13 миссий, звёзд 0 из 10", QuestEngine.daily().size() == 13 and QuestEngine.stars_today() == 0
		and QuestEngine.stars_needed() == 10)
	var q0: Dictionary = QuestEngine.daily()[0]
	q0["progress"] = int(q0["target"])
	check("выполнено, но не забрано — звезды ещё нет", QuestEngine.stars_today() == 0 and QuestEngine.is_claimable(q0))
	_claim_n(9)
	check("9 звёзд — сундук закрыт", QuestEngine.stars_today() == 9 and not QuestEngine.bonus_ready())
	_claim_n(1)
	check("10-я звезда — сундук готов и на бейдже", QuestEngine.stars_today() == 10 and QuestEngine.bonus_ready()
		and QuestEngine.claimable_count() >= 1)
	# Недельный потолок повторяемых долларов исчерпан — пяти долларам сундука это не мешает.
	MetaRewards.dollars_left_this_week()
	MetaState.sub("wk_dollars")["n"] = int(MetaData.daily()["premium_cap"]["per_week"])
	check("потолок недели исчерпан", MetaRewards.dollars_left_this_week() == 0)
	var d0 := GameState.dollars
	var c0 := GameState.coins
	var r := QuestEngine.claim_bonus()
	check("сундук звёзд: ровно 5 долларов, мимо недельного потолка", bool(r["ok"]) and GameState.dollars == d0 + 5
		and int(r["reward"]["dollars"]) == 5)
	check("в первый день серии монет сундук не даёт (монеты дня — в миссиях)", GameState.coins == c0)
	check("сундук открыт — второй раз нет", not QuestEngine.bonus_ready() and not bool(QuestEngine.claim_bonus()["ok"]))
	_claim_n(3)
	check("звёзды 11–13 после сундука собираются (все 13 — «идеальный день»)", QuestEngine.stars_today() == 13
		and MetaState.counter("perfect_days") == 1 and not QuestEngine.bonus_ready())
	# Старый сейв посреди дня: в наборе пять заданий — сундук открывают все пять.
	_fresh()
	QuestEngine.refresh()
	QuestEngine.daily().resize(5)
	_claim_n(5)
	check("старый набор из 5 заданий: сундук на 5-й звезде", QuestEngine.stars_needed() == 5 and QuestEngine.bonus_ready())


## Мета-слой слушает шину, как в игре: MetaService сам кормит MetaEvents.
func _test_ads() -> void:
	_fresh()
	QuestEngine.refresh()
	MetaState.sub("daily")["last"] = MetaState.today()   # окно подарка дня не нужно
	var svc := MetaService.attach(self)
	await get_tree().process_frame
	var heard: Array = []
	var cb := func(id: StringName, data: Dictionary) -> void:
		if id == &"ad_watched":
			heard.append(String(data.get("placement", "")))
	GameState.game_event.connect(cb)
	var day_ad := _find(QuestEngine.daily(), "watch_ads")
	var week_ad := _find(MetaState.sub("quests")["weekly"], "watch_ads")
	check("миссии «посмотри рекламу» выданы: день 5, неделя 25", not day_ad.is_empty() and not week_ad.is_empty()
		and int(day_ad["target"]) == 5 and int(week_ad["target"]) == 25)
	var d0 := GameState.dollars
	var ok_n := 0
	for i in range(6):
		if bool(ShopService.claim_ad("small_premium_currency")["ok"]):
			ok_n += 1
	check("ролик «доллары»: 5 раз в сутки, шестой — отказ", ok_n == 5 and ShopService.ad_uses_left("small_premium_currency") == 0)
	check("5 роликов по 5 долларов = 25 долларов", GameState.dollars == d0 + 25)
	check("каждый ролик — событие шины ad_watched с точкой показа", heard.size() == 5 and heard[0] == "small_premium_currency")
	check("5 роликов закрывают дневную миссию", QuestEngine.is_done(day_ad) and int(day_ad["progress"]) == 5)
	check("и двигают недельную: 5/25", int(week_ad["progress"]) == 5 and not QuestEngine.is_done(week_ad))
	# Остальные точки показа идут тем же счётом.
	ShopService.claim_ad("small_coins")
	MetaAds.request(MetaAds.QUEST, func() -> void: pass)
	TechAds.request(func(_ok: bool) -> void: pass)
	ShopRemote.watch_ad()
	GameState.try_use_ad_reward("skip_sleep_at_home")
	check("монеты, «×2», скважина, покупка из шахты, сон — тоже ролики: 10/25", int(week_ad["progress"]) == 10
		and heard.has("small_coins") and heard.has(MetaAds.QUEST) and heard.has(TechAds.PLACEMENT)
		and heard.has(ShopRemote.PLACEMENT) and heard.has("skip_sleep_at_home"))
	check("счётчик просмотров мета-слоя", MetaState.counter("ads") == 10)
	for i in range(15):
		GameState.note_ad_watched("test")
	check("25 роликов за неделю закрывают недельную миссию", QuestEngine.is_done(week_ad))
	check("«посмотри рекламу» не заменяется", not QuestEngine.can_reroll(day_ad) or QuestEngine.is_done(day_ad))
	var fresh_ad := day_ad.duplicate()
	fresh_ad["progress"] = 0
	fresh_ad["claimed"] = false
	check("и невыполненная тоже не заменяется", not QuestGen.can_reroll(fresh_ad, QuestEngine.daily(), ALL_SEEN, 120))
	GameState.game_event.disconnect(cb)
	svc.queue_free()
	await get_tree().process_frame


func _test_panel() -> void:
	_fresh()
	QuestEngine.refresh()
	MetaState.sub("daily")["last"] = MetaState.today()
	var svc := MetaService.attach(self)
	await get_tree().process_frame
	svc.open_tasks()
	await get_tree().process_frame
	var p := svc.tasks
	check("окно: 13 плиток в прокрутке", p.is_open() and p._list.get_child_count() == 13 and p._scroll != null)
	check("шкала звёзд: 13 клеток, засечка на 10", p._track != null and p._track.total == 13 and p._track.needed == 10
		and p._track.stars == 0)
	check("прокрутка не выше экрана", p._scroll.custom_minimum_size.y <= get_viewport().get_visible_rect().size.y)
	var q: Dictionary = QuestEngine.daily()[5]
	q["progress"] = int(q["target"])
	p.refresh()
	await get_tree().process_frame
	check("готовое — первой плиткой", p._list.get_child(0).get_meta("qid") == String(q["id"]) and p._track.done == 1)
	p._claim(String(q["id"]), 1.0, p._list.get_child(0))
	await get_tree().process_frame
	check("забрал из окна — звезда на шкале, плитка внизу", p._track.stars == 1
		and p._list.get_child(12).get_meta("qid") == String(q["id"]))
	_claim_n(9)
	p.refresh()
	await get_tree().process_frame
	var chest := p.find_child("Chest", true, false) as Button
	check("10 звёзд — сундук-кнопка в окне", chest != null and QuestEngine.bonus_ready())
	var d0 := GameState.dollars
	p._press_chest(chest)
	await get_tree().process_frame
	check("нажатие на сундук — 5 долларов", GameState.dollars == d0 + 5 and bool(MetaState.sub("quests")["bonus_claimed"]))
	p.close()
	await get_tree().create_timer(0.4).timeout
	svc.queue_free()
	await get_tree().process_frame

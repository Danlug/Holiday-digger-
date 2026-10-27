extends Node
## test_newbie_streak — стрик новичка (владелец 27.10) без main.tscn: календарь на
## подставных часах и поясе (день N открыт в N-е местные сутки, будущие закрыты,
## прошедшие пропущены, часы назад не открывают вчерашний день), миссии по событиям
## шины и по состоянию игры, засчитывание дня, награда, возврат пропущенного дня
## ровно за 50 долларов (не дешевле и не при нехватке), сейв/загрузка, конец месяца,
## «бот забирает дни» (claim_all), пункт меню без бейджа и экран (плитки, кнопки).
##
## Запуск: godot --headless --path . res://tests/test_newbie_streak.tscn

var failures := 0
var total := 0

## 2026-10-19 — понедельник (как в test_daily_tasks).
const D0 := 20745
const H := 3600


func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", label])


func _ready() -> void:
	print("=== test_newbie_streak ===")
	await get_tree().process_frame
	GameState.debug_free_shop = false
	_test_data()
	_test_start_and_calendar()
	_test_missions_day1()
	_test_filters_and_today_only()
	_test_restore()
	_test_clock_back_and_tz()
	_test_checks()
	_test_month_over()
	_test_save_roundtrip()
	_test_claim_all()
	await _test_screen()
	MetaClock.override_unix = -1
	MetaClock.override_tz_sec = MetaClock.TZ_AUTO
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


## Местное время: unix = сутки UTC + час, пояс — смещение в часах.
func _at(day: int, utc_hour: float, tz_hours: float = 3.0) -> void:
	MetaClock.override_unix = day * MetaClock.DAY + int(utc_hour * H)
	MetaClock.override_tz_sec = int(tz_hours * H)


func _fresh(unlocked: bool = true) -> void:
	GameState.reset_progress()
	GameState.world_seed = 4242
	_at(D0, 9.0)
	MetaState.root()["unlocked"] = unlocked


func _ev(id: StringName, data: Dictionary = {}) -> int:
	return NewbieStreak.on_event(id, data)


func _mi(n: int, mid: String) -> int:
	var ms := NewbieStreak.missions(n)
	for i in range(ms.size()):
		if String(ms[i]["id"]) == mid:
			return i
	return -1


## Выполнить все миссии сегодняшнего дня «по-честному»: события и состояние игры.
func _complete_today() -> int:
	var n := NewbieStreak.today_n()
	var done := 0
	for m in NewbieStreak.missions(n):
		var t := NewbieStreak.target_of(m)
		match String(m.get("check", "")):
			"depth":
				GameState.max_depth_reached = maxi(GameState.max_depth_reached, t)
			"level":
				GameState.level = maxi(GameState.level, t)
			"artifacts":
				while GameState.collected_artifacts.size() < t:
					GameState.collected_artifacts.append("fake_%d" % GameState.collected_artifacts.size())
			"tool":
				if not GameState.owned_tools.has(String(m["item"])):
					GameState.owned_tools.append(String(m["item"]))
			"well":
				GameState.well_level = maxi(GameState.well_level, t)
			_:
				var d: Dictionary = (m.get("filter", {}) as Dictionary).duplicate()
				if d.has("depth_min"):
					d["cell"] = Vector2i(3, int(d["depth_min"]) + 1)
				if d.has("loot"):
					d["loot"] = true
				if d.get("kind", "") == "stone":
					d["tile"] = TileTypes.Type.STONE
				var s := String(m.get("sum", ""))
				if s != "":
					d[s] = t
					done = maxi(done, _ev(StringName(m["event"]), d))
				else:
					for _i in range(t):
						done = maxi(done, _ev(StringName(m["event"]), d))
	return maxi(done, NewbieStreak.refresh())


# ---------------------------------------------------------------------------

func _test_data() -> void:
	check("30 дней (число владельца)", NewbieStreak.days_total() == 30)
	check("возврат дня — 50 долларов (число владельца)", NewbieStreak.restore_price() == 50)
	var raw: Dictionary = NewbieStreak.data()
	check("30 дней и 50 $ помечены proposed: false",
		raw["days_total"]["proposed"] == false and raw["restore_dollars"]["proposed"] == false)
	check("подарок за 30 дней — заглушка proposed: true", raw["grand_prize"]["proposed"] == true and raw["grand_prize"]["status"] == "soon")
	var ok_size := true
	var ok_reward := true
	var ok_titles := true
	var events := {}
	var checks := {}
	for n in range(1, 31):
		var ms := NewbieStreak.missions(n)
		if ms.size() < 3 or ms.size() > 5:
			ok_size = false
		var r := NewbieStreak.reward(n)
		if int(r.get("coins", 0)) <= 0 or r.has("dollars"):
			ok_reward = false
		for m in ms:
			if NewbieStreak.mission_title(m).contains("{") or String(m.get("name_en", "")) == "":
				ok_titles = false
			if m.has("event"):
				events[String(m["event"])] = true
			else:
				checks[String(m["check"])] = true
	check("у каждого дня 3–5 миссий", ok_size)
	check("награда дня — монеты (и опыт/расходник), без долларов", ok_reward)
	check("у каждой миссии есть ru и en название без пустых {}", ok_titles)
	check("сценарий ведёт по механикам: продажа, еда, сон, копка, тайник, жадность, задания дня",
		events.has("sold") and events.has("ate") and events.has("slept") and events.has("dug")
		and events.has("chest_opened") and events.has("fever_started") and events.has("quest_done"))
	check("к концу — глубина, артефакты, ручной бур и скважина", checks.has("depth") and checks.has("artifacts")
		and checks.has("tool") and checks.has("well"))
	check("первые дни простые: день 1 — продажа, еда, сон, глубина 50",
		_mi(1, "sell") >= 0 and _mi(1, "eat") >= 0 and _mi(1, "sleep") >= 0
		and int(NewbieStreak.missions(1)[_mi(1, "depth")]["target"]) == 50)
	var deep := []
	for n in range(1, 31):
		for m in NewbieStreak.missions(n):
			if String(m.get("check", "")) == "depth":
				deep.append(int(m["target"]))
	check("глубина в сценарии растёт и доходит до 300/500/800", deep.has(300) and deep.has(500) and deep.has(800)
		and deep == _sorted(deep))
	var old := Settings.language
	Settings.language = "en"
	check("en: заголовок и название миссии", NewbieStreak.text("title") == "Newbie streak"
		and NewbieStreak.mission_title(NewbieStreak.missions(1)[0]) == "Sell 5 items at the workshop")
	Settings.language = old


func _sorted(a: Array) -> Array:
	var b := a.duplicate()
	b.sort()
	return b


func _test_start_and_calendar() -> void:
	_fresh(false)
	check("до онбординга стрик не начат", not NewbieStreak.is_started() and NewbieStreak.current_index() == 0)
	_ev(&"sold", {"coins": 10, "count": 5})
	check("до онбординга события не считаются", not NewbieStreak.is_started()
		and NewbieStreak.status(1) == NewbieStreak.St.LOCKED)
	MetaState.root()["unlocked"] = true
	check("мета включилась — день 1 начался в эти местные сутки", NewbieStreak.ensure_started()
		and NewbieStreak.start_day() == MetaState.today() and NewbieStreak.current_index() == 1)
	check("повторный старт не сдвигает день 1", not NewbieStreak.ensure_started())
	check("день 1 — сегодня, день 2 и дальше закрыты", NewbieStreak.status(1) == NewbieStreak.St.TODAY
		and NewbieStreak.status(2) == NewbieStreak.St.LOCKED and NewbieStreak.status(30) == NewbieStreak.St.LOCKED)
	check("до дня 5 — 4 суток", NewbieStreak.days_until(5) == 4)
	_at(D0, 20.0)   # 23:00 по местному (UTC+3) — те же сутки
	check("23:00 — ещё день 1", NewbieStreak.current_index() == 1)
	_at(D0, 21.0)   # местная полночь
	check("местная полночь — день 2 открылся, день 1 пропущен", NewbieStreak.current_index() == 2
		and NewbieStreak.status(2) == NewbieStreak.St.TODAY and NewbieStreak.status(1) == NewbieStreak.St.MISSED)


func _test_missions_day1() -> void:
	_fresh()
	NewbieStreak.ensure_started()
	var coins0 := GameState.coins
	check("продажа 3 вещей — 3/5", _ev(&"sold", {"coins": 12, "count": 3}) == 0 and NewbieStreak.progress(1, _mi(1, "sell")) == 3)
	_ev(&"sold", {"coins": 30, "count": 4})
	check("ещё 4 — упирается в цель 5/5", NewbieStreak.progress(1, _mi(1, "sell")) == 5)
	_ev(&"ate", {"id": "food_soup"})
	_ev(&"slept", {"hours": 8.0})
	GameState.max_depth_reached = 49
	check("глубина 49 из 50 — день не засчитан", NewbieStreak.refresh() == 0 and not NewbieStreak.is_done(1)
		and NewbieStreak.progress(1, _mi(1, "depth")) == 49)
	check("доля дня — между 0 и 1", NewbieStreak.fraction(1) > 0.9 and NewbieStreak.fraction(1) < 1.0)
	GameState.max_depth_reached = 50
	check("рекорд 50 — день 1 засчитан (возвращает номер дня)", NewbieStreak.refresh() == 1 and NewbieStreak.is_done(1))
	check("засчитанный день — DONE, награда ждёт", NewbieStreak.status(1) == NewbieStreak.St.DONE
		and NewbieStreak.can_claim(1) and NewbieStreak.claimable_count() == 1)
	check("повторная проверка не засчитывает второй раз", NewbieStreak.refresh() == 0)
	var lv0 := GameState.level
	var xp0 := GameState.xp
	var res := NewbieStreak.claim(1)
	check("награда дня 1: +100 монет и опыт", bool(res["ok"]) and GameState.coins == coins0 + 100
		and (GameState.level > lv0 or GameState.xp > xp0))
	check("второй раз не забрать", not bool(NewbieStreak.claim(1)["ok"]) and GameState.coins == coins0 + 100)
	GameState.max_depth_reached = 0
	check("засчитанный день не «расчитывается» обратно", NewbieStreak.is_done(1) and NewbieStreak.mission_done(1, _mi(1, "depth")))


func _test_filters_and_today_only() -> void:
	_fresh()
	NewbieStreak.ensure_started()
	_at(D0 + 2, 9.0)   # день 3: камни, железо, еда ×2, глубина 100
	check("сейчас день 3", NewbieStreak.today_n() == 3)
	_ev(&"dug", {"cell": Vector2i(1, 30), "tile": TileTypes.Type.DIRT, "loot": false})
	check("земля — не камень", NewbieStreak.progress(3, _mi(3, "stone")) == 0)
	_ev(&"dug", {"cell": Vector2i(1, 30), "tile": TileTypes.Type.STONE, "loot": false})
	check("камень засчитан", NewbieStreak.progress(3, _mi(3, "stone")) == 1)
	_ev(&"picked", {"item": "lead", "count": 9})
	check("свинец не идёт в «железо»", NewbieStreak.progress(3, _mi(3, "iron")) == 0)
	_ev(&"picked", {"item": "iron_ore", "count": 4})
	check("железо считается штуками", NewbieStreak.progress(3, _mi(3, "iron")) == 4)
	check("события сегодня не трогают прошлые и будущие дни", NewbieStreak.progress(2, 0) == 0
		and NewbieStreak.progress(4, 0) == 0 and NewbieStreak.status(4) == NewbieStreak.St.LOCKED)
	# День 6 — склад (dir: put), день 7 — задания дня (kind: daily).
	_at(D0 + 5, 9.0)
	_ev(&"stored", {"item": "iron_ore", "count": 7, "dir": "take"})
	check("«взять со склада» не засчитывается как «положить»", NewbieStreak.progress(6, _mi(6, "store")) == 0)
	_ev(&"stored", {"item": "iron_ore", "count": 7, "dir": "put"})
	check("«положить на склад» — 7", NewbieStreak.progress(6, _mi(6, "store")) == 7)
	_at(D0 + 6, 9.0)
	_ev(&"quest_done", {"id": "weekly:1:0", "kind": "weekly", "source": "meta"})
	check("недельное задание — не «задание дня»", NewbieStreak.progress(7, _mi(7, "quests")) == 0)
	_ev(&"quest_done", {"id": "daily:1:0", "kind": "daily", "source": "meta"})
	check("задание дня засчитано", NewbieStreak.progress(7, _mi(7, "quests")) == 1)
	_ev(&"dug", {"cell": Vector2i(1, 99), "tile": TileTypes.Type.DIRT, "loot": false})
	_ev(&"dug", {"cell": Vector2i(1, 100), "tile": TileTypes.Type.DIRT, "loot": false})
	check("«глубже 100»: клетка 99 не считается, 100 — считается", NewbieStreak.progress(7, _mi(7, "deep")) == 1)
	# Полночь посреди дня: прогресс дня 7 замирает, новые события идут в день 8.
	_at(D0 + 7, 9.0)
	_ev(&"quest_done", {"id": "daily:2:0", "kind": "daily", "source": "meta"})
	check("после полуночи день 7 пропущен и прогресс его не растёт",
		NewbieStreak.status(7) == NewbieStreak.St.MISSED and NewbieStreak.progress(7, _mi(7, "quests")) == 1)


func _test_restore() -> void:
	_fresh()
	NewbieStreak.ensure_started()
	_at(D0 + 3, 9.0)   # сегодня день 4; дни 1–3 пропущены
	check("дни 1–3 пропущены, 4 — сегодня, 5 — закрыт", NewbieStreak.status(1) == NewbieStreak.St.MISSED
		and NewbieStreak.status(3) == NewbieStreak.St.MISSED and NewbieStreak.status(4) == NewbieStreak.St.TODAY
		and NewbieStreak.status(5) == NewbieStreak.St.LOCKED)
	GameState.dollars = 49
	var coins0 := GameState.coins
	var r := NewbieStreak.restore(3)
	check("49 долларов — вернуть нельзя, ничего не списано", not bool(r["ok"]) and GameState.dollars == 49
		and NewbieStreak.status(3) == NewbieStreak.St.MISSED and not NewbieStreak.can_restore(3))
	GameState.dollars = 120
	check("с 120 долларами можно", NewbieStreak.can_restore(3))
	r = NewbieStreak.restore(3)
	check("вернуть день 3: списано ровно 50 (не меньше)", bool(r["ok"]) and int(r["price"]) == 50 and GameState.dollars == 70)
	check("день засчитан целиком, без миссий, отметка «за доллары»", NewbieStreak.status(3) == NewbieStreak.St.DONE
		and NewbieStreak.was_bought(3) and NewbieStreak.missions_complete(3))
	check("награда дня 3 выдана сразу (+200 монет)", GameState.coins == coins0 + 200 and not NewbieStreak.can_claim(3))
	check("второй раз тот же день не купить", not bool(NewbieStreak.restore(3)["ok"]) and GameState.dollars == 70)
	check("сегодняшний день не покупается", not bool(NewbieStreak.restore(4)["ok"]) and GameState.dollars == 70)
	check("будущий день не покупается", not bool(NewbieStreak.restore(5)["ok"]) and GameState.dollars == 70)
	check("день вне 1..30 не покупается", not bool(NewbieStreak.restore(31)["ok"]) and not bool(NewbieStreak.restore(0)["ok"]))
	GameState.dollars = 50
	check("ровно 50 — хватает, остаётся 0", bool(NewbieStreak.restore(1)["ok"]) and GameState.dollars == 0)
	check("выполнено 2 дня из 30", NewbieStreak.done_count() == 2)
	GameState.debug_free_shop = false


func _test_clock_back_and_tz() -> void:
	_fresh()
	NewbieStreak.ensure_started()
	_at(D0 + 2, 9.0)
	check("день 3", NewbieStreak.today_n() == 3)
	_at(D0, 9.0)   # перевели часы на двое суток назад
	check("часы назад: сегодня остаётся днём 3, день 1 не открылся заново", NewbieStreak.today_n() == 3
		and NewbieStreak.status(1) == NewbieStreak.St.MISSED)
	_ev(&"sold", {"coins": 50, "count": 5})
	check("часы назад: продажа не идёт в день 1", NewbieStreak.progress(1, _mi(1, "sell")) == 0)
	# Перелёт на запад (UTC+3 → UTC−5) в те же сутки UTC: местная дата «назад» — день не меняется.
	_fresh()
	NewbieStreak.ensure_started()
	_at(D0, 22.0, 3.0)   # 01:00 следующих местных суток: стрик начат вчера → день 2
	check("UTC+3, 22:00 UTC — у игрока уже день 2", NewbieStreak.today_n() == 2)
	_at(D0, 22.5, -5.0)   # пояс −5: по местным часам снова 17:30 вчерашних суток
	check("смена пояса на запад не возвращает день 1", NewbieStreak.today_n() == 2)


func _test_checks() -> void:
	_fresh()
	NewbieStreak.ensure_started()
	_at(D0 + 23, 9.0)   # день 24: ручной бур
	check("день 24 — сегодня", NewbieStreak.today_n() == 24)
	var di := _mi(24, "drill")
	check("бура нет — миссия 0/1", NewbieStreak.progress(24, di) == 0)
	GameState.owned_tools.append("hand_drill")
	check("бур уже есть — миссия выполнена сразу", NewbieStreak.mission_done(24, di))
	check("остальные миссии дня ещё нет — день не засчитан", NewbieStreak.refresh() == 0)
	check("выполнить день 24 целиком", _complete_today() == 24 and NewbieStreak.is_done(24))
	_at(D0 + 28, 9.0)   # день 29: скважина
	check("скважины нет — 0/1", NewbieStreak.progress(29, _mi(29, "well")) == 0)
	GameState.well_level = 1
	check("скважина построена — выполнено", NewbieStreak.mission_done(29, _mi(29, "well")))
	check("проверки пропущенного дня не «оживают» (день 25 пропущен)", NewbieStreak.status(25) == NewbieStreak.St.MISSED
		and NewbieStreak.progress(25, _mi(25, "depth")) == 0)


func _test_month_over() -> void:
	_fresh()
	NewbieStreak.ensure_started()
	for d in range(30):
		_at(D0 + d, 9.0)
		if d % 2 == 0:
			_complete_today()
	check("15 дней выполнено миссиями, 15 пропущено", NewbieStreak.done_count() == 15)
	_at(D0 + 30, 9.0)
	check("31-е сутки: сегодняшнего дня нет, все невыполненные — пропущены", NewbieStreak.today_n() == 0
		and NewbieStreak.status(30) == NewbieStreak.St.MISSED and NewbieStreak.status(2) == NewbieStreak.St.MISSED)
	check("крупный подарок ещё не готов", not NewbieStreak.grand_ready())
	GameState.dollars = 15 * 50
	var ok := true
	for n in range(1, 31):
		if NewbieStreak.status(n) == NewbieStreak.St.MISSED:
			ok = ok and bool(NewbieStreak.restore(n)["ok"])
	check("после месяца пропущенные дни всё ещё возвращаются за доллары", ok and GameState.dollars == 0)
	check("все 30 дней — подарок «готов», но это заглушка: забрать нельзя", NewbieStreak.grand_ready()
		and not NewbieStreak.grand_available())


func _test_save_roundtrip() -> void:
	_fresh()
	NewbieStreak.ensure_started()
	_complete_today()
	_at(D0 + 1, 9.0)
	_ev(&"dug", {"cell": Vector2i(1, 5), "tile": TileTypes.Type.DIRT, "loot": false})
	_ev(&"dug", {"cell": Vector2i(1, 6), "tile": TileTypes.Type.DIRT, "loot": false})
	var start := NewbieStreak.start_day()
	var data: Dictionary = SaveSystem._serialize()
	var rt = JSON.parse_string(JSON.stringify(data))
	GameState.ext.clear()
	check("после очистки ext стрика нет", not NewbieStreak.is_started())
	SaveSystem._apply(rt)
	check("начало стрика пережило сейв", NewbieStreak.start_day() == start and NewbieStreak.today_n() == 2)
	check("день 1 засчитан и награда ждёт (числа из JSON)", NewbieStreak.is_done(1) and NewbieStreak.can_claim(1))
	check("прогресс дня 2 (2 клетки) пережил сейв", NewbieStreak.progress(2, _mi(2, "dig")) == 2)
	_ev(&"dug", {"cell": Vector2i(1, 7), "tile": TileTypes.Type.DIRT, "loot": false})
	check("после загрузки прогресс растёт дальше", NewbieStreak.progress(2, _mi(2, "dig")) == 3)
	check("забрать после загрузки работает", bool(NewbieStreak.claim(1)["ok"]))
	GameState.ext[NewbieStreak.KEY] = {"start": 3.0}
	check("частичный сейв (без days) читается", NewbieStreak.start_day() == 3 and not NewbieStreak.is_done(1))
	GameState.reset_progress()
	check("сброс игры стирает стрик", not NewbieStreak.is_started())


func _test_claim_all() -> void:
	_fresh()
	NewbieStreak.ensure_started()
	for d in range(3):
		_at(D0 + d, 9.0)
		_complete_today()
	var c0 := GameState.coins
	check("бот: claim_all забирает все готовые дни", NewbieStreak.claim_all() == 3 and GameState.coins == c0 + 100 + 150 + 200)
	check("бот: повторно забирать нечего", NewbieStreak.claim_all() == 0)


func _test_screen() -> void:
	_fresh()
	var svc := NewbieStreakService.attach(self)
	await get_tree().process_frame
	var entry: Dictionary = {}
	for e in MenuRegistry.entries():
		if String(e["id"]) == "newbie_streak":
			entry = e
	check("пункт меню «•••» есть и без бейджа (счётчик меню не трогаем)", not entry.is_empty()
		and not entry.has("badge") and MenuRegistry.badge_of(entry) == 0)
	check("подпись пункта: «День 1 из 30 · выполнено 0»", MenuRegistry.text_of(entry, "body") == "День 1 из 30 · выполнено 0")
	MetaState.root()["unlocked"] = false
	var hidden := true
	for e in MenuRegistry.entries():
		if String(e["id"]) == "newbie_streak":
			hidden = false
	check("до онбординга пункта нет", hidden)
	MetaState.root()["unlocked"] = true
	_complete_today()
	_at(D0 + 3, 9.0)   # сегодня день 4; 2 и 3 пропущены
	GameState.dollars = 60
	svc.open()
	await get_tree().process_frame
	var p := svc.panel
	check("экран открыт, выбран сегодняшний день", p.is_open() and p.selected() == 4)
	check("30 плиток-дней", p._grid.get_child_count() == 30)
	var detail := p._box.find_child("Detail", true, false)
	check("у сегодняшнего дня — строки миссий и нет кнопки возврата", detail.find_child("Mission0", true, false) != null
		and detail.find_child("Restore", true, false) == null)
	p.select(2)
	await get_tree().process_frame
	detail = p._box.find_child("Detail", true, false)
	var rb := detail.find_child("Restore", true, false) as Button
	var cap := rb.find_child("Caption", true, false) as Label if rb != null else null
	check("пропущенный день — кнопка «Вернуть за 50» со значком доллара", cap != null and cap.text == "Вернуть за 50")
	rb.pressed.emit()
	await get_tree().process_frame
	check("нажатие вернуло день 2 за 50 $", NewbieStreak.status(2) == NewbieStreak.St.DONE and GameState.dollars == 10)
	p.select(3)
	await get_tree().process_frame
	rb = p._box.find_child("Detail", true, false).find_child("Restore", true, false) as Button
	rb.pressed.emit()
	await get_tree().process_frame
	check("10 $ — нажатие не покупает день 3", NewbieStreak.status(3) == NewbieStreak.St.MISSED and GameState.dollars == 10)
	p.select(1)
	await get_tree().process_frame
	var cb := p._box.find_child("Detail", true, false).find_child("Claim", true, false) as Button
	var c0 := GameState.coins
	check("выполненный день с наградой — кнопка «Забрать»", cb != null)
	if cb != null:
		cb.pressed.emit()
		await get_tree().process_frame
	check("нажатие забирает награду дня 1", GameState.coins == c0 + 100 and NewbieStreak.is_claimed(1))
	p.select(9)
	await get_tree().process_frame
	detail = p._box.find_child("Detail", true, false)
	check("будущий день — без миссий (секрет), только замок", detail.find_child("Mission0", true, false) == null)
	check("внизу — карточка подарка за 30 дней", p._box.find_child("Grand", true, false) != null)
	p.select(4)
	_at(D0 + 4, 9.0)
	p._tick = 1.0
	p._process(0.0)
	check("полночь при открытом окне: выбран новый сегодняшний день", p.selected() == 5)
	p.close()
	await get_tree().create_timer(0.4).timeout
	check("окно закрывается", not p.is_open())
	svc.queue_free()
	await get_tree().process_frame

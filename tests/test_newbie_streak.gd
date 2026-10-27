extends Node
## test_newbie_streak — стрик новичка (владелец 27.10) без main.tscn: календарь на
## подставных часах и поясе (день N открыт в N-е местные сутки, будущие закрыты,
## прошедшие пропущены, часы назад не открывают вчерашний день), отметка за вход
## (без миссий: зашёл в свои сутки — день отмечен), награда, возврат пропущенного
## дня ровно за 50 долларов (не дешевле и не при нехватке), сейв/загрузка, конец
## месяца, «бот забирает дни» (claim_all), пункт меню без бейджа, кнопка на главном
## экране (NewbieStreakButton) и экран (плитки, кнопки).
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
	_test_checkin()
	_test_restore()
	_test_clock_back_and_tz()
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


# ---------------------------------------------------------------------------

func _test_data() -> void:
	check("30 дней (число владельца)", NewbieStreak.days_total() == 30)
	check("возврат дня — 50 долларов (число владельца)", NewbieStreak.restore_price() == 50)
	var raw: Dictionary = NewbieStreak.data()
	check("30 дней и 50 $ помечены proposed: false",
		raw["days_total"]["proposed"] == false and raw["restore_dollars"]["proposed"] == false)
	check("подарок за 30 дней — заглушка proposed: true", raw["grand_prize"]["proposed"] == true and raw["grand_prize"]["status"] == "soon")
	var ok_reward := true
	var no_missions := true
	for n in range(1, 31):
		var r := NewbieStreak.reward(n)
		if int(r.get("coins", 0)) <= 0 or r.has("dollars"):
			ok_reward = false
		if NewbieStreak.day_def(n).has("missions"):
			no_missions = false
	check("награда дня — монеты (и опыт/расходник), без долларов", ok_reward)
	check("у дней нет миссий — стрик это отметка за вход (владелец 27.10)", no_missions)
	var old := Settings.language
	Settings.language = "en"
	check("en: заголовок", NewbieStreak.text("title") == "Newbie streak")
	Settings.language = old


func _test_start_and_calendar() -> void:
	_fresh(false)
	check("до онбординга стрик не начат", not NewbieStreak.is_started() and NewbieStreak.current_index() == 0)
	check("до онбординга вход не отмечается", NewbieStreak.refresh() == 0 and not NewbieStreak.is_started()
		and NewbieStreak.status(1) == NewbieStreak.St.LOCKED)
	MetaState.root()["unlocked"] = true
	check("мета включилась — день 1 начался в эти местные сутки", NewbieStreak.ensure_started()
		and NewbieStreak.start_day() == MetaState.today() and NewbieStreak.current_index() == 1)
	check("повторный старт не сдвигает день 1", not NewbieStreak.ensure_started())
	check("день 1 — сегодня (ещё не отмечен), день 2 и дальше закрыты", NewbieStreak.status(1) == NewbieStreak.St.TODAY
		and NewbieStreak.status(2) == NewbieStreak.St.LOCKED and NewbieStreak.status(30) == NewbieStreak.St.LOCKED)
	check("до дня 5 — 4 суток", NewbieStreak.days_until(5) == 4)
	_at(D0, 20.0)   # 23:00 по местному (UTC+3) — те же сутки
	check("23:00 — ещё день 1", NewbieStreak.current_index() == 1)
	_at(D0, 21.0)   # местная полночь
	check("местная полночь — день 2 открылся, неотмеченный день 1 пропущен", NewbieStreak.current_index() == 2
		and NewbieStreak.status(2) == NewbieStreak.St.TODAY and NewbieStreak.status(1) == NewbieStreak.St.MISSED)


func _test_checkin() -> void:
	_fresh()
	var coins0 := GameState.coins
	check("вход — день 1 отмечен сразу, без миссий (возвращает номер дня)", NewbieStreak.refresh() == 1
		and NewbieStreak.is_done(1) and not NewbieStreak.was_bought(1))
	check("отмеченный день — DONE, награда ждёт", NewbieStreak.status(1) == NewbieStreak.St.DONE
		and NewbieStreak.can_claim(1) and NewbieStreak.claimable_count() == 1)
	check("второй вход в те же сутки не отмечает ничего", NewbieStreak.refresh() == 0 and NewbieStreak.done_count() == 1)
	var lv0 := GameState.level
	var xp0 := GameState.xp
	var res := NewbieStreak.claim(1)
	check("награда дня 1: +100 монет и опыт", bool(res["ok"]) and GameState.coins == coins0 + 100
		and (GameState.level > lv0 or GameState.xp > xp0))
	check("второй раз не забрать", not bool(NewbieStreak.claim(1)["ok"]) and GameState.coins == coins0 + 100)
	_at(D0 + 1, 9.0)
	check("на следующие сутки вход отмечает день 2", NewbieStreak.refresh() == 2 and NewbieStreak.is_done(2))
	_at(D0 + 3, 9.0)   # пропустил сутки
	check("пропуск суток: день 3 пропущен, вход отмечает день 4", NewbieStreak.refresh() == 4
		and NewbieStreak.status(3) == NewbieStreak.St.MISSED and NewbieStreak.done_count() == 3)
	check("будущие дни закрыты и не отмечаются", NewbieStreak.status(5) == NewbieStreak.St.LOCKED and not NewbieStreak.is_done(5))


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
	check("день отмечен, отметка «за доллары»", NewbieStreak.status(3) == NewbieStreak.St.DONE and NewbieStreak.was_bought(3))
	check("награда дня 3 выдана сразу (+200 монет)", GameState.coins == coins0 + 200 and not NewbieStreak.can_claim(3))
	check("второй раз тот же день не купить", not bool(NewbieStreak.restore(3)["ok"]) and GameState.dollars == 70)
	check("сегодняшний день не покупается", not bool(NewbieStreak.restore(4)["ok"]) and GameState.dollars == 70)
	check("будущий день не покупается", not bool(NewbieStreak.restore(5)["ok"]) and GameState.dollars == 70)
	check("день вне 1..30 не покупается", not bool(NewbieStreak.restore(31)["ok"]) and not bool(NewbieStreak.restore(0)["ok"]))
	GameState.dollars = 50
	check("ровно 50 — хватает, остаётся 0", bool(NewbieStreak.restore(1)["ok"]) and GameState.dollars == 0)
	check("отмечено 2 дня из 30", NewbieStreak.done_count() == 2)
	NewbieStreak.refresh()
	check("отмеченный входом день не покупается", NewbieStreak.is_done(4) and not bool(NewbieStreak.restore(4)["ok"]))


func _test_clock_back_and_tz() -> void:
	_fresh()
	NewbieStreak.ensure_started()
	_at(D0 + 2, 9.0)
	check("день 3", NewbieStreak.today_n() == 3)
	_at(D0, 9.0)   # перевели часы на двое суток назад
	check("часы назад: сегодня остаётся днём 3, день 1 не открылся заново", NewbieStreak.today_n() == 3
		and NewbieStreak.status(1) == NewbieStreak.St.MISSED)
	check("часы назад: вход отмечает день 3, а не день 1", NewbieStreak.refresh() == 3 and not NewbieStreak.is_done(1))
	# Перелёт на запад (UTC+3 → UTC−5) в те же сутки UTC: местная дата «назад» — день не меняется.
	_fresh()
	NewbieStreak.ensure_started()
	_at(D0, 22.0, 3.0)   # 01:00 следующих местных суток: стрик начат вчера → день 2
	check("UTC+3, 22:00 UTC — у игрока уже день 2", NewbieStreak.today_n() == 2)
	_at(D0, 22.5, -5.0)   # пояс −5: по местным часам снова 17:30 вчерашних суток
	check("смена пояса на запад не возвращает день 1", NewbieStreak.today_n() == 2)


func _test_month_over() -> void:
	_fresh()
	NewbieStreak.ensure_started()
	for d in range(30):
		_at(D0 + d, 9.0)
		if d % 2 == 0:
			NewbieStreak.refresh()
	check("15 дней отмечено входом, 15 пропущено", NewbieStreak.done_count() == 15)
	_at(D0 + 30, 9.0)
	check("31-е сутки: сегодняшнего дня нет, вход ничего не отмечает", NewbieStreak.today_n() == 0
		and NewbieStreak.refresh() == 0 and NewbieStreak.status(30) == NewbieStreak.St.MISSED
		and NewbieStreak.status(2) == NewbieStreak.St.MISSED)
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
	NewbieStreak.refresh()
	_at(D0 + 1, 9.0)
	var start := NewbieStreak.start_day()
	var data: Dictionary = SaveSystem._serialize()
	var rt = JSON.parse_string(JSON.stringify(data))
	GameState.ext.clear()
	check("после очистки ext стрика нет", not NewbieStreak.is_started())
	SaveSystem._apply(rt)
	check("начало стрика пережило сейв", NewbieStreak.start_day() == start and NewbieStreak.today_n() == 2)
	check("день 1 отмечен и награда ждёт (числа из JSON)", NewbieStreak.is_done(1) and NewbieStreak.can_claim(1))
	check("после загрузки вход отмечает день 2", NewbieStreak.refresh() == 2)
	check("забрать после загрузки работает", bool(NewbieStreak.claim(1)["ok"]))
	# Сейв прежней версии (день засчитан миссиями, с прогрессом p) читается как отмеченный.
	GameState.ext[NewbieStreak.KEY] = {"v": 1, "start": float(start), "days": {"1": {"p": [5.0, 1.0], "done": true, "how": "missions", "claimed": false}}}
	check("старый сейв с миссиями: день 1 отмечен, награда ждёт", NewbieStreak.is_done(1) and NewbieStreak.can_claim(1)
		and NewbieStreak.refresh() == 2)
	GameState.ext[NewbieStreak.KEY] = {"start": 3.0}
	check("частичный сейв (без days) читается", NewbieStreak.start_day() == 3 and not NewbieStreak.is_done(1))
	GameState.reset_progress()
	check("сброс игры стирает стрик", not NewbieStreak.is_started())


func _test_claim_all() -> void:
	_fresh()
	for d in range(3):
		_at(D0 + d, 9.0)
		NewbieStreak.refresh()
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
	check("подпись пункта: «День 1 из 30 · отмечено 1» (узел отметил вход в первом кадре)", MenuRegistry.text_of(entry, "body") == "День 1 из 30 · отмечено 1")

	# Кнопка на главном экране: узел сам отмечает вход (опрос раз в секунду).
	var host := VBoxContainer.new()
	add_child(host)
	var btn := NewbieStreakButton.mount(host)
	svc._acc = NewbieStreakService.POLL_SEC
	svc._process(0.0)
	btn._sync()
	check("узел стрика отметил вход без действий игрока", NewbieStreak.is_done(1))
	check("кнопка на главном экране видна, под ней «1/30»", btn.visible and btn._count.text == "1/30")
	check("на кнопке бейдж «1» — награда ждёт", btn._claimable == 1)
	btn.button.pressed.emit()
	await get_tree().process_frame
	check("нажатие кнопки открывает экран стрика", svc.panel.is_open())
	svc.panel.close()
	await get_tree().create_timer(0.4).timeout
	MetaState.root()["unlocked"] = false
	btn._sync()
	check("до онбординга кнопки нет", not btn.visible)
	var hidden := true
	for e in MenuRegistry.entries():
		if String(e["id"]) == "newbie_streak":
			hidden = false
	check("до онбординга пункта нет", hidden)
	MetaState.root()["unlocked"] = true
	host.queue_free()

	_at(D0 + 3, 9.0)   # сегодня день 4; 2 и 3 пропущены
	GameState.dollars = 60
	svc.open()
	await get_tree().process_frame
	var p := svc.panel
	check("экран открыт, выбран сегодняшний день, и он уже отмечен входом", p.is_open() and p.selected() == 4
		and NewbieStreak.status(4) == NewbieStreak.St.DONE)
	check("30 плиток-дней", p._grid.get_child_count() == 30)
	var detail := p._box.find_child("Detail", true, false)
	check("у сегодняшнего дня — «Забрать» и нет кнопки возврата", detail.find_child("Claim", true, false) != null
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
	check("отмеченный день с наградой — кнопка «Забрать»", cb != null)
	if cb != null:
		cb.pressed.emit()
		await get_tree().process_frame
	check("нажатие забирает награду дня 1", GameState.coins == c0 + 100 and NewbieStreak.is_claimed(1))
	p.select(9)
	await get_tree().process_frame
	detail = p._box.find_child("Detail", true, false)
	check("будущий день — без кнопок, только замок", detail.find_child("Claim", true, false) == null
		and detail.find_child("Restore", true, false) == null)
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

extends Node
## test_analytics — аналитика по согласию (ГДД §16.1, scripts/core/analytics.gd):
##  1. Без согласия ("unset", "denied") и с выключенной сборкой не копится ничего.
##  2. С согласием событие несёт свойства устройства и сессии; запретных ключей нет,
##     сложные значения (словари, векторы) отброшены.
##  3. Очередь не длиннее 500 (старые выпадают); отказ стирает очередь и её файл.
##  4. flush собирает правильный /batch/ (отправитель подменён, сети нет), успех чистит
##     отправленное, неудача оставляет и ставит паузу; без ключа отправки нет.
##  5. Шина GameState: нужные события уходят, частые — нет; вехи глубины по 100.
##  6. Settings хранит согласие; окно согласия под тестом само не появляется, кнопки пишут ответ.
## Сценой — нужны автозагрузки:  godot --headless --path . res://tests/test_analytics.tscn

var failures := 0
var total := 0
var _sent: Array = []
var _done := Callable()


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _ready() -> void:
	print("=== test_analytics ===")
	Analytics.set_config({"enabled_build": true, "host": "https://eu.i.posthog.com/", "api_key": "phc_test"})
	Analytics.sender = func(url: String, body: String, done: Callable) -> void:
		_sent.append({"url": url, "body": body})
		_done = done
	_test_no_consent()
	_test_granted_props()
	_test_cap_and_opt_out()
	await _test_flush()
	await _test_bus()
	await _test_settings_and_dialog()
	Analytics.sender = Callable()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _consent(v: String) -> void:
	Settings.set_analytics_consent(v)


func _test_no_consent() -> void:
	Analytics.clear_queue()
	check("под тестом окно согласия не спрашивается", Analytics.automated() and not Analytics.should_ask())
	Settings.analytics_consent = "unset"
	Analytics.track("bought", {"id": "a"})
	check("unset: ничего не копится", Analytics.queue().is_empty())
	_consent("denied")
	Analytics.track("bought", {"id": "a"})
	check("denied: ничего не копится", Analytics.queue().is_empty())
	_consent("granted")
	Analytics.set_config({"enabled_build": false, "host": "https://eu.i.posthog.com/", "api_key": "phc_test"})
	Analytics.track("bought", {"id": "a"})
	check("сборка без аналитики: ничего", Analytics.queue().is_empty())
	Analytics.set_config({"enabled_build": true, "host": "https://eu.i.posthog.com/", "api_key": "phc_test"})


func _test_granted_props() -> void:
	_consent("granted")
	Analytics.clear_queue()
	Analytics.track("bought", {"id": "drill_1", "currency": "coins", "name": "Вася", "email": "a@b.c",
		"ip": "1.2.3.4", "save": "{}", "cell": Vector2i(3, 4), "items": {"coal": 2}})
	var q := Analytics.queue()
	check("granted: событие в очереди", q.size() == 1)
	if q.is_empty():
		return
	var e: Dictionary = q[0]
	var p: Dictionary = e["properties"]
	check("событие: имя, uuid, distinct_id, время", e["event"] == "bought" and String(e["uuid"]).length() == 36
		and String(e["distinct_id"]).length() == 36 and String(e["timestamp"]).ends_with("Z"))
	for k in ["build", "$os", "$os_version", "$device_model", "locale", "screen", "viewport", "window", "dpi_scale",
			"gpu", "renderer", "session_id", "session_s", "control_mode", "reduce_motion"]:
		check("свойство " + k, p.has(k))
	check("геолокация выключена", p.get("$geoip_disable") == true)
	check("свои свойства дошли", p.get("id") == "drill_1" and p.get("currency") == "coins")
	check("вектор и словарь отброшены", not p.has("cell") and not p.has("items"))
	for bad in ["name", "email", "ip", "$ip", "save"]:
		check("нет ключа " + bad, not _has_key(e, bad))
	check("distinct_id постоянный (файл)", FileAccess.file_exists(Analytics.ID_PATH)
		and FileAccess.get_file_as_string(Analytics.ID_PATH) == e["distinct_id"])


func _has_key(v, key: String) -> bool:
	if typeof(v) == TYPE_DICTIONARY:
		for k in v:
			if String(k) == key or _has_key(v[k], key):
				return true
	elif typeof(v) == TYPE_ARRAY:
		for x in v:
			if _has_key(x, key):
				return true
	return false


func _test_cap_and_opt_out() -> void:
	_consent("granted")
	Analytics.clear_queue()
	for i in 600:
		Analytics.track("t", {"i": i})
	var q := Analytics.queue()
	check("очередь не длиннее 500", q.size() == Analytics.QUEUE_CAP, str(q.size()))
	check("выпали старые", int(q[0]["properties"]["i"]) == 100 and int(q[-1]["properties"]["i"]) == 599)
	Analytics.save_queue()
	check("очередь пишется на диск", FileAccess.file_exists(Analytics.QUEUE_PATH))
	_consent("denied")
	check("отказ стирает очередь", Analytics.queue().is_empty())
	check("отказ стирает файл очереди", not FileAccess.file_exists(Analytics.QUEUE_PATH))


func _test_flush() -> void:
	_consent("granted")
	Analytics.clear_queue()
	var a := Analytics.attach(self)
	await get_tree().process_frame
	check("согласие при запуске: session_start", Analytics.queue().size() == 1 and Analytics.queue()[0]["event"] == "session_start")
	Analytics.track("bought", {"id": "x"})
	_sent.clear()
	a.flush()
	check("flush зовёт отправителя", _sent.size() == 1)
	if _sent.is_empty():
		a.queue_free()
		return
	check("адрес /batch/", _sent[0]["url"] == "https://eu.i.posthog.com/batch/", _sent[0]["url"])
	var body = JSON.parse_string(_sent[0]["body"])
	check("тело: api_key и batch", typeof(body) == TYPE_DICTIONARY and body.get("api_key") == "phc_test"
		and typeof(body.get("batch")) == TYPE_ARRAY and body["batch"].size() == 2)
	var ev: Dictionary = body["batch"][1]
	check("в пачке event, distinct_id, timestamp, properties", ev.get("event") == "bought" and ev.has("distinct_id")
		and ev.has("timestamp") and typeof(ev.get("properties")) == TYPE_DICTIONARY)
	a.flush()
	check("пока ответа нет — вторая отправка не идёт", _sent.size() == 1)
	Analytics.track("late", {})
	_done.call(true)
	check("успех: отправленное ушло, новое осталось", Analytics.queue().size() == 1 and Analytics.queue()[0]["event"] == "late")
	a.flush()
	_done.call(false)
	check("неудача: событие осталось, пауза", Analytics.queue().size() == 1 and a._backoff >= Analytics.FLUSH_EVERY_S)
	a._backoff = 0.0
	Analytics.set_config({"enabled_build": true, "host": "https://eu.i.posthog.com/", "api_key": ""})
	_sent.clear()
	a.flush()
	check("пустой ключ: не отправляем, очередь копится", _sent.is_empty() and Analytics.queue().size() == 1)
	Analytics.set_config({"enabled_build": true, "host": "https://eu.i.posthog.com/", "api_key": "phc_test"})
	_consent("denied")
	_sent.clear()
	Analytics.track("x", {})
	a.flush()
	check("отказ: не отправляем ничего", _sent.is_empty())
	a.queue_free()
	await get_tree().process_frame


func _test_bus() -> void:
	_consent("granted")
	var a := Analytics.attach(self)
	await get_tree().process_frame
	Analytics.clear_queue()
	GameState.emit_event("bought", {"id": "pick_2", "currency": "coins"})
	GameState.emit_event("dug", {"cell": Vector2i(1, 1)})
	GameState.emit_event("screen_opened", {"id": "shop", "tab": "food"})
	var names := Analytics.queue().map(func(e): return String(e["event"]))
	check("шина: bought и screen_opened уходят, dug — нет", names == ["bought", "screen_opened"], str(names))
	Analytics.clear_queue()
	a._depth_mark = 0
	GameState.max_depth_changed.emit(150)
	GameState.max_depth_changed.emit(180)
	GameState.max_depth_changed.emit(205)
	names = Analytics.queue().map(func(e): return "%s:%d" % [e["event"], int(e["properties"].get("depth", 0))])
	check("вехи глубины по 100", names == ["depth_milestone:100", "depth_milestone:200"], str(names))
	Analytics.clear_queue()
	GameState.leveled_up.emit(5, 1)
	GameState.tool_changed.emit("drill")
	names = Analytics.queue().map(func(e): return String(e["event"]))
	check("уровень и инструмент", names == ["level_up", "tool_changed"], str(names))
	a.queue_free()
	await get_tree().process_frame
	_consent("denied")


func _test_settings_and_dialog() -> void:
	_consent("granted")
	Settings.analytics_consent = "unset"
	Settings.load_from_disk()
	check("согласие хранится в settings.json", Settings.analytics_consent == "granted")
	var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "analytics_consent": "maybe"}))
	f.close()
	Settings.load_from_disk()
	check("чужое значение — ещё не спрашивали", Settings.analytics_consent == "unset")
	var d := ConsentDialog.open_on(self)
	check("окно открыто, сюжет ждёт", d.is_open() and ConsentDialog.is_open_any())
	for n in ["Allow", "Deny", "More"]:
		var b := d.find_child(n, true, false) as Button
		check("кнопка %s не меньше 25" % n, b != null and b.get_combined_minimum_size().y >= UiBtn.TOUCH_MIN)
	d.show_details(true)
	check("«Подробнее» показывает список", (d.find_child("Details", true, false) as Control).visible)
	d.show_details(false)
	(d.find_child("Allow", true, false) as Button).pressed.emit()
	check("«Разрешить» пишет granted и закрывает", Settings.analytics_consent == "granted" and not ConsentDialog.is_open_any())
	await get_tree().process_frame
	d = ConsentDialog.open_on(self)
	(d.find_child("Deny", true, false) as Button).pressed.emit()
	check("«Нет, спасибо» пишет denied", Settings.analytics_consent == "denied" and Analytics.queue().is_empty())
	await get_tree().process_frame

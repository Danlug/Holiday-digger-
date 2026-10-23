extends Node
## test_foundation — общие контракты, на которые опираются все подсистемы:
## подсказки Tip, фасады Sfx/Fx/Haptics (безопасны без сервиса), реестр меню,
## расширяемое хранилище GameState.ext и его путь через сейв.
##
## Запуск: godot --headless --path . res://tests/test_foundation.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_foundation ===")
	await get_tree().process_frame

	# --- фасады без сервиса: тихо ничего не делают ---
	Sfx.play("coin")
	Sfx.music("mus_surface")
	Sfx.stop_music()
	Fx.burst("dig_dirt", Vector2(10, 10))
	Fx.float_text(Vector2.ZERO, "+1")
	Fx.shake()
	Fx.flash()
	Fx.fly_to(null, Vector2.ZERO, Vector2(100, 100))
	Haptics.tap()
	check("фасады Sfx/Fx/Haptics без сервиса не падают", true)

	# --- фасад находит сервис по группе ---
	var svc := _FakeSvc.new()
	svc.add_to_group(Sfx.GROUP)
	svc.add_to_group(Fx.GROUP)
	add_child(svc)
	Sfx.play("coin", 1.2, -3.0)
	Fx.burst("spark", Vector2(1, 2), 2.0)
	check("Sfx.play доходит до сервиса с аргументами", svc.last_play == ["coin", 1.2, -3.0])
	check("Fx.burst доходит до сервиса с аргументами", svc.last_burst == ["spark", Vector2(1, 2), 2.0])
	svc.queue_free()

	# --- реестр меню ---
	MenuRegistry.clear()
	MenuRegistry.add("b", {"title": "B", "order": 20, "on_press": func() -> void: pass})
	MenuRegistry.add("a", {"title": "A", "order": 10, "badge": func() -> int: return 3})
	MenuRegistry.add("hidden", {"title": "H", "order": 5, "visible": func() -> bool: return false})
	var es := MenuRegistry.entries()
	check("реестр меню: порядок по order, скрытые не попадают", es.size() == 2 and es[0]["id"] == "a" and es[1]["id"] == "b")
	check("реестр меню: badge считается", MenuRegistry.badge_of(es[0]) == 3 and MenuRegistry.badge_of(es[1]) == 0)
	MenuRegistry.add("a", {"title": "A2", "order": 99})
	check("реестр меню: повторный add заменяет запись", MenuRegistry.entries()[1]["title"] == "A2")
	MenuRegistry.clear()

	# --- GameState.ext и сейв ---
	GameState.ext.clear()
	GameState.ext_set("probe", {"n": 7, "list": [1, 2, 3]})
	check("GameState.ext_get возвращает записанное", int(GameState.ext_get("probe")["n"]) == 7)
	check("GameState.ext_get даёт default для чужого ключа", GameState.ext_get("nope", 42) == 42)
	var data: Dictionary = SaveSystem._serialize()
	check("ext попадает в сериализацию сейва", data.has("ext") and data["ext"].has("probe"))
	var round_trip = JSON.parse_string(JSON.stringify(data))
	GameState.ext.clear()
	SaveSystem._apply(round_trip)
	check("ext восстанавливается из сейва", GameState.ext.has("probe") and int(GameState.ext["probe"]["n"]) == 7)
	SaveSystem._apply({})
	GameState.reset_progress()
	check("reset_progress очищает ext", GameState.ext.is_empty())

	# --- подсказка Tip ---
	var layer := CanvasLayer.new()
	add_child(layer)
	var btn := Button.new()
	btn.text = "x"
	btn.position = Vector2(100, 200)
	btn.size = Vector2(30, 30)
	layer.add_child(btn)
	await get_tree().process_frame
	Tip.bind(btn, "Железная кирка", "Копает вдвое быстрее", "1 200 монет")
	check("Tip.bind делает Control способным принимать наведение", btn.mouse_filter != Control.MOUSE_FILTER_IGNORE)
	Tip.show_now(btn)
	await get_tree().process_frame
	check("Tip.show_now показывает подсказку", Tip.is_showing())
	var panel: PanelContainer = get_tree().root.find_child("TipLayer", true, false).get_child(0)
	var vp := get_viewport().get_visible_rect()
	var r := Rect2(panel.position, panel.get_combined_minimum_size())
	check("подсказка целиком внутри вьюпорта (%s в %s)" % [r, vp], vp.encloses(r))
	Tip.hide_all()
	check("Tip.hide_all прячет подсказку", not Tip.is_showing())

	# подсказка у самого края не выезжает за вьюпорт
	btn.position = Vector2(vp.end.x - 20.0, 2.0)
	await get_tree().process_frame
	Tip.set_text(btn, "Очень длинное название предмета для проверки переноса", "И описание в несколько строк, чтобы панель стала высокой и широкой")
	Tip.show_now(btn)
	await get_tree().process_frame
	r = Rect2(panel.position, panel.get_combined_minimum_size())
	check("подсказка у края вьюпорта прижимается к нему (%s)" % str(r), vp.grow(1.0).encloses(r))
	Tip.hide_all()

	# долгое нажатие мышью: подсказка, затем swallowed() после отпускания
	btn.position = Vector2(100, 200)
	await get_tree().process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	btn.gui_input.emit(down)
	await get_tree().create_timer(Tip.LONG_PRESS + 0.15).timeout
	check("долгое нажатие показывает подсказку", Tip.is_showing())
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	btn.gui_input.emit(up)
	check("после долгого нажатия swallowed() истинно", Tip.swallowed())
	await get_tree().create_timer(0.35).timeout
	check("swallowed() гаснет через долю секунды", not Tip.swallowed())
	Tip.hide_all()

	# короткое нажатие подсказку не показывает и не глотает нажатие
	btn.gui_input.emit(down)
	await get_tree().create_timer(0.08).timeout
	btn.gui_input.emit(up)
	await get_tree().create_timer(Tip.LONG_PRESS + 0.1).timeout
	check("короткое нажатие не показывает подсказку и не глотает нажатие",
		not Tip.is_showing() and not Tip.swallowed())

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


class _FakeSvc extends Node:
	var last_play: Array = []
	var last_burst: Array = []

	func play(id: String, pitch: float, vol: float) -> void:
		last_play = [id, pitch, vol]

	func burst(kind: String, pos: Vector2, amount: float) -> void:
		last_burst = [kind, pos, amount]

	func music(_id: String, _fade: float) -> void:
		pass

	func stop_music(_fade: float) -> void:
		pass

	func float_text(_p: Vector2, _t: String, _c: Color) -> void:
		pass

	func shake(_s: float, _d: float) -> void:
		pass

	func flash(_c: Color, _d: float) -> void:
		pass

	func fly_to(_i, _a: Vector2, _b: Vector2, _n: int) -> void:
		pass

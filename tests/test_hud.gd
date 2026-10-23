extends Node
## test_hud — логика интерфейса: меню «•••» строится из MenuRegistry, якоря
## для Fx.fly_to, настройки (вибро, «меньше движения»), рюкзак-сетка, анимации
## полосок и счётчиков. Визуал проверяется скриншотами (test_screenshot_hud).
##
## Запуск: godot --headless --path . res://tests/test_hud.tscn

var failures := 0
var total := 0
var _hud: Control
var _pressed: Array[String] = []


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== test_hud ===")
	Settings.reduce_motion = true   # твины в тесте не нужны, состояние — сразу
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = preload("res://scripts/ui/hud.gd").new()
	layer.add_child(_hud)
	await _frames(3)

	await _check_menu()
	_check_anchors()
	_check_settings()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _menu_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in _hud._more_grid.get_children():
		out.append(c as Button)
	return out


func _check_menu() -> void:
	check("HUD в группе hud", _hud.is_in_group("hud"))
	var ids: Array = []
	for e: Dictionary in MenuRegistry.entries():
		ids.append(e["id"])
	for id in ["workshop", "controls", "settings", "reset"]:
		check("стандартный пункт меню зарегистрирован: " + id, ids.has(id))

	_pressed.clear()
	MenuRegistry.add("t_quest", {
		"icon": UiIcons.tex("quest"), "title": "Задания", "body": "Тест", "order": 40,
		"badge": func() -> int: return 3,
		"on_press": func() -> void: _pressed.append("quest"),
	})
	MenuRegistry.add("t_hidden", {
		"title": "Скрытый", "order": 41,
		"visible": func() -> bool: return false,
		"on_press": func() -> void: _pressed.append("hidden"),
	})
	MenuRegistry.add("t_danger", {
		"icon": UiIcons.tex("trash"), "title": "Опасно", "order": 42, "confirm": true,
		"on_press": func() -> void: _pressed.append("danger"),
	})

	_hud._toggle_more_menu()
	await _frames(2)
	check("меню открылось", _hud.is_more_menu_open())
	var expected := MenuRegistry.entries().size()
	check("плиток в меню столько же, сколько видимых пунктов реестра", _menu_buttons().size() == expected)

	var quest_btn: Button = null
	var danger_btn: Button = null
	for b in _menu_buttons():
		var meta: Dictionary = b.get_meta(Tip.META)
		if meta["title"] == "Задания":
			quest_btn = b
		elif meta["title"] == "Опасно":
			danger_btn = b
	check("пункт из чужой подсистемы попал в меню", quest_btn != null)
	check("скрытый пункт в меню не попал", not _hud._more_grid.get_children().any(
		func(b: Node) -> bool: return (b.get_meta(Tip.META) as Dictionary)["title"] == "Скрытый"))
	check("у плитки с badge есть красная цифра 3",
		quest_btn != null and quest_btn.get_node_or_null(UiBtn.BADGE_NAME) != null
		and (quest_btn.get_node(UiBtn.BADGE_NAME) as Control).visible
		and (quest_btn.get_node(UiBtn.BADGE_NAME + "/N") as Label).text == "3")
	check("у плитки есть подсказка (Tip) с названием и описанием",
		quest_btn != null and (quest_btn.get_meta(Tip.META) as Dictionary)["body"] == "Тест")

	if danger_btn != null:
		danger_btn.pressed.emit()
		check("опасный пункт: первое нажатие только взводит, меню остаётся",
			_pressed.is_empty() and _hud.is_more_menu_open())
		danger_btn.pressed.emit()
		check("опасный пункт: второе нажатие выполняет и закрывает меню",
			_pressed == ["danger"] and not _hud.is_more_menu_open())
	_pressed.clear()

	_hud._toggle_more_menu()
	await _frames(2)
	for b in _menu_buttons():
		if (b.get_meta(Tip.META) as Dictionary)["title"] == "Задания":
			b.pressed.emit()
	check("нажатие на плитку зовёт on_press и закрывает меню",
		_pressed == ["quest"] and not _hud.is_more_menu_open())

	MenuRegistry.remove("t_quest")
	MenuRegistry.remove("t_hidden")
	MenuRegistry.remove("t_danger")


func _check_anchors() -> void:
	var vp := _hud.get_viewport_rect().size
	for id in ["coins", "dollars", "backpack", "hp", "hunger", "stamina", "menu", "depth"]:
		var p := HudAnchors.get_anchor(id)
		check("якорь %s внутри экрана (%.0f, %.0f)" % [id, p.x, p.y],
			Rect2(Vector2.ZERO, vp).has_point(p))
	check("якорь «рюкзак» — в нижней полосе", HudAnchors.get_anchor("backpack").y > vp.y - _hud.STRIP_H)
	check("якорь «монеты» — в правой половине сверху",
		HudAnchors.get_anchor("coins").x > vp.x * 0.5 and HudAnchors.get_anchor("coins").y < 80.0)
	check("якорь «hp» — в левой половине сверху",
		HudAnchors.get_anchor("hp").x < vp.x * 0.5 and HudAnchors.get_anchor("hp").y < 100.0)
	check("неизвестный id — центр экрана", HudAnchors.get_anchor("nope").is_equal_approx(vp * 0.5))


func _check_settings() -> void:
	var was: bool = Settings.haptics_enabled
	Settings.set_haptics_enabled(false)
	check("Settings.haptics_enabled выключает Haptics.enabled", Haptics.enabled == false)
	Settings.set_haptics_enabled(true)
	check("Settings.haptics_enabled включает Haptics.enabled", Haptics.enabled == true)
	Settings.set_haptics_enabled(was)

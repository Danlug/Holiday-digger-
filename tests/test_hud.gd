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
	await _check_well()
	_check_count_format()
	await _check_count_anim()
	await _check_bar()
	_check_purse_and_gauges()
	await _check_backpack()
	await _check_settings_sheet()
	_check_toast()
	_check_warnings()

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


func _find_pill(n: Node) -> HudPill:
	if n is HudPill:
		return n
	for c in n.get_children():
		var r := _find_pill(c)
		if r != null:
			return r
	return null


func _check_well() -> void:
	_hud.show_well_report({"seconds": 5400.0, "items": {"iron_ore": 24, "gold": 1}})
	await _frames(2)
	var pill := _find_pill(_hud._well_panel)
	check("отчёт скважины: время на плашке «1:30» (было «%s»)" % (pill.count.text if pill != null else "-"), pill != null and pill.count.text == "1:30")
	_hud.close_well_report()
	check("отчёт скважины закрывается", _hud._well_panel == null)


func _check_count_format() -> void:
	check("число: 1250 -> «1 250»", CountLabel.short_text(1250) == "1 250")
	check("число: 0 -> «0»", CountLabel.short_text(0) == "0")
	check("число: 9 999 999 целиком", CountLabel.short_text(9999999) == "9 999 999")
	check("число: 12 345 678 -> «12,3M»", CountLabel.short_text(12345678) == "12,3M")
	check("число: 123 456 789 -> «123,5M»", CountLabel.short_text(123456789) == "123,5M")
	check("число: 2 000 000 000 -> «2B»", CountLabel.short_text(2000000000) == "2B")
	check("точная сумма для подсказки группируется пробелами", CountLabel.group_digits(1234567) == "1 234 567")


func _check_count_anim() -> void:
	Settings.reduce_motion = false
	var c := CountLabel.new()
	add_child(c)
	c.set_value(0, true)
	c.set_value(1000)
	await get_tree().create_timer(0.2).timeout
	var mid := int(c.text.replace(" ", ""))
	check("накрутка: в середине пути число между старым и новым (%d)" % mid, mid > 0 and mid < 1000)
	await get_tree().create_timer(0.7).timeout
	check("накрутка: в конце — ровно новое число", c.text == "1 000" and c.value() == 1000)
	c.set_value(5, true)
	check("накрутка: instant ставит сразу", c.text == "5")
	c.queue_free()
	Settings.reduce_motion = true


func _check_bar() -> void:
	Settings.reduce_motion = false
	var b := HudBar.new().setup(Color.RED, null)
	add_child(b)
	b.set_fraction(1.0, true)
	check("полоска: полная не в тревоге", not b.is_alarm())
	b.set_fraction(0.5)
	check("полоска: после потери заливка сразу на 0.5, хвост ещё выше",
		is_equal_approx(b._value, 0.5) and b._ghost > 0.9)
	await get_tree().create_timer(1.6).timeout
	check("полоска: хвост догнал заливку", is_equal_approx(b._ghost, b._value))
	b.set_fraction(0.2)
	check("полоска: ниже 25% — тревога (пульс)", b.is_alarm())
	b.set_fraction(0.9)
	await get_tree().create_timer(0.7).timeout
	check("полоска: рост плавный и доходит до цели", is_equal_approx(b._value, 0.9))
	b.pulse_above = 1.0
	b.set_fraction(1.0, true)
	check("полоска веса: тревога, когда ПОЛНО", b.is_alarm())
	b.set_fraction(0.5, true)
	check("полоска веса: не в тревоге на половине", not b.is_alarm())
	b.queue_free()
	Settings.reduce_motion = true


func _check_purse_and_gauges() -> void:
	var coins0: int = GameState.coins
	GameState.coins = 5000
	GameState.coins_changed.emit(5000)
	check("кошелёк: 5000 -> «5 000»", _hud._coins_pill.count.text == "5 000")
	GameState.coins = 123456789
	GameState.coins_changed.emit(123456789)
	check("кошелёк: длинное число сокращено «123,5M»", _hud._coins_pill.count.text == "123,5M")
	var tip: Dictionary = _hud._coins_pill.get_meta(Tip.META)
	check("кошелёк: точная сумма — в подсказке", String(tip["body"]) == "123 456 789")
	GameState.coins = coins0
	GameState.coins_changed.emit(coins0)

	var max_hp := GameState.get_max_hp()
	var hp0: float = GameState.hp
	GameState.hp = max_hp * 0.1
	GameState.hp_changed.emit(GameState.hp, max_hp)
	check("HP: полоска на 10%", absf(_hud._hp_bar.fraction() - 0.1) < 0.001)
	check("HP: ниже 25% — красная рамка по краям экрана", _hud._vignette.visible)
	GameState.hp = max_hp
	GameState.hp_changed.emit(max_hp, max_hp)
	check("HP: вылечился — рамка погасла", not _hud._vignette.visible)
	GameState.hp = hp0
	GameState.hp_changed.emit(hp0, max_hp)

	var inv0: Dictionary = GameState.inventory.duplicate()
	GameState.inventory = {"uranium": 100}
	GameState.inventory_changed.emit()
	check("вес: перегруз — полоска красная и полная",
		_hud._load_bar.fill_color == Color8(0xD9, 0x4F, 0x4A) and _hud._load_bar.is_alarm())
	GameState.inventory = {}
	GameState.inventory_changed.emit()
	check("вес: пустой рюкзак — зелёная полоска", _hud._load_bar.fill_color == Color8(0x7F, 0xB8, 0x6B))
	GameState.inventory = inv0
	GameState.inventory_changed.emit()


func _check_backpack() -> void:
	var inv0: Dictionary = GameState.inventory.duplicate()
	GameState.inventory = {"gold": 5, "iron_ore": 12, "diamond": 2, "copper": 40, "coal": 7,
		"silver": 1, "uranium": 1, "energy_bar": 2}
	var sheet: BackpackSheet = _hud._inv_sheet
	sheet.refresh()
	await _frames(1)
	check("рюкзак: слотов по числу стопок (8)", sheet.slot_count() == 8)
	check("рюкзак: сетка не меньше 12 клеток", sheet._grid.get_child_count() >= BackpackSheet.MIN_SLOTS)
	check("рюкзак: иконка у каждого слота", sheet._slot_buttons.values().all(func(b: Button) -> bool: return b.icon != null))
	check("рюкзак: редкость по цене (железо/золото/алмаз/уран)",
		BackpackSheet.tier_of("iron_ore") == 0 and BackpackSheet.tier_of("gold") == 2
		and BackpackSheet.tier_of("diamond") == 3 and BackpackSheet.tier_of("uranium") == 4)
	check("рюкзак: находка без цены — эпическая, еда — обычная",
		BackpackSheet.tier_of("obsidian") == 3 and BackpackSheet.tier_of("energy_bar") == 0)
	var uranium_tip: Dictionary = sheet._slot_buttons["uranium"].get_meta(Tip.META)
	check("рюкзак: в подсказке слота название и вес", String(uranium_tip["title"]) == "Уран"
		and String(uranium_tip["body"]).contains("10.0 кг"))
	check("рюкзак: первым лежит самая дорогая стопка (уран)",
		sheet._grid.get_child(0) == sheet._slot_buttons["uranium"])

	sheet._slot_buttons["gold"].pressed.emit()
	check("рюкзак: нажатие выбирает слот", sheet.selected_id() == "gold")
	sheet._slot_buttons["gold"].pressed.emit()
	check("рюкзак: повторное нажатие снимает выбор", sheet.selected_id() == "")
	sheet._slot_buttons["energy_bar"].pressed.emit()
	check("рюкзак: у выбранной еды появляется «съесть»", sheet._eat_btn.visible)
	sheet._slot_buttons["gold"].pressed.emit()
	check("рюкзак: у руды «съесть» нет", not sheet._eat_btn.visible)

	var got: Array = []
	sheet.drop_confirmed.connect(func(id: String, n: int) -> void: got.append([id, n]))
	sheet.open_drop("copper", 40)
	check("окно «сколько»: открылось, по умолчанию вся стопка", sheet.is_drop_open() and sheet.drop_amount() == 40)
	sheet._drop_field.text = "7"
	sheet._drop_field.text_changed.emit("7")
	check("окно «сколько»: число в поле двигает ползунок", sheet.drop_amount() == 7)
	sheet._drop_field.text = "9x9"
	sheet._drop_field.text_changed.emit("9x9")
	check("окно «сколько»: буквы вычищаются из поля", sheet._drop_field.text == "99" or sheet._drop_field.text == "40")
	sheet._drop_slider.value = 3
	sheet.apply_drop()
	check("окно «сколько»: «выбросить» шлёт id и количество и закрывается",
		got == [["copper", 3]] and not sheet.is_drop_open())

	check("HUD снимает выброшенное из рюкзака", int(GameState.inventory.get("copper", 0)) == 37)
	check("HUD: старые имена _open_drop/_close_drop живы", _hud.has_method("_open_drop") and _hud.has_method("_close_drop"))
	GameState.inventory = inv0
	GameState.inventory_changed.emit()


func _check_settings_sheet() -> void:
	var sheet := SettingsSheet.new()
	add_child(sheet)
	sheet.open()
	await _frames(1)
	check("настройки: шторка открылась", sheet.is_open())
	var modes: Array = []
	sheet.mode_chosen.connect(func(m: String) -> void: modes.append(m))
	sheet._mode_btns["hold"].pressed.emit()
	check("настройки: кнопка режима шлёт mode_chosen", modes == ["hold"])
	var h0: bool = Settings.haptics_enabled
	sheet._haptics_btn.pressed.emit()
	check("настройки: кнопка вибро переключает Settings.haptics_enabled и Haptics.enabled",
		Settings.haptics_enabled == (not h0) and Haptics.enabled == (not h0))
	Settings.set_haptics_enabled(h0)
	var m0: bool = Settings.sound_muted
	sheet._sound_btn.pressed.emit()
	check("настройки: кнопка динамика переключает мьют", Settings.sound_muted == (not m0))
	Settings.set_sound_muted(m0)
	var rm0: bool = Settings.reduce_motion
	sheet._motion_btn.pressed.emit()
	check("настройки: «меньше движения» переключается", Settings.reduce_motion == (not rm0))
	Settings.set_reduce_motion(rm0)
	var v0: float = Settings.sound_volume
	sheet._sound_slider.value = 40.0
	check("настройки: ползунок звука пишет громкость", absf(Settings.sound_volume - 0.4) < 0.001)
	Settings.set_sound_volume(v0)
	check("настройки: недоступные языки серые", (sheet._lang_btns["en"] as Button).disabled
		and not (sheet._lang_btns["ru"] as Button).disabled)
	sheet.close()
	check("настройки: шторка закрылась", not sheet.is_open())
	sheet.queue_free()


func _check_toast() -> void:
	_hud.toast_icon("hp", "−5")
	var kinds: Array = _hud._toast_row.get_children().map(func(c: Node) -> String: return c.get_class())
	check("тост с иконкой: иконка и число", _hud._toast_panel.visible and kinds == ["TextureRect", "Label"])
	var short_h: float = _hud._toast_panel.get_combined_minimum_size().y
	_hud.toast("Очень длинный текст тоста, который обязан перенестись на несколько строк, потому что не помещается в одну строку на узком экране телефона.")
	var long_h: float = _hud._toast_panel.get_combined_minimum_size().y
	check("длинный тост переносится, панель выше (%.0f > %.0f)" % [long_h, short_h], long_h > short_h + 10.0)
	check("тост не шире TOAST_MAX_W", _hud._toast_panel.get_combined_minimum_size().x <= _hud.TOAST_MAX_W + 1.0)
	check("низ тоста стоит на месте", is_equal_approx(_hud._toast_panel.offset_bottom, _hud.TOAST_BOTTOM_OFFSET))


func _check_warnings() -> void:
	_hud._toast_panel.visible = false
	GameState.survival_warning.emit("hunger", true)
	check("предупреждение 10%: тост с иконкой голода и «!!»", _hud._toast_panel.visible
		and _hud._toast_row.get_child_count() == 2)
	Settings.reduce_motion = false
	GameState.survival_warning.emit("stamina", true)
	check("серьёзное предупреждение мигает красным ~2 с", _hud._stamina_bar._alert > 1.5)
	Settings.reduce_motion = true
	_hud._stamina_bar._alert = 0.0
	GameState.exhausted_changed.emit(true)
	check("пустая бодрость: тост «−50%»", _hud._toast_panel.visible)

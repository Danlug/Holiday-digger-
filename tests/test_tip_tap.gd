extends Node
## test_tip_tap — режим «показ по тапу» у Tip (Tip.bind_tap): тап открывает и
## закрывает описание, не трогает swallowed(), не ломает наведение и долгое
## нажатие. События шлём прямо в gui_input контролов (в headless окно 64×64 и
## настоящий указатель до интерфейса не доходит).
##
##   godot --headless --path . res://tests/test_tip_tap.tscn

var failures := 0
var total := 0
var a: Button
var b: Button


func _ready() -> void:
	print("=== test_tip_tap ===")
	Settings.reduce_motion = true
	var host := Control.new()
	add_child(host)
	a = _make_btn(host, Vector2(20, 100))
	b = _make_btn(host, Vector2(120, 100))
	await _frames(2)

	Tip.bind_tap(a, "Железо", "Есть: 3 из 10", "Не хватает: 7")
	Tip.bind_tap(b, "Медь", "Есть: 9 из 10")
	_reset()
	_test_tap_opens_and_closes()
	_test_tap_does_not_touch_swallow()
	_test_hover_tip_is_pinned_by_tap()
	_test_drag_is_not_tap()
	_test_second_control_replaces()
	_test_outside_press_hides()
	_test_mouse_exit_keeps_pinned()
	_test_twin_events_count_once()
	_test_hover_and_long_press_still_work()
	_test_empty_title_and_gone()
	_test_double_bind_updates_text()

	Tip.hide_all()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _make_btn(host: Control, pos: Vector2) -> Button:
	var c := Button.new()
	c.position = pos
	c.size = Vector2(40, 40)
	host.add_child(c)
	return c


func _reset() -> void:
	Tip.hide_all()
	Tip._swallow_until_ms = 0
	Tip._dismissed_until_ms = 0


func _mouse(c: Control, pressed: bool, at: Vector2 = Vector2(5, 5), emulated: bool = false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	e.global_position = at
	if emulated:
		e.device = InputEvent.DEVICE_ID_EMULATION
	c.gui_input.emit(e)


func _touch(c: Control, pressed: bool, at: Vector2 = Vector2(5, 5)) -> void:
	var e := InputEventScreenTouch.new()
	e.pressed = pressed
	e.position = at
	c.gui_input.emit(e)


func _tap(c: Control, at: Vector2 = Vector2(5, 5)) -> void:
	_mouse(c, true, at)
	_mouse(c, false, at)


func _outside_press() -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = Vector2(200, 400)
	Tip._on_global_input(e)


func _test_tap_opens_and_closes() -> void:
	_reset()
	_tap(a)
	check("тап открывает описание", Tip.is_showing() and Tip.is_pinned())
	check("панель показывает название и «есть из»",
		Tip._title.text == "Железо" and Tip._body.text == "Есть: 3 из 10" and Tip._extra.text == "Не хватает: 7")
	_tap(a)
	check("повторный тап закрывает", not Tip.is_showing() and not Tip.is_pinned())
	_tap(a)
	_tap(a)
	check("и снова: открыть, закрыть — цикл повторяется", not Tip.is_showing())


func _test_tap_does_not_touch_swallow() -> void:
	_reset()
	_tap(a)
	check("тап не включает swallowed() — кнопка под пальцем сработает", not Tip.swallowed())
	_tap(a)
	check("закрывающий тап — тоже", not Tip.swallowed())


func _test_hover_tip_is_pinned_by_tap() -> void:
	_reset()
	Tip.show_now(a)
	check("подсказка от наведения не закреплена", Tip.is_showing() and not Tip.is_pinned())
	_tap(a)
	check("тап по ней закрепляет, а не гасит", Tip.is_showing() and Tip.is_pinned())
	_tap(a)
	check("следующий тап закрывает", not Tip.is_showing())


func _test_drag_is_not_tap() -> void:
	_reset()
	_mouse(a, true, Vector2(5, 5))
	_mouse(a, false, Vector2(5, 35))
	check("перетаскивание (прокрутка) описание не открывает", not Tip.is_showing())
	_mouse(a, false)
	check("отпускание без нажатия — не тап", not Tip.is_showing())


func _test_second_control_replaces() -> void:
	_reset()
	_tap(a)
	_tap(b)
	check("тап по другому значку переносит описание на него",
		Tip.is_pinned() and Tip._owner_ctrl == b and Tip._title.text == "Медь")


func _test_outside_press_hides() -> void:
	_reset()
	_tap(a)
	var inside := InputEventMouseButton.new()
	inside.button_index = MOUSE_BUTTON_LEFT
	inside.pressed = true
	inside.position = a.get_global_rect().get_center()
	Tip._on_global_input(inside)
	check("нажатие на самом значке описание не гасит (это решит тап)", Tip.is_showing())
	_outside_press()
	check("нажатие мимо закрывает описание", not Tip.is_showing())
	check("и помечает «закрыто тапом», чтобы окно под ним не закрылось следом", Tip.dismissed_by_tap())
	check("но swallowed() остаётся ложным", not Tip.swallowed())
	_reset()
	_outside_press()
	check("без открытого описания нажатие мимо ничего не помечает", not Tip.dismissed_by_tap())


func _test_mouse_exit_keeps_pinned() -> void:
	_reset()
	_tap(a)
	a.mouse_exited.emit()
	check("мышь ушла со значка — открытое тапом описание остаётся", Tip.is_pinned())
	a.mouse_entered.emit()
	check("и возвращение мыши его не перезапускает", Tip.is_pinned())
	Tip.hide_all()
	Tip.show_now(a)
	a.mouse_exited.emit()
	check("а подсказка от наведения по-прежнему гаснет при уходе мыши", not Tip.is_showing())


func _test_twin_events_count_once() -> void:
	_reset()
	# Телефон: само касание и эмулированная мышь приходят подряд.
	_touch(a, true)
	_mouse(a, true, Vector2(5, 5), true)
	_touch(a, false)
	_mouse(a, false, Vector2(5, 5), true)
	check("касание и его мышиный близнец — один тап, не открыть-закрыть", Tip.is_pinned())


func _test_hover_and_long_press_still_work() -> void:
	_reset()
	check("у привязанного по тапу значка есть и обычная подсказка (hover)",
		a.has_meta(Tip.META) and String((a.get_meta(Tip.META) as Dictionary)["title"]) == "Железо")
	# Долгое нажатие: показ случился по таймеру (здесь — вручную), затем отпускание.
	_mouse(a, true)
	Tip._shown_by_press = true
	Tip.show_now(a)
	_mouse(a, false)
	check("долгое нажатие по-прежнему включает swallowed()", Tip.swallowed())
	check("и не превращается в тап (описание не закреплено и не переключено)",
		Tip.is_showing() and not Tip.is_pinned())
	Tip.hide_all()
	_reset()


func _test_empty_title_and_gone() -> void:
	_reset()
	var c := _make_btn(a.get_parent(), Vector2(70, 200))
	Tip.bind_tap(c, "")
	_tap(c)
	check("без названия тап ничего не показывает", not Tip.is_showing())
	Tip.set_text(c, "Появилось")
	_tap(c)
	check("после появления текста работает", Tip.is_pinned())
	c.hide()
	check("скрытый значок уносит описание", not Tip.is_showing())
	c.queue_free()


func _test_double_bind_updates_text() -> void:
	_reset()
	Tip.bind_tap(a, "Железо", "Есть: 10 из 10", "Хватает")
	_tap(a)
	check("повторный bind_tap обновляет текст, а не дублирует обработчик",
		Tip._body.text == "Есть: 10 из 10" and Tip.is_pinned())
	_tap(a)
	check("и один тап по-прежнему переключает один раз", not Tip.is_showing())

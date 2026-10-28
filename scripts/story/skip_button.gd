class_name SkipButton
extends Control
## Кнопка «пропустить сцену»: иконка из двух стрелок вместо слова. Случайно
## пропустить сюжетную сцену нельзя: одиночное касание лишь подсказывает, как
## подтвердить, а пропуск срабатывает по долгому нажатию (кольцо заполняется)
## или по двойному касанию.

signal confirmed

const SIZE_PX := Vector2(34, 26)   # цель нажатия ≥ 25 (44 pt)
const HOLD_SEC := 0.6
const DOUBLE_MS := 600
const HINT_SEC := 2.2

## Куда класть подсказку: слева от кнопки (полоса кинокадра) или под ней (плашка автокопки).
var hint_below: bool = false

var _down: bool = false
var _hover: bool = false
var _hold: float = 0.0
var _last_tap_ms: int = -100000
var _hint_left: float = 0.0
var _flash: float = 0.0
var _bg: StyleBoxFlat
var _hint: PanelContainer
var _hint_label: Label


func _init() -> void:
	custom_minimum_size = SIZE_PX
	size = SIZE_PX
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = StyleBoxFlat.new()
	_bg.bg_color = Color(0, 0, 0, 0.62)
	_bg.border_color = DialogueStyle.MUTED
	_bg.set_border_width_all(1)
	_bg.set_corner_radius_all(11)
	_bg.anti_aliasing = true

	_hint = PanelContainer.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0.07, 0.055, 0.043, 0.94)
	hb.border_color = DialogueStyle.GOLD_DIM
	hb.set_border_width_all(1)
	hb.set_corner_radius_all(8)
	hb.content_margin_left = 7
	hb.content_margin_right = 7
	hb.content_margin_top = 2
	hb.content_margin_bottom = 3
	hb.anti_aliasing = true
	_hint.add_theme_stylebox_override("panel", hb)
	_hint_label = Label.new()
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	DialogueStyle.shadowed(_hint_label, 9, DialogueStyle.TEXT)
	_hint.add_child(_hint_label)
	add_child(_hint)

	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	refresh_texts()
	Tip.bind(self, StoryText.get_text("ui.skip"), StoryText.get_text("ui.skip_hint"))


## Тексты берутся из StoryText: язык мог смениться после создания кнопки.
func refresh_texts() -> void:
	_hint_label.text = StoryText.get_text("ui.skip_hint")
	_hint.reset_size()
	Tip.set_text(self, StoryText.get_text("ui.skip"), StoryText.get_text("ui.skip_hint"))
	_place_hint()


func reset_state() -> void:
	_down = false
	_hold = 0.0
	_hint_left = 0.0
	_hint.visible = false
	queue_redraw()


func is_holding() -> bool:
	return _down


func hold_progress() -> float:
	return clampf(_hold / HOLD_SEC, 0.0, 1.0)


func hint_visible() -> bool:
	return _hint.visible


func _place_hint() -> void:
	if hint_below:
		_hint.position = Vector2(SIZE_PX.x - _hint.size.x, SIZE_PX.y + 5.0)
	else:
		_hint.position = Vector2(-_hint.size.x - 5.0, (SIZE_PX.y - _hint.size.y) * 0.5)


func _gui_input(event: InputEvent) -> void:
	var is_press := false
	var is_release := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		is_press = mb.pressed
		is_release = not mb.pressed
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		is_press = st.pressed
		is_release = not st.pressed
	else:
		return
	accept_event()
	if is_press:
		press()
	elif is_release:
		release()


## Нажатие начато (палец/мышь вниз).
func press() -> void:
	if _down:
		return
	_down = true
	_hold = 0.0
	Haptics.tap()
	queue_redraw()


## Отпускание: если держали достаточно, пропуск уже случился; иначе это касание.
func release() -> void:
	if not _down:
		return
	_down = false
	var held := _hold
	_hold = 0.0
	queue_redraw()
	if held >= HOLD_SEC:
		return
	var now := Time.get_ticks_msec()
	if now - _last_tap_ms <= DOUBLE_MS:
		_last_tap_ms = -100000
		_confirm()
		return
	_last_tap_ms = now
	_show_hint()


func _show_hint() -> void:
	Sfx.play("ui_tap", 0.9)
	_hint_left = HINT_SEC
	_hint.visible = true
	# Размер плашки считается уже в дереве: до этого шрифт ещё без темы и меряет крупнее.
	_hint_label.text = StoryText.get_text("ui.skip_hint")
	_hint.reset_size()
	_place_hint()
	if not DialogueStyle.reduced() and is_inside_tree():
		_hint.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_hint, "modulate:a", 1.0, 0.12)
	else:
		_hint.modulate.a = 1.0


func _confirm() -> void:
	_hint.visible = false
	_hint_left = 0.0
	_flash = 1.0
	Sfx.play("ui_close")
	confirmed.emit()
	queue_redraw()


func _process(dt: float) -> void:
	if _down:
		_hold += dt
		queue_redraw()
		if _hold >= HOLD_SEC:
			_down = false
			_hold = 0.0
			_confirm()
	if _hint_left > 0.0:
		_hint_left -= dt
		if _hint_left <= 0.0:
			_hint.visible = false
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 4.0)
		queue_redraw()


func _draw() -> void:
	var lit := _down or _hover or _hint.visible
	_bg.border_color = DialogueStyle.GOLD if lit else DialogueStyle.MUTED
	draw_style_box(_bg, Rect2(Vector2.ZERO, SIZE_PX))
	var col := DialogueStyle.GOLD if lit else Color8(0xC8, 0xB8, 0x9A)
	var cx := SIZE_PX.x * 0.5
	var cy := SIZE_PX.y * 0.5
	var nudge := 1.0 if _down else 0.0
	# Две стрелки и «стоп»-черта — значок «в конец».
	for i in 2:
		var x := cx - 7.0 + 6.0 * float(i) + nudge
		draw_colored_polygon(PackedVector2Array([Vector2(x, cy - 5), Vector2(x + 6, cy), Vector2(x, cy + 5)]), col)
	draw_rect(Rect2(cx + 6.0 + nudge, cy - 5.0, 2.0, 10.0), col)
	if _down and _hold > 0.0:
		var r := SIZE_PX.y * 0.5 + 3.0
		var frac := hold_progress()
		draw_arc(Vector2(cx, cy), r, -PI * 0.5, -PI * 0.5 + TAU * frac, 28, DialogueStyle.GOLD, 2.0, true)
	if _flash > 0.0:
		draw_circle(Vector2(cx, cy), 16.0 * (1.6 - _flash), Color(DialogueStyle.GOLD, _flash * 0.5))

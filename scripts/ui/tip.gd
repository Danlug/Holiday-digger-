class_name Tip
extends RefCounted
## Tip — подсказка к любому Control: при наведении мыши (ПК) или долгом
## нажатии пальцем (телефон). Решение владельца: в интерфейсе текст только
## по наведению на объект, на самих плитках — иконки и числа.
##
##   Tip.bind(button, "Железная кирка", "Копает в 2 раза быстрее", "1 200 монет")
##   Tip.set_text(button, "Новый заголовок")      # поменять текст уже
##                                                # привязанной подсказки
##   Tip.unbind(button)
##
## Правило для обработчиков нажатия: долгое нажатие показывает подсказку, а
## отпускание пальца всё равно приходит кнопке как «нажата». Поэтому действие,
## которое нельзя совершить случайно (покупка, продажа, выброс), начинается
## с проверки
##
##   if Tip.swallowed(): return
##
## — она истинна ~0.25 с после отпускания, завершившего долгое нажатие.
##
## Подсказка рисуется на своём CanvasLayer поверх всего, не перехватывает ввод,
## прижимается к краям вьюпорта и сама гаснет через несколько секунд.

const HOVER_DELAY := 0.22
const LONG_PRESS := 0.38
const AUTO_HIDE := 3.2
const AFTER_RELEASE := 1.8
const MOVE_CANCEL_PX := 12.0
const MAX_WIDTH := 160.0
const META := &"_tip_data"

const COL_BG := Color8(0x17, 0x13, 0x0F, 0xF2)
const COL_BORDER := Color8(0xE0, 0xA9, 0x3B)
const COL_TITLE := Color8(0xF2, 0xD9, 0x9B)
const COL_BODY := Color8(0xD8, 0xCF, 0xC0)
const COL_EXTRA := Color8(0x9D, 0x8B, 0x73)

static var _layer: CanvasLayer = null
static var _panel: PanelContainer = null
static var _title: Label = null
static var _body: Label = null
static var _extra: Label = null
static var _owner_ctrl: Control = null
static var _token: int = 0
static var _swallow_until_ms: int = 0
static var _press_active: bool = false
static var _press_moved: float = 0.0
static var _shown_by_press: bool = false


## Привязывает подсказку. Повторный вызов на том же Control только обновляет
## текст. title пустой — подсказки нет вовсе (удобно для «закрытых» плиток).
static func bind(ctrl: Control, title: String, body: String = "", extra: String = "") -> void:
	if ctrl == null:
		return
	var first := not ctrl.has_meta(META)
	ctrl.set_meta(META, {"title": title, "body": body, "extra": extra})
	if not first:
		if _owner_ctrl == ctrl and _panel != null and _panel.visible:
			_fill(ctrl)
		return
	if ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
	ctrl.mouse_entered.connect(func() -> void: _on_enter(ctrl))
	ctrl.mouse_exited.connect(func() -> void: _on_exit(ctrl))
	ctrl.gui_input.connect(func(ev: InputEvent) -> void: _on_input(ctrl, ev))
	ctrl.tree_exiting.connect(func() -> void: _on_exit(ctrl))
	ctrl.visibility_changed.connect(func() -> void:
		if not ctrl.is_visible_in_tree():
			_on_exit(ctrl))


static func set_text(ctrl: Control, title: String, body: String = "", extra: String = "") -> void:
	bind(ctrl, title, body, extra)


static func unbind(ctrl: Control) -> void:
	if ctrl != null and ctrl.has_meta(META):
		ctrl.set_meta(META, {"title": "", "body": "", "extra": ""})
		_on_exit(ctrl)


static func swallowed() -> bool:
	return Time.get_ticks_msec() < _swallow_until_ms


static func hide_all() -> void:
	_token += 1
	_shown_by_press = false
	_press_active = false
	_owner_ctrl = null
	if _panel != null and is_instance_valid(_panel):
		_panel.visible = false


static func is_showing() -> bool:
	return _panel != null and is_instance_valid(_panel) and _panel.visible


## Показывает подсказку немедленно (для тестов и для «покажи, что это» из кода).
static func show_now(ctrl: Control) -> void:
	_show(ctrl)


static func _on_enter(ctrl: Control) -> void:
	if not _has_text(ctrl) or _press_active:
		return
	var token := _bump()
	var tree := ctrl.get_tree()
	if tree == null:
		return
	await tree.create_timer(HOVER_DELAY).timeout
	if token == _token and is_instance_valid(ctrl) and ctrl.is_visible_in_tree():
		_show(ctrl)
		_schedule_hide(token, AUTO_HIDE)


static func _on_exit(ctrl: Control) -> void:
	if _owner_ctrl == ctrl or _owner_ctrl == null:
		if _press_active and _shown_by_press:
			return
		hide_all()
	else:
		_bump()


static func _on_input(ctrl: Control, ev: InputEvent) -> void:
	if not _has_text(ctrl):
		return
	var pressed := false
	var released := false
	if ev is InputEventScreenTouch:
		pressed = ev.pressed
		released = not ev.pressed
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		pressed = ev.pressed
		released = not ev.pressed
	if pressed:
		_press_active = true
		_press_moved = 0.0
		_shown_by_press = false
		var token := _bump()
		var tree := ctrl.get_tree()
		if tree == null:
			return
		await tree.create_timer(LONG_PRESS).timeout
		if token == _token and _press_active and _press_moved < MOVE_CANCEL_PX \
				and is_instance_valid(ctrl) and ctrl.is_visible_in_tree():
			_shown_by_press = true
			_show(ctrl)
		return
	if released:
		var was_long := _shown_by_press
		_press_active = false
		if was_long:
			_swallow_until_ms = Time.get_ticks_msec() + 250
			var token2 := _bump()
			_schedule_hide(token2, AFTER_RELEASE)
		else:
			_bump()
		_shown_by_press = false
		return
	if _press_active:
		if ev is InputEventMouseMotion:
			_press_moved += (ev as InputEventMouseMotion).relative.length()
		elif ev is InputEventScreenDrag:
			_press_moved += (ev as InputEventScreenDrag).relative.length()


static func _has_text(ctrl: Control) -> bool:
	if ctrl == null or not is_instance_valid(ctrl) or not ctrl.has_meta(META):
		return false
	return String((ctrl.get_meta(META) as Dictionary).get("title", "")) != ""


static func _bump() -> int:
	_token += 1
	return _token


static func _schedule_hide(token: int, seconds: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	await tree.create_timer(seconds).timeout
	if token == _token and not _press_active:
		hide_all()


static func _ensure_panel(tree: SceneTree) -> void:
	if _panel != null and is_instance_valid(_panel):
		return
	_layer = CanvasLayer.new()
	_layer.layer = 128
	_layer.name = "TipLayer"
	tree.root.add_child(_layer)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(ProgressUiKit.R_TILE)
	sb.shadow_color = ProgressUiKit.SHADOW
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	_panel.add_child(box)
	_title = _make_label(11, COL_TITLE)
	_body = _make_label(10, COL_BODY)
	_extra = _make_label(10, COL_EXTRA)
	box.add_child(_title)
	box.add_child(_body)
	box.add_child(_extra)
	_layer.add_child(_panel)


static func _make_label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 0.0
	return l


static func _fill(ctrl: Control) -> void:
	var d: Dictionary = ctrl.get_meta(META)
	_title.text = String(d.get("title", ""))
	_body.text = String(d.get("body", ""))
	_body.visible = _body.text != ""
	_extra.text = String(d.get("extra", ""))
	_extra.visible = _extra.text != ""
	for l: Label in [_title, _body, _extra]:
		l.custom_minimum_size.x = 0.0
		l.size.x = 0.0
	var widest := 0.0
	for l: Label in [_title, _body, _extra]:
		if l.visible:
			widest = maxf(widest, l.get_theme_font("font").get_string_size(
				l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x)
	var w := clampf(widest + 1.0, 28.0, MAX_WIDTH)
	# Размер ярлыка задаём целиком, вместе с высотой: при повторном показе поверх
	# уже показанной подсказки высота оставалась от ширины 0 (автоперенос по
	# букве), и панель раздувалась на весь экран.
	for l: Label in [_title, _body, _extra]:
		l.custom_minimum_size.x = w
		l.size = Vector2(w, 0.0)
		l.get_line_count()   # заставляет ярлык переразбить текст по новой ширине сразу
	_panel.reset_size()


static func _show(ctrl: Control) -> void:
	if not _has_text(ctrl):
		return
	var tree := ctrl.get_tree()
	if tree == null:
		return
	_ensure_panel(tree)
	_owner_ctrl = ctrl
	_fill(ctrl)
	var was_visible := _panel.visible
	_panel.visible = true
	_panel.reset_size()
	var vp := ctrl.get_viewport().get_visible_rect()
	var r := ctrl.get_global_rect()
	var sz := _panel.get_combined_minimum_size()
	var pos := Vector2(r.position.x + r.size.x * 0.5 - sz.x * 0.5, r.position.y - sz.y - 4.0)
	if pos.y < vp.position.y + 2.0:
		pos.y = r.end.y + 4.0
	pos.x = clampf(pos.x, vp.position.x + 2.0, maxf(vp.position.x + 2.0, vp.end.x - sz.x - 2.0))
	pos.y = clampf(pos.y, vp.position.y + 2.0, maxf(vp.position.y + 2.0, vp.end.y - sz.y - 2.0))
	_panel.position = pos
	# Лёгкое проявление: подсказка не «выскакивает», но и не мешает (0.1 с).
	if not was_visible and not UiAnim.instant(_panel):
		_panel.modulate.a = 0.0
		_panel.create_tween().tween_property(_panel, "modulate:a", 1.0, 0.1)
	else:
		_panel.modulate.a = 1.0

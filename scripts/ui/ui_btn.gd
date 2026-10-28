class_name UiBtn
extends RefCounted
## UiBtn — единый стиль кнопок-иконок интерфейса: приподнятая плитка с тенью,
## которая «проседает» под пальцем, золотая подсветка при наведении/включении,
## отклик звуком (ui_tap) и вибро (Haptics.tap) на каждое нажатие.
##
##   var b := UiBtn.icon_button(UiIcons.tex("gear"), Vector2(28, 28))
##   Tip.bind(b, "Настройки")
##   UiBtn.set_badge(b, 3)            # красная цифра в углу (0 — скрыть)
##
## Старые кнопки с текстом тоже можно «одеть»: UiBtn.style(button, kind).
## Тот же отклик через ProgressUiKit.make_button получают экраны прокачки/музея.

enum Kind { NORMAL, ACCENT, DANGER, GHOST }

const BG := Color8(0x26, 0x1E, 0x16)
const BG_HOVER := Color8(0x34, 0x28, 0x1B)
const BG_PRESS := Color8(0x1B, 0x15, 0x10)
const BORDER := Color8(0x52, 0x40, 0x2D)
const GOLD := Color8(0xE0, 0xA9, 0x3B)
const GOLD_DIM := Color8(0x9C, 0x76, 0x2C)
const RED := Color8(0xB8, 0x5A, 0x52)
const MUTED := Color8(0x9D, 0x8B, 0x73)
const SHADOW := Color(0, 0, 0, 0.6)
const FEEDBACK_META := &"_ui_feedback"
const BADGE_NAME := "Badge"
## Крестик «закрыть»: один размер и отступ на всех экранах и окнах.
const CLOSE_SIZE := 28.0   # ≥ 25 единиц ≈ 44 pt на iPhone
const CLOSE_INSET := 4.0   # от правого и верхнего края окна
const CLOSE_ROW := CLOSE_SIZE + CLOSE_INSET * 2.0   # высота полосы под крестиком сверху


static func _box(kind: int, state: String) -> StyleBox:
	if kind == Kind.GHOST and state in ["normal", "focus", "disabled"]:
		var e := StyleBoxEmpty.new()
		e.set_content_margin_all(3)
		return e
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(3)
	sb.anti_aliasing = true
	var border := BORDER
	var bg := BG
	match kind:
		Kind.ACCENT:
			border = GOLD_DIM
			bg = BG_HOVER
		Kind.DANGER:
			border = RED
	match state:
		"hover":
			bg = BG_HOVER
			border = GOLD if kind != Kind.DANGER else RED.lightened(0.2)
		"pressed":
			bg = BG_PRESS
			border = GOLD if kind != Kind.DANGER else RED.lightened(0.2)
		"disabled":
			bg = Color(BG.r, BG.g, BG.b, 0.5)
			border = Color(BORDER.r, BORDER.g, BORDER.b, 0.5)
		"focus":
			bg = BG
	sb.bg_color = bg
	sb.border_color = border
	# Приподнятая плитка: тень снизу; нажатая — «вдавлена» (тени нет, иконка ниже).
	if state == "pressed":
		sb.content_margin_top = 4
		sb.content_margin_bottom = 2
	else:
		sb.shadow_color = SHADOW
		sb.shadow_size = 1
		sb.shadow_offset = Vector2(0, 2)
		sb.content_margin_top = 2
		sb.content_margin_bottom = 4
	return sb


## Одевает существующую кнопку в общий стиль и подключает отклик нажатия.
static func style(b: Button, kind: int = Kind.NORMAL, with_feedback: bool = true) -> Button:
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, _box(kind, "pressed" if state == "hover_pressed" else state))
	b.add_theme_color_override("font_color", MUTED)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_hover_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color8(0x5A, 0x50, 0x44))
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.35))
	b.focus_mode = Control.FOCUS_NONE
	if with_feedback:
		wire_feedback(b)
	return b


static func set_kind(b: Button, kind: int) -> void:
	style(b, kind)


## Кнопка с одной иконкой. icon_px — размер картинки в проектных единицах
## (16 = один пиксель рисунка на единицу; 32 — вдвое крупнее).
static func icon_button(icon: Texture2D, size: Vector2 = Vector2(28, 28), kind: int = Kind.NORMAL, icon_px: int = 16) -> Button:
	var b := Button.new()
	b.icon = icon
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", icon_px)
	b.custom_minimum_size = size
	style(b, kind)
	return b


## Крестик «закрыть» — единственное место, где он создаётся. С parent (обычный
## Control, не контейнер) встаёт в его правый верхний угол; без parent — для ряда
## заголовка окна, вызывающий сам ставит его последним (справа).
static func close_button(on_close: Callable, parent: Control = null, tip: String = "Закрыть") -> Button:
	var b := icon_button(UiIcons.tex("close"), Vector2(CLOSE_SIZE, CLOSE_SIZE), Kind.GHOST)
	b.name = "Close"
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	Tip.bind(b, tip)
	b.pressed.connect(func() -> void:
		if not Tip.swallowed():
			on_close.call())
	if parent != null:
		b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		b.offset_left = -CLOSE_INSET - CLOSE_SIZE
		b.offset_right = -CLOSE_INSET
		var st := HudSafeArea.top((Engine.get_main_loop() as SceneTree).root)   # под вырезом/статус-баром
		b.offset_top = CLOSE_INSET + st
		b.offset_bottom = CLOSE_INSET + CLOSE_SIZE + st
		parent.add_child(b)
	return b


## Звук + вибро + «проседание» под пальцем. Безопасно звать повторно.
static func wire_feedback(b: Button, sfx: String = "ui_tap") -> void:
	if b.has_meta(FEEDBACK_META):
		return
	wire_sink(b)
	b.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		Haptics.tap()
		Sfx.play(sfx))


## Только «проседание» под пальцем, без звука и вибро (у кнопки свой отклик).
static func wire_sink(b: Button) -> void:
	if b.has_meta(FEEDBACK_META):
		return
	b.set_meta(FEEDBACK_META, true)
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.pivot_offset = b.size * 0.5
	b.button_down.connect(func() -> void: _sink(b, true))
	b.button_up.connect(func() -> void: _sink(b, false))
	b.mouse_exited.connect(func() -> void: _sink(b, false))


static func _sink(b: Button, down: bool) -> void:
	if is_instance_valid(b):
		UiAnim.press(b, down)


## Красная цифра в правом верхнем углу кнопки. n <= 0 — прячет значок,
## n > 99 рисуется как «99+». Рост числа подпрыгивает.
static func set_badge(b: Control, n: int) -> void:
	var badge := b.get_node_or_null(BADGE_NAME) as PanelContainer
	if n <= 0:
		if badge != null:
			badge.visible = false
		return
	var label: Label
	if badge == null:
		badge = PanelContainer.new()
		badge.name = BADGE_NAME
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color8(0xD0, 0x45, 0x3C)
		sb.border_color = Color8(0x1A, 0x10, 0x0C)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 3
		sb.content_margin_right = 3
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		badge.add_theme_stylebox_override("panel", sb)
		badge.custom_minimum_size = Vector2(12, 12)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.offset_right = 5.0
		badge.offset_top = -5.0
		label = Label.new()
		label.name = "N"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_child(label)
		b.add_child(badge)
	else:
		label = badge.get_node("N") as Label
	var text := "99+" if n > 99 else str(n)
	var grew := badge.visible and label.text != text and label.text.is_valid_int() and n > int(label.text)
	label.text = text
	badge.visible = true
	badge.reset_size()
	if grew or not badge.has_meta(&"_shown"):
		badge.set_meta(&"_shown", true)
		UiAnim.pulse(badge, 0.35, 0.26)


## Ползунок в общем стиле: тёмная канавка, заливка цветом, золотая круглая ручка.
static func style_slider(s: HSlider, fill: Color = GOLD_DIM) -> void:
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(0.06, 0.05, 0.04)
	groove.border_color = BORDER
	groove.set_border_width_all(1)
	groove.set_corner_radius_all(3)
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", groove)
	var filled := StyleBoxFlat.new()
	filled.bg_color = fill
	filled.set_corner_radius_all(3)
	filled.content_margin_top = 3
	filled.content_margin_bottom = 3
	s.add_theme_stylebox_override("grabber_area", filled)
	s.add_theme_stylebox_override("grabber_area_highlight", filled)
	var knob := knob_texture(GOLD)
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob_texture(GOLD.lightened(0.3)))
	s.add_theme_icon_override("grabber_disabled", knob)
	s.custom_minimum_size.y = maxf(s.custom_minimum_size.y, 22.0)


## Ручка ползунка — золотой кружок с тёмной обводкой, рисуется из кода (16×16).
static func knob_texture(col: Color) -> Texture2D:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length()
			if d <= 7.5:
				var shade := col
				if d >= 6.2:
					shade = Color8(0x1A, 0x13, 0x0D)
				elif (x + y) < n - 3 and d < 4.5:
					shade = col.lightened(0.35)
				img.set_pixel(x, y, shade)
	return ImageTexture.create_from_image(img)


## Вызывает action при нажатии левой кнопкой/пальцем по control (затемнение за
## шторкой: тап мимо карточки закрывает её).
static func on_tap(c: Control, action: Callable) -> void:
	c.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			action.call())

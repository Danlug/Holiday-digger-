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
## Единственная фабрика кнопок. Виды:
##   UiBtn.text_button / style(b, kind)  — плитка: NORMAL (обычная), ACCENT (главная),
##                                         DANGER (опасная), GHOST (без плашки, крестик);
##   UiBtn.icon_button                   — плитка с одной иконкой;
##   UiBtn.fill(b, цвет)                 — цветная плашка-призыв («Забрать», «×2»);
##   UiBtn.texture_button("green", …)    — рисованная кнопка магазина и дома.
## У всех одинаково: «проседание» на нажатие вниз (UiAnim.press), звук и вибро на
## отпускание, цель нажатия не меньше TOUCH_MIN.

enum Kind { NORMAL, ACCENT, DANGER, GHOST }

const BG := UiTheme.BTN
const BG_HOVER := UiTheme.BTN_HOVER
const BG_PRESS := UiTheme.BTN_PRESS
const BORDER := UiTheme.EDGE
const GOLD := UiTheme.GOLD
const GOLD_DIM := UiTheme.GOLD_DIM
const RED := UiTheme.RED
const MUTED := UiTheme.MUTED
const SHADOW := Color(0, 0, 0, 0.6)
const FEEDBACK_META := &"_ui_feedback"
const BADGE_NAME := "Badge"
## Крестик «закрыть»: один размер и отступ на всех экранах и окнах.
const CLOSE_SIZE := 28.0   # ≥ 25 единиц ≈ 44 pt на iPhone
const CLOSE_INSET := 4.0   # от правого и верхнего края окна
const CLOSE_ROW := CLOSE_SIZE + CLOSE_INSET * 2.0   # высота полосы под крестиком сверху
const TOUCH_MIN := 25.0   # меньше пальцем не попасть (≈ 44 pt на iPhone)


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
	b.add_theme_color_override("font_disabled_color", UiTheme.DISABLED)
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.35))
	b.focus_mode = Control.FOCUS_NONE
	if with_feedback:
		wire_feedback(b)
	return b


static func set_kind(b: Button, kind: int) -> void:
	style(b, kind)


## Кнопка с подписью в общем стиле.
static func text_button(text: String, kind: int = Kind.NORMAL, size: Vector2 = Vector2.ZERO,
		font_size: int = UiTheme.FS_SMALL) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = _touch(size)
	return style(b, kind)


## Цветная плашка-призыв: фон цветом, светлая рамка, золотая при наведении,
## нажатая темнее. Белый текст; у выключенной — серый фон и тусклый текст.
static func fill(b: Button, bg: Color, margin: int = 3, with_feedback: bool = true) -> Button:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := ProgressUiKit.box(bg, GOLD if st == "hover" else bg.lightened(0.25), ProgressUiKit.R_TILE)
		if st == "pressed":
			sb.bg_color = bg.darkened(0.2)
		if st == "disabled":
			sb.bg_color = Color(0.15, 0.13, 0.11)
			sb.border_color = UiTheme.BORDER
		sb.set_content_margin_all(margin)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", UiTheme.DIM)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = _touch(b.custom_minimum_size)
	if with_feedback:
		wire_feedback(b)
	return b


## Плашка-призыв с иконкой (и подписью): «Забрать», «×2 за ролик».
static func fill_button(icon: Texture2D, size: Vector2, bg: Color, text: String = "",
		font_size: int = UiTheme.FS_BODY) -> Button:
	var b := Button.new()
	b.icon = icon
	b.text = text
	b.add_theme_constant_override("icon_max_width", 16)
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = size
	return fill(b, bg)


## Рисованная кнопка магазина и дома: девятизонник btn_<kind> (green/red/gold/gray)
## и знак по центру (узел «Glyph»). with_sound = false — звук даёт сам экран.
static func texture_button(kind: String, glyph: Texture2D, size: Vector2, glyph_px: float = 16.0,
		with_sound: bool = true) -> Button:
	size = _touch(size)
	var b := Button.new()
	b.custom_minimum_size = size
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	var texture := ShopArt.tex("btn_" + kind)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var sb := StyleBoxTexture.new()
		sb.texture = texture
		sb.texture_margin_left = 5
		sb.texture_margin_right = 5
		sb.texture_margin_top = 5
		sb.texture_margin_bottom = 5
		match st:
			"pressed", "hover_pressed":
				sb.modulate_color = Color(0.78, 0.78, 0.78)
			"disabled":
				sb.modulate_color = Color(0.45, 0.45, 0.5)
		b.add_theme_stylebox_override(st, sb)
	if glyph != null:
		var ic := ShopArt.rect(glyph, (size - Vector2(glyph_px, glyph_px)) * 0.5, Vector2(glyph_px, glyph_px))
		ic.name = "Glyph"
		b.add_child(ic)
	if with_sound:
		wire_feedback(b)
	else:
		wire_sink(b)
	return b


static func _touch(size: Vector2) -> Vector2:
	if size == Vector2.ZERO:
		return Vector2(0, TOUCH_MIN)
	return Vector2(maxf(size.x, TOUCH_MIN) if size.x > 0.0 else 0.0, maxf(size.y, TOUCH_MIN))


## Кнопка с одной иконкой. icon_px — размер картинки в проектных единицах
## (16 = один пиксель рисунка на единицу; 32 — вдвое крупнее).
static func icon_button(icon: Texture2D, size: Vector2 = Vector2(28, 28), kind: int = Kind.NORMAL, icon_px: int = 16) -> Button:
	var b := Button.new()
	b.icon = icon
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", icon_px)
	b.custom_minimum_size = _touch(size)
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
		b.offset_top = CLOSE_INSET
		b.offset_bottom = CLOSE_INSET + CLOSE_SIZE
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
		sb.bg_color = UiTheme.DANGER
		sb.border_color = UiTheme.INK
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
		label.add_theme_font_size_override("font_size", UiTheme.FS_TINY)
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

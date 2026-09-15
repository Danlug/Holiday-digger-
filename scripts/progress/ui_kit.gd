class_name ProgressUiKit
extends RefCounted
## Общие детали оформления для трёх экранов (прокачка, музей, рекорды).
##
## ПОЧЕМУ отдельный файл: экраны лежат в разных папках (progress/ и museum/),
## но открываются одной кнопкой и переключаются вкладками — если бы каждый
## красил себя сам, вкладки выглядели бы как три разные игры. Палитра взята
## из hud.gd, чтобы экраны не выбивались из общего интерфейса.

const GOLD := Color8(0xE0, 0xA9, 0x3B)
const MUTED := Color8(0x9D, 0x8B, 0x73)
const DIM := Color8(0x6A, 0x5C, 0x4C)
const BORDER := Color8(0x3E, 0x31, 0x25)
const BG := Color(0.071, 0.055, 0.043, 0.97)
const PANEL_BG := Color(0.11, 0.09, 0.07, 1.0)
const GREEN := Color8(0x7F, 0xB8, 0x6B)
const RED := Color8(0xB8, 0x5A, 0x52)
const BLUE := Color8(0x6E, 0x93, 0xA8)


static func panel_box(bg: Color = PANEL_BG, border: Color = BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func make_panel(bg: Color = PANEL_BG, border: Color = BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box(bg, border))
	return p


static func make_label(text: String, size: int = 10, color: Color = MUTED) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func make_wrapped_label(text: String, size: int = 9, color: Color = DIM) -> Label:
	var l := make_label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Кнопка в стиле нижней полосы HUD: прозрачная, с рамкой, подсветка золотом.
static func make_button(text: String, font_size: int = 9) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = BORDER
		sb.set_border_width_all(1)
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		if state == "pressed" or state == "hover":
			sb.border_color = GOLD
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", MUTED)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_disabled_color", DIM)
	return b


## Горизонтальная полоска заполнения (опыт, прогресс коллекции).
## Возвращает сам заполнитель — двигать надо его size.x.
static func make_bar(parent: Control, width: float, height: float, fill_color: Color) -> ColorRect:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(width, height)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.035, 0.027, 0.9)
	sb.border_color = BORDER
	sb.set_border_width_all(1)
	track.add_theme_stylebox_override("panel", sb)
	parent.add_child(track)

	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = Vector2(1, 1)
	fill.size = Vector2(width - 2, height - 2)
	track.add_child(fill)
	return fill


## Ряд «фишек» ступеней: закрашенные = купленные. Читается быстрее числа
## «3/10» — видно, сколько ещё осталось, не считая в уме.
static func make_pips(parent: Control, total: int, filled: int, pip_w: float = 7.0, pip_h: float = 5.0) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)
	for i in range(total):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(pip_w, pip_h)
		pip.color = GOLD if i < filled else Color(0.18, 0.15, 0.12, 1.0)
		row.add_child(pip)


static func make_separator(parent: Control, height: int = 6) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)

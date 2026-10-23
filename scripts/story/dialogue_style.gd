class_name DialogueStyle
extends RefCounted
## Общие цвета и рамки оформления диалогов и карточек сцен. Тёмный тёплый фон,
## золотая рамка, мягкая тень — как у экранов магазина и меты.

const GOLD := Color8(0xE0, 0xA9, 0x3B)
const GOLD_DIM := Color8(0x9C, 0x76, 0x2C)
const TEXT := Color8(0xF2, 0xE8, 0xD0)
const TEXT_NARR := Color8(0xD9, 0xCF, 0xB6)
const MUTED := Color8(0x9D, 0x8B, 0x73)
const PANEL_BG := Color(0.071, 0.055, 0.043, 0.95)
const INK := Color(0, 0, 0, 0.55)


static func panel_box(radius: int = 10, border: int = 2, shadow: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = GOLD
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = shadow
	sb.shadow_offset = Vector2(0, 2)
	sb.anti_aliasing = true
	return sb


## Ленточка с именем: фон — тёмный оттенок цвета говорящего, рамка золотая.
static func ribbon_box(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(0.45)
	sb.border_color = GOLD
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(0, 1)
	sb.anti_aliasing = true
	return sb


## Подсказка для Label: тень в один пиксель, чтобы текст читался на любом фоне.
static func shadowed(label: Label, size: int, color: Color) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)


static func reduced() -> bool:
	return Settings.reduce_motion

class_name HudPill
extends PanelContainer
## HudPill — «таблетка» кошелька: иконка и число с накруткой на тёмной
## полупрозрачной плашке. Название валюты и точная сумма — в подсказке (Tip).
##
##   var p := HudPill.new().setup(UiIcons.tex("coin"), UiTheme.GOLD)
##   p.set_value(1250)

var icon_rect: TextureRect
var count: CountLabel


static func pill_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.055, 0.043, 0.74)
	sb.border_color = Color(color.r, color.g, color.b, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(ProgressUiKit.R_CARD)
	sb.content_margin_left = 4
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


func setup(icon: Texture2D, color: Color) -> HudPill:
	add_theme_stylebox_override("panel", pill_style(color))
	mouse_filter = Control.MOUSE_FILTER_PASS

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	add_child(row)

	icon_rect = TextureRect.new()
	icon_rect.texture = icon
	icon_rect.custom_minimum_size = Vector2(16, 16)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_rect)

	count = CountLabel.new()
	count.base_color = color
	count.add_theme_font_size_override("font_size", UiTheme.FS_TITLE)
	count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	count.add_theme_constant_override("outline_size", 2)
	count.custom_minimum_size = Vector2(28, 0)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count)
	return self


func set_value(v: int, instant: bool = false) -> void:
	var changed := v != count.value()
	count.set_value(v, instant)
	if changed and not instant:
		UiAnim.pulse(icon_rect, 0.25, 0.28)

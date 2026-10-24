class_name HeroTabButton
extends Button
## Кнопка вкладки нижней панели экрана героя: только иконка (подпись — в
## подсказке Tip), золотая рамка у выбранной и зелёный значок-число в углу,
## когда есть что делать (свободные очки навыков).

var icon_name: String = ""
var selected: bool = false
var badge: int = 0

var _sb := StyleBoxFlat.new()


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true
	custom_minimum_size = Vector2(0, 26)
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_sb.set_corner_radius_all(ProgressUiKit.R_TILE)
	_sb.set_border_width_all(1)
	UiBtn.wire_sink(self)   # то же «проседание», что у всех кнопок; звук играет экран вкладок


func setup(icon_name_: String, tip_title: String, tip_body: String = "") -> void:
	icon_name = icon_name_
	Tip.bind(self, tip_title, tip_body)


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func set_badge(value: int) -> void:
	if badge == value:
		return
	badge = value
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	_sb.bg_color = HeroUi.TILE_BG_HI if selected else HeroUi.TILE_BG
	_sb.border_color = ProgressUiKit.GOLD if selected else ProgressUiKit.BORDER
	_sb.set_border_width_all(2 if selected else 1)
	draw_style_box(_sb, rect)
	var tex := HeroIcons.get_icon(icon_name)
	if tex != null:
		var isz := Vector2(16, 16)
		draw_texture_rect(tex, Rect2(((size - isz) * 0.5).floor(), isz), false,
			Color.WHITE if selected else Color(1, 1, 1, 0.62))
	if badge > 0:
		var c := Vector2(size.x - 7.0, 6.0)
		draw_circle(c, 6.0, Color(0.06, 0.05, 0.04))
		draw_circle(c, 5.0, HeroUi.OK)
		var font := ThemeDB.fallback_font
		var text := str(mini(badge, 99))
		var fs := 8
		draw_string(font, Vector2(c.x - 6.0, c.y + font.get_ascent(fs) * 0.5 - 1.0), text,
			HORIZONTAL_ALIGNMENT_CENTER, 12.0, fs, Color(0.05, 0.12, 0.06))

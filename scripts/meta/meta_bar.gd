class_name MetaBar
extends Control
## Полоска прогресса с числом «12/40» по центру. Рисуется целиком в _draw —
## ширину задаёт контейнер, заливка пересчитывается сама.

var frac: float = 0.0:
	set(v):
		frac = clampf(v, 0.0, 1.0)
		queue_redraw()
var text: String = "":
	set(t):
		text = t
		queue_redraw()
var fill_color: Color = MetaUiKit.GOLD
var font_size: int = UiTheme.FS_TINY


func _init() -> void:
	custom_minimum_size = Vector2(40, 13)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.043, 0.035, 0.027, 0.95))
	draw_rect(Rect2(Vector2.ZERO, size), MetaUiKit.BORDER, false, 1.0)
	var inner := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	if frac > 0.0:
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * frac, inner.size.y)), fill_color)
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * frac, 2.0)), fill_color.lightened(0.3))
	if text != "":
		var font := ThemeDB.fallback_font
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var p := Vector2((size.x - ts.x) * 0.5, (size.y + ts.y) * 0.5 - 2.0)
		draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color(0, 0, 0, 0.9))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

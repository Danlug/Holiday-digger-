class_name MetaRing
extends Control
## Прогресс-кольцо вокруг значка: дуга от «12 часов» по часовой. Рисуется без
## сглаживания — в тон пиксельной графике.

var value: float = 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
var ring_color: Color = MetaUiKit.GOLD:
	set(c):
		ring_color = c
		queue_redraw()
var track_color: Color = Color(0, 0, 0, 0.5)
var width: float = 2.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func animate_to(v: float, seconds: float = 0.5) -> void:
	if not is_inside_tree() or UiAnim.reduced():
		value = clampf(v, 0.0, 1.0)
		return
	var t := create_tween()
	t.tween_property(self, "value", clampf(v, 0.0, 1.0), seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - width * 0.5
	if r <= 1.0:
		return
	draw_arc(c, r, 0.0, TAU, 48, track_color, width)
	if value > 0.0:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * value, maxi(6, int(48.0 * value)), ring_color, width)

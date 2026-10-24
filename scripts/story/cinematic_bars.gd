class_name CinematicBars
extends Control
## «Кинематографические полосы» сверху и снизу на катсценах: въезжают при начале
## сцены и уезжают при её конце. Живут отдельным узлом, а не внутри корня сцены:
## корень прячется мгновенно, а полосы успевают уехать на глазах у игрока.

const FRACTION := 0.055
const OPEN_SEC := 0.5
const CLOSE_SEC := 0.35

var height: float = 0.0:
	set(v):
		height = v
		queue_redraw()
var target_height: float = 0.0

var _tween: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


static func bar_height_for(vp_h: float) -> float:
	return roundf(vp_h * FRACTION)


## Полоса нужной высоты для вьюпорта; вызывать при каждом пересчёте раскладки.
func fit(vp: Vector2) -> void:
	size = vp
	var h := bar_height_for(vp.y)
	var was_open := target_height > 0.0
	target_height = h if was_open else 0.0
	if was_open and (_tween == null or not _tween.is_valid()):
		height = h
	queue_redraw()


func open(vp: Vector2, animated: bool = true) -> void:
	size = vp
	var h := bar_height_for(vp.y)
	target_height = h
	visible = true
	_kill()
	if not animated or Settings.reduce_motion or not is_inside_tree():
		height = h
		return
	_tween = create_tween()
	_tween.tween_property(self, "height", h, OPEN_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close(animated: bool = true) -> void:
	target_height = 0.0
	_kill()
	if not animated or Settings.reduce_motion or not is_inside_tree() or not visible:
		height = 0.0
		visible = false
		return
	_tween = create_tween()
	_tween.tween_property(self, "height", 0.0, CLOSE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void:
		if target_height <= 0.0:
			visible = false)


func is_open() -> bool:
	return visible and target_height > 0.0


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _draw() -> void:
	if height <= 0.5:
		return
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, height), Color.BLACK)
	draw_rect(Rect2(0, h - height, w, height), Color.BLACK)
	# Тонкая тёплая кромка и мягкая тень от неё на кадр.
	var edge := Color(DialogueStyle.GOLD, 0.28)
	draw_rect(Rect2(0, height - 1, w, 1), edge)
	draw_rect(Rect2(0, h - height, w, 1), edge)
	var fade := PackedColorArray([Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), Color(0, 0, 0, 0)])
	draw_polygon(PackedVector2Array([Vector2(0, height), Vector2(w, height), Vector2(w, height + 8), Vector2(0, height + 8)]), fade)
	var fade_b := PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45)])
	draw_polygon(PackedVector2Array([Vector2(0, h - height - 8), Vector2(w, h - height - 8), Vector2(w, h - height), Vector2(0, h - height)]), fade_b)

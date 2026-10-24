class_name HpVignette
extends Control
## HpVignette — красноватая рамка по краям экрана при низком здоровье
## (ниже порога) и ритмичный «пульс» в такт полоске HP. Ничего не
## перехватывает; при «меньше движения» горит ровно, без пульса.

const THRESHOLD := 0.25
const LAYERS := 7
const STEP := 3.0

var _level: float = 1.0
var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _ready() -> void:
	set_process(visible and not Settings.reduce_motion)


## frac — доля здоровья 0..1.
func set_level(frac: float) -> void:
	_level = frac
	var on := frac < THRESHOLD and frac > 0.0
	visible = on
	set_process(on and not Settings.reduce_motion)
	queue_redraw()


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func _draw() -> void:
	var danger := clampf(1.0 - _level / THRESHOLD, 0.0, 1.0)
	var beat := 1.0 if Settings.reduce_motion else 0.65 + 0.35 * sin(_t * 7.0)
	for i in LAYERS:
		var fade := 1.0 - float(i) / float(LAYERS)
		var a := 0.32 * danger * beat * fade
		var inset := STEP * i
		var r := Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0)
		draw_rect(r, Color(0.85, 0.12, 0.1, a), false, STEP)

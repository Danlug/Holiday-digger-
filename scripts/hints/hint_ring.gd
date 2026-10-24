class_name HintRing
extends Control
## Рамка и расходящееся «эхо» вокруг цели подсказки. Рисует сама; пульс — свойство
## pulse (0..1), его гонит твин. Без твина (Settings.reduce_motion) рамка просто стоит.

const GOLD := Color8(0xE0, 0xA9, 0x3B)
const GOLD_LIGHT := Color8(0xF2, 0xD9, 0x9B)

var rect: Rect2 = Rect2()
var pulse: float = 0.0:
	set(v):
		pulse = v
		queue_redraw()

var _tw: Tween
var _box: StyleBoxFlat


func _init() -> void:
	_box = StyleBoxFlat.new()
	_box.set_corner_radius_all(7)
	_box.anti_aliasing = false
	set_anchors_preset(Control.PRESET_TOP_LEFT)


func setup(r: Rect2) -> void:
	rect = r
	queue_redraw()


func start() -> void:
	stop()
	if not is_inside_tree():
		return
	_tw = create_tween().set_loops()
	_tw.tween_property(self, "pulse", 1.0, 0.95).from(0.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tw.tween_interval(0.12)


func stop() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = null


func _draw() -> void:
	if rect.size == Vector2.ZERO:
		return
	# Основная рамка слегка дышит и подсвечивает цель изнутри.
	var main := rect.grow(2.0 + 1.5 * (1.0 - pulse))
	_box.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.10 + 0.08 * (1.0 - pulse))
	_box.border_color = Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, 0.95)
	_box.set_border_width_all(2)
	draw_style_box(_box, main)
	# «Эхо»: второе кольцо расходится и гаснет — сигнал «сюда», заметный краем глаза.
	var echo := rect.grow(3.0 + 9.0 * pulse)
	_box.bg_color = Color(0, 0, 0, 0)
	_box.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.75 * (1.0 - pulse))
	_box.set_border_width_all(2)
	draw_style_box(_box, echo)

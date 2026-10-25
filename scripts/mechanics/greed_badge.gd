class_name GreedBadge
extends Node2D
## Значок жадности над героем (в мире, слой ViewRoot поверх всего): бело-золотое
## пламя и «×7», под ними тонкая полоска оставшегося времени; за героем — золотые
## штрихи скорости по его пути. «Меньше движения» — без покачивания и штрихов.

const COL_GOLD := Color8(0xFF, 0xE5, 0x7A)
const COL_DEEP := Color8(0xF0, 0x7A, 0x1E)
const COL_SHADOW := Color(0.05, 0.04, 0.03, 0.9)
const TRAIL_N := 7
const HEAD_DY := -38.0     # над макушкой героя (центр героя — середина клетки)

var director: Node = null

var _alpha: float = 0.0
var _time: float = 0.0
var _trail: Array = []     # последние позиции героя, пиксели мира
var _icon: Texture2D
var _label: Label


func _ready() -> void:
	z_index = 50
	_icon = Mechanics.tex("fever")
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", COL_GOLD)
	_label.add_theme_constant_override("outline_size", 3)
	_label.add_theme_color_override("font_outline_color", COL_SHADOW)
	add_child(_label)
	visible = false


func _process(delta: float) -> void:
	var streak: StreakLogic = director.streak if director != null else null
	var player = director.player if director != null else null
	var on := streak != null and streak.in_greed() and player != null and is_instance_valid(player)
	if not on and _alpha <= 0.0:
		if visible:
			visible = false
			_trail.clear()
		return
	_time += delta
	_alpha = 1.0 if on and Settings.reduce_motion else move_toward(_alpha, 1.0 if on else 0.0, delta * (8.0 if on else 3.0))
	if Settings.reduce_motion and not on:
		_alpha = 0.0
	visible = _alpha > 0.0
	if player != null and is_instance_valid(player):
		var p := Vector2(float(player.x) * 32.0, float(player.y) * 32.0)
		if on and not Settings.reduce_motion:
			_trail.push_front(p)
			if _trail.size() > TRAIL_N:
				_trail.pop_back()
		elif not _trail.is_empty():
			_trail.pop_back()
		var bob := 0.0 if Settings.reduce_motion else roundf(sin(_time * 6.0) * 1.5)
		position = p + Vector2(0, HEAD_DY + bob)
		_label.text = "×%d" % roundi(GreedRules.speed_mult())
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.0:
		return
	var streak: StreakLogic = director.streak if director != null else null
	# штрихи скорости: координаты следа — в мире, а рисуем от своего position
	for i in range(1, _trail.size()):
		var a: Vector2 = _trail[i - 1]
		var b: Vector2 = _trail[i]
		var d := a - b
		if d.length() < 3.0:
			continue
		var n := Vector2(-d.y, d.x).normalized()
		var k := 1.0 - float(i) / float(TRAIL_N)
		var col := Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.55 * k * _alpha)
		for off in [-7.0, 0.0, 7.0]:
			draw_line(a + n * off - position, b + n * off - position, col, 1.0)
	# пламя + «×7»
	var font_w := _label.get_minimum_size().x
	var icon_s := 14.0
	var total_w := icon_s + 1.0 + font_w
	var x0 := roundf(-total_w * 0.5)
	if _icon != null:
		draw_texture_rect(_icon, Rect2(Vector2(x0, -icon_s * 0.5 - 1.0), Vector2(icon_s, icon_s)), false,
			Color(1, 1, 1, _alpha))
	_label.position = Vector2(x0 + icon_s + 1.0, roundf(-_label.get_minimum_size().y * 0.5) - 1.0)
	_label.modulate.a = _alpha
	# таймер: тонкая полоска под значком
	if streak != null:
		var w := 22.0
		var r := Rect2(Vector2(-w * 0.5, icon_s * 0.5 + 1.0), Vector2(w, 3))
		draw_rect(r, Color(COL_SHADOW.r, COL_SHADOW.g, COL_SHADOW.b, 0.85 * _alpha))
		var f := streak.meter() if streak.in_greed() else 0.0
		var low := streak.greed_left < 1.0 and not Settings.reduce_motion
		var col := COL_GOLD if not low or sin(_time * 18.0) > 0.0 else COL_DEEP
		col.a = _alpha
		if f > 0.0:
			draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(floorf((w - 2.0) * f), 1)), col)

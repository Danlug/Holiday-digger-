class_name HeroPortrait
extends Control
## Портрет героя на карточке экрана: кадры стойки из art/character/idle.png
## (спрайты как есть — тот же лист, что рисует CharacterView в мире), мягкий
## «софит» за спиной и тень под ногами. Герой чуть дышит: кадры стойки
## сменяются медленно.
##
## ПОЧЕМУ лист читается напрямую, а не через CharacterView: CharacterView
## привязан к живому Player (позиция, копка, состояние) и крутит десятки
## листов; портрету нужна одна статичная стойка, и ему незачем знать о мире.

const SHEET := "res://art/character/idle.png"
const FRAME := 144
const FEET_Y := 138.0          # линия земли внутри кадра
const SPRITE_SCALE := 0.82
const BREATH_SECONDS := 0.5

var _tex: Texture2D = null
var _frames: int = 1
var _frame: int = 0
var _t: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(84, 118)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if ResourceLoader.exists(SHEET):
		_tex = load(SHEET)
		_frames = maxi(int(_tex.get_width() / FRAME), 1)
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))


func _process(delta: float) -> void:
	_t += delta
	var f := int(_t / BREATH_SECONDS) % _frames
	if f != _frame:
		_frame = f
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(HeroUi.box(Color(0.07, 0.06, 0.09), ProgressUiKit.GOLD.darkened(0.35), 5, 1), rect)

	# софит: несколько прозрачных эллипсов вместо градиента — без шейдеров
	var center := Vector2(size.x * 0.5, size.y * 0.52)
	for i in range(9):
		var k := float(i) / 8.0
		draw_set_transform(center, 0.0, Vector2(1.0, 1.25))
		draw_circle(Vector2.ZERO, lerpf(42.0, 10.0, k), Color(0.95, 0.72, 0.3, 0.028))
	var feet_y := size.y - 8.0
	draw_set_transform(Vector2(size.x * 0.5, feet_y), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, 22.0, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if _tex == null:
		return
	var w := float(FRAME) * SPRITE_SCALE
	var dest := Rect2(Vector2((size.x - w) * 0.5, feet_y - FEET_Y * SPRITE_SCALE), Vector2(w, w))
	draw_texture_rect_region(_tex, dest, Rect2(float(_frame * FRAME), 0.0, float(FRAME), float(FRAME)))

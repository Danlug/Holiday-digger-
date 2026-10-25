class_name DialoguePortrait
extends Control
## Один портрет говорящего: рамка со скруглением, бюст 64×64 из листа
## art/dialogue/portrait_<id>.png, выражение лица, «рот» при печати реплики,
## моргание. Говорящий подсвечен (полный цвет, золотая кромка, свечение),
## молчащий — тусклый и чуть меньше. Позицию ведёт DialogueUI.

const ART := 64.0
const PAD := 2.0
const SIZE_PX := ART + PAD * 2.0
const DIM := Color(0.5, 0.5, 0.58, 1.0)
const INACTIVE_SCALE := 0.86
const MOUTH_HZ := 8.0

var who: String = ""
var portrait_id: String = ""
var face: String = "neutral"
var talking: bool = false
var active: bool = false
var target_pos: Vector2 = Vector2.ZERO
## Смещение «реакции» (прыжок удивления, подскок радости, дрожь злости): плюсуется к позиции.
var react_off: Vector2 = Vector2.ZERO

var _sheet: Texture2D = null
var _accent: Color = DialogueCast.DEFAULT_ACCENT
var _bg: StyleBoxFlat
var _edge: StyleBoxFlat
var _t: float = 0.0
var _blink_in: float = 3.0
var _blink_left: float = 0.0
var _frame: int = 0
var _tween: Tween = null
var _vis_tween: Tween = null
var _react_tween: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	size = Vector2(SIZE_PX, SIZE_PX)
	pivot_offset = Vector2(SIZE_PX * 0.5, SIZE_PX)
	_bg = StyleBoxFlat.new()
	_bg.set_corner_radius_all(7)
	_bg.anti_aliasing = true
	_bg.shadow_offset = Vector2(0, 2)
	_edge = StyleBoxFlat.new()
	_edge.bg_color = Color(0, 0, 0, 0)
	_edge.set_corner_radius_all(7)
	_edge.set_border_width_all(2)
	_edge.anti_aliasing = true


## Назначить говорящего. Возвращает false, если портрета нет (лист не найден).
func assign(speaker_id: String, portrait: String) -> bool:
	who = speaker_id
	portrait_id = portrait
	_sheet = DialogueCast.sheet(portrait)
	_accent = DialogueCast.accent(speaker_id)
	_bg.bg_color = _accent.darkened(0.66)
	_blink_in = randf_range(2.0, 4.5)
	_apply_active_look()
	queue_redraw()
	return _sheet != null


func set_face(f: String, pop: bool = true) -> void:
	if f == face:
		return
	face = f
	_frame = 0
	queue_redraw()
	if pop:
		pulse()


func has_art() -> bool:
	return _sheet != null


## Видимый кадр: 0 «молчит», 1 «рот открыт», 2 «моргнул».
func current_frame() -> int:
	return _frame


func set_active(a: bool, animate: bool = true) -> void:
	active = a
	_apply_active_look()
	var want_scale := Vector2.ONE if a else Vector2.ONE * INACTIVE_SCALE
	var want_tint := Color.WHITE if a else DIM
	_kill_tween()
	if not animate or DialogueStyle.reduced() or not is_inside_tree():
		scale = want_scale
		self_modulate = want_tint
		return
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "scale", want_scale, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "self_modulate", want_tint, 0.16)


func pulse() -> void:
	if not active or DialogueStyle.reduced() or not is_inside_tree():
		return
	_kill_tween()
	scale = Vector2.ONE * 1.07
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Появление: из-под плашки сбоку, с проявлением.
func appear(from_offset: Vector2) -> void:
	_kill_vis()
	visible = true
	if DialogueStyle.reduced() or not is_inside_tree():
		modulate.a = 1.0
		position = target_pos
		return
	position = target_pos + from_offset
	modulate.a = 0.0
	_vis_tween = create_tween()
	_vis_tween.tween_property(self, "modulate:a", 1.0, 0.16)


## Уход: быстрое затухание и скрытие (закадровый текст, смена декорации).
func vanish() -> void:
	_kill_vis()
	talking = false
	who = ""
	portrait_id = ""
	if not visible:
		return
	if DialogueStyle.reduced() or not is_inside_tree():
		visible = false
		return
	_vis_tween = create_tween()
	_vis_tween.tween_property(self, "modulate:a", 0.0, 0.12)
	_vis_tween.tween_callback(func() -> void: visible = false)


## Короткая телодвижение по выражению: удивление — прыжок, радость — два подскока,
## злость — дрожь, грусть — оседание. Нейтральное лицо не двигается.
func react(f: String) -> void:
	if _react_tween != null and _react_tween.is_valid():
		_react_tween.kill()
	_react_tween = null
	react_off = Vector2.ZERO
	if not active or f == "neutral" or DialogueStyle.reduced() or not is_inside_tree():
		return
	var tw := create_tween()
	_react_tween = tw
	match f:
		"surprise":
			tw.tween_property(self, "react_off", Vector2(0, -5), 0.07).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "react_off", Vector2.ZERO, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		"happy":
			for _i in 2:
				tw.tween_property(self, "react_off", Vector2(0, -3), 0.08).set_ease(Tween.EASE_OUT)
				tw.tween_property(self, "react_off", Vector2.ZERO, 0.08).set_ease(Tween.EASE_IN)
		"angry":
			for dx in [2.5, -2.5, 2.0, -1.5, 0.0]:
				tw.tween_property(self, "react_off", Vector2(dx, 0), 0.04)
		"sad":
			tw.tween_property(self, "react_off", Vector2(0, 3), 0.25).set_trans(Tween.TRANS_SINE)
			tw.tween_property(self, "react_off", Vector2(0, 1), 0.4)


func _kill_vis() -> void:
	if _vis_tween != null and _vis_tween.is_valid():
		_vis_tween.kill()
	_vis_tween = null
	modulate.a = 1.0


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _apply_active_look() -> void:
	if active:
		_edge.border_color = DialogueStyle.GOLD
		_bg.shadow_color = Color(_accent.r, _accent.g, _accent.b, 0.6)
		_bg.shadow_size = 6
	else:
		_edge.border_color = DialogueStyle.GOLD_DIM.darkened(0.35)
		_bg.shadow_color = Color(0, 0, 0, 0.45)
		_bg.shadow_size = 3
	queue_redraw()


## Шаг анимации: рот на «говорит» пока идёт печать, моргание в паузах.
func tick(dt: float) -> void:
	_t += dt
	var want := 0
	if not DialogueStyle.reduced():
		if talking and active:
			want = 1 if int(_t * MOUTH_HZ) % 2 == 0 else 0
		else:
			_blink_in -= dt
			if _blink_in <= 0.0:
				_blink_left = 0.12
				_blink_in = randf_range(2.5, 5.0)
			if _blink_left > 0.0:
				_blink_left -= dt
				want = 2
	if want != _frame:
		_frame = want
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(SIZE_PX, SIZE_PX))
	draw_style_box(_bg, r)
	# Мягкий «софит» за головой — бюст не сливается с рамкой.
	draw_circle(Vector2(SIZE_PX * 0.5, 26.0), 27.0, Color(_accent.r, _accent.g, _accent.b, 0.16))
	draw_circle(Vector2(SIZE_PX * 0.5, 26.0), 19.0, Color(_accent.r, _accent.g, _accent.b, 0.14))
	if _sheet != null:
		draw_texture_rect_region(_sheet, Rect2(PAD, PAD, ART, ART), DialogueCast.region(face, _frame))
	draw_style_box(_edge, r)

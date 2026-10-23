class_name HudBar
extends Control
## HudBar — анимированная полоска состояния (HP, голод, бодрость): иконка слева,
## заливка с бликом и «рисками» по четвертям.
##
## Что она умеет:
##  - потеря показывается «догоняющей» светлой полосой: заливка падает сразу, а
##    светлый хвост ещё мгновение висит и плавно съедается — видно, СКОЛЬКО потеряно;
##  - резкая потеря (>= FLASH_DROP от шкалы) даёт белую вспышку заливки и дрожь иконки;
##  - ниже LOW (25%) заливка и иконка пульсируют, пока не поправишься
##    (у полоски веса — наоборот, когда заполнена: pulse_above);
##  - рост плавный, а не скачком.
## Числа на ней не пишутся: «72/100» живёт в подсказке (Tip).
##
## При включённом «меньше движения» (Settings.reduce_motion) всё мгновенное,
## пульс и вспышка отключены.

const ICON_PX := 16.0
const GAP := 3.0
const BAR_H := 8.0
const LOW := 0.25
const FLASH_DROP := 0.06
const GHOST_HOLD := 0.35
const GHOST_SPEED := 0.9     # доля шкалы в секунду
const RISE_SPEED := 2.5

var fill_color: Color = Color8(0xD0, 0x4B, 0x4B):
	set(v):
		fill_color = v
		queue_redraw()
var icon: Texture2D = null:
	set(v):
		icon = v
		_update_min()
		queue_redraw()
var bar_h: float = BAR_H:
	set(v):
		bar_h = v
		_update_min()
		queue_redraw()
## Для полоски «наполнение» (вес рюкзака) тревога — когда ПОЛНО, а не пусто:
## pulse_above >= 0 включает пульс при значении не ниже порога.
var pulse_above: float = -1.0
var bar_width: float = 76.0:
	set(v):
		bar_width = v
		_update_min()
		queue_redraw()

var _target: float = 1.0
var _value: float = 1.0     # то, что нарисовано заливкой
var _ghost: float = 1.0     # светлый «хвост» потери
var _hold: float = 0.0
var _flash: float = 0.0
var _alert: float = 0.0      # секунд красного мигания (серьёзное предупреждение)
var _shake: float = 0.0
var _t: float = 0.0
var _track_box: StyleBoxFlat
var _fill_box: StyleBoxFlat


func _update_min() -> void:
	var lead := (ICON_PX + GAP) if icon != null else 0.0
	custom_minimum_size = Vector2(lead + bar_width, maxf(bar_h + 2.0, ICON_PX if icon != null else 0.0))


func _init() -> void:
	_update_min()
	mouse_filter = Control.MOUSE_FILTER_PASS
	_track_box = StyleBoxFlat.new()
	_track_box.bg_color = Color(0.04, 0.03, 0.025, 0.82)
	_track_box.border_color = Color(0, 0, 0, 0.7)
	_track_box.set_border_width_all(1)
	_track_box.set_corner_radius_all(3)
	_fill_box = StyleBoxFlat.new()
	_fill_box.set_corner_radius_all(2)


func setup(color: Color, tex: Texture2D) -> HudBar:
	fill_color = color
	icon = tex
	queue_redraw()
	return self


## Задаёт долю 0..1. instant — без анимации (первичная установка).
func set_fraction(f: float, instant: bool = false) -> void:
	f = clampf(f, 0.0, 1.0)
	var drop := _target - f
	_target = f
	if instant or Settings.reduce_motion:
		_value = f
		_ghost = f
		_flash = 0.0
		set_process(is_alarm())
		queue_redraw()
		return
	if drop > 0.0:
		# Потеря: заливка падает сразу, хвост остаётся на старом месте.
		_value = f
		_hold = GHOST_HOLD
		if drop >= FLASH_DROP:
			_flash = 1.0
			_shake = 1.0
	set_process(true)
	queue_redraw()


## Красное мигание на duration секунд — «серьёзное предупреждение» (ГДД п.7).
## При «меньше движения» — одна вспышка вместо мигания.
func alert(duration: float = 2.0) -> void:
	_flash = 1.0
	_shake = 1.0
	if Settings.reduce_motion:
		return
	_alert = duration
	set_process(true)


func fraction() -> float:
	return _target


func is_alarm() -> bool:
	if pulse_above >= 0.0:
		return _target >= pulse_above
	return _target < LOW and _target > 0.0


func _process(dt: float) -> void:
	_t += dt
	var busy := false
	if _value < _target:
		_value = minf(_target, _value + RISE_SPEED * dt)
		busy = true
	if _hold > 0.0:
		_hold -= dt
		busy = true
	elif _ghost > _value:
		_ghost = maxf(_value, _ghost - GHOST_SPEED * dt)
		busy = true
	if _ghost < _value:
		_ghost = _value
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 4.0)
		busy = true
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - dt * 3.5)
		busy = true
	if _alert > 0.0:
		_alert = maxf(0.0, _alert - dt)
		busy = true
	if is_alarm() and not Settings.reduce_motion:
		busy = true
	queue_redraw()
	if not busy:
		set_process(false)


func _draw() -> void:
	var h := size.y
	var pulse := 0.0
	if (is_alarm() or _alert > 0.0) and not Settings.reduce_motion:
		pulse = 0.5 + 0.5 * sin(_t * (14.0 if _alert > 0.0 else 7.0))
	# --- иконка ---
	if icon != null:
		var s := ICON_PX * (1.0 + 0.14 * pulse)
		var off := Vector2(sin(_t * 60.0) * 1.5 * _shake, 0.0)
		draw_texture_rect(icon, Rect2(Vector2(0.0, (h - s) * 0.5) + off + Vector2((ICON_PX - s) * 0.5, 0.0),
			Vector2(s, s)), false)
	# --- дорожка ---
	var x0 := (ICON_PX + GAP) if icon != null else 0.0
	var bar_rect := Rect2(x0, (h - bar_h) * 0.5, maxf(size.x - x0, 8.0), bar_h)
	draw_style_box(_track_box, bar_rect)
	var inner := Rect2(bar_rect.position + Vector2.ONE, bar_rect.size - Vector2(2, 2))
	# --- светлый хвост потери ---
	if _ghost > _value + 0.002:
		var gx := inner.position.x + inner.size.x * _value
		var gw := inner.size.x * (_ghost - _value)
		draw_rect(Rect2(gx, inner.position.y, gw, inner.size.y), Color(1, 0.93, 0.8, 0.85))
	# --- заливка ---
	var fw := inner.size.x * _value
	if fw >= 1.0:
		var col := fill_color.lerp(Color.WHITE, 0.25 * pulse + 0.7 * _flash)
		if _alert > 0.0:
			col = fill_color.lerp(Color(1.0, 0.2, 0.15), 0.4 + 0.5 * pulse)
		_fill_box.bg_color = col
		draw_style_box(_fill_box, Rect2(inner.position, Vector2(fw, inner.size.y)))
		# блик сверху и тень снизу — «объём» без градиента
		draw_rect(Rect2(inner.position.x + 1, inner.position.y, maxf(fw - 2, 0.0), 2),
			Color(1, 1, 1, 0.28))
		draw_rect(Rect2(inner.position.x + 1, inner.end.y - 1, maxf(fw - 2, 0.0), 1),
			Color(0, 0, 0, 0.22))
	# --- риски по четвертям ---
	for i in range(1, 4):
		var tx := inner.position.x + inner.size.x * 0.25 * i
		draw_rect(Rect2(tx, inner.position.y, 1, inner.size.y), Color(0, 0, 0, 0.28))
	# --- красная рамка на пульсе ---
	if pulse > 0.0:
		var warn := StyleBoxFlat.new()
		warn.bg_color = Color(0, 0, 0, 0)
		warn.border_color = Color(1.0, 0.3, 0.25, 0.35 + 0.5 * pulse)
		warn.set_border_width_all(1)
		warn.set_corner_radius_all(3)
		draw_style_box(warn, bar_rect.grow(1.0))

class_name CollapseFx
extends Node2D
## Видимая сторона обвала и землетрясения (ГДД §8): предупреждение — пыль сыплется
## с «потолка» зоны и зона мерцает, удар — облако пыли по всей зоне. Правил не
## меняет: прямоугольник выбирает CollapseEvents, этот узел только рисует.
## Тряска экрана и звук — через фасады Fx/Sfx (их строит ветка «Звук и сок»), пыль
## в зоне рисуем сами: фасад Fx.burst не умеет «занавес» по прямоугольнику.
##
## Рисуем только ту часть зоны, что попала в окно камеры, и не больше ~60 зёрен.

const TILE := 32.0
const MAX_GRAINS := 60

var _cam := Vector2.ZERO
var _view := Vector2(7, 14)
var _warn: Dictionary = {}     # {x0,y0,w,h} клетки
var _warn_t := 0.0
var _warn_len := 0.0
var _impact: Dictionary = {}
var _impact_t := 0.0
var _grains: Array = []
var _rng := RandomNumberGenerator.new()
var _drew := false


func _ready() -> void:
	_rng.randomize()


func is_warning() -> bool:
	return not _warn.is_empty()


## Предупреждение о скором обвале в прямоугольнике rect (клетки) на seconds секунд.
func warn(rect: Dictionary, seconds: float) -> void:
	_warn = rect
	_warn_t = 0.0
	_warn_len = maxf(seconds, 0.1)


func cancel_warning() -> void:
	_warn = {}


## Удар: облако пыли по зоне (rect — клетки). Землетрясение зовёт с зоной всего окна камеры.
func impact(rect: Dictionary) -> void:
	_warn = {}
	_impact = rect
	_impact_t = 0.0
	for i in range(MAX_GRAINS):
		_spawn_grain(rect, true)


func update(cam: Vector2, view_w: int, view_h: int, dt: float) -> void:
	_cam = cam
	_view = Vector2(view_w, view_h)
	var active := false
	if not _warn.is_empty():
		_warn_t += dt
		active = true
		if _grains.size() < MAX_GRAINS / 2 and _rng.randf() < 0.9:
			_spawn_grain(_warn, false)
	if not _impact.is_empty():
		_impact_t += dt
		active = true
		if _impact_t > 0.9:
			_impact = {}
	var i := _grains.size() - 1
	while i >= 0:
		var g: Dictionary = _grains[i]
		g.t += dt
		g.x += g.vx * dt
		g.y += g.vy * dt
		g.vy += 40.0 * dt
		if g.t >= g.life:
			_grains.remove_at(i)
		i -= 1
	if not _grains.is_empty():
		active = true
	# перерисовка нужна, пока что-то есть, и ещё один раз, чтобы стереть последнее
	if active or _drew:
		queue_redraw()
	_drew = active


## Зерно пыли в части зоны, видимой камерой.
func _spawn_grain(rect: Dictionary, burst: bool) -> void:
	var vx0 := maxi(int(rect.x0), int(floor(_cam.x)))
	var vx1 := mini(int(rect.x0) + int(rect.w), int(floor(_cam.x + _view.x)) + 1)
	var vy0 := maxi(int(rect.y0), int(floor(_cam.y)))
	var vy1 := mini(int(rect.y0) + int(rect.h), int(floor(_cam.y + _view.y)) + 1)
	if vx1 <= vx0 or vy1 <= vy0:
		return
	var x := _rng.randf_range(float(vx0), float(vx1)) * TILE
	var y := float(vy0) * TILE + _rng.randf_range(0.0, 1.0) * (float(vy1 - vy0) * TILE if burst else TILE * 0.6)
	_grains.append({"x": x, "y": y, "vx": _rng.randf_range(-14.0, 14.0) if burst else _rng.randf_range(-3.0, 3.0),
			"vy": _rng.randf_range(-30.0, 10.0) if burst else _rng.randf_range(10.0, 30.0),
			"t": 0.0, "life": _rng.randf_range(0.5, 1.1) if burst else _rng.randf_range(0.6, 1.2),
			"s": 2.0 if _rng.randf() < 0.3 else 1.0})


func _draw() -> void:
	if not _warn.is_empty():
		var pulse := 0.5 + 0.5 * sin(_warn_t * 18.0)
		var k := clampf(_warn_t / _warn_len, 0.0, 1.0)
		var r := _clip(_warn)
		if r.size.x > 0.0:
			draw_rect(r, Color(0.0, 0.0, 0.0, (0.06 + 0.14 * pulse) * (0.4 + 0.6 * k)))
			draw_rect(r, Color(1.0, 0.82, 0.5, 0.12 + 0.2 * pulse), false, 1.0)
	if not _impact.is_empty():
		var r2 := _clip(_impact)
		if r2.size.x > 0.0:
			draw_rect(r2, Color(0.55, 0.45, 0.32, 0.38 * (1.0 - _impact_t / 0.9)))
	for g in _grains:
		var a := clampf(1.0 - float(g.t) / float(g.life), 0.0, 1.0)
		draw_rect(Rect2(roundf(g.x), roundf(g.y), g.s, g.s), Color(0.74, 0.64, 0.5, 0.8 * a))


func _clip(rect: Dictionary) -> Rect2:
	var full := Rect2(float(rect.x0) * TILE, float(rect.y0) * TILE, float(rect.w) * TILE, float(rect.h) * TILE)
	var win := Rect2(_cam * TILE, _view * TILE)
	return full.intersection(win)

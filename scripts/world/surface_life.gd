class_name SurfaceLife
extends Node2D
## Живая поверхность (ветка «world»): колышущаяся трава у кромки земли, бабочки над
## огородом и птицы в небе днём, светлячки ночью. Всё — процедурный пиксель-арт
## (прямоугольники и пара отрезков) в мировых координатах, без текстур и узлов-
## частиц; смена дня и ночи берётся у DayCycle.sky_dark(), сам DayCycle не трогаем.
## Узел спит, когда камера под землёй (cam.y >= 2).

const TILE := 32.0
const GARDEN_X0 := 15
const MAX_BIRDS := 3
const MAX_BUTTERFLIES := 4
const MAX_FIREFLIES := 9

const C_GRASS := Color8(0x4F, 0x7A, 0x34)
const C_GRASS_LIGHT := Color8(0x6E, 0xA0, 0x46)
const C_GRASS_DARK := Color8(0x36, 0x54, 0x23)
const C_BIRD := Color8(0x3D, 0x28, 0x18)
const WINGS := [Color8(0xCC, 0x5A, 0x3A), Color8(0xE8, 0xB3, 0x2E), Color8(0x6F, 0xE0, 0xD8), Color8(0xD8, 0x78, 0xBC), Color8(0xF4, 0xF7, 0xFA)]

var _t := 0.0
var _cam := Vector2.ZERO
var _view := Vector2(7, 14)
var _rng := RandomNumberGenerator.new()
var _birds: Array = []
var _bflies: Array = []
var _fireflies: Array = []
var _dark := 0.0
## Тестовый крючок скриншотов: >= 0 — принудительная «темнота» вместо DayCycle.
var force_dark: float = -1.0


func _ready() -> void:
	_rng.seed = 20260923
	for i in range(MAX_BIRDS):
		_birds.append({"x": _rng.randf_range(-2.0, 34.0) * TILE, "y": -_rng.randf_range(3.6, 6.2) * TILE,
				"vx": _rng.randf_range(10.0, 20.0) * (1.0 if _rng.randf() < 0.7 else -1.0), "ph": _rng.randf() * TAU})
	for i in range(MAX_BUTTERFLIES):
		_bflies.append({"cx": _rng.randf_range(16.0, 31.0) * TILE, "cy": _rng.randf_range(-0.1, 0.55) * TILE,
				"ph": _rng.randf() * TAU, "sp": _rng.randf_range(0.5, 1.0), "c": WINGS[i % WINGS.size()], "r": _rng.randf_range(18.0, 40.0)})
	for i in range(MAX_FIREFLIES):
		_fireflies.append({"cx": _rng.randf_range(15.5, 31.5) * TILE, "cy": _rng.randf_range(0.0, 0.7) * TILE,
				"ph": _rng.randf() * TAU, "sp": _rng.randf_range(0.4, 0.9)})


func update(cam: Vector2, view_w: int, view_h: int, dt: float) -> void:
	_cam = cam
	_view = Vector2(view_w, view_h)
	visible = cam.y < 2.0
	if not visible:
		return
	_t += dt
	var dc := get_node_or_null("/root/DayCycle")
	_dark = clampf(dc.sky_dark() / 0.9, 0.0, 1.0) if dc != null else 0.0
	if force_dark >= 0.0:
		_dark = force_dark
	for b in _birds:
		b.x += b.vx * dt
		var span := (_view.x + 8.0) * TILE
		var left := _cam.x * TILE - 4.0 * TILE
		if b.vx > 0.0 and b.x > left + span:
			b.x = left - 20.0
			b.y = -_rng.randf_range(3.6, 6.2) * TILE
		elif b.vx < 0.0 and b.x < left - 20.0:
			b.x = left + span
			b.y = -_rng.randf_range(3.6, 6.2) * TILE
	queue_redraw()


func _draw() -> void:
	_draw_grass()
	var day := 1.0 - _dark
	if day > 0.15:
		for b in _birds:
			_draw_bird(b, day)
		for f in _bflies:
			_draw_butterfly(f, day)
	if _dark > 0.2:
		for f in _fireflies:
			_draw_firefly(f, _dark)


## Травинки на кромке земли: у каждой клетки огорода по три пучка, качаются с
## фазой от мирового x — волна идёт по полю, а не весь ряд в такт.
func _draw_grass() -> void:
	var x0 := maxi(GARDEN_X0, int(floor(_cam.x)) - 1)
	var x1 := int(floor(_cam.x + _view.x)) + 1
	for wx in range(x0, x1 + 1):
		if wx == WorldGen.TUNNEL_X:
			continue
		for k in range(3):
			var h := _hash(wx, k)
			if h < 0.28:
				continue
			var bx := float(wx) * TILE + 4.0 + float(k) * 10.0 + h * 4.0
			var height := 5.0 + floorf(h * 4.0)
			var sway := sin(_t * 1.9 + float(wx) * 0.8 + float(k)) * 1.4 + sin(_t * 0.7 + float(wx) * 0.3) * 0.8
			var col := C_GRASS_LIGHT if h > 0.8 else C_GRASS
			var gy := TILE - 1.0
			var base := Vector2(roundf(bx), gy)
			var mid := Vector2(roundf(bx + sway * 0.45), gy - roundf(height * 0.55))
			draw_line(base, mid, C_GRASS_DARK, 1.0)
			draw_line(mid, Vector2(roundf(bx + sway), gy - height), col, 1.0)
			draw_line(base + Vector2(2, 0), Vector2(roundf(bx + 2.0 + sway * 0.7), gy - height + 1.0), col, 1.0)


func _draw_bird(b: Dictionary, day: float) -> void:
	var flap := sin(_t * 9.0 + float(b.ph)) > 0.0
	var p := Vector2(roundf(b.x), roundf(b.y + sin(_t * 0.9 + float(b.ph)) * 6.0))
	var dir := 1.0 if float(b.vx) > 0.0 else -1.0
	var c := Color(C_BIRD, day)
	var tip := Vector2(3.0 * dir, -2.0 if flap else 2.0)
	var tip2 := Vector2(-3.0 * dir, -2.0 if flap else 2.0)
	draw_line(p, p + tip, c, 1.0)
	draw_line(p, p + tip2, c, 1.0)
	draw_rect(Rect2(p.x - 1.0, p.y, 2, 1), c)


func _draw_butterfly(f: Dictionary, day: float) -> void:
	var t: float = _t * float(f.sp) + float(f.ph)
	var r: float = f.r
	var p := Vector2(float(f.cx) + sin(t) * r, float(f.cy) + sin(t * 2.0) * r * 0.25)
	p = Vector2(roundf(p.x), roundf(p.y))
	var open := absf(sin(_t * 13.0 + float(f.ph)))
	var w := 1.0 + roundf(open * 2.0)
	var c: Color = f.c
	c.a = day
	draw_rect(Rect2(p.x - w, p.y - 1.0, w, 2), c)
	draw_rect(Rect2(p.x + 1.0, p.y - 1.0, w, 2), c)
	draw_rect(Rect2(p.x, p.y, 1, 2), Color(C_BIRD, day))


func _draw_firefly(f: Dictionary, night: float) -> void:
	var t: float = _t * float(f.sp) + float(f.ph)
	var p := Vector2(float(f.cx) + sin(t * 1.3) * 22.0, float(f.cy) + cos(t * 0.9) * 10.0)
	p = Vector2(roundf(p.x), roundf(p.y))
	var b := 0.5 + 0.5 * sin(_t * 3.4 + float(f.ph) * 3.0)
	draw_rect(Rect2(p.x - 1.0, p.y - 1.0, 4, 4), Color(0.82, 0.95, 0.42, 0.10 * b * night))
	draw_rect(Rect2(p.x, p.y, 2, 2), Color(0.88, 0.98, 0.5, (0.3 + 0.7 * b) * night))


func _hash(x: int, k: int) -> float:
	var h: int = ((x * 73856093) ^ (k * 19349663 + 83492791)) & 0x7FFFFFFF
	h = (h ^ (h >> 13)) * 1274126177 & 0x7FFFFFFF
	return float(h % 1009) / 1009.0

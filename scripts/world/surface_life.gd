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
const C_LEAF := [Color8(0x6E, 0xA0, 0x46), Color8(0x8C, 0xB0, 0x4A), Color8(0xB8, 0x9A, 0x3C), Color8(0x4F, 0x7A, 0x34)]

## Растения огорода, которые качает ветер: имя спрайта (art/env/garden) -> размах верхушки, px.
## WorldView при decor_external пропускает их, рисуем здесь с наклоном (низ стоит, верх едет).
const SWAY_DECOR := {
	"tree_pine": 2.4, "tree_spruce": 2.4, "bush_fir": 1.4, "sunflower": 2.2, "tomato": 1.3,
	"lavender": 1.5, "cornflowers": 1.5, "daisies": 1.5, "hosta": 0.9,
}
const ART_SCALE := 3.0

## Дом внука (art/env/house_rich.png, 448x256, правым краем к огороду): трубы и окна в px картинки.
const HOUSE_W := 448.0
const HOUSE_H := 256.0
const CHIMNEY := Vector2(298.0, 18.0)
## Стёкла окон: x, y, w, h (px картинки) и тип света: 0 — лампа, 1 — телевизор (мерцает синим).
const WINDOWS := [
	[172, 82, 66, 66, 0], [315, 82, 73, 66, 0], [172, 182, 66, 66, 1], [283, 182, 113, 66, 0],
]
const LAMPS := [Vector2(153, 92), Vector2(287, 92), Vector2(411, 92)]
const MAX_SMOKE := 9
const MAX_LEAVES := 5
const HALO_PATH := "res://art/fx/glow_soft.png"
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

var _pane: Node2D                 # стёкла окон (обычное смешивание) — над затемнением света мира, z 11
var _glow: Node2D                 # аддитивный слой: лампы и пятна света, тоже z 11
var _halo: Texture2D
var _smoke: Array = []            # дымок трубы: {x, y, t, life, vx, s}
var _smoke_in: float = 0.0
var _leaves: Array = []           # листья на ветру: {x, y, t, ph, vx, c}
var _leaf_in: float = 0.0
var _wind_view: Node = null       # WorldView, которому мы отдали рисование растений


func _ready() -> void:
	_halo = load(HALO_PATH) if ResourceLoader.exists(HALO_PATH) else null
	_pane = Node2D.new()
	_pane.name = "HousePanes"
	_pane.z_index = 11
	_pane.draw.connect(_draw_panes)
	add_child(_pane)
	_glow = Node2D.new()
	_glow.name = "HouseGlow"
	_glow.z_index = 11
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_wind_view = get_parent().get_node_or_null("WorldView") if get_parent() != null else null
	if _wind_view != null and "decor_external" in _wind_view:
		_wind_view.decor_external = true
		_wind_view.get_node("Overlay").queue_redraw()
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


func _exit_tree() -> void:
	if _wind_view != null and is_instance_valid(_wind_view) and "decor_external" in _wind_view:
		_wind_view.decor_external = false


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
	_tick_smoke(dt)
	_tick_leaves(dt)
	queue_redraw()
	_pane.queue_redraw()
	_glow.queue_redraw()


func _draw() -> void:
	_draw_sway_decor()
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
	_draw_smoke()
	_draw_leaves(day)


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


# ---------------------------------------------------------------------------
# Ветер: растения огорода, листья, дымок трубы. Свет окон — ниже.
# ---------------------------------------------------------------------------

func _house_origin() -> Vector2:
	return Vector2(float(WorldGen.GARDEN_X_MIN * 32) - HOUSE_W, 32.0 - HOUSE_H)


func _has_house() -> bool:
	return GameState.era != "grandpa" and not GameState.house_is_indoors


## Порыв ветра: медленная волна по полю плюс редкие сильные порывы; 0 при «меньше движения».
func _wind(x: float) -> float:
	if Settings.reduce_motion:
		return 0.0
	var gust := maxf(0.0, sin(_t * 0.37 + 1.0)) * 0.55
	return sin(_t * 0.9 + x * 0.012) * 0.55 + sin(_t * 2.1 + x * 0.05) * 0.22 + gust


func _draw_sway_decor() -> void:
	var world := GameState.world_ref as WorldGen
	if world == null or _cam.y >= 1.0 or _wind_view == null:
		return
	var x0 := int(floor(_cam.x)) - 2
	var x1 := int(floor(_cam.x + _view.x)) + 2
	for wx in range(x0, x1 + 1):
		if wx < GARDEN_X0 or world.is_dug(wx, 1):
			continue
		var name := world.garden_decor_at(wx)
		var amp: float = SWAY_DECOR.get(name, 0.0)
		if amp <= 0.0:
			continue
		var tex := TileArt.garden_texture(name)
		if tex == null:
			continue
		var w := tex.get_width() / ART_SCALE
		var h := tex.get_height() / ART_SCALE
		var base := Vector2(float(wx) * TILE + TILE * 0.5, TILE * 0.5)
		var lean := _wind(base.x) * amp
		# низ стоит на месте, верхушка уезжает на lean px: сдвиг по x пропорционален высоте
		draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(-lean / h, 1.0), base))
		draw_texture_rect(tex, Rect2(-w * 0.5, -h, w, h), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _tick_smoke(dt: float) -> void:
	var on := _has_house() and not Settings.reduce_motion
	var o := _house_origin() + CHIMNEY
	var near := absf(o.x - (_cam.x + _view.x * 0.5) * TILE) < (_view.x * 0.5 + 6.0) * TILE
	_smoke_in -= dt
	if on and near and _smoke_in <= 0.0 and _smoke.size() < MAX_SMOKE:
		_smoke_in = _rng.randf_range(0.55, 0.9)
		_smoke.append({"x": o.x + _rng.randf_range(-3.0, 3.0), "y": o.y, "t": 0.0, "life": _rng.randf_range(3.2, 4.4),
				"vx": _rng.randf_range(2.0, 5.0), "s": _rng.randf_range(0.8, 1.2)})
	var i := _smoke.size() - 1
	while i >= 0:
		var p: Dictionary = _smoke[i]
		p.t += dt
		p.y -= (9.0 + 4.0 * float(p.s)) * dt
		p.x += (float(p.vx) + _wind(float(p.x)) * 9.0) * dt
		if p.t >= p.life or not on:
			_smoke.remove_at(i)
		i -= 1


func _draw_smoke() -> void:
	for p in _smoke:
		var u: float = float(p.t) / float(p.life)
		var a := sin(PI * minf(u * 1.15, 1.0)) * 0.5
		var r := roundf(1.0 + u * 3.5 * float(p.s))
		var c := Color(0.86, 0.86, 0.9, a * (1.0 - 0.45 * _dark))
		var x := roundf(p.x)
		var y := roundf(p.y)
		draw_rect(Rect2(x - r, y - r, r * 2.0, r * 2.0), c)
		draw_rect(Rect2(x - r - 1.0, y - r + 1.0, r * 2.0 + 2.0, maxf(r * 2.0 - 2.0, 1.0)), Color(c, c.a * 0.6))


func _tick_leaves(dt: float) -> void:
	var calm := Settings.reduce_motion or _dark > 0.6
	var left := _cam.x * TILE - 10.0
	_leaf_in -= dt
	if not calm and _leaf_in <= 0.0 and _leaves.size() < MAX_LEAVES:
		_leaf_in = _rng.randf_range(1.4, 3.2)
		_leaves.append({"x": left, "y": -_rng.randf_range(4.0, 70.0), "t": 0.0, "ph": _rng.randf() * TAU,
				"vx": _rng.randf_range(26.0, 44.0), "c": C_LEAF[_rng.randi() % C_LEAF.size()]})
	var right := (_cam.x + _view.x) * TILE + 14.0
	var i := _leaves.size() - 1
	while i >= 0:
		var l: Dictionary = _leaves[i]
		l.t += dt
		l.x += (float(l.vx) + _wind(float(l.x)) * 22.0) * dt
		l.y += (sin(l.t * 3.1 + l.ph) * 14.0 + 6.0) * dt
		if l.x > right or l.y > 22.0 or calm:
			_leaves.remove_at(i)
		i -= 1


func _draw_leaves(day: float) -> void:
	for l in _leaves:
		var flip := sin(float(l.t) * 7.0 + float(l.ph)) > 0.0
		var c: Color = l.c
		c.a = day
		var x := roundf(l.x)
		var y := roundf(l.y)
		draw_rect(Rect2(x, y, 2, 1) if flip else Rect2(x, y, 1, 2), c)
		draw_rect(Rect2(x + 1.0, y + 1.0, 1, 1), Color(c.r * 0.7, c.g * 0.7, c.b * 0.7, day * 0.8))



## Насколько включён вечерний свет окон: 0 днём, 1 ночью. Согласован с DayCycle через тот же _dark, что у светлячков.
func _lamp_level() -> float:
	return smoothstep(0.18, 0.55, _dark)


func _window_tint(wdef: Array) -> Color:
	return Color(0.62, 0.74, 1.0) if int(wdef[4]) == 1 else Color(1.0, 0.7, 0.3)


func _window_flicker(wdef: Array) -> float:
	if int(wdef[4]) == 1 and not Settings.reduce_motion:
		return 0.75 + 0.25 * sin(_t * 11.0) * sin(_t * 3.7 + 1.0) + 0.12 * sin(_t * 23.0)
	return 1.0


func _window_visible(r: Rect2) -> bool:
	return r.end.x >= _cam.x * TILE - 80.0 and r.position.x <= (_cam.x + _view.x) * TILE + 80.0


## Стёкла: обычное смешивание (аддитивный жёлтый на светлом стекле даёт белёсое), заливка гаснет книзу —
## потолок светлее пола. Слой лежит над затемнением света мира (z 11), поэтому окна горят и ночью.
func _draw_panes() -> void:
	if not _has_house():
		return
	var lit := _lamp_level()
	if lit <= 0.01:
		return
	var o := _house_origin()
	for wdef in WINDOWS:
		var r := Rect2(o.x + float(wdef[0]), o.y + float(wdef[1]), float(wdef[2]), float(wdef[3]))
		if not _window_visible(r):
			continue
		var col := _window_tint(wdef)
		var flick := _window_flicker(wdef)
		var rows := 6
		for k in range(rows):
			var f := 1.0 - 0.4 * float(k) / float(rows - 1)
			var ya := floorf(r.position.y + r.size.y * float(k) / float(rows))
			var yb := floorf(r.position.y + r.size.y * float(k + 1) / float(rows))
			_pane.draw_rect(Rect2(r.position.x, ya, r.size.x, yb - ya), Color(col.r, col.g, col.b, 0.5 * f * lit * flick))


## Пятна света перед окнами, на траве, и фонари у стены: мягкие аддитивные ореолы.
func _draw_glow() -> void:
	if not _has_house() or _halo == null:
		return
	var lit := _lamp_level()
	if lit <= 0.01:
		return
	var o := _house_origin()
	for wdef in WINDOWS:
		var r := Rect2(o.x + float(wdef[0]), o.y + float(wdef[1]), float(wdef[2]), float(wdef[3]))
		if not _window_visible(r):
			continue
		var col := _window_tint(wdef)
		var flick := _window_flicker(wdef)
		if r.position.y > o.y + 120.0:
			var spill := Vector2(r.size.x * 1.5, 46.0)
			_glow.draw_texture_rect(_halo, Rect2(Vector2(r.position.x + r.size.x * 0.5, 30.0) - spill * 0.5, spill), false,
					Color(col.r, col.g, col.b, 0.24 * lit * flick))
		else:
			var sz := Vector2(r.size.x * 1.4, r.size.y * 1.1)
			_glow.draw_texture_rect(_halo, Rect2(r.get_center() - sz * 0.5, sz), false, Color(col.r, col.g, col.b, 0.14 * lit * flick))
	for lp in LAMPS:
		var p: Vector2 = o + lp
		_glow.draw_rect(Rect2(p.x - 2.0, p.y - 3.0, 5, 7), Color(1.0, 0.82, 0.45, 0.55 * lit))
		_glow.draw_texture_rect(_halo, Rect2(p.x - 18.0, p.y - 16.0, 36, 36), false, Color(1.0, 0.78, 0.4, 0.28 * lit))

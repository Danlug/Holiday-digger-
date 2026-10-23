class_name AmbientFx
extends Node2D
## Лёгкие подземные эффекты по поясам (ГДД §4.2): пыль и капли, светлячки,
## блики кристаллов, искры и угли, огоньки пустоты, золотая пыль небес.
##
## Не CPUParticles2D, а пул из ~28 частиц, которые считает и рисует сам узел:
## частицы живут только в ВИДИМОЙ пустоте (клетка пуста и открыта туманом), а
## этого не умеет ни один эмиттер. Рисуются прямоугольниками по сетке в 1
## логический px — тот же «пиксель», что у тайлов. На поверхности (y < 2) узел спит:
## там живёт SurfaceLife.

const TILE := 32.0
const MAX_PARTICLES := 28
const SPAWN_PER_FRAME := 2
const TRIES := 6

## ambient пояса (data/world_layers.json -> biomes) -> [[вид, вес], ...]
const MIXES := {
	"dust_drip": [["dust", 3.0], ["drip", 1.5]],
	"drip_firefly": [["drip", 2.0], ["firefly", 2.0], ["dust", 1.0]],
	"glint": [["glint", 3.0], ["dust", 1.0], ["drip", 0.6]],
	"ember_dust": [["ember", 2.0], ["dust", 1.5], ["glint", 0.5]],
	"dust_fall": [["dust_fall", 3.0], ["dust", 1.5]],
	"ember": [["ember", 4.0], ["dust", 0.5]],
	"wisp": [["wisp", 3.0], ["glint", 1.0]],
	"gold_mote": [["gold_mote", 3.0], ["glint", 1.0]],
}

var world: WorldGen = null
var fog: FogOfWar = null
var player: Node = null

var _p: Array = []          # частицы: Dictionary {k, x, y, vx, vy, t, life, ph}
var _cam := Vector2.ZERO
var _view := Vector2(7, 14)
var _rng := RandomNumberGenerator.new()
var _mix: Array = []
var _mix_total := 0.0
var _mix_key := ""


func _ready() -> void:
	_rng.randomize()
	z_index = 0


func update(cam: Vector2, view_w: int, view_h: int, dt: float) -> void:
	_cam = cam
	_view = Vector2(view_w, view_h)
	if world == null or fog == null or player == null:
		return
	var depth := int(floor(float(player.y)))
	if depth < 2:
		if not _p.is_empty():
			_p.clear()
			queue_redraw()
		return
	_select_mix(Biomes.get_biome(Biomes.index_at(depth)).get("ambient", "dust_drip"))
	_step(dt)
	var spawned := 0
	while _p.size() < MAX_PARTICLES and spawned < SPAWN_PER_FRAME:
		_try_spawn()
		spawned += 1
	queue_redraw()


func particle_count() -> int:
	return _p.size()


func _select_mix(key: String) -> void:
	if key == _mix_key:
		return
	_mix_key = key
	_mix = MIXES.get(key, MIXES["dust_drip"])
	_mix_total = 0.0
	for e in _mix:
		_mix_total += float(e[1])


func _pick_kind() -> String:
	var r := _rng.randf() * _mix_total
	for e in _mix:
		r -= float(e[1])
		if r < 0.0:
			return String(e[0])
	return String(_mix[0][0])


func _is_empty_visible(cx: int, cy: int) -> bool:
	return cy >= 1 and world.get_tile(cx, cy) == TileTypes.Type.EMPTY \
			and fog.get_state(cx, cy) == FogOfWar.State.FULL


func _try_spawn() -> void:
	var kind := _pick_kind()
	var needs_ceiling := kind == "drip" or kind == "dust_fall"
	for _i in range(TRIES):
		var cx := int(floor(_cam.x)) + _rng.randi_range(0, int(_view.x))
		var cy := int(floor(_cam.y)) + _rng.randi_range(0, int(_view.y))
		if not _is_empty_visible(cx, cy):
			continue
		if needs_ceiling and world.get_tile(cx, cy - 1) == TileTypes.Type.EMPTY:
			continue
		var px := float(cx) * TILE + _rng.randf_range(4.0, TILE - 4.0)
		var py := float(cy) * TILE + _rng.randf_range(4.0, TILE - 4.0)
		var d := {"k": kind, "x": px, "y": py, "vx": 0.0, "vy": 0.0, "t": 0.0, "life": 4.0, "ph": _rng.randf() * TAU}
		match kind:
			"dust":
				d.vx = _rng.randf_range(-3.0, 3.0)
				d.vy = _rng.randf_range(-1.5, 3.0)
				d.life = _rng.randf_range(4.0, 8.0)
			"drip":
				d.y = float(cy) * TILE + 1.0
				d.life = 3.0
			"dust_fall":
				d.y = float(cy) * TILE + 1.0
				d.vy = 18.0
				d.vx = _rng.randf_range(-2.0, 2.0)
				d.life = 3.0
			"firefly":
				d.vx = _rng.randf_range(-6.0, 6.0)
				d.vy = _rng.randf_range(-4.0, 4.0)
				d.life = _rng.randf_range(8.0, 14.0)
			"glint":
				d.life = _rng.randf_range(0.9, 1.6)
			"ember":
				d.vy = -_rng.randf_range(8.0, 16.0)
				d.vx = _rng.randf_range(-4.0, 4.0)
				d.life = _rng.randf_range(2.5, 5.0)
			"wisp":
				d.vx = _rng.randf_range(-5.0, 5.0)
				d.vy = _rng.randf_range(-3.0, 3.0)
				d.life = _rng.randf_range(7.0, 12.0)
			"gold_mote":
				d.vy = -_rng.randf_range(2.0, 6.0)
				d.vx = _rng.randf_range(-2.0, 2.0)
				d.life = _rng.randf_range(4.0, 8.0)
		_p.append(d)
		return


func _step(dt: float) -> void:
	var i := _p.size() - 1
	while i >= 0:
		var d: Dictionary = _p[i]
		d.t += dt
		var k: String = d.k
		var dead: bool = d.t >= d.life
		match k:
			"drip":
				d.vy += 260.0 * dt
				d.y += d.vy * dt
				if world.get_tile(int(floor(d.x / TILE)), int(floor((d.y + 3.0) / TILE))) != TileTypes.Type.EMPTY:
					d.k = "splash"
					d.t = 0.0
					d.life = 0.22
					d.vy = 0.0
			"splash":
				pass
			"dust_fall":
				d.x += d.vx * dt + sin(d.t * 3.0 + d.ph) * 4.0 * dt
				d.y += d.vy * dt
			"firefly", "wisp":
				d.vx += sin(d.t * 1.7 + d.ph) * 14.0 * dt
				d.vy += cos(d.t * 1.3 + d.ph) * 10.0 * dt
				d.vx = clampf(d.vx, -9.0, 9.0)
				d.vy = clampf(d.vy, -7.0, 7.0)
				d.x += d.vx * dt
				d.y += d.vy * dt
			"ember", "gold_mote":
				d.x += (d.vx + sin(d.t * 2.5 + d.ph) * 5.0) * dt
				d.y += d.vy * dt
			"glint":
				pass
			_:
				d.x += d.vx * dt
				d.y += d.vy * dt
		# частица, ушедшая в породу или за экран, пропадает
		if not dead:
			var cx := int(floor(d.x / TILE))
			var cy := int(floor(d.y / TILE))
			if k != "splash" and world.get_tile(cx, cy) != TileTypes.Type.EMPTY:
				dead = true
			elif absf(d.x - (_cam.x + _view.x * 0.5) * TILE) > _view.x * TILE * 0.5 + 40.0 \
					or absf(d.y - (_cam.y + _view.y * 0.5) * TILE) > _view.y * TILE * 0.5 + 40.0:
				dead = true
		if dead:
			_p.remove_at(i)
		i -= 1


func _draw() -> void:
	for d in _p:
		var x := roundf(d.x)
		var y := roundf(d.y)
		var f: float = clampf(minf(d.t / 0.5, (d.life - d.t) / 0.7), 0.0, 1.0)
		match String(d.k):
			"dust":
				draw_rect(Rect2(x, y, 1, 1), Color(0.86, 0.80, 0.68, 0.5 * f))
			"dust_fall":
				draw_rect(Rect2(x, y, 1, 1), Color(0.78, 0.70, 0.52, 0.65 * f))
			"drip":
				draw_rect(Rect2(x, y, 1, 3), Color(0.62, 0.80, 0.92, 0.9))
			"splash":
				var s: float = 1.0 + float(d.t) * 9.0
				draw_rect(Rect2(x - s, y - 1.0, 1, 1), Color(0.7, 0.85, 0.95, 0.7 * (1.0 - d.t / d.life)))
				draw_rect(Rect2(x + s, y - 1.0, 1, 1), Color(0.7, 0.85, 0.95, 0.7 * (1.0 - d.t / d.life)))
			"firefly":
				var b := 0.5 + 0.5 * sin(d.t * 4.0 + d.ph)
				draw_rect(Rect2(x, y, 2, 2), Color(0.82, 0.95, 0.42, 0.25 + 0.7 * b * f))
				draw_rect(Rect2(x - 1, y - 1, 4, 4), Color(0.82, 0.95, 0.42, 0.10 * b * f))
			"glint":
				var u := sin(PI * clampf(d.t / d.life, 0.0, 1.0))
				var c := Color(0.82, 0.74, 1.0, 0.95 * u) if int(d.ph * 10.0) % 2 == 0 else Color(0.6, 0.98, 0.95, 0.95 * u)
				draw_rect(Rect2(x, y, 1, 1), c)
				if u > 0.55:
					draw_rect(Rect2(x - 1, y, 3, 1), Color(c, c.a * 0.55))
					draw_rect(Rect2(x, y - 1, 1, 3), Color(c, c.a * 0.55))
			"ember":
				var fl := 0.6 + 0.4 * sin(d.t * 14.0 + d.ph)
				var hot: bool = d.t < d.life * 0.5
				draw_rect(Rect2(x, y, 1, 1), Color(1.0, 0.72, 0.28, 0.95 * fl * f) if hot else Color(1.0, 0.36, 0.12, 0.8 * fl * f))
			"wisp":
				var p := 0.5 + 0.5 * sin(d.t * 2.2 + d.ph)
				draw_rect(Rect2(x, y, 2, 2), Color(0.72, 0.8, 1.0, (0.2 + 0.5 * p) * f))
				draw_rect(Rect2(x - 1, y - 1, 4, 4), Color(0.55, 0.62, 1.0, 0.1 * p * f))
			"gold_mote":
				var tw := 0.55 + 0.45 * sin(d.t * 5.0 + d.ph)
				draw_rect(Rect2(x, y, 1, 1), Color(1.0, 0.88, 0.42, 0.9 * tw * f))

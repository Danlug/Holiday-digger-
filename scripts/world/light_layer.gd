class_name LightLayer
extends Node2D
## Слой света мира (ветка «world-fx»): затемнение глубиной с тёплым факелом героя, ночная дымка
## у земли и ореолы светящихся руд. Только вид — ни геймплея, ни сохранений.
##
## Два узла внутри:
##  • «Veil» — один прямоугольник на экран с шейдером light_overlay: тьма растёт с глубиной, факел героя её
##    вырезает и греет, ночью у земли ложится синяя дымка. Экран не читается, пиксель за пикселем считается
##    арифметика — дёшево для gl_compatibility и телефона. Прямоугольник едет за камерой, поэтому на кадр —
##    позиция узла и пара uniform'ов, без перерисовки.
##  • «Halos» — аддитивные спрайты-ореолы у светящихся руд (список даёт WorldView.glow_cells(), он живёт по
##    версии мира, как кэш окна). Узел стоит в мировых координатах и сам едет с камерой, перерисовывается
##    только когда изменился список клеток или раз в 0,1 с ради мерцания.
##
## «Меньше движения» (Settings.reduce_motion) гасит мерцание факела, пульс ореолов и блёстки.

const TILE := 32
const CONFIG_PATH := "res://data/fx_light.json"
const SHADER_PATH := "res://shaders/light_overlay.gdshader"
const HALO_PATH := "res://art/fx/glow_soft.png"
const HALO_PX := 96.0            # сторона текстуры ореола = 3 клетки при r = 1.5
const MARGIN := 16.0             # запас вокруг экрана под тряску мира
const SURFACE_Y := 32.0          # мировой y линии земли: верх первой земляной клетки

## Тип клетки -> вид свечения (индекс в GLOW_KEYS). WorldView кладёт его в слот пула при перекраске.
const GLOW_TILES := {
	TileTypes.Type.URANIUM_ORE: 1,
	TileTypes.Type.GEOCRYSTAL: 2,
	TileTypes.Type.HELLSTONE: 3,
	TileTypes.Type.DIVINE_HEART: 4,
	TileTypes.Type.UNIVERSALIUM: 5,
	TileTypes.Type.ANGEL_STONE: 6,
	TileTypes.Type.DARK_MATTER: 7,
	TileTypes.Type.DIAMOND: 8,
	TileTypes.Type.RUBY: 9,
	TileTypes.Type.EMERALD: 10,
}
const GLOW_TYPE_OF := [0, TileTypes.Type.URANIUM_ORE, TileTypes.Type.GEOCRYSTAL, TileTypes.Type.HELLSTONE,
		TileTypes.Type.DIVINE_HEART, TileTypes.Type.UNIVERSALIUM, TileTypes.Type.ANGEL_STONE, TileTypes.Type.DARK_MATTER,
		TileTypes.Type.DIAMOND, TileTypes.Type.RUBY, TileTypes.Type.EMERALD]
const GLOW_KEYS := ["", "uranium_ore", "geocrystal", "hellstone", "divine_heart", "universalium",
		"angel_stone", "dark_matter", "diamond", "ruby", "emerald"]

static var _cfg: Dictionary = {}
static var _cfg_loaded: bool = false
static var _defs: Array = []     # по индексу вида: {color: Color, r, k, pulse, twinkle}

var world_view: Node = null
var player: Node = null

var _veil: Node2D
var _halos: Node2D
var _mat: ShaderMaterial
var _halo_tex: Texture2D
var _t: float = 0.0
var _dark: float = 0.0           # сглаженное затемнение
var _dark_color: Color = Color(0.07, 0.04, 0.03)
var _torch_color: Color = Color(1.0, 0.72, 0.4)
var _torch_r_cells: float = 4.0
var _radius_timer: float = 0.0
var _halo_ver: int = -1
var _halo_tick: float = 0.0
var _halo_count: int = 0
var _inited: bool = false
## Тест и скриншоты: >= 0 — принудительная ночь вместо DayCycle (0..1).
var force_night: float = -1.0
## Отключить слой целиком (сравнения «до/после» и замеры).
var enabled: bool = true


static func config() -> Dictionary:
	if not _cfg_loaded:
		_cfg_loaded = true
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f != null:
			var raw = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(raw) == TYPE_DICTIONARY:
				_cfg = raw
		_defs = [{}]
		var g: Dictionary = _cfg.get("glow", {})
		for i in range(1, GLOW_KEYS.size()):
			var d: Dictionary = g.get(GLOW_KEYS[i], {})
			_defs.append({
				"color": Color.html(String(d.get("color", "FFFFFF"))),
				"r": float(d.get("r", 1.5)),
				"k": float(d.get("k", 0.4)),
				"pulse": float(d.get("pulse", 0.1)),
				"twinkle": int(d.get("twinkle", 0)),
			})
	return _cfg


## Затемнение за пределами факела на глубине depth (клеток): кусочно-линейная кривая из конфига, сглаженная.
static func dark_for_depth(depth: float) -> float:
	var stops: Array = (config().get("depth_dark", {}) as Dictionary).get("stops", [])
	if stops.is_empty():
		return 0.0
	if depth <= float(stops[0][0]):
		return float(stops[0][1])
	for i in range(1, stops.size()):
		var d1 := float(stops[i][0])
		if depth <= d1:
			var d0 := float(stops[i - 1][0])
			var t := smoothstep(0.0, 1.0, (depth - d0) / maxf(d1 - d0, 0.001))
			return lerpf(float(stops[i - 1][1]), float(stops[i][1]), t)
	return float(stops[stops.size() - 1][1])


## Цвет тьмы и факела на глубине y: плавно между соседними поясами (Biomes.blend_at).
static func belt_colors(y: float) -> Dictionary:
	var belts: Dictionary = config().get("belts", {})
	var bl := Biomes.blend_at(y)
	var a: Dictionary = belts.get(String(Biomes.get_biome(int(bl.a)).get("id", "")), {})
	var b: Dictionary = belts.get(String(Biomes.get_biome(int(bl.b)).get("id", "")), {})
	var t := float(bl.t)
	return {
		"dark": Color.html(String(a.get("dark", "120A06"))).lerp(Color.html(String(b.get("dark", "120A06"))), t),
		"torch": Color.html(String(a.get("torch", "FFB868"))).lerp(Color.html(String(b.get("torch", "FFB868"))), t),
	}


static func glow_def(kind: int) -> Dictionary:
	config()
	return _defs[kind] if kind > 0 and kind < _defs.size() else {}


func _ready() -> void:
	name = "LightLayer"
	config()
	_halo_tex = load(HALO_PATH) if ResourceLoader.exists(HALO_PATH) else null

	_veil = Node2D.new()
	_veil.name = "Veil"
	_veil.z_index = 10    # над героем и монстрами, под частицами (FxService, z 20)
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_veil.material = _mat
	_veil.draw.connect(_draw_veil)
	add_child(_veil)

	_halos = Node2D.new()
	_halos.name = "Halos"
	_halos.z_index = 11
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halos.material = add
	_halos.draw.connect(_draw_halos)
	add_child(_halos)
	get_viewport().size_changed.connect(_veil.queue_redraw)
	_veil.queue_redraw()


func _draw_veil() -> void:
	var vs := get_viewport_rect().size + Vector2.ONE * (MARGIN * 2.0)
	_veil.draw_rect(Rect2(Vector2.ZERO, vs), Color.WHITE)


func _process(dt: float) -> void:
	var on := enabled and player != null and not GameState.house_is_indoors
	_veil.visible = on
	_halos.visible = on
	if not on:
		return
	_t += dt
	var parent := get_parent() as Node2D
	if parent == null:
		return
	var cam_px := -parent.position
	var origin := (cam_px - Vector2.ONE * MARGIN).floor()
	if not _inited or _veil.position != origin:
		_veil.position = origin
	var hero := Vector2(float(player.x), float(player.y)) * TILE
	var depth: float = float(player.y)

	# Цели: затемнение и цвета по глубине героя; сглаживаем, чтобы телепорт и падение не дёргали кадр.
	var target_dark := dark_for_depth(depth)
	var cols := belt_colors(depth)
	var k := 1.0 if not _inited else 1.0 - exp(-4.0 * dt)
	_dark = lerpf(_dark, target_dark, k)
	_dark_color = _dark_color.lerp(cols.dark, k)
	_torch_color = _torch_color.lerp(cols.torch, k)

	_radius_timer -= dt
	if _radius_timer <= 0.0 or not _inited:
		_radius_timer = 0.5
		var tc: Dictionary = config().get("torch", {})
		var res_r := FogOfWar.vision_radius(GameState.get_vision_resource_radius())
		_torch_r_cells = maxf(float(tc.get("radius_min_cells", 3.2)), res_r + float(tc.get("radius_extra_cells", 1.6)))
	var tc2: Dictionary = config().get("torch", {})
	var flick := 1.0
	if not Settings.reduce_motion:
		flick += float(tc2.get("flicker", 0.06)) * (sin(_t * 9.1) * 0.5 + sin(_t * 15.7 + 1.3) * 0.3 + sin(_t * 3.3) * 0.2)
	var underground := smoothstep(1.5, 8.0, depth)
	var night := force_night if force_night >= 0.0 else _night_phase()
	var nc: Dictionary = config().get("night", {})

	_mat.set_shader_parameter("origin", origin)
	_mat.set_shader_parameter("hero", hero)
	_mat.set_shader_parameter("torch_r", _torch_r_cells * TILE * flick)
	_mat.set_shader_parameter("torch_in", float(tc2.get("inner_cells", 1.1)) * TILE)
	_mat.set_shader_parameter("depth_dark", _dark)
	_mat.set_shader_parameter("dark_color", Vector3(_dark_color.r, _dark_color.g, _dark_color.b))
	_mat.set_shader_parameter("torch_color", Vector3(_torch_color.r, _torch_color.g, _torch_color.b))
	_mat.set_shader_parameter("torch_k", float(tc2.get("warm_k", 0.13)) * maxf(underground, night))
	_mat.set_shader_parameter("night_k", night * float(nc.get("max_alpha", 0.46)))
	var ncol := Color.html(String(nc.get("color", "0A1230")))
	_mat.set_shader_parameter("night_color", Vector3(ncol.r, ncol.g, ncol.b))
	_mat.set_shader_parameter("night_up", float(nc.get("up_px", 150)))
	_mat.set_shader_parameter("night_down", float(nc.get("down_px", 420)))
	_mat.set_shader_parameter("surface_y", SURFACE_Y)
	_inited = true

	_tick_halos(dt)


func _night_phase() -> float:
	var dc := get_node_or_null("/root/DayCycle")
	return clampf(dc.sky_dark() / 0.9, 0.0, 1.0) if dc != null else 0.0


func _tick_halos(dt: float) -> void:
	if world_view == null or not world_view.has_method("glow_cells"):
		return
	var cells: Array = world_view.glow_cells()
	var ver: int = world_view.glow_version
	_halo_count = cells.size()
	if cells.is_empty():
		if _halo_ver != ver:
			_halo_ver = ver
			_halos.queue_redraw()
		return
	_halo_tick -= dt
	if ver != _halo_ver or (_halo_tick <= 0.0 and not Settings.reduce_motion):
		_halo_ver = ver
		_halo_tick = 0.1
		_halos.queue_redraw()


func halo_count() -> int:
	return _halo_count


func _draw_halos() -> void:
	if world_view == null or not world_view.has_method("glow_cells"):
		return
	var calm: bool = Settings.reduce_motion
	# Чем глубже и темнее, тем ярче ореол читается; у поверхности (редкие самоцветы) он вполовину тише.
	var boost := 0.62 + 0.85 * _dark
	for c: Vector3i in world_view.glow_cells():
		var d: Dictionary = glow_def(c.z)
		if d.is_empty():
			continue
		var ph := float(((c.x * 73856093) ^ (c.y * 19349663)) & 0xFF) / 40.0
		var pulse := 1.0 if calm else 1.0 + float(d.pulse) * (sin(_t * 2.3 + ph) * 0.7 + sin(_t * 5.9 + ph * 2.0) * 0.3)
		var col: Color = d.color
		col.a = clampf(float(d.k) * pulse * boost, 0.0, 1.0)
		var s: float = float(d.r) * 2.0 * TILE
		var center := Vector2((c.x + 0.5) * TILE, (c.y + 0.5) * TILE)
		if _halo_tex != null:
			_halos.draw_texture_rect(_halo_tex, Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s)), false, col)
		# Сам светящийся камень не тускнеет вместе со стеной: слегка подсвечиваем его тайл поверх тьмы.
		if float(d.k) >= 0.4:
			_relight(center, GLOW_TYPE_OF[c.z], c.x, c.y, 0.7)
		if not calm and int(d.twinkle) > 0:
			_draw_twinkle(center, ph, col)
	# Лава светится сама: тайл возвращает яркость, которую снимает затемнение.
	if world_view.has_method("lava_cells"):
		var tick := TileArt.lava_tick()
		for lc: Vector2i in world_view.lava_cells():
			var tex := TileArt.lava_texture(lc.x, lc.y, tick)
			if tex == null:
				continue
			var cc := Vector2((lc.x + 0.5) * TILE, (lc.y + 0.5) * TILE)
			var a := _veil_alpha_at(cc)
			if a > 0.01:
				_halos.draw_texture_rect(tex, Rect2(cc - Vector2(TILE, TILE) * 0.5, Vector2(TILE, TILE)), false, Color(1, 1, 1, a))


## Вернуть клетке часть яркости, снятой затемнением (additive поверх тьмы).
func _relight(center: Vector2, tile_type: int, cx: int, cy: int, k: float) -> void:
	var tex := TileArt.texture_for(tile_type, cx, cy)
	if tex == null:
		return
	var a := _veil_alpha_at(center) * k
	if a > 0.01:
		_halos.draw_texture_rect(tex, Rect2(center - Vector2(TILE, TILE) * 0.5, Vector2(TILE, TILE)), false, Color(1, 1, 1, a))


## Какую долю яркости сейчас съедает затемнение в этой точке мира (повторяет формулу шейдера).
func _veil_alpha_at(p: Vector2) -> float:
	var tc: Dictionary = config().get("torch", {})
	var hero := Vector2(float(player.x), float(player.y)) * TILE
	var lit := 1.0 - smoothstep(float(tc.get("inner_cells", 1.1)) * TILE, _torch_r_cells * TILE, p.distance_to(hero))
	return _dark * smoothstep(SURFACE_Y, SURFACE_Y + 120.0, p.y) * (1.0 - 0.92 * lit)


## Блёстки на гранях: раз в пару секунд на клетке вспыхивает крестик из пикселей и гаснет.
func _draw_twinkle(center: Vector2, ph: float, col: Color) -> void:
	var u := fposmod(_t * 0.55 + ph * 0.37, 1.0)
	if u > 0.22:
		return
	var f := sin(PI * u / 0.22)
	var hx := int(ph * 97.0) % 13 - 6
	var hy := int(ph * 57.0) % 11 - 5
	var p := (center + Vector2(hx, hy)).floor()
	var c := Color(1.0, 1.0, 1.0, 0.95 * f)
	_halos.draw_rect(Rect2(p, Vector2.ONE), c)
	if f > 0.5:
		var arm := Color(col.r, col.g, col.b, 0.8 * f)
		_halos.draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), arm)
		_halos.draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), arm)

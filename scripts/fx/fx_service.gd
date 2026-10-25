class_name FxService
extends Node2D
## Сервис визуальных эффектов: частицы из пула CPUParticles2D, всплывающие
## числа/иконки, тряска мира, вспышка экрана, летящие в HUD иконки. Узел
## состоит в группе Fx.GROUP; живёт в мировой сцене (ViewRoot), поэтому
## мировые пиксели Player.global_position — его родные координаты.
##
## Экономия для веба и слабых телефонов: фиксированный пул эмиттеров,
## общий потолок живых частиц, в вебе — урезанная плотность. Тряска двигает
## canvas_transform вьюпорта: она сдвигает мир, но не HUD (у него свой
## CanvasLayer), и не мешает main.gd, который сам задаёт view_root.position.
##
## «Меньше движения» (Settings.reduce_motion) гасит тряску и приглушает вспышки.

signal flier_landed(target: Vector2, index: int, total: int)

const LAYER_FLASH := 58
const LAYER_FLY := 59
const FLY_SIZE := 14.0
const POPUP_RISE := 24.0

const C_SOIL := [Color("3E2A1A"), Color("6B4428"), Color("8F6238"), Color("B4854E")]
const C_STONE := [Color("3A3A44"), Color("5C5C68"), Color("7E7E8C")]
const C_GOLD := [Color("E8B32E"), Color("FFE066"), Color("FFFFFF")]
const C_DUST := [Color("8F8A80"), Color("B8B2A4"), Color("D8D2C4")]
const C_RED := [Color("C21E3A"), Color("FF5570"), Color("FFFFFF")]
const C_LEVEL := [Color("FFE066"), Color("FFFFFF"), Color("E8B32E"), Color("6FE0D8")]
const C_HEAL := [Color("4DE094"), Color("1C8A52"), Color("CFFFE4")]
const C_FIRE := [Color("FFE066"), Color("E89A5E"), Color("C2703A"), Color("C21E3A")]
const C_SPARK := [Color("FFE066"), Color("FFFFFF"), Color("FFB34D")]

## Виды частиц. n — число частиц при amount=1; tex — рисунок частицы;
## curve — как меняется размер (shrink/grow/none); fade — гаснуть к концу.
const C_SMOKE := [Color("3A3633"), Color("5A5550"), Color("7C766E")]
const C_SHARD := [Color("5A2438"), Color("8E3A4E"), Color("C21E3A"), Color("FF5570"), Color("FFD0D8")]
const C_GLINT := [Color("FFFFFF"), Color("FFF2B0"), Color("BDF6FF")]

## Виды частиц. n — число частиц при amount=1; tex — рисунок частицы; curve — как меняется размер
## (shrink/grow/none); fade — гаснуть к концу; spin — вращение в град/с (±); add — аддитивное смешивание
## (искры и блёстки светятся, а не красят). Порода и осколки — «кусочки» (chip) с гравитацией и вращением,
## пыль — мягкие облачка (puff), искры и блёстки — лучики (glint).
const PRESETS := {
	"dig_dirt": {"n": 8, "life": 0.55, "vmin": 35.0, "vmax": 95.0, "spread": 75.0, "dir": Vector2(0, -1), "grav": 430.0,
		"smin": 0.8, "smax": 1.4, "tex": "chip", "cols": C_SOIL, "curve": "shrink", "fade": false, "spin": 520.0},
	"dig_stone": {"n": 8, "life": 0.5, "vmin": 40.0, "vmax": 110.0, "spread": 80.0, "dir": Vector2(0, -1), "grav": 460.0,
		"smin": 0.8, "smax": 1.4, "tex": "chip", "cols": C_STONE, "curve": "shrink", "fade": false, "spin": 640.0},
	"dig_ore": {"n": 9, "life": 0.55, "vmin": 40.0, "vmax": 115.0, "spread": 85.0, "dir": Vector2(0, -1), "grav": 440.0,
		"smin": 0.8, "smax": 1.5, "tex": "chip", "cols": C_STONE, "curve": "shrink", "fade": false, "spin": 600.0},
	"dig_gold": {"n": 11, "life": 0.65, "vmin": 40.0, "vmax": 125.0, "spread": 90.0, "dir": Vector2(0, -1), "grav": 400.0,
		"smin": 0.5, "smax": 1.0, "tex": "chip", "cols": C_GOLD, "curve": "shrink", "fade": false, "spin": 560.0},
	"dig_puff": {"n": 5, "life": 0.6, "vmin": 6.0, "vmax": 24.0, "spread": 100.0, "dir": Vector2(0, -1), "grav": -10.0,
		"smin": 0.7, "smax": 1.2, "tex": "puff", "cols": C_DUST, "curve": "grow", "fade": true, "damp": 24.0},
	"ore_glint": {"n": 5, "life": 0.42, "vmin": 25.0, "vmax": 70.0, "spread": 180.0, "dir": Vector2(0, -1), "grav": 0.0,
		"smin": 0.7, "smax": 1.1, "tex": "glint", "cols": C_GLINT, "curve": "shrink", "fade": true, "damp": 90.0, "add": true},
	"pickup_glint": {"n": 6, "life": 0.55, "vmin": 12.0, "vmax": 46.0, "spread": 180.0, "dir": Vector2(0, -1), "grav": -30.0,
		"smin": 0.6, "smax": 1.0, "tex": "glint", "cols": C_GLINT, "curve": "shrink", "fade": true, "damp": 40.0, "add": true},
	"spark": {"n": 8, "life": 0.32, "vmin": 60.0, "vmax": 150.0, "spread": 180.0, "dir": Vector2(0, -1), "grav": 0.0,
		"smin": 0.7, "smax": 1.2, "tex": "px", "cols": C_SPARK, "curve": "shrink", "fade": false, "damp": 120.0, "add": true},
	"poof": {"n": 7, "life": 0.5, "vmin": 8.0, "vmax": 32.0, "spread": 180.0, "dir": Vector2(0, -1), "grav": -14.0,
		"smin": 0.6, "smax": 1.2, "tex": "puff", "cols": C_DUST, "curve": "grow", "fade": true, "damp": 30.0},
	"land_dust_l": {"n": 5, "life": 0.45, "vmin": 22.0, "vmax": 58.0, "spread": 22.0, "dir": Vector2(-1, -0.18), "grav": -6.0,
		"smin": 0.7, "smax": 1.2, "tex": "puff", "cols": C_DUST, "curve": "grow", "fade": true, "damp": 70.0},
	"land_dust_r": {"n": 5, "life": 0.45, "vmin": 22.0, "vmax": 58.0, "spread": 22.0, "dir": Vector2(1, -0.18), "grav": -6.0,
		"smin": 0.7, "smax": 1.2, "tex": "puff", "cols": C_DUST, "curve": "grow", "fade": true, "damp": 70.0},
	"jump_puff": {"n": 4, "life": 0.38, "vmin": 10.0, "vmax": 30.0, "spread": 160.0, "dir": Vector2(0, -0.4), "grav": 0.0,
		"smin": 0.5, "smax": 0.9, "tex": "puff", "cols": C_DUST, "curve": "grow", "fade": true, "damp": 60.0},
	"rock_fall": {"n": 7, "life": 0.9, "vmin": 6.0, "vmax": 40.0, "spread": 40.0, "dir": Vector2(0, 1), "grav": 520.0,
		"smin": 0.8, "smax": 1.6, "tex": "chip", "cols": C_STONE, "curve": "none", "fade": false, "spin": 480.0},
	"hit_enemy": {"n": 9, "life": 0.3, "vmin": 70.0, "vmax": 150.0, "spread": 180.0, "dir": Vector2(0, -1), "grav": 220.0,
		"smin": 0.8, "smax": 1.3, "tex": "px", "cols": C_RED, "curve": "shrink", "fade": false, "add": true},
	"enemy_die": {"n": 16, "life": 0.7, "vmin": 40.0, "vmax": 130.0, "spread": 180.0, "dir": Vector2(0, -1), "grav": 160.0,
		"smin": 0.9, "smax": 1.7, "tex": "chip", "cols": C_SHARD, "curve": "shrink", "fade": true, "damp": 50.0, "spin": 500.0},
	"hit_flash": {"n": 2, "life": 0.14, "vmin": 0.0, "vmax": 5.0, "spread": 180.0, "dir": Vector2(0, -1), "grav": 0.0,
		"smin": 1.7, "smax": 2.3, "tex": "glint", "cols": [Color.WHITE, Color("FFE9B0")], "curve": "shrink", "fade": true, "add": true},
	"die_smoke": {"n": 6, "life": 0.8, "vmin": 8.0, "vmax": 28.0, "spread": 120.0, "dir": Vector2(0, -1), "grav": -26.0,
		"smin": 0.8, "smax": 1.4, "tex": "puff", "cols": C_SMOKE, "curve": "grow", "fade": true, "damp": 26.0},
	"levelup": {"n": 28, "life": 1.1, "vmin": 50.0, "vmax": 160.0, "spread": 70.0, "dir": Vector2(0, -1), "grav": 150.0,
		"smin": 0.5, "smax": 1.1, "tex": "dia", "cols": C_LEVEL, "curve": "shrink", "fade": true, "damp": 40.0},
	"coins": {"n": 8, "life": 0.85, "vmin": 70.0, "vmax": 140.0, "spread": 55.0, "dir": Vector2(0, -1), "grav": 400.0,
		"smin": 0.2, "smax": 0.26, "tex": "coin", "cols": [Color.WHITE], "curve": "none", "fade": true},
	"heal": {"n": 10, "life": 0.95, "vmin": 10.0, "vmax": 36.0, "spread": 45.0, "dir": Vector2(0, -1), "grav": -36.0,
		"smin": 0.6, "smax": 1.0, "tex": "plus", "cols": C_HEAL, "curve": "none", "fade": true},
	"fire": {"n": 14, "life": 0.6, "vmin": 15.0, "vmax": 48.0, "spread": 28.0, "dir": Vector2(0, -1), "grav": -90.0,
		"smin": 0.6, "smax": 1.3, "tex": "dot", "cols": C_FIRE, "curve": "shrink", "fade": false, "add": true},
}

const TEX_PATTERNS := {
	"px": ["##", "##"],
	"dot": [".##.", "####", "####", ".##."],
	"plus": ["..#..", "..#..", "#####", "..#..", "..#.."],
	"dia": ["..#..", ".###.", "#####", ".###.", "..#.."],
	"chip": [".##", "###", "##."],
	"puff": [".##.", "####", "####", ".##."],
	"glint": ["..#..", "..#..", "##.##", "..#..", "..#.."],
}

var max_particles: int = 220
var density: float = 1.0
var max_fliers: int = 24
var max_popups: int = 10
var stats := {"bursts": 0, "skipped": 0, "popups": 0, "fliers": 0}

var _emitters: Array[CPUParticles2D] = []
var _busy_until: Array[int] = []
var _emit_n: Array[int] = []
var _tex: Dictionary = {}
var _curves: Dictionary = {}
var _fade_ramp: Gradient
var _ramps: Dictionary = {}
var _palette_cache: Dictionary = {}
var _mat_add: CanvasItemMaterial

var _popups: Array[Node2D] = []
var _popup_free: Array[Node2D] = []
var _popup_tween: Dictionary = {}

var _flash_layer: CanvasLayer
var _flash: ColorRect
var _flash_tween: Tween
var _fly_layer: CanvasLayer
var _fliers_active: int = 0
var _coin_tex: Texture2D

## Магнит добычи: блёстки летят от выкопанной клетки к герою, разгоняясь (как будто тянет). Спрайты — пул
## в этом же узле (мировые координаты); точку героя отдаёт magnet_target (его выставляет JuiceDirector).
const MAG_MAX := 10
var magnet_target: Callable = Callable()
var _mag: Array = []
var _mag_free: Array = []

var _shake_amp: float = 0.0
var _shake_dur: float = 0.0
var _shake_t: float = 0.0
var _shake_applied: bool = false


func _ready() -> void:
	add_to_group(Fx.GROUP)
	z_index = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	max_particles = int(Juice.num("fx.max_particles", 220.0))
	max_fliers = int(Juice.num("fx.max_fliers", 24.0))
	max_popups = int(Juice.num("fx.max_popups", 10.0))
	if OS.has_feature("web"):
		density = Juice.num("fx.web_density", 0.7)
	_build_textures()
	_mat_add = CanvasItemMaterial.new()
	_mat_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_build_pool(int(Juice.num("fx.emitters", 18.0)))

	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = LAYER_FLASH
	add_child(_flash_layer)
	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	_flash_layer.add_child(_flash)
	_fly_layer = CanvasLayer.new()
	_fly_layer.layer = LAYER_FLY
	add_child(_fly_layer)


func _exit_tree() -> void:
	_reset_shake()


# ---------------------------------------------------------------------------
# Частицы
# ---------------------------------------------------------------------------

func _build_textures() -> void:
	for key in TEX_PATTERNS:
		var rows: Array = TEX_PATTERNS[key]
		var h := rows.size()
		var w := String(rows[0]).length()
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				img.set_pixel(x, y, Color.WHITE if String(rows[y])[x] == "#" else Color(1, 1, 1, 0))
		_tex[key] = ImageTexture.create_from_image(img)
	if ResourceLoader.exists("res://art/ui/icon_coin.png"):
		_coin_tex = load("res://art/ui/icon_coin.png")
		_tex["coin"] = _coin_tex
	else:
		_tex["coin"] = _tex["dia"]
	_curves["shrink"] = _make_curve([Vector2(0, 1.0), Vector2(1, 0.15)])
	_curves["grow"] = _make_curve([Vector2(0, 0.45), Vector2(0.35, 1.0), Vector2(1, 1.5)])
	_fade_ramp = Gradient.new()
	_fade_ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	_fade_ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])


func _make_curve(pts: Array) -> Curve:
	var c := Curve.new()
	for p in pts:
		c.add_point(p)
	return c


func _build_pool(count: int) -> void:
	for i in count:
		var e := CPUParticles2D.new()
		e.emitting = false
		e.one_shot = true
		e.explosiveness = 1.0
		# local_coords: частицы едут вместе с миром, когда камера следует за героем.
		e.local_coords = true
		e.amount = 8
		e.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(e)
		_emitters.append(e)
		_busy_until.append(0)
		_emit_n.append(0)


func active_particles() -> int:
	var now := Time.get_ticks_msec()
	var s := 0
	for i in _emitters.size():
		if _busy_until[i] > now:
			s += _emit_n[i]
	return s


func pool_size() -> int:
	return _emitters.size()


func has_kind(kind: String) -> bool:
	return PRESETS.has(kind)


func burst(kind: String, pos: Vector2, amount: float = 1.0, tint: Color = Color(0, 0, 0, 0)) -> void:
	var pr: Dictionary = PRESETS.get(kind, {})
	if pr.is_empty() or _emitters.is_empty():
		return
	var calm := Settings.reduce_motion and kind != "levelup" and kind != "heal" and kind != "coins"
	var n := int(round(float(pr["n"]) * amount * density * (0.5 if calm else 1.0)))
	n = clampi(n, 0, 60)
	if n < 1:
		return
	var now := Time.get_ticks_msec()
	var room := max_particles - active_particles()
	if room < 3:
		stats["skipped"] += 1
		return
	n = mini(n, room)

	var idx := -1
	var oldest := 0
	for i in _emitters.size():
		if _busy_until[i] <= now:
			idx = i
			break
		if _busy_until[i] < _busy_until[oldest]:
			oldest = i
	if idx < 0:
		idx = oldest
	var e := _emitters[idx]
	e.emitting = false
	e.position = pos
	e.amount = n
	e.lifetime = float(pr["life"])
	e.direction = pr["dir"]
	e.spread = float(pr["spread"])
	e.gravity = Vector2(0, float(pr["grav"]))
	e.initial_velocity_min = float(pr["vmin"])
	e.initial_velocity_max = float(pr["vmax"])
	e.scale_amount_min = float(pr["smin"])
	e.scale_amount_max = float(pr["smax"])
	e.linear_accel_min = 0.0
	e.linear_accel_max = 0.0
	var damp := float(pr.get("damp", 0.0))
	e.damping_min = damp * 0.6
	e.damping_max = damp
	e.lifetime_randomness = 0.3
	var spin := float(pr.get("spin", 0.0))
	e.angle_min = -180.0 if spin > 0.0 else 0.0
	e.angle_max = 180.0 if spin > 0.0 else 0.0
	e.angular_velocity_min = -spin if not calm else 0.0
	e.angular_velocity_max = spin if not calm else 0.0
	e.material = _mat_add if bool(pr.get("add", false)) else null
	e.texture = _tex[pr["tex"]]
	e.scale_amount_curve = _curves.get(pr["curve"])
	e.color_ramp = _fade_ramp if pr["fade"] else null
	e.color_initial_ramp = _ramp_for(kind, pr["cols"], tint)
	e.restart()
	e.emitting = true
	_busy_until[idx] = now + int(float(pr["life"]) * 1000.0 * 1.3)
	_emit_n[idx] = n
	stats["bursts"] += 1


func _ramp_for(kind: String, cols: Array, tint: Color) -> Gradient:
	var key := kind
	var colors: Array = cols
	if tint.a > 0.0:
		if kind == "ore_glint" or kind == "pickup_glint":
			# блёстки руды: её цвет, светлее и белый
			colors = [tint.lightened(0.25), tint.lightened(0.6), Color.WHITE]
		else:
			# Руда: серые осколки породы плюс вкрапления её цвета.
			colors = [C_STONE[1], C_STONE[2], tint, tint, tint.lightened(0.35)]
		key = ""
	elif _ramps.has(key):
		return _ramps[key]
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	var cs := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / float(colors.size()))
		cs.append(colors[i])
	g.offsets = offs
	g.colors = cs
	if key != "":
		_ramps[key] = g
	return g


## Цвет вкраплений руды — по самым «непохожим на породу» пикселям её тайла.
func tile_accent(tile: int) -> Color:
	var pal := tile_palette(tile)
	return pal[2] if pal.size() >= 3 else Color(0, 0, 0, 0)


func tile_palette(tile: int) -> Array:
	if _palette_cache.has(tile):
		return _palette_cache[tile]
	var out: Array = []
	var tex := TileArt.texture_for(tile, 0, 0)
	if tex != null:
		var img := tex.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			out = _palette_of(img)
	_palette_cache[tile] = out
	return out


func _palette_of(img: Image) -> Array:
	var samples: Array = []
	var step := 3
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				samples.append(c)
	if samples.size() < 9:
		return []
	var rs: Array = samples.map(func(c: Color) -> float: return c.r)
	var gs: Array = samples.map(func(c: Color) -> float: return c.g)
	var bs: Array = samples.map(func(c: Color) -> float: return c.b)
	rs.sort()
	gs.sort()
	bs.sort()
	var mid := samples.size() / 2
	var med := Color(rs[mid], gs[mid], bs[mid])
	var scored: Array = []
	for c in samples:
		var d: float = (c.r - med.r) * (c.r - med.r) + (c.g - med.g) * (c.g - med.g) + (c.b - med.b) * (c.b - med.b)
		scored.append([d, c])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var top: Array = scored.slice(0, maxi(9, scored.size() / 12))
	top.sort_custom(func(a: Array, b: Array) -> bool: return a[1].get_luminance() < b[1].get_luminance())
	var third := top.size() / 3
	return [med, _avg(top.slice(0, third)), _avg(top.slice(third, third * 2)), _avg(top.slice(third * 2))]


func _avg(items: Array) -> Color:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	for it in items:
		var c: Color = it[1]
		r += c.r
		g += c.g
		b += c.b
	var k := float(maxi(items.size(), 1))
	return Color(r / k, g / k, b / k)


# ---------------------------------------------------------------------------
# Магнит добычи
# ---------------------------------------------------------------------------

func active_magnets() -> int:
	return _mag.size()


## Пускает count блёсток цвета tint из мировой точки from к герою. «Меньше движения» и пустой магнит_target — ничего.
func magnet(from: Vector2, tint: Color, count: int = 3) -> void:
	if Settings.reduce_motion or not magnet_target.is_valid() or _emitters.is_empty():
		return
	for i in range(count):
		if _mag.size() >= MAG_MAX:
			return
		var sp: Sprite2D
		if not _mag_free.is_empty():
			sp = _mag_free.pop_back()
		else:
			sp = Sprite2D.new()
			sp.texture = _tex["dia"]
			sp.material = _mat_add
			add_child(sp)
		sp.visible = false
		sp.modulate = tint
		_mag.append({"s": sp, "from": from + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)),
				"t": 0.0, "dur": randf_range(0.34, 0.5), "delay": float(i) * 0.05, "bend": randf_range(-14.0, 14.0),
				"last": i == count - 1, "tint": tint})


func _tick_magnet(dt: float) -> void:
	var target: Vector2 = magnet_target.call() if magnet_target.is_valid() else Vector2.ZERO
	var i := _mag.size() - 1
	while i >= 0:
		var m: Dictionary = _mag[i]
		var sp: Sprite2D = m.s
		m.delay = float(m.delay) - dt
		if float(m.delay) > 0.0:
			i -= 1
			continue
		m.t = float(m.t) + dt / float(m.dur)
		var u := clampf(float(m.t), 0.0, 1.0)
		var e := u * u * (1.0 + 0.6 * (1.0 - u))     # медленный старт, рывок к герою
		var from: Vector2 = m.from
		var dir := target - from
		var side := dir.orthogonal().normalized() * float(m.bend) * sin(PI * u)
		sp.position = (from.lerp(target, e) + side).round()
		sp.scale = Vector2.ONE * lerpf(0.9, 0.5, u)
		sp.visible = true
		if u >= 1.0:
			if bool(m.last):
				burst("pickup_glint", target, 0.5, m.tint)
			sp.visible = false
			_mag_free.append(sp)
			_mag.remove_at(i)
		i -= 1


# ---------------------------------------------------------------------------
# Всплывающий текст / иконки
# ---------------------------------------------------------------------------

func float_text(world_pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	_popup(world_pos, null, text, color)


func float_icon(world_pos: Vector2, icon: Texture2D, text: String = "", color: Color = Color.WHITE) -> void:
	_popup(world_pos, icon, text, color)


func active_popups() -> int:
	return _popups.size() - _popup_free.size()


func _make_popup() -> Node2D:
	var root := Node2D.new()
	var sp := Sprite2D.new()
	sp.name = "Icon"
	sp.centered = true
	root.add_child(sp)
	var lb := Label.new()
	lb.name = "Text"
	lb.add_theme_font_size_override("font_size", 11)
	lb.add_theme_constant_override("outline_size", 3)
	lb.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.95))
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lb)
	add_child(root)
	_popups.append(root)
	return root


func _popup(pos: Vector2, icon: Texture2D, text: String, color: Color) -> Node2D:
	if icon == null and text.is_empty():
		return null
	var root: Node2D
	if not _popup_free.is_empty():
		root = _popup_free.pop_back()
	elif _popups.size() < max_popups:
		root = _make_popup()
	else:
		# все заняты — вытесняем самый старый (первый в очереди)
		root = _popups[0]
		_popups.remove_at(0)
		_popups.append(root)
		var old: Tween = _popup_tween.get(root)
		if old != null and old.is_valid():
			old.kill()
	stats["popups"] += 1

	var sp: Sprite2D = root.get_node("Icon")
	var lb: Label = root.get_node("Text")
	lb.text = text
	lb.visible = not text.is_empty()
	lb.add_theme_color_override("font_color", color)
	lb.reset_size()
	var tw_w: float = lb.get_minimum_size().x if lb.visible else 0.0
	var tw_h: float = lb.get_minimum_size().y
	var icon_w := 0.0
	sp.visible = icon != null
	if icon != null:
		sp.texture = icon
		var side := float(maxi(icon.get_width(), icon.get_height()))
		sp.scale = Vector2.ONE * (FLY_SIZE / maxf(side, 1.0))
		icon_w = FLY_SIZE
	var gap := 2.0 if (icon != null and lb.visible) else 0.0
	var total := icon_w + gap + tw_w
	sp.position = Vector2(-total * 0.5 + icon_w * 0.5, 0)
	lb.position = Vector2(-total * 0.5 + icon_w + gap, -tw_h * 0.5)

	root.position = pos
	root.modulate = Color(1, 1, 1, 1)
	root.scale = Vector2(1.5, 1.5)
	root.visible = true
	var tw := create_tween().set_parallel(true)
	_popup_tween[root] = tw
	tw.tween_property(root, "position:y", pos.y - POPUP_RISE, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "modulate:a", 0.0, 0.4).set_delay(0.55)
	tw.chain().tween_callback(_recycle_popup.bind(root))
	return root


## «+N» со слиянием (aaa-feel): подряд добытое одно и то же (key) в окне window_s
## складывается в одно всплывающее число, которое «подпрыгивает» при каждой
## добавке, а не в стопку одинаковых «+1». Возвращает накопленное число.
func float_stack(key: String, pos: Vector2, icon: Texture2D, add: int, color: Color = Color.WHITE,
		window_s: float = 0.75) -> int:
	var now := Time.get_ticks_msec()
	var total := add
	var base := pos
	var e: Variant = _stack.get(key)
	if typeof(e) == TYPE_DICTIONARY:
		var old_root: Node2D = e["root"]
		# пул мог отдать этот узел другому числу — сверяем надпись
		if now <= int(e["until"]) and is_instance_valid(old_root) and old_root.visible \
				and (old_root.get_node("Text") as Label).text == "+%d" % int(e["count"]):
			total += int(e["count"])
			base = e["base"]
			var old_tw: Tween = _popup_tween.get(old_root)
			if old_tw != null and old_tw.is_valid():
				old_tw.kill()
			_recycle_popup(old_root)
	var root := _popup(base, icon, "+%d" % total, color)
	_stack[key] = {"root": root, "count": total, "until": now + int(window_s * 1000.0), "base": base}
	return total


var _stack: Dictionary = {}   # key -> {root, count, until, base}


func _recycle_popup(root: Node2D) -> void:
	root.visible = false
	if not _popup_free.has(root):
		_popup_free.append(root)


# ---------------------------------------------------------------------------
# Тряска и вспышка
# ---------------------------------------------------------------------------

func shake(strength: float = 4.0, duration: float = 0.2) -> void:
	if Settings.reduce_motion or strength <= 0.0:
		return
	# более сильная тряска не должна гаситься слабой
	var left := _shake_amp * clampf(1.0 - _shake_t / maxf(_shake_dur, 0.001), 0.0, 1.0)
	if strength < left:
		return
	_shake_amp = strength
	_shake_dur = maxf(duration, 0.02)
	_shake_t = 0.0


func is_shaking() -> bool:
	return _shake_amp > 0.0 and _shake_t < _shake_dur


func _process(delta: float) -> void:
	if not _mag.is_empty():
		_tick_magnet(delta)
	if _shake_amp <= 0.0:
		return
	_shake_t += delta
	if _shake_t >= _shake_dur:
		_reset_shake()
		return
	var k := 1.0 - _shake_t / _shake_dur
	var a := _shake_amp * k * k
	# целые пиксели — иначе пиксель-арт «плывёт»
	var off := Vector2(roundf(randf_range(-a, a)), roundf(randf_range(-a, a)))
	get_viewport().canvas_transform = Transform2D(0.0, off)
	_shake_applied = true


func _reset_shake() -> void:
	_shake_amp = 0.0
	_shake_t = 0.0
	if _shake_applied and is_inside_tree():
		get_viewport().canvas_transform = Transform2D.IDENTITY
	_shake_applied = false


func flash(color: Color = Color(1, 1, 1, 0.5), duration: float = 0.15) -> void:
	if _flash == null:
		return
	if Settings.reduce_motion:
		color.a *= 0.3
	_flash.size = get_viewport().get_visible_rect().size
	_flash.position = Vector2.ZERO
	_flash.color = color
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, maxf(duration, 0.02)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# Летящие иконки
# ---------------------------------------------------------------------------

func world_to_screen(world_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas() * world_pos


func active_fliers() -> int:
	return _fliers_active


func fly_to(icon: Texture2D, from_screen: Vector2, to_screen: Vector2, count: int = 1) -> void:
	if icon == null:
		icon = _coin_tex
	if icon == null or _fly_layer == null:
		return
	count = clampi(count, 1, 12)
	var scale_to := FLY_SIZE / maxf(float(maxi(icon.get_width(), icon.get_height())), 1.0)
	for i in count:
		if _fliers_active >= max_fliers:
			break
		_fliers_active += 1
		stats["fliers"] += 1
		var s := Sprite2D.new()
		s.texture = icon
		s.scale = Vector2.ONE * scale_to
		s.visible = false
		_fly_layer.add_child(s)
		var start := from_screen + Vector2(randf_range(-9.0, 9.0), randf_range(-6.0, 6.0))
		var ctrl := (start + to_screen) * 0.5 + Vector2(randf_range(-45.0, 45.0), -randf_range(30.0, 75.0))
		var dur := 0.55 + randf() * 0.2
		var tw := create_tween()
		tw.tween_interval(float(i) * 0.05)
		tw.tween_callback(_fly_show.bind(s, start))
		tw.tween_method(_fly_step.bind(s, start, ctrl, to_screen), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(_fly_land.bind(s, to_screen, i, count))


func _fly_show(s: Sprite2D, start: Vector2) -> void:
	if is_instance_valid(s):
		s.position = start
		s.visible = true


func _fly_step(t: float, s: Sprite2D, a: Vector2, c: Vector2, b: Vector2) -> void:
	if not is_instance_valid(s):
		return
	var u := 1.0 - t
	s.position = a * (u * u) + c * (2.0 * u * t) + b * (t * t)
	# в самом конце гаснет — «впитывается» в счётчик
	s.modulate.a = 1.0 if t < 0.9 else (1.0 - t) * 10.0


func _fly_land(s: Sprite2D, to: Vector2, index: int, total: int) -> void:
	_fliers_active = maxi(0, _fliers_active - 1)
	if is_instance_valid(s):
		s.queue_free()
	flier_landed.emit(to, index, total)

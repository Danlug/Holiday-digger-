class_name SkyView
extends Node2D
## SkyView — небо над огородом: градиент с зарёй, звёзды в три слоя, Млечный Путь, солнце, луна по дуге.
##
## Устройство (дёшево для веба и телефона, ничего не пересчитывается по кадрам):
##  * _quad — один прямоугольник с шейдером shaders/sky.gdshader: градиент, тёплая полоса зари, свечение
##    светил, Млечный Путь и три слоя звёзд (art/env/sky/*.png, рисует tools/gen_sky.py). Мерцание — в шейдере
##    из фазы текселя, звёзд на спрайты не режем. Прямоугольник статичен, меняются только uniform'ы.
##  * _celestial/_bodies — спрайты солнца (art/env/sun.png) и луны (атлас 8 фаз art/env/moon.png). Слой «прибит» к
##    экрану (солнце и месяц не улетают из кадра, когда герой поднимается), дуга считается в экранных px,
##    камера двигает только позицию слоя.
##  * _fx — падающие звёзды, тоже в экранных координатах.
## Небо — ребёнок ViewRoot, рисуется раньше Backdrop (горы, лес, забор), поэтому светила садятся ЗА лес.
##
## Прежняя схема (вырезка спрайтов из авторского листа, 420 спрайтов-звёзд, 24 прямоугольника градиента
## каждый кадр) убрана: в вырезку месяца попал «мусор» — соседние звёздочки и кайма ключа фона.
##
## В катсценах (scripts/story/cutscene_player.gd) тот же узел ставится дочерним при use_day_cycle(true);
## там нет камеры, set_scene_rect() переводит всё в локальные координаты сцены.

const TILE: int = preload("res://scripts/world/world_view.gd").TILE
const SKY_HEIGHT: int = preload("res://scripts/world/world_view.gd").SKY_HEIGHT
const COLOR_DAY: Color = preload("res://scripts/world/world_view.gd").COLOR_SKY

const SHADER_PATH := "res://shaders/sky.gdshader"
const SKY_DIR := "res://art/env/sky/"
const SUN_TEX_PATH := "res://art/env/sun.png"
const MOON_TEX_PATH := "res://art/env/moon.png"

## Спрайты нарезаны в ART_SCALE раз крупнее логических пикселей (как тайлы и персонажи).
const ART_SCALE_TEX := 3.0
const MOON_FRAMES := 8
const MOON_FRAME_PX := 112.0

## Ширина полосы и доля сдвига камеры слоя _celestial — контракт, который проверяет tests/test_backdrop.gd
## (задание владельца: «небо на 10% шире горы, параллакс на 10% меньше»). Светила (дочерний слой _bodies) его
## компенсируют и стоят на своих экранных координатах дуги с лёгким дрейфом CELESTIAL_DRIFT.
const SKY_W_LOGICAL: float = Backdrop.MOUNTAIN_W_LOGICAL * 1.1        # 880
const SKY_PARALLAX_X: float = Backdrop.MOUNTAIN_PARALLAX_X * 0.9      # 0.315
const CELESTIAL_DRIFT := 0.06

## Параллакс слоёв звёзд: far, mid, near — доля движения камеры, которая доходит до слоя (и по X, и по Y).
## Ближний слой почти едет с миром, дальний отстаёт: при полёте вверх звёзды расходятся по глубине.
const STAR_PARALLAX := Vector3(0.45, 0.62, 0.80)

## Дуга светил в экранных px при опорной камере (герой стоит на огороде, верх экрана на 6.5 клетки выше
## земли; кромка леса там на y≈125). Горизонт ниже кромки леса на радиус светила — восход и заход
## происходят ЗА лесом, а не у края экрана. По x дуга идёт от X_RISE к X_SET ширины экрана.
const SUN_HORIZON_Y := 192.0
const SUN_APEX_Y := 70.0
## Спрайт солнца (75 px с лучами) в полоске неба над лесом велик — чуть уменьшен, чтобы утром оно не пряталось за деревьями до полудня.
const SUN_SCALE := 0.85
const MOON_HORIZON_Y := 170.0
const MOON_APEX_Y := 62.0
const ARC_X_RISE := 0.07
const ARC_X_SET := 0.82
## Показатель при синусе высоты: меньше 1 — дуга сплюснута у краёв, светило дольше держится над горой.
const ARC_FLATNESS := 0.6

## Палитра: день — прежний ровный голубой (решение владельца 2026-09-21), ночь — три тона по высоте.
const NIGHT_HORIZON := Color8(0x30, 0x20, 0x78)
const NIGHT_MID := Color8(0x18, 0x0B, 0x58)
const NIGHT_ZENITH := Color8(0x0A, 0x04, 0x34)
## Сумерки: между днём и ночью небо проходит через насыщенный синий, а не через серую смесь голубого и индиго.
const DUSK_HORIZON := Color(0.46, 0.38, 0.74)
const DUSK_MID := Color(0.26, 0.30, 0.66)
const DUSK_ZENITH := Color(0.12, 0.18, 0.52)
const DUSK_LOW := Color(1.0, 0.50, 0.20)
const DUSK_HIGH := Color(0.78, 0.26, 0.50)
const DAWN_LOW := Color(1.0, 0.62, 0.36)
const DAWN_HIGH := Color(0.86, 0.48, 0.64)
const MOON_GLOW_COLOR := Color(0.62, 0.72, 1.0)

## Падающие звёзды: редко, только в полной темноте.
const METEOR_GAP_MIN := 28.0
const METEOR_GAP_MAX := 75.0

var _mat: ShaderMaterial
var _quad: Node2D
var _celestial: Node2D
var _bodies: Node2D
var _fx: Node2D
var _tex_sun: Texture2D
var _tex_moon: Texture2D
var _star_total: int = 0

var _day_cycle: Node = null

## true в катсцене (после set_scene_rect()): там нет камеры, всё в локальных координатах сцены.
var _mode_scene: bool = false
var _rect_w_px: float = float(WorldGen.WIDTH) * float(TILE)
var _rect_horizon_y: float = 0.0
var _rect_top_y: float = -float(SKY_HEIGHT) * float(TILE)

var _screen_w_px: float = 224.0
var _cam_px: Vector2 = Vector2.ZERO  # камера в мировых px (для катсцены — ноль)
var _underground: bool = false
var _last_hour: float = -100.0
var _last_night: int = -100
var _star_vis: float = 0.0
var _sun_screen: Vector2 = Vector2.ZERO
var _sun_alt: float = -1.0
var _moon_screen: Vector2 = Vector2.ZERO
var _moon_alt: float = -1.0
var _moon_u: float = 0.0
var _moon_phase: int = 1
var _uniforms: Dictionary = {}
var _meteors: Array = []
var _meteor_timer: float = 25.0
var _clouds_view: Node = null

## Источник цветов прежнего неба; задаёт main.gd. Палитра теперь живёт здесь (см. шапку), поле оставлено,
## чтобы не трогать чужую сборку сцены.
var sky_color_source: Node = null


func _ready() -> void:
	_day_cycle = get_node_or_null("/root/DayCycle")
	_build_material()
	if ResourceLoader.exists(SUN_TEX_PATH):
		_tex_sun = load(SUN_TEX_PATH)
	if ResourceLoader.exists(MOON_TEX_PATH):
		_tex_moon = load(MOON_TEX_PATH)

	_quad = Node2D.new()
	_quad.name = "Gradient"
	_quad.material = _mat
	_quad.draw.connect(_draw_quad)
	add_child(_quad)

	_celestial = Node2D.new()
	_celestial.name = "Celestial"
	add_child(_celestial)
	# Солнце и луна рисуются в экранных координатах (локальные = экранные), поэтому камера двигает только
	# позицию этого слоя, а не заставляет его перерисовываться. Линейный фильтр: светила плывут с долями
	# пикселя, и край луны при ближайшем соседе «ползал» бы.
	_bodies = Node2D.new()
	_bodies.name = "Bodies"
	_bodies.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bodies.draw.connect(_draw_celestial)
	_celestial.add_child(_bodies)

	_fx = Node2D.new()
	_fx.name = "Meteors"
	_fx.draw.connect(_draw_meteors)
	add_child(_fx)

	_quad.queue_redraw()
	_update_state()
	set_process(true)


func _build_material() -> void:
	if not ResourceLoader.exists(SHADER_PATH):
		return
	var sh: Shader = load(SHADER_PATH)
	if sh == null:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	for pair in [["stars_far", "stars_far.png"], ["stars_mid", "stars_mid.png"],
			["stars_near", "stars_near.png"], ["milkyway", "milkyway.png"]]:
		var path: String = SKY_DIR + String(pair[1])
		if ResourceLoader.exists(path):
			_mat.set_shader_parameter(String(pair[0]), load(path))
	if FileAccess.file_exists(SKY_DIR + "sky.json"):
		var f := FileAccess.open(SKY_DIR + "sky.json", FileAccess.READ)
		var meta = JSON.parse_string(f.get_as_text())
		if typeof(meta) == TYPE_DICTIONARY:
			for layer in (meta.get("layers", {}) as Dictionary).values():
				_star_total += int(layer.get("stars", 0))
	_mat.set_shader_parameter("parallax", STAR_PARALLAX)


## Переопределяет область неба под чужую (не мировую) систему координат — катсцена (её сцена не в клетках
## по 32 px, а в пикселях экрана). horizon_y/top_y — в локальных координатах ЭТОГО узла.
func set_scene_rect(width_px: float, horizon_y: float, top_y: float) -> void:
	_mode_scene = true
	_rect_w_px = width_px
	_rect_horizon_y = horizon_y
	_rect_top_y = top_y
	_screen_w_px = width_px
	_cam_px = Vector2.ZERO
	if _celestial != null:
		_celestial.position = Vector2.ZERO
		_bodies.position = Vector2.ZERO
	if _quad != null:
		_quad.queue_redraw()
	_uniforms.clear()
	_update_state()


## Зовёт main.gd каждый кадр (сразу после world_view.render(cam)). cam — в КЛЕТКАХ, как возвращает
## Main._camera().
func set_camera(cam: Vector2, view_w_cells: int) -> void:
	_screen_w_px = float(view_w_cells) * float(TILE)
	if _mode_scene:
		return
	# Верх экрана ниже травы: неба на экране нет совсем — не считаем и не рисуем (под землёй это была четверть
	# стоимости _process в прежнем небе).
	var under: bool = cam.y >= 1.0
	if under != _underground:
		_underground = under
		visible = not under
	if under:
		return
	var cam_px := cam * float(TILE)
	_celestial.position = Vector2((1.0 - SKY_PARALLAX_X) * cam_px.x, cam_px.y)
	# Слой _celestial едет с параллаксом SKY_PARALLAX_X; светилам возвращаем экранные координаты дуги
	# и добавляем лёгкий дрейф при ходьбе — одной позицией, без перерисовки.
	var cam_mid: float = float(WorldGen.GARDEN_X_MIN + WorldGen.WIDTH) * 0.5 * float(TILE) - _screen_w_px * 0.5
	var drift: float = -CELESTIAL_DRIFT * (cam_px.x - cam_mid)
	_bodies.position = Vector2(SKY_PARALLAX_X * cam_px.x + drift, 0.0)
	_fx.position = cam_px
	_cam_px = cam_px
	_set_u("cam_px", cam_px)
	_set_u("body_shift", drift)


func _process(delta: float) -> void:
	if _underground:
		return
	var hour: float = float(_day_cycle.hour) if _day_cycle != null else 12.0
	var night: int = int(_day_cycle.night_day()) if _day_cycle != null else 0
	if absf(hour - _last_hour) > 0.0015 or night != _last_night:
		_update_state()
	_tick_meteors(delta)


func _set_u(uniform_name: String, value) -> void:
	if _mat == null:
		return
	if _uniforms.has(uniform_name) and _uniforms[uniform_name] == value:
		return
	_uniforms[uniform_name] = value
	_mat.set_shader_parameter(uniform_name, value)


## Всё, что зависит от часа суток: палитра, видимость звёзд, положение светил. Зовётся при заметном сдвиге
## часов (раз в секунду-две реального времени), а не каждый кадр.
func _update_state() -> void:
	var dc := _day_cycle
	_last_hour = float(dc.hour) if dc != null else 12.0
	_last_night = int(dc.night_day()) if dc != null else 0
	var p: float = dc.night_amount() if dc != null else 0.0
	var tw: float = dc.twilight() if dc != null else 0.0
	var dawn: bool = dc.is_dawn() if dc != null else false
	_star_vis = dc.star_glow() if dc != null else 0.0

	_set_u("col_horizon", _tri(COLOR_DAY, DUSK_HORIZON, NIGHT_HORIZON, p))
	_set_u("col_mid", _tri(COLOR_DAY, DUSK_MID, NIGHT_MID, p))
	_set_u("col_zenith", _tri(COLOR_DAY, DUSK_ZENITH, NIGHT_ZENITH, smoothstep(0.0, 0.9, p)))
	_set_u("twilight", tw * 0.95)
	_set_u("tw_col_low", DAWN_LOW if dawn else DUSK_LOW)
	_set_u("tw_col_high", DAWN_HIGH if dawn else DUSK_HIGH)
	_set_u("tw_x", _screen_w_px * (0.10 if dawn else 0.90))
	_set_u("tw_spread", maxf(120.0, _screen_w_px * 0.9))
	_set_u("horizon_y", _rect_horizon_y if _mode_scene else 0.0)
	_set_u("star_vis", _star_vis)
	var illum: float = dc.moon_illumination() if dc != null else 0.5
	# Яркая луна смывает Млечный Путь; на новолуние он виден лучше всего.
	_set_u("neb_vis", smoothstep(0.70, 1.0, p) * (1.0 - 0.7 * illum))
	_set_u("twinkle", 0.25 if Settings.reduce_motion else 1.0)

	_moon_phase = dc.moon_phase() if dc != null else 1
	_sun_alt = dc.sun_alt() if dc != null else -1.0
	_moon_alt = dc.moon_alt() if dc != null else -1.0
	_place_celestial()


## День -> сумерки -> ночь: p в 0..0.5 ведёт от дня к сумеркам, в 0.5..1 от сумерек к ночи.
func _tri(day: Color, dusk: Color, night: Color, p: float) -> Color:
	if p <= 0.0:
		return day
	if p < 0.5:
		return day.lerp(dusk, p * 2.0)
	return dusk.lerp(night, (p - 0.5) * 2.0)


## Дуга: x идёт от X_RISE к X_SET ширины экрана, y — синус высоты от горизонта (за лесом) к зениту.
func _arc(u: float, y_horizon: float, y_apex: float) -> Vector2:
	var x: float = _screen_w_px * lerpf(ARC_X_RISE, ARC_X_SET, u)
	var y: float = y_horizon - (y_horizon - y_apex) * pow(maxf(sin(PI * u), 0.0), ARC_FLATNESS)
	return Vector2(x, y)


func _place_celestial() -> void:
	if _day_cycle == null:
		return
	var sun_h := SUN_HORIZON_Y
	var sun_a := SUN_APEX_Y
	var moon_h := MOON_HORIZON_Y
	var moon_a := MOON_APEX_Y
	if _mode_scene:
		# В катсцене дуга привязана к её горизонту и верху, а не к экрану мира: светило уходит за землю сцены.
		var span: float = _rect_horizon_y - _rect_top_y
		sun_h = _rect_horizon_y + 38.0
		sun_a = _rect_top_y + 0.28 * span
		moon_h = _rect_horizon_y + 20.0
		moon_a = _rect_top_y + 0.20 * span
	var arc_span: float = _day_cycle.ARC_TO - _day_cycle.ARC_FROM
	if _sun_alt >= 0.0:
		_sun_screen = _arc((_day_cycle.sun_t() - _day_cycle.ARC_FROM) / arc_span, sun_h, sun_a)
	if _moon_alt >= 0.0:
		_moon_u = (_day_cycle.moon_t() - _day_cycle.ARC_FROM) / arc_span
		_moon_screen = _arc(_moon_u, moon_h, moon_a)

	# Свечение вокруг светил считает шейдер неба; ниже горизонта светило не светит.
	var sun_k: float = 0.0
	if _sun_alt >= 0.0:
		var low := 1.0 - smoothstep(0.0, 0.55, _sun_alt)
		sun_k = (0.26 + 0.40 * low) * smoothstep(0.0, 0.10, _sun_alt)
		_set_u("sun_glow", Vector4(_sun_screen.x, _sun_screen.y, lerpf(70.0, 120.0, low), sun_k))
		_set_u("sun_col", Color(1.0, 0.93, 0.70).lerp(Color(1.0, 0.62, 0.30), low))
	else:
		_set_u("sun_glow", Vector4(0.0, 0.0, 80.0, 0.0))
	if _moon_alt >= 0.0:
		var illum: float = _day_cycle.moon_illumination()
		var k: float = (0.08 + 0.32 * illum) * (0.45 + 0.55 * smoothstep(0.0, 0.30, _moon_alt))
		_set_u("moon_glow", Vector4(_moon_screen.x, _moon_screen.y, 20.0 + 14.0 * illum, k))
		_set_u("moon_col", MOON_GLOW_COLOR)
	else:
		_set_u("moon_glow", Vector4(0.0, 0.0, 30.0, 0.0))
	if _clouds_view == null and get_parent() != null:
		_clouds_view = get_parent().get_node_or_null("CloudsView")
	if _clouds_view != null and _clouds_view.has_method("set_moon_light"):
		var lit: float = 0.0
		if _moon_alt >= 0.0:
			lit = _day_cycle.moon_illumination() * smoothstep(0.0, 0.25, _moon_alt)
		_clouds_view.set_moon_light(_moon_screen, lit)
	if _bodies != null:
		_bodies.queue_redraw()


func _draw_quad() -> void:
	var rect: Rect2
	if _mode_scene:
		rect = Rect2(0.0, _rect_top_y, _rect_w_px, _rect_horizon_y - _rect_top_y)
	else:
		# Весь огород с запасом по две клетки: камера ходит внутри мира, прямоугольник не перерисовывается.
		var w: float = float(WorldGen.WIDTH) * float(TILE) + 4.0 * float(TILE)
		rect = Rect2(-2.0 * float(TILE), -float(SKY_HEIGHT) * float(TILE), w, float(SKY_HEIGHT) * float(TILE))
	_quad.draw_rect(rect, COLOR_DAY if _mat == null else Color.WHITE, true)


func _draw_celestial() -> void:
	if _day_cycle == null:
		return
	if _sun_alt >= 0.0:
		_draw_sun()
	if _moon_alt >= 0.0:
		_draw_moon()


func _draw_sun() -> void:
	var pos := _sun_screen
	var low := 1.0 - smoothstep(0.0, 0.5, _sun_alt)
	# Низкое солнце крупнее и краснее — ровно то, что видно на закате.
	var k: float = SUN_SCALE * (1.0 + 0.16 * low)
	var tint := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.66, 0.46), low)
	if _tex_sun != null:
		var w: float = _tex_sun.get_width() / ART_SCALE_TEX * k
		var h: float = _tex_sun.get_height() / ART_SCALE_TEX * k
		_bodies.draw_texture_rect(_tex_sun, Rect2(pos - Vector2(w, h) * 0.5, Vector2(w, h)), false, tint)
	else:
		_bodies.draw_circle(pos, 11.0 * k, Color8(0xFF, 0xD9, 0x6B))


func _draw_moon() -> void:
	var pos := _moon_screen
	if _tex_moon == null:
		_bodies.draw_circle(pos, 17.0, Color8(0xE9, 0xEE, 0xF4))
		return
	var size: float = MOON_FRAME_PX / ART_SCALE_TEX
	var src := Rect2(float(_moon_phase) * MOON_FRAME_PX, 0.0, MOON_FRAME_PX, MOON_FRAME_PX)
	# Лёгкий наклон: к рассвету серп разворачивается вслед за уходящим вниз солнцем.
	var tilt: float = lerpf(0.5, -0.5, clampf(_moon_u, 0.0, 1.0))
	_bodies.draw_set_transform(pos, tilt, Vector2.ONE)
	_bodies.draw_texture_rect_region(_tex_moon, Rect2(Vector2(-size, -size) * 0.5, Vector2(size, size)), src)
	_bodies.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------------------
# Падающие звёзды
# ---------------------------------------------------------------------------

func _tick_meteors(delta: float) -> void:
	if not _meteors.is_empty():
		for m in _meteors:
			m.age += delta
		_meteors = _meteors.filter(func(m): return m.age < m.life)
		_fx.queue_redraw()
	if Settings.reduce_motion or _star_vis < 0.95:
		return
	_meteor_timer -= delta
	if _meteor_timer > 0.0:
		return
	_meteor_timer = randf_range(METEOR_GAP_MIN, METEOR_GAP_MAX)
	var ang: float = deg_to_rad(randf_range(16.0, 36.0))
	var speed: float = randf_range(230.0, 330.0)
	_meteors.append({
		"p": Vector2(randf_range(0.05, 0.85) * _screen_w_px, randf_range(14.0, 108.0)),
		"v": Vector2(cos(ang), sin(ang)) * speed,
		"age": 0.0,
		"life": randf_range(0.5, 0.8),
		"len": randf_range(34.0, 62.0),
	})


func _draw_meteors() -> void:
	for m in _meteors:
		var t: float = float(m.age) / float(m.life)
		var env: float = sqrt(sin(PI * t))
		var head: Vector2 = m.p + m.v * float(m.age)
		var dir: Vector2 = (m.v as Vector2).normalized()
		var steps := 9
		var prev := head
		for i in range(1, steps + 1):
			var f: float = float(i) / float(steps)
			var cur: Vector2 = head - dir * float(m.len) * f
			var a: float = pow(1.0 - f, 1.6) * env * 0.9
			_fx.draw_line(prev, cur, Color(0.86, 0.92, 1.0, a), 1.2)
			prev = cur
		_fx.draw_circle(head, 1.1, Color(1.0, 1.0, 1.0, env))


# ---------------------------------------------------------------------------
# Хуки для тестов (tests/test_day_cycle.gd, tests/test_backdrop.gd, tests/test_sky.gd)
# ---------------------------------------------------------------------------

## Сколько звёзд лежит в трёх слоях (по art/env/sky/sky.json).
func debug_star_count() -> int:
	return _star_total


func debug_uniform(uniform_name: String):
	return _uniforms.get(uniform_name)


func debug_moon_phase() -> int:
	return _moon_phase


func debug_has_shader() -> bool:
	return _mat != null


func debug_spawn_meteor() -> void:
	_meteor_timer = 0.0
	_star_vis = 1.0
	_tick_meteors(0.0)


func debug_meteor_count() -> int:
	return _meteors.size()

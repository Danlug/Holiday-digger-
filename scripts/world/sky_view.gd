class_name SkyView
extends Node2D
## SkyView — солнце, месяц и звёзды над огородом (цвет самого неба красит
## world_view.gd:_sky_color через DayCycle.sky_dark() — см. комментарий там
## же про то, почему это НЕ отдельный слой: у неба нет тумана войны, и
## подмешать темноту в уже готовый градиент проще и надёжнее, чем городить
## полноэкранный оверлей поверх непрозрачных тайлов того же пула спрайтов).
##
## Этот узел рисует то, что градиентом не нарисовать: диск солнца с ореолом,
## серп месяца и мерцающее поле звёзд. Он — ребёнок ViewRoot В ГЛАВНОЙ СЦЕНЕ,
## сразу после WorldView (main.gd): тот же локальный масштаб "клетка = TILE
## пикселей", то же движение камеры по X и Y, что и у тайлов, — значит
## положение солнца на клетке (5) над горизонтом совпадает что при взгляде с
## земли, что если игрок поднялся на ранце. Рисуется ПОСЛЕ WorldView (позже
## в списке детей = поверх), потому что тайлы неба у WorldView непрозрачные
## — под ними солнце/звёзды были бы не видны.
##
## В катсценах (scripts/story/cutscene_player.gd) этот же узел ставится
## дочерним, когда включён use_day_cycle(true) — см. CutscenePlayer._build();
## там своя локальная система координат сцены, поэтому SkyView расположение
## по X/Y настраивает сам вызывающий (см. set_scene_rect()).

const TILE: int = preload("res://scripts/world/world_view.gd").TILE
const SKY_HEIGHT: int = preload("res://scripts/world/world_view.gd").SKY_HEIGHT

const STAR_ATLAS_PATH := "res://art/env/stars.png"
const STAR_META_PATH := "res://art/env/stars.json"

## Атлас нарезан tools/import_stars.py в ART_SCALE раз крупнее логических
## пикселей (тот же приём, что у тайлов/персонажей, см. import_art.ART_SCALE
## и world_view.gd:_set_texture) — рисуем уменьшенным, иначе "мелкие 3-7px"
## звёзды из задания владельца выйдут на экран 9-21-пиксельными пятнами.
const STAR_ART_SCALE := 3.0

## Столько звёзд раскидано по всей ширине огорода (32 клетки, WorldGen.WIDTH)
## и по большей части высоты неба — см. _spawn_stars(). Стоя на земле, камера
## показывает не все SKY_HEIGHT=24 клетки неба, а только половину экрана
## (view_h/2, у обычного окна это ~7 клеток) — плотность подобрана так, чтобы
## именно В ЭТОМ обычном окне на экране было 20-40 звёзд, как просил
## владелец, а не в теоретическом максимуме (видимом только в полёте на
## ранце). Атлас не размножаем — звёзды переиспользуют одни и те же ~40
## рисунков в разных точках неба, так и должно быть, звёзд на небе больше,
## чем рисунков.
const STAR_COUNT := 260
const STAR_SEED := 20260921

## Полоса вокруг высоты солнца/месяца (~4.5 клетки над землёй), где звёзд
## нет, — чтобы месяц (единственное светило, которое СОСУЩЕСТВУЕТ со
## звёздами ночью — солнце и звёзды по времени суток не пересекаются
## никогда) не наезжал на них силуэтом. Более узкая полоса, чем в первой
## версии этого файла: та эксклюзивная зона (низ 6 клеток из 24) случайно
## съедала весь обычно видимый кусок неба у стоящего на земле героя, и
## звёзды рисовались только высоко над камерой — то есть нигде не видимые
## без полёта (см. отчёт агента).
const MOON_GAP_TOP_ROW := 3.3
const MOON_GAP_BOTTOM_ROW := 5.7
## Верхняя граница разброса — не весь SKY_HEIGHT (там смотрит только герой в
## полёте на пределе ранца), а с небольшим запасом за типичное окно камеры
## стоящего на земле героя (видит ~8 клеток неба, см. отчёт агента про
## первую версию этого файла, где вся полоса звёзд ушла ВЫШЕ этого окна).
const STAR_TOP_ROW := 12
## Раз в 3-8 секунд звезда на 0.5-1 с плавно проваливается в 0-15% —
## интервал ПОДОБРАН так, что доля "спокойного" времени (видна на 70%)
## естественно ложится в заданные 80-90%: idle/(idle+dip) при dip=0.5-1с и
## idle=3-8с даёт 0.86-0.89.
const DIP_INTERVAL_MIN := 3.0
const DIP_INTERVAL_MAX := 8.0
const DIP_DURATION_MIN := 0.5
const DIP_DURATION_MAX := 1.0
const DIP_ALPHA_MIN := 0.0
const DIP_ALPHA_MAX := 0.15
const STAR_BASE_ALPHA := 0.7

const SUN_COLOR := Color8(0xFF, 0xD9, 0x6B)
const SUN_HALO_COLOR := Color8(0xFF, 0xE7, 0xA8, 90)
const SUN_RADIUS := 5.0
const SUN_HALO_RADIUS := 10.0
const MOON_COLOR := Color8(0xE9, 0xEE, 0xF4)
const MOON_BITE_COLOR := Color8(0x0A, 0x0E, 0x18, 210)
const MOON_RADIUS := 5.0

var _star_atlas: Texture2D
var _star_regions: Array = []       # [{"x","y","w","h"}, ...]
var _stars: Array = []              # см. _spawn_stars()

## Область РАЗБРОСА ЗВЁЗД в ЛОКАЛЬНЫХ координатах узла (0..width_px по X,
## горизонт..верх по Y). По умолчанию — вся ширина огорода, как в мире:
## звёзды честно раскиданы по карте и едут вместе с ней при панораме камеры
## (задание "следуй за камерой по X" — тем же движением, что у тайлов, без
## отдельного кода, см. шапку файла). catscene_player.use_day_cycle(true)
## подставляет свой прямоугольник сцены (там она и есть "весь экран").
var _rect_w_px: float = float(WorldGen.WIDTH) * float(TILE)
var _rect_horizon_y: float = 0.0
var _rect_top_y: float = -float(SKY_HEIGHT) * float(TILE)

## Солнце/месяц — ДРУГОЕ дело: DayCycle.sun_t()/moon_t() отдают долю ШИРИНЫ
## ЭКРАНА (-0.1..1.1, задание владельца "приходит слева/пропадает справа ЗА
## ГРАНИЦЕЙ ЭКРАНА"), а не всей 32-клеточной карты — иначе на типичном окне
## в 7 клеток светило почти всегда стояло бы за пределами видимой камеры.
## _screen_w_px/_cam_x_px обновляет main.gd каждый кадр через set_camera():
## первое — ширина текущего окна камеры в пикселях, второе — перевод
## "доли экрана" в локальные (мировые) координаты этого узла, те же, в
## которых WorldView рисует тайлы. Y камеру не спрашивает: "высота над
## землёй" уже мировая (абсолютная), а по вертикали камеру отрабатывает сам
## ViewRoot (см. main.gd), сдвигая этот узел вместе с тайлами.
var _screen_w_px: float = float(WorldGen.WIDTH) * float(TILE)
var _cam_x_px: float = 0.0

var _day_cycle: Node = null


func _ready() -> void:
	_day_cycle = get_node_or_null("/root/DayCycle")
	_load_stars()
	_spawn_stars()
	set_process(true)


## Переопределяет область неба под чужую (не мировую) систему координат —
## используется катсценой (её сцена не в клетках 32px, а в своих пикселях
## экрана). horizon_y/top_y — в локальных координатах ЭТОГО узла.
func set_scene_rect(width_px: float, horizon_y: float, top_y: float) -> void:
	_rect_w_px = width_px
	_rect_horizon_y = horizon_y
	_rect_top_y = top_y
	# У катсцены нет прокрутки камеры — "экран" сцены и есть вся её ширина,
	# а смещение нулевое (see set_camera()).
	_screen_w_px = width_px
	_cam_x_px = 0.0
	_spawn_stars()


## Зовёт main.gd каждый кадр (сразу после world_view.render(cam)) — см.
## комментарий у _screen_w_px выше про то, зачем солнцу/месяцу вообще нужна
## камера, когда звёздам она не нужна.
func set_camera(cam: Vector2, view_w_cells: int) -> void:
	_cam_x_px = cam.x * float(TILE)
	_screen_w_px = float(view_w_cells) * float(TILE)


func _load_stars() -> void:
	if ResourceLoader.exists(STAR_ATLAS_PATH):
		_star_atlas = load(STAR_ATLAS_PATH)
	if FileAccess.file_exists(STAR_META_PATH):
		var f := FileAccess.open(STAR_META_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_star_regions = parsed.get("regions", [])


func _spawn_stars() -> void:
	_stars.clear()
	if _star_regions.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	# Строки мировой сетки (0 — горизонт, отрицательные — вверх) переносим в
	# локальные координаты ЭТОГО прямоугольника (может быть меньше/больше
	# мировых 24 клеток — у катсцены своя высота неба, см. set_scene_rect()).
	var row_to_y := func(row: float) -> float:
		var t: float = -row / float(SKY_HEIGHT)  # row=0 -> t=0 (горизонт), row=-SKY_HEIGHT -> t=1 (верх)
		return _rect_horizon_y + t * (_rect_top_y - _rect_horizon_y)
	for i in range(STAR_COUNT):
		var region: Dictionary = _star_regions[rng.randi() % _star_regions.size()]
		var row := rng.randf_range(1.0, float(STAR_TOP_ROW))
		# Полоса месяца — не отдельный отрезок randf_range (тот не умеет
		# "дырявый" интервал), а сдвиг к ближайшему краю дыры: чуть плотнее
		# на кромках полосы, зато без сложной перевзвешенной вероятности,
		# в которой в первой версии этого файла терялась половина звёзд.
		if row > MOON_GAP_TOP_ROW and row < MOON_GAP_BOTTOM_ROW:
			var to_top := row - MOON_GAP_TOP_ROW
			var to_bottom := MOON_GAP_BOTTOM_ROW - row
			row = MOON_GAP_TOP_ROW if to_top < to_bottom else MOON_GAP_BOTTOM_ROW
		var y: float = row_to_y.call(-row)
		var star := {
			"region": region,
			"x": rng.randf_range(0.0, _rect_w_px),
			"y": y,
			"timer": rng.randf_range(0.0, DIP_INTERVAL_MAX),
			"in_dip": false,
			"dip_elapsed": 0.0,
			"dip_dur": 1.0,
			"dip_min": 0.0,
			"alpha": STAR_BASE_ALPHA,
		}
		_stars.append(star)


func _process(delta: float) -> void:
	_tick_stars(delta)
	queue_redraw()


func _tick_stars(delta: float) -> void:
	for star in _stars:
		if star.in_dip:
			star.dip_elapsed += delta
			var t: float = star.dip_elapsed / star.dip_dur
			if t >= 1.0:
				star.in_dip = false
				star.timer = _rng_between(DIP_INTERVAL_MIN, DIP_INTERVAL_MAX)
				star.alpha = STAR_BASE_ALPHA
				continue
			# Плавный провал и возврат одной волной (0 -> пик провала -> 0).
			var wave: float = sin(PI * t)
			star.alpha = lerpf(STAR_BASE_ALPHA, star.dip_min, wave)
		else:
			star.timer -= delta
			if star.timer <= 0.0:
				star.in_dip = true
				star.dip_elapsed = 0.0
				star.dip_dur = _rng_between(DIP_DURATION_MIN, DIP_DURATION_MAX)
				star.dip_min = _rng_between(DIP_ALPHA_MIN, DIP_ALPHA_MAX)


func _rng_between(a: float, b: float) -> float:
	return a + randf() * (b - a)


# ---------------------------------------------------------------------------
# Публичные хуки для тестов (tests/test_day_cycle.gd) — тот же приём, что и
# в house_view.gd: тест не должен ждать реальных кадров/времени, чтобы
# убедиться, что звёзды заспавнены асинхронно (разные фазы мерцания).
# ---------------------------------------------------------------------------

func debug_star_count() -> int:
	return _stars.size()


func debug_star_timer(i: int) -> float:
	return float(_stars[i].timer) if i >= 0 and i < _stars.size() else 0.0


## Источник цветов неба — WorldView (_sky_color(wy) с затемнением DayCycle);
## задаёт main.gd. В катсцене (set_scene_rect) источника нет — там небо
## красит сама сцена, а этот узел рисует только светила и звёзды.
var sky_color_source: Node = null


func _draw() -> void:
	_draw_sky_gradient()
	if _day_cycle == null:
		return
	_draw_sun()
	_draw_moon()
	_draw_stars()


## Небо построчно, в мировых координатах, на ширину окна с запасом по клетке
## с каждой стороны: тайлы неба WorldView больше не красит (см. там
## _paint_cell), иначе заливка закрывала бы гору и забор Backdrop.
func _draw_sky_gradient() -> void:
	if sky_color_source == null or not sky_color_source.has_method("_sky_color"):
		return
	var x0: float = _cam_x_px - float(TILE)
	var w: float = _screen_w_px + 2.0 * float(TILE)
	for wy in range(-SKY_HEIGHT, 0):
		var c: Color = sky_color_source._sky_color(wy)
		draw_rect(Rect2(x0, float(wy) * float(TILE), w, float(TILE) + 0.5), c, true)


func _sun_moon_y() -> float:
	# "высота ~4-5 клеток над землёй" — задание владельца; берём середину.
	return _rect_horizon_y - 4.5 * float(TILE) * (_rect_horizon_y - _rect_top_y) \
		/ (float(SKY_HEIGHT) * float(TILE))


func _draw_sun() -> void:
	var t: float = _day_cycle.sun_t()
	if t < -0.15 or t > 1.15:
		return
	var x: float = t * _screen_w_px + _cam_x_px
	var y: float = _sun_moon_y()
	draw_circle(Vector2(x, y), SUN_HALO_RADIUS, SUN_HALO_COLOR)
	draw_circle(Vector2(x, y), SUN_RADIUS, SUN_COLOR)


func _draw_moon() -> void:
	var t: float = _day_cycle.moon_t()
	if t < -0.15 or t > 1.15:
		return
	var x: float = t * _screen_w_px + _cam_x_px
	var y: float = _sun_moon_y()
	draw_circle(Vector2(x, y), MOON_RADIUS, MOON_COLOR)
	# Серп: "откусываем" часть диска кругом цвета ночного неба, сдвинутым к
	# краю, — дешёвый и надёжный способ получить полумесяц без масок/шейдера.
	draw_circle(Vector2(x + MOON_RADIUS * 0.62, y - MOON_RADIUS * 0.28), MOON_RADIUS * 0.92, MOON_BITE_COLOR)


func _draw_stars() -> void:
	if _star_atlas == null:
		return
	var global_alpha: float = _day_cycle.stars_alpha()
	if global_alpha <= 0.0:
		return
	for star in _stars:
		var a: float = star.alpha * global_alpha
		if a <= 0.003:
			continue
		var r: Dictionary = star.region
		var region := Rect2(float(r.x), float(r.y), float(r.w), float(r.h))
		var dst_w: float = float(r.w) / STAR_ART_SCALE
		var dst_h: float = float(r.h) / STAR_ART_SCALE
		var pos := Vector2(star.x - dst_w * 0.5, star.y - dst_h * 0.5)
		draw_texture_rect_region(_star_atlas, Rect2(pos, Vector2(dst_w, dst_h)), region,
			Color(1.0, 1.0, 1.0, a))

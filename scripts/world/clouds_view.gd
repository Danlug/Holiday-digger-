class_name CloudsView
extends Node2D
## CloudsView — слой облаков над огородом (задание владельца, доп. пункт к
## подложкам/небу: "ширина неба на 10% шире горы... параллакс на 10% меньше,
## чем гора... ещё должен быть слой с облаками — ширина на 10% УЖЕ горы,
## параллакс на 10% БОЛЬШЕ, чем у горы").
##
## Геометрия — тот же приём, что у Backdrop._mountain_layer (см. шапку
## scripts/world/backdrop.gd): update() каждый кадр гасит часть сдвига
## view_root по X, оставляя долю CLOUDS_PARALLAX_X — она БОЛЬШЕ, чем у горы
## (Backdrop.MOUNTAIN_PARALLAX_X), значит облака едут ЗАМЕТНЕЕ горы, ближе к
## игроку. Облака НАРИСОВАНЫ на полосе шириной CLOUDS_W_LOGICAL (10% УЖЕ
## периода горы) — это не текстура на повтор, а ширина, на которую раскиданы
## отдельные спрайты (тот же смысл, что у SkyView.SKY_W_LOGICAL для звёзд).
##
## По Y — НЕ закреплены (в отличие от горы и slice неба/светил, см.
## sky_view.gd:_celestial): узел не компенсирует сдвиг камеры по вертикали
## вовсе, облака нарисованы на обычных МИРОВЫХ Y-координатах (как трава,
## как декор WorldView) — "иначе закреплены" из задания владельца. Ряды
## (клетки над землёй) подобраны так, чтобы на обычной высоте стояния героя
## (см. Backdrop.MOUNTAIN_REF_CAM_Y_PX — верх экрана там на ~6.5 клетки над
## землёй) облака оставались ВИДНЫ и НЕ перекрывали гору снизу (та на этой
## же опорной камере стоит пиком на экранной высоте ~69px, т.е. world-
## эквивалент ~4.3 клетки, см. отчёт агента) — см. CLOUD_ROW_MIN/MAX.
##
## Место в дереве сцены (scripts/main.gd): между Backdrop и WorldView —
## облака параллаксом ближе к игроку, чем гора (крупнее CLOUDS_PARALLAX_X),
## поэтому рисуются ПОСЛЕ неё (нет перекрытия силуэтом горы снизу — облака
## floating выше), но ДО тайлов/дома (переднего плана).

const TILE := 32.0

const CLOUDS_W_LOGICAL: float = Backdrop.MOUNTAIN_W_LOGICAL * 0.9      # 720
const CLOUDS_PARALLAX_X: float = Backdrop.MOUNTAIN_PARALLAX_X * 1.1    # 0.385

const ART_SCALE_TEX := 3.0
const CLOUD_COUNT := 12
const CLOUD_TEX_DIR := "res://art/env/clouds/"

## Видимость: облака "видны днём, с 6 утра до 8 вечера" (задание владельца).
## Резкая граница мигала бы при переходе через ровно 6:00/20:00 — плавный
## переход за FADE_HOURS игровых часов (15 игровых минут = 0.25 часа) убирает
## мигание, как и у stars_alpha()/sky_dark() в day_cycle.gd.
const VISIBLE_START := 6.0
const VISIBLE_END := 20.0
const FADE_HOURS := 0.25

## Облачность по ДНЯМ — не по кадрам: "делай случайно, не слишком
## повторяющимися", но детерминированно на один день (иначе будет мигать/
## меняться каждый кадр, а при перезаходе в тот же день внутри игры — не
## совпадать само с собой). Сид — hash(world_seed, day): разные миры и
## разные дни одного мира дают разные, но воспроизводимые раскладки.
## HEAVY_CHANCE=0.25 — "иногда более облачная погода (25%)" дословно из
## задания; HEAVY/LIGHT диапазоны покрытия — тоже дословно оттуда.
const HEAVY_CHANCE := 0.25
const HEAVY_COVERAGE_MIN := 0.15
const HEAVY_COVERAGE_MAX := 0.25
const LIGHT_COVERAGE_MIN := 0.0
const LIGHT_COVERAGE_MAX := 0.05

## Число облаков "по coverage" (задание: "расставь 3-9 облаков") — линейно
## между минимумом (совсем ясный день) и максимумом (самый пасмурный,
## coverage=HEAVY_COVERAGE_MAX) от доли покрытия.
const CLOUD_COUNT_MIN := 3
const CLOUD_COUNT_MAX := 9

## "плывут выше горы, на 8-14 клеток над землёй" (задание) — но облака НЕ
## закреплены по высоте (см. шапку файла), поэтому эти числа — обычные
## мировые Y, которые вместе с камерой скроллятся как трава/декор. Чтобы на
## обычной высоте стояния героя (видимое окно сверху — около 6.5-8 клеток
## неба, см. sky_view.gd:STAR_TOP_ROW и его комментарий) облака и правда
## было видно, а не всегда выше кадра, и чтобы низкие из них не залезали
## СИЛУЭТОМ поверх горы (та в этой же типичной раскладке стоит пиком
## world-эквивалентно на ~5.6 клетки, см. Backdrop.MOUNTAIN_TOP_WORLD_Y) —
## диапазон сдвинут ниже дословных "8-14" (см. докстринг файла и отчёт
## агента про подбор по скриншоту).
const CLOUD_ROW_MIN := 4.6
const CLOUD_ROW_MAX := 6.6

## Разброс масштаба/прозрачности отдельных облаков — "шум по X/Y/масштабу"
## из задания, чтобы одинаковые спрайты не выглядели штампом.
const SCALE_MIN := 0.7
const SCALE_MAX := 1.3
const ALPHA_MIN := 0.55
const ALPHA_MAX := 0.95

## Дрейф (решение владельца 2026-09-21): "облака потихонечку плывут по небу,
## очень медленно, каждый день в рандомном направлении, либо направо, либо
## налево" — направление ОБЩЕЕ на весь день (один знак для всех облаков
## этого дня, тот же сид, что и раскладка), "облака имеют рандомно разную
## скорость, некоторые 0.1 тайла в секунду, некоторые до 0.5" — скорость
## СВОЯ у каждого облака, в клетках/с, умножается на общий знак дня.
const DRIFT_SPEED_MIN_TILES := 0.1
const DRIFT_SPEED_MAX_TILES := 0.5

var _textures: Array[Texture2D] = []
var _clouds: Array = []          # [{"tex","x","y","scale","alpha"}, ...]
var _last_day: int = -1
var _last_coverage: float = 0.0
var _last_cam: Vector2 = Vector2.ZERO


func _ready() -> void:
	_load_textures()
	set_process(true)
	_regenerate(_current_day())


func _load_textures() -> void:
	_textures.clear()
	for i in range(1, CLOUD_COUNT + 1):
		var path := "%scloud_%d.png" % [CLOUD_TEX_DIR, i]
		if ResourceLoader.exists(path):
			_textures.append(load(path))


func _current_day() -> int:
	var dc := get_node_or_null("/root/DayCycle")
	return int(dc.day) if dc != null else 1


func _world_seed() -> int:
	var gs := get_node_or_null("/root/GameState")
	return int(gs.world_seed) if gs != null else 1


## Пересчитывает раскладку облаков на конкретный день — детерминированно
## (см. шапку файла), но с достаточным разбросом, чтобы соседние дни не
## выглядели одинаково: сид мешает world_seed И day, а не только day.
func _regenerate(day: int) -> void:
	_clouds.clear()
	_last_day = day

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("clouds:%d:%d" % [_world_seed(), day])

	var coverage: float
	if rng.randf() < HEAVY_CHANCE:
		coverage = rng.randf_range(HEAVY_COVERAGE_MIN, HEAVY_COVERAGE_MAX)
	else:
		coverage = rng.randf_range(LIGHT_COVERAGE_MIN, LIGHT_COVERAGE_MAX)
	_last_coverage = coverage

	var t: float = clampf(coverage / HEAVY_COVERAGE_MAX, 0.0, 1.0)
	var count: int = clampi(int(round(lerpf(float(CLOUD_COUNT_MIN), float(CLOUD_COUNT_MAX), t))),
		CLOUD_COUNT_MIN, CLOUD_COUNT_MAX)

	# Знак дрейфа — один на весь день (владелец: "каждый день в рандомном
	# направлении"), выбирается тем же rng, что и раскладка, ПОСЛЕ coverage/
	# count — так их подсчёт не сдвигается на единицу вызовов randf() между
	# версиями кода, а порядок вызовов внутри одного _regenerate стабилен.
	var day_dir: float = 1.0 if rng.randf() < 0.5 else -1.0

	for i in range(count):
		var tex_index: int = rng.randi_range(0, maxi(0, _textures.size() - 1))
		var row: float = rng.randf_range(CLOUD_ROW_MIN, CLOUD_ROW_MAX)
		var speed_tiles: float = rng.randf_range(DRIFT_SPEED_MIN_TILES, DRIFT_SPEED_MAX_TILES)
		_clouds.append({
			"tex_index": tex_index,
			"x": rng.randf_range(0.0, CLOUDS_W_LOGICAL),
			"y": -row * TILE,
			"scale": rng.randf_range(SCALE_MIN, SCALE_MAX),
			"alpha": rng.randf_range(ALPHA_MIN, ALPHA_MAX),
			"drift_px_s": speed_tiles * TILE * day_dir,
		})


## Вызывается там же и так же, как Backdrop.update() (scripts/main.gd) —
## cam в КЛЕТКАХ. По X гасим часть сдвига view_root, оставляя
## CLOUDS_PARALLAX_X (тот же приём, что и у горы, см. backdrop.gd). По Y —
## НИЧЕГО не гасим: облака едут с миром 1:1, как трава (см. шапку файла).
func update(cam: Vector2) -> void:
	_last_cam = cam
	var cam_px := cam * TILE
	position = Vector2((1.0 - CLOUDS_PARALLAX_X) * cam_px.x, 0.0)

	var day := _current_day()
	if day != _last_day:
		_regenerate(day)


## Дрейф копится в реальном времени, а не в игровых часах (владелец сказал
## "очень медленно" в ощущаемом темпе, не привязывая к суточному циклу) —
## оборачивается по ширине полосы CLOUDS_W_LOGICAL, чтобы облако, уплывшее
## за край, тут же появлялось с другого: полоса шире окна параллакса (см.
## шапку файла), поэтому шов заворота никогда не виден на экране разом с
## тем местом, откуда облако "вышло".
func _process(dt: float) -> void:
	for cloud in _clouds:
		cloud.x = wrapf(cloud.x + float(cloud.drift_px_s) * dt, 0.0, CLOUDS_W_LOGICAL)
	queue_redraw()


func _visibility_alpha() -> float:
	var dc := get_node_or_null("/root/DayCycle")
	if dc == null:
		return 1.0
	var hour: float = float(dc.hour)
	if hour < VISIBLE_START or hour > VISIBLE_END:
		return 0.0
	if hour < VISIBLE_START + FADE_HOURS:
		return (hour - VISIBLE_START) / FADE_HOURS
	if hour > VISIBLE_END - FADE_HOURS:
		return (VISIBLE_END - hour) / FADE_HOURS
	return 1.0


func _draw() -> void:
	if _textures.is_empty():
		return
	var vis: float = _visibility_alpha()
	if vis <= 0.0:
		return
	for cloud in _clouds:
		var tex: Texture2D = _textures[cloud.tex_index] if cloud.tex_index < _textures.size() else null
		if tex == null:
			continue
		var w: float = tex.get_width() / ART_SCALE_TEX * cloud.scale
		var h: float = tex.get_height() / ART_SCALE_TEX * cloud.scale
		var pos := Vector2(cloud.x - w * 0.5, cloud.y - h * 0.5)
		draw_texture_rect(tex, Rect2(pos, Vector2(w, h)), false,
			Color(1.0, 1.0, 1.0, cloud.alpha * vis))


# ---------------------------------------------------------------------------
# Публичные хуки для тестов (tests/test_clouds.gd) — тот же приём, что у
# SkyView.debug_star_count()/backdrop.gd: тест не ждёт реальных дней/кадров.
# ---------------------------------------------------------------------------

func debug_cloud_count() -> int:
	return _clouds.size()


func debug_coverage() -> float:
	return _last_coverage


func debug_regenerate_for_day(day: int) -> void:
	_regenerate(day)


func debug_cloud_drift_px_s(i: int) -> float:
	return float(_clouds[i].drift_px_s) if i >= 0 and i < _clouds.size() else 0.0


func debug_cloud_x(i: int) -> float:
	return float(_clouds[i].x) if i >= 0 and i < _clouds.size() else 0.0


func debug_advance(dt: float) -> void:
	_process(dt)


func debug_visibility_alpha() -> float:
	return _visibility_alpha()

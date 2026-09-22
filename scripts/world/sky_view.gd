class_name SkyView
extends Node2D
## SkyView — солнце, месяц и звёзды над огородом (цвет самого неба красит
## world_view.gd:_sky_color через DayCycle.sky_dark() — см. комментарий там
## же про то, почему это НЕ отдельный слой: у неба нет тумана войны, и
## подмешать темноту в уже готовый градиент проще и надёжнее, чем городить
## полноэкранный оверлей поверх непрозрачных тайлов того же пула спрайтов).
##
## Этот узел рисует то, что градиентом не нарисовать: небесный градиент — сам
## (_draw(), на всю ширину окна камеры, ширина растёт и падает вместе с ним —
## заливке "период повтора" не нужен). Диск солнца, серп месяца и мерцающее
## поле звёзд — отдельный ребёнок _celestial (см. ниже): по заданию владельца
## они образуют СВОЙ слой заднего плана — ширина ПОЛОСЫ (не окна камеры!) на
## 10% больше горы (Backdrop.MOUNTAIN_W_LOGICAL), параллакс на 10% МЕНЬШЕ
## (значит эта полоса едет ещё медленнее горы — она глубже неё), и она
## ЗАКРЕПЛЕНА ПО ВЫСОТЕ так же, как гора (_celestial.position компенсирует
## сдвиг камеры по Y ПОЛНОСТЬЮ — тот же приём, что backdrop.gd:update()
## делает для _mountain_layer, см. его шапку файла). Он — ребёнок ViewRoot
## В ГЛАВНОЙ СЦЕНЕ, сразу после WorldView (main.gd), рисуется ПОСЛЕ него
## (позже в списке детей = поверх), потому что тайлы неба у WorldView
## непрозрачные — под ними солнце/звёзды были бы не видны.
##
## В катсценах (scripts/story/cutscene_player.gd) этот же узел ставится
## дочерним, когда включён use_day_cycle(true) — см. CutscenePlayer._build();
## там своя локальная система координат сцены (нет камеры вообще, значит нет
## и параллакса/фиксации по высоте — сцена просто не двигает ни SkyView, ни
## его _celestial), поэтому set_scene_rect() держит СТАРУЮ, простую схему:
## светила и звёзды раскиданы по ширине vp.x "как есть", без периода и без
## компенсации Y — см. _mode_scene ниже.

const TILE: int = preload("res://scripts/world/world_view.gd").TILE
const SKY_HEIGHT: int = preload("res://scripts/world/world_view.gd").SKY_HEIGHT

const STAR_ATLAS_PATH := "res://art/env/stars.png"
const STAR_META_PATH := "res://art/env/stars.json"
const SUN_TEX_PATH := "res://art/env/sun.png"
const MOON_TEX_PATH := "res://art/env/moon.png"

## Атлас/спрайты нарезаны в ART_SCALE раз крупнее логических пикселей (тот же
## приём, что у тайлов/персонажей, см. import_art.ART_SCALE и
## world_view.gd:_set_texture) — рисуем уменьшенными в это же число раз.
const ART_SCALE_TEX := 3.0

## Ширина ПОЛОСЫ, на которую раскиданы звёзды/расчерчена дуга солнца-месяца
## (не окно камеры!) и её X-параллакс — задание владельца (первый заход):
## "ширина неба на 10% шире горы... на 10% меньше параллакс, чем гора". Гора —
## Backdrop (MOUNTAIN_W_LOGICAL=800, MOUNTAIN_PARALLAX_X=0.35), Backdrop уже
## class_name, поэтому берём константы прямо оттуда, а не дублируем числа. Эти
## две константы остаются как есть — ими по-прежнему рисуются СОЛНЦЕ и МЕСЯЦ
## (_celestial, см. ниже), для которых ничего не менялось.
const SKY_W_LOGICAL: float = Backdrop.MOUNTAIN_W_LOGICAL * 1.1        # 880
const SKY_PARALLAX_X: float = Backdrop.MOUNTAIN_PARALLAX_X * 0.9      # 0.315

## ЗВЁЗДЫ (в отличие от солнца/месяца/горы) рисуются отдельным слоем
## _star_layer, не _celestial — задание владельца (второй заход, отчёт с
## реального iPhone): "на уровне месяца вообще нет звёзд... прорисуй звёзды
## ниже персонажа тоже, так как когда взлетаешь над землёй там просто нет
## звёзд... прорисуй звёздное небо ещё на 10% больше и увеличь параллакс".
##
## Корень первых двух багов ("нет звёзд"/"нет звёзд ниже при полёте") —
## ОДИН: _celestial.position.y раньше ставился РОВНО в cam_px.y (полная
## компенсация сдвига view_root, см. set_camera() ниже, до правки) — слой
## был ЖЁСТКО ПРИКОЛОЧЕН К ЭКРАНУ, как гора (закреплена по высоте — и это
## для горы правильно, она бесконечно далёкая деталь пейзажа). Для звёзд
## это ломает и заметность, и полёт разом: измерено диагностикой
## (tests/tmp_star_diag.gd, удалён) — ровно 28 из 150 звёзд оказываются в
## пределах экрана, и ЭТО ЖЕ САМОЕ число (28/150), БЕЗ ЕДИНОЙ звезды
## разницы, что стоя на земле, что после подъёма на 22 клетки к потолку
## неба: слой вообще не двигался вертикально ни на пиксель, что бы ни делал
## игрок. Фикс — свой параллакс-слой для звёзд (STAR_PARALLAX ниже, есть и
## по X, и по Y, в отличие от _celestial, где Y всегда был жёстко заперт), и
## поле разброса по строкам расширено до самого потолка полёта (см.
## STAR_TOP_ROW), а не только до высоты человеческого роста.
const STAR_W_LOGICAL: float = SKY_W_LOGICAL * 1.1                     # ~968, "ещё на 10% больше"
## Доля движения камеры, которая реально доходит до звёзд — 0 значит "звёзды
## приколочены к экрану" (старое поведение, и есть баг), 1 значит "звёзды
## едут вместе с миром 1:1, как обычный передний план" (слишком быстро для
## фона на глаз, при таком масштабе экрана звёзды бы неслись). 0.85 —
## заметное, почти как у переднего плана, движение и по X, и по Y (раньше по
## Y не было ВООБЩЕ, слой стоял насмерть) — задание владельца "увеличь
## параллакс звёзд" без точного числа, подобрано измерением через
## tests/tmp_star_diag.gd (временный диагностический инструмент, удалён из
## финального коммита): на этом значении видимое число звёзд ощутимо растёт
## по мере подъёма (25 на земле -> 78 у потолка неба, см. STAR_COUNT_WORLD
## ниже), а не остаётся одним и тем же, как было с жёсткой прикруткой.
const STAR_PARALLAX := 0.85

## Столько звёзд раскидано по ОДНОЙ полосе STAR_W_LOGICAL (мировой режим).
## Раньше (STAR_TOP_ROW=12, жёсткая прикрутка к экрану) было 150 — но поле
## разброса стало вдвое выше (STAR_TOP_ROW: 12 -> 24) и на 10% шире
## (STAR_W_LOGICAL), то есть звёзды размазаны по ~2.2× большей площади;
## простое умножение на неё (150 * 2.2 ≈ 330) с новым, не запертым
## параллаксом (STAR_PARALLAX=0.85) всё ещё давало маловато на земле —
## подобрано измерением (tests/tmp_star_diag.gd, временный инструмент,
## удалён из финального коммита) до значения, при котором на земле видно
## около 25 звёзд (цель владельца, тот же расчёт что и раньше — "20-40 в
## типичном окне"), а у самого потолка неба — уже 78 (звёзды честно
## сгущаются с высотой вместе с камерой, не одно и то же число всегда).
const STAR_COUNT_WORLD := 420
## Катсцена (see шапка файла) — старое поведение, звёзды на всю ширину
## экрана сцены (vp.x, обычно ~224px), не трогаем плотность интро.
const STAR_COUNT_SCENE := 260
const STAR_SEED := 20260921

## Полоса вокруг высоты солнца/месяца (~4.5 клетки над землёй), где звёзд
## нет, — чтобы месяц (единственное светило, которое СОСУЩЕСТВУЕТ со
## звёздами ночью — солнце и звёзды по времени суток не пересекаются
## никогда) не наезжал на них силуэтом.
const MOON_GAP_TOP_ROW := 3.3
const MOON_GAP_BOTTOM_ROW := 5.7
## Верхняя граница разброса строк — весь SKY_HEIGHT (потолок полёта, см.
## player.gd:_sky_ceiling()/JET_DEPTH). РАНЬШЕ стояло 12 (половина высоты
## неба, "типичное окно камеры стоящего на земле героя") — из-за жёсткой
## фиксации слоя по Y (см. STAR_PARALLAX выше) это уже само по себе не имело
## значения (звёзды всё равно не двигались), но теперь, когда звёзды честно
## едут с камерой, полю разброса ОБЯЗАНО хватать на весь путь героя вверх —
## иначе на подлёте к потолку кончились бы сами звёзды, а не только вид на
## них (отчёт владельца: "звёзды ниже персонажа тоже", то есть по всей
## высоте полёта, а не только у земли).
const STAR_TOP_ROW := SKY_HEIGHT
## Раскладка звёзд — «дрожащая сетка» (см. _spawn_stars): поле от края
## каждой ячейки, за которое не заходит случайная точка внутри неё, — не 0
## и не 0.5 (иначе звёзды либо садятся на границы соседних ячеек почти
## впритык, либо стягиваются точно в центр и снова читаются как сетка).
const CELL_MARGIN := 0.12
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

## "высота ~4.5 клетки над землёй" — как и раньше, для обоих режимов (см.
## _sun_moon_y()). Диски солнца/месяца теперь настоящие спрайты (art/env/
## sun.png, moon.png — art/_source/sky_clouds_sun_moon_sheet.jpg, см.
## tools/import_clouds.py), а не векторные draw_circle: draw_circle не мог
## дать ни лучи солнца, ни кратеры месяца, которые просил владелец.
const SUN_MOON_WORLD_Y := -4.5 * float(TILE)
## Фолбэк-цвета на случай отсутствия текстур (headless-тест без art/env) —
## тот же грубый рисунок, что был раньше, лучше пустого места.
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
var _tex_sun: Texture2D
var _tex_moon: Texture2D

## true в катсцене (после set_scene_rect()) — см. шапку файла: там нет
## камеры, поэтому нет ни периода/параллакса, ни фиксации по высоте, только
## старая схема "ширина сцены = вся полоса, сдвига нет".
var _mode_scene: bool = false

## Область РАЗБРОСА в ЛОКАЛЬНЫХ координатах: по умолчанию (мировой режим) —
## одна полоса SKY_W_LOGICAL шириной; в катсцене (_mode_scene=true) —
## set_scene_rect() переопределяет на ширину/горизонт/верх экрана сцены.
var _rect_w_px: float = SKY_W_LOGICAL
var _rect_horizon_y: float = 0.0
var _rect_top_y: float = -float(SKY_HEIGHT) * float(TILE)

## Небесный градиент (_draw() этого узла, НЕ _celestial) по-прежнему красится
## во весь диапазон окна камеры — см. _draw_sky_gradient(). _screen_w_px/
## _cam_x_px обновляет main.gd каждый кадр через set_camera().
var _screen_w_px: float = float(WorldGen.WIDTH) * float(TILE)
var _cam_x_px: float = 0.0

## Слой светил (солнце+месяц) — свой Node2D с собственным _draw(), а не
## часть _draw() этого узла: ему нужна СВОЯ позиция (параллакс + фиксация по
## высоте), а _draw()-градиенту — нет (см. шапку файла и backdrop.gd про
## тот же приём с _mountain_layer/_fence_layer). Остаётся ЖЁСТКО закреплён по
## высоте ("всегда ~4.5 клетки над головой") — так и было задумано, не
## трогаем.
var _celestial: Node2D
## Звёзды — ОТДЕЛЬНЫЙ слой от _celestial (см. STAR_PARALLAX выше и его же
## комментарий про баг "звёзды не видно"/"не видно при полёте"): в отличие
## от солнца/месяца, звёздам нужен настоящий параллакс и по X, и по Y, а не
## жёсткая прикрутка к экрану.
var _star_layer: Node2D

var _day_cycle: Node = null


func _ready() -> void:
	_day_cycle = get_node_or_null("/root/DayCycle")
	_load_stars()
	_load_sun_moon()

	# Порядок детей = порядок отрисовки (задание владельца: "звёзды, потом
	# солнце/месяц") — звёздный слой добавлен ПЕРВЫМ, светила рисуются
	# поверх них, как и раньше.
	_star_layer = Node2D.new()
	_star_layer.name = "Stars"
	_star_layer.draw.connect(_draw_stars)
	add_child(_star_layer)

	_celestial = Node2D.new()
	_celestial.name = "Celestial"
	_celestial.draw.connect(_draw_celestial)
	add_child(_celestial)

	_spawn_stars()
	set_process(true)


## Переопределяет область неба под чужую (не мировую) систему координат —
## используется катсценой (её сцена не в клетках 32px, а в своих пикселях
## экрана). horizon_y/top_y — в локальных координатах ЭТОГО узла.
func set_scene_rect(width_px: float, horizon_y: float, top_y: float) -> void:
	_mode_scene = true
	_rect_w_px = width_px
	_rect_horizon_y = horizon_y
	_rect_top_y = top_y
	# У катсцены нет прокрутки камеры — "экран" сцены и есть вся её ширина,
	# а смещение нулевое (see set_camera()); _celestial и _star_layer тоже
	# остаются на Vector2.ZERO (set_camera() в этом режиме больше их не
	# двигает, см. ниже) — точь-в-точь как раньше (катсцены этот агент не
	# трогает, см. задание).
	_screen_w_px = width_px
	_cam_x_px = 0.0
	if _celestial != null:
		_celestial.position = Vector2.ZERO
	if _star_layer != null:
		_star_layer.position = Vector2.ZERO
	_spawn_stars()


## Зовёт main.gd каждый кадр (сразу после world_view.render(cam)). cam — в
## КЛЕТКАХ, как возвращает Main._camera(). Для градиента (этот узел) — как
## раньше, окно камеры. Для _celestial (мировой режим) — параллакс по X
## (SKY_PARALLAX_X от полного сдвига, тот же приём что у Backdrop.
## _mountain_layer) и ПОЛНАЯ компенсация по Y (слой не едет по вертикали —
## "закреплена по высоте, как и гора").
func set_camera(cam: Vector2, view_w_cells: int) -> void:
	_cam_x_px = cam.x * float(TILE)
	_screen_w_px = float(view_w_cells) * float(TILE)
	if _mode_scene:
		return
	var cam_px := cam * float(TILE)
	if _celestial != null:
		_celestial.position = Vector2((1.0 - SKY_PARALLAX_X) * cam_px.x, cam_px.y)
	# Звёзды — свой, куда более "живой" параллакс, и по X, и (что раньше
	# отсутствовало вовсе) по Y (см. STAR_PARALLAX и комментарий у него же):
	# баг владельца "нет звёзд"/"нет звёзд при полёте" был в том, что этот
	# слой двигался ТОЧНО как _celestial (в частности, Y гасился ПОЛНОСТЬЮ,
	# 0% движения) — звёздное поле было прибито к экрану намертво.
	if _star_layer != null:
		_star_layer.position = Vector2((1.0 - STAR_PARALLAX) * cam_px.x, (1.0 - STAR_PARALLAX) * cam_px.y)


func _load_stars() -> void:
	if ResourceLoader.exists(STAR_ATLAS_PATH):
		_star_atlas = load(STAR_ATLAS_PATH)
	if FileAccess.file_exists(STAR_META_PATH):
		var f := FileAccess.open(STAR_META_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_star_regions = parsed.get("regions", [])


func _load_sun_moon() -> void:
	if ResourceLoader.exists(SUN_TEX_PATH):
		_tex_sun = load(SUN_TEX_PATH)
	if ResourceLoader.exists(MOON_TEX_PATH):
		_tex_moon = load(MOON_TEX_PATH)


func _spawn_stars() -> void:
	_stars.clear()
	if _star_regions.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	var count: int = STAR_COUNT_SCENE if _mode_scene else STAR_COUNT_WORLD
	# Строки мировой сетки (0 — горизонт, отрицательные — вверх) переносим в
	# локальные координаты ЭТОГО прямоугольника (может быть меньше/больше
	# мировых 24 клеток — у катсцены своя высота неба, см. set_scene_rect()).
	var row_to_y := func(row: float) -> float:
		var t: float = -row / float(SKY_HEIGHT)  # row=0 -> t=0 (горизонт), row=-SKY_HEIGHT -> t=1 (верх)
		return _rect_horizon_y + t * (_rect_top_y - _rect_horizon_y)

	# Раскладка «дрожащей сеткой» (задание владельца от 2026-09-21: "более
	# рандомно и на 70% более равномерно") — чистый randf_range по X и Y (как
	# было раньше) статистически честен, но на глаз даёт заметные сгустки и
	# пустоты просто по случайности. Тут делим полосу на cols×rows ячеек,
	# перемешиваем их порядок (детерминированно, тем же rng) и внутри каждой
	# занятой ячейки берём случайную точку с полями 6% от края — сетка
	# гарантирует равномерное покрытие, а перемешивание ячеек + случайный
	# сдвиг внутри каждой не дают глазу увидеть ряды/столбцы.
	# Соотношение cols/rows берём из реального размера полосы разброса (ширина
	# против пиксельной высоты полосы STAR_TOP_ROW строк), а не константой:
	# у катсцены (set_scene_rect) своя ширина/высота, сильно отличная от
	# мирового режима.
	#
	# Ширина полосы звёзд — STAR_W_LOGICAL в мировом режиме (СВОЯ, шире
	# SKY_W_LOGICAL/_rect_w_px на 10% — задание владельца "звёздное небо ещё
	# на 10% больше", см. STAR_W_LOGICAL выше), у катсцены — по-прежнему
	# _rect_w_px (там своя, отдельная договорённость, не трогаем).
	var star_w: float = _rect_w_px if _mode_scene else STAR_W_LOGICAL
	var span_top_px: float = row_to_y.call(-float(STAR_TOP_ROW))
	var span_bottom_px: float = row_to_y.call(-1.0)
	var aspect: float = star_w / maxf(1.0, absf(span_top_px - span_bottom_px))
	var cols: int = maxi(1, int(ceil(sqrt(float(count) * aspect))))
	var rows: int = maxi(1, int(ceil(float(count) / float(cols))))
	var total_cells := cols * rows
	var cell_order: Array = range(total_cells)
	for i in range(cell_order.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = cell_order[i]
		cell_order[i] = cell_order[j]
		cell_order[j] = tmp

	for i in range(count):
		var cell: int = cell_order[i % cell_order.size()]
		var cell_x: int = cell % cols
		var cell_y: int = cell / cols
		var region: Dictionary = _star_regions[rng.randi() % _star_regions.size()]
		var jitter_x: float = rng.randf_range(CELL_MARGIN, 1.0 - CELL_MARGIN)
		var jitter_row: float = rng.randf_range(CELL_MARGIN, 1.0 - CELL_MARGIN)
		var x_norm: float = (float(cell_x) + jitter_x) / float(cols)
		var row_norm: float = (float(cell_y) + jitter_row) / float(rows)
		# row берётся из СПЛОШНОГО диапазона (1..STAR_TOP_ROW), единственная
		# поправка — сдвиг прочь из полосы месяца (послечистка уже взятого
		# row, а не отдельная случайная величина, иначе интервал с "дыркой"
		# перекашивает плотность).
		var row: float = 1.0 + row_norm * (float(STAR_TOP_ROW) - 1.0)
		if row > MOON_GAP_TOP_ROW and row < MOON_GAP_BOTTOM_ROW:
			var to_top := row - MOON_GAP_TOP_ROW
			var to_bottom := MOON_GAP_BOTTOM_ROW - row
			row = MOON_GAP_TOP_ROW if to_top < to_bottom else MOON_GAP_BOTTOM_ROW
		# В мировом режиме звёзды больше НЕ идут через _world_y_to_local
		# (та фиксирует Y относительно Backdrop.MOUNTAIN_REF_CAM_Y_PX — приём,
		# рассчитанный на слой, жёстко прибитый к экрану, как гора/солнце/
		# месяц). Звёздный слой теперь сам возит свою позицию параллаксом
		# (см. set_camera()/STAR_PARALLAX), поэтому локальная координата
		# звезды — просто её МИРОВОЙ пиксель Y как есть: тот же приём, что и
		# у обычных тайлов WorldView. В катсцене (_mode_scene) ничего не
		# меняется — _world_y_to_local там и раньше была тождеством.
		var y: float = row_to_y.call(-row) if not _mode_scene else _world_y_to_local(row_to_y.call(-row))
		var star := {
			"region": region,
			"x": x_norm * star_w,
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
	if _celestial != null:
		_celestial.queue_redraw()
	if _star_layer != null:
		_star_layer.queue_redraw()


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
# Публичные хуки для тестов (tests/test_day_cycle.gd, tests/test_backdrop.gd)
# — тот же приём, что и в house_view.gd: тест не должен ждать реальных
# кадров/времени, чтобы убедиться, что звёзды заспавнены асинхронно (разные
# фазы мерцания).
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


## Переводит "мировую"/сценовую Y (см. _sun_moon_y()/row_to_y выше) в
## ЛОКАЛЬНУЮ координату _celestial. В катсцене (_mode_scene) слой не
## компенсирует камеру вовсе (её и нет) — локальная Y равна как считали
## всегда. В мире _celestial.position.y уже полностью гасит сдвиг камеры
## (см. set_camera()), поэтому то, что здесь нарисовано в локальных
## координатах, — уже готовый ЭКРАННЫЙ пиксель: числа переводим через тот
## же "опорная камера стоящего героя" приём, что backdrop.gd делает для
## горы (Backdrop.MOUNTAIN_REF_CAM_Y_PX) — так на типичной высоте стояния
## расклад остаётся ровно таким же, каким был при старой, незакреплённой
## схеме, а выше/ниже (полёт, шахта) светила и звёзды больше не гуляют по
## экрану вместе с камерой.
func _world_y_to_local(world_y: float) -> float:
	if _mode_scene:
		return world_y
	return world_y - Backdrop.MOUNTAIN_REF_CAM_Y_PX


func _sun_moon_y() -> float:
	if _mode_scene:
		# "высота ~4-5 клеток над землёй" — доля от сценового прямоугольника
		# (тот может быть не 24 клетки высотой), как и раньше.
		return _rect_horizon_y - 4.5 * float(TILE) * (_rect_horizon_y - _rect_top_y) \
			/ (float(SKY_HEIGHT) * float(TILE))
	return SUN_MOON_WORLD_Y


## Порядок слоёв на небе — задание владельца (2026-09-21): подложка (см.
## _draw_sky_gradient выше — рисуется этим же узлом, но раньше, до всех
## детей), ЗВЁЗДЫ, потом солнце/месяц, потом уже гора/забор (Backdrop) и
## всё остальное поверх. Звёзды теперь рисует отдельный узел _star_layer,
## добавленный в дерево ПЕРЕД _celestial (см. _ready()) — порядок детей и
## даёт "звёзды, потом солнце/месяц" без явного вызова отсюда.
func _draw_celestial() -> void:
	if _day_cycle == null:
		return
	_draw_sun()
	_draw_moon()


## X солнца/месяца: доля t (-0.1..1.1, "приходит слева/пропадает справа за
## границей") вдоль ПОЛОСЫ — в мировом режиме это SKY_W_LOGICAL (задание
## владельца: "доля вдоль полосы неба, а не окна камеры"; _celestial сам уже
## сдвинут параллаксом, поэтому cam_x_px сюда добавлять не нужно), в
## катсцене — старая ширина экрана сцены (там и есть "вся полоса").
func _sun_moon_x(t: float) -> float:
	if _mode_scene:
		return t * _screen_w_px + _cam_x_px
	return t * SKY_W_LOGICAL


func _draw_sun() -> void:
	var t: float = _day_cycle.sun_t()
	if t < -0.15 or t > 1.15:
		return
	var x: float = _sun_moon_x(t)
	var y: float = _world_y_to_local(_sun_moon_y())
	if _tex_sun != null:
		var w: float = _tex_sun.get_width() / ART_SCALE_TEX
		var h: float = _tex_sun.get_height() / ART_SCALE_TEX
		_celestial.draw_texture_rect(_tex_sun, Rect2(x - w * 0.5, y - h * 0.5, w, h), false)
	else:
		_celestial.draw_circle(Vector2(x, y), SUN_HALO_RADIUS, SUN_HALO_COLOR)
		_celestial.draw_circle(Vector2(x, y), SUN_RADIUS, SUN_COLOR)


func _draw_moon() -> void:
	var t: float = _day_cycle.moon_t()
	if t < -0.15 or t > 1.15:
		return
	var x: float = _sun_moon_x(t)
	var y: float = _world_y_to_local(_sun_moon_y())
	if _tex_moon != null:
		var w: float = _tex_moon.get_width() / ART_SCALE_TEX
		var h: float = _tex_moon.get_height() / ART_SCALE_TEX
		_celestial.draw_texture_rect(_tex_moon, Rect2(x - w * 0.5, y - h * 0.5, w, h), false)
	else:
		_celestial.draw_circle(Vector2(x, y), MOON_RADIUS, MOON_COLOR)
		# Серп: "откусываем" часть диска кругом цвета ночного неба, сдвинутым к
		# краю, — дешёвый и надёжный способ получить полумесяц без масок/шейдера.
		_celestial.draw_circle(Vector2(x + MOON_RADIUS * 0.62, y - MOON_RADIUS * 0.28),
			MOON_RADIUS * 0.92, MOON_BITE_COLOR)


## Отрисовка звёзд — теперь колбэк _star_layer.draw (свой слой, см.
## STAR_PARALLAX и _ready() выше), а не часть _draw_celestial(): звёздам
## нужна ОТДЕЛЬНАЯ позиция узла (параллакс), а не позиция _celestial
## (солнце/месяц, жёстко закреплены по высоте) — раньше оба набора рисовало
## одно и то же _celestial.draw_texture_rect_region(...) с ОДНОЙ на двоих
## позицией узла, и звёзды поэтому были обречены двигаться как солнце с
## месяцем ("приколочены к экрану"), а не как самостоятельный фон.
func _draw_stars() -> void:
	if _star_atlas == null or _day_cycle == null:
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
		var dst_w: float = float(r.w) / ART_SCALE_TEX
		var dst_h: float = float(r.h) / ART_SCALE_TEX
		var pos := Vector2(star.x - dst_w * 0.5, star.y - dst_h * 0.5)
		_star_layer.draw_texture_rect_region(_star_atlas, Rect2(pos, Vector2(dst_w, dst_h)), region,
			Color(1.0, 1.0, 1.0, a))

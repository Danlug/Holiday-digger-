class_name Backdrop
extends Node2D
## Backdrop — фоновая подложка за домом и огородом: гора на дальнем плане
## (за лесом и забором, мягкий параллакс) и забор с лесом на среднем плане
## (двигается с миром вровень). См. art/_source/backdrop_*.jpg и
## tools/import_backdrops.py — там же посчитаны метрики шва и тона.
##
## Место в дереве сцены (scripts/main.gd): внутри view_root, ПЕРВЫМ ребёнком —
## раньше WorldView (тайлы) и HouseSystem (дом), поэтому и тайлы, и дом рисуются
## поверх подложки. Небо — отдельный слой другого агента (SkyView, см. контракт
## в задании); он ложится ещё раньше (ближе к началу списка детей), Backdrop
## его не создаёт и не трогает scripts/world/world_view.gd (_sky_color и
## COLOR_SKY*) — это чужая зона.
##
## Слои — свои Node2D с собственным _draw(), а не Sprite2D/TextureRect: тайлы
## подложки должны повторяться по X на большую ширину, чем сама текстура
## (см. _draw_fence/_draw_mountain), а TextureRect.STRETCH_TILE внутри
## Node2D-дерева (а не Control-иерархии) ведёт себя не всегда предсказуемо.
## Тот же приём уже используется в scripts/world/world_view.gd (_overlay).
##
## Параллакс — не через камеру Node2D, а руками в update(): Main каждый кадр
## сдвигает весь view_root на -cam*TILE (см. scripts/main.gd:_process), и
## Backdrop — child этого view_root, то есть ПОЛУЧАЕТ тот же сдвиг бесплатно.
## Забору это и нужно (двигаться с миром 1:1 — см. ГДД задания), поэтому его
## слой вообще не трогает свою позицию. Горе нужно ДВИГАТЬСЯ МЕДЛЕННЕЕ мира —
## update() компенсирует часть сдвига view_root, прибавляя слою гор
## (1 - MOUNTAIN_PARALLAX_X) * cam.x * TILE: итоговое смещение на экране —
## ровно MOUNTAIN_PARALLAX_X * cam.x * TILE, то есть доля от полного. По Y гора
## компенсирует сдвиг ПОЛНОСТЬЮ (+cam.y * TILE) — на экране она не двигается
## вовсе, пока камера гуляет по вертикали (задание: "гора остаётся у земли").

const TILE := 32.0
const ART_SCALE := 3.0

# ── геометрия забора (art/env/backdrop_fence_*.png, 960×192 текстурных px) ──
const FENCE_TEX_W := 960.0
const FENCE_TEX_H := 192.0
const FENCE_H_LOGICAL := FENCE_TEX_H / ART_SCALE     # 64 — 2 клетки
const FENCE_W_LOGICAL := FENCE_TEX_W / ART_SCALE     # 320 — 10 клеток, период повтора

## Нижние ALPHA_GRAD_LOGICAL логических px картинки прозрачны (см.
## tools/import_backdrops.py:ALPHA_GRAD_PX) — специально: низ подложки ставится
## НИЖЕ мировой линии травы (y=0), заходя в саму клетку травы, а не точно на
## неё. Мир рисуется ПОСЛЕ Backdrop (WorldView — более поздний ребёнок
## view_root, см. scripts/main.gd), поэтому непрозрачный тайл травы поверх
## затухающего хвоста подложки полностью его перекрывает — глазу достаётся
## только уже подогнанная по тону, полностью непрозрачная часть подложки,
## кромка которой стоит точно на y=0. Без этого захода на клетку ниже
## прозрачный градиент был бы виден как исчезающая в пустоту полоска ПЕРЕД
## травой, а не слитая с ней кромка.
const FENCE_ALPHA_GRAD_LOGICAL := 5.0
const FENCE_BOTTOM_Y := FENCE_ALPHA_GRAD_LOGICAL      # низ картинки — мировые Y
const FENCE_TOP_Y := FENCE_BOTTOM_Y - FENCE_H_LOGICAL  # -59

## Ширина мира с запасом по клетке с каждой стороны — на случай, если камера
## упрётся точно в край и краю подложки будет что показать.
const WORLD_WIDTH_LOGICAL := 32.0 * TILE   # WorldGen.WIDTH * TILE, см. world_gen.gd
const FENCE_MARGIN := FENCE_W_LOGICAL

# ── геометрия горы (art/env/backdrop_mountain.png, 2400×480 текстурных px) ──
const MOUNTAIN_TEX_W := 2400.0
const MOUNTAIN_TEX_H := 480.0
const MOUNTAIN_H_LOGICAL := MOUNTAIN_TEX_H / ART_SCALE   # 160 — 5 клеток
const MOUNTAIN_W_LOGICAL := MOUNTAIN_TEX_W / ART_SCALE    # 800 — 25 клеток, период повтора

## Гора закреплена по экрану: update() гасит сдвиг камеры по Y ПОЛНОСТЬЮ (см.
## update() ниже), поэтому её нарисованное положение — уже не мировая
## координата, а прямо ЭКРАННЫЙ пиксель (после полной компенсации итоговое
## глобальное смещение — константа, равная ровно тому Y, что задан в
## _draw_mountain). Число подобрано под опорную раскладку камеры на
## поверхности (портрет 224×480, игрок у земли y=0.5, экран 14 клеток
## высотой — см. scripts/ui/hud.gd:get_view_cells — даёт cam.y = -6.5
## клеток), так чтобы НИЗ горы на экране совпал с тем местом, где в ЭТОТ
## момент рисуется ВЕРХ забора (мировой FENCE_TOP_Y при том же cam.y даёт
## экранный Y = FENCE_TOP_Y - cam.y*TILE): луг горы прячется за лес и забор
## именно тогда, когда игрок стоит на своём огороде — как просил владелец.
## Дальше, пока порог HIDE_BELOW_CAMERA_Y не спрятал весь фон, гора остаётся
## на этом же месте экрана, даже если камера уходит высоко в небо или чуть
## проседает — задание: "по Y не двигается относительно горизонта".
const MOUNTAIN_REF_CAM_Y_PX := -6.5 * TILE
## Низ горы зафиксирован по высоте на уровне леса (задание владельца от
## 2026-09-21: «зафиксить по высоте по уровню леса, на полторы тайла выше
## травы») — ровно −1.5 клетки мировых Y (0 — линия травы, отрицательное —
## выше, в небе): нижний край картинки горы прячется за кронами деревьев
## картинки забора (небо над её лесом прозрачно, см. import_backdrops.py), а
## над кронами остаются только склоны и вершины.
const MOUNTAIN_BOTTOM_WORLD_Y := -1.5 * TILE   # −48: 1.5 клетки выше травы
const MOUNTAIN_BOTTOM_SCREEN_Y := MOUNTAIN_BOTTOM_WORLD_Y - MOUNTAIN_REF_CAM_Y_PX  # 160
const MOUNTAIN_TOP_SCREEN_Y := MOUNTAIN_BOTTOM_SCREEN_Y - MOUNTAIN_H_LOGICAL  # 0

## Доля смещения камеры по X, которую всё-таки получает гора (0.3–0.4 из
## задания). 0.35 — середина диапазона: за пробег через весь тридцатидвух-
## клеточный огород гора уезжает примерно на четверть экрана (224 * 0.35 ≈
## экран/4 при полном проходе камеры), что и просил владелец.
const MOUNTAIN_PARALLAX_X := 0.35

## Запас по X для статичной прорисовки горы: она должна оставаться закрытой
## при любом положении камеры несмотря на смещение параллакса, поэтому лишний
## повтор с каждой стороны сверх WORLD_WIDTH_LOGICAL безопаснее, чем считать
## видимое окно каждый кадр.
const MOUNTAIN_MARGIN := MOUNTAIN_W_LOGICAL

## Порог глубины (в клетках камеры, см. scripts/main.gd:_camera — cam.y > 0
## значит верх экрана уже под землёй): ниже него подложка не рисуется вовсе —
## под землёй её и так не должно быть видно, а гора закреплена по экрану
## (см. update()) и иначе осталась бы висеть в кадре и там. Число не задано
## ГДД — ПРЕДЛОЖЕНО: 2 клетки за кромку с запасом, чтобы не мигало на границе.
const HIDE_BELOW_CAMERA_Y := 2.0

const TEX_MOUNTAIN := "res://art/env/backdrop_mountain.png"
const TEX_FENCE_NOW := "res://art/env/backdrop_fence_white.png"
const TEX_FENCE_GRANDPA := "res://art/env/backdrop_fence_old.png"
const SHADER_GRADE := "res://shaders/grade.gdshader"

var era: String = "now"

var _mountain_layer: Node2D
var _fence_layer: Node2D
var _mountain_mat: ShaderMaterial
var _fence_mat: ShaderMaterial

var _tex_mountain: Texture2D
var _tex_fence_now: Texture2D
var _tex_fence_grandpa: Texture2D

var _last_cam: Vector2 = Vector2.ZERO


func _ready() -> void:
	_load_textures()

	_mountain_layer = Node2D.new()
	_mountain_layer.name = "Mountain"
	_mountain_mat = _make_grade_material()
	_mountain_layer.material = _mountain_mat
	_mountain_layer.draw.connect(_draw_mountain)
	add_child(_mountain_layer)
	# Гора не перерисовывается покадрово (её update() только двигает узел, а
	# не перекладывает рисунок — см. шапку файла), поэтому первый queue_redraw
	# нужен явно: в отличие от забора, у которого его бесплатно даёт
	# set_era() ниже, здесь без этой строки CanvasItem ни разу не позовёт
	# _draw_mountain и слой останется пустым.
	_mountain_layer.queue_redraw()

	_fence_layer = Node2D.new()
	_fence_layer.name = "Fence"
	_fence_mat = _make_grade_material()
	_fence_layer.material = _fence_mat
	_fence_layer.draw.connect(_draw_fence)
	add_child(_fence_layer)

	set_era(era)
	update(Vector2.ZERO)


func _load_textures() -> void:
	if ResourceLoader.exists(TEX_MOUNTAIN):
		_tex_mountain = load(TEX_MOUNTAIN)
	if ResourceLoader.exists(TEX_FENCE_NOW):
		_tex_fence_now = load(TEX_FENCE_NOW)
	if ResourceLoader.exists(TEX_FENCE_GRANDPA):
		_tex_fence_grandpa = load(TEX_FENCE_GRANDPA)


## Цветокоррекция дня/ночи: DayCycle.grade() → uniform'ы шейдера на обоих
## слоях. Читается каждый кадр (три числа — дёшево), автозагрузки нет →
## значения по умолчанию 1.0, картинка как есть.
func _process(_dt: float) -> void:
	var dc := get_node_or_null("/root/DayCycle")
	if dc == null or not dc.has_method("grade"):
		return
	var g: Dictionary = dc.grade()
	for mat in [_mountain_mat, _fence_mat]:
		if mat == null or mat.shader == null:
			continue
		mat.set_shader_parameter("exposure", float(g.get("exposure", 1.0)))
		mat.set_shader_parameter("saturation", float(g.get("saturation", 1.0)))
		mat.set_shader_parameter("contrast", float(g.get("contrast", 1.0)))


func _make_grade_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(SHADER_GRADE):
		mat.shader = load(SHADER_GRADE)
	return mat


## "now" -> белый забор (сейчас), "grandpa" -> старый деревянный (интро деда).
## Переиспользуется CutscenePlayer.set_backdrop_era() для сцен сюжета.
func set_era(new_era: String) -> void:
	era = new_era
	if _fence_layer != null:
		_fence_layer.queue_redraw()


func _fence_texture() -> Texture2D:
	return _tex_fence_grandpa if era == "grandpa" else _tex_fence_now


## Вызывается там же, где двигается камера (scripts/main.gd:_process, следом
## за view_root.position). cam — в КЛЕТКАХ, как возвращает Main._camera() —
## тот же Vector2, которым main.gd двигает view_root и мировой рендер.
func update(cam: Vector2) -> void:
	_last_cam = cam
	var cam_px := cam * TILE

	visible = cam.y < HIDE_BELOW_CAMERA_Y

	if _fence_layer != null:
		# Забору сдвигать нечего: он и так едет 1:1 вместе со всем view_root.
		_fence_layer.position = Vector2.ZERO

	if _mountain_layer != null:
		# По X гасим часть сдвига view_root — остаётся MOUNTAIN_PARALLAX_X от
		# движения камеры. По Y гасим сдвиг целиком — гора не едет по вертикали.
		_mountain_layer.position = Vector2((1.0 - MOUNTAIN_PARALLAX_X) * cam_px.x, cam_px.y)


func _draw_fence() -> void:
	var tex := _fence_texture()
	if tex == null:
		return
	var x := -FENCE_MARGIN
	var x_end := WORLD_WIDTH_LOGICAL + FENCE_MARGIN
	while x < x_end:
		_fence_layer.draw_texture_rect(tex, Rect2(x, FENCE_TOP_Y, FENCE_W_LOGICAL, FENCE_H_LOGICAL), false)
		x += FENCE_W_LOGICAL


func _draw_mountain() -> void:
	if _tex_mountain == null:
		return
	# Статичная широкая полоса вместо пересчёта окна каждый кадр (см. шапку
	# файла): при MOUNTAIN_PARALLAX_X = 0.3–0.4 и cam.x во всём диапазоне
	# мира видимое окно остаётся внутри [-MOUNTAIN_MARGIN, WORLD_WIDTH+MARGIN].
	var x := -MOUNTAIN_MARGIN
	var x_end := WORLD_WIDTH_LOGICAL + MOUNTAIN_MARGIN
	while x < x_end:
		_mountain_layer.draw_texture_rect(_tex_mountain,
				Rect2(x, MOUNTAIN_TOP_SCREEN_Y, MOUNTAIN_W_LOGICAL, MOUNTAIN_H_LOGICAL), false)
		x += MOUNTAIN_W_LOGICAL

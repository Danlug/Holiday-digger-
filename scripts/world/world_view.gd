extends Node2D
## WorldView — рендер видимого окна мира: тайлы, туман войны, ауры обзора,
## подсветка копаемой клетки. Портировано из draw()/drawTile() web/index.html:
## окно перерисовывается на лету из WorldGen/FogOfWar, полная карта нигде
## не хранится как узлы сцены — только пул спрайтов размером с экран.

const TILE := 32

var world: WorldGen = null
var fog: FogOfWar = null
var player: Node = null  # Player, см. scripts/player/player.gd

var view_w: int = 7
var view_h: int = 14

var _pool: Array = []          # Array[Sprite2D], индекс = row*cols + col
var _pool_cols: int = 0
var _pool_rows: int = 0
var _white_tex: ImageTexture

## Высота неба: сколько клеток воздуха лежит над поверхностью (строки
## y = -1 .. -SKY_HEIGHT; y = 0 — сама кромка земли). 24 клетки — середина
## заказанного владельцем диапазона 20–30 и почти два экрана по высоте
## (экран ~14 клеток): подъём на ранце успевает почувствоваться полётом, но
## верх неба видно уже с земли, и небо не превращается в пустую шахту вверх.
##
## Число живёт здесь, потому что небо — это картинка, и рисует её этот файл.
## Из него же его берут камера (scripts/main.gd:_camera) и потолок полёта
## (scripts/player/player.gd): небо обязано кончаться в одной и той же
## клетке и на экране, и в физике, иначе герой упирается в пустоту или
## улетает за нарисованную кромку.
const SKY_HEIGHT := 24

# Цвета вне палитры тайлов (небо, земля-поверхность, неразведанное, ГДД п.12)
# Дневное небо — ровный голубой 81D3F4, самая тёмная ночь — 11053B (решение
# владельца 2026-09-21). Градиента по высоте больше нет: верх и низ одного
# цвета, а суточный цикл ведёт весь купол от дневного к ночному разом.
const COLOR_SKY := Color8(0x81, 0xD3, 0xF4)          # день, у самой земли
const COLOR_SKY_TOP := Color8(0x81, 0xD3, 0xF4)      # день, верхняя кромка неба
const COLOR_SKY_NIGHT := Color8(0x11, 0x05, 0x3B)    # самая тёмная ночь
const COLOR_HORIZON := Color8(0x81, 0xD3, 0xF4)      # полоса горизонта — тот же день
const COLOR_GROUND := Color8(0x3E, 0x5A, 0x2E)
const COLOR_FOG_BLACK := Color8(0x08, 0x06, 0x05)
const COLOR_GRAY_SOLID := Color8(0x2C, 0x24, 0x1B)
const COLOR_GRAY_EMPTY := Color8(0x10, 0x0D, 0x0A)
const COLOR_STAIRCASE := Color8(0x6B, 0x5B, 0x45)
const COLOR_FALLBACK_SOLID := Color8(0x4A, 0x3A, 0x2A)
const COLOR_FALLBACK_EMPTY := Color8(0x0F, 0x0C, 0x09)

var _overlay: Node2D  # дочерний узел с кастомным _draw() поверх тайлов


func _ready() -> void:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white_tex = ImageTexture.create_from_image(img)

	_build_sky_colors()

	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.draw.connect(_on_overlay_draw)
	add_child(_overlay)


func set_view_size(w: int, h: int) -> void:
	view_w = w
	view_h = h
	_rebuild_pool()


func _rebuild_pool() -> void:
	for s in _pool:
		s.queue_free()
	_pool.clear()
	_pool_cols = view_w + 3
	_pool_rows = view_h + 3
	for i in range(_pool_cols * _pool_rows):
		var s := Sprite2D.new()
		s.centered = false
		add_child(s)
		_pool.append(s)
	move_child(_overlay, get_child_count() - 1)


func _set_color(s: Sprite2D, color: Color) -> void:
	s.texture = _white_tex
	s.scale = Vector2(TILE, TILE)
	s.modulate = color


## Тайл на диске в ART_SCALE раз крупнее клетки (см. tools/import_art.py):
## рисуем уменьшенным, чтобы клетка осталась клеткой, а подробности достались
## экрану телефона.
const ART_SCALE := 3.0


func _set_texture(s: Sprite2D, tex: Texture2D) -> void:
	s.texture = tex
	s.scale = Vector2(1.0 / ART_SCALE, 1.0 / ART_SCALE)
	s.modulate = Color.WHITE


var _cam_bx: int = 0    # левый край окна камеры в клетках — overlay рисует по нему декор огорода


## Перерисовывает окно вокруг камеры (в КЛЕТКАХ, см. player.camera()).
func render(cam: Vector2) -> void:
	if world == null or fog == null or _pool.is_empty():
		return
	var bx := int(floor(cam.x))
	var by := int(floor(cam.y))
	_cam_bx = bx

	for r in range(-1, view_h + 2):
		var wy := by + r
		for c in range(-1, view_w + 2):
			var wx := bx + c
			var idx := (r + 1) * _pool_cols + (c + 1)
			if idx < 0 or idx >= _pool.size():
				continue
			var s: Sprite2D = _pool[idx]
			s.position = Vector2(wx * TILE, wy * TILE)
			_paint_cell(s, wx, wy)

	_overlay.queue_redraw()


## Цвета неба по строкам считаются один раз: render() зовут каждый кадр на
## каждую клетку экрана, и lerp на клетку там был бы арифметикой на пустом
## месте. Индекс 0 — строка y = -1 (у самой земли).
var _sky_colors: PackedColorArray = PackedColorArray()


func _build_sky_colors() -> void:
	_sky_colors.resize(SKY_HEIGHT)
	for i in range(SKY_HEIGHT):
		var t: float = float(i) / float(maxi(SKY_HEIGHT - 1, 1))
		_sky_colors[i] = COLOR_SKY.lerp(COLOR_SKY_TOP, t)
	# Горизонт: строка воздуха над самой землёй чуть светлее неба. Без неё
	# кромка земли на тёмном фоне читается не как горизонт, а как обрыв.
	_sky_colors[0] = COLOR_HORIZON


## Цвет строки неба. Выше верхней кромки тоже спрашивают: render() рисует на
## клетку шире экрана, а камера стоит ровно на -SKY_HEIGHT — берём верхний
## цвет, чтобы на кромке не зияла дыра из неинициализированного спрайта.
##
## Затемнение суточного цикла (задание владельца: "синее небо ... постепенно
## темнеет на 90 процентов с 6 до 8 вечера") применяется прямо здесь поверх
## дневного градиента, а не отдельным слоем над тайлами: у неба нет тумана
## войны (см. _paint_cell: wy<0 красится безусловно), поэтому подмешать
## DayCycle.sky_dark() в уже готовый цвет ничего не ломает, и не нужен
## отдельный полноэкранный оверлей, который просвечивал бы сквозь
## непрозрачные тайлы земли/шахты, нарисованные этим же пулом спрайтов ниже
## горизонта.
func _sky_color(wy: int) -> Color:
	var base: Color
	if _sky_colors.is_empty():
		base = COLOR_SKY
	else:
		base = _sky_colors[clampi(-wy - 1, 0, _sky_colors.size() - 1)]
	# sky_dark() идёт 0..0.9 (окна 18–20 и 4–6, см. day_cycle.gd); в самой
	# тёмной точке небо — ровно COLOR_SKY_NIGHT, а не «чёрное на 90 %».
	var day_cycle := get_node_or_null("/root/DayCycle")
	if day_cycle != null:
		var k: float = clampf(day_cycle.sky_dark() / 0.9, 0.0, 1.0)
		base = base.lerp(COLOR_SKY_NIGHT, k)
	return base


func _paint_cell(s: Sprite2D, wx: int, wy: int) -> void:
	# Небо (wy < 0) тайлами больше не красится: сплошная заливка закрывала бы
	# гору и забор (Backdrop), которые лежат между небом и тайлами. Градиент
	# неба рисует SkyView (первый слой ViewRoot) — тем же _sky_color(wy),
	# чтобы цвета и затемнение DayCycle остались в одном месте.
	if wy < 0:
		s.visible = false
		return
	s.visible = true
	if wy == 0:
		var grass := TileArt.grass_texture(wx)
		if grass != null:
			_set_texture(s, grass)
		else:
			_set_color(s, COLOR_GROUND)
		return

	var state := fog.get_state(wx, wy)
	if state == FogOfWar.State.BLACK:
		_set_color(s, COLOR_FOG_BLACK)
		return

	var type := world.get_tile(wx, wy)
	if state == FogOfWar.State.GRAY:
		var solid := type != TileTypes.Type.EMPTY
		_set_color(s, COLOR_GRAY_SOLID if solid else COLOR_GRAY_EMPTY)
		return

	# FULL — ресурс виден
	if type == TileTypes.Type.STAIRCASE:
		_set_color(s, COLOR_STAIRCASE)
		return
	var tex := TileArt.texture_for(type, wx, wy)
	if tex != null:
		_set_texture(s, tex)
	else:
		var solid2 := type != TileTypes.Type.EMPTY
		_set_color(s, COLOR_FALLBACK_SOLID if solid2 else COLOR_FALLBACK_EMPTY)


## Клетки, подсвеченные обучающим заданием. Ставит сюжет (story_director),
## мир только рисует: какие клетки важны — знание сюжета, а не карты.
var _quest_cells: Array = []


func set_quest_cells(cells: Array) -> void:
	_quest_cells = cells
	if _overlay != null:
		_overlay.queue_redraw()


## Летающий декор (бабочки, стрекозы над цветами) — не садится в траву, как
## остальной декор: насекомое над цветком должно висеть, а не тонуть в земле
## вместе со стеблем. Основание остаётся на верхней кромке тайла, как раньше.
const GARDEN_DECOR_FLYING := ["flowers_butterflies", "flowers_dragonfly"]

## Декор огорода (art/env/garden/*.png) поверх тайла травы — деревья, грядки,
## камни. Свой draw_texture_rect, а не спрайт из пула _paint_cell: объекты
## разной высоты (дерево — под три клетки) и должны расти ВВЕРХ от границы
## y=0, залезая в клетки неба, а пул рисует ровно одну клетку на спрайт.
## Чисто декоративно — без коллизии, герой проходит сквозь них насквозь.
##
## Основание объекта — не на верхней кромке тайла травы (иначе он выглядит
## поставленным НА траву), а на середине тайла (решение владельца: объекты
## должны расти ИЗ травы). Трава при этом не перекрывает нижнюю половину:
## декор рисуется на _overlay, который уже лежит поверх пула тайлов (см.
## move_child(_overlay, ...) в _ready), поэтому нижняя половина объекта ложится
## НАД непрозрачной травой, а не под ней. y=0 (верхняя кромка тайла травы) —
## всегда трава: клетка y<1 не участвует в копке (WorldGen.get_tile/dig_cell),
## так что декор никогда не повисает над выкопанной ямой — под травой ямы не
## бывает.
func _draw_garden_decor() -> void:
	if world == null:
		return
	for wx in range(_cam_bx - 1, _cam_bx + view_w + 2):
		# Клетка y=0 (трава) сама никогда не копается (world.get_tile трактует
		# y<1 как EMPTY всегда), но игрок мог выкопать землю ПОД декором
		# (y=1, самый верхний диггаемый слой) — тогда дерево/куст стоял бы
		# прямо над чёрной ямой, повиснув в воздухе. Декор рисуется только
		# над нетронутой землёй.
		if world.is_dug(wx, 1):
			continue
		var name := world.garden_decor_at(wx)
		if name.is_empty():
			continue
		var tex := TileArt.garden_texture(name)
		if tex == null:
			continue
		var w: float = tex.get_width() / ART_SCALE
		var h: float = tex.get_height() / ART_SCALE
		var x: float = wx * TILE + (TILE - w) / 2.0
		# Низ объекта: середина тайла травы — кроме летающего декора (см. выше).
		var base_y: float = 0.0 if GARDEN_DECOR_FLYING.has(name) else TILE / 2.0
		var y: float = base_y - h
		_overlay.draw_texture_rect(tex, Rect2(x, y, w, h), false)


## Припаркованный у устья бурмобиль (GameState.rig_parked_at, см.
## player.gd "Бурмобиль как транспорт" и tools/import_rig_exit.py) — объект
## мира, а не героя: он стоит там и когда герой давно ушёл в дом пешком.
## Свой, отдельный от _draw_garden_decor (та функция и её данные — GARDEN_*
## в world_gen.gd — чужая задача декора огорода, не трогаем).
const RIG_PARKED_TEX_PATH := "res://art/env/drill_mobile_parked.png"
var _rig_parked_tex: Texture2D = null
var _rig_parked_tex_checked: bool = false


func _draw_parked_rig() -> void:
	if not GameState.is_rig_parked():
		return
	# Во время самой анимации выхода/посадки машина уже нарисована как часть
	# кадра rig_exit.png (see character_view._draw_rig_transition) — второй,
	# мировой спрайт поверх неё дал бы удвоенную машину на экране.
	if player != null and String(player.get("rig_transition")) != "":
		return
	if not _rig_parked_tex_checked:
		_rig_parked_tex_checked = true
		if ResourceLoader.exists(RIG_PARKED_TEX_PATH):
			_rig_parked_tex = load(RIG_PARKED_TEX_PATH)
	if _rig_parked_tex == null:
		return
	var cell: Vector2i = GameState.rig_parked_at
	var w: float = _rig_parked_tex.get_width() / ART_SCALE
	var h: float = _rig_parked_tex.get_height() / ART_SCALE
	# Низ машины — на линии земли (верх клетки y=0), центр — по клетке
	# парковки; та же привязка, что у декора огорода до правки середины
	# тайла (машина не "растение", ей стоять на кромке, а не расти из неё).
	var x: float = cell.x * TILE + (TILE - w) / 2.0
	var y: float = cell.y * TILE - h
	_overlay.draw_texture_rect(_rig_parked_tex, Rect2(x, y, w, h), false)


func _on_overlay_draw() -> void:
	_draw_garden_decor()
	_draw_parked_rig()
	if player == null:
		return
	var pcx: float = player.x * TILE
	var pcy: float = player.y * TILE

	# Ауры тумана войны (ГДД п.12): большая — рельеф, меньшая — ресурсы.
	# Радиус берём у самого тумана, а не считаем здесь: нарисованный круг и
	# круг раскрытия обязаны быть одним и тем же кругом, иначе аура переезжает
	# через клетку раньше, чем та открывается.
	var relief_r: float = FogOfWar.vision_radius(GameState.get_vision_terrain_radius()) * TILE
	var res_r: float = FogOfWar.vision_radius(GameState.get_vision_resource_radius()) * TILE
	_overlay.draw_arc(Vector2(pcx, pcy), relief_r, 0, TAU, 48, Color(0.918, 0.867, 0.776, 0.16), 1.0)
	_overlay.draw_arc(Vector2(pcx, pcy), res_r, 0, TAU, 48, Color(0.878, 0.663, 0.231, 0.3), 1.0)

	# Клетки обучающего задания (пять самородков золота): пульсирующая рамка,
	# чтобы их было видно среди породы. Задание висит строкой в интерфейсе, но
	# «на четвёртом уровне» — не адрес: без рамки игрок ходит и ищет.
	if not _quest_cells.is_empty():
		var pulse: float = 0.55 + 0.45 * sin(float(Time.get_ticks_msec()) / 260.0)
		for c: Vector2i in _quest_cells:
			var qx: float = c.x * TILE
			var qy: float = c.y * TILE
			_overlay.draw_rect(Rect2(qx + 1, qy + 1, TILE - 2, TILE - 2),
				Color(0.878, 0.663, 0.231, pulse), false, 2.0)

	# Подсветка копаемой клетки.
	if player.digging != null:
		var d = player.digging
		var dx: float = d.x * TILE
		var dy: float = d.y * TILE
		_overlay.draw_rect(Rect2(dx, dy, TILE, TILE), Color(0, 0, 0, 0.44))
		var frac: float = clampf(d.t / d.total, 0.0, 1.0)
		_overlay.draw_rect(Rect2(dx + 3, dy + TILE - 6, (TILE - 6) * frac, 3), Color8(0xE0, 0xA9, 0x3B))

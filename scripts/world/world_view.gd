extends Node2D
## WorldView — рендер видимого окна мира: тайлы, туман войны, ауры обзора,
## подсветка копаемой клетки. Портировано из draw()/drawTile() web/index.html:
## окно перерисовывается на лету из WorldGen/FogOfWar, полная карта нигде
## не хранится как узлы сцены — только пул спрайтов размером с экран.
##
## Пул кольцевой: клетка (x, y) всегда занимает один и тот же спрайт
## (y mod строк, x mod столбцов), поэтому при прокрутке камеры существующие
## спрайты не трогаются — перекрашивается только входящая полоса клеток. Вид
## клетки пересчитывается лишь когда что-то изменилось: версия мира
## (WorldGen.changes_since — копка, обвал, землетрясение), версия тумана
## (FogOfWar.changed_since) или такт анимации лавы. Неподвижный кадр не делает
## ничего. Подробности и замеры — ГДД §19 «Производительность».

const TILE := 32

var world: WorldGen = null
var fog: FogOfWar = null
var player: Node = null  # Player, см. scripts/player/player.gd

var view_w: int = 7
var view_h: int = 14

var _pool: Array = []          # Array[Sprite2D], индекс = (y mod rows)*cols + (x mod cols)
var _pool_cols: int = 0
var _pool_rows: int = 0
var _white_tex: Texture2D

# Кэш окна: какая клетка сейчас лежит в каждом спрайте и анимирована ли она (лава).
var _slot_wx: PackedInt32Array = PackedInt32Array()
var _slot_wy: PackedInt32Array = PackedInt32Array()
var _slot_lava: PackedByteArray = PackedByteArray()
var _win_ok: bool = false       # окно нарисовано и версии ниже актуальны
var _win_x: int = 0             # левый верхний угол нарисованного окна (с запасом в клетку)
var _win_y: int = 0
var _world_ver: int = -1
var _fog_ver: int = -1
var _seen_world: WorldGen = null
var _seen_fog: FogOfWar = null
var _style_sig: int = -1
var _grandpa: bool = false
var _lava_tick: int = -1
var _row_bi_y: int = -1073741824   # пояс строки — считается один раз на строку
var _row_bi: int = 0
var _check_row: int = 0
var _frame_no: int = 0

## Раз в сколько кадров перепроверять одну строку окна «в лоб» (страховка от правок мира мимо
## WorldGen.version: прямая запись в diffs, динамический overlay вроде ворот арены). 0 — не
## перепроверять (тесты точности явной инвалидации).
var validate_every: int = 2
## Тест: такт лавы вместо часов (<0 — по часам).
var lava_tick_override: int = -1
## Счётчики для замеров и тестов: сколько клеток перекрашено и сколько раз перерисован overlay.
var stat_cells_painted: int = 0
var stat_overlay_redraws: int = 0

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
const COLOR_FALLBACK_SOLID := Color8(0x4A, 0x3A, 0x2A)
const COLOR_FALLBACK_EMPTY := Color8(0x0F, 0x0C, 0x09)

var _overlay: Node2D  # дочерний узел с кастомным _draw() поверх тайлов

## Подземный фон-стена (DeepBackdrop) лежит позади тайлов: пустые клетки не рисуем,
## сквозь них видна стена пояса. Включает main.gd — без стены (тесты, сцены без
## неё) пустота рисуется как раньше, иначе в дырах просвечивало бы небо.
var deep_backdrop_active: bool = false
# Цвета «серой» разведанной породы по поясам (ГДД §4.2): считаются один раз.
var _gray_solid: PackedColorArray = PackedColorArray()
var _gray_empty: PackedColorArray = PackedColorArray()


func _ready() -> void:
	# Белая заливка берётся из общего атласа тайлов: тогда соседние клетки (тайл / туман) идут одним
	# пакетом отрисовки. Нет атласа — отдельная текстура 1x1, как раньше.
	_white_tex = TileArt.white_texture()
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)

	_build_sky_colors()
	for i in range(Biomes.count()):
		_gray_solid.append(Biomes.color_of(i, "gray_solid", COLOR_GRAY_SOLID))
		_gray_empty.append(Biomes.color_of(i, "gray_empty", COLOR_GRAY_EMPTY))

	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.draw.connect(_on_overlay_draw)
	add_child(_overlay)
	get_viewport().size_changed.connect(_on_viewport_resized)


## Окно браузера или поворот телефона растянули вьюпорт: пул размером со старый экран оставил бы
## пустые полосы справа и снизу. Только растим, не сжимаем — чтобы пул не пересобирался туда-сюда.
func _on_viewport_resized() -> void:
	var vp := get_viewport_rect().size
	var need_w := int(ceil(vp.x / TILE))
	var need_h := int(ceil(vp.y / TILE))
	if need_w > view_w or need_h > view_h:
		set_view_size(maxi(view_w, need_w), maxi(view_h, need_h))


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
	_slot_wx.resize(_pool.size())
	_slot_wy.resize(_pool.size())
	_slot_wx.fill(-1073741824)
	_slot_wy.fill(-1073741824)
	_slot_lava.resize(_pool.size())
	_slot_lava.fill(0)
	_lava_list_dirty = true
	_win_ok = false


# Свойства спрайта пула ставим только при изменении: render() идёт каждый кадр на
# каждую клетку, а сеттеры Node2D/CanvasItem обновляют трансформ и перерисовку
# даже при том же значении.
const _SCALE_COLOR := Vector2(TILE, TILE)
const _SCALE_ART := Vector2(1.0 / 3.0, 1.0 / 3.0)


func _set_color(s: Sprite2D, color: Color) -> void:
	if s.texture != _white_tex:
		s.texture = _white_tex
	if s.scale != _SCALE_COLOR:
		s.scale = _SCALE_COLOR
	if s.modulate != color:
		s.modulate = color


## Тайл на диске в ART_SCALE раз крупнее клетки (см. tools/import_art.py):
## рисуем уменьшенным, чтобы клетка осталась клеткой, а подробности достались
## экрану телефона.
const ART_SCALE := 3.0


func _set_texture(s: Sprite2D, tex: Texture2D) -> void:
	if s.texture != tex:
		s.texture = tex
	if s.scale != _SCALE_ART:
		s.scale = _SCALE_ART
	if s.modulate != Color.WHITE:
		s.modulate = Color.WHITE


var _cam_bx: int = 0    # левый край окна камеры в клетках — overlay рисует по нему декор огорода
var _cam_by: int = 0

# Что overlay рисовал в прошлый раз: перерисовываем только при изменении (см. _overlay_dirty).
var _ov_px: float = INF
var _ov_py: float = INF
var _ov_was_digging: bool = false
var _ov_rig_parked: bool = false
var _ov_vision: bool = true
var _ov_cam_x: int = -1073741824
var _ov_cam_y: int = -1073741824
var _ov_idle_frames: int = 0


## Перерисовывает окно вокруг камеры (в КЛЕТКАХ, см. player.camera()). Работает только над тем, что
## изменилось с прошлого кадра; неподвижный кадр почти ничего не стоит.
func render(cam: Vector2) -> void:
	if world == null or fog == null or _pool.is_empty():
		return
	var bx := int(floor(cam.x))
	var by := int(floor(cam.y))
	_cam_bx = bx
	_cam_by = by
	_frame_no += 1
	var cols := _pool_cols
	var rows := _pool_rows
	var x0 := bx - 1
	var y0 := by - 1
	_grandpa = world.era == "grandpa"

	var lt: int = lava_tick_override if lava_tick_override >= 0 else TileArt.lava_tick()
	var lava_changed := lt != _lava_tick
	_lava_tick = lt

	var sig := (1 if _grandpa else 0) | (2 if deep_backdrop_active else 0)
	var full := not _win_ok or sig != _style_sig or world != _seen_world or fog != _seen_fog
	var world_changes: Variant = null
	var fog_changes: Variant = null
	if not full:
		if world.version != _world_ver:
			world_changes = world.changes_since(_world_ver)
			full = world_changes == null
		if not full and fog.version != _fog_ver:
			fog_changes = fog.changed_since(_fog_ver)
			full = fog_changes == null
	var world_dirty := full or world.version != _world_ver

	if full:
		_paint_rect(x0, y0, cols, rows)
	else:
		var dx := x0 - _win_x
		var dy := y0 - _win_y
		if dx != 0 or dy != 0:
			if absi(dx) >= cols or absi(dy) >= rows:
				_paint_rect(x0, y0, cols, rows)
			else:
				# Новые полосы: строки целиком, столбцы — по общим строкам старого и нового окна.
				if dy > 0:
					_paint_rect(x0, y0 + rows - dy, cols, dy)
				elif dy < 0:
					_paint_rect(x0, y0, cols, -dy)
				var ys := maxi(y0, _win_y)
				var ye := mini(y0 + rows, _win_y + rows)
				if dx > 0:
					_paint_rect(x0 + cols - dx, ys, dx, ye - ys)
				elif dx < 0:
					_paint_rect(x0, ys, -dx, ye - ys)
		if world_changes is PackedInt32Array:
			for key: int in world_changes:
				var wx: int = key % WorldGen.WIDTH
				var wy: int = key / WorldGen.WIDTH
				# Копнули клетку — перекрасить её; соседей это не меняет (туман — отдельная версия).
				if wx >= x0 and wx < x0 + cols and wy >= y0 and wy < y0 + rows:
					_paint_at(wx, wy)
		if fog_changes is PackedInt32Array:
			for key: int in fog_changes:
				var fx: int = key % WorldGen.WIDTH
				var fy: int = key / WorldGen.WIDTH
				if fx >= x0 and fx < x0 + cols and fy >= y0 and fy < y0 + rows:
					_paint_at(fx, fy)

	_win_ok = true
	_win_x = x0
	_win_y = y0
	_world_ver = world.version
	_fog_ver = fog.version
	_seen_world = world
	_seen_fog = fog
	_style_sig = sig

	if lava_changed and not full:
		_repaint_lava()

	# Страховочная перепроверка одной строки окна: чинит правки мира мимо version.
	if validate_every > 0 and _frame_no % validate_every == 0:
		_check_row = (_check_row + 1) % rows
		_paint_rect(x0, y0 + _check_row, cols, 1)

	if _overlay_dirty(world_dirty):
		_overlay.queue_redraw()


## Перекрасить прямоугольник мировых клеток (они обязаны лежать в окне камеры).
func _paint_rect(rx: int, ry: int, rw: int, rh: int) -> void:
	if rw <= 0 or rh <= 0:
		return
	var cols := _pool_cols
	var rows := _pool_rows
	for wy in range(ry, ry + rh):
		var row_base := posmod(wy, rows) * cols
		for wx in range(rx, rx + rw):
			var si := row_base + posmod(wx, cols)
			var s: Sprite2D = _pool[si]
			if _slot_wx[si] != wx or _slot_wy[si] != wy:
				_slot_wx[si] = wx
				_slot_wy[si] = wy
				s.position = Vector2(wx * TILE, wy * TILE)
			var lava: int = 1 if _paint_cell(s, wx, wy) else 0
			if _slot_lava[si] != lava:
				_slot_lava[si] = lava
				_lava_list_dirty = true
	stat_cells_painted += rw * rh


func _paint_at(wx: int, wy: int) -> void:
	_paint_rect(wx, wy, 1, 1)


var _lava_list: Array = []
var _lava_list_dirty: bool = true


## Клетки разведанной лавы в окне (Vector2i): ровно те, что нарисованы анимированной лавой. Список
## пересобирается только когда состав изменился; TechWorld берёт его для свечения вместо того, чтобы
## заново спрашивать get_tile и туман у каждой клетки экрана раз в 0,2 с.
func lava_cells() -> Array:
	if _lava_list_dirty:
		_lava_list_dirty = false
		_lava_list = []
		for si in range(_slot_lava.size()):
			if _slot_lava[si] != 0:
				_lava_list.append(Vector2i(_slot_wx[si], _slot_wy[si]))
	return _lava_list


## Смена кадра лавы: трогаем только спрайты, где сейчас лава (их единицы), и только раз в такт.
func _repaint_lava() -> void:
	for si in range(_slot_lava.size()):
		if _slot_lava[si] == 0:
			continue
		var tex := TileArt.lava_texture(_slot_wx[si], _slot_wy[si], _lava_tick)
		if tex != null:
			_set_texture(_pool[si], tex)


## Нужна ли перерисовка overlay (кольца обзора, декор огорода, рамка копки, клетки задания).
func _overlay_dirty(cells_changed: bool) -> bool:
	var dirty := cells_changed
	if _cam_bx != _ov_cam_x or _cam_by != _ov_cam_y:
		_ov_cam_x = _cam_bx
		_ov_cam_y = _cam_by
		dirty = true
	var px := INF
	var py := INF
	var digging := false
	if player != null:
		px = player.x
		py = player.y
		digging = player.digging != null
	if px != _ov_px or py != _ov_py:
		_ov_px = px
		_ov_py = py
		dirty = true
	if digging or _ov_was_digging or not _quest_cells.is_empty():
		dirty = true
	_ov_was_digging = digging
	var parked: bool = GameState.is_rig_parked()
	if parked != _ov_rig_parked or (parked and player != null and String(player.get("rig_transition")) != ""):
		dirty = true
	_ov_rig_parked = parked
	if Settings.show_vision_radius != _ov_vision:
		_ov_vision = Settings.show_vision_radius
		dirty = true
	# Радиусы обзора меняет прокачка, спросить их каждый кадр дороже, чем раз в 15 кадров.
	_ov_idle_frames += 1
	if _ov_idle_frames >= 15:
		dirty = true
	if dirty:
		_ov_idle_frames = 0
		stat_overlay_redraws += 1
	return dirty


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
var _day_cycle: Node = null


func _sky_color(wy: int) -> Color:
	var base: Color
	if _sky_colors.is_empty():
		base = COLOR_SKY
	else:
		base = _sky_colors[clampi(-wy - 1, 0, _sky_colors.size() - 1)]
	# sky_dark() идёт 0..0.9 (окна 18–20 и 4–6, см. day_cycle.gd); в самой
	# тёмной точке небо — ровно COLOR_SKY_NIGHT, а не «чёрное на 90 %».
	# Узел цикла дня ищем один раз: эту функцию SkyView зовёт на каждую из 24 строк неба каждый кадр.
	if _day_cycle == null:
		_day_cycle = get_node_or_null("/root/DayCycle")
	if _day_cycle != null:
		var k: float = clampf(_day_cycle.sky_dark() / 0.9, 0.0, 1.0)
		base = base.lerp(COLOR_SKY_NIGHT, k)
	return base


## Выставляет спрайт под клетку (wx, wy). Возвращает true, если там анимированная лава.
func _paint_cell(s: Sprite2D, wx: int, wy: int) -> bool:
	# Небо (wy < 0) тайлами больше не красится: сплошная заливка закрывала бы
	# гору и забор (Backdrop), которые лежат между небом и тайлами. Градиент
	# неба рисует SkyView (первый слой ViewRoot) — тем же _sky_color(wy),
	# чтобы цвета и затемнение DayCycle остались в одном месте.
	if wy < 0:
		if s.visible:
			s.visible = false
		return false
	if not s.visible:
		s.visible = true
	if wy == 0:
		var grass := TileArt.grass_texture(wx)
		if grass != null:
			_set_texture(s, grass)
		else:
			_set_color(s, COLOR_GROUND)
		return false

	# Эпоха деда (интро-флешбэк на живой карте, см. GameState.era/world.era,
	# scripts/story/cutscene_player.gd) — это не разведка игроком, а память:
	# зритель СМОТРИТ сцену, а не открывает карту сам, поэтому обычный туман
	# войны (маленький радиус обзора вокруг героя — см. FogOfWar.
	# DEFAULT_TERRAIN_RADIUS=2) здесь неуместен и производил ровно ту самую
	# путаницу, которую владелец описал как «тут почему-то тоннель»: узкая
	# аура обзора оставляла почти весь кадр вокруг деда чёрным прямоугольником
	# ещё ДО первой копки — неотличимым на глаз от настоящей вырытой шахты.
	# В эту эпоху порода видна целиком, как в классической (не-мировой)
	# катсцене раньше — а выкопанные дедом клетки всё равно честно пропадают
	# (get_tile вернёт EMPTY для них), просто без наложенного тумана поверх.
	var state: int = FogOfWar.State.FULL if world.era == "grandpa" else fog.get_state(wx, wy)
	if state == FogOfWar.State.BLACK:
		_set_color(s, COLOR_FOG_BLACK)
		return false

	var type := world.get_tile(wx, wy)
	if state == FogOfWar.State.GRAY:
		var solid := type != TileTypes.Type.EMPTY
		if _row_bi_y != wy:
			_row_bi_y = wy
			_row_bi = Biomes.index_at(wy)
		var bi := _row_bi
		if not solid and deep_backdrop_active:
			# известная, но не разведанная пустота: стена пояса, притушенная
			_set_color(s, Color(_gray_empty[bi], 0.55))
			return false
		_set_color(s, _gray_solid[bi] if solid else _gray_empty[bi])
		return false

	# FULL — ресурс виден
	if type == TileTypes.Type.EMPTY and deep_backdrop_active:
		s.visible = false   # сквозь пустоту видна стена пояса
		return false
	var tex: Texture2D
	var is_lava := type == TileTypes.Type.LAVA
	if is_lava:
		tex = TileArt.lava_texture(wx, wy, _lava_tick if _lava_tick >= 0 else TileArt.lava_tick())
	else:
		tex = TileArt.texture_for(type, wx, wy)
	if tex != null:
		_set_texture(s, tex)
		return is_lava
	var solid2 := type != TileTypes.Type.EMPTY
	_set_color(s, COLOR_FALLBACK_SOLID if solid2 else COLOR_FALLBACK_EMPTY)
	return false


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
	# Декор растёт вверх от середины клетки y=0: когда верх экрана ниже этой клетки, его не видно.
	if world == null or _cam_by >= 1:
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
	# через клетку раньше, чем та открывается. Видимость — настройка игрока
	# (Settings.show_vision_radius, панель «Настройки → Отображение»): сам
	# радиус раскрытия тумана она не трогает, только рисование кольца.
	if Settings.show_vision_radius:
		var relief_r: float = FogOfWar.vision_radius(GameState.get_vision_terrain_radius()) * TILE
		var res_r: float = FogOfWar.vision_radius(GameState.get_vision_resource_radius()) * TILE
		# цвет колец — по поясу глубины героя (ГДД §4.2); на поверхности — прежний
		var pb := Biomes.index_at(int(floor(player.y)))
		var c_relief := Biomes.color_of(pb, "aura_relief", Color(0.918, 0.867, 0.776))
		var c_res := Biomes.color_of(pb, "aura_res", Color(0.878, 0.663, 0.231))
		_overlay.draw_arc(Vector2(pcx, pcy), relief_r, 0, TAU, 48, Color(c_relief, 0.2), 1.0)
		_overlay.draw_arc(Vector2(pcx, pcy), res_r, 0, TAU, 48, Color(c_res, 0.34), 1.0)

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

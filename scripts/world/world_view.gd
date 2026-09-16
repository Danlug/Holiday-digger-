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

# Цвета вне палитры тайлов (небо, земля-поверхность, неразведанное, ГДД п.12)
const COLOR_SKY := Color8(0x1D, 0x2A, 0x33)
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


func _set_texture(s: Sprite2D, tex: Texture2D) -> void:
	s.texture = tex
	s.scale = Vector2.ONE
	s.modulate = Color.WHITE


## Перерисовывает окно вокруг камеры (в КЛЕТКАХ, см. player.camera()).
func render(cam: Vector2) -> void:
	if world == null or fog == null or _pool.is_empty():
		return
	var bx := int(floor(cam.x))
	var by := int(floor(cam.y))

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


func _paint_cell(s: Sprite2D, wx: int, wy: int) -> void:
	if wy < 0:
		_set_color(s, COLOR_SKY)
		return
	if wy == 0:
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


func _on_overlay_draw() -> void:
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

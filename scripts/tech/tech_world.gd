class_name TechWorld
extends Node2D
## Объекты мира ветки «Техника»: станция заправки и скважина-качалка на огороде
## и тёплое свечение клеток лавы. Узел лежит в ViewRoot сразу за WorldView и едет
## с камерой, как дом.
##
## Свечение — мягкие аддитивные пятна поверх лавы (отдельный дочерний узел с
## режимом смешивания ADD): дёшево для веба, один спрайт на клетку, пульсирует с
## фазой клетки. Список клеток лавы в кадре пересобирается раз в 0.2 с и при
## смене клетки камеры, а не каждый кадр — get_tile на глубине считает лаву.

const TILE := 32
const SPRITE_H := 64.0
const WELL_SEQUENCE := [0, 1, 2, 3, 2, 1]
const WELL_FPS := 6.0
const GLOW_PX := 96.0

var world: WorldGen = null
var fog: FogOfWar = null

var _station_tex: Texture2D
var _well_tex: Array = []
var _glow_tex: Texture2D
var _glow_node: Node2D
var _t: float = 0.0
var _lava_cells: Array = []
var _rebuild_in: float = 0.0
var _last_cam: Vector2i = Vector2i(-9999, -9999)


func _ready() -> void:
	name = "TechWorld"
	_station_tex = TechUi.tex("station")
	for i in range(4):
		_well_tex.append(TechUi.tex("well_%d" % i))
	_glow_tex = TechUi.tex("glow")
	_glow_node = Node2D.new()
	_glow_node.name = "LavaGlow"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_node.material = mat
	_glow_node.draw.connect(_draw_glow)
	add_child(_glow_node)
	# Сразу за WorldView: поверх тайлов и декора, но под героем.
	var parent := get_parent()
	if parent != null:
		var wv := parent.get_node_or_null("WorldView")
		if wv != null:
			parent.move_child(self, wv.get_index() + 1)


func station_visible() -> bool:
	return FuelRefinery.station_built()


func well_visible() -> bool:
	return IdleWell.is_built() and GameState.era != "grandpa"


func _process(dt: float) -> void:
	_t += dt
	_rebuild_in -= dt
	var cam := _camera_cells()
	if cam != _last_cam or _rebuild_in <= 0.0:
		_last_cam = cam
		_rebuild_in = 0.2
		_rebuild_lava()
	queue_redraw()
	_glow_node.queue_redraw()


## Левый верхний угол видимого окна в клетках (ViewRoot едет на -cam*TILE).
func _camera_cells() -> Vector2i:
	var p := get_parent() as Node2D
	if p == null:
		return Vector2i.ZERO
	return Vector2i(int(floor(-p.position.x / TILE)), int(floor(-p.position.y / TILE)))


func _rebuild_lava() -> void:
	_lava_cells = []
	if world == null:
		return
	# Разведанную лаву в окне уже знает WorldView (рисует её): берём его список, а не гоняем get_tile
	# и туман по всем клеткам экрана (≈0,5 мс на каждое пересобирание раз в 0,2 с).
	var wv := get_parent().get_node_or_null("WorldView") if get_parent() != null else null
	if wv != null and wv.has_method("lava_cells"):
		_lava_cells = wv.lava_cells()
		return
	var cam := _camera_cells()
	var vs := get_viewport_rect().size
	var cols := int(ceil(vs.x / TILE)) + 2
	var rows := int(ceil(vs.y / TILE)) + 2
	if cam.y + rows < LavaField.min_depth():
		return
	for y in range(maxi(cam.y - 1, LavaField.min_depth()), cam.y + rows):
		for x in range(cam.x - 1, cam.x + cols):
			if world.get_tile(x, y) != TileTypes.Type.LAVA:
				continue
			# Свет идёт только от разведанной лавы: свечение из тумана войны выдало бы карту.
			if fog != null and fog.get_state(x, y) != FogOfWar.State.FULL:
				continue
			_lava_cells.append(Vector2i(x, y))


func _draw() -> void:
	if station_visible() and _station_tex != null:
		draw_texture(_station_tex, Vector2(WorldGen.FUEL_STATION_X * TILE, TILE * 0.5 - SPRITE_H))
	if well_visible():
		var frame: int = WELL_SEQUENCE[int(_t * WELL_FPS) % WELL_SEQUENCE.size()]
		var tex: Texture2D = _well_tex[frame]
		if tex != null:
			draw_texture(tex, Vector2(WorldGen.WELL_X * TILE, TILE * 0.5 - SPRITE_H))


func _draw_glow() -> void:
	if _glow_tex == null:
		return
	for c: Vector2i in _lava_cells:
		var phase := float(((c.x * 73856093) ^ (c.y * 19349663)) & 0xFF) / 40.0
		var pulse := 0.55 + 0.25 * sin(_t * 2.2 + phase) + 0.1 * sin(_t * 5.3 + phase * 2.0)
		var center := Vector2((c.x + 0.5) * TILE, (c.y + 0.5) * TILE)
		var r := Rect2(center - Vector2(GLOW_PX, GLOW_PX) * 0.5, Vector2(GLOW_PX, GLOW_PX))
		_glow_node.draw_texture_rect(_glow_tex, r, false, Color(1, 1, 1, pulse * 0.55))

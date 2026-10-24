class_name DeepBackdrop
extends Node2D
## Подземный параллакс-задник (ГДД §4.2): стена пояса глубины, видимая сквозь
## пустые клетки (WorldView их не рисует, см. deep_backdrop_active). Слоистая глина ->
## пещеры -> кристаллы -> магма -> руины -> преисподняя -> пустота -> небеса.
##
## Лежит в ViewRoot между облаками и тайлами. Стена едет медленнее мира
## (PARALLAX), поэтому читается как дальняя поверхность, а не как плитка под
## ногами. У границы поясов два слоя кроссфейдятся. Выше линии земли (y < 0)
## не рисуется — там небо, гора и забор (Backdrop).
##
## Рисуем сами через draw_texture_rect_region по сетке из периодов текстуры (1 текстель =
## 1 логический px, как пиксель руды), а не Sprite2D с region: так легко обрезать по
## линии земли без скачка фазы узора.
##
## Поверх стены — тени кромок: порода, которая нависает над пустотой, отбрасывает на дальнюю
## стену ступенчатую тень (сверху сильнее всего, как при свете сверху-слева). Тени стоят в
## мировых координатах и не едут с параллаксом, поэтому тоннель читается как выемка в породе,
## а стена — как её дальняя плоскость. Пересчитываются только при смене клетки камеры или версии мира.

const TILE := 32.0
## Доли смещения камеры, которые получает стена: чем меньше, тем она «дальше».
const PARALLAX := Vector2(0.55, 0.45)
## Яркость стены уже запечена в PNG (tools/walls_deep.py): она тёмная и низкоконтрастная, чтобы герой,
## руда и монстры читались поверх. Множитель оставлен для общей подстройки.
const DIM := 1.0
## Ступени тени от кромки вглубь (по SHADE_STEP_PX пикселей на ступень): пиксельная лесенка, не размытие.
const SHADE_TOP := [0.60, 0.44, 0.30, 0.19, 0.10, 0.04]
const SHADE_SIDE := [0.42, 0.28, 0.16, 0.07]
const SHADE_BOTTOM := [0.34, 0.18, 0.07]
const SHADE_STEP_PX := 2.0

var _cam := Vector2.ZERO
var _view := Vector2(7, 14)
var _tex: Dictionary = {}
var _wv: Node = null
var _shade_key := Vector3i(-99999, -99999, -1)
var _shade_rects := PackedVector2Array()   # позиция клетки (x, y в мировых клетках)
var _shade_masks := PackedInt32Array()     # бит 1 — сверху, 2 — слева, 4 — справа, 8 — снизу
var _ramps: Dictionary = {}
var _grid := PackedByteArray()
var _grid_x := 0
var _grid_y := 0
var _grid_w := 0
var _grid_h := 0
var _grid_ver := -1
var _grid_world: WorldGen = null


func update(cam: Vector2, view_w: int, view_h: int) -> void:
	_cam = cam
	_view = Vector2(view_w, view_h)
	visible = cam.y + float(view_h) > 0.0
	if visible:
		queue_redraw()


func _wall_texture(wall: String) -> Texture2D:
	if _tex.has(wall):
		return _tex[wall]
	var path := "res://art/env/deep/wall_%s.png" % wall
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex[wall] = t
	return t


func _draw() -> void:
	var depth := _cam.y + _view.y * 0.5
	var bl := Biomes.blend_at(depth)
	var wa := String(Biomes.get_biome(int(bl["a"])).get("wall", ""))
	_draw_layer(wa, 1.0)
	if float(bl["t"]) > 0.0:
		var wb := String(Biomes.get_biome(int(bl["b"])).get("wall", ""))
		if wb != wa:
			_draw_layer(wb, float(bl["t"]))
	_draw_edge_shade()


func _draw_layer(wall: String, alpha: float) -> void:
	var tex := _wall_texture(wall)
	if tex == null:
		return
	var period := float(tex.get_width())
	var cam_px := _cam * TILE
	var phase := Vector2(fposmod(-PARALLAX.x * cam_px.x, period), fposmod(-PARALLAX.y * cam_px.y, period))
	var origin := cam_px + phase - Vector2(period, period)
	var cols := int(ceil(_view.x * TILE / period)) + 2
	var rows := int(ceil(_view.y * TILE / period)) + 2
	var col := Color(DIM, DIM, DIM, alpha)
	for j in range(rows):
		for i in range(cols):
			var dst := Rect2(origin + Vector2(i * period, j * period), Vector2(period, period))
			if dst.end.y <= 0.0:
				continue
			var src := Rect2(0, 0, period, period)
			if dst.position.y < 0.0:
				var cut := -dst.position.y
				dst = Rect2(dst.position.x, 0.0, period, period - cut)
				src = Rect2(0, cut, period, period - cut)
			draw_texture_rect_region(tex, dst, src, col)


## Лесенка тени: текстура 1 x n (вертикальная) или n x 1 (горизонтальная) из чёрного с убывающей альфой.
func _ramp(steps: Array, vertical: bool) -> Texture2D:
	var key := "%s%d" % ["v" if vertical else "h", steps.size() * 1000 + int(float(steps[0]) * 100.0)]
	if _ramps.has(key):
		return _ramps[key]
	var n := steps.size()
	var img := Image.create(1 if vertical else n, n if vertical else 1, false, Image.FORMAT_RGBA8)
	for i in range(n):
		var c := Color(0, 0, 0, float(steps[i]))
		if vertical:
			img.set_pixel(0, i, c)
		else:
			img.set_pixel(i, 0, c)
	var t := ImageTexture.create_from_image(img)
	_ramps[key] = t
	return t


func _world_of_view() -> WorldGen:
	if _wv == null or not is_instance_valid(_wv):
		var p := get_parent()
		_wv = p.get_node_or_null("WorldView") if p != null else null
	if _wv == null:
		return null
	return _wv.get("world") as WorldGen


func _rebuild_shade(world: WorldGen, x0: int, y0: int, cols: int, rows: int) -> void:
	_shade_rects.clear()
	_shade_masks.clear()
	var w := cols + 2
	var h := rows + 2
	var ox := x0 - 1
	var oy := y0 - 1
	# Окно «порода/не порода» двигается по миру: при той же версии мира старые клетки берём из прошлого окна,
	# get_tile зовём только для новой полосы (иначе ~170 вызовов на каждую смену клетки камеры).
	var reuse := _grid_ver == world.version and _grid_w == w and _grid_h == h \
			and absi(ox - _grid_x) < w and absi(oy - _grid_y) < h and world == _grid_world
	var solid := PackedByteArray()
	solid.resize(w * h)
	for j in range(h):
		var oj := oy + j - _grid_y
		for i in range(w):
			var oi := ox + i - _grid_x
			if reuse and oi >= 0 and oi < w and oj >= 0 and oj < h:
				solid[j * w + i] = _grid[oj * w + oi]
			else:
				var t := world.get_tile(ox + i, oy + j)
				solid[j * w + i] = 1 if (t != TileTypes.Type.EMPTY and t != TileTypes.Type.LAVA) else 0
	_grid = solid
	_grid_x = ox
	_grid_y = oy
	_grid_w = w
	_grid_h = h
	_grid_ver = world.version
	_grid_world = world
	for j in range(rows):
		for i in range(cols):
			var k := (j + 1) * w + (i + 1)
			if solid[k] == 1:
				continue
			var m := 0
			if solid[k - w] == 1:
				m |= 1
			if solid[k - 1] == 1:
				m |= 2
			if solid[k + 1] == 1:
				m |= 4
			if solid[k + w] == 1:
				m |= 8
			if m != 0:
				_shade_rects.append(Vector2(x0 + i, y0 + j))
				_shade_masks.append(m)


func _draw_edge_shade() -> void:
	var world := _world_of_view()
	if world == null:
		return
	var x0 := int(floor(_cam.x)) - 1
	var y0 := maxi(int(floor(_cam.y)) - 1, 1)
	var cols := int(_view.x) + 3
	var rows := int(_view.y) + 3
	var key := Vector3i(x0, y0, world.version)
	if key != _shade_key:
		_shade_key = key
		_rebuild_shade(world, x0, y0, cols, rows)
	var ramp_top := _ramp(SHADE_TOP, true)
	var ramp_bottom := _ramp(SHADE_BOTTOM, true)
	var ramp_side := _ramp(SHADE_SIDE, false)
	var th := SHADE_TOP.size() * SHADE_STEP_PX
	var bh := SHADE_BOTTOM.size() * SHADE_STEP_PX
	var sw := SHADE_SIDE.size() * SHADE_STEP_PX
	for n in range(_shade_rects.size()):
		var p := _shade_rects[n] * TILE
		var m := _shade_masks[n]
		if m & 1:
			draw_texture_rect(ramp_top, Rect2(p.x, p.y, TILE, th), false)
		if m & 8:
			draw_texture_rect(ramp_bottom, Rect2(p.x, p.y + TILE, TILE, -bh), false)
		if m & 2:
			draw_texture_rect(ramp_side, Rect2(p.x, p.y, sw, TILE), false)
		if m & 4:
			draw_texture_rect(ramp_side, Rect2(p.x + TILE, p.y, -sw, TILE), false)

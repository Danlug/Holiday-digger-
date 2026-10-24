class_name ChestLayer
extends Node2D
## Сундуки в мире: рисуются поверх своей клетки (тайл породы под ними не меняется)
## в ViewRoot сразу над WorldView — поэтому свет глубины и тени ложатся на них так
## же, как на тайлы.
##
## Видимость — правила тумана (ГДД §12): закрытый сундук — содержимое породы, как
## руда, и виден только в полном обзоре; серый туман его не выдаёт. Локатора нет
## (ГДД §16): за пределами обзора о сундуке ничего не известно. Открытый сундук
## лежит в выкопанной клетке, пока она пуста: с добычей — крышка откинута и над
## ним покачивается значок того, что осталось; пустой — притушен.

const TILE := 32
const FRAME_PX := 96
const OPEN_S := 0.42
const ROWS_AROUND := 12

var director: MechDirector = null

var _tex: Dictionary = {}
var _anims: Dictionary = {}      # Vector2i → секунд с начала открытия
var _entries: Array = []          # [{cell, tier, frame, alpha, left_icon}]
var _sig: int = 0
var _time: float = 0.0


func _ready() -> void:
	for t in ["wood", "iron", "gold"]:
		_tex[t] = Mechanics.tex("chest_" + t)


func play_open(cell: Vector2i) -> void:
	if Settings.reduce_motion:
		return
	_anims[cell] = 0.0
	queue_redraw()


func entries() -> Array:
	return _entries


func _process(delta: float) -> void:
	_time += delta
	for c in _anims.keys():
		_anims[c] = float(_anims[c]) + delta
		if float(_anims[c]) > OPEN_S:
			_anims.erase(c)
	var sig := _collect()
	var animated := not _anims.is_empty() or (_has_bob() and not Settings.reduce_motion)
	if sig != _sig or animated:
		_sig = sig
		queue_redraw()


func _has_bob() -> bool:
	for e in _entries:
		if e["left_icon"] != null:
			return true
	return false


## Собирает видимые сундуки около героя. Возвращает подпись (меняется — перерисовать).
func _collect() -> int:
	_entries.clear()
	if director == null or director.world == null or director.fog == null or director.player == null:
		return 0
	if not MechData.gate_open():
		return 0
	var world := director.world
	var fog := director.fog
	var py := int(floor(float(director.player.y)))
	var y0 := maxi(ChestLogic.y_min(), py - ROWS_AROUND)
	var y1 := py + ROWS_AROUND
	if y1 < y0:
		return 0
	var sig := 17
	for band in range(ChestLogic.band_of(y0), ChestLogic.band_of(y1) + 1):
		var ch := director.chest_for_band(band)
		if ch.is_empty():
			continue
		var cell: Vector2i = ch["cell"]
		var state := fog.get_state(cell.x, cell.y)
		var empty := world.get_tile(cell.x, cell.y) == TileTypes.Type.EMPTY
		var opened := MechState.chest_opened(cell)
		var e := {"cell": cell, "tier": String(ch["tier"]), "frame": 0, "alpha": 1.0, "left_icon": null}
		if not opened:
			# закрытый — только в полном обзоре и только пока он в породе
			if state != FogOfWar.State.FULL or empty:
				continue
		else:
			if not empty or state == FogOfWar.State.BLACK:
				continue   # клетку засыпал обвал: сундук открыт, его больше не видно
			var left := MechState.chest_left(cell)
			if left.is_empty():
				e["frame"] = 3
				e["alpha"] = 0.8
			else:
				e["frame"] = 2
				e["left_icon"] = UiIcons.item_small(String(left.keys()[0]), 16)
		sig = sig * 31 + cell.x * 7 + cell.y * 131 + int(e["frame"]) * 3 + (1 if opened else 0)
		_entries.append(e)
	return sig


func _draw() -> void:
	for e in _entries:
		var cell: Vector2i = e["cell"]
		var tex: Texture2D = _tex.get(e["tier"], null)
		if tex == null:
			continue
		var frame := int(e["frame"])
		var scale := 1.0
		if _anims.has(cell):
			var t := float(_anims[cell]) / OPEN_S
			frame = 1 if t < 0.4 else 2 if e["left_icon"] != null or t < 0.9 else int(e["frame"])
			scale = 1.0 + 0.18 * sin(clampf(t, 0.0, 1.0) * PI)
		var rect := Rect2(Vector2(cell.x * TILE, cell.y * TILE), Vector2(TILE, TILE))
		if scale != 1.0:
			# «хлопок» крышки: сундук подпрыгивает от низа клетки
			var grow := Vector2(TILE, TILE) * (scale - 1.0)
			rect = Rect2(rect.position - Vector2(grow.x * 0.5, grow.y), rect.size + grow)
		var src := Rect2(frame * FRAME_PX, 0, FRAME_PX, FRAME_PX)
		draw_texture_rect_region(tex, rect, src, Color(1, 1, 1, float(e["alpha"])))
		if e["tier"] == "gold" and frame == 0 and not Settings.reduce_motion:
			_glint(rect)
		var icon: Texture2D = e["left_icon"]
		if icon != null:
			var bob := 0.0 if Settings.reduce_motion else sin(_time * 3.2 + float(cell.x)) * 1.5
			var at := Vector2(cell.x * TILE + 8, cell.y * TILE - 10 + bob)
			draw_rect(Rect2(at - Vector2(1, 1), Vector2(18, 18)), Color(0.07, 0.05, 0.04, 0.7))
			draw_texture_rect(icon, Rect2(at, Vector2(16, 16)), false)


## Редкий блик на золотом сундуке: раз в ~2.4 с крестик-искра пробегает по крышке.
func _glint(rect: Rect2) -> void:
	var ph := fmod(_time, 2.4) / 2.4
	if ph > 0.18:
		return
	var a := 1.0 - ph / 0.18
	var p := rect.position + Vector2(rect.size.x * (0.3 + ph * 2.0), rect.size.y * 0.36)
	var col := Color(1.0, 0.97, 0.8, a)
	draw_rect(Rect2(p, Vector2(1, 1)), col)
	draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), Color(col, a * 0.6))
	draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), Color(col, a * 0.6))

class_name CaveLayer
extends Node2D
## CaveLayer — вид полости-фигуры (раунд 5): подсвеченная кромка цветом формы,
## лёгкая дымка в воздухе и сундук в центре. Лежит в ViewRoot сразу над
## WorldView (как ChestLayer): тайлы под ним не меняются, свет глубины и тени
## ложатся сверху. Ничего не решает — читает мир, туман и CaveGuards.
##
## Туман — как у всего в мире (ГДД §12): кромка и дымка видны, когда клетка не
## чёрная (рельеф), сундук — только в полном обзоре (содержимое). Локатора нет.
## Сундук: заперт (цепи, красный свет), пока живы стражи; отперт — обычный
## закрытый с бликом; открыт — крышка откинута и значок остатка, пуст — притушен.

const TILE := 32
const FRAME_PX := 96
const ROWS_AROUND := 14
const OPEN_S := 0.42
const FRAME_LOCKED := 4

var director: Node = null

var _tex: Texture2D = null
var _glow: Texture2D = null
var _entries: Array = []
var _anims: Dictionary = {}
var _scan_left: float = 0.0
var _pulse_left: float = 0.0
var _time: float = 0.0
var _sig: int = 0


func _ready() -> void:
	_tex = Mechanics.tex("chest_cave")
	var gp := "res://art/fx/glow_soft.png"
	_glow = load(gp) if ResourceLoader.exists(gp) else null
	GameState.game_event.connect(_on_event)


func _exit_tree() -> void:
	if GameState.game_event.is_connected(_on_event):
		GameState.game_event.disconnect(_on_event)


func _on_event(id: StringName, data: Dictionary) -> void:
	if id != &"chest_opened" or Settings.reduce_motion:
		return
	var cell: Vector2i = data.get("cell", Vector2i(-1, -1))
	for e in _entries:
		if not e["chest"].is_empty() and e["chest"]["cell"] == cell:
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
	_scan_left -= delta
	_pulse_left -= delta
	if _scan_left <= 0.0:
		_scan_left = 0.1
		var sig := _collect()
		if sig != _sig:
			_sig = sig
			queue_redraw()
	if not _entries.is_empty() and (not _anims.is_empty() or (not Settings.reduce_motion and _pulse_left <= 0.0)):
		_pulse_left = 0.08
		queue_redraw()


func _air(c: Dictionary, dx: int, dy: int) -> bool:
	return Caves.in_shape(c, dx, dy) and not (dx == 0 and dy == 1)


## Полости у героя: клетки кромки с масками сторон, обращённых к воздуху, дымка, сундук.
func _collect() -> int:
	_entries.clear()
	if director == null or director.world == null or director.fog == null or director.player == null:
		return 0
	var world: WorldGen = director.world
	var fog = director.fog
	var py := int(floor(float(director.player.y)))
	var sig := 17
	for c in Caves.caves_between(world, py - ROWS_AROUND, py + ROWS_AROUND):
		if int(c.y1) < py - ROWS_AROUND or int(c.y0) > py + ROWS_AROUND:
			continue
		var r := int(c.r)
		var cx := int(c.cx)
		var cy := int(c.cy)
		var rim: Array = []
		var haze: Array = []
		for dy in range(-r - 1, r + 2):
			for dx in range(-r - 1, r + 2):
				var cell := Vector2i(cx + dx, cy + dy)
				if fog.get_state(cell.x, cell.y) == FogOfWar.State.BLACK:
					continue
				var altar := dx == 0 and dy == 1
				if _air(c, dx, dy):
					haze.append(cell)
					continue
				if not altar and not Caves.is_rim(c, dx, dy):
					continue
				if world.get_tile(cell.x, cell.y) == TileTypes.Type.EMPTY:
					continue   # кромку выкопали
				var mask := 0
				if _air(c, dx, dy - 1):
					mask |= 1
				if _air(c, dx + 1, dy):
					mask |= 2
				if _air(c, dx, dy + 1):
					mask |= 4
				if _air(c, dx - 1, dy):
					mask |= 8
				if mask == 0:
					continue
				rim.append([cell, mask])
				sig = sig * 31 + cell.x * 7 + cell.y * 131 + mask
		var chest := {}
		var ccell := Caves.chest_cell(c)
		if fog.get_state(ccell.x, ccell.y) == FogOfWar.State.FULL:
			var state := CaveGuards.chest_state(c)
			chest = {"cell": ccell, "state": state, "icon": null}
			if state == "loot":
				var left := MechState.chest_left(ccell)
				if not left.is_empty():
					chest["icon"] = UiIcons.item_small(String(left.keys()[0]), 16)
			sig = sig * 31 + ccell.x * 13 + ccell.y * 17 + state.hash() % 1000
		if rim.is_empty() and haze.is_empty() and chest.is_empty():
			continue
		sig = sig * 7 + haze.size()
		_entries.append({"cave": c, "rim": rim, "haze": haze, "chest": chest, "color": Caves.color_of(c)})
	return sig


func _draw() -> void:
	var calm := Settings.reduce_motion
	var pulse := 1.0 if calm else 0.5 + 0.5 * sin(_time * 2.4)
	for e in _entries:
		var col: Color = e["color"]
		var chest: Dictionary = e["chest"]
		var locked: bool = not chest.is_empty() and chest["state"] == "locked"
		# дымка: воздух полости чуть окрашен цветом формы — полость читается как место
		var haze_col := Color(col, 0.05 + 0.02 * pulse)
		for cell: Vector2i in e["haze"]:
			draw_rect(Rect2(cell.x * TILE, cell.y * TILE, TILE, TILE), haze_col)
		# кромка: светлая полоса по краю камня, обращённому к воздуху, и тёмная тень под ней
		var bright := Color(col, 0.75 + 0.25 * pulse)
		var dark := Color(col.darkened(0.55), 0.85)
		for pair in e["rim"]:
			var cell: Vector2i = pair[0]
			var mask: int = pair[1]
			var px := float(cell.x * TILE)
			var py := float(cell.y * TILE)
			if mask & 1:
				draw_rect(Rect2(px, py, TILE, 2), bright)
				draw_rect(Rect2(px, py + 2, TILE, 1), dark)
			if mask & 4:
				draw_rect(Rect2(px, py + TILE - 2, TILE, 2), bright)
				draw_rect(Rect2(px, py + TILE - 3, TILE, 1), dark)
			if mask & 8:
				draw_rect(Rect2(px, py, 2, TILE), bright)
				draw_rect(Rect2(px + 2, py, 1, TILE), dark)
			if mask & 2:
				draw_rect(Rect2(px + TILE - 2, py, 2, TILE), bright)
				draw_rect(Rect2(px + TILE - 3, py, 1, TILE), dark)
		if chest.is_empty() or _tex == null:
			continue
		_draw_chest(chest, col, locked, pulse)


func _draw_chest(chest: Dictionary, col: Color, locked: bool, pulse: float) -> void:
	var cell: Vector2i = chest["cell"]
	var state := String(chest["state"])
	var rect := Rect2(Vector2(cell.x * TILE, cell.y * TILE), Vector2(TILE, TILE))
	var center := rect.get_center()
	# свет под сундуком: цвет формы, у запертого — красный, у пустого — нет
	if _glow != null and state != "empty":
		var gc := Color("FF6A5A") if locked else col
		var ga := (0.18 if locked else 0.28) + 0.12 * pulse
		var gs := 60.0 + 6.0 * pulse
		draw_texture_rect(_glow, Rect2(center - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false, Color(gc, ga))
	var frame := FRAME_LOCKED if locked else (0 if state == "closed" else (2 if state == "loot" else 3))
	var alpha := 0.8 if state == "empty" else 1.0
	var scale := 1.0
	if _anims.has(cell):
		var t := float(_anims[cell]) / OPEN_S
		frame = 1 if t < 0.4 else 2
		scale = 1.0 + 0.18 * sin(clampf(t, 0.0, 1.0) * PI)
	if scale != 1.0:
		var grow := Vector2(TILE, TILE) * (scale - 1.0)
		rect = Rect2(rect.position - Vector2(grow.x * 0.5, grow.y), rect.size + grow)
	var src := Rect2(frame * FRAME_PX, 0, FRAME_PX, FRAME_PX)
	draw_texture_rect_region(_tex, rect, src, Color(1, 1, 1, alpha))
	if state == "closed" and not Settings.reduce_motion:
		_glint(rect, col)
	var icon: Texture2D = chest["icon"]
	if icon != null:
		var bob := 0.0 if Settings.reduce_motion else sin(_time * 3.2 + float(cell.x)) * 1.5
		var at := Vector2(cell.x * TILE + 8, cell.y * TILE - 10 + bob)
		draw_rect(Rect2(at - Vector2(1, 1), Vector2(18, 18)), Color(0.07, 0.05, 0.04, 0.7))
		draw_texture_rect(icon, Rect2(at, Vector2(16, 16)), false)


## Блик отпертого сундука — крестик-искра пробегает по крышке раз в ~2 с.
func _glint(rect: Rect2, col: Color) -> void:
	var ph := fmod(_time, 2.0) / 2.0
	if ph > 0.2:
		return
	var a := 1.0 - ph / 0.2
	var p := rect.position + Vector2(rect.size.x * (0.28 + ph * 2.2), rect.size.y * 0.34)
	var c := Color(col.lightened(0.6), a)
	draw_rect(Rect2(p, Vector2(1, 1)), c)
	draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), Color(c, a * 0.6))
	draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), Color(c, a * 0.6))

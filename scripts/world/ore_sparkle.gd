class_name OreSparkle
extends Node2D
## Искра на самоцветах и золоте (зона ore-look): на разведанной клетке драгоценной руды раз в несколько
## секунд вспыхивает крестик-блик в четыре фазы — тайл «живой», но не мигает. У каждой клетки свой ритм и
## своя точка блика (от мировых координат): соседние клетки не вспыхивают хором. Settings.reduce_motion —
## искр нет совсем (статичный блик уже нарисован в тайле). Цена: раз в 0,2 с обход окна камеры
## (WorldView.window_rect(), ~180 клеток, get_tile из кэша) и 0–3 крестика из прямоугольников на кадр.
## Лежит в overlay WorldView: поверх тайлов, под героем и HUD.

const TILE := 32.0
const PERIOD := 3.4      # с: полный цикл одной клетки
const FLASH := 0.42      # с: сколько длится вспышка (4 фазы)
const SCAN_EVERY := 0.2  # с: как часто пересобирать список клеток

## Цвет лучей по типу руды; центр крестика всегда белый.
const COLORS := {
	TileTypes.Type.GOLD_ORE: Color(1.0, 0.93, 0.62),
	TileTypes.Type.SILVER_ORE: Color(0.87, 0.93, 1.0),
	TileTypes.Type.PLATINUM_ORE: Color(0.9, 0.95, 1.0),
	TileTypes.Type.DIAMOND: Color(0.8, 1.0, 1.0),
	TileTypes.Type.RUBY: Color(1.0, 0.72, 0.8),
	TileTypes.Type.EMERALD: Color(0.72, 1.0, 0.82),
	TileTypes.Type.GEOCRYSTAL: Color(1.0, 0.88, 0.6),
	TileTypes.Type.UNIVERSALIUM: Color(0.95, 0.98, 1.0),
	TileTypes.Type.ANGEL_STONE: Color(1.0, 0.95, 0.7),
	TileTypes.Type.DIVINE_HEART: Color(1.0, 0.8, 0.88),
}

var world_view: Node2D = null   # WorldView: даёт world, fog и окно камеры
var _t: float = 0.0
var _scan_t: float = 0.0
var _cells: Array = []          # [[wx, wy, Color], …] — разведанные клетки искристой руды в окне
var _drawn: int = -1            # сколько искр нарисовано в прошлый кадр: перерисовка только при изменении
var _drawn_sig: int = -1


func _process(delta: float) -> void:
	if Settings.reduce_motion or world_view == null:
		if _drawn != 0:
			_drawn = 0
			_drawn_sig = -1
			queue_redraw()
		return
	_t += delta
	_scan_t += delta
	if _scan_t >= SCAN_EVERY:
		_scan_t = 0.0
		_rescan()
	# подпись кадра: какие клетки и в какой фазе — рисуем заново только когда она сменилась
	var sig := 0
	var n := 0
	for c in _cells:
		var ph := _phase(c[0], c[1])
		if ph >= 0:
			n += 1
			sig = (sig * 31 + c[0] * 7 + c[1] * 131 + ph) & 0x3FFFFFFF
	if n != _drawn or sig != _drawn_sig:
		_drawn = n
		_drawn_sig = sig
		queue_redraw()


func _rescan() -> void:
	_cells.clear()
	var wv := world_view
	if not wv.has_method("window_rect") or wv.world == null or wv.fog == null:
		return
	var r: Rect2i = wv.window_rect()
	var world = wv.world
	var fog = wv.fog
	for wy in range(maxi(r.position.y, 1), r.position.y + r.size.y):
		for wx in range(maxi(r.position.x, 0), mini(r.position.x + r.size.x, WorldGen.WIDTH)):
			var type: int = world.get_tile(wx, wy)
			if not COLORS.has(type):
				continue
			if fog.get_state(wx, wy) != FogOfWar.State.FULL:
				continue
			_cells.append([wx, wy, COLORS[type]])


## Фаза вспышки клетки: 0..3 во время вспышки, -1 — спит.
func _phase(wx: int, wy: int) -> int:
	var h: int = ((wx * 73856093) ^ (wy * 19349663) ^ 0x27d4eb2f) & 0xFFFF
	var local := fmod(_t + float(h) / 65535.0 * PERIOD, PERIOD)
	if local >= FLASH:
		return -1
	return mini(int(local / FLASH * 4.0), 3)


## Точка блика внутри клетки — в средней части тайла, у каждой клетки своя (там, где у залежи грань или
## самородок, точно не угадать: вариант раскладки выбирает TileArt; середина тайла всегда занята залежью).
func _anchor(wx: int, wy: int) -> Vector2:
	var h: int = ((wx * 83492791) ^ (wy * 2654435761)) & 0xFFFF
	var ax := 10.0 + float(h & 0xFF) / 255.0 * 12.0
	var ay := 9.0 + float((h >> 8) & 0xFF) / 255.0 * 12.0
	return Vector2(float(wx) * TILE + floorf(ax), float(wy) * TILE + floorf(ay))


func _draw() -> void:
	if _drawn <= 0:
		return
	for c in _cells:
		var ph := _phase(c[0], c[1])
		if ph < 0:
			continue
		var p := _anchor(c[0], c[1])
		var col: Color = c[2]
		# четыре фазы: точка → крестик → большой крестик с ослабленными концами → крестик
		var arm: int = [1, 2, 3, 2][ph]
		var core := Color(1, 1, 1, 1.0 if ph != 0 else 0.8)
		for k in range(1, arm + 1):
			var a := col
			a.a = 1.0 if k < arm else 0.55
			draw_rect(Rect2(p.x + k, p.y, 1, 1), a)
			draw_rect(Rect2(p.x - k, p.y, 1, 1), a)
			draw_rect(Rect2(p.x, p.y + k, 1, 1), a)
			draw_rect(Rect2(p.x, p.y - k, 1, 1), a)
		draw_rect(Rect2(p.x, p.y, 1, 1), core)

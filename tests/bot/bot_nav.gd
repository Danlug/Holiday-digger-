extends RefCounted
## Навигатор бота-игрока (tests/bot_play.gd): кратчайший путь по клеткам с учётом того,
## что герой умеет на самом деле — ходить и падать по пустоте, взлетать на ранце по
## пустоте, копать вбок (стоя на полу) и вниз. Вверх копать нельзя никому (ГДД §6).
##
## Дейкстра на корзинах (цены — маленькие целые): пустая клетка 1, копка — dig_cost.
## Окно поиска ограничено рядами [y_min, y_max] — глубина мира 10 000, всю не обходим.

const EMPTY := 0   # TileTypes.Type.EMPTY

var world: WorldGen
## (x, y) -> int: цена копки клетки или -1, если её не взять (инструмент, лава, бетон).
var dig_cost: Callable
var nodes_last := 0


## Путь от from до первой клетки, где goal(cell) — истина: [from, ..., цель] или [].
## allow_dig=false — только по пустоте (подъём по готовому стволу).
func plan(from: Vector2i, goal: Callable, y_min: int, y_max: int, max_cost: int = 400,
		allow_dig: bool = true) -> Array:
	y_min = maxi(1, y_min)
	if from.y < y_min or from.y > y_max:
		return []
	var w := WorldGen.WIDTH
	var h := y_max - y_min + 1
	var n := w * h
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(1 << 30)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var buckets: Array = []
	buckets.resize(max_cost + 8)
	var start := (from.y - y_min) * w + from.x
	dist[start] = 0
	buckets[0] = [start]
	nodes_last = 0
	var cost := 0
	while cost <= max_cost:
		var b = buckets[cost]
		if b == null or (b as Array).is_empty():
			cost += 1
			continue
		var k: int = (b as Array).pop_back()
		if dist[k] != cost:
			continue
		nodes_last += 1
		var cx := k % w
		var cy := k / w + y_min
		if goal.call(Vector2i(cx, cy)):
			return _path(prev, k, w, y_min)
		var standing := world.get_tile(cx, cy + 1) != EMPTY
		# вбок
		for dx in [-1, 1]:
			var nx: int = cx + dx
			if nx < 0 or nx >= w:
				continue
			var c := _step_cost(nx, cy, allow_dig and standing)
			if c > 0:
				_relax(dist, prev, buckets, k, (cy - y_min) * w + nx, cost + c, max_cost)
		# вниз
		if cy + 1 <= y_max:
			var c2 := _step_cost(cx, cy + 1, allow_dig)
			if c2 > 0:
				_relax(dist, prev, buckets, k, (cy + 1 - y_min) * w + cx, cost + c2, max_cost)
		# вверх — только по пустоте (полёт)
		if cy - 1 >= y_min and world.get_tile(cx, cy - 1) == EMPTY:
			_relax(dist, prev, buckets, k, (cy - 1 - y_min) * w + cx, cost + 1, max_cost)
	return []


func _step_cost(x: int, y: int, dig_ok: bool) -> int:
	if world.get_tile(x, y) == EMPTY:
		return 1
	if not dig_ok:
		return -1
	return int(dig_cost.call(x, y))


func _relax(dist: PackedInt32Array, prev: PackedInt32Array, buckets: Array, from: int, to: int,
		d: int, max_cost: int) -> void:
	if d >= dist[to] or d > max_cost:
		return
	dist[to] = d
	prev[to] = from
	if buckets[d] == null:
		buckets[d] = []
	(buckets[d] as Array).append(to)


func _path(prev: PackedInt32Array, k: int, w: int, y_min: int) -> Array:
	var out: Array = []
	while k >= 0:
		out.push_front(Vector2i(k % w, k / w + y_min))
		k = prev[k]
	return out

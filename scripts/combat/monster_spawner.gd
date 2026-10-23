class_name MonsterSpawner
extends RefCounted
## MonsterSpawner — где и когда появляются монстры. Только глубже start_depth
## (4000) и только в пустых клетках выкопанных тоннелей, до которых герой
## дотягивается по тоннелю: BFS по выкопанным клеткам от героя. Нетронутую
## породу и естественные пустоты не читаем — это дорого и незачем: монстры
## ходят по следам игрока. Засадник — исключение: он сидит в породе рядом с
## тоннелем. Плотность и темп растут с глубиной (data/combat.json → spawn).
## Появляются вне экрана, чтобы монстр не возникал на глазах.

const NEIGHBORS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var cw: CombatWorld
var rng := RandomNumberGenerator.new()
var _timer: float = -1.0
var _group_seq: int = 0


func _init(p_cw: CombatWorld = null, seed_value: int = 0) -> void:
	cw = p_cw
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func reset() -> void:
	_timer = -1.0


static func _lerp_cfg(key: String, depth: int) -> float:
	var arr: Array = CombatData.spawn_cfg(key, [1, 1])
	var d0 := CombatData.start_depth()
	var d1 := int(CombatData.spawn_cfg("depth_full", 10000))
	var t := clampf(float(depth - d0) / float(maxi(1, d1 - d0)), 0.0, 1.0)
	return lerpf(float(arr[0]), float(arr[1]), t)


static func max_alive(depth: int) -> int:
	return int(round(_lerp_cfg("max_alive", depth)))


static func interval(depth: int) -> float:
	return _lerp_cfg("interval_sec", depth)


## Вес вида на глубине: 0 вне пояса, плавное нарастание за rampup клеток от
## верхней границы — новый вид появляется не стеной, а понемногу.
static func weight_at(mid: String, depth: int) -> float:
	var m := CombatData.monster(mid)
	var rng_arr: Array = m.get("depth", [4000, 10000])
	if depth < int(rng_arr[0]) or depth > int(rng_arr[1]):
		return 0.0
	var ramp := float(CombatData.spawn_cfg("rampup", 300))
	var k := clampf(float(depth - int(rng_arr[0]) + 1) / maxf(ramp, 1.0), 0.0, 1.0)
	return float(m.get("weight", 1)) * k


## Тикает таймер; когда пора — возвращает список заявок на появление
## [{id, x, y, group, emerge: Vector2}]. alive_count — сколько уже живых.
func tick(dt: float, hero_x: float, hero_y: float, alive_count: int) -> Array:
	var depth := int(floor(hero_y))
	if depth < CombatData.start_depth():
		_timer = -1.0
		return []
	if _timer < 0.0:
		_timer = float(CombatData.spawn_cfg("first_delay_sec", 5.0))
	_timer -= dt
	if _timer > 0.0:
		return []
	_timer = interval(depth) * rng.randf_range(0.8, 1.25)
	if alive_count >= max_alive(depth):
		return []
	return spawn_once(hero_x, hero_y)


func view_rect(hero_x: float, hero_y: float) -> Rect2:
	var half: Array = CombatData.spawn_cfg("view_half", [4.5, 8.5])
	return Rect2(hero_x - float(half[0]), hero_y - float(half[1]), float(half[0]) * 2.0, float(half[1]) * 2.0)


## Клетки выкопанных тоннелей, достижимые от героя: {Vector2i: расстояние}.
func reachable_cells(hero_x: float, hero_y: float) -> Dictionary:
	var start := Vector2i(int(floor(hero_x)), int(floor(hero_y)))
	var seen := {start: 0}
	var queue: Array[Vector2i] = [start]
	var limit := int(CombatData.spawn_cfg("bfs_limit", 320))
	var head := 0
	while head < queue.size() and seen.size() < limit:
		var c: Vector2i = queue[head]
		head += 1
		for n in NEIGHBORS:
			var p := c + n
			if seen.has(p) or p.x < 0 or p.x >= CombatWorld.WIDTH or p.y < 1:
				continue
			if not cw.is_dug(p.x, p.y):
				continue
			seen[p] = int(seen[c]) + 1
			queue.append(p)
	return seen


func spawn_once(hero_x: float, hero_y: float) -> Array:
	var depth := int(floor(hero_y))
	var cells := reachable_cells(hero_x, hero_y)
	var min_d := float(CombatData.spawn_cfg("min_dist", 4.0))
	var max_d := float(CombatData.spawn_cfg("max_dist", 13.0))
	var view := view_rect(hero_x, hero_y)
	var hero := Vector2(hero_x, hero_y)

	var air: Array[Vector2i] = []
	var ground: Array[Vector2i] = []
	for c in cells.keys():
		var cc: Vector2i = c
		var center := Vector2(cc.x + 0.5, cc.y + 0.5)
		var dist := center.distance_to(hero)
		if dist < min_d or dist > max_d or view.has_point(center):
			continue
		air.append(cc)
		if cw.solid(cc.x, cc.y + 1):
			ground.append(cc)

	# засадник: порода рядом с достижимой клеткой, не в кадре
	var amb: Array = []
	if weight_at("rock_mimic", depth) > 0.0:
		for c in cells.keys():
			var cc: Vector2i = c
			var center := Vector2(cc.x + 0.5, cc.y + 0.5)
			var dist := center.distance_to(hero)
			if dist < 3.0 or dist > max_d or view.has_point(center):
				continue
			for n in NEIGHBORS:
				var p := cc + n
				if p.x < 0 or p.x >= CombatWorld.WIDTH or cw.is_dug(p.x, p.y) or not cw.solid(p.x, p.y):
					continue
				if not _is_ambush_rock(p):
					continue
				amb.append([p, cc])

	# вид по весам среди тех, для кого нашлось место
	var options: Array = []
	var total := 0.0
	for mid in CombatData.monster_ids():
		var w := weight_at(String(mid), depth)
		if w <= 0.0:
			continue
		var beh := String(CombatData.monster(String(mid)).get("behavior", ""))
		var fits := false
		match beh:
			"crawler", "jumper":
				fits = not ground.is_empty()
			"flyer", "swarm":
				fits = not air.is_empty()
			"ambusher":
				fits = not amb.is_empty()
		if fits:
			options.append([String(mid), w])
			total += w
	if options.is_empty():
		return []
	var roll := rng.randf() * total
	var pick: String = options[0][0]
	for o in options:
		roll -= float(o[1])
		if roll <= 0.0:
			pick = String(o[0])
			break

	var def := CombatData.monster(pick)
	var beh2 := String(def.get("behavior", ""))
	_group_seq += 1
	var out: Array = []
	match beh2:
		"crawler", "jumper":
			var cc2: Variant = _pick_fit(ground, pick, depth, 0.5, 0.0, true)
			if cc2 != null:
				out.append(_req(pick, cc2.x + 0.5, float(cc2.y), _group_seq))
		"flyer":
			var cc3: Variant = _pick_fit(air, pick, depth, 0.5, 0.5, false)
			if cc3 != null:
				out.append(_req(pick, cc3.x + 0.5, cc3.y + 0.5, _group_seq))
		"swarm":
			var cc4: Vector2i = air[rng.randi() % air.size()]
			var g: Array = def.get("group", [3, 5])
			var n := rng.randi_range(int(g[0]), int(g[1]))
			for i in range(n):
				out.append(_req(pick, cc4.x + 0.5 + rng.randf_range(-0.25, 0.25),
					cc4.y + 0.5 + rng.randf_range(-0.25, 0.25), _group_seq))
		"ambusher":
			for attempt in range(8):
				var pair: Array = amb[rng.randi() % amb.size()]
				var rock: Vector2i = pair[0]
				var open: Vector2i = pair[1]
				var hh: float = float((def.get("size", [1.0, 0.8]) as Array)[1]) / 2.0
				var em := Vector2(open.x + 0.5, float(open.y) + 1.0 - hh - Monster.EPS)
				var probe := Monster.create(pick, em.x, float(open.y), depth)
				if not probe.fits(cw.solid):
					continue
				var r := _req(pick, rock.x + 0.5, float(rock.y), _group_seq)
				r["emerge"] = em
				out.append(r)
				break
	return out


## Случайная клетка из списка, где монстр вида mid помещается. null — нет такой.
func _pick_fit(cells: Array, mid: String, depth: int, ox: float, oy: float, ground: bool) -> Variant:
	for attempt in range(10):
		var c: Vector2i = cells[rng.randi() % cells.size()]
		var probe := Monster.create(mid, c.x + ox, float(c.y) + (0.0 if ground else oy), depth)
		if probe.fits(cw.solid):
			return c
	return null


func _req(mid: String, x: float, y: float, group: int) -> Dictionary:
	return {"id": mid, "x": x, "y": y, "group": group, "emerge": Vector2.ZERO}


## Годится ли порода в засаду: обычная порода, а не железобетон/фундамент.
func _is_ambush_rock(p: Vector2i) -> bool:
	if cw.world == null:
		return true
	var tt := int(cw.world.get_tile(p.x, p.y))
	return tt != TileTypes.Type.REINFORCED and tt != TileTypes.Type.FOUNDATION \
		and tt != TileTypes.Type.STAIRCASE and TileTypes.is_diggable(tt)

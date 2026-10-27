extends Node
## test_greed_fall — падение в жадности (владелец 27.10, ГДД §20.1): урона нет;
## каждые 3 клетки полёта вниз — миг остановки (скорость вниз — ноль), потом
## падение дальше; подъём и торможение ранцем, прыжок и копка вниз не
## останавливаются; спуск в жадности с 20 клеток и глубже не быстрее обычного
## падения; жадность кончилась в полёте — урон только за высоту ниже точки конца.
## Настоящий Player на мире-полигоне, шаги физики — вручную.
##
## Запуск:  godot --headless --path . res://tests/test_greed_fall.tscn

const DT := 1.0 / 60.0
const FLOOR_Y := 300

var failures := 0
var total := 0
var _stops := 0


class Arena:
	extends WorldGen
	var cells: Dictionary = {}
	func _init() -> void:
		super(7)
	func get_tile(x: int, y: int) -> int:
		return int(cells.get(Vector2i(x, y), TileTypes.Type.EMPTY))
	func dig_cell(x: int, y: int) -> bool:
		var c := Vector2i(x, y)
		if not cells.has(c) or not TileTypes.is_diggable(int(cells[c])):
			return false
		cells.erase(c)
		return true
	func fill(x0: int, y0: int, x1: int, y1: int, type: int) -> void:
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				cells[Vector2i(xx, yy)] = type


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _ready() -> void:
	print("=== test_greed_fall ===")
	await get_tree().process_frame
	Settings.reduce_motion = false
	GameState.reset_progress()
	StoryState.set_flag("food_ordered", true)
	_test_data()
	_test_fall_20()
	_test_normal_unchanged()
	_test_time()
	_test_greed_ends_midair()
	_test_short_drops()
	_test_dig_down()
	_test_jetpack()
	_test_shaft_no_stuck()
	_test_rig()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _player(arena: Arena) -> Node:
	var p = load("res://scripts/player/player.gd").new()
	p.world = arena
	add_child(p)
	p.greed_fall_stopped.connect(func() -> void: _stops += 1)
	GameState.is_alive = true
	GameState.hp = GameState.get_max_hp()
	GameState.current_tool = "iron_pickaxe"
	GameState.current_gear = ""
	return p


func _heal() -> void:
	GameState.hp = GameState.get_max_hp()
	GameState.is_alive = true


## Падение с высоты h на пол FLOOR_Y. Траектория — по кадру: y, vy, висит ли.
## end_greed_at — на какой высоте над полом жадность кончается (MechDirector
## ставит greed_mult = 1 между кадрами), −1 — не кончается.
func _fall(mult: float, h: float, dt: float = DT, end_greed_at: float = -1.0) -> Dictionary:
	var a := Arena.new()
	a.fill(0, FLOOR_Y, 31, FLOOR_Y + 1, TileTypes.Type.STONE)
	var p = _player(a)
	p.x = 15.5
	p.y = float(FLOOR_Y) - 1.0 / 3.0 - 0.001 - h
	p.vy = 0.0
	p.on_ground = false
	p.greed_mult = mult
	var y0: float = p.y
	_stops = 0
	var hp0: float = GameState.hp
	var frames := 0
	var traj: Array = []
	var y_end := NAN
	while not p.on_ground and frames < 4000:
		if end_greed_at >= 0.0 and p.greed_mult > 1.0 and float(FLOOR_Y) - p.y <= end_greed_at:
			p.greed_mult = 1.0
			y_end = p.y
		p.physics_tick(dt)
		frames += 1
		traj.append({"y": p.y, "vy": p.vy, "hang": p._greed_hang_left > 0.0})
	var out := {"frames": frames, "t": frames * dt, "dmg": hp0 - GameState.hp, "y": p.y, "y0": y0,
		"stops": _stops, "traj": traj, "y_end": y_end}
	_heal()
	p.queue_free()
	return out


func _segments_ok(hangs: Array, slack: float) -> bool:
	var prev := 0.0
	for h in hangs:
		var seg: float = float(h[2]) - prev
		if seg < 3.0 or seg > 3.0 + slack:
			return false
		prev = float(h[2])
	return true


## Отрезки остановок: [кадр начала, кадров висел, пролетел клеток от старта].
func _hangs(f: Dictionary) -> Array:
	var out: Array = []
	var traj: Array = f["traj"]
	var i := 0
	while i < traj.size():
		if bool(traj[i]["hang"]):
			var j := i
			while j < traj.size() and bool(traj[j]["hang"]):
				j += 1
			out.append([i, j - i + 1, float(traj[i]["y"]) - float(f["y0"])])
			i = j
		else:
			i += 1
	return out


# ---------------------------------------------------------------------------

func _test_data() -> void:
	check("каждые 3 клетки (владелец 27.10)", is_equal_approx(GreedRules.fall_stop_cells(), 3.0))
	var s := GreedRules.fall_stop_seconds()
	check("остановка %.2f с — «на мгновение» (0.12–0.2)" % s, s >= 0.12 and s <= 0.2)
	var node: Dictionary = MechData.section("greed").get("fall_stop_s", {})
	check("числа в data/mechanics.json → greed, слово владельца в note",
		node.get("proposed", true) == false and String(node.get("note", "")).contains("27.10"))


func _test_fall_20() -> void:
	var f := _fall(7.0, 20.0)
	var hangs := _hangs(f)
	check("20 клеток в жадности: на полу, урона нет (%.0f HP)" % f["dmg"],
		float(f["y"]) < float(FLOOR_Y) and float(f["dmg"]) == 0.0)
	check("остановок 6 — на 3, 6, … 18 клетке (было %d)" % f["stops"], int(f["stops"]) == 6 and hangs.size() == 6)
	var at: Array = []
	var ok_len := true
	var ok_zero := true
	var want := int(ceil(GreedRules.fall_stop_seconds() / DT))
	for k in hangs.size():
		var h: Array = hangs[k]
		at.append(snappedf(float(h[2]), 0.01))
		for i in range(int(h[0]), int(h[0]) + int(h[1]) - 1):
			ok_zero = ok_zero and is_zero_approx(float(f["traj"][i]["vy"]))
		ok_len = ok_len and absi(int(h[1]) - want) <= 1
	# отрезок — от прошлой остановки: 3 клетки и перелёт меньше шага движения (кадр / 7)
	check("остановки по траектории на %s клетки — через 3 (+<0.2)" % str(at), _segments_ok(hangs, 0.2))
	check("каждая длится ≈ %d кадров (%.2f с)" % [want, GreedRules.fall_stop_seconds()], ok_len)
	check("пока висит — скорость вниз ноль и высота та же", ok_zero)
	# между остановками герой падает (скорость растёт от нуля), а не висит
	var ok_fall := true
	var traj: Array = f["traj"]
	for i in range(1, traj.size()):
		if not bool(traj[i]["hang"]) and not bool(traj[i - 1]["hang"]) and i < traj.size() - 1:
			ok_fall = ok_fall and float(traj[i]["vy"]) >= float(traj[i - 1]["vy"]) - 0.001
	var vmax := 0.0
	for e in traj:
		vmax = maxf(vmax, float(e["vy"]))
	check("между остановками — разгон с нуля, не выше %.1f кл./с (3 клетки падения)" % vmax, ok_fall and vmax < 11.0)
	# 30 к/с: шаг вдвое длиннее — остановки там же с запасом в треть клетки
	var g := _fall(7.0, 20.0, 0.033)
	check("на 30 к/с — те же 6 остановок через 3 кл. (+<0.35), без урона (было %d)" % g["stops"],
		int(g["stops"]) == 6 and float(g["dmg"]) == 0.0 and _segments_ok(_hangs(g), 0.35))
	check("высокое падение (90 кл.) в жадности — без урона", float(_fall(7.0, 90.0)["dmg"]) == 0.0)


func _test_normal_unchanged() -> void:
	for h in [4.0, 12.0, 20.0]:
		var f := _fall(1.0, h)
		var want := roundf(Balance.get_fall_damage_from_speed(sqrt(2.0 * 16.0 * h), 16.0))
		check("без жадности %.0f кл.: урон %.0f (как раньше, ~%.0f), остановок нет" % [h, f["dmg"], want],
			int(f["stops"]) == 0 and absf(float(f["dmg"]) - want) <= 3.0 and (h < 5.0 or float(f["dmg"]) > 0.0))


## Спуск в жадности не выгоднее обычного падения (и тем более полёта вниз на
## ранце — он медленнее падения). Короткий прыжок ×7 быстрее — это и есть
## «скорость падения ×7» владельца; лифтом вниз жадность не становится.
func _test_time() -> void:
	var line := ""
	var ok := true
	for h in [20.0, 30.0, 40.0, 100.0]:
		var n := _fall(1.0, h)
		var g := _fall(7.0, h)
		line += " %d: %.2f/%.2f" % [int(h), g["t"], n["t"]]
		ok = ok and float(g["t"]) >= float(n["t"])
	check("время спуска жадность/обычно, с:%s — не быстрее" % line, ok)
	var n100 := _fall(1.0, 100.0)
	var g100 := _fall(7.0, 100.0)
	check("тоннель 100 кл.: в жадности %.1f кл./с, обычное падение %.1f" % [
		100.0 / float(g100["t"]), 100.0 / float(n100["t"])], 100.0 / float(g100["t"]) < 12.0)
	# с какой высоты жадность перестаёт быть быстрее (для ГДД)
	var from := -1
	for h in range(3, 41):
		var faster := float(_fall(7.0, float(h))["t"]) < float(_fall(1.0, float(h))["t"])
		if faster:
			from = -1
		elif from < 0:
			from = h
	check("начиная с %d клеток спуск в жадности не быстрее обычного (ориентир — 20)" % from, from > 0 and from <= 20)


func _test_greed_ends_midair() -> void:
	var g := _fall(7.0, 30.0, DT, 12.0)
	var after: float = float(g["y"]) - float(g["y_end"])
	var n := _fall(1.0, after)
	var n30 := _fall(1.0, 30.0)
	check("жадность кончилась в %.1f кл. над полом: урон %.0f — как у обычного падения с %.1f кл. (%.0f), не с 30 (%.0f)" % [
		after, g["dmg"], after, n["dmg"], n30["dmg"]],
		absf(float(g["dmg"]) - float(n["dmg"])) <= 2.0 and float(g["dmg"]) > 0.0 and float(g["dmg"]) < float(n30["dmg"]) * 0.5)
	var g4 := _fall(7.0, 30.0, DT, 4.0)
	check("кончилась в 4 кл. над полом — урона нет (%.0f)" % g4["dmg"], float(g4["dmg"]) == 0.0)


func _test_short_drops() -> void:
	var f := _fall(7.0, 2.5)
	check("2.5 клетки в жадности — без остановки", int(f["stops"]) == 0)
	var a := Arena.new()
	a.fill(0, FLOOR_Y, 31, FLOOR_Y, TileTypes.Type.STONE)
	var p = _player(a)
	p.x = 15.5
	p.y = float(FLOOR_Y) - 0.34
	p.on_ground = true
	p.greed_mult = 7.0
	_stops = 0
	p.set_intent(0, true, false)
	_steps(p, 3)
	p.set_intent(0, false, false)
	var landed := false
	for i in 60:
		p.physics_tick(DT)
		landed = landed or (p.on_ground and i > 2)
	check("прыжок в жадности (2.2 кл. вверх и вниз) — без остановки", landed and _stops == 0)
	p.queue_free()


func _steps(p, n: int, dt: float = DT) -> void:
	for i in n:
		p.physics_tick(dt)


## Копка вниз — не падение: герой встаёт на каждую клетку, отсчёт с нуля.
func _test_dig_down() -> void:
	var a := Arena.new()
	a.fill(10, FLOOR_Y - 20, 20, FLOOR_Y + 20, TileTypes.Type.DIRT)
	var p = _player(a)
	p.x = 15.5
	p.y = float(FLOOR_Y - 21) + 1.0 - 1.0 / 3.0 - 0.001
	p.on_ground = true
	p.greed_mult = 7.0
	_stops = 0
	var hp0: float = GameState.hp
	var y0: float = p.y
	p.set_intent(0, false, true)
	_steps(p, 240)
	p.set_intent(0, false, false)
	check("копка вниз в жадности: %.0f клеток за 4 с, остановок нет, урона нет" % (p.y - y0),
		p.y - y0 > 8.0 and _stops == 0 and GameState.hp == hp0)
	p.digging = null
	_heal()
	p.queue_free()


func _test_jetpack() -> void:
	var a := Arena.new()
	a.fill(0, FLOOR_Y, 31, FLOOR_Y, TileTypes.Type.STONE)
	var p = _player(a)
	GameState.grant_gear("jetpack")
	GameState.set_current_gear("jetpack")
	p.x = 15.5
	p.y = float(FLOOR_Y) - 60.0
	p.vy = 0.0
	p.on_ground = false
	p.greed_mult = 7.0
	_stops = 0
	# подъём: тяга всё время, без остановок
	var y_start: float = p.y
	p.set_intent(0, true, false)
	var up_ok := true
	for i in 90:
		p.physics_tick(DT)
		up_ok = up_ok and p.thrust != "" and p._greed_hang_left <= 0.0
	check("подъём джетпаком в жадности: %.1f кл. вверх, тяга не прерывалась, остановок нет" % (y_start - p.y),
		up_ok and y_start - p.y > 3.0 and _stops == 0)
	# отпустил — падает: от вершины через 3 клетки первая остановка
	p.set_intent(0, false, false)
	var top: float = p.y
	while _stops == 0 and p.y < float(FLOOR_Y) - 2.0:
		p.physics_tick(DT)
		top = minf(top, p.y)
	check("отпустил тягу — остановка через 3 кл. от вершины (%.2f)" % (p.y - top), _stops == 1 and absf(p.y - top - 3.0) < 0.2)
	# в остановке нажал «вверх» — тяга включается сразу, а не через миг
	p.set_intent(0, true, false)
	p.physics_tick(DT)
	check("«вверх» в остановке — сразу тяга (%s)" % p.thrust, p.thrust != "" and p._greed_hang_left <= 0.0)
	# торможение тягой в падении — не падение: остановок нет
	p.set_intent(0, false, false)
	_steps(p, 4)
	var s0 := _stops
	p.set_intent(0, true, false)
	_steps(p, 40)
	check("торможение джетпаком в падении — без остановок", _stops == s0)
	GameState.current_gear = ""
	GameState.owned_gear.clear()
	p.queue_free()


## Узкая шахта (1 клетка) и смещённый герой: остановки не оставляют его в породе.
func _test_shaft_no_stuck() -> void:
	var a := Arena.new()
	a.fill(0, FLOOR_Y, 31, FLOOR_Y, TileTypes.Type.STONE)
	a.fill(14, FLOOR_Y - 40, 14, FLOOR_Y - 1, TileTypes.Type.STONE)
	a.fill(16, FLOOR_Y - 40, 16, FLOOR_Y - 1, TileTypes.Type.STONE)
	var p = _player(a)
	p.x = 15.42
	p.y = float(FLOOR_Y) - 38.0
	p.vy = 0.0
	p.on_ground = false
	p.greed_mult = 7.0
	_stops = 0
	var inside := 0
	var frames := 0
	while not p.on_ground and frames < 2000:
		p.physics_tick(DT)
		frames += 1
		for cx in [p.x - 0.37, p.x + 0.37]:
			for cy in [p.y - 0.32, p.y + 0.32]:
				if a.get_tile(int(floor(cx)), int(floor(cy))) != TileTypes.Type.EMPTY:
					inside += 1
	check("шахта в клетку, 38 кл.: %d остановок, на полу, ни кадра в породе" % _stops,
		_stops >= 11 and p.on_ground and inside == 0 and p.y < float(FLOOR_Y) and p.y > float(FLOOR_Y) - 1.0)
	p.queue_free()


func _test_rig() -> void:
	var a := Arena.new()
	a.fill(0, FLOOR_Y, 31, FLOOR_Y + 1, TileTypes.Type.STONE)
	var p = _player(a)
	GameState.current_tool = "drill_rig"
	p.x = 15.5
	p.y = float(FLOOR_Y) - 20.0 - 0.334
	p.vy = 0.0
	p.on_ground = false
	p.greed_mult = 7.0
	_stops = 0
	var hp0: float = GameState.hp
	var frames := 0
	while not p.on_ground and frames < 2000:
		p.physics_tick(DT)
		frames += 1
	check("бурмобиль: 20 кл. в жадности — %d остановок, без урона" % _stops, _stops == 6 and GameState.hp == hp0)
	GameState.current_tool = "iron_pickaxe"
	_heal()
	p.queue_free()

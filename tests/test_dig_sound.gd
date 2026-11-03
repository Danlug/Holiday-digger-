extends Node
## test_dig_sound — звук копки (зона dig-sound): сопоставление порода → материал и
## инструмент → слой, полнота каталога, ритм ударов по длительности клетки,
## финал с осыпанием, дребезг ржавой кирки, моторы бура и бурмобиля, усталость
## громкости, а затем — настоящий SfxService с require_gesture=false и настоящий
## Player в настоящей main.tscn: копаем несколько клеток разных пород и смотрим
## SfxService.stats.played и последние id. Звука в headless не слышно —
## проверяются состояния.
##
## Запуск: godot --headless --path . res://tests/test_dig_sound.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== test_dig_sound ===")
	await _frames(2)
	_test_mapping()
	await _test_catalog()
	await _test_rhythm()
	await _test_motors()
	await _test_real_dig()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# Сопоставления
# ---------------------------------------------------------------------------

func _test_mapping() -> void:
	check("земля → dirt", DigSound.material_for(TileTypes.Type.DIRT) == "dirt")
	check("торф и уголь → peat (сухое крошение)", DigSound.material_for(TileTypes.Type.PEAT) == "peat"
			and DigSound.material_for(TileTypes.Type.COAL) == "peat")
	check("камень и кладка руин → stone", DigSound.material_for(TileTypes.Type.STONE) == "stone"
			and DigSound.material_for(TileTypes.Type.RUIN_BRICK) == "stone")
	check("железо, медь, уран, металлолом → ore", DigSound.material_for(TileTypes.Type.IRON_ORE) == "ore"
			and DigSound.material_for(TileTypes.Type.COPPER_ORE) == "ore"
			and DigSound.material_for(TileTypes.Type.URANIUM_ORE) == "ore"
			and DigSound.material_for(TileTypes.Type.SCRAP_METAL) == "ore")
	check("золото и платина → gold", DigSound.material_for(TileTypes.Type.GOLD_ORE) == "gold"
			and DigSound.material_for(TileTypes.Type.PLATINUM_ORE) == "gold")
	check("алмаз, рубин, изумруд, геокристалл → gem", DigSound.material_for(TileTypes.Type.DIAMOND) == "gem"
			and DigSound.material_for(TileTypes.Type.RUBY) == "gem"
			and DigSound.material_for(TileTypes.Type.EMERALD) == "gem"
			and DigSound.material_for(TileTypes.Type.GEOCRYSTAL) == "gem")
	check("фундамент, обсидиан, адский камень, божественное сердце → hard",
			DigSound.material_for(TileTypes.Type.FOUNDATION) == "hard"
			and DigSound.material_for(TileTypes.Type.OBSIDIAN) == "hard"
			and DigSound.material_for(TileTypes.Type.HELLSTONE) == "hard"
			and DigSound.material_for(TileTypes.Type.DIVINE_HEART) == "hard")
	check("лава → lava", DigSound.material_for(TileTypes.Type.LAVA) == "lava")

	check("лопата → shovel, кирки → pick", DigSound.tool_kind("shovel") == "shovel"
			and DigSound.tool_kind("rusty_pickaxe") == "pick" and DigSound.tool_kind("obsidian_pickaxe") == "pick")
	check("неизвестный инструмент → pick", DigSound.tool_kind("ничего") == "pick")
	check("id удара: земля киркой", DigSound.strike_id("dirt", "pick") == "dig_dirt_pick")
	check("лопата по камню звучит как кирка (лопата камень не берёт)", DigSound.strike_id("stone", "shovel") == "dig_stone_pick")
	check("лопата по металлолому — свой звук", DigSound.strike_id("ore", "shovel") == "dig_ore_shovel")
	check("лава — один удар для всех инструментов", DigSound.strike_id("lava", "drill") == "dig_lava")
	check("осыпание по материалу", DigSound.break_id("gem") == "break_gem")

	# ритм: число ударов на клетку
	check("кирка 0.38 с: клетка 3.0 с → 8 ударов", DigSound.hits_for(3.0, "iron_pickaxe") == 8)
	check("короткая клетка → один удар (финал)", DigSound.hits_for(0.1, "iron_pickaxe") == 1)
	check("бурмобиль 0.12 с: клетка 1.0 с → 8 ударов", DigSound.hits_for(1.0, "drill_rig") == 8)


# ---------------------------------------------------------------------------
# Каталог
# ---------------------------------------------------------------------------

func _test_catalog() -> void:
	var sfx := SfxService.new()
	add_child(sfx)
	await _frames(1)
	var missing: Array = []
	for mat in ["dirt", "peat", "stone", "ore", "gold", "gem", "hard"]:
		for kind in ["pick", "drill"]:
			if not sfx.has_sfx("dig_%s_%s" % [mat, kind]):
				missing.append("dig_%s_%s" % [mat, kind])
		if not sfx.has_sfx("break_" + mat):
			missing.append("break_" + mat)
	for mat in ["dirt", "peat", "ore"]:
		if not sfx.has_sfx("dig_%s_shovel" % mat):
			missing.append("dig_%s_shovel" % mat)
	for id in ["dig_lava", "break_lava", "rattle", "drill_loop", "rig_loop", "swing"]:
		if not sfx.has_sfx(id):
			missing.append(id)
	check("каталог: все удары, осыпания, дребезг и моторы (нет: %s)" % str(missing), missing.is_empty())
	check("старые id — псевдонимы на те же файлы", sfx.has_sfx("dig_dirt") and sfx.has_sfx("tile_break")
			and sfx._defs["dig_dirt"]["streams"][0] == sfx._defs["dig_dirt_pick"]["streams"][0])
	check("моторы — петли", bool(sfx._defs["drill_loop"]["loop"]) and bool(sfx._defs["rig_loop"]["loop"]))
	var few: Array = []
	for id in sfx.sfx_ids():
		if (id.begins_with("dig_") and id != "dig_lava") and sfx._defs[id]["streams"].size() < 3:
			few.append(id)
	check("у каждого удара 3 варианта (мало: %s)" % str(few), few.is_empty())
	var machine_gun: Array = []
	for id in sfx.sfx_ids():
		if id.begins_with("dig_") or id.begins_with("break_"):
			var d: Dictionary = sfx._defs[id]
			if int(d["cd"]) < 30 or int(d["voices"]) > 2 or float(d["pv"]) <= 0.0:
				machine_gun.append(id)
	check("запрет «пулемёта»: cooldown ≥ 30 мс, ≤ 2 голосов, разброс высоты (нарушают: %s)" % str(machine_gun),
			machine_gun.is_empty())
	var long: Array = []
	for id in sfx.sfx_ids():
		if id.begins_with("dig_") and id.find("_drill") > 0:
			for s in sfx._defs[id]["streams"]:
				if s.get_length() > 1.0:
					long.append(id)
	check("удары бура короче секунды (иначе накладываются на 0.12 с ритма)", long.is_empty())
	sfx.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------
# Ритм, финал, дребезг, усталость — на записи вызовов
# ---------------------------------------------------------------------------

func _test_rhythm() -> void:
	var rec := _Rec.new()
	rec.add_to_group(Sfx.GROUP)
	add_child(rec)
	var pl := _FakePlayer.new()
	add_child(pl)
	var ds := DigSound.new()

	GameState.current_tool = "iron_pickaxe"
	pl.digging = {"x": 5, "y": 13, "t": 0.0, "total": 3.0, "type": TileTypes.Type.STONE}
	ds.tick(pl, 0.016)
	check("начало копки: лёгкий замах", rec.count("swing") == 1)
	var struck := 0
	var t := 0.0
	while t < 3.0:
		t += 1.0 / 60.0
		pl.digging["t"] = t
		if ds.tick(pl, 1.0 / 60.0):
			struck += 1
	check("камень киркой 3 с: 7 ударов до финала, все dig_stone_pick", struck == 7 and rec.count("dig_stone_pick") == 7)
	check("удары тише финала (профиль кирки −7 дБ)", rec.last_db("dig_stone_pick") < -3.0)
	check("удары к концу клетки крепче первых", rec.first_db("dig_stone_pick") < rec.last_db("dig_stone_pick"))
	check("без ржавой кирки дребезга нет", rec.count("rattle") == 0)
	var regular_db := rec.last_db("dig_stone_pick")
	rec.clear()
	ds.on_dug(TileTypes.Type.STONE, "iron_pickaxe")
	pl.digging = null
	ds.tick(pl, 0.016)
	check("финал: удар громче рядовых на 1.5+ дБ + осыпание камня", rec.count("dig_stone_pick") == 1 and rec.count("break_stone") == 1
			and rec.last_db("dig_stone_pick") > regular_db + 1.5)
	check("последние id доступны (%s)" % str(ds.recent.slice(-2)), ds.recent.slice(-2) == ["dig_stone_pick", "break_stone"])

	# ржавая кирка дребезжит
	rec.clear()
	GameState.current_tool = "rusty_pickaxe"
	pl.digging = {"x": 5, "y": 14, "t": 0.0, "total": 4.0, "type": TileTypes.Type.IRON_ORE}
	t = 0.0
	while t < 4.0:
		t += 1.0 / 60.0
		pl.digging["t"] = t
		ds.tick(pl, 1.0 / 60.0)
	ds.on_dug(TileTypes.Type.IRON_ORE, "rusty_pickaxe")
	pl.digging = null
	ds.tick(pl, 0.016)
	check("ржавая кирка: руда звучит металлом и дребезжит", rec.count("dig_ore_pick") >= 9 and rec.count("rattle") >= 4)

	# лопата по земле, торфу; короткая клетка — только финал
	rec.clear()
	GameState.current_tool = "shovel"
	pl.digging = {"x": 6, "y": 1, "t": 0.0, "total": 0.2, "type": TileTypes.Type.DIRT}
	t = 0.0
	while t < 0.2:
		t += 1.0 / 60.0
		pl.digging["t"] = t
		ds.tick(pl, 1.0 / 60.0)
	ds.on_dug(TileTypes.Type.DIRT, "shovel")
	pl.digging = null
	ds.tick(pl, 0.016)
	check("короткая клетка лопатой: один шорх + осыпание, без промежуточных ударов",
			rec.count("dig_dirt_shovel") == 1 and rec.count("break_dirt") == 1)
	rec.clear()
	ds.on_dug(TileTypes.Type.PEAT, "shovel")
	ds.on_dug(TileTypes.Type.GOLD_ORE, "diamond_pickaxe")
	ds.on_dug(TileTypes.Type.DIAMOND, "diamond_pickaxe")
	ds.on_dug(TileTypes.Type.OBSIDIAN, "diamond_pickaxe")
	ds.on_dug(TileTypes.Type.LAVA, "diamond_pickaxe")
	check("материалы различимы: торф, золото, самоцвет, твёрдое, лава",
			rec.count("dig_peat_shovel") == 1 and rec.count("break_peat") == 1
			and rec.count("dig_gold_pick") == 1 and rec.count("break_gold") == 1
			and rec.count("dig_gem_pick") == 1 and rec.count("break_gem") == 1
			and rec.count("dig_hard_pick") == 1 and rec.count("break_hard") == 1
			and rec.count("dig_lava") == 1 and rec.count("break_lava") == 1)

	# усталость: 12 с непрерывной копки — удары тише, чем в начале
	rec.clear()
	GameState.current_tool = "iron_pickaxe"
	ds = DigSound.new()
	pl.digging = {"x": 7, "y": 20, "t": 0.0, "total": 12.0, "type": TileTypes.Type.STONE}
	t = 0.0
	while t < 12.0:
		t += 1.0 / 60.0
		pl.digging["t"] = t
		ds.tick(pl, 1.0 / 60.0)
	var first_db := rec.first_db("dig_stone_pick")
	var last_db := rec.last_db("dig_stone_pick")
	check("долгая серия устаёт: последний удар тише первого на 1.5+ дБ (%.1f → %.1f)" % [first_db, last_db], last_db < first_db - 1.5)
	pl.digging = null
	ds.tick(pl, 0.016)

	# свёрнутая вкладка: большой скачок t не сыплет очередь ударов
	rec.clear()
	pl.digging = {"x": 8, "y": 20, "t": 0.0, "total": 3.0, "type": TileTypes.Type.STONE}
	ds.tick(pl, 0.016)
	pl.digging["t"] = 2.0
	ds.tick(pl, 2.0)
	ds.tick(pl, 0.016)
	check("скачок времени → один удар, а не очередь", rec.count("dig_stone_pick") == 1)
	pl.digging = null
	ds.tick(pl, 0.016)

	rec.queue_free()
	pl.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------
# Моторы
# ---------------------------------------------------------------------------

func _test_motors() -> void:
	var rec := _Rec.new()
	rec.add_to_group(Sfx.GROUP)
	add_child(rec)
	var pl := _FakePlayer.new()
	add_child(pl)
	var ds := DigSound.new()
	FuelTank.set_fuel("hand_drill", 5.0)
	FuelTank.set_fuel("drill_rig", 5.0)

	GameState.current_tool = "hand_drill"
	pl.digging = {"x": 5, "y": 13, "t": 0.0, "total": 1.0, "type": TileTypes.Type.STONE}
	ds.tick(pl, 0.016)
	check("ручной бур: мотор включается с копкой, без замаха", rec.loops.get("drill_loop", false) and rec.count("swing") == 0)
	var t := 0.0
	while t < 1.0:
		t += 1.0 / 60.0
		pl.digging["t"] = t
		ds.tick(pl, 1.0 / 60.0)
	check("бур грызёт в ритме 0.16 с: 5 ударов dig_stone_drill за секунду", rec.count("dig_stone_drill") == 5)
	check("обороты проседают после удара (loop_set с pitch < 1)", rec.min_pitch("drill_loop") < 0.99)
	ds.on_dug(TileTypes.Type.STONE, "hand_drill")
	pl.digging = null
	ds.tick(pl, 0.1)
	check("пауза между клетками короче 0.35 с: мотор не глушится", rec.loops.get("drill_loop", false))
	ds.tick(pl, 0.3)
	check("копка кончилась: мотор затихает", not rec.loops.get("drill_loop", false))

	# бурмобиль
	rec.clear()
	GameState.current_tool = "drill_rig"
	pl.in_rig = true
	ds.tick(pl, 0.016)
	var idle_db := rec.last_db_loop("rig_loop")
	var idle_pitch := rec.last_pitch("rig_loop")
	check("в бурмобиле двигатель работает на холостых", rec.loops.get("rig_loop", false) and idle_db <= -10.0 and idle_pitch < 1.0)
	pl.digging = {"x": 5, "y": 13, "t": 0.0, "total": 1.0, "type": TileTypes.Type.DIRT}
	t = 0.0
	while t < 1.0:
		t += 1.0 / 60.0
		pl.digging["t"] = t
		ds.tick(pl, 1.0 / 60.0)
	check("под нагрузкой двигатель громче и выше", rec.last_db_loop("rig_loop") > idle_db + 4.0 and rec.last_pitch("rig_loop") > 1.0)
	check("бурмобиль бьёт низко: удары dig_dirt_drill с pitch < 1", rec.count("dig_dirt_drill") == 7 and rec.last_pitch_play("dig_dirt_drill") < 0.9)
	pl.digging = null
	for i in 90:
		ds.tick(pl, 1.0 / 60.0)
	check("без копки двигатель возвращается на холостые", rec.last_db_loop("rig_loop") < idle_db + 1.0 and rec.last_pitch("rig_loop") < idle_pitch + 0.05)
	pl.in_rig = false
	GameState.current_tool = "iron_pickaxe"
	ds.tick(pl, 0.016)
	check("вылез из машины — двигатель заглушен", not rec.loops.get("rig_loop", false))
	ds.stop()

	rec.queue_free()
	pl.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------
# Настоящая сцена: SfxService без жеста, Player копает разные породы
# ---------------------------------------------------------------------------

func _test_real_dig() -> void:
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	GameState.world_seed = 4242
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(8)
	var sfx := get_tree().get_first_node_in_group(Sfx.GROUP) as SfxService
	var dir: JuiceDirector = main.get_node_or_null("JuiceDirector")
	check("в Main есть сервис звука и режиссёр", sfx != null and dir != null)
	if sfx == null or dir == null:
		main.queue_free()
		return
	sfx.require_gesture = false
	sfx.unlocked = true
	var p = main.player
	var world = main.world
	p.frozen = false
	GameState.is_alive = true
	if not GameState.owned_tools.has("iron_pickaxe"):
		GameState.owned_tools.append("iron_pickaxe")
	GameState.set_current_tool("iron_pickaxe")

	# ставим героя на столб из разных пород и копаем вниз: земля, камень, железо, золото, уголь.
	# Породы подкладываем через overlay мира (как делают сцены сюжета); выкопанные — пустые.
	var cx: int = 24
	var cy: int = 12
	var column := [TileTypes.Type.DIRT, TileTypes.Type.STONE, TileTypes.Type.IRON_ORE, TileTypes.Type.GOLD_ORE, TileTypes.Type.COAL]
	var col := {}
	for i in column.size():
		col[Vector2i(cx, cy + 1 + i)] = column[i]
	col[Vector2i(cx, cy)] = TileTypes.Type.EMPTY
	col[Vector2i(cx, cy - 1)] = TileTypes.Type.EMPTY
	world.overlay_y_min = 1
	world.overlay = func(x: int, y: int) -> int:
		var k := Vector2i(x, y)
		if not col.has(k):
			return -1
		if world.diffs.has(world._key(x, y)):
			return TileTypes.Type.EMPTY
		return col[k]
	p.x = float(cx) + 0.5
	p.y = float(cy) + 0.5
	p.vy = 0.0
	p.on_ground = true
	sfx._last_ms.clear()
	sfx.recent.clear()
	var played0: int = sfx.stats["played"]
	var expect := ["dig_dirt_pick", "break_dirt", "dig_stone_pick", "break_stone", "dig_ore_pick", "break_ore",
			"dig_gold_pick", "break_gold", "dig_peat_pick", "break_peat"]
	var dug := 0
	var seen := {}
	var streams := {}
	p.hold_down = true
	var guard := 0
	while dug < column.size() and guard < 60 * 120:
		guard += 1
		p.physics_tick(1.0 / 60.0)
		dir._process(1.0 / 60.0)
		sfx._last_ms.clear()   # ритм ударов здесь ускорен относительно стенных часов — остывание не мешает
		for id in sfx.last_played(4):
			seen[id] = true
		for i in sfx._pool.size():
			if sfx._meta[i]["id"] == "dig_stone_pick" and sfx._pool[i].stream != null:
				streams[sfx._pool[i].stream] = true
		if p.cell_y() > cy + dug:
			dug += 1
	p.hold_down = false
	check("герой прокопал столб из 5 пород (%d)" % dug, dug == column.size())
	check("звуки реально сыграны сервисом (played %d → %d)" % [played0, sfx.stats["played"]], sfx.stats["played"] - played0 >= 20)
	var absent: Array = []
	for id in expect:
		if not seen.has(id):
			absent.append(id)
	check("по каждой породе — свой удар и своё осыпание (нет: %s)" % str(absent), absent.is_empty())
	check("удары чередуют варианты файлов (%d)" % streams.size(), streams.size() >= 2)
	world.overlay = Callable()   # замыкание держит мир — без сброса цикл ссылок течёт при выходе
	main.queue_free()
	await get_tree().create_timer(0.3).timeout


# ---------------------------------------------------------------------------

class _FakePlayer extends Node:
	var x: float = 15.5
	var y: float = 12.5
	var digging = null
	var frozen: bool = false
	var in_rig: bool = false

	func cell_x() -> int:
		return int(floor(x))

	func cell_y() -> int:
		return int(floor(y))

	func is_in_rig() -> bool:
		return in_rig


class _Rec extends Node:
	var calls: Array = []
	var loops := {}

	func clear() -> void:
		calls.clear()

	func count(id: String) -> int:
		return calls.filter(func(c: Array) -> bool: return c[0] == "play" and c[1] == id).size()

	func first_db(id: String) -> float:
		for c in calls:
			if c[0] == "play" and c[1] == id:
				return c[3]
		return 0.0

	func last_db(id: String) -> float:
		var r := 0.0
		for c in calls:
			if c[0] == "play" and c[1] == id:
				r = c[3]
		return r

	func last_pitch_play(id: String) -> float:
		var r := 1.0
		for c in calls:
			if c[0] == "play" and c[1] == id:
				r = c[2]
		return r

	func min_pitch(id: String) -> float:
		var r := 10.0
		for c in calls:
			if c[0] == "loop_set" and c[1] == id:
				r = minf(r, c[3])
		return r

	func last_pitch(id: String) -> float:
		var r := 1.0
		for c in calls:
			if (c[0] == "loop_set" or c[0] == "loop_start") and c[1] == id:
				r = c[3]
		return r

	func last_db_loop(id: String) -> float:
		var r := 0.0
		for c in calls:
			if (c[0] == "loop_set" or c[0] == "loop_start") and c[1] == id:
				r = c[2]
		return r

	func play(id: String, pitch: float = 1.0, vol: float = 0.0) -> void:
		calls.append(["play", id, pitch, vol])

	func loop_start(id: String, vol: float, pitch: float) -> void:
		calls.append(["loop_start", id, vol, pitch])
		loops[id] = true

	func loop_stop(id: String, _fade: float) -> void:
		calls.append(["loop_stop", id])
		loops[id] = false

	func loop_set(id: String, vol: float, pitch: float) -> void:
		calls.append(["loop_set", id, vol, pitch])

	func unlock() -> void:
		pass

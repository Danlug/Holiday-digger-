extends Node
## test_greed — режим жадности (ГДД §20.1, слова владельца раунда 4): порог и
## длительность по ступеням ветки «Жадность», копка с первого удара, ход и падение
## ×7 без лишнего урона и без прохода сквозь породу, конец режима, ступень в сейве.
## Настоящий Player на мире-полигоне (клетки задаёт тест), шаги физики — вручную.
##
## Запуск:  godot --headless --path . res://tests/test_greed.tscn

const DT := 1.0 / 60.0
const FLOOR_Y := 200

var failures := 0
var total := 0


## Мир-полигон: всё, чего нет в словаре, — пустота (пещера), клетки — какие задали.
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


class StubHost:
	extends Node
	var player: Node
	var world: WorldGen
	var fog: FogOfWar
	var view_root: Node2D


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _ready() -> void:
	print("=== test_greed ===")
	await get_tree().process_frame
	Settings.reduce_motion = false
	GameState.reset_progress()
	StoryState.set_flag("food_ordered", true)   # механики — после онбординга
	_test_rules()
	_test_logic_by_stage()
	_test_first_hit()
	_test_speed_walk()
	_test_speed_fall()
	_test_fall_damage()
	_test_collisions()
	_test_jump_and_fly()
	await _test_director()
	_test_save_and_tree()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _player(arena: Arena) -> Node:
	var p = load("res://scripts/player/player.gd").new()
	p.world = arena
	add_child(p)
	GameState.is_alive = true
	GameState.hp = GameState.get_max_hp()
	GameState.current_tool = "iron_pickaxe"
	return p


func _steps(p, n: int, dt: float = DT) -> void:
	for i in n:
		p.physics_tick(dt)


# ---------------------------------------------------------------------------

func _test_rules() -> void:
	var at := []
	var sec := []
	for s in range(0, 6):
		at.append(GreedRules.threshold(s))
		sec.append(roundi(GreedRules.seconds(s)))
	check("порог по ступеням 60/57/54/51/48/45 (−5…−25%%): %s" % str(at), at == [60, 57, 54, 51, 48, 45])
	check("длительность по ступеням 3/4/5/6/7/8 с: %s" % str(sec), sec == [3, 4, 5, 6, 7, 8])
	check("ветка «Жадность» — 5 ступеней", GreedRules.max_stage() == 5)
	check("скорость ×7", is_equal_approx(GreedRules.speed_mult(), 7.0))
	check("первый удар кирки — полпериода удара (0.19 с)",
		is_equal_approx(GreedRules.dig_seconds("iron_pickaxe"), Feel.hit_period("iron_pickaxe") * 0.5))
	check("бурмобиль бьёт чаще — его первый удар раньше",
		GreedRules.dig_seconds("drill_rig") < GreedRules.dig_seconds("iron_pickaxe"))


func _test_logic_by_stage() -> void:
	var s := StreakLogic.new(5)
	check("ступень 5: шкала 45 клеток, жадность 8 с", s.fever_at == 45 and is_equal_approx(s.greed_s, 8.0))
	for i in range(44):
		s.on_dug(100)
	check("44 клетки — ещё нет", not s.in_greed())
	check("45-я — жадность", bool(s.on_dug(100)["started"]) and s.in_greed())
	s.tick(7.9, true, true)
	check("7.9 с — ещё жадность", s.in_greed())
	s.tick(0.2, false, true)
	check("8 с — конец, серия с нуля", not s.in_greed() and s.count == 0)
	var t := StreakLogic.new(0)
	for i in range(50):
		t.on_dug(100)
	t.set_stage(4)
	check("купил ступень посреди серии — порог ближе, серия цела", t.count == 50 and t.fever_at == 48)
	check("следующая клетка — сразу жадность (51 ≥ 48)", bool(t.on_dug(100)["started"]))


func _test_first_hit() -> void:
	var a := Arena.new()
	a.fill(10, FLOOR_Y, 12, FLOOR_Y + 3, TileTypes.Type.STONE)
	var p = _player(a)
	p.x = 11.5
	p.y = float(FLOOR_Y) - 0.34
	p.on_ground = true
	p._start_dig(11, FLOOR_Y)
	var normal: float = p.digging.total
	p.digging = null
	p.greed_mult = 7.0
	p._start_dig(11, FLOOR_Y)
	var greedy: float = p.digging.total
	check("камень киркой: обычно %.2f с, в жадности %.2f с (первый удар)" % [normal, greedy],
		normal > 2.0 and is_equal_approx(greedy, GreedRules.dig_seconds("iron_pickaxe")))
	_steps(p, int(ceil(greedy / DT)) + 1)
	check("клетка выкопана за первый удар", a.get_tile(11, FLOOR_Y) == TileTypes.Type.EMPTY)
	# несокрушимое — и в жадности несокрушимо
	p.digging = null
	a.cells.clear()
	a.fill(10, FLOOR_Y, 12, FLOOR_Y, TileTypes.Type.REINFORCED)
	p.x = 11.5
	p.y = float(FLOOR_Y) - 0.34
	p.vy = 0.0
	p._start_dig(11, FLOOR_Y)
	_steps(p, 30)
	check("зафиксированная порода не копается и в жадности", a.get_tile(11, FLOOR_Y) == TileTypes.Type.REINFORCED)
	# лава — 5 с всегда
	p.digging = null
	a.cells.clear()
	a.fill(10, FLOOR_Y, 12, FLOOR_Y, TileTypes.Type.STONE)
	a.cells[Vector2i(11, FLOOR_Y)] = TileTypes.Type.LAVA
	GameState.debug_invincible = true
	p._start_dig(11, FLOOR_Y)
	GameState.debug_invincible = false
	check("лава в жадности — те же %.0f с" % Heat.lava_dig_seconds(),
		p.digging != null and is_equal_approx(float(p.digging.total), Heat.lava_dig_seconds()))
	p.digging = null
	p.queue_free()


## Коридор: пол на FLOOR_Y, герой идёт вправо N кадров.
func _walk_distance(mult: float, frames: int, dt: float = DT) -> float:
	var a := Arena.new()
	a.fill(0, FLOOR_Y, 31, FLOOR_Y, TileTypes.Type.STONE)
	var p = _player(a)
	p.x = 2.5
	p.y = float(FLOOR_Y) - 0.34
	p.on_ground = true
	p.greed_mult = mult
	p.set_intent(1, false, false)
	_steps(p, frames, dt)
	var d: float = p.x - 2.5
	p.queue_free()
	return d


func _test_speed_walk() -> void:
	var n1 := _walk_distance(1.0, 30)
	var n7 := _walk_distance(7.0, 30)
	check("ходьба: за 0.5 с обычно %.2f кл., в жадности %.2f кл. (×%.2f)" % [n1, n7, n7 / n1],
		absf(n7 / n1 - 7.0) < 0.15)


## Шахта: пол на FLOOR_Y, герой падает с высоты h; сколько кадров до земли.
func _fall(mult: float, h: float, dt: float = DT) -> Dictionary:
	var a := Arena.new()
	a.fill(0, FLOOR_Y, 31, FLOOR_Y + 1, TileTypes.Type.STONE)
	var p = _player(a)
	p.x = 15.5
	p.y = float(FLOOR_Y) - h
	p.vy = 0.0
	p.on_ground = false
	p.greed_mult = mult
	var hp0: float = GameState.hp
	var frames := 0
	while not p.on_ground and frames < 2000:
		p.physics_tick(dt)
		frames += 1
	var out := {"frames": frames, "dmg": hp0 - GameState.hp, "y": p.y}
	GameState.hp = GameState.get_max_hp()
	GameState.is_alive = true
	p.queue_free()
	return out


func _test_speed_fall() -> void:
	var f1 := _fall(1.0, 30.0)
	var f7 := _fall(7.0, 30.0)
	var k := float(f1["frames"]) / float(f7["frames"])
	check("падение 30 кл.: обычно %d кадров, в жадности %d (×%.1f)" % [f1["frames"], f7["frames"], k],
		k > 6.0 and k < 8.0)


func _test_fall_damage() -> void:
	for h in [1.2, 4.0, 12.0, 22.0]:
		var f1 := _fall(1.0, h)
		var f7 := _fall(7.0, h)
		check("падение %.0f кл.: урон в жадности %.0f = обычному %.0f" % [h, f7["dmg"], f1["dmg"]],
			absf(float(f7["dmg"]) - float(f1["dmg"])) < 0.6)
	check("клетка вниз в жадности не ранит", float(_fall(7.0, 1.2)["dmg"]) == 0.0)
	check("12 кл. ранят как обычно (проверка, что урон вообще считается)", float(_fall(1.0, 12.0)["dmg"]) > 0.0)


func _test_collisions() -> void:
	# стена в клетку толщиной: бег ×7 на 30 к/с полсекунды — не насквозь
	var a := Arena.new()
	a.fill(0, FLOOR_Y, 31, FLOOR_Y, TileTypes.Type.STONE)
	a.fill(8, FLOOR_Y - 1, 8, FLOOR_Y - 1, TileTypes.Type.REINFORCED)
	var p = _player(a)
	p.x = 2.5
	p.y = float(FLOOR_Y) - 0.34
	p.on_ground = true
	p.greed_mult = 7.0
	p.set_intent(1, false, false)
	_steps(p, 30, 0.033)
	check("бег ×7 упирается в стену толщиной в клетку (x=%.2f)" % p.x, p.x < 8.0)
	p.queue_free()
	# падение ×7 с предельной скоростью на 30 к/с — на пол в клетку, а не сквозь
	var f := _fall(7.0, 90.0, 0.033)
	check("падение ×7 с 90 кл. на 30 к/с встаёт на пол (y=%.2f)" % f["y"],
		float(f["y"]) < float(FLOOR_Y) and float(f["y"]) > float(FLOOR_Y) - 1.0)


func _test_jump_and_fly() -> void:
	var a := Arena.new()
	a.fill(0, FLOOR_Y, 31, FLOOR_Y, TileTypes.Type.STONE)
	var p = _player(a)
	p.x = 15.5
	p.y = float(FLOOR_Y) - 0.34
	p.on_ground = true
	p.greed_mult = 7.0
	p.set_intent(0, true, false)
	var top: float = p.y
	for i in 12:
		p.physics_tick(DT)
		top = minf(top, p.y)
	check("прыжок в жадности — та же высота (%.2f кл.), только быстрее" % (float(FLOOR_Y) - 0.34 - top),
		float(FLOOR_Y) - 0.34 - top > 1.8)
	p.queue_free()


func _test_director() -> void:
	GameState.skill_stages["greed"] = 2
	var a := Arena.new()
	a.fill(0, FLOOR_Y, 31, FLOOR_Y + 5, TileTypes.Type.DIRT)
	var host := StubHost.new()
	host.name = "Host"
	var p = load("res://scripts/player/player.gd").new()
	p.name = "Player"
	p.world = a
	p.x = 15.5
	p.y = float(FLOOR_Y) - 0.34
	p.on_ground = true
	host.player = p
	host.world = a
	host.fog = FogOfWar.new()
	host.view_root = Node2D.new()
	host.add_child(p)
	host.add_child(host.view_root)
	add_child(host)
	var d := Mechanics.attach(host) as MechDirector
	await get_tree().process_frame
	d.set_process(false)
	d.step(DT)
	check("ступень 2: шкала 54 клетки, жадность 5 с", d.streak.fever_at == 54 and is_equal_approx(d.streak.greed_s, 5.0))
	for i in range(54):
		GameState.emit_event(&"dug", {"cell": Vector2i(3, FLOOR_Y + 10), "tile": TileTypes.Type.DIRT, "mineral": "", "loot": false})
	check("54 клетки — жадность, герой ×7", d.streak.in_greed() and is_equal_approx(p.greed_mult, 7.0))
	check("значок над героем создан", d.badge != null and d.badge.get_parent() == host.view_root)
	# копаем вниз: клетка за первый удар, падение и снова копка
	p.set_intent(0, false, true)
	var y0: float = p.y
	for i in range(60):
		p.physics_tick(DT)
		d.step(DT)
	var dug := int(round(p.y - y0))
	check("за секунду жадности вниз прокопано %d клеток (обычно земля киркой — 1.8 с/кл.)" % dug, dug >= 3)
	# долгое падение ×7 на 30 к/с: за кадр герой проходит до 7 клеток — туман по пути
	# открывает режиссёр (main.gd открывает только вокруг конечной точки, как здесь)
	p.set_intent(0, false, false)
	p.digging = null
	p.x = 20.5
	p.y = float(FLOOR_Y) - 80.0
	p.vy = 0.0
	p.on_ground = false
	d.step(0.033)
	GameState.debug_invincible = true   # 80 клеток убили бы героя, а смерть гасит жадность — здесь проверяется туман
	var tr := GameState.get_vision_terrain_radius()
	var rr := GameState.get_vision_resource_radius()
	var max_step := 0.0
	for i in range(120):
		var y_before: float = p.y
		p.physics_tick(0.033)
		max_step = maxf(max_step, p.y - y_before)
		host.fog.reveal_around(p.x, p.y, tr, rr)
		d.step(0.033)
		if p.on_ground:
			break
	GameState.debug_invincible = false
	var dark := 0
	for yy in range(FLOOR_Y - 78, FLOOR_Y - 1):
		if host.fog.get_state(20, yy) == FogOfWar.State.BLACK:
			dark += 1
	check("падение ×7 (до %.1f кл. за кадр) не оставляет тёмных клеток на пути: %d" % [max_step, dark],
		max_step > 2.0 * float(tr) and dark == 0)
	var ended := [false]
	d.fever_ended.connect(func() -> void: ended[0] = true)
	for i in range(int(5.0 / DT)):
		d.step(DT)
	check("через 5 с жадность кончилась: ×1, сигнал конца", not d.streak.in_greed() and is_equal_approx(p.greed_mult, 1.0) and ended[0])
	# дом/смерть рвут жадность
	for i in range(54):
		GameState.emit_event(&"dug", {"cell": Vector2i(3, FLOOR_Y + 10), "tile": TileTypes.Type.DIRT, "mineral": "", "loot": false})
	check("снова жадность", d.streak.in_greed())
	GameState.died.emit()
	check("смерть гасит жадность и ×7", not d.streak.in_greed() and is_equal_approx(p.greed_mult, 1.0))
	host.queue_free()
	GameState.skill_stages.erase("greed")


func _test_save_and_tree() -> void:
	GameState.reset_progress()
	GameState.skill_points_available = 100
	check("ступень жадности покупается за 4 очка", SkillTree.try_buy("greed", false)
		and GameState.get_skill_stage("greed") == 1 and GameState.skill_points_available == 96)
	SkillTree.try_buy("greed", false)
	SkillTree.try_buy("greed", false)
	var data = JSON.parse_string(JSON.stringify(SaveSystem._serialize()))
	GameState.reset_progress()
	check("сброс — ступень 0", GameState.get_skill_stage("greed") == 0)
	SaveSystem._apply(data)
	check("ступень 3 пережила сейв", GameState.get_skill_stage("greed") == 3)
	var txt := SkillTree.effect_text(Balance.get_upgrade_branch("greed"), 3)
	check("подсказка ступени: «%s»" % txt, txt.contains("6 с") and txt.contains("51"))
	check("у ветки есть значок", HeroIcons.skill_icon("greed") != null)

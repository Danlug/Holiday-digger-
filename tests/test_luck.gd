extends Node
## test_luck — удача (ГДД §11, решение владельца раунда 3): шанс бросается на каждую
## прокопанную клетку («ресурс» — добыча, «земля» — земля и камень); при удаче находка
## умножается на множитель удачи, а пока ветка множителя не куплена — ×2. У руды
## умножаются штуки, у земли — опыт. Случайность — свой сид, реальное время не нужно.
##
## Запуск: godot --headless --path . res://tests/test_luck.tscn

var failures := 0
var total := 0
var _events: Array = []


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_luck ===")
	for _i in range(4):
		await get_tree().process_frame
	GameState.game_event.connect(func(id: StringName, data: Dictionary):
		if id == &"lucky_find":
			_events.append(data))
	_test_roll()
	_test_dig_ore()
	_test_dig_earth()
	_test_full_backpack()
	_test_achievement()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_roll() -> void:
	check("без ступеней шанса удачи нет", Balance.luck_find_multiplier(0.0, true, 0, 3) == 1)
	check("пока множитель не куплен, удача даёт ×2", Balance.luck_find_multiplier(0.5, true, 1, 0) == 2)
	check("ресурс 1-й ступени: 1% — бросок 1.0 уже мимо", Balance.luck_find_multiplier(1.0, true, 1, 0) == 1)
	check("ресурс 5-й ступени: 5%", Balance.luck_find_multiplier(4.9, true, 5, 0) == 2
			and Balance.luck_find_multiplier(5.0, true, 5, 0) == 1)
	check("земля 5-й ступени: 10%", Balance.luck_find_multiplier(9.9, false, 5, 0) == 2
			and Balance.luck_find_multiplier(10.0, false, 5, 0) == 1)
	check("множитель ×3 и ×4 на ступенях 2 и 3", Balance.luck_find_multiplier(0.0, true, 5, 2) == 3
			and Balance.luck_find_multiplier(0.0, true, 5, 3) == 4)
	check("находка при удаче без множителя — ×2", Balance.get_lucky_find_multiplier(0) == 2)


func _fresh(chance_stage: int, mult_stage: int) -> void:
	GameState.reset_progress()
	GameState.is_alive = true
	GameState.house_is_indoors = false
	GameState.debug_invincible = false
	GameState.current_tool = "iron_pickaxe"
	GameState.skill_stages["luck_chance"] = chance_stage
	GameState.skill_stages["luck_multiplier"] = mult_stage
	_events.clear()


func _player(world: WorldGen) -> Node:
	var p = preload("res://scripts/player/player.gd").new()
	p.world = world
	add_child(p)
	return p


## Сид, у которого первый бросок попадает (или не попадает) в percent.
func _rng(percent: float, hit: bool) -> RandomNumberGenerator:
	for s in range(1, 5000):
		var r := RandomNumberGenerator.new()
		r.seed = s
		if (r.randf() * 100.0 < percent) == hit:
			var out := RandomNumberGenerator.new()
			out.seed = s
			return out
	return null


func _find(world: WorldGen, want_loot: bool, want_type: int = -1) -> Vector2i:
	for y in range(30, 400):
		for x in range(0, 40):
			var t := world.get_tile(x, y)
			if t == TileTypes.Type.EMPTY or not TileTypes.is_diggable(t):
				continue
			if want_type >= 0 and t != want_type:
				continue
			if MineralMap.is_loot(t) == want_loot and (not want_loot or not MineralMap.mineral_id_for(t).is_empty()):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _dig(p: Node, world: WorldGen, cell: Vector2i) -> void:
	p.digging = {"x": cell.x, "y": cell.y, "t": 0.0, "total": 1.0, "type": world.get_tile(cell.x, cell.y)}
	p._finish_dig()


func _test_dig_ore() -> void:
	var world := WorldGen.new(4242)
	var cell := _find(world, true)
	check("нашлась руда", cell.x >= 0)
	var mineral := MineralMap.mineral_id_for(world.get_tile(cell.x, cell.y))

	_fresh(5, 2)
	var p = _player(world)
	p._luck_rng = _rng(5.0, true)
	_dig(p, world, cell)
	check("удача на руде: ×3 штуки при множителе 2-й ступени", GameState.get_item_count(mineral) == 3)
	check("событие lucky_find с множителем 3", _events.size() == 1 and int(_events[0]["mult"]) == 3
			and String(_events[0]["mineral"]) == mineral)
	p.queue_free()

	var world2 := WorldGen.new(4242)
	_fresh(5, 2)
	var p2 = _player(world2)
	p2._luck_rng = _rng(5.0, false)
	_dig(p2, world2, cell)
	check("без удачи — одна штука", GameState.get_item_count(mineral) == 1 and _events.is_empty())
	p2.queue_free()

	var world3 := WorldGen.new(4242)
	_fresh(0, 3)
	var p3 = _player(world3)
	_dig(p3, world3, cell)
	check("без ступеней шанса бросок не делается вовсе", p3._luck_rng == null
			and GameState.get_item_count(mineral) == 1)
	p3.queue_free()


func _test_dig_earth() -> void:
	var cell := _find(WorldGen.new(4242), false, TileTypes.Type.DIRT)
	check("нашлась земля", cell.x >= 0)
	# Опыт за клетку смешан с бонусом новой глубины — сравниваем с тем же ударом без удачи.
	var gained := []
	for hit in [false, true]:
		var world := WorldGen.new(4242)
		_fresh(5, 0)
		var p = _player(world)
		p._luck_rng = _rng(10.0, hit)
		var xp0 := GameState.xp
		_dig(p, world, cell)
		gained.append(GameState.xp - xp0)
		p.queue_free()
	check("удача на земле: опыт за клетку ×2 (+1 к обычному: %d → %d)" % gained, int(gained[1]) - int(gained[0]) == 1)
	check("событие удачи на земле без минерала", _events.size() == 1 and String(_events[0]["mineral"]) == "")


func _test_full_backpack() -> void:
	var world := WorldGen.new(4242)
	var cell := _find(world, true)
	var mineral := MineralMap.mineral_id_for(world.get_tile(cell.x, cell.y))
	_fresh(5, 3)
	# Места ровно на две штуки: удача ×4 даёт только то, что влезло.
	var w := Balance.get_mineral_weight(mineral)
	if w <= 0.0:
		check("у руды есть вес (иначе проверка рюкзака невозможна)", false)
		return
	var filler := "stone" if Balance.get_mineral_weight("stone") > 0.0 else mineral
	var free_kg := GameState.get_max_carry_kg() - GameState.get_total_weight()
	var fill_kg := free_kg - 2.0 * w - w * 0.5
	if filler != mineral and fill_kg > 0.0:
		GameState.inventory[filler] = int(floor(fill_kg / Balance.get_mineral_weight(filler)))
	var p = _player(world)
	p._luck_rng = _rng(5.0, true)
	var before := GameState.get_item_count(mineral)
	_dig(p, world, cell)
	var got := GameState.get_item_count(mineral) - before
	check("полный рюкзак: удача кладёт только то, что влезло (%d)" % got, got >= 1 and got <= 4)
	check("событие показывает реально полученное", _events.is_empty() and got == 1
			or (_events.size() == 1 and int(_events[0]["mult"]) == got))
	p.queue_free()


## «Удачник»: счётчик lucky копится по событию lucky_find, ступени 100/200/500/2000/5000.
func _test_achievement() -> void:
	GameState.reset_progress()
	MetaState.root()["unlocked"] = true
	var ids := []
	for a in MetaData.achievements():
		if String(a["counter"]) == "lucky":
			ids.append([String(a["id"]), int(a["target"])])
	check("у «Удачника» 5 ступеней: 100, 200, 500, 2000, 5000",
			ids.map(func(r): return r[1]) == [100, 200, 500, 2000, 5000])
	check("значок клевера есть", ResourceLoader.exists("res://art/meta/clover.png"))
	for i in range(99):
		MetaEvents.apply(&"lucky_find", {"mineral": "", "mult": 2})
	check("99 удач — ещё не «Удачник»", not Achievements.is_done("lucky_100") and MetaState.counter("lucky") == 99)
	var coins0 := GameState.coins
	var got: Array = MetaEvents.apply(&"lucky_find", {"mineral": "iron_ore", "mult": 2})["ach"]
	check("сотая удача открывает «Удачника» и даёт награду", Achievements.is_done("lucky_100")
			and got.size() == 1 and String(got[0]["id"]) == "lucky_100" and GameState.coins > coins0)
	for i in range(100):
		MetaEvents.apply(&"lucky_find", {"mineral": "", "mult": 2})
	check("двухсотая — вторая ступень, третья ещё закрыта", Achievements.is_done("lucky_200")
			and not Achievements.is_done("lucky_500"))
	GameState.reset_progress()

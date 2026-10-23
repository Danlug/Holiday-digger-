extends Node
## test_economy_sanity — сторож баланса: закрытые «расхождения» ГДД §18 и
## достижимость каждой ступени прогресса.
##
## Запуск: godot --headless --path . res://tests/test_economy_sanity.tscn
##
## Что ловит:
##  * числа, на которых договорились (бур ×2 от кирки, стан 1 с, бронза 1:1, клад 50 монет),
##    не «уехали» обратно в данных или в запасных значениях кода;
##  * ступень, для которой в мире нет материала (нельзя собрать — тупик прогресса):
##    так было с ручным буром, пока металлолом лежал только до глубины 200;
##  * линейки кирок и ранцев перестали расти по цене и по эффекту.
## Полное время по ступеням считает tools/sim_economy.gd — здесь только инварианты.

var failures := 0
var total := 0

## Доля материала на ступень от всего запаса в окне глубин: больше — игроку придётся
## выкопать почти всё, что есть, и часть сидов не соберёт ступень вовсе. Порог 60% взят по
## симулятору: при 50% бур собирали все шесть сидов (за ~5.7 ч), при ~78% — два из шести.
const MAX_SHARE_OF_SUPPLY := 0.60
const SUPPLY_WINDOW := 1000
const SUPPLY_SEEDS := [11, 4242, 777001]


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _ready() -> void:
	print("=== test_economy_sanity ===")
	_test_closed_discrepancies()
	_test_stun_duration()
	_test_ladders_monotonic()
	_test_ingredients_reachable()
	_test_start_money_buys_backpack()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


# ---------------------------------------------------------------------------
# ГДД §18 «Расхождения, которые надо закрыть» — решения зафиксированы тестом
# ---------------------------------------------------------------------------

func _test_closed_discrepancies() -> void:
	# 1. Ручной бур — в 2 раза быстрее лучшей кирки, бурмобиль — в 2 раза быстрее бура (ГДД §5).
	# Демо-множитель 0.45 — число старого прототипа с одной кирки, к нынешней линейке не относится.
	var best := Balance.get_best_pickaxe_speed_multiplier()
	check("ручной бур = 2 × лучшая кирка (ГДД §5)",
		is_equal_approx(Balance.get_tool_speed_multiplier("hand_drill"), 2.0 * best))
	check("бурмобиль = 2 × ручной бур",
		is_equal_approx(Balance.get_tool_speed_multiplier("drill_rig"),
			2.0 * Balance.get_tool_speed_multiplier("hand_drill") * Balance.get_drill_rig_tier_multiplier(0)))

	# 2. Стан от лопаты — секунда, а не минута (ГДД §5).
	var stun: float = float(Balance.unwrap(Balance.balance.get("digging", {}).get("shovel_stun_on_stone_or_gold_seconds", -1)))
	check("стан от лопаты в данных — 1 секунда", is_equal_approx(stun, 1.0), "в данных: %s" % stun)

	# 3. Бронза 1:1 — и в balance.json, и в minerals.json, и в рецепте мастерской.
	check("balance.json: 1 металлолом = 1 бронза",
		int(Balance.unwrap(Balance.balance.get("crafting", {}).get("scrap_per_bronze", 0))) == 1)
	var bronze_recipe: Dictionary = Balance.get_mineral("bronze").get("recipe", {})
	check("minerals.json: рецепт бронзы 1:1", int(bronze_recipe.get("scrap", 0)) == 1,
		"в данных: %s" % str(bronze_recipe))
	check("мастерская плавит бронзу 1:1", int(ShopCatalog.recipe("bronze").get("inputs", {}).get("scrap", 0)) == 1)

	# 4. Никчёмный клад — 50 монет и 5 премиума (ГДД §9); сцена и данные артефакта сходятся.
	var story := _read_json("res://data/story.json")
	var scene_coins := 0
	var scene_dollars := 0
	for sc in story.get("scenes", []):
		if String(sc.get("id", "")) != "dud_treasure":
			continue
		for e in sc.get("effects", []):
			if String(e.get("do", "")) == "coins":
				scene_coins += int(e.get("n", 0))
			if String(e.get("do", "")) == "dollars":
				scene_dollars += int(e.get("n", 0))
	check("сцена клада: 50 монет и 5 премиума", scene_coins == 50 and scene_dollars == 5,
		"монеты %d, доллары %d" % [scene_coins, scene_dollars])
	check("данные артефакта antiquity_1: те же 50 монет", Balance.get_artifact_find_coins("antiquity_1") == scene_coins,
		"в данных: %d" % Balance.get_artifact_find_coins("antiquity_1"))


## Настоящий удар лопатой по золоту после мастерской: герой оглушён примерно на секунду,
## а не на запасные 60 из кода.
func _test_stun_duration() -> void:
	var world := WorldGen.new(20260101)
	var player = preload("res://scripts/player/player.gd").new()
	player.world = world
	add_child(player)
	var saved_seen: Array = GameState.story_seen.duplicate()
	var saved_tool := GameState.current_tool
	var cell: Vector2i = world.scripted_loot_cells()[0]
	for y in range(1, cell.y):
		world.dig_cell(cell.x, y)
	GameState.current_tool = "shovel"
	if not GameState.story_seen.has("workshop"):
		GameState.story_seen.append("workshop")
	player.x = float(cell.x) + 0.5
	player.y = float(cell.y) - player.HH - 0.01
	player.on_ground = true
	player.hold_dx = 0
	player.hold_up = false
	player.hold_down = true
	player.stun_until_msec = 0.0
	for _i in range(4):
		player.physics_tick(1.0 / 60.0)
	var left_ms: float = player.stun_until_msec - float(Time.get_ticks_msec())
	check("лопата о золото оглушает примерно на секунду", left_ms > 300.0 and left_ms <= 1100.0,
		"осталось %.0f мс" % left_ms)
	GameState.story_seen = saved_seen
	GameState.current_tool = saved_tool
	player.queue_free()


# ---------------------------------------------------------------------------
# Линейки растут: дороже — лучше
# ---------------------------------------------------------------------------

func _test_ladders_monotonic() -> void:
	var picks := Balance.get_tools_in_line("pickaxe")
	var ok_cost := true
	var ok_speed := true
	for i in range(1, picks.size()):
		if Balance.get_tool_cost_coins(picks[i]) <= Balance.get_tool_cost_coins(picks[i - 1]):
			ok_cost = false
		if Balance.get_tool_speed_multiplier(picks[i]) <= Balance.get_tool_speed_multiplier(picks[i - 1]):
			ok_speed = false
	check("кирки: каждая следующая дороже", ok_cost, str(picks))
	check("кирки: каждая следующая быстрее", ok_speed, str(picks))

	var gear := Balance.get_gear_ids()
	var gear_cost_ok := true
	var gear_speed_ok := true
	for i in range(1, gear.size()):
		if Balance.get_gear_cost_coins(gear[i]) <= Balance.get_gear_cost_coins(gear[i - 1]):
			gear_cost_ok = false
		if Balance.get_gear_fly_multiplier(gear[i]) <= Balance.get_gear_fly_multiplier(gear[i - 1]):
			gear_speed_ok = false
	check("ранцы: каждая следующая ступень дороже", gear_cost_ok, str(gear))
	check("ранцы: каждая следующая летит быстрее", gear_speed_ok, str(gear))


# ---------------------------------------------------------------------------
# Каждый материал ступени реально лежит в мире, и в разумном количестве
# ---------------------------------------------------------------------------

func _test_ingredients_reachable() -> void:
	var needs: Dictionary = {}  # id материала -> [сколько нужно, для какой ступени]
	var per_bronze := maxi(1, int(Balance.unwrap(Balance.balance.get("crafting", {}).get("scrap_per_bronze", 1))))
	for tool_id in Balance.balance.get("tools", {}).keys():
		var cost := Balance.get_tool_cost(String(tool_id))
		for item in cost.keys():
			if String(item) == "coins":
				continue
			var n := int(Balance.unwrap(cost[item]))
			var id := String(item)
			if id == "bronze":
				id = "scrap"
				n *= per_bronze
			if not needs.has(id) or n > int(needs[id][0]):
				needs[id] = [n, String(tool_id)]

	for id: String in needs.keys():
		var mineral := Balance.get_mineral(id)
		var d_min := int(Balance.unwrap(mineral.get("depth_min", 1)))
		var tile := MineralMap.tile_type_for(id)
		if tile < 0 or d_min < 0:
			check("материал %s (для %s) вообще добывается" % [id, needs[id][1]], false)
			continue
		var found := 0
		for seed_value in SUPPLY_SEEDS:
			found += _count_tiles(WorldGen.new(int(seed_value)), tile, maxi(d_min, 1), SUPPLY_WINDOW)
		var supply := float(found) / float(SUPPLY_SEEDS.size())
		var need := float(needs[id][0])
		check("материал %s: %d нужно на «%s», в окне %d..%d в мире ~%.0f (доля %.0f%% ≤ %.0f%%)" % [
			id, int(need), needs[id][1], d_min, d_min + SUPPLY_WINDOW, supply, 100.0 * need / maxf(supply, 1.0),
			100.0 * MAX_SHARE_OF_SUPPLY], need <= supply * MAX_SHARE_OF_SUPPLY)


func _count_tiles(world: WorldGen, tile: int, y0: int, rows: int) -> int:
	var n := 0
	for y in range(y0, y0 + rows):
		for x in range(WorldGen.WIDTH):
			if world.get_tile(x, y) == tile:
				n += 1
	return n


# ---------------------------------------------------------------------------
# Первая покупка доступна сразу после онбординга
# ---------------------------------------------------------------------------

func _test_start_money_buys_backpack() -> void:
	var tutorial_money := 5 * Balance.get_mineral_price("gold") + Balance.get_artifact_find_coins("antiquity_1")
	check("пять самородков и клад оплачивают ранец (первая покупка)",
		tutorial_money >= Balance.get_gear_cost_coins("backpack"),
		"денег после обучения %d, ранец %d" % [tutorial_money, Balance.get_gear_cost_coins("backpack")])

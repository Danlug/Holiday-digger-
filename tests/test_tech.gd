extends Node
## test_tech — ветка «Техника»: бак и заправка, жара, лава и костюм, idle-скважина
## (доход, ступени, офлайн-кап, защита от перемотки часов, окно отчёта, «×2»).
## Время симулируем явными метками unix (collect(now)), реальные часы не трогаем.
##
## Запуск: godot --headless --path . res://tests/test_tech.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _fresh() -> void:
	GameState.reset_progress()
	GameState.is_alive = true
	GameState.house_is_indoors = false
	GameState.player_depth = 0
	GameState.debug_invincible = false
	GameState.coins = 0
	GameState.dollars = 0


func _ready() -> void:
	print("=== test_tech ===")
	for _i in range(4):
		await get_tree().process_frame
	_test_data()
	_test_fuel_tank()
	_test_persistence()
	_test_player_fuel()
	_test_heat()
	_test_suit()
	_test_lava_field()
	_test_lava_dig()
	_test_well_formula()
	_test_well_time()
	_test_well_upgrade()
	_test_double_and_ads()
	await _test_screens()
	await _test_system()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------------------
# Данные
# ---------------------------------------------------------------------------

func _test_data() -> void:
	TechData.reload()
	for tool_id in ["hand_drill", "drill_rig"]:
		var caps := FuelTank.capacities(tool_id)
		var ok := caps.size() == 5
		for i in range(1, caps.size()):
			ok = ok and float(caps[i]) > float(caps[i - 1])
		check("%s: ёмкости баков растут по уровням" % tool_id, ok)
		var costs = TechData.v(TechData.fuel()["tanks"][tool_id]["upgrade_cost"])
		check("%s: цен улучшений на одну меньше, чем уровней" % tool_id, costs.size() == caps.size() - 1)
		check("%s: расход на клетку задан в balance.json" % tool_id, FuelTank.rate_per_cell(tool_id) > 0.0)
		var cells_prev := 0.0
		var growing := true
		for c in caps:
			var cells := float(c) / FuelTank.rate_per_cell(tool_id)
			growing = growing and cells > cells_prev
			cells_prev = cells
		check("%s: ход на баке растёт" % tool_id, growing)
	var tiers := Heat.suit_tiers()
	var ok_t := tiers.size() == 5
	for i in range(1, tiers.size()):
		ok_t = ok_t and float(tiers[i]["tolerance_c"]) > float(tiers[i - 1]["tolerance_c"]) \
			and float(tiers[i]["lava_resist"]) > float(tiers[i - 1]["lava_resist"]) \
			and int(tiers[i]["unlock_depth"]) >= int(tiers[i - 1]["unlock_depth"]) \
			and int(tiers[i]["cost"]["coins"]) > int(tiers[i - 1]["cost"]["coins"])
	check("ступени костюма строго растут: стойкость, защита, глубина, цена", ok_t)
	check("последняя ступень делает лаву проходимой (защита 100%)", float(tiers[tiers.size() - 1]["lava_resist"]) == 1.0)
	var levels := IdleWell.levels()
	var ok_w := levels.size() == 10
	for i in range(1, levels.size()):
		ok_w = ok_w and int(levels[i]["depth_cap"]) > int(levels[i - 1]["depth_cap"]) \
			and float(levels[i]["cells_per_hour"]) > float(levels[i - 1]["cells_per_hour"]) \
			and float(levels[i]["cap_hours"]) >= float(levels[i - 1]["cap_hours"]) \
			and levels[i]["cost"] != null
	check("ступени скважины растут: глубина, скорость, кап; у каждой кроме первой есть цена", ok_w)
	check("первая ступень (постройка) без цены ступени", levels[0]["cost"] == null)
	for key in ["capacity_blocks", "upgrade_cost"]:
		var n = TechData.fuel()["tanks"]["hand_drill"][key]
		# баки владелец утвердил на странице разбора чисел (26.10)
		check("числа бака %s утверждены (proposed: false)" % key, typeof(n) == TYPE_DICTIONARY and n.get("proposed", true) == false)
	# владелец принял совет на странице разбора чисел (26.10): ступени костюма утверждены
	check("ступени костюма утверждены владельцем (proposed: false)", TechData.heat()["suit_tiers"].get("proposed", true) == false)
	check("ступени скважины помечены proposed", TechData.well()["levels"].get("proposed", false) == true)
	check("лава — решения владельца: 3000 / 20 HP/с / 5 с",
		Heat.lava_min_depth() == 3000 and Heat.lava_raw_dps() == 20.0 and Heat.lava_dig_seconds() == 5.0)


# ---------------------------------------------------------------------------
# Бак
# ---------------------------------------------------------------------------

func _test_fuel_tank() -> void:
	_fresh()
	check("свежий бак пуст", FuelTank.fuel("hand_drill") == 0.0 and not FuelTank.has_fuel("hand_drill"))
	check("уровень 0, ёмкость из данных", FuelTank.level("hand_drill") == 0 and FuelTank.capacity("hand_drill") == 4.0)
	check("бак бурмобиля вдвое ёмче при вдвое большем расходе", FuelTank.capacity("drill_rig") == 12.0
		and absf(FuelTank.rate_per_cell("drill_rig") / FuelTank.rate_per_cell("hand_drill") - 10.0 / 3.0) < 0.01)

	var events: Array = []
	var cb := func(id: StringName, data: Dictionary) -> void:
		if id == &"refueled" or id == &"fuel_used":
			events.append([id, data.duplicate()])
	GameState.game_event.connect(cb)

	GameState.inventory["fuel_block"] = 7
	HouseStorage.store_directly("fuel_block", 5)
	var n := FuelTank.refuel("hand_drill", "pack")
	check("заливка из рюкзака: влезло 4 из 7", n == 4 and FuelTank.fuel("hand_drill") == 4.0)
	check("в рюкзаке осталось 3", GameState.get_item_count("fuel_block") == 3)
	check("полный бак больше не берёт", FuelTank.refuel("hand_drill", "pack") == 0 and FuelTank.room_blocks("hand_drill") == 0)
	check("событие refueled ушло на шину с количеством и источником",
		events.size() == 1 and events[0][0] == &"refueled" and float(events[0][1]["amount"]) == 4.0
		and String(events[0][1]["source"]) == "pack")

	FuelTank.set_fuel("hand_drill", 0.0)
	check("со склада можно заливать частями", FuelTank.refuel("hand_drill", "storage", 2) == 2 and FuelTank.in_storage() == 3)
	check("после заливки со склада в баке 2", FuelTank.fuel("hand_drill") == 2.0)

	# Расход: 0.03 блока за клетку — 33 клетки на блок, дробный остаток не теряется.
	events.clear()
	FuelTank.set_fuel("hand_drill", 1.0)
	var rate := FuelTank.rate_per_cell("hand_drill")
	for i in range(33):
		FuelTank.burn_cell("hand_drill")
	check("33 клетки сжигают почти блок (остаток меньше одной клетки)",
		FuelTank.fuel("hand_drill") > 0.0 and FuelTank.fuel("hand_drill") < rate + 0.0001)
	FuelTank.burn_cell("hand_drill")
	check("следующая клетка опустошает бак ровно в ноль", FuelTank.fuel("hand_drill") == 0.0)
	check("пустой бак в минус не уходит", FuelTank.burn_cell("hand_drill") == 0.0 and FuelTank.fuel("hand_drill") == 0.0)
	check("fuel_used эмитится на каждую сожжённую клетку: 34 события", events.size() == 34
		and events[0][0] == &"fuel_used")
	check("в событии fuel_used есть инструмент и остаток",
		String(events[33][1]["tool"]) == "hand_drill" and float(events[33][1]["left"]) == 0.0)
	GameState.game_event.disconnect(cb)

	FuelTank.set_fuel("hand_drill", 2.5)
	check("дробный хвост не льём: влезает целых блоков %d" % FuelTank.room_blocks("hand_drill"), FuelTank.room_blocks("hand_drill") == 1)
	check("клеток в баке считается от расхода", FuelTank.cells_left("hand_drill") == int(floor(2.5 / rate)))
	check("«на исходе» срабатывает ниже порога", FuelTank.is_low("hand_drill") == false)
	FuelTank.set_fuel("hand_drill", 0.5)
	check("«на исходе» срабатывает на 12%", FuelTank.is_low("hand_drill"))
	check("инструмент без бака топлива не жжёт", FuelTank.burn_cell("shovel") == 0.0 and not FuelTank.uses_fuel("iron_pickaxe"))

	# Улучшение бака: только на поверхности, цена — склад, потом рюкзак.
	_fresh()
	GameState.player_depth = 12
	var r := FuelTank.upgrade("hand_drill")
	check("под землёй бак не улучшить", not bool(r["ok"]) and FuelTank.level("hand_drill") == 0)
	GameState.player_depth = 0
	check("без материалов улучшение отказывает", not bool(FuelTank.upgrade("hand_drill")["ok"]))
	GameState.coins = 700
	HouseStorage.store_directly("aluminium", 10)
	GameState.inventory["aluminium"] = 5
	r = FuelTank.upgrade("hand_drill")
	check("с монетами и материалами бак растёт", bool(r["ok"]) and FuelTank.level("hand_drill") == 1)
	check("ёмкость выросла до 6", FuelTank.capacity("hand_drill") == 6.0)
	check("монеты списаны (600)", GameState.coins == 100)
	check("материал сначала со склада, потом из рюкзака", HouseStorage.count("aluminium") == 0 and GameState.get_item_count("aluminium") == 0)
	check("прирост бака пуст — топливо заливают отдельно", FuelTank.fuel("hand_drill") == 0.0)
	for i in range(3):
		GameState.coins = 100000
		HouseStorage.store_directly("copper", 100)
		HouseStorage.store_directly("aluminium", 100)
		HouseStorage.store_directly("nickel", 100)
		HouseStorage.store_directly("silver", 100)
		HouseStorage.store_directly("gold", 100)
		FuelTank.upgrade("hand_drill")
	check("после четырёх улучшений бак максимален (16)", FuelTank.level("hand_drill") == 4 and FuelTank.capacity("hand_drill") == 16.0)
	check("дальше улучшать нечего", FuelTank.next_cost("hand_drill") == null and not bool(FuelTank.upgrade("hand_drill")["ok"]))


func _test_persistence() -> void:
	_fresh()
	FuelTank.set_fuel("drill_rig", 7.5)
	TechState.tank("drill_rig")["level"] = 2
	TechState.set_suit(3)
	# Через JSON числа возвращаются float — всё читается через int()/float().
	var parsed = JSON.parse_string(JSON.stringify(GameState.ext))
	GameState.ext = parsed
	check("уровень бака пережил сейв", FuelTank.level("drill_rig") == 2)
	check("топливо пережило сейв", absf(FuelTank.fuel("drill_rig") - 7.5) < 0.001)
	check("костюм пережил сейв", TechState.suit() == 3 and Heat.suit_tier() == 3)
	GameState.reset_progress()
	check("сброс прогресса опустошает бак и снимает костюм", FuelTank.fuel("drill_rig") == 0.0 and Heat.suit_tier() == 0)


func _test_player_fuel() -> void:
	_fresh()
	var world := WorldGen.new(4242)
	var p = preload("res://scripts/player/player.gd").new()
	p.world = world
	add_child(p)
	GameState.owned_tools = ["shovel", "rusty_pickaxe", "iron_pickaxe", "hand_drill", "drill_rig"]
	GameState.current_tool = "hand_drill"
	var best := Balance.get_best_pickaxe_speed_multiplier()
	check("пустой бак бура: копаем киркой, а не буром", is_equal_approx(p._tool_speed_multiplier(), best))
	FuelTank.set_fuel("hand_drill", 1.0)
	check("с топливом бур вдвое быстрее лучшей кирки", is_equal_approx(p._tool_speed_multiplier(), best * 2.0))

	var cell := _find_diggable(world, 20, 40)
	check("нашлась клетка для копки", cell.x >= 0)
	p.digging = {"x": cell.x, "y": cell.y, "t": 0.0, "total": 1.0, "type": world.get_tile(cell.x, cell.y)}
	p._finish_dig()
	check("прокопанная бурком клетка жжёт 0.03 блока", absf(FuelTank.fuel("hand_drill") - (1.0 - 0.03)) < 0.0001)
	FuelTank.set_fuel("hand_drill", 0.0)
	var cell2 := _find_diggable(world, 20, cell.y + 1)
	p.digging = {"x": cell2.x, "y": cell2.y, "t": 0.0, "total": 1.0, "type": world.get_tile(cell2.x, cell2.y)}
	p._finish_dig()
	check("вхолостую (бак пуст) топливо не уходит в минус", FuelTank.fuel("hand_drill") == 0.0)
	GameState.current_tool = "iron_pickaxe"
	FuelTank.set_fuel("hand_drill", 1.0)
	var cell3 := _find_diggable(world, 20, cell2.y + 1)
	p.digging = {"x": cell3.x, "y": cell3.y, "t": 0.0, "total": 1.0, "type": world.get_tile(cell3.x, cell3.y)}
	p._finish_dig()
	check("киркой бак бура не жжётся", FuelTank.fuel("hand_drill") == 1.0)
	p.queue_free()


func _find_diggable(world: WorldGen, x: int, y0: int) -> Vector2i:
	for y in range(y0, y0 + 60):
		if world.get_tile(x, y) != TileTypes.Type.EMPTY and TileTypes.is_diggable(world.get_tile(x, y)):
			return Vector2i(x, y)
	return Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# Жара, костюм
# ---------------------------------------------------------------------------

func _test_heat() -> void:
	_fresh()
	check("температура у поверхности 16", Heat.temperature(0) == 16.0)
	check("температура на 3000 — 140", Heat.temperature(3000) == 140.0)
	check("между опорными точками линейно (1500 → 63.5)", absf(Heat.temperature(1500) - 63.5) < 0.01)
	check("глубже последней точки не растёт (450)", Heat.temperature(9000) == 450.0)
	check("зоны: прохладно → тепло → лавовые → пекло",
		Heat.zone(0)["id"] == "cool" and Heat.zone(1000)["id"] == "warm" and Heat.zone(3500)["id"] == "furnace"
		and Heat.zone(5000)["id"] == "inferno")
	check("на тысячной метке жара только едва начинается (< ×1.1)", Heat.stamina_multiplier(1000) < 1.1)
	check("на 3000 без костюма бодрость тратится втрое", absf(Heat.stamina_multiplier(3000) - 3.0) < 0.01)
	check("потолок множителя ×6 глубже", Heat.stamina_multiplier(6500) == 6.0)
	check("костюм 3 гасит жару на 3000 полностью", Heat.stamina_multiplier(3000, 3) == 1.0)
	check("костюм 1 на 3000 смягчает жару, но не убирает", Heat.stamina_multiplier(3000, 1) < 3.0 and Heat.stamina_multiplier(3000, 1) > 1.5)
	check("ощущения: комфортно / припекает / печёт", Heat.felt_level(100) == 0 and Heat.felt_level(1500) == 1 and Heat.felt_level(3000) == 2)
	var raw := Heat.lava_cell_cost_hp(0)
	check("клетка лавы без костюма стоит 100 HP — вся полоска на старте", raw == 100.0)
	var costs: Array = []
	for t in range(0, 6):
		costs.append(Heat.lava_cell_cost_hp(t))
	var want := [100.0, 75.0, 50.0, 30.0, 15.0, 0.0]
	var costs_ok := true
	for i in range(6):
		costs_ok = costs_ok and absf(float(costs[i]) - float(want[i])) < 0.001
	check("цена клетки по ступеням: 100/75/50/30/15/0", costs_ok)


func _test_suit() -> void:
	_fresh()
	var tiers := Heat.suit_tiers()
	check("без материалов костюм не сделать", not bool(Heat.craft_suit()["ok"]))
	GameState.max_depth_reached = 500
	_give_cost(tiers[0]["cost"])
	var r := Heat.craft_suit()
	check("пока глубина не открыла рецепт — отказ с глубиной", not bool(r["ok"]) and String(r["message"]).contains("1000"))
	GameState.max_depth_reached = 1000
	GameState.player_depth = 40
	check("под землёй костюм не собрать", not bool(Heat.craft_suit()["ok"]))
	GameState.player_depth = 0
	var coins_before := GameState.coins
	r = Heat.craft_suit()
	check("со всем на месте ступень 1 делается и надевается", bool(r["ok"]) and Heat.suit_tier() == 1)
	check("монеты списаны", coins_before - GameState.coins == int(tiers[0]["cost"]["coins"]))
	check("материалы списаны", HouseStorage.count("titanium") == 0 and GameState.get_item_count("titanium") == 0)
	check("защита от лавы 25%, стойкость 70°", Heat.lava_resist() == 0.25 and Heat.tolerance_c() == 70.0)
	check("следующая ступень — вторая", int(Heat.next_suit()["tier"]) == 2)
	check("вторая без материалов не делается", not bool(Heat.craft_suit()["ok"]))
	TechState.set_suit(5)
	check("после пятой ступени костюм лучший, лава безвредна", Heat.next_suit()["ok"] == false and Heat.lava_dps() == 0.0)


func _give_cost(cost: Dictionary) -> void:
	GameState.coins = int(cost.get("coins", 0))
	for id in cost.get("items", {}).keys():
		HouseStorage.store_directly(String(id), int(cost["items"][id]) - 1)
		GameState.inventory[String(id)] = 1


# ---------------------------------------------------------------------------
# Лава
# ---------------------------------------------------------------------------

func _test_lava_field() -> void:
	LavaField._p = {}
	var seed_v := 31337
	var above := 0
	for y in range(2900, 3000):
		for x in range(0, 32):
			if LavaField.is_lava(seed_v, x, y, 0):
				above += 1
	check("выше 3000 лавы нет вовсе", above == 0)
	var near := _lava_fraction(seed_v, 3000, 3200)
	var deep := _lava_fraction(seed_v, 5800, 6000)
	check("на 3000–3200 лавы 4–20%% клеток (%.0f%%)" % (near * 100.0), near > 0.04 and near < 0.20)
	check("с глубиной лавы больше (%.0f%% → %.0f%%)" % [near * 100.0, deep * 100.0], deep > near)
	check("лава — функция координат: два вызова дают одно", LavaField.is_lava(seed_v, 7, 3100, 0) == LavaField.is_lava(seed_v, 7, 3100, 0))
	var diff := 0
	for y in range(3050, 3090):
		for x in range(0, 32):
			if LavaField.is_lava(seed_v, x, y, 0) != LavaField.is_lava(seed_v, x, y, 12345):
				diff += 1
	check("событие сброса (соль) перетряхивает озёра", diff > 20)
	# Озёра связные, а не россыпь: у лавы чаще лава рядом, чем у случайной клетки.
	var pairs := 0
	var lavas := 0
	for y in range(3100, 3300):
		for x in range(1, 31):
			if LavaField.is_lava(seed_v, x, y, 0):
				lavas += 1
				if LavaField.is_lava(seed_v, x + 1, y, 0):
					pairs += 1
	check("лава лежит озёрами: сосед лавы — лава чаще чем в половине случаев", lavas > 0 and float(pairs) / float(lavas) > 0.5)

	var world := WorldGen.new(seed_v)
	var found := Vector2i(-1, -1)
	for y in range(3000, 3100):
		for x in range(0, 32):
			if LavaField.is_lava(seed_v, x, y, 0):
				found = Vector2i(x, y)
				break
		if found.x >= 0:
			break
	check("мир отдаёт клетку лавы там, где её видит LavaField", found.x >= 0 and world.get_tile(found.x, found.y) == TileTypes.Type.LAVA)
	check("лава копается киркой, лопатой нет", TileTypes.can_dig_with_pickaxe(TileTypes.Type.LAVA) and not TileTypes.can_dig_with_shovel(TileTypes.Type.LAVA))
	check("лава — не руда (ни для статистики, ни для скупки)", not TileTypes.is_ore(TileTypes.Type.LAVA))
	check("остывшая лава оставляет обсидиан", MineralMap.mineral_id_for(TileTypes.Type.LAVA) == "obsidian"
		and MineralMap.tile_type_for("obsidian") == TileTypes.Type.OBSIDIAN)
	var t0 := Time.get_ticks_msec()
	for i in range(3000):
		world.get_tile(i % 32, 3200 + i / 32)
	check("get_tile на глубине с лавой не тормозит (3000 вызовов быстрее 3 с)", Time.get_ticks_msec() - t0 < 3000)


func _lava_fraction(seed_v: int, y0: int, y1: int) -> float:
	var n := 0
	var total := 0
	for y in range(y0, y1):
		for x in range(0, 32):
			total += 1
			if LavaField.is_lava(seed_v, x, y, 0):
				n += 1
	return float(n) / float(total)


func _test_lava_dig() -> void:
	_fresh()
	var seed_v := 777
	var world := WorldGen.new(seed_v)
	var found := Vector2i(-1, -1)
	for y in range(3000, 3200):
		for x in range(0, 32):
			if world.get_tile(x, y) == TileTypes.Type.LAVA:
				found = Vector2i(x, y)
				break
		if found.x >= 0:
			break
	check("в мире 777 нашлась лава", found.x >= 0)
	var p = preload("res://scripts/player/player.gd").new()
	p.world = world
	add_child(p)
	GameState.owned_tools = ["shovel", "rusty_pickaxe", "iron_pickaxe", "obsidian_pickaxe", "hand_drill"]
	var refused: Array = []
	p.dig_refused_by_lava.connect(func(cost: float) -> void: refused.append(cost))

	GameState.current_tool = "iron_pickaxe"
	GameState.hp = 100.0
	p.digging = null
	p._start_dig(found.x, found.y)
	check("со 100 HP без костюма лава — стена: копка не началась", p.digging == null)
	check("игрок получил отказ с ценой клетки 100", refused.size() == 1 and refused[0] == 100.0)

	GameState.hp = 250.0
	for tool_id in ["iron_pickaxe", "obsidian_pickaxe", "hand_drill"]:
		GameState.current_tool = tool_id
		FuelTank.set_fuel("hand_drill", 3.0)
		p.digging = null
		p._start_dig(found.x, found.y)
		check("%s: клетка лавы копается ровно 5 секунд, инструмент скорость не меняет" % tool_id,
			p.digging != null and p.digging.total == 5.0)
	TechState.set_suit(5)
	GameState.hp = 10.0
	p.digging = null
	p._start_dig(found.x, found.y)
	check("с обсидиановым скафандром лава проходима даже на 10 HP", p.digging != null)

	# Урон за время копки.
	GameState.skill_stages["hp"] = 10   # 300 HP: иначе take_damage подрезает hp до максимума в 100
	TechState.set_suit(0)
	GameState.hp = 300.0
	for i in range(5):
		Heat.burn_digger(1.0)
	check("5 секунд лавы без костюма — ровно 100 HP", absf(GameState.hp - 200.0) < 0.01)
	TechState.set_suit(3)
	GameState.hp = 300.0
	for i in range(5):
		Heat.burn_digger(1.0)
	check("с костюмом 3 те же 5 секунд — 30 HP", absf(GameState.hp - 270.0) < 0.01)
	TechState.set_suit(5)
	GameState.hp = 300.0
	for i in range(5):
		Heat.burn_digger(1.0)
	check("с костюмом 5 лава не жжёт", GameState.hp == 300.0)
	GameState.debug_invincible = true
	check("отладочное бессмертие тоже открывает лаву", Heat.can_dig_lava())
	GameState.debug_invincible = false

	# Копка до конца: обсидиан в рюкзак, клетка пустая.
	GameState.hp = 300.0
	GameState.current_tool = "obsidian_pickaxe"
	p.digging = {"x": found.x, "y": found.y, "t": 0.0, "total": 5.0, "type": TileTypes.Type.LAVA}
	p._finish_dig()
	check("прокопанная лава оставляет обсидиан", GameState.get_item_count("obsidian") == 1)
	check("клетка лавы стала проходимой", world.get_tile(found.x, found.y) == TileTypes.Type.EMPTY)
	p.queue_free()


# ---------------------------------------------------------------------------
# Скважина
# ---------------------------------------------------------------------------

func _built_well(level: int, depth: int) -> void:
	_fresh()
	GameState.well_level = level
	GameState.max_depth_reached = depth


func _test_well_formula() -> void:
	_built_well(1, 100)
	check("скважина построена и копит", IdleWell.is_built())
	check("глубина копки — min(рекорд, ступень)", IdleWell.effective_depth() == 100)
	GameState.max_depth_reached = 5000
	check("глубже ступени скважина не копает", IdleWell.effective_depth() == IdleWell.depth_cap(1) and IdleWell.depth_cap(1) == 200)
	var cpc := IdleWell.coins_per_cell(200)
	check("выручка клетки на 200 положительна (%.1f)" % cpc, cpc > 1.0)
	check("доход = клеток в час × выручка клетки", absf(IdleWell.income_per_hour() - IdleWell.cells_per_hour() * cpc) < 0.01)
	var prev := 0.0
	var growing := true
	for l in range(1, IdleWell.max_level() + 1):
		var rate := IdleWell.income_per_hour(l)
		growing = growing and rate > prev
		prev = rate
	check("доход растёт с каждой ступенью (на глубине её предела)", growing)
	check("непостроенная скважина не даёт дохода", (func() -> bool:
		GameState.well_level = 0
		return IdleWell.income_per_hour() == 0.0 and IdleWell.income_coins_for_seconds(3600.0) == 0).call())

	# Состав добычи.
	for depth in [150, 600, 1500, 3500, 6500]:
		_built_well(IdleWell.max_level(), depth)
		var items := IdleWell._basket_for_value(100000)
		var ok := not items.is_empty() and items.size() <= IdleWell.MAX_KINDS
		var bad := false
		var sum := 0
		for id in items.keys():
			var price := Balance.get_mineral_price(String(id))
			sum += price * int(items[id])
			bad = bad or price <= 0 or String(Balance.get_mineral(String(id)).get("category", "")) == "crafted"
		check("глубина %d: корзина из 1–4 видов, без выплавленного и без экзотики без цены" % depth, ok and not bad)
		check("глубина %d: корзина стоит примерно заказанное (±15%%: %d из 100000)" % [depth, sum], absf(float(sum) - 100000.0) < 15000.0)
	_built_well(1, 150)
	check("золото в корзине всегда", IdleWell._basket_for_value(5000).has("gold"))


func _test_well_time() -> void:
	var t0 := 1_900_000_000
	_built_well(2, 600)
	GameState.well_last_collect_unix = t0
	var rate := IdleWell.income_per_hour()
	var rep := IdleWell.collect(t0 + 3600)
	check("час простоя: отчёт есть, время 3600 с, не кап", not rep.is_empty() and rep["seconds"] == 3600.0 and not bool(rep["capped"]))
	check("ценность отчёта = час дохода", absf(float(rep["coins_value"]) - rate) <= 1.0)
	check("добыча легла на склад", HouseStorage.total_items() > 0)
	check("якорь забора сдвинулся на момент забора", GameState.well_last_collect_unix == t0 + 3600)
	check("донатная валюта нетронута", GameState.dollars == 0)
	check("рюкзак не тронут", GameState.inventory.is_empty())
	var again := IdleWell.collect(t0 + 3600 + 120)
	check("через две минуты отчёта нет (меньше well.report_min_seconds)", again.is_empty())
	check("а время при этом не потеряно: якорь на месте", GameState.well_last_collect_unix == t0 + 3600)
	check("через четверть часа отчёт есть", not IdleWell.collect(t0 + 3600 + 900).is_empty())

	# Офлайн-кап.
	_built_well(2, 600)
	GameState.well_last_collect_unix = t0
	rep = IdleWell.collect(t0 + 100 * 3600)
	check("сто часов простоя оплачены по капу", not rep.is_empty() and rep["seconds"] == IdleWell.cap_hours(2) * 3600.0 and bool(rep["capped"]))
	check("в отчёте видно, сколько реально прошло", rep["raw_seconds"] == 100.0 * 3600.0)
	check("кап = часы ступени 2 (8 ч)", IdleWell.cap_hours(2) == 8.0)
	check("ценность капа = кап часов дохода", absf(float(rep["coins_value"]) - IdleWell.income_per_hour() * 8.0) <= 1.0)

	# Частые заборы против редких: за сутки (кап 8 ч) редкий забор берёт треть.
	_built_well(2, 600)
	GameState.well_last_collect_unix = t0
	var hourly := 0
	for h in range(1, 25):
		var r := IdleWell.collect(t0 + h * 3600)
		hourly += int(r.get("coins_value", 0))
	_built_well(2, 600)
	GameState.well_last_collect_unix = t0
	var once := int(IdleWell.collect(t0 + 24 * 3600).get("coins_value", 0))
	check("каждый час за сутки — 24 часа дохода (нет накрутки частыми заборами)",
		absf(float(hourly) / (rate * 24.0) - 1.0) < 0.02)
	check("раз в сутки при капе 8 ч — треть (кап режет редкие заходы)", absf(float(once) / float(hourly) - 1.0 / 3.0) < 0.03)

	# Перемотка часов назад.
	_built_well(2, 600)
	GameState.well_last_collect_unix = t0
	IdleWell.note_time(t0 + 3600)
	check("откат на 100 с — поправка времени, не перемотка", not IdleWell.clock_rolled_back(t0 + 3500))
	check("откат на два часа — перемотка", IdleWell.clock_rolled_back(t0 + 3600 - 7200))
	check("при перемотке скважина ничего не копит", IdleWell.pending_seconds(t0 + 3600 - 7200) == 0.0)
	check("и не платит", IdleWell.collect(t0 + 3600 - 7200).is_empty())
	check("якорь забора при перемотке не двигается", GameState.well_last_collect_unix == t0)
	var back := IdleWell.collect(t0 + 2 * 3600)
	check("когда время вернулось вперёд — платит за честный интервал (2 ч от якоря)", not back.is_empty() and back["seconds"] == 7200.0)
	# Давний откат прощается: телефон сам исправил часы.
	_built_well(2, 600)
	GameState.well_last_collect_unix = t0
	TechState.well_meta()["seen_unix"] = t0 + 49 * 3600
	check("откат на двое суток прощается: отчёта нет, но скважина не глохнет навсегда",
		IdleWell.collect(t0).is_empty() and int(TechState.well_meta()["seen_unix"]) == t0)
	check("после прощения время идёт заново", IdleWell.pending_seconds(t0 + 3600) == 3600.0)

	# Перемотка вперёд на месяц между сессиями не платит больше капа.
	_built_well(3, 800)
	GameState.well_last_collect_unix = t0
	rep = IdleWell.collect(t0 + 30 * 86400)
	check("месяц вперёд даёт ровно кап ступени, не больше", rep["seconds"] == IdleWell.cap_hours(3) * 3600.0)

	# Первый запуск и непостроенная.
	_built_well(1, 300)
	GameState.well_last_collect_unix = 0
	check("первый забор ничего не платит, только ставит отметку", IdleWell.collect(t0).is_empty() and GameState.well_last_collect_unix == t0)
	GameState.well_level = 0
	GameState.well_last_collect_unix = t0
	check("непостроенная скважина не платит", IdleWell.collect(t0 + 99999).is_empty())

	# Реальные часы: pending_seconds без явной метки читает системное время.
	_built_well(1, 300)
	GameState.well_last_collect_unix = int(Time.get_unix_time_from_system()) - 6 * 3600
	check("по реальным часам шесть часов назад ≈ 21600 с", absf(IdleWell.pending_seconds() - 21600.0) < 5.0)
	check("полоска накопленного растёт от капа", absf(IdleWell.fill_fraction() - 6.0 / 8.0) < 0.01)


func _test_well_upgrade() -> void:
	var t0 := 1_900_000_000
	_built_well(1, 300)
	check("следующая ступень стоит 2500 монет", IdleWell.next_cost() != null and int(IdleWell.next_cost()["coins"]) == 2500)
	GameState.coins = 100
	check("без монет улучшение отказывает", not bool(IdleWell.upgrade()["ok"]) and GameState.well_level == 1)
	GameState.coins = 3000
	GameState.player_depth = 20
	check("под землёй скважину не улучшить", not bool(IdleWell.upgrade()["ok"]))
	GameState.player_depth = 0
	GameState.well_last_collect_unix = int(Time.get_unix_time_from_system()) - 2 * 3600
	var rate_old := IdleWell.income_per_hour()
	var r := IdleWell.upgrade()
	check("с монетами ступень растёт", bool(r["ok"]) and GameState.well_level == 2 and GameState.coins == 500)
	var rep: Dictionary = r["report"]
	check("накопленное выплатилось по СТАРОЙ ставке до улучшения (2 ч)",
		not rep.is_empty() and absf(float(rep["coins_value"]) - rate_old * 2.0) <= 2.0)
	check("у новой ступени доход выше, кап и глубина — по таблице",
		IdleWell.income_per_hour() > rate_old and IdleWell.depth_cap() == 400)
	GameState.well_level = IdleWell.max_level()
	check("на последней ступени дальше нечего", IdleWell.next_cost() == null and not bool(IdleWell.upgrade()["ok"]))
	GameState.well_level = 2
	GameState.coins = 6000
	check("третья ступень просит ещё и железо", not bool(IdleWell.upgrade()["ok"]))
	HouseStorage.store_directly("iron_ore", 120)
	check("с железом на складе — делается", bool(IdleWell.upgrade()["ok"]) and HouseStorage.count("iron_ore") == 0)


func _test_double_and_ads() -> void:
	var t0 := 1_900_000_000
	_built_well(2, 600)
	GameState.well_last_collect_unix = t0
	var rep := IdleWell.collect(t0 + 4 * 3600)
	var before := HouseStorage.contents().duplicate()
	var added := IdleWell.double_report(rep)
	var doubled := true
	for id in rep["items"].keys():
		doubled = doubled and HouseStorage.count(String(id)) == int(before[id]) * 2
	check("«×2» кладёт на склад ещё столько же", doubled and added == rep["items"])
	check("«×2» не трогает доллары и монеты", GameState.dollars == 0 and GameState.coins == 0)

	GameState.ad_daily_counts.clear()
	check("лимит роликов в сутки — 3", TechAds.daily_limit() == 3 and TechAds.left_today() == 3)
	var results: Array = []
	for i in range(4):
		TechAds.request(func(ok: bool) -> void: results.append(ok))
	check("три ролика дали награду, четвёртый — отказ", results == [true, true, true, false])
	check("осталось ноль", TechAds.left_today() == 0)
	check("рекламная сеть не подключена: AdManager честно говорит «нет готового»", not AdManager.is_ad_ready(TechAds.PLACEMENT))
	check("точка показа заведена в monetization.json (AdManager её знает)", not AdManager.placement(TechAds.PLACEMENT).is_empty())
	GameState.ad_daily_counts.clear()


# ---------------------------------------------------------------------------
# Экраны и окно отчёта
# ---------------------------------------------------------------------------

func _test_screens() -> void:
	var t0 := int(Time.get_unix_time_from_system())
	_built_well(3, 800)
	GameState.owned_tools = ["shovel", "rusty_pickaxe", "hand_drill", "drill_rig"]
	GameState.well_last_collect_unix = t0 - 6 * 3600
	var rep := IdleWell.collect()
	check("для окна есть что показать", not rep.is_empty())

	var host := Node.new()
	add_child(host)
	var win := WellReport.attach(host)
	win.show_report(rep)
	await get_tree().process_frame
	check("окно отчёта показано", win.visible and WellReport.is_open())
	check("плиток столько же, сколько видов добычи", win._tiles.size() == rep["items"].size())
	check("модальность видна HUD-у", TechSystem.is_modal_open())
	var before := HouseStorage.total_items()
	GameState.ad_daily_counts.clear()
	win._on_double()
	check("кнопка «×2» удвоила добычу на складе", HouseStorage.total_items() == before + _sum_items(rep["items"]))
	check("повторное «×2» в том же окне не срабатывает", (func() -> bool:
		var n := HouseStorage.total_items()
		win._on_double()
		return HouseStorage.total_items() == n).call())
	win.close()
	check("окно закрылось", not win.visible and not WellReport.is_open())
	win.show_report({})
	check("пустой отчёт не открывает окно", not win.visible)

	# Экран техники: все три вкладки собираются, станционный режим открывает склад.
	var screen := TechScreen.attach(host, null)
	TechScreen.open(TechScreen.TAB_TANK, true)
	await get_tree().process_frame
	check("экран техники открыт на баке", TechScreen.is_open() and screen._content.get_child_count() > 0)
	GameState.inventory["fuel_block"] = 3
	HouseStorage.store_directly("fuel_block", 9)
	screen.refresh()
	screen._pour("storage", -1, screen, screen)
	await get_tree().process_frame
	check("заливка со склада на станции работает", FuelTank.fuel("hand_drill") > 0.0 or FuelTank.fuel(screen._tool) > 0.0)
	TechScreen.open(TechScreen.TAB_SUIT)
	await get_tree().process_frame
	check("вкладка костюма собирается", screen._content.get_child_count() > 0)
	TechScreen.open(TechScreen.TAB_WELL)
	await get_tree().process_frame
	check("вкладка скважины собирается", screen._content.get_child_count() > 0)
	GameState.well_level = 0
	screen.refresh()
	check("непостроенная скважина тоже рисуется (замок)", screen._content.get_child_count() > 0)
	TechScreen.close_screen()
	check("экран закрылся", not TechScreen.is_open())
	host.free()   # сразу, не queue_free: статический _instance окна не должен пережить хозяина


func _sum_items(items: Dictionary) -> int:
	var n := 0
	for id in items.keys():
		n += int(items[id])
	return n


# ---------------------------------------------------------------------------
# Система в живой сцене
# ---------------------------------------------------------------------------

func _test_system() -> void:
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = main_scene.instantiate()
	add_child(main)
	for _i in range(5):
		await get_tree().process_frame
	var sys := TechSystem.instance()
	check("TechSystem подключён в main", sys != null and sys.player == main.player and sys.hud == main.hud)
	if sys == null:
		return
	check("есть группа well_report (HUD найдёт окно)", get_tree().get_first_node_in_group("well_report") != null)

	# Жара: бодрость уходит быстрее по формуле Heat.
	GameState.reset_progress()
	GameState.skill_stages["hp"] = 10
	GameState.is_alive = true
	main.player.frozen = false
	GameState.player_depth = 3000
	GameState.stamina = 100.0
	var base := Balance.get_bar_depletion_rate_per_second("stamina", GameState.is_digging)
	sys._heat_tick(1.0)
	check("на 3000 без костюма жара тратит ещё ×2 бодрости за секунду",
		absf((100.0 - GameState.stamina) - base * 2.0 * 100.0) < 0.01)
	TechState.set_suit(3)
	GameState.stamina = 100.0
	sys._heat_tick(1.0)
	check("в костюме 3 на 3000 жара бодрость не трогает", GameState.stamina == 100.0)
	GameState.house_is_indoors = true
	TechState.set_suit(0)
	GameState.stamina = 100.0
	sys._heat_tick(1.0)
	check("дома жары нет", GameState.stamina == 100.0)
	GameState.house_is_indoors = false

	# Лава: урон за кадр, пока копается клетка лавы.
	GameState.hp = 300.0
	main.player.digging = {"x": 5, "y": 3100, "t": 0.0, "total": 5.0, "type": TileTypes.Type.LAVA}
	sys._lava_tick(0.5)
	check("лава жжёт 10 HP за полсекунды (20 HP/с)", absf(GameState.hp - 290.0) < 0.01)
	main.player.digging = null

	# Станция: кнопка появляется рядом и только на поверхности после сцены заправки.
	GameState.era = "now"   # интро деда могло успеть выставить эпоху
	main.player.frozen = false
	StoryState.flags()["fuel_station_built"] = true
	GameState.player_depth = 0
	main.player.x = float(WorldGen.FUEL_STATION_X) + 1.0
	main.player.y = 0.5
	sys._hotspot_tick()
	check("у станции над героем кнопка «Заправка»", sys._hot_btn.visible and sys._hot_target == "station")
	main.player.x = 18.5
	sys._hotspot_tick()
	check("далеко от станции кнопки нет", not sys._hot_btn.visible)
	GameState.well_level = 1
	main.player.x = float(WorldGen.WELL_X) + 1.0
	sys._hotspot_tick()
	check("у скважины кнопка скважины", sys._hot_btn.visible and sys._hot_target == "well")
	GameState.player_depth = 30
	sys._hotspot_tick()
	check("под землёй кнопок нет", not sys._hot_btn.visible)
	GameState.player_depth = 0

	# Меню «•••»: пункт «Техника» зарегистрирован и виден после сотой метки.
	GameState.max_depth_reached = 0
	GameState.well_level = 0
	var visible_before := _menu_has("tech")
	GameState.max_depth_reached = 150
	check("пункт меню «Техника» появляется с глубиной 100", not visible_before and _menu_has("tech"))

	# Возвращение в приложение: окно отчёта.
	GameState.well_level = 2
	GameState.max_depth_reached = 600
	GameState.well_last_collect_unix = int(Time.get_unix_time_from_system()) - 3 * 3600
	var rep := sys.check_return()
	check("вернулись через 3 часа: забрали и показали окно", not rep.is_empty() and WellReport.is_open())
	WellReport.instance().close()
	check("сразу после забора повторного окна нет", sys.check_return().is_empty())
	main.queue_free()


func _menu_has(id: String) -> bool:
	for e in MenuRegistry.entries():
		if String(e["id"]) == id:
			return true
	return false

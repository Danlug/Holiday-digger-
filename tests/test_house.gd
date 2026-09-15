extends Node
## test_house — проверка системы дома (scripts/house/): сон, еда, переходы.
##
## Запускается СЦЕНОЙ, а не через --script: дом обращается к автозагрузкам
## GameState/Balance, а в режиме --script их нет (см. docs/BUILD.md):
##   godot --headless --path . res://tests/test_house.tscn
##
## Проверяется ровно то, ради чего система написана: бодрость и голод должны
## восстанавливаться, а вход в дом и обратно — не терять состояние игрока.

var failures := 0
var total := 0

var world: WorldGen
var fog: FogOfWar
var player
var house: HouseSystem


func _ready() -> void:
	print("=== test_house ===")
	world = WorldGen.new(4242)
	fog = FogOfWar.new()
	GameState.world_ref = world
	GameState.fog_ref = fog
	GameState.reset_progress()

	player = load("res://scripts/player/player.gd").new()
	player.world = world
	add_child(player)

	house = HouseSystem.new()
	add_child(house)
	house.player = player
	house.world = world

	_test_sleep_restores_stamina()
	_test_sleep_minimum_and_cap()
	_test_sleep_refuses_when_hungry()
	_test_forced_sleep_ignores_hunger()
	_test_food_delivery_and_eating()
	_test_paid_order_needs_coins()
	_test_energy_bar_effect()
	_test_enter_and_exit_keeps_state()
	_test_hatch_transition()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func check_near(label: String, actual: float, expected: float, tolerance: float = 0.01) -> void:
	check("%s (получено %.2f, ожидалось %.2f)" % [label, actual, expected],
		absf(actual - expected) <= tolerance)


# ---------------------------------------------------------------------------
# Сон (ГДД п.7)
# ---------------------------------------------------------------------------

func _test_sleep_restores_stamina() -> void:
	GameState.set_stamina(40.0)
	GameState.set_hunger(100.0)
	var clock_before := GameState.game_clock_hours
	var result := HouseSleep.sleep_now()

	check("сон состоялся", bool(result["ok"]))
	# 60% недостающей бодрости при 12.5% за игровой час — это 4.8 игровых часа.
	check_near("проспал 4.8 игровых часа", float(result["hours"]), 4.8, 0.001)
	check_near("бодрость восстановлена до 100%", GameState.stamina, 100.0, 0.001)
	check_near("игровые часы сдвинулись на длину сна",
		GameState.game_clock_hours - clock_before, 4.8, 0.05)
	# Голод за сон: половина обычной скорости простоя, то есть 6.25% за
	# игровой час (см. house.sleep_hunger_factor в balance.json).
	check_near("сон съел 30% сытости", GameState.hunger, 70.0, 0.2)


func _test_sleep_minimum_and_cap() -> void:
	GameState.set_stamina(95.0)
	GameState.set_hunger(100.0)
	var too_fresh := HouseSleep.sleep_now()
	check("с почти полной бодростью кровать не пускает", not bool(too_fresh["ok"]))
	check_near("бодрость не тронута", GameState.stamina, 95.0, 0.001)
	check_near("сытость не тронута", GameState.hunger, 100.0, 0.001)

	# 15% недостачи — это 1.2 игрового часа, но меньше двух часов спать
	# нельзя (ГДД п.7), поэтому ложимся ровно на минимум.
	GameState.set_stamina(85.0)
	var result := HouseSleep.sleep_now()
	check_near("минимальный сон — 2 игровых часа", float(result["hours"]), 2.0, 0.001)
	check_near("бодрость не переливается за 100%", GameState.stamina, 100.0, 0.001)

	GameState.set_stamina(0.0)
	GameState.set_hunger(100.0)
	var full := HouseSleep.sleep_now()
	check_near("полная ночь — 8 игровых часов", float(full["hours"]), 8.0, 0.001)
	check_near("полная ночь стоит 50% сытости", GameState.hunger, 50.0, 0.2)


func _test_sleep_refuses_when_hungry() -> void:
	GameState.set_stamina(0.0)
	GameState.set_hunger(10.0)
	var result := HouseSleep.sleep_now()
	check("голодным лечь нельзя", not bool(result["ok"]))
	check("отказ объяснён текстом", not String(result["reason"]).is_empty())
	check_near("бодрость не изменилась после отказа", GameState.stamina, 0.0, 0.001)
	check_near("сытость не изменилась после отказа", GameState.hunger, 10.0, 0.001)


func _test_forced_sleep_ignores_hunger() -> void:
	GameState.set_stamina(0.0)
	GameState.set_hunger(5.0)
	var result := HouseSleep.sleep_now(true)
	check("обучающий сон состоялся вопреки голоду", bool(result["ok"]))
	check_near("обучающий сон поднял бодрость", GameState.stamina, 100.0, 0.001)
	check_near("обучающий сон не списал сытость", GameState.hunger, 5.0, 0.001)


# ---------------------------------------------------------------------------
# Еда (ГДД п.7)
# ---------------------------------------------------------------------------

func _test_food_delivery_and_eating() -> void:
	GameState.house_food_at_door.clear()
	GameState.house_free_orders_used_today = 0
	GameState.inventory.clear()
	GameState.set_hunger(20.0)

	var free_before := HouseFood.free_orders_left()
	check("бесплатные заказы вообще есть", free_before > 0)
	check("заказ супа разрешён", bool(HouseFood.can_order("food_soup")["ok"]))
	check("оплата заказа прошла", HouseFood.pay_for_order("food_soup"))
	check("бесплатных заказов стало меньше", HouseFood.free_orders_left() == free_before - 1)

	check("до доставки у двери пусто", HouseFood.food_at_door_count() == 0)
	HouseFood.deliver("food_soup")
	check("после доставки у двери одна порция", HouseFood.food_at_door_count() == 1)
	check("в рюкзаке еды ещё нет", GameState.get_item_count("food_soup") == 0)

	check("забрал доставку", HouseFood.take_from_door() == 1)
	check("порция в рюкзаке", GameState.get_item_count("food_soup") == 1)
	check("у двери снова пусто", HouseFood.food_at_door_count() == 0)

	var eaten := HouseFood.eat("food_soup")
	check("съел", bool(eaten["ok"]))
	check_near("суп восстановил 50% сытости", GameState.hunger, 70.0, 0.2)
	check("порция израсходована", GameState.get_item_count("food_soup") == 0)


func _test_paid_order_needs_coins() -> void:
	# Бесплатные заказы кончились: дальше еда стоит монет.
	GameState.house_free_orders_used_today = HouseConfig.free_orders_per_day()
	GameState.coins = 0
	check("без монет заказать нельзя", not bool(HouseFood.can_order("food_soup")["ok"]))

	var price := HouseConfig.food_price_coins("food_soup")
	GameState.add_coins(price)
	check("с монетами заказать можно", bool(HouseFood.can_order("food_soup")["ok"]))
	check("оплата прошла", HouseFood.pay_for_order("food_soup"))
	check("монеты списаны", GameState.coins == 0)


func _test_energy_bar_effect() -> void:
	# Батончик из ГДД п.7: 100% бодрости и 50% сытости. Им же система учит
	# есть при втором истощении в шахте (п.9).
	GameState.set_stamina(0.0)
	GameState.set_hunger(0.0)
	GameState.inventory.clear()
	GameState.add_item("energy_bar", 1)
	var eaten := HouseFood.eat("energy_bar")
	check("батончик съеден", bool(eaten["ok"]))
	check_near("батончик дал 100% бодрости", GameState.stamina, 100.0, 0.001)
	check_near("батончик дал 50% сытости", GameState.hunger, 50.0, 0.001)


# ---------------------------------------------------------------------------
# Переходы дом ↔ огород ↔ шахта (ГДД п.3, 9)
# ---------------------------------------------------------------------------

func _test_enter_and_exit_keeps_state() -> void:
	GameState.inventory.clear()
	GameState.add_item("iron_ore", 3)
	GameState.set_stamina(55.0)
	GameState.set_hunger(66.0)
	GameState.hp = 77.0
	var hp_before := GameState.hp
	var stamina_before := GameState.stamina
	var hunger_before := GameState.hunger
	var iron_before := GameState.get_item_count("iron_ore")

	player.x = 20.5
	player.y = 0.5
	house.enter_house("hall")
	check("герой в доме", GameState.house_is_indoors)
	check("физика героя заморожена", player.frozen)
	check("комната запомнена", GameState.house_room == "hall")

	house.exit_to_door()
	var door := HouseConfig.door_cell()
	check("герой снова снаружи", not GameState.house_is_indoors)
	check("физика разморожена", not player.frozen)
	check_near("герой стоит у двери по x", player.x, door.x + 0.5, 0.001)
	check_near("герой стоит на поверхности", player.y, 0.5, 0.001)
	check("скорость обнулена", player.vx == 0.0 and player.vy == 0.0)

	check("HP не изменилось", is_equal_approx(GameState.hp, hp_before))
	check("бодрость не изменилась", is_equal_approx(GameState.stamina, stamina_before))
	check("сытость не изменилась", is_equal_approx(GameState.hunger, hunger_before))
	check("инвентарь цел", GameState.get_item_count("iron_ore") == iron_before)


func _test_hatch_transition() -> void:
	var hatch := HouseConfig.hatch_cell()
	GameState.house_hatch_built = false
	house.enter_house("basement")
	check("без люка спуститься нельзя", not house.exit_through_hatch())
	check("герой остался в доме", GameState.house_is_indoors)

	# Роберт закончил работу: люк построен, огород закрыт (ГДД п.9).
	# Вызываем ровно тем именем, которым дом зовёт сюжетная сцена Роберта
	# (data/story.json: {"do":"hook","target":"house","method":"build_hatch"}).
	check("хук сюжета build_hatch на месте", house.has_method("build_hatch"))
	house.build_hatch()
	check("после Роберта люк построен", GameState.house_hatch_built)
	check("после Роберта огород закрыт", GameState.house_garden_closed)

	check("спуск через люк сработал", house.exit_through_hatch())
	check("герой снаружи", not GameState.house_is_indoors)
	check_near("герой стоит в клетке люка по x", player.x, hatch.x + 0.5, 0.001)
	check_near("герой стоит в клетке люка по y", player.y, hatch.y + 0.5, 0.001)
	check("клетка люка пробита", world.get_tile(hatch.x, hatch.y) == TileTypes.Type.EMPTY)
	check("люк лежит прямо под фундаментом", hatch.y == 6)

	# Землетрясение стирает диффы: клетка люка обязана пробиваться заново,
	# иначе спуск замуровывает героя в породе.
	world.apply_global_event(12345)
	house.enter_house("basement")
	check("спуск после землетрясения сработал", house.exit_through_hatch())
	check("клетка люка снова пуста", world.get_tile(hatch.x, hatch.y) == TileTypes.Type.EMPTY)

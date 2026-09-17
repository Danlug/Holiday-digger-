extends Node
## test_house — проверка системы дома (scripts/house/): сон, еда, переходы,
## и — с редизайна владельца от 2026-09-16 — дом как пространство: герой
## ходит по комнате, кнопки-хотспоты всплывают над ним в радиусе точки (и
## гаснут вне его), несколько точек в радиусе дают несколько кнопок разом,
## переходы между комнатами ставят героя у нужной двери, а «Спать» у кровати
## идёт через короткую анимацию, а не мгновенно.
##
## Запускается СЦЕНОЙ, а не через --script: дом обращается к автозагрузкам
## GameState/Balance, а в режиме --script их нет (см. docs/BUILD.md):
##   godot --headless --path . res://tests/test_house.tscn

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
	_test_tunnel_transition()
	_test_storage_access_rules()
	_test_storage_survives_death_and_save()

	_test_room_hotspots_appear_and_fade()
	_test_room_two_buttons_on_overlap()
	_test_room_transitions_use_enter_points()
	_test_pickaxe_hotspot()
	_test_front_door_take_delivery_condition()
	_test_sleep_button_uses_animation_sequence()
	_test_outdoor_enter_hotspot()
	_test_house_button_context_gone()

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


## Список action'ов активных хотспотов вида (см. house_view.gd:active_hotspots).
func _actions() -> Array:
	var out: Array = []
	for h in house._view.active_hotspots():
		out.append(String(h["action"]))
	return out


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
# Еда (ГДД п.7) — чистая логика HouseFood/HouseConfig, не зависит от того,
# что «Заказать» теперь открывает магазин, а не карточку прихожей.
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
# Склад в мастерской (ГДД п.14)
# ---------------------------------------------------------------------------

func _test_storage_access_rules() -> void:
	GameState.house_storage.clear()
	GameState.inventory.clear()
	GameState.add_item("iron_ore", 10)

	# Со дна шахты склад только виден.
	GameState.house_is_indoors = false
	GameState.house_room = "hall"
	check("из шахты склада не достать", not HouseStorage.can_access())
	check("из шахты на склад не положить", HouseStorage.put("iron_ore", 5) == 0)
	check("отказ объяснён", not HouseStorage.access_reason().is_empty())
	check("руда осталась в рюкзаке", GameState.get_item_count("iron_ore") == 10)

	# Дома, но не в мастерской — тоже нельзя: склад стоит у верстака.
	GameState.house_is_indoors = true
	check("в прихожей склада нет", not HouseStorage.can_access())
	check("из прихожей на склад не положить", HouseStorage.put("iron_ore", 5) == 0)

	# Подошли к складу.
	GameState.house_room = HouseStorage.ROOM
	check("в мастерской склад доступен", HouseStorage.can_access())
	check("положили 10 руды", HouseStorage.put("iron_ore", 10) == 10)
	check("рюкзак пуст", GameState.get_item_count("iron_ore") == 0)
	check("склад помнит 10 руды", HouseStorage.count("iron_ore") == 10)
	check("вес склада посчитан",
		is_equal_approx(HouseStorage.total_weight(), Balance.get_mineral_weight("iron_ore") * 10.0))

	check("забрали 4 обратно", HouseStorage.take("iron_ore", 4) == 4)
	check("в рюкзаке 4", GameState.get_item_count("iron_ore") == 4)
	check("на складе осталось 6", HouseStorage.count("iron_ore") == 6)

	# Верстак берёт со склада напрямую, мимо рюкзака (ГДД п.14).
	check("верстак списал со склада 6", HouseStorage.consume("iron_ore", 6) == 6)
	check("склад опустел", HouseStorage.count("iron_ore") == 0)

	# Склад не ограничен грузоподъёмностью, а рюкзак ограничен: обратно
	# всё сразу не уносится — в этом и разница между складом и рюкзаком.
	GameState.inventory.clear()
	HouseStorage.store_directly("lead", 100)
	var max_by_weight := int(GameState.get_max_carry_kg() / Balance.get_mineral_weight("lead"))
	var taken := HouseStorage.take("lead", 100)
	check("рюкзак взял только то, что тянет", taken == max_by_weight and taken < 100)
	check("остальное осталось на складе", HouseStorage.count("lead") == 100 - taken)


func _test_storage_survives_death_and_save() -> void:
	GameState.house_storage.clear()
	GameState.inventory.clear()
	GameState.house_is_indoors = true
	GameState.house_room = HouseStorage.ROOM
	HouseStorage.store_directly("gold", 7)
	GameState.add_item("silver", 3)

	# Смерть забирает рюкзак (ГДД п.7), но не дом: склад — это то, что уже
	# донесено, и терять его дважды было бы наказанием за саму игру.
	GameState.die()
	check("смерть очистила рюкзак", GameState.get_item_count("silver") == 0)
	check("склад смерть не тронула", HouseStorage.count("gold") == 7)
	GameState.respawn()

	# Перезапуск игры: склад обязан сохраниться.
	SaveSystem.save_game()
	GameState.house_storage.clear()
	SaveSystem.load_game()
	check("склад пережил перезапуск", HouseStorage.count("gold") == 7)
	SaveSystem.delete_save()


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
	check("вид открыл именно салон", house._view.room_id() == "hall")

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


func _test_tunnel_transition() -> void:
	# Люк отменён владельцем: после огорода Роберт пробивает вниз бетонный
	# тоннель — колодец по клетке WorldGen.TUNNEL_X глубиной TUNNEL_DEPTH,
	# стенки TUNNEL_WALL_LEFT и TUNNEL_WALL_RIGHT железобетонные, остальной
	# огород засыпан и больше не копается. Геометрию держит мир, дом только
	# зовёт его и ставит героя в устье.
	GameState.house_hatch_built = false
	GameState.house_garden_closed = false
	house.enter_house("workshop")
	check("без тоннеля спуститься нельзя", not house.exit_through_tunnel())
	check("герой остался в доме", GameState.house_is_indoors)
	check("до Роберта устье тоннеля не пробито",
		world.get_tile(WorldGen.TUNNEL_X, 1) != TileTypes.Type.EMPTY)
	check("до Роберта огород ещё копается", not world.is_garden_locked())

	# Роберт закончил работу (ГДД п.9). Вызываем ровно тем именем, которым дом
	# зовёт сюжетная сцена Роберта (data/story.json: {"do":"hook",
	# "target":"house","method":"build_tunnel"}). Копаем клетку огорода,
	# чтобы было что засыпать.
	world.dig_cell(25, 2)
	check("клетка огорода выкопана до прихода Роберта", world.is_dug(25, 2))
	check("хук сюжета build_tunnel на месте", house.has_method("build_tunnel"))
	# Старое имя хука обязано остаться: в сейве может лежать очередь сцен,
	# записанная до отмены люка.
	check("старый хук build_hatch остался обёрткой", house.has_method("build_hatch"))
	house.build_tunnel()
	check("после Роберта тоннель построен", GameState.house_hatch_built)
	check("после Роберта огород закрыт", GameState.house_garden_closed)
	check("после Роберта огород засыпан землёй", not world.is_dug(25, 2))
	check("после Роберта огород больше не вскопать", world.is_garden_locked())

	var mouth := world.tunnel_mouth()
	check("устье тоннеля — верхняя клетка колодца",
		mouth == Vector2i(WorldGen.TUNNEL_X, 1))
	check("дом спрашивает устье у мира", house.tunnel_mouth() == mouth)
	# Старое имя клетки люка отдаёт то же устье: люка больше нет, а вернуть
	# несуществующую клетку — значит замуровать спускающегося.
	check("HouseConfig.hatch_cell() отдаёт устье тоннеля",
		HouseConfig.tunnel_mouth_cell() == HouseConfig.hatch_cell())

	var shaft_empty := true
	for y in range(1, WorldGen.TUNNEL_DEPTH + 1):
		if world.get_tile(WorldGen.TUNNEL_X, y) != TileTypes.Type.EMPTY:
			shaft_empty = false
	check("колодец пробит на всю глубину", shaft_empty)

	check("спуск по тоннелю сработал", house.exit_through_tunnel())
	check("герой снаружи", not GameState.house_is_indoors)
	# Из дома герой попадает РОВНО в устье (решение владельца): вниз ведёт
	# только колодец, шага в сторону из него нет.
	check_near("герой стоит в устье по x", player.x, mouth.x + 0.5, 0.001)
	check_near("герой стоит в устье по y", player.y, mouth.y + 0.5, 0.001)

	# Устье НИКУДА НЕ ТЯНЕТ (решение владельца): из шахты герой просто
	# вылетает наверх, а в дом заходит сам, кнопкой у окна веранды. Прежний
	# автоматический перенос читался как непонятный телепорт.
	for step in range(30):
		house._process(0.016)
	check("на устье в дом не затягивает", not GameState.house_is_indoors)
	player.y = mouth.y + WorldGen.TUNNEL_DEPTH - 0.5
	for step in range(10):
		house._process(0.016)
	check("в глубине колодца тоже не затягивает", not GameState.house_is_indoors)
	player.y = mouth.y + 0.5
	for step in range(10):
		house._process(0.016)
	check("подъём к устью снизу героя не переносит", not GameState.house_is_indoors)
	check("автоматического переноса из шахты в дом больше нет",
		not house.has_method("_auto_enter_tunnel_if_touched"))

	# Кнопки «В шахту» в мастерской тоже нет: из дома выходят на улицу и
	# спускаются в тоннель ногами.
	var stairs: Dictionary = HouseRoomsConfig.points("workshop").get("stairs", {})
	var stairs_actions: Array = []
	for b in stairs.get("buttons", []):
		stairs_actions.append(String(b.get("action", "")))
	check("у лестницы в мастерской нет кнопки в шахту",
		not stairs_actions.has("exit_tunnel"))
	check("подъём в салон у лестницы остался", stairs_actions.has("goto:hall"))

	# Землетрясение стирает диффы: колодец обязан пробиваться заново, иначе
	# спуск замуровывает героя в породе.
	world.apply_global_event(12345)
	check("спуск после землетрясения сработал", house.exit_through_tunnel())
	check("устье снова пусто",
		world.get_tile(mouth.x, mouth.y) == TileTypes.Type.EMPTY)
	check("огород после землетрясения всё так же закрыт", world.is_garden_locked())


# ---------------------------------------------------------------------------
# Дом как пространство (решение владельца, 2026-09-16): хотспоты появляются
# и гаснут по радиусу, несколько точек в радиусе дают несколько кнопок.
# ---------------------------------------------------------------------------

## Доля x точки — из той же разметки, по которой живёт игра (data/rooms.json,
## переопределённый art/env/room_<id>.json художника). Цифры в тесте не
## зашиваем: арт пересобирают отдельно от логики, и тест с числами падал бы
## на каждой пересборке, ничего не проверяя.
func _px(room: String, point: String) -> float:
	return float(HouseRoomsConfig.points(room)[point]["x"])


func _test_room_hotspots_appear_and_fade() -> void:
	if GameState.house_is_indoors:
		house.exit_to_door()
	house.enter_house("hall")
	check("вошёл в салон", house._view.room_id() == "hall")

	house._view.set_hero_x_fraction(_px("hall", "door_workshop"))
	check("у правой двери — кнопка «Мастерская»", _actions().has("goto:workshop"))

	# Входная дверь — деревянная у левого края салона, от правой двери далеко.
	house._view.set_hero_x_fraction(_px("hall", "front_door"))
	var actions := _actions()
	check("у входной двери — «Заказать»", actions.has("open_shop"))
	check("кнопка мастерской вдали погасла", not actions.has("goto:workshop"))

	# Далеко от всех точек — хотспотов нет вовсе. Между входной дверью и
	# дверями в глубине есть пустая стена: середина этого промежутка.
	var gap := (_px("hall", "front_door") + _px("hall", "door_bedroom")) / 2.0
	house._view.set_hero_x_fraction(gap)
	check("вдали от всех точек хотспотов нет", _actions().is_empty())


func _test_room_two_buttons_on_overlap() -> void:
	if GameState.house_is_indoors:
		house.exit_to_door()
	house.enter_house("workshop")
	# Верстак и сундук стоят рядом, радиусы пересекаются — посередине между
	# ними общий механизм радиусов даёт обе кнопки, ровно то место, про
	# которое владелец просил две кнопки на выбор.
	var wb := _px("workshop", "workbench")
	var ch := _px("workshop", "chest")
	house._view.set_hero_x_fraction((wb + ch) / 2.0)
	var actions := _actions()
	check("на стыке верстака и сундука — «Верстак»", actions.has("open_equipment"))
	check("на стыке верстака и сундука — «Склад»", actions.has("storage"))
	check("ровно две кнопки, не одна и не три", actions.size() == 2)

	# У самого верстака, с дальней от сундука стороны — только одна из двух.
	house._view.set_hero_x_fraction(wb + (wb - ch) * 0.6)
	actions = _actions()
	check("у самого верстака — только «Верстак»", actions.has("open_equipment") and not actions.has("storage"))


func _test_room_transitions_use_enter_points() -> void:
	if GameState.house_is_indoors:
		house.exit_to_door()
	house.enter_house("hall")
	house._view.set_hero_x_fraction(_px("hall", "door_workshop"))
	house._view.trigger_point_button("door_workshop")
	check("нажатие у двери перевело в мастерскую", house._view.room_id() == "workshop")
	check("GameState.house_room обновился (бухгалтерию ведёт дом)",
		GameState.house_room == "workshop")
	check_near("вошёл у лестницы (enter_at из data/rooms.json)",
		house._view.hero_x_fraction(), _px("workshop", "stairs"), 0.001)

	house._view.trigger_point_button("stairs", 0)  # index 0 — «Подняться в дом»
	check("лестница ведёт обратно в салон", house._view.room_id() == "hall")
	check_near("вошёл у той же двери, из которой уходил",
		house._view.hero_x_fraction(), _px("hall", "door_workshop"), 0.001)


func _test_pickaxe_hotspot() -> void:
	GameState.owned_tools = ["shovel"]
	GameState.current_tool = "shovel"
	if GameState.house_is_indoors:
		house.exit_to_door()
	house.enter_house("workshop")

	house._view.set_hero_x_fraction(_px("workshop", "mops_wall"))
	check("у стены с удочками — «Взять кирку»", _actions().has("take_pickaxe"))

	house._view.trigger_point_button("mops_wall")
	# Тест не заводит сюжетную систему (house._story остаётся null) — значит
	# сработал запасной прямой путь выдачи, а не очередь сюжетной сцены.
	check("инструмент переключён на кирку", GameState.current_tool == "rusty_pickaxe")
	check("сцена мастерской отмечена просмотренной (гейт хотспота)",
		StoryState.is_seen("workshop"))

	house._view.refresh()
	check("кнопка «Взять кирку» пропала — кирка уже есть", not _actions().has("take_pickaxe"))

	# Запасной путь выдачи пишет StoryState на диск (user://story.json) —
	# тест обязан не оставлять его «просмотренным» для других тестов и для
	# настоящей игры, иначе сцена "workshop" молча не сыграет никому другому.
	StoryState.clear_all()


func _test_front_door_take_delivery_condition() -> void:
	GameState.house_food_at_door.clear()
	GameState.inventory.clear()
	if GameState.house_is_indoors:
		house.exit_to_door()
	house.enter_house("hall")
	house._view.set_hero_x_fraction(_px("hall", "front_door"))
	var actions := _actions()
	check("без доставки — только «Заказать»", actions.has("open_shop"))
	check("без доставки кнопки «Забрать» нет", not actions.has("take_delivery"))

	HouseFood.deliver("food_soup")
	house._view.refresh()
	actions = _actions()
	check("доставка у двери — появилась «Забрать»", actions.has("take_delivery"))

	house._view.trigger_point_button("front_door", 1)  # index 1 — «Забрать»
	check("нажатие забрало доставку в рюкзак", GameState.get_item_count("food_soup") == 1)
	house._view.refresh()
	check("после «Забрать» кнопка снова пропала", not _actions().has("take_delivery"))


func _test_sleep_button_uses_animation_sequence() -> void:
	if GameState.house_is_indoors:
		house.exit_to_door()
	GameState.set_stamina(20.0)
	GameState.set_hunger(100.0)
	house.enter_house("bedroom")
	house._view.set_hero_x_fraction(_px("bedroom", "bed"))
	check("у кровати — кнопка «Спать»", _actions().has("sleep"))

	house._view.trigger_point_button("bed")
	check("сон начался (house_system держит комнату на паузе)", house._view.is_sleeping())
	check_near("эффект сна ЕЩЁ не применился — идёт анимация", GameState.stamina, 20.0, 0.001)
	check("хотспоты спрятаны, пока герой спит", house._view.active_hotspots().is_empty())
	check_near("анимация — ровно house.sleep_animation_seconds из balance.json",
		HouseConfig.sleep_animation_seconds(), 10.0, 0.001)

	# house_system сам отсчитывает реальные секунды таймером; тест не ждёт их
	# взаправду — зовёт тот же метод, которым таймер завершает сон.
	house._finish_sleep_sequence()
	check("анимация закончилась", not house._view.is_sleeping())
	check("эффект сна применился по её концу", GameState.stamina > 20.0)


func _test_outdoor_enter_hotspot() -> void:
	if GameState.house_is_indoors:
		house.exit_to_door()
	var door := HouseConfig.door_cell()

	player.x = door.x + 0.5
	player.y = 0.5
	house._update_outdoor_hotspot()
	check("«Зайти» видна у окна веранды", house._outdoor_button.visible)
	check("подпись — «Зайти» (не «Дом»)", house._outdoor_button.text == "Зайти")

	player.x = door.x + 20.0
	house._update_outdoor_hotspot()
	check("кнопка гаснет вдали от двери", not house._outdoor_button.visible)

	player.x = door.x + 0.5
	house._update_outdoor_hotspot()
	check("кнопка снова видна у двери", house._outdoor_button.visible)

	house._outdoor_button.pressed.emit()
	check("нажатие «Зайти» физически завело героя в салон",
		GameState.house_is_indoors and GameState.house_room == "hall")


## «Дом» как контекстная кнопка внизу экрана отменена (решение владельца):
## house._button (группа "house_button" от HUD) больше ничего не показывает
## и не подписывает — тест держит и его, чтобы регрессия не вернулась молча.
func _test_house_button_context_gone() -> void:
	var btn := Button.new()
	btn.add_to_group("house_button")
	add_child(btn)
	house._button = btn
	house._button_action = ""

	if GameState.house_is_indoors:
		house.exit_to_door()
	var door := HouseConfig.door_cell()
	player.x = float(door.x) + 0.5
	player.y = 0.5
	house._update_hud_button()
	check("«Дом» больше не показывается даже у двери", not btn.visible)
	check("действие у кнопки не назначается", house._button_action.is_empty())
	house.on_hud_button()  # не должен падать без назначенного действия

	btn.queue_free()
	house._button = null

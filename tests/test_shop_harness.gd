extends Node
## test_shop_harness — проверка экономики: продажа сырья, верстак, лавка,
## обмен долларов и владение инструментами (scripts/shop/).
##
## Запускается сценой, а не через --script: ShopService работает поверх
## автолоадов GameState и Balance, а те поднимаются только при обычной
## загрузке движка (тот же приём, что и в test_player_harness).
##
##   godot --headless --path . res://tests/test_shop_harness.tscn

var failures := 0
var total := 0


func _ready() -> void:
	print("=== test_shop_harness ===")
	GameState.reset_progress()

	_test_sell_stack()
	_test_sell_only_selected()
	_test_not_bought()
	_test_craft_bronze()
	_test_craft_fuel_block()
	_test_craft_fuel_block_coal()
	_test_idle_well_payout()
	_test_craft_without_materials()
	_test_hand_drill_from_storage()
	_test_tool_requires_ownership()
	_test_buy_spends_coins()
	_test_exchange_dollars()
	_test_ad_double_sale()
	_test_workshop_gives_rusty_pickaxe()
	_test_cannot_sell_from_mine()

	# --- прогресс за деньги (переписан владельцем) ---
	_test_pickaxe_prices_and_multipliers()
	_test_gear_prices_and_multipliers()
	_test_buy_pickaxe_spends_exact_coins()
	_test_buy_tool_cannot_dismount_rig_underground()
	_test_buy_gear_spends_exact_coins()
	_test_pickaxes_and_gear_are_not_crafted()
	_test_tech_is_still_crafted()
	_test_equipment_switches_dig_and_fly()
	_test_shop_ui_builds_every_screen()
	_test_save_migration_v1()
	_test_rig_state_persists_save_load()

	# --- апгрейд бура (задача «Апгрейд бура») ---
	_test_drill_upgrade_hidden_without_rig()
	_test_drill_upgrade_sequential_gate()
	_test_drill_upgrade_speed_multiplies_live()
	_test_drill_upgrade_spends_exact_coins()
	_test_drill_upgrade_debug_free_shop()
	_test_drill_upgrade_persists_save_load()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


## Чистый стол: пустой рюкзак, ноль монет, никаких вложений и инструментов.
func _fresh() -> void:
	GameState.inventory.clear()
	GameState.coins = 0
	GameState.dollars = 0
	GameState.next_sale_doubled = false
	GameState.house_storage.clear()
	GameState.owned_tools = ["shovel"]
	GameState.current_tool = "shovel"
	GameState.owned_gear = []
	GameState.current_gear = ""
	GameState.max_depth_reached = 0
	GameState.drill_rig_tier = 0
	GameState.debug_free_shop = false
	# Скупка и верстак работают только дома (ГДД раздел 5: мастерская в
	# подвале). Большинство проверок — про саму арифметику, поэтому ставим
	# героя домой; отдельная проверка ниже следит за тем, что из шахты
	# продать нельзя.
	GameState.house_is_indoors = true
	# Склад и верстак стоят в мастерской (ГДД п.14): класть материалы можно
	# только подойдя к ним, поэтому герой сразу в нужной комнате.
	GameState.house_room = "workshop"


# ---------------------------------------------------------------------------
# Продажа
# ---------------------------------------------------------------------------

func _test_sell_stack() -> void:
	_fresh()
	GameState.inventory["iron_ore"] = 12
	var price := Balance.get_mineral_price("iron_ore")
	var weight_before := GameState.get_total_weight()
	var result := ShopService.sell({"iron_ore": 12})

	check("продажа стопки прошла", bool(result["ok"]))
	check("выручка = цена × количество (%d × 12 = %d)" % [price, price * 12],
		GameState.coins == price * 12 and int(result["coins"]) == price * 12)
	check("проданная стопка ушла из рюкзака", GameState.get_item_count("iron_ore") == 0)
	check("рюкзак полегчал ровно на вес стопки",
		is_equal_approx(weight_before - GameState.get_total_weight(), Balance.get_mineral_weight("iron_ore") * 12.0))
	check("выручка учтена в счётчике заработанного продажей",
		GameState.lifetime_coins_from_sales == price * 12)


func _test_sell_only_selected() -> void:
	_fresh()
	GameState.inventory["iron_ore"] = 5
	GameState.inventory["lead"] = 2
	var result := ShopService.sell({"lead": 2})
	check("продано только выбранное — свинец ушёл",
		bool(result["ok"]) and GameState.get_item_count("lead") == 0)
	check("невыбранное железо осталось в рюкзаке", GameState.get_item_count("iron_ore") == 5)
	check("выручка только за свинец", GameState.coins == Balance.get_mineral_price("lead") * 2)

	# Продать больше, чем лежит в рюкзаке, нельзя — берётся то, что есть.
	var over := ShopService.sell({"iron_ore": 99})
	check("продажа сверх наличия ограничена рюкзаком", int(over["count"]) == 5)


func _test_not_bought() -> void:
	_fresh()
	GameState.inventory["bronze"] = 3
	GameState.inventory["geocrystal"] = 1
	var result := ShopService.sell({"bronze": 3, "geocrystal": 1})
	check("бронзу мастерская не скупает (иначе плавка печатает монеты)",
		not bool(result["ok"]) and GameState.get_item_count("bronze") == 3)
	check("геокристалл не продаётся вовсе (ГДД раздел 4)",
		GameState.get_item_count("geocrystal") == 1 and GameState.coins == 0)


# ---------------------------------------------------------------------------
# Верстак
# ---------------------------------------------------------------------------

func _test_craft_bronze() -> void:
	_fresh()
	var recipe := ShopCatalog.recipe("bronze")
	var need := int(recipe["inputs"]["scrap"])
	check("бронза плавится из металлолома 1:1 (ГДД раздел 5)", need == 1)

	GameState.inventory["scrap"] = 4
	check("крафт прошёл", bool(ShopService.craft("bronze")["ok"]))
	check("металлолом списан ровно по рецепту", GameState.get_item_count("scrap") == 4 - need)
	check("бронза появилась в рюкзаке", GameState.get_item_count("bronze") == 1)


func _test_craft_fuel_block() -> void:
	_fresh()
	var recipe := ShopCatalog.recipe("fuel_block")
	check("топливный блок делается из 4 торфа (ГДД раздел 5)", int(recipe["inputs"]["peat"]) == 4)

	GameState.inventory["peat"] = 3
	check("с тремя торфами блок не делается", not bool(ShopService.craft("fuel_block")["ok"]))
	check("неудачный крафт не тронул торф", GameState.get_item_count("peat") == 3)

	GameState.inventory["peat"] = 4
	check("с четырьмя торфами блок делается", bool(ShopService.craft("fuel_block")["ok"]))
	check("торф списан весь", GameState.get_item_count("peat") == 0)
	check("блок лежит в рюкзаке", GameState.get_item_count("fuel_block") == 1)


## Бурмобиль требует брикеты угля (задача «Бурмобиль — транспорт», решение
## владельца: «если он экипирован бурмобилем, он должен иметь на себе
## топливо (брикеты каменного угля)»). Уголь — второй путь к тому же
## предмету fuel_block, рядом с торфом, а не замена ему.
func _test_craft_fuel_block_coal() -> void:
	_fresh()
	var recipe := ShopCatalog.recipe("fuel_block_coal")
	check("рецепт угольного блока существует", not recipe.is_empty())
	var need := int(recipe["inputs"]["coal"])
	check("выход тот же предмет, что и у торфяного рецепта", String(recipe["output"]["id"]) == "fuel_block")

	GameState.max_depth_reached = 1000  # рецепт открывается той же глубиной, что и уголь
	GameState.inventory["coal"] = need - 1
	check("без достаточного угля блок не делается", not bool(ShopService.craft("fuel_block_coal")["ok"]))

	GameState.inventory["coal"] = need
	check("с углём по рецепту блок делается", bool(ShopService.craft("fuel_block_coal")["ok"]))
	check("уголь списан весь", GameState.get_item_count("coal") == 0)
	check("блок лежит в рюкзаке", GameState.get_item_count("fuel_block") == 1)


## Скважина платит рудой и золотом и никогда — донатной валютой
## (решение владельца).
func _test_idle_well_payout() -> void:
	GameState.dollars = 0
	GameState.house_storage.clear()
	GameState.max_depth_reached = 400
	GameState.well_level = 0
	GameState.well_last_collect_unix = int(Time.get_unix_time_from_system()) - 3600 * 5
	check("непостроенная скважина не платит вовсе", IdleWell.collect().is_empty())

	GameState.well_level = 1
	GameState.well_last_collect_unix = int(Time.get_unix_time_from_system()) - 3600 * 5
	var report := IdleWell.collect()
	check("скважина что-то накопала", not report.is_empty())
	if report.is_empty():
		return
	check("донатной валюты не дала", GameState.dollars == 0)
	check("добыча легла на склад, а не в рюкзак", not GameState.house_storage.is_empty())
	var has_ore := false
	var has_crafted := false
	for id in report["items"].keys():
		if String(Balance.get_mineral(String(id)).get("category", "")) == "crafted":
			has_crafted = true
		else:
			has_ore = true
	check("в отчёте есть добыча", has_ore)
	check("выплавленного (бронзы) скважина не производит", not has_crafted)

	# Офлайн-кап: сутки простоя не дают больше, чем кап в часах.
	GameState.well_last_collect_unix = int(Time.get_unix_time_from_system()) - 3600 * 24
	var day: int = IdleWell.income_coins_for_seconds(IdleWell.pending_seconds())
	GameState.well_last_collect_unix = int(Time.get_unix_time_from_system()) - 3600 * 8
	var capped: int = IdleWell.income_coins_for_seconds(IdleWell.pending_seconds())
	check("офлайн-кап работает: сутки не дороже капа", day <= capped)

	GameState.well_level = 0
	GameState.house_storage.clear()


func _test_craft_without_materials() -> void:
	_fresh()
	GameState.max_depth_reached = 100
	GameState.coins = 10000
	var result := ShopService.craft("hand_drill")
	check("без материалов техника не крафтится", not bool(result["ok"]))
	check("неудачный крафт не тронул монеты", GameState.coins == 10000)
	check("инструмент не появился", not GameState.owned_tools.has("hand_drill"))


## Ручной бур: 500 железа + 100 бронзы + 50 серебра + 2000 монет. Материалы
## копятся на складе в мастерской за несколько ходок (ГДД п.14, «Склад»):
## одним рюкзаком в 60 кг их не принести. Это осталось единственной ветвью,
## где крафт из материалов вообще есть, — техника.
func _test_hand_drill_from_storage() -> void:
	_fresh()
	GameState.max_depth_reached = 100
	var recipe := ShopCatalog.recipe("hand_drill")
	check("рецепт ручного бура существует", not recipe.is_empty())
	if recipe.is_empty():
		return
	check("рецепт бура: 500 железа", int(recipe["inputs"]["iron_ore"]) == 500)
	check("рецепт бура: 2000 монет", int(recipe["coins"]) == 2000)

	var total_kg := 0.0
	for id in recipe["inputs"].keys():
		total_kg += Balance.get_mineral_weight(String(id)) * int(recipe["inputs"][id])
	check("материалы бура тяжелее одного рюкзака — склад нужен по делу",
		total_kg > GameState.get_max_carry_kg())

	# Первая ходка: принесли часть железа и сложили на склад.
	GameState.inventory["iron_ore"] = 400
	ShopService.invest("hand_drill")
	check("сложенное ушло из рюкзака", GameState.get_item_count("iron_ore") == 0)
	check("сложенное лежит на складе", HouseStorage.count("iron_ore") == 400)
	check("неполного рецепта не хватает на крафт", not ShopService.can_craft("hand_drill"))

	# Вторая ходка: остальное. Лишнее железо сверх рецепта остаётся в рюкзаке —
	# на склад уходит ровно столько, сколько нужно.
	GameState.inventory["iron_ore"] = 150
	GameState.inventory["bronze"] = 100
	GameState.inventory["silver"] = 50
	ShopService.invest("hand_drill")
	check("на склад ушло ровно недостающее", HouseStorage.count("iron_ore") == 500)
	check("излишек остался у игрока", GameState.get_item_count("iron_ore") == 50)

	GameState.coins = 1999
	check("без монет бур не собирается", not ShopService.can_craft("hand_drill"))
	GameState.coins = 2050
	check("набранного склада хватает на крафт", bool(ShopService.craft("hand_drill")["ok"]))
	check("монеты списаны ровно по рецепту", GameState.coins == 50)
	check("бур в собственности", GameState.owned_tools.has("hand_drill"))
	check("бур взят в руки", GameState.current_tool == "hand_drill")
	check("склад опустел ровно на рецепт", HouseStorage.count("iron_ore") == 0
		and HouseStorage.count("silver") == 0 and HouseStorage.count("bronze") == 0)
	check("излишек из рюкзака крафт не тронул", GameState.get_item_count("iron_ore") == 50)


# ---------------------------------------------------------------------------
# Инструменты: покупка и крафт вместо выдачи по глубине
# ---------------------------------------------------------------------------

func _test_tool_requires_ownership() -> void:
	_fresh()
	GameState.max_depth_reached = 100
	GameState.set_current_tool("hand_drill")
	check("платный инструмент нельзя надеть, не собрав его", GameState.current_tool == "shovel")

	check("бесплатная дедова кирка владением не гейтится", GameState.owns_tool("rusty_pickaxe"))
	GameState.set_current_tool("rusty_pickaxe")
	check("дедова кирка надевается", GameState.current_tool == "rusty_pickaxe")

	check("ручной бур открывается только с глубины 100 (ГДД раздел 6)",
		ShopCatalog.unlock_depth("hand_drill") == 100)
	GameState.max_depth_reached = 0
	check("выше глубины 100 рецепт бура закрыт", not ShopService.is_recipe_unlocked("hand_drill"))

	GameState.grant_tool("hand_drill")
	GameState.set_current_tool("hand_drill")
	check("собранный бур надевается", GameState.current_tool == "hand_drill")


# ---------------------------------------------------------------------------
# Лавка, обмен, реклама
# ---------------------------------------------------------------------------

func _test_buy_spends_coins() -> void:
	_fresh()
	var goods := ShopCatalog.goods_coins()
	check("в лавке есть хотя бы один товар за монеты", not goods.is_empty())
	if goods.is_empty():
		return
	var good: Dictionary = goods[0]
	var price := ShopCatalog.good_price(good, "coins")

	GameState.coins = price - 1
	check("без монет покупка не проходит", not bool(ShopService.buy(String(good["id"]), "coins")["ok"]))
	check("неудачная покупка монет не тронула", GameState.coins == price - 1)

	GameState.coins = price + 30
	GameState.set_stamina(10.0)
	check("покупка прошла", bool(ShopService.buy(String(good["id"]), "coins")["ok"]))
	check("монеты списаны ровно по цене", GameState.coins == 30)
	check("эффект применён — бодрость выросла", GameState.stamina > 10.0)


func _test_exchange_dollars() -> void:
	_fresh()
	GameState.dollars = 2
	var rate := ShopCatalog.coins_per_dollar()
	var result := ShopService.exchange_dollars_to_coins(1)
	check("обмен прошёл", bool(result["ok"]))
	check("доллар списан", GameState.dollars == 1)
	check("монеты начислены по курсу", GameState.coins == rate)

	GameState.dollars = 0
	check("без долларов менять нечего", not bool(ShopService.exchange_dollars_to_coins(1)["ok"]))


func _test_ad_double_sale() -> void:
	_fresh()
	GameState.ad_daily_counts.clear()
	var claimed := ShopService.claim_ad("double_income_on_sale")
	check("ролик на удвоение засчитан", bool(claimed["ok"]) and GameState.next_sale_doubled)

	GameState.inventory["gold"] = 2
	var price := Balance.get_mineral_price("gold")
	ShopService.sell({"gold": 2})
	check("удвоение сработало на одну сделку", GameState.coins == price * 2 * 2)
	check("удвоение потрачено", not GameState.next_sale_doubled)

	# Лимит роликов на день — из balance.json (ГДД раздел 15).
	var limit := Balance.get_ad_daily_limit("small_coins")
	GameState.ad_daily_counts.clear()
	var granted := 0
	for i in range(limit + 2):
		if bool(ShopService.claim_ad("small_coins")["ok"]):
			granted += 1
	check("дневной лимит роликов соблюдён (%d)" % limit, granted == limit)


func _test_workshop_gives_rusty_pickaxe() -> void:
	_fresh()
	GameState.workshop_visited = false
	GameState.owned_tools = ["shovel"]
	GameState.house_is_indoors = false
	check("из шахты мастерскую не 'посетить' — кирку так не получить",
		not ShopService.visit_workshop())
	GameState.house_is_indoors = true
	check("первый визит в мастерскую выдаёт дедову кирку", ShopService.visit_workshop())
	check("кирка записана в собственность", GameState.owned_tools.has("rusty_pickaxe"))
	check("кирка сразу в руках", GameState.current_tool == "rusty_pickaxe")
	check("второй визит кирку не дублирует", not ShopService.visit_workshop())


# ---------------------------------------------------------------------------
# Место: скупка и верстак — только дома (ГДД раздел 5)
# ---------------------------------------------------------------------------

func _test_cannot_sell_from_mine() -> void:
	_fresh()
	GameState.house_is_indoors = false
	GameState.inventory["gold"] = 2
	var result := ShopService.sell({"gold": 2})
	check("из шахты продать нельзя — лут надо донести наверх",
		not bool(result["ok"]) and GameState.coins == 0)
	check("золото осталось в рюкзаке", GameState.get_item_count("gold") == 2)
	check("класть на склад из шахты тоже нельзя",
		not bool(ShopService.invest("iron_pickaxe")["ok"]))

	# Единственный способ продать со дна — рекламная награда "скинуть лут
	# дистанционно" (ГДД раздел 15, лимит на день).
	GameState.ad_daily_counts.clear()
	var price := Balance.get_mineral_price("gold")
	check("дистанционная сдача за ролик работает", bool(ShopService.remote_dump_loot()["ok"]))
	check("монеты пришли по цене золота", GameState.coins == price * 2)
	check("рюкзак опустел", GameState.get_item_count("gold") == 0)

	var limit := Balance.get_ad_daily_limit("remote_dump_loot_for_sale")
	GameState.ad_daily_counts.clear()
	var used := 0
	for i in range(limit + 2):
		GameState.inventory["gold"] = 1
		if bool(ShopService.remote_dump_loot()["ok"]):
			used += 1
	check("лимит дистанционных сдач на день соблюдён (%d)" % limit, used == limit)
	GameState.house_is_indoors = true


# ---------------------------------------------------------------------------
# Прогресс за деньги (владелец переписал развитие игры)
#
# «Больше не нужно ресурсы собирать для крафта, есть 6 видов кирок, они стоят
# разных денег»: цены и множители заданы словами владельца и проверяются
# здесь ровно теми числами, которые он назвал. Разойдутся данные со словами —
# падать должно тут, а не в игре.
# ---------------------------------------------------------------------------

## Ржавая ×1.0 (находится в мастерской), железная 500/×1.3, титановая
## 1500/×1.6, платиновая 10000/×2.5, алмазная 20000/×3.5, обсидиановая
## 50000/×5.
func _test_pickaxe_prices_and_multipliers() -> void:
	var want := [
		["rusty_pickaxe", 0, 1.0],
		["iron_pickaxe", 500, 1.3],
		["titanium_pickaxe", 1500, 1.6],
		["platinum_pickaxe", 10000, 2.5],
		["diamond_pickaxe", 20000, 3.5],
		["obsidian_pickaxe", 50000, 5.0],
	]
	var line := Balance.get_tools_in_line("pickaxe")
	check("кирок ровно шесть (владелец: «есть 6 видов кирок»)", line.size() == 6)
	for i in range(want.size()):
		var id := String(want[i][0])
		var price := int(want[i][1])
		var mult := float(want[i][2])
		check("кирка %s стоит на своей ступени (%d-я)" % [id, i], i < line.size() and line[i] == id)
		check("%s: цена %d монет" % [id, price], Balance.get_tool_cost_coins(id) == price)
		check("%s: копка ×%s" % [id, mult],
			is_equal_approx(Balance.get_tool_speed_multiplier(id), mult))
		# Деньги — единственные ворота прогресса (решение агента, см. отчёт):
		# по глубине кирки не ограничены вовсе.
		check("%s: по глубине не ограничена" % id, Balance.get_tool_max_depth(id) < 0)
	# У лопаты ограничение осталось: она про землю, а не про породу.
	check("у лопаты ограничение по глубине осталось", Balance.get_tool_max_depth("shovel") == 4)


## Ранец 100, улучшенный 1000/×2, джетпак 5000/×3, топовый 20000/×10.
## Множитель — на скорость полёта, то есть на потолок подъёма в клетках/сек.
func _test_gear_prices_and_multipliers() -> void:
	var base := Balance.get_gear_base_speed()
	var want := [
		["backpack", 100, 1.0],
		["backpack_plus", 1000, 2.0],
		["jetpack", 5000, 3.0],
		["jetpack_top", 20000, 10.0],
	]
	var line := Balance.get_gear_ids()
	check("ранцев ровно четыре", line.size() == 4)
	for i in range(want.size()):
		var id := String(want[i][0])
		var price := int(want[i][1])
		var mult := float(want[i][2])
		check("ранец %s стоит на своей ступени (%d-я)" % [id, i], i < line.size() and line[i] == id)
		check("%s: цена %d монет" % [id, price], Balance.get_gear_cost_coins(id) == price)
		check("%s: полёт ×%s" % [id, mult],
			is_equal_approx(Balance.get_gear_fly_multiplier(id), mult))
		check("%s: потолок подъёма %.1f кл/с" % [id, base * mult],
			is_equal_approx(Balance.get_gear_max_speed(id), base * mult))
	check("верхние две ступени — реактивные", Balance.get_gear_kind("jetpack") == "jet"
		and Balance.get_gear_kind("jetpack_top") == "jet")
	check("нижние две — пропеллеры", Balance.get_gear_kind("backpack") == "prop"
		and Balance.get_gear_kind("backpack_plus") == "prop")


## Покупка снимает РОВНО цену — ни монетой больше.
func _test_buy_pickaxe_spends_exact_coins() -> void:
	_fresh()
	var price := Balance.get_tool_cost_coins("titanium_pickaxe")
	GameState.coins = price - 1
	check("без монет титановая кирка не покупается",
		not bool(ShopService.buy_tool("titanium_pickaxe")["ok"]))
	check("неудачная покупка монет не тронула", GameState.coins == price - 1)
	check("кирка не появилась", not GameState.owned_tools.has("titanium_pickaxe"))

	GameState.coins = price + 77
	check("покупка прошла", bool(ShopService.buy_tool("titanium_pickaxe")["ok"]))
	check("списано ровно %d монет" % price, GameState.coins == 77)
	check("кирка в собственности", GameState.owned_tools.has("titanium_pickaxe"))
	check("купленная кирка сразу в руках", GameState.current_tool == "titanium_pickaxe")

	check("дважды одну кирку не продают",
		not bool(ShopService.buy_tool("titanium_pickaxe")["ok"]))
	check("повторная покупка монет не тронула", GameState.coins == 77)

	# Ржавая кирка не продаётся вовсе: она находится в мастерской.
	_fresh()
	GameState.coins = 10000
	check("ржавая кирка в магазине не продаётся",
		not bool(ShopService.buy_tool("rusty_pickaxe")["ok"]))


## Бурмобиль — транспорт (решение владельца): его нельзя бросить под землёй,
## купив по дороге другую кирку. Магазин у входной двери работает откуда
## угодно (can_shop_here() == true всегда), и это единственный путь, которым
## смена инструмента могла бы проскочить мимо GameState.set_current_tool.
func _test_buy_tool_cannot_dismount_rig_underground() -> void:
	_fresh()
	GameState.owned_tools = ["shovel", "drill_rig"]
	GameState.current_tool = "drill_rig"
	GameState.house_is_indoors = false
	GameState.player_depth = 50  # под землёй
	GameState.coins = 100000

	var result := ShopService.buy_tool("titanium_pickaxe")
	check("под землёй в бурмобиле новую кирку не купить", not bool(result["ok"]))
	check("монеты не списаны", GameState.coins == 100000)
	check("бурмобиль остался в руках", GameState.current_tool == "drill_rig")
	check("кирка не куплена", not GameState.owned_tools.has("titanium_pickaxe"))

	# На поверхности — можно.
	GameState.player_depth = 0
	check("на поверхности новую кирку купить можно", bool(ShopService.buy_tool("titanium_pickaxe")["ok"]))
	check("бурмобиль снят, кирка в руках", GameState.current_tool == "titanium_pickaxe")

	# Дома под тем же кодом глубины — тоже можно (house_is_indoors снимает запрет).
	_fresh()
	GameState.owned_tools = ["shovel", "drill_rig"]
	GameState.current_tool = "drill_rig"
	GameState.house_is_indoors = true
	GameState.player_depth = 50
	GameState.coins = 100000
	check("дома под землёй бурмобиль тоже можно сменить",
		bool(ShopService.buy_tool("titanium_pickaxe")["ok"]))


func _test_buy_gear_spends_exact_coins() -> void:
	_fresh()
	var price := Balance.get_gear_cost_coins("backpack")
	GameState.coins = price - 1
	check("без монет ранец не покупается", not bool(ShopService.buy_gear("backpack")["ok"]))
	check("неудачная покупка монет не тронула", GameState.coins == price - 1)

	GameState.coins = price + 5
	check("ранец куплен", bool(ShopService.buy_gear("backpack")["ok"]))
	check("списано ровно %d монет" % price, GameState.coins == 5)
	check("ранец в собственности", GameState.has_gear("backpack"))
	check("купленный ранец сразу надет", GameState.current_gear == "backpack")

	# Ступень получше надевается сама; ступень похуже — нет, иначе покупка
	# запасного ранца пересаживала бы игрока с джетпака на пропеллеры.
	GameState.coins = Balance.get_gear_cost_coins("jetpack")
	check("джетпак куплен", bool(ShopService.buy_gear("jetpack")["ok"]))
	check("джетпак надет сам — он быстрее", GameState.current_gear == "jetpack")
	GameState.coins = Balance.get_gear_cost_coins("backpack_plus")
	check("улучшенный ранец куплен", bool(ShopService.buy_gear("backpack_plus")["ok"]))
	check("медленная ступень сама не надевается", GameState.current_gear == "jetpack")


## Ни одной кирки и ни одного ранца в рецептах быть не должно.
func _test_pickaxes_and_gear_are_not_crafted() -> void:
	var craftable: Array = []
	for r in ShopCatalog.recipes():
		craftable.append(String(r["id"]))
	for id in Balance.get_tools_in_line("pickaxe"):
		check("кирка %s не крафтится" % id, not craftable.has(id))
	for id in Balance.get_gear_ids():
		check("ранец %s не крафтится" % id, not craftable.has(id))
	check("рецепта джетпака больше нет", ShopCatalog.recipe("jetpack").is_empty())

	# И наоборот: технику за одни монеты не купить.
	_fresh()
	GameState.coins = 999999
	check("ручной бур за монеты не продаётся — он собирается",
		not bool(ShopService.buy_tool("hand_drill")["ok"]))
	check("монеты не тронуты", GameState.coins == 999999)


## Техника по-прежнему собирается из материалов (решение владельца).
func _test_tech_is_still_crafted() -> void:
	var craftable: Array = []
	for r in ShopCatalog.recipes():
		craftable.append(String(r["id"]))
	for id in ["hand_drill", "drill_rig", "well"]:
		check("техника %s осталась в рецептах" % id, craftable.has(id))

	# Скважина ставится уровнем, а не кладётся в рюкзак.
	_fresh()
	GameState.well_level = 0
	GameState.max_depth_reached = 200
	var r := ShopCatalog.recipe("well")
	check("рецепт скважины есть", not r.is_empty())
	if r.is_empty():
		return
	GameState.coins = int(r["coins"])
	for id in r["inputs"].keys():
		GameState.house_storage[String(id)] = int(r["inputs"][id])
	var res := ShopService.craft("well")
	check("скважина собралась: " + String(res.get("message", "")), bool(res["ok"]))
	check("скважина построена уровнем 1", GameState.well_level == 1)
	check("монеты за скважину списаны", GameState.coins == 0)
	check("второй раз скважину не собрать", not ShopService.can_craft("well"))
	GameState.well_level = 0


## Экипировка меняет то, ради чего она и заведена: скорость копки и полёта.
func _test_equipment_switches_dig_and_fly() -> void:
	_fresh()
	GameState.grant_tool("iron_pickaxe")
	GameState.grant_tool("obsidian_pickaxe")
	GameState.set_current_tool("iron_pickaxe")
	check("на железной кирке копка ×1.3",
		is_equal_approx(Equipment.current_dig_multiplier(), 1.3))
	check("смена кирки на верстаке прошла", bool(Equipment.equip_tool("obsidian_pickaxe")["ok"]))
	check("на обсидиановой копка ×5", is_equal_approx(Equipment.current_dig_multiplier(), 5.0))
	check("в руках именно она", GameState.current_tool == "obsidian_pickaxe")

	# Того, чего нет, не надеть.
	check("некупленную кирку надеть нельзя",
		not bool(Equipment.equip_tool("diamond_pickaxe")["ok"]))
	check("в руках осталась прежняя", GameState.current_tool == "obsidian_pickaxe")

	var base := Balance.get_gear_base_speed()
	GameState.grant_gear("backpack")
	GameState.grant_gear("jetpack_top")
	check("после покупки надет топовый джетпак", GameState.current_gear == "jetpack_top")
	check("потолок полёта = база ×10",
		is_equal_approx(Equipment.current_fly_speed(), base * 10.0))
	check("смена ранца на верстаке прошла", bool(Equipment.equip_gear("backpack")["ok"]))
	check("на базовом ранце потолок = база",
		is_equal_approx(Equipment.current_fly_speed(), base))
	check("некупленный ранец надеть нельзя",
		not bool(Equipment.equip_gear("backpack_plus")["ok"]))

	# Переодеваться можно только у верстака, в мастерской.
	GameState.house_is_indoors = false
	check("из шахты кирку не сменить", not bool(Equipment.equip_tool("iron_pickaxe")["ok"]))
	check("из шахты ранец не сменить", not bool(Equipment.equip_gear("jetpack_top")["ok"]))
	GameState.house_is_indoors = true


# ---------------------------------------------------------------------------
# Совместимость сейвов
#
# После обновления у игрока не должно пропасть НИЧЕГО из того, что он уже
# заработал по старым правилам.
# ---------------------------------------------------------------------------

func _test_save_migration_v1() -> void:
	_fresh()

	# Старый сейв: собранная железная кирка и джетпак с верстака, глубина 300.
	# Ранца в сейве нет вовсе — старый код выдавал его по глубине 10.
	var old_save := {
		"version": 1,
		"depth": {"max_depth_reached": 300},
		"tool": {"current_tool": "iron_pickaxe"},
		"economy": {
			"owned_tools": ["shovel", "rusty_pickaxe", "iron_pickaxe"],
			"owned_gear": ["jetpack"],
		},
	}
	var migrated := SaveSystem._migrate(old_save.duplicate(true))
	check("миграция подняла версию сейва до 2", int(migrated["version"]) == 2)
	var eco: Dictionary = migrated["economy"]
	check("железная кирка не пропала", Array(eco["owned_tools"]).has("iron_pickaxe"))
	check("джетпак не пропал", Array(eco["owned_gear"]).has("jetpack"))
	check("ранец, летавший по глубине, записан в собственность",
		Array(eco["owned_gear"]).has("backpack"))
	check("надет лучший из имеющихся — джетпак", String(eco["current_gear"]) == "jetpack")

	# Совсем старый сейв: блока economy нет вовсе, только глубина 150.
	# По прежним правилам джетпак давался с глубины 100, ранец — с 10.
	var ancient := {"version": 1, "depth": {"max_depth_reached": 150}}
	var eco2: Dictionary = SaveSystem._migrate(ancient)["economy"]
	check("древний сейв: джетпак с глубины 100 сохранён",
		Array(eco2["owned_gear"]).has("jetpack"))
	check("древний сейв: ранец с глубины 10 сохранён",
		Array(eco2["owned_gear"]).has("backpack"))
	check("древний сейв: надет джетпак", String(eco2["current_gear"]) == "jetpack")

	# Мелкая глубина — ни ранца, ни джетпака: отдавать то, чего не было, тоже
	# нельзя, иначе обновление раздаёт снаряжение бесплатно.
	var shallow := {"version": 1, "depth": {"max_depth_reached": 3}}
	var eco3: Dictionary = SaveSystem._migrate(shallow)["economy"]
	check("на глубине 3 ранца не было и не появилось",
		Array(eco3["owned_gear"]).is_empty() and String(eco3["current_gear"]).is_empty())

	# Сейв текущей версии миграция не переписывает.
	var fresh_save := {
		"version": 2,
		"depth": {"max_depth_reached": 500},
		"economy": {"owned_gear": ["backpack"], "current_gear": "backpack"},
	}
	var eco4: Dictionary = SaveSystem._migrate(fresh_save)["economy"]
	check("сейв версии 2 миграция не переписывает",
		Array(eco4["owned_gear"]).size() == 1 and String(eco4["current_gear"]) == "backpack")


## Бурмобиль — транспорт (задача «Бурмобиль — транспорт», решение владельца):
## состояние "в машине" — это current_tool == "drill_rig" (единственная
## истина, без отдельного in_rig), и оно уже сохраняется как обычный
## инструмент; брикеты — обычный предмет инвентаря. Оба переживают реальный
## цикл save_game()/load_game() через user://save.json — не только миграцию.
func _test_rig_state_persists_save_load() -> void:
	_fresh()
	GameState.owned_tools = ["shovel", "drill_rig"]
	GameState.current_tool = "drill_rig"
	GameState.inventory["fuel_block"] = 4
	GameState.max_depth_reached = 1000

	check("сейв записался", SaveSystem.save_game())

	# Имитация нового запуска: состояние сбрасывается перед загрузкой.
	GameState.current_tool = "shovel"
	GameState.owned_tools = ["shovel"]
	GameState.inventory.clear()
	GameState.max_depth_reached = 0

	check("сейв загрузился", SaveSystem.load_game())
	check("бурмобиль остался в собственности", GameState.owned_tools.has("drill_rig"))
	check("бурмобиль остался экипирован после перезапуска (одно состояние истины — current_tool)",
		GameState.current_tool == "drill_rig")
	check("брикеты пережили перезапуск", GameState.get_item_count("fuel_block") == 4)


## Апгрейд бура (задача «Апгрейд бура», решение владельца дословно: «в
## магазине после появления бурмобиля появляется опция улучшить бурмобиль»).
## Строки видны только когда бурмобиль уже есть — до покупки самой машины
## апгрейд ступени того, чего нет, смысла не имеет.
# ---------------------------------------------------------------------------

func _test_drill_upgrade_hidden_without_rig() -> void:
	_fresh()
	check("без бурмобиля строк апгрейда нет вовсе (владением проверяет UI)",
		not GameState.owns_tool("drill_rig"))
	GameState.owned_tools.append("drill_rig")
	check("с бурмобилем строки апгрейда есть — четыре тира из balance.json",
		ShopCatalog.drill_upgrade_rows().size() == Balance.get_drill_rig_tier_count())


## Строго последовательно: платину нельзя купить, не купив титан, — тем же
## гейтом, каким в игре устроены другие последовательные апгрейды.
func _test_drill_upgrade_sequential_gate() -> void:
	_fresh()
	GameState.owned_tools.append("drill_rig")
	GameState.coins = 100000000

	var rows := ShopCatalog.drill_upgrade_rows()
	check("тир 1 (титан) — следующий, доступный к покупке", String(rows[0]["status"]) == "next")
	check("тир 2 (платина) заперт, пока не куплен титан", String(rows[1]["status"]) == "locked")
	check("тир 3 (алмаз) заперт", String(rows[2]["status"]) == "locked")
	check("тир 4 (обсидиан) заперт", String(rows[3]["status"]) == "locked")

	# Прыгнуть через ступень нельзя: buy_drill_upgrade всегда продаёт РОВНО
	# следующую по порядку, а не ту, что попросили бы явно (интерфейс её и
	# не предлагает — кнопка заблокирована, см. shop_ui.gd:_make_drill_upgrade_row).
	check("тир 1 продан первым", bool(ShopService.buy_drill_upgrade()["ok"]))
	check("тир игрока стал 1 (титан)", GameState.drill_rig_tier == 1)

	rows = ShopCatalog.drill_upgrade_rows()
	check("титан теперь 'куплено'", String(rows[0]["status"]) == "owned")
	check("платина теперь следующая", String(rows[1]["status"]) == "next")
	check("алмаз по-прежнему заперт (нельзя перескочить платину)",
		String(rows[2]["status"]) == "locked")

	check("тир 2 продан вторым", bool(ShopService.buy_drill_upgrade()["ok"]))
	check("тир игрока стал 2 (платина)", GameState.drill_rig_tier == 2)
	check("тир 3 продан третьим", bool(ShopService.buy_drill_upgrade()["ok"]))
	check("тир игрока стал 3 (алмаз)", GameState.drill_rig_tier == 3)
	check("тир 4 продан четвёртым", bool(ShopService.buy_drill_upgrade()["ok"]))
	check("тир игрока стал 4 (обсидиан) — последняя ступень", GameState.drill_rig_tier == 4)

	var result := ShopService.buy_drill_upgrade()
	check("пятой ступени не существует — покупка отказывает", not bool(result["ok"]))
	check("тир не пополз выше 4", GameState.drill_rig_tier == 4)

	# Без самого бурмобиля апгрейд не продаётся, даже если тир почему-то не 0.
	_fresh()
	GameState.coins = 100000000
	check("без бурмобиля апгрейд не продаётся", not bool(ShopService.buy_drill_upgrade()["ok"]))


## Balance.get_tool_speed_multiplier("drill_rig") реально растёт ×1.2 за
## купленный тир — не только на уровне данных (test_balance.gd это уже
## проверяет без GameState), а живьём, через GameState.drill_rig_tier,
## который меняет именно покупка в магазине.
func _test_drill_upgrade_speed_multiplies_live() -> void:
	_fresh()
	GameState.owned_tools.append("drill_rig")
	GameState.coins = 100000000

	var prev: float = Balance.get_tool_speed_multiplier("drill_rig")
	for tier in range(1, 5):
		check("тир %d куплен" % tier, bool(ShopService.buy_drill_upgrade()["ok"]))
		var cur: float = Balance.get_tool_speed_multiplier("drill_rig")
		check("тир %d: скорость бурмобиля выросла ровно ×1.2 (сравнение соседних тиров)" % tier,
			is_equal_approx(cur, prev * 1.2))
		prev = cur


func _test_drill_upgrade_spends_exact_coins() -> void:
	_fresh()
	GameState.owned_tools.append("drill_rig")
	var price := Balance.get_drill_rig_tier_cost_coins(1)
	GameState.coins = price - 1
	check("без монет титановый бур не покупается", not bool(ShopService.buy_drill_upgrade()["ok"]))
	check("неудачная покупка монет не тронула", GameState.coins == price - 1)
	check("тир не сдвинулся", GameState.drill_rig_tier == 0)

	GameState.coins = price + 42
	check("покупка прошла", bool(ShopService.buy_drill_upgrade()["ok"]))
	check("списано ровно %d монет" % price, GameState.coins == 42)
	check("тир стал 1", GameState.drill_rig_tier == 1)


## Тот же тумблер, что и у кирок/ранцев/крафта — единственная точка списания
## монет во всей игре (GameState.spend_coins), апгрейд бура ничего не
## изобретает заново (см. ShopService.buy_drill_upgrade).
func _test_drill_upgrade_debug_free_shop() -> void:
	_fresh()
	GameState.owned_tools.append("drill_rig")
	GameState.coins = 0
	GameState.debug_free_shop = true
	check("«Бесплатно»: апгрейд бура проходит без монет", bool(ShopService.buy_drill_upgrade()["ok"]))
	check("«Бесплатно»: монеты не списались", GameState.coins == 0)
	check("тир всё равно вырос", GameState.drill_rig_tier == 1)
	GameState.debug_free_shop = false


## Тир апгрейда — часть экономики (scripts/shop/), переживает реальный цикл
## save_game()/load_game(), как и владение бурмобилем (см.
## _test_rig_state_persists_save_load выше).
func _test_drill_upgrade_persists_save_load() -> void:
	_fresh()
	GameState.owned_tools = ["shovel", "drill_rig"]
	GameState.drill_rig_tier = 3

	check("сейв записался", SaveSystem.save_game())
	GameState.drill_rig_tier = 0
	check("сейв загрузился", SaveSystem.load_game())
	check("тир апгрейда бура пережил перезапуск", GameState.drill_rig_tier == 3)
	GameState.drill_rig_tier = 0


## Дымовая проверка шторки: каждый из четырёх разделов магазина и экран
## экипировки должны СТРОИТЬСЯ. Кнопки здесь не нажимаются — вся арифметика
## проверена выше, — но список строится кодом, и опечатка в имени поля роняет
## не тест, а игрока, открывшего магазин.
func _test_shop_ui_builds_every_screen() -> void:
	_fresh()
	GameState.coins = 100000
	GameState.grant_tool("iron_pickaxe")
	GameState.grant_gear("backpack")
	GameState.inventory["gold"] = 3

	var ui = load("res://scenes/shop.tscn").instantiate()
	add_child(ui)
	for screen in [ShopUI.TAB_PICKS, ShopUI.TAB_TECH, ShopUI.TAB_FOOD,
			ShopUI.TAB_SELL, ShopUI.SCREEN_EQUIP]:
		ui.open(screen)
		check("раздел «%s» открылся и построил список" % screen,
			ui.is_open() and ui._list.get_child_count() > 0)
	ui.close()
	check("шторка закрывается", not ui.is_open())
	ui.queue_free()
	_fresh()

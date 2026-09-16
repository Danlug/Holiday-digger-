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
	_test_craft_jetpack()
	_test_idle_well_payout()
	_test_craft_without_materials()
	_test_iron_pickaxe_from_storage()
	_test_tool_requires_ownership()
	_test_buy_spends_coins()
	_test_exchange_dollars()
	_test_ad_double_sale()
	_test_workshop_gives_rusty_pickaxe()
	_test_cannot_sell_from_mine()

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
	GameState.max_depth_reached = 0
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


## Джетпак собирается на верстаке (решение владельца), а не выдаётся по
## глубине. Снаряжение не берут в руки и оно не занимает вес.
func _test_craft_jetpack() -> void:
	var r := ShopCatalog.recipe("jetpack")
	check("рецепт джетпака есть на верстаке", not r.is_empty())
	if r.is_empty():
		return
	check("джетпак — снаряжение, а не инструмент", String(r["kind"]) == "gear")
	check("рецепт открывается с глубины", int(r["unlock_depth"]) > 0)

	GameState.owned_gear.clear()
	GameState.coins = 999999
	for id in r["inputs"].keys():
		GameState.house_storage[String(id)] = int(r["inputs"][id]) * 2
	var res := ShopService.craft("jetpack")
	check("джетпак собрался: " + String(res.get("message", "")), bool(res["ok"]))
	check("джетпак теперь есть", GameState.has_gear("jetpack"))
	check("в руках остался прежний инструмент, джетпак в руки не берут",
		GameState.current_tool != "jetpack")
	check("джетпак не лёг в рюкзак и не занял вес",
		GameState.get_item_count("jetpack") == 0)


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
	GameState.coins = 10000
	var result := ShopService.craft("iron_pickaxe")
	check("без материалов кирка не крафтится", not bool(result["ok"]))
	check("неудачный крафт не тронул монеты", GameState.coins == 10000)
	check("инструмент не появился", not GameState.owned_tools.has("iron_pickaxe"))


## Железная кирка: 25 железа + 10 бронзы + 30 свинца + 200 монет (ГДД раздел 5).
## 160 кг материалов при рюкзаке 60 кг — копятся на складе за несколько ходок
## (ГДД раздел 14, «Склад в мастерской»).
func _test_iron_pickaxe_from_storage() -> void:
	_fresh()
	var recipe := ShopCatalog.recipe("iron_pickaxe")
	check("рецепт железной кирки из ГДД: 25 железа",  int(recipe["inputs"]["iron_ore"]) == 25)
	check("рецепт железной кирки из ГДД: 10 бронзы",  int(recipe["inputs"]["bronze"]) == 10)
	check("рецепт железной кирки из ГДД: 30 свинца",  int(recipe["inputs"]["lead"]) == 30)
	check("рецепт железной кирки из ГДД: 200 монет",  int(recipe["coins"]) == 200)

	var total_kg := 0.0
	for id in recipe["inputs"].keys():
		total_kg += Balance.get_mineral_weight(String(id)) * int(recipe["inputs"][id])
	check("материалы кирки тяжелее одного рюкзака — склад нужен по делу",
		total_kg > GameState.get_max_carry_kg())

	# Первая ходка: принесли часть железа и сложили на склад.
	GameState.inventory["iron_ore"] = 20
	ShopService.invest("iron_pickaxe")
	check("сложенное ушло из рюкзака", GameState.get_item_count("iron_ore") == 0)
	check("сложенное лежит на складе", HouseStorage.count("iron_ore") == 20)
	check("неполного рецепта не хватает на крафт", not ShopService.can_craft("iron_pickaxe"))

	# Вторая ходка: остальное железо и свинец. Лишнее железо сверх рецепта
	# остаётся в рюкзаке — на склад уходит ровно столько, сколько нужно.
	GameState.inventory["iron_ore"] = 10
	GameState.inventory["lead"] = 30
	ShopService.invest("iron_pickaxe")
	check("на склад ушло ровно недостающее", HouseStorage.count("iron_ore") == 25)
	check("излишек остался у игрока", GameState.get_item_count("iron_ore") == 5)

	# Третья ходка: бронза и монеты.
	GameState.inventory["bronze"] = 10
	ShopService.invest("iron_pickaxe")
	GameState.coins = 199
	check("без монет кирка не собирается", not ShopService.can_craft("iron_pickaxe"))
	GameState.coins = 250
	check("набранного склада хватает на крафт", bool(ShopService.craft("iron_pickaxe")["ok"]))
	check("монеты списаны ровно по рецепту", GameState.coins == 50)
	check("кирка в собственности", GameState.owned_tools.has("iron_pickaxe"))
	check("кирка взята в руки", GameState.current_tool == "iron_pickaxe")
	check("склад опустел ровно на рецепт", HouseStorage.count("iron_ore") == 0
		and HouseStorage.count("lead") == 0 and HouseStorage.count("bronze") == 0)
	check("излишек из рюкзака крафт не тронул", GameState.get_item_count("iron_ore") == 5)


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

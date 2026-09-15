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
	_test_craft_without_materials()
	_test_iron_pickaxe_project()
	_test_tool_requires_ownership()
	_test_buy_spends_coins()
	_test_exchange_dollars()
	_test_ad_double_sale()
	_test_workshop_gives_rusty_pickaxe()

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
	GameState.craft_invested.clear()
	GameState.owned_tools = ["shovel"]
	GameState.current_tool = "shovel"
	GameState.max_depth_reached = 0


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


func _test_craft_without_materials() -> void:
	_fresh()
	GameState.coins = 10000
	var result := ShopService.craft("iron_pickaxe")
	check("без материалов кирка не крафтится", not bool(result["ok"]))
	check("неудачный крафт не тронул монеты", GameState.coins == 10000)
	check("инструмент не появился", not GameState.owned_tools.has("iron_pickaxe"))


## Железная кирка: 25 железа + 10 бронзы + 30 свинца + 200 монет (ГДД раздел 5).
## 160 кг материалов при рюкзаке 60 кг — собирается за несколько ходок.
func _test_iron_pickaxe_project() -> void:
	_fresh()
	var recipe := ShopCatalog.recipe("iron_pickaxe")
	check("рецепт железной кирки из ГДД: 25 железа",  int(recipe["inputs"]["iron_ore"]) == 25)
	check("рецепт железной кирки из ГДД: 10 бронзы",  int(recipe["inputs"]["bronze"]) == 10)
	check("рецепт железной кирки из ГДД: 30 свинца",  int(recipe["inputs"]["lead"]) == 30)
	check("рецепт железной кирки из ГДД: 200 монет",  int(recipe["coins"]) == 200)

	var total_kg := 0.0
	for id in recipe["inputs"].keys():
		total_kg += Balance.get_mineral_weight(String(id)) * int(recipe["inputs"][id])
	check("материалы кирки тяжелее одного рюкзака — проект нужен по делу",
		total_kg > GameState.get_max_carry_kg())

	# Первая ходка: принесли часть железа.
	GameState.inventory["iron_ore"] = 20
	ShopService.invest("iron_pickaxe")
	check("вложенное ушло из рюкзака", GameState.get_item_count("iron_ore") == 0)
	check("вложенное записано в проект", GameState.get_invested("iron_pickaxe", "iron_ore") == 20)
	check("неполный проект не собирается", not ShopService.can_craft("iron_pickaxe"))

	# Вторая ходка: остальное железо и свинец. Лишнее железо сверх рецепта
	# остаётся в рюкзаке — проект берёт ровно столько, сколько нужно.
	GameState.inventory["iron_ore"] = 10
	GameState.inventory["lead"] = 30
	ShopService.invest("iron_pickaxe")
	check("проект берёт ровно недостающее", GameState.get_invested("iron_pickaxe", "iron_ore") == 25)
	check("излишек остался у игрока", GameState.get_item_count("iron_ore") == 5)

	# Третья ходка: бронза и монеты.
	GameState.inventory["bronze"] = 10
	ShopService.invest("iron_pickaxe")
	GameState.coins = 199
	check("без монет кирка не собирается", not ShopService.can_craft("iron_pickaxe"))
	GameState.coins = 250
	check("собранный проект даёт крафт", bool(ShopService.craft("iron_pickaxe")["ok"]))
	check("монеты списаны ровно по рецепту", GameState.coins == 50)
	check("кирка в собственности", GameState.owned_tools.has("iron_pickaxe"))
	check("кирка взята в руки", GameState.current_tool == "iron_pickaxe")
	check("вложения проекта израсходованы", GameState.get_invested("iron_pickaxe", "iron_ore") == 0)


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
	check("первый визит в мастерскую выдаёт дедову кирку", ShopService.visit_workshop())
	check("кирка записана в собственность", GameState.owned_tools.has("rusty_pickaxe"))
	check("кирка сразу в руках", GameState.current_tool == "rusty_pickaxe")
	check("второй визит кирку не дублирует", not ShopService.visit_workshop())

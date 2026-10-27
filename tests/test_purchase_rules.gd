extends Node
## test_purchase_rules — правило «где можно покупать снаряжение и еду»
## (заказ владельца, ГДД §15): дома у входной двери — без ограничений, под землёй
## — не более 3 раз в сутки и каждый раз за ролик, в остальных местах нельзя.
## Раунд 4: всё, что платится долларами, — где угодно, без ролика и мимо счётчика.
## Проверяет сервис (ShopService.can_buy и все покупки), счётчик ShopRemote
## (сутки, защита от перемотки часов, сейв), состояния плиток ShopItems и то,
## что не мешает продаже, обмену долларов, роликам и онбордингу (ГДД §9).
##
## Сценой, а не --script: нужны автолоады GameState и Balance.
##   godot --headless --path . res://tests/test_purchase_rules.tscn

const DAY := 86400
## Фиксированные «сутки» — тест не зависит от настоящих часов.
const D0 := 20000

var failures := 0
var total := 0


func _ready() -> void:
	print("=== test_purchase_rules ===")
	_test_places()
	_test_door_is_unlimited()
	_test_underground_three_ads()
	_test_underground_does_not_waste_ads()
	_test_underground_food_order()
	_test_outside_door_denied()
	_test_dollars_anywhere()
	_test_dual_price_good()
	_test_exempt_kinds_and_selling()
	_test_day_reset_and_clock_guard()
	_test_save_load()
	_test_shares_ext_key_with_seen()
	_test_tiles_by_place()
	_test_onboarding_door_order()
	_test_ui_flow()
	_test_garden_reminder()
	_test_hud_hints()
	MetaClock.override_unix = -1
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


## Чистый стол: новая игра, фиксированные сутки, сколько нужно монет.
func _fresh(coins: int = 1000000) -> void:
	GameState.reset_progress()
	MetaClock.override_unix = D0 * DAY + 3600
	GameState.coins = coins
	GameState.dollars = 50
	GameState.house_food_at_door.clear()
	GameState.house_free_orders_used_today = 0
	GameState.next_sale_doubled = false
	GameState.debug_free_shop = false
	ShopCatalog.reload()


func _place(place: String) -> void:
	match place:
		"door":
			GameState.house_is_indoors = true
			GameState.house_room = "hall"
			GameState.player_depth = 0
		"house":
			GameState.house_is_indoors = true
			GameState.house_room = "workshop"
			GameState.player_depth = 0
		"garden":
			GameState.house_is_indoors = false
			GameState.player_depth = 0
		"underground":
			GameState.house_is_indoors = false
			GameState.player_depth = 40


# ---------------------------------------------------------------------------

func _test_places() -> void:
	_fresh()
	_place("door")
	check("прихожая — у двери", ShopService.purchase_place() == ShopService.PLACE_DOOR)
	_place("house")
	check("другая комната — «в доме»", ShopService.purchase_place() == ShopService.PLACE_HOUSE)
	_place("garden")
	check("огород — на поверхности", ShopService.purchase_place() == ShopService.PLACE_GARDEN)
	_place("underground")
	check("с первой выкопанной клетки — под землёй", ShopService.purchase_place() == ShopService.PLACE_UNDERGROUND)
	GameState.player_depth = 1
	check("глубина 1 — уже под землёй", ShopService.purchase_place() == ShopService.PLACE_UNDERGROUND)
	check("лимит в сутки — 3 (данные владельца)", ShopRemote.limit() == 3)
	check("на старте осталось 3", ShopRemote.left_today() == 3 and ShopRemote.used_today() == 0)
	for kind in ["tool", "gear", "drill", "food", "good"]:
		check("«%s» подпадает под правило" % kind, ShopService.is_gated(kind))
	for kind in ["recipe", "exchange", "ad", "sell", "nosale", "equip_tool", "equip_gear", "info"]:
		check("«%s» вне правила" % kind, not ShopService.is_gated(kind))
	check("покупка за доллары узнаётся по валюте", ShopService.is_dollar_purchase({"kind": "good", "currency": "dollars"}))
	check("покупка за монеты — нет", not ShopService.is_dollar_purchase({"kind": "good", "currency": "coins"}))
	check("без валюты — нет (кирки, ранцы, еда)", not ShopService.is_dollar_purchase({"kind": "tool"}))


func _test_door_is_unlimited() -> void:
	_fresh()
	_place("door")
	for kind in ["tool", "gear", "drill", "food", "good"]:
		var g := ShopService.can_buy({"kind": kind})
		check("у двери «%s» можно, ролик не нужен" % kind, bool(g["ok"]) and not bool(g["needs_ad"]) and String(g["reason"]) == "")

	GameState.owned_tools.append("drill_rig")
	# Больше трёх покупок подряд всех видов — лимит у двери не трогается.
	var results: Array = [
		ShopService.buy_tool("iron_pickaxe"),
		ShopService.buy_tool("titanium_pickaxe"),
		ShopService.buy_gear("backpack"),
		ShopService.buy_gear("backpack_plus"),
		ShopService.buy_drill_upgrade(),
		ShopService.buy("energy_drink", "coins"),
		ShopService.buy("teleport_watch", "dollars"),
		HouseSystem.order_food("food_bar"),
		HouseSystem.order_food("food_buldak"),
	]
	var all_ok := true
	for r in results:
		all_ok = all_ok and bool(r["ok"])
	check("девять покупок подряд у двери прошли", all_ok)
	check("ни одна не помечена «за ролик»", not results.any(func(r): return bool(r.get("remote", false))))
	check("лимит роликов у двери не тронут", ShopRemote.left_today() == 3 and ShopRemote.used_today() == 0)
	check("кирки и ранцы получены", GameState.owned_tools.has("titanium_pickaxe") and GameState.has_gear("backpack_plus"))


func _test_underground_three_ads() -> void:
	_fresh()
	_place("underground")
	var g := ShopService.can_buy({"kind": "tool"})
	check("под землёй можно, но за ролик", bool(g["ok"]) and bool(g["needs_ad"]))
	check("в ответе остаток и лимит", int(g["left"]) == 3 and int(g["limit"]) == 3)

	var r1 := ShopService.buy_tool("iron_pickaxe")
	check("1-я покупка (кирка) под землёй прошла", bool(r1["ok"]) and bool(r1.get("remote", false)))
	check("осталось 2", ShopRemote.left_today() == 2)
	var r2 := ShopService.buy_gear("backpack")
	check("2-я покупка (ранец) прошла", bool(r2["ok"]) and bool(r2.get("remote", false)))
	check("осталось 1", ShopRemote.left_today() == 1)
	var coins := GameState.coins
	var r3 := ShopService.buy("energy_drink", "coins")
	check("3-я покупка (допинг) прошла", bool(r3["ok"]) and bool(r3.get("remote", false)))
	check("осталось 0", ShopRemote.left_today() == 0 and ShopRemote.used_today() == 3)
	check("допинг списал ровно цену", GameState.coins == coins - ShopCatalog.good_price(ShopCatalog.good("energy_drink", "coins"), "coins"))

	var g4 := ShopService.can_buy({"kind": "gear"})
	check("4-я: can_buy отказывает", not bool(g4["ok"]) and not bool(g4["needs_ad"]))
	check("4-я: причина названа (ролики кончились)", String(g4["reason"]).to_lower().contains("ролик"))
	var coins_before := GameState.coins
	var denials: Array = [
		ShopService.buy_tool("titanium_pickaxe"),
		ShopService.buy_gear("backpack_plus"),
		ShopService.buy("energy_drink", "coins"),
		HouseSystem.order_food("food_buldak"),
	]
	check("4-я покупка за монеты любого вида отказана", denials.all(func(r): return not bool(r["ok"])))
	check("отказ объясняет причину", denials.all(func(r): return String(r["message"]).to_lower().contains("ролик")))
	check("монеты не списаны", GameState.coins == coins_before)
	check("кирка и ранец не выданы", not GameState.owned_tools.has("titanium_pickaxe") and not GameState.has_gear("backpack_plus"))
	check("счётчик не ушёл в минус", ShopRemote.used_today() == 3)
	var dollars := GameState.dollars
	var watch := ShopService.buy("teleport_watch", "dollars")
	check("а за доллары и при пустом лимите покупка идёт (раунд 4)", bool(watch["ok"]) and not bool(watch.get("remote", false)))
	check("доллары списаны, счётчик тот же", GameState.dollars < dollars and ShopRemote.used_today() == 3)

	# Ступень бура берёт тот же один счётчик, гаджет за доллары — нет (раунд 4;
	# раньше тут ждали, что и гаджет спишет ролик).
	_fresh()
	_place("underground")
	GameState.owned_tools.append("drill_rig")
	var gadget := ShopService.buy("teleport_watch", "dollars")
	check("гаджет за доллары под землёй — без ролика", bool(gadget["ok"]) and not bool(gadget.get("remote", false)))
	check("ступень бура под землёй — за ролик", bool(ShopService.buy_drill_upgrade()["ok"]))
	check("из общего счётчика списала только ступень", ShopRemote.left_today() == 2)


## Ролик не пропадает зря: пока покупка не состоится, единица лимита цела.
func _test_underground_does_not_waste_ads() -> void:
	_fresh()
	_place("underground")
	GameState.coins = 10
	check("не хватает монет — отказ", not bool(ShopService.buy_tool("iron_pickaxe")["ok"]))
	check("не хватает монет — ролик цел", ShopRemote.left_today() == 3)
	GameState.dollars = 0
	check("не хватает долларов — отказ", not bool(ShopService.buy("teleport_watch", "dollars")["ok"]))
	check("не хватает долларов — ролик цел", ShopRemote.left_today() == 3)
	GameState.coins = 100000
	GameState.grant_tool("iron_pickaxe")
	check("уже есть — отказ", not bool(ShopService.buy_tool("iron_pickaxe")["ok"]))
	check("уже есть — ролик цел", ShopRemote.left_today() == 3)
	check("верстачный бур не покупается", not bool(ShopService.buy_tool("hand_drill")["ok"]))
	check("верстачный бур — ролик цел", ShopRemote.left_today() == 3)
	check("ступень без бурмобиля — отказ", not bool(ShopService.buy_drill_upgrade()["ok"]))
	check("ступень без бурмобиля — ролик цел", ShopRemote.left_today() == 3)
	GameState.coins = 0
	GameState.house_free_orders_used_today = HouseConfig.free_orders_per_day()
	check("заказ без денег и без бесплатных — отказ", not bool(HouseSystem.order_food("food_bar")["ok"]))
	check("заказ без денег — ролик цел", ShopRemote.left_today() == 3)
	check("«Бесплатно» (отладка) ролик всё равно списывает", _debug_free_spends_ad())


func _debug_free_spends_ad() -> bool:
	GameState.debug_free_shop = true
	GameState.coins = 0
	var ok := bool(ShopService.buy_gear("backpack")["ok"]) and ShopRemote.left_today() == 2
	GameState.debug_free_shop = false
	return ok


func _test_underground_food_order() -> void:
	_fresh()
	_place("underground")
	GameState.house_free_orders_used_today = 0
	var r := HouseSystem.order_food("food_buldak")
	check("заказ еды под землёй прошёл за ролик", bool(r["ok"]) and bool(r.get("remote", false)))
	check("бесплатный заказ бабки тоже потрачен", GameState.house_free_orders_used_today == 1)
	check("ролик списан", ShopRemote.left_today() == 2)
	check("порция уехала к двери", HouseFood.food_at_door_count() == 1)
	GameState.set_hunger(10.0)
	var steak := HouseSystem.order_food("food_steak")
	check("стейк под землёй съедается на месте", bool(steak["ok"]) and GameState.hunger > 10.0)
	check("и тоже стоит ролика", ShopRemote.left_today() == 1)


func _test_outside_door_denied() -> void:
	var reasons: Dictionary = {}
	for place in ["garden", "house"]:
		_fresh()
		_place(place)
		GameState.owned_tools.append("drill_rig")
		GameState.max_depth_reached = 5000
		var g := ShopService.can_buy({"kind": "food"})
		check("%s: can_buy отказывает без ролика" % place, not bool(g["ok"]) and not bool(g["needs_ad"]))
		check("%s: причина названа" % place, String(g["reason"]) != "")
		reasons[place] = String(g["reason"])
		var coins := GameState.coins
		var dollars := GameState.dollars
		var tries: Array = [
			ShopService.buy_tool("iron_pickaxe"),
			ShopService.buy_gear("backpack"),
			ShopService.buy_drill_upgrade(),
			ShopService.buy("energy_drink", "coins"),
			HouseSystem.order_food("food_bar"),
		]
		check("%s: ни одна покупка за монеты не прошла" % place, tries.all(func(r): return not bool(r["ok"])))
		check("%s: у каждого отказа есть причина" % place, tries.all(func(r): return String(r["message"]) != ""))
		check("%s: деньги целы" % place, GameState.coins == coins and GameState.dollars == dollars)
		check("%s: ролики не тронуты" % place, ShopRemote.left_today() == 3)
		check("%s: ничего не выдано" % place, not GameState.owned_tools.has("iron_pickaxe") and not GameState.has_gear("backpack"))
	check("огород и дом объясняют по-разному", reasons["garden"] != reasons["house"])


## Раунд 4, слова владельца: «Покупки за доллары можно делать в любом месте, не
## нужен просмотр рекламы». Все товары за доллары в каждом месте, в том числе под
## землёй при пустом лимите: без ролика, счётчик «N/3» не тронут.
func _test_dollars_anywhere() -> void:
	var ids: Array = ShopCatalog.goods_dollars().map(func(g): return String(g["id"]))
	check("товары за доллары: батончик, часы, выгрузка на склад (таблетки нет — раунд 6)",
		ids.has("energy_bar") and ids.has("teleport_watch") and ids.has("premium_unload") and not ids.has("full_restore_pill"))
	var bought: Array = []
	var on_event := func(id: StringName, data: Dictionary) -> void:
		if id == &"bought":
			bought.append(data)
	GameState.game_event.connect(on_event)
	for place in ["door", "house", "garden", "underground", "underground_empty"]:
		_fresh()
		_place("underground" if place == "underground_empty" else place)
		if place == "underground_empty":
			for i in ShopRemote.limit():
				ShopRemote.watch_ad()
		var used := ShopRemote.used_today()
		GameState.add_item("iron_ore", 2)   # выгрузке на склад есть что отправить (раунд 6)
		var g := ShopService.can_buy({"kind": "good", "currency": "dollars"})
		check("%s: за доллары можно, без ролика" % place,
			bool(g["ok"]) and not bool(g["needs_ad"]) and String(g["reason"]) == "")
		if place != "door":
			var coin_gate := ShopService.can_buy({"kind": "good", "currency": "coins"})
			check("%s: за монеты правило места прежнее" % place, not bool(coin_gate["ok"]) or bool(coin_gate["needs_ad"]))
		var coins := GameState.coins
		var dollars := GameState.dollars
		var price := 0
		var results: Array = []
		bought.clear()
		for id in ids:
			results.append(ShopService.buy(id, "dollars"))
			price += ShopCatalog.good_price(ShopCatalog.good(id, "dollars"), "dollars")
		check("%s: все %d товара за доллары куплены" % [place, ids.size()], results.all(func(r): return bool(r["ok"])))
		check("%s: ни один не «за ролик» (и в событии bought)" % place,
			results.all(func(r): return not bool(r.get("remote", false))) \
			and bought.size() == ids.size() and bought.all(func(d): return not d.has("remote")))
		check("%s: списаны ровно доллары, монеты целы" % place, GameState.dollars == dollars - price and GameState.coins == coins)
		check("%s: счётчик роликов не тронут" % place, ShopRemote.used_today() == used)
	GameState.game_event.disconnect(on_event)
	_fresh()
	_place("garden")
	GameState.dollars = 0
	GameState.add_item("iron_ore", 1)
	var poor := ShopService.buy("premium_unload", "dollars")
	check("без долларов — отказ про доллары, а не про место", not bool(poor["ok"]) and String(poor["message"]).contains("доллар"))


## Цена в двух валютах — это две плитки, каждая платится одной валютой и идёт по
## правилу своей валюты: монетная — по месту, долларовая — где угодно. Смешанной
## цены «монеты + доллары разом» в витрине нет (ГДД §15).
func _test_dual_price_good() -> void:
	_fresh()
	var dual := {"id": "test_dual", "name_ru": "Двойная цена", "desc_ru": "", "shelf": "food",
		"effect": "restore", "stamina_percent": 10, "price_coins": 100, "price_dollars": 1}
	ShopCatalog.data()["goods_coins"]["extra"].append(dual)
	ShopCatalog.data()["goods_dollars"]["extra"].append(dual)
	_place("garden")
	var coin_tile := _find(_offers("food"), "good:coins:test_dual")
	var dollar_tile := _find(_offers("food"), "good:dollars:test_dual")
	check("цена в двух валютах — две плитки", not coin_tile.is_empty() and not dollar_tile.is_empty())
	check("огород: монетная плитка заперта", String(coin_tile.get("state", "")) == "away")
	check("огород: долларовая свободна", String(dollar_tile.get("state", "")) == "available" and not dollar_tile.has("lock_reason"))
	check("огород: за монеты — отказ", not bool(ShopService.buy("test_dual", "coins")["ok"]))
	check("огород: за доллары — куплено", bool(ShopService.buy("test_dual", "dollars")["ok"]))
	_place("underground")
	coin_tile = _find(_offers("food"), "good:coins:test_dual")
	dollar_tile = _find(_offers("food"), "good:dollars:test_dual")
	check("шахта: монетная — за ролик, долларовая — без",
		bool(coin_tile.get("needs_ad", false)) and not dollar_tile.has("needs_ad") and not dollar_tile.has("count_text"))
	ShopCatalog.reload()


func _test_exempt_kinds_and_selling() -> void:
	_fresh()
	_place("underground")
	check("ролики кончились", ShopRemote.watch_ad() and ShopRemote.watch_ad() and ShopRemote.watch_ad() and ShopRemote.left_today() == 0)
	for kind in ["recipe", "exchange", "ad", "sell", "equip_tool", "info"]:
		var g := ShopService.can_buy({"kind": kind})
		check("при пустом лимите «%s» всё равно разрешено правилом" % kind, bool(g["ok"]) and not bool(g["needs_ad"]))
	var coins := GameState.coins
	check("обмен долларов работает под землёй без роликов", bool(ShopService.exchange_dollars_to_coins(1)["ok"]) and GameState.coins > coins)
	check("ролик-награда работает под землёй", bool(ShopService.claim_ad("small_coins")["ok"]))
	GameState.inventory["gold"] = 4
	var dump := ShopService.remote_dump_loot()
	check("дистанционная продажа за ролик работает", bool(dump["ok"]) and GameState.get_item_count("gold") == 0)
	check("она не берёт ролики на покупки", ShopRemote.left_today() == 0 and ShopRemote.used_today() == 3)

	# Продажа в мастерской (дом, не у двери) — правило покупок ей не мешает.
	_fresh()
	_place("house")
	GameState.inventory["gold"] = 2
	check("в мастерской продажа идёт, хотя покупки там закрыты", bool(ShopService.sell_all()["ok"]))
	check("верстак дома по-прежнему работает (правило покупок ему не мешает)",
		String(ShopService.check_craft("bronze")["reason"]) != "Верстак дома, в подвале")
	_place("underground")
	check("а из шахты верстак закрыт, как и раньше",
		String(ShopService.check_craft("bronze")["reason"]) == "Верстак дома, в подвале")


func _test_day_reset_and_clock_guard() -> void:
	_fresh()
	_place("underground")
	for i in 3:
		ShopRemote.watch_ad()
	check("за сутки D0 использовано 3", ShopRemote.left_today() == 0)
	check("четвёртый ролик не засчитан", not ShopRemote.watch_ad())

	# Новые реальные сутки: ГДД §15 — сброс по GameState.daily_reset.
	MetaClock.override_unix = (D0 + 1) * DAY + 50
	GameState.daily_reset.emit()
	check("в новые сутки снова 3", ShopRemote.left_today() == 3)
	check("и снова можно купить", bool(ShopService.buy_gear("backpack")["ok"]))
	check("осталось 2", ShopRemote.left_today() == 2)

	# Перемотка часов назад: счётчик не возвращается.
	MetaClock.override_unix = D0 * DAY + 50
	GameState.daily_reset.emit()
	check("часы назад: остаток не вырос", ShopRemote.left_today() == 2)
	check("часы назад: на вчерашние сутки не откатились", ShopRemote.left_today() != 3)
	ShopRemote.watch_ad()
	ShopRemote.watch_ad()
	check("часы назад: потратили остаток", ShopRemote.left_today() == 0)
	MetaClock.override_unix = (D0 - 5) * DAY
	check("часы далеко назад: по-прежнему 0", ShopRemote.left_today() == 0 and not ShopRemote.watch_ad())

	# Тот же день после «перезахода»: не сбрасывается.
	MetaClock.override_unix = (D0 + 1) * DAY + 80000
	check("те же сутки позже вечером: всё ещё 0", ShopRemote.left_today() == 0)
	# Вперёд на следующие — сброс.
	MetaClock.override_unix = (D0 + 2) * DAY + 1
	check("следующие сутки: снова 3", ShopRemote.left_today() == 3)


func _test_save_load() -> void:
	_fresh()
	_place("underground")
	ShopRemote.watch_ad()
	ShopRemote.watch_ad()
	check("потрачено 2", ShopRemote.left_today() == 1)
	check("сейв записался", SaveSystem.save_game())
	GameState.ext.clear()
	check("после стирания состояния — снова 3 (проверка, что тест честный)", ShopRemote.left_today() == 3)
	check("сейв загрузился", SaveSystem.load_game())
	check("счётчик пережил сейв: осталось 1", ShopRemote.left_today() == 1)
	check("ключ лежит в ext[\"shop\"][\"remote\"]", GameState.ext_get("shop", {}).has("remote"))
	# Загрузка тем же днём не воскрешает роликов.
	_place("underground")
	check("после загрузки четвёртой покупки тоже нет", ShopRemote.watch_ad() and not ShopRemote.watch_ad())


## Ключ «shop» делят «новинки» витрины и счётчик: ни одно не стирает другое.
func _test_shares_ext_key_with_seen() -> void:
	_fresh()
	_place("door")
	ShopRemote.watch_ad()
	ShopItems.seed_seen()
	check("seed_seen не затёр счётчик", ShopRemote.used_today() == 1)
	var seen: Array = GameState.ext_get("shop", {}).get("seen", [])
	check("«виденное» записалось", not seen.is_empty())
	ShopItems.mark_seen(["tool:fake"])
	check("mark_seen не затёр счётчик", ShopRemote.used_today() == 1)
	ShopRemote.watch_ad()
	check("а счётчик не затирает «виденное»", (GameState.ext_get("shop", {}).get("seen", []) as Array).has("tool:fake"))


func _offers(tab: String) -> Array:
	return ShopItems.offers_flat(tab)


func _badged(offers: Array) -> Array:
	return offers.filter(func(o): return bool(o.get("needs_ad", false)))


func _locked(offers: Array) -> Array:
	return offers.filter(func(o): return o.has("lock_reason"))


func _test_tiles_by_place() -> void:
	# Дома у двери — плитки как были.
	_fresh()
	_place("door")
	for tab in ["food", "picks", "tech", "premium"]:
		var offers := _offers(tab)
		check("у двери «%s»: нет ни бейджей, ни замков по правилу места" % tab,
			_badged(offers).is_empty() and _locked(offers).is_empty())
	var iron: Dictionary = _find(_offers("picks"), "tool:iron_pickaxe")
	check("у двери кирка доступна как раньше", String(iron["state"]) == "available" and String(iron.get("count_text", "")) == "")

	# Под землёй с роликами: бейдж «осталось N/3» и значок ролика.
	_fresh()
	_place("underground")
	GameState.owned_tools.append("drill_rig")
	GameState.grant_tool("iron_pickaxe")
	for tab in ["food", "picks", "tech", "premium"]:
		var offers := _offers(tab)
		var gated := offers.filter(func(o): return ShopService.is_gated(String(o["kind"])) \
				and not ShopService.is_dollar_purchase(o) \
				and (String(o["state"]) == "available" or String(o["state"]) == "poor"))
		var all_badged := true
		for o in gated:
			all_badged = all_badged and bool(o.get("needs_ad", false)) and String(o.get("count_text", "")) == "3/3" \
					and String(o.get("corner_tl", "")) == "video"
		# Во вкладке за доллары монетных товаров нет — бейджей там не ждём (раунд 4).
		check("под землёй «%s»: у %d плиток за монеты бейдж 3/3 и ролик" % [tab, gated.size()],
			all_badged and (tab in ["tech", "premium"] or not gated.is_empty()))
	var dollar_tiles: Array = _offers("premium").filter(func(o): return String(o["currency"]) == "dollars" and String(o["kind"]) == "good")
	check("под землёй плитки за доллары без бейджа N/3, ролика и замка", dollar_tiles.size() >= 3 \
		and dollar_tiles.all(func(o): return _plain(o)))
	var owned: Dictionary = _find(_offers("picks"), "tool:iron_pickaxe")
	check("купленное бейджа не получает", String(owned["state"]) == "owned" and not owned.has("needs_ad"))
	var tool_tile: Dictionary = _find(_offers("picks"), "tool:titanium_pickaxe")
	check("в подсказке плитки — цена и ролик", String(tool_tile["extra"]).contains("ролик") and String(tool_tile["extra"]).contains("монет"))
	var ads: Array = _offers("food").filter(func(o): return String(o["kind"]) == "ad")
	check("плитки-ролики наград правилом не затронуты", not ads.is_empty() and ads.all(func(o): return not o.has("needs_ad") and not o.has("lock_reason")))
	var exch: Dictionary = _find(_offers("premium"), "exchange:1")
	check("обмен долларов правилом не затронут", not exch.has("needs_ad") and not exch.has("lock_reason"))
	var recipes := _offers("tech").filter(func(o): return String(o["kind"]) == "recipe")
	check("рецепты верстака правилом не затронуты", not recipes.is_empty() and recipes.all(func(o): return not o.has("needs_ad") and not o.has("lock_reason")))

	# Под землёй, ролики кончились: замок и причина.
	ShopRemote.watch_ad()
	ShopRemote.watch_ad()
	ShopRemote.watch_ad()
	var locked_food := _locked(_offers("food"))
	check("без роликов еда заперта", not locked_food.is_empty() and locked_food.all(func(o): return String(o["state"]) == "away" \
			and String(o["corner"]) == "lock" and String(o["count_text"]) == "0/3" and String(o["extra"]) == String(o["lock_reason"])))
	check("заперта и экипировка", not _locked(_offers("picks")).is_empty())
	check("запертое не считается «новинкой»", _locked(_offers("food")).all(func(o): return not bool(o["new"])))
	var premium_empty: Array = _offers("premium")
	check("без роликов плитки за доллары по-прежнему открыты", premium_empty.filter(func(o): \
		return String(o["currency"]) == "dollars" and String(o["kind"]) == "good").all(func(o): return _plain(o)))

	check("под землёй без роликов — замок, а не дверь", locked_food.all(func(o): return not o.has("at_door")))

	# На огороде и в доме вне двери (раунд 5): вместо замка значок двери, причина,
	# без счётчика «N/3» и без ролика. Было: замок — владелец попросил, чтобы
	# огород напоминал «покупать у входной двери».
	for place in ["garden", "house"]:
		_fresh()
		_place(place)
		var food := _locked(_offers("food"))
		check("%s: еда «у двери» — значок двери, без счётчика и ролика" % place, not food.is_empty() and food.all(func(o): \
				return String(o["corner"]) == "door" and bool(o.get("at_door", false)) and String(o["state"]) == "away" \
				and String(o.get("count_text", "")) == "" and not o.has("needs_ad") and String(o.get("corner_tl", "")) == ""))
		check("%s: и снаряжение «у двери»" % place, _locked(_offers("picks")).all(func(o): return String(o["corner"]) == "door"))
		var reason := String(food[0]["lock_reason"])
		check("%s: причина — про входную дверь" % place, reason.contains("двер"))
		check("%s: про ролик ни слова" % place, not reason.contains("ролик"))
		check("%s: в подсказке та же причина" % place, String(food[0]["extra"]) == reason)
		check("%s: ад-бейджей нет" % place, _badged(_offers("picks")).is_empty())
		# «3/3» у ролика-награды «+1 $» — его собственный лимит, не покупка: его не проверяем.
		var paid: Array = _offers("premium").filter(func(o): return String(o["currency"]) == "dollars")
		check("%s: плитки за доллары (%d) без замка и «N/3»" % [place, paid.size()],
			paid.size() >= 4 and paid.all(func(o): return _plain(o)))


## Плитка «как у двери»: правило места её не тронуло.
func _plain(o: Dictionary) -> bool:
	return not o.has("needs_ad") and not o.has("lock_reason") and String(o.get("count_text", "")) == "" \
		and String(o.get("corner_tl", "")) == "" and String(o["state"]) != "away"


func _find(offers: Array, key: String) -> Dictionary:
	for o in offers:
		if String(o["key"]) == key:
			return o
	return {}


## ГДД §9: первый заказ еды при онбординге делается у входной двери — бабкины
## деньги покрывают его, ролики не нужны и не трогаются.
func _test_onboarding_door_order() -> void:
	_fresh(0)
	_place("door")
	var r := HouseSystem.order_food("food_bar")
	check("первый заказ у двери без монет прошёл (деньги бабки)", bool(r["ok"]))
	check("без ролика", not bool(r.get("remote", false)) and ShopRemote.left_today() == 3)
	check("использован бесплатный заказ", GameState.house_free_orders_used_today == 1)
	check("порция едет к двери", HouseFood.food_at_door_count() == 1)
	_place("garden")
	var far := HouseSystem.order_food("food_bar")
	check("с огорода заказ закрыт, причина названа", not bool(far["ok"]) and String(far["message"]).contains("двер"))
	check("бесплатный заказ не потрачен зря", GameState.house_free_orders_used_today == 1)


func _test_ui_flow() -> void:
	_fresh()
	GameState.max_depth_reached = 100
	GameState.coins = 5000
	var ui = load("res://scenes/shop.tscn").instantiate()
	add_child(ui)

	# Под землёй витрина открывается как прежде, плитки с бейджем.
	_place("underground")
	ui.open(ShopUI.TAB_PICKS)
	var tile: ShopTile = ui._tiles["tool:iron_pickaxe"]
	check("под землёй открылась вкладка снаряжения", ui.is_open())
	check("плитка кирки показывает 3/3", String(tile.offer.get("count_text", "")) == "3/3")
	check("значок ролика в углу плитки", tile._corner_tl.visible)
	check("при открытии под землёй плашки-объяснения нет", not ui._notice_panel.visible)
	ui._on_tile_pressed(tile.offer, tile)
	check("тап открыл карточку", ui._card != null)
	var has_ad_glyph := false
	if ui._card_ok != null:
		for c in ui._card_ok.get_children():
			if c is TextureRect and (c as TextureRect).texture == ShopArt.tex("glyph_video"):
				has_ad_glyph = true
	check("на кнопке покупки значок ролика", has_ad_glyph)
	ui._confirm_card()
	check("покупка по галочке прошла и списала ролик", GameState.owned_tools.has("iron_pickaxe") and ShopRemote.left_today() == 2)
	var tile2: ShopTile = ui._tiles["tool:titanium_pickaxe"]
	check("после покупки бейдж на других плитках — 2/3", String(tile2.offer.get("count_text", "")) == "2/3")
	ui.close()

	# Без роликов: замок, тап не открывает карточку и говорит причину.
	ShopRemote.watch_ad()
	ShopRemote.watch_ad()
	ui.open(ShopUI.TAB_FOOD)
	var food_tile: ShopTile = ui._tiles["food:food_bar"]
	check("без роликов плитка еды заперта", String(food_tile.offer["state"]) == "away" and food_tile._corner_tr.visible)
	ui._notice_panel.visible = false
	ui._on_tile_pressed(food_tile.offer, food_tile)
	check("тап по замку карточку не открывает", ui._card == null)
	check("причина показана плашкой", ui._notice_panel.visible and ui._notice_label.text == String(food_tile.offer["lock_reason"]))
	var tip := food_tile.get_meta(Tip.META) as Dictionary
	check("причина в подсказке плитки", String(tip["extra"]) == String(food_tile.offer["lock_reason"]))
	ui.close()

	# Без роликов витрина за доллары работает как дома у двери (раунд 4).
	ui._notice_panel.visible = false
	GameState.add_item("iron_ore", 1)   # выгрузке есть что отправить
	ui.open(ShopUI.SCREEN_PREMIUM)
	var pill: ShopTile = ui._tiles["good:dollars:premium_unload"]
	check("шахта без роликов: выгрузка без замка и «N/3»", String(pill.offer["state"]) == "available" \
		and not pill._corner_tr.visible and not pill._corner_tl.visible and String(pill.offer.get("count_text", "")) == "")
	ui._on_tile_pressed(pill.offer, pill)
	check("тап по выгрузке открыл карточку", ui._card != null)
	var pill_ad_glyph := false
	if ui._card_ok != null:
		for c in ui._card_ok.get_children():
			if c is TextureRect and (c as TextureRect).texture == ShopArt.tex("glyph_video"):
				pill_ad_glyph = true
	check("на кнопке покупки за доллары значка ролика нет", not pill_ad_glyph)
	var dollars_before := GameState.dollars
	ui._confirm_card()
	check("выгрузка куплена за доллары, счётчик роликов тот же",
		GameState.dollars == dollars_before - int(pill.offer["price"]) and ShopRemote.used_today() == ShopRemote.limit())
	ui.close()

	# Огород: витрина открывается, плитки «у двери», внизу полоса-напоминание
	# (раунд 5; раньше — плашка с текстом сверху, она закрывала первый ряд).
	_place("garden")
	ui._notice_panel.visible = false
	ui.open(ShopUI.TAB_FOOD)
	check("на огороде витрина открывается", ui.is_open())
	check("полоса «у входной двери» видна сразу", ui._door_strip.visible and ui._door_strip._label.text.contains("двер"))
	check("плашки с текстом сверху нет", not ui._notice_panel.visible)
	check("на огороде есть кнопка «к двери»", ui._door_strip.go_btn.visible)
	check("список не уходит под полосу", is_equal_approx(ui._scroll.offset_bottom, -(ShopUI.NAV_H + ShopDoorStrip.H)))
	ui.close()
	ui._notice_panel.visible = false
	ui.open(ShopUI.SCREEN_PREMIUM)
	check("премиум-витрина (кнопка «Магазин») на огороде открыта", ui.is_open())
	var exch: ShopTile = ui._tiles["exchange:1"]
	check("обмен долларов на огороде доступен", String(exch.offer["state"]) == "available")
	check("на огороде во вкладке за доллары плашки «к двери» нет (раунд 4)", not ui._notice_panel.visible)
	check("и полосы «у двери» нет", not ui._door_strip.visible)
	var watch: ShopTile = ui._tiles["good:dollars:teleport_watch"]
	check("часы на огороде без замка", String(watch.offer["state"]) == "available" and not watch._corner_tr.visible)
	ui.close()

	# У двери — всё как раньше, плашки нет.
	_place("door")
	ui._notice_panel.visible = false
	ui.open(ShopUI.TAB_FOOD)
	check("у двери плашки нет", not ui._notice_panel.visible)
	check("у двери плитки без замков", not ui._tiles.values().any(func(t): return t.offer.has("lock_reason")))
	check("у двери полосы «к двери» нет", not ui._door_strip.visible)
	ui.close()

	# Новые сутки: открытая витрина обновляет бейджи сама.
	_place("underground")
	ui.open(ShopUI.TAB_PICKS)
	var before: ShopTile = ui._tiles["tool:platinum_pickaxe"]
	check("до сброса плитка заперта (роликов нет)", String(before.offer["state"]) == "away")
	MetaClock.override_unix = (D0 + 1) * DAY + 5
	GameState.daily_reset.emit()
	var after: ShopTile = ui._tiles["tool:platinum_pickaxe"]
	check("после daily_reset плитка снова 3/3", String(after.offer.get("count_text", "")) == "3/3")
	ui.close()
	ui.queue_free()


## Раунд 5, слова владельца: «В огороде покупки напоминают, что покупать надо у
## входной двери». Тап по монетной плитке на огороде: карточки нет, ролик и
## деньги не тронуты, полоса внизу вспыхивает; «к двери» закрывает витрину и
## ведёт стрелкой (не телепорт); в прихожей витрина открывается сама.
func _test_garden_reminder() -> void:
	_fresh()
	GameState.max_depth_reached = 100
	var ui = load("res://scenes/shop.tscn").instantiate()
	add_child(ui)
	_place("garden")
	ui.open(ShopUI.TAB_FOOD)
	var tile: ShopTile = ui._tiles["food:food_bar"]
	check("огород: плитка еды с дверью в углу", tile._corner_tr.visible and tile._corner_tr.texture == ShopArt.tex("glyph_door"))
	check("огород: без «N/3» и значка ролика", not tile._count.visible and not tile._corner_tl.visible)
	ui._notice_panel.visible = false
	var coins := GameState.coins
	ui._on_tile_pressed(tile.offer, tile)
	check("тап по плитке «у двери» карточку не открывает", ui._card == null)
	check("плашки с текстом сверху нет — отвечает полоса", not ui._notice_panel.visible and ui._door_strip.visible)
	check("ролики и деньги не тронуты", ShopRemote.left_today() == ShopRemote.limit() and GameState.coins == coins)
	var gear: ShopTile = ui._tiles.get("good:coins:energy_drink", null)
	if gear == null:
		for t in ui._tiles.values():
			if String(t.offer.get("kind", "")) == "good" and String(t.offer.get("currency", "")) == "coins":
				gear = t
				break
	check("допинги за монеты тоже «у двери»", gear != null and bool(gear.offer.get("at_door", false)))
	# «Купить» с карточки (если бы она открылась) тоже отвечает дверью, а не отказом.
	ui._card_offer = tile.offer
	ui._card = Control.new()
	ui._root.add_child(ui._card)
	ui._confirm_card()
	check("кнопка «купить» на огороде: напоминание, карточка закрыта", ui._card == null and not ui._notice_panel.visible)
	check("и ничего не куплено", GameState.coins == coins and HouseFood.food_at_door_count() == 0)
	ui.close()

	# «К двери»: витрина закрывается, стрелка запоминает вкладку.
	ui.open(ShopUI.TAB_PICKS)
	check("на вкладке снаряжения полоса тоже есть", ui._door_strip.visible)
	ui._go_to_door()
	check("«к двери» закрыл витрину", not ui.is_open())
	check("стрелка к двери запущена и помнит вкладку", ui._door_guide.is_active() and ui._door_guide.tab == ShopUI.TAB_PICKS)
	check("это не телепорт: герой не в доме", not GameState.house_is_indoors)
	ui.open(ShopUI.TAB_FOOD)
	check("витрину открыли снова — стрелка погасла", not ui._door_guide.is_active())
	ui.close()

	# Куда смотрит стрелка: дверь в кадре — вниз над ней, за краем — к краю.
	var g: ShopDoorGuide = ui._door_guide
	var view := Vector2(224, 480)
	check("дверь в кадре — стрелка вниз", g._place_marks(Vector2(120, 300), view) == "down" and g._down.visible and not g._edge.visible)
	check("дверь правее кадра — стрелка у правого края", g._place_marks(Vector2(400, 300), view) == "right" \
		and g._edge.visible and g._edge.position.x > 150.0 and not g._edge_arrow.flip_h)
	check("дверь левее кадра — у левого края", g._place_marks(Vector2(-90, 300), view) == "left" \
		and g._edge.position.x < 20.0 and g._edge_arrow.flip_h)
	check("стрелка у края не уходит под шапку HUD", g._place_marks(Vector2(-90, -400), view) == "left" and g._edge.position.y >= 120.0)
	g.stop()

	# Без мира (нет дома) стрелка гаснет сама, а не висит.
	g.start(ShopUI.TAB_FOOD)
	g._update(0.0)
	check("без дома стрелка гаснет на первом шаге", not g.is_active() and not g._down.visible and not g._edge.visible)

	# Дошёл и зашёл в прихожую — витрина открылась сама на той вкладке.
	g.tab = ShopUI.TAB_PICKS
	g._reopen_left = ShopDoorGuide.REOPEN_SECONDS
	g._reopen_wait = 0.4
	g._update(0.1)
	check("пока на огороде — ждёт", g.is_reopen_pending() and not ui.is_open())
	_place("door")
	g._update(0.1)
	check("в прихожей не сразу — дом ещё открывается", not ui.is_open())
	g._update(0.5)
	check("в прихожей витрина открылась сама на вкладке снаряжения", ui.is_open() and ui._tab == ShopUI.TAB_PICKS)
	check("у двери плитки без двери и замка", not ui._tiles.values().any(func(t): return t.offer.has("lock_reason")))
	ui.close()
	_place("garden")
	g._reopen_left = ShopDoorGuide.REOPEN_SECONDS
	_place("underground")
	g._update(0.1)
	check("ушёл в шахту — витрину не открываем", not g.is_reopen_pending() and not ui.is_open())
	_place("house")
	g._reopen_left = ShopDoorGuide.REOPEN_SECONDS
	g._update(0.1)
	check("зашёл не в прихожую — тоже нет", not g.is_reopen_pending() and not ui.is_open())

	# В комнате дома полоса без кнопки «к двери»: в прихожую ведут двери интерьера.
	_place("house")
	ui.open(ShopUI.TAB_FOOD)
	check("в комнате дома полоса есть, кнопки «к двери» нет", ui._door_strip.visible and not ui._door_strip.go_btn.visible)
	ui.close()
	# В шахте — как было: замок, без полосы.
	_place("underground")
	for i in ShopRemote.limit():
		ShopRemote.watch_ad()
	ui.open(ShopUI.TAB_FOOD)
	var under: ShopTile = ui._tiles["food:food_bar"]
	check("шахта без роликов: замок, без полосы «к двери»", under._corner_tr.texture == ShopArt.tex("glyph_lock") and not ui._door_strip.visible)
	ui._notice_panel.visible = false
	ui._on_tile_pressed(under.offer, under)
	check("шахта: тап по замку по-прежнему говорит причину плашкой", ui._notice_panel.visible and ui._notice_label.text.contains("Ролик"))
	ui.close()
	ui.queue_free()


func _test_hud_hints() -> void:
	_fresh()
	_place("underground")
	var tip := ShopPlaceHint.button_tip()
	check("под землёй в подсказке кнопки остаток", String(tip[2]).contains("3 из 3"))
	check("на кнопке красная цифра 3", ShopPlaceHint.button_badge() == 3)
	check("пункт меню называет ролики", ShopPlaceHint.menu_body().contains("ролик"))
	ShopRemote.watch_ad()
	check("цифра на кнопке уменьшилась", ShopPlaceHint.button_badge() == 2)
	check("под землёй подсказка говорит, что за доллары ролик не нужен", String(ShopPlaceHint.button_tip()[1]).contains("доллар"))
	_place("garden")
	check("на огороде цифры нет", ShopPlaceHint.button_badge() == 0)
	check("на огороде подсказка про дверь", String(ShopPlaceHint.button_tip()[1]).contains("двер"))
	check("на огороде подсказка: за доллары — где угодно", String(ShopPlaceHint.button_tip()[2]).contains("доллар"))
	check("на огороде в меню про дверь", ShopPlaceHint.menu_body().contains("двер"))
	check("и про доллары", ShopPlaceHint.menu_body().contains("доллар"))
	_place("door")
	check("у двери меню как раньше", ShopPlaceHint.menu_body() == "Продажа, верстак, лавка")
	var btn := Button.new()
	add_child(btn)
	_place("underground")
	ShopPlaceHint.sync_button(btn)
	check("кнопка получила подсказку и цифру", btn.has_meta(Tip.META) and btn.get_node_or_null(UiBtn.BADGE_NAME) != null)
	btn.queue_free()

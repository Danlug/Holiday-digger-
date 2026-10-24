extends Node
## test_craft_qty — переработка пачкой на верстаке (раунд 4, «craft-qty»):
## слово владельца «когда плавишь металлолом… тупо делать по одному — надо
## ползунок». Проверяет ShopService.max_craft / craft_plan / craft(id, n) и
## карточку рецепта с ползунком (CraftQtyBox в ShopUI).
##
##   godot --headless --path . res://tests/test_craft_qty.tscn

var failures := 0
var total := 0
var _events: Array = []


func _ready() -> void:
	print("=== test_craft_qty ===")
	GameState.reset_progress()
	GameState.game_event.connect(func(id: StringName, data: Dictionary) -> void:
		if id == &"crafted":
			_events.append(data.duplicate()))

	_test_which_recipes_are_batch()
	_test_max_by_materials()
	_test_max_needs_workshop()
	_test_batch_from_storage_and_pack()
	_test_atomic_refusals()
	_test_space_weight_spills_to_storage()
	_test_space_stack_spills_to_storage()
	_test_plan_matches_result()
	_test_single_recipes_unchanged()
	_test_batch_persists_save_load()
	await _test_card_slider()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


## Дома, у верстака, пустые рюкзак и склад.
func _fresh() -> void:
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.coins = 0
	GameState.owned_tools = ["shovel"]
	GameState.current_tool = "shovel"
	GameState.owned_gear = []
	GameState.current_gear = ""
	GameState.max_depth_reached = 0
	GameState.well_level = 0
	GameState.debug_free_shop = false
	GameState.house_is_indoors = true
	GameState.house_room = "hall"
	_events.clear()


func _snapshot() -> Dictionary:
	return {"inv": GameState.inventory.duplicate(), "st": GameState.house_storage.duplicate(),
		"coins": GameState.coins}


func _same(a: Dictionary, b: Dictionary) -> bool:
	return a["inv"] == b["inv"] and a["st"] == b["st"] and a["coins"] == b["coins"]


# ---------------------------------------------------------------------------

func _test_which_recipes_are_batch() -> void:
	check("плавка бронзы — переработка (ползунок)", ShopService.is_batch("bronze"))
	for id in ["hand_drill", "drill_rig", "well"]:
		check("%s — разовая постройка, по одной" % id, not ShopService.is_batch(id))
	check("несуществующий рецепт — не переработка", not ShopService.is_batch("nope"))


func _test_max_by_materials() -> void:
	_fresh()
	check("без металлолома MAX = 0", ShopService.max_craft("bronze") == 0)
	GameState.inventory["scrap"] = 14
	check("MAX = металлолом в рюкзаке (14)", ShopService.max_craft("bronze") == 14)
	GameState.house_storage["scrap"] = 23
	check("MAX = рюкзак + склад (14 + 23 = 37), ГДД §14", ShopService.max_craft("bronze") == 37)
	GameState.inventory.erase("scrap")
	check("MAX = только склад (23)", ShopService.max_craft("bronze") == 23)
	# Место MAX не режет: что не влезло в рюкзак, ложится на склад.
	GameState.inventory["scrap"] = 99
	GameState.inventory["iron_ore"] = 99
	check("полный рюкзак не режет MAX (99 + 23 = 122)", ShopService.max_craft("bronze") == 122)
	var pill := ""
	for o in ShopItems.recipe_offers():
		if String(o["key"]) == "recipe:bronze":
			pill = String((o["pill"] as Dictionary).get("text", ""))
	check("на плитке плавки — на сколько хватает (×122)", pill == "×122")


func _test_max_needs_workshop() -> void:
	_fresh()
	GameState.inventory["scrap"] = 10
	GameState.house_is_indoors = false
	check("вне дома MAX = 0 (верстак в доме)", ShopService.max_craft("bronze") == 0)
	var before := _snapshot()
	check("вне дома пачка не крафтится", not bool(ShopService.craft("bronze", 5)["ok"]))
	check("и ничего не тронуто", _same(before, _snapshot()))


func _test_batch_from_storage_and_pack() -> void:
	_fresh()
	GameState.inventory["scrap"] = 14
	GameState.house_storage["scrap"] = 23
	var res := ShopService.craft("bronze", 37)
	check("пачка 37 прошла", bool(res["ok"]) and int(res["count"]) == 37)
	check("металлолом списан целиком (рюкзак и склад)",
		GameState.get_item_count("scrap") == 0 and HouseStorage.count("scrap") == 0)
	check("бронза из складского лома — на складе (23)", HouseStorage.count("bronze") == 23)
	check("бронза из рюкзачного лома — в рюкзаке (14)", GameState.get_item_count("bronze") == 14)
	check("в ответе — сколько ушло сырья", int((res["used"] as Dictionary).get("scrap", 0)) == 37)
	check("событие crafted одно, с количеством 37",
		_events.size() == 1 and int(_events[0]["count"]) == 37 and String(_events[0]["recipe"]) == "bronze")
	check("в событии — раскладка 14 в рюкзак / 23 на склад",
		_events.size() == 1 and int(_events[0]["to_pack"]) == 14 and int(_events[0]["to_storage"]) == 23)

	# Часть пачки: склад тратится первым — рюкзак сохраняется под обратную дорогу.
	_fresh()
	GameState.inventory["scrap"] = 14
	GameState.house_storage["scrap"] = 23
	res = ShopService.craft("bronze", 9)
	check("пачка 9 берёт со склада, рюкзак не тронут",
		bool(res["ok"]) and HouseStorage.count("scrap") == 14 and GameState.get_item_count("scrap") == 14)
	check("и 9 бронзы легли на склад", HouseStorage.count("bronze") == 9 and GameState.get_item_count("bronze") == 0)


func _test_atomic_refusals() -> void:
	_fresh()
	GameState.inventory["scrap"] = 14
	GameState.house_storage["scrap"] = 23
	GameState.coins = 50
	var before := _snapshot()
	var res := ShopService.craft("bronze", 38)
	check("пачка больше MAX — отказ", not bool(res["ok"]) and int(res["count"]) == 0)
	check("отказ с причиной", String(res["message"]) != "")
	check("отказ ничего не списал и не выдал", _same(before, _snapshot()))
	check("отказ без события", _events.is_empty())
	check("ноль штук — отказ без изменений", not bool(ShopService.craft("bronze", 0)["ok"]) and _same(before, _snapshot()))
	check("минус штук — отказ без изменений", not bool(ShopService.craft("bronze", -3)["ok"]) and _same(before, _snapshot()))

	GameState.max_depth_reached = 1200
	GameState.inventory["iron_ore"] = 999
	GameState.inventory["bronze"] = 999
	GameState.inventory["silver"] = 999
	GameState.coins = 999999
	before = _snapshot()
	res = ShopService.craft("hand_drill", 2)
	check("разовую постройку пачкой не собрать", not bool(res["ok"]) and not GameState.owns_tool("hand_drill"))
	check("и ничего не списано", _same(before, _snapshot()))


## Рюкзак почти полон: бронза (2 кг) тяжелее лома (1 кг). Вес не превышается
## никогда — то, что не выдержит рюкзак, ложится на склад.
func _test_space_weight_spills_to_storage() -> void:
	_fresh()
	var cap := GameState.get_max_carry_kg()
	var scrap_w := Balance.get_mineral_weight("scrap")
	var bronze_w := Balance.get_mineral_weight("bronze")
	check("бронза тяжелее металлолома (иначе проверка не о том)", bronze_w > scrap_w)
	GameState.inventory["scrap"] = 20
	# Догружаем рюкзак камнем-грузом до полного.
	var ballast := "iron_ore"
	var bw := Balance.get_mineral_weight(ballast)
	GameState.inventory[ballast] = int(floor((cap - GameState.get_total_weight()) / bw))
	var free_before := cap - GameState.get_total_weight()
	var expect_pack := mini(20, int(floor((free_before + 20.0 * scrap_w) / bronze_w)))
	var res := ShopService.craft("bronze", 20)
	check("пачка на полном рюкзаке проходит целиком", bool(res["ok"]) and int(res["count"]) == 20)
	check("вес рюкзака не превышен (%.1f ≤ %.1f)" % [GameState.get_total_weight(), cap],
		GameState.get_total_weight() <= cap + 0.001)
	check("часть бронзы — в рюкзаке, остальное — на складе",
		int(res["to_pack"]) > 0 and int(res["to_storage"]) > 0
		and GameState.get_item_count("bronze") + HouseStorage.count("bronze") == 20)
	check("в рюкзак ушло ровно столько, сколько выдерживает вес (%d)" % expect_pack,
		int(res["to_pack"]) == expect_pack and GameState.get_item_count("bronze") == expect_pack)


func _test_space_stack_spills_to_storage() -> void:
	_fresh()
	# Бурмобиль добавляет грузоподъёмности: упираемся в стопку, а не в вес.
	GameState.owned_tools.append("drill_rig")
	GameState.current_tool = "drill_rig"
	var stack := Balance.get_mineral_max_stack("bronze")
	GameState.inventory["bronze"] = stack - 4
	GameState.inventory["scrap"] = 14
	var res := ShopService.craft("bronze", 14)
	check("стопка бронзы в рюкзаке не выше %d" % stack, GameState.get_item_count("bronze") == stack)
	check("лишнее сверх стопки — на склад (10)", bool(res["ok"]) and HouseStorage.count("bronze") == 10
		and int(res["to_pack"]) == 4 and int(res["to_storage"]) == 10)


## Карточка показывает раскладку до крафта — она обязана совпасть с тем, что
## крафт сделает.
func _test_plan_matches_result() -> void:
	# [лом в рюкзаке, лом на складе, сколько плавить, бронза в рюкзаке, груз-железо]
	var cases := [[14, 23, 37, 0, 0], [30, 0, 30, 0, 30], [5, 90, 60, 20, 0], [40, 40, 80, 0, 20], [40, 0, 40, 5, 0]]
	var all_ok := true
	for c in cases:
		_fresh()
		GameState.inventory["scrap"] = int(c[0])
		if int(c[1]) > 0:
			GameState.house_storage["scrap"] = int(c[1])
		if int(c[3]) > 0:
			GameState.inventory["bronze"] = int(c[3])
		if int(c[4]) > 0:
			GameState.inventory["iron_ore"] = int(c[4])
		var plan := ShopService.craft_plan("bronze", int(c[2]))
		var res := ShopService.craft("bronze", int(c[2]))
		var ok := bool(res["ok"]) and int(plan["to_pack"]) == int(res["to_pack"]) \
			and int(plan["to_storage"]) == int(res["to_storage"]) and int(plan["made"]) == int(res["count"]) \
			and GameState.get_total_weight() <= GameState.get_max_carry_kg() + 0.001
		if not ok:
			print("  расхождение: %s план %s итог %s" % [str(c), str(plan), str(res)])
		all_ok = all_ok and ok
	check("раскладка карточки = раскладка крафта (5 случаев), вес не превышен", all_ok)


func _test_single_recipes_unchanged() -> void:
	_fresh()
	GameState.inventory["scrap"] = 4
	var res := ShopService.craft("bronze")
	check("крафт без числа — одна штука, как раньше",
		bool(res["ok"]) and GameState.get_item_count("scrap") == 3 and GameState.get_item_count("bronze") == 1)

	_fresh()
	GameState.max_depth_reached = 1200
	var r := ShopCatalog.recipe("hand_drill")
	for id in (r["inputs"] as Dictionary).keys():
		GameState.house_storage[String(id)] = int(r["inputs"][id])
	GameState.coins = int(r["coins"])
	check("ручной бур: MAX = 1", ShopService.max_craft("hand_drill") == 1)
	res = ShopService.craft("hand_drill")
	check("ручной бур собран по одной", bool(res["ok"]) and GameState.owns_tool("hand_drill"))
	check("событие crafted у постройки — с количеством 1",
		_events.size() == 1 and int(_events[0]["count"]) == 1 and String(_events[0]["item"]) == "hand_drill")
	check("собранный бур: MAX = 0", ShopService.max_craft("hand_drill") == 0)


func _test_batch_persists_save_load() -> void:
	_fresh()
	GameState.inventory["scrap"] = 14
	GameState.house_storage["scrap"] = 23
	check("пачка прошла", bool(ShopService.craft("bronze", 30)["ok"]))
	var inv_b := GameState.get_item_count("bronze")
	var st_b := HouseStorage.count("bronze")
	var inv_s := GameState.get_item_count("scrap")
	# Крафт сам пишет сейв; имитация нового запуска — сброс перед загрузкой.
	GameState.inventory.clear()
	GameState.house_storage.clear()
	check("сейв загрузился", SaveSystem.load_game())
	check("после перезапуска бронза в рюкзаке и на складе та же (%d / %d)" % [inv_b, st_b],
		GameState.get_item_count("bronze") == inv_b and HouseStorage.count("bronze") == st_b)
	check("и остаток металлолома тот же (%d)" % inv_s,
		GameState.get_item_count("scrap") == inv_s and HouseStorage.count("scrap") == 0)


## Карточка рецепта: у плавки — ползунок с MAX по материалам, у бура — нет;
## галочка крафтит ровно столько, сколько стоит на ползунке.
func _test_card_slider() -> void:
	_fresh()
	Settings.reduce_motion = true
	GameState.inventory["scrap"] = 14
	GameState.house_storage["scrap"] = 23
	var ui: ShopUI = load("res://scenes/shop.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	ui.open(ShopUI.TAB_TECH)
	await get_tree().process_frame
	var t: ShopTile = ui._tiles["recipe:bronze"]
	ui._on_tile_pressed(t.offer, t)
	await get_tree().process_frame
	var box := ui._card.find_child("CraftQty", true, false) as CraftQtyBox if ui._card != null else null
	check("в карточке плавки есть ползунок", box != null)
	if box == null:
		ui.queue_free()
		return
	var slider := box.find_child("CraftQtySlider", true, false) as HSlider
	check("ползунок открылся на MAX = 37", box.max_amount() == 37 and box.amount() == 37
		and slider != null and int(slider.max_value) == 37)
	slider.value = 9
	check("ползунок двигается (9)", box.amount() == 9)
	check("на галочке «×9»", ui._craft_qty_ok != null and ui._craft_qty_ok.text == "×9")
	slider.value = 500
	check("ползунок не уходит выше MAX", box.amount() == 37)
	slider.value = 9
	ui._confirm_card()
	await get_tree().process_frame
	check("галочка сплавила ровно 9", HouseStorage.count("scrap") == 14 and HouseStorage.count("bronze") == 9
		and GameState.get_item_count("scrap") == 14)
	check("событие crafted с количеством 9", _events.size() == 1 and int(_events[-1]["count"]) == 9)
	check("карточка закрылась", ui._card == null)

	# Разовый рецепт — без ползунка.
	GameState.max_depth_reached = 1200
	GameState.inventory["iron_ore"] = 300
	GameState.inventory["bronze"] = 40
	GameState.inventory["silver"] = 60
	ui.open(ShopUI.TAB_TECH)
	await get_tree().process_frame
	t = ui._tiles["recipe:hand_drill"]
	ui._on_tile_pressed(t.offer, t)
	await get_tree().process_frame
	check("у ручного бура ползунка нет", ui._card != null and ui._card.find_child("CraftQty", true, false) == null)

	# Нечего плавить — ползунка нет, галочка выключена.
	GameState.inventory.clear()
	GameState.house_storage.clear()
	ui.open(ShopUI.TAB_TECH)
	await get_tree().process_frame
	t = ui._tiles["recipe:bronze"]
	ui._on_tile_pressed(t.offer, t)
	await get_tree().process_frame
	check("без лома ползунка нет и галочка выключена", ui._card != null
		and ui._card.find_child("CraftQty", true, false) == null and ui._card_ok.disabled)
	ui.close()
	ui.queue_free()

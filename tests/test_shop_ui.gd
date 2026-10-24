extends Node
## test_shop_ui — витрина магазина (scripts/shop/shop_*.gd): состав плиток,
## состояния, покупка через карточку подтверждения, продажа, экипировка,
## «новинка», расширение каталога данными. Без окна и звука: логика под
## тестом, а как это выглядит — смотрит test_screenshot_shop.
##
##   godot --headless --path . res://tests/test_shop_ui.tscn

var failures := 0
var total := 0
var ui: ShopUI


func _ready() -> void:
	print("=== test_shop_ui ===")
	Settings.reduce_motion = true   # без твинов: карточка и монеты появляются сразу
	_fresh()
	ui = load("res://scenes/shop.tscn").instantiate()
	add_child(ui)
	await _frames(2)

	_test_number_format()
	_test_offers_are_well_formed()
	_test_tile_states()
	_test_tiles_have_tips_and_no_text()
	await _test_buy_through_card()
	await _test_cancel_and_poor()
	await _test_recipe_card()
	await _test_card_description_by_tap()
	await _test_recipe_chips_by_tap()
	await _test_food_order()
	await _test_sell_flow()
	await _test_remote_sell()
	await _test_ads()
	await _test_equip()
	_test_new_flags()
	await _test_extension_by_data()
	await _test_empty_backpack()
	await _test_navigation()
	await _test_pointer_input()

	ui.queue_free()
	_fresh()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _fresh() -> void:
	GameState.reset_progress()
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
	GameState.house_is_indoors = true
	GameState.house_room = "workshop"
	GameState.ad_daily_counts.clear()
	GameState.house_free_orders_used_today = 0
	ShopCatalog.reload()


func _offer(tab: String, key: String) -> Dictionary:
	for o in ShopItems.offers_flat(tab):
		if String(o["key"]) == key:
			return o
	return {}


## Нажать плитку так, как нажал бы палец: сигнал pressed у самой плитки.
func _tap(key: String) -> void:
	var t: ShopTile = ui._tiles.get(key)
	check("плитка «%s» есть на экране" % key, t != null)
	if t != null:
		t.pressed.emit()


# ---------------------------------------------------------------------------

func _test_number_format() -> void:
	check("950 остаётся 950", ShopArt.compact(950) == "950")
	check("9999 без сокращения", ShopArt.compact(9999) == "9999")
	check("12345 -> 12.3K", ShopArt.compact(12345) == "12.3K")
	check("123456 -> 123K", ShopArt.compact(123456) == "123K")
	check("1234567 -> 1.23M", ShopArt.compact(1234567) == "1.23M")
	check("1000000 -> 1M без хвоста нулей", ShopArt.compact(1000000) == "1M")
	check("полное число с пробелами: 1 234 567", ShopArt.full(1234567) == "1 234 567")
	check("полное число: 0 и 999", ShopArt.full(0) == "0" and ShopArt.full(999) == "999")
	check("кошелёк до миллиона целиком", ShopUI.wallet_text(999999) == "999 999")
	check("кошелёк от миллиона сжимается", ShopUI.wallet_text(1234567) == "1.23M")


func _test_offers_are_well_formed() -> void:
	_fresh()
	GameState.max_depth_reached = 1200
	GameState.grant_tool("drill_rig")
	GameState.inventory["gold"] = 3
	GameState.inventory["bronze"] = 1
	for tab in ["food", "picks", "tech", "sell", "premium", "equip"]:
		var keys: Dictionary = {}
		var ok_fields := true
		var dup := false
		var offers := ShopItems.offers_flat(tab)
		for o in offers:
			for f in ["key", "kind", "ref", "state", "tier", "title", "extra", "pill", "effects"]:
				if not o.has(f):
					ok_fields = false
			if keys.has(o["key"]):
				dup = true
			keys[o["key"]] = true
		check("вкладка «%s»: предложения есть" % tab, not offers.is_empty())
		check("вкладка «%s»: у всех есть обязательные поля" % tab, ok_fields)
		check("вкладка «%s»: ключи не повторяются" % tab, not dup)
	check("значок есть у каждой покупаемой плитки", _all_have_icons())


func _all_have_icons() -> bool:
	for tab in ["food", "picks", "tech", "premium", "equip"]:
		for o in ShopItems.offers_flat(tab):
			if o.get("icon", null) == null:
				print("   нет значка: ", o["key"])
				return false
	return true


func _test_tile_states() -> void:
	_fresh()
	GameState.coins = 600
	check("железная кирка за 500 при 600 монетах доступна",
		String(_offer("picks", "tool:iron_pickaxe")["state"]) == "available")
	check("титановая за 1500 при 600 монетах — не хватает денег",
		String(_offer("picks", "tool:titanium_pickaxe")["state"]) == "poor")
	check("ржавая кирка (цена 0) помечена как «лежит в мастерской»",
		String(_offer("picks", "tool:rusty_pickaxe")["state"]) in ["owned", "locked"])
	GameState.grant_tool("iron_pickaxe")
	var owned := _offer("picks", "tool:iron_pickaxe")
	check("купленная кирка — состояние owned с галочкой",
		String(owned["state"]) == "owned" and String(owned["corner"]) == "check")
	check("цена не хватает — бейдж красный",
		(_offer("picks", "tool:platinum_pickaxe")["pill"]["color"] as Color).r > 0.9
		and (_offer("picks", "tool:platinum_pickaxe")["pill"]["color"] as Color).g < 0.5)
	check("в подсказке полная цена, а не сокращённая",
		String(_offer("picks", "tool:diamond_pickaxe")["extra"]).contains("20 000"))
	check("бурмобиль до глубины 1000 заперт",
		String(_offer("tech", "recipe:drill_rig")["state"]) == "locked")
	GameState.max_depth_reached = 1500
	GameState.coins = 20000
	GameState.inventory["nickel"] = 50
	GameState.inventory["platinum"] = 20
	check("бурмобиль с материалами и монетами готов к сборке",
		String(_offer("tech", "recipe:drill_rig")["state"]) == "ready")
	GameState.house_is_indoors = false
	check("вне дома рецепт «вдали от верстака»",
		String(_offer("tech", "recipe:drill_rig")["state"]) == "away")
	GameState.house_is_indoors = true
	GameState.debug_free_shop = true
	check("при debug_free_shop даже дорогая кирка доступна",
		String(_offer("picks", "tool:obsidian_pickaxe")["state"]) == "available")
	GameState.debug_free_shop = false


func _test_tiles_have_tips_and_no_text() -> void:
	_fresh()
	GameState.coins = 5000
	GameState.inventory["gold"] = 3
	GameState.inventory["geocrystal"] = 2
	var bad_tip := ""
	var bad_text := ""
	for tab in [ShopUI.TAB_FOOD, ShopUI.TAB_PICKS, ShopUI.TAB_TECH, ShopUI.TAB_SELL,
			ShopUI.SCREEN_PREMIUM, ShopUI.SCREEN_EQUIP]:
		ui.open(tab)
		for key in ui._tiles.keys():
			var t: ShopTile = ui._tiles[key]
			if not t.has_meta(Tip.META) or String((t.get_meta(Tip.META) as Dictionary).get("title", "")) == "":
				bad_tip = "%s/%s" % [tab, key]
			for l in _labels(t):
				# на плитке допустимы только числа и сокращения: 99, 12.3K, 3/3, ×2
				if l.text.length() > 8:
					bad_text = "%s/%s: «%s»" % [tab, key, l.text]
		ui.close()
	check("у каждой плитки есть подсказка Tip с названием" + (" (нет: %s)" % bad_tip if bad_tip != "" else ""), bad_tip == "")
	check("на плитках нет текста длиннее числа" + (" (%s)" % bad_text if bad_text != "" else ""), bad_text == "")


func _labels(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append(n)
	for c in n.get_children():
		out.append_array(_labels(c))
	return out


func _test_buy_through_card() -> void:
	_fresh()
	GameState.coins = 600
	ui.open(ShopUI.TAB_PICKS)
	await _frames(1)
	_tap("tool:iron_pickaxe")
	await _frames(1)
	check("тап по плитке открывает карточку, а не покупает",
		ui._card != null and not GameState.owns_tool("iron_pickaxe") and GameState.coins == 600)
	check("кнопка «купить» на карточке включена", ui._card_ok != null and not ui._card_ok.disabled)
	ui._card_ok.pressed.emit()
	await _frames(1)
	check("после галочки кирка куплена", GameState.owns_tool("iron_pickaxe"))
	check("списано ровно 500 монет", GameState.coins == 100)
	check("карточка закрылась", ui._card == null)
	check("плитка стала «куплено»",
		(ui._tiles["tool:iron_pickaxe"] as ShopTile).offer["state"] == "owned")
	ui.close()


func _test_cancel_and_poor() -> void:
	_fresh()
	GameState.coins = 600
	ui.open(ShopUI.TAB_PICKS)
	await _frames(1)
	_tap("tool:iron_pickaxe")
	await _frames(1)
	ui._close_card(false)
	await _frames(1)
	check("отмена карточки ничего не купила", not GameState.owns_tool("iron_pickaxe") and GameState.coins == 600)
	_tap("tool:titanium_pickaxe")
	await _frames(1)
	check("плитка «не хватает денег» карточку не открывает", ui._card == null)
	check("и ничего не покупает", not GameState.owns_tool("titanium_pickaxe") and GameState.coins == 600)
	GameState.coins = 600
	_tap("tool:rusty_pickaxe")
	check("плитку «куплено»/«заперто» нажать безопасно", ui._card == null)
	ui.close()


func _test_recipe_card() -> void:
	_fresh()
	GameState.max_depth_reached = 200
	GameState.coins = 3000
	GameState.inventory["iron_ore"] = 500
	GameState.inventory["silver"] = 50
	GameState.inventory["bronze"] = 100
	ui.open(ShopUI.TAB_TECH)
	await _frames(1)
	var o := _offer("tech", "recipe:hand_drill")
	check("рецепт бура готов к сборке", String(o["state"]) == "ready")
	check("в предложении рецепта есть материалы значками",
		(o["inputs"] as Array).size() == 3 and int(o["coins_need"]) == 2000)
	_tap("recipe:hand_drill")
	await _frames(1)
	check("карточка рецепта открылась", ui._card != null)
	ui._card_ok.pressed.emit()
	await _frames(1)
	check("бур собран", GameState.owns_tool("hand_drill"))
	check("материалы и монеты списаны", GameState.coins == 1000 and GameState.get_item_count("iron_ore") == 0)
	# нехватка материалов: карточка всё равно показывает, чего нет, но «собрать» выключена
	GameState.owned_tools = ["shovel"]
	GameState.inventory.clear()
	GameState.coins = 3000
	ui._render()
	_tap("recipe:hand_drill")
	await _frames(1)
	check("при нехватке материалов карточка открывается, но «собрать» выключена",
		ui._card != null and ui._card_ok.disabled)
	ui._close_card(false)
	ui.close()


## Узлы карточки с описанием по тапу (Tip.bind_tap), в порядке обхода.
func _tap_targets() -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [ui._card]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and n.has_meta(Tip.TAP_META):
			out.append(n)
		for c in n.get_children():
			stack.push_back(c)
	out.reverse()
	return out


## Тап, как его видит контрол: нажатие и отпускание в gui_input, а у кнопки
## ещё и pressed (сам BaseButton из gui_input.emit не срабатывает).
func _click(c: Control) -> void:
	var at := Vector2(4, 4)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		c.gui_input.emit(e)
	if c is BaseButton:
		(c as BaseButton).pressed.emit()


## Тап по значку товара в карточке подтверждения раскрывает описание и ничего
## не покупает; кнопки «купить/отмена» остаются главными.
func _test_card_description_by_tap() -> void:
	_fresh()
	Tip.hide_all()
	GameState.coins = 600
	ui.open(ShopUI.TAB_PICKS)
	await _frames(1)
	_tap("tool:iron_pickaxe")
	await _frames(2)
	var offer := _offer("picks", "tool:iron_pickaxe")
	var targets := _tap_targets()
	check("в карточке покупки есть значки, раскрывающиеся тапом", targets.size() >= 1)
	var icon: Control = targets[0]
	check("главный значок — плитка товара крупнее 22 точек", icon is ShopTile and icon.size.x >= 22.0 and icon.size.y >= 22.0)
	check("на значке есть подсказка-намёк «i»", icon.get_child_count() > 0 and icon.get_child(icon.get_child_count() - 1) is TextureRect \
		and (icon.get_child(icon.get_child_count() - 1) as TextureRect).texture != null)
	check("кнопка «купить» не привязана к тапу-описанию (она покупает)", not ui._card_ok.has_meta(Tip.TAP_META))
	check("пока никто не тапнул, описания нет", not Tip.is_showing())

	_click(icon)
	check("тап по значку раскрывает описание", Tip.is_pinned())
	check("в нём название, эффект и цена из предложения",
		Tip._title.text == String(offer["title"]) and Tip._body.text == String(offer["body"])
		and Tip._extra.text == String(offer["extra"]) and Tip._title.text != "")
	check("тап не покупает и не закрывает карточку",
		ui._card != null and not GameState.owns_tool("iron_pickaxe") and GameState.coins == 600)
	check("тап не включает swallowed(): кнопки работают", not Tip.swallowed())
	var rect := Tip._panel.get_global_rect()
	var card_rect := ui._card_panel.get_global_rect()
	check("описание над карточкой: не закрывает ни значок, ни кнопки", rect.end.y <= card_rect.position.y + 0.5)
	var vp := ui.get_viewport().get_visible_rect().grow(0.5)
	check("описание целиком в окне", vp.encloses(rect))
	check("запомнили, что игрок знает про тап", bool((GameState.ext_get(ShopUI.CARD_INFO_KEY, {}) as Dictionary).get("tapped", false)))

	_click(icon)
	check("повторный тап скрывает описание", not Tip.is_showing())
	check("карточка при этом на месте", ui._card != null)

	# Тап вне: сперва гаснет только описание, окно остаётся.
	_click(icon)
	var dim: ColorRect = ui._card.get_child(0)
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	outside.position = Vector2(200, 12)
	Tip._on_global_input(outside)
	dim.gui_input.emit(outside)
	check("тап вне прячет описание", not Tip.is_showing())
	check("и тот же тап не закрывает карточку", ui._card != null)
	Tip._dismissed_until_ms = 0
	dim.gui_input.emit(outside)
	await _frames(1)
	check("следующий тап по фону закрывает карточку как раньше", ui._card == null)

	# Отмена и покупка при открытом описании работают как раньше.
	_tap("tool:iron_pickaxe")
	await _frames(2)
	_click(_tap_targets()[0])
	check("описание открыто", Tip.is_pinned())
	ui._close_card(false)
	check("закрытие карточки уносит описание", not Tip.is_showing())
	_tap("tool:iron_pickaxe")
	await _frames(2)
	_click(_tap_targets()[0])
	Tip._swallow_until_ms = Time.get_ticks_msec() + 250
	ui._card_ok.pressed.emit()
	check("защита от случайной покупки жива: swallowed() не даёт купить", not GameState.owns_tool("iron_pickaxe"))
	Tip._swallow_until_ms = 0
	ui._card_ok.pressed.emit()
	await _frames(1)
	check("«купить» при открытом описании покупает", GameState.owns_tool("iron_pickaxe") and GameState.coins == 100)
	check("после покупки описания нет", not Tip.is_showing() and ui._card == null)
	ui.close()


## Значки материалов рецепта: тап — название и сколько есть.
func _test_recipe_chips_by_tap() -> void:
	_fresh()
	Tip.hide_all()
	GameState.max_depth_reached = 200
	GameState.coins = 900
	GameState.inventory["iron_ore"] = 300
	GameState.inventory["bronze"] = 40
	GameState.inventory["silver"] = 60
	ui.open(ShopUI.TAB_TECH)
	await _frames(1)
	_tap("recipe:hand_drill")
	await _frames(2)
	var o := _offer("tech", "recipe:hand_drill")
	var targets := _tap_targets()
	var inputs: Array = o["inputs"]
	check("у рецепта тапабельны значок товара, чипы эффекта и каждый материал (+ монеты)",
		targets.size() >= inputs.size() + 1 + 1)
	var chips: Array[Control] = []
	for t in targets:
		if not (t is ShopTile) and String((t.get_meta(Tip.META) as Dictionary).get("body", "")).begins_with("Есть:"):
			chips.append(t)
	check("значков материалов: по числу материалов и монеты", chips.size() == inputs.size() + 1)
	var all_big := true
	for c in chips:
		all_big = all_big and c.size.y >= 22.0 and c.custom_minimum_size.y >= 22.0
	check("цель нажатия каждого значка материала не ниже 22 точек", all_big)
	var first: Control = chips[0]
	var first_input: Dictionary = inputs[0]
	_click(first)
	check("тап по материалу раскрывает описание", Tip.is_pinned())
	check("название — название предмета", Tip._title.text == ShopCatalog.item_name(String(first_input["id"])))
	check("в описании «есть из нужно» полными числами",
		Tip._body.text == "Есть: %s из %s" % [ShopArt.full(int(first_input["have"])), ShopArt.full(int(first_input["need"]))])
	check("тап по материалу ничего не собирает", not GameState.owns_tool("hand_drill") and GameState.coins == 900 and ui._card != null)
	check("и не включает swallowed()", not Tip.swallowed())
	_click(chips[1])
	check("тап по соседнему материалу переносит описание на него", Tip.is_pinned() and Tip._owner_ctrl == chips[1])
	_click(chips[1])
	check("повторный тап по нему скрывает", not Tip.is_showing())
	var coins_chip: Control = chips[chips.size() - 1]
	_click(coins_chip)
	check("монеты: «Монеты» и сколько есть", Tip._title.text == "Монеты" and Tip._body.text == "Есть: 900 из 2 000")
	Tip.hide_all()
	ui._close_card(false)
	ui.close()


func _test_food_order() -> void:
	_fresh()
	GameState.coins = 0
	ui.open(ShopUI.TAB_FOOD)
	await _frames(1)
	var free_before := HouseFood.free_orders_left()
	check("в начале дня есть бесплатные заказы", free_before > 0)
	_tap("food:food_bar")
	await _frames(1)
	check("заказ тоже идёт через карточку", ui._card != null)
	ui._card_ok.pressed.emit()
	await _frames(1)
	check("бесплатный заказ списал одну бесплатную порцию", HouseFood.free_orders_left() == free_before - 1)
	GameState.house_free_orders_used_today = HouseConfig.free_orders_per_day()
	GameState.coins = 10
	ui._render()
	check("без бесплатных и без денег еда «не хватает денег»",
		String(_offer("food", "food:food_bar")["state"]) == "poor")
	ui.close()


func _test_sell_flow() -> void:
	_fresh()
	GameState.inventory["gold"] = 3
	GameState.inventory["lead"] = 9
	GameState.inventory["bronze"] = 2
	ui.open(ShopUI.TAB_SELL)
	await _frames(1)
	check("в продаже две стопки, бронза отдельно (не скупается)",
		ui._tiles.has("sell:gold") and ui._tiles.has("sell:lead") and ui._tiles.has("nosale:bronze"))
	var gold_sum := int(_offer("sell", "sell:gold")["sum"])
	var lead_sum := int(_offer("sell", "sell:lead")["sum"])
	check("по умолчанию отмечено всё", ui._selection_items().size() == 2)
	_tap("sell:lead")
	check("тап по плитке снимает стопку с продажи", ui._selection_items().size() == 1 and not ui._selection_items().has("lead"))
	check("итог на кнопке пересчитан", ui._sell_label.text == ShopArt.full(gold_sum))
	_tap("nosale:bronze")
	check("нескупаемую плитку нажать безопасно", GameState.get_item_count("bronze") == 2)
	ui._sell_btn.pressed.emit()
	await get_tree().create_timer(1.3).timeout
	check("продано только выбранное: монеты = сумма золота", GameState.coins == gold_sum)
	check("золото ушло, свинец остался", GameState.get_item_count("gold") == 0 and GameState.get_item_count("lead") == 9)
	check("в шапке итоговые монеты", ui._chips["coins"]["label"].text == ShopUI.wallet_text(gold_sum))
	check("после продажи вкладка перерисована без проданного", not ui._tiles.has("sell:gold") and ui._tiles.has("sell:lead"))
	check("busy снят", not ui._busy)
	# удвоение рекламой
	GameState.coins = 0
	GameState.next_sale_doubled = true
	ui._render()
	check("с роликом ×2 на кнопке удвоенная сумма", ui._sell_label.text == ShopArt.full(lead_sum * 2) and ui._sell_x2.visible)
	ui._on_sell_pressed()
	await get_tree().create_timer(1.3).timeout
	check("выручка удвоена", GameState.coins == lead_sum * 2 and not GameState.next_sale_doubled)
	ui.close()


func _test_remote_sell() -> void:
	_fresh()
	GameState.house_is_indoors = false
	GameState.inventory["gold"] = 2
	ui.open(ShopUI.TAB_SELL)
	await _frames(1)
	check("вне дома продажа — режим «ролик»", ui._footer_mode == "remote")
	check("плитки вне дома без отметок (это прайс-лист)", not (ui._tiles["sell:gold"] as ShopTile).offer.has("selected"))
	var left := ShopService.ad_uses_left("remote_dump_loot_for_sale")
	ui._on_sell_pressed()
	await get_tree().create_timer(1.3).timeout
	check("дистанционная сдача продала всё и потратила один ролик",
		GameState.get_item_count("gold") == 0 and ShopService.ad_uses_left("remote_dump_loot_for_sale") == left - 1)
	ui.close()


func _test_ads() -> void:
	_fresh()
	ui.open(ShopUI.TAB_FOOD)
	await _frames(1)
	var left := ShopService.ad_uses_left("small_coins")
	_tap("ad:small_coins")
	await _frames(1)
	check("ролик за монеты выдал награду", GameState.coins == 1000)
	check("ролик потратил одно использование", ShopService.ad_uses_left("small_coins") == left - 1)
	ui.close()
	GameState.ad_daily_counts["double_income_on_sale"] = 0
	GameState.inventory["gold"] = 1
	ui.open(ShopUI.TAB_SELL)
	await _frames(1)
	ui._ad_btn.pressed.emit()
	check("кнопка ×2 включает удвоение следующей продажи", GameState.next_sale_doubled)
	ui.close()


func _test_equip() -> void:
	_fresh()
	GameState.grant_tool("iron_pickaxe")
	GameState.grant_gear("backpack")
	GameState.grant_gear("backpack_plus")
	GameState.set_current_tool("rusty_pickaxe")
	ui.open(ShopUI.SCREEN_EQUIP)
	await _frames(1)
	check("надетая кирка подсвечена (active)", String(_offer("equip", "equip_tool:rusty_pickaxe")["state"]) == "active")
	check("ненайденная кирка заперта", String(_offer("equip", "equip_tool:obsidian_pickaxe")["state"]) == "locked")
	_tap("equip_tool:iron_pickaxe")
	await _frames(1)
	check("тап по купленной кирке берёт её в руки", GameState.current_tool == "iron_pickaxe")
	check("подсветка переехала",
		String((ui._tiles["equip_tool:iron_pickaxe"] as ShopTile).offer["state"]) == "active")
	_tap("equip_gear:backpack_plus")
	await _frames(1)
	check("тап по ранцу надевает его", GameState.current_gear == "backpack_plus")
	_tap("equip_tool:obsidian_pickaxe")
	check("заперто — не надевается", GameState.current_tool == "iron_pickaxe")
	ui.close()
	GameState.house_is_indoors = false
	ui.open(ShopUI.SCREEN_EQUIP)
	await _frames(1)
	check("вне мастерской плитки «вдали от верстака»",
		String(_offer("equip", "equip_tool:iron_pickaxe")["state"]) == "active"
		and String(_offer("equip", "equip_tool:rusty_pickaxe")["state"]) == "away"
		and String(_offer("equip", "equip_gear:backpack")["state"]) == "away")
	_tap("equip_gear:backpack")
	check("вне мастерской переодеться нельзя", GameState.current_gear == "backpack_plus")
	ui.close()


func _test_new_flags() -> void:
	_fresh()
	ShopItems.seed_seen()
	check("у нового игрока витрина без «новинок»", ShopItems.new_count("picks") == 0 and ShopItems.new_count("food") == 0)
	GameState.max_depth_reached = 150
	check("рецепт, открывшийся по глубине, — новинка", ShopItems.new_count("tech") > 0)
	check("новинка светится на плитке", bool(_offer("tech", "recipe:hand_drill")["new"]))
	ShopItems.mark_seen(ShopItems.new_keys("tech"))
	check("увиденное больше не новинка", ShopItems.new_count("tech") == 0)
	var saved: Dictionary = GameState.ext_get("shop", {})
	check("список виденного лежит в GameState.ext под ключом shop", (saved.get("seen", []) as Array).size() > 0)


func _test_extension_by_data() -> void:
	_fresh()
	GameState.coins = 100
	GameState.max_depth_reached = 50
	# Другая ветка добавляет товар только данными: ни строки кода в UI.
	var extra: Array = ShopCatalog.data()["goods_coins"]["extra"]
	extra.append({
		"id": "test_fuel_can", "name_ru": "Канистра", "desc_ru": "Топливо", "shelf": "picks",
		"icon": "res://art/ui/shop/item_fuel_block.png", "tier": 2,
		"effect": "grant_item", "item": "peat", "count": 2,
		"price_coins": 30, "unlock_depth": 100,
		"effects": [{"icon": "glyph_fly", "text": "+2"}],
	})
	var o := _offer("picks", "good:coins:test_fuel_can")
	check("товар из данных появился на указанной полке", not o.is_empty())
	check("до глубины открытия товар заперт", String(o.get("state", "")) == "locked")
	GameState.max_depth_reached = 100
	o = _offer("picks", "good:coins:test_fuel_can")
	check("после открытия доступен", String(o["state"]) == "available")
	check("значок и ступень рамки взяты из записи", o["icon"] != null and int(o["tier"]) == 2)
	check("чипы эффекта из записи", (o["effects"] as Array).size() == 1 and String(o["effects"][0]["text"]) == "+2")
	ui.open(ShopUI.TAB_PICKS)
	await _frames(1)
	_tap("good:coins:test_fuel_can")
	await _frames(1)
	ui._card_ok.pressed.emit()
	await _frames(1)
	check("покупка по записи выдала предмет в рюкзак", GameState.get_item_count("peat") == 2 and GameState.coins == 70)
	ui.close()
	extra.pop_back()
	ShopCatalog.reload()


func _test_empty_backpack() -> void:
	_fresh()
	ui.open(ShopUI.TAB_SELL)
	await _frames(1)
	check("пустой рюкзак: на вкладке есть картинка-заглушка", ui._list.get_child_count() > 0)
	check("кнопка продажи выключена", ui._sell_btn.disabled)
	check("итог 0", ui._sell_label.text == "0")
	ui.close()


func _test_navigation() -> void:
	_fresh()
	ui.open(ShopUI.TAB_FOOD)
	await _frames(1)
	for tab in ShopUI.NAV_TABS:
		ui._tab_buttons[tab].pressed.emit()
		await _frames(1)
		check("вкладка «%s» открывается" % tab, ui._tab == tab and ui._list.get_child_count() > 0)
	check("панель продажи видна только на «Продать»",
		not ui._action.visible)
	ui._tab_buttons[ShopUI.TAB_SELL].pressed.emit()
	await _frames(1)
	check("на «Продать» панель продажи видна", ui._action.visible)
	check("прокрутка перетаскиванием подключена", ui._scroll.get_node_or_null("DragScroll") != null)
	ui.open(ShopUI.SCREEN_EQUIP)
	check("на экране верстака вкладок нет, есть кнопка «готово»", not ui._nav_tabs.visible and ui._nav_done.visible)
	ui.open(ShopUI.TAB_FOOD)
	check("вкладки возвращаются", ui._nav_tabs.visible and not ui._nav_done.visible)
	ui.close()
	check("шторка закрывается", not ui.is_open())


## Настоящие события указателя: тап покупает через карточку, перетаскивание
## (прокрутка) и долгое нажатие (подсказка) — нет.
func _test_pointer_input() -> void:
	# В headless окно 64×64, и события указателя до интерфейса не доходят —
	# проверка работает только под настоящим рендером (xvfb-run, см. шапку
	# test_screenshot_shop), в run_tests.sh она честно пропускается. Запуск руками:
	# окно 1:1 (--resolution 224x480): push_input берёт оконные координаты, а плитки
	# считаются в логических, при окне 448×960 они разъедутся вдвое.
	if DisplayServer.get_name() == "headless":
		print("[--] события указателя: headless, проверка пропущена")
		return
	_fresh()
	GameState.coins = 600
	ui.open(ShopUI.TAB_PICKS)
	await _frames(3)
	var t: ShopTile = ui._tiles["tool:iron_pickaxe"]
	var pos := t.get_global_rect().get_center()

	_motion(pos, Vector2.ZERO)
	await _frames(1)
	_mouse(pos, true)
	await _frames(1)
	_mouse(pos, false)
	await _frames(2)
	check("короткий тап пальцем открывает карточку", ui._card != null)
	ui._close_card(false)
	await _frames(2)

	_mouse(pos, true)
	await _frames(1)
	for i in range(1, 6):
		_motion(pos + Vector2(0, 8.0 * i), Vector2(0, 8))
		await _frames(1)
	_mouse(pos + Vector2(0, 40), false)
	await _frames(2)
	check("перетаскивание по плитке — прокрутка, карточка не открывается", ui._card == null)
	check("и ничего не куплено", not GameState.owns_tool("iron_pickaxe") and GameState.coins == 600)

	_mouse(pos, true)
	await get_tree().create_timer(0.6).timeout
	var tip_shown := Tip.is_showing()
	_mouse(pos, false)
	await _frames(2)
	check("долгое нажатие показывает подсказку", tip_shown)
	check("долгое нажатие не открывает карточку и не покупает", ui._card == null and not GameState.owns_tool("iron_pickaxe"))
	Tip.hide_all()

	# Описание в карточке — по обычному тапу (настоящий указатель, не только gui_input).
	await get_tree().create_timer(0.35).timeout   # swallowed() после долгого нажатия гаснет за 0.25 с
	_mouse(pos, true)
	await _frames(1)
	_mouse(pos, false)
	await _frames(2)
	var icon: Control = _tap_targets()[0]
	var ipos := icon.get_global_rect().get_center()
	_mouse(ipos, true)
	await _frames(1)
	_mouse(ipos, false)
	await _frames(2)
	check("тап пальцем по значку в карточке раскрывает описание", Tip.is_pinned() and ui._card != null)
	check("и ничего не покупает", not GameState.owns_tool("iron_pickaxe") and GameState.coins == 600)
	_mouse(ipos, true)
	await _frames(1)
	_mouse(ipos, false)
	await _frames(2)
	check("повторный тап пальцем скрывает его", not Tip.is_showing() and ui._card != null)
	_mouse(ipos, true)
	await _frames(1)
	_mouse(ipos, false)
	await _frames(2)
	var away := Vector2(200.0, 12.0)
	_mouse(away, true)
	await _frames(1)
	_mouse(away, false)
	await _frames(2)
	check("тап мимо гасит описание, но не закрывает карточку", not Tip.is_showing() and ui._card != null)
	await get_tree().create_timer(0.4).timeout
	_mouse(away, true)
	await _frames(1)
	_mouse(away, false)
	await _frames(3)
	check("следующий тап по фону закрывает карточку", ui._card == null)
	Tip.hide_all()
	ui.close()


func _mouse(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(e)


func _motion(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e)

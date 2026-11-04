extends Node
## test_bronze_timer — печь бронзы (BronzeFurnace): слово владельца «бронза
## делается со скоростью минута штука» (разбор чисел, 26.10).
##
## Очередь и отсчёт, N штук — N минут, время вне игры и защита от отмотки часов,
## сейв/загрузка и старые сейвы, отмена с возвратом лома туда, откуда он пришёл,
## забор готового дома (рюкзак/склад по правилу craft_plan), карточка рецепта с
## ползунком на N штук и печью (FurnaceBox), отсчёт на плитке, цепочка «Проекты»
## и ручной бур из бронзы, выплавленной в печи. Часы печи подменены
## (BronzeFurnace.override_unix): тест не ждёт настоящих минут.
##
##   godot --headless --path . res://tests/test_bronze_timer.tscn

const T0 := 1_800_000_000

var failures := 0
var total := 0
var _events: Array = []


func _ready() -> void:
	print("=== test_bronze_timer ===")
	GameState.reset_progress()
	GameState.game_event.connect(func(id: StringName, data: Dictionary) -> void:
		if id == &"crafted" or id == &"smelt_started" or id == &"smelt_cancelled":
			var d := data.duplicate()
			d["_id"] = String(id)
			_events.append(d))

	_test_number_in_data()
	_test_queue_and_countdown()
	_test_collect_where_it_lands()
	_test_append_while_busy()
	_test_cancel_refunds_unstarted()
	_test_offline_and_clock()
	_test_save_load_and_old_saves()
	_test_project_chain_counts_furnace()
	_test_hand_drill_from_smelted_bronze()
	await _test_card_slider_and_furnace_box()

	BronzeFurnace.override_unix = -1
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


## Дома, в мастерской, пустые рюкзак, склад и печь, часы печи на T0.
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
	GameState.house_room = "workshop"
	GameState.ext.erase(BronzeFurnace.KEY)
	BronzeFurnace.override_unix = T0
	_events.clear()


func _at(dt: int) -> void:
	BronzeFurnace.override_unix = T0 + dt


func _count(id: String) -> int:
	return _events.filter(func(e: Dictionary) -> bool: return String(e["_id"]) == id).size()


# ---------------------------------------------------------------------------

func _test_number_in_data() -> void:
	var raw = Balance.balance.get("crafting", {}).get("seconds_per_bronze", null)
	check("balance.json → crafting.seconds_per_bronze — обёртка {value, proposed, note}",
		typeof(raw) == TYPE_DICTIONARY and raw.has("value") and raw.has("note"))
	check("число владельца: 60 секунд, proposed: false",
		typeof(raw) == TYPE_DICTIONARY and int(raw["value"]) == 60 and raw.get("proposed", true) == false)
	check("код читает его через Balance.unwrap (60)", BronzeFurnace.seconds_per_unit() == int(Balance.unwrap(raw)))
	check("в рецепте бронзы — секунды на штуку", int(ShopCatalog.recipe("bronze").get("seconds", 0)) == 60)
	check("бронза по-прежнему переработка с ползунком", ShopService.is_batch("bronze"))
	check("отсчёт пишется по-человечески", BronzeFurnace.clock_text(42) == "0:42"
		and BronzeFurnace.clock_text(605) == "10:05" and BronzeFurnace.clock_text(3723) == "1:02:03")


func _test_queue_and_countdown() -> void:
	_fresh()
	var per := BronzeFurnace.seconds_per_unit()
	GameState.inventory["scrap"] = 3
	GameState.house_storage["scrap"] = 5
	var res := ShopService.craft("bronze", 6)
	check("загрузка 6 штук прошла", bool(res["ok"]) and bool(res.get("timed", false)))
	check("готового сразу нет (count 0), в очереди 6", int(res["count"]) == 0 and int(res["queued"]) == 6
		and BronzeFurnace.queued() == 6 and BronzeFurnace.ready_count() == 0)
	check("лом списан при загрузке: склад первым (5), из рюкзака 1",
		HouseStorage.count("scrap") == 0 and GameState.get_item_count("scrap") == 2)
	check("бронзы нигде нет", GameState.get_item_count("bronze") == 0 and HouseStorage.count("bronze") == 0)
	check("событие smelt_started, а crafted — нет", _count("smelt_started") == 1 and _count("crafted") == 0)
	check("отсчёт: следующая через минуту, вся очередь — 6 минут",
		BronzeFurnace.next_in() == per and BronzeFurnace.all_in() == 6 * per)
	_at(25)
	check("через 25 с: следующая через 35 с, полоска на 25/60",
		BronzeFurnace.next_in() == per - 25 and is_equal_approx(BronzeFurnace.unit_progress(), 25.0 / per))
	check("запросы не пишут сейв печи (отметка та же)",
		int((GameState.ext[BronzeFurnace.KEY] as Dictionary)["at"]) == T0)
	_at(per)
	check("через минуту: одна готова, 5 в очереди, снова минута",
		BronzeFurnace.ready_count() == 1 and BronzeFurnace.queued() == 5 and BronzeFurnace.next_in() == per)
	_at(6 * per - 1)
	check("за секунду до шести минут — одна ещё плавится", BronzeFurnace.queued() == 1 and BronzeFurnace.ready_count() == 5)
	_at(6 * per)
	check("N штук — N минут: через 6 минут готово 6, печь пуста",
		BronzeFurnace.queued() == 0 and BronzeFurnace.ready_count() == 6 and BronzeFurnace.next_in() == 0)
	_at(100 * per)
	check("пустая печь не плавит лишнего", BronzeFurnace.ready_count() == 6)


func _test_collect_where_it_lands() -> void:
	# Продолжение: 5 штук из складского лома, 1 — из рюкзачного.
	GameState.house_is_indoors = false
	var away := BronzeFurnace.collect()
	check("вдали от дома готовое не забирается", int(away["count"]) == 0 and BronzeFurnace.ready_count() == 6)
	GameState.house_is_indoors = true
	var got := BronzeFurnace.collect()
	check("дома забирается всё (6)", int(got["count"]) == 6 and BronzeFurnace.ready_count() == 0)
	check("складской лом → склад (5), рюкзачный → рюкзак (1) — правило мгновенного крафта",
		HouseStorage.count("bronze") == 5 and GameState.get_item_count("bronze") == 1
		and int(got["to_storage"]) == 5 and int(got["to_pack"]) == 1)
	check("событие crafted одно, с раскладкой", _count("crafted") == 1
		and int(_events[-1]["count"]) == 6 and int(_events[-1]["to_pack"]) == 1 and int(_events[-1]["to_storage"]) == 5)
	check("повторный забор пустой", int(BronzeFurnace.collect()["count"]) == 0 and _count("crafted") == 1)

	# Рюкзак полон к возвращению: рюкзачная бронза ложится на склад.
	_fresh()
	GameState.inventory["scrap"] = 10
	check("загрузка 10 из рюкзака", bool(ShopService.craft("bronze", 10)["ok"]))
	# За ходку рюкзак забили рудой: места осталось примерно на 4 бронзы.
	var ballast := "iron_ore"
	var bronze_w := Balance.get_mineral_weight("bronze")
	GameState.inventory[ballast] = int(floor((GameState.get_max_carry_kg() - GameState.get_total_weight()
		- 4.0 * bronze_w) / Balance.get_mineral_weight(ballast)))
	var free := GameState.get_max_carry_kg() - GameState.get_total_weight()
	var fits := mini(10, int(floor(free / bronze_w)))
	_at(10 * BronzeFurnace.seconds_per_unit())
	got = BronzeFurnace.collect()
	check("почти полный рюкзак: в рюкзак сколько влезло (%d из 10), остальное на склад" % fits,
		fits > 0 and fits < 10 and int(got["to_pack"]) == fits and HouseStorage.count("bronze") == 10 - fits
		and GameState.get_total_weight() <= GameState.get_max_carry_kg() + 0.001)


func _test_append_while_busy() -> void:
	_fresh()
	var per := BronzeFurnace.seconds_per_unit()
	GameState.house_storage["scrap"] = 10
	ShopService.craft("bronze", 2)
	_at(30)
	check("догрузка в работающую печь", bool(ShopService.craft("bronze", 3)["ok"]))
	check("очередь 5, штука в работе не начата заново (30 с)",
		BronzeFurnace.queued() == 5 and BronzeFurnace.next_in() == per - 30)
	check("вся очередь — 4.5 минуты", BronzeFurnace.all_in() == per - 30 + 4 * per)
	_at(5 * per)
	check("через 5 минут от первой загрузки — все 5 готовы", BronzeFurnace.ready_count() == 5)
	# Догрузка в пустую печь — отсчёт с момента загрузки, а не со старой отметки.
	BronzeFurnace.collect()
	_at(20 * per)
	ShopService.craft("bronze", 1)
	check("пустая печь стартует с загрузки (минута, а не «уже готово»)",
		BronzeFurnace.queued() == 1 and BronzeFurnace.next_in() == per)


func _test_cancel_refunds_unstarted() -> void:
	_fresh()
	var per := BronzeFurnace.seconds_per_unit()
	GameState.inventory["scrap"] = 6
	GameState.house_storage["scrap"] = 4
	ShopService.craft("bronze", 10)   # 4 штуки из складского лома, 6 — из рюкзачного
	_at(per + 20)   # одна готова, вторая плавится 20 с
	GameState.house_is_indoors = false
	var res := BronzeFurnace.cancel()
	check("вдали от дома отменить нельзя", not bool(res["ok"]) and BronzeFurnace.queued() == 9)
	GameState.house_is_indoors = true
	res = BronzeFurnace.cancel()
	check("отмена вернула лом за 8 не начатых", bool(res["ok"]) and int(res["refunded"]) == 8)
	check("штука в работе осталась и доплавляется (40 с)",
		BronzeFurnace.queued() == 1 and BronzeFurnace.next_in() == per - 20 and BronzeFurnace.ready_count() == 1)
	check("лом вернулся туда, откуда пришёл: рюкзак 6, склад 2",
		GameState.get_item_count("scrap") == 6 and HouseStorage.count("scrap") == 2)
	check("событие smelt_cancelled", _count("smelt_cancelled") == 1 and int(_events[-1]["count"]) == 8)
	check("одну штуку в работе отменять нечего", not bool(BronzeFurnace.cancel()["ok"]))
	_at(2 * per)
	BronzeFurnace.collect()
	check("итог: 2 бронзы со склада, лом 8 — ничего не пропало",
		HouseStorage.count("bronze") == 2 and GameState.get_item_count("scrap") + HouseStorage.count("scrap") == 8)


func _test_offline_and_clock() -> void:
	_fresh()
	var per := BronzeFurnace.seconds_per_unit()
	GameState.house_storage["scrap"] = 30
	ShopService.craft("bronze", 30)
	# Игра закрыта (часы печи шли без неё) — как у скважины, по unix-времени.
	_at(17 * per + 5)
	check("время вне игры засчитано: 17 готово, 13 в очереди", BronzeFurnace.ready_count() == 17
		and BronzeFurnace.queued() == 13 and BronzeFurnace.next_in() == per - 5)
	BronzeFurnace.advance()
	# Часы телефона отмотали назад: печь не плавит «в минус» и ничего не теряет.
	_at(10 * per)
	check("отмотка часов назад: не плавится и не откатывается", BronzeFurnace.ready_count() == 17
		and BronzeFurnace.queued() == 13)
	_at(17 * per + 5 + 2 * per)
	check("часы вернулись — плавка идёт дальше", BronzeFurnace.ready_count() == 19)
	BronzeFurnace.advance()
	# Давняя отмотка (больше двух суток) прощается, иначе печь стояла бы до старой отметки.
	_at(-3 * 86400)
	BronzeFurnace.advance()
	_at(-3 * 86400 + per)
	check("после давней отмотки печь снова плавит", BronzeFurnace.ready_count() == 20 and BronzeFurnace.queued() == 10)


func _test_save_load_and_old_saves() -> void:
	_fresh()
	var per := BronzeFurnace.seconds_per_unit()
	GameState.inventory["scrap"] = 4
	GameState.house_storage["scrap"] = 6
	ShopService.craft("bronze", 10)   # сам пишет сейв
	_at(3 * per)
	BronzeFurnace.advance()
	SaveSystem.save_game()
	# Новый запуск через час: состояние из сейва, время вне игры доплавляет.
	GameState.ext.erase(BronzeFurnace.KEY)
	check("сброс перед загрузкой — печь пуста", BronzeFurnace.queued() == 0)
	check("сейв загрузился", SaveSystem.load_game())
	_at(3 * per + 3600)
	check("после загрузки и часа вне игры — все 10 готовы", BronzeFurnace.ready_count() == 10
		and BronzeFurnace.queued() == 0)
	BronzeFurnace.collect()
	check("и легли по правилу (6 склад, 4 рюкзак)", HouseStorage.count("bronze") == 6
		and GameState.get_item_count("bronze") == 4)

	# Старый сейв без печи грузится без ошибок: печь пуста, бронза как была.
	_fresh()
	GameState.house_storage["bronze"] = 7
	SaveSystem.save_game()
	GameState.house_storage.clear()
	check("старый сейв (без печи) загрузился", SaveSystem.load_game())
	check("печь пуста, бронза на складе та же", not BronzeFurnace.is_busy() and HouseStorage.count("bronze") == 7)
	check("забор из пустой печи ничего не делает", int(BronzeFurnace.collect()["count"]) == 0)

	# JSON отдаёт числа float; битая форма — пустая печь, а не падение.
	GameState.ext[BronzeFurnace.KEY] = {"qs": 3.0, "qp": 0.0, "at": float(T0), "rs": 1.0, "rp": 0.0}
	_at(per)
	check("числа float из JSON читаются (3 в очереди → 1 готова через минуту)",
		BronzeFurnace.queued() == 2 and BronzeFurnace.ready_count() == 2)
	GameState.ext[BronzeFurnace.KEY] = "мусор"
	check("битая запись — пустая печь", BronzeFurnace.queued() == 0 and BronzeFurnace.ready_count() == 0)
	GameState.ext[BronzeFurnace.KEY] = {"qs": "x", "at": -5}
	check("битые поля — нули", not BronzeFurnace.is_busy())


func _test_project_chain_counts_furnace() -> void:
	_fresh()
	GameState.max_depth_reached = 150
	var need := int(ShopCatalog.recipe("hand_drill")["inputs"]["bronze"])
	GameState.house_storage["scrap"] = need - 10
	var before := ProjectChain.material("bronze", need)
	ShopService.craft("bronze", need - 10)
	var m := ProjectChain.material("bronze", need)
	check("лом в печи — уже почти бронза: полоска проекта не падает",
		int(m["effective"]) == int(before["effective"]) and int(m["smelting"]) == need - 10 and not bool(m["done"]))
	var scrap_need := 0
	for e in ProjectChain.needed_for("scrap"):
		if String(e["project"]) == "hand_drill":
			scrap_need = int(e["need"])
	check("«нужно для» просит лом только сверх печи (10)", scrap_need == 10)


func _test_hand_drill_from_smelted_bronze() -> void:
	_fresh()
	GameState.max_depth_reached = 150
	var r := ShopCatalog.recipe("hand_drill")
	var inputs: Dictionary = r["inputs"]
	var bronze_need := int(inputs["bronze"])
	for id in inputs.keys():
		if String(id) != "bronze":
			GameState.house_storage[String(id)] = int(inputs[id])
	GameState.house_storage["scrap"] = bronze_need
	GameState.coins = int(r["coins"])
	check("ручной бур ещё не собрать — бронзы нет", not ShopService.can_craft("hand_drill"))
	check("лом на всю бронзу бура (%d) загружен" % bronze_need, bool(ShopService.craft("bronze", bronze_need)["ok"]))
	check("бур ждёт печь", not ShopService.can_craft("hand_drill"))
	_at(bronze_need * BronzeFurnace.seconds_per_unit())
	BronzeFurnace.collect()
	check("через %d минут бронза на складе" % bronze_need, HouseStorage.count("bronze") == bronze_need)
	var res := ShopService.craft("hand_drill")
	check("ручной бур собирается из выплавленной бронзы", bool(res["ok"]) and GameState.owns_tool("hand_drill"))


## Карточка рецепта бронзы: ползунок на N штук грузит печь, печь показывает
## очередь, отсчёт и «готово N»; крестик печи возвращает лом; плитка — отсчёт.
func _test_card_slider_and_furnace_box() -> void:
	_fresh()
	var per := BronzeFurnace.seconds_per_unit()
	Settings.reduce_motion = true
	GameState.inventory["scrap"] = 5
	GameState.house_storage["scrap"] = 7
	var ui: ShopUI = load("res://scenes/shop.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	ui.open(ShopUI.TAB_TECH)
	await get_tree().process_frame
	var t: ShopTile = ui._tiles["recipe:bronze"]
	check("пустая печь — на плитке ни огонька, ни отсчёта", String(t.offer.get("count_text", "")) == ""
		and not bool(t.offer.get("furnace", false)))
	ui._on_tile_pressed(t.offer, t)
	await get_tree().process_frame
	var qty := ui._card.find_child("CraftQty", true, false) as CraftQtyBox if ui._card != null else null
	var box := ui._card.find_child("FurnaceBox", true, false) as FurnaceBox if ui._card != null else null
	check("в карточке бронзы ползунок (MAX 12) и печь", qty != null and box != null and qty.max_amount() == 12)
	if qty == null or box == null:
		ui.queue_free()
		return
	check("пустая печь: очередь 0, «1:00» на штуку, готово 0",
		box._q_lbl.text == "0" and box._t_lbl.text == "1:00" and box._r_lbl.text == "готово 0")
	qty.set_amount(7)
	ui._confirm_card()
	await get_tree().process_frame
	check("ползунок на 7 → в печи 7, лом списан (склад первым)", BronzeFurnace.queued() == 7
		and HouseStorage.count("scrap") == 0 and GameState.get_item_count("scrap") == 5)
	t = ui._tiles["recipe:bronze"]
	check("на плитке огонёк и отсчёт «1:00»", String(t.offer.get("corner_tl", "")) == "flame"
		and String(t.offer.get("count_text", "")) == "1:00")
	_at(per + 30)
	ui._furnace_tick()
	check("плитка тикает: «0:30»", t._count.text == "0:30" and t._count.visible)
	ui._on_tile_pressed(t.offer, t)
	await get_tree().process_frame
	box = ui._card.find_child("FurnaceBox", true, false) as FurnaceBox
	check("карточка: в очереди 6, до следующей 0:30, готово 1", box != null and box._q_lbl.text == "6"
		and box._t_lbl.text == "0:30" and box._r_lbl.text == "готово 1")
	check("полоска штуки — наполовину", box != null and is_equal_approx(box._fill.size.x, floorf(FurnaceBox.BAR_W * 0.5)))
	check("крестик печи виден дома", box != null and box._stop.visible and not box._stop.disabled)
	box._on_stop()
	await get_tree().process_frame
	check("крестик вернул лом за 5 не начатых", BronzeFurnace.queued() == 1
		and GameState.get_item_count("scrap") + HouseStorage.count("scrap") == 10)
	check("карточка открылась заново с новым MAX (10)", ui._card != null
		and (ui._card.find_child("CraftQty", true, false) as CraftQtyBox).max_amount() == 10)

	# Вдали от дома: плитка «дома», но работающую печь можно открыть и посмотреть.
	ui.close()
	GameState.house_is_indoors = false
	_at(3 * per)
	ui.open(ShopUI.TAB_TECH)
	await get_tree().process_frame
	t = ui._tiles["recipe:bronze"]
	check("из шахты готовое не забирается (2 ждут в печи)", BronzeFurnace.ready_count() == 2
		and HouseStorage.count("bronze") == 0)
	check("на плитке «+2» готового", String(t.offer.get("count_text", "")) == "+2" and String(t.offer["state"]) == "away")
	ui._on_tile_pressed(t.offer, t)
	await get_tree().process_frame
	box = ui._card.find_child("FurnaceBox", true, false) as FurnaceBox if ui._card != null else null
	check("из шахты карточка открывается: готово 2, без ползунка, молоток выключен", box != null
		and box._r_lbl.text == "готово 2" and ui._card.find_child("CraftQty", true, false) == null and ui._card_ok.disabled)
	ui.close()

	# Домой — при входе в магазин бронза сама ложится по правилу (склад 2: лом был складской).
	GameState.house_is_indoors = true
	ui.open(ShopUI.TAB_FOOD)
	await get_tree().process_frame
	check("при входе в магазин дома готовое забралось само", BronzeFurnace.ready_count() == 0
		and HouseStorage.count("bronze") == 2)
	ui.close()
	ui.queue_free()

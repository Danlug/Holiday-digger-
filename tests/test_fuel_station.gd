extends Node
## test_fuel_station — станция заправки: перегонка торфа и угля в топливные блоки
## (FuelRefinery) и экран станции (TechScreen, вкладка бака). Решение владельца,
## раунд 3: «переработка торфа в топливо — на заправочной станции, а не в магазине».
##
##   godot --headless --path . res://tests/test_fuel_station.tscn
##
## Проверяется: пропорции из balance.json, откуда берётся сырьё и куда ложатся
## блоки, лимиты и нехватка сырья, глубина угля, событие шины, сохранение,
## отсутствие рецептов в мастерской, экран станции (перегнать, затем залить) и
## доступность станции по сюжету: сцена заправки играет на той же сотой метке,
## что открывает рецепт бура, — окна «бур есть, станции нет» нет.

var failures := 0
var total := 0
var _events: Array = []


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _fresh() -> void:
	GameState.reset_progress()
	GameState.is_alive = true
	GameState.house_is_indoors = false
	GameState.player_depth = 0
	GameState.era = "now"
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.story_flags["fuel_station_built"] = true
	_events.clear()


func _ready() -> void:
	print("=== test_fuel_station ===")
	GameState.game_event.connect(func(id: StringName, data: Dictionary) -> void:
		if id == &"fuel_refined" or id == &"refueled":
			_events.append([String(id), data.duplicate()]))
	_test_ratios()
	_test_refine_from_pack()
	_test_refine_from_storage_and_mixed()
	_test_limits()
	_test_coal_gate()
	_test_uranium()
	_test_station_gate()
	_test_events()
	_test_save_load()
	_test_no_shop_recipes()
	await _test_screen()
	await _test_story_chain()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# Логика перегонки
# ---------------------------------------------------------------------------

func _test_ratios() -> void:
	var fc: Dictionary = Balance.balance["fuel_consumption"]
	check("торф: 4 на блок — число владельца из balance.json",
		FuelRefinery.per_block("peat") == int(Balance.unwrap(fc["peat_per_fuel_block"])) and FuelRefinery.per_block("peat") == 4)
	check("уголь: на блок столько, сколько в balance.json",
		FuelRefinery.per_block("coal") == int(Balance.unwrap(fc["coal_per_fuel_block"])))
	check("сырьё станции — торф, уголь и уран (владелец 30.10), торф первым", FuelRefinery.inputs() == ["peat", "coal", "uranium"])
	check("другое сырьё не перегоняется", not FuelRefinery.is_input("iron_ore") and FuelRefinery.max_blocks("iron_ore") == 0)
	# Торф 0.25 кг (владелец, 27.10) — блок обязан остаться легче своих четырёх торфин и двух углей,
	# иначе перегонка делает рюкзак тяжелее, а сырьё выгоднее носить как есть.
	var block_kg := Balance.get_mineral_weight("fuel_block")
	check("блок легче сырья: 4 торфа и 2 угля по весу из minerals.json",
		block_kg < FuelRefinery.per_block("peat") * Balance.get_mineral_weight("peat")
		and block_kg < FuelRefinery.per_block("coal") * Balance.get_mineral_weight("coal"))


func _test_refine_from_pack() -> void:
	_fresh()
	GameState.inventory["peat"] = 10
	check("из 10 торфа выходит 2 блока", FuelRefinery.max_blocks("peat") == 2)
	var w0 := GameState.get_total_weight()
	var r := FuelRefinery.refine("peat", 2)
	check("перегонка прошла", bool(r["ok"]) and int(r["made"]) == 2)
	check("торф списан ровно по курсу (8), остаток 2", GameState.get_item_count("peat") == 2 and int(r["used"]) == 8)
	check("блоки из рюкзачного торфа — в рюкзак", GameState.get_item_count("fuel_block") == 2 and int(r["to_pack"]) == 2)
	check("склад не тронут", HouseStorage.total_items() == 0)
	check("рюкзак стал легче (блок легче четырёх торфин)", GameState.get_total_weight() < w0)


func _test_refine_from_storage_and_mixed() -> void:
	_fresh()
	GameState.inventory["peat"] = 6
	HouseStorage.store_directly("peat", 10)
	check("показ: рюкзак + склад = 16 торфа, 4 блока", FuelRefinery.held("peat") == 16 and FuelRefinery.max_blocks("peat") == 4)
	var r := FuelRefinery.refine("peat", 4)
	check("сначала рюкзак (6), потом склад (10)", int(r["used_pack"]) == 6 and int(r["used_storage"]) == 10)
	check("целый блок из рюкзака — в рюкзак (1)", int(r["to_pack"]) == 1 and GameState.get_item_count("fuel_block") == 1)
	check("смешанный и складские блоки — на склад (3)", int(r["to_storage"]) == 3 and HouseStorage.count("fuel_block") == 3)
	check("торфа не осталось нигде", FuelRefinery.held("peat") == 0)

	# Рюкзак не принимает (стопка 99 или вес) — лишнее не теряется, а ложится на склад.
	_fresh()
	GameState.inventory["fuel_block"] = 98
	GameState.inventory["peat"] = 12
	var r2 := FuelRefinery.refine("peat", 3)
	check("полный рюкзак: ни один блок не потерян, лишнее — на склад",
		bool(r2["ok"]) and GameState.get_item_count("fuel_block") <= 99
		and GameState.get_item_count("fuel_block") + HouseStorage.count("fuel_block") == 101
		and HouseStorage.count("fuel_block") == int(r2["to_storage"]) and int(r2["to_storage"]) >= 2)


func _test_limits() -> void:
	_fresh()
	GameState.inventory["peat"] = 3
	var r := FuelRefinery.refine("peat", 1)
	check("трёх торфин на блок мало — отказ", not bool(r["ok"]) and String(r["reason"]) != "")
	check("отказ ничего не тронул", GameState.get_item_count("peat") == 3 and GameState.get_item_count("fuel_block") == 0)
	GameState.inventory["peat"] = 9
	var r2 := FuelRefinery.refine("peat", 50)
	check("просили больше, чем есть: перегнано сколько можно (2)", bool(r2["ok"]) and int(r2["made"]) == 2)
	check("остаток торфа — 1", GameState.get_item_count("peat") == 1)
	check("ноль блоков — отказ", not bool(FuelRefinery.refine("peat", 0)["ok"]))
	check("отрицательное число — отказ", not bool(FuelRefinery.refine("peat", -3)["ok"]))


## Владелец 30.10: «с урана выходит 4 блока топлива».
func _test_uranium() -> void:
	_fresh()
	check("уран — сырьё станции: 1 уран → 4 блока",
		FuelRefinery.is_input("uranium") and FuelRefinery.per_block("uranium") == 1 and FuelRefinery.blocks_per_batch("uranium") == 4)
	GameState.max_depth_reached = FuelRefinery.unlock_depth("uranium") - 1
	check("уран до своей глубины под замком", not FuelRefinery.is_unlocked("uranium"))
	GameState.max_depth_reached = FuelRefinery.unlock_depth("uranium")
	GameState.inventory["uranium"] = 3
	check("3 урана — 3 перегонки, 12 блоков", FuelRefinery.max_batches("uranium") == 3 and FuelRefinery.max_blocks("uranium") == 12)
	var r := FuelRefinery.refine("uranium", 8)
	check("просили 8 блоков — ушло 2 урана, вышло 8 блоков",
		bool(r["ok"]) and int(r["used"]) == 2 and int(r["made"]) == 8 and GameState.get_item_count("uranium") == 1
		and GameState.get_item_count("fuel_block") == 8 and int(r["to_pack"]) == 8)
	var r2 := FuelRefinery.refine("uranium", 1)
	check("один блок не делится: перегонка урана целиком — 4 блока", bool(r2["ok"]) and int(r2["made"]) == 4 and int(r2["used"]) == 1)
	check("урана не осталось — отказ", not bool(FuelRefinery.refine("uranium", 4)["ok"]))


func _test_coal_gate() -> void:
	_fresh()
	var per := FuelRefinery.per_block("coal")
	GameState.max_depth_reached = FuelRefinery.unlock_depth("coal") - 1
	check("уголь до своей глубины закрыт", not FuelRefinery.is_unlocked("coal"))
	check("закрытый уголь не перегоняется", not bool(FuelRefinery.refine("coal", 1)["ok"]))
	GameState.inventory["coal"] = per * 3
	check("но уголь на руках (скважина принесла) открывает перегонку", FuelRefinery.is_unlocked("coal"))
	GameState.max_depth_reached = FuelRefinery.unlock_depth("coal")
	var r := FuelRefinery.refine("coal", 3)
	check("уголь: 3 блока по курсу", bool(r["ok"]) and GameState.get_item_count("fuel_block") == 3
		and GameState.get_item_count("coal") == 0)
	check("глубина угля — 1000 (как у самого угля)", FuelRefinery.unlock_depth("coal") == 1000)
	check("торф открыт с самого начала", FuelRefinery.unlock_depth("peat") == 0)


func _test_station_gate() -> void:
	_fresh()
	GameState.story_flags.erase("fuel_station_built")
	GameState.owned_tools = ["shovel", "rusty_pickaxe"]
	GameState.inventory["peat"] = 8
	check("без сцены заправки и без техники станции нет", not FuelRefinery.station_built())
	check("без станции перегонки нет", not bool(FuelRefinery.refine("peat", 1)["ok"]) and GameState.get_item_count("peat") == 8)
	GameState.owned_tools.append("hand_drill")
	check("страховка: бур на руках — станция стоит, даже если сцена не сыграла", FuelRefinery.station_built())
	GameState.era = "grandpa"
	check("в эпоху деда станции нет", not FuelRefinery.station_built())
	GameState.era = "now"


func _test_events() -> void:
	_fresh()
	GameState.inventory["peat"] = 8
	FuelRefinery.refine("peat", 2)
	var ev: Array = _events.filter(func(e: Array) -> bool: return e[0] == "fuel_refined")
	check("перегонка шлёт fuel_refined", ev.size() == 1)
	if ev.size() == 1:
		var d: Dictionary = ev[0][1]
		check("в событии сырьё, расход и выход", String(d["raw"]) == "peat" and int(d["used"]) == 8
			and int(d["blocks"]) == 2 and int(d["to_pack"]) == 2 and int(d["to_storage"]) == 0)
	_events.clear()
	GameState.owned_tools.append("hand_drill")
	FuelTank.refuel("hand_drill", "pack", -1)
	check("заправка по-прежнему шлёт refueled (на нём задания)",
		_events.size() == 1 and _events[0][0] == "refueled" and String(_events[0][1]["tool"]) == "hand_drill")


func _test_save_load() -> void:
	_fresh()
	GameState.inventory["peat"] = 7
	HouseStorage.store_directly("peat", 9)
	FuelRefinery.refine("peat", 4)
	var pack_blocks := GameState.get_item_count("fuel_block")
	var store_blocks := HouseStorage.count("fuel_block")
	check("сейв записался", SaveSystem.save_game())
	GameState.inventory.clear()
	GameState.house_storage.clear()
	check("сейв загрузился", SaveSystem.load_game())
	check("блоки в рюкзаке пережили перезапуск", GameState.get_item_count("fuel_block") == pack_blocks and pack_blocks == 1)
	check("блоки на складе пережили перезапуск", HouseStorage.count("fuel_block") == store_blocks and store_blocks == 3)
	check("остатки торфа тоже", FuelRefinery.held("peat") == 0)


func _test_no_shop_recipes() -> void:
	check("в мастерской нет рецепта блока из торфа", ShopCatalog.recipe("fuel_block").is_empty())
	check("в мастерской нет рецепта блока из угля", ShopCatalog.recipe("fuel_block_coal").is_empty())
	var makes_block := false
	for r in ShopCatalog.recipes():
		makes_block = makes_block or String(r["output"]["id"]) == "fuel_block"
	check("ни один рецепт мастерской не делает топливный блок", not makes_block)


# ---------------------------------------------------------------------------
# Экран станции
# ---------------------------------------------------------------------------

func _test_screen() -> void:
	_fresh()
	Settings.reduce_motion = true
	GameState.owned_tools = ["shovel", "rusty_pickaxe", "hand_drill"]
	GameState.current_tool = "hand_drill"
	GameState.inventory["peat"] = 14
	FuelTank.set_fuel("hand_drill", 0.0)
	var host := Node.new()
	add_child(host)
	var screen := TechScreen.attach(host, null)
	TechScreen.open(TechScreen.TAB_TANK, true)
	await _frames(2)
	var card := screen._content.find_child("Refinery", true, false)
	check("у станции на вкладке бака есть карточка перегонки", card != null)
	var still := screen._content.find_child("Still", true, false) as Button
	var slider := screen._content.find_child("RefineSlider", true, false) as HSlider
	check("куб-кнопка и ползунок на месте", still != null and slider != null)
	if still == null or slider == null:
		host.free()
		return
	check("ползунок по умолчанию на максимуме (14 торфа -> 3 блока)", int(slider.value) == 3 and int(slider.max_value) == 3)
	slider.value = 2
	check("подписи следуют за ползунком", (screen._ref["used"] as Label).text == "−8" and (screen._ref["made"] as Label).text == "+2")
	still.pressed.emit()
	await _frames(1)
	check("кнопка «перегнать» сделала 2 блока в рюкзак", GameState.get_item_count("fuel_block") == 2 and GameState.get_item_count("peat") == 6)
	var slider2 := screen._content.find_child("RefineSlider", true, false) as HSlider
	check("после перегонки ползунок снова на новом максимуме (1)", slider2 != null and int(slider2.max_value) == 1 and int(slider2.value) == 1)
	screen._pour("pack", -1, screen, screen)
	check("и тут же заливка в бак — станция = перегонка + заправка", FuelTank.fuel("hand_drill") >= 2.0 and GameState.get_item_count("fuel_block") == 0)

	# Плитка угля под замком до 1000; нажатие — отказ, выбор не меняется.
	var coal_tile := screen._content.find_child("Raw_coal", true, false) as Button
	check("плитка угля есть", coal_tile != null)
	if coal_tile != null:
		coal_tile.pressed.emit()
		check("закрытый уголь не выбирается", screen._raw_sel == "peat")
	GameState.max_depth_reached = 1000
	GameState.inventory["coal"] = 5
	screen.refresh()
	coal_tile = screen._content.find_child("Raw_coal", true, false) as Button
	coal_tile.pressed.emit()
	await _frames(1)
	check("открытый уголь выбирается, максимум по его курсу",
		screen._raw_sel == "coal" and int((screen._ref["slider"] as HSlider).max_value) == 5 / FuelRefinery.per_block("coal"))

	# Не у станции (из меню): перегонка видна, но под замком.
	TechScreen.close_screen()
	TechScreen.open(TechScreen.TAB_TANK, false)
	await _frames(1)
	var still3 := screen._content.find_child("Still", true, false) as Button
	var blocks_before := GameState.get_item_count("fuel_block")
	still3.pressed.emit()
	check("из меню карточка перегонки видна", screen._content.find_child("Refinery", true, false) != null)
	check("но вдали от станции перегонять нельзя", GameState.get_item_count("fuel_block") == blocks_before and GameState.get_item_count("coal") == 5)
	TechScreen.close_screen()
	host.free()
	Settings.reduce_motion = false


# ---------------------------------------------------------------------------
# Сюжет: станция появляется вместе с буром — не раньше и не позже
# ---------------------------------------------------------------------------

## Решение владельца (data/story.json, сцена fuel_station): заправка появляется
## ПОСЛЕ того, как у героя завёлся ручной бур. Раньше сцена смотрела «рецепт
## открыт на сотой метке» и играла без бура (docs/PLAYTEST.md, P1.4); тупика
## «бур есть, станции нет» тоже быть не должно — страховка station_built().
func _test_story_chain() -> void:
	var drill_depth := ShopCatalog.unlock_depth("hand_drill")
	check("торф перегоняется с самого начала — к буру сырьё уже есть", FuelRefinery.unlock_depth("peat") <= drill_depth)

	for f in ["user://save.json", "user://save.json.bak", "user://records.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	GameState.reset_progress()
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	# Сцены арки на сотой метке (звонок у могилы, «Глубина 100») — не про заправку, не мешаем ими.
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure",
			"workshop", "death", "backpack", "robert", "sleep_lesson_1", "sleep_lesson_2", "grave_call", "depth_100"]:
		StoryState.mark_seen(id)
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "gold_sold", "food_ordered"]:
		StoryState.set_flag(f)
	GameState.world_seed = 4242
	GameState.max_depth_reached = drill_depth
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(8)
	var director := main.find_child("StoryDirector", true, false) as StoryDirector
	check("режиссёр сюжета найден", director != null)
	if director == null:
		main.free()
		return
	await _frames(20)
	check("сотая метка: рецепт бура открыт", ShopService.is_recipe_unlocked("hand_drill"))
	check("сотая метка без бура: сцены заправки нет",
		not StoryState.is_seen("fuel_station") and not GameState.story_queue.has("fuel_station"))
	check("сотая метка без бура: станции нет", not FuelRefinery.station_built())

	# Бур собирают в мастерской: пока окно открыто, сцена не встаёт поверх него.
	var shop := ShopUI.instance
	if shop != null:
		shop.open()
		await _frames(2)
	GameState.grant_tool("hand_drill")
	check("бур собран — станция стоит сразу (страховка от «бур есть, топлива нет»)", FuelRefinery.station_built())
	if shop != null:
		await _frames(10)
		check("пока мастерская открыта, сцена заправки ждёт",
			not StoryState.is_seen("fuel_station") and not GameState.story_queue.has("fuel_station")
			and not (director.cutscene != null and director.cutscene.is_playing and director.cutscene.scene_id == "fuel_station"))
		shop.close()
	var played := false
	for _i in range(60):
		await _frames(1)
		if director.cutscene != null and director.cutscene.is_playing:
			played = played or director.cutscene.scene_id == "fuel_station"
			director.cutscene.skip()
		if StoryState.is_seen("fuel_station"):
			break
	check("бур есть — сыграла сцена заправки", played and StoryState.is_seen("fuel_station"))
	check("станция стоит (флаг сцены)", StoryState.has_flag("fuel_station_built") and FuelRefinery.station_built())
	main.free()

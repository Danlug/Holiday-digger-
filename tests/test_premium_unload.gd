extends Node
## test_premium_unload — премиум-выгрузка на склад вместо таблетки восстановления
## (раунд 6, слова владельца 27.10) и сцена «выгрузка» на глубине 150.
##
## Проверяет: таблетки нет ни в магазине, ни в данных, ни в значках; выгрузка за доллары
## переносит на склад всю добычу (склад без предела), припасы и надетое не трогает,
## списывает ровно цену и не берёт денег с пустого рюкзака; старый сейв с таблеткой
## грузится и получает её цену назад; затемнение пропускает только цель; сцена на 150
## взводится рекордом в своём поясе один раз, ждёт безопасного момента, ведёт стрелкой
## к магазину и к плитке, первый раз выгружает бесплатно и объясняет катсценой; к 200
## (обучение часам) не начатая сцена тихо пропускается.
##
## Сценой, а не --script: нужны автолоады и настоящая main.tscn.
##   godot --headless --path . res://tests/test_premium_unload.tscn

var failures := 0
var total := 0
var events: Array = []


func check(label: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", label, ("  " + detail) if not ok and detail != "" else ""])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== test_premium_unload ===")
	GameState.game_event.connect(func(id: StringName, data: Dictionary) -> void: events.append([String(id), data]))
	_test_no_pill()
	_test_unload_service()
	_test_legacy_save()
	await _test_spotlight()
	await _test_lesson()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _fresh() -> void:
	GameState.reset_progress()
	GameState.debug_free_shop = false
	GameState.house_is_indoors = false
	GameState.player_depth = 150
	GameState.dollars = 100
	ShopCatalog.reload()
	events.clear()


func _events(id: String) -> Array:
	return events.filter(func(e): return e[0] == id)


# ---------------------------------------------------------------------------
# 1. Таблетки нет, на её месте — выгрузка
# ---------------------------------------------------------------------------

func _test_no_pill() -> void:
	ShopCatalog.reload()
	check("таблетки нет среди товаров за доллары", ShopCatalog.good("full_restore_pill", "dollars").is_empty())
	check("и за монеты тоже", ShopCatalog.good("full_restore_pill", "coins").is_empty())
	var g := ShopCatalog.good(PremiumUnload.ID, "dollars")
	check("выгрузка на склад — товар за доллары", not g.is_empty() and String(g["effect"]) == PremiumUnload.EFFECT)
	var raw: Dictionary = g["price_dollars"]
	check("цена — {value, proposed: true, note} в data/shop.json", int(raw["value"]) == 25 and bool(raw["proposed"])
		and String(raw.get("note", "")).length() > 40)
	check("цена в витрине = значению из данных", ShopCatalog.good_price(g, "dollars") == int(raw["value"]))
	var keys: Array = []
	for sec in ShopItems.sections("premium"):
		for o in sec["offers"]:
			keys.append(String(o["key"]))
	check("плитка выгрузки на вкладке за доллары", keys.has("good:dollars:premium_unload"))
	check("плитки таблетки нет", not keys.any(func(k): return String(k).contains("full_restore")))
	check("гаджеты за доллары в balance.json: выгрузка вместо таблетки",
		Balance.balance["monetization"]["gadgets_premium_currency"].has("premium_unload")
		and not Balance.balance["monetization"]["gadgets_premium_currency"].has("full_restore_pill"))
	check("значка таблетки больше нет", not ResourceLoader.exists("res://art/ui/shop/item_full_restore_pill.png"))
	var icon := ShopArt.item_icon(PremiumUnload.ID)
	check("значок выгрузки нарисован (32×32)", icon != null and icon != ShopArt.tex("item_unknown") and icon.get_size() == Vector2(32, 32))
	var img := icon.get_image()
	var opaque := 0
	for y in 32:
		for x in 32:
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
	check("значок не пустой и не сплошной (силуэт)", opaque > 250 and opaque < 900, str(opaque))
	var differs := true
	for other in ["teleport_watch", "energy_drink", "medkit", "energy_bar"]:
		var o := ShopArt.item_icon(other)
		differs = differs and (o == null or o.get_image().get_data() != img.get_data())
	check("значок не совпадает с соседями по витрине", differs)


# ---------------------------------------------------------------------------
# 2. Выгрузка: что уходит, что остаётся, деньги
# ---------------------------------------------------------------------------

func _test_unload_service() -> void:
	_fresh()
	GameState.grant_tool("iron_pickaxe")
	GameState.current_tool = "iron_pickaxe"
	GameState.grant_gear("backpack")
	GameState.current_gear = "backpack"
	GameState.inventory = {"iron_ore": 30, "gold": 5, "food_soup": 2, "medkit": 1, "fuel_block": 3, "energy_bar": 1}
	GameState.house_storage = {"iron_ore": 10}
	var tools_before: Array = GameState.owned_tools.duplicate()
	check("припасы не считаются добычей", PremiumUnload.is_supply("food_soup") and PremiumUnload.is_supply("medkit")
		and PremiumUnload.is_supply("fuel_block") and PremiumUnload.is_supply("energy_bar") and not PremiumUnload.is_supply("gold"))
	check("улетит 35 штук", PremiumUnload.movable_count() == 35)
	var offer := _premium_offer()
	check("плитка доступна, на карточке «рюкзак ×35 → склад»", String(offer.get("state", "")) == "available"
		and offer["effects"].size() == 2 and String(offer["effects"][0]["text"]) == "×35")
	var r := ShopService.buy(PremiumUnload.ID, "dollars")
	check("покупка прошла", bool(r["ok"]) and String(r["effect"]) == PremiumUnload.EFFECT)
	check("доллары списаны ровно по цене", GameState.dollars == 75)
	check("добыча на складе (склад сложился с тем, что было)", HouseStorage.count("iron_ore") == 40 and HouseStorage.count("gold") == 5)
	check("в рюкзаке добычи нет", GameState.get_item_count("iron_ore") == 0 and GameState.get_item_count("gold") == 0)
	check("припасы остались с героем", GameState.get_item_count("food_soup") == 2 and GameState.get_item_count("medkit") == 1
		and GameState.get_item_count("fuel_block") == 3 and GameState.get_item_count("energy_bar") == 1)
	check("надетое не тронуто", GameState.current_tool == "iron_pickaxe" and GameState.current_gear == "backpack"
		and GameState.owned_tools == tools_before)
	check("витрине отдано, что улетело", int(r["unload"]["count"]) == 35 and int(r["unload"]["moved"]["iron_ore"]) == 30)
	check("событие stored на каждую стопку, premium_unload — одно, не бесплатное",
		_events("stored").size() == 2 and _events("premium_unload").size() == 1 and not bool(_events("premium_unload")[0][1]["free"]))
	check("событие покупки — как у других товаров", _events("bought").size() == 1)

	# Пустой рюкзак (одни припасы): денег не берём.
	var before := GameState.dollars
	var empty := ShopService.buy(PremiumUnload.ID, "dollars")
	check("рюкзак без добычи — отказ, доллары целы", not bool(empty["ok"]) and GameState.dollars == before)
	check("плитка при пустом рюкзаке тусклая, без замка", String(_premium_offer()["state"]) == "poor" and not _premium_offer().has("lock_reason"))

	# Нет денег: ничего не улетает.
	GameState.add_item("gold", 2)
	GameState.dollars = 10
	var poor := ShopService.buy(PremiumUnload.ID, "dollars")
	check("не хватает долларов — отказ, добыча на месте", not bool(poor["ok"]) and String(poor["message"]).contains("доллар")
		and GameState.get_item_count("gold") == 2 and HouseStorage.count("gold") == 5)

	# Склад без предела (ГДД п.14): уходит всё, сколько бы ни было.
	GameState.dollars = 100
	GameState.inventory["iron_ore"] = 99999
	var big := ShopService.buy(PremiumUnload.ID, "dollars")
	check("склад без предела: 99 999 штук ушли все", bool(big["ok"]) and GameState.get_item_count("iron_ore") == 0
		and HouseStorage.count("iron_ore") == 40 + 99999)

	# Где угодно, без ролика: огород, прихожая, шахта.
	for place in [["garden", false, 0], ["hall", true, 0], ["mine", false, 300]]:
		GameState.house_is_indoors = bool(place[1])
		GameState.house_room = "hall"
		GameState.player_depth = int(place[2])
		GameState.add_item("copper", 1)
		var used := ShopRemote.used_today()
		var rr := ShopService.buy(PremiumUnload.ID, "dollars")
		check("%s: выгрузка за доллары без ролика" % place[0], bool(rr["ok"]) and not bool(rr["remote"]) and ShopRemote.used_today() == used)


func _premium_offer() -> Dictionary:
	for sec in ShopItems.sections("premium"):
		for o in sec["offers"]:
			if String(o["key"]) == "good:dollars:premium_unload":
				return o
	return {}


# ---------------------------------------------------------------------------
# 3. Старый сейв с таблеткой
# ---------------------------------------------------------------------------

func _test_legacy_save() -> void:
	_fresh()
	GameState.dollars = 10
	GameState.inventory = {"full_restore_pill": 2, "gold": 1}
	GameState.house_storage = {"full_restore_pill": 1, "iron_ore": 3}
	SaveSystem.save_game()
	GameState.reset_progress()
	var ok := SaveSystem.load_game()
	check("сейв со старой таблеткой грузится", ok)
	check("таблетки нет ни в рюкзаке, ни на складе", not GameState.inventory.has("full_restore_pill")
		and not GameState.house_storage.has("full_restore_pill"))
	check("за каждую таблетку — её цена долларами (= одна выгрузка)", GameState.dollars == 10 + 3 * PremiumUnload.LEGACY_PILL_DOLLARS)
	check("остальное в сейве цело", GameState.get_item_count("gold") == 1 and HouseStorage.count("iron_ore") == 3)
	check("повторная загрузка ничего не начисляет", SaveSystem.load_game() and GameState.dollars == 10 + 3 * PremiumUnload.LEGACY_PILL_DOLLARS)
	SaveSystem.delete_save()


# ---------------------------------------------------------------------------
# 4. Затемнение пропускает только цель
# ---------------------------------------------------------------------------

func _test_spotlight() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var behind := Button.new()   # то, что лежит под затемнением
	behind.position = Vector2(20, 300)
	behind.size = Vector2(60, 40)
	host.add_child(behind)
	var behind_hits := [0]
	behind.pressed.connect(func() -> void: behind_hits[0] += 1)
	var target := Rect2(150, 60, 30, 24)
	var sp := GuideSpotlight.new()
	add_child(sp)
	var hits := [0]
	sp.target_pressed.connect(func() -> void: hits[0] += 1)
	sp.point_at(func() -> Rect2: return target)
	await _frames(2)
	var view := get_viewport().get_visible_rect().size
	check("окно в затемнении — цель с полями", sp.hole() == target.grow(GuideSpotlight.GROW))
	var dim_area := 0.0
	for d in sp._dims:
		if d.visible:
			dim_area += d.size.x * d.size.y
	check("затемнено всё, кроме окна", absf(dim_area + sp.hole().get_area() - view.x * view.y) < 1.0)
	check("пропускает только цель", sp.lets_through(target.get_center()) and not sp.lets_through(behind.get_global_rect().get_center())
		and not sp.lets_through(Vector2(5, 470)))
	_click(behind.get_global_rect().get_center())
	await _frames(2)
	check("нажатие мимо цели не дошло до кнопки под затемнением", behind_hits[0] == 0 and hits[0] == 0)
	_click(target.get_center())
	await _frames(2)
	check("нажатие по цели — сигнал ровно один раз", hits[0] == 1)
	var arrow_c: Vector2 = sp._arrow.position + sp._arrow.size * 0.5   # стрелка повёрнута вокруг середины
	check("стрелка у цели и смотрит на неё", sp._arrow.visible and absf(arrow_c.x - target.get_center().x) < 2.0
		and arrow_c.y > target.end.y and arrow_c.y < target.end.y + 40.0 and is_equal_approx(sp._arrow.rotation, PI),
		"стрелка %s цель %s" % [arrow_c, target])
	check("⏭ не закрывает цель", not sp._skip.get_global_rect().intersects(sp.hole()))
	var skipped := [0]
	sp.skipped.connect(func() -> void: skipped[0] += 1)
	sp._skip.confirmed.emit()
	check("⏭ — сигнал пропуска", skipped[0] == 1)
	sp.clear()
	_click(behind.get_global_rect().get_center())
	await _frames(2)
	check("снятое затемнение ничего не держит", not sp.visible and behind_hits[0] == 1)
	sp.queue_free()
	host.queue_free()
	await _frames(1)


func _click(pos: Vector2) -> void:
	var p := get_viewport().get_final_transform() * pos
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(ev)
		Input.flush_buffered_events()


# ---------------------------------------------------------------------------
# 5. Сцена на 150 в настоящей игре
# ---------------------------------------------------------------------------

func _fresh_main() -> Node2D:
	for f in ["user://save.json", "user://save.json.bak", "user://records.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	GameState.reset_progress()
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure",
			"workshop", "death", "backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2",
			"grave_call", "diary_first", "first_artifact", "depth_100"]:
		StoryState.mark_seen(id)
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "gold_sold", "food_ordered", "diary_found"]:
		StoryState.set_flag(f)
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	await _frames(6)
	return m


func _close_popups() -> void:
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms) and ms.popup.is_open():
		ms.popup.close()
	await _frames(2)


func _place_hero(main: Node2D, depth: int) -> void:
	var w: WorldGen = main.world
	for y in range(depth - 2, depth + 1):
		for x in range(10, 24):
			w.dig_cell(x, y)
	var p = main.player
	p.x = 16.5
	p.y = float(depth) + 0.6
	p.vx = 0.0
	p.vy = 0.0
	p.on_ground = true
	p.digging = null
	p.frozen = false
	GameState.player_depth = depth
	GameState.house_is_indoors = false


func _test_lesson() -> void:
	var main := await _fresh_main()
	await _close_popups()
	var lesson := PremiumUnloadLesson.instance
	check("урок подключён к игре", lesson != null and is_instance_valid(lesson))
	if lesson == null:
		return
	lesson.calm_wait_s = 0.0
	lesson.fx_wait_s = 0.0
	var director: StoryDirector = main.find_child("StoryDirector", true, false)
	var p = main.player
	var hud = main.hud
	check("пояс сцены 150–200, а не 200 (там обучение часам)", PremiumUnloadLesson.band() == Vector2i(150, 200))
	_place_hero(main, 151)
	GameState.inventory.clear()
	GameState.add_item("iron_ore", 5)
	GameState.add_item("gold", 2)
	GameState.add_item("food_soup", 1)
	GameState.house_storage.clear()
	GameState.dollars = 0
	events.clear()

	GameState.max_depth_reached = 160
	await _frames(4)
	check("глубина без рекорда (прямое присвоение) сцену не взводит", PremiumUnloadLesson.state() == "" and not lesson.is_active())
	GameState.max_depth_reached = 120
	GameState.update_max_depth(149)
	check("рекорд 149 — ещё не пояс", PremiumUnloadLesson.state() == "")
	GameState.update_max_depth(150)
	check("рекорд 150 взводит сцену", PremiumUnloadLesson.state() == "armed")

	# Безопасный момент: рюкзак открыт, бой, падение, окно смерти — ждём.
	hud.open_inventory()
	lesson.tick(0.1)
	check("поверх открытого рюкзака не начинается", not lesson.is_active())
	hud.close_inventory()
	await _frames(2)
	GameState.ext_set("combat", {"active": true})
	lesson.tick(0.1)
	check("в бою не начинается", not lesson.is_active())
	GameState.ext.erase("combat")
	p.on_ground = false
	lesson.tick(0.1)
	check("в падении не начинается", not lesson.is_active())
	p.on_ground = true
	var inv: Dictionary = GameState.inventory.duplicate()
	GameState.inventory = {"food_soup": 1}
	lesson.tick(0.1)
	check("без добычи в рюкзаке не начинается", not lesson.is_active())
	GameState.inventory = inv
	_place_hero(main, 151)
	lesson.tick(0.1)
	check("спокойный момент — сцена началась", lesson.is_active() and lesson.step == PremiumUnloadLesson.Step.SHOP)
	await _frames(2)
	var shop_btn: Control = hud.get("_shop_btn")
	check("шаг 1: окно — кнопка магазина на HUD", lesson.target_rect().encloses(shop_btn.get_global_rect()))
	check("герой стоит, джойстик выключен", bool(p.frozen) and not hud.is_processing_input(),
		"frozen %s input %s" % [p.frozen, hud.is_processing_input()])
	check("подсказки молчат, пока идёт урок", HintBusy.is_busy())

	# Мимо цели: рюкзак на HUD под затемнением не открывается.
	var inv_btn: Control = hud.get("_inv_button")
	_click(inv_btn.get_global_rect().get_center())
	await _frames(3)
	check("нажатие мимо цели (рюкзак) не прошло", not hud.get("_inv_sheet").visible and not ShopUI.instance.is_open())
	_click(lesson.target_rect().get_center())
	await _frames(3)
	check("нажатие по кнопке магазина открыло витрину за доллары", ShopUI.instance.is_open() and ShopUI.instance._tab == ShopUI.SCREEN_PREMIUM)
	check("шаг 2: окно — плитка выгрузки", lesson.step == PremiumUnloadLesson.Step.TILE
		and lesson.target_rect().encloses(ShopUI.instance._tiles["good:dollars:premium_unload"].get_global_rect()))
	var exch: Control = ShopUI.instance._tiles["exchange:1"]
	_click(exch.get_global_rect().get_center())
	await _frames(3)
	check("мимо цели в витрине ничего не нажалось", ShopUI.instance._card == null and lesson.step == PremiumUnloadLesson.Step.TILE)

	_click(lesson.target_rect().get_center())
	await _frames(3)
	check("первая выгрузка бесплатная: добыча на складе", HouseStorage.count("iron_ore") == 5 and HouseStorage.count("gold") == 2
		and GameState.get_item_count("iron_ore") == 0)
	check("бесплатно: доллары не тронуты (их и не было)", GameState.dollars == 0)
	check("еда осталась в рюкзаке", GameState.get_item_count("food_soup") == 1)
	check("событие выгрузки помечено бесплатным", _events("premium_unload").size() == 1 and bool(_events("premium_unload")[0][1]["free"]))
	await _frames(4)
	check("урок засчитан", PremiumUnloadLesson.state() == "done" and not lesson.is_active())
	check("витрина закрыта, объяснение — катсцена unload_150", not ShopUI.instance.is_open()
		and director.cutscene.is_playing and director.cutscene.scene_id == "unload_150")
	director.cutscene.skip()
	await _frames(6)
	check("после объяснения герой свободен, HUD слушает ввод", not bool(p.frozen) and hud.is_processing_input() and hud.visible)
	check("сцена объяснения помечена просмотренной", StoryState.is_seen("unload_150"))

	GameState.add_item("gold", 1)
	GameState.update_max_depth(170)
	lesson.tick(0.1)
	await _frames(3)
	check("один раз за игру: новый рекорд в поясе сцену не повторяет", not lesson.is_active() and PremiumUnloadLesson.state() == "done")

	# Пропуск ⏭ на шаге 1.
	GameState.ext_set(PremiumUnloadLesson.EXT_KEY, {"lesson": "armed"})
	_place_hero(main, 171)
	lesson.tick(0.1)
	check("снова взведённый урок начался", lesson.is_active())
	lesson.spotlight._skip.confirmed.emit()
	await _frames(2)
	check("⏭: урок пропущен насовсем, герой свободен", PremiumUnloadLesson.state() == "skipped" and not lesson.is_active()
		and not bool(p.frozen) and hud.is_processing_input() and not lesson.spotlight.visible)
	check("⏭: ничего не улетело", GameState.get_item_count("gold") == 1)

	# Пояс и обучение часам на 200.
	GameState.ext_set(PremiumUnloadLesson.EXT_KEY, {})
	GameState.max_depth_reached = 140
	GameState.update_max_depth(210)
	check("рекорд сразу за 200 (мимо пояса) сцену не взводит", PremiumUnloadLesson.state() == "")
	GameState.max_depth_reached = 140
	GameState.update_max_depth(155)
	check("рекорд в поясе взвёл", PremiumUnloadLesson.state() == "armed")
	hud.open_inventory()   # игрок всё время занят
	GameState.update_max_depth(200)
	lesson.tick(0.1)
	hud.close_inventory()
	await _frames(2)
	lesson.tick(0.1)
	check("к 200 не начатая сцена пропущена — с обучением часам не совпадает",
		PremiumUnloadLesson.state() == "missed" and not lesson.is_active())
	_place_hero(main, 205)
	for _i in 5:
		lesson.tick(0.5)
	check("глубже 200 сцена не начинается никогда", not lesson.is_active())
	main.queue_free()
	await _frames(2)

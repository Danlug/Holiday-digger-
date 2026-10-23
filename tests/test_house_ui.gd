extends Node
## test_house_ui — представление дома (scripts/house/): значки на пузырях и
## Tip у каждого интерактива, значки всех блюд, принудительные окна обучения,
## склад (плитки, окно «сколько», замок вдали от мастерской), ролик сна
## (часы, пропуск за ролик), доставка еды (значок курьера, пакет у двери).
## Логика дома сама проверена в test_house; здесь — что игрок видит и нажимает.
##
## Запускается СЦЕНОЙ (дом обращается к автозагрузкам):
##   godot --headless --path . res://tests/test_house_ui.tscn

var failures := 0
var total := 0

var world: WorldGen
var fog: FogOfWar
var player
var house: HouseSystem
var _events: Array = []   # [{id, data}] — что дом выложил на шину событий


func _on_event(id: StringName, data: Dictionary) -> void:
	_events.append({"id": String(id), "data": data})


func _event_count(id: String) -> int:
	var n := 0
	for e in _events:
		if e["id"] == id:
			n += 1
	return n


func _ready() -> void:
	print("=== test_house_ui ===")
	Settings.reduce_motion = true
	GameState.game_event.connect(_on_event)
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

	_test_food_icons()
	_test_rooms_data_has_icons_and_tips()
	_test_bubble_widget()
	_test_view_bubbles_have_tips()
	_test_sleep_bubble_state()
	_test_outdoor_bubbles()
	_test_forced_sleep_card()
	_test_forced_bar_prompt()
	_test_storage_helpers()
	_test_storage_view_remote()
	_test_storage_view_at_workshop()
	_test_qty_card_outside_tap()
	_test_sleep_clock_and_skip()
	await _test_sleep_fade_race()
	_test_delivery_flow()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _leave() -> void:
	if GameState.house_is_indoors:
		house.exit_to_door()


func _tip_title(c: Object) -> String:
	if c == null or not c.has_meta(Tip.META):
		return ""
	return String((c.get_meta(Tip.META) as Dictionary).get("title", ""))


func _tip_extra(c: Object) -> String:
	if c == null or not c.has_meta(Tip.META):
		return ""
	return String((c.get_meta(Tip.META) as Dictionary).get("extra", ""))


func _px(room: String, point: String) -> float:
	return float(HouseRoomsConfig.points(room)[point].get("x", 0.5))


# ---------------------------------------------------------------------------
# Значки и подсказки
# ---------------------------------------------------------------------------

func _test_food_icons() -> void:
	var unknown := ShopArt.tex("item_unknown")
	var items := HouseConfig.food_items()
	check("в меню и допингах не меньше шести блюд", items.size() >= 6)
	var all_ok := true
	for item in items:
		var icon := HouseArt.food_icon(String(item["id"]))
		if icon == null or icon == unknown:
			all_ok = false
			print("  нет значка у блюда: " + String(item["id"]))
	check("у каждого блюда свой значок (не «булыжник»)", all_ok)
	check("значок блюда 32×32", HouseArt.food_icon("food_buldak").get_size() == Vector2(32, 32))


func _test_rooms_data_has_icons_and_tips() -> void:
	var buttons := 0
	var bad := 0
	for room_id in HouseRoomsConfig.ROOM_IDS:
		var points := HouseRoomsConfig.points(room_id)
		for key in points.keys():
			for b in (points[key].get("buttons", []) as Array):
				buttons += 1
				var icon := String(b.get("icon", ""))
				if icon.is_empty() or HouseArt.tex(icon) == null \
						or String(b.get("tip", "")).is_empty() or String(b.get("label", "")).is_empty():
					bad += 1
					print("  кнопка без значка/подсказки: %s.%s %s" % [room_id, key, String(b.get("action", ""))])
	check("в data/rooms.json есть кнопки", buttons >= 10)
	check("у каждой кнопки есть значок, заголовок и описание подсказки", bad == 0)


func _test_bubble_widget() -> void:
	var b := HouseBubble.create({"action": "x", "label": "Тест", "icon": "act_bed", "tip": "Описание"})
	add_child(b)
	check("пузырь не меньше 24×24 (палец)", b.size.x >= 24.0 and b.size.y >= 24.0)
	check("на пузыре нет текста", b.text == "")
	check("подсказка пузыря — заголовок и описание", _tip_title(b) == "Тест"
		and String((b.get_meta(Tip.META) as Dictionary).get("body", "")) == "Описание")
	check("пузырь ловит нажатия", b.mouse_filter != Control.MOUSE_FILTER_IGNORE)
	check("значок пузыря загружен", b.get_child(0).get_child_count() > 0)
	b.set_count(3)
	check("цифра в углу пузыря", b.get_node_or_null(UiBtn.BADGE_NAME) != null
		and (b.get_node(UiBtn.BADGE_NAME) as Control).visible)
	b.set_state("dim")
	check("приглушённый пузырь запоминает состояние", b.is_dim())
	b.queue_free()


func _test_view_bubbles_have_tips() -> void:
	_leave()
	var missing := 0
	var seen := 0
	for room_id in HouseRoomsConfig.ROOM_IDS:
		house.enter_house(room_id)
		var points := HouseRoomsConfig.points(room_id)
		for key in points.keys():
			house._view.set_hero_x_fraction(float(points[key].get("x", 0.5)))
			for b in house._view._hotspot_buttons:
				seen += 1
				if not (b is HouseBubble) or _tip_title(b).is_empty():
					missing += 1
		_leave()
	check("у точек дома видны пузыри", seen >= 8)
	check("каждый пузырь дома — HouseBubble с подсказкой", missing == 0)


func _test_sleep_bubble_state() -> void:
	_leave()
	GameState.set_hunger(100.0)
	GameState.set_stamina(100.0)
	house.enter_house("bedroom")
	house._view.set_hero_x_fraction(_px("bedroom", "bed"))
	var bed: HouseBubble = house._view._hotspot_buttons[0]
	check("бодрость полная — пузырь кровати приглушён", bed.is_dim())
	check("причина отказа — в подсказке, не на экране", _tip_extra(bed) != "")

	GameState.set_stamina(30.0)
	house._view.refresh()
	bed = house._view._hotspot_buttons[0]
	check("бодрость просела — пузырь кровати живой", not bed.is_dim())
	check("в подсказке кровати — что даст сон (часы, бодрость, сытость)", "ч" in _tip_extra(bed))
	_leave()


func _test_outdoor_bubbles() -> void:
	check("«Зайти» — пузырь", house._outdoor_button is HouseBubble)
	check("«В бурмобиль» — пузырь", house._rig_button is HouseBubble)
	check("у «Зайти» есть подсказка", _tip_title(house._outdoor_button) == "Зайти")
	check("у «В бурмобиль» есть подсказка", _tip_title(house._rig_button) == "В бурмобиль")
	check("пузыри снаружи без текста", house._outdoor_button.text == "" and house._rig_button.text == "")
	check("пузыри снаружи не меньше 24 ед.", house._outdoor_button.custom_minimum_size.x >= 24.0
		and house._rig_button.custom_minimum_size.y >= 24.0)

	# Машина у самой двери: два пузыря не лежат друг на друге.
	var door := HouseConfig.door_cell()
	GameState.rig_parked_at = Vector2i(door.x, 0)
	player.x = door.x + 0.5
	player.y = 0.5
	# Позицию считает HUD (в тесте его нет), поэтому проверяем сам разводящий сдвиг.
	var left := house._side_shift(-1.0)
	var right := house._side_shift(1.0)
	check("пузыри «Зайти» и «В бурмобиль» разведены в разные стороны",
		left > 0.0 and right < 0.0 and absf(left - absf(right)) < 0.01)
	GameState.rig_parked_at = Vector2i(door.x + 8, 0)
	check("машина далеко от двери — пузыри не сдвигаются", house._side_shift(-1.0) == 0.0)
	GameState.rig_parked_at = Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# Принудительные окна обучения
# ---------------------------------------------------------------------------

func _test_forced_sleep_card() -> void:
	_leave()
	GameState.house_tutorial_stage = 0
	GameState.set_stamina(0.0)
	house._start_forced_sleep()
	var card: HouseForcedCard = house._view._forced
	check("принудительный сон: окно обучения открыто", card.visible and house._view.forced_mode() == "sleep")
	check("у окна нет текста — только значок и кнопка", card.find_children("*", "Label", true, false).is_empty())
	check("объяснение в подсказке значка", _tip_title(card._frame) == "Ты вымотался"
		and String((card._frame.get_meta(Tip.META) as Dictionary).get("body", "")).length() > 20)
	check("у кнопки окна есть подсказка", _tip_title(card._button) == "Лечь спать")

	# Тап в пустое место окно не закрывает: оно ждёт одного действия.
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = Vector2(4, 4)
	card.gui_input.emit(tap)
	check("обучающее окно не закрывается тапом мимо", card.visible and house._view.forced_mode() == "sleep")
	check("герой заморожен окном обучения", player.frozen)

	card._button.pressed.emit()
	check("кнопка окна кладёт спать", not card.visible and GameState.house_tutorial_stage == 1)
	check("после обучающего сна бодрость полная", GameState.stamina >= 99.9)
	_leave()


func _test_forced_bar_prompt() -> void:
	_leave()
	GameState.inventory.clear()
	GameState.house_tutorial_stage = 1
	GameState.set_stamina(0.0)
	GameState.set_hunger(40.0)
	house._start_forced_bar()
	var card: HouseForcedCard = house._prompt._card
	check("второе истощение: окно с батончиком открыто", house._prompt.visible and card.visible)
	check("батончик лежит в портфеле", GameState.get_item_count(HouseSystem.TUTORIAL_FOOD) == 1)
	check("в окне нет текста", card.find_children("*", "Label", true, false).is_empty())
	check("значок окна — батончик, подсказка у значка и кнопки",
		_tip_title(card._frame) == "Полоска кончилась" and _tip_title(card._button) == "Съесть батончик")
	card._button.pressed.emit()
	check("кнопка заставляет съесть батончик", GameState.get_item_count(HouseSystem.TUTORIAL_FOOD) == 0
		and GameState.house_tutorial_stage == 2)
	check("окно закрылось после еды", not house._prompt.visible)
	check("отдел допингов открыт", GameState.house_dopings_shop_unlocked)
	player.frozen = false


# ---------------------------------------------------------------------------
# Склад
# ---------------------------------------------------------------------------

func _test_storage_helpers() -> void:
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.house_is_indoors = true
	GameState.house_room = "workshop"
	GameState.house_storage["iron_ore"] = 500
	var limit := HouseStorage.max_takeable("iron_ore")
	check("max_takeable не больше склада и стопки в 99", limit > 0 and limit <= 99)
	var got := HouseStorage.take("iron_ore", 9999)
	check("take забирает ровно max_takeable", got == limit)
	check("после этого больше не влезает", HouseStorage.max_takeable("iron_ore") == 0)

	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.house_storage["lead"] = 3
	GameState.house_storage["gold"] = 2
	var moved := HouseStorage.take_all()
	check("take_all забрал всё, что влезло", moved == 5 and HouseStorage.total_items() == 0)
	GameState.inventory.clear()
	GameState.house_is_indoors = false
	check("вдали от мастерской take_all ничего не берёт", HouseStorage.take_all() == 0)


func _test_storage_view_remote() -> void:
	_leave()
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.house_storage["iron_ore"] = 12
	GameState.house_storage["lead"] = 5
	GameState.inventory["gold"] = 4
	house.open_storage()
	var view = house._storage_view
	check("склад открылся вдали от мастерской", view.visible)
	check("по плитке на каждую позицию склада", view._tiles.size() == 2 and view._tiles.has("store:iron_ore"))
	check("рюкзака издалека не показываем", not view._tiles.has("bag:gold"))
	var tile: ShopTile = view._tiles["store:iron_ore"]
	check("у плитки склада есть подсказка", _tip_title(tile) != "")
	check("причина «только в мастерской» — в подсказке плитки", _tip_extra(tile) == HouseStorage.access_reason())
	check("кнопки «забрать» и «сложить» закрыты замком", view._take_lock.visible and view._put_lock.visible)
	check("причина замка — в подсказке кнопки «забрать»", _tip_extra(view._take_btn) == HouseStorage.access_reason())
	tile.pressed.emit()
	check("тап по плитке вдали окно не открывает", not view._qty.is_open())
	view._take_btn.pressed.emit()
	check("«забрать всё» вдали ничего не двигает", HouseStorage.count("iron_ore") == 12 and GameState.get_item_count("iron_ore") == 0)
	check("у крестика есть подсказка", _tip_title(view._close_btn) == "Закрыть")
	view.close_panel()
	check("склад закрылся крестиком", not view.visible)
	check("герой разморожен после закрытия склада", not player.frozen)


func _test_storage_view_at_workshop() -> void:
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.house_storage["iron_ore"] = 10
	GameState.house_storage["lead"] = 5
	GameState.inventory["scrap"] = 3
	GameState.inventory["peat"] = 1
	house.enter_house("workshop")
	house.open_storage()
	var view = house._storage_view
	check("у склада есть плитки склада и рюкзака", view._tiles.size() == 4 and view._tiles.has("bag:scrap"))
	check("замков на кнопках у склада нет", not view._take_lock.visible and not view._put_lock.visible)
	var every_tip := true
	for key in view._tiles.keys():
		if _tip_title(view._tiles[key]) == "":
			every_tip = false
	check("у каждой плитки склада есть подсказка", every_tip)
	check("на плитке число, а не название", (view._tiles["store:iron_ore"] as ShopTile).offer["count_text"] == "10")

	# Забрать часть: тап → окно → ползунок → галочка.
	(view._tiles["store:iron_ore"] as ShopTile).pressed.emit()
	check("тап по плитке склада открыл окно «сколько»", view._qty.is_open())
	check("ползунок по умолчанию на максимуме", view._qty.amount() == 10)
	view._qty.set_amount(4)
	view._qty._ok.pressed.emit()
	check("забрал 4 из 10", HouseStorage.count("iron_ore") == 6 and GameState.get_item_count("iron_ore") == 4)
	check("окно закрылось после галочки", not view._qty.is_open())

	# Положить одну штуку — без окна: ползунку нечего выбирать.
	(view._tiles["bag:peat"] as ShopTile).pressed.emit()
	check("единственную штуку кладёт сразу, без окна", not view._qty.is_open() and HouseStorage.count("peat") == 1)

	# Положить всё и забрать всё — кнопками внизу.
	view._put_btn.pressed.emit()
	check("склад выкладывает события «stored» на шину", _event_count("stored") >= 2)
	check("«сложить рюкзак» опустошил рюкзак", GameState.inventory.is_empty() and HouseStorage.count("iron_ore") == 10)
	view._take_btn.pressed.emit()
	check("«забрать всё» вернул, что влезло", GameState.get_item_count("lead") == 5 and HouseStorage.count("lead") == 0)
	view.close_panel()
	_leave()


func _test_qty_card_outside_tap() -> void:
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.house_storage["iron_ore"] = 10
	house.enter_house("workshop")
	house.open_storage()
	var view = house._storage_view
	(view._tiles["store:iron_ore"] as ShopTile).pressed.emit()
	check("окно «сколько» открыто", view._qty.is_open())
	check("у кнопок окна есть подсказки", _tip_title(view._qty._ok) == "Забрать"
		and _tip_title(view._qty._max_btn) != "" and _tip_title(view._qty._minus) != "")

	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	view._qty._dim.gui_input.emit(tap)
	check("тап за границей окна «сколько» закрывает его", not view._qty.is_open())
	check("закрытие тапом ничего не переложило", HouseStorage.count("iron_ore") == 10)
	check("сам склад тапом мимо не закрылся", view.visible)

	# Окно, которое держит вес рюкзака: ползунок не обещает лишнего.
	GameState.house_storage["iron_ore"] = 80
	GameState.inventory["scrap"] = 40
	view.refresh()
	view._signature = ""
	view.refresh()
	var expected := HouseStorage.max_takeable("iron_ore")
	(view._tiles["store:iron_ore"] as ShopTile).pressed.emit()
	check("ползунок «забрать» не выше того, что влезет", view._qty.amount() == expected and expected < 80)
	view._qty.cancel_card()
	view.close_panel()
	_leave()


# ---------------------------------------------------------------------------
# Сон
# ---------------------------------------------------------------------------

func _test_sleep_clock_and_skip() -> void:
	_leave()
	GameState.ad_daily_counts.clear()
	GameState.set_stamina(20.0)
	GameState.set_hunger(100.0)
	house.enter_house("bedroom")
	house._view.set_hero_x_fraction(_px("bedroom", "bed"))
	var plan := HouseSleep.plan(GameState.stamina, GameState.hunger)
	var start_total := 6.0 + GameState.game_clock_hours
	house._view.trigger_point_button("bed")
	var fx: HouseSleepFx = house._view._sleep_fx
	check("ролик сна запущен", fx.is_playing() and fx.visible)
	check("кнопка «пропустить за ролик» видна", fx._skip.visible)
	check("лимит роликов в день — 5", HouseSleepFx.skips_left() == 5)
	check("значок счётчика — число", fx._skip.get_node(UiBtn.BADGE_NAME).get_node("N").text == "5")
	check("у кнопки пропуска есть подсказка", _tip_title(fx._skip) == "Проснуться сразу"
		and "5" in _tip_extra(fx._skip))

	fx.debug_progress(1.0)
	var end_hour := fmod(start_total + float(plan["hours"]), 24.0)
	var want := "%02d:%02d" % [int(end_hour), int((end_hour - floor(end_hour)) * 60.0)]
	check("в конце ролика часы показывают час пробуждения", fx._time.text == want)

	_events.clear()
	house._skip_sleep_for_ad()
	check("сон выкладывает событие «slept» с пометкой пропуска",
		_event_count("slept") == 1 and bool(_events.filter(func(e): return e["id"] == "slept")[0]["data"]["skipped"]))
	check("пропуск закончил сон сразу", not house._sleeping and not house._view.is_sleeping())
	check("пропуск потратил один ролик", GameState.get_ad_uses_today(HouseSystem.SKIP_SLEEP_AD) == 1
		and HouseSleepFx.skips_left() == 4)
	check("сон применился: бодрость полная", GameState.stamina >= 99.9)
	DayCycle._recompute()
	var real := "%02d:%02d" % [int(DayCycle.hour), int((DayCycle.hour - floor(DayCycle.hour)) * 60.0)]
	check("часы ролика совпали с настоящими часами игры (DayCycle)", real == want)

	# Ролики кончились: кнопка закрыта замком, пропуск не срабатывает.
	GameState.ad_daily_counts[HouseSystem.SKIP_SLEEP_AD] = Balance.get_ad_daily_limit(HouseSystem.SKIP_SLEEP_AD)
	GameState.set_stamina(20.0)
	GameState.set_hunger(100.0)
	house._view.refresh()
	house._view.trigger_point_button("bed")
	check("второй сон запущен", house._sleeping)
	check("роликов не осталось — замок на кнопке", fx._lock.visible and fx._skip.disabled)
	house._skip_sleep_for_ad()
	check("без роликов пропуск не работает", house._sleeping)
	house._finish_sleep_sequence()
	check("обычный сон всё равно заканчивается по таймеру", not house._sleeping)
	GameState.ad_daily_counts.clear()
	_leave()


## Сон закончили и сразу легли снова, пока старый ролик ещё гас: затухание
## старого не должно спрятать новый (был такой баг: наложенные твины).
func _test_sleep_fade_race() -> void:
	Settings.reduce_motion = false
	var fx := HouseSleepFx.new()
	add_child(fx)
	fx.play(5.0, 4.0, false)
	fx.stop()
	fx.stop()
	fx.play(5.0, 4.0, false)
	await get_tree().create_timer(0.45).timeout
	check("новый ролик сна не спрятан затуханием старого", fx.visible and fx.modulate.a > 0.99)
	fx.stop()
	await get_tree().create_timer(0.45).timeout
	check("после остановки ролик гаснет и прячется", not fx.visible)
	fx.queue_free()
	Settings.reduce_motion = true


# ---------------------------------------------------------------------------
# Доставка
# ---------------------------------------------------------------------------

func _test_delivery_flow() -> void:
	_leave()
	GameState.house_food_at_door.clear()
	GameState.inventory.clear()
	GameState.house_free_orders_used_today = 0
	house._pending.clear()
	var badge: HouseDeliveryBadge = house._delivery_badge
	badge.reset()

	var result := HouseSystem.order_food("food_buldak")
	check("заказ принят", bool(result["ok"]))
	check("значок курьера показан и едет", badge.is_visible_now() and badge.state() == "transit"
		and badge.orders_in_flight() == 1)
	check("у значка доставки есть подсказка", _tip_title(badge._holder) == "Курьер едет")
	check("еда ещё не у двери — курьер в пути", HouseFood.food_at_door_count() == 0)

	house.debug_deliver_now()
	check("курьер доехал: порция у двери", HouseFood.food_at_door_count() == 1)
	check("заказ и приезд — события на шине", _event_count("food_ordered") >= 1 and _event_count("food_delivered") == 1)
	check("значок стучит у двери", badge.state() == "knock" and badge.orders_in_flight() == 0)

	# Пакет у двери: снаружи — спрайт мира, в салоне — реквизит комнаты.
	house._update_door_package()
	check("снаружи у двери виден пакет", house._door_pack.visible)
	house.enter_house("hall")
	house._view.refresh()
	check("в салоне у двери виден пакет", house._view.door_package_visible())
	house._view.set_hero_x_fraction(_px("hall", "front_door"))
	var take_bubble: HouseBubble = null
	for b in house._view._hotspot_buttons:
		if String(b.get_meta("action", "")) == "take_delivery":
			take_bubble = b
	check("у двери есть пузырь «Забрать» с числом порций", take_bubble != null
		and (take_bubble.get_node(UiBtn.BADGE_NAME) as Control).visible)
	house._view.go_to_room("bedroom")
	house._view.refresh()
	check("в спальне пакета нет", not house._view.door_package_visible())
	house._view.go_to_room("hall")
	house._view.set_hero_x_fraction(_px("hall", "front_door"))
	house._view.trigger_point_button("front_door", 1)
	house._view.refresh()
	check("«Забрать» унёс пакет в рюкзак", GameState.get_item_count("food_buldak") == 1
		and not house._view.door_package_visible())
	_leave()
	house._update_door_package()
	check("пакет снаружи пропал", not house._door_pack.visible)

	# Еду, которую нельзя унести, не доставляют: её съедают на месте.
	GameState.set_hunger(20.0)
	var eaten := HouseSystem.order_food("food_steak")
	check("стейк съеден на месте, курьер не выезжал", bool(eaten["ok"]) and badge.orders_in_flight() == 0)
	badge.reset()

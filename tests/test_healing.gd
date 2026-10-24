extends Node
## test_healing — лечение раунда 4 (ГДД §7 «Лечение», scripts/house/healing.gd):
## сон лечит по часам и сытости, еда — по питательности, аптечка из лавки
## «применяется» из рюкзака, смерть забирает рюкзак и 200 монет («скорая»),
## карточка смерти это показывает. Сценой — нужны автозагрузки:
##   godot --headless --path . res://tests/test_healing.tscn

var failures := 0
var total := 0
var _events: Array = []


func _ready() -> void:
	print("=== test_healing ===")
	GameState.reset_progress()
	GameState.game_event.connect(func(id: StringName, data: Dictionary) -> void:
		_events.append({"id": String(id), "data": data}))

	_test_numbers()
	_test_full_sleep_fed_heals()
	_test_hungry_sleep_heals_less()
	_test_sleep_scales_with_hours()
	_test_wounded_but_rested_can_sleep()
	_test_rested_and_healthy_refused()
	_test_wounded_hungry_refused()
	_test_tired_wounded_half_fed()
	_test_food_heals_by_nutrition()
	_test_full_meal_and_sleep_reach_90()
	_test_medkit_in_shop()
	_test_medkit_purchase_place_rules()
	_test_medkit_use()
	_test_death_fee()
	await _test_death_card()
	_test_economy_ordering()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func check_near(label: String, actual: float, expected: float, tol: float = 0.05) -> void:
	check("%s (получено %.2f, ожидалось %.2f)" % [label, actual, expected], absf(actual - expected) <= tol)


func _set_hp_percent(p: float) -> void:
	GameState.is_alive = true
	GameState.hp = GameState.get_max_hp() * p / 100.0


func _hp_percent() -> float:
	return 100.0 * GameState.hp / GameState.get_max_hp()


func _events_of(id: String) -> Array:
	var out: Array = []
	for e in _events:
		if e["id"] == id:
			out.append(e["data"])
	return out


# ---------------------------------------------------------------------------

func _test_numbers() -> void:
	check("полная ночь — 8 игровых часов", is_equal_approx(Healing.full_night_hours(), 8.0))
	check("плата скорой — 200 монет (число владельца)", Healing.death_fee_coins() == 200)
	check("аптечка лечит 50%", Healing.medkit_hp_percent() == 50)
	check("стейк лечит 25% (сытость 100 × 0.25)", Healing.food_hp_percent("food_steak") == 25)
	check("пельмени лечат 19%", Healing.food_hp_percent("food_dumplings") == 19)
	check("батончик лечит 5%", Healing.food_hp_percent("food_bar") == 5)
	check("энергетик (0% сытости) не лечит", Healing.food_hp_percent("energy_drink") == 0)
	check("руда не лечит", Healing.item_hp_percent("iron_ore") == 0)
	check("сытый спит в полную силу", is_equal_approx(Healing.sleep_fed_factor(75.0), 1.0))
	check("голодный — в четверть силы", is_equal_approx(Healing.sleep_fed_factor(0.0), 0.25))


func _test_full_sleep_fed_heals() -> void:
	_set_hp_percent(10.0)
	GameState.set_stamina(0.0)
	GameState.set_hunger(100.0)
	var plan := HouseSleep.plan(GameState.stamina, GameState.hunger)
	check_near("план: полная ночь сытым обещает +75% HP", float(plan["hp_gain"]), 75.0)
	_events.clear()
	var r := HouseSleep.sleep_now()
	check("сон состоялся", bool(r["ok"]))
	check_near("полная ночь сытым: HP 10% → 85%", _hp_percent(), 85.0)
	check_near("бодрость полная", GameState.stamina, 100.0, 0.01)
	check_near("сон съел 50% сытости, как и раньше", GameState.hunger, 50.0, 0.3)
	check("событие healed от сна", _events_of("healed").size() == 1
		and String(_events_of("healed")[0]["source"]) == "sleep")


func _test_hungry_sleep_heals_less() -> void:
	_set_hp_percent(10.0)
	GameState.set_stamina(0.0)
	GameState.set_hunger(55.0)
	var r := HouseSleep.sleep_now()
	check("полуголодным уснул (сытости хватило на ночь)", bool(r["ok"]))
	var healed := _hp_percent() - 10.0
	# средняя сытость 55 − 25 = 30 → сила (30 − 10) / (60 − 10) между 0.25 и 1 → 0.55
	check_near("полуголодный сон лечит слабее: +41%", healed, 75.0 * 0.55, 0.3)
	check("и заметно меньше сытого (75%)", healed < 60.0)


func _test_sleep_scales_with_hours() -> void:
	_set_hp_percent(100.0)
	GameState.set_stamina(50.0)
	GameState.set_hunger(100.0)
	var p_full := HouseSleep.plan(50.0, 100.0, 100.0)
	check_near("здоровому бодрость 50% — 4 часа, как раньше", float(p_full["hours"]), 4.0, 0.01)
	check_near("здоровому лечить нечего", float(p_full["hp_gain"]), 0.0, 0.01)
	var p_hurt := HouseSleep.plan(50.0, 100.0, 50.0)
	# 50% HP в полную силу — 50 / 9.375 = 5.33 часа: раненый спит дольше усталого
	check_near("раненый спит дольше: 5.33 часа", float(p_hurt["hours"]), 50.0 / (75.0 / 8.0), 0.01)
	check_near("и добирает HP целиком", float(p_hurt["hp_gain"]), 50.0, 0.05)
	check_near("короткий сон лечит пропорционально: 2 ч → +18.75%",
		Healing.sleep_hp_percent(2.0, 100.0, HouseSleep.hunger_cost(2.0)), 75.0 * 2.0 / 8.0, 0.01)


func _test_wounded_but_rested_can_sleep() -> void:
	_set_hp_percent(40.0)
	GameState.set_stamina(100.0)
	GameState.set_hunger(100.0)
	var r := HouseSleep.sleep_now()
	check("бодрый, но раненый может лечь ради здоровья", bool(r["ok"]))
	check_near("и встаёт здоровым", _hp_percent(), 100.0, 0.05)
	check_near("спал 6.4 часа (60% HP при 9.375% в час)", float(r["hours"]), 6.4, 0.01)


func _test_rested_and_healthy_refused() -> void:
	_set_hp_percent(95.0)
	GameState.set_stamina(95.0)
	GameState.set_hunger(100.0)
	var r := HouseSleep.sleep_now()
	check("бодрый и почти здоровый — кровать не пускает", not bool(r["ok"]))
	check_near("HP не тронуто", _hp_percent(), 95.0, 0.01)


func _test_wounded_hungry_refused() -> void:
	_set_hp_percent(40.0)
	GameState.set_stamina(100.0)
	GameState.set_hunger(10.0)
	var r := HouseSleep.sleep_now()
	check("раненый, но голодный — «сначала поешь»", not bool(r["ok"]) and String(r["reason"]).contains("поешь"))
	check_near("сытость не тронута", GameState.hunger, 10.0, 0.01)


func _test_tired_wounded_half_fed() -> void:
	# Раньше: бодрость 60% → 3.2 ч и 20% сытости. Раненый сон не должен отнимать
	# этот сон у того, кому на полную ночь сытости не хватает.
	var p := HouseSleep.plan(60.0, 40.0, 20.0)
	check("усталый раненый с 40% сытости всё равно спит", bool(p["ok"]))
	check_near("спит столько, на сколько хватит сытости (6.4 ч)", float(p["hours"]), 6.4, 0.01)
	check("и не меньше, чем нужно бодрости (3.2 ч)", float(p["hours"]) >= 3.2)


func _test_food_heals_by_nutrition() -> void:
	GameState.inventory.clear()
	_set_hp_percent(50.0)
	GameState.set_hunger(20.0)
	GameState.add_item("food_bar", 1)
	_events.clear()
	var r := HouseFood.eat("food_bar")
	check("батончик съеден", bool(r["ok"]))
	check_near("батончик: +5% HP", _hp_percent(), 55.0, 0.01)
	var ate := _events_of("ate")
	check("событие ate несёт hp", ate.size() == 1 and float(ate[0].get("hp", 0.0)) > 0.0)
	_set_hp_percent(50.0)
	HouseFood.eat_now("food_steak")
	check_near("стейк на месте: +25% HP", _hp_percent(), 75.0, 0.01)
	_set_hp_percent(50.0)
	GameState.set_stamina(10.0)
	HouseFood.eat_now("energy_drink")
	check_near("энергетик HP не лечит", _hp_percent(), 50.0, 0.01)
	# Витрина: значок +HP числом в эффектах блюда, словами — только в подсказке.
	var steak := {}
	for o in ShopItems.food_offers():
		if String(o["ref"]) == "food_steak":
			steak = o
	var hp_chip := false
	for e in steak.get("effects", []):
		if e["icon"] == ShopArt.ui("icon_hp") and String(e["text"]) == "+25":
			hp_chip = true
	check("карточка стейка: значок HP «+25»", hp_chip)
	check("подсказка стейка говорит про здоровье", String(steak.get("body", "")).contains("здоровье +25%"))


func _test_full_meal_and_sleep_reach_90() -> void:
	for food in ["food_steak", "food_dumplings"]:
		_set_hp_percent(1.0)
		GameState.set_stamina(0.0)
		GameState.set_hunger(25.0)
		HouseFood.eat_now(food)
		var r := HouseSleep.sleep_now()
		check("%s + полный сон: сон состоялся" % food, bool(r["ok"]))
		check("%s + полный сон → HP %.0f%% (90–100%%)" % [food, _hp_percent()], _hp_percent() >= 90.0)


func _test_medkit_in_shop() -> void:
	var g := ShopCatalog.good("medkit", "coins")
	check("аптечка — товар лавки за монеты", not g.is_empty())
	check("цена аптечки 150 монет", ShopCatalog.good_price(g, "coins") == 150)
	check("аптечка кладётся в рюкзак (grant_item)", String(g.get("effect", "")) == "grant_item"
		and String(g.get("item", "")) == "medkit")
	check("у аптечки есть значок", ShopArt.item_icon("medkit") == ShopArt.tex("item_medkit")
		and ShopArt.tex("item_medkit") != null)
	check("у аптечки есть вес и имя", Balance.get_mineral_weight("medkit") > 0.0
		and String(Balance.get_mineral("medkit").get("name_ru", "")) == "Аптечка")
	var offer := {}
	for o in ShopItems.goods_offers("food"):
		if String(o["ref"]) == "medkit":
			offer = o
	check("плитка аптечки на полке «Еда»", not offer.is_empty())
	var hp_chip := false
	for e in offer.get("effects", []):
		if e["icon"] == ShopArt.ui("icon_hp") and String(e["text"]) == "+50":
			hp_chip = true
	check("карточка аптечки: значок HP «+50»", hp_chip)
	check("аптечка — не «вид добычи» достижений", not Achievements.is_kind("medkit"))


func _test_medkit_purchase_place_rules() -> void:
	GameState.inventory.clear()
	GameState.coins = 1000
	GameState.ext.erase("shop")
	# огород: монетные покупки — только у двери (§15)
	GameState.house_is_indoors = false
	GameState.player_depth = 0
	var r := ShopService.buy("medkit", "coins")
	check("в огороде аптечку не купить", not bool(r["ok"]) and GameState.coins == 1000)
	# у двери — можно
	GameState.house_is_indoors = true
	GameState.house_room = "hall"
	r = ShopService.buy("medkit", "coins")
	check("у двери аптечка куплена", bool(r["ok"]))
	check("списано 150 монет", GameState.coins == 850)
	check("аптечка в рюкзаке", GameState.get_item_count("medkit") == 1)
	# под землёй — за ролик, из общего лимита
	GameState.house_is_indoors = false
	GameState.player_depth = 40
	var left := ShopRemote.left_today()
	r = ShopService.buy("medkit", "coins")
	check("под землёй — за ролик", bool(r["ok"]) and bool(r.get("remote", false)))
	check("ролик списан из лимита", ShopRemote.left_today() == left - 1)
	check("вторая аптечка в рюкзаке", GameState.get_item_count("medkit") == 2)
	GameState.player_depth = 0


func _test_medkit_use() -> void:
	_set_hp_percent(100.0)
	var n := GameState.get_item_count("medkit")
	var r := HouseFood.eat("medkit")
	check("при полном здоровье аптечка не тратится", not bool(r["ok"]) and GameState.get_item_count("medkit") == n)
	_set_hp_percent(20.0)
	GameState.set_hunger(30.0)
	_events.clear()
	r = HouseFood.eat("medkit")
	check("аптечка применена кнопкой рюкзака", bool(r["ok"]))
	check_near("аптечка: HP 20% → 70%", _hp_percent(), 70.0, 0.01)
	check("аптечка израсходована", GameState.get_item_count("medkit") == n - 1)
	check_near("аптечка сытость не трогает", GameState.hunger, 30.0, 0.01)
	check("аптечка — не еда: «поешь N раз» не засчитан", _events_of("ate").is_empty())
	check("событие healed от аптечки", _events_of("healed").size() == 1
		and String(_events_of("healed")[0]["source"]) == "medkit")


func _test_death_fee() -> void:
	GameState.inventory.clear()
	GameState.black_box.clear()
	GameState.add_item("silver", 3)
	GameState.add_item("food_bar", 1)
	GameState.add_item("medkit", 1)
	GameState.add_to_black_box("gold", 2)
	GameState.coins = 1000
	_events.clear()
	GameState.die()
	check("смерть: весь рюкзак пропал (руда, еда, аптечка)", GameState.inventory.is_empty())
	check("смерть: чёрный ящик цел", int(GameState.black_box.get("gold", 0)) == 2)
	check("смерть: скорая забрала 200", GameState.coins == 800)
	var amb := _events_of("ambulance")
	check("событие ambulance {coins: 200}", amb.size() == 1 and int(amb[0]["coins"]) == 200)
	check("плата скорой — не «трата» для заданий дня", _events_of("spent").is_empty())
	GameState.respawn()
	check("после респавна жив и здоров", GameState.is_alive and is_equal_approx(GameState.hp, GameState.get_max_hp()))

	GameState.coins = 50
	GameState.die()
	check("меньше 200 — забрали сколько было", GameState.coins == 0 and Healing.last_death_fee == 50)
	GameState.respawn()
	GameState.die()
	check("без монет — в минус не уходим", GameState.coins == 0 and Healing.last_death_fee == 0)
	GameState.respawn()


func _test_death_card() -> void:
	GameState.reset_progress()
	GameState.coins = 600
	GameState.add_item("iron_ore", 4)
	GameState.player_depth = 80
	StoryState.set_flag("gold_sold", true)
	var dir := FeelDirector.new()
	add_child(dir)
	await get_tree().process_frame
	GameState.add_item("iron_ore", 1)
	GameState.die()
	var rep: Dictionary = dir._pending
	check("отчёт смерти знает плату скорой", int(rep.get("fee", 0)) == 200)
	check("в отчёте монеты уже после платы", int(rep["coins"]) == 400)
	check("карточку стоит показать", DeathCard.worth_showing(rep))
	var empty := DeathCard.build_report({}, 0, "", 200)
	check("даже с пустым рюкзаком на поверхности: −200 — повод показать карточку", DeathCard.worth_showing(empty))
	var card := DeathCard.new()
	add_child(card)
	await get_tree().process_frame
	card.open(rep)
	var fee_node := card.find_child("Fee", true, false) as Control
	check("на карточке есть «скорая −200»", fee_node != null and fee_node.visible)
	var fee_label := false
	if fee_node != null:
		for l in fee_node.find_children("*", "Label", true, false):
			if String((l as Label).text) == "−200":
				fee_label = true
	check("число на чипе — «−200»", fee_label)
	check("у «скорой» подсказка Tip", fee_node != null and fee_node.has_meta(Tip.META))
	card.close()
	await get_tree().process_frame   # старый корень карточки уходит из дерева к концу кадра
	var rep0 := DeathCard.build_report({"iron_ore": 1}, 10, "", 0)
	card.open(rep0)
	fee_node = card.find_child("Fee", true, false) as Control
	check("без платы чипа скорой нет", fee_node == null or not fee_node.visible)
	card.close()
	GameState.respawn()
	card.queue_free()
	dir.queue_free()
	await get_tree().process_frame


## Экономика лечения: смерть дороже аптечки, аптечка не отменяет таблетку.
func _test_economy_ordering() -> void:
	var medkit := ShopCatalog.good_price(ShopCatalog.good("medkit", "coins"), "coins")
	check("аптечка (%d) дешевле платы скорой (%d) — лечиться выгоднее, чем умирать" % [medkit, Healing.death_fee_coins()],
		medkit < Healing.death_fee_coins())
	var pill := ShopCatalog.good("full_restore_pill", "dollars")
	check("таблетка по-прежнему полное восстановление трёх полосок", String(pill.get("effect", "")) == "full_restore")
	check("аптечка лечит не всё (таблетка не лишняя)", Healing.medkit_hp_percent() < 100)
	var steak_coins := HouseConfig.food_price_coins("food_steak")
	check("аптечка лечит дешевле еды за процент HP", float(medkit) / Healing.medkit_hp_percent()
		< float(steak_coins) / Healing.food_hp_percent("food_steak"))

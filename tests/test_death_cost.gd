extends Node
## test_death_cost — цена смерти раунда 5 (ветка death-cost; ГДД §7 «Цена смерти»).
## Владелец: «Смерть должна стоить 5 процентов, но не менее 50, не более 5000. Смерть не
## должна быть удобным способом копать вниз и просто потом, чтобы не лететь, — умирать».
##  1. Плата: границы 0, 49, 50, 999, 1000, 100000 монет (и соседи), в минус не уходим.
##  2. Поездка скорой: прямой полёт × коэффициент, потолок; смерть не быстрее лучшего
##     собственного подъёма (кроме потолка на сверхглубине).
##  3. Полоски после скорой: HP 50%, сытость и бодрость как были (не ниже 25%); до конца
##     онбординга — по-старому.
##  4. Настоящая main.tscn: смерть на 400 — герой мёртв и дома, карточка с отсчётом не
##     закрывается, сейв посреди поездки её продолжает, по приезде HP половина.
## Сценой — нужны автозагрузки:  godot --headless --path . res://tests/test_death_cost.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== test_death_cost ===")
	GameState.world_seed = 4242
	_test_fee_bounds()
	_test_fee_on_die()
	_test_ride_formula()
	_test_ride_not_a_lift()
	_test_respawn_bars()
	await _test_main_ride()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# 1. Плата
# ---------------------------------------------------------------------------

func _test_fee_bounds() -> void:
	var cases := [[0, 0], [1, 1], [49, 49], [50, 50], [51, 50], [999, 50], [1000, 50], [1019, 50], [1020, 51],
		[10000, 500], [99999, 4999], [100000, 5000], [100020, 5000], [1000000, 5000], [-30, 0]]
	for c in cases:
		var got := Healing.death_fee_for(int(c[0]))
		check("плата с %d монет = %d" % [c[0], c[1]], got == int(c[1]), "получено %d" % got)


func _test_fee_on_die() -> void:
	GameState.reset_progress()
	StoryState.set_flag("gold_sold", true)
	for c in [[0, 0], [49, 0], [50, 0], [999, 949], [1000, 950], [100000, 95000]]:
		GameState.is_alive = true
		GameState.coins = int(c[0])
		GameState.add_item("silver", 2)
		GameState.die()
		check("смерть с %d монет: осталось %d, рюкзак пуст" % [c[0], c[1]],
			GameState.coins == int(c[1]) and GameState.inventory.is_empty() and Healing.last_death_fee == int(c[0]) - int(c[1]),
			"монеты %d, плата %d" % [GameState.coins, Healing.last_death_fee])
		DeathRide.respawn()


# ---------------------------------------------------------------------------
# 2. Поездка скорой
# ---------------------------------------------------------------------------

func _test_ride_formula() -> void:
	check("прямой полёт с 300 на джетпаке (7.5 кл/с) = 40 + 2.5 с разгона",
		is_equal_approx(DeathRide.flight_seconds(300, "jetpack", false), 42.5))
	check("прямой полёт с 1300 на топовом (25 кл/с) = 52 + 2.5 с",
		is_equal_approx(DeathRide.flight_seconds(1300, "jetpack_top", false), 54.5))
	check("без ранца — как базовый ранец (2.5 кл/с)",
		is_equal_approx(DeathRide.flight_seconds(100, "", false), DeathRide.flight_seconds(100, "backpack", false)))
	check("бурмобиль летит на 30% быстрее — и скорая с ним",
		DeathRide.flight_seconds(300, "jetpack", true) < DeathRide.flight_seconds(300, "jetpack", false))
	check("коэффициент: у поверхности 1, на 150 — 1.5, с 300 — 2",
		is_equal_approx(DeathRide.factor(0), 1.0) and is_equal_approx(DeathRide.factor(150), 1.5)
		and is_equal_approx(DeathRide.factor(300), 2.0) and is_equal_approx(DeathRide.factor(5000), 2.0))
	check("у самой поверхности не везёт (2 клетки)", DeathRide.ride_seconds(2, "backpack", false) == 0.0)
	check("с 300 на джетпаке — 85 с (вдвое дольше полёта)", is_equal_approx(DeathRide.ride_seconds(300, "jetpack", false), 85.0))
	check("с 1300 на топовом — 109 с", is_equal_approx(DeathRide.ride_seconds(1300, "jetpack_top", false), 109.0))
	check("потолок 150 с (1300 на простом джетпаке)", is_equal_approx(DeathRide.ride_seconds(1300, "jetpack", false), 150.0))
	var newbie := DeathRide.ride_seconds(40, "backpack", false)
	check("новичок, разбившийся на 40 с базовым ранцем, ждёт меньше 20 с (%.1f)" % newbie, newbie > 15.0 and newbie < 20.0)


## «Не лифт наверх»: на любых глубинах и ступенях ранца скорая не быстрее лучшего
## собственного подъёма — пока не упёрлась в потолок (тогда смерть уже стоит 5000 и рюкзак
## экзотики). Печатает таблицу для ГДД §7.
func _test_ride_not_a_lift() -> void:
	var gears := ["backpack", "backpack_plus", "jetpack", "jetpack_top"]
	var bad: Array = []
	for g in gears:
		var line := "  %-14s" % g
		for d in [40, 100, 300, 700, 1300, 3000]:
			var fly := DeathRide.flight_seconds(d, g, false)
			var ride := DeathRide.ride_seconds(d, g, false)
			line += "  %4d: %5.0f/%-5.0f" % [d, fly, ride]
			if ride + 0.01 < fly and ride < DeathRide.max_seconds() - 0.01:
				bad.append("%s@%d" % [g, d])
			if ride + 0.01 < fly and fly < 150.0:
				bad.append("%s@%d (потолок раньше полёта)" % [g, d])
		print(line, "   (глубина: полёт/скорая, с)")
	check("скорая не быстрее прямого полёта, пока не упёрлась в потолок", bad.is_empty(), str(bad))
	# с 300 клеток — уже вдвое дольше лучшего полёта: «умереть, чтобы не лететь» не экономит время
	for g in ["backpack_plus", "jetpack", "jetpack_top"]:
		for d in [300, 700, 1300]:
			var fly := DeathRide.flight_seconds(d, g, false)
			var ride := DeathRide.ride_seconds(d, g, false)
			if ride < DeathRide.max_seconds() - 0.01:
				check("%s, глубина %d: скорая (%.0f с) ≥ 2 × полёт (%.0f с)" % [g, d, ride, fly], ride >= 2.0 * fly - 0.01)


# ---------------------------------------------------------------------------
# 3. Полоски после скорой
# ---------------------------------------------------------------------------

func _test_respawn_bars() -> void:
	GameState.reset_progress()
	DeathRide.reset()
	StoryState.set_flag("gold_sold", true)
	GameState.grant_gear("jetpack")
	GameState.set_current_gear("jetpack")
	GameState.hunger = 40.0
	GameState.stamina = 10.0
	GameState.coins = 0
	GameState.die()
	var t := DeathRide.start(500)
	check("смерть на 500 с джетпаком: поездка %.1f с" % t, absf(t - DeathRide.ride_seconds(500, "jetpack", false)) < 0.01 and t > 0.0)
	check("пока едет — riding, героя нет", DeathRide.riding() and not GameState.is_alive)
	check("остаток поездки записан в сейв (ext)", float((GameState.ext_get(DeathRide.EXT_KEY, {}) as Dictionary).get("left", 0.0)) > 0.0)
	var done := DeathRide.tick(1.0)
	check("тик: секунда прошла, ещё едем", not done and absf(DeathRide.seconds_left() - (t - 1.0)) < 0.01)
	check("прогресс растёт", DeathRide.progress() > 0.0 and DeathRide.progress() < 1.0)
	DeathRide.skip()
	check("промотали — приехали", DeathRide.tick(0.0))
	var clock0 := GameState.game_clock_hours
	DeathRide.respawn()
	check("приезд: жив, HP — половина", GameState.is_alive and absf(GameState.hp - GameState.get_max_hp() * 0.5) < 0.01)
	check("сытость как была (40%)", is_equal_approx(GameState.hunger, 40.0))
	check("бодрость не ниже 25% (была 10%)", is_equal_approx(GameState.stamina, 25.0))
	check("часы мира догнали время поездки", GameState.game_clock_hours > clock0)
	check("сейв поездки очищен", not GameState.ext.has(DeathRide.EXT_KEY))
	check("после приезда не едем", not DeathRide.riding() and DeathRide.seconds_left() == 0.0)

	# смерть у поверхности: без поездки, но полоски — те же правила
	GameState.hunger = 80.0
	GameState.stamina = 90.0
	GameState.die()
	check("у поверхности (1 клетка) поездки нет", DeathRide.start(1) == 0.0 and not DeathRide.riding())
	DeathRide.respawn()
	check("и всё равно HP половина, полоски как были", absf(GameState.hp - GameState.get_max_hp() * 0.5) < 0.01
		and is_equal_approx(GameState.hunger, 80.0) and is_equal_approx(GameState.stamina, 90.0))

	# до конца онбординга смерть мягкая
	StoryState.set_flag("gold_sold", false)
	GameState.hunger = 30.0
	GameState.die()
	check("онбординг: поездки нет даже на 500", DeathRide.start(500) == 0.0)
	DeathRide.respawn()
	check("онбординг: полные полоски, как раньше", is_equal_approx(GameState.hp, GameState.get_max_hp())
		and is_equal_approx(GameState.hunger, 100.0) and is_equal_approx(GameState.stamina, 100.0))
	StoryState.set_flag("gold_sold", true)

	# чужой respawn() посреди поездки её обрывает, новая смерть — новая поездка
	GameState.die()
	DeathRide.start(500)
	GameState.respawn()
	check("чужой респавн обрывает поездку", not DeathRide.riding())
	GameState.die()
	check("новая смерть не подхватывает старый остаток", not DeathRide.riding())
	DeathRide.respawn()


# ---------------------------------------------------------------------------
# 4. Настоящая игра
# ---------------------------------------------------------------------------

func _fresh_main(keep_save: bool = false) -> Node2D:
	if not keep_save:
		for f in ["user://save.json", "user://save.json.bak", "user://records.json"]:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		GameState.reset_progress()
		StoryState.delete_from_disk()
		GameState.story_flags = {}
		GameState.story_seen = []
		GameState.story_queue = []
		for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure",
				"workshop", "death", "backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2"]:
			StoryState.mark_seen(id)
		for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "gold_sold", "food_ordered"]:
			StoryState.set_flag(f)
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	await _frames(6)
	return m


func _hold(key: Key, sec: float) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.keycode = key
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		if pressed:
			await get_tree().create_timer(sec).timeout


func _card(main: Node) -> DeathCard:
	return main.find_child("DeathCard", true, false) as DeathCard


func _test_main_ride() -> void:
	var main: Node2D = await _fresh_main()
	var p = main.player
	GameState.max_depth_reached = 450
	GameState.grant_gear("jetpack")
	GameState.set_current_gear("jetpack")
	GameState.coins = 1000
	GameState.add_item("silver", 3)
	GameState.hunger = 40.0
	GameState.stamina = 10.0
	p.x = 16.5
	p.y = 400.5
	p.frozen = false
	await _frames(1)
	var expect := DeathRide.ride_seconds(p.cell_y(), "jetpack", false)
	GameState.coins = 1000   # после кадра: награды достижений за глубину уже пришли
	GameState.take_damage(1e6, "fall")
	await _frames(3)
	check("смерть на 400: герой мёртв и уже дома, скорая едет", not GameState.is_alive and DeathRide.riding() and p.y < 1.0)
	check("поездка как по формуле (%.1f с)" % expect, absf(DeathRide.total_seconds() - expect) < 0.05)
	# первая смерть открывает достижение с наградой монетами — сверяем саму плату
	check("плата 5% от 1000 = 50, рюкзак пуст", Healing.last_death_fee == 50 and GameState.coins >= 950
		and GameState.inventory.is_empty(), "плата %d монеты %d" % [Healing.last_death_fee, GameState.coins])
	await get_tree().create_timer(0.9).timeout
	var card := _card(main)
	check("карточка открыта сразу, не после респавна", card != null and card.is_open() and card.is_riding())
	var ride_row := card.find_child("Ride", true, false) as Control if card != null else null
	check("на карточке полоса поездки с отсчётом", ride_row != null and ride_row.visible
		and card.find_child("RideLeft", true, false) != null)
	if card != null:
		card.close()
	check("пока едет — карточку не закрыть", card != null and card.is_open())
	var left0 := DeathRide.seconds_left()
	await _frames(10)
	check("отсчёт идёт", DeathRide.seconds_left() < left0)
	var x0: float = p.x
	await _hold(KEY_D, 0.3)
	check("пока едет — ввод героя не двигает", is_equal_approx(p.x, x0) and not GameState.is_alive, "x %.2f -> %.2f" % [x0, p.x])

	# выход из игры посреди поездки её не отменяет
	var left_saved := DeathRide.seconds_left()
	SaveSystem.save_game()
	main.free()
	await _frames(2)
	var main2: Node2D = await _fresh_main(true)
	check("загрузка посреди поездки: скорая всё ещё едет", not GameState.is_alive and DeathRide.riding()
		and DeathRide.seconds_left() > left_saved - 2.0, "осталось %.1f, было %.1f" % [DeathRide.seconds_left(), left_saved])
	await get_tree().create_timer(0.3).timeout
	var card2 := _card(main2)
	check("после загрузки карточка снова ведёт отсчёт", card2 != null and card2.is_open() and card2.is_riding())
	DeathRide.skip()
	await _frames(3)
	check("приехали: жив, HP половина", GameState.is_alive
		and absf(GameState.hp - GameState.get_max_hp() * DeathRide.respawn_hp_percent() / 100.0) < 0.5)
	check("сытость как была, бодрость не ниже 25%", absf(GameState.hunger - 40.0) < 0.5 and absf(GameState.stamina - 25.0) < 0.5,
		"сытость %.1f бодрость %.1f" % [GameState.hunger, GameState.stamina])
	check("карточка теперь закрывается", card2 != null and not card2.is_riding())
	if card2 != null:
		card2.close()
	check("и закрылась", card2 != null and not card2.is_open())
	check("сейв поездки очищен", not GameState.ext.has(DeathRide.EXT_KEY))
	main2.free()
	await _frames(2)

extends Node
## test_death_window — окно смерти (ГДД §7 «Цена смерти»; владелец, разбор чисел 26.10:
## «когда умираешь, покажи окно: ты умер — причина смерти, потеряно — список и изображения
## предметов, потрачено на больницу денег»; «Да, только хп полное»).
##  1. Причина приходит из источника урона, а не угадывается: голод, изнеможение, падение
##     (с высотой), лава, монстр, страж полости, снаряд (кто стрелял), босс, ртуть, неизвестное;
##     фразы ru/en, падеж «клетки/клеток».
##  2. Потери: рюкзак до очистки, дорогое первым, плитки со значками и ×N, пустой рюкзак,
##     переполнение «+N».
##  3. Плата больнице: 5% монет, 50…5000, меньше 50 — сколько есть; в окне «−N».
##  4. После смерти: HP полное, сытость и бодрость как были, но не ниже 25%; онбординг — всё полное.
##  5. Настоящая main.tscn: поездки нет — герой сразу дома и жив, окно открывается, «Дальше»
##     нажимается пальцем (мышью), пока окно открыто — HUD героя не ведёт; сейв мёртвым — респавн.
## Сценой — нужны автозагрузки:  godot --headless --path . res://tests/test_death_window.tscn

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
	print("=== test_death_window ===")
	GameState.world_seed = 4242
	Settings.language = "ru"
	_test_no_ride_left()
	_test_cause_texts()
	_test_survival_causes()
	_test_fee_bounds()
	_test_respawn_bars()
	await _test_lost_window()
	await _test_main()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


## Убита ли герой этим уроном — и какую причину запомнил GameState.
func _kill(source: String, info: Dictionary = {}) -> Dictionary:
	GameState.is_alive = true
	GameState.hp = 1.0
	GameState.take_damage(1e6, source, info)
	var c := GameState.death_cause.duplicate()
	GameState.respawn()
	return c


# ---------------------------------------------------------------------------
# 0. Скорой нет
# ---------------------------------------------------------------------------

func _test_no_ride_left() -> void:
	var names: Array = []
	for c in ProjectSettings.get_global_class_list():
		names.append(String(c["class"]))
	check("класса поездки (DeathRide) больше нет", not names.has("DeathRide") and names.has("DeathWindow"))
	check("старой карточки (DeathCard) больше нет", not names.has("DeathCard"))
	var death: Dictionary = Healing.data().get("death", {})
	check("healing.json: death.ride убран", not death.has("ride"))
	var hp_node: Dictionary = death.get("respawn", {}).get("hp_percent", {})
	check("healing.json: HP после смерти 100%, решение владельца (proposed: false)",
		int(hp_node.get("value", 0)) == 100 and not bool(hp_node.get("proposed", true)))
	var bars_node: Dictionary = death.get("respawn", {}).get("bars_min_percent", {})
	check("healing.json: полоски не ниже 25%, решение владельца", int(bars_node.get("value", 0)) == 25
		and not bool(bars_node.get("proposed", true)))
	var texts := FileAccess.get_file_as_string("res://data/death_window.json").to_lower()
	var re := RegEx.create_from_string("скор(ая|ой|ую|ее)")
	check("в текстах окна нет слова «скорая»", re.search(texts) == null and not texts.contains("ambulance"))


# ---------------------------------------------------------------------------
# 1. Причины
# ---------------------------------------------------------------------------

func _test_cause_texts() -> void:
	GameState.reset_progress()
	var cases := [
		["starvation", {}, "Умер с голоду"],
		["exhaustion", {}, "Умер от изнеможения"],
		["fall", {"cells": 42}, "Разбился при падении с высоты 42 клеток"],
		["fall", {"cells": 21}, "Разбился при падении с высоты 21 клетки"],
		["fall", {}, "Разбился при падении"],
		["lava", {}, "Сгорел в лаве"],
		["heat", {}, "Сгорел от жары"],
		["monster:cinder_grub", {"guard": false}, "Убит монстром: Угольный червь"],
		["monster:cave_bat", {"guard": true}, "Убит стражем полости: Гротовая мышь"],
		["projectile:acid", {"id": "acid_spitter"}, "Убит стражем полости: Плевун"],
		["projectile:acid", {}, "Убит выстрелом монстра"],
		["boss:slam", {}, "Убит боссом: Идол Бездны"],
		["mercury", {}, "Отравился ртутью"],
		["test", {}, "Погиб"],
		["", {}, "Погиб"],
	]
	for c in cases:
		var cause := _kill(String(c[0]), c[1])
		var got := DeathCause.phrase(cause)
		check("причина «%s» → «%s»" % [c[0], c[2]], got == String(c[2]), "получено «%s» (%s)" % [got, str(cause)])
		check("  значок причины «%s» есть" % c[0], DeathCause.icon(cause) != null)
	check("die() без причины — «Погиб»", _die_plain() == "Погиб")
	check("монстр: значок — кадр его листа (портрет), а не общий клык",
		DeathCause.icon(DeathCause.make("monster:cave_bat")) is AtlasTexture)
	check("босс: значок — кадр листа Идола", DeathCause.icon(DeathCause.make("boss:wave")) is AtlasTexture)
	check("подсказка Tip к причине есть (падение)", DeathCause.hint(DeathCause.make("fall")) != "")
	for n in [[1, "1 клетки"], [5, "5 клеток"], [11, "11 клеток"], [21, "21 клетки"], [101, "101 клетки"], [111, "111 клеток"]]:
		check("«с высоты %s»" % n[1], DeathCause.cells_text(int(n[0])) == String(n[1]), DeathCause.cells_text(int(n[0])))
	Settings.language = "en"
	check("en: заголовок «You died»", DeathCause.text("title") == "You died")
	check("en: страж полости по-английски", DeathCause.phrase(DeathCause.make("monster:cave_bat", {"guard": true}))
		== "Killed by a cave guard: Cave Bat")
	check("en: падение «Fell from a height of 1 cell»", DeathCause.phrase(DeathCause.make("fall", {"cells": 1}))
		== "Fell from a height of 1 cell")
	Settings.language = "uk"
	check("язык без перевода — русская строка", DeathCause.text("title") == "Ты умер")
	Settings.language = "ru"


func _die_plain() -> String:
	GameState.is_alive = true
	GameState.die()
	var s := DeathCause.phrase(GameState.death_cause)
	GameState.respawn()
	return s


## Настоящие пути урона: голод в тике выживания, лава при копке, падение героя, удары боя.
func _test_survival_causes() -> void:
	GameState.reset_progress()
	GameState.hp = 0.5
	GameState.set_hunger(0.0)
	GameState.set_stamina(50.0)
	for _i in 40:
		if not GameState.is_alive:
			break
		GameState._tick_survival(1.0)
	check("голод в тике выживания убивает с причиной starvation", not GameState.is_alive
		and String(GameState.death_cause.get("source", "")) == "starvation", str(GameState.death_cause))
	GameState.respawn()
	if Balance.get_hp_drain_per_second(false, true) > 0.0:
		GameState.hp = 0.5
		GameState.set_hunger(60.0)
		GameState.set_stamina(0.0)
		for _i in 40:
			if not GameState.is_alive:
				break
			GameState._tick_survival(1.0)
		check("пустая бодрость убивает с причиной exhaustion", String(GameState.death_cause.get("source", "")) == "exhaustion")
		GameState.respawn()
	GameState.hp = 1.0
	Heat.burn_digger(1.0)
	check("лава при копке: причина lava", not GameState.is_alive and String(GameState.death_cause.get("source", "")) == "lava")
	GameState.respawn()


# ---------------------------------------------------------------------------
# 3. Плата больнице
# ---------------------------------------------------------------------------

func _test_fee_bounds() -> void:
	var cases := [[0, 0], [1, 1], [49, 49], [50, 50], [51, 50], [999, 50], [1000, 50], [1019, 50], [1020, 51],
		[10000, 500], [99999, 4999], [100000, 5000], [100020, 5000], [1000000, 5000], [-30, 0]]
	for c in cases:
		var got := Healing.death_fee_for(int(c[0]))
		check("плата больнице с %d монет = %d" % [c[0], c[1]], got == int(c[1]), "получено %d" % got)
	GameState.reset_progress()
	StoryState.set_flag("gold_sold", true)
	for c in [[0, 0], [30, 0], [49, 0], [50, 0], [999, 949], [1000, 950], [20000, 19000], [100000, 95000], [250000, 245000]]:
		GameState.is_alive = true
		GameState.coins = int(c[0])
		GameState.add_item("silver", 2)
		GameState.die()
		var rep := DeathWindow.report_now()
		check("смерть с %d монет: осталось %d, в отчёте окна −%d" % [c[0], c[1], int(c[0]) - int(c[1])],
			GameState.coins == int(c[1]) and int(rep["fee"]) == int(c[0]) - int(c[1]) and GameState.inventory.is_empty(),
			"монеты %d, плата %d" % [GameState.coins, int(rep["fee"])])
		Healing.respawn_after_death()


# ---------------------------------------------------------------------------
# 4. Полоски после смерти
# ---------------------------------------------------------------------------

func _test_respawn_bars() -> void:
	GameState.reset_progress()
	StoryState.set_flag("gold_sold", true)
	GameState.hunger = 40.0
	GameState.stamina = 10.0
	GameState.die()
	Healing.respawn_after_death()
	check("после смерти жив, HP полное", GameState.is_alive and is_equal_approx(GameState.hp, GameState.get_max_hp()))
	check("сытость как была (40%)", is_equal_approx(GameState.hunger, 40.0))
	check("бодрость не ниже 25% (была 10%)", is_equal_approx(GameState.stamina, 25.0))
	GameState.hunger = 0.0
	GameState.stamina = 90.0
	GameState.die()
	Healing.respawn_after_death()
	check("умер с голоду — сытость 25%, бодрость как была", is_equal_approx(GameState.hunger, 25.0)
		and is_equal_approx(GameState.stamina, 90.0) and is_equal_approx(GameState.hp, GameState.get_max_hp()))
	GameState.ext["death_ride"] = {"left": 30.0, "total": 60.0}
	GameState.die()
	Healing.respawn_after_death()
	check("остаток поездки из старого сейва стёрт", not GameState.ext.has("death_ride"))
	StoryState.set_flag("gold_sold", false)
	GameState.hunger = 30.0
	GameState.die()
	Healing.respawn_after_death()
	check("онбординг: все полоски полные", is_equal_approx(GameState.hp, GameState.get_max_hp())
		and is_equal_approx(GameState.hunger, 100.0) and is_equal_approx(GameState.stamina, 100.0))
	StoryState.set_flag("gold_sold", true)


# ---------------------------------------------------------------------------
# 2. Потери и вёрстка окна
# ---------------------------------------------------------------------------

func _labels(n: Node) -> Array:
	var out: Array = []
	for l in n.find_children("*", "Label", true, false):
		out.append(String((l as Label).text))
	return out


func _test_lost_window() -> void:
	GameState.reset_progress()
	StoryState.set_flag("gold_sold", true)
	GameState.coins = 4280
	for it in [["iron_ore", 3], ["diamond", 1], ["medkit", 1], ["food_bar", 2]]:
		GameState.add_item(String(it[0]), int(it[1]))
	GameState.player_depth = 410
	GameState.hp = 1.0
	GameState.take_damage(1e6, "monster:cave_bat", {"guard": true})
	check("рюкзак запомнен до очистки (4 вида)", GameState.death_lost.size() == 4 and GameState.inventory.is_empty()
		and int(GameState.death_lost.get("iron_ore", 0)) == 3)
	var rep := DeathWindow.report_now()
	var lost: Array = rep["lost"]
	check("в отчёте 4 стопки, дорогое первым (алмаз)", lost.size() == 4 and String(lost[0]["id"]) == "diamond")
	check("плата в отчёте — 5% от 4280 = 214", int(rep["fee"]) == 214)
	check("глубина смерти 410", int(rep["depth"]) == 410)
	var win := DeathWindow.new()
	add_child(win)
	await _frames(1)
	win.open(rep)
	await _frames(2)
	check("окно открыто", win.is_open() and DeathWindow.is_open_any())
	var labels := _labels(win)
	check("заголовок «Ты умер»", labels.has("Ты умер"))
	check("причина человеческой фразой", labels.has("Убит стражем полости: Гротовая мышь"), str(labels))
	check("глубина под причиной", labels.has("глубина 410"))
	check("подпись «Потеряно»", labels.has("Потеряно"))
	var tiles := win.find_children("Item_*", "PanelContainer", true, false)
	var with_icon := 0
	for t in tiles:
		var rects := (t as Node).find_children("*", "TextureRect", true, false)
		if not rects.is_empty() and (rects[0] as TextureRect).texture != null:
			with_icon += 1
	check("плитки потерь: 4 со значками", tiles.size() == 4 and with_icon == 4)
	check("количество на плитках (×3, ×2, ×1)", labels.has("×3") and labels.has("×2") and labels.has("×1"))
	check("у плитки название в Tip", tiles.size() > 0 and (tiles[0] as Control).has_meta(Tip.META))
	check("«Потрачено на больницу −214»", labels.has("Потрачено на больницу") and labels.has("−214"))
	var nxt := win.find_child("Next", true, false) as Button
	check("кнопка «Дальше»", nxt != null and nxt.text == "Дальше")
	var card := win.find_child("Card", true, false) as Control
	check("окно влезает в экран 224 по ширине", card != null and card.size.x <= 224.0, str(card.size if card else Vector2.ZERO))
	win.close()
	check("закрывается", not win.is_open() and not DeathWindow.is_open_any())
	await _frames(1)

	# пустой рюкзак
	win.open(DeathWindow.build_report({}, 30, DeathCause.make("fall", {"cells": 34}), 50))
	await _frames(2)
	labels = _labels(win)
	check("пустой рюкзак: «Рюкзак был пуст», плиток нет", labels.has("Рюкзак был пуст")
		and win.find_children("Item_*", "PanelContainer", true, false).is_empty())
	check("падение с высотой в окне", labels.has("Разбился при падении с высоты 34 клеток"))
	win.close()
	await _frames(1)

	# без монет — «0», переполнение рюкзака — «+N»
	var many := {}
	for id in ["iron_ore", "silver", "copper", "lead", "aluminium", "nickel", "gold", "coal", "peat", "scrap", "diamond", "ruby", "emerald", "medkit"]:
		many[id] = 2
	win.open(DeathWindow.build_report(many, 900, DeathCause.make("lava"), 0))
	await _frames(2)
	labels = _labels(win)
	var shown := win.find_children("Item_*", "PanelContainer", true, false).size()
	check("14 стопок: 11 плиток и «+3»", shown == DeathWindow.MAX_TILES - 1 and labels.has("+3"), "плиток %d" % shown)
	check("без платы — «0», не «−0»", labels.has("0") and not labels.has("−0"))
	check("окно с 14 стопками влезает в экран 480 по высоте", (win.find_child("Card", true, false) as Control).size.y < 470.0)
	win.close()
	win.queue_free()
	GameState.respawn()
	await _frames(1)


# ---------------------------------------------------------------------------
# 5. Настоящая игра
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
		# все сцены просмотрены: звонок с кладбища и вехи глубины играют поверх окна (слой 100)
		for id in StoryData.scene_ids():
			StoryState.mark_seen(String(id))
		for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "gold_sold", "food_ordered"]:
			StoryState.set_flag(f)
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	await _frames(6)
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms):
		ms.set_process(false)
		if ms.popup != null and ms.popup.is_open():
			ms.popup.close()
	return m


func _window(main: Node) -> DeathWindow:
	return main.find_child("DeathWindow", true, false) as DeathWindow


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		get_viewport().push_input(ev, true)
		await _frames(1)


func _test_main() -> void:
	var main: Node2D = await _fresh_main()
	var p = main.player
	GameState.max_depth_reached = 450
	GameState.grant_gear("jetpack")
	GameState.set_current_gear("jetpack")
	GameState.add_item("silver", 3)
	GameState.hunger = 40.0
	GameState.stamina = 10.0
	p.x = 16.5
	p.y = 400.5
	p.frozen = false
	await _frames(1)
	GameState.coins = 1000   # после кадра: награды достижений за глубину уже пришли
	# настоящий удар о землю: верхняя точка полёта 52 клетки выше (ранец тормозил — скорость
	# удара 28 кл/с, как с 24 клеток свободного падения: в окне — настоящая высота)
	p._air_top_y = p.y - 52.0
	p.vy = 28.0
	GameState.hp = 1.0
	p._land()
	check("удар о землю: причина «падение с высоты 52 клеток»", String(GameState.death_cause.get("source", "")) == "fall"
		and int(GameState.death_cause.get("cells", 0)) == 52, str(GameState.death_cause))
	await _frames(3)
	check("поездки нет: герой сразу дома и жив", GameState.is_alive and p.y < 1.0)
	check("HP полное, сытость 40%, бодрость 25%", is_equal_approx(GameState.hp, GameState.get_max_hp())
		and absf(GameState.hunger - 40.0) < 0.5 and absf(GameState.stamina - 25.0) < 0.5,
		"HP %.1f/%.1f, сытость %.1f, бодрость %.1f" % [GameState.hp, GameState.get_max_hp(), GameState.hunger, GameState.stamina])
	check("плата 50, рюкзак пуст", Healing.last_death_fee == 50 and GameState.inventory.is_empty())
	await get_tree().create_timer(0.9).timeout
	var win := _window(main)
	check("окно смерти открылось дома", win != null and win.is_open())
	var labels := _labels(win) if win != null else []
	check("в окне причина «Разбился при падении с высоты 52 клеток»", labels.has("Разбился при падении с высоты 52 клеток"), str(labels))
	check("пока окно открыто, HUD не ведёт героя пальцем", main.hud._world_input_blocked())
	var nxt := win.find_child("Next", true, false) as Button if win != null else null
	await get_tree().create_timer(0.45).timeout   # защита от «добивающего» тапа
	if nxt != null:
		await _click(nxt.get_global_rect().get_center())
	check("«Дальше» нажимается пальцем — окно закрылось", win != null and not win.is_open())
	check("после закрытия HUD снова ведёт героя", not main.hud._world_input_blocked())

	# сейв мёртвым (вышел из игры в кадр смерти) — при загрузке сразу дома, без поездки
	GameState.is_alive = false
	GameState.hp = 0.0
	GameState.ext["death_ride"] = {"left": 40.0, "total": 80.0, "depth": 400}
	SaveSystem.save_game()
	main.free()
	await _frames(2)
	var main2: Node2D = await _fresh_main(true)
	check("загрузка мёртвым: сразу жив, HP полное, старой поездки нет", GameState.is_alive
		and is_equal_approx(GameState.hp, GameState.get_max_hp()) and not GameState.ext.has("death_ride"))
	main2.free()
	await _frames(2)

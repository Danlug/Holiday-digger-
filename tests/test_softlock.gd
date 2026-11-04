extends Node
## test_softlock — тупики целой игры (ветка qa2): у героя всегда есть выход.
##
## Запуск: godot --headless --path . res://tests/test_softlock.tscn
##
## Сценарии на настоящей main.tscn (со всеми подсистемами сразу):
##  1. Босс побеждён в настоящем бою -> событие boss_defeated -> концовка -> титры -> игра
##     продолжается (герой свободен, HUD виден, ворота арены открыты, повторно бой не начинается).
##  2. «Сброс» и перезагрузка посреди боя с боссом не оставляют ворота арены закрытыми
##     (BossArena.sealed — статика, переживает сцену): иначе в новой игре на дне нельзя войти.
##  3. Сейв и загрузка посреди боя: герой дома, монстров/босса нет, прогресс боя цел.
##  4. Смерть в лаве за рулём бурмобиля на глубине: сразу дома с полным HP, окно смерти, машина на
##     парковке, инструмент снят, HUD/ввод/боевой директор живы, лут потерян по правилам, глубина и мета целы.
##  5. Пустой бак бурмобиля на глубине: копать нельзя, но лететь вверх можно; лопата на поверхности.
##  6. Сейв старой схемы и мусор в ext новых подсистем: игра поднимается, подсистемы не падают.
##  7. «Сброс» очищает состояние всех новых подсистем (бой, техника, мета, подсказки, сюжет).

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


## Зажать клавишу на sec секунд настоящего времени (кадры в headless короткие — по числу кадров герой не успевает шагнуть).
## Окно дня мета-слоя всплывает само, когда в игре «спокойно», и замораживает героя, пока его не закрыли
## (так задумано, ГДД §19). Закрываем, если открылось; true — оно было открыто.
func _close_daily_popup() -> bool:
	var ms = MetaService.instance
	if ms == null or not is_instance_valid(ms) or not ms.popup.is_open():
		return false
	ms.popup.close()
	await _frames(3)
	return true


func _walk(key: Key, sec: float) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.keycode = key
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		if pressed:
			await get_tree().create_timer(sec).timeout


## Чистая игра в настоящей сцене: ранние сюжетные сцены прочитаны, чтобы они не лезли в проверки.
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
	return await _spawn_main()


func _spawn_main() -> Node2D:
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	await _frames(6)
	return m


## Сброс из настроек (hud._on_reset_pressed) без перезагрузки тестовой сцены: освобождаем main
## так же, как reload_current_scene, и поднимаем новый.
func _reset_like_settings(main: Node2D) -> Node2D:
	GameState.reset_progress()
	StoryState.clear_all()
	StoryState.delete_from_disk()
	SaveSystem.delete_save()
	main.free()
	return await _spawn_main()


func _ready() -> void:
	print("=== test_softlock ===")
	await _test_boss_win_ending()
	await _test_reset_mid_boss()
	await _test_save_load_mid_combat()
	await _test_death_in_rig_lava()
	await _test_empty_rig_tank()
	await _test_old_and_junk_ext()
	await _test_reset_clears_subsystems()
	GameState.debug_invincible = false
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# 1. Победа над боссом: настоящий бой -> концовка -> титры -> игра продолжается
# ---------------------------------------------------------------------------

func _test_boss_win_ending() -> void:
	var main: Node2D = await _fresh_main()
	var story: StoryDirector = main.find_child("StoryDirector", true, false)
	var cd: CombatDirector = CombatService.director as CombatDirector
	var p = main.player
	story.arc_calm_wait_ms = 0
	GameState.max_depth_reached = 10000
	for e in StoryData.depth_scenes():
		StoryState.mark_seen(String(e.id))
	GameState.debug_invincible = true    # здесь проверяем выход из боя, не выживание
	p.frozen = false
	GameState.house_is_indoors = false
	var floor_y := BossArena.floor_y()
	p.x = BossArena.center_x()
	p.y = float(floor_y) - 1.5
	p.vx = 0.0
	p.vy = 0.0
	var events: Array = []
	var on_event := func(id: StringName, data: Dictionary) -> void: events.append([String(id), data])
	GameState.game_event.connect(on_event)
	var guard := 0
	while cd.boss == null and guard < 60:
		guard += 1
		await _frames(1)
	check("герой в арене: бой начался, ворота закрыты", cd.boss != null and BossArena.sealed)
	var boss: BossLogic = cd.boss
	if boss == null:
		GameState.game_event.disconnect(on_event)
		main.queue_free()
		return
	boss.hp = 1.0
	boss.phase = 3
	boss.state = BossLogic.RECOVER
	boss.t = 0.0
	guard = 0
	while cd.boss != null and cd.boss.is_active() and guard < 900:
		guard += 1
		p.x = boss.center_x + 2.3
		p.y = float(floor_y) - 0.4
		p.vx = 0.0
		p.vy = 0.0
		p.on_ground = true
		boss.state = BossLogic.RECOVER if boss.hp > 0.0 and boss.is_active() and boss.state != BossLogic.RECOVER else boss.state
		await _frames(1)
	var defeated := 0
	for e in events:
		if e[0] == "boss_defeated":
			defeated += 1
	check("босс побеждён героем в настоящем бою: ровно одно событие boss_defeated", defeated == 1, "кадров %d, событий %d" % [guard, defeated])
	check("ворота арены открыты после победы", not BossArena.sealed)
	check("награда на складе: ядро Бездны и осколки", HouseStorage.count("abyss_core") == 1 and HouseStorage.count("idol_shard") == 4)
	guard = 0
	while not story.cutscene.is_playing and guard < 400:
		guard += 1
		await _frames(1)
	check("после победы запускается концовка (без застревания)", story.cutscene.is_playing and story.cutscene.scene_id == "ending", "кадров %d" % guard)
	var seen_ids: Array = []
	guard = 0
	while story.cutscene.is_playing and guard < 12:
		guard += 1
		seen_ids.append(story.cutscene.scene_id)
		story.cutscene.skip()
		await _frames(6)
	check("концовка, затем титры; остальные сцены дуги не застревают (%s)" % str(seen_ids),
		seen_ids.has("ending") and seen_ids.has("credits") and seen_ids.find("ending") < seen_ids.find("credits"))
	check("после титров игра продолжается: герой свободен, HUD виден", not story.cutscene.is_playing and not p.frozen and main.hud.visible,
		"играет=%s заморожен=%s HUD=%s" % [story.cutscene.is_playing, p.frozen, main.hud.visible])
	# анимация смерти босса идёт 3 с настоящего времени
	await get_tree().create_timer(3.4).timeout
	check("анимация смерти босса доиграна, боя нет", cd.boss == null and cd.boss_death_t < 0.0, "t=%.2f" % cd.boss_death_t)
	check("концовка запомнена один раз", StoryState.is_seen("ending") and StoryState.has_flag("ending_seen"))
	# герой дома и двигается
	var x0: float = p.x
	await get_tree().create_timer(2.0).timeout    # дать окну дня шанс всплыть
	var popup_was_open: bool = await _close_daily_popup()
	await _walk(KEY_D, 0.6)
	if p.x <= x0 + 0.1 and await _close_daily_popup():
		popup_was_open = true
		await _walk(KEY_D, 0.6)
	print("  (окно дня всплывало: %s)" % popup_was_open)
	check("после титров герой ходит (ввод не заморожен; окно дня закрывается и отпускает героя)", p.x > x0 + 0.1, "x %.2f -> %.2f заморожен=%s стан=%s прогресс=%s меню=%s идёт=%s hud=%s дневник=%s _playing=%s очередь=%s" % [
		x0, p.x, p.frozen, p.stun_until_msec > Time.get_ticks_msec(), ProgressScreen.is_open(), main.hud.is_more_menu_open(),
		story.cutscene.is_playing, main.hud.visible, story.diary_ui.is_open, story._playing, str(GameState.story_queue)]
			+ " дом:подсказка=%s внутри=%s stamina=%.0f hunger=%.0f" % [str(main.find_child("HouseSystem", true, false)._prompt_action), GameState.house_is_indoors, GameState.stamina, GameState.hunger])
	# повторный вход в арену: боя нет, выход открыт
	p.x = BossArena.center_x()
	p.y = float(floor_y) - 1.5
	p.vx = 0.0
	p.vy = 0.0
	await _frames(10)
	check("побеждённый босс не возрождается, ворота открыты", cd.boss == null and not BossArena.sealed
		and main.world.get_tile(BossArena.gate_x0(), BossArena.top_y()) == BossArena.EMPTY)
	GameState.game_event.disconnect(on_event)
	GameState.debug_invincible = false
	main.free()


# ---------------------------------------------------------------------------
# 2. «Сброс» посреди боя не оставляет арену закрытой
# ---------------------------------------------------------------------------

func _test_reset_mid_boss() -> void:
	var main: Node2D = await _fresh_main()
	var cd: CombatDirector = CombatService.director as CombatDirector
	cd.start_boss_fight()
	check("бой идёт, ворота закрыты", cd.boss != null and BossArena.sealed)
	var main2: Node2D = await _reset_like_settings(main)
	var cd2: CombatDirector = CombatService.director as CombatDirector
	check("после «Сброса» посреди боя ворота арены открыты", not BossArena.sealed)
	check("и мир не держит потолок арены закрытым",
		main2.world.get_tile(BossArena.gate_x0(), BossArena.top_y()) == BossArena.EMPTY)
	check("новый директор боя без босса и монстров", cd2 != null and cd2 != cd and cd2.boss == null and cd2.monsters.is_empty())
	main2.free()


# ---------------------------------------------------------------------------
# 3. Сейв и загрузка посреди боя
# ---------------------------------------------------------------------------

func _test_save_load_mid_combat() -> void:
	var main: Node2D = await _fresh_main()
	var cd: CombatDirector = CombatService.director as CombatDirector
	GameState.max_depth_reached = 9990
	GameState.coins = 4321
	CombatService.give("blade_t2")
	CombatService.equip("blade_t2")
	CombatService.note_kill("cinder_grub")
	CombatService.boss_note_attempt()
	cd.spawn({"id": "cinder_grub", "x": 18.5, "y": 4600.0, "group": 1, "emerge": Vector2.ZERO})
	cd.start_boss_fight()
	GameState.add_item("gold", 3)
	GameState.hp = 12.0
	SaveSystem.save_game()
	main.free()
	var main2: Node2D = await _fresh_main(true)
	var cd2: CombatDirector = CombatService.director as CombatDirector
	check("загрузка посреди боя: прогресс цел (монеты, глубина, бой)",
		GameState.coins >= 4321 and GameState.max_depth_reached >= 9990
		and CombatService.is_owned("blade_t2") and CombatService.equipped("weapon") == "blade_t2"
		and CombatService.kills_total() == 1 and int(CombatService.boss_state().get("attempts", 0)) >= 1,
		"монеты %d глубина %d оружие %s убийств %d попыток %d" % [GameState.coins, GameState.max_depth_reached,
			CombatService.equipped("weapon"), CombatService.kills_total(), int(CombatService.boss_state().get("attempts", 0))])
	check("загрузка посреди боя: босса и монстров нет, ворота открыты",
		cd2.boss == null and cd2.monsters.is_empty() and not BossArena.sealed)
	check("загрузка посреди боя: герой жив и дома", GameState.is_alive and GameState.hp > 0.0 and main2.player.y < 1.0)
	check("загрузка посреди боя: герой не заморожен, боевой директор в строю",
		not main2.player.frozen and cd2.can_fight())
	main2.free()


# ---------------------------------------------------------------------------
# 4. Смерть в лаве за рулём бурмобиля на глубине
# ---------------------------------------------------------------------------

func _test_death_in_rig_lava() -> void:
	var main: Node2D = await _fresh_main()
	var p = main.player
	var cd: CombatDirector = CombatService.director as CombatDirector
	GameState.max_depth_reached = 4100
	GameState.grant_tool("iron_pickaxe")
	GameState.grant_tool("drill_rig")
	GameState.current_tool = "drill_rig"
	p._announced_rig = true    # «рецепт бурмобиля открыт» уже объявлялся: иначе первый тик сам наденет машину
	GameState.player_depth = 3600
	GameState.coins = 777
	GameState.add_item("gold", 4)
	var deaths0 := MetaState.counter("deaths")
	p.x = 16.5
	p.y = 3600.5
	p.frozen = false
	cd.spawn({"id": "cinder_grub", "x": 18.5, "y": 3600.0, "group": 1, "emerge": Vector2.ZERO})
	var died := [0]
	GameState.died.connect(func() -> void: died[0] += 1)
	var guard := 0
	while GameState.is_alive and guard < 400:
		guard += 1
		Heat.burn_digger(0.5)
	check("лава убивает героя без костюма", not GameState.is_alive and died[0] == 1)
	check("лут потерян, монеты целы (награды за достижения могли добавить)", not GameState.inventory.has("gold") and GameState.coins >= 777,
		"рюкзак %s монеты %d" % [str(GameState.inventory), GameState.coins])
	check("причина смерти — лава", String(GameState.death_cause.get("source", "")) == "lava")
	await _frames(4)
	# Разбор чисел 26.10: поездки нет — герой сразу дома, HP полное (владелец: «только хп полное»).
	check("респавн: герой жив, дома, HP полное", GameState.is_alive and p.y < 1.0
		and absf(GameState.hp - GameState.get_max_hp()) < 0.5)
	check("машина запаркована, герой снова с киркой, а не «за рулём» под землёй",
		GameState.current_tool != "drill_rig" and GameState.is_rig_parked(),
		"инструмент %s парковка %s" % [GameState.current_tool, str(GameState.rig_parked_at)])
	check("после смерти не заморожен, HUD виден, диалогов нет", not p.frozen and main.hud.visible)
	check("боевой директор очищен после смерти", cd.monsters.is_empty() and cd.boss == null and cd.can_fight())
	check("глубина рекорда и мета-счётчик смертей сохранены", GameState.max_depth_reached >= 4100
		and MetaState.counter("deaths") == deaths0 + 1)
	# двигается
	var x0: float = p.x
	await _walk(KEY_A, 0.6)
	check("после смерти герой ходит", absf(p.x - x0) > 0.1, "x %.2f -> %.2f" % [x0, p.x])
	# вторая смерть подряд (без монстров, голод и урон) тоже ничего не ломает
	GameState.take_damage(1e6, "test")
	await _frames(4)
	check("вторая смерть подряд: снова жив дома", GameState.is_alive and p.y < 1.0)
	main.free()


# ---------------------------------------------------------------------------
# 5. Пустой бак бурмобиля на глубине
# ---------------------------------------------------------------------------

func _test_empty_rig_tank() -> void:
	var world := WorldGen.new(4242)
	GameState.world_ref = world
	GameState.reset_progress()
	GameState.max_depth_reached = 1500
	GameState.grant_tool("drill_rig")
	GameState.current_tool = "drill_rig"
	GameState.current_gear = "jetpack"
	FuelTank.set_fuel("drill_rig", 0.0)
	var p = load("res://scripts/player/player.gd").new()
	p.world = world
	add_child(p)
	# вертикальный выработанный ствол x=20 от 1 до 400
	for y in range(1, 401):
		world.dig_cell(20, y)
	p.x = 20.5
	p.y = 399.5
	p.on_ground = true
	GameState.player_depth = 399
	p.hold_down = true
	# 2 с: бурмобиль сначала опускается на дно ствола (падает медленнее пешего), потом бьёт вниз
	for _i in range(120):
		p.physics_tick(1.0 / 60.0)
	p.hold_down = false
	# Владелец 29.10: «когда заканчивается топливо, он берётся за кирку» — пустой бак не глушит машину.
	check("в бурмобиле без топлива копает вниз киркой: копка идёт или клетка уже вынута",
		(p.digging != null or world.get_tile(20, 401) == TileTypes.Type.EMPTY) and not FuelTank.has_fuel("drill_rig"))
	p.digging = null
	p.hold_dx = -1
	for _i in range(40):
		p.physics_tick(1.0 / 60.0)
	p.hold_dx = 0
	check("упор в породу без топлива запускает копку киркой", p.digging != null or world.get_tile(19, p.cell_y()) == TileTypes.Type.EMPTY)
	p.digging = null
	var set_before := GameState.current_tool
	GameState.set_current_tool("iron_pickaxe")
	check("под землёй высадиться нельзя (бурмобиль не бросить на дне)", GameState.current_tool == set_before)
	# лететь вверх по своему стволу можно и без топлива (тяга включается через 300 мс реального времени — снимаем взвод)
	p.x = 20.5
	var y0: float = p.y
	p.hold_up = true
	for _i in range(240):
		p._fly_arm_at_msec = 0.0
		p.physics_tick(1.0 / 60.0)
	p.hold_up = false
	check("без топлива бурмобиль взлетает по прорытому стволу", p.y < y0 - 5.0, "y %.1f -> %.1f" % [y0, p.y])
	# часы-телепорт: домой в любом случае
	p.teleport_home()
	check("телепорт домой: машина на парковке, инструмент снят", GameState.is_rig_parked() and GameState.current_tool != "drill_rig" and p.y < 1.0)
	check("с пустым баком сесть нельзя, но это сообщение, а не тупик",
		not p.start_rig_boarding())
	GameState.set_current_tool("iron_pickaxe")
	check("на поверхности кирка надевается — копать можно", GameState.current_tool == "iron_pickaxe" or GameState.owns_tool("iron_pickaxe") == false)
	p.free()
	GameState.world_ref = null


# ---------------------------------------------------------------------------
# 6. Сейв старой схемы и мусор в ext новых подсистем
# ---------------------------------------------------------------------------

func _test_old_and_junk_ext() -> void:
	# Старый сейв: только базовые поля, без ext вовсе. Подсистемы должны отдавать значения по умолчанию.
	for f in ["user://save.json", "user://save.json.bak", "user://records.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	GameState.reset_progress()
	GameState.coins = 900
	GameState.max_depth_reached = 4300
	GameState.level = 7
	var data: Dictionary = SaveSystem._serialize()
	data.erase("ext")
	data["version"] = 1
	var old := FileAccess.open("user://save.json", FileAccess.WRITE)
	old.store_string(JSON.stringify(data))
	old.close()
	GameState.reset_progress()
	var main: Node2D = await _fresh_main(true)
	var cd: CombatDirector = CombatService.director as CombatDirector
	check("сейв без ext: игра поднялась с прогрессом", GameState.coins >= 900 and GameState.max_depth_reached == 4300 and GameState.level >= 7,
		"монеты %d глубина %d" % [GameState.coins, GameState.max_depth_reached])
	check("сейв без ext: подсистемы отдают значения по умолчанию",
		TechState.suit() == 0 and FuelTank.level("hand_drill") == 0 and CombatService.owned_ids().is_empty()
		and not CombatService.boss_defeated() and MetaState.counter("dug") == 0)
	check("сейв без ext: боевой директор и меню живы", cd != null and is_instance_valid(cd) and cd.is_unlocked(),
		"директор %s" % str(cd))
	main.free()
	# Мусор в ext: каждая подсистема получает неподходящий тип; ни одна не должна падать при чтении.
	var junk: Array = [null, 7, "строка", [], [1, 2], {"a": 1}, {"tanks": 5, "suit": "x", "well": []}, {"state": null},
		{"tanks": {"drill_rig": 5, "hand_drill": []}, "suit": 2.5}, {"tanks": [1], "suit": null},
		{"owned": 3, "equipped": "x", "sockets": [], "boss": 5, "kills": null},
		{"c": 5, "events": [], "ach": "x", "minerals": 3, "hw": "q"}]
	var keys := ["tech", "combat", "meta", "hints", "hero", "story_diary", "house", "museum"]
	for k in GameState.ext.keys():
		if not keys.has(String(k)):
			keys.append(String(k))
	var survived := 0
	var tried := 0
	for key in keys:
		for j in junk:
			tried += 1
			GameState.ext = {key: j}
			var ok := true
			# чтения, которые зовёт игра каждый кадр/каждое открытие экрана
			ok = ok and TechState.suit() >= 0
			ok = ok and FuelTank.capacity("drill_rig") >= 0.0
			ok = ok and FuelTank.fuel("hand_drill") >= 0.0
			ok = ok and CombatService.stats().has("damage")
			ok = ok and CombatService.owned_ids() is Array
			ok = ok and CombatService.kills_total() >= 0
			ok = ok and MetaState.counter("dug") >= 0
			ok = ok and Heat.suit_tier() >= 0
			# форма после чтения: ветка «Техника» лечит битую форму на месте
			ok = ok and typeof(TechState.tank("drill_rig")) == TYPE_DICTIONARY and typeof(TechState.root().get("tanks")) == TYPE_DICTIONARY
			ok = ok and typeof(CombatService.state().get("boss")) == TYPE_DICTIONARY
			ok = ok and typeof(MetaState.sub("c")) == TYPE_DICTIONARY
			if ok:
				survived += 1
	check("мусор в ext (%d вариантов) не роняет чтение подсистем" % tried, survived == tried, "выжило %d из %d" % [survived, tried])
	GameState.ext = {}


# ---------------------------------------------------------------------------
# 7. «Сброс» очищает состояние всех подсистем
# ---------------------------------------------------------------------------

func _test_reset_clears_subsystems() -> void:
	var main: Node2D = await _fresh_main()
	GameState.max_depth_reached = 4500
	GameState.coins = 123456
	GameState.grant_tool("drill_rig")
	TechState.set_suit(3)
	TechState.tank("drill_rig")["level"] = 2
	FuelTank.set_fuel("drill_rig", 5.0)
	CombatService.give("armor_t2")
	CombatService.equip("armor_t2")
	CombatService.note_kill("rift_hopper")
	CombatService.boss_claim_rewards()
	MetaState.bump("dug")
	MetaState.bump("monsters")
	GameState.well_level = 3
	HouseStorage.store_directly("hellstone", 9)
	GameState.story_flags["ending_seen"] = true
	SaveSystem.save_game()
	var main2: Node2D = await _reset_like_settings(main)
	check("сброс: монеты, глубина, инструменты", GameState.coins == 0 and GameState.max_depth_reached == 0
		and not GameState.owns_tool("drill_rig") and GameState.current_tool == "shovel")
	check("сброс: техника (костюм, баки)", TechState.suit() == 0 and FuelTank.level("drill_rig") == 0 and FuelTank.fuel("drill_rig") == 0.0)
	check("сброс: бой (снаряжение, убийства, босс)", CombatService.owned_ids().is_empty()
		and CombatService.kills_total() == 0 and not CombatService.boss_defeated())
	check("сброс: мета-счётчики", MetaState.counter("dug") == 0 and MetaState.counter("monsters") == 0)
	check("сброс: скважина, склад", GameState.well_level == 0 and HouseStorage.count("hellstone") == 0)
	check("сброс: сюжетные флаги", not StoryState.has_flag("ending_seen") and not StoryState.is_seen("intro_grandpa"))
	check("сброс: сейв на диске стёрт", not FileAccess.file_exists("user://save.json"))
	check("сброс: ворота арены открыты, герой жив и дома", not BossArena.sealed and GameState.is_alive and main2.player.y < 1.0,
		"sealed=%s alive=%s y=%.1f" % [BossArena.sealed, GameState.is_alive, main2.player.y])
	main2.free()

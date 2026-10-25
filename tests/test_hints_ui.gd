extends Node
## test_hints_ui — подсказки в настоящей игровой сцене: цели находятся у живого HUD (кнопка
## героя, рюкзак, «•••», значки техники, объекты мира), меню «•••» — двухшаговая цель,
## метки «!» и «NEW», строка настроек «подсказки», сохранение через SaveSystem и
## реальный проход правила «очки навыков» до кольца вокруг кнопки героя.
## Картинку проверяет test_screenshot_hints (нужен настоящий рендер).
##
## Запуск: godot --headless --path . res://tests/test_hints_ui.tscn

var failures := 0
var total := 0
var main: Node2D


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _ready() -> void:
	print("=== test_hints_ui ===")
	Settings.reduce_motion = true
	Settings.hints_enabled = true
	# Онбординг пройден: вводные сцены сыграны, чтобы режиссёр не запустил интро. Файл
	# сюжета от прошлых запусков стираем: режиссёр при старте читает флаги с диска.
	StoryState.delete_from_disk()
	if FileAccess.file_exists(SaveSystem.SAVE_PATH):
		DirAccess.remove_absolute(SaveSystem.SAVE_PATH)   # сейв прошлого запуска не должен влиять
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure", "workshop", "death",
			"backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2"]:
		GameState.story_seen.append(id)
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered"]:
		GameState.story_flags[f] = true
	# Сцены сюжетной арки (звонок про могилу, глубины) на глубине 150 не должны перебить кадр.
	for id in ["grave_call", "first_artifact", "grandma_returns"]:
		GameState.story_seen.append(id)
	StoryData.ensure_loaded()
	for entry in StoryData.depth_scenes():
		GameState.story_seen.append(String(entry.id))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(6)
	var director = main.get_node("StoryDirector")
	for _i in range(6):
		if director.cutscene != null and director.cutscene.is_playing:
			director.cutscene.skip()
		await _wait(0.2)

	await _check_wiring()
	await _check_hud_targets()
	await _check_menu_targets()
	await _check_tech_and_world_targets()
	await _check_marks()
	await _check_real_rule()
	await _check_settings_row()
	_check_persistence()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _in_view(r: Rect2) -> bool:
	return Rect2(Vector2.ZERO, main.hud.get_viewport_rect().size).intersects(r)


func _check_wiring() -> void:
	var d := get_tree().root.find_child("HintDirector", true, false)
	check("HintDirector подключён к main и находится по имени", d is HintDirector)
	check("HintDirector.instance() отдаёт его же", HintDirector.instance() == d)
	check("у движка есть слой с тостом и слой меток", d.overlay != null and d.marks != null)
	check("после онбординга игрок не «занят»", not HintBusy.is_busy())
	check("подсказки включены", HintState.enabled() and HintBusy.onboarding_done())


func _check_hud_targets() -> void:
	for id in ["hero", "backpack", "menu", "tool", "load", "hp", "hunger", "stamina", "coins", "dollars"]:
		var r := HintTargets.resolve("hud:" + id)
		check("hud:%s находится и виден на экране" % id, not r.is_empty() and _in_view(r["rect"]) and bool(r["final"]))
	var hero := HintTargets.resolve("hud:hero")
	check("hud:hero — именно кнопка героя (≥ 22 единицы под палец)",
		hero["node"] == main.hud.get("_hero_button") and (hero["rect"] as Rect2).size.x >= 22.0)
	check("hud:нет_такого — пусто, без падения", HintTargets.resolve("hud:zzz").is_empty())
	var seen := HintTargets.resolve(["hud:zzz", "hud:backpack"])
	check("список целей: пропускает ненайденную", seen["spec"] == "hud:backpack")


func _check_menu_targets() -> void:
	main.hud.close_more_menu()
	await _frames(2)
	var closed := HintTargets.resolve("menu:workshop")
	check("меню закрыто: цель «Мастерская» — кнопка «•••»", not closed.is_empty()
		and closed["node"] == main.hud.get("_more_button") and not bool(closed["final"]))
	check("меню: несуществующий пункт — пусто", HintTargets.resolve("menu:zzz").is_empty())
	main.hud.call("_toggle_more_menu")
	await _frames(3)
	var opened := HintTargets.resolve("menu:workshop")
	check("меню открыто: цель — плитка пункта, конечная", not opened.is_empty() and bool(opened["final"])
		and opened["node"] != main.hud.get("_more_button"))
	var tip: Dictionary = opened["node"].get_meta(Tip.META)
	check("плитка опознана по заголовку Tip", String(tip["title"]) == "Мастерская")
	var settings := HintTargets.resolve("menu:settings")
	check("плитка «Настройки» находится и отличается от «Мастерской»",
		not settings.is_empty() and settings["node"] != opened["node"])
	main.hud.close_more_menu()
	await _frames(2)


func _check_tech_and_world_targets() -> void:
	check("значок топлива скрыт, пока в руках лопата", HintTargets.resolve("tech_hud:fuel").is_empty())
	GameState.grant_tool("hand_drill")
	GameState.set_current_tool("hand_drill")
	await _frames(3)
	var fuel := HintTargets.resolve("tech_hud:fuel")
	check("значок топлива виден с буром в руках", not fuel.is_empty() and _in_view(fuel["rect"]))

	var player = main.player
	player.x = WorldGen.FUEL_STATION_X + 1.0
	await _frames(4)
	var st := HintTargets.resolve("world:station")
	check("world:station находится, когда герой у станции", not st.is_empty() and bool(st["world"]))
	check("world:station — прямоугольник на экране", _in_view(st["rect"]) and (st["rect"] as Rect2).size.x >= 16.0)
	player.x = GraveSite.GRAVE_X
	await _frames(4)
	check("world:grave находится у могилы", not HintTargets.resolve("world:grave").is_empty())
	player.x = 60.0
	await _frames(4)
	check("world:grave не видна, пока герой далеко (кольцо не рисуется в никуда)",
		HintTargets.resolve("world:grave").is_empty())
	player.x = WorldGen.WELL_X + 1.0
	await _frames(4)
	check("world:well находится у скважины", not HintTargets.resolve("world:well").is_empty())
	player.teleport_home()
	GameState.set_current_tool("shovel")
	await _frames(2)


func _check_marks() -> void:
	var d: HintDirector = HintDirector.instance()
	GameState.max_depth_reached = 150   # пункт «Техника» открывается с глубины 100
	HintState.mark_entry_opened("projects")   # «Проекты» (ветка guidance) видны всегда — проверяем одну «Технику»
	await _wait(0.4)
	d.marks.refresh()
	await _frames(2)
	var more: Control = main.hud.get("_more_button")
	check("«!» на кнопке «•••», пока есть непосещённый пункт", d.marks.visible_marks("bang").size() == 1)
	var bang: TextureRect = d.marks.visible_marks("bang")[0]["mark"]
	check("метка не перехватывает нажатия", bang.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	check("«!» стоит в углу кнопки «•••»", more.get_global_rect().grow(8.0).has_point(bang.position + bang.size * 0.5))
	main.hud.call("_toggle_more_menu")
	await _wait(0.4)
	d.marks.refresh()
	await _frames(2)
	var tile: Button = null
	for b in main.hud.get("_more_grid").get_children():
		if String((b.get_meta(Tip.META) as Dictionary).get("title", "")) == "Техника":
			tile = b
	check("пункт «Техника» есть в меню", tile != null)
	var news: Array = d.marks.visible_marks("new")
	if news.size() != 1:
		for m in d.marks._marks:
			print("   метка ", m["kind"], " видна=", m["mark"].visible, " цель видна=", (m["target"] as Control).is_visible_in_tree(), " в сетке=", m["target"].get_parent() == main.hud.get("_more_grid"))
	check("на плитке «Техника» ярлык NEW, и он один", news.size() == 1 and news[0]["target"] == tile)
	var mark: TextureRect = news[0]["mark"]
	check("ярлык стоит на углу плитки", tile.get_global_rect().grow(8.0).has_point(mark.position + mark.size * 0.5))
	check("на «Мастерской» ярлыка нет", _tile_has_no_mark("Мастерская"))
	check("«!» на «•••» скрыт, пока меню открыто", d.marks.visible_marks("bang").is_empty())
	tile.pressed.emit()
	await _frames(3)
	check("нажали по пункту — он запомнен открытым, экран техники открылся", HintState.entry_opened("tech")
		and TechScreen.is_open())
	check("пока экран техники открыт, игрок «занят»", HintBusy.is_busy())
	TechScreen.close_screen()
	await _frames(2)
	check("ярлык с плитки снят", d.marks.visible_marks("new").is_empty())
	await _wait(0.4)
	check("пунктов без посещения больше нет — «!» не нужен", d.marks.new_entries().is_empty()
		and d.marks.visible_marks("bang").is_empty())
	main.hud.close_more_menu()
	Settings.hints_enabled = false
	HintState.reset()
	main.hud.call("_toggle_more_menu")
	await _wait(0.5)
	check("«не мешать»: ярлыков NEW нет", d.marks.visible_marks("new").is_empty())
	main.hud.close_more_menu()
	await _wait(0.4)
	check("«не мешать»: «!» на «•••» скрыт", d.marks.visible_marks("bang").is_empty())
	Settings.hints_enabled = true
	await _wait(0.4)
	check("включили подсказки — «!» вернулся", d.marks.visible_marks("bang").size() == 1)


func _tile_has_no_mark(title: String) -> bool:
	var d: HintDirector = HintDirector.instance()
	for m: Dictionary in d.marks.visible_marks("new"):
		var meta: Dictionary = m["target"].get_meta(Tip.META)
		if String(meta.get("title", "")) == title:
			return false
	return true


func _check_real_rule() -> void:
	var d: HintDirector = HintDirector.instance()
	HintState.reset()
	d.reload()
	GameState.skill_points_available = 2
	GameState.skill_points_changed.emit(2)
	for i in range(100):
		d.tick(0.25)
		if d.is_active():
			break
	if d.active_id() != "skill_points":
		print("   активна: «%s», занят: %s, показано: %s" % [d.active_id(), HintBusy.is_busy(), HintState.root()["seen"]])
	check("очки навыков: подсказка показалась", d.active_id() == "skill_points")
	var hero: Control = main.hud.get("_hero_button")
	check("кольцо вокруг кнопки героя", d.overlay._ring.rect.is_equal_approx(hero.get_global_rect()))
	check("тост «очки» и палец", d.overlay.is_showing() and d.overlay._finger.visible)
	var tipmeta: Dictionary = d.overlay.chip().get_meta(Tip.META)
	check("описание — в Tip на тосте, на экране только слово", String(tipmeta["title"]) == "Очки навыков"
		and d.overlay._chip_label.text == "очки")
	check("подсказка записана в ext", HintState.is_seen("skill_points"))
	# Игрок открыл экран героя — снимается как «сделано».
	ProgressScreen.open("progress")
	await _frames(3)
	d.tick(0.25)
	check("открыл героя — подсказка снята как «сделано»", not d.is_active() and HintState.was_done("skill_points"))
	ProgressScreen.close_screen()
	GameState.skill_points_available = 0
	await _frames(2)


func _check_settings_row() -> void:
	main.hud.open_settings()
	await _frames(2)
	var sheet = main.hud.get("_settings_sheet")
	var row: HintSettingsRow = sheet.get("_hints_row")
	check("в шторке настроек есть строка «подсказки»", row != null and row.toggle != null and row.replay != null)
	check("лампочка горит, пока подсказки включены", Settings.hints_enabled and row.toggle.icon == HintArt.tex("bulb_on"))
	row.toggle.pressed.emit()
	check("нажали лампочку — подсказки выключены и сохранены", not Settings.hints_enabled)
	check("лампочка погасла", row.toggle.icon == HintArt.tex("bulb_off"))
	var raw = JSON.parse_string(FileAccess.get_file_as_string(Settings.PATH))
	check("выключатель записан в settings.json", typeof(raw) == TYPE_DICTIONARY and raw["hints_enabled"] == false)
	row.toggle.pressed.emit()
	check("нажали снова — включены", Settings.hints_enabled)
	HintState.mark_seen("skill_points")
	HintState.mark_entry_opened("tech")
	row.replay.pressed.emit()
	check("«показать заново» сбрасывает показанное и метки",
		not HintState.is_seen("skill_points") and not HintState.entry_opened("tech"))
	Settings.set_hints_enabled(false)
	row.replay.pressed.emit()
	check("«показать заново» заодно включает подсказки", Settings.hints_enabled)
	main.hud.close_settings()


func _check_persistence() -> void:
	HintState.mark_seen("daily_reward")
	HintState.mark_done("skill_points")
	HintState.mark_entry_opened("meta_rewards")
	check("сейв записан", SaveSystem.save_game())
	GameState.ext.erase("hints")
	check("после стирания ничего не помнится", not HintState.is_seen("daily_reward"))
	SaveSystem.load_game()
	check("после загрузки сейва «показана» помнится", HintState.is_seen("daily_reward"))
	check("после загрузки «сделано» помнится", HintState.was_done("skill_points"))
	check("после загрузки открытые пункты меню помнятся", HintState.entry_opened("meta_rewards"))
	GameState.reset_progress()
	check("сброс прогресса стирает и подсказки", not HintState.is_seen("daily_reward"))


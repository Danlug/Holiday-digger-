extends Node
## test_screenshot_hints — не автотест, а инструмент: поднимает настоящую main-сцену,
## доводит игру до условий подсказок и снимает кадры: кнопка героя при очках навыков,
## «!» на «•••» и «NEW» на плитке, станция заправки, могила, скважина, пустой бак,
## жара и строка «подсказки» в настройках. Нужен настоящий рендер:
##
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . res://tests/test_screenshot_hints.tscn \
##       --rendering-driver opengl3 -- /каталог
##
## Перед запуском: export XDG_DATA_HOME=$PWD/.godot/xdg (user:// общий на машине).

var _out_dir := "/tmp/hints_screens"
var _main: Node2D
var _dir: HintDirector


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		_out_dir = a
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	Settings.reduce_motion = false
	Settings.hints_enabled = true
	StoryState.delete_from_disk()
	if FileAccess.file_exists(SaveSystem.SAVE_PATH):
		DirAccess.remove_absolute(SaveSystem.SAVE_PATH)
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
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _wait(0.5)
	var story = _main.get_node("StoryDirector")
	for _i in range(6):
		if story.cutscene != null and story.cutscene.is_playing:
			story.cutscene.skip()
		await _wait(0.2)
	_dir = HintDirector.instance()

	# 1. Кнопка героя: очки навыков.
	GameState.skill_points_available = 3
	GameState.skill_points_changed.emit(3)
	await _show_hint("skill_points", "01_skill_points")
	Tip.show_now(_dir.overlay.chip())   # описание — только в Tip на тосте
	await _wait(0.3)
	await _shot("01b_tip")
	Tip.hide_all()
	_finish()
	GameState.skill_points_available = 0

	# 2. Новый пункт меню: «!» на «•••», потом открытое меню с «NEW» и кольцом на плитке.
	GameState.max_depth_reached = 150
	await _show_hint("menu_tech", "02_menu_closed")
	_main.hud.call("_toggle_more_menu")
	await _wait(0.7)
	await _shot("03_menu_open")
	_main.hud.call("close_more_menu")
	_finish()

	# 3. Станция заправки на огороде (стрелка и кольцо в мире).
	GameState.story_flags["fuel_station_built"] = true
	GameState.grant_tool("hand_drill")
	_main.player.x = WorldGen.FUEL_STATION_X - 2.0
	await _wait(0.3)
	await _show_hint("station_new", "04_station")
	_finish()

	# 4. Могила деда.
	GameState.story_seen.append("grave_call")
	_main.player.x = GraveSite.GRAVE_X - 3.0
	await _wait(0.3)
	await _show_hint("grave_news", "05_grave")
	_finish()
	GameState.story_flags["diary_found"] = true

	# 5. Отчёт скважины ждёт: «•••» → плитка «Техника».
	GameState.well_level = 1
	GameState.well_last_collect_unix = IdleWell.now_unix() - 30 * 86400
	HintState.mark_entry_opened("tech")
	await _show_hint("well_ready", "06_well_menu_closed")
	_main.hud.call("_toggle_more_menu")
	await _wait(0.7)
	await _shot("07_well_menu_open")
	_main.hud.call("close_more_menu")
	_finish()
	GameState.well_level = 0

	# 6. Пустой бак: значок топлива под героем.
	GameState.set_current_tool("hand_drill")
	FuelTank.set_fuel("hand_drill", 0.0)
	_main.player.teleport_home()
	await _wait(0.3)
	await _show_hint("tank_empty", "08_tank_empty")
	_finish()
	GameState.set_current_tool("shovel")

	# 7. Снаряжение (ветка боя): пункт появляется с глубины 3500.
	GameState.max_depth_reached = 3600
	await _show_hint("menu_equipment", "08b_equipment_closed")
	_main.hud.call("_toggle_more_menu")
	await _wait(0.7)
	await _shot("08c_equipment_open")
	_main.hud.call("close_more_menu")
	_finish()
	GameState.max_depth_reached = 150

	# 8. Настройки: лампочка и «показать заново».
	_main.hud.open_settings()
	await _wait(0.5)
	await _shot("09_settings")
	_main.hud.close_settings()

	print("test_screenshot_hints: готово")
	get_tree().quit(0)


## Показывает ровно одно правило: остальные выключены, «увиденное» сброшено.
func _show_hint(id: String, shot_name: String) -> void:
	HintState.reset()
	_dir.set_rules([HintData.rule(id)])
	for i in range(400):
		_dir.tick(0.25)
		if _dir.active_id() == id:
			break
	if _dir.active_id() != id:
		print("test_screenshot_hints: подсказка %s не показалась (занят: %s)" % [id, HintBusy.is_busy()])
	await _wait(0.7)
	await _shot(shot_name)


func _finish() -> void:
	_dir.dismiss()
	HintState.reset()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("test_screenshot_hints: ", path, " ", img.get_size())

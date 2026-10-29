extends Node
## test_screenshot_newbie — не автотест, а инструмент: поднимает настоящую main-сцену
## и снимает стрик новичка: кнопку на главном экране под ежедневными миссиями, пункт в
## меню «•••», первые дни (сегодня — день 3, отмечен входом), пропущенный день с кнопкой «Вернуть за 50 $» (хватает и не хватает
## долларов), закрытый день, конец месяца с карточкой подарка, английский язык.
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_newbie.tscn --rendering-driver opengl3 --resolution 448x960 -- /каталог

var _out_dir := "/tmp/newbie_screens"
const BASE_DAY := 20760


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		_out_dir = a
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var director = main.get_node("StoryDirector")
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure", "workshop", "death",
			"backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2"]:
		StoryState.mark_seen(id)
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered"]:
		StoryState.set_flag(f)
	for _i in range(8):
		if director.cutscene != null and director.cutscene.is_playing:
			director.cutscene.skip()
		await _wait(0.4)
	StoryState.set_flag("gold_sold")
	for sid in StoryData.scene_ids():
		StoryState.mark_seen(String(sid))
	GameState.ext.clear()
	MetaClock.override_unix = BASE_DAY * MetaClock.DAY + 40000
	GameState.max_depth_reached = 64
	GameState.level = 5
	GameState.coins = 1340
	GameState.dollars = 72
	var meta: MetaService = main.get_node("MetaService")
	meta._poll()
	MetaState.sub("daily")["last"] = MetaState.today()   # окно подарка дня не всплывает поверх
	var svc: NewbieStreakService = main.get_node("NewbieStreakService")
	meta.toast.visible = false   # тосты достижений от подставленного прогресса закрывали бы шапку окна

	# Начало: дни 1 и 2 позади, сегодня день 3.
	NewbieStreak.ensure_started()
	NewbieStreak.state()["start"] = BASE_DAY - 2
	_finish_day(1, true)
	_finish_day(2, false)
	await _wait(1.3)   # узел стрика отмечает сегодняшний вход (опрос раз в секунду)

	# 0. Главный экран: кнопка стрика под кнопкой ежедневных миссий.
	await _shot("00_main_screen")

	# 1. Меню «•••» с пунктом стрика.
	main.hud.call("_toggle_more_menu")
	await _wait(0.5)
	await _shot("01_menu")
	main.hud.call("close_more_menu")
	await _wait(0.3)

	# 2. Первые дни: сегодня — день 3.
	svc.open()
	await _wait(0.7)
	await _shot("02_first_days")
	# День 2 — выполнен, награда ждёт.
	svc.panel.select(2)
	await _wait(0.3)
	await _shot("04_done_unclaimed")
	# Закрытый день.
	svc.panel.select(17)
	await _wait(0.3)
	await _shot("05_locked")
	svc.panel.close()
	await _wait(0.5)

	# 3. Пропущенный день: сегодня день 9, дни 4 и 6 пропущены.
	NewbieStreak.state()["start"] = BASE_DAY - 8
	for n in [3, 5, 7, 8]:
		_finish_day(n, true)
	svc.open()
	await _wait(0.5)
	svc.panel.select(6)
	await _wait(0.4)
	await _shot("06_missed_restore")
	var btn := svc.panel._box.find_child("Restore", true, false) as Button
	Tip.show_now(btn)
	await _wait(0.25)
	await _shot("07_restore_tip")
	Tip.hide_all()
	btn.pressed.emit()
	await _wait(0.25)
	await _shot("08_restored_burst")
	await _wait(1.0)
	GameState.dollars = 12
	svc.panel.select(4)
	await _wait(0.4)
	await _shot("09_missed_no_dollars")
	svc.panel.close()
	await _wait(0.5)

	# 4. Конец месяца: сегодня день 29, почти всё выполнено.
	GameState.dollars = 140
	NewbieStreak.state()["start"] = BASE_DAY - 28
	for n in range(1, 29):
		if n != 4 and n != 13 and n != 22:
			_finish_day(n, true)
	svc.open()
	await _wait(0.6)
	await _shot("10_month_end")
	Tip.show_now(svc.panel._box.find_child("Grand", true, false))
	await _wait(0.25)
	await _shot("11_grand_tip")
	Tip.hide_all()
	svc.panel.close()
	await _wait(0.5)

	# 5. Английский.
	Settings.language = "en"
	svc.open()
	await _wait(0.5)
	svc.panel.select(13)
	await _wait(0.3)
	await _shot("12_en_missed")
	Settings.language = "ru"

	MetaClock.override_unix = -1
	get_tree().quit(0)


func _finish_day(n: int, claimed: bool) -> void:
	var r := NewbieStreak.rec(n)
	r["done"] = true
	r["how"] = "visit"
	r["claimed"] = claimed


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("test_screenshot_newbie: ", path, " ", img.get_size())

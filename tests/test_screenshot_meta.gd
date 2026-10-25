extends Node
## test_screenshot_meta — не автотест, а инструмент: поднимает настоящую main-сцену,
## наполняет мета-слой правдоподобным прогрессом и снимает экраны: меню «•••» с
## бейджами, окно ежедневной награды (день 3 и день 7), хаб (задания, достижения,
## дорога), тост и взрыв наград. Нужен настоящий рендер:
##
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . res://tests/test_screenshot_meta.tscn \
##       --rendering-driver opengl3 -- /каталог
##
## Окно — 224×480 (проектный вьюпорт), кадры снимаются как есть.

var _out_dir := "/tmp/meta_screens"
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

	# Игрок «после онбординга»: вводные сцены сыграны (режиссёр на старте ставит интро
	# в очередь — пропускаем его), иначе ролик закроет экран.
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
	# Все сюжетные сцены считаем сыгранными: иначе «Бабка звонит из Таиланда» ложится
	# поверх экранов мета-слоя и кадр показывает не их.
	for sid in StoryData.scene_ids():
		StoryState.mark_seen(String(sid))
	# Не reset_progress(): он шлёт max_depth_changed(0), и режиссёр начинает сюжет заново.
	GameState.ext.clear()
	MetaClock.override_unix = BASE_DAY * MetaClock.DAY + 40000
	GameState.max_depth_reached = 140
	GameState.level = 7
	GameState.coins = 3420
	GameState.dollars = 3
	var svc: MetaService = main.get_node("MetaService")
	svc._poll()
	_seed_progress(svc)
	await _wait(0.3)

	# 1. Меню «•••» с пунктами мета-слоя и красными бейджами.
	main.hud.call("_toggle_more_menu")
	await _wait(0.5)
	await _shot("01_menu")
	main.hud.call("close_more_menu")

	# 2. Окно ежедневной награды, день 3 (серия 2).
	var d := MetaState.sub("daily")
	d["last"] = BASE_DAY - 1
	d["streak"] = 2
	d["pos"] = 2
	d["cycles"] = 0
	svc.open_daily()
	await _wait(0.6)
	await _shot("02_daily_day3")
	svc.popup.close()

	# 3. День 7 с бонусом серии.
	d["streak"] = 13
	d["pos"] = 6
	d["cycles"] = 1
	svc.open_daily()
	await _wait(0.6)
	await _shot("03_daily_day7")
	# Взрыв и полёт в кошелёк — кадр сразу после нажатия.
	svc.popup._claim(1.0)
	await _wait(0.22)
	await _shot("04_daily_claim_burst")
	await _wait(1.6)

	# 4. Хаб: задания.
	svc.open_hub("tasks")
	await _wait(0.5)
	await _shot("05_hub_tasks")

	# Подсказка на карточке задания (долгое нажатие / наведение).
	Tip.show_now(svc.hub._vbox.get_child(2))
	await _wait(0.2)
	await _shot("05b_tip_quest")
	Tip.hide_all()

	# Забрать готовое задание — кадр со взрывом из карточки.
	var ready_card := _first_claim_button(svc.hub)
	if ready_card != null:
		ready_card.pressed.emit()
		await _wait(0.2)
		await _shot("06_hub_claim_burst")
		await _wait(0.9)

	# 5. Достижения.
	svc.hub._set_tab("ach")
	await _wait(0.5)
	await _shot("07_hub_achievements")
	var grid: GridContainer = null
	for c in svc.hub._vbox.get_children():
		if c is GridContainer:
			grid = c
	Tip.show_now(grid.get_child(10))
	await _wait(0.2)
	await _shot("07b_tip_achievement")
	Tip.hide_all()
	svc.hub._scroll.scroll_vertical = 400
	await _wait(0.2)
	await _shot("08_hub_achievements_scrolled")

	# 6. Дорога трофеев.
	svc.hub._set_tab("road")
	await _wait(0.5)
	await _shot("09_hub_road")
	svc.hub.close()

	# 7. Тост достижения поверх игры.
	MetaState.root()["ach"].erase("depth_100")
	GameState.max_depth_reached = 101
	svc._apply(&"max_depth_changed", {"depth": 101})
	await _wait(0.5)
	await _shot("10_toast_achievement")

	MetaClock.override_unix = -1
	get_tree().quit(0)


func _first_claim_button(hub: MetaHub) -> Button:
	for card in hub._vbox.get_children():
		var found := _find_claim(card)
		if found != null:
			return found
	return null


func _find_claim(n: Node) -> Button:
	if n is Button and (n as Button).icon == MetaUiKit.tex("check") and (n as Button).text == "":
		return n
	for c in n.get_children():
		var f := _find_claim(c)
		if f != null:
			return f
	return null


## Правдоподобная середина игры: часть заданий в процессе, одно готово, одно
## забрано; достижения копятся; на дороге несколько ступеней ждут.
func _seed_progress(svc: MetaService) -> void:
	var qs := MetaState.sub("quests")
	var daily: Array = qs["daily"]
	daily[0]["progress"] = int(int(daily[0]["target"]) * 0.6)
	daily[1]["progress"] = int(daily[1]["target"])
	daily[2]["progress"] = int(daily[2]["target"])
	daily[2]["claimed"] = true
	var weekly: Array = qs["weekly"]
	weekly[0]["progress"] = int(int(weekly[0]["target"]) * 0.35)
	weekly[1]["progress"] = int(int(weekly[1]["target"]) * 0.1)
	for ev in [
		[&"picked", {"item": "gold", "count": 34}], [&"picked", {"item": "iron_ore", "count": 120}],
		[&"picked", {"item": "copper", "count": 12}], [&"picked", {"item": "lead", "count": 20}],
		[&"picked", {"item": "silver", "count": 5}], [&"picked", {"item": "diamond", "count": 1}],
		[&"sold", {"coins": 8400, "count": 90}], [&"sold", {"coins": 1900, "count": 25}],
		[&"died", {}], [&"died", {}],
	]:
		MetaEvents.apply(ev[0], ev[1])
	MetaState.sub("c")["dug"] = 640
	MetaState.sub("c")["picked"] = 380
	Achievements.evaluate()
	MetaState.root()["pts"] = 23
	svc.after_change()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("test_screenshot_meta: ", path, " ", img.get_size())

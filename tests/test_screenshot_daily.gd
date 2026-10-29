extends Node
## test_screenshot_daily — не автотест, а инструмент глаз: поднимает настоящую
## main-сцену, включает мета-слой, наполняет 13 миссий дня правдоподобным
## прогрессом и снимает: кнопку заданий на экране (в шахте и на поверхности),
## открытое окно (шкала звёзд, прокрутка вниз), подсказку плитки, взрыв награды
## и полёт звезды, замену, сундук на 10-й звезде, открытый сундук.
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_daily.tscn --rendering-driver opengl3 --resolution 448x960 -- /каталог
##
## Часы подменены (MetaClock.override_unix/override_tz_sec): кадр не зависит от даты.

var _out_dir := "/tmp/daily_screens"
const BASE_DAY := 20760
var _main: Node2D = null
var _svc: MetaService = null


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		_out_dir = a
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	GameState.world_seed = 4242
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	var director = _main.get_node("StoryDirector")
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
	Settings.reduce_motion = false
	GameState.ext.clear()
	MetaClock.override_unix = BASE_DAY * MetaClock.DAY + 13 * 3600 + 47 * 60
	MetaClock.override_tz_sec = 3 * 3600
	GameState.max_depth_reached = 140
	GameState.level = 12
	GameState.coins = 3420
	GameState.dollars = 3
	_svc = _main.get_node("MetaService")
	_svc._poll()
	MetaState.sub("daily")["last"] = MetaState.today()   # подарок дня уже взят — окно не всплывёт
	_main.hud.set_gauges_visible(true)
	_seed_progress()
	await _wait(3.2)   # тост дороги трофеев от подставного прогресса уходит

	# 1. Кнопка на поверхности: бейдж «1 готово», полоска дня, покачивание.
	await _shot("01_surface_button")

	# 2. В шахте.
	_main.player.y = 24.5
	await _wait(0.5)
	await _shot("02_mine_button")

	# 2б. Задание закрылось прямо в шахте: тост и значок летит от героя в кнопку.
	var hunt: Dictionary = QuestEngine.daily()[3]
	hunt["progress"] = int(hunt["target"]) - 1
	var ev = hunt["event"]
	_svc._apply(StringName(String(ev[0] if ev is Array else ev)), _event_for(hunt))
	await _wait(0.3)
	await _shot("02b_mine_quest_done_fly")
	await _wait(0.4)
	await _shot("02c_mine_quest_done_badge")
	await _wait(2.4)
	_main.player.y = 4.5

	# 3. Окно заданий: шкала звёзд, готовое сверху; прокрутка до конца списка.
	_svc.open_tasks()
	await _wait(0.6)
	await _shot("03_panel")
	_svc.tasks._scroll.scroll_vertical = 10000
	await _wait(0.3)
	await _shot("03b_panel_scrolled")
	_svc.tasks._scroll.scroll_vertical = 0
	await _wait(0.2)

	# 4. Подсказка плитки (название и описание — только в Tip).
	Tip.show_now(_svc.tasks._list.get_child(0))
	await _wait(0.25)
	await _shot("04_panel_tip")
	Tip.hide_all()

	# 5. Забрать готовое — взрыв значков из плитки, монеты летят в кошелёк окна.
	var claim := _find_button(_svc.tasks._list, "check")
	if claim != null:
		claim.pressed.emit()
		await _wait(0.2)
		await _shot("05_claim_burst")
		await _wait(0.35)
		await _shot("05b_star_fly")
		await _wait(1.0)

	# 6. Замена задания (бесплатная).
	var rr := _find_button(_svc.tasks._list, "reroll")
	if rr != null:
		rr.pressed.emit()
		await _wait(0.5)
		await _shot("06_after_reroll")

	# 7. Десять звёзд — сундук звёзд готов (серия 6); три миссии ещё впереди.
	var st: Dictionary = MetaState.sub("quests")["streak"]
	st["n"] = 5
	st["last"] = MetaState.today() - 1
	st["best"] = 9
	var left := 0
	for q in QuestEngine.daily():
		if QuestEngine.stars_today() >= 10:
			if not bool(q["claimed"]) and left < 1:
				q["progress"] = int(q["target"])   # одна выполнена, но не забрана
			left += 1
			continue
		q["progress"] = int(q["target"])
		if not bool(q["claimed"]):
			QuestEngine.claim(String(q["id"]))
	_svc.tasks.refresh()
	await _wait(0.6)
	await _shot("07_chest_ready")
	Tip.show_now(_svc.tasks.find_child("StarsRow", true, false))
	await _wait(0.25)
	await _shot("07b_stars_tip")
	Tip.hide_all()
	var open := _svc.tasks.find_child("Chest", true, false) as Button
	if open != null:
		open.pressed.emit()
		await _wait(0.22)
		await _shot("08_chest_burst")
		await _wait(1.4)
		await _shot("09_chest_open")
	for q in QuestEngine.daily():
		q["progress"] = int(q["target"])
		if not bool(q["claimed"]):
			QuestEngine.claim(String(q["id"]))
	_svc.tasks.refresh()
	await _wait(0.5)
	await _shot("09b_day_done")
	_svc.tasks.close()
	await _wait(0.5)
	await _shot("10_button_day_done")

	MetaClock.override_unix = -1
	MetaClock.override_tz_sec = MetaClock.TZ_AUTO
	get_tree().quit(0)


## Середина дня: копка 312/500, две миссии забраны, одна готова, остальное в работе.
func _seed_progress() -> void:
	var ds := QuestEngine.daily()
	var fr := [0.624, 1.0, 0.5, 0.34, 0.8, 1.0, 0.4, 0.34, 1.0, 0.0, 0.5, 0.2, 0.6]
	for i in range(ds.size()):
		var q: Dictionary = ds[i]
		q["progress"] = int(round(float(q["target"]) * float(fr[mini(i, fr.size() - 1)])))
	for i in [5, 8]:
		QuestEngine.claim(String(ds[i]["id"]))
	QuestEngine.mark_opened()
	_svc.after_change()


## Подставное событие, которое двигает это задание на единицу.
func _event_for(q: Dictionary) -> Dictionary:
	var d := {"cell": Vector2i(5, 200), "tile": TileTypes.Type.STONE, "loot": true, "count": 1, "depth": 9999,
		"amount": 1, "coins": 1, "blocks": 1}
	var f: Dictionary = q["filter"]
	if String(f.get("kind", "")) == "dirt":
		d["tile"] = TileTypes.Type.DIRT
		d["loot"] = false
	if f.has("item"):
		d["item"] = f["item"]
	if f.has("currency"):
		d["currency"] = f["currency"]
	return d


func _find_button(n: Node, icon_name: String) -> Button:
	if n is Button and (n as Button).icon == MetaUiKit.tex(icon_name) and (n as Button).text == "":
		return n
	for c in n.get_children():
		var f := _find_button(c, icon_name)
		if f != null:
			return f
	return null


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("test_screenshot_daily: ", path, " ", img.get_size())

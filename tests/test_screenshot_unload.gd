extends Node
## test_screenshot_unload — не автотест, а инструмент глаз: премиум-выгрузка на склад
## (раунд 6) на настоящей main.tscn — рюкзак до и после, витрина за доллары с плиткой
## выгрузки, карточка, «улетело домой», и шаги сцены на 150: затемнение с кнопкой
## магазина, затемнение с плиткой, полёт, объяснение по телефону.
##
##   export XDG_DATA_HOME=$PWD/.godot/xdg
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_unload.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог

var _out_dir := "/tmp/unload_shots"
var main: Node2D
var lesson: PremiumUnloadLesson
var director: StoryDirector


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	get_window().size = Vector2i(448, 960)
	Settings.reduce_motion = false
	await _spawn()
	await _shoot_purchase()
	await _shoot_lesson()
	print("test_screenshot_unload: снимки -> " + _out_dir)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _sec(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	await _frames(2)
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join(name + ".png"))


func _spawn() -> void:
	for f in ["user://save.json", "user://save.json.bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	GameState.reset_progress()
	StoryState.delete_from_disk()
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure",
			"workshop", "death", "backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2",
			"grave_call", "diary_first", "first_artifact", "depth_100"]:
		StoryState.mark_seen(id)
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "gold_sold", "food_ordered", "diary_found"]:
		StoryState.set_flag(f)
	GameState.grant_tool("iron_pickaxe")
	GameState.current_tool = "iron_pickaxe"
	GameState.grant_gear("backpack")
	GameState.current_gear = "backpack"
	GameState.max_depth_reached = 151   # без баннера вехи «сотка» поверх кадров
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(8)
	lesson = PremiumUnloadLesson.instance
	lesson.calm_wait_s = 0.0
	director = main.find_child("StoryDirector", true, false)
	_place_hero(151)
	await _sec(0.6)
	_close_popups()


func _close_popups() -> void:
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms) and ms.popup.is_open():
		ms.popup.close()


func _place_hero(depth: int) -> void:
	var w: WorldGen = main.world
	for y in range(depth - 2, depth + 1):
		for x in range(10, 24):
			w.dig_cell(x, y)
	var p = main.player
	p.x = 16.5
	p.y = float(depth) + 0.6
	p.vx = 0.0
	p.vy = 0.0
	p.on_ground = true
	p.digging = null
	p.frozen = false
	GameState.player_depth = depth
	GameState.max_depth_reached = maxi(GameState.max_depth_reached, depth)


func _loot() -> void:
	GameState.inventory.clear()
	GameState.inventory.merge({"iron_ore": 14, "copper": 9, "gold": 3, "coal": 6, "silver": 2,
		"food_soup": 1, "medkit": 1, "fuel_block": 2})
	GameState.inventory_changed.emit()


func _shoot_purchase() -> void:
	GameState.ext_set(PremiumUnloadLesson.EXT_KEY, {"lesson": "done"})   # урок снимаем отдельно
	_loot()
	GameState.dollars = 40
	var hud = main.hud
	hud.open_inventory()
	await _sec(0.5)
	await _shot("01_backpack_before")
	var sheet = hud.get("_inv_sheet")
	sheet.get("_unload_btn").pressed.emit()   # кнопка «на склад» в рюкзаке → карточка витрины
	await _sec(0.5)
	await _shot("02_card_from_backpack")
	var ui := ShopUI.instance
	ui._close_card(true)
	await _sec(0.3)
	await _shot("03_shop_premium")
	var t: ShopTile = ui._tiles["good:dollars:premium_unload"]
	ui._on_tile_pressed(t.offer, t)
	await _sec(0.4)
	ui._confirm_card()
	await _sec(0.42)
	await _shot("04_fly_home_mid")
	await _sec(0.55)
	await _shot("05_fly_home_count")
	await _sec(1.2)
	await _shot("06_shop_after")
	ui.close()
	await _frames(3)
	hud.open_inventory()
	await _sec(0.5)
	await _shot("07_backpack_after")
	hud.close_inventory()
	await _sec(0.4)


func _shoot_lesson() -> void:
	GameState.ext_set(PremiumUnloadLesson.EXT_KEY, {})
	_loot()
	GameState.dollars = 0
	GameState.max_depth_reached = 120
	_place_hero(151)
	GameState.max_depth_reached = 120
	GameState.update_max_depth(150)
	var guard := 0
	while not lesson.is_active() and guard < 200:
		guard += 1
		_close_popups()
		await _frames(1)
	await _sec(0.5)
	await _shot("10_lesson_shop_button")
	lesson.spotlight.tap(lesson.target_rect().get_center())
	await _sec(0.5)
	await _shot("11_lesson_tile")
	lesson.spotlight.tap(lesson.target_rect().get_center())
	await _sec(0.45)
	await _shot("12_lesson_fly")
	guard = 0
	while not director.cutscene.is_playing and guard < 600:
		guard += 1
		await _frames(1)
	var cs := director.cutscene
	var n := 0
	guard = 0
	while cs.is_playing and guard < 600:
		guard += 1
		await _frames(1)
		if cs._typing:
			cs._line.visible_ratio = 1.0
			cs._typing = false
		if cs._waiting_tap or cs._beat_timer > 0.0:
			await _frames(14)
			await _shot("13_explain_%02d" % n)
			n += 1
			cs._waiting_tap = false
			cs._beat_timer = 0.0
			cs._tap_target.visible = false
			cs._advance()
	await _sec(0.6)
	await _shot("19_after_lesson")

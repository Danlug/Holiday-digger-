extends Node
## test_screenshot_station — не автотест, а инструмент глаз: экран станции заправки
## (перегонка + заправка) до, во время и после перегонки. Нужен настоящий рендер:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_station.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [сцена ...]
##
## Сцены: world before refine coal menu empty tip. На диск (user://) тест не пишет.

var _out_dir := "/tmp/station_shots"
var _only: Array[String] = []
var _main: Node2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	for i in range(1, args.size()):
		_only.append(args[i])
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)

	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	GameState.world_seed = 4242
	GameState.max_depth_reached = 640
	GameState.coins = 4200
	GameState.owned_tools = ["shovel", "rusty_pickaxe", "iron_pickaxe", "hand_drill"]
	GameState.current_tool = "hand_drill"

	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(3)
	StoryState.flags()["bars_introduced"] = true
	StoryState.flags()["fuel_station_built"] = true
	_main.hud.set_gauges_visible(true)
	if WellReport.is_open():
		WellReport.instance().close()
	_stock()
	await _frames(3)

	if _want("world"):
		await _scene_world()
	if _want("before") or _want("refine"):
		await _scene_refine()
	if _want("coal"):
		await _scene_coal()
	if _want("menu"):
		await _scene_menu()
	if _want("empty"):
		await _scene_empty()
	if _want("tip"):
		await _scene_tip()
	print("test_screenshot_station: снимки -> " + _out_dir)
	get_tree().quit(0)


func _stock() -> void:
	GameState.inventory.clear()
	GameState.house_storage.clear()
	FuelTank.set_fuel("hand_drill", 0.8)
	GameState.inventory["peat"] = 26
	GameState.inventory["iron_ore"] = 6
	GameState.house_storage["peat"] = 40
	GameState.house_storage["fuel_block"] = 2
	GameState.inventory_changed.emit()


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(name + ".png"))


func _close_meta() -> void:
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms) and ms.popup.is_open():
		ms.popup.close()


func _scene_world() -> void:
	Settings.reduce_motion = false   # пар над кубом рисуется только с движением
	_close_meta()
	GameState.player_depth = 0
	var p = _main.player
	p.x = float(WorldGen.FUEL_STATION_X) + 1.0
	p.y = 0.5
	p.vx = 0.0
	p.vy = 0.0
	await get_tree().create_timer(1.2).timeout
	await _shot("st_0_world")
	Settings.reduce_motion = true


func _scene_refine() -> void:
	Settings.reduce_motion = true
	_close_meta()
	TechScreen.open(TechScreen.TAB_TANK, true)
	await _frames(4)
	await _shot("st_1_before")
	var s := TechScreen.instance()
	(s._ref["slider"] as HSlider).value = 4
	await _frames(2)
	await _shot("st_2_slider4")
	if not _want("refine"):
		TechScreen.close_screen()
		return
	Settings.reduce_motion = false
	(s._ref["slider"] as HSlider).value = (s._ref["slider"] as HSlider).max_value
	await _frames(1)
	(s._content.find_child("Still", true, false) as Button).pressed.emit()
	await get_tree().create_timer(0.3).timeout
	await _shot("st_3_flying_in")
	await get_tree().create_timer(0.55).timeout
	await _shot("st_4_flare")
	await get_tree().create_timer(0.45).timeout
	await _shot("st_5_blocks_out")
	await get_tree().create_timer(1.2).timeout
	await _shot("st_6_after")
	s._pour("pack", -1, s, s)
	await get_tree().create_timer(1.0).timeout
	await _shot("st_7_poured")
	Settings.reduce_motion = true
	TechScreen.close_screen()
	await _frames(2)


func _scene_coal() -> void:
	Settings.reduce_motion = true
	_stock()
	GameState.max_depth_reached = 1300
	GameState.inventory["coal"] = 9
	TechScreen.open(TechScreen.TAB_TANK, true)
	await _frames(3)
	var s := TechScreen.instance()
	(s._content.find_child("Raw_coal", true, false) as Button).pressed.emit()
	await _frames(3)
	await _shot("st_8_coal")
	TechScreen.close_screen()
	GameState.max_depth_reached = 640
	GameState.inventory.erase("coal")
	await _frames(2)


func _scene_menu() -> void:
	Settings.reduce_motion = true
	_stock()
	TechScreen.open(TechScreen.TAB_TANK, false)
	await _frames(4)
	await _shot("st_9_menu_locked")
	TechScreen.close_screen()
	await _frames(2)


func _scene_empty() -> void:
	Settings.reduce_motion = true
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.inventory["peat"] = 3
	TechScreen.open(TechScreen.TAB_TANK, true)
	await _frames(4)
	await _shot("st_10_not_enough")
	TechScreen.close_screen()
	await _frames(2)


func _scene_tip() -> void:
	Settings.reduce_motion = true
	_stock()
	TechScreen.open(TechScreen.TAB_TANK, true)
	await _frames(4)
	var s := TechScreen.instance()
	Tip.show_now(s._content.find_child("Still", true, false) as Control)
	await _frames(4)
	await _shot("st_11_tip_still")
	Tip.hide_all()
	Tip.show_now(s._content.find_child("Raw_peat", true, false) as Control)
	await _frames(4)
	await _shot("st_12_tip_peat")
	Tip.hide_all()
	TechScreen.close_screen()
	await _frames(2)

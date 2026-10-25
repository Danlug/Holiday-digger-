extends Node
## test_screenshot_tech — не автотест, а инструмент глаз: поднимает main.tscn и
## снимает экраны ветки «Техника» (станция заправки, бак, костюм, скважина, окно
## отчёта, лава с жаром и HUD-значки). Нужен настоящий рендер; окно вдвое крупнее,
## чтобы пиксели читались:
##
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_tech.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [сцена ...]
##
## Сцены: station tank suit well report lava hud. На диск (user://) тест не пишет.

var _out_dir := "/tmp/tech_shots"
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
	GameState.well_level = 4
	GameState.well_last_collect_unix = int(Time.get_unix_time_from_system())
	GameState.max_depth_reached = 1600
	GameState.coins = 18500
	GameState.owned_tools = ["shovel", "rusty_pickaxe", "iron_pickaxe", "hand_drill", "drill_rig"]
	GameState.current_tool = "hand_drill"

	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(3)
	# Сюжетные флаги — после запуска main: режиссёр при старте перечитывает их с диска.
	StoryState.flags()["bars_introduced"] = true
	StoryState.flags()["fuel_station_built"] = true
	_main.hud.set_gauges_visible(true)
	GameState.coins_changed.emit(GameState.coins)
	if WellReport.is_open():
		WellReport.instance().close()
	FuelTank.set_fuel("hand_drill", 3.4)
	FuelTank.set_fuel("drill_rig", 12.0)
	GameState.inventory["fuel_block"] = 7
	GameState.house_storage["fuel_block"] = 40
	GameState.house_storage["titanium"] = 12
	GameState.inventory["aluminium"] = 30
	GameState.inventory_changed.emit()
	await _frames(3)

	if _want("station"):
		await _scene_station()
	if _want("tank"):
		await _scene_tank()
	if _want("suit"):
		await _scene_suit()
	if _want("well"):
		await _scene_well()
	if _want("report"):
		await _scene_report()
	if _want("lava"):
		await _scene_lava()
	if _want("hud"):
		await _scene_hud()
	print("test_screenshot_tech: снимки -> " + _out_dir)
	get_tree().quit(0)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(name + ".png"))


func _stand_at(x: float, y: float) -> void:
	var p = _main.player
	p.x = x
	p.y = y
	p.vx = 0.0
	p.vy = 0.0
	p.digging = null


func _scene_station() -> void:
	Settings.reduce_motion = true
	GameState.player_depth = 0
	_stand_at(float(WorldGen.FUEL_STATION_X) + 1.0, 0.5)
	await _frames(8)
	await _shot("station_hotspot")
	_stand_at(float(WorldGen.WELL_X) + 1.0, 0.5)
	await _frames(8)
	await _shot("well_hotspot")


func _scene_tank() -> void:
	Settings.reduce_motion = true
	TechScreen.open(TechScreen.TAB_TANK, true)
	await _frames(4)
	await _shot("tank_station")
	TechScreen.instance().select_tool("drill_rig")
	await _frames(3)
	await _shot("tank_rig")
	TechScreen.close_screen()
	await _frames(2)


func _scene_suit() -> void:
	Settings.reduce_motion = true
	TechScreen.open(TechScreen.TAB_SUIT)
	await _frames(4)
	await _shot("suit_1")
	TechState.set_suit(2)
	GameState.max_depth_reached = 3600
	TechScreen.open(TechScreen.TAB_SUIT)
	await _frames(3)
	await _shot("suit_3_next")
	TechState.set_suit(0)
	GameState.max_depth_reached = 1600
	TechScreen.close_screen()
	await _frames(2)


func _scene_well() -> void:
	Settings.reduce_motion = true
	GameState.well_last_collect_unix = int(Time.get_unix_time_from_system()) - 5 * 3600 - 700
	TechScreen.open(TechScreen.TAB_WELL)
	await _frames(4)
	await _shot("well")
	TechScreen.close_screen()
	await _frames(2)


func _scene_report() -> void:
	Settings.reduce_motion = false
	GameState.max_depth_reached = 800
	GameState.well_level = 3
	GameState.well_last_collect_unix = int(Time.get_unix_time_from_system()) - 7 * 3600 - 1260
	var rep := IdleWell.collect()
	var w := WellReport.instance()
	w.show_report(rep)
	await get_tree().create_timer(0.7).timeout
	await _shot("report_a_tiles")
	await get_tree().create_timer(1.15).timeout
	await _shot("report_b_pouring")
	await get_tree().create_timer(1.6).timeout
	await _shot("report_c_done")
	w._on_double()
	await get_tree().create_timer(0.6).timeout
	await _shot("report_d_doubled")
	await get_tree().create_timer(1.2).timeout
	w.close()
	Settings.reduce_motion = true
	await _frames(2)


func _scene_lava() -> void:
	Settings.reduce_motion = false
	var world: WorldGen = _main.world
	var seed_v := GameState.world_seed
	# Ищем озеро лавы с двумя клетками высоты, где можно встать рядом.
	var found := Vector2i(-1, -1)
	for y in range(3030, 3400):
		for x in range(2, WorldGen.WIDTH - 2):
			if LavaField.is_lava(seed_v, x, y, 0) and LavaField.is_lava(seed_v, x + 1, y, 0) \
					and LavaField.is_lava(seed_v, x, y + 1, 0) and LavaField.is_lava(seed_v, x - 1, y, 0):
				found = Vector2i(x, y)
				break
		if found.x >= 0:
			break
	print("lava at ", found)
	GameState.max_depth_reached = 3100
	# Расчищаем площадку-пещеру слева и выше озера, лава остаётся нетронутой.
	for yy in range(found.y - 5, found.y + 3):
		for xx in range(found.x - 5, found.x + 3):
			if world.get_tile(xx, yy) != TileTypes.Type.LAVA and not (yy >= found.y + 2):
				world.dig_cell(xx, yy)
	_main.fog.reveal_around(found.x - 2.0, found.y - 1.0, 9, 9)
	GameState.player_depth = found.y - 1
	_stand_at(float(found.x) - 2.5, float(found.y) + 1.4)
	GameState.hp = 100.0
	GameState.is_alive = true
	await _frames(40)
	var ts := TechSystem.instance()
	print("haze visible=", ts._haze_rect.visible, " strength=", ts._haze_strength)
	await _shot("lava_cave")
	await _frames(30)
	await _shot("lava_cave_2")
	# Копка лавы с костюмом 3: идёт урон 6 HP/с, видны искры.
	TechState.set_suit(3)
	GameState.hp = 200.0
	var p = _main.player
	p.hold_dx = 1
	p.facing = 1
	await _frames(30)
	await _shot("lava_digging")
	p.hold_dx = 0
	TechState.set_suit(0)


func _scene_hud() -> void:
	Settings.reduce_motion = true
	await _frames(4)
	await _shot("hud_deep")

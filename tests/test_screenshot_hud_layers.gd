extends Node
## test_screenshot_hud_layers — не автотест, а инструмент глаз (ветка hud-layers, 26.10):
## жалоба владельца «штука с буром светится поверх других менюшек». Все HUD-виджеты
## разом на экране — трекер проекта «Ручной бур», бак бура и термометр, шкала азарта,
## значок курьера, кнопка «Тест» отладочной сборки — и поверх них окна HUD: рюкзак,
## настройки, меню «•••». Ни один виджет не должен просвечивать сквозь окно.
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_hud_layers.tscn --rendering-driver opengl3 --resolution 448x960 \
##       -- /каталог [виды через запятую] [префикс имён]
##
## Виды: base, backpack, settings, more. По умолчанию все.

var _out_dir := "/tmp/hud_layers_shots"
var _spec := "base,backpack,settings,more"
var _prefix := ""
var _main: Node2D = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_spec = args[1]
	if args.size() > 2:
		_prefix = args[2]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	GameState.world_seed = 4242
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	var director = _main.get_node("StoryDirector")
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered", "gold_sold",
			"backpack_owned"]:
		StoryState.set_flag(f)
	for sid in StoryData.scene_ids():
		StoryState.mark_seen(String(sid))
	for _i in range(6):
		if director.cutscene != null and director.cutscene.is_playing:
			director.cutscene.skip()
		await _wait(0.3)
	Settings.reduce_motion = true
	MetaState.sub("daily")["last"] = MetaState.today()   # окно дня не всплывёт
	_main.hud.set_gauges_visible(true)
	GameState.level = 9
	GameState.max_depth_reached = 760
	GameState.coins = 446
	GameState.grant_gear("backpack")
	GameState.inventory.clear()
	for id in ["gold", "iron_ore", "silver", "scrap", "peat", "energy_bar", "fuel_block", "noodles"]:
		GameState.inventory[id] = 2
	HintState.mark_seen("project_hand_drill")
	HintState.mark_seen("project_well")
	ProjectChain.set_tracked("hand_drill", false)
	# бур в руках — бак и термометр (глубина 760 — жарко) у левого края
	GameState.grant_tool("hand_drill")
	GameState.set_current_tool("hand_drill")
	_main.player.y = 760.5
	GameState.player_depth = 760
	# шкала азарта копится, курьер везёт заказ
	var mech := _main.get_node_or_null("MechDirector") as MechDirector
	if mech != null:
		mech.streak.work = 3.0
	var hs := _main.find_child("HouseSystem", true, false)
	if hs != null and hs.get("_delivery_badge") != null:
		hs.get("_delivery_badge").track("noodles", 40.0)
	await _wait(1.0)
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms) and ms.popup.is_open():
		ms.popup.close()
	var tech_hud := _main.find_child("TechHud", true, false)
	if tech_hud != null:
		tech_hud.call("refresh")
	await _wait(0.3)

	if _want("base"):
		await _shot("00_hud_widgets")
	if _want("backpack"):
		_main.hud.open_inventory()
		await _wait(0.5)
		await _shot("01_backpack")
		_main.hud.close_inventory()
		await _wait(0.5)
	if _want("settings"):
		_main.hud.open_settings()
		await _wait(0.5)
		await _shot("02_settings")
		_main.hud.close_settings()
		await _wait(0.5)
	if _want("more"):
		_main.hud.call("_toggle_more_menu")
		await _wait(0.5)
		await _shot("03_more_menu")
		_main.hud.close_more_menu()
		await _wait(0.5)
	get_tree().quit(0)


func _want(kind: String) -> bool:
	return _spec.split(",").has(kind)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s%s.png" % [_out_dir, _prefix, name]
	img.save_png(path)
	print("test_screenshot_hud_layers: ", path, " ", img.get_size())

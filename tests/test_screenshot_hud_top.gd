extends Node
## test_screenshot_hud_top — не автотест, а инструмент глаз (ветка hud-top, 27.10): верх HUD —
## портрет с лицом героя, часы под ним, кошелёк от верха экрана; огород, шахта со всеми плашками
## (бак бура, термометр, трекер проекта, азарт, курьер, задание), смоделированный вырез телефона, дом.
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_hud_top.tscn --rendering-driver opengl3 --resolution 448x960 \
##       -- /каталог [префикс имён] [вырез в единицах, по умолчанию 24]
##
## Широкий экран — тот же запуск с --resolution 960x960 (вьюпорт растягивается вширь).

var _out_dir := "/tmp/hud_top_shots"
var _prefix := ""
var _notch := 24.0
var _main: Node2D = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_prefix = args[1]
	if args.size() > 2:
		_notch = float(args[2])
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	GameState.world_seed = 4242
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	var director = _main.get_node("StoryDirector")
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered", "gold_sold",
			"backpack_owned", "death_seen", "robert_seen", "autodig_done", "workshop_seen"]:
		StoryState.set_flag(f)
	for sid in StoryData.scene_ids():
		StoryState.mark_seen(String(sid))
	GameState.house_tutorial_stage = 2
	for _i in range(6):
		if director.cutscene != null and director.cutscene.is_playing:
			director.cutscene.skip()
		await _wait(0.3)
	Settings.reduce_motion = true
	MetaState.sub("daily")["last"] = MetaState.today()   # окно дня не всплывёт
	var hud = _main.hud
	hud.set_gauges_visible(true)
	GameState.level = 9
	GameState.coins = 1250
	GameState.dollars = 3
	GameState.coins_changed.emit(GameState.coins)
	GameState.dollars_changed.emit(GameState.dollars)
	GameState.grant_gear("backpack")
	await _wait(1.0)
	_close_daily()
	await _shot("01_surface")

	# Шахта: бур в руках, 760 — жарко, трекер, азарт, курьер, задание.
	GameState.max_depth_reached = 760
	GameState.inventory.clear()
	for id in ["gold", "iron_ore", "silver", "scrap", "peat", "energy_bar", "fuel_block", "noodles"]:
		GameState.inventory[id] = 2
	HintState.mark_seen("project_hand_drill")
	HintState.mark_seen("project_well")
	ProjectChain.set_tracked("drill_rig")
	GameState.grant_tool("hand_drill")
	GameState.set_current_tool("hand_drill")
	_main.player.y = 760.5
	GameState.player_depth = 760
	var mech := _main.get_node_or_null("MechDirector") as MechDirector
	if mech != null:
		mech.set_process(false)
		mech.streak.work = 3.0
	var hs := _main.find_child("HouseSystem", true, false)
	if hs != null and hs.get("_delivery_badge") != null:
		hs.get("_delivery_badge").track("noodles", 900.0)
	await _wait(1.0)
	_close_daily()
	_refresh()
	await _wait(0.6)
	await _shot("02_mine_all")
	hud.set_objective("Задание: загляни к могиле деда — у забора огорода, правее двери")
	await _wait(0.4)
	await _shot("03_mine_objective")
	hud._on_quest_button_pressed()   # свернуть баннер

	HudSafeArea.debug_top = _notch
	hud._update_layout()
	_refresh()
	await _wait(0.7)
	await _shot("04_mine_notch")
	HudSafeArea.debug_top = -1.0
	hud._update_layout()
	await _wait(0.7)

	# Дом: HUD спрятан, курьер — на прежнем месте под шапкой дома.
	GameState.set_current_tool("shovel")
	_main.player.y = 0.5
	GameState.player_depth = 0
	await _wait(0.5)
	HouseSystem.instance.enter_house("hall")
	await _wait(0.8)
	await _shot("05_house")
	get_tree().quit(0)


func _refresh() -> void:
	var tech_hud := _main.find_child("TechHud", true, false)
	if tech_hud != null:
		tech_hud.call("refresh")


func _close_daily() -> void:
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms) and ms.popup.is_open():
		ms.popup.close()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s%s.png" % [_out_dir, _prefix, name]
	img.save_png(path)
	print("test_screenshot_hud_top: ", path, " ", img.get_size())

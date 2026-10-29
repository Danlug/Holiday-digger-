extends Node
## test_screenshot_guidance — не автотест, а инструмент глаз (ветка guidance):
## экран «Проекты», трекер на HUD (в шахте и «готово»), значки «нужно для…» на
## витрине продажи и на складе, кнопка «цепочка» на карточке рецепта и подсказка-
## знакомство. Нужен настоящий рендер:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_guidance.tscn --rendering-driver opengl3 --resolution 448x960 \
##       -- /каталог [виды через запятую]
##
## Виды: screen, tip, rig, titles, en, hud, ready, sell, storage, card, hint. По умолчанию все.
## titles — шапка «Проект: …» у каждого проекта; en — то же на английском.

var _out_dir := "/tmp/guidance_shots"
var _spec := "screen,tip,rig,titles,en,hud,ready,sell,storage,card,hint"
var _main: Node2D = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_spec = args[1]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	GameState.world_seed = 4242
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	var director = _main.get_node("StoryDirector")
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered", "gold_sold"]:
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
	GameState.max_depth_reached = 140
	GameState.coins = 1650
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.inventory["scrap"] = 34
	GameState.inventory["iron_ore"] = 22
	GameState.inventory["gold"] = 4
	GameState.inventory["silver"] = 6
	GameState.house_storage["iron_ore"] = 180
	GameState.house_storage["bronze"] = 25
	GameState.house_storage["silver"] = 50
	GameState.house_storage["lead"] = 12
	HintState.mark_seen("project_hand_drill")
	HintState.mark_seen("project_well")
	ProjectChain.set_tracked("hand_drill", false)
	await _wait(0.6)
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms) and ms.popup.is_open():
		ms.popup.close()
		await _wait(0.4)

	if _want("screen"):
		ProjectsScreen.open_for("hand_drill")
		await _wait(0.5)
		await _shot("01_screen_hand_drill")
	if _want("tip"):
		var s := ProjectsScreen.instance()
		if s != null and s.is_open():
			Tip.show_now(s._body.get_child(3).get_child(0))
			await _wait(0.3)
			await _shot("02_screen_tip_scrap")
			Tip.hide_all()
	if _want("rig"):
		var s2 := ProjectsScreen.instance()
		if s2 != null and s2.is_open():
			s2._set_project("drill_rig")
			await _wait(0.4)
			await _shot("03_screen_drill_rig")
	if _want("titles") or _want("en"):
		var s3 := ProjectsScreen.instance()
		var langs: Array = []
		if _want("titles"):
			langs.append("ru")
		if _want("en"):
			langs.append("en")
		for lang in langs:
			Settings.language = lang
			for id in ProjectChain.ids():
				s3._set_project(String(id))
				await _wait(0.3)
				await _shot("11_title_%s_%s" % [lang, id])
		Settings.language = "ru"
	ProjectsScreen.instance().close()
	await _wait(0.4)

	if _want("hud"):
		_main.player.y = 24.5
		await _wait(0.8)
		await _shot("04_hud_tracker_mine")
		_main.player.y = 0.5
		await _wait(0.4)
	if _want("ready"):
		GameState.house_storage["iron_ore"] = 500
		GameState.house_storage["bronze"] = 100
		GameState.coins = 2400
		await _wait(0.6)
		await _shot("05_hud_tracker_ready")
		GameState.house_storage["iron_ore"] = 180
		GameState.house_storage["bronze"] = 25
		GameState.coins = 1650
		await _wait(0.5)

	if _want("sell"):
		ShopUI.instance.open(ShopUI.TAB_SELL)
		await _wait(0.5)
		await _shot("06_sell_need_badges")
		var t: ShopTile = ShopUI.instance._tiles.get("sell:scrap")
		if t != null:
			Tip.show_now(t)
			await _wait(0.3)
			await _shot("07_sell_tip_scrap")
			Tip.hide_all()
	if _want("card"):
		ShopUI.instance._set_tab(ShopUI.TAB_TECH, false)
		await _wait(0.3)
		var rt: ShopTile = ShopUI.instance._tiles.get("recipe:hand_drill")
		if rt != null:
			ShopUI.instance._open_card(rt.offer, rt)
			await _wait(0.5)
			await _shot("08_recipe_card_chain_button")
			ShopUI.instance._close_card(false)
	ShopUI.instance.close()
	await _wait(0.3)

	if _want("storage"):
		var hs := _main.find_child("HouseSystem", true, false)
		GameState.house_is_indoors = true
		if hs != null and hs.has_method("open_storage"):
			hs.call("open_storage")
		else:
			var v = load("res://scripts/house/house_storage_view.gd").new()
			add_child(v)
			v.open()
		await _wait(0.5)
		await _shot("09_storage_need_badges")
		GameState.house_is_indoors = false

	if _want("hint"):
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if n.has_method("close_panel") and n.get("visible") != false:
				n.call("close_panel")
		await _wait(0.3)
		HintState.reset()
		for r: Dictionary in HintData.rules():
			if not String(r["id"]).begins_with("project_hand_drill"):
				HintState.mark_seen(String(r["id"]))
		var hd := HintDirector.instance()
		for _i in range(120):
			hd.tick(0.25)
			if hd.is_active():
				break
		await _wait(0.6)
		await _shot("10_hint_project")

	get_tree().quit(0)


func _want(kind: String) -> bool:
	return _spec.split(",").has(kind)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("test_screenshot_guidance: ", path, " ", img.get_size())

extends Node
## test_screenshot_pill — не автотест, а инструмент глаз: значок таблетки восстановления
## (item_full_restore_pill) во всех местах, где он показывается: плитка в магазине, карточка
## покупки, рюкзак, склад дома, тост (16 px). Нужен настоящий рендер, окно вдвое крупнее:
##
##   export XDG_DATA_HOME=$PWD/.godot/xdg
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_pill.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [снимок ...]
##
## Снимки: shop card inventory storage toast.

var _out_dir := "/tmp/pill_shots"
var _only: Array[String] = []
var _main: Node2D
var _shop: ShopUI
var _house: HouseSystem


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	for i in range(1, args.size()):
		_only.append(args[i])
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(2)
	var director = _main.get_node("StoryDirector")
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure", "workshop", "death",
			"backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2"]:
		StoryState.mark_seen(id)
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered"]:
		StoryState.set_flag(f)
	var meta = _main.get_node_or_null("MetaService")
	if meta != null:
		meta.set_process(false)
		if meta.popup != null and meta.popup.is_open():
			meta.popup.close()
	for _i in range(6):
		if director.cutscene != null and director.cutscene.is_playing:
			director.cutscene.skip()
		await _wait(0.3)
	Settings.reduce_motion = true
	_house = HouseSystem.instance
	_house.player = _main.player
	_house.hud = _main.hud
	for c in _main.get_children():
		if c is ShopUI:
			_shop = c
	GameState.house_is_indoors = true
	GameState.dollars = 8
	GameState.coins = 340
	GameState.inventory["full_restore_pill"] = 2
	GameState.inventory["energy_bar"] = 3
	GameState.house_storage["full_restore_pill"] = 5
	GameState.house_storage["iron_ore"] = 12
	GameState.house_storage["energy_bar"] = 4
	GameState.inventory_changed.emit()
	_main.hud.set_gauges_visible(true)
	await _frames(3)

	if _want("shop"):
		_shop.open(ShopUI.SCREEN_PREMIUM)
		await _frames(5)
		_shot("shop")
		_shop.close()
		await _frames(2)

	if _want("card"):
		_shop.open(ShopUI.SCREEN_PREMIUM)
		await _frames(3)
		var key := ""
		for k in _shop._tiles:
			if String(k).ends_with("full_restore_pill"):
				key = String(k)
		if key != "":
			var t: ShopTile = _shop._tiles[key]
			_shop._on_tile_pressed(t.offer, t)
			await _frames(8)
			_shot("card")
		else:
			print("плитки таблетки нет на премиум-вкладке")
		_shop.close()
		await _frames(2)

	if _want("inventory"):
		_main.hud.open_inventory()
		await _frames(4)
		_shot("inventory")
		_main.hud.close_inventory()
		await _frames(2)

	if _want("storage"):
		_house.enter_house("workshop")
		_house._view.set_hero_x_fraction(0.5)
		_house.open_storage()
		await _frames(4)
		_shot("storage")

	if _want("toast"):
		_main.hud.toast_parts([
			{"icon_tex": UiIcons.item("full_restore_pill"), "text": "+1", "color": Color.WHITE},
			{"icon_tex": UiIcons.item("energy_bar"), "text": "+1", "color": Color.WHITE},
		], 3.0, "good")
		await _frames(4)
		_shot("toast")

	print("test_screenshot_pill: снимки -> " + _out_dir)
	get_tree().quit(0)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(n + ".png"))

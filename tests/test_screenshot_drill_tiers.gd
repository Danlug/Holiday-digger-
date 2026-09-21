extends Node
## test_screenshot_drill_tiers — не автотест, а разовый инструмент (по
## образцу test_screenshot_rig.gd): запускает настоящую main-сцену, сажает
## героя в бурмобиль, копающий вбок (бур виден сбоку целиком, крупный план),
## и прогоняет по очереди все пять состояний бура — обычный (тир 0) и
## титан/платина/алмаз/обсидиан (тиры 1-4, GameState.drill_rig_tier), сохраняя
## по одному PNG на тир. Плюс отдельный кадр раздела «Техника» магазина —
## строки апгрейда бура (ShopUI, вкладка TAB_TECH).
##
## Нужен реальный рендер (не --headless):
##
##   xvfb-run godot --path . res://tests/test_screenshot_drill_tiers.tscn \
##       --rendering-driver opengl3 -- /tmp/out_dir
##
## Каталог для сохранения — первый аргумент после "--", по умолчанию /tmp.
## Кадры: drill_tier_0_base.png .. drill_tier_4_obsidian.png, shop_drill_upgrade.png.

var _out_dir := "/tmp"

const TIER_NAMES := ["0_base", "1_titanium", "2_platinum", "3_diamond", "4_obsidian"]


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		_out_dir = a
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)

	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")

	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var player = main.player
	var world = main.world

	GameState.current_tool = "drill_rig"

	var cell := Vector2i(-1, -1)
	for y in range(15, 60):
		for x in range(10, 30):
			if world.get_tile(x, y) == TileTypes.Type.DIRT \
					and world.get_tile(x + 1, y) == TileTypes.Type.DIRT:
				cell = Vector2i(x, y)
				break
		if cell.x >= 0:
			break
	if cell.x < 0:
		push_error("test_screenshot_drill_tiers: не нашлась клетка земли сбоку для копки")
		get_tree().quit(1)
		return

	player.x = float(cell.x) + 0.5
	player.y = float(cell.y) + 0.5
	player.vx = 0.0
	player.vy = 0.0
	player.on_ground = true
	player.facing = 1
	player.digging = {"x": cell.x + 1, "y": cell.y, "t": 0.0, "total": 999.0,
			"type": TileTypes.Type.DIRT}
	player.frozen = true   # только отрисовка, физика не переигрывает позу

	for i in range(5):
		GameState.drill_rig_tier = i
		# ждём, пока анимация копки дойдёт до цикла бурения (тот же запас
		# кадров, что в test_screenshot_rig.gd).
		for f in range(90):
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := _out_dir.path_join("drill_tier_" + TIER_NAMES[i] + ".png")
		img.save_png(path)
		print("  сохранено: " + path)

	GameState.drill_rig_tier = 0
	player.digging = null
	player.frozen = false

	# --- строка апгрейда бура в магазине (вкладка «Техника») ---
	GameState.owned_tools.append("drill_rig")
	GameState.coins = 500000
	var ui = load("res://scenes/shop.tscn").instantiate()
	add_child(ui)
	ui.open(ShopUI.TAB_TECH)
	await get_tree().process_frame
	await get_tree().process_frame
	# Апгрейд бура — последний блок списка, ниже рецептов техники: список
	# длиннее экрана, и без прокрутки строку не увидеть в кадре вовсе (см.
	# scroll — ScrollContainer, 4-й ребёнок _root: bg/head/tabs/scroll/footer).
	var scroll: ScrollContainer = ui._root.get_child(3)
	scroll.scroll_vertical = 100000
	await get_tree().process_frame
	var shop_img := get_viewport().get_texture().get_image()
	var shop_path := _out_dir.path_join("shop_drill_upgrade.png")
	shop_img.save_png(shop_path)
	print("  сохранено: " + shop_path)

	get_tree().quit(0)

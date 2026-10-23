extends Node
## test_screenshot_juice — разовый QA-инструмент (не автотест): поднимает
## настоящую main-сцену и снимает частицы, всплывающие числа, вспышку и летящие
## монеты на реальном рендере. Нужен настоящий рендер:
##
##   xvfb-run -a godot --path . res://tests/test_screenshot_juice.tscn \
##       --rendering-driver opengl3 -- /каталог
##
## Снимки лежат в каталоге из первого аргумента после "--".

var _out := "/tmp/juice_shots"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		_out = a
	if not DirAccess.dir_exists_absolute(_out):
		DirAccess.make_dir_recursive_absolute(_out)
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 40:
		await get_tree().process_frame
	_shot("00_base")

	var p: Node2D = main.player
	var base := Vector2(float(p.cell_x()) * 32.0 + 16.0, float(p.cell_y()) * 32.0)

	# все виды частиц одним кадром
	var kinds := ["dig_dirt", "dig_stone", "dig_ore", "dig_gold", "spark", "poof",
			"hit_enemy", "enemy_die", "levelup", "coins", "heal", "fire"]
	for i in kinds.size():
		var col := i % 4
		var row := i / 4
		var pos := base + Vector2(float(col - 1) * 52.0 - 20.0, float(row) * 44.0 - 36.0)
		var tint := Color(0, 0, 0, 0)
		if kinds[i] == "dig_ore":
			tint = (get_tree().get_first_node_in_group(Fx.GROUP) as FxService).tile_accent(TileTypes.Type.IRON_ORE)
		Fx.burst(kinds[i], pos, 1.4, tint)
	await get_tree().create_timer(0.16).timeout
	_shot("01_kinds_early")
	await get_tree().create_timer(0.25).timeout
	_shot("02_kinds_late")
	await get_tree().create_timer(1.0).timeout

	# всплывающие числа и иконки
	var coin: Texture2D = load("res://art/ui/icon_coin.png")
	var gold_tex := TileArt.texture_for(TileTypes.Type.GOLD_ORE, 0, 0)
	Fx.float_icon(base + Vector2(-30, -40), gold_tex, "+3", Color("F2E9D0"))
	Fx.float_icon(base + Vector2(20, -52), TileArt.texture_for(TileTypes.Type.DIAMOND, 0, 0), "+1", Color("6FE0D8"))
	Fx.float_text(base + Vector2(0, -80), "-12", Color("FF5570"))
	Fx.float_text(base + Vector2(0, -100), "УР. 5", Color("FFE066"))
	Fx.float_icon(base + Vector2(-20, -66), coin, "+250", Color("E8B32E"))
	await get_tree().create_timer(0.3).timeout
	_shot("03_popups")
	await get_tree().create_timer(1.2).timeout

	# вспышка урона и летящие монеты
	Fx.flash(Color(0.85, 0.08, 0.1, 0.45), 0.6)
	Fx.fly_to(null, Vector2(112, 300), HudAnchors.get_anchor("coins"), 8)
	await get_tree().create_timer(0.3).timeout
	_shot("04_flash_fly")
	await get_tree().create_timer(0.25).timeout
	_shot("05_fly_late")
	await get_tree().create_timer(1.0).timeout

	# настоящая цепочка: копка вниз событием dug
	for t in [TileTypes.Type.DIRT, TileTypes.Type.STONE, TileTypes.Type.GOLD_ORE, TileTypes.Type.EMERALD]:
		GameState.emit_event(&"dug", {"cell": Vector2i(p.cell_x(), p.cell_y() + 1), "tile": t, "mineral": "x", "loot": false,
				"pos": Vector2(float(p.cell_x()) * 32.0 + 16.0, float(p.cell_y() + 1) * 32.0 + 16.0)})
		await get_tree().create_timer(0.12).timeout
		_shot("06_dug_%d" % t)
		await get_tree().create_timer(0.6).timeout
	get_tree().quit(0)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))

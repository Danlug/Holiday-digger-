extends Node
## test_screenshot_hero_ground — не автотест, а снимок героя В ИГРЕ крупно (зона
## boy-scale): поднимает main.tscn, ставит героя на поверхность, даёт физике
## осесть и снимает экран в нескольких позах, а рядом кладёт увеличенный ×4
## вырез вокруг героя — чтобы глазами сверить подошву с кромкой земли.
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_hero_ground.tscn --rendering-driver opengl3 --resolution 448x960 -- /каталог
##
## Снимки: ground_idle.png, ground_walk.png, ground_dig_side_drill.png,
## ground_dig_down_pick.png, ground_fly.png (+ *_zoom.png — вырез ×4).

var _out_dir := "/tmp/hero_ground"
var _main: Node2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	StoryState.flags()["bars_introduced"] = true

	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(4)
	var player = _main.player
	var world = _main.world

	# Поверхность: клетка 20, ряд 0 — физика сама сажает героя на землю.
	player.x = 20.5
	player.y = 0.5
	player.vx = 0.0
	player.vy = 0.0
	player.hold_dx = 0
	player.hold_up = false
	player.hold_down = false
	await _frames(30)
	await _shot("ground_idle", player)

	player.frozen = true
	player.vx = 2.0
	player.anim = 40.0
	await _frames(2)
	await _shot("ground_walk", player)
	player.vx = 0.0

	# Ручной бур вбок: клетка справа — земля (ряд 1 под поверхностью).
	var cy := 2
	var cx := 20
	for y in range(1, 12):
		if world.get_tile(cx, y) != TileTypes.Type.EMPTY and world.get_tile(cx + 1, y) != TileTypes.Type.EMPTY:
			cy = y
			break
	world.unlock_pre_autodig_garden()
	if not world.dig_cell(cx, cy):
		print("клетка %d,%d не выкопалась" % [cx, cy])
	player.x = cx + 0.5
	player.y = float(cy) + 0.5
	player.frozen = false
	await _frames(30)   # оседает на дно клетки
	player.frozen = true
	player.facing = 1
	GameState.current_tool = "hand_drill"
	player.digging = {"x": cx + 1, "y": cy, "t": 0.0, "total": 999.0, "type": TileTypes.Type.DIRT}
	await _frames(20)
	await _shot("ground_dig_side_drill", player)
	player.digging = null
	await _frames(20)
	await _shot("ground_idle_pit", player)

	GameState.current_tool = "pickaxe"
	player.digging = {"x": cx, "y": cy + 1, "t": 0.0, "total": 999.0, "type": TileTypes.Type.DIRT}
	await _frames(20)
	await _shot("ground_dig_down_pick", player)
	player.digging = null

	player.on_ground = false
	player.thrust = "up"
	_main.find_child("CharacterView", true, false).set_flight_tier(1)
	await _frames(4)
	await _shot("ground_fly", player)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(name: String, player) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(name + ".png"))
	# Вырез вокруг героя ×4: экранная точка героя = (позиция в мире − камера) × масштаб окна.
	var cv: Node2D = _main.find_child("CharacterView", true, false)
	var screen := cv.get_global_transform_with_canvas().origin
	var scale_k: float = get_viewport().get_screen_transform().get_scale().x
	var c := Vector2i(int(screen.x * scale_k), int(screen.y * scale_k))
	var half := Vector2i(int(60 * scale_k), int(60 * scale_k))
	var r := Rect2i(c - half, half * 2).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	crop.resize(crop.get_width() * 4, crop.get_height() * 4, Image.INTERPOLATE_NEAREST)
	crop.save_png(_out_dir.path_join(name + "_zoom.png"))
	print("снимок: ", name, " герой на экране ", screen, " масштаб ", scale_k)

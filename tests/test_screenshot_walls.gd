extends Node
## test_screenshot_walls — не автотест, а инструмент глаз: подземная стена-фон на настоящем рендере
## (ветка «walls»). На каждой глубине вырыт тоннель с шахтой и залом, герой стоит внутри, рядом монстры,
## чтобы видеть, читаются ли герой, руда и монстры на фоне. Запуск:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" \
##       godot --path . res://tests/test_screenshot_walls.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [глубины через запятую] [префикс]
##
## По умолчанию: 50,600,1500,2500,3500,5000,7500,9000. Файлы: <префикс>_<глубина>.png.

var _out_dir := "/tmp/walls_shots"
var _spec := "50,600,1500,2500,3500,5000,7500,9000"
var _prefix := "wall"
var main: Node2D
var director: CombatDirector


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
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	StoryState.flags()["bars_introduced"] = true
	Settings.reduce_motion = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(4)
	main.hud.set_gauges_visible(true)
	director = CombatService.director as CombatDirector
	director.spawning_enabled = false
	GameState.max_depth_reached = 10000
	main.player._announced_backpack = true
	main.player._announced_jetpack = true
	main.player._announced_rig = true
	for item in _spec.split(","):
		await _shoot(int(item))
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _cell(x: int, y: int) -> void:
	main.world.diffs[y * WorldGen.WIDTH + x] = true


## Тоннель во всю ширину кадра, шахта вверх, зал с «карманом» и боковая ниша: видны и широкая пустота, и узкая.
func _carve(cy: int) -> void:
	for x in range(8, 26):
		for dy in range(-1, 2):
			_cell(x, cy + dy)
	for dy in range(-6, -1):
		_cell(16, cy + dy)
		_cell(17, cy + dy)
	for x in range(11, 15):
		for dy in range(-5, -1):
			_cell(x, cy + dy)
	for x in range(19, 22):
		for dy in range(2, 5):
			_cell(x, cy + dy)
	for dy in range(2, 7):
		_cell(12, cy + dy)


func _shoot(depth: int) -> void:
	var cy := maxi(depth, 3)
	_carve(cy)
	director.cw.invalidate()
	var p = main.player
	p.x = 15.5
	p.y = float(cy) + 1.0
	p.vx = 0.0
	p.vy = 0.0
	p.on_ground = true
	p.facing = 1
	p.frozen = false
	main.fog.reveal_around(p.x, p.y, 10, 10)
	GameState.player_depth = cy
	GameState.hp = GameState.get_max_hp()
	director.monsters.clear()
	director.iframes = 99.0
	director.swing_cd = 99.0
	for spec in [["cinder_grub", 19.5, 0.9], ["gloom_moth", 12.5, -0.9]]:
		var m := director.spawn({"id": spec[0], "x": float(spec[1]), "y": float(cy) + float(spec[2]), "group": 1, "emerge": Vector2.ZERO})
		m.state = "patrol"
	director.set_process(false)
	await _frames(6)
	main.fog.reveal_around(p.x, p.y, 10, 10)
	await _frames(20)
	if main.hud._toast_panel != null:
		main.hud._toast_panel.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%d.png" % [_out_dir, _prefix, depth]
	img.save_png(path)
	print("снимок: ", path, " ", img.get_size(), " пояс: ", Biomes.name_at(cy))
	director.set_process(true)
	director.monsters.clear()

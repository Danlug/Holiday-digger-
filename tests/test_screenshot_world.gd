extends Node
## Скриншоты настоящего рендера мира на разных глубинах (ветка «world»): пояса,
## швы, читаемость руды, стена-фон, образования. Не автотест. Запуск:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" \
##       godot --path . res://tests/test_screenshot_world.tscn \
##       --rendering-driver opengl3 --resolution 448x960 -- /tmp/world_shots [глубины и виды через запятую]
##
## Второй аргумент: список, например "5,300,1200,cavern:1500,ruin:4200,grotto:2500,vein:900,pit:1000".
## Герой телепортируется (player.x/y), вокруг выкапывается карман, туман раскрывается широко.

var _out_dir := "/tmp/world_shots"
var _spec := "5,300,1200,3000,4000,6000,9000"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_spec = args[1]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)

	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	for item in _spec.split(","):
		var parts := item.split(":")
		var kind := "plain"
		var depth := 0
		if parts.size() == 2:
			kind = parts[0]
			depth = int(parts[1])
		else:
			depth = int(parts[0])
		await _shoot(main, kind, depth)
	get_tree().quit(0)


## Ближайшее образование нужного вида не выше глубины from: возвращает центр.
func _find_formation(world: WorldGen, kind: String, from: int) -> Vector2i:
	var want := Formations.NAMES.find(kind)
	for s in range((from - 1) / 36, 400):
		var f := Formations.slot_params(world, s)
		if f.is_empty() or int(f.kind) != want:
			continue
		return Vector2i((int(f.x0) + int(f.x1)) / 2, (int(f.y0) + int(f.y1)) / 2)
	return Vector2i(-1, -1)


func _shoot(main: Node2D, kind: String, depth: int) -> void:
	var world: WorldGen = main.world
	var player = main.player
	var cx := 20
	var cy := depth
	if Formations.NAMES.has(kind):
		var c := _find_formation(world, kind, depth)
		if c.x < 0:
			print("нет образования ", kind, " глубже ", depth)
			return
		cx = c.x
		cy = c.y
		if kind == "ruin" or kind == "grotto" or kind == "cavern":
			cy = c.y
	# карман 3x4 под героем, чтобы стоял в пустоте (для plain)
	if kind == "plain" or kind == "vein" or kind == "warn" or kind == "impact":
		for dx in range(-1, 2):
			for dy in range(0, 4):
				world.dig_cell(cx + dx, cy + dy)
		for dx in range(2, 4):
			world.dig_cell(cx + dx, cy + 3)
			world.dig_cell(cx + dx, cy + 2)
	var on_surface := kind == "surface" or kind == "night"
	if on_surface:
		cx = 22
		cy = 0
	if kind == "night":
		main.surface_life.force_dark = 1.0
	player.x = float(cx) + 0.5
	player.y = float(cy) + (0.5 if on_surface else 1.5)
	player.vx = 0.0
	player.vy = 0.0
	main.fog.reveal_around(player.x, player.y, 8, 6)
	GameState.player_depth = cy
	for i in range(6):
		await get_tree().process_frame
	main.fog.reveal_around(player.x, player.y, 8, 6)
	if kind == "warn":
		main.collapse_fx.warn({"x0": cx - 3, "y0": cy + 2, "w": 8, "h": 6}, 9.0)
	elif kind == "impact":
		main.collapse_fx.impact({"x0": cx - 3, "y0": cy + 2, "w": 8, "h": 6})
	for i in range(40 if kind != "impact" else 8):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%d.png" % [_out_dir, kind, depth]
	img.save_png(path)
	print("снимок: ", path, " ", img.get_size(), " герой y=", snappedf(player.y, 0.1),
			" частиц: ", main.ambient_fx.particle_count(), " пояс: ", Biomes.name_at(cy))

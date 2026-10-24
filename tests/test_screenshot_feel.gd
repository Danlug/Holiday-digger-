extends Node
## Скриншоты «ощущения» (ветка aaa-feel): трещины на копаемой клетке по стадиям,
## «+N» со слиянием, карточка смерти, камера на ходу (упреждение) и наезд. Не
## автотест. Запуск:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" \
##       godot --path . res://tests/test_screenshot_feel.tscn \
##       --rendering-driver opengl3 --resolution 448x960 -- /tmp/feel_shots [виды через запятую]
##
## Виды: cracks (три стадии), loot, death, walk, punch. По умолчанию все.

var _out_dir := "/tmp/feel_shots"
var _spec := "cracks,loot,walk,punch,death"
var main: Node2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_spec = args[1]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)

	GameState.world_seed = 777
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	GameState.current_tool = "iron_pickaxe"
	for kind in _spec.split(","):
		match kind:
			"cracks":
				await _cracks()
			"loot":
				await _loot()
			"death":
				await _death()
			"walk":
				await _walk()
			"punch":
				await _punch()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("снимок: ", path, " ", img.get_size())


## Герой стоит в кармане на глубине depth, справа от него камень.
func _pocket(depth: int, tile: int) -> Vector2i:
	var world: WorldGen = main.world
	var player = main.player
	var cx := 20
	for dx in range(-2, 2):
		for dy in range(0, 4):
			world.dig_cell(cx + dx, depth + dy)
	player.x = float(cx) + 0.5
	player.y = float(depth) + 2.5
	player.vx = 0.0
	player.vy = 0.0
	player.release_control()
	GameState.player_depth = depth
	main.fog.reveal_around(player.x, player.y, 8, 6)
	# сплошная стена справа: тайл нужного вида в клетке, которую копаем
	var target := Vector2i(cx + 1, depth + 2)
	world.diffs.erase(target.y * WorldGen.WIDTH + target.x)
	return target


## Камень, у которого слева есть твёрдый пол: герой встанет рядом и бьёт вправо.
func _stone_with_floor() -> Vector2i:
	var world: WorldGen = main.world
	for y in range(8, 80):
		for x in range(WorldGen.GARDEN_X_MIN + 3, WorldGen.WIDTH - 2):
			if world.get_tile(x, y) == TileTypes.Type.STONE and world.get_tile(x - 1, y + 1) != TileTypes.Type.EMPTY \
					and world.get_tile(x - 1, y) != TileTypes.Type.EMPTY:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _cracks() -> void:
	var player = main.player
	var world: WorldGen = main.world
	var s := _stone_with_floor()
	print("камень для трещин: ", s)
	world.dig_cell(s.x - 1, s.y)
	world.dig_cell(s.x - 1, s.y - 1)
	world.dig_cell(s.x - 2, s.y)
	world.dig_cell(s.x - 2, s.y - 1)
	player.x = float(s.x - 1) + 0.5
	player.y = float(s.y) + 0.5
	player.vx = 0.0
	player.vy = 0.0
	player.release_control()
	GameState.player_depth = s.y
	main.fog.reveal_around(player.x, player.y, 8, 6)
	await _frames(6)
	for stage in [[0.2, "a"], [0.55, "b"], [0.95, "c"]]:
		var frac: float = stage[0]
		player.digging = {"x": s.x, "y": s.y, "t": frac * 1000.0, "total": 1000.0, "type": TileTypes.Type.STONE}
		await _frames(3)
		await _shot("cracks_%s" % stage[1])
	player.digging = null


func _loot() -> void:
	var player = main.player
	_pocket(60, TileTypes.Type.STONE)
	await _frames(4)
	var head := Vector2(player.x, player.y - 0.9) * 32.0
	var icon: Texture2D = UiIcons.item("iron_ore")
	for i in 3:
		Fx.float_stack("iron_ore", head, icon, 1, Color("F2E9D0"))
	Fx.float_stack("silver", head + Vector2(-26, 8), UiIcons.item("silver"), 2, Color("F2E9D0"))
	Fx.float_stack("ruby", head + Vector2(26, -6), UiIcons.item("ruby"), 1, Color("6FE0D8"))
	Fx.burst("spark", head + Vector2(26, -6), 2.0)
	await _frames(8)
	await _shot("loot_stack")


func _death() -> void:
	# reset_progress() нельзя: он шлёт max_depth_changed(0), и режиссёр сюжета проигрывает интро заново
	GameState.inventory.clear()
	GameState.black_box.clear()
	GameState.add_item("iron_ore", 14)
	GameState.add_item("silver", 6)
	GameState.add_item("diamond", 2)
	GameState.add_item("ruby", 1)
	GameState.add_item("coal", 9)
	GameState.add_to_black_box("gold", 7)
	GameState.coins = 4280
	GameState.level = 12
	GameState.max_depth_reached = 640
	GameState.player_depth = 410
	StoryState.set_flag("gold_sold", true)
	var rep := DeathCard.build_report(GameState.inventory.duplicate(), 410, "fall")
	var card: DeathCard = main.get_node("FeelDirector").card
	card.open(rep)
	await _frames(14)
	await _shot("death_card")
	card.close()
	StoryState.set_flag("gold_sold", false)


func _walk() -> void:
	var player = main.player
	_pocket(80, TileTypes.Type.STONE)
	for dx in range(2, 12):
		for dy in range(0, 4):
			main.world.dig_cell(20 + dx, 80 + dy)
	await _frames(20)
	player.set_intent(1, false, false)
	await _frames(50)
	await _shot("walk_lead_right")
	player.set_intent(0, false, false)
	player.release_control()


func _punch() -> void:
	var player = main.player
	_pocket(100, TileTypes.Type.STONE)
	await _frames(20)
	Feel.punch(0.07)
	await _frames(2)
	await _shot("punch_peak")
	await _frames(40)
	await _shot("punch_after")

extends Node
## Скриншоты отклика удачи (ветка luck-juice, владелец 27.10): обычная находка руды
## и та же находка при удаче — крупнее значок с «×N», вспышка, толчок и наезд камеры.
## Не автотест. Запуск:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" \
##       godot --path . res://tests/test_screenshot_luck_juice.tscn \
##       --rendering-driver opengl3 --resolution 448x960 -- /каталог
##
## Кадры: normal_* (без удачи), lucky_* (удача ×3) — через 40, 250 и 700 мс после удара.

var _out_dir := "/tmp/luck_juice_shots"
var main: Node2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	GameState.world_seed = 777
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	GameState.current_tool = "iron_pickaxe"
	GameState.skill_stages["luck_chance"] = 5
	GameState.skill_stages["luck_multiplier"] = 2
	await _find("normal", false, 60)
	await _frames(90)
	await _find("lucky", true, 64)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("снимок: ", path, " ", img.get_size())


## Герой в кармане на глубине depth бьёт вправо по железной руде.
func _find(tag: String, lucky: bool, depth: int) -> void:
	var world: WorldGen = main.world
	var player = main.player
	var cx := 20
	for dx in range(-3, 0):
		for dy in range(0, 4):
			world.dig_cell(cx + dx, depth + dy)
	player.x = float(cx) - 0.5
	player.y = float(depth) + 3.5
	player.vx = 0.0
	player.vy = 0.0
	player.release_control()
	GameState.player_depth = depth
	main.fog.reveal_around(player.x, player.y, 8, 6)
	# клетка справа — камень или земля; награду считает тип из digging (руда)
	var target := Vector2i(cx, depth + 3)
	await _frames(30)
	player._luck_rng = _rng(5.0, lucky)
	player.digging = {"x": target.x, "y": target.y, "t": 0.0, "total": 1.0, "type": TileTypes.Type.IRON_ORE}
	player._finish_dig()
	# по часам, а не по кадрам: под xvfb кадр бывает и 16, и 100 мс
	var t0 := Time.get_ticks_msec()
	for ms in [40, 250, 700]:
		while Time.get_ticks_msec() - t0 < ms:
			await get_tree().process_frame
		_shot("%s_%03d" % [tag, ms])


## Сид, у которого первый бросок попадает (или не попадает) в percent.
func _rng(percent: float, hit: bool) -> RandomNumberGenerator:
	for s in range(1, 5000):
		var r := RandomNumberGenerator.new()
		r.seed = s
		if (r.randf() * 100.0 < percent) == hit:
			var out := RandomNumberGenerator.new()
			out.seed = s
			return out
	return null

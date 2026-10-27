extends Node
## Скриншоты отклика на урон (HurtJuice, владелец 27.10): один удар по фазам
## (сразу, конец задержки 0.3 с, середина возврата, после 3.3 с), серия ударов
## (наезд и краснота стопкой, потолки) и голод (слабый ровный фон). Не автотест.
## Время стоит (Engine.time_scale = 0), отклик шагается вручную — кадры точные.
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" \
##       godot --path . res://tests/test_screenshot_hurt.tscn \
##       --rendering-driver opengl3 --resolution 448x960 -- /tmp/hurt_shots

var _out_dir := "/tmp/hurt_shots"
var main: Node2D
var hj: HurtJuice


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
	hj = main.get_node("FeelDirector").hurt
	_pocket(60)
	await _frames(20)
	Engine.time_scale = 0.0
	hj.set_process(false)
	await _shot("0_before")

	# один удар
	GameState.take_damage(10.0, "monster:cave_bat")
	_adv(0.02)
	await _shot("1_hit_0.02s")
	_adv(0.27)
	await _shot("1_hit_0.29s_hold")
	_adv(1.2)
	await _shot("1_hit_1.5s_return")
	_adv(1.85)
	await _shot("1_hit_3.35s_done")

	# серия: четыре удара раз в 0.4 с, затем пятый — потолки
	for i in 5:
		GameState.take_damage(10.0, "monster:cave_bat")
		_adv(0.02)
		await _shot("2_series_hit%d" % (i + 1))
		_adv(0.38)
	_adv(3.5)
	await _shot("2_series_done")

	# голод: 1 HP/с каплями
	for i in 200:
		GameState.take_damage(0.01, "starvation")
		_adv(0.01)
	await _shot("3_starvation")
	_adv(3.5)
	Engine.time_scale = 1.0
	get_tree().quit(0)


## Шаг отклика вручную (кадры при time_scale = 0 приходят с delta = 0).
func _adv(seconds: float) -> void:
	var dt := 0.01
	for i in int(round(seconds / dt)):
		CameraKick.tick(dt, main.player)
		hj.tick(dt)
	# тряска живёт на delta кадров (а их нет): короткая (0.2 с) к этому моменту уже кончилась бы
	var fx = get_tree().get_first_node_in_group(Fx.GROUP)
	if seconds >= 0.2 and fx != null:
		fx._reset_shake()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("снимок: ", path, " зум ", snappedf(main._cam_rig.zoom, 0.001), " краснота ", snappedf(hj.alpha(), 0.001))


func _pocket(depth: int) -> void:
	var world: WorldGen = main.world
	var player = main.player
	var cx := 20
	for dx in range(-2, 2):
		for dy in range(0, 4):
			world.dig_cell(cx + dx, depth + dy)
	player.x = float(cx) + 0.5
	player.y = float(depth) + 3.5
	player.vx = 0.0
	player.vy = 0.0
	player.release_control()
	GameState.player_depth = depth
	main.fog.reveal_around(player.x, player.y, 8, 6)

extends Node
## test_screenshot_rig_jump_fly — не автотест, а разовый инструмент (по
## образцу test_screenshot_rig.gd): запускает настоящую main-сцену, сажает
## героя в бурмобиль на поверхности и прогоняет его через прыжок,
## приземление и начало полёта, сохраняя PNG на каждом шаге анимации —
## для визуальной проверки art/character/rig_jump.png/rig_fly.png в игре.
## Нужен реальный рендер (не --headless):
##
##   xvfb-run godot --path . res://tests/test_screenshot_rig_jump_fly.tscn \
##       --rendering-driver opengl3 -- /tmp/out_dir
##
## Каталог для сохранения — первый аргумент после "--", по умолчанию /tmp.
## Кадры: rig_jump_XX_<фаза>.png (прыжок/приземление), rig_fly_XX_<фаза>.png
## (розжиг турбины).

var _out_dir := "/tmp"


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

	# Бурмобиль — требует владения; тест только про отрисовку.
	GameState.current_tool = "drill_rig"
	player.x = 20.5
	player.y = 0.5   # поверхность
	player.vx = 0.0; player.vy = 0.0
	player.on_ground = true
	player.digging = null
	player.hold_dx = 0; player.hold_up = false; player.hold_down = false

	# Заморозка — main.gd каждый кадр сам гонит настоящую физику
	# (player.physics_tick с реальным dt), и она тут же переписывает
	# выставленные руками on_ground/vy/thrust следующим же кадром (упавший
	# точно на границу тайла герой то и дело промахивался мимо коллизии и
	# заново проваливался — см. отчёт агента). frozen останавливает именно
	# физику (physics_tick рано выходит), а не отрисовку: character_view не
	# смотрит на frozen вовсе и рисует ровно то, что выставлено руками ниже.
	player.frozen = true

	await _shot("rig_jump_00_idle", player)

	# --- прыжок: толчок вверх, кадры втягивания бура 1..8 ---
	player.on_ground = false
	player.vy = -8.1   # JUMP_V
	await _shot("rig_jump_01_launch", player)

	for i in range(3):
		player.anim += 7.0   # ANIM_DIV в character_view.gd — один кадр анимации
		await _shot("rig_jump_0%d_retract" % (i + 2), player)

	player.anim += 7.0 * 4.0   # доиграть до последнего кадра (закрытый корпус)
	await _shot("rig_jump_05_closed_midair", player)

	# --- приземление: реверс той же анимации ---
	player.on_ground = true
	await _shot("rig_jump_06_land", player)
	for i in range(2):
		player.anim += 7.0
		await _shot("rig_jump_0%d_land" % (i + 7), player)

	# --- начало полёта: розжиг турбины ---
	player.on_ground = false
	player.vy = 0.0
	player.thrust = "prop"
	player.anim = 0.0
	await _shot("rig_fly_00_ignition_start", player)

	for i in range(3):
		player.anim += 7.0
		await _shot("rig_fly_0%d_ignition" % (i + 1), player)

	player.anim += 7.0 * 2.0   # в цикл полного хода турбины
	await _shot("rig_fly_04_full_thrust", player)

	print("test_screenshot_rig_jump_fly: готово, каталог -> " + _out_dir)
	get_tree().quit(0)


func _shot(name: String, player) -> void:
	# Кадр отрисовки должен успеть увидеть новое состояние player перед
	# захватом — один process_frame достаточно (character_view._process
	# читает player каждый кадр).
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join(name + ".png")
	img.save_png(path)
	print("  сохранено: " + path)

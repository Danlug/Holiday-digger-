extends Node
## test_screenshot_rig — не автотест, а разовый инструмент: запускает
## настоящую main-сцену, сажает героя в бурмобиль, копающий вниз, ждёт, пока
## анимация войдёт в фазу цикла (см. DIG_PHASES в character_view.gd), и
## сохраняет скриншот. Нужен реальный рендер (не --headless):
##
##   xvfb-run godot --path . res://tests/test_screenshot_rig.tscn --rendering-driver opengl3
##
## Путь для сохранения — первый аргумент после "--", по умолчанию
## /tmp/rig_down_screenshot.png.

var _frames := 0
var _out_path := "/tmp/rig_down_screenshot.png"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		_out_path = a

	# Интро (дед/внук, ГДД раздел 2) иначе закрывает весь экран текстом —
	# отмечаем как уже увиденное, чтобы сразу попасть в игру.
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")

	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var player = main.player
	var world = main.world

	# бурмобиль — требует владения; тест только про отрисовку
	GameState.current_tool = "drill_rig"

	var cell := Vector2i(-1, -1)
	for y in range(15, 60):
		for x in range(10, 30):
			if world.get_tile(x, y) == TileTypes.Type.DIRT \
					and world.get_tile(x, y + 1) == TileTypes.Type.DIRT:
				cell = Vector2i(x, y)
				break
		if cell.x >= 0:
			break
	if cell.x < 0:
		push_error("test_screenshot_rig: не нашлась клетка земли для копки")
		get_tree().quit(1)
		return

	player.x = float(cell.x) + 0.5
	player.y = float(cell.y) + 0.5
	player.vx = 0.0
	player.vy = 0.0
	player.on_ground = true
	player.hold_down = true

	# ждём, пока копка стартует и анимация дойдёт до цикла бурения
	# (старт — 3 кадра по ANIM_DIV=7, anim растёт на 2 за физтик — с запасом)
	for i in range(90):
		await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	var dir := _out_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(_out_path)
	print("test_screenshot_rig: сохранено -> " + _out_path)
	get_tree().quit(0)

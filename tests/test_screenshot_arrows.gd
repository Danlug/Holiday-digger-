extends Node
## test_screenshot_arrows — не автотест, а разовый инструмент: запускает
## настоящую main-сцену, переключает HUD в режим «стрелки» (третий режим по
## кругу кнопки «Управление») и сохраняет скриншот раскладки — слева ◀ ▶,
## справа ▲ ▼ (задача «раскладка стрелок», решение владельца). Нужен
## настоящий рендер (не --headless):
##
##   xvfb-run godot --path . res://tests/test_screenshot_arrows.tscn --rendering-driver opengl3
##
## Путь для сохранения — первый аргумент после "--", по умолчанию
## /tmp/arrows_screenshot.png.

var _out_path := "/tmp/arrows_screenshot.png"


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

	# Режимы по кругу: "stick" -> "hold" -> "arrows" (см. hud.gd:MODES).
	main.hud._set_mode("arrows")
	await get_tree().process_frame
	await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	var dir := _out_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(_out_path)
	print("test_screenshot_arrows: сохранено -> " + _out_path)
	get_tree().quit(0)

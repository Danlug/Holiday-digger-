extends Node
## Снимки заставки старта (SplashScreen): логотип и полоска, середина проявления, игра после.
## Не автотест — нужен настоящий рендер:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_splash.tscn --rendering-driver opengl3 --resolution 448x960 -- /каталог

var _out_dir := "/tmp/splash_shots"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		_out_dir = a
	DirAccess.make_dir_recursive_absolute(_out_dir)
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var splash := SplashScreen.attach(main, true)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("01_splash_start")
	await get_tree().create_timer(0.4).timeout
	await _shot("02_splash_bar")
	if splash != null:
		await get_tree().create_timer(maxf(0.0, splash.seconds_left() - SplashScreen.FADE * 0.5)).timeout
	await _shot("03_splash_fade_mid")
	await get_tree().create_timer(0.6).timeout
	await _shot("04_game")
	print("test_screenshot_splash: снимки -> " + _out_dir)
	get_tree().quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join(name + ".png"))

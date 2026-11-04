extends Node
## Снимки постановочных кадров стора (StoreShots: home, dig, shop, museum, combat) в 224x480 —
## посмотреть глазами, прежде чем снимать веб-сборку tools/store_screens.js. Не автотест:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_store.tscn --rendering-driver opengl3 --resolution 448x960 -- /каталог

var _out_dir := "/tmp/store_shots"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		_out_dir = a
	DirAccess.make_dir_recursive_absolute(_out_dir)
	GameState.world_seed = 20260101
	for sid in StoryData.scene_ids():
		StoryState.mark_seen(String(sid))
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var shots := StoreShots.attach(main, "home")
	for id in StoreShots.SHOTS:
		if shots.current != id:
			shots.show_shot(id)
		while shots.current != id or shots._busy:
			await get_tree().process_frame
		await get_tree().create_timer(0.9).timeout   # анимации окон и замах копки
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out_dir.path_join(id + ".png"))
	print("test_screenshot_store: снимки -> " + _out_dir)
	get_tree().quit(0)

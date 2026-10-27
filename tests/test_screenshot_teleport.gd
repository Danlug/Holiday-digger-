extends Node
## test_screenshot_teleport — не автотест, а инструмент глаз для часов-телепорта:
## площадка справа от тоннеля, огонёк возврата (несколько кадров анимации), пузырь
## «Вниз», шаги обучения на глубине 200 (затемнение + стрелка). Нужен настоящий рендер:
##
##   export XDG_DATA_HOME=$PWD/.godot/xdg
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_teleport.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [снимок ...]
##
## Снимки: yard (двор без возврата), glow (огонёк, 4 кадра), lesson (шаги а–в).

var _out_dir := "/tmp/teleport_shots"
var _only: Array[String] = []
var _main: Node2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	for i in range(1, args.size()):
		_only.append(args[i])
	DirAccess.make_dir_recursive_absolute(_out_dir)
	get_window().size = Vector2i(448, 960)
	Settings.hints_enabled = false
	StoryState.delete_from_disk()
	if FileAccess.file_exists(SaveSystem.SAVE_PATH):
		DirAccess.remove_absolute(SaveSystem.SAVE_PATH)
	GameState.reset_progress()
	GameState.world_seed = 4242
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure", "workshop", "death",
			"backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2", "grave_call",
			"first_artifact", "grandma_returns"]:
		StoryState.mark_seen(id)
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered"]:
		StoryState.set_flag(f)
	StoryData.ensure_loaded()
	for e in StoryData.depth_scenes():
		StoryState.mark_seen(String(e.id))
	GameState.house_hatch_built = true
	GameState.house_garden_closed = true
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(4)
	_main.world.build_robert_tunnel()
	var meta = _main.get_node_or_null("MetaService")
	if meta != null:
		meta.set_process(false)
		if meta.popup != null and meta.popup.is_open():
			meta.popup.close()
	GameState.game_clock_hours = 10.0

	if _want("yard"):
		await _shoot_yard()
	print("test_screenshot_teleport: снимки -> " + _out_dir)
	get_tree().quit(0)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(n + ".png"))
	print("  кадр " + n)


func _place(x: float, y: float) -> void:
	var p = _main.player
	p.x = x
	p.y = y
	p.vx = 0.0
	p.vy = 0.0


func _shoot_yard() -> void:
	_place(19.5, 0.5)
	await _frames(30)
	_shot("yard_19")
	_place(20.5, 0.5)
	await _frames(30)
	_shot("yard_20")

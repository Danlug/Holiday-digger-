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
var _tw: TeleportWatch


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

	_tw = TeleportWatch.find(get_tree())
	if _want("yard"):
		await _shoot_yard()
	if _want("glow"):
		await _shoot_glow()
	if _want("lesson"):
		await _shoot_lesson()
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


func _wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _spot(x: int, y: int) -> void:
	_main.world.dig_cell(x, y)
	_main.world.dig_cell(x, y - 1)


## Площадка без огонька: герой стоит на ней (возврата нет).
func _shoot_yard() -> void:
	TeleportWatch.clear_return()
	_place(TeleportWatch.pad_x(), 0.5)
	await _wait(1.0)
	_shot("yard_pad")


## Часы с глубины 150: герой на площадке, огонёк и пузырь «Вниз»; потом герой отходит
## к станции — огонёк без героя, 4 кадра анимации.
func _shoot_glow() -> void:
	_spot(24, 150)
	_place(24.5, 150.5)
	await _wait(0.6)
	TeleportWatch.use(_main.player)
	await _wait(1.2)
	_shot("glow_hero")
	_place(TeleportWatch.pad_x() + 2.2, 0.5)
	await _wait(1.0)
	for i in 4:
		_shot("glow_%d" % i)
		await _wait(0.55)
	TeleportWatch.clear_return()
	await _wait(0.5)
	_shot("glow_fading")
	await _wait(1.0)


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)
		await _frames(2)


## Обучение на 200: а) кнопка лавки, б) плитка часов, в) объяснение, г) после переноса.
func _shoot_lesson() -> void:
	GameState.dollars = 3
	GameState.dollars_changed.emit(3)
	_spot(23, 200)
	_place(23.5, 200.5)
	GameState.max_depth_reached = 200
	await _wait(0.8)
	var s := TeleportWatch.state()
	s["lesson"] = ""
	GameState.ext_set(TeleportWatch.KEY, s)
	_tw.lesson.begin()
	var guard := 0
	while not FocusTour.is_any_running() and guard < 600:
		guard += 1
		await _frames(1)
	await _wait(0.6)
	_shot("lesson_a_shop_button")
	var tour: FocusTour = _tw.lesson.tour
	var btn: Control = _main.hud.get("_shop_btn")
	await _click(btn.get_global_rect().get_center())
	await _wait(0.8)
	_shot("lesson_b_watch_tile")
	var tile := FocusTour._shop_tile("good:dollars:" + TeleportWatch.GOOD_ID)
	if tile != null:
		await _click(tile.get_global_rect().get_center())
	await _wait(0.6)
	_shot("lesson_c_card")
	var cb := tour.card_button() if is_instance_valid(tour) else null
	if cb != null:
		await _click(cb.get_global_rect().get_center())
	await _wait(1.2)
	_shot("lesson_d_after")

extends Node
## test_screenshot_fog — не автотест, а инструмент глаз (ветка fog-projects): плавное раскрытие
## тумана войны. Герой стоит в тоннеле на глубине, делает шаг на клетку вправо — новые клетки
## открываются; снимаем несколько кадров подряд: до шага, сразу после и по ходу проявления.
## Часы проявления ведёт тест (FogFade.manual_clock), поэтому кадры не зависят от скорости машины:
## сначала камера успевает доехать за героем, потом проявление идёт ступенями по 1/25 с.
## Нет узла FogFade (код до правки) — кадры просто идут подряд: видно прежнее раскрытие скачком.
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_fog.tscn --rendering-driver opengl3 --resolution 448x960 \
##       -- /каталог [глубина]

var _out_dir := "/tmp/fog_shots"
var _depth := 40
var _main: Node2D = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_depth = int(args[1])
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	GameState.world_seed = 4242
	for sid in StoryData.scene_ids():
		StoryState.mark_seen(String(sid))
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(3)
	var director = _main.get_node_or_null("StoryDirector")
	for _i in range(6):
		if director != null and director.cutscene != null and director.cutscene.is_playing:
			director.cutscene.skip()
		await _frames(10)
	Settings.reduce_motion = true
	MetaState.sub("daily")["last"] = MetaState.today()
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms) and ms.popup.is_open():
		ms.popup.close()
	_main.hud.set_gauges_visible(true)

	var world: WorldGen = _main.world
	var p = _main.player
	var cx := 10
	var cy := _depth
	# Тоннель в одну клетку высотой: герой стоит на полу, туман вокруг ещё не тронут.
	for x in range(cx - 1, cx + 6):
		world.dig_cell(x, cy)
	p.frozen = true
	p.x = float(cx) + 0.5
	p.y = float(cy) + 0.5
	p.vx = 0.0
	p.vy = 0.0
	GameState.player_depth = cy
	var fade = _main.world_view.get("fog_fade")
	if fade != null:
		fade.manual_clock = true
	await _frames(240)   # камера доезжает, реплики сюжета гаснут
	if fade != null:
		fade.advance(10.0)   # всё прежнее уже проявилось
	await _frames(4)
	await _shot("fog_0_before_step")

	p.x += 1.0
	await _shot("fog_1_step_frame1")
	if fade != null:
		print("test_screenshot_fog: проявляются клеток: ", fade.active_count(), ", длительность ", fade.duration, " с")
	await _frames(150)   # камера доезжает; при ручных часах проявление стоит на нуле
	await _shot("fog_2_camera_settled")
	var step := 0.04
	for i in range(1, 6):
		if fade != null:
			fade.advance(step)
		await _frames(1)
		await _shot("fog_3_t%03d" % int(round(i * step * 1000.0)))
	if fade != null:
		fade.advance(10.0)
	await _frames(2)
	await _shot("fog_4_done")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("test_screenshot_fog: ", path, " ", img.get_size())

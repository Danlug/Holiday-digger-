extends Node
## test_screenshot_sky — не автотест, а инструмент глаз: снимает небо настоящим рендером в нескольких
## моментах суток за один запуск (в run_tests.sh не входит). Нужен реальный рендер, не --headless:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" \
##       godot --path . res://tests/test_screenshot_sky.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог 18,19,20,22,1,5 [день=3] [высота_героя_в_клетках=0] [кадров_ожидания=8]
##
## Аргументы после "--": каталог, часы через запятую (дробные можно: 19.5), номера дней через запятую (фаза луны от дня),
## высота героя над землёй в клетках (0 — стоит на земле; подъём показывает параллакс звёзд), число кадров ожидания
## перед каждым снимком (чтобы поймать мерцание в разные моменты: одинаковые часы, большая пауза).
## Файлы: <каталог>/h<HH><MM>_d<день>.png

var _out_dir := "/tmp/sky_shots"
var _hours: Array = [12.0]
var _days: Array = [1]
var _lift := 0.0
var _dwell := 8


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_dir = args[0]
	if args.size() >= 2:
		_hours = []
		for s in args[1].split(","):
			_hours.append(s.to_float())
	if args.size() >= 3:
		_days = []
		for s in args[2].split(","):
			_days.append(s.to_int())
	if args.size() >= 4:
		_lift = args[3].to_float()
	if args.size() >= 5:
		_dwell = args[4].to_int()

	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	GameState.world_seed = 20260921

	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(_out_dir)
	var player = main.player
	player.x = float(WorldGen.GARDEN_X_MIN + WorldGen.WIDTH) / 2.0
	player.y = 0.5 - _lift
	player.vx = 0.0
	player.vy = 0.0
	player.on_ground = _lift <= 0.0

	for day in _days:
		for h in _hours:
			# Часы ставим напрямую (set_hour умеет только вперёд): (день-1)*24 + (час-6).
			GameState.game_clock_hours = float(day - 1) * 24.0 + (float(h) - 6.0)
			if GameState.game_clock_hours < 0.0:
				GameState.game_clock_hours += 24.0
			player.vx = 0.0
			player.vy = 0.0
			for i in range(_dwell):
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var hh := int(floor(h))
			var mm := int(round((h - floor(h)) * 60.0))
			var path := "%s/h%02d%02d_d%d.png" % [_out_dir, hh, mm, day]
			img.save_png(path)
			print("test_screenshot_sky: %s (час=%.2f день=%d)" % [path, DayCycle.hour, DayCycle.day])
	get_tree().quit(0)

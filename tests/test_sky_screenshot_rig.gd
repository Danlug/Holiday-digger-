extends Node
## test_sky_screenshot_rig — не автотест, а разовый инструмент (см.
## tests/test_screenshot_rig.gd — тот же приём): запускает настоящую
## main-сцену, ставит DayCycle на заданные час/день, ждёт кадр-другой и
## сохраняет скриншот. Нужен реальный рендер (не --headless):
##
##   xvfb-run godot --path . res://tests/test_sky_screenshot_rig.tscn \
##       --rendering-driver opengl3 -- /tmp/out.png 13.0 5
##
## Аргументы после "--": путь PNG, час (0-24, по умолчанию 13.0),
## день (по умолчанию 1, для облаков — сид облачности зависит от дня).

var _out_path := "/tmp/sky_screenshot.png"
var _hour := 13.0
var _day := 1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_path = args[0]
	if args.size() >= 2:
		_hour = args[1].to_float()
	if args.size() >= 3:
		_day = args[2].to_int()

	# Интро (дед/внук) иначе закрывает весь экран текстом — отмечаем как уже
	# увиденное, чтобы сразу попасть в игру (тот же приём, что в
	# test_screenshot_rig.gd).
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")

	# Фиксированный сид мира — воспроизводимые скриншоты между запусками:
	# world_seed иначе рандомизируется в main.gd:_ready() каждый раз
	# (GameState.ensure_world_seed()), и раскладка облаков (сид которой
	# мешает world_seed, см. clouds_view.gd) плавала бы от запуска к запуску.
	GameState.world_seed = 20260921

	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# День N: сдвигаем игровые часы вперёд на (N-1)*24 + до нужного часа —
	# set_hour() умеет только вперёд (см. day_cycle.gd), поэтому доводим
	# день явным приращением game_clock_hours.
	if _day > 1:
		GameState.game_clock_hours += float(_day - 1) * 24.0
	DayCycle.set_hour(_hour)

	var player = main.player
	# Подальше от дома (WorldGen.GARDEN_X_MIN..WIDTH) — иначе высокая крыша
	# дома закрывает почти всё небо на скриншоте.
	player.x = float(WorldGen.GARDEN_X_MIN + WorldGen.WIDTH) / 2.0
	player.y = 0.5
	player.vx = 0.0
	player.vy = 0.0
	player.on_ground = true

	# Несколько кадров: звёзды/облака читают DayCycle каждый кадр, а
	# CloudsView пересчитывает раскладку дня в update() (вызывается из
	# main.gd:_process) — один кадр может не успеть.
	for i in range(6):
		await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	var dir := _out_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(_out_path)
	var cov_str := ""
	if main.clouds_view != null:
		cov_str = " облачность=%.3f (%d облаков)" % [main.clouds_view.debug_coverage(),
			main.clouds_view.debug_cloud_count()]
	print("test_sky_screenshot_rig: сохранено -> " + _out_path
		+ " (час=%.2f, день=%d)" % [DayCycle.hour, DayCycle.day] + cov_str)
	get_tree().quit(0)

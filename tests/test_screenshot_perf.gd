extends Node
## Скриншоты слоя тайлов для сверки «до/после» оптимизаций рендера мира (ветка «perf»). Не автотест.
## Всё случайное и сторонее (небо, частицы, герой, интерфейс) спрятано, сид мира и такт лавы
## зафиксированы, камеру ведём руками: два прогона на разных версиях кода дают одинаковые пиксели,
## если рендер тайлов не изменился. Запуск:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" \
##       godot --path . res://tests/test_screenshot_perf.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /tmp/perf_shots [список]
##
## Список через запятую: d:5 — стоять на глубине 5; walk:300 — пройти с копкой и раскрытием тумана
## на ту же глубину (инкрементальный путь); surface — поверхность с декором огорода. По умолчанию —
## поверхность и глубины 5, 300, 1200, 3100, 6000, 9000 стоя и с проходом.

const SEED := 20260101

var _out_dir := "/tmp/perf_shots"
var _spec := "surface,d:5,d:300,d:1200,d:3100,d:6000,d:9000,walk:5,walk:300,walk:1200,walk:3100,walk:6000,walk:9000"
var _main: Node2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_spec = args[1]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	GameState.world_seed = SEED
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	RenderingServer.set_default_clear_color(Color.BLACK)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main.set_process(false)
	_hide_noise()
	var wv = _main.world_view
	if "lava_tick_override" in wv:
		wv.lava_tick_override = 0
	for item in _spec.split(","):
		var parts := item.split(":")
		var kind := parts[0]
		var depth := int(parts[1]) if parts.size() > 1 else 0
		await _shoot(kind, depth)
	get_tree().quit(0)


## Оставляем только тайлы, стену пояса и overlay мира: остальное меняется от запуска к запуску.
func _hide_noise() -> void:
	for c in _main.get_children():
		if c is CanvasLayer:
			c.visible = false
	for c in _main.view_root.get_children():
		if c.name != "WorldView" and c.name != "DeepBackdrop":
			c.visible = false


func _frame(cam_override: Variant = null) -> void:
	_main._reveal_around_player()
	var cam: Vector2 = _main._camera() if cam_override == null else cam_override
	_main.view_root.position = Vector2(-cam.x * 32.0, -cam.y * 32.0)
	_main.world_view.render(cam)
	_main.deep_backdrop.update(cam, _main._view_w(), _main._view_h())
	await get_tree().process_frame


func _place(x: float, y: float) -> void:
	var p = _main.player
	p.x = x
	p.y = y
	p.vx = 0.0
	p.vy = 0.0
	GameState.player_depth = int(y)


func _shoot(kind: String, depth: int) -> void:
	var world: WorldGen = _main.world
	var fog: FogOfWar = _main.fog
	var p = _main.player
	if kind == "surface":
		_place(22.5, 0.5)
		fog.reveal_around(p.x, p.y, 8, 6)
		for i in range(4):
			await _frame()
		_save("surface_0")
		return
	var cx := 20
	var cy := depth
	# карман 3x4 под героем и ниша справа
	for dx in range(-1, 2):
		for dy in range(0, 4):
			world.dig_cell(cx + dx, cy + dy)
	for dx in range(2, 4):
		world.dig_cell(cx + dx, cy + 3)
		world.dig_cell(cx + dx, cy + 2)
	_place(float(cx) + 0.5, float(cy) + 1.5)
	fog.reveal_around(p.x, p.y, 8, 6)
	for i in range(6):
		await _frame()
	if kind == "d":
		_save("d_%d" % depth)
		return
	# проход: 30 кадров по 0.12 клетки вправо и вниз, на пути копка клеток и раскрытие тумана
	for i in range(30):
		p.x += 0.1
		p.y += 0.07
		if i % 6 == 0:
			world.dig_cell(int(p.x) + 1, int(p.y))
			world.dig_cell(int(p.x), int(p.y) + 1)
		await _frame()
	# и назад вверх-влево, чтобы пройти все четыре направления прокрутки
	for i in range(20):
		p.x -= 0.2
		p.y -= 0.12
		await _frame()
	for i in range(3):
		await _frame()
	_save("walk_%d" % depth)


func _save(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, tag]
	img.save_png(path)
	print("снимок: ", path, " ", img.get_size())

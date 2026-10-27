extends Node
## Скриншоты артефактов в породе (ArtifactLayer): предмет в полном обзоре, силуэт в
## сером тумане, несколько веток. Не автотест. Запуск (сохранение — во временный
## каталог данных, иначе перезапишется настоящий сейв):
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" \
##       godot --path . res://tests/test_screenshot_artifacts.tscn \
##       --rendering-driver opengl3 --resolution 448x960 -- /tmp/artifact_shots
##
## На Windows — то же без xvfb-run, с APPDATA на временный каталог.

const SEED := 4242

var _out_dir := "/tmp/artifact_shots"
var main: Node2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)

	GameState.world_seed = SEED
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	StoryState.set_flag("food_ordered", true)
	Settings.hints_enabled = false
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	GameState.current_tool = "iron_pickaxe"
	await _view("antiquity_2", "artifact_antiquity_full", 4, 3)
	await _view("mysticism_1", "artifact_mysticism_full", 4, 3)
	await _view("occult_2", "artifact_occult_gray", 4, 1)
	await _view("forgotten_civilizations_1", "artifact_forgotten_full", 4, 3)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("снимок: ", path, " ", img.get_size())


## Герой в выкопанном кармане в двух клетках слева от артефакта; обзор рельефа
## terrain, ресурсов resource (resource < 2 — предмет остаётся в сером тумане).
func _view(id: String, name: String, terrain: int, resource: int) -> void:
	var world: WorldGen = main.world
	var player = main.player
	var cell := ArtifactSpawn.cell_of(Balance.get_artifact(id), SEED, world)
	var side := 1 if cell.x < 16 else -1
	for dx in range(1, 4):
		for dy in range(-2, 1):
			world.dig_cell(cell.x + side * dx, cell.y + dy)
	player.x = float(cell.x + side * 2) + 0.5
	player.y = float(cell.y) + 0.5
	player.vx = 0.0
	player.vy = 0.0
	player.release_control()
	GameState.player_depth = cell.y
	main.fog.reveal_around(player.x, player.y, terrain, resource)
	print("артефакт ", id, " в клетке ", cell)
	await _frames(24)
	await _shot(name)
	# крупный план ×2 (к экранным пикселям): три клетки вокруг предмета, без сглаживания — видно пиксели
	var img := get_viewport().get_texture().get_image()
	var vr: Node2D = main.view_root
	var at: Vector2 = get_viewport().get_final_transform() * (vr.get_global_transform_with_canvas() * (Vector2(cell.x - 1, cell.y - 1) * 32.0))
	var px := int(round(96.0 * vr.get_global_transform_with_canvas().get_scale().x * get_viewport().get_final_transform().get_scale().x))
	var r := Rect2i(Vector2i(at.round()), Vector2i(px, px)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	crop.resize(r.size.x * 2, r.size.y * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s_zoom.png" % [_out_dir, name])

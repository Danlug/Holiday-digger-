extends Node
## Кадры падения в жадности (владелец 27.10): шахта в 20 клеток, жадность включена —
## каждые 3 клетки герой на миг «зацепляется» (облачко и искра у ног). Не автотест.
## Шаг игры ручной (1/60 с на кадр), поэтому кадры не зависят от скорости машины.
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" \
##       godot --path . res://tests/test_screenshot_greed_fall.tscn \
##       --rendering-driver opengl3 --resolution 448x960 -- /каталог
##
## В каталоге: f_000.png… (вырез 240×300 вокруг героя, каждый кадр) и log.txt (кадр, y, vy, висит).

const SEED := 4242
const DT := 1.0 / 60.0
const FRAMES := 130

var _out_dir := "/tmp/greed_fall"
var main: Node2D
var d: MechDirector


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
	d = main.get_node("MechDirector")
	GameState.current_tool = "iron_pickaxe"
	await _fall()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Столбец сплошной породы под шахту: 21 клетка сверху вниз и пол под ней.
func _column(y0: int, n: int) -> int:
	var w: WorldGen = main.world
	for x in range(20, 30):
		var ok := true
		for y in range(y0 - 2, y0 + n + 1):
			for xx in [x - 1, x, x + 1]:
				if w.get_tile(xx, y) == TileTypes.Type.EMPTY or not TileTypes.is_diggable(w.get_tile(xx, y)):
					ok = false
		if ok:
			return x
	return 24


func _fall() -> void:
	var y0 := 60
	var n := 21
	var x := _column(y0, n)
	var w: WorldGen = main.world
	for y in range(y0, y0 + n):
		w.dig_cell(x, y)
	var p = main.player
	p.release_control()
	p.x = float(x) + 0.5
	p.y = float(y0) + 0.6
	p.vx = 0.0
	p.vy = 0.0
	p.on_ground = false
	GameState.player_depth = y0
	for y in range(y0 - 2, y0 + n + 3, 2):
		main.fog.reveal_around(p.x, float(y), 4, 3)
	main.set_process(false)
	d.set_process(false)
	# жадность: шкала полна, клетка — режим включён (как в test_screenshot_mechanics)
	d.streak.reset()
	d.on_dug({"cell": Vector2i(x, y0), "mineral": "", "loot": false})
	d.streak.work = d.streak.fever_s
	d.on_dug({"cell": Vector2i(x, y0), "mineral": "", "loot": false})
	var log := FileAccess.open(_out_dir + "/log.txt", FileAccess.WRITE)
	for i in FRAMES:
		d.step(DT)
		if i < 2:
			p.y = float(y0) + 0.6   # пока камера встаёт на место — держим у верха шахты
			p.vy = 0.0
		main._process(DT)
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		# вырез 240×300 вокруг героя (в пикселях окна: проект 224×480 растянут)
		var k := float(img.get_width()) / 224.0
		var vr: Node2D = main.view_root
		var at: Vector2 = (vr.position + Vector2(p.x, p.y) * 32.0 * vr.scale) * k
		var r := Rect2i(int(at.x) - 120, int(at.y) - 170, 240, 300)
		r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(r).save_png("%s/f_%03d.png" % [_out_dir, i])
		log.store_line("%d y=%.2f vy=%.2f hang=%s greed=%s ground=%s" % [
			i, p.y - float(y0), p.vy, str(p._greed_hang_left > 0.0), str(d.streak.in_greed()), str(p.on_ground)])
	log.close()
	main.set_process(true)
	d.set_process(true)
	print("кадры: ", _out_dir)

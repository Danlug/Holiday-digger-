extends Node
## test_screenshot_poses — не автотест, а витрина «все позы в ряд» (зона
## boy-scale): каждый лист героя и актёров сцен рисуется тем же кодом, что в
## игре (CharacterView.pose_override / WorldActor.set_pose), на одной линии
## земли, с клеткой под ногами — чтобы глазами увидеть, прыгает ли мальчик и
## меняет ли размер при смене позы. Нужен настоящий рендер:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_poses.tscn --rendering-driver opengl3 -- /каталог
##
## Снимок poses.png (увеличение ×3): ряд 1 — герой, опорный кадр, лицом вправо;
## ряд 2 — то же влево; ряд 3 — герой, кадр 3 каждого листа (середина
## анимации); ряд 4 — актёры сцен (boy, boy_gear, дед, бабушки, Роберт).

const ZOOM := 3.0
const STEP := 64.0           # логических px между позами
const ROW_H := 100.0
const GROUND_ROWS := [78.0, 178.0, 278.0, 378.0]   # y линии земли каждого ряда (лог. px)
const HERO_POSES := ["idle", "walk", "fall", "fly", "fly_jet", "fly_1", "fly_2", "fly_3", "fly_4",
		"dig_shovel", "dig_pick", "dig_pick_rusty", "dig_drill_down", "dig_drill_side", "sleep",
		"dig_rig_down", "dig_rig_side", "rig_jump", "rig_fly", "rig_exit", "rig_exit:4", "rig_exit:6"]
const ACTOR_POSES := [["boy", "idle"], ["boy", "walk"], ["boy", "dig_pick_rusty"], ["boy", "fall"], ["boy", "sleep"],
		["boy_gear", "idle"], ["boy_gear", "walk"], ["boy_gear", "dig_pick"], ["boy_gear", "dig_shovel"],
		["boy_gear", "fly"], ["boy_gear", "fly_jet"], ["boy_gear", "fall"],
		["grandpa", "idle"], ["grandpa", "walk"], ["grandpa", "dig_shovel"], ["grandpa_gear", "idle"],
		["grandma_poor", "idle"], ["grandma_poor", "walk"], ["grandma_rich", "idle"], ["robert", "idle"]]

var _out_dir := "/tmp/poses_shots"
var _sub: SubViewport
var _root: Node2D


class PoseStub extends Node:
	var x := 0.0
	var y := 0.0
	var facing := 1
	var stun_until_msec := 0.0


class Labels extends Node2D:
	var items: Array = []   # [pos, text]
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for it in items:
			draw_string(font, it[0], it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 0.9, 0.5))


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)

	var width: float = STEP * (HERO_POSES.size() + 1)
	_sub = SubViewport.new()
	_sub.size = Vector2i(int(width * ZOOM), int(ROW_H * 4 * ZOOM))
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.transparent_bg = false
	add_child(_sub)
	_root = Node2D.new()
	_root.scale = Vector2(ZOOM, ZOOM)
	_sub.add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.17, 0.2)
	bg.size = Vector2(width, ROW_H * 4)
	_root.add_child(bg)
	var labels := Labels.new()

	for row in 3:
		var ground: float = GROUND_ROWS[row]
		for i in HERO_POSES.size():
			var spec: String = HERO_POSES[i]
			var pose := spec.get_slice(":", 0)
			var g := PoseAnchor.geom(pose)
			var frame: int = int(spec.get_slice(":", 1)) if spec.contains(":") else int(g.get("ref_frame", 0))
			if row == 2:
				frame = 3
			var cx: float = STEP * 0.5 + STEP * i + 16.0
			_cell(cx, ground)
			var stub := PoseStub.new()
			stub.x = cx / 32.0
			stub.y = (ground - 16.0) / 32.0
			stub.facing = -1 if row == 1 else 1
			_root.add_child(stub)
			var view: Node2D = load("res://scripts/player/character_view.gd").new()
			view.player = stub
			_root.add_child(view)
			view.set_pose_override(pose, frame)
			labels.items.append([Vector2(cx - 16.0, ground + 10.0), "%s %d" % [pose.trim_prefix("dig_"), frame]])

	var ground4: float = GROUND_ROWS[3]
	for i in ACTOR_POSES.size():
		var dir: String = ACTOR_POSES[i][0]
		var pose: String = ACTOR_POSES[i][1]
		var cx: float = STEP * 0.5 + STEP * i + 16.0
		_cell(cx, ground4)
		var a := WorldActor.new()
		a.setup(dir)
		a.x = cx / 32.0
		a.y = (ground4 - 16.0) / 32.0
		_root.add_child(a)
		a.set_pose(pose, false)
		a.anim = float(int(PoseAnchor.geom(pose, dir).get("ref_frame", 0))) * a.ANIM_DIV
		labels.items.append([Vector2(cx - 16.0, ground4 + 10.0), "%s/%s" % [dir, pose.trim_prefix("dig_")]])
	_root.add_child(labels)

	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _sub.get_texture().get_image()
	var path := _out_dir.path_join("poses.png")
	img.save_png(path)
	print("снимок: ", path, " ", img.get_size())
	get_tree().quit(0)


## Клетка под ногами: столбец земли ниже линии и рамка клетки 32×32 над ней.
func _cell(cx: float, ground: float) -> void:
	var soil := ColorRect.new()
	soil.color = Color(0.36, 0.25, 0.16)
	soil.position = Vector2(cx - 16.0, ground)
	soil.size = Vector2(32.0, 8.0)
	_root.add_child(soil)
	var line := ColorRect.new()
	line.color = Color(1.0, 0.3, 0.3)
	line.position = Vector2(cx - 30.0, ground - 0.5)
	line.size = Vector2(60.0, 0.5)
	_root.add_child(line)
	var frame := ReferenceRect.new()
	frame.editor_only = false
	frame.border_color = Color(0.5, 0.55, 0.65, 0.6)
	frame.position = Vector2(cx - 16.0, ground - 32.0)
	frame.size = Vector2(32.0, 32.0)
	_root.add_child(frame)

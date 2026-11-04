extends Node
## test_boy_scale — одна высота тела и одна точка опоры у мальчика во всех
## позах (зона boy-scale, бриф 6): метаданные art/character/poses.json против
## пикселей листов и против того, куда их кладут рисовальщики.
##
##   1. у каждого листа героя и актёров сцен есть геометрия: ширина листа кратна
##      кадру (или лист — одиночная поза), высота кадра не больше высоты листа;
##   2. по пикселям опорного кадра: подошва (нижний непрозрачный пиксель в
##      полосе ±7 лог. px вокруг оси тела) лежит на ground_y−1 (±sole_tol);
##      макушка (верхний непрозрачный в полосе ±4 лог. px) даёт рост
##      ground_y−макушка = body_h_std±body_tol либо заявленный body_h±2;
##   3. CharacterView кладёт линию земли каждой позы на низ хитбокса героя
##      (стоя — низ клетки), а ось тела — на x героя, при обоих разворотах;
##   4. WorldActor — ступни на низу клетки у всех актёров и поз при росте 1.0 и 0.92;
##   5. классическая сцена режет широкие листы копки мальчика на 8 кадров по
##      192, а не показывает полосу целиком (регресс dud_treasure/workshop),
##      и ставит квадратные листы ровно туда же, где они стояли;
##   6. rig_exit.json и poses.json согласны о кадре и линии земли бурмобиля.
##
## Запуск: godot --headless --path . res://tests/test_boy_scale.tscn

const ALPHA_MIN := 40
const SOLE_HALF := 21
const CROWN_HALF := 12
const ACTOR_DIRS := ["boy", "boy_gear", "grandpa", "grandpa_gear", "grandma_poor", "grandma_rich", "robert"]
const SKIP_FILES := ["portrait"]

var failures := 0
var total := 0


class PoseStub extends Node:
	var x := 0.0
	var y := 0.0
	var facing := 1
	var stun_until_msec := 0.0


func _ready() -> void:
	print("=== test_boy_scale ===")
	await get_tree().process_frame
	_test_meta_covers_sheets()
	_test_pixels()
	_test_hero_view_alignment()
	_test_world_actor_alignment()
	_test_classic_cutscene()
	_test_rig_exit_meta()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", label,
		("  " + detail) if not ok and not detail.is_empty() else ""])


## Все листы: [{dir, pose, path}] — герой (art/character/*.png) и актёры сцен.
func _sheets() -> Array:
	var out: Array = []
	for dir: String in [""] + ACTOR_DIRS:
		var folder: String = "res://art/character" + ("/" + dir if not dir.is_empty() else "")
		var da := DirAccess.open(folder)
		if da == null:
			continue
		for f in da.get_files():
			if not f.ends_with(".png") or SKIP_FILES.has(f.get_basename()):
				continue
			out.append({"dir": dir, "pose": f.get_basename(), "path": folder + "/" + f})
	return out


func _image(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


func _test_meta_covers_sheets() -> void:
	check("poses.json прочитан", not PoseAnchor.doc().is_empty())
	var sheets := _sheets()
	check("листы найдены (герой + актёры)", sheets.size() > 40, str(sheets.size()))
	for sh in sheets:
		var img := _image(sh.path)
		if img == null:
			check("%s/%s: лист читается" % [sh.dir, sh.pose], false)
			continue
		var g := PoseAnchor.geom(sh.pose, sh.dir)
		var fw: int = g.frame_w
		var ok_w: bool = img.get_width() % fw == 0 or img.get_width() == fw
		check("%s/%s: ширина листа %d кратна кадру %d" % [sh.dir, sh.pose, img.get_width(), fw], ok_w)
		check("%s/%s: кадр %d не выше листа %d" % [sh.dir, sh.pose, g.frame_h, img.get_height()],
			g.frame_h <= img.get_height())
		check("%s/%s: земля %d внутри кадра" % [sh.dir, sh.pose, g.ground_y],
			g.ground_y > 0 and g.ground_y <= g.frame_h)


## Нижний непрозрачный ряд в полосе колонок [x0, x1] кадра (или -1).
func _lowest(img: Image, fx: int, x0: int, x1: int, fh: int) -> int:
	for y in range(fh - 1, -1, -1):
		for x in range(maxi(0, x0), mini(x1 + 1, img.get_width() - fx)):
			if img.get_pixel(fx + x, y).a8 > ALPHA_MIN:
				return y
	return -1


func _highest(img: Image, fx: int, x0: int, x1: int, fh: int) -> int:
	for y in range(fh):
		for x in range(maxi(0, x0), mini(x1 + 1, img.get_width() - fx)):
			if img.get_pixel(fx + x, y).a8 > ALPHA_MIN:
				return y
	return -1


func _test_pixels() -> void:
	var doc := PoseAnchor.doc()
	var body_std: int = int(doc.get("body_h_std", 121))
	var body_tol: int = int(doc.get("body_tol", 4))
	for sh in _sheets():
		var img := _image(sh.path)
		if img == null:
			continue
		var g := PoseAnchor.geom(sh.pose, sh.dir)
		var fw: int = g.frame_w
		var fh: int = mini(g.frame_h, img.get_height())
		var frames: int = maxi(1, img.get_width() / fw) if img.get_width() % fw == 0 else 1
		var ref: int = clampi(int(g.get("ref_frame", 0)), 0, frames - 1)
		var fx: int = ref * fw
		var axis: int = g.axis_x
		var label := "%s/%s" % [sh.dir if not sh.dir.is_empty() else "герой", sh.pose]
		if bool(g.get("sole_check", true)):
			var sole := _lowest(img, fx, axis - SOLE_HALF, axis + SOLE_HALF, fh)
			var tol: int = int(g.get("sole_tol", 1))
			check("%s: подошва кадра %d на линии земли (%d, допуск %d)" % [label, ref, g.ground_y - 1, tol],
				sole >= 0 and absi(sole - (g.ground_y - 1)) <= tol, "подошва %d" % sole)
		if bool(g.get("crown_check", true)):
			var crown := _highest(img, fx, axis - CROWN_HALF, axis + CROWN_HALF, fh)
			var body: int = g.ground_y - crown
			if g.has("body_h"):
				check("%s: рост тела %d = заявленный %d (±2, поза)" % [label, body, int(g.body_h)],
					crown >= 0 and absi(body - int(g.body_h)) <= 2)
			else:
				check("%s: рост тела %d = эталон %d (±%d)" % [label, body, body_std, body_tol],
					crown >= 0 and absi(body - body_std) <= body_tol)


func _test_hero_view_alignment() -> void:
	var stub := PoseStub.new()
	add_child(stub)
	var view: Node2D = load("res://scripts/player/character_view.gd").new()
	view.player = stub
	add_child(view)
	var spr: Sprite2D = view._sprite
	var poses: Array = PoseAnchor.doc().get("poses", {}).keys()
	check("в poses.json есть позы героя", poses.size() >= 20, str(poses.size()))
	for facing in [1, -1]:
		stub.facing = facing
		for pose: String in poses:
			var g := PoseAnchor.geom(pose)
			view.set_pose_override(pose, int(g.get("ref_frame", 0)))
			view._process(0.0)
			var label := "герой %s (%s)" % [pose, "вправо" if facing > 0 else "влево"]
			check("%s: лист загружен" % label, spr.texture != null)
			if spr.texture == null:
				continue
			check("%s: кадр %dx%d" % [label, g.frame_w, g.frame_h],
				spr.region_rect.size == Vector2(g.frame_w, g.frame_h), str(spr.region_rect))
			var feet: float = spr.position.y + float(g.ground_y) / PoseAnchor.ART_SCALE
			check("%s: ступни на низу хитбокса героя (%.2f)" % [label, PoseAnchor.FEET_Y_HERO],
				is_equal_approx(feet, PoseAnchor.FEET_Y_HERO), "%.2f" % feet)
			var axis: float = float(g.axis_x if facing > 0 else g.frame_w - g.axis_x)
			var body_x: float = spr.position.x + axis / PoseAnchor.ART_SCALE
			check("%s: ось тела на x героя" % label, absf(body_x) < 0.01, "%.2f" % body_x)
	# Override не снимаем до освобождения: обычная ветка _process читает у
	# героя rig_transition и прочее, чего у заглушки нет.
	view.set_process(false)
	view.queue_free()
	stub.queue_free()


func _test_world_actor_alignment() -> void:
	for sh in _sheets():
		if sh.dir.is_empty() or sh.pose.begins_with("age_"):
			continue
		var a := WorldActor.new()
		a.setup(sh.dir)
		a.x = 10.5
		a.y = 0.5
		add_child(a)
		for flip in [false, true]:
			check("%s/%s: поза загружена" % [sh.dir, sh.pose], a.set_pose(sh.pose, flip))
			a._process(0.0)
			var spr: Sprite2D = a.get_child(0)
			var g := PoseAnchor.geom(sh.pose, sh.dir)
			var s: float = a.height_k / PoseAnchor.ART_SCALE
			var feet: float = spr.position.y + float(g.ground_y) * s
			check("%s/%s%s: ступни на низу клетки актёра (рост %.2f)" % [sh.dir, sh.pose, " ↔" if flip else "", a.height_k],
				is_equal_approx(feet, PoseAnchor.FEET_Y_ACTOR), "%.2f против %.2f" % [feet, PoseAnchor.FEET_Y_ACTOR])
			var axis: float = float(g.frame_w - g.axis_x if flip else g.axis_x)
			check("%s/%s%s: ось тела на x актёра" % [sh.dir, sh.pose, " ↔" if flip else ""],
				absf(spr.position.x + axis * s) < 0.01)
			var frames_expected: int = PoseAnchor.frames(spr.texture, sh.pose, sh.dir)
			check("%s/%s: кадров %d" % [sh.dir, sh.pose, frames_expected], a._frames == frames_expected)
		a.queue_free()


func _test_classic_cutscene() -> void:
	var cs := CutscenePlayer.new()
	add_child(cs)
	cs._show_actor({"actor": "boy", "pose": "dig_shovel", "at": "center"})
	check("классика: boy dig_shovel — 8 кадров по 192, не полоса",
		cs._actors.has("boy") and int(cs._actors["boy"].frames) == 8
		and is_equal_approx(float(cs._actors["boy"].frame_w), 192.0),
		str(cs._actors.get("boy", {})))
	cs._show_actor({"actor": "boy", "pose": "dig_pick_rusty", "at": "center"})
	check("классика: boy dig_pick_rusty — 8 кадров по 192",
		int(cs._actors["boy"].frames) == 8 and is_equal_approx(float(cs._actors["boy"].frame_w), 192.0))
	cs._show_actor({"actor": "grandpa", "pose": "dig_shovel", "at": "left"})
	check("классика: grandpa dig_shovel — 6 кадров по 144",
		int(cs._actors["grandpa"].frames) == 6 and is_equal_approx(float(cs._actors["grandpa"].frame_w), 144.0))
	# Квадратный лист стоит там же, где и раньше: низ кадра 144 на низу стойки.
	cs._show_actor({"actor": "boy", "pose": "idle", "at": "center"})
	var a: Dictionary = cs._actors["boy"]
	var node: TextureRect = a.node
	var h: float = a.tex_h * a.scale / cs.ART_SCALE
	check("классика: idle — низ кадра на низу стойки (как было)",
		is_equal_approx(node.position.y, cs._stage.size.y - h), "%.2f против %.2f" % [node.position.y, cs._stage.size.y - h])
	# Широкий лист копки — ступни на той же линии, что у стойки.
	cs._show_actor({"actor": "boy", "pose": "dig_shovel", "at": "center"})
	var b: Dictionary = cs._actors["boy"]
	var feet_dig: float = b.node.position.y + float(b.ground_y) * b.scale / cs.ART_SCALE
	var feet_idle: float = cs._stage.size.y - h + 138.0 * a.scale / cs.ART_SCALE
	check("классика: ступни в копке на линии ступней стойки", is_equal_approx(feet_dig, feet_idle),
		"%.2f против %.2f" % [feet_dig, feet_idle])
	cs.queue_free()


func _test_rig_exit_meta() -> void:
	var f := FileAccess.open("res://art/character/rig_exit.json", FileAccess.READ)
	check("rig_exit.json читается", f != null)
	if f == null:
		return
	var meta = JSON.parse_string(f.get_as_text())
	var g := PoseAnchor.geom("rig_exit")
	check("rig_exit: линия земли в rig_exit.json и poses.json одна", int(meta.get("ground_y", -1)) == g.ground_y)
	check("rig_exit: кадр в rig_exit.json и poses.json один",
		int(meta.get("frame_w", -1)) == g.frame_w and int(meta.get("frame_h", -1)) == g.frame_h)
	check("rig_exit и бурмобиль: одна линия земли", g.ground_y == PoseAnchor.geom("dig_rig_side").ground_y)

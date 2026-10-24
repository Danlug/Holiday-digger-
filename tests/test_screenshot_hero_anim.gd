extends Node
## test_screenshot_hero_anim — не автотест, а «плёнка» героя: поднимает main.tscn,
## гоняет героя по сценариям с ФИКСИРОВАННЫМ шагом времени (1/60 с, физика и
## отрисовка вызываются руками, не от кадров движка — лента воспроизводима) и
## сохраняет вырезки вокруг героя на каждом N-м шаге. Склейка в ленты и подписи —
## tools/film_strip.py. Нужен настоящий рендер:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_hero_anim.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [сценарий ...]
##
## Сценарии: idle walk jump leap fall dig_down dig_side shovel fly_prop fly_jet
## hurt die sleep turn. Без имён — все. Состояние только в памяти (user:// не пишем).

const DT := 1.0 / 60.0
const CROP := 72.0         # сторона вырезки в логических точках

var _out := "/tmp/hero_film"
var _only: Array[String] = []
var main: Node2D
var player
var view
var _n := 0
var _prefix := ""
var _every := 3


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	for i in range(1, args.size()):
		_only.append(args[i])
	if not DirAccess.dir_exists_absolute(_out):
		DirAccess.make_dir_recursive_absolute(_out)

	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	StoryState.flags()["bars_introduced"] = true
	GameState.debug_invincible = true

	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	player = main.player
	view = main.find_child("CharacterView", true, false)
	main.set_process(false)
	view.set_process(false)

	if _want("idle"): await _sc_idle()
	if _want("walk"): await _sc_walk()
	if _want("turn"): await _sc_turn()
	if _want("jump"): await _sc_jump(0)
	if _want("leap"): await _sc_jump(1)
	if _want("fall"): await _sc_fall()
	if _want("dig_down"): await _sc_dig("dig_down", "pickaxe", false)
	if _want("dig_side"): await _sc_dig("dig_side", "pickaxe", true)
	if _want("shovel"): await _sc_dig("shovel", "shovel", true)
	if _want("fly_prop"): await _sc_fly("fly_prop", "backpack")
	if _want("fly_jet"): await _sc_fly("fly_jet", "jetpack_top")
	if _want("hurt"): await _sc_hurt()
	if _want("die"): await _sc_die()
	if _want("sleep"): await _sc_sleep()
	print("test_screenshot_hero_anim: готово -> " + _out)
	get_tree().quit(0)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


# ---------------------------------------------------------------------------
# Инфраструктура
# ---------------------------------------------------------------------------

func _begin(prefix: String, every: int = 3) -> void:
	_set_flat(not (prefix.begins_with("dig") or prefix == "shovel"))
	_prefix = prefix
	_every = every
	_n = 0
	GameState.is_alive = true
	GameState.hp = GameState.max_hp if "max_hp" in GameState else GameState.hp
	GameState.current_gear = ""
	GameState.current_tool = "pickaxe"
	player.frozen = false
	player.digging = null
	player.stun_until_msec = 0.0
	player.thrust = ""
	player.release_control()
	view._reset_motion() if view.has_method("_reset_motion") else null


## Плоский фон: прячем мир, небо и HUD, чтобы на ленте был только герой и линия земли.
func _set_flat(flat: bool) -> void:
	RenderingServer.set_default_clear_color(Color(0.2, 0.22, 0.27) if flat else Color(0, 0, 0))
	for c in main.get_children():
		if c == main.view_root:
			continue
		if c is CanvasItem or c is CanvasLayer:
			c.visible = not flat
	for c in main.view_root.get_children():
		if c == view or c.name == "GroundLine":
			continue
		if c is CanvasItem:
			c.visible = not flat
	var gl = main.view_root.get_node_or_null("GroundLine")
	if gl == null:
		gl = ColorRect.new()
		gl.name = "GroundLine"
		gl.color = Color(0.55, 0.6, 0.7, 0.6)
		gl.size = Vector2(4000, 1)
		gl.position = Vector2(0, 31)
		gl.z_index = -1
		main.view_root.add_child(gl)
	gl.visible = flat


func _stand_at(x: float, y: float, face: int = 1) -> void:
	player.x = x
	player.y = y
	player.vx = 0.0
	player.vy = 0.0
	player.facing = face
	player.on_ground = true


## Выкопать норку: герой стоит в клетке (cx, cy), справа и снизу — порода.
func _pit(cx: int, cy: int) -> void:
	var w = main.world
	for dy in range(-2, 1):
		w.dig_cell(cx, cy + dy)
	for dy in range(-2, 1):
		w.dig_cell(cx - 1, cy + dy)


## Один шаг мира. capture — снять вырезку после шага.
func _step(capture: bool) -> void:
	player.physics_tick(DT)
	view._process(DT)
	var cam: Vector2 = main._camera()
	main.view_root.position = Vector2(-cam.x * 32.0, -cam.y * 32.0)
	main.world_view.render(cam)
	if capture:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_grab()


func _run(seconds: float, label_each: int = -1) -> void:
	var steps := int(round(seconds / DT))
	for i in range(steps):
		var cap: bool = (_n_steps % _every) == 0
		_n_steps += 1
		await _step(cap)


var _n_steps := 0


func _grab() -> void:
	var img := get_viewport().get_texture().get_image()
	var sc: float = float(img.get_width()) / 224.0
	var origin: Vector2 = view.get_global_transform_with_canvas().origin
	var half := CROP * 0.5 * sc
	var cx := origin.x * sc
	var cy := (origin.y + 4.0) * sc
	var r := Rect2i(int(cx - half), int(cy - half), int(CROP * sc), int(CROP * sc))
	r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var crop := img.get_region(r)
	crop.save_png("%s/%s_%03d.png" % [_out, _prefix, _n])
	_n += 1


func _sc(prefix: String, every: int = 3) -> void:
	_n_steps = 0
	_begin(prefix, every)


# ---------------------------------------------------------------------------
# Сценарии
# ---------------------------------------------------------------------------

func _sc_idle() -> void:
	_sc("idle", 12)
	_stand_at(20.5, 0.5)
	await _run(0.5)
	await _run(8.0)


func _sc_walk() -> void:
	_sc("walk", 3)
	_stand_at(20.5, 0.5)
	await _run(0.3)
	player.set_intent(1, false, false)
	await _run(1.4)
	player.release_control()
	await _run(0.6)


func _sc_turn() -> void:
	_sc("turn", 2)
	_stand_at(20.5, 0.5)
	await _run(0.2)
	player.set_intent(1, false, false)
	await _run(0.6)
	player.set_intent(-1, false, false)
	await _run(0.6)
	player.release_control()
	await _run(0.4)


func _sc_jump(horizontal: int) -> void:
	_sc("jump" if horizontal == 0 else "leap", 2)
	_stand_at(20.5, 0.5)
	await _run(0.3)
	player.set_intent(horizontal, true, false)
	await _run(0.05)
	player.set_intent(horizontal, false, false) if horizontal != 0 else player.release_control()
	await _run(1.3)
	player.release_control()
	await _run(0.5)


func _sc_fall() -> void:
	_sc("fall", 2)
	_stand_at(20.5, -5.5)
	player.on_ground = false
	await _run(1.4)
	await _run(0.5)


func _sc_dig(prefix: String, tool_id: String, side: bool) -> void:
	_sc(prefix, 3)
	var cx := 22
	var cy := 9
	_pit(cx, cy)
	GameState.current_tool = tool_id
	_stand_at(float(cx) + 0.5, float(cy) + 0.5)
	if side:
		player.x = float(cx + 1) - 0.38 - 0.01
	player.on_ground = true
	await _run(0.3)
	if side:
		player.set_intent(1, false, false)
	else:
		player.set_intent(0, false, true)
	await _run(3.4)
	player.release_control()
	await _run(0.5)


func _sc_fly(prefix: String, gear: String) -> void:
	_sc(prefix, 3)
	GameState.current_gear = gear
	_stand_at(20.5, 0.5)
	await _run(0.3)
	player.set_intent(0, true, false)
	await _run(1.4)
	player.set_intent(1, true, false)
	await _run(0.8)
	player.release_control()
	await _run(0.9)


func _sc_hurt() -> void:
	_sc("hurt", 2)
	_stand_at(20.5, 0.5)
	await _run(0.3)
	if view.has_method("on_hurt"):
		view.on_hurt(10.0, -1)
	player.stun_until_msec = float(Time.get_ticks_msec()) + 600.0
	await _run(1.0)


func _sc_die() -> void:
	_sc("die", 3)
	_stand_at(20.5, 0.5)
	await _run(0.3)
	GameState.is_alive = false
	player.frozen = true
	if view.has_method("on_died"):
		view.on_died()
	await _run(1.6)


func _sc_sleep() -> void:
	_sc("sleep", 6)
	_stand_at(20.5, 0.5)
	if view.has_method("set_sleeping"):
		view.set_sleeping(true)
	await _run(3.0)
	if view.has_method("set_sleeping"):
		view.set_sleeping(false)

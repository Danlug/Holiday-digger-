extends Node
## test_screenshot_caves — не автотест, а инструмент глаз: полости-фигуры на
## настоящем рендере. Полости четырёх форм с кромкой, дымкой и стражами;
## бой с каждым видом стража (замах); снаряд плевуна в полёте; сундук заперт /
## отперт / открыт.
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_caves.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [сцена ...]
##
## Сцены: caves fight projectile chest. Сид подбирается так, чтобы в одном мире
## были все четыре формы не глубже 3999.

var _out_dir := "/tmp/cave_shots"
var _only: Array[String] = []
var main: Node2D
var director: CombatDirector
var _by_kind := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	for i in range(1, args.size()):
		_only.append(args[i])
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var seed_value := _pick_seed()
	GameState.world_seed = seed_value
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	StoryState.set_flag("food_ordered", true)
	StoryState.flags()["bars_introduced"] = true
	Settings.reduce_motion = true
	Settings.hints_enabled = false

	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(4)
	main.hud.set_gauges_visible(true)
	GameState.ext.clear()
	director = CombatService.director as CombatDirector
	director.spawning_enabled = false
	director._stats_dirty = true
	main.player.frozen = false
	GameState.max_depth_reached = 10000
	main.player._announced_backpack = true
	main.player._announced_jetpack = true
	main.player._announced_rig = true
	for c in Caves.caves_between(main.world, 1500, 3999):
		if not _by_kind.has(String(c.kind)):
			_by_kind[String(c.kind)] = c
	print("сид %d, формы: %s" % [seed_value, str(_by_kind.keys())])

	if _want("caves"):
		await _scene_caves()
	if _want("fight"):
		await _scene_fight()
	if _want("projectile"):
		await _scene_projectile()
	if _want("chest"):
		await _scene_chest()
	get_tree().quit(0)


func _pick_seed() -> int:
	for s in range(1, 60):
		var w := WorldGen.new(s)
		var kinds := {}
		for c in Caves.caves_between(w, 1500, 3999):
			kinds[String(c.kind)] = true
		if kinds.size() == 4:
			return s
	return 4242


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	if main.hud._toast_panel != null:
		main.hud._toast_panel.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("снимок: ", path, " ", img.get_size())


## Герой на алтаре в центре полости (или на полу поближе к центру), туман вокруг открыт.
func _place(c: Dictionary, on_floor: bool = false, dx: float = 0.0) -> void:
	var p = main.player
	var cell := Caves.chest_cell(c)
	if on_floor:
		var best: Vector2i = cell
		var bd := 1 << 30
		for f: Vector2i in Caves.floor_cells(c):
			if Caves.run_width(c, f) < 3:
				continue
			var d := absi(f.x - cell.x) * 2 + absi(f.y - cell.y)
			if d < bd:
				bd = d
				best = f
		cell = best
	p.frozen = false
	p.x = float(cell.x) + 0.5 + dx
	p.y = float(cell.y) + 1.0 - CombatDirector.HERO_HH - 0.01
	p.vx = 0.0
	p.vy = 0.0
	p.on_ground = true
	p.facing = 1
	p.digging = null
	main.fog.reveal_around(p.x, p.y, 12, 12)
	director.iframes = 99.0
	director.swing_cd = 99.0
	GameState.hp = GameState.get_max_hp()
	director.monsters.clear()
	director.projectiles.clear()


func _freeze_guards() -> void:
	for m: Monster in director.monsters:
		m.state = "patrol"
		m.telegraph = false
		m.vx = 0.0
		m.vy = 0.0
		m.anim_t = 0.3


func _scene_caves() -> void:
	for kind in Caves.KINDS:
		if not _by_kind.has(kind):
			continue
		var c: Dictionary = _by_kind[kind]
		_place(c)
		for req in director.caves.spawn_requests(Caves.center(c), []):
			director.spawn(req)
		_freeze_guards()
		director.set_process(false)
		await _frames(3)
		await _shot("cave_%s" % kind)
		director.set_process(true)
	director.monsters.clear()


func _scene_fight() -> void:
	var c: Dictionary = _by_kind.get("circle", _by_kind.values()[0])
	for id in CombatData.cave_monster_ids():
		_place(c, true)
		var p = main.player
		var air := String(CombatData.monster(String(id)).get("behavior")) == "flyer"
		var m := director.spawn({"id": String(id), "x": p.x + 1.7, "y": p.y + (-0.8 if air else CombatDirector.HERO_HH), "group": 1, "emerge": Vector2.ZERO})
		m.state = "windup"
		m.telegraph = true
		m.t = 0.3
		m.facing = -1
		m.anim_t = 0.35
		director.set_process(false)
		await _frames(3)
		await _shot("fight_%s" % id)
		director.set_process(true)
	director.monsters.clear()


func _scene_projectile() -> void:
	var c: Dictionary = _by_kind.get("rhombus", _by_kind.values()[0])
	_place(c, true)
	var p = main.player
	var sp := director.spawn({"id": "acid_spitter", "x": p.x + 3.5, "y": p.y + CombatDirector.HERO_HH, "group": 1, "emerge": Vector2.ZERO})
	sp.state = "recover"
	sp.facing = -1
	sp.anim_t = 0.6
	var spec: Dictionary = CombatData.monster("acid_spitter").get("projectile", {})
	var aim := Projectile.aim(-3.5, 0.0, float(spec.get("speed", 7.5)), float(spec.get("gravity", 11.0)), true)
	var pr := Projectile.create(spec, sp.x - 0.5, sp.y - 0.3, aim.x, aim.y, 10.0, "void")
	# снаряд на середине дуги
	for i in range(12):
		pr.tick(1.0 / 30.0, {"x": -100.0, "y": -100.0, "hw": 0.38, "hh": 0.33, "alive": false}, director.cw.solid)
	director.projectiles.append(pr)
	var pr2 := Projectile.create({"kind": "stone", "speed": 6.0, "gravity": 0.0, "radius": 0.2, "ttl": 3.0}, p.x + 2.0, p.y - 1.6, -6.0, 0.0, 5.0, "phys")
	director.projectiles.append(pr2)
	director.set_process(false)
	await _frames(3)
	await _shot("projectile_flight")
	director.set_process(true)
	director.monsters.clear()
	director.projectiles.clear()


## Герой висит слева от сундука (заморожен, как в сцене), чтобы сундук был виден.
func _scene_chest() -> void:
	var c: Dictionary = _by_kind.get("star", _by_kind.values()[0])
	var id := Caves.id_of(c)
	GameState.ext.clear()
	_place(c)
	var p = main.player
	p.x -= 1.6
	p.frozen = true
	director.set_process(false)
	await _frames(3)
	await _shot("chest_locked")
	for g in Caves.guards(c):
		CaveGuards.note_kill(id, int(g.index))
	await _frames(3)
	await _shot("chest_unlocked")
	GameState.inventory.clear()
	director.caves.tick_chest(Vector2(Caves.chest_cell(c)) + Vector2(0.5, 0.5), main.get_node_or_null("MechDirector"))
	await _frames(3)
	await _shot("chest_opened")
	director.set_process(true)
	p.frozen = false

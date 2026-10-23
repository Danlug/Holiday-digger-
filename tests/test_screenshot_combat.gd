extends Node
## test_screenshot_combat — не автотест, а инструмент глаз: бой на настоящем
## рендере. Монстры рядом с героем (размер относительно его кадра 48×48),
## взмах, телеграфы и окно уязвимости босса, экран «Снаряжение» и ковка.
##
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_combat.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [сцена ...]
##
## Сцены: monsters swing hurt warden arena_telegraph arena_exposed gear forge.

var _out_dir := "/tmp/combat_shots"
var _only: Array[String] = []
var main: Node2D
var director: CombatDirector


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	for i in range(1, args.size()):
		_only.append(args[i])
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	StoryState.flags()["bars_introduced"] = true
	Settings.reduce_motion = true

	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(4)
	main.hud.set_gauges_visible(true)
	GameState.ext.clear()
	director = CombatService.director as CombatDirector
	director.spawning_enabled = false
	director._stats_dirty = true
	main.player.frozen = false
	GameState.max_depth_reached = 10000   # без опыта за рубежи глубины и анонсов снаряжения
	main.player._announced_backpack = true
	main.player._announced_jetpack = true
	main.player._announced_rig = true
	GameState.coins = 120000
	GameState.coins_changed.emit(GameState.coins)

	if _want("monsters"):
		await _scene_monsters()
	if _want("swing"):
		await _scene_swing()
	if _want("hurt"):
		await _scene_hurt()
	if _want("warden"):
		await _scene_warden()
	if _want("arena_telegraph") or _want("arena_exposed"):
		await _scene_arena()
	if _want("gear"):
		await _scene_gear()
	if _want("forge"):
		await _scene_forge()
	get_tree().quit(0)


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


## Широкая выработка (3 клетки высотой) на глубине и открытый туман вокруг.
func _carve(depth: int, x0: int, x1: int) -> void:
	var w: WorldGen = main.world
	for x in range(x0, x1 + 1):
		for dy in range(-2, 1):
			w.diffs[(depth + dy) * WorldGen.WIDTH + x] = true
	director.cw.invalidate()


func _place(depth: int, x: float = 16.5) -> void:
	var p = main.player
	p.x = x
	p.y = float(depth) + 0.6
	p.vx = 0.0
	p.vy = 0.0
	p.on_ground = true
	p.facing = 1
	p.digging = null
	main.fog.reveal_around(p.x, p.y, 9, 9)
	director.iframes = 0.0
	GameState.hp = GameState.get_max_hp()


func _scene_monsters() -> void:
	var depth := 6200
	_carve(depth, 8, 25)
	for id in CombatData.monster_ids():
		for pose in ["idle", "windup"]:
			_place(depth, 14.5)
			director.monsters.clear()
			var def := CombatData.monster(String(id))
			var air := String(def["behavior"]) in ["flyer", "swarm"]
			var y := float(depth) - (0.9 if air else 0.0)
			var n := 3 if String(def["behavior"]) == "swarm" else 1
			for k in range(n):
				director.spawn({"id": String(id), "x": 16.4 + k * 0.45, "y": y - (k % 2) * 0.5, "group": 1, "emerge": Vector2.ZERO})
			director.swing_cd = 99.0
			director.iframes = 99.0
			director.set_process(false)
			for m: Monster in director.monsters:
				m.state = "patrol" if pose == "idle" else "windup"
				m.telegraph = pose == "windup"
				m.t = 0.1
				m.vx = 0.0
				m.facing = -1
				m.anim_t = 0.2
				if m.behavior == "ambusher":
					m.state = "chase" if pose == "idle" else "windup"
			await _frames(2)
			await _shot("mon_%s_%s" % [id, pose])
			director.set_process(true)
	# спящий засадник в породе
	_place(depth, 14.5)
	director.monsters.clear()
	var mm := director.spawn({"id": "rock_mimic", "x": 16.5, "y": float(depth) + 1.0, "group": 1, "emerge": Vector2(15.5, float(depth))})
	mm.state = "dormant"
	director.set_process(false)
	await _frames(2)
	await _shot("mon_rock_mimic_dormant")
	director.set_process(true)
	director.monsters.clear()


func _scene_swing() -> void:
	var depth := 5200
	_carve(depth, 8, 25)
	_place(depth, 14.5)
	director.monsters.clear()
	var g := director.spawn({"id": "cinder_grub", "x": 16.0, "y": float(depth), "group": 1, "emerge": Vector2.ZERO})
	g.hp = 1e9
	g.max_hp = 1e9
	director.swing_cd = 0.0
	director.iframes = 99.0
	await _frames(2)
	director.try_swing(1)
	await _frames(3)
	await _shot("combat_swing")
	director.monsters.clear()
	await _frames(20)   # старый взмах догорел
	# и в другую сторону: взмах влево по червю слева
	var g2 := director.spawn({"id": "cinder_grub", "x": 13.0, "y": float(depth), "group": 1, "emerge": Vector2.ZERO})
	g2.hp = 1e9
	g2.max_hp = 1e9
	director.swing_cd = 0.0
	await _frames(2)
	director.try_swing(-1)
	await _frames(3)
	await _shot("combat_swing_left")
	director.monsters.clear()


func _scene_hurt() -> void:
	var depth := 5200
	_carve(depth, 8, 25)
	_place(depth, 14.5)
	director.monsters.clear()
	var g := director.spawn({"id": "gloom_moth", "x": 16.3, "y": float(depth) - 0.8, "group": 1, "emerge": Vector2.ZERO})
	g.state = "windup"
	g.t = 0.0
	g.telegraph = true
	director.swing_cd = 99.0
	director.iframes = 0.0
	director._hurt_hero(20.0, "void", 1, "test")
	await _frames(3)
	await _shot("combat_hurt_telegraph")
	director.monsters.clear()


func _scene_warden() -> void:
	var depth := 8400
	_carve(depth, 8, 25)
	_place(depth, 14.5)
	director.monsters.clear()
	var wd := director.spawn({"id": "abyss_warden", "x": 17.0, "y": float(depth), "group": 1, "emerge": Vector2.ZERO})
	wd.state = "windup"
	wd.t = 0.55
	wd.telegraph = true
	wd.facing = -1
	director.swing_cd = 99.0
	director.iframes = 99.0
	director.set_process(false)
	await _frames(3)
	await _shot("combat_warden_windup")
	director.set_process(true)
	director.monsters.clear()


func _scene_arena() -> void:
	var p = main.player
	CombatService.give("blade_t4")
	CombatService.equip("blade_t4")
	CombatService.give("armor_t4")
	CombatService.equip("armor_t4")
	director._stats_dirty = true
	var floor_y := BossArena.floor_y()
	p.x = 14.0
	p.y = float(floor_y) - 1.5
	main.fog.reveal_around(16.5, float(floor_y) - 4.0, 10, 10)
	GameState.hp = GameState.get_max_hp()
	director.monsters.clear()
	await _frames(3)
	var boss: BossLogic = director.boss
	if boss == null:
		print("босс не начался")
		return
	await _frames(40)
	await _shot("arena_intro")
	# дождаться телеграфа слэма
	director.set_process(false)
	var guard := 0
	while boss.state != BossLogic.TELEGRAPH and guard < 2000:
		guard += 1
		director.iframes = 99.0
		director._process(1.0 / 30.0)
	director.set_process(false)
	boss.t = boss._tele * 0.7
	if _want("arena_telegraph"):
		await _frames(2)
		await _shot("arena_telegraph")
	guard = 0
	while boss.state != BossLogic.RECOVER and guard < 2000:
		guard += 1
		director.iframes = 99.0
		director._process(1.0 / 30.0)
	p.x = boss.center_x + 2.3
	p.y = float(floor_y) - 0.4
	if _want("arena_exposed"):
		await _frames(3)
		await _shot("arena_exposed")
		director.swing_cd = 0.0
		director.try_swing(-1)
		await _frames(3)
		await _shot("arena_hit")
	director.set_process(true)
	GameState.take_damage(1e6, "test")
	await _frames(3)
	GameState.respawn()


func _scene_gear() -> void:
	GameState.ext.clear()
	for a in ["antiquity_5", "occult_5", "legends_5"]:
		GameState.collected_artifacts.append(a)
	for id in ["helm_t2", "armor_t3", "blade_t3", "shield_t2", "charm_t3", "blade_t1", "helm_t1", "idol_crown"]:
		CombatService.give(id)
	for id in ["helm_t2", "armor_t3", "blade_t3", "shield_t2", "charm_t3"]:
		CombatService.equip(id)
	CombatService.equip("ult_glove")
	GameState.house_is_indoors = true
	GameState.inventory["hellstone"] = 2
	director._stats_dirty = true
	director.open_equipment()
	await _frames(4)
	await _shot("equip_gear")
	GameState.house_is_indoors = false
	director.equip_screen.close()
	GameState.house_is_indoors = false


func _scene_forge() -> void:
	GameState.house_is_indoors = true
	GameState.house_storage["hellstone"] = 20
	GameState.house_storage["cinder_ash"] = 5
	GameState.house_storage["dark_matter"] = 4
	GameState.inventory["moth_dust"] = 12
	director.open_equipment()
	director.equip_screen._tab = "forge"
	director.equip_screen._rebuild()
	await _frames(4)
	await _shot("equip_forge")
	director.equip_screen._scroll.scroll_vertical = 400
	await _frames(3)
	await _shot("equip_forge_scrolled")
	director.equip_screen.close()
	GameState.house_is_indoors = false

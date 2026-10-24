extends Node
## test_screenshot_fx — не автотест, а инструмент глаз для эффектов мира (ветка «world-fx»): свет и тени на
## глубинах, светящиеся руды, поверхность в разное время суток, частицы копки, приземления, подбора и боя.
## Нужен настоящий рендер, окно вдвое крупнее:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_fx.tscn --rendering-driver opengl3 --resolution 448x960 -- /каталог [сцена ...]
##
## Сцены (через запятую можно несколько): ores:300 ores:3100 surface:12 surface:19 surface:23 depth:5 depth:9000
## fx:dig_stone fx:dig_ore fx:dig_dirt fx:land fx:pickup fx:hit fx:die fx:quake fx:smoke.
## Для ores и depth снимается пара «_off» (слой света выключен) и «_on». Тест работает и на старой сборке без
## слоя света (узел LightLayer не найден) — так снимаются кадры «до».

var _out_dir := "/tmp/fx_shots"
var _spec := "ores:300,ores:3100,ores:6000,surface:12,surface:19,surface:23,fx:dig_stone,fx:dig_ore,fx:land,fx:pickup,fx:hit,fx:die"
var main: Node2D

const ORES := [
	TileTypes.Type.URANIUM_ORE, TileTypes.Type.GEOCRYSTAL, TileTypes.Type.HELLSTONE, TileTypes.Type.DIVINE_HEART,
	TileTypes.Type.UNIVERSALIUM, TileTypes.Type.ANGEL_STONE, TileTypes.Type.DARK_MATTER, TileTypes.Type.DIAMOND,
	TileTypes.Type.RUBY, TileTypes.Type.EMERALD,
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_spec = ",".join(args.slice(1))
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	GameState.world_seed = 20261024   # одинаковый мир в каждом запуске: кадры «до/после» сравнимы
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	StoryState.flags()["bars_introduced"] = true
	GameState.max_depth_reached = 10000
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(4)
	main.hud.set_gauges_visible(true)
	main.player._announced_backpack = true
	main.player._announced_jetpack = true
	main.player._announced_rig = true
	for item in _spec.split(","):
		var parts := item.split(":")
		var arg := int(parts[1]) if parts.size() > 1 else 0
		match parts[0]:
			"ores":
				await _scene_ores(arg)
			"depth":
				await _scene_ores(arg, false)
			"surface":
				await _scene_surface(arg)
			"fx":
				await _scene_fx(parts[1])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	if main.hud._toast_panel != null:
		main.hud._toast_panel.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("снимок: ", path, " ", img.get_size())


func _light_nodes() -> Array:
	var vr: Node = main.view_root
	return [vr.get_node_or_null("LightLayer"), vr.get_node_or_null("ContactShadows")]


func _set_light(on: bool) -> void:
	var ln := _light_nodes()
	if ln[0] != null:
		ln[0].enabled = on
	if ln[1] != null:
		ln[1].visible = on


func _place(cx: int, cy: int, standing: bool = true) -> void:
	var p = main.player
	p.x = float(cx) + 0.5
	p.y = float(cy) + (1.5 if standing else 0.5)
	p.vx = 0.0
	p.vy = 0.0
	p.digging = null
	p.facing = 1
	GameState.player_depth = cy
	main.fog.reveal_around(p.x, p.y, 8, 6)
	GameState.hp = GameState.get_max_hp()


func _carve_pocket(cx: int, cy: int) -> void:
	var w: WorldGen = main.world
	for dx in range(-1, 2):
		for dy in range(0, 4):
			w.dig_cell(cx + dx, cy + dy)
	for dx in range(2, 4):
		w.dig_cell(cx + dx, cy + 3)
		w.dig_cell(cx + dx, cy + 2)


func _scene_ores(depth: int, with_ores: bool = true) -> void:
	var w: WorldGen = main.world
	var cx := 20
	var cy := depth
	_carve_pocket(cx, cy)
	if with_ores:
		var spots := [Vector2i(-2, 1), Vector2i(-2, 2), Vector2i(2, 0), Vector2i(2, 1), Vector2i(0, -1), Vector2i(1, -1),
				Vector2i(-1, 4), Vector2i(0, 4), Vector2i(1, 4), Vector2i(3, 1)]
		var map := {}
		for i in range(spots.size()):
			map[Vector2i(cx + spots[i].x, cy + spots[i].y)] = ORES[i]
		w.overlay = func(x: int, y: int) -> int: return int(map.get(Vector2i(x, y), -1))
		w.overlay_y_min = 1
	_place(cx, cy)
	await _frames(8)
	main.fog.reveal_around(main.player.x, main.player.y, 8, 6)
	await _frames(30)
	var sh = main.view_root.get_node_or_null("ContactShadows")
	if sh != null:
		print("тень героя: видима ", sh._hero.visible, " поз ", sh._hero.position, " масштаб ", sh._hero.scale, " a ", sh._hero.modulate.a,
				" земля ", sh._ground_row, " герой y ", snappedf(main.player.y, 0.01), " в дереве ", sh._hero.is_visible_in_tree(), " глоб ", sh._hero.global_position, " tex ", sh._hero.texture, " тени-видимы ", sh.visible, " z ", sh._hero.z_index)
	_set_light(false)
	await _frames(3)
	await _shot("%s_%d_off" % ["ores" if with_ores else "depth", depth])
	_set_light(true)
	await _frames(6)
	await _shot("%s_%d_on" % ["ores" if with_ores else "depth", depth])
	w.overlay = Callable()
	w.overlay_y_min = 1 << 30


func _scene_surface(hour: int) -> void:
	var dc := get_node_or_null("/root/DayCycle")
	if dc != null:
		dc.set_hour(float(hour))
	_place(13, 0, false)
	main.player.y = 0.7
	main.fog.reveal_around(main.player.x, main.player.y, 8, 6)
	await _frames(30)
	await _shot("surface_%02d" % hour)


func _scene_fx(kind: String) -> void:
	var cx := 20
	var cy := 300
	_carve_pocket(cx, cy)
	_place(cx, cy)
	await _frames(20)
	var p = main.player
	var pos := Vector2(p.x, p.y) * 32.0
	match kind:
		"dig_stone", "dig_dirt", "dig_ore":
			var tile := TileTypes.Type.STONE
			if kind == "dig_dirt":
				tile = TileTypes.Type.DIRT
			elif kind == "dig_ore":
				tile = TileTypes.Type.GEOCRYSTAL
			GameState.emit_event(&"dug", {"tile": tile, "pos": pos + Vector2(40, 0), "loot": true})
			await _wait(0.10)
		"land":
			p.y -= 3.0
			p.on_ground = false
			p.vy = 0.0
			await _wait(0.55)
			await _wait(0.05)
		"pickup":
			GameState.emit_event(&"dug", {"tile": TileTypes.Type.GOLD_ORE, "pos": pos + Vector2(40, 0), "loot": true})
			GameState.emit_event(&"picked", {"item": "gold", "count": 2})
			await _wait(0.25)
		"hit":
			GameState.emit_event(&"monster_hit", {"pos": pos + Vector2(36, -4), "damage": 12})
			await _wait(0.08)
		"die":
			GameState.emit_event(&"monster_killed", {"pos": pos + Vector2(36, -4)})
			await _wait(0.16)
		"quake":
			Fx.burst("poof", pos, 1.0)
			await _wait(0.12)
		"smoke":
			await _wait(1.5)
	await _shot("fx_%s" % kind)

extends Node
## test_screenshot_ores — не автотест, а инструмент глаз для руды (зона ore-look): как залежи читаются в
## настоящем рендере на разных глубинах, с вариантами тайла и искрами, и совпадают ли значки в рюкзаке с тайлами.
## Нужен реальный рендер, окно вдвое крупнее:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_ores.tscn --rendering-driver opengl3 --resolution 448x960 -- /каталог [глубины]
##
## Второй аргумент — глубины через запятую (по умолчанию 50,300,800,1500,2500,3500,4500,6000). На каждой глубине
## два кадра: showcase_<y>.png — вокруг героя выложены руды этой глубины (по 3x3 клетки каждой: видны все три
## варианта тайла и стык пластов; порода подменяется через WorldGen.overlay, сам мир не меняется) и plain_<y>.png —
## как сгенерировано. Плюс inventory.png (рюкзак со всеми рудами) и toast.png. Состояние выставляется только в памяти.

const IDS := ["iron_ore", "lead", "silver", "copper", "aluminium", "gold", "diamond", "peat", "coal", "nickel", "mercury",
		"platinum", "titanium", "lithium", "uranium", "ruby", "emerald", "scrap", "geocrystal", "ancient_metal", "obsidian",
		"hellstone", "dark_matter", "universum", "angelstone", "divine_heart"]

## Витрина по глубине: восемь руд, которые тут водятся (ГДД §4 и data/minerals.json).
const SHOWCASE := {
	50: ["IRON_ORE", "LEAD_ORE", "SILVER_ORE", "SCRAP_METAL", "PEAT", "IRON_ORE", "LEAD_ORE", "SCRAP_METAL"],
	300: ["COPPER_ORE", "GOLD_ORE", "ALUMINIUM_ORE", "DIAMOND", "PEAT", "IRON_ORE", "SILVER_ORE", "LEAD_ORE"],
	800: ["NICKEL_ORE", "MERCURY_ORE", "GOLD_ORE", "PEAT", "DIAMOND", "SILVER_ORE", "COPPER_ORE", "ALUMINIUM_ORE"],
	1500: ["COAL", "PLATINUM_ORE", "TITANIUM_ORE", "LITHIUM_ORE", "URANIUM_ORE", "NICKEL_ORE", "MERCURY_ORE", "GOLD_ORE"],
	2500: ["RUBY", "EMERALD", "URANIUM_ORE", "LITHIUM_ORE", "TITANIUM_ORE", "PLATINUM_ORE", "COAL", "DIAMOND"],
	3500: ["GEOCRYSTAL", "ANCIENT_METAL", "OBSIDIAN", "RUBY", "EMERALD", "URANIUM_ORE", "COAL", "PLATINUM_ORE"],
	4500: ["HELLSTONE", "DARK_MATTER", "GEOCRYSTAL", "ANCIENT_METAL", "OBSIDIAN", "RUBY", "EMERALD", "URANIUM_ORE"],
	6000: ["UNIVERSALIUM", "ANGEL_STONE", "DIVINE_HEART", "HELLSTONE", "DARK_MATTER", "GEOCRYSTAL", "OBSIDIAN", "ANCIENT_METAL"],
}

var _out_dir := "/tmp/ores_shots"
var _depths := "50,300,800,1500,2500,3500,4500,6000"
var _plant: Dictionary = {}   # Vector2i -> TileTypes.Type (витрина поверх мира)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_depths = args[1]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	GameState.debug_invincible = true   # на 4500+ без костюма жара убивает за пару кадров — нам нужна руда, не смерть

	for d in _depths.split(","):
		var depth := int(d)
		if depth <= 0:
			continue
		await _world_shot(main, depth, true)
		await _world_shot(main, depth, false)

	var hud = main.hud
	for i in IDS.size():
		GameState.inventory[IDS[i]] = 1 + i
	hud.open_inventory()
	await _frames(3)
	hud._render_inventory()
	await _frames(4)
	_shot("inventory")
	hud.close_inventory()
	await _frames(2)
	hud.toast_parts([{"icon_tex": UiIcons.item("gold")}, {"text": "+3"}, {"icon_tex": UiIcons.item("diamond")},
			{"text": "+1"}, {"icon_tex": UiIcons.item("coal")}, {"text": "+5"}], 4.0)
	await _frames(6)
	_shot("toast")
	get_tree().quit(0)


## Герой на глубине depth в узком кармане; при showcase вокруг — витрина руд этой глубины (3x3 клетки на руду,
## слева и справа от героя в пределах экрана шириной 7 клеток).
func _world_shot(main: Node2D, depth: int, showcase: bool) -> void:
	var world: WorldGen = main.world
	var player = main.player
	var cx := 16
	_plant.clear()
	world.overlay = Callable()
	world.overlay_y_min = 1 << 30
	if showcase:
		var types: Array = SHOWCASE.get(_nearest_key(depth), SHOWCASE[50])
		for i in range(types.size()):
			var type: int = TileTypes.Type[types[i]]
			var x0 := 13 if i % 2 == 0 else 17
			var y0 := depth - 4 + (i / 2) * 3
			for dx in range(3):
				for dy in range(3):
					_plant[Vector2i(x0 + dx, y0 + dy)] = type
		world.overlay_y_min = depth - 4
		world.overlay = _overlay_tile
	# карман 1x2 под героем
	world.dig_cell(cx, depth)
	world.dig_cell(cx, depth + 1)
	player.x = float(cx) + 0.5
	player.y = float(depth) + 1.5
	player.vx = 0.0
	player.vy = 0.0
	GameState.player_depth = depth
	main.fog.reveal_around(player.x, player.y, 8, 8)
	for i in range(6):
		await get_tree().process_frame
	main.fog.reveal_around(player.x, player.y, 8, 8)
	for i in range(30):
		await get_tree().process_frame
	_shot("%s_%d" % ["showcase" if showcase else "plain", depth])
	world.overlay = Callable()
	world.overlay_y_min = 1 << 30


func _overlay_tile(x: int, y: int) -> int:
	return int(_plant.get(Vector2i(x, y), -1))


func _nearest_key(depth: int) -> int:
	var best := 50
	for k in SHOWCASE:
		if absi(int(k) - depth) < absi(best - depth):
			best = int(k)
	return best


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(sname: String) -> void:
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join(sname + ".png"))
	print("снимок: ", sname)

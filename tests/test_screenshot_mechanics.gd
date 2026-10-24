extends Node
## Скриншоты механик раунда 3: сундук в породе (закрытый, в момент открытия, с
## остатком), шкала азарта, лихорадка, журнал (руды и тайники). Не автотест. Запуск:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" \
##       godot --path . res://tests/test_screenshot_mechanics.tscn \
##       --rendering-driver opengl3 --resolution 448x960 -- /tmp/mech_shots [виды через запятую]
##
## Виды: chest, open, streak, fever, journal, chests_tab. По умолчанию все.

const SEED := 4242

var _out_dir := "/tmp/mech_shots"
var _spec := "chest,open,streak,fever,journal,chests_tab"
var main: Node2D
var d: MechDirector


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_spec = args[1]
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
	for kind in _spec.split(","):
		match kind:
			"chest":
				await _chest("gold", "chest_closed")
				await _chest("wood", "chest_wood")
			"open":
				await _open()
			"streak":
				await _streak(false)
			"fever":
				await _streak(true)
			"journal":
				await _journal(JournalScreen.TAB_ORES, "journal_ores")
			"chests_tab":
				await _journal(JournalScreen.TAB_CHESTS, "journal_chests")
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


## Первый сундук нужной ступени ниже y_from.
func _find(tier: String, y_from: int = 20) -> Dictionary:
	for b in range(ChestLogic.band_of(maxi(y_from, 20)), 900):
		var ch := d.chest_for_band(b)
		if not ch.is_empty() and String(ch["tier"]) == tier and int(ch["cell"].x) > 1 and int(ch["cell"].x) < 30:
			return ch
	return {}


## Герой стоит в выкопанном кармане слева от сундука, обзор открыт.
func _stand_left_of(cell: Vector2i) -> void:
	var world: WorldGen = main.world
	var player = main.player
	for dx in range(-3, 0):
		for dy in range(-2, 1):
			if not (dx == 0 and dy == 0):
				world.dig_cell(cell.x + dx, cell.y + dy)
	player.x = float(cell.x - 1) + 0.5
	player.y = float(cell.y) + 0.5
	player.vx = 0.0
	player.vy = 0.0
	player.release_control()
	GameState.player_depth = cell.y
	main.fog.reveal_around(player.x, player.y, 4, 3)


func _chest(tier: String, name: String) -> void:
	var ch := _find(tier)
	print("сундук ", tier, ": ", ch)
	_stand_left_of(ch["cell"])
	await _frames(24)
	await _shot(name)


func _open() -> void:
	var ch := _find("iron", 150)
	var cell: Vector2i = ch["cell"]
	_stand_left_of(cell)
	await _frames(20)
	# рюкзак почти полон: часть добычи останется в сундуке, над ним — значок остатка
	GameState.inventory.clear()
	GameState.add_item("lead", 18)
	main.world.dig_cell(cell.x, cell.y)
	GameState.emit_event(&"dug", {"cell": cell, "tile": TileTypes.Type.DIRT, "mineral": "", "loot": false,
		"pos": Vector2(cell.x * 32.0 + 16.0, cell.y * 32.0 + 16.0)})
	await _frames(5)
	await _shot("chest_opening")
	await _frames(40)
	await _shot("chest_left")
	GameState.inventory.clear()


func _streak(fever: bool) -> void:
	var ch := _find("wood", 400)
	_stand_left_of(Vector2i(ch["cell"].x, ch["cell"].y))
	d.streak.reset()
	var y: int = ch["cell"].y
	for i in range(55 if fever else 31):
		d.streak.on_dug(y)
	main.player.digging = {"x": int(main.player.x) + 1, "y": y, "t": 0.3, "total": 1.0, "type": TileTypes.Type.DIRT}
	await _frames(40)
	await _shot("fever" if fever else "streak")
	main.player.digging = null
	d.streak.reset()


func _journal(tab: String, name: String) -> void:
	var counts := {"iron_ore": 620, "scrap": 44, "lead": 90, "silver": 160, "copper": 300, "gold": 260,
		"aluminium": 12, "diamond": 11, "nickel": 4, "peat": 1600, "coal": 2}
	for id in counts.keys():
		var n := int(counts[id]) - MechState.mastery_count(id)
		if n > 0:
			MechState.add_mastery(id, n)
		MechState.set_stars_granted(id, MasteryLogic.stars_for(id, MechState.mastery_count(id)))
	MechState.mark_all_seen()
	MechState.root()["mastery"]["seen"]["nickel"] = 0   # «новая» запись — зелёная рамка
	MechState.root()["mastery"]["seen"]["diamond"] = 1
	for i in range(9):
		MechState.mark_chest_opened(Vector2i(i, -5), "wood" if i < 6 else ("iron" if i < 8 else "gold"))
	MechState.bump_stat("fevers", 7)
	MechState.bump_stat("bonus_items", 41)
	d.journal.open(tab)
	await _frames(20)
	await _shot(name)
	d.journal.close()
	await _frames(6)

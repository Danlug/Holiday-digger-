extends Node
## test_screenshot_death — не автотест, а инструмент глаз для окна смерти (ГДД §7 «Цена
## смерти», разбор чисел 26.10): каждая причина настоящим путём урона (удар стража, падение,
## голод, лава, босс), переполненный рюкзак, подсказки, английский текст и дом после «Дальше».
##
##   export XDG_DATA_HOME=$PWD/.godot/xdg
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_death.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [снимок ...]
##
## Снимки: guard fall hunger lava boss many tip_cause tip_fee en home_after.

var _out_dir := "/tmp/death_shots"
var _only: Array[String] = []
var _main: Node2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	for i in range(1, args.size()):
		_only.append(args[i])
	DirAccess.make_dir_recursive_absolute(_out_dir)
	GameState.world_seed = 4242
	GameState.reset_progress()
	# все сцены просмотрены: звонок с кладбища и вехи глубины иначе играют поверх окна
	for id in StoryData.scene_ids():
		StoryState.mark_seen(String(id))
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "gold_sold", "food_ordered"]:
		StoryState.set_flag(f)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(6)
	var meta = _main.get_node_or_null("MetaService")
	if meta != null:
		meta.set_process(false)
		if meta.popup != null and meta.popup.is_open():
			meta.popup.close()
	GameState.level = 14
	GameState.max_depth_reached = 2400

	await _scene("guard", _s_guard)
	await _scene("fall", _s_fall)
	await _scene("hunger", _s_hunger)
	await _scene("lava", _s_lava)
	await _scene("boss", _s_boss)
	await _scene("many", _s_many)
	await _scene("tip_cause", _s_tip_cause)
	await _scene("tip_fee", _s_tip_fee)
	await _scene("en", _s_en)
	await _scene("home_after", _s_home_after)
	print("test_screenshot_death: снимки -> " + _out_dir)
	get_tree().quit(0)


func _scene(sname: String, fn: Callable) -> void:
	if not _only.is_empty() and not _only.has(sname):
		return
	_reset()
	await fn.call()
	await _frames(4)
	_shot(sname)
	_cleanup()
	await _frames(3)


func _reset() -> void:
	Settings.language = "ru"
	GameState.is_alive = true
	GameState.hp = GameState.get_max_hp()
	GameState.set_hunger(70.0)
	GameState.set_stamina(60.0)
	GameState.inventory.clear()
	GameState.inventory_changed.emit()
	Tip.hide_all()


func _cleanup() -> void:
	Tip.hide_all()
	var win := _window()
	if win.is_open():
		win.close()


func _window() -> DeathWindow:
	return _main.get_node("FeelDirector").card


func _pack(items: Dictionary) -> void:
	for id in items:
		GameState.add_item(String(id), int(items[id]))


## Герой на глубине depth с coins монет; урон добивает настоящим путём, затем ждём окно.
func _die_at(depth: int, coins: int, kill: Callable) -> void:
	var p = _main.player
	p.x = 16.5
	p.y = float(depth) + 0.5
	p.frozen = false
	await _frames(2)
	GameState.coins = coins
	GameState.hp = 1.0
	kill.call()
	var win := _window()
	for _i in range(40):
		if win.is_open():
			break
		await _wait(0.1)
	await _frames(12)   # анимация появления
	print("%s: %s, монет %d, плата %d" % [DeathCause.phrase(GameState.death_cause), str(GameState.death_cause),
		GameState.coins, Healing.last_death_fee])


func _hurt(source: String, info: Dictionary = {}) -> void:
	var cd = CombatService.director
	cd.iframes = 0.0
	cd._hurt_hero(1e6, "phys", 1, source, info)


func _s_guard() -> void:
	_pack({"silver": 6, "iron_ore": 14, "ruby": 1, "diamond": 2, "coal": 9, "medkit": 1, "food_steak": 1})
	await _die_at(1800, 4280, func() -> void: _hurt("monster:cave_bat", {"guard": true}))


func _s_fall() -> void:
	_pack({"iron_ore": 9, "silver": 3, "food_bar": 1})
	var p = _main.player
	await _die_at(410, 900, func() -> void:
		p._air_top_y = p.y - 52.0
		p.vy = 28.0
		p._land())


func _s_hunger() -> void:
	await _die_at(120, 30, func() -> void:
		GameState.set_hunger(0.0)
		for _i in 20:
			if not GameState.is_alive:
				break
			GameState._tick_survival(1.0))


func _s_lava() -> void:
	_pack({"hellstone": 3, "geocrystal": 5, "uranium": 2, "obsidian": 7})
	await _die_at(3200, 250000, func() -> void: Heat.burn_digger(1.0))


func _s_boss() -> void:
	_pack({"idol_shard": 1, "dark_matter": 2})
	await _die_at(4300, 0, func() -> void: _hurt("boss:slam"))


func _s_many() -> void:
	var many := {}
	for id in ["iron_ore", "silver", "copper", "lead", "aluminium", "nickel", "gold", "coal", "peat", "scrap",
			"diamond", "ruby", "emerald", "medkit"]:
		many[id] = randi_range(1, 12)
	GameState.inventory = many   # мимо add_item: переполнение, а не предел веса рюкзака
	GameState.inventory_changed.emit()
	await _die_at(1650, 12800, func() -> void: _hurt("projectile:acid", {"id": "acid_spitter"}))


func _s_tip_cause() -> void:
	await _s_guard()
	Tip.show_now(_window().find_child("CauseIcon", true, false))
	await _frames(4)


func _s_tip_fee() -> void:
	await _s_hunger()
	Tip.show_now(_window().find_child("Hospital", true, false))
	await _frames(4)


func _s_en() -> void:
	Settings.language = "en"
	await _s_fall()


## «Дальше» — герой дома, полоски: HP полное, сытость и бодрость не ниже 25%.
func _s_home_after() -> void:
	await _s_hunger()
	var nxt := _window().find_child("Next", true, false) as Button
	await _wait(0.5)
	nxt.pressed.emit()
	await _frames(10)
	print("home_after: HP %.0f/%.0f, сытость %.0f, бодрость %.0f" % [GameState.hp, GameState.get_max_hp(),
		GameState.hunger, GameState.stamina])


# ---------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(sname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(sname + ".png"))
	print("снимок: " + sname)

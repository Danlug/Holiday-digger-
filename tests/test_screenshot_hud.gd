extends Node
## test_screenshot_hud — не автотест, а инструмент глаз: поднимает main.tscn и
## снимает HUD в разных состояниях (база, меню «•••», настройки, рюкзак с
## кучей предметов, низкое HP, длинные числа). Нужен настоящий рендер; окно
## лучше брать вдвое крупнее, чтобы текст и иконки читались:
##
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_hud.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [сцена ...]
##
## Первый аргумент после "--" — каталог, остальные — имена сцен (по умолчанию
## все): base menu settings inventory drop lowhp bigmoney toasts.

var _out_dir := "/tmp/hud_shots"
var _only: Array[String] = []
var _hud: Control


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
	# Полоски жизни режиссура прячет до сцены смерти; флаг — только в памяти,
	# на диск (user://) тест ничего не пишет.
	StoryState.flags()["bars_introduced"] = true
	Settings.reduce_motion = true   # снимки без «полёта» посреди твина

	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	_hud = main.hud
	_hud.set_gauges_visible(true)
	GameState.coins = 1250
	GameState.dollars = 3
	GameState.coins_changed.emit(GameState.coins)
	GameState.dollars_changed.emit(GameState.dollars)
	await _frames(3)

	if _want("base"):
		await _shot("base")

	if _want("menu"):
		_hud._toggle_more_menu()
		await _frames(3)
		await _shot("menu")
		_hud.close_more_menu()
		await _frames(2)

	if _want("settings"):
		_hud.open_settings()
		await _frames(3)
		await _shot("settings")
		_hud.close_settings()
		await _frames(2)

	if _want("inventory") or _want("drop"):
		GameState.inventory = {"gold": 5, "obsidian": 3, "iron_ore": 12, "diamond": 2,
			"copper": 40, "coal": 7, "silver": 1, "uranium": 1, "energy_bar": 2}
		GameState.inventory_changed.emit()
		_hud.open_inventory()
		await _frames(3)
		if _want("inventory"):
			await _shot("inventory")
		if _want("drop"):
			_hud._open_drop("gold", 5)
			await _frames(3)
			await _shot("drop")
			_hud._close_drop()
		_hud.close_inventory()
		await _frames(2)

	if _want("lowhp"):
		GameState.hp = 18.0
		GameState.hp_changed.emit(GameState.hp, GameState.get_max_hp())
		GameState.hunger = 20.0
		GameState.hunger_changed.emit(GameState.hunger)
		GameState.stamina = 60.0
		GameState.stamina_changed.emit(GameState.stamina)
		await _frames(30)
		await _shot("lowhp")

	if _want("bigmoney"):
		GameState.coins = 123456789
		GameState.dollars = 99999
		GameState.coins_changed.emit(GameState.coins)
		GameState.dollars_changed.emit(GameState.dollars)
		await _frames(40)
		await _shot("bigmoney")

	if _want("toasts"):
		_hud.toast("Готово.")
		await _frames(3)
		await _shot("toast_short")

	print("test_screenshot_hud: снимки -> " + _out_dir)
	get_tree().quit(0)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(n + ".png"))

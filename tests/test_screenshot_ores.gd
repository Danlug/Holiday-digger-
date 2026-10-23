extends Node
## test_screenshot_ores — не автотест, а инструмент глаз для значков ресурсов (ветка «ores-gems»): рюкзак со всеми
## самоцветами, глубинными рудами и добычей монстров, тост с предметами в настоящем рендере.
## Нужен реальный рендер, окно вдвое крупнее:
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_ores.tscn --rendering-driver opengl3 --resolution 448x960 -- /каталог
##
## Состояние выставляется только в памяти.

const IDS := ["diamond", "ruby", "emerald", "geocrystal", "ancient_metal", "obsidian", "hellstone", "dark_matter",
		"universum", "angelstone", "divine_heart", "cinder_ash", "moth_dust", "hopper_fang", "mimic_geode",
		"spark_core", "warden_plate", "abyss_core", "idol_shard"]

var _out_dir := "/tmp/ores_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	var hud = main.hud
	for i in IDS.size():
		GameState.inventory[IDS[i]] = 2 + i * 3
	hud.open_inventory()
	await _frames(3)
	hud._render_inventory()
	await _frames(4)
	_shot("inventory")
	hud.close_inventory()
	await _frames(2)
	hud.toast_parts([{"icon_tex": UiIcons.item("divine_heart")}, {"text": "+1"}, {"icon_tex": UiIcons.item("dark_matter")},
			{"text": "+2"}, {"icon_tex": UiIcons.item("universum")}], 4.0)
	await _frames(6)
	_shot("toast")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(sname: String) -> void:
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join(sname + ".png"))
	print("снимок: ", sname)

extends Node
## test_screenshot_analytics — не автотест, а инструмент глаз для аналитики (ГДД §16.1): окно
## согласия при первом запуске, «Подробнее», переключатель в настройках (вкл/выкл) и его Tip.
##
##   godot --path . res://tests/test_screenshot_analytics.tscn --rendering-driver opengl3 \
##       --resolution 552x1200 -- /каталог
##
## Снимки: consent details settings_on settings_off settings_tip.

var _out_dir := "/tmp/analytics_shots"
var _main: Node2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	Analytics.sender = func(_u: String, _b: String, done: Callable) -> void: done.call(true)   # сети нет
	Settings.reduce_motion = true
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(6)
	var meta = _main.get_node_or_null("MetaService")
	if meta != null and meta.popup != null and meta.popup.is_open():
		meta.popup.close()
	var d := ConsentDialog.open_on(_main)
	await _frames(4)
	_shot("consent")
	d.show_details(true)
	await _frames(3)
	_shot("details")
	d.show_details(false)
	d.choose(true)
	await _frames(3)
	var hud = _main.hud
	hud.open_settings()
	await _frames(4)
	_shot("settings_on")
	var btn: Button = hud._settings_sheet._analytics_btn
	btn.pressed.emit()
	await _frames(3)
	_shot("settings_off")
	Tip.show_now(btn)
	await _frames(4)
	_shot("settings_tip")
	Analytics.sender = Callable()
	print("test_screenshot_analytics: снимки -> " + _out_dir)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(sname: String) -> void:
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join(sname + ".png"))
	print("снимок: " + sname)

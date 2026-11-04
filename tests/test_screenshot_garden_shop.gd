extends Node
## test_screenshot_garden_shop — не автотест, а инструмент глаз (раунд 5, ветка
## garden-shop): витрина на огороде в живой игре и стрелка «к двери» над миром.
## Поднимает main.tscn; нужен настоящий рендер, окно лучше вдвое крупнее:
##
##   export XDG_DATA_HOME=$PWD/.godot/xdg
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_garden_shop.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [снимок ...]
##
## Снимки: shop_garden (витрина с огорода, вкладка еды), guide_right (дверь
## правее кадра — стрелка у края), guide_left (дверь левее кадра), guide_near
## (дверь в кадре — стрелка вниз над ней), guide_arrived (дошёл: пузырь «Зайти»,
## стрелка погасла), reopen_hall (зашёл — витрина открылась в прихожей сама).
## Состояние — только в памяти; на диск (user://) тест не пишет.

var _out_dir := "/tmp/garden_shop_shots"
var _only: Array[String] = []
var _main: Node2D
var _house: HouseSystem


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	for i in range(1, args.size()):
		_only.append(args[i])
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(2)
	var director = _main.get_node("StoryDirector")
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure", "workshop", "death",
			"backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2"]:
		StoryState.mark_seen(id)
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered"]:
		StoryState.set_flag(f)
	var meta = _main.get_node_or_null("MetaService")
	if meta != null:
		meta.set_process(false)
		if meta.popup != null and meta.popup.is_open():
			meta.popup.close()
	for _i in range(6):
		if director.cutscene != null and director.cutscene.is_playing:
			director.cutscene.skip()
		await _wait(0.3)
	Settings.reduce_motion = true
	_house = HouseSystem.instance
	_house.player = _main.player
	_house.hud = _main.hud

	await _scene("shop_garden", _s_shop_garden)
	await _scene("guide_right", _s_guide_right)
	await _scene("guide_left", _s_guide_left)
	await _scene("guide_near", _s_guide_near)
	await _scene("guide_arrived", _s_guide_arrived)
	await _scene("reopen_hall", _s_reopen_hall)
	print("test_screenshot_garden_shop: снимки -> " + _out_dir)
	get_tree().quit(0)


func _scene(sname: String, fn: Callable) -> void:
	if not _only.is_empty() and not _only.has(sname):
		return
	_reset()
	await fn.call()
	await _frames(4)
	_shot(sname)
	await _cleanup()


func _reset() -> void:
	GameState.house_hatch_built = true
	GameState.coins = 340
	GameState.dollars = 2
	GameState.hp = GameState.get_max_hp()
	GameState.set_stamina(80.0)
	GameState.set_hunger(90.0)
	GameState.house_tutorial_stage = 2
	GameState.era = "now"
	GameState.player_depth = 0
	Tip.hide_all()


func _cleanup() -> void:
	Tip.hide_all()
	if ShopUI.instance.is_open():
		ShopUI.instance.close()
	ShopUI.instance._door_guide.stop()
	if GameState.house_is_indoors:
		_house.exit_to_door()
	_house._view.close()
	await _frames(2)


## Герой на поверхности в клетке x; камере даём доехать.
func _stand(x: float) -> void:
	_main.player.x = x
	_main.player.y = 0.5
	_main.player.vx = 0.0
	_main.player.vy = 0.0
	await _wait(0.8)


func _s_shop_garden() -> void:
	await _stand(4.5)
	ShopUI.open_shop()
	await _frames(3)


func _guide_from(x: float) -> void:
	await _stand(x)
	ShopUI.open_shop()
	await _frames(2)
	ShopUI.instance._go_to_door()
	await _wait(0.3)


func _s_guide_right() -> void:
	await _guide_from(2.5)


func _s_guide_left() -> void:
	await _guide_from(26.5)


func _s_guide_near() -> void:
	await _guide_from(float(HouseConfig.door_cell().x) - 2.0)


func _s_guide_arrived() -> void:
	await _guide_from(float(HouseConfig.door_cell().x) - 2.0)
	_main.player.x = float(HouseConfig.door_cell().x) + 0.5
	await _wait(0.3)


func _s_reopen_hall() -> void:
	await _guide_from(float(HouseConfig.door_cell().x) - 2.0)
	_main.player.x = float(HouseConfig.door_cell().x) + 0.5
	await _wait(0.2)
	_house.enter_house("hall")
	await _wait(0.8)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(sname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(sname + ".png"))

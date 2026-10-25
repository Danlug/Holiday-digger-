extends Node
## test_screenshot_purchase — не автотест, а инструмент глаз: витрина по правилу
## «где можно покупать» (ГДД §15): под землёй плитки с бейджем «осталось N/3» и
## значком ролика, без роликов — замок и причина, у двери — как раньше.
## Плитки за доллары (раунд 4) — везде как у двери: без замка, «N/3» и ролика.
## Огород и комнаты дома (раунд 5): значок двери на монетных плитках, полоса
## «за монеты — у входной двери» внизу и кнопка «к двери» (только огород).
## Нужен настоящий рендер; «родной» размер вьюпорта 224×480, вдвое крупнее
## читается лучше:
##
##   export XDG_DATA_HOME=$PWD/.godot/xdg
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_purchase.tscn --rendering-driver opengl3 \
##       --resolution 224x480 -- /каталог [сцена ...]
##
## Сцены: door_food door_picks under_food under_picks under_premium under_card
## under_empty_picks under_empty_food garden_food garden_food_clean garden_picks
## garden_premium garden_premium_clean (_clean — плашка-причина уже погасла)
## under_empty_premium under_premium_card (покупка за доллары в шахте без роликов)
## garden_tap garden_tap_end (тап по плитке «у двери»: дверь летит в полосу)
## house_food (комната дома: полоса без кнопки «к двери»).
## Стрелку «к двери» над миром снимает tests/test_screenshot_garden_shop.

var _out_dir := "/tmp/purchase_shots"
var _only: Array[String] = []
var _ui: ShopUI


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	for i in range(1, args.size()):
		_only.append(args[i])
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	Settings.reduce_motion = true

	var back := ColorRect.new()
	back.color = Color8(0x60, 0x90, 0xC0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	_ui = load("res://scenes/shop.tscn").instantiate()
	add_child(_ui)
	await _frames(3)

	await _scene("door_food", _s_door_food)
	await _scene("door_picks", _s_door_picks)
	await _scene("under_food", _s_under_food)
	await _scene("under_picks", _s_under_picks)
	await _scene("under_premium", _s_under_premium)
	await _scene("under_card", _s_under_card)
	await _scene("under_empty_picks", _s_under_empty_picks)
	await _scene("under_empty_food", _s_under_empty_food)
	await _scene("garden_food", _s_garden_food)
	await _scene("garden_food_clean", _s_garden_food_clean)
	await _scene("garden_picks", _s_garden_picks)
	await _scene("garden_premium", _s_garden_premium)
	await _scene("garden_premium_clean", _s_garden_premium_clean)
	await _scene("under_empty_premium", _s_under_empty_premium)
	await _scene("under_premium_card", _s_under_premium_card)
	await _scene("garden_tap", _s_garden_tap)
	await _scene("garden_tap_end", _s_garden_tap_end)
	await _scene("house_food", _s_house_food)
	print("test_screenshot_purchase: снимки -> " + _out_dir)
	get_tree().quit(0)


func _scene(sname: String, fn: Callable) -> void:
	if not _only.is_empty() and not _only.has(sname):
		return
	_reset()
	await fn.call()
	await _frames(4)
	_shot(sname)
	if _ui.is_open():
		_ui.close()
	await _frames(2)


func _reset() -> void:
	GameState.reset_progress()
	MetaClock.override_unix = 20000 * 86400 + 3600
	GameState.max_depth_reached = 1200
	GameState.coins = 1700
	GameState.dollars = 4
	GameState.inventory.clear()
	GameState.grant_tool("iron_pickaxe")
	GameState.house_free_orders_used_today = 3
	_ui._notice_panel.visible = false
	ShopCatalog.reload()


func _place(place: String) -> void:
	GameState.house_is_indoors = place in ["door", "house"]
	GameState.house_room = "hall" if place == "door" else "workshop"
	GameState.player_depth = 40 if place == "underground" else 0


func _burn_ads() -> void:
	for i in ShopRemote.limit():
		ShopRemote.watch_ad()


func _s_door_food() -> void:
	_place("door")
	_ui.open(ShopUI.TAB_FOOD)


func _s_door_picks() -> void:
	_place("door")
	_ui.open(ShopUI.TAB_PICKS)


func _s_under_food() -> void:
	_place("underground")
	_ui.open(ShopUI.TAB_FOOD)


func _s_under_picks() -> void:
	_place("underground")
	_ui.open(ShopUI.TAB_PICKS)


func _s_under_premium() -> void:
	_place("underground")
	_ui.open(ShopUI.SCREEN_PREMIUM)


func _s_under_card() -> void:
	_place("underground")
	_ui.open(ShopUI.TAB_PICKS)
	await _frames(2)
	var t: ShopTile = _ui._tiles["tool:titanium_pickaxe"]
	_ui._on_tile_pressed(t.offer, t)
	await _frames(6)


func _s_under_empty_picks() -> void:
	_place("underground")
	_burn_ads()
	_ui.open(ShopUI.TAB_PICKS)


func _s_under_empty_food() -> void:
	_place("underground")
	_burn_ads()
	_ui.open(ShopUI.TAB_FOOD)
	await _frames(2)
	var t: ShopTile = _ui._tiles["food:food_buldak"]
	_ui._on_tile_pressed(t.offer, t)


func _s_garden_food() -> void:
	_place("garden")
	_ui.open(ShopUI.TAB_FOOD)


func _s_garden_food_clean() -> void:
	_place("garden")
	_ui.open(ShopUI.TAB_FOOD)
	await _frames(2)
	_ui._notice_panel.visible = false


func _s_garden_picks() -> void:
	_place("garden")
	_ui.open(ShopUI.TAB_PICKS)


func _s_garden_premium() -> void:
	_place("garden")
	_ui.open(ShopUI.SCREEN_PREMIUM)


func _s_garden_premium_clean() -> void:
	_place("garden")
	_ui.open(ShopUI.SCREEN_PREMIUM)
	await _frames(2)
	_ui._notice_panel.visible = false


func _s_under_empty_premium() -> void:
	_place("underground")
	_burn_ads()
	_ui.open(ShopUI.SCREEN_PREMIUM)


func _s_under_premium_card() -> void:
	_place("underground")
	_burn_ads()
	_ui.open(ShopUI.SCREEN_PREMIUM)
	await _frames(2)
	var t: ShopTile = _ui._tiles["good:dollars:teleport_watch"]
	_ui._on_tile_pressed(t.offer, t)
	await _frames(6)


## Отклик на тап снимаем с движением: дверь в полёте к полосе.
func _s_garden_tap() -> void:
	await _tap_door_tile(0.12)


func _s_garden_tap_end() -> void:
	await _tap_door_tile(0.42)


func _tap_door_tile(sec: float) -> void:
	_place("garden")
	_ui.open(ShopUI.TAB_FOOD)
	await _frames(2)
	Settings.reduce_motion = false
	var t: ShopTile = _ui._tiles["food:food_buldak"]
	_ui._on_tile_pressed(t.offer, t)
	await get_tree().create_timer(sec).timeout
	Settings.reduce_motion = true


func _s_house_food() -> void:
	_place("house")
	_ui.open(ShopUI.TAB_FOOD)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(sname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(sname + ".png"))

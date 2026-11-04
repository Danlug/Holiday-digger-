extends Node
## test_screenshot_craft — не автотест, а инструмент глаз: карточка рецепта
## мастерской с ползунком «сколько плавить» (раунд 4, «craft-qty»). Нужен
## настоящий рендер; окно лучше брать вдвое крупнее:
##
##   export XDG_DATA_HOME=$PWD/.godot/xdg
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_craft.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [сцена ...]
##
## Сцены: bronze_max (ползунок на максимуме), bronze_mid (на середине),
## bronze_one (материала на одну штуку), bronze_none (материала нет),
## bronze_fly (полёт материалов в верстак после «плавить»), bronze_done (итог
## «+N»), drill (разовый рецепт — без ползунка, вид прежний).
## Печь бронзы (26.10, «минута штука»): furnace_busy (карточка: очередь, отсчёт,
## готово N, крестик), furnace_tile (плитка с огоньком и отсчётом), furnace_away
## (из шахты: карточка без ползунка, только печь), furnace_load (лом долетел в
## печь — огонёк с «+N» в очередь).

var _out_dir := "/tmp/craft_shots"
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

	await _scene("bronze_max", _s_bronze_max)
	await _scene("bronze_mid", _s_bronze_mid)
	await _scene("bronze_one", _s_bronze_one)
	await _scene("bronze_none", _s_bronze_none)
	await _scene("bronze_fly", _s_bronze_fly)
	await _scene("bronze_done", _s_bronze_done)
	await _scene("drill", _s_drill)
	await _scene("furnace_busy", _s_furnace_busy)
	await _scene("furnace_tile", _s_furnace_tile)
	await _scene("furnace_away", _s_furnace_away)
	await _scene("furnace_load", _s_furnace_load)
	BronzeFurnace.override_unix = -1
	print("test_screenshot_craft: снимки -> " + _out_dir)
	get_tree().quit(0)


func _scene(sname: String, fn: Callable) -> void:
	if not _only.is_empty() and not _only.has(sname):
		return
	_reset()
	await fn.call()
	await _frames(4)
	_shot(sname)
	Settings.reduce_motion = true
	if _ui.is_open():
		_ui.close()
	await _frames(2)


func _reset() -> void:
	GameState.reset_progress()
	GameState.house_is_indoors = true
	# Витрина с «Техникой» открывается у входной двери (в мастерской сверху
	# висела бы плашка «Покупки — у входной двери»); верстак работает из всего дома.
	GameState.house_room = "hall"
	GameState.max_depth_reached = 0
	GameState.coins = 340
	GameState.dollars = 2
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.ad_daily_counts.clear()
	_ui._notice_panel.visible = false
	ShopCatalog.reload()


func _open_bronze() -> void:
	_ui.open(ShopUI.TAB_TECH)
	await _frames(2)
	var t: ShopTile = _ui._tiles["recipe:bronze"]
	_ui._on_tile_pressed(t.offer, t)
	await _frames(6)


func _s_bronze_max() -> void:
	GameState.inventory["scrap"] = 14
	GameState.house_storage["scrap"] = 23
	await _open_bronze()


func _s_bronze_mid() -> void:
	GameState.inventory["scrap"] = 14
	GameState.house_storage["scrap"] = 23
	await _open_bronze()
	_set_qty(9)
	await _frames(3)


func _s_bronze_one() -> void:
	GameState.inventory["scrap"] = 1
	await _open_bronze()


func _s_bronze_none() -> void:
	await _open_bronze()


func _s_bronze_fly() -> void:
	GameState.inventory["scrap"] = 14
	GameState.house_storage["scrap"] = 23
	await _open_bronze()
	Settings.reduce_motion = false
	_ui._confirm_card()
	await _frames(14)


func _s_bronze_done() -> void:
	GameState.inventory["scrap"] = 14
	GameState.house_storage["scrap"] = 23
	await _open_bronze()
	Settings.reduce_motion = false
	_ui._confirm_card()
	await _frames(44)


func _s_drill() -> void:
	GameState.max_depth_reached = 1200
	GameState.coins = 900
	GameState.inventory["iron_ore"] = 300
	GameState.inventory["bronze"] = 40
	GameState.inventory["silver"] = 60
	_ui.open(ShopUI.TAB_TECH)
	await _frames(2)
	var t: ShopTile = _ui._tiles["recipe:hand_drill"]
	_ui._on_tile_pressed(t.offer, t)
	await _frames(6)


## Печь: 12 штук загружено полторы минуты назад — одна готова, вторая наполовину.
func _load_furnace() -> void:
	BronzeFurnace.override_unix = 1_800_000_000
	GameState.house_storage["scrap"] = 12
	ShopService.craft("bronze", 12)
	BronzeFurnace.override_unix += BronzeFurnace.seconds_per_unit() * 3 / 2


func _s_furnace_busy() -> void:
	GameState.inventory["scrap"] = 14
	_load_furnace()
	await _open_bronze()


func _s_furnace_tile() -> void:
	_load_furnace()
	_ui.open(ShopUI.TAB_TECH)
	await _frames(2)


func _s_furnace_away() -> void:
	_load_furnace()
	GameState.house_is_indoors = false
	await _open_bronze()


func _s_furnace_load() -> void:
	GameState.inventory["scrap"] = 14
	GameState.house_storage["scrap"] = 23
	await _open_bronze()
	Settings.reduce_motion = false
	_ui._confirm_card()
	# Полёт лома идёт по настоящему времени (~0.9 с), кадры под xvfb быстрее.
	await get_tree().create_timer(1.05).timeout


## Ползунок карточки ищется по имени: тест не должен знать, как устроена строка.
func _set_qty(n: int) -> void:
	if _ui._card == null:
		return
	var s := _ui._card.find_child("CraftQtySlider", true, false) as HSlider
	if s != null:
		s.value = n


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(sname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(sname + ".png"))

extends Node
## test_screenshot_healing — не автотест, а инструмент глаз для лечения раунда 4:
## пузырь кровати с «здоровье +N%», пробуждение со вспышкой +HP, рюкзак с
## аптечкой (кнопка «Применить» и её подсказка), тост после аптечки, плитка и
## карточка аптечки в лавке, окно смерти с платой больнице (−5% монет; все причины
## смерти — tests/test_screenshot_death).
##
##   export XDG_DATA_HOME=$PWD/.godot/xdg
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_healing.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [снимок ...]
##
## Снимки: bed_tip sleep_wake backpack_medkit backpack_tip medkit_toast eat_toast
## shop_food shop_card death_card death_card_poor death_real.

var _out_dir := "/tmp/healing_shots"
var _only: Array[String] = []
var _main: Node2D
var _house: HouseSystem


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	for i in range(1, args.size()):
		_only.append(args[i])
	DirAccess.make_dir_recursive_absolute(_out_dir)
	GameState.world_seed = 4242
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
	_house = HouseSystem.instance
	_house.player = _main.player
	_house.hud = _main.hud

	await _scene("bed_tip", _s_bed_tip)
	await _scene("sleep_wake", _s_sleep_wake)
	await _scene("backpack_medkit", _s_backpack_medkit)
	await _scene("backpack_tip", _s_backpack_tip)
	await _scene("medkit_toast", _s_medkit_toast)
	await _scene("eat_toast", _s_eat_toast)
	await _scene("shop_food", _s_shop_food)
	await _scene("shop_card", _s_shop_card)
	await _scene("death_card", _s_death_card)
	await _scene("death_card_poor", _s_death_card_poor)
	await _scene("death_real", _s_death_real)
	print("test_screenshot_healing: снимки -> " + _out_dir)
	get_tree().quit(0)


func _scene(sname: String, fn: Callable) -> void:
	if not _only.is_empty() and not _only.has(sname):
		return
	_reset()
	await fn.call()
	await _frames(3)
	_shot(sname)
	await _cleanup()


func _reset() -> void:
	GameState.is_alive = true
	GameState.house_hatch_built = true
	GameState.coins = 640
	GameState.dollars = 2
	GameState.hp = GameState.get_max_hp() * 0.3
	GameState.hp_changed.emit(GameState.hp, GameState.get_max_hp())
	GameState.set_stamina(25.0)
	GameState.set_hunger(95.0)
	GameState.inventory.clear()
	GameState.inventory_changed.emit()
	GameState.house_tutorial_stage = 2
	GameState.era = "now"
	Tip.hide_all()


func _cleanup() -> void:
	Tip.hide_all()
	var shop := ShopUI.instance
	if shop != null and shop.is_open():
		shop.close()
	if _main.hud._inv_sheet.visible:
		_main.hud.close_inventory()
	var card: DeathWindow = _main.get_node("FeelDirector").card
	if card.is_open():
		card.close()
	if GameState.house_is_indoors:
		_house.exit_to_door()
	await _frames(3)


func _enter(room: String, point: String) -> void:
	_house.enter_house(room)
	var x := float(HouseRoomsConfig.points(room).get(point, {}).get("x", 0.5))
	_house._view.set_hero_x_fraction(x)


# --- сон --------------------------------------------------------------------

func _s_bed_tip() -> void:
	_enter("bedroom", "bed")
	await _frames(4)
	Tip.show_now(_house._view._hotspot_buttons[0])


func _s_sleep_wake() -> void:
	_enter("bedroom", "bed")
	await _frames(2)
	_house._view.trigger_point_button("bed")
	await _frames(2)
	_house._finish_sleep_sequence()
	# числа над полосками живут 0.9 с — снимаем сразу (кадры под xvfb долгие)
	await _frames(1)
	_shot("sleep_wake_flash")
	await _frames(8)


# --- рюкзак ---------------------------------------------------------------

func _pack() -> void:
	GameState.inventory = {"medkit": 2, "food_bar": 3, "iron_ore": 12, "silver": 2, "coal": 5}
	GameState.inventory_changed.emit()
	_main.hud.open_inventory()
	await _frames(3)
	_main.hud._inv_sheet._slot_buttons["medkit"].pressed.emit()
	await _frames(2)


func _s_backpack_medkit() -> void:
	await _pack()


func _s_backpack_tip() -> void:
	await _pack()
	Tip.show_now(_main.hud._inv_sheet._eat_btn)


func _s_medkit_toast() -> void:
	await _pack()
	_main.hud._inv_sheet._eat_btn.pressed.emit()
	await _frames(4)


func _s_eat_toast() -> void:
	GameState.set_hunger(40.0)
	GameState.inventory = {"food_bar": 3}
	GameState.inventory_changed.emit()
	_main.hud._eat_from_inventory("food_bar")
	await _frames(4)


# --- лавка ------------------------------------------------------------------

func _s_shop_food() -> void:
	_enter("hall", "front_door")
	await _frames(2)
	ShopUI.instance.open(ShopUI.TAB_FOOD)
	await _frames(4)


func _s_shop_card() -> void:
	await _s_shop_food()
	var ui := ShopUI.instance
	var t: ShopTile = ui._tiles["good:coins:medkit"]
	ui._on_tile_pressed(t.offer, t)
	await _frames(8)


# --- смерть -----------------------------------------------------------------

func _death_report(coins_before: int) -> Dictionary:
	GameState.inventory.clear()
	GameState.add_item("iron_ore", 14)
	GameState.add_item("silver", 6)
	GameState.add_item("ruby", 1)
	GameState.add_item("medkit", 1)
	GameState.max_depth_reached = maxi(GameState.max_depth_reached, 640)
	GameState.coins = coins_before
	var fee := Healing.death_fee_for(coins_before)
	GameState.coins -= fee
	return DeathWindow.build_report(GameState.inventory.duplicate(), 410, DeathCause.make("fall", {"cells": 47}), fee)


func _s_death_card() -> void:
	var card: DeathWindow = _main.get_node("FeelDirector").card
	card.open(_death_report(4280))
	await _frames(14)


func _s_death_card_poor() -> void:
	var card: DeathWindow = _main.get_node("FeelDirector").card
	card.open(_death_report(70))
	await _frames(6)
	Tip.show_now(card.find_child("Hospital", true, false))


## Настоящая смерть в игре: урон → респавн дома → окно смерти режиссёра
## «ощущений» (весь путь, без ручного build_report).
func _s_death_real() -> void:
	StoryState.set_flag("gold_sold", true)
	GameState.coins = 900
	GameState.inventory = {"iron_ore": 9, "silver": 3, "food_bar": 1}
	GameState.inventory_changed.emit()
	GameState.player_depth = 30
	GameState.take_damage(9999.0, "fall")
	var card: DeathWindow = _main.get_node("FeelDirector").card
	for _i in range(40):
		if card.is_open():
			break
		await _wait(0.25)
	await _frames(10)
	print("death_real: монет %d, карточка %s" % [GameState.coins, card.is_open()])


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

extends Node
## test_screenshot_house — не автотест, а инструмент глаз: поднимает main.tscn и
## снимает экраны дома: пузыри-подсказки, принудительные окна обучения, сон,
## доставку еды, склад (пустой/полный/вдали от мастерской/окно количества).
## Нужен настоящий рендер; окно лучше брать вдвое крупнее:
##
##   export XDG_DATA_HOME=$PWD/.godot/xdg
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_house.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [снимок ...]
##
## Снимки: hall_door hall_delivery hall_exit bedroom workshop workshop_pick
## outdoor outdoor_rig forced_sleep forced_bar sleep_1 sleep_2 sleep_3 sleep_wake
## delivery_ring delivery_knock storage_empty storage_full storage_remote
## storage_qty storage_qty_limit storage_bignum storage_poor_bag header_low
## delivery_hall_pack door_package delivery_far knock_anim forced_tip bubble_tip storage_tip.
## Состояние выставляется только в памяти — на диск (user://) тест не пишет.

var _out_dir := "/tmp/house_shots"
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
	# Игрок «после онбординга»: режиссёр на старте ставит интро в очередь, пропускаем.
	var director = _main.get_node("StoryDirector")
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure", "workshop", "death",
			"backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2"]:
		StoryState.mark_seen(id)
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered"]:
		StoryState.set_flag(f)
	# Окно ежедневной награды — чужое и всплывает в «спокойный момент»: гасим сервис.
	var meta = _main.get_node_or_null("MetaService")
	if meta != null:
		meta.set_process(false)
		if meta.popup != null and meta.popup.is_open():
			meta.popup.close()
	for _i in range(6):
		if director.cutscene != null and director.cutscene.is_playing:
			director.cutscene.skip()
		await _wait(0.3)
	# После main: HUD при старте перечитывает настройки и сбрасывает флаг.
	Settings.reduce_motion = true
	_house = HouseSystem.instance
	_house.player = _main.player
	_house.hud = _main.hud

	await _scene("hall_door", _s_hall_door)
	await _scene("hall_delivery", _s_hall_delivery)
	await _scene("hall_exit", _s_hall_exit)
	await _scene("bedroom", _s_bedroom)
	await _scene("workshop", _s_workshop)
	await _scene("workshop_pick", _s_workshop_pick)
	await _scene("outdoor", _s_outdoor)
	await _scene("outdoor_rig", _s_outdoor_rig)
	await _scene("forced_sleep", _s_forced_sleep)
	await _scene("forced_bar", _s_forced_bar)
	await _scene("sleep_1", _s_sleep_1)
	await _scene("sleep_2", _s_sleep_2)
	await _scene("sleep_3", _s_sleep_3)
	await _scene("sleep_wake", _s_sleep_wake)
	await _scene("delivery_ring", _s_delivery_ring)
	await _scene("delivery_knock", _s_delivery_knock)
	await _scene("delivery_hall_pack", _s_delivery_hall_pack)
	await _scene("door_package", _s_door_package)
	await _scene("knock_anim", _s_knock_anim)
	await _scene("forced_tip", _s_forced_tip)
	await _scene("bubble_tip", _s_bubble_tip)
	await _scene("storage_tip", _s_storage_tip)
	await _scene("delivery_far", _s_delivery_far)
	await _scene("storage_empty", _s_storage_empty)
	await _scene("storage_full", _s_storage_full)
	await _scene("storage_remote", _s_storage_remote)
	await _scene("storage_qty", _s_storage_qty)
	await _scene("storage_bignum", _s_storage_bignum)
	await _scene("storage_poor_bag", _s_storage_poor_bag)
	await _scene("storage_qty_limit", _s_storage_qty_limit)
	await _scene("header_low", _s_header_low)
	print("test_screenshot_house: снимки -> " + _out_dir)
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
	# Не reset_progress(): он шлёт max_depth_changed(0), и режиссёр начинает сюжет заново.
	GameState.house_hatch_built = true
	GameState.coins = 340
	GameState.dollars = 2
	GameState.hp = GameState.get_max_hp()
	GameState.set_stamina(80.0)
	GameState.set_hunger(90.0)
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.house_food_at_door.clear()
	GameState.ad_daily_counts.clear()
	GameState.house_tutorial_stage = 2
	StoryState.mark_seen("workshop")
	GameState.era = "now"
	Tip.hide_all()


func _cleanup() -> void:
	Tip.hide_all()
	_house._pending.clear()
	_house._delivery_badge.reset()
	if _house._storage_view != null and _house._storage_view.visible:
		_house._storage_view.close_panel()
	if _house._prompt != null and _house._prompt.visible:
		_house._prompt.hide_prompt()
		_house._prompt_action = ""
	if _house._view.forced_mode() != "":
		_house._view.set_forced("")
	if _house._sleeping:
		_house._finish_sleep_sequence()
	if GameState.house_is_indoors:
		_house.exit_to_door()
	_house._view.close()
	await _frames(2)


func _px(room: String, point: String) -> float:
	return float(HouseRoomsConfig.points(room)[point].get("x", 0.5))


func _enter(room: String, point: String) -> void:
	_house.enter_house(room)
	_house._view.set_hero_x_fraction(_px(room, point))


# --- пузыри --------------------------------------------------------------

func _s_hall_door() -> void:
	_enter("hall", "front_door")


func _s_hall_delivery() -> void:
	HouseFood.deliver("food_buldak")
	HouseFood.deliver("food_bar", 2)
	_enter("hall", "front_door")


func _s_hall_exit() -> void:
	_enter("hall", "veranda_window")


func _s_bedroom() -> void:
	GameState.set_stamina(30.0)
	_enter("bedroom", "bed")


func _s_workshop() -> void:
	_enter("workshop", "workbench")
	_house._view.set_hero_x_fraction((_px("workshop", "workbench") + _px("workshop", "chest")) * 0.5)


func _s_workshop_pick() -> void:
	# Не clear_all(): режиссёр видит пустую память и начинает сюжет заново.
	GameState.story_seen.erase("workshop")
	_enter("workshop", "mops_wall")


func _s_outdoor() -> void:
	var door := HouseConfig.door_cell()
	_main.player.x = door.x + 0.5
	_main.player.y = 0.5
	await _frames(3)


func _s_outdoor_rig() -> void:
	var door := HouseConfig.door_cell()
	GameState.rig_parked_at = Vector2i(door.x, 0)
	_main.player.x = door.x + 0.5
	_main.player.y = 0.5
	await _frames(3)


# --- принудительные окна -----------------------------------------------------

func _s_forced_sleep() -> void:
	GameState.house_tutorial_stage = 0
	GameState.set_stamina(0.0)
	_house._start_forced_sleep()


func _s_forced_bar() -> void:
	GameState.house_tutorial_stage = 1
	_house._start_forced_bar()


# --- сон ------------------------------------------------------------------

func _s_sleep_1() -> void:
	GameState.set_stamina(20.0)
	_enter("bedroom", "bed")
	_house._view.trigger_point_button("bed")
	await _frames(2)


func _s_sleep_2() -> void:
	await _s_sleep_1()


	_house._view.call("debug_sleep_progress", 0.5)


func _s_sleep_3() -> void:
	await _s_sleep_1()
	_house._view.call("debug_sleep_progress", 0.9)


func _s_sleep_wake() -> void:
	await _s_sleep_1()
	_house._finish_sleep_sequence()
	await _frames(2)


# --- доставка ---------------------------------------------------------------

func _s_delivery_ring() -> void:
	_enter("hall", "front_door")
	HouseSystem.order_food("food_buldak")
	await _frames(2)


func _s_delivery_knock() -> void:
	_enter("hall", "front_door")
	HouseSystem.order_food("food_buldak")
	await _frames(2)
	_house.call("debug_deliver_now")
	await _frames(2)


func _s_delivery_hall_pack() -> void:
	_enter("hall", "front_door")
	HouseFood.deliver("food_buldak")
	_house._view.set_hero_x_fraction(_px("hall", "front_door") + 0.1)
	await _frames(3)


func _s_knock_anim() -> void:
	# Единственный снимок с движением: курьер у двери и удар (флаг «меньше движения» снят).
	Settings.reduce_motion = false
	_enter("hall", "front_door")
	_house._view.set_hero_x_fraction(_px("hall", "front_door") + 0.1)
	HouseSystem.order_food("food_buldak")
	await _frames(2)
	_house.call("debug_deliver_now")
	await _wait(0.75)
	_shot("knock_anim_a")
	await _wait(0.9)
	Settings.reduce_motion = true


func _s_bubble_tip() -> void:
	GameState.set_stamina(30.0)
	_enter("bedroom", "bed")
	await _frames(3)
	Tip.show_now(_house._view._hotspot_buttons[0])


func _s_storage_tip() -> void:
	_fill_storage()
	_enter("workshop", "chest")
	_house.open_storage()
	await _frames(3)
	Tip.show_now(_house._storage_view._tiles["store:iron_ore"])


func _s_forced_tip() -> void:
	GameState.house_tutorial_stage = 0
	GameState.set_stamina(0.0)
	_house._start_forced_sleep()
	await _wait(0.9)


func _s_door_package() -> void:
	HouseFood.deliver("food_buldak")
	var door := HouseConfig.door_cell()
	_main.player.x = door.x + 1.5
	_main.player.y = 0.5
	await _frames(3)


func _s_delivery_far() -> void:
	var door := HouseConfig.door_cell()
	_main.player.x = door.x - 4.0
	_main.player.y = 0.5
	HouseSystem.order_food("food_buldak")
	await _wait(2.2)


# --- склад ------------------------------------------------------------------

func _fill_storage() -> void:
	var ids := ["scrap", "iron_ore", "lead", "silver", "copper", "gold", "diamond", "peat", "coal", "bronze", "aluminium", "titanium"]
	for i in ids.size():
		GameState.house_storage[ids[i]] = 3 + i * 7


func _s_storage_empty() -> void:
	_enter("workshop", "chest")
	_house.open_storage()


func _s_storage_full() -> void:
	_fill_storage()
	GameState.inventory["iron_ore"] = 12
	GameState.inventory["peat"] = 5
	GameState.inventory["scrap"] = 40
	_enter("workshop", "chest")
	_house.open_storage()


func _s_storage_remote() -> void:
	_fill_storage()
	GameState.inventory["gold"] = 4
	_house.open_storage()


func _s_storage_qty() -> void:
	_fill_storage()
	GameState.inventory["iron_ore"] = 12
	_enter("workshop", "chest")
	_house.open_storage()
	await _frames(3)
	_house._storage_view.call("debug_open_qty", "iron_ore", true)


func _s_storage_bignum() -> void:
	GameState.house_storage["scrap"] = 1234567
	GameState.house_storage["iron_ore"] = 98765
	GameState.house_storage["lead"] = 9999
	GameState.house_storage["gold"] = 12
	GameState.inventory["peat"] = 99
	_enter("workshop", "chest")
	_house.open_storage()


func _s_storage_poor_bag() -> void:
	_fill_storage()
	for id in ["iron_ore", "lead", "silver", "copper", "gold", "scrap", "peat", "coal"]:
		GameState.inventory[id] = 99
	_enter("workshop", "chest")
	_house.open_storage()
	await _frames(3)
	_house._storage_view.call("debug_open_qty", "iron_ore", false)


func _s_storage_qty_limit() -> void:
	GameState.house_storage["iron_ore"] = 80
	GameState.inventory["scrap"] = 40
	_enter("workshop", "chest")
	_house.open_storage()
	await _frames(3)
	_house._storage_view.call("debug_open_qty", "iron_ore", true)


func _s_header_low() -> void:
	GameState.set_stamina(8.0)
	GameState.set_hunger(15.0)
	GameState.hp = 20.0
	_enter("hall", "door_workshop")


# ---------------------------------------------------------------------------

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(sname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(sname + ".png"))

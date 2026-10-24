extends Node
## test_screenshot_shop — не автотест, а инструмент глаз: снимает витрину в
## разных состояниях (вкладки, карточка покупки, продажа, пустой рюкзак,
## длинные числа, экипировка, прокрутка). Нужен настоящий рендер; окно лучше
## брать вдвое крупнее, чтобы текст и значки читались:
##
##   export XDG_DATA_HOME=$PWD/.godot/xdg
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_shop.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [сцена ...]
##
## Сцены: food picks tech sell sell_empty sell_remote premium equip equip_away
## card card_poor card_recipe bignum scroll sale_anim many new tip tech_locked drill
## card_info_open card_recipe_chip card_recipe_long card_info_long card_pulse
## (описание по тапу в карточке; card_pulse — «i» в разгаре пульсации).

var _out_dir := "/tmp/shop_shots"
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

	await _scene("food", _s_food)
	await _scene("picks", _s_picks)
	await _scene("tech", _s_tech)
	await _scene("sell", _s_sell)
	await _scene("sell_empty", _s_sell_empty)
	await _scene("sell_remote", _s_sell_remote)
	await _scene("premium", _s_premium)
	await _scene("equip", _s_equip)
	await _scene("equip_away", _s_equip_away)
	await _scene("card", _s_card)
	await _scene("card_poor", _s_card_poor)
	await _scene("card_recipe", _s_card_recipe)
	await _scene("bignum", _s_bignum)
	await _scene("scroll", _s_scroll)
	await _scene("many", _s_many)
	await _scene("sale_anim", _s_sale_anim)
	await _scene("new", _s_new)
	await _scene("tip", _s_tip)
	await _scene("tech_locked", _s_tech_locked)
	await _scene("drill", _s_drill)
	await _scene("card_info_open", _s_card_info_open)
	await _scene("card_recipe_chip", _s_card_recipe_chip)
	await _scene("card_recipe_long", _s_card_recipe_long)
	await _scene("card_info_long", _s_card_info_long)
	await _scene("card_pulse", _s_card_pulse)
	print("test_screenshot_shop: снимки -> " + _out_dir)
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
	GameState.house_is_indoors = true
	GameState.max_depth_reached = 0
	GameState.coins = 340
	GameState.dollars = 2
	GameState.inventory.clear()
	GameState.ad_daily_counts.clear()
	_ui._notice_panel.visible = false
	ShopCatalog.reload()


func _give_ore() -> void:
	GameState.inventory["scrap"] = 14
	GameState.inventory["iron_ore"] = 37
	GameState.inventory["lead"] = 9
	GameState.inventory["silver"] = 4
	GameState.inventory["copper"] = 12
	GameState.inventory["gold"] = 3
	GameState.inventory["diamond"] = 1
	GameState.inventory["peat"] = 22
	GameState.inventory["coal"] = 5
	GameState.inventory["bronze"] = 2


func _s_food() -> void:
	_ui.open(ShopUI.TAB_FOOD)


func _s_picks() -> void:
	GameState.coins = 1200
	GameState.grant_tool("iron_pickaxe")
	_ui.open(ShopUI.TAB_PICKS)


func _s_tech() -> void:
	GameState.max_depth_reached = 1200
	GameState.coins = 9000
	GameState.inventory["iron_ore"] = 300
	GameState.inventory["bronze"] = 40
	GameState.inventory["silver"] = 60
	GameState.inventory["scrap"] = 3
	_ui.open(ShopUI.TAB_TECH)


func _s_sell() -> void:
	_give_ore()
	_ui.open(ShopUI.TAB_SELL)
	await _frames(2)
	_ui._on_tile_pressed(_ui._tiles["sell:lead"].offer, _ui._tiles["sell:lead"])


func _s_sell_empty() -> void:
	_ui.open(ShopUI.TAB_SELL)


func _s_sell_remote() -> void:
	_give_ore()
	GameState.house_is_indoors = false
	GameState.next_sale_doubled = true
	_ui.open(ShopUI.TAB_SELL)


func _s_premium() -> void:
	_ui.open(ShopUI.SCREEN_PREMIUM)


func _s_equip() -> void:
	GameState.grant_tool("iron_pickaxe")
	GameState.grant_tool("titanium_pickaxe")
	GameState.grant_gear("backpack")
	GameState.grant_gear("backpack_plus")
	_ui.open(ShopUI.SCREEN_EQUIP)


func _s_equip_away() -> void:
	GameState.house_is_indoors = false
	GameState.grant_tool("iron_pickaxe")
	_ui.open(ShopUI.SCREEN_EQUIP)


func _s_card() -> void:
	GameState.coins = 1200
	_ui.open(ShopUI.TAB_PICKS)
	await _frames(2)
	var t: ShopTile = _ui._tiles["tool:iron_pickaxe"]
	_ui._on_tile_pressed(t.offer, t)
	await _frames(6)


func _s_card_poor() -> void:
	GameState.coins = 1200
	_ui.open(ShopUI.TAB_PICKS)
	await _frames(2)
	var t: ShopTile = _ui._tiles["gear:jetpack_top"]
	_ui._on_tile_pressed(t.offer, t)
	await _frames(4)


func _s_card_recipe() -> void:
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


func _s_bignum() -> void:
	GameState.coins = 1234567
	GameState.dollars = 12345
	GameState.inventory["gold"] = 99
	GameState.inventory["diamond"] = 99
	GameState.inventory["uranium"] = 99
	GameState.inventory["iron_ore"] = 99
	_ui.open(ShopUI.TAB_SELL)


func _s_scroll() -> void:
	GameState.coins = 40
	_ui.open(ShopUI.TAB_PICKS)
	await _frames(2)
	_ui._scroll.scroll_vertical = 200


func _s_many() -> void:
	_give_ore()
	for id in ["nickel", "platinum", "titanium", "lithium", "mercury", "uranium", "ruby", "emerald", "aluminium"]:
		GameState.inventory[id] = 7
	GameState.inventory["geocrystal"] = 2
	GameState.inventory["obsidian"] = 5
	GameState.inventory["food_bar"] = 3
	_ui.open(ShopUI.TAB_SELL)
	await _frames(2)
	_ui._scroll.scroll_vertical = 100


func _s_sale_anim() -> void:
	Settings.reduce_motion = false
	_give_ore()
	GameState.next_sale_doubled = true
	_ui.open(ShopUI.TAB_SELL)
	await _frames(3)
	_ui._on_sell_pressed()
	await get_tree().create_timer(0.42).timeout
	Settings.reduce_motion = true


func _s_new() -> void:
	ShopItems.seed_seen()
	GameState.max_depth_reached = 150
	_ui.open(ShopUI.TAB_TECH)
	await _frames(2)
	_ui._set_tab(ShopUI.TAB_FOOD, false)
	GameState.max_depth_reached = 150
	_ui._render()


func _s_tip() -> void:
	GameState.coins = 1200
	_ui.open(ShopUI.TAB_PICKS)
	await _frames(2)
	Tip.show_now(_ui._tiles["tool:iron_pickaxe"])
	await _frames(2)


func _s_tech_locked() -> void:
	_ui.open(ShopUI.TAB_TECH)


func _s_drill() -> void:
	GameState.grant_tool("drill_rig")
	GameState.drill_rig_tier = 1
	GameState.coins = 60000
	GameState.max_depth_reached = 2000
	_ui.open(ShopUI.TAB_TECH)


## Узлы карточки, привязанные к описанию по тапу (Tip.bind_tap), в порядке обхода.
func _tap_targets() -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [_ui._card]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and n.has_meta(Tip.TAP_META):
			out.append(n)
		for c in n.get_children():
			stack.push_back(c)
	out.reverse()
	return out


func _s_card_info_open() -> void:
	await _s_card()
	Tip.tap_toggle(_tap_targets()[0])
	await _frames(3)


func _s_card_recipe_chip() -> void:
	await _s_card_recipe()
	Tip.tap_toggle(_tap_targets()[2])
	await _frames(3)


## Рецепт с самыми длинными названиями материалов и огромными числами: берём
## настоящее предложение бура и подменяем материалы на предметы с длинными именами.
func _s_card_recipe_long() -> void:
	GameState.max_depth_reached = 1200
	GameState.coins = 900
	_ui.open(ShopUI.TAB_TECH)
	await _frames(2)
	var t: ShopTile = _ui._tiles["recipe:hand_drill"]
	var o: Dictionary = t.offer.duplicate(true)
	o["title"] = "Топливный блок (уголь)"
	o["body"] = "Горит дольше торфяного брикета и греет ровнее: хватает на целую смену под землёй."
	var inputs: Array = []
	for id in ["geocrystal", "moth_dust", "divine_heart", "energy_bar"]:
		inputs.append({"id": id, "icon": ShopArt.item_icon(id), "have": 1234567, "need": 2500000})
	o["inputs"] = inputs
	_ui._on_tile_pressed(o, t)
	await _frames(6)
	var chips := _tap_targets()
	Tip.tap_toggle(chips[3])
	await _frames(3)


## Длинные название и описание товара: панель переносит строки и остаётся в окне.
func _s_card_info_long() -> void:
	GameState.max_depth_reached = 1200
	GameState.coins = 900
	_ui.open(ShopUI.TAB_TECH)
	await _frames(2)
	var t: ShopTile = _ui._tiles["recipe:hand_drill"]
	var o: Dictionary = t.offer.duplicate(true)
	o["title"] = "Топливный блок из каменного угля (большой)"
	o["body"] = "Горит дольше торфяного брикета и греет ровнее: хватает на целую смену под землёй, даже в лаве."
	o["extra"] = "Не хватает материалов: Геотермальный кристалл"
	_ui._on_tile_pressed(o, t)
	await _frames(6)
	Tip.tap_toggle(_tap_targets()[0])
	await _frames(3)


## Первое знакомство: «i» пульсирует, описание ещё закрыто.
func _s_card_pulse() -> void:
	Settings.reduce_motion = false
	GameState.ext_set(ShopUI.CARD_INFO_KEY, {})
	GameState.coins = 1200
	_ui.open(ShopUI.TAB_PICKS)
	await _frames(2)
	var t: ShopTile = _ui._tiles["tool:iron_pickaxe"]
	_ui._on_tile_pressed(t.offer, t)
	await get_tree().create_timer(0.58).timeout
	Settings.reduce_motion = true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(sname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(sname + ".png"))

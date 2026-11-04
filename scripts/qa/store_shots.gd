class_name StoreShots
extends Node
## Постановочные кадры для стора (product-polish, раунд 6). По запросу игра сама ставит сцену:
##   веб:   index.html?shot=<id>          — tools/store_screens.js (Playwright) снимает 1290x2796 и 1242x2208
##   натив: godot --path . -- shot=<id>   — tests/test_screenshot_store: те же кадры в 224x480, чтобы посмотреть
## Кадры (SHOTS): home — дом и огород; dig — копка киркой на глубине ~800 среди руды; shop — лавка;
## museum — музей с находками; combat — бой на глубине 4500. Без запроса attach ничего не делает.
##
## Страница узнаёт о готовности через RaskopkiShell.shotReady = id и просит следующий кадр
## вызовом RaskopkiQA.shot('shop') — одна загрузка на все кадры. Пока постановка активна,
## сейв не пишется (SaveSystem.readonly): подставной прогресс не должен попасть игроку.

signal shot_ready(id: String)

const SHOTS := ["home", "dig", "shop", "museum", "combat"]
const SHAFT_X := 16

var main: Node2D
var current := ""
var _js_cb = null   # JavaScriptObject колбэка: без ссылки его соберёт сборщик
var _busy := false


static func attach(host: Node2D, forced_id: String = "") -> StoreShots:
	var id := forced_id if not forced_id.is_empty() else requested_id()
	if id.is_empty():
		return null
	var s := StoreShots.new()
	s.name = "StoreShots"
	s.main = host
	host.add_child(s)
	s.show_shot(id)
	return s


## id кадра из аргументов запуска (shot=<id> после «--») или из адреса страницы (?shot=<id>).
static func requested_id() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			return a.substr(5)
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("new URLSearchParams(location.search).get('shot') || ''")
		return String(v) if v != null else ""
	return ""


func _ready() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.RaskopkiQA = window.RaskopkiQA || {}")
		var qa = JavaScriptBridge.get_interface("RaskopkiQA")
		if qa != null:
			_js_cb = JavaScriptBridge.create_callback(_on_js_shot)
			qa.shot = _js_cb


func _on_js_shot(args: Array) -> void:
	if args.is_empty():
		return
	show_shot(String(args[0]))


func show_shot(id: String) -> void:
	if _busy or not SHOTS.has(id):
		return
	_busy = true
	current = id
	SaveSystem.readonly = true
	_prepare_common()
	await _frames(2)
	_close_all()
	await _frames(1)
	match id:
		"home":
			_scene_home()
		"dig":
			_scene_dig()
		"shop":
			_scene_shop()
		"museum":
			_scene_museum()
		"combat":
			_scene_combat()
	# Подставной прогресс будит тосты, баннер задания и подсказку инструмента; режиссёр сюжета и
	# объявления снаряжения приходят не сразу — ждём, потом убираем всё разом.
	await get_tree().create_timer(0.6).timeout
	if main.hud != null:
		main.hud.set_objective("")   # режиссёр ставит баннер снова только при смене задания
		main.hud.call("_hide_toast")
	Tip.hide_all()
	await _frames(1)
	_busy = false
	_announce(id)


# ---------------------------------------------------------------------------

## Общая подготовка: сюжет «уже пройден», окна мета-слоя не всплывают, полоски видны,
## правдоподобный прогресс игрока середины игры.
func _prepare_common() -> void:
	for sid in StoryData.scene_ids():
		StoryState.mark_seen(String(sid))
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered", "gold_sold"]:
		StoryState.set_flag(f)
	var consent = main.get_node_or_null("ConsentDialog")   # первый запуск в чистом браузере: окно согласия
	if consent != null and consent.is_open():
		consent.choose(false)
	var meta = main.get_node_or_null("MetaService")
	if meta != null:
		meta.set_process(false)
		if meta.popup != null and meta.popup.is_open():
			meta.popup.close()
		if meta.toast != null:
			meta.toast.visible = false
	var hints = main.get_node_or_null("HintDirector")
	if hints != null:
		hints.set_process(false)
	GameState.is_alive = true
	GameState.hp = GameState.get_max_hp()
	GameState.set_hunger(82.0)
	GameState.set_stamina(74.0)
	GameState.coins = 2480
	GameState.dollars = 12
	GameState.level = 7
	GameState.xp_changed.emit(GameState.xp, GameState.level)   # портрет HUD перечитывает уровень
	GameState.max_depth_reached = maxi(GameState.max_depth_reached, 820)
	GameState.inventory.clear()
	for id in ["iron_ore", "copper", "coal", "gold", "silver"]:
		GameState.inventory[id] = 2 + id.length() % 4
	GameState.inventory_changed.emit()
	if main.hud != null:
		main.hud.set_gauges_visible(true)
		main.hud.set_objective("")   # баннер сюжетного задания; режиссёр ставит его снова только при смене
		main.hud.call("_hide_toast")
		main.hud.call("_set_mode", "stick")


func _close_all() -> void:
	var hud = main.hud
	if hud != null:
		hud.close_inventory()
		hud.close_settings()
		hud.call("close_more_menu")
	if ShopUI.instance != null and ShopUI.instance.is_open():
		ShopUI.instance.close()
	if ProgressScreen.is_open():
		ProgressScreen.close_screen()
	if WellReport.is_open():
		WellReport.instance().close()
	var house := HouseSystem.instance
	if house != null and GameState.house_is_indoors:
		house.exit_to_door()
	var d = CombatService.director
	if d != null:
		d.monsters.clear()
		d.set_process(true)
	_release_keys()


func _scene_home() -> void:
	main.player.teleport_home()
	main.player.facing = 1
	DayCycle.set_hour(10.5)


func _scene_dig() -> void:
	var depth := 800
	GameState.max_depth_reached = maxi(GameState.max_depth_reached, depth + 10)   # без веховых наград
	GameState.grant_tool("iron_pickaxe")
	GameState.set_current_tool("iron_pickaxe")
	_carve(depth - 10, depth, 1)   # шахта до героя; под ногами порода — есть что копать
	_place(float(depth) + 0.5)
	# Копает вниз сам: нажатая «S» идёт обычным путём клавиатуры HUD, кадр ловит замах.
	var ev := InputEventKey.new()
	ev.keycode = KEY_S
	ev.physical_keycode = KEY_S
	ev.pressed = true
	Input.parse_input_event(ev)


func _scene_shop() -> void:
	main.player.teleport_home()
	ShopUI.open_shop()


func _scene_museum() -> void:
	main.player.teleport_home()
	for a in ["antiquity_1", "antiquity_2", "antiquity_3", "antiquity_4", "mystic_1", "mystic_2", "occult_1", "legends_3"]:
		if not GameState.collected_artifacts.has(a):
			GameState.collected_artifacts.append(a)
	ProgressScreen.open(ProgressScreen.TAB_MUSEUM)


func _scene_combat() -> void:
	var depth := 4500
	GameState.max_depth_reached = maxi(GameState.max_depth_reached, depth + 10)   # без веховых наград
	GameState.grant_tool("titanium_pickaxe")
	GameState.set_current_tool("titanium_pickaxe")
	for id in ["helm_t2", "armor_t2", "blade_t2", "shield_t1"]:
		CombatService.give(id)
		CombatService.equip(id)
	TechState.set_suit(Heat.suit_tiers().size())   # лучший жарозащитный костюм: без капель урона от жары в кадре
	GameState.hp = GameState.get_max_hp()
	_carve(depth - 2, depth + 1, 5)
	_place(float(depth) + 0.5)
	main.player.facing = 1
	var d = CombatService.director
	if d == null:
		return
	d.monsters.clear()
	d.swing_cd = 99.0
	d.iframes = 99.0   # до появления монстров: ни одного удара по герою в кадре
	var ground: Array = []
	for id in CombatData.monster_ids():
		var def := CombatData.monster(String(id))
		if String(def.get("behavior", "")) in ["crawler", "jumper"]:   # не засадник: тот прячется в породе
			ground.append(String(id))
	if ground.is_empty():
		ground = CombatData.monster_ids()
	# Два монстра в кадре: справа замахивается, слева подходит (экран — 7 клеток вокруг героя).
	var xs := [float(SHAFT_X) + 2.6, float(SHAFT_X) - 2.4]
	for i in range(mini(2, ground.size())):
		var m = d.spawn({"id": ground[i], "x": xs[i], "y": float(depth), "group": 1, "emerge": Vector2.ZERO})
		if m != null:
			m.state = "windup" if i == 0 else "chase"
			m.telegraph = i == 0
			m.t = 0.1
			m.vx = 0.0
			m.facing = -1 if i == 0 else 1
			m.anim_t = 0.2
	d.set_process(false)   # монстры замирают в позах — кадр стабилен


# ---------------------------------------------------------------------------

## Вертикальная шахта шириной 1+2*half вокруг SHAFT_X от y0 до y1 включительно, открытая в тумане.
func _carve(y0: int, y1: int, half: int) -> void:
	for y in range(y0, y1 + 1):
		for dx in range(-half, half + 1):
			main.world.dig_cell(SHAFT_X + dx, y)


func _place(y: float) -> void:
	var p = main.player
	p.x = float(SHAFT_X) + 0.5
	p.y = y
	p.vx = 0.0
	p.vy = 0.0
	p.on_ground = true
	p.digging = null
	# Объявления «открыт ранец/джетпак/бурмобиль» по глубине — не на постановочном кадре.
	p._announced_backpack = true
	p._announced_jetpack = true
	p._announced_rig = true
	main.fog.reveal_around(p.x, p.y, 9, 9)


func _release_keys() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_S
	ev.physical_keycode = KEY_S
	ev.pressed = false
	Input.parse_input_event(ev)


func _announce(id: String) -> void:
	shot_ready.emit(id)
	print("StoreShots: готов кадр " + id)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.RaskopkiShell && (window.RaskopkiShell.shotReady = '%s')" % id)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

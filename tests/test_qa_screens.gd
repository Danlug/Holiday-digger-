extends Node
## test_qa_screens — сквозной QA-проход скриншотами всех экранов игры (не автотест):
## запускает настоящую main-сцену и по очереди снимает ключевые панели на реальном портретном
## вьюпорте 224x480 — HUD на поверхности и под землёй, настройки и «О игре», меню «•••», рюкзак
## (пустой, полный, окно выброса), лавка по вкладкам, герой/навыки/музей/рекорды, хаб наград,
## задания дня, стрик новичка, техника, отчёт скважины, проекты, журнал, снаряжение, окно смерти,
## согласие на аналитику, дом и склад, тосты и диалог; с аргументом safe — те же экраны с смоделированной
## безопасной зоной телефона (вырез 24 сверху, полоска 12 снизу). Смотреть на каждый кадр (Read)
## и чинить перекрытия/обрезку — так проверяется визуал (product-polish, раунд 6).
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_qa_screens.tscn --rendering-driver opengl3 --resolution 448x960 -- /каталог [safe]
##
## Каталог для сохранения — аргумент после "--", по умолчанию /tmp/qa_screens; слово safe — тот же проход
## с смоделированными безопасными зонами телефона (вырез 24 сверху, полоска «домой» 12 снизу), снимки safe_*.

var _out_dir := "/tmp/qa_screens"
var _main: Node2D
var _hud: Control
var _n := 0
var _safe := false   # режим «safe»: вырез 24 сверху и полоска «домой» 12 снизу с самого старта


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "safe":
			_safe = true
		else:
			_out_dir = a
	if _safe:
		# Экраны читают безопасную зону при сборке (как на телефоне с самого запуска), поэтому
		# вырез моделируется ДО main.tscn; снимки получают префикс safe_.
		HudSafeArea.debug_top = 24.0
		HudSafeArea.debug_bottom = 12.0
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)

	GameState.world_seed = 20260101
	for sid in StoryData.scene_ids():
		StoryState.mark_seen(String(sid))
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered", "gold_sold"]:
		StoryState.set_flag(f)

	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(2)
	_hud = _main.hud
	# Окно подарка дня — чужое, всплывает «в спокойный момент» и закрыло бы кадры.
	var meta = _main.get_node_or_null("MetaService")
	if meta != null:
		meta.set_process(false)
		if meta.popup != null and meta.popup.is_open():
			meta.popup.close()
		if meta.toast != null:
			meta.toast.visible = false   # тосты достижений от подставного прогресса закрывали бы шапки окон
	if WellReport.is_open():
		WellReport.instance().close()
	Settings.reduce_motion = true
	_hud.set_gauges_visible(true)
	GameState.coins = 1340
	GameState.dollars = 12
	GameState.level = 5
	await _frames(2)

	await _shot("hud_surface")
	await _scene_settings()
	await _scene_menu()
	await _scene_backpack()
	await _scene_shop()
	await _scene_hero()
	await _scene_meta()
	await _scene_tech()
	await _scene_guidance_journal()
	await _scene_equipment()
	await _scene_death()
	await _scene_consent()
	await _scene_house()
	await _scene_underground()
	await _scene_toasts()
	await _scene_dialogue()

	print("test_qa_screens: %d снимков сохранены -> %s" % [_n, _out_dir])
	get_tree().quit(0)


# ---------------------------------------------------------------------------

func _scene_settings() -> void:
	_hud.open_settings()
	await _frames(2)
	await _shot("settings")
	var sheet: SettingsSheet = _hud._settings_sheet
	var scroll: ScrollContainer = null
	for c in sheet.find_children("*", "ScrollContainer", true, false):
		scroll = c
		break
	if scroll != null:
		scroll.scroll_vertical = 10000
		await _frames(2)
		await _shot("settings_bottom")
	sheet.open_about()
	await _frames(2)
	await _shot("about")
	_hud.close_settings()
	await _frames(2)


func _scene_menu() -> void:
	_hud.call("_toggle_more_menu")
	await _frames(2)
	await _shot("menu_more")
	_hud.call("close_more_menu")
	await _frames(2)


func _scene_backpack() -> void:
	GameState.inventory.clear()
	GameState.inventory_changed.emit()
	_hud.open_inventory()
	await _frames(2)
	await _shot("backpack_empty")
	for id in ["iron_ore", "copper", "gold", "obsidian", "coal", "silver", "diamond", "food_soup", "ruby"]:
		GameState.inventory[id] = 1 + (id.length() % 7)
	GameState.inventory_changed.emit()
	_hud._render_inventory()
	await _frames(2)
	await _shot("backpack_filled")
	_hud._open_drop("iron_ore", 5)
	await _frames(2)
	await _shot("backpack_drop")
	_hud._close_drop()
	_hud.close_inventory()
	await _frames(2)


func _scene_shop() -> void:
	ShopUI.open_shop()
	await _frames(2)
	if ShopUI.instance == null:
		return
	await _shot("shop_food")
	for tab in [ShopUI.TAB_SELL, ShopUI.TAB_TECH, ShopUI.TAB_PICKS]:
		ShopUI.instance._set_tab(tab, false)
		await _frames(2)
		await _shot("shop_" + tab)
	ShopUI.instance.close()
	await _frames(2)


func _scene_hero() -> void:
	ProgressScreen.open(ProgressScreen.TAB_HERO)
	await _frames(2)
	var s := ProgressScreen.instance()
	if s == null:
		return
	await _shot("hero")
	s.open_tab(ProgressScreen.TAB_PROGRESS)
	await _frames(2)
	await _shot("hero_skills")
	GameState.collected_artifacts.clear()
	s.open_tab(ProgressScreen.TAB_MUSEUM)
	await _frames(2)
	await _shot("museum_empty")
	for a in ["antiquity_1", "antiquity_2", "mystic_1", "legends_3"]:
		if not GameState.collected_artifacts.has(a):
			GameState.collected_artifacts.append(a)
	s.open_tab(ProgressScreen.TAB_HERO)
	s.open_tab(ProgressScreen.TAB_MUSEUM)
	await _frames(2)
	await _shot("museum_found")
	s.open_tab(ProgressScreen.TAB_RECORDS)
	await _frames(2)
	await _shot("hero_records")
	ProgressScreen.close_screen()
	await _frames(2)


func _scene_meta() -> void:
	var svc = _main.get_node_or_null("MetaService")
	if svc == null:
		return
	svc.open_hub("tasks")
	await _frames(2)
	await _shot("hub_tasks")
	svc.hub.close()
	await _frames(2)
	svc.open_hub("ach")
	await _frames(2)
	await _shot("hub_achievements")
	svc.hub.close()
	await _frames(2)
	svc.open_hub("road")
	await _frames(2)
	await _shot("hub_road")
	if svc.hub != null and svc.hub.has_method("close"):
		svc.hub.close()
	await _frames(2)
	svc.open_daily()
	await _frames(2)
	await _shot("daily_gift")
	if svc.popup != null and svc.popup.is_open():
		svc.popup.close()
	await _frames(2)
	svc.open_tasks()
	await _frames(2)
	await _shot("daily_tasks")
	if svc.tasks != null and svc.tasks.has_method("close"):
		svc.tasks.close()
	await _frames(2)
	var nb = _main.get_node_or_null("NewbieStreakService")
	if nb != null:
		nb.open()
		await _frames(2)
		await _shot("newbie_streak")
		if nb.panel != null and nb.panel.has_method("close"):
			nb.panel.close()
		await _frames(2)


func _scene_tech() -> void:
	GameState.max_depth_reached = 800
	GameState.well_level = 2
	for tab in [TechScreen.TAB_TANK, TechScreen.TAB_SUIT, TechScreen.TAB_WELL]:
		TechScreen.open(tab, tab == TechScreen.TAB_TANK)
		await _frames(2)
		await _shot("tech_" + tab)
	TechScreen.close_screen()
	await _frames(2)
	GameState.well_last_collect_unix = int(Time.get_unix_time_from_system()) - 7 * 3600 - 1260
	var rep := IdleWell.collect()
	var w := WellReport.instance()
	if w != null and not rep.is_empty():
		w.show_report(rep)
		await _frames(8)
		await _shot("well_report")
		w.close()
		await _frames(2)


func _scene_guidance_journal() -> void:
	ProjectsScreen.open_for("hand_drill")
	await _frames(2)
	await _shot("projects")
	var ps := ProjectsScreen.instance()
	if ps != null and ps.is_open():
		ps.close()
	await _frames(2)
	var d = _main.get_node_or_null("MechDirector")
	if d != null and d.journal != null:
		d.journal.open("mastery")
		await _frames(2)
		await _shot("journal")
		d.journal.close()
		await _frames(2)


func _scene_equipment() -> void:
	var d = CombatService.director
	if d == null:
		return
	GameState.house_is_indoors = true
	d.open_equipment()
	await _frames(2)
	await _shot("equipment")
	GameState.house_is_indoors = false
	if d.equip_screen != null:
		d.equip_screen.close()
	await _frames(2)


func _scene_death() -> void:
	var fd = _main.get_node_or_null("FeelDirector")
	if fd == null or fd.card == null:
		return
	var cause := DeathCause.make("fall", {"cells": 9})
	var rep := DeathWindow.build_report({"gold": 3, "iron_ore": 12, "diamond": 1}, 412, cause, 180)
	fd.card.open(rep)
	await _frames(4)
	await _shot("death_window")
	fd.card.close()
	await _frames(2)


func _scene_consent() -> void:
	var d := ConsentDialog.open_on(_main)
	await _frames(2)
	await _shot("consent")
	if d != null:
		d.show_details(true)
		await _frames(2)
		await _shot("consent_details")
		d.choose(false)
	await _frames(2)


func _scene_house() -> void:
	var house := HouseSystem.instance
	if house == null:
		return
	if house.player == null:
		house.player = _main.player
	if house.hud == null:
		house.hud = _hud
	house.enter_house("hall")
	await _frames(3)
	await _shot("house_hall")
	house.enter_house("bedroom")
	await _frames(3)
	await _shot("house_bedroom")
	GameState.house_storage.clear()
	house.open_storage()
	await _frames(2)
	await _shot("storage_empty")
	house._storage_view.close_panel()
	await _frames(2)
	for id in ["iron_ore", "copper", "coal", "gold", "silver"]:
		HouseStorage.store_directly(id, 3 + id.length())
	house.open_storage()
	await _frames(2)
	await _shot("storage_filled")
	house._storage_view.close_panel()
	await _frames(2)
	house.exit_to_door()
	await _frames(3)


func _scene_underground() -> void:
	var p = _main.player
	var w = _main.world
	for dy in range(-2, 3):
		for dx in range(-1, 2):
			w.dig_cell(16 + dx, 300 + dy)
	p.x = 16.5
	p.y = 300.5
	p.vx = 0.0
	p.vy = 0.0
	await _frames(6)
	await _shot("hud_underground")
	_hud.call("_set_mode", "arrows")
	await _frames(2)
	await _shot("hud_arrows")
	_hud.call("_set_mode", "hold")
	await _frames(2)
	await _shot("hud_hold")
	_hud.call("_set_mode", "stick")
	p.teleport_home()
	await _frames(3)


func _scene_toasts() -> void:
	_hud.toast("Готово.")
	await _frames(2)
	await _shot("toast_short")
	_hud.toast(StoryText.get_text("workshop.toast_pickaxe"))
	await _frames(2)
	await _shot("toast_long_real")
	_hud.toast("Это очень длинный тестовый текст тоста, специально составленный так, чтобы проверить перенос по словам и то, как панель тоста растягивается вверх, когда строка занимает много строк подряд и грозит вылезти за пределы видимой области экрана на портретном вьюпорте самого маленького из поддерживаемых размеров.")
	await _frames(2)
	await _shot("toast_stress")
	_hud.call("_hide_toast")
	await _frames(2)


func _scene_dialogue() -> void:
	var cs = _main.find_child("CutscenePlayer", true, false)
	if cs == null:
		return
	cs._root.visible = true
	cs._layout()
	cs._run_beat({"t": "narr", "text": "intro_boy.n3"})
	cs._line.visible_ratio = 1.0
	await _frames(2)
	await _shot("dialogue_longest_real")
	cs._run_beat({"t": "say", "who": "boy", "text": "intro_boy.s3"})
	cs._line.visible_ratio = 1.0
	await _frames(2)
	await _shot("dialogue_short_real")
	cs._root.visible = false
	await _frames(2)


# ---------------------------------------------------------------------------

func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join("%s%02d_%s.png" % ["safe_" if _safe else "", _n, name]))

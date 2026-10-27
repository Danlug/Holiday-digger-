extends Node
## test_hud_layers — порядок слоёв экрана: мир < HUD < окна < подсказки (UiLayers, ГДД §16).
##
## Владелец 26.10 (скриншот с телефона): «штука с буром светится поверх других менюшек» —
## трекер проекта «Ручной бур» (ProjectTracker, свой CanvasLayer 2) рисовался над открытым
## рюкзаком: шторки HUD жили в самом HUD на слое 1, и любой виджет со своим слоем (бак бура,
## шкала азарта, курьер, кнопка «Тест») был выше них. Теперь окна HUD — на слое HUD_WINDOWS.
##
## Настоящая main.tscn, все HUD-виджеты разом на экране. Открываем по очереди каждое окно и
## проверяем: (1) по порядку отрисовки (CanvasLayer.layer, затем z_index и порядок в дереве) —
## окно выше КАЖДОГО элемента HUD-слоёв; (2) по пальцу — точка виджета, накрытая окном, попадает
## в окно, а не в виджет; (3) виджеты остались над миром. Плюс контроль чувствительности: окна
## HUD, опущенные на слой HUD, снова проигрывают трекеру — проверка это видит.
##
## Запуск:  godot --headless --path . res://tests/test_hud_layers.tscn

const SEED := 4242

## Слои HUD и «над миром» (мир < они ≤ UiLayers.HUD_TOP). "HUD" — безымянный слой самого HUD (main.gd).
const WIDGET_LAYERS := ["HUD", "HeatHaze", "ProjectTrackerLayer", "StreakLayer", "TechHudLayer", "CombatHud",
	"DoorGuide", "TechHotspot", "GraveHotspot", "OutdoorHotspot", "RigHotspot", "House", "DeliveryBadge",
	"TeleportHotspot"]
## Слои окон (≥ UiLayers.HUD_WINDOWS).
const WINDOW_LAYERS := ["HudWindows", "HouseStorageView", "ShopUI", "DiaryUI", "HousePrompt", "EquipmentLayer",
	"JournalScreen", "MetaHub", "DeathWindow", "ProjectsScreen", "DailyTasksPanel", "DailyPopup", "TechLayer",
	"ProgressLayer", "ArtifactCardLayer", "WellReportLayer", "CutscenePlayer"]
## Виджеты из жалобы и соседи по болезни: должны найтись в HUD-слоях.
const KEY_WIDGETS := ["ProjectTracker", "TechHud", "StreakMeter", "DebugPanel", "Objective", "AttackButton",
	"EnterHouseBtn", "BoardRigBtn", "GraveBtn", "DailyTasksButton", "SurvivalBadge"]

var failures := 0
var total := 0
var main: Node2D
var hud
var story
var tracker: ProjectTracker
var _widget_layers: Array = []   # CanvasLayer HUD-диапазона


func check(label: String, ok: bool, detail: String = "") -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label + ("" if detail.is_empty() else "  — " + detail))


func _ready() -> void:
	print("=== test_hud_layers ===")
	await _boot()
	_check_bands()
	await _show_widgets()
	_check_key_widgets()
	_check_world_below_hud()
	await _check_hud_windows_geometry()
	await _check_visibility_follows_hud()
	await _check_sensitivity()
	await _check_all_windows()
	_quit()


func _quit() -> void:
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ---------------------------------------------------------------------------
# Игра после онбординга
# ---------------------------------------------------------------------------

func _boot() -> void:
	for f in ["user://save.json", "user://save.json.bak", "user://records.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	GameState.reset_progress()
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	GameState.world_seed = SEED
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(4)
	hud = main.hud
	story = main.get_node("StoryDirector")
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered", "gold_sold",
			"backpack_owned", "death_seen", "robert_seen", "autodig_done", "workshop_seen"]:
		StoryState.set_flag(f)
	for sid in StoryData.scene_ids():
		StoryState.mark_seen(String(sid))
	GameState.house_tutorial_stage = 2
	for i in 6:
		if story.cutscene != null and story.cutscene.is_playing:
			story.cutscene.skip()
		await _frames(3)
	Settings.reduce_motion = true
	MetaState.sub("daily")["last"] = MetaState.today()
	var ms = MetaService.instance
	if ms != null and ms.popup.is_open():
		ms.popup.close()
	GameState.house_is_indoors = false
	hud.visible = true
	hud.set_process_input(true)
	await _frames(2)


## Все виджеты HUD разом: трекер проекта, бак бура и термометр, шкала азарта, курьер,
## значок голода, строка задания (и «Тест», кнопка заданий дня — они и так на экране).
func _show_widgets() -> void:
	hud.set_gauges_visible(true)
	GameState.grant_gear("backpack")
	GameState.inventory.clear()
	for id in ["gold", "iron_ore", "silver", "scrap", "peat", "energy_bar", "fuel_block", "noodles"]:
		GameState.inventory[id] = 2
	HintState.mark_seen("project_hand_drill")
	HintState.mark_seen("project_well")
	# Ручной бур уже в руках (бак у левого края), поэтому трекер — на бурмобиле: тот же виджет,
	# что у владельца, приколот рукой — автослежка не переключит.
	ProjectChain.set_tracked("drill_rig")
	GameState.grant_tool("hand_drill")
	GameState.set_current_tool("hand_drill")
	GameState.max_depth_reached = 760
	GameState.player_depth = 760
	GameState.set_hunger(8.0)
	var mech := main.get_node_or_null("MechDirector") as MechDirector
	if mech != null:
		mech.set_process(false)   # шкала азарта не тает, пока тест открывает окна
		mech.streak.work = 3.0
	var hs := main.find_child("HouseSystem", true, false)
	if hs != null and hs.get("_delivery_badge") != null:
		hs.get("_delivery_badge").track("noodles", 600.0)
	hud.set_objective("Задание: проверка слоёв")
	await _frames(30)
	var th := main.find_child("TechHud", true, false)
	if th != null:
		th.call("refresh")
	tracker = main.find_child("ProjectTracker", true, false) as ProjectTracker
	if tracker != null:
		tracker.sync()
	await _frames(4)
	var seen: Array = []
	for n in ["ProjectTracker", "TechHud", "StreakMeter", "DebugPanel", "Objective"]:
		var c := main.find_child(n, true, false) as CanvasItem
		if c != null and c.is_visible_in_tree():
			seen.append(n)
	var badge_holder := _first_control(main.find_child("DeliveryBadge", true, false))
	if badge_holder != null and badge_holder.is_visible_in_tree():
		seen.append("курьер")
	print("  видимые виджеты: ", ", ".join(seen))
	check("трекер проекта на экране (виджет со скриншота владельца)",
		tracker != null and tracker.is_visible_in_tree() and tracker.tracked_id() == "drill_rig")
	check("на экране и бак бура, шкала азарта, курьер, «Тест», строка задания",
		seen.has("TechHud") and seen.has("StreakMeter") and seen.has("курьер") and seen.has("Objective")
			and (seen.has("DebugPanel") or not DebugPanel.allowed()), str(seen))


# ---------------------------------------------------------------------------
# Диапазоны слоёв
# ---------------------------------------------------------------------------

func _layer_name(cl: CanvasLayer) -> String:
	if cl == hud.get_parent():
		return "HUD"
	if String(cl.name).begins_with("@"):   # безымянные: вспышка и летящие иконки Fx
		return "%s/@" % cl.get_parent().name
	return String(cl.name)


func _check_bands() -> void:
	var found_w: Array = []
	var found_win: Array = []
	var unknown: Array = []
	for n in main.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		var nm := _layer_name(cl)
		if nm in WIDGET_LAYERS:
			found_w.append(nm)
			_widget_layers.append(cl)
			check("слой HUD «%s» (%d) — над миром и не выше HUD_TOP" % [nm, cl.layer],
				cl.layer >= UiLayers.HUD and cl.layer <= UiLayers.HUD_TOP)
		elif nm in WINDOW_LAYERS:
			found_win.append(nm)
			check("окно «%s» (%d) — не ниже слоя окон" % [nm, cl.layer], cl.layer >= UiLayers.HUD_WINDOWS)
		else:
			unknown.append("%s=%d" % [nm, cl.layer])
	if not unknown.is_empty():
		print("  прочие слои (подсказки, тосты, эффекты): ", ", ".join(unknown))
	var miss: Array = []
	for nm in WIDGET_LAYERS + WINDOW_LAYERS:
		if not (nm in found_w or nm in found_win):
			miss.append(nm)
	check("все известные слои HUD и окон нашлись (переименование не прячет слой от проверки)",
		miss.is_empty(), str(miss))
	check("окна HUD (рюкзак, настройки, «•••») — на своём слое, а не в слое HUD",
		hud._inv_sheet.get_canvas_layer_node() == hud._windows_layer
			and hud._settings_sheet.get_canvas_layer_node() == hud._windows_layer
			and hud._more_panel.get_canvas_layer_node() == hud._windows_layer
			and hud._windows_layer.layer == UiLayers.HUD_WINDOWS)


func _check_key_widgets() -> void:
	var miss: Array = []
	for nm in KEY_WIDGETS:
		if nm == "DebugPanel" and not DebugPanel.allowed():
			continue
		var c := main.find_child(nm, true, false) as CanvasItem
		if c == null:
			miss.append(nm + " (нет)")
		elif not _in_widget_band(c):
			miss.append("%s (слой %d)" % [nm, _layer_num(c)])
	check("виджеты (трекер, бак, азарт, «Тест», задание, удар, пузыри, задания дня, голод) — в слоях HUD",
		miss.is_empty(), str(miss))


func _check_world_below_hud() -> void:
	var world_view := main.find_child("WorldView", true, false) as CanvasItem
	var greed := main.find_child("GreedBadge", true, false) as CanvasItem
	check("мир под HUD: трекер выше мира", world_view != null and _draws_over(tracker, world_view))
	check("значок жадности над героем — в мире, под HUD (z_index 50 не спасает)",
		greed != null and _layer_num(greed) == UiLayers.WORLD and _draws_over(tracker, greed)
			and _draws_over(hud, greed))


# ---------------------------------------------------------------------------
# Окна HUD: та же геометрия, видимость вместе с HUD, чувствительность проверки
# ---------------------------------------------------------------------------

func _check_hud_windows_geometry() -> void:
	var vp: Vector2 = hud.size
	hud.open_inventory()
	await _frames(3)
	var r: Rect2 = hud._inv_sheet.get_global_rect()
	check("рюкзак занимает экран над нижней полосой, как раньше (полоса с кнопкой рюкзака видна)",
		r.position == Vector2.ZERO and r.size.is_equal_approx(Vector2(vp.x, vp.y - hud.STRIP_H)), str(r))
	hud.close_inventory()
	hud.call("_toggle_more_menu")
	await _frames(3)
	var m: Rect2 = hud._more_panel.get_global_rect()
	check("меню «•••» прижато к правому краю над полосой, как раньше",
		m.size.x > 0.0 and is_equal_approx(m.end.x, vp.x - 4.0) and is_equal_approx(m.end.y, vp.y - hud.STRIP_H - 2.0),
		str(m))
	hud.close_more_menu()
	await _frames(20)


func _check_visibility_follows_hud() -> void:
	hud.open_inventory()
	await _frames(2)
	hud.visible = false   # так прячут HUD дом и сцены смерти
	await _frames(1)
	var hidden_ok: bool = not hud._windows_layer.visible and not hud._inv_sheet.is_visible_in_tree()
	hud.visible = true
	await _frames(1)
	check("HUD спрятан (дом, сцена) — его окна прячутся с ним, показан — возвращаются",
		hidden_ok and hud._windows_layer.visible and hud._inv_sheet.is_visible_in_tree())
	hud.close_inventory()
	await _frames(2)


## Контроль: окна HUD на слое HUD (как было до 26.10) — трекер снова над рюкзаком, и обе
## проверки (отрисовка и палец) это ловят. Без него зелёный тест мог бы ничего не мерить.
func _check_sensitivity() -> void:
	hud.open_inventory()
	await _frames(2)
	var was: int = hud._windows_layer.layer
	hud._windows_layer.layer = UiLayers.HUD
	await _frames(1)
	var drawn_over := not _draws_over(hud._inv_sheet, tracker)
	var hit := _hover(tracker.get_global_rect().get_center())
	var finger_to_tracker := hit != null and (hit == tracker or tracker.is_ancestor_of(hit))
	hud._windows_layer.layer = was
	await _frames(1)
	check("контроль: окна в слое HUD — проверка видит трекер над рюкзаком (как у владельца)",
		drawn_over and finger_to_tracker, "отрисовка=%s палец=%s" % [drawn_over, hit])
	var hit2 := _hover(tracker.get_global_rect().get_center())
	check("сейчас: палец в точке трекера при открытом рюкзаке попадает в рюкзак",
		_inside(hud._inv_sheet, hit2), str(hit2))
	hud.close_inventory()
	await _frames(2)


# ---------------------------------------------------------------------------
# Каждое окно поверх игры
# ---------------------------------------------------------------------------

func _windows() -> Array:
	var ms = MetaService.instance
	var mech := main.get_node_or_null("MechDirector") as MechDirector
	var equip := main.find_child("EquipmentLayer", true, false)
	var hs := main.find_child("HouseSystem", true, false)
	var feel := main.find_child("FeelDirector", true, false)
	return [
		{"name": "рюкзак", "open": func() -> void: hud.open_inventory(),
			"close": func() -> void: hud.close_inventory(), "node": func() -> Node: return hud._inv_sheet},
		{"name": "окно «сколько выбросить»", "open": func() -> void:
				hud.open_inventory()
				hud.call("_open_drop", "gold", 2),
			"close": func() -> void:
				hud.call("_close_drop")
				hud.close_inventory(),
			"node": func() -> Node: return hud._inv_sheet},
		{"name": "настройки", "open": func() -> void: hud.open_settings(),
			"close": func() -> void: hud.close_settings(), "node": func() -> Node: return hud._settings_sheet},
		{"name": "меню «•••»", "open": func() -> void: hud.call("_toggle_more_menu"),
			"close": func() -> void: hud.close_more_menu(), "node": func() -> Node: return hud._more_panel},
		{"name": "лавка", "open": func() -> void: ShopUI.open_shop(),
			"close": func() -> void: ShopUI.instance.close(), "node": func() -> Node: return ShopUI.instance},
		{"name": "мастерская", "open": func() -> void: ShopUI.open_workshop(),
			"close": func() -> void: ShopUI.instance.close(), "node": func() -> Node: return ShopUI.instance},
		{"name": "карточка рецепта", "open": func() -> void:
				ShopUI.open_workshop()
				ShopUI.instance._set_tab(ShopUI.TAB_TECH, false)
				for k in ShopUI.instance._tiles.keys():
					if String(k).begins_with("recipe:"):
						var t: ShopTile = ShopUI.instance._tiles[k]
						ShopUI.instance._open_card(t.offer, t)
						break,
			"close": func() -> void:
				ShopUI.instance._close_card(false)
				ShopUI.instance.close(),
			"node": func() -> Node: return ShopUI.instance},
		{"name": "склад", "open": func() -> void: hs.open_storage(),
			"close": func() -> void: hs.get("_storage_view").close_panel(),
			"node": func() -> Node: return hs.get("_storage_view")},
		{"name": "«Техника»", "open": func() -> void: TechScreen.open(TechScreen.TAB_TANK),
			"close": func() -> void: TechScreen.close_screen(), "node": func() -> Node: return TechScreen.instance()},
		{"name": "навыки", "open": func() -> void: ProgressScreen.open(ProgressScreen.TAB_PROGRESS),
			"close": func() -> void: ProgressScreen.close_screen(), "node": func() -> Node: return ProgressScreen.instance()},
		{"name": "музей", "open": func() -> void: ProgressScreen.open(ProgressScreen.TAB_MUSEUM),
			"close": func() -> void: ProgressScreen.close_screen(), "node": func() -> Node: return ProgressScreen.instance()},
		{"name": "герой", "open": func() -> void: ProgressScreen.open(ProgressScreen.TAB_HERO),
			"close": func() -> void: ProgressScreen.close_screen(), "node": func() -> Node: return ProgressScreen.instance()},
		{"name": "достижения", "open": func() -> void: ms.open_hub(MetaHub.TAB_ACH),
			"close": func() -> void: ms.hub.close(), "node": func() -> Node: return ms.hub},
		{"name": "задания дня", "open": func() -> void: ms.open_tasks(),
			"close": func() -> void: ms.tasks.close(), "node": func() -> Node: return ms.tasks},
		{"name": "подарок дня", "open": func() -> void: ms.open_daily(),
			"close": func() -> void: ms.popup.close(), "node": func() -> Node: return ms.popup},
		{"name": "проекты", "open": func() -> void: ProjectsScreen.open_for("hand_drill"),
			"close": func() -> void: ProjectsScreen.instance().close(), "node": func() -> Node: return ProjectsScreen.instance()},
		{"name": "журнал добытчика", "open": func() -> void: mech.journal.open(),
			"close": func() -> void: mech.journal.close(), "node": func() -> Node: return mech.journal},
		{"name": "снаряжение", "open": func() -> void: equip.open(),
			"close": func() -> void: equip.close(), "node": func() -> Node: return equip},
		{"name": "дневник", "open": func() -> void: story.diary_ui.open_diary(),
			"close": func() -> void: story.diary_ui.close_diary(), "node": func() -> Node: return story.diary_ui},
		{"name": "окно смерти", "open": func() -> void: feel.card.open(DeathWindow.report_now()),
			"close": func() -> void: feel.card.close(), "node": func() -> Node: return feel.card},
		{"name": "катсцена с диалогом", "open": func() -> void: story.cutscene.play("autodig_done", {}),
			"close": func() -> void: story.cutscene.skip(), "node": func() -> Node: return story.cutscene},
	]


func _check_all_windows() -> void:
	var items := _widget_items()
	check("в слоях HUD есть что сравнивать (%d элементов)" % items.size(), items.size() > 50)
	for w: Dictionary in _windows():
		await _check_window(w, items)


func _check_window(w: Dictionary, items: Array) -> void:
	var nm := String(w["name"])
	(w["open"] as Callable).call()
	await _frames(4)
	var node: Node = (w["node"] as Callable).call()
	var rep := _rep(node)
	if rep == null or not rep.is_visible_in_tree():
		check("окно «%s» открылось" % nm, false)
		(w["close"] as Callable).call()
		await _frames(10)
		return
	# (1) отрисовка: окно выше каждого элемента HUD-слоёв
	var over: Array = []
	for it: CanvasItem in items:
		if not _draws_over(rep, it):
			over.append("%s (слой %d)" % [it.get_path(), _layer_num(it)])
	check("окно «%s» (слой %d) рисуется поверх всех %d элементов HUD" % [nm, _layer_num(rep), items.size()],
		over.is_empty(), "над окном: " + ", ".join(over.slice(0, 4)))
	# (2) палец: точка видимого виджета, накрытая окном, — в окно
	var win_root: Node = rep if rep is Control and node is Control else rep.get_canvas_layer_node()
	var areas := _stop_rects(win_root)
	var leaks: Array = []
	var probed := 0
	for c: Control in _interactive_widgets():
		var p := c.get_global_rect().get_center()
		if not _covered(areas, p):
			continue
		probed += 1
		var hit := _hover(p)
		if not _inside(win_root, hit):
			leaks.append("%s → %s" % [c.name, hit.get_path() if hit != null else "никто"])
	check("окно «%s»: палец по виджетам под окном (%d точек) попадает в окно" % [nm, probed],
		leaks.is_empty(), ", ".join(leaks.slice(0, 4)))
	if nm == "рюкзак":
		_check_tip_over(rep)
	(w["close"] as Callable).call()
	await _frames(12)


## Подсказка Tip — над окнами (порядок «окна < подсказки»).
func _check_tip_over(window_item: CanvasItem) -> void:
	Tip.show_now(hud._inv_button)
	var tip_layer := get_tree().root.find_child("TipLayer", true, false) as CanvasLayer
	var max_win := 0
	for n in main.find_children("*", "CanvasLayer", true, false):
		if _layer_name(n) in WINDOW_LAYERS:
			max_win = maxi(max_win, (n as CanvasLayer).layer)
	check("подсказка Tip над всеми окнами (слой %d > %d)" % [tip_layer.layer if tip_layer else -1, max_win],
		tip_layer != null and tip_layer.layer > max_win and tip_layer.layer > _layer_num(window_item))
	Tip.hide_all()


# ---------------------------------------------------------------------------
# Порядок отрисовки
# ---------------------------------------------------------------------------

func _layer_num(ci: CanvasItem) -> int:
	var cl := ci.get_canvas_layer_node()
	return cl.layer if cl != null else 0


## Итоговый z: z_index складывается с родительским, пока z_as_relative.
func _abs_z(ci: CanvasItem) -> int:
	var z := 0
	var n: Node = ci
	while n is CanvasItem:
		var c := n as CanvasItem
		z += c.z_index
		if not c.z_as_relative:
			break
		n = n.get_parent()
	return z


## a рисуется поверх b? Сначала номер слоя; в одном слое — z, затем порядок в дереве.
## Один номер у двух разных слоёв — порядок движком не обещан: считаем «не поверх».
func _draws_over(a: CanvasItem, b: CanvasItem) -> bool:
	var la := a.get_canvas_layer_node()
	var lb := b.get_canvas_layer_node()
	var na := la.layer if la != null else 0
	var nb := lb.layer if lb != null else 0
	if na != nb:
		return na > nb
	if la != lb:
		return false
	var za := _abs_z(a)
	var zb := _abs_z(b)
	if za != zb:
		return za > zb
	return a.is_greater_than(b)


func _in_widget_band(ci: CanvasItem) -> bool:
	var cl := ci.get_canvas_layer_node()
	return cl != null and cl in _widget_layers


## Все CanvasItem слоёв HUD (кроме вложенных слоёв — окна HUD сидят в HUD своим слоем).
func _widget_items() -> Array:
	var out: Array = []
	for cl: CanvasLayer in _widget_layers:
		for n in cl.find_children("*", "CanvasItem", true, false):
			if (n as CanvasItem).get_canvas_layer_node() == cl:
				out.append(n)
	return out


## Видимые кнопки и плашки HUD-слоёв, которые ловят палец.
func _interactive_widgets() -> Array:
	var out: Array = []
	for n in _widget_items():
		if n is Control and (n as Control).is_visible_in_tree() \
				and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and (n as Control).get_global_rect().size.x > 2.0:
			out.append(n)
	return out


## Представитель окна для сравнения: сам Control или первый видимый Control его слоя.
func _rep(node: Node) -> CanvasItem:
	if node == null:
		return null
	if node is CanvasItem:
		return node as CanvasItem
	var c := _first_control(node)
	return c


func _first_control(node: Node) -> Control:
	if node == null:
		return null
	for ch in node.find_children("*", "Control", true, false):
		if (ch as Control).is_visible_in_tree():
			return ch as Control
	return null


## Где окно держит палец: видимые Control с MOUSE_FILTER_STOP.
func _stop_rects(root: Node) -> Array:
	var out: Array = []
	var nodes: Array = [root] if root is Control else []
	nodes.append_array(root.find_children("*", "Control", true, false))
	for n in nodes:
		var c := n as Control
		if c.is_visible_in_tree() and c.mouse_filter == Control.MOUSE_FILTER_STOP:
			out.append(_clipped_rect(c))
	return out


## Видимая часть: прокрутка и прочие clip_contents обрезают и картинку, и палец.
func _clipped_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p is Control:
		if (p as Control).clip_contents:
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r


func _inside(root: Node, n: Node) -> bool:
	return n != null and (n == root or root.is_ancestor_of(n))


func _covered(areas: Array, p: Vector2) -> bool:
	for r: Rect2 in areas:
		if r.has_point(p):
			return true
	return false


## Кто под пальцем в точке p (тот же выбор, что у касания: слой → z → дерево).
func _hover(p: Vector2) -> Control:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	get_viewport().push_input(mm, true)
	return get_viewport().gui_get_hovered_control()

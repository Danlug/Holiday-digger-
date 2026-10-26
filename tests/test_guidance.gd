extends Node
## test_guidance — «Проекты» (ветка guidance, раунд 4; ГДД §21): подсчёт материалов
## по цепочке с промежуточными (лом → бронза), рюкзак + склад, «нужно для…» на
## плитках продажи и склада (значок, строка Tip, янтарная рамка у отмеченной к
## продаже), трекер на HUD, автослежка, экран и вход в него, подсказка-знакомство.
## Реальное время и мир не нужны: состояние ставится руками.
##
## Запуск: godot --headless --path . res://tests/test_guidance.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_guidance ===")
	for _i in range(3):
		await get_tree().process_frame
	_test_defs()
	_test_chain_counts()
	_test_where()
	_test_needed_for()
	_test_tiles()
	_test_auto_track()
	await _test_tracker()
	await _test_screen()
	_test_hint_hooks()
	_test_save()
	_reset()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _reset(depth: int = 0) -> void:
	GameState.reset_progress()
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.ext.clear()
	GameState.coins = 0
	GameState.max_depth_reached = depth
	GameState.story_flags["food_ordered"] = true


func _fill(project: String, frac: float = 1.0) -> void:
	var d := ProjectChain.def(project)
	for id in (d["inputs"] as Dictionary).keys():
		GameState.house_storage[String(id)] = int(ceil(float(d["inputs"][id]) * frac))
	GameState.coins = maxi(GameState.coins, int(d["coins"]))


# ---------------------------------------------------------------------------

func _test_defs() -> void:
	_reset()
	var ids := ProjectChain.ids()
	check("проекты: бур, скважина, бурмобиль, костюм — по порядку открытия",
		ids == ["hand_drill", "well", "drill_rig", "heat_suit"])
	var bur := ProjectChain.def("hand_drill")
	check("бур: состав из рецепта верстака (железо, бронза, серебро) и монеты",
		(bur["inputs"] as Dictionary).has("iron_ore") and (bur["inputs"] as Dictionary).has("bronze")
		and (bur["inputs"] as Dictionary).has("silver") and int(bur["coins"]) > 0)
	check("у каждого проекта есть значок", ids.all(func(id) -> bool: return ProjectChain.icon(String(id)) != null))
	check("бур открывается на глубине рецепта", int(bur["unlock_depth"]) == ShopCatalog.unlock_depth("hand_drill"))
	var suit := ProjectChain.def("heat_suit")
	check("костюм: следующая ступень из «Техники»", String(suit.get("where_built", "")) == "tech"
		and not (suit["inputs"] as Dictionary).is_empty())
	TechState.set_suit(Heat.suit_tiers().size())
	check("все ступени костюма сделаны — проекта больше нет", not ProjectChain.ids().has("heat_suit"))
	_reset()
	check("промежуточное: бронза плавится из металлолома",
		ProjectChain.sources("bronze").size() == 1 and String(ProjectChain.sources("bronze")[0]["id"]) == "scrap")
	check("у руды промежуточного нет", ProjectChain.sources("iron_ore").is_empty())


func _test_chain_counts() -> void:
	_reset(100)
	GameState.inventory["iron_ore"] = 20
	GameState.house_storage["iron_ore"] = 100
	GameState.inventory["scrap"] = 30
	GameState.house_storage["bronze"] = 40
	var iron := ProjectChain.material("iron_ore", 500)
	check("есть = рюкзак + склад (20 + 100)", int(iron["have"]) == 120 and int(iron["effective"]) == 120)
	var br := ProjectChain.material("bronze", 100)
	check("бронза: своей 40, из лома выйдет 30 → по цепочке 70",
		int(br["have"]) == 40 and int(br["effective"]) == 70 and int(br["via"][0]["makes"]) == 30)
	check("лом в бронзе не считается «готово», пока не переплавлен", not bool(br["done"]))
	var silver_frac := 0.0
	var drill_in: Dictionary = ShopCatalog.recipe("hand_drill")["inputs"]
	var exp := (120.0 / float(drill_in["iron_ore"]) + 70.0 / float(drill_in["bronze"]) + silver_frac + 0.0) / 4.0
	check("общий прогресс бура = среднее материалов (с переработкой) и монет",
		absf(ProjectChain.progress("hand_drill") - exp) < 0.001)
	check("не всё есть — не готов", not ProjectChain.ready("hand_drill"))
	var c := ProjectChain.counts("hand_drill")
	check("готово строк 0 из 4", int(c["done"]) == 0 and int(c["total"]) == 4)

	_reset(100)
	_fill("hand_drill")
	check("всё на складе и монеты есть — готов", ProjectChain.ready("hand_drill")
		and is_equal_approx(ProjectChain.progress("hand_drill"), 1.0))
	GameState.house_storage["bronze"] = 0
	GameState.inventory["scrap"] = 99
	GameState.house_storage["scrap"] = 1
	check("бронзы нет, но лома на всю — полоска полная, а «готов» нет (надо переплавить)",
		is_equal_approx(ProjectChain.progress("hand_drill"), 1.0) and not ProjectChain.ready("hand_drill"))

	_reset(0)
	_fill("hand_drill")
	check("рецепт не открыт по глубине — проект не открыт и не готов",
		not ProjectChain.is_open("hand_drill") and not ProjectChain.ready("hand_drill"))
	GameState.max_depth_reached = 100
	GameState.owned_tools.append("hand_drill")
	check("собран — не открыт", ProjectChain.is_built("hand_drill") and not ProjectChain.is_open("hand_drill"))
	GameState.well_level = 1
	check("скважина собрана по уровню", ProjectChain.is_built("well"))


func _test_where() -> void:
	_reset()
	var w := ProjectChain.where("iron_ore")
	check("железо: с 5 м, больше всего около 100", int(w["min"]) == 5 and int(w["best"]) == 100 and String(w["tool"]) == "")
	check("никель берётся только ручным буром", String(ProjectChain.where("nickel")["tool"]) == "hand_drill")
	check("бронза не копается — плавится", bool(ProjectChain.where("bronze")["crafted"]))
	check("подсказка «где копать» с числом глубины", ProjectChain.where_text("silver").contains("50"))
	check("подсказка у бронзы называет лом", ProjectChain.where_text("bronze").contains("Металлолом"))


func _test_needed_for() -> void:
	_reset(0)
	GameState.inventory["scrap"] = 30
	check("до открытия проектов лом ни для чего не нужен", ProjectChain.needed_for("scrap").is_empty())
	_reset(100)
	GameState.inventory["scrap"] = 30
	GameState.house_storage["bronze"] = 40
	var n := ProjectChain.needed_for("scrap")
	# с 26.10 (владелец): бур — 80 бронзы (−20%), скважина дороже бура — 100 бронзы
	var for_drill := n.filter(func(e) -> bool: return String(e["project"]) == "hand_drill")
	var for_well := n.filter(func(e) -> bool: return String(e["project"]) == "well")
	check("лом нужен буру через бронзу: 30 из 40 (80 − 40 бронзы)", for_drill.size() == 1
		and String(for_drill[0]["via"]) == "bronze"
		and int(for_drill[0]["have"]) == 30 and int(for_drill[0]["need"]) == 40)
	check("и скважине через бронзу: 30 из 60 (100 − 40 бронзы) — она дороже бура", for_well.size() == 1
		and String(for_well[0]["via"]) == "bronze" and int(for_well[0]["need"]) == 60)
	check("текст Tip: «Ручной бур (бронза) — 30/40»", ProjectChain.needed_text("scrap").contains("30/40")
		and ProjectChain.needed_text("scrap").contains("бронза"))
	var iron := ProjectChain.needed_for("iron_ore")
	check("железо нужно и буру, и скважине", iron.size() == 2)
	ProjectChain.set_tracked("well")
	check("отслеживаемый проект — первым", String(ProjectChain.needed_for("iron_ore")[0]["project"]) == "well")
	GameState.house_storage["iron_ore"] = 500
	check("набрано — значка больше нет", ProjectChain.needed_for("iron_ore").is_empty())
	check("золото ни для чего не нужно", ProjectChain.needed_for("gold").is_empty())


func _test_tiles() -> void:
	_reset(100)
	GameState.inventory["scrap"] = 12
	GameState.inventory["gold"] = 3
	var offers := ShopItems.sell_offers({"scrap": true, "gold": true}, false)
	var scrap: Dictionary = {}
	var gold: Dictionary = {}
	for o in offers:
		if String(o["ref"]) == "scrap":
			scrap = o
		elif String(o["ref"]) == "gold":
			gold = o
	check("плитка продажи лома: значок бура", scrap.get("need_icon", null) == ProjectChain.icon("hand_drill"))
	check("плитка продажи лома: в Tip «нужно для»", String(scrap.get("extra", "")).contains("Нужно для"))
	check("плитка продажи золота без значка", not gold.has("need_icon"))

	var t := ShopTile.new()
	add_child(t)
	t.setup(scrap)
	var badge := _find_badge(t)
	check("плитка рисует значок проекта в углу", badge != null and badge.visible and badge.texture != null)
	check("отмечена к продаже — янтарная рамка и пульс значка",
		badge != null and badge.warn and t._rim.modulate == ShopTile.COL_NEED)
	scrap["selected"] = false
	t.setup(scrap)
	check("снята с продажи — без предупреждения", badge != null and not badge.warn and t._rim.modulate != ShopTile.COL_NEED)
	t.setup(gold)
	check("плитка без нужды — значок спрятан", badge != null and not badge.visible)
	t.queue_free()

	var view = load("res://scripts/house/house_storage_view.gd").new()
	var so: Dictionary = view._offer("scrap", 12, true, true)
	check("плитка склада: тот же значок и строка Tip", so.get("need_icon", null) != null
		and String(so.get("extra", "")).contains("Нужно для"))
	view.free()


func _find_badge(n: Node) -> NeedBadge:
	for c in n.get_children():
		if c is NeedBadge:
			return c
	return null


func _test_auto_track() -> void:
	_reset(0)
	check("ничего не открыто — следить не за чем", ProjectChain.auto_track() == "" and ProjectChain.tracked() == "")
	GameState.max_depth_reached = 100
	check("открылся бур — трекер берёт его сам", ProjectChain.auto_track() == "hand_drill"
		and ProjectChain.tracked() == "hand_drill")
	GameState.owned_tools.append("hand_drill")
	ProjectChain.auto_track()
	check("бур собран — трекер переходит к скважине", ProjectChain.tracked() == "well")
	ProjectChain.set_tracked("", true)
	ProjectChain.auto_track()
	check("игрок снял слежку руками — автослежка не вмешивается", ProjectChain.tracked() == "")
	ProjectChain.set_tracked("well", true)
	GameState.well_level = 1
	ProjectChain.auto_track()
	check("собранное снимается и при ручной слежке", ProjectChain.tracked() == "")


func _test_tracker() -> void:
	_reset(100)
	var tr := ProjectTracker.new()
	add_child(tr)
	await get_tree().process_frame
	tr.sync()
	check("трекер спрятан, пока не за чем следить", not tr.visible)
	ProjectChain.set_tracked("hand_drill")
	_fill("hand_drill", 0.5)
	tr.sync()
	check("трекер виден с проектом", tr.visible and tr.tracked_id() == "hand_drill")
	check("по полоске на материал и монеты (3 + 1)", tr.bar_count() == 4)
	check("половина — не готов", not tr.is_ready_state())
	check("Tip трекера: название и строки материалов", String((tr.get_meta(Tip.META) as Dictionary)["title"]) == "Ручной бур"
		and String((tr.get_meta(Tip.META) as Dictionary)["body"]).contains("Железо"))
	_fill("hand_drill", 1.0)
	tr.sync()
	check("всё набрано — трекер «готов»", tr.is_ready_state())
	check("трекер — цель нажатия не меньше 22 по высоте", tr.size.y >= 22.0)
	GameState.owned_tools.append("hand_drill")
	tr.sync()
	check("собрано — трекер прячется", not tr.visible)
	GameState.story_flags.erase("food_ordered")
	ProjectChain.set_tracked("well")
	tr.sync()
	check("до конца онбординга трекера нет", not tr.visible)
	tr.queue_free()


func _test_screen() -> void:
	_reset(100)
	GameState.inventory["scrap"] = 7
	var s := ProjectsScreen.new()
	add_child(s)
	await get_tree().process_frame
	check("экран закрыт по умолчанию", not s.is_open() and not ProjectsScreen.is_open_any())
	ProjectsScreen.open_for("hand_drill")
	await get_tree().process_frame
	check("открывается на нужном проекте", s.is_open() and s.current() == "hand_drill")
	# карточка + 3 материала + подстрока лома + монеты
	check("строки: карточка, 3 материала, лом → бронза, монеты", s._body.get_child_count() == 6)
	check("вкладки — по проекту на вкладку", s._tab_buttons.size() == ProjectChain.ids().size())
	check("подсказка считает экран открытым", HintConditions.screen_open("projects"))
	s._toggle_track("hand_drill")
	check("«следить» приколачивает проект", ProjectChain.tracked() == "hand_drill" and ProjectChain.is_manual())
	s._toggle_track("hand_drill")
	check("повторно — снимает", ProjectChain.tracked() == "")
	s._set_project("drill_rig")
	check("вкладка бурмобиля: никель и платина, без подстрок", s.current() == "drill_rig" and s._body.get_child_count() == 4)
	s.close()
	await get_tree().create_timer(0.4).timeout
	check("закрывается", not s.is_open())

	# вход с карточки рецепта мастерской
	var host := Control.new()
	var panel := PanelContainer.new()
	host.add_child(panel)
	add_child(host)
	ProjectsScreen.decorate_card(panel, {"kind": "recipe", "ref": "hand_drill"})
	var btn := host.get_node_or_null("ProjectsChainButton") as Button
	check("карточка рецепта бура получает кнопку «цепочка»", btn != null)
	if btn != null:
		btn.pressed.emit()
		await get_tree().process_frame
		check("кнопка открывает экран на буре", s.is_open() and s.current() == "hand_drill")
	ProjectsScreen.decorate_card(panel, {"kind": "recipe", "ref": "bronze"})
	check("у плавки бронзы кнопки нет (не проект)", host.get_child_count() == 2)
	s.close()
	host.queue_free()
	await get_tree().create_timer(0.4).timeout
	s.queue_free()


func _test_hint_hooks() -> void:
	_reset(0)
	check("условие project_open известно", HintConditions.is_known("project_open"))
	check("project_open ложно до глубины 100", not HintConditions.test({"fn": "project_open", "id": "hand_drill"}))
	GameState.max_depth_reached = 100
	check("project_open истинно, когда рецепт открылся", HintConditions.test({"fn": "project_open", "id": "hand_drill"}))
	check("значки тоста проектов находятся", HintArt.icon("items:hand_drill") != null
		and HintArt.icon("shop:item_well") != null and HintArt.icon("items:drill_rig_icon") != null)
	var ids: Array = []
	for r: Dictionary in HintData.rules():
		ids.append(String(r["id"]))
	check("подсказки-знакомства для бура, скважины и бурмобиля",
		ids.has("project_hand_drill") and ids.has("project_well") and ids.has("project_drill_rig"))
	check("пункт меню «Проекты» с меткой «new»", HintData.menu_new_entries().has("projects"))


func _test_save() -> void:
	_reset(100)
	ProjectChain.set_tracked("well")
	GameState.ext = JSON.parse_string(JSON.stringify(GameState.ext))
	check("слежка переживает сейв", ProjectChain.tracked() == "well" and ProjectChain.is_manual())

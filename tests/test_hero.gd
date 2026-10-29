extends Node
## test_hero — экран героя: дерево прокачки (покупка ступеней, очки, требования),
## закрытие ветки музея, схема названий 25 артефактов (ru+en, без пустых и
## дублей), иконки, подсказки и сборка вкладок. Визуал — под скриншотом
## (tests/test_screenshot_hero.gd).
##
## Запускается как сцена (нужны автолоады GameState/Balance):
##   godot --headless --path . res://tests/test_hero.tscn

var failures := 0
var total := 0


func _ready() -> void:
	print("=== test_hero ===")
	# Подсказки (Tip) строят свой слой в корне окна — корень занят, пока _ready не вернулся.
	await get_tree().process_frame
	GameState.reset_progress()
	Settings.language = "ru"
	Settings.reduce_motion = true   # тесты не ждут твинов

	_test_text_scheme()
	_test_text_language_switch()
	_test_icons_exist()
	_test_buy_logic()
	_test_skill_tree_nodes()
	_test_branch_completion()
	_test_find_records_depth()
	_test_museum_and_showcase()
	_test_hero_panel()
	_test_screen_tabs()
	_test_card_queue()

	Settings.language = "ru"
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", label])


func check_eq(label: String, actual, expected) -> void:
	check("%s (получено=%s, ожидалось=%s)" % [label, actual, expected], actual == expected)


func _has_cyrillic(s: String) -> bool:
	for i in range(s.length()):
		var c := s.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			return true
	return false


# ---------------------------------------------------------------------------
# Тексты артефактов
# ---------------------------------------------------------------------------

func _test_text_scheme() -> void:
	print("--- Схема названий и описаний ---")
	var arts: Array = Balance.artifacts.get("artifacts", [])
	check_eq("артефактов ровно 25", arts.size(), 25)
	var seen := {}
	var problems: Array = []
	for a: Dictionary in arts:
		var id := String(a.get("id", ""))
		for field in ["name_ru", "name_en", "desc_ru", "desc_en", "hint_ru", "hint_en"]:
			var v := String(a.get(field, "")).strip_edges()
			if v.is_empty():
				problems.append("%s: пустое %s" % [id, field])
				continue
			var key: String = field + "|" + v
			if seen.has(key):
				problems.append("%s: %s дублирует %s" % [id, field, seen[key]])
			seen[key] = id
		if _has_cyrillic(String(a.get("name_en", ""))) or _has_cyrillic(String(a.get("desc_en", ""))) \
				or _has_cyrillic(String(a.get("hint_en", ""))):
			problems.append("%s: в английском тексте кириллица" % id)
		for field in ["name_ru", "desc_ru", "hint_ru"]:
			if not _has_cyrillic(String(a.get(field, ""))):
				problems.append("%s: в %s нет кириллицы" % [id, field])
		# Подсказка Tip узкая (152 точки): длинные описания превращаются в простыню.
		if String(a.get("desc_ru", "")).length() > 110 or String(a.get("desc_en", "")).length() > 110:
			problems.append("%s: описание длиннее 110 знаков" % id)
		if String(a.get("hint_ru", "")).length() > 60 or String(a.get("hint_en", "")).length() > 60:
			problems.append("%s: намёк длиннее 60 знаков" % id)
		# Намёк не выдаёт название ненайденного предмета.
		if String(a.get("hint_ru", "")).to_lower().contains(String(a.get("name_ru", "")).to_lower()):
			problems.append("%s: намёк содержит название" % id)
	for p in problems:
		print("   ! ", p)
	check_eq("у всех 25 есть ru+en название, описание и намёк, без пустых и дублей", problems.size(), 0)

	var branches_en := true
	for b: Dictionary in Balance.artifacts.get("branches", []):
		if String(b.get("name_en", "")).is_empty():
			branches_en = false
	check("у всех веток есть английское название", branches_en)
	var pieces: Dictionary = Balance.artifacts.get("ultimate_set", {}).get("piece_names", {})
	var pieces_ok := pieces.size() == 5
	for k in pieces.keys():
		if String(pieces[k].get("ru", "")).is_empty() or String(pieces[k].get("en", "")).is_empty():
			pieces_ok = false
	check("названия пяти слотов сета есть на обоих языках", pieces_ok)


func _test_text_language_switch() -> void:
	print("--- Выбор языка ---")
	var a := Balance.get_artifact("legends_5")
	Settings.language = "ru"
	check_eq("ru: название", ArtifactText.name_of(a), "Перчатка Мироздания")
	Settings.language = "en"
	check_eq("en: название", ArtifactText.name_of(a), "Gauntlet of Creation")
	check_eq("en: слот сета", ArtifactText.set_piece_name("glove"), "glove")
	Settings.language = "uk"
	check_eq("язык без перевода сползает на русский", ArtifactText.name_of(a), "Перчатка Мироздания")
	check_eq("слот сета на русском", ArtifactText.set_piece_name("glove"), "перчатка")
	Settings.language = "ru"
	check_eq("неизвестный слот возвращает ключ", ArtifactText.set_piece_name("boots"), "boots")


func _test_icons_exist() -> void:
	print("--- Иконки ---")
	var missing: Array = []
	for a: Dictionary in Balance.artifacts.get("artifacts", []):
		if not ArtifactArt.has_art(String(a["id"])):
			missing.append(a["id"])
	check_eq("иконки всех артефактов на месте", missing, [])
	var tex: Texture2D = ArtifactArt.texture_for("antiquity_3")
	check("иконка артефакта 32×32", tex != null and tex.get_width() == 32 and tex.get_height() == 32)
	var skill_missing: Array = []
	for b: Dictionary in Balance.upgrades.get("branches", []):
		if HeroIcons.skill_icon(String(b["id"])) == null:
			skill_missing.append(b["id"])
	check_eq("у каждой ветки прокачки есть иконка", skill_missing, [])
	var ui_missing: Array = []
	for n in ["tab_hero", "tab_skills", "tab_museum", "tab_close", "ui_lock", "ui_check", "ui_star", "ui_depth",
			"ui_gem", "ui_bag", "ui_coin", "ui_dollar", "ui_trophy", "ui_chest", "ui_xp",
			"gem_hellstone", "gem_dark_matter", "gem_universum", "gem_angelstone", "gem_divine_heart"]:
		if HeroIcons.get_icon(n) == null:
			ui_missing.append(n)
	check_eq("служебные иконки на месте", ui_missing, [])
	check("нет файла — null, а не падение", HeroIcons.get_icon("нет_такой") == null)


# ---------------------------------------------------------------------------
# Покупка ступеней
# ---------------------------------------------------------------------------

func _test_buy_logic() -> void:
	print("--- Покупка ступеней: очки и требования ---")
	GameState.reset_progress()
	var cost1 := Balance.get_upgrade_stage_cost("hp", 1)
	var cost2 := Balance.get_upgrade_stage_cost("hp", 2)
	GameState.skill_points_available = cost1 + cost2 - 1

	check("без очков на вторую ступень сначала покупается первая", SkillTree.try_buy("hp", false))
	check_eq("очки списаны по цене первой ступени", GameState.skill_points_available, cost2 - 1)
	check_eq("ступень HP = 1", GameState.get_skill_stage("hp"), 1)
	check("на вторую очков не хватает на одно", not SkillTree.try_buy("hp", false))
	check_eq("отказ не списал очки", GameState.skill_points_available, cost2 - 1)
	GameState.skill_points_available += 1
	check("добавили очко — вторая ступень куплена", SkillTree.try_buy("hp", false))
	check_eq("ступень HP = 2", GameState.get_skill_stage("hp"), 2)
	check_eq("очки на нуле", GameState.skill_points_available, 0)

	# HP: потолок вырос — полоска доливается на прибавку ступени.
	GameState.reset_progress()
	GameState.skill_points_available = 100
	GameState.hp = 40.0
	var per_stage := float(Balance.unwrap(Balance.get_upgrade_branch("hp").get("effect", {}).get("per_stage", 20)))
	SkillTree.try_buy("hp", false)
	check("после покупки HP подлечилось на прибавку ступени", is_equal_approx(GameState.hp, 40.0 + per_stage))

	# Ступени идут по порядку: пропустить нельзя, а у цены следующей — своя строка таблицы.
	GameState.reset_progress()
	GameState.skill_points_available = 1000
	var prev := 1000
	var ladder_ok := true
	for s in range(1, 6):
		var expect_cost := Balance.get_upgrade_stage_cost("dig_speed", s)
		SkillTree.try_buy("dig_speed", false)
		if prev - GameState.skill_points_available != expect_cost or GameState.get_skill_stage("dig_speed") != s:
			ladder_ok = false
		prev = GameState.skill_points_available
	check("5 ступеней скорости копки списывают очки по таблице цен", ladder_ok)
	check("неизвестная ветка не покупается", not SkillTree.try_buy("нет_такой", false))

	var stages := int(Balance.get_upgrade_branch("luck_multiplier").get("stages", 0))
	GameState.reset_progress()
	GameState.skill_points_available = 10000
	SkillTree.try_buy("luck_chance", false)  # множитель открывается после ступени шанса (раунд 4)
	for i in range(stages + 2):
		SkillTree.try_buy("luck_multiplier", false)
	check_eq("выше максимума ступеней не поднять", GameState.get_skill_stage("luck_multiplier"), stages)


func _test_skill_tree_nodes() -> void:
	print("--- Дерево: состояния узлов и двойное нажатие ---")
	GameState.reset_progress()
	GameState.skill_points_available = 3
	GameState.skill_stages = {"hp": 2}

	var tree := SkillTree.new()
	tree.save_on_buy = false
	tree.size = Vector2(216, 460)
	add_child(tree)

	var hp_nodes: Array = []
	for c in tree.get_children():
		if c is SkillNode and (c as SkillNode).branch_id == "hp":
			hp_nodes.append(c)
	var branch_stages := int(Balance.get_upgrade_branch("hp").get("stages", 0))
	check_eq("узлов ветки HP столько же, сколько ступеней", hp_nodes.size(), branch_stages)
	check_eq("ступени 1–2 куплены", [hp_nodes[0].state, hp_nodes[1].state],
		[SkillNode.State.DONE, SkillNode.State.DONE])
	var cost3 := Balance.get_upgrade_stage_cost("hp", 3)
	check_eq("ступень 3 следующая и по карману (цена %d, очков 3)" % cost3,
		hp_nodes[2].state, SkillNode.State.NEXT_READY if cost3 <= 3 else SkillNode.State.NEXT_POOR)
	check_eq("ступень 4 закрыта замком", hp_nodes[3].state, SkillNode.State.LOCKED)
	check_eq("цена на узле равна цене из таблицы", hp_nodes[2].cost, cost3)

	# Закрытая ступень не покупается нажатием.
	var points_before: int = GameState.skill_points_available
	hp_nodes[3].pressed.emit()
	check_eq("нажатие по закрытой ступени ничего не стоит", GameState.skill_points_available, points_before)
	check_eq("ступень HP по-прежнему 2", GameState.get_skill_stage("hp"), 2)

	# Первое нажатие — «взвод» (галочка), второе — покупка.
	GameState.skill_points_available = cost3 + 5
	tree.refresh()
	hp_nodes[2].pressed.emit()
	check("первое нажатие взводит узел и очков не тратит",
		hp_nodes[2].armed and GameState.skill_points_available == cost3 + 5)
	hp_nodes[2].pressed.emit()
	check_eq("второе нажатие купило ступень", GameState.get_skill_stage("hp"), 3)
	check_eq("очки списаны по цене", GameState.skill_points_available, 5)
	check_eq("узел стал купленным", hp_nodes[2].state, SkillNode.State.DONE)
	check("взвод снят после покупки", not hp_nodes[2].armed)
	check_eq("следующая ступень стала доступной цели",
		hp_nodes[3].state in [SkillNode.State.NEXT_READY, SkillNode.State.NEXT_POOR], true)

	# Взведённый узел не покупает, если очки успели уйти.
	GameState.skill_points_available = Balance.get_upgrade_stage_cost("hp", 4)
	tree.refresh()
	hp_nodes[3].pressed.emit()
	GameState.skill_points_available = 0
	tree.refresh()
	check("взвод снимается, когда очков не стало", not hp_nodes[3].armed)
	hp_nodes[3].pressed.emit()
	check_eq("без очков второе нажатие ничего не купило", GameState.get_skill_stage("hp"), 3)

	# Подсказка узла: название ветки и цена живут в Tip, на узле текста нет.
	var meta: Dictionary = hp_nodes[2].get_meta(Tip.META)
	check("у узла есть подсказка с названием ветки", String(meta.get("title", "")).contains("HP"))
	check("текста на узле нет", (hp_nodes[2] as SkillNode).text == "")
	tree.queue_free()


# ---------------------------------------------------------------------------
# Музей
# ---------------------------------------------------------------------------

func _test_branch_completion() -> void:
	print("--- Закрытие ветки: награда и значки ---")
	GameState.reset_progress()
	var items := Balance.get_artifacts_in_branch(2)
	var reward: Dictionary = {}
	for b: Dictionary in Balance.artifacts.get("branches", []):
		if int(b["branch"]) == 2:
			reward = b["completion_reward"]
	var coins_reward := int(Balance.unwrap(reward["coins"]))
	var dollars_reward := int(Balance.unwrap(reward["premium_currency"]))

	var completed_signal := []
	var on_done := func(n: int) -> void: completed_signal.append(n)
	GameState.branch_completed.connect(on_done)
	var finds_sum := 0
	for i in range(items.size() - 1):
		GameState.collect_artifact(String(items[i]["id"]))
		finds_sum += Balance.get_artifact_find_coins(String(items[i]["id"]))
	check("четырёх предметов мало: ветка не закрыта", not GameState.completed_branches.has(2))
	var coins_before: int = GameState.coins
	var dollars_before: int = GameState.dollars
	GameState.collect_artifact(String(items[items.size() - 1]["id"]))
	var last_coins := Balance.get_artifact_find_coins(String(items[items.size() - 1]["id"]))
	check("пятый предмет закрыл ветку", GameState.completed_branches.has(2))
	check_eq("монеты: находка + награда за ветку", GameState.coins - coins_before, last_coins + coins_reward)
	check_eq("доллары: награда за ветку", GameState.dollars - dollars_before, dollars_reward)
	check_eq("сигнал закрытия пришёл один раз", completed_signal, [2])
	GameState.collect_artifact(String(items[0]["id"]))
	check_eq("повторная находка не платит дважды", completed_signal, [2])
	GameState.branch_completed.disconnect(on_done)


func _test_find_records_depth() -> void:
	print("--- Глубина находки в сейве героя ---")
	GameState.reset_progress()
	check_eq("пока не найден — глубины нет", HeroData.find_depth("occult_2"), -1)
	HeroData.record_find("occult_2", 273)
	check_eq("глубина записана", HeroData.find_depth("occult_2"), 273)
	# Тип из JSON — float: после «сохранения» значение читается обратно целым.
	GameState.ext["hero"] = {"finds": {"occult_2": 273.0}}
	check_eq("float из JSON читается как int", HeroData.find_depth("occult_2"), 273)
	check("ветка не отмечена увиденной", not HeroData.is_branch_seen(3))
	HeroData.mark_branch_seen(3)
	HeroData.mark_branch_seen(3)
	check("ветка отмечена", HeroData.is_branch_seen(3))
	check_eq("отметка записана один раз", (GameState.ext["hero"]["seen_branches"] as Array).size(), 1)

	# Через настоящий путь находки: ArtifactFinder пишет глубину клетки.
	var world := WorldGen.new(777)
	GameState.world_ref = world
	GameState.world_seed = 777
	var finder := ArtifactFinder.new()
	add_child(finder)
	finder.setup(null, null)
	var artifact: Dictionary = Balance.get_artifacts_in_branch(1)[2]
	var cell: Vector2i = ArtifactSpawn.cell_of(artifact, GameState.world_seed, GameState.world_ref)
	var id := finder.claim_at(cell.x, cell.y)
	check_eq("находка выдана", id, String(artifact["id"]))
	check_eq("глубина находки = строка клетки", HeroData.find_depth(id), cell.y)
	finder.queue_free()


func _test_museum_and_showcase() -> void:
	print("--- Витрины: 5×5 и центральная витрина сета ---")
	GameState.reset_progress()
	GameState.collect_artifact("antiquity_1")
	GameState.collect_artifact("antiquity_5")
	var panel := MuseumPanel.new()
	add_child(panel)
	var slots: Array = panel.find_children("*", "ArtifactSlot", true, false)
	check_eq("30 ячеек: 25 в ветках + 5 в центральной витрине", slots.size(), 30)
	var found := 0
	var unknown_without_tip := 0
	for s: ArtifactSlot in slots:
		if s.found:
			found += 1
		var meta: Dictionary = s.get_meta(Tip.META, {})
		if String(meta.get("title", "")).is_empty():
			unknown_without_tip += 1
	check_eq("найденных ячеек 2 + 1 в сете (antiquity_5 стоит и там)", found, 3)
	check_eq("у каждой ячейки есть подсказка", unknown_without_tip, 0)

	var found_slot: ArtifactSlot = null
	var hidden_slot: ArtifactSlot = null
	for s: ArtifactSlot in slots:
		if s.artifact_id == "antiquity_5" and found_slot == null:
			found_slot = s
		if s.artifact_id == "legends_1":
			hidden_slot = s
	var meta_found: Dictionary = found_slot.get_meta(Tip.META)
	check_eq("найденный: в подсказке настоящее название", meta_found["title"], "Золотой щит спартанского полководца")
	check("найденный: в подсказке есть описание", String(meta_found["body"]).length() > 10)
	var meta_hidden: Dictionary = hidden_slot.get_meta(Tip.META)
	check_eq("ненайденный: название скрыто", meta_hidden["title"], "???")
	check("ненайденный: вместо описания — намёк", String(meta_hidden["body"]) == String(Balance.get_artifact("legends_1")["hint_ru"]))
	check("ненайденный: название не просочилось в подсказку",
		not (String(meta_hidden["body"]) + String(meta_hidden["extra"])).contains("Клинок"))
	check("ненайденный: сказано, на какой глубине искать", String(meta_hidden["extra"]).contains("800"))

	var showcase: SetShowcase = panel.find_children("*", "SetShowcase", true, false)[0]
	check_eq("в центральной витрине пять предметов", showcase.slots.size(), 5)
	check_eq("собрано из сета: 1", showcase.have, 1)
	for piece in ["helmet", "chestplate", "shield", "amulet", "glove"]:
		if not showcase.slots.has(piece):
			check("слот сета " + piece, false)
	for id in ["antiquity_5", "mysticism_5", "occult_5", "forgotten_civilizations_5", "legends_5"]:
		GameState.collect_artifact(id)
	showcase.refresh()
	check_eq("сет собран целиком", showcase.have, 5)
	panel.celebrate_branch(1)   # без дерева на экране — тихо ничего не делает
	panel.queue_free()


# ---------------------------------------------------------------------------
# Вкладка героя и экран
# ---------------------------------------------------------------------------

func _test_hero_panel() -> void:
	print("--- Вкладка героя ---")
	GameState.reset_progress()
	GameState.level = 7
	GameState.skill_points_available = 4
	GameState.skill_stages = {"hp": 3, "strength": 2, "dig_speed": 5, "vision": 2, "stamina": 1, "hunger": 2}
	GameState.max_depth_reached = 321
	var panel := HeroPanel.new()
	add_child(panel)
	panel.refresh()
	var stats: Dictionary = panel._stats
	check_eq("шесть плиток характеристик", stats.size(), 6)
	check_eq("HP = 100 + 3×20", HeroUi.tile_value(stats["hp"]).text, "160")
	check_eq("обзор на ступени 2", HeroUi.tile_value(stats["vision"]).text,
		str(Balance.get_vision_radius("vision", 2)))
	check_eq("скорость копки с одним знаком", HeroUi.tile_value(stats["dig_speed"]).text,
		"%.1fс" % Balance.get_dig_time_seconds(5))
	check("вес показан как «сейчас/максимум»", HeroUi.tile_value(stats["strength"]).text.contains("/"))
	check_eq("уровень на карточке", panel._level_label.text, "7")
	check_eq("очки навыков на карточке", panel._points_label.text, "4")
	var rec_tiles := panel.records_panel.find_children("*", "PanelContainer", true, false)
	check_eq("шесть плиток рекордов", rec_tiles.size(), 6)
	var depth_shown := false
	for t in rec_tiles:
		if HeroUi.tile_value(t).text == "321":
			depth_shown = true
	check("рекорд глубины на плитке", depth_shown)
	# Текстовых абзацев на вкладке нет: автоперенос — только в подсказках.
	var wrapped := 0
	for l in panel.find_children("*", "Label", true, false):
		if (l as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			wrapped += 1
	check_eq("на вкладке героя нет переносимых абзацев", wrapped, 0)

	check_eq("1234 -> 1234", UiFmt.short(1234), "1234")
	check_eq("12 345 -> 12.3к", UiFmt.short(12345), "12.3к")
	check_eq("10 000 -> 10к", UiFmt.short(10000), "10к")
	check_eq("4 200 000 -> 4.2М", UiFmt.short(4200000), "4.2М")
	panel.queue_free()


func _test_screen_tabs() -> void:
	print("--- Экран: вкладки ---")
	GameState.reset_progress()
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := ProgressScreen.new()
	layer.add_child(screen)
	check("экран зарегистрировал себя", ProgressScreen.instance() == screen)
	check("экран скрыт, пока не открыт", not ProgressScreen.is_open())
	ProgressScreen.open("progress")
	check("open(\"progress\") открывает экран (так зовёт HUD)", ProgressScreen.is_open())
	check_eq("текущая вкладка — навыки", screen._current_tab, "progress")
	screen.open_tab("records")
	check_eq("«records» — это вкладка героя", screen._current_tab, "hero")
	screen.open_tab("museum")
	check_eq("музей", screen._current_tab, "museum")
	screen.open_tab("нет_такой")
	check_eq("неизвестная вкладка → навыки", screen._current_tab, "progress")
	check_eq("три вкладки с иконками", screen._tab_buttons.size(), 3)
	GameState.skill_points_available = 5
	screen._sync_tabs()
	check_eq("значок на вкладке навыков = свободные очки", (screen._tab_buttons["progress"] as HeroTabButton).badge, 5)
	var text_tabs := 0
	for b in screen._tab_buttons.values():
		if (b as Button).text != "":
			text_tabs += 1
	check_eq("на вкладках нет подписей, только иконки", text_tabs, 0)
	screen.close()
	check("экран закрыт", not ProgressScreen.is_open())
	ProgressScreen.new_museum_panel().queue_free()
	layer.queue_free()


func _test_card_queue() -> void:
	print("--- Карточка находки ---")
	# Без экрана (тесты, режим без интерфейса) показ не должен падать.
	ArtifactCard.show_find("legends_2")
	ArtifactCard.show_branch(3)
	check("без карточки на сцене вызовы безопасны", ArtifactCard.instance() == null)

	var layer := CanvasLayer.new()
	add_child(layer)
	var card := ArtifactCard.new()
	layer.add_child(card)
	check("карточка зарегистрировалась", ArtifactCard.instance() == card)
	check("до первой находки карточки не видно", not card.visible)
	ArtifactCard.show_find("antiquity_3")
	ArtifactCard.show_branch(1)
	check("после находки карточка видна", card.visible)
	check_eq("вторая карточка ждёт в очереди", card._queue.size(), 1)
	card._done()
	check("ветка показывается после предмета", card._entry.get("kind", "") == "branch")
	card._done()
	check("очередь пуста — карточка спрятана", not card.visible)
	layer.queue_free()

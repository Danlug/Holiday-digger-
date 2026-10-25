extends Node
## test_skills — дерево навыков, раунд 4 (ГДД §11):
##  * требования-предки (поле requires в data/upgrades.json): «Удача — множитель»
##    открывается после ступени «Удачи — шанс»; покупка без предка отклоняется;
##  * старый сейв с множителем, купленным без шанса, не ломается: ступень остаётся;
##  * нарастающие очки за уровни (таблица) и доплата старым сейвам;
##  * дерево: порядок колонок, замок со значком предка, место под девятую колонку.
##
## Запуск: godot --headless --path . res://tests/test_skills.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func check_eq(name: String, got, want) -> void:
	check("%s (получено=%s, ожидалось=%s)" % [name, str(got), str(want)] if got != want else name, got == want)


func _ready() -> void:
	print("=== test_skills ===")
	for _i in range(3):
		await get_tree().process_frame
	_test_requirement_data()
	_test_buy_needs_ancestor()
	_test_generic_requirement()
	_test_points_table()
	_test_level_up_points()
	_test_old_save()
	await _test_tree_view()
	await _test_room_for_more_columns()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _fresh(points: int = 1000) -> void:
	GameState.reset_progress()
	GameState.skill_points_available = points


# ---------------------------------------------------------------------------
# Требования
# ---------------------------------------------------------------------------

func _test_requirement_data() -> void:
	print("--- requires в data/upgrades.json ---")
	check_eq("множитель удачи требует ступень 1 шанса",
		Balance.get_upgrade_requirements("luck_multiplier"), [{"branch": "luck_chance", "stage": 1}])
	check_eq("у шанса удачи предков нет", Balance.get_upgrade_requirements("luck_chance"), [])
	check_eq("у неизвестной ветки предков нет", Balance.get_upgrade_requirements("нет_такой"), [])
	# Ступени множителя не сдвигались (решение владельца): ×2 → ×3 → ×4.
	check_eq("множитель по-прежнему ×2/×3/×4", [Balance.get_lucky_find_multiplier(1),
		Balance.get_lucky_find_multiplier(2), Balance.get_lucky_find_multiplier(3)], [2, 3, 4])


func _test_buy_needs_ancestor() -> void:
	print("--- Покупка без предка отклоняется ---")
	_fresh(1000)
	check_eq("без шанса множитель не открыт",
		GameState.unmet_skill_requirements("luck_multiplier"), [{"branch": "luck_chance", "stage": 1}])
	check("GameState.spend_skill_point отказывает", not GameState.spend_skill_point("luck_multiplier"))
	check("SkillTree.try_buy отказывает", not SkillTree.try_buy("luck_multiplier", false))
	check_eq("очки не списаны", GameState.skill_points_available, 1000)
	check_eq("ступень множителя 0", GameState.get_skill_stage("luck_multiplier"), 0)
	check("шанс покупается без условий", SkillTree.try_buy("luck_chance", false))
	check("после ступени шанса требований нет", GameState.unmet_skill_requirements("luck_multiplier").is_empty())
	var cost := Balance.get_upgrade_stage_cost("luck_multiplier", 1)
	var before: int = GameState.skill_points_available
	check("теперь множитель покупается", SkillTree.try_buy("luck_multiplier", false))
	check_eq("списано по цене ступени", before - GameState.skill_points_available, cost)
	check("и дальше по ступеням", SkillTree.try_buy("luck_multiplier", false)
		and GameState.get_skill_stage("luck_multiplier") == 2)


## Механизм общий: любая ветка, любая минимальная ступень предка.
func _test_generic_requirement() -> void:
	print("--- Требование в общем виде: ветка и минимальная ступень ---")
	var hp := Balance.get_upgrade_branch("hp")
	hp["requires"] = [{"branch": "vision", "stage": {"value": 2, "proposed": true}}]
	_fresh(1000)
	check("HP закрыто без «Обзора»", not GameState.spend_skill_point("hp"))
	GameState.spend_skill_point("vision")
	check("одной ступени предка мало, нужно две", not GameState.spend_skill_point("hp"))
	check_eq("причина — та же ветка и ступень",
		GameState.unmet_skill_requirements("hp"), [{"branch": "vision", "stage": 2}])
	GameState.spend_skill_point("vision")
	check("со второй ступенью предка HP открыто", GameState.spend_skill_point("hp"))
	check("в подсказке названа ветка и ступень",
		SkillTree.requirements_text([{"branch": "vision", "stage": 2}]).contains("«Обзор», ступень 2"))
	hp.erase("requires")
	check("без поля requires требований нет", Balance.get_upgrade_requirements("hp").is_empty())


# ---------------------------------------------------------------------------
# Очки за уровни
# ---------------------------------------------------------------------------

func _test_points_table() -> void:
	print("--- Очки за уровни: таблица ---")
	var same_early := true
	for l in range(1, 11):
		if Balance.skill_points_total(l) != Balance.skill_points_total(l, true):
			same_early = false
	check("до 10-го уровня — как раньше (ранние уровни не щедрее)", same_early)
	# уровень → очков за него, накоплено к нему (ГДД §11, таблица)
	var table := {2: [1, 1], 5: [3, 6], 10: [3, 13], 11: [2, 15], 15: [4, 25], 25: [4, 49],
		26: [3, 52], 30: [5, 66], 50: [5, 134], 75: [5, 219], 100: [5, 304]}
	var bad: Array = []
	for l: int in table.keys():
		var got := [Balance.skill_points_for_level(l), Balance.skill_points_total(l)]
		if got != table[l]:
			bad.append("%d: %s вместо %s" % [l, str(got), str(table[l])])
	check_eq("таблица «уровень → очков, накоплено»", bad, [])
	var grows := true
	for l in range(3, 101):
		var base := Balance.skill_points_for_level(l) - (2 if l % 5 == 0 else 0)
		var prev := Balance.skill_points_for_level(l - 1) - (2 if (l - 1) % 5 == 0 else 0)
		if base < prev:
			grows = false
	check("очков за уровень со временем только больше", grows)
	check("к сотому больше прежних 139", Balance.skill_points_total(100) > Balance.skill_points_total(100, true))
	check_eq("прежнее правило к сотому — 139", Balance.skill_points_total(100, true), 139)
	var tree := Balance.get_upgrade_tree_total_cost()
	check("всё дерево к сотому не купить — билд выбирать (%d из %d)" % [Balance.skill_points_total(100), tree],
		Balance.skill_points_total(100) < int(tree * 0.7))
	var cheapest := 1 << 30
	for b: Dictionary in Balance.upgrades.get("branches", []):
		cheapest = mini(cheapest, Balance.get_upgrade_total_cost(String(b["id"]), int(b["stages"])))
	var most := 0
	for l in range(2, 101):
		most = maxi(most, Balance.skill_points_for_level(l))
	check("один уровень не закрывает ни одну ветку целиком (%d < %d)" % [most, cheapest], most < cheapest)


func _test_level_up_points() -> void:
	print("--- Уровни в игре дают очки по таблице ---")
	_fresh(0)
	var got: Dictionary = {}
	var on_level := func(lvl: int, pts: int) -> void: got[lvl] = pts
	GameState.leveled_up.connect(on_level)
	var need := 0
	for n in range(1, 11):
		need += Balance.xp_required_for_level(n)
	GameState.add_xp(need)
	GameState.leveled_up.disconnect(on_level)
	check_eq("уровень 11", GameState.level, 11)
	check_eq("сигнал несёт очки уровня (5-й, 10-й, 11-й)", [got.get(5), got.get(10), got.get(11)], [3, 3, 2])
	check_eq("очков накоплено по таблице", GameState.skill_points_available, Balance.skill_points_total(11))
	check_eq("сейв помечен новым правилом", int(GameState.ext_get(GameState.SKILL_POINTS_EXT, 0)),
		GameState.SKILL_POINTS_RULE)
	check_eq("помеченному сейву доплаты нет", GameState.top_up_skill_points(), 0)


# ---------------------------------------------------------------------------
# Старый сейв
# ---------------------------------------------------------------------------

func _test_old_save() -> void:
	print("--- Старый сейв: множитель без шанса и очки по старому правилу ---")
	_fresh(5)
	GameState.level = 30
	GameState.skill_stages = {"luck_multiplier": 1, "hp": 2}
	GameState.ext.erase(GameState.SKILL_POINTS_EXT)  # сейв до раунда 4 пометки не знает
	check("сейв записан", SaveSystem.save_game())
	GameState.reset_progress()
	check("сейв прочитан", SaveSystem.load_game())
	check_eq("купленная ступень множителя осталась", GameState.get_skill_stage("luck_multiplier"), 1)
	check_eq("остальные ступени целы", GameState.get_skill_stage("hp"), 2)
	var diff := Balance.skill_points_total(30) - Balance.skill_points_total(30, true)
	check_eq("доплачена разница правил за 30 уровней (+%d)" % diff, GameState.skill_points_available, 5 + diff)
	check("следующая ступень множителя ждёт шанса", not GameState.spend_skill_point("luck_multiplier"))
	check("удача по-прежнему считается: без шанса броска нет",
		Balance.luck_find_multiplier(0.0, true, GameState.get_skill_stage("luck_chance"), 1) == 1)
	check("шанс куплен — множитель качается дальше", GameState.spend_skill_point("luck_chance")
		and GameState.spend_skill_point("luck_multiplier") and GameState.get_skill_stage("luck_multiplier") == 2)
	# Повторная загрузка второй раз не доплачивает.
	var pts: int = GameState.skill_points_available
	SaveSystem.save_game()
	GameState.reset_progress()
	SaveSystem.load_game()
	check_eq("вторая загрузка ничего не добавила", GameState.skill_points_available, pts)
	# Ранний сейв (уровень ≤ 10) ничего не получает: правила там совпадают.
	_fresh(2)
	GameState.level = 8
	GameState.ext.erase(GameState.SKILL_POINTS_EXT)
	SaveSystem.save_game()
	GameState.reset_progress()
	SaveSystem.load_game()
	check_eq("сейву 8-го уровня доплаты нет", GameState.skill_points_available, 2)
	SaveSystem.delete_save()


# ---------------------------------------------------------------------------
# Дерево
# ---------------------------------------------------------------------------

func _make_tree() -> SkillTree:
	var tree := SkillTree.new()
	tree.save_on_buy = false
	tree.size = Vector2(216, 460)
	add_child(tree)
	return tree


func _nodes(tree: SkillTree, id: String) -> Array:
	var out: Array = []
	for c in tree.get_children():
		if c is SkillNode and (c as SkillNode).branch_id == id:
			out.append(c)
	return out


func _head(tree: SkillTree, id: String) -> Control:
	for c in tree.get_children():
		if c is Button and not (c is SkillNode) and c.get_meta("branch_id", "") == id:
			return c
	return null


func _test_tree_view() -> void:
	print("--- Дерево: замок со значком предка, связь, порядок ---")
	_fresh(100)
	var order: Array = []
	for b: Dictionary in SkillTree.display_order(Balance.upgrades.get("branches", [])):
		order.append(String(b["id"]))
	check("множитель стоит сразу за шансом", order.find("luck_multiplier") == order.find("luck_chance") + 1)
	check_eq("веток в дереве столько же, сколько в данных", order.size(), Balance.upgrades.get("branches", []).size())

	var tree := _make_tree()
	await get_tree().process_frame
	var mult := _nodes(tree, "luck_multiplier")
	var chance := _nodes(tree, "luck_chance")
	check_eq("первая ступень множителя — замок предка", mult[0].state, SkillNode.State.BLOCKED)
	check_eq("значок в углу — ветка «Удача — шанс»", mult[0].need_branch, "luck_chance")
	check_eq("дальше — обычный замок", mult[1].state, SkillNode.State.LOCKED)
	check("ступени множителя начинаются ниже первой ступени шанса",
		mult[0].position.y > chance[0].position.y + 10.0)
	check("колонка множителя правее шанса", mult[0].position.x > chance[0].position.x)
	var tip: Dictionary = mult[0].get_meta(Tip.META)
	check("подсказка объясняет причину", String(tip.get("extra", "")).contains("Удача — шанс"))
	var head_tip: Dictionary = _head(tree, "luck_multiplier").get_meta(Tip.META)
	check("подсказка ветки — когда откроется", String(head_tip.get("extra", "")).contains("Откроется после"))
	mult[0].pressed.emit()
	mult[0].pressed.emit()
	check_eq("нажатия по замку ничего не купили", GameState.get_skill_stage("luck_multiplier"), 0)
	check_eq("и очки целы", GameState.skill_points_available, 100)

	chance[0].pressed.emit()
	chance[0].pressed.emit()
	check_eq("шанс куплен двумя нажатиями", GameState.get_skill_stage("luck_chance"), 1)
	check_eq("множитель открылся: следующая ступень по карману", mult[0].state, SkillNode.State.NEXT_READY)
	check("причина из подсказки ушла", not String((mult[0].get_meta(Tip.META) as Dictionary).get("extra", "")).contains("Сначала"))

	# Старый сейв: множитель куплен без шанса — ступень видна купленной, следующая ждёт предка.
	GameState.skill_stages = {"luck_multiplier": 1}
	tree.refresh()
	check_eq("купленная без предка ступень видна купленной", mult[0].state, SkillNode.State.DONE)
	check_eq("следующая — замок предка", mult[1].state, SkillNode.State.BLOCKED)
	tree.queue_free()


## Ветка «Жадность» (агент greed) — девятая колонка; запас — и десятая.
func _test_room_for_more_columns() -> void:
	print("--- Место под девятую и десятую колонки ---")
	var branches: Array = Balance.upgrades["branches"]
	var saved := branches.duplicate()
	for extra in ["test_extra_a", "test_extra_b"]:
		if Balance.get_upgrade_branch(extra).is_empty():
			branches.append({"id": extra, "name_ru": "Проба", "stages": 5, "effect": {}, "cost_points": [1, 2, 3, 4, 5]})
		_fresh(10)
		var tree := _make_tree()
		await get_tree().process_frame
		var cols: Dictionary = {}
		for c in tree.get_children():
			if c is SkillNode and c.stage == 1:
				cols[c.branch_id] = c
		var rects: Array = []
		for id in cols:
			rects.append(Rect2(cols[id].position, cols[id].size))
		rects.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
		var ok := rects.size() == branches.size()
		for i in range(rects.size()):
			var r: Rect2 = rects[i]
			if r.size.x < SkillTree.MIN_NODE or r.position.x < 0.0 or r.end.x > 216.0:
				ok = false
			if i > 0 and r.position.x < (rects[i - 1] as Rect2).end.x + 1.0:
				ok = false
		check("%d колонок: все в 216 точках, узлы ≥ %d и не слипаются (сторона %.1f)" % [
			branches.size(), int(SkillTree.MIN_NODE), rects[0].size.x if not rects.is_empty() else 0.0], ok)
		tree.queue_free()
		await get_tree().process_frame
	branches.clear()
	branches.append_array(saved)

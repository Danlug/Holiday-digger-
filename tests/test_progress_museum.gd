extends Node
## test_progress_museum — прокачка, спавн артефактов, музей и рекорды.
##
## Запускается как сцена, а не через --script: проверкам нужны автолоады
## (GameState/Balance), а SceneTree с --script их не поднимает (та же причина,
## что у tests/test_player_harness.gd):
##   godot --headless --path . res://tests/test_progress_museum.tscn
## Код возврата 0 — всё зелено, 1 — есть провалы.

var failures := 0
var total := 0
var world: WorldGen
var player


func _ready() -> void:
	print("=== test_progress_museum ===")
	world = WorldGen.new(4242)
	GameState.world_ref = world
	GameState.world_seed = 4242
	GameState.reset_progress()

	player = load("res://scripts/player/player.gd").new()
	player.world = world
	add_child(player)

	_test_spend_point_applies_effect()
	_test_point_is_spent_only_once()
	_test_costs_follow_gdd()
	_test_artifact_cells_are_in_their_depth_band()
	_test_artifact_is_found_and_goes_to_museum()
	_test_branch_completion()
	_test_museum_panel_shows_all_slots()
	_test_records()
	_test_save_survives_restart()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", label])


func check_eq(label: String, actual, expected) -> void:
	check("%s (получено=%s, ожидалось=%s)" % [label, actual, expected], actual == expected)


func check_near(label: String, actual: float, expected: float, tol: float = 0.001) -> void:
	check("%s (получено=%s, ожидалось=%s)" % [label, actual, expected], absf(actual - expected) <= tol)


# ---------------------------------------------------------------------------
# Прокачка
# ---------------------------------------------------------------------------

## Очко тратится — и эффект сразу виден в тех же функциях, которыми пользуется
## игра (грузоподъёмность, радиус тумана, время копки, максимум HP).
func _test_spend_point_applies_effect() -> void:
	print("--- Очко прокачки применяется ---")
	GameState.reset_progress()
	GameState.skill_points_available = 50

	var carry_before := GameState.get_max_carry_kg()
	check("сила куплена", GameState.spend_skill_point("strength"))
	check_near("грузоподъёмность выросла на 8 кг", GameState.get_max_carry_kg(), carry_before + 8.0)

	var radius_before := GameState.get_vision_terrain_radius()
	check("видимость рельефа куплена", GameState.spend_skill_point("terrain_vision"))
	check_eq("радиус обзора рельефа +1", GameState.get_vision_terrain_radius(), radius_before + 1)

	var dig_before := Balance.get_dig_time_seconds(GameState.get_skill_stage("dig_speed"))
	check("скорость копки куплена", GameState.spend_skill_point("dig_speed"))
	check("копка стала быстрее",
		Balance.get_dig_time_seconds(GameState.get_skill_stage("dig_speed")) < dig_before)

	var hp_before := GameState.get_max_hp()
	check("HP куплено", GameState.spend_skill_point("hp"))
	check_near("максимум HP вырос на 20", GameState.get_max_hp(), hp_before + 20.0)

	check("удача-множитель куплена", GameState.spend_skill_point("luck_multiplier"))
	check_near("множитель удачи стал ×2", Balance.get_luck_multiplier(GameState.get_skill_stage("luck_multiplier")), 2.0)

	# Выносливость и голод: эффект живёт в UpgradeEffects (ядро их не считает),
	# проверяем, что возвращаемая доля растёт со ступенью и не выходит за рамки.
	var effects := UpgradeEffects.new()
	add_child(effects)
	check_near("без прокачки выносливости ничего не возвращается",
		effects._saved_fraction("stamina", 0), 0.0)
	check_near("ступень 1 выносливости экономит 13% расхода",
		effects._saved_fraction("stamina", 1), 1.0 - 1.0 / 1.15, 0.001)
	check_near("ступень 10 голода экономит 80% расхода",
		effects._saved_fraction("hunger", 10), 0.8, 0.001)
	effects.queue_free()


## Одно и то же очко нельзя потратить дважды: после покупки баланс очков
## падает ровно на цену, а без очков ступень не растёт.
func _test_point_is_spent_only_once() -> void:
	print("--- Очко тратится ровно один раз ---")
	GameState.reset_progress()
	var cost := Balance.get_upgrade_stage_cost("terrain_vision", 1)
	GameState.skill_points_available = cost

	check("первая покупка проходит", GameState.spend_skill_point("terrain_vision"))
	check_eq("очки списаны ровно по цене", GameState.skill_points_available, 0)
	check_eq("ступень поднялась на 1", GameState.get_skill_stage("terrain_vision"), 1)

	check("вторая покупка без очков отклонена", not GameState.spend_skill_point("terrain_vision"))
	check_eq("ступень не изменилась", GameState.get_skill_stage("terrain_vision"), 1)
	check_eq("очки не ушли в минус", GameState.skill_points_available, 0)

	# Ветка на максимуме больше ничего не берёт, даже когда очков вагон.
	GameState.skill_points_available = 10000
	var stages := int(Balance.get_upgrade_branch("luck_multiplier").get("stages", 0))
	for i in range(stages):
		GameState.spend_skill_point("luck_multiplier")
	var points_at_max: int = GameState.skill_points_available
	check("на максимуме ступеней покупка отклонена", not GameState.spend_skill_point("luck_multiplier"))
	check_eq("очки за отклонённую покупку не списаны", GameState.skill_points_available, points_at_max)
	check_eq("ступеней ровно максимум", GameState.get_skill_stage("luck_multiplier"), stages)


## Цены ступеней из ГДД раздела 11 и суммарная стоимость полной прокачки.
func _test_costs_follow_gdd() -> void:
	print("--- Цены ступеней ---")
	check_eq("видимость рельефа: 1-я ступень стоит 1", Balance.get_upgrade_stage_cost("terrain_vision", 1), 1)
	check_eq("видимость ресурсов: 1-я ступень стоит 2", Balance.get_upgrade_stage_cost("resource_vision", 1), 2)
	check_eq("удача-множитель: ступени 8/16/32",
		[Balance.get_upgrade_stage_cost("luck_multiplier", 1),
		 Balance.get_upgrade_stage_cost("luck_multiplier", 2),
		 Balance.get_upgrade_stage_cost("luck_multiplier", 3)], [8, 16, 32])

	var all_branches := 0
	for b in Balance.upgrades.get("branches", []):
		all_branches += Balance.get_upgrade_total_cost(String(b.get("id", "")), int(b.get("stages", 0)))
	# ГДД: "на полную прокачку нужно ~500 очков при 140 доступных".
	check("полная прокачка стоит около 500 очков (%d)" % all_branches,
		all_branches > 400 and all_branches < 700)


# ---------------------------------------------------------------------------
# Артефакты
# ---------------------------------------------------------------------------

## Каждый артефакт лежит в своей полосе глубин и внутри мира по ширине.
func _test_artifact_cells_are_in_their_depth_band() -> void:
	print("--- Клетки артефактов в своей полосе ---")
	var artifacts: Array = Balance.artifacts.get("artifacts", [])
	check_eq("артефактов ровно 25 (5 веток × 5)", artifacts.size(), 25)

	var all_in_band := true
	var all_in_width := true
	var all_have_cells := true
	for a in artifacts:
		var band := ArtifactSpawn.depth_range(a)
		var cells := ArtifactSpawn.candidate_cells(a, 4242)
		if cells.is_empty():
			all_have_cells = false
		for cell: Vector2i in cells:
			if cell.y < band.x or cell.y > band.y:
				all_in_band = false
			if cell.x < 0 or cell.x >= ArtifactSpawn.WORLD_WIDTH:
				all_in_width = false
	check("у каждого артефакта есть хотя бы одна клетка", all_have_cells)
	check("все клетки внутри своей полосы глубин", all_in_band)
	check("все клетки внутри ширины мира 0..31", all_in_width)

	# Полосы глубин веток совпадают с таблицей ГДД раздела 10.
	var antiquity := Balance.get_artifacts_in_branch(1)
	check_eq("ветка 1 начинается с глубины 15", ArtifactSpawn.depth_range(antiquity[0]).x, 15)
	var legends := Balance.get_artifacts_in_branch(5)
	check_eq("последний артефакт легенд на 3850–4100",
		ArtifactSpawn.depth_range(legends[4]), Vector2i(3850, 4100))

	# Скриптовая находка онбординга лежит во всём ряду 15 — её нельзя пропустить.
	check_eq("Никчёмный клад занимает весь ряд 15",
		ArtifactSpawn.candidate_cells(antiquity[0], 4242).size(), ArtifactSpawn.WORLD_WIDTH)

	# Один и тот же сид — те же клетки, разный сид — другие.
	var same_a := ArtifactSpawn.candidate_cells(antiquity[2], 4242)
	var same_b := ArtifactSpawn.candidate_cells(antiquity[2], 4242)
	var other := ArtifactSpawn.candidate_cells(antiquity[2], 777)
	check("позиции детерминированы от сида", same_a == same_b)
	check("другой сид — другие позиции", same_a != other)

	# Редкость растёт с эпохой: на одну клетку раскопок в полосе ветки 5
	# приходится заметно меньше шансов, чем в полосе ветки 1.
	var chance_b1 := _find_chance_per_cell(antiquity[2])
	var chance_b5 := _find_chance_per_cell(legends[2])
	check("артефакты легенд реже античных (%.5f против %.5f)" % [chance_b5, chance_b1],
		chance_b5 < chance_b1)


func _find_chance_per_cell(artifact: Dictionary) -> float:
	var band := ArtifactSpawn.depth_range(artifact)
	var cells := float((band.y - band.x + 1) * ArtifactSpawn.WORLD_WIDTH)
	return float(ArtifactSpawn.candidate_count(artifact)) / cells


## Артефакт находится при раскопке своей клетки и попадает в музей
## (GameState.collected_artifacts — то, что рисует витрина), а вместе с ним
## приходят опыт и монеты за находку.
func _test_artifact_is_found_and_goes_to_museum() -> void:
	print("--- Находка попадает в музей ---")
	GameState.reset_progress()
	var finder := ArtifactFinder.new()
	add_child(finder)
	finder.setup(null, null)

	var artifact: Dictionary = Balance.get_artifacts_in_branch(1)[1]  # Религиозный свиток
	var id := String(artifact["id"])
	var cell: Vector2i = ArtifactSpawn.candidate_cells(artifact, GameState.world_seed)[0]

	check_eq("в клетке артефакта лежит именно он", finder.artifact_at(cell.x, cell.y), id)
	check_eq("в соседней клетке артефакта нет",
		finder.artifact_at((cell.x + 5) % ArtifactSpawn.WORLD_WIDTH, cell.y + 3), "")

	var xp_before: int = GameState.xp
	var coins_before: int = GameState.coins
	check_eq("раскопка клетки выдала артефакт", finder.claim_at(cell.x, cell.y), id)
	check("артефакт лежит в музее", GameState.collected_artifacts.has(id))
	check("опыт за находку начислен", GameState.xp > xp_before or GameState.level > 1)
	check_eq("монеты за находку начислены",
		GameState.coins - coins_before, Balance.get_artifact_find_coins(id))

	check_eq("повторная раскопка той же клетки ничего не даёт", finder.claim_at(cell.x, cell.y), "")
	check_eq("артефакт в музее ровно один раз", GameState.collected_artifacts.count(id), 1)

	# Тот же путь, но целиком: сигнал игрока о завершённой копке -> находка.
	# Так связка проверяется ровно в том виде, в каком она работает в игре.
	var artifact2: Dictionary = Balance.get_artifacts_in_branch(1)[2]
	var id2 := String(artifact2["id"])
	var cell2: Vector2i = ArtifactSpawn.candidate_cells(artifact2, GameState.world_seed)[0]
	finder.setup(player, null)
	player.dig_finished.emit(cell2.x, cell2.y, TileTypes.Type.DIRT, "earth", false, 0)
	check("находка приходит по сигналу игрока dig_finished",
		GameState.collected_artifacts.has(id2))
	finder.queue_free()


## Закрытие ветки: пятый предмет достраивает комплект и приносит награду.
func _test_branch_completion() -> void:
	print("--- Закрытие ветки ---")
	GameState.reset_progress()
	var items := Balance.get_artifacts_in_branch(1)
	var coins_before: int = GameState.coins
	for a in items:
		GameState.collect_artifact(String(a["id"]))
	check("ветка 1 отмечена собранной", GameState.completed_branches.has(1))
	check("награда за ветку больше суммы находок",
		GameState.coins - coins_before > _sum_find_coins(items))
	check("ветка считается закрытой и в Balance",
		Balance.is_branch_complete(1, GameState.collected_artifacts))
	check("ветка 2 ещё не закрыта",
		not Balance.is_branch_complete(2, GameState.collected_artifacts))


func _sum_find_coins(items: Array) -> int:
	var sum := 0
	for a in items:
		sum += Balance.get_artifact_find_coins(String(a["id"]))
	return sum


## Витрина строит все 25 слотов и ультимативный сет из пяти пятых предметов.
func _test_museum_panel_shows_all_slots() -> void:
	print("--- Витрина музея ---")
	GameState.reset_progress()
	GameState.collect_artifact("antiquity_1")

	var panel := MuseumPanel.new()
	add_child(panel)
	var slot_count := _count_buttons(panel)
	# 25 слотов витрины + 5 слотов ультимативного сета (те же предметы,
	# показанные отдельной строкой).
	check_eq("на экране 30 слотов (25 предметов + 5 в сете)", slot_count, 30)

	var set_pieces: Array = Balance.artifacts.get("ultimate_set", {}).get("pieces", [])
	check_eq("в ультимативном сете пять частей", set_pieces.size(), 5)
	var ultimate_ids: Array = []
	for a in Balance.artifacts.get("artifacts", []):
		if bool(a.get("is_ultimate_set_piece", false)):
			ultimate_ids.append(String(a["id"]))
	check_eq("частей сета ровно пять — пятые предметы веток", ultimate_ids.size(), 5)
	check("сет собран из пятых предметов всех веток",
		ultimate_ids.has("antiquity_5") and ultimate_ids.has("legends_5"))

	# Спрайтов артефактов ещё нет — витрина обязана открываться и без них.
	check("витрина работает без спрайтов (заглушка вместо картинки)",
		not ArtifactArt.has_art("antiquity_1"))
	check_eq("инициалы для заглушки", ArtifactArt.placeholder_initials("Религиозный свиток"), "РС")
	panel.queue_free()


func _count_buttons(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is Button and child.custom_minimum_size.x == MuseumPanel.SLOT:
			count += 1
		count += _count_buttons(child)
	return count


# ---------------------------------------------------------------------------
# Рекорды
# ---------------------------------------------------------------------------

func _test_records() -> void:
	print("--- Локальные рекорды ---")
	GameState.reset_progress()
	var store := RecordsStore.new()
	add_child(store)
	store.reset()

	GameState.add_coins(1000)
	check_eq("заработанные монеты попали в рекорд", store.lifetime_coins_earned, 1000)
	GameState.spend_coins(400)
	check_eq("трата монет рекорд не уменьшает", store.lifetime_coins_earned, 1000)

	store._on_dig_finished(0, 10, 0, "iron_ore", true, 5)
	store._on_dig_finished(0, 11, 0, "iron_ore", true, 5)
	store._on_dig_finished(0, 12, 0, "gold", true, 100)
	check_eq("открыто два разных минерала", store.get_discovered_minerals_count(), 2)
	check("процент открытых минералов больше нуля", store.get_minerals_percent() > 0.0)
	check_eq("всего добываемых минералов", store.get_total_minerals(), 28)

	GameState.add_item("gold", 3)
	store._credit_haul()
	check_eq("вынесенное оценено по ценам минералов",
		store.lifetime_hauled_value, Balance.get_mineral_price("gold") * 3)
	store._credit_haul()
	check_eq("повторный подъём с тем же рюкзаком не удваивает богатство",
		store.lifetime_hauled_value, Balance.get_mineral_price("gold") * 3)
	check_eq("богатство = заработано + вынесено",
		store.get_wealth(), store.lifetime_coins_earned + store.lifetime_hauled_value)

	GameState.collect_artifact("antiquity_1")
	check_near("процент артефактов = 1 из 25", store.get_artifacts_percent(), 4.0, 0.01)
	store.queue_free()


# ---------------------------------------------------------------------------
# Сохранение
# ---------------------------------------------------------------------------

## Перезапуск: потраченные очки, ступени и содержимое музея переживают
## запись на диск и чтение обратно. Рекорды лежат в своём файле — проверяем
## его отдельно тем же способом.
func _test_save_survives_restart() -> void:
	print("--- Сохранение переживает перезапуск ---")
	GameState.reset_progress()
	GameState.skill_points_available = 30
	GameState.spend_skill_point("strength")
	GameState.spend_skill_point("strength")
	GameState.spend_skill_point("hunger")
	GameState.collect_artifact("antiquity_1")
	GameState.collect_artifact("mysticism_1")
	GameState.add_xp(250)

	var strength_stage := GameState.get_skill_stage("strength")
	var hunger_stage := GameState.get_skill_stage("hunger")
	var points_left: int = GameState.skill_points_available
	var carry := GameState.get_max_carry_kg()
	var artifacts := GameState.collected_artifacts.duplicate()
	var level: int = GameState.level

	check("сейв записан", SaveSystem.save_game())

	# Имитация перезапуска: состояние обнуляется так же, как при старте
	# процесса, после чего сейв читается заново.
	GameState.reset_progress()
	check_eq("после обнуления ступеней нет", GameState.get_skill_stage("strength"), 0)
	check("сейв прочитан", SaveSystem.load_game())

	check_eq("ступень силы восстановлена", GameState.get_skill_stage("strength"), strength_stage)
	check_eq("ступень голода восстановлена", GameState.get_skill_stage("hunger"), hunger_stage)
	check_eq("остаток очков восстановлен", GameState.skill_points_available, points_left)
	check_near("эффект силы действует после загрузки", GameState.get_max_carry_kg(), carry)
	check_eq("уровень восстановлен", GameState.level, level)
	check_eq("музей восстановлен", GameState.collected_artifacts, artifacts)

	var store := RecordsStore.new()
	add_child(store)
	store.reset()
	store.lifetime_coins_earned = 4321
	store.discovered_minerals = ["gold", "iron_ore", "peat"]
	store.best_haul_value = 900
	check("файл рекордов записан", store.save_records())
	store.lifetime_coins_earned = 0
	store.discovered_minerals = []
	store.best_haul_value = 0
	check("файл рекордов прочитан", store.load_records())
	check_eq("заработок пережил перезапуск", store.lifetime_coins_earned, 4321)
	check_eq("открытые минералы пережили перезапуск", store.get_discovered_minerals_count(), 3)
	check_eq("лучшая ходка пережила перезапуск", store.best_haul_value, 900)
	store.reset()
	store.queue_free()
	SaveSystem.delete_save()

extends SceneTree
## Headless-тест генерации мира. Запуск:
##   godot --headless --script res://tests/test_world_gen.gd
## Не использует автозагрузки и сцены — только WorldGen/TileTypes/FogOfWar/
## CollapseEvents напрямую (все доступны глобально через class_name).

var checks := 0
var failures := 0


func _init() -> void:
	print("=== test_world_gen: старт ===")
	test_determinism()
	test_layer_percentages_shallow()
	test_deep_void_and_stone()
	test_ore_density_corridors()
	test_gold_and_peat_ramp_grow()
	test_foundation_solid()
	test_scripted_diamond()
	test_staircase()
	test_peat_seam_solid()
	test_all_solid_tiles_are_pickaxe_diggable()
	test_fog_basic()
	test_collapse_and_earthquake()
	print("=== Итог: %d проверок, %d провалов ===" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("  OK    ", label)
	else:
		failures += 1
		print("  FAIL  ", label)


func check_range(label: String, value: float, lo: float, hi: float) -> void:
	check("%s (значение %.4f, ожидалось [%.4f; %.4f])" % [label, value, lo, hi], value >= lo and value <= hi)


# ============================== ДЕТЕРМИНИЗМ ==============================

func test_determinism() -> void:
	print("-- Детерминизм генерации --")
	var a := WorldGen.new(12345)
	var b := WorldGen.new(12345)
	var mismatches := 0
	var coords: Array = []
	for i in range(2000):
		coords.append(Vector2i(i % WorldGen.WIDTH, 1 + (i * 37) % 3000))
	# запрашиваем клетки у "a" в прямом порядке, у "b" в перемешанном —
	# результат не должен зависеть от порядка вызовов (чистая функция)
	var shuffled := coords.duplicate()
	shuffled.shuffle()
	for c in coords:
		if a.get_tile(c.x, c.y) != b.get_tile(c.x, c.y):
			mismatches += 1
	for c in shuffled:
		var again := b.get_tile(c.x, c.y)
		var first := a.get_tile(c.x, c.y)
		if again != first:
			mismatches += 1
	check("get_tile(seed=12345) идентичен между экземплярами и порядку вызовов", mismatches == 0)

	# один и тот же seed, тот же инстанс, повторные вызовы — стабильность
	var w := WorldGen.new(777)
	var first_pass: Array = []
	for c in coords:
		first_pass.append(w.get_tile(c.x, c.y))
	var stable := true
	for i in range(coords.size()):
		if w.get_tile(coords[i].x, coords[i].y) != first_pass[i]:
			stable = false
			break
	check("повторные вызовы get_tile на одном экземпляре стабильны", stable)

	var w2 := WorldGen.new(999999)
	var different := 0
	for c in coords:
		if w.get_tile(c.x, c.y) != w2.get_tile(c.x, c.y):
			different += 1
	check("разные seed дают разный ландшафт (не константа)", different > coords.size() / 4)


# ============================== ПРОЦЕНТЫ ПО СЛОЯМ ==============================
## Для 1-2 строк на seed выборки не хватает — гоняем много seed'ов на
## фиксированной узкой полосе глубины, это эквивалентно многократному
## пересэмплированию тех же вероятностей.

func _stone_fraction(w: WorldGen, y_min: int, y_max: int, seeds: int) -> float:
	var hit := 0
	var total := 0
	for s in range(seeds):
		w.world_seed = s * 7919 + 1
		for y in range(y_min, y_max + 1):
			for x in range(WorldGen.WIDTH):
				total += 1
				if w.get_tile(x, y) == TileTypes.Type.STONE:
					hit += 1
	return float(hit) / float(total)


func test_layer_percentages_shallow() -> void:
	print("-- Плотность камня, слои 1-4 --")
	var w := WorldGen.new(1)
	check_range("камень на глубине 1 (ожидание 3%)", _stone_fraction(w, 1, 1, 400), 0.01, 0.06)
	check_range("камень на глубине 2 (ожидание 7%)", _stone_fraction(w, 2, 2, 400), 0.04, 0.11)
	check_range("камень на глубине 3-4 (ожидание 10%)", _stone_fraction(w, 3, 4, 250), 0.06, 0.15)


func test_deep_void_and_stone() -> void:
	print("-- Плотность пустот/камня, слои 6+ --")
	var w := WorldGen.new(2)
	var void_hit := 0
	var stone_hit := 0
	var total := 0
	for y in range(6, 1500):
		for x in range(WorldGen.WIDTH):
			var t := w.get_tile(x, y)
			total += 1
			if t == TileTypes.Type.EMPTY:
				void_hit += 1
			elif t == TileTypes.Type.STONE:
				stone_hit += 1
	check_range("пустоты в слоях 6+ (ожидание 10%)", float(void_hit) / float(total), 0.07, 0.13)
	check_range("фоновый камень в слоях 6-1500 (ожидание ~7.5%, 5-10%)", float(stone_hit) / float(total), 0.04, 0.11)


func test_ore_density_corridors() -> void:
	print("-- Плотность руд в заявленных коридорах ГДД --")
	var w := WorldGen.new(3)
	var iron := _ore_fraction(w, TileTypes.Type.IRON_ORE, 6, 200)
	check_range("железо 5-200 (ГДД 5-10%)", iron, 0.02, 0.13)
	var lead := _ore_fraction(w, TileTypes.Type.LEAD_ORE, 20, 200)
	check_range("свинец 20-200 (ГДД 2-4%)", lead, 0.005, 0.07)
	var silver := _ore_fraction(w, TileTypes.Type.SILVER_ORE, 50, 250)
	check_range("серебро 50-250 (ГДД 2-3%)", silver, 0.005, 0.06)
	var diamond := _ore_fraction(w, TileTypes.Type.DIAMOND, 200, 600)
	check_range("алмаз 200+ (ГДД 1%)", diamond, 0.001, 0.03)


func _ore_fraction(w: WorldGen, tile: int, y_min: int, y_max: int) -> float:
	var hit := 0
	var total := 0
	for y in range(y_min, y_max + 1):
		for x in range(WorldGen.WIDTH):
			total += 1
			if w.get_tile(x, y) == tile:
				hit += 1
	return float(hit) / float(total)


func test_gold_and_peat_ramp_grow() -> void:
	print("-- Рост плотности: золото 2%→10%, торф 5%→20% --")
	var w := WorldGen.new(4)
	var gold_early := 0
	var gold_late := 0
	var total_early := 0
	var total_late := 0
	for s in range(60):
		w.world_seed = s * 131 + 5
		for x in range(WorldGen.WIDTH):
			total_early += 1
			if w.get_tile(x, 101) == TileTypes.Type.GOLD_ORE:
				gold_early += 1
			total_late += 1
			if w.get_tile(x, 498) == TileTypes.Type.GOLD_ORE:
				gold_late += 1
	var frac_early := float(gold_early) / float(total_early)
	var frac_late := float(gold_late) / float(total_late)
	print("     золото на y=101: %.4f, на y=498: %.4f" % [frac_early, frac_late])
	check("золото: плотность у глубины 500 выше, чем у глубины 100", frac_late > frac_early)

	var peat_early_hits := 0
	var peat_late_hits := 0
	var peat_total := 0
	for s in range(60):
		w.world_seed = s * 131 + 5
		for x in range(WorldGen.WIDTH):
			peat_total += 1
			if w.get_tile(x, 61) == TileTypes.Type.PEAT:
				peat_early_hits += 1
			if w.get_tile(x, 449) == TileTypes.Type.PEAT:
				peat_late_hits += 1
	var peat_early := float(peat_early_hits) / float(peat_total)
	var peat_late := float(peat_late_hits) / float(peat_total)
	print("     торф на y=61: %.4f, на y=449: %.4f" % [peat_early, peat_late])
	check("торф: плотность к глубине 450 выше, чем у начала пласта", peat_late > peat_early)


# ============================== СТРУКТУРНЫЕ ГАРАНТИИ ==============================

func test_foundation_solid() -> void:
	print("-- Сплошной зафиксированный фундамент на глубине 5 --")
	var ok := true
	for seed_try in [1, 42, 999]:
		var w := WorldGen.new(seed_try)
		for x in range(WorldGen.WIDTH):
			if w.get_tile(x, 5) != TileTypes.Type.FOUNDATION:
				ok = false
	check("y=5 сплошь FOUNDATION для всех x при любом seed", ok)
	var w := WorldGen.new(1)
	check("фундамент зафиксирован (is_permanent_feature)", w.is_permanent_feature(10, 5))


func test_scripted_diamond() -> void:
	print("-- Сценарный алмаз на глубине 80 --")
	var ok_diamond := true
	var ok_guards := true
	for seed_try in [1, 2, 3, 4, 5]:
		var w := WorldGen.new(seed_try)
		if w.get_tile(20, 80) != TileTypes.Type.DIAMOND:
			ok_diamond = false
		if w.get_tile(19, 80) != TileTypes.Type.STONE:  # слева
			ok_guards = false
		if w.get_tile(21, 80) != TileTypes.Type.STONE:  # справа
			ok_guards = false
		if w.get_tile(20, 81) != TileTypes.Type.STONE:  # снизу
			ok_guards = false
		if w.get_tile(20, 79) != TileTypes.Type.STONE:  # сверху
			ok_guards = false
	check("алмаз на (20, 80) при любом seed", ok_diamond)
	check("алмаз окружён камнями со всех четырёх сторон", ok_guards)


func test_staircase() -> void:
	print("-- Нерушимая лестница у дома --")
	var w := WorldGen.new(1)
	var expected_counts := {1: 1, 2: 2, 3: 3, 4: 4}
	var ok := true
	for y in expected_counts.keys():
		var count := 0
		for x in range(WorldGen.WIDTH):
			if w.get_tile(x, y) == TileTypes.Type.STAIRCASE:
				count += 1
		if count != expected_counts[y]:
			ok = false
			print("     уровень %d: найдено %d клеток лестницы, ожидалось %d" % [y, count, expected_counts[y]])
	check("количество клеток лестницы по уровням 1/2/3/4", ok)


func test_peat_seam_solid() -> void:
	print("-- Сплошной торфяной пласт 450-455 --")
	var ok := true
	for seed_try in [1, 2, 3]:
		var w := WorldGen.new(seed_try)
		for y in range(450, 456):
			for x in range(WorldGen.WIDTH):
				if w.get_tile(x, y) != TileTypes.Type.PEAT:
					ok = false
	check("y=450..455 сплошь PEAT для всех x при любом seed", ok)


func test_all_solid_tiles_are_pickaxe_diggable() -> void:
	print("-- Гарантия отсутствия запертых пустот --")
	# Каждый непустой тип клетки, кроме нерушимой лестницы, должен копаться
	# киркой: раз любую стену можно прокопать сбоку, пустота, окружённая
	# такими стенами, никогда не станет недостижимой навсегда (копать вверх
	# запрещено правилами игры, но и не требуется — герой всегда может
	# прокопать соседнюю стену сбоку/снизу вплоть до самой пустоты).
	var seen_types := {}
	for seed_try in [1, 2, 3]:
		var w := WorldGen.new(seed_try)
		for y in range(1, 600, 3):
			for x in range(WorldGen.WIDTH):
				seen_types[w.get_tile(x, y)] = true
	var ok := true
	for t in seen_types.keys():
		if t == TileTypes.Type.EMPTY or t == TileTypes.Type.STAIRCASE:
			continue
		if not TileTypes.can_dig_with_pickaxe(t):
			ok = false
			print("     тип %s не копается киркой — потенциальная запертая пустота" % TileTypes.type_name(t))
	check("все встреченные непроходимые типы (кроме лестницы) копаются киркой", ok)


# ============================== ТУМАН ВОЙНЫ ==============================

func test_fog_basic() -> void:
	print("-- Туман войны --")
	var fog := FogOfWar.new()
	check("клетка не разведана изначально -> BLACK", fog.get_state(15, 100) == FogOfWar.State.BLACK)

	fog.reveal_around(15, 100, 2, 1)
	check("в радиусе ресурсов -> FULL", fog.get_state(15, 100) == FogOfWar.State.FULL)
	check("в радиусе ресурсов по горизонтали -> FULL", fog.get_state(16, 100) == FogOfWar.State.FULL)
	check("вне радиуса ресурсов, внутри радиуса рельефа -> GRAY", fog.get_state(17, 100) == FogOfWar.State.GRAY)
	check("вне обоих радиусов -> BLACK", fog.get_state(20, 100) == FogOfWar.State.BLACK)

	fog.reset_all()
	check("после reset_all всё снова BLACK", fog.get_state(15, 100) == FogOfWar.State.BLACK)


# ============================== СОБЫТИЯ СБРОСА ==============================

func test_collapse_and_earthquake() -> void:
	print("-- Обвал чанка и землетрясение --")
	var w := WorldGen.new(55)
	var fog := FogOfWar.new()
	fog.reveal_around(15, 50, 2, 1)

	# (25, 2) гарантированно DIRT или STONE при любом seed (мелкий слой,
	# вне зоны лестницы) — детерминированно копается независимо от seed
	var dug_normal := w.dig_cell(25, 2)
	var dug_foundation := w.dig_cell(16, 5)
	check("выкопали обычную клетку земли/камня перед обвалом", dug_normal)
	check("выкопали фундамент перед обвалом", dug_foundation)

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var rect := CollapseEvents.trigger_chunk_collapse(w, fog, rng)
	check("обвал вернул непустой прямоугольник", rect.w > 0 and rect.h > 0)
	check("после обвала туман полностью сброшен", fog.get_state(15, 50) == FogOfWar.State.BLACK)

	# зафиксированные клетки (фундамент/лестница/торф/алмаз) полностью
	# исключены из событий сброса (см. world_gen._clear_diffs_in_rect):
	# уже выкопанный фундамент остаётся выкопанным навсегда, а не
	# "досыпается" обвалом обратно.
	check("выкопанный фундамент остаётся выкопанным после обвала", w.is_dug(16, 5))
	check("выкопанный фундамент показывает EMPTY после обвала", w.get_tile(16, 5) == TileTypes.Type.EMPTY)

	var w2 := WorldGen.new(56)
	var fog2 := FogOfWar.new()
	fog2.reveal_around(15, 3000, 3, 2)
	# (25, 2) и (26, 3) гарантированно диггаемы при любом seed (см. выше)
	w2.dig_cell(25, 2)
	w2.dig_cell(26, 3)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	CollapseEvents.trigger_earthquake(w2, fog2, rng2)
	check("землетрясение сжимает список событий до одной глобальной записи", w2.events.size() == 1)
	check("землетрясение сбрасывает выкопанные обычные клетки", not w2.is_dug(25, 2) and not w2.is_dug(26, 3))
	check("после землетрясения туман полностью сброшен", fog2.get_state(15, 3000) == FogOfWar.State.BLACK)

	# зафиксированные клетки остаются зафиксированными и после землетрясения
	check("фундамент остаётся FOUNDATION после землетрясения", w2.get_tile(3, 5) == TileTypes.Type.FOUNDATION)
	check("торфяной пласт остаётся PEAT после землетрясения", w2.get_tile(3, 452) == TileTypes.Type.PEAT)

	# Сценарные клетки обучения (ГДД п.9, порядок владельца): пять самородков
	# золота на ЧЕТВЁРТОМ уровне огорода. Ничего другого в огород не кладётся:
	# до фундамента в игре нет ни жизни, ни голода, ни энергии, ни мастерской,
	# и продавать добычу некому.
	var w3 := WorldGen.new(1)
	var w4 := WorldGen.new(999999)
	check("сценарное золото лежит там же при любом сиде",
		w3.get_tile(20, 4) == TileTypes.Type.GOLD_ORE
		and w4.get_tile(20, 4) == TileTypes.Type.GOLD_ORE)
	check("сценарное золото зафиксировано (обвал его не трогает)",
		w3.is_permanent_feature(20, 4))
	check("сценарных клеток ровно 5 и все на четвёртом уровне",
		_scripted_gold_count(w3, 4) == 5 and _scripted_gold_count(w3, 1) == 0
		and _scripted_gold_count(w3, 2) == 0 and _scripted_gold_count(w3, 3) == 0)
	# Лопатой золото не берётся — на этом держится весь четвёртый уровень:
	# автокопка проходит мимо, а игрок возвращается за ним уже киркой деда.
	check("сценарное золото лопатой не берётся",
		not TileTypes.can_dig_with_shovel(TileTypes.Type.GOLD_ORE)
		and TileTypes.can_dig_with_pickaxe(TileTypes.Type.GOLD_ORE))
	check("никакой другой сценарной добычи в огороде нет",
		_scripted_scrap_count(w3) == 0)
	w3.dig_cell(20, 4)
	check("выкопанное сценарное золото не отрастает", w3.get_tile(20, 4) == TileTypes.Type.EMPTY)
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 11
	CollapseEvents.trigger_earthquake(w3, FogOfWar.new(), rng3)
	check("землетрясение не возвращает выкопанное сценарное золото",
		w3.get_tile(20, 4) == TileTypes.Type.EMPTY)


func _scripted_gold_count(w: WorldGen, y: int) -> int:
	var n := 0
	for x in range(WorldGen.GARDEN_X_MIN, WorldGen.WIDTH):
		if w.get_tile(x, y) == TileTypes.Type.GOLD_ORE:
			n += 1
	return n


func _scripted_scrap_count(w: WorldGen) -> int:
	var n := 0
	for y in range(1, 5):
		for x in range(WorldGen.GARDEN_X_MIN, WorldGen.WIDTH):
			if w.get_tile(x, y) == TileTypes.Type.SCRAP_METAL:
				n += 1
	return n

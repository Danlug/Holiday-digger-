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
	test_fog_coverage_rule()
	test_deep_void_and_stone()
	test_ore_density_corridors()
	test_gold_and_peat_ramp_grow()
	test_foundation_solid()
	test_scripted_diamond()
	test_staircase()
	test_robert_tunnel()
	test_garden_sealed_after_robert()
	test_garden_decor()
	test_tunnel_survives_collapse()
	test_peat_seam_solid()
	test_all_solid_tiles_are_pickaxe_diggable()
	test_fog_basic()
	test_collapse_and_earthquake()
	test_collapse_fog_only_in_zone()
	test_collapse_below_player_only()
	test_full_reset_waits_for_player()
	# --- задача «Огород под домом / тоннель Роберта» (правила владельца B) ---
	test_house_never_diggable()
	test_collapse_never_touches_house()
	test_tunnel_absent_before_robert()
	test_tunnel_mouth_save_load_roundtrip()
	# --- задача «Огород до автокопки: копать только правее лестницы» ---
	test_pre_autodig_gate()
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


## Первые четыре уровня огорода — обучающая песочница БЕЗ КАМНЯ. Лопата о
## камень даёт минуту стана (ГДД п.5), а кирки на этих уровнях ещё нет и
## взяться ей неоткуда: наказание за незнание на первой минуте игры, которое
## ничему не учит. Плюс автокопка камень не берёт и оставляла бы его торчать
## посреди расчищенной земли — ровно на пути к фундаменту. Камень начинается
## ниже фундамента.
func test_layer_percentages_shallow() -> void:
	print("-- Первые четыре уровня: камня нет --")
	var w := WorldGen.new(1)
	check("на глубине 1 камня нет", is_zero_approx(_stone_fraction(w, 1, 1, 400)))
	check("на глубине 2 камня нет", is_zero_approx(_stone_fraction(w, 2, 2, 400)))
	check("на глубинах 3-4 камня нет", is_zero_approx(_stone_fraction(w, 3, 4, 250)))
	check("ниже фундамента камень есть", _stone_fraction(w, 6, 12, 200) > 0.01)


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


## Тоннель Роберта: единственный вход в копальню после того, как он закончил
## огород (решение владельца — люк и лестница отменены).
func test_robert_tunnel() -> void:
	print("-- Тоннель Роберта вместо лестницы --")
	var w := WorldGen.new(4242)

	# --- до Роберта мир прежний: лестница есть, железобетона нет, копается ---
	check("до Роберта огород не заперт", not w.is_garden_locked())
	var reinforced_before := 0
	var staircase_before := 0
	for y in range(1, 5):
		for x in range(WorldGen.WIDTH):
			var t := w.get_tile(x, y)
			if t == TileTypes.Type.REINFORCED:
				reinforced_before += 1
			elif t == TileTypes.Type.STAIRCASE:
				staircase_before += 1
	check("до Роберта железобетона в мире нет", reinforced_before == 0)
	check("до Роберта лестница на месте (1+2+3+4 клетки)", staircase_before == 10)
	# обучение копает первые четыре уровня — берём клетку заведомо вне
	# лестницы и вне сценарного золота
	check("до Роберта огород копается", w.dig_cell(22, 2))
	check("выкопанная до Роберта клетка — дыра", w.get_tile(22, 2) == TileTypes.Type.EMPTY)

	# --- Роберт закончил ---
	w.build_robert_tunnel()
	check("после Роберта огород заперт", w.is_garden_locked())
	check("устье тоннеля — (17, 1)", w.tunnel_mouth() == Vector2i(WorldGen.TUNNEL_X, 1))

	var ok_shaft := true
	var ok_walls := true
	for y in range(1, WorldGen.TUNNEL_DEPTH + 1):
		if w.get_tile(WorldGen.TUNNEL_X, y) != TileTypes.Type.EMPTY:
			ok_shaft = false
		if w.get_tile(WorldGen.TUNNEL_WALL_LEFT, y) != TileTypes.Type.REINFORCED:
			ok_walls = false
		if w.get_tile(WorldGen.TUNNEL_WALL_RIGHT, y) != TileTypes.Type.REINFORCED:
			ok_walls = false
	check("колонка x=17 пуста на уровнях 1..4", ok_shaft)
	check("колонки x=16 и x=18 — железобетон на уровнях 1..4", ok_walls)
	check("глубина тоннеля ровно 4", WorldGen.TUNNEL_DEPTH == 4)
	check("тоннель не уходит на пятый уровень (там фундамент)",
		w.get_tile(WorldGen.TUNNEL_WALL_LEFT, 5) == TileTypes.Type.FOUNDATION)

	# --- железобетон не копается НИКАКИМ инструментом ---
	check("железобетон не берётся лопатой",
		not TileTypes.can_dig_with_shovel(TileTypes.Type.REINFORCED))
	check("железобетон не берётся киркой",
		not TileTypes.can_dig_with_pickaxe(TileTypes.Type.REINFORCED))
	check("железобетон вообще не копается", not TileTypes.is_diggable(TileTypes.Type.REINFORCED))
	var ok_walls_hold := true
	for y in range(1, WorldGen.TUNNEL_DEPTH + 1):
		if w.dig_cell(WorldGen.TUNNEL_WALL_LEFT, y) or w.dig_cell(WorldGen.TUNNEL_WALL_RIGHT, y):
			ok_walls_hold = false
		if w.get_tile(WorldGen.TUNNEL_WALL_LEFT, y) != TileTypes.Type.REINFORCED:
			ok_walls_hold = false
	check("стены тоннеля не прокопать (dig_cell отказывает и стена цела)", ok_walls_hold)

	# --- лестницы больше нет ---
	var staircase_after := 0
	for y in range(1, 6):
		for x in range(WorldGen.WIDTH):
			if w.get_tile(x, y) == TileTypes.Type.STAIRCASE:
				staircase_after += 1
	check("после Роберта лестницы в мире нет", staircase_after == 0)

	# --- мягкая блокировка: колодец не тупик ---
	check("фундамент под устьем пробит", w.get_tile(WorldGen.TUNNEL_X, 5) == TileTypes.Type.EMPTY)
	check("фундамент рядом с устьем цел (пробита ровно одна клетка)",
		w.get_tile(WorldGen.TUNNEL_X + 1, 5) == TileTypes.Type.FOUNDATION)
	var ok_landing := true
	for y in range(6, 8):
		for x in range(WorldGen.TUNNEL_WALL_LEFT, WorldGen.TUNNEL_WALL_RIGHT + 1):
			if w.get_tile(x, y) != TileTypes.Type.EMPTY:
				ok_landing = false
	check("под фундаментом расчищена площадка 3 клетки в ширину на 2 вниз", ok_landing)

	# --- идемпотентность ---
	var before := w.get_save_data()
	w.build_robert_tunnel()
	w.build_robert_tunnel()
	var after := w.get_save_data()
	check("повторная постройка тоннеля ничего не меняет",
		before["dug"].size() == after["dug"].size() and w.is_garden_locked())

	# --- замок переживает сохранение/загрузку ---
	var reloaded := WorldGen.new(4242)
	reloaded.load_save_data(after)
	check("замок огорода сохраняется и загружается", reloaded.is_garden_locked())
	check("после загрузки тоннель на месте",
		reloaded.get_tile(WorldGen.TUNNEL_X, 3) == TileTypes.Type.EMPTY
		and reloaded.get_tile(WorldGen.TUNNEL_WALL_LEFT, 3) == TileTypes.Type.REINFORCED)


## После Роберта копать в огороде нельзя вообще, а верхний грунт неприкасаем
## всегда — и до него, и после.
func test_garden_sealed_after_robert() -> void:
	print("-- Запечатанный огород --")
	var w := WorldGen.new(7)

	# поверхность неприкасаема ещё до Роберта
	var ok_surface := true
	for x in range(WorldGen.WIDTH):
		if w.dig_cell(x, 0) or w.get_tile(x, 0) != TileTypes.Type.EMPTY:
			ok_surface = false
	check("верхний грунт (y=0) не копается и до Роберта", ok_surface)

	# наковыряли воронок по всему огороду, как обучение
	var dug_before := 0
	for y in range(1, 5):
		for x in range(WorldGen.GARDEN_X_MIN, WorldGen.WIDTH):
			if w.dig_cell(x, y):
				dug_before += 1
	check("до Роберта огород копался (воронок наковыряли)", dug_before > 0)

	w.build_robert_tunnel()

	# воронки засыпаны: дыр в огороде не осталось нигде, кроме тоннеля
	var holes := 0
	for y in range(1, 5):
		for x in range(WorldGen.GARDEN_X_MIN, WorldGen.WIDTH):
			if x == WorldGen.TUNNEL_X:
				continue
			if w.get_tile(x, y) == TileTypes.Type.EMPTY:
				holes += 1
	check("Роберт засыпал все воронки огорода (дыр нет)", holes == 0)

	# и больше ничего не выкопать
	var ok_sealed := true
	for y in range(1, 5):
		for x in range(WorldGen.GARDEN_X_MIN, WorldGen.WIDTH):
			if x == WorldGen.TUNNEL_X:
				continue
			if w.dig_cell(x, y):
				ok_sealed = false
			if w.get_tile(x, y) == TileTypes.Type.EMPTY:
				ok_sealed = false
	check("после Роберта огород на уровнях 1..4 не копается ни в одной клетке", ok_sealed)
	check("верхний грунт не копается и после Роберта", not w.dig_cell(20, 0))

	# ниже фундамента мир по-прежнему копается: запечатан только огород
	check("под фундаментом копать по-прежнему можно", w.dig_cell(25, 20))

	# Хук для дома и игрока: по нему они отказывают в ударе ДО начала копки,
	# не дожидаясь, пока dig_cell вернёт false в конце анимации.
	check("is_garden_sealed_cell: грядка заперта", w.is_garden_sealed_cell(25, 3))
	check("is_garden_sealed_cell: ствол тоннеля не заперт",
		not w.is_garden_sealed_cell(WorldGen.TUNNEL_X, 3))
	check("is_garden_sealed_cell: ниже фундамента не заперто",
		not w.is_garden_sealed_cell(25, 20))
	var fresh := WorldGen.new(7)
	check("is_garden_sealed_cell: до Роберта ничего не заперто",
		not fresh.is_garden_sealed_cell(25, 3))


## Декор поверхности (art/env/garden/*.png, tools/import_garden.py):
## детерминирован, не лезет на дом (0..14) и на вход тоннеля (17), а каждое
## возвращённое имя — существующий файл, и до, и после Роберта.
func test_garden_decor() -> void:
	print("-- Декор огорода на поверхности --")
	var seeds := [1, 42, 4242, 999999]

	for sd in seeds:
		var w := WorldGen.new(sd)
		var w2 := WorldGen.new(sd)
		var stable := true
		var house_clear := true
		var tunnel_clear := true
		var assets_ok := true
		for x in range(WorldGen.WIDTH):
			var name := w.garden_decor_at(x)
			if name != w2.garden_decor_at(x):
				stable = false
			if x <= WorldGen.HOUSE_X_MAX and not name.is_empty():
				house_clear = false
			if x == WorldGen.TUNNEL_X and not name.is_empty():
				tunnel_clear = false
			if not name.is_empty() and not ResourceLoader.exists("res://art/env/garden/%s.png" % name):
				assets_ok = false
		check("сид %d: декор — чистая функция (не меняется между экземплярами)" % sd, stable)
		check("сид %d: декор не залезает на дом (0..14)" % sd, house_clear)
		check("сид %d: декор не закрывает вход тоннеля (17)" % sd, tunnel_clear)
		check("сид %d: каждое имя декора — существующий файл" % sd, assets_ok)

	# после Роберта раскладка меняется (дикий -> ухоженный огород), но правила
	# те же: дом и тоннель по-прежнему свободны.
	var w3 := WorldGen.new(2024)
	var before: Array = []
	for x in range(WorldGen.WIDTH):
		before.append(w3.garden_decor_at(x))
	w3.build_robert_tunnel()
	var differs := false
	var tunnel_clear_after := true
	var assets_ok_after := true
	for x in range(WorldGen.WIDTH):
		var name := w3.garden_decor_at(x)
		if name != before[x]:
			differs = true
		if x == WorldGen.TUNNEL_X and not name.is_empty():
			tunnel_clear_after = false
		if not name.is_empty() and not ResourceLoader.exists("res://art/env/garden/%s.png" % name):
			assets_ok_after = false
	check("после Роберта раскладка декора меняется (дикий -> ухоженный)", differs)
	check("после Роберта тоннель по-прежнему свободен", tunnel_clear_after)
	check("после Роберта все имена декора — существующие файлы", assets_ok_after)


## Обвал и землетрясение тоннель не разрушают: он зафиксирован так же, как
## фундамент и лестница.
func test_tunnel_survives_collapse() -> void:
	print("-- События сброса не трогают тоннель --")
	var w := WorldGen.new(31337)
	var fog := FogOfWar.new()
	w.build_robert_tunnel()

	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(5):
		CollapseEvents.trigger_chunk_collapse(w, fog, rng)
	var ok_after_chunks := _tunnel_intact(w)
	check("обвалы чанков тоннель не разрушают", ok_after_chunks)

	CollapseEvents.trigger_earthquake(w, fog, rng)
	check("землетрясение тоннель не разрушает", _tunnel_intact(w))
	check("землетрясение не возвращает фундамент под устьем",
		w.get_tile(WorldGen.TUNNEL_X, 5) == TileTypes.Type.EMPTY)
	check("землетрясение не отпирает огород", w.is_garden_locked())

	# и запечатанный огород после встряски всё так же не копается и без дыр
	var ok_sealed := true
	for y in range(1, 5):
		for x in range(WorldGen.GARDEN_X_MIN, WorldGen.WIDTH):
			if x == WorldGen.TUNNEL_X:
				continue
			if w.dig_cell(x, y) or w.get_tile(x, y) == TileTypes.Type.EMPTY:
				ok_sealed = false
	check("после землетрясения огород всё так же запечатан и цел", ok_sealed)


func _tunnel_intact(w: WorldGen) -> bool:
	for y in range(1, WorldGen.TUNNEL_DEPTH + 1):
		if w.get_tile(WorldGen.TUNNEL_X, y) != TileTypes.Type.EMPTY:
			return false
		if w.get_tile(WorldGen.TUNNEL_WALL_LEFT, y) != TileTypes.Type.REINFORCED:
			return false
		if w.get_tile(WorldGen.TUNNEL_WALL_RIGHT, y) != TileTypes.Type.REINFORCED:
			return false
	return true


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

	fog.reveal_around_cell(15, 100, 2, 1)
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
	fog.reveal_around_cell(15, 50, 2, 1)

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
	# Весь туман обвал больше не гасит (решение владельца) — только свою зону.
	# Подробно это проверяет test_collapse_fog_only_in_zone, здесь достаточно
	# совпадения: разведанная клетка чернеет тогда и только тогда, когда она
	# попала в прямоугольник обвала.
	var probe_in_rect: bool = 50 >= int(rect.y0) and 50 < int(rect.y0) + int(rect.h) \
		and 15 >= int(rect.x0) and 15 < int(rect.x0) + int(rect.w)
	check("после обвала туман погашен ровно в его зоне",
		(fog.get_state(15, 50) == FogOfWar.State.BLACK) == probe_in_rect)

	# зафиксированные клетки (фундамент/лестница/торф/алмаз) полностью
	# исключены из событий сброса (см. world_gen._clear_diffs_in_rect):
	# уже выкопанный фундамент остаётся выкопанным навсегда, а не
	# "досыпается" обвалом обратно.
	check("выкопанный фундамент остаётся выкопанным после обвала", w.is_dug(16, 5))
	check("выкопанный фундамент показывает EMPTY после обвала", w.get_tile(16, 5) == TileTypes.Type.EMPTY)

	var w2 := WorldGen.new(56)
	var fog2 := FogOfWar.new()
	fog2.reveal_around_cell(15, 3000, 3, 2)
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


## Правило владельца: "когда случается обвал, ты вообще гасишь мне весь экран,
## не надо закрывать всю карту, только там где случился обвал". Разведанная
## глубина стоит игроку часов — обвал в пяти клетках не имеет права её стирать.
func test_collapse_fog_only_in_zone() -> void:
	print("-- Обвал: туман гаснет только в своей зоне --")
	var f := FogOfWar.new()
	f.reveal_around_cell(10, 100, 3, 2)
	f.reveal_around_cell(10, 200, 3, 2)
	f.reset_rect(9, 99, 3, 3)
	check("клетка внутри прямоугольника погашена", f.get_state(10, 100) == FogOfWar.State.BLACK)
	check("угол прямоугольника погашен", f.get_state(9, 99) == FogOfWar.State.BLACK)
	check("клетка сразу за правым краем уцелела", f.get_state(12, 100) != FogOfWar.State.BLACK)
	check("клетка сразу под нижним краем уцелела", f.get_state(10, 102) != FogOfWar.State.BLACK)
	check("разведка на другой глубине не тронута", f.get_state(10, 200) != FogOfWar.State.BLACK)

	# Прямоугольник обвала не обязан лежать внутри одного чанка тумана
	# (32 строки): граница проходит по y = 33, и гасить надо по обе стороны.
	var f2 := FogOfWar.new()
	for y in range(28, 40):
		f2.reveal_around_cell(5, y, 1, 0)
	f2.reset_rect(4, 30, 3, 8)
	check("гашение переходит границу чанка (выше)", f2.get_state(5, 32) == FogOfWar.State.BLACK)
	check("гашение переходит границу чанка (ниже)", f2.get_state(5, 34) == FogOfWar.State.BLACK)
	check("за пределами прямоугольника чанк не выброшен целиком",
		f2.get_state(5, 29) != FogOfWar.State.BLACK and f2.get_state(5, 38) != FogOfWar.State.BLACK)

	# Тот же закон через сам обвал: всё, что он погасил, лежит в его
	# прямоугольнике, а разведка вдалеке остаётся на месте.
	var w := WorldGen.new(4242)
	var f3 := FogOfWar.new()
	var probes: Array = []
	for i in range(40):
		var y := 50 + i * 111
		probes.append(y)
		f3.reveal_around_cell(15, y, 2, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var rect := CollapseEvents.trigger_chunk_collapse(w, f3, rng)
	var outside_alive := 0
	var inside_dark := true
	for y in probes:
		var in_rect: bool = y >= int(rect.y0) and y < int(rect.y0) + int(rect.h) \
			and 15 >= int(rect.x0) and 15 < int(rect.x0) + int(rect.w)
		if in_rect:
			if f3.get_state(15, y) != FogOfWar.State.BLACK:
				inside_dark = false
		elif f3.get_state(15, y) != FogOfWar.State.BLACK:
			outside_alive += 1
	check("обвал погасил клетки своей зоны", inside_dark)
	check("обвал не тронул разведку вне своей зоны (уцелело %d проб)" % outside_alive,
		outside_alive > 0)

	# Землетрясение — это "перетряхнуло копальню целиком", и вот оно гасит всё.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 3
	CollapseEvents.trigger_earthquake(w, f3, rng2)
	var any_left := false
	for y in probes:
		if f3.get_state(15, y) != FogOfWar.State.BLACK:
			any_left = true
	check("землетрясение по-прежнему гасит весь туман", not any_left)


## Правило владельца: "обвал не может произойти выше или прямо на уровне
## героя". Порода, сомкнувшаяся на самом герое, отнимает ход не по его вине.
func test_collapse_below_player_only() -> void:
	print("-- Обвал только ниже героя --")
	var w := WorldGen.new(777)
	var fog := FogOfWar.new()
	var player_y := 500
	# Самый верхний край, который выдал обвал за все прогоны. Стартует НИЖЕ
	# дна, иначе минимум никогда не поднимется до реальных значений и
	# проверка пройдёт впустую.
	var worst := w.max_depth + 1
	var empties := 0
	for i in range(200):
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		var rect := CollapseEvents.trigger_chunk_collapse(w, fog, rng, player_y)
		if rect.is_empty():
			empties += 1
			continue
		worst = mini(worst, int(rect.y0))
	check("обвал всегда случается (место под героем есть)", empties == 0)
	check("верхний край обвала строго ниже клетки героя (самый верхний — %d при герое на %d)"
		% [worst, player_y], worst > player_y)

	# Герой у самого дна: класть обвал некуда — события просто нет, и тост
	# показывать не о чем (main.gd проверяет пустой словарь).
	var rng_deep := RandomNumberGenerator.new()
	rng_deep.seed = 5
	var deep := CollapseEvents.trigger_chunk_collapse(w, fog, rng_deep, w.max_depth - 1)
	check("у самого дна обвала не происходит (пустой словарь)", deep.is_empty())

	# Без героя (-1) ограничения нет — так обвал зовут тесты и код без сцены.
	var rng_free := RandomNumberGenerator.new()
	rng_free.seed = 9
	var free_rect := CollapseEvents.trigger_chunk_collapse(w, fog, rng_free, -1)
	check("без героя обвал по-прежнему возможен на любой глубине",
		not free_rect.is_empty() and int(free_rect.y0) >= 1)


## Правило владельца: "не может произойти полный ресет пока он в земле, даже
## если тригернулось событие... пока он не вылезет наверх или в 3 на 3 клетки".
func test_full_reset_waits_for_player() -> void:
	print("-- Полный ресет ждёт, пока герой не выберется --")
	check("на поверхности трясти можно", CollapseEvents.is_safe_for_full_reset(0, false))
	check("на входе в шахту трясти можно", CollapseEvents.is_safe_for_full_reset(1, false))
	check("на клетку ниже входа — уже нельзя", not CollapseEvents.is_safe_for_full_reset(2, false))
	check("в доме трясти можно с любой глубины", CollapseEvents.is_safe_for_full_reset(300, true))

	var w := WorldGen.new(31337)
	var fog := FogOfWar.new()
	fog.reveal_around_cell(15, 300, 2, 1)
	w.dig_cell(25, 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var shook: bool = CollapseEvents.try_trigger_earthquake(w, fog, 300, false, rng)
	check("под землёй землетрясение не применяется", not shook)
	check("мир под землёй остался как был", w.is_dug(25, 2))
	check("туман под землёй остался разведанным", fog.get_state(15, 300) != FogOfWar.State.BLACK)

	# Герой вылез — отложенное событие применяется тем же вызовом.
	var shook_up: bool = CollapseEvents.try_trigger_earthquake(w, fog, 1, false, rng)
	check("наверху отложенное землетрясение применяется", shook_up)
	check("мир перетряхнуло", not w.is_dug(25, 2))
	check("туман сброшен целиком", fog.get_state(15, 300) == FogOfWar.State.BLACK)

	# Дом — вторая безопасная точка: ресет догоняет героя и там.
	var w2 := WorldGen.new(31338)
	var fog2 := FogOfWar.new()
	w2.dig_cell(25, 2)
	check("в доме отложенное землетрясение применяется",
		CollapseEvents.try_trigger_earthquake(w2, fog2, 900, true, rng))
	check("мир перетряхнуло и из дома", not w2.is_dug(25, 2))


# ============================== ДОМ НЕ КОПАЕТСЯ (решение владельца B.1) ==============================

## «Огород под домом вообще никогда нельзя копать» — дом занимает x 0..14
## (ГДД раздел 3), и dig_cell — единственная точка входа для любой копки
## (лопата/кирка/бур/бурмобиль/автокопка идут через неё же), поэтому
## запрет здесь закрывает все инструменты разом.
func test_house_never_diggable() -> void:
	print("-- Под домом (x 0..14) не копают никогда --")
	var w := WorldGen.new(2026)

	# и до, и после Роберта: замок огорода тут ни при чём, запрет безусловный
	var ok_before := true
	for x in range(0, WorldGen.HOUSE_X_MAX + 1):
		for y in [1, 2, 3, 4, 5, 100]:
			if w.dig_cell(x, y):
				ok_before = false
			if w.is_dug(x, y):
				ok_before = false
	check("до Роберта под домом ничего не выкопать (x=0..14, разные y)", ok_before)

	w.build_robert_tunnel()
	var ok_after := true
	for x in range(0, WorldGen.HOUSE_X_MAX + 1):
		for y in [1, 2, 3, 4, 5, 100]:
			if w.dig_cell(x, y):
				ok_after = false
	check("после Роберта под домом по-прежнему ничего не выкопать", ok_after)

	# Огород (x >= 15) копается как обычно — граница ровно по HOUSE_X_MAX, не
	# сдвинута ни в одну из сторон. (25, 2) — мелкий слой без камня (см. другие
	# тесты этого файла), гарантированно DIRT при любом сиде: вне лестницы,
	# вне сценарного золота (то на y=4, не y=2).
	var w2 := WorldGen.new(2026)
	check("соседняя клетка огорода копается (x=25, y=2)", w2.dig_cell(25, 2))
	check("HOUSE_X_MAX и GARDEN_X_MIN примыкают без зазора",
		WorldGen.HOUSE_X_MAX + 1 == WorldGen.GARDEN_X_MIN)


## Обвал (раздел 8 ГДД) не должен дырявить дом заодно с огородом — ни один
## прямоугольник обвала не имеет права задеть x <= HOUSE_X_MAX, при любом
## сиде генератора случайных чисел.
func test_collapse_never_touches_house() -> void:
	print("-- Обвал никогда не задевает дом (x 0..14) --")
	var w := WorldGen.new(31415)
	var fog := FogOfWar.new()
	var touched_house := false
	var got_full_width_shape := false
	for i in range(300):
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		var rect: Dictionary = CollapseEvents.trigger_chunk_collapse(w, fog, rng)
		if rect.is_empty():
			continue
		var x0 := int(rect.x0)
		var x1 := x0 + int(rect.w)
		if x0 < WorldGen.GARDEN_X_MIN:
			touched_house = true
		if x1 - x0 >= WorldGen.WIDTH - WorldGen.GARDEN_X_MIN:
			got_full_width_shape = true
	check("за 300 обвалов ни один не начинается левее огорода", not touched_house)
	check("широкие формы обвала (5×32 / 10×32) встретились хотя бы раз — форма проверена не вхолостую",
		got_full_width_shape)


# ============================== ТОННЕЛЬ ДО РОБЕРТА (решение владельца B.3) ==============================

## «Тоннеля нет, пока не произошёл сюжет с Робертом»: на свежем сиде без
## флага колонки 16..18 на уровнях 1..4 — обычная земля, а не железобетон/
## пустота, и tunnel_mouth() честно говорит "нет", а не подсовывает координаты
## ещё не построенного колодца.
func test_tunnel_absent_before_robert() -> void:
	print("-- Тоннеля нет до сцены Роберта --")
	var ok_ordinary := true
	for seed_try in [1, 55, 999999]:
		var w := WorldGen.new(seed_try)
		for y in range(1, WorldGen.TUNNEL_DEPTH + 1):
			for x in [WorldGen.TUNNEL_WALL_LEFT, WorldGen.TUNNEL_X, WorldGen.TUNNEL_WALL_RIGHT]:
				var t := w.get_tile(x, y)
				if t == TileTypes.Type.REINFORCED:
					ok_ordinary = false
				# x=17/18 на уровне 4 — часть треугольной лестницы (x_start=15,
				# растёт по клетке в уровень) — это и есть "обычная земля" ДО
				# Роберта: сама лестница, а не тоннель. Пустота там означала бы,
				# что тоннель уже прорезан без сцены.
				if t == TileTypes.Type.EMPTY:
					ok_ordinary = false
	check("свежий мир без флага: x=16..18, y=1..4 — обычная земля/лестница, не тоннель",
		ok_ordinary)

	var w := WorldGen.new(2026)
	check("до Роберта is_garden_locked() == false", not w.is_garden_locked())
	check("до Роберта tunnel_mouth() говорит «нет» (-1, -1)",
		w.tunnel_mouth() == Vector2i(-1, -1))

	w.build_robert_tunnel()
	check("после Роберта tunnel_mouth() возвращает устье", w.tunnel_mouth() == Vector2i(WorldGen.TUNNEL_X, 1))


## Сохранение: старый сейв с построенным тоннелем грузится с тоннелем, новый
## (до Роберта) — без. get_save_data()/load_save_data() хранят только флаг
## garden_locked — geometрия тоннеля вычисляется из него же при каждом
## обращении, так что круглый путь save->load обязан воспроизводить и
## отсутствие тоннеля, а не только его наличие (последнее уже покрыто
## test_robert_tunnel).
func test_tunnel_mouth_save_load_roundtrip() -> void:
	print("-- tunnel_mouth() переживает сохранение/загрузку в обе стороны --")
	var fresh := WorldGen.new(7)
	var fresh_save := fresh.get_save_data()
	var loaded_fresh := WorldGen.new(7)
	loaded_fresh.load_save_data(fresh_save)
	check("новый сейв (без Роберта) после загрузки — без тоннеля",
		not loaded_fresh.is_garden_locked() and loaded_fresh.tunnel_mouth() == Vector2i(-1, -1))
	check("новый сейв после загрузки: устье ещё обычная лестница/земля",
		loaded_fresh.get_tile(WorldGen.TUNNEL_X, 1) != TileTypes.Type.REINFORCED)

	var built := WorldGen.new(7)
	built.build_robert_tunnel()
	var built_save := built.get_save_data()
	var loaded_built := WorldGen.new(7)
	loaded_built.load_save_data(built_save)
	check("старый сейв (с Робертом) после загрузки — с тоннелем",
		loaded_built.is_garden_locked() and loaded_built.tunnel_mouth() == Vector2i(WorldGen.TUNNEL_X, 1))
	check("старый сейв после загрузки: устье пусто, стены — железобетон",
		loaded_built.get_tile(WorldGen.TUNNEL_X, 1) == TileTypes.Type.EMPTY
		and loaded_built.get_tile(WorldGen.TUNNEL_WALL_LEFT, 1) == TileTypes.Type.REINFORCED)


## Туман открывает клетку, когда круг обзора накрыл её не меньше чем на
## половину площади (решение владельца), и круг этот — ровно тот, что
## нарисован на экране. Раньше правило было «центр клетки внутри круга», а
## рисовался круг на полклетки больше: аура переезжала через клетку заметно
## раньше, чем та открывалась.
func test_fog_coverage_rule() -> void:
	print("-- Туман: раскрытие по половине клетки --")
	var f := FogOfWar.new()
	f.reveal_around(10.5, 10.5, 1, 0)
	check("своя клетка открыта", f.get_state(10, 10) != FogOfWar.State.BLACK)
	check("соседняя по горизонтали открыта", f.get_state(11, 10) != FogOfWar.State.BLACK)
	check("соседняя по диагонали открыта", f.get_state(11, 11) != FogOfWar.State.BLACK)
	check("через одну клетку — закрыто", f.get_state(12, 10) == FogOfWar.State.BLACK)

	# Круг симметричен: слева открывается ровно столько же, сколько справа.
	check("раскрытие симметрично", f.get_state(9, 10) != FogOfWar.State.BLACK
		and f.get_state(8, 10) == FogOfWar.State.BLACK)

	# Полклетки радиуса — общие у тумана и у отрисовки, чтобы круг был один.
	check("радиус обзора = ступень + полклетки",
		is_equal_approx(FogOfWar.vision_radius(2), 2.5))

	# Сдвиг героя на полклетки вправо сдвигает и раскрытие.
	var f2 := FogOfWar.new()
	f2.reveal_around(11.5, 10.5, 1, 0)
	check("раскрытие едет за героем: клетка, закрытая слева, открывается справа",
		f2.get_state(12, 10) != FogOfWar.State.BLACK
		and f2.get_state(9, 10) == FogOfWar.State.BLACK)


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


## Правило владельца (ГДД п.9): "в начале игры ему можно копать только
## справа от дома и лестницы, пока не запустится сценарий со скоростным
## копанием". Гейт по умолчанию снят (голый WorldGen.new(seed) в тестах и
## утилитах копается как и раньше — ломать чужие тесты этой задаче нельзя),
## взводит его явно StoryDirector для новой/незавершённой обучением игры.
func test_pre_autodig_gate() -> void:
	print("-- Гейт «до автокопки — только правее лестницы» --")

	# is_pre_autodig_locked_cell — чистая функция от координат (тайл не
	# спрашивает), поэтому границу можно проверить на любой глубине без риска
	# попасть в «пустоту» глубоких слоёв.
	var w := WorldGen.new(777)
	check("по умолчанию гейт снят (как было всегда, до этой задачи)",
		not w.is_pre_autodig_locked_cell(16, 50))
	w.lock_pre_autodig_garden()

	var ok_locked := true
	for x in range(WorldGen.GARDEN_X_MIN, 19):  # 15..18 — вкл. правый край лестницы на 4-м уровне
		if not w.is_pre_autodig_locked_cell(x, 1) or not w.is_pre_autodig_locked_cell(x, 50):
			ok_locked = false
	check("15..18 заперты на любой глубине, включая ниже лестницы", ok_locked)

	var ok_free := true
	for x in range(19, WorldGen.WIDTH):
		if w.is_pre_autodig_locked_cell(x, 1) or w.is_pre_autodig_locked_cell(x, 50):
			ok_free = false
	check("19 и правее свободны на любой глубине", ok_free)
	check("дом (x<=14) — не забота этого гейта, им ведает dig_cell отдельно",
		not w.is_pre_autodig_locked_cell(10, 1))

	# Реальная копка: (16, 1) вне самой лестницы (на первом уровне она
	# занимает только x=15), поэтому без гейта копается свободно, а с гейтом —
	# только из-за него, не из-за типа клетки.
	var w2 := WorldGen.new(777)
	check("без гейта (16,1) копается", w2.dig_cell(16, 1))

	var w3 := WorldGen.new(777)
	w3.lock_pre_autodig_garden()
	check("с гейтом (16,1) не копается", not w3.dig_cell(16, 1))
	check("выкопать так и не удалось — клетка не EMPTY", w3.get_tile(16, 1) != TileTypes.Type.EMPTY)
	check("с гейтом (19,1), сразу правее лестницы, копается", w3.dig_cell(19, 1))
	check("под домом отказ по-прежнему свой (x=10)", not w3.dig_cell(10, 1))

	w3.unlock_pre_autodig_garden()
	check("после unlock (17,2) снова копается", w3.dig_cell(17, 2))

	# Страховка: build_robert_tunnel снимает гейт сама, даже если его забыли
	# снять раньше (тест зовёт метод напрямую, минуя обучение).
	var w4 := WorldGen.new(777)
	w4.lock_pre_autodig_garden()
	w4.build_robert_tunnel()
	check("build_robert_tunnel снимает гейт как страховку",
		not w4.is_pre_autodig_locked_cell(16, 1))

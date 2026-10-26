extends Node
## test_survival — голод и усталость давят сильнее (раунд 5, ГДД §7,
## scripts/survival/, data/survival.json): расход выше (кроме мягкого старта),
## ступени на 25%/10%/нуле режут копку, ходьбу, прыжок и удачу, без сил шатает;
## ветки «Голод» и «Выносливость» дешевле, выносливость сильнее; значки у полосок.
## Сценой — нужны автозагрузки:
##   godot --headless --path . res://tests/test_survival.tscn

var failures := 0
var total := 0


func _ready() -> void:
	print("=== test_survival ===")
	GameState.reset_progress()

	_test_tiers()
	_test_drain_and_soft_start()
	_test_skills_answer_pressure()
	_test_branch_prices()
	_test_dig_time()
	_test_walk_and_stagger()
	_test_jump()
	_test_flight_untouched()
	_test_luck()
	_test_owner_numbers_kept()
	await _test_badges()
	_test_data_marked_proposed()

	GameState.reset_progress()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func check_near(label: String, actual: float, expected: float, tol: float = 0.01) -> void:
	check("%s (получено %.3f, ожидалось %.3f)" % [label, actual, expected], absf(actual - expected) <= tol)


func _fresh(hunger: float = 100.0, stamina: float = 100.0, past_soft_start: bool = true) -> void:
	GameState.reset_progress()
	GameState.is_alive = true
	GameState.house_is_indoors = false
	GameState.debug_invincible = false
	GameState.debug_instant_dig = false
	GameState.story_seen.erase("sleep_lesson_1")
	if past_soft_start:
		GameState.story_seen.append("sleep_lesson_1")
	GameState.set_hunger(hunger)
	GameState.set_stamina(stamina)
	GameState._update_exhausted()


func _player(world: WorldGen) -> Node:
	var p = preload("res://scripts/player/player.gd").new()
	p.world = world
	add_child(p)
	return p


# ---------------------------------------------------------------------------

func _test_tiers() -> void:
	print("--- Ступени: те же пороги, что у предупреждений ---")
	check("100% — норма", SurvivalRules.tier(100.0) == "")
	check("26% — норма", SurvivalRules.tier(26.0) == "")
	check("25% — «мало» (порог предупреждения)", SurvivalRules.tier(25.0) == SurvivalRules.LOW)
	check("10% — «критично» (порог серьёзного предупреждения)", SurvivalRules.tier(10.0) == SurvivalRules.CRITICAL)
	check("0 — «пусто»", SurvivalRules.tier(0.0) == SurvivalRules.EMPTY)


func _test_drain_and_soft_start() -> void:
	print("--- Расход выше базы владельца, кроме мягкого старта ---")
	var base := Balance.get_bar_depletion_rate_per_second("hunger", true) * 100.0   # % в секунду
	_fresh(100.0, 100.0, true)
	GameState.level = 1
	GameState.is_digging = true
	GameState._tick_survival(10.0)
	check_near("после урока сна голод тает ×1.5 при копке", 100.0 - GameState.hunger, base * 10.0 * 1.5)
	check_near("после урока сна бодрость тает ×1.3 при копке", 100.0 - GameState.stamina, base * 10.0 * 1.3)

	_fresh(100.0, 100.0, false)
	GameState.level = 1
	GameState.is_digging = true
	check("до урока сна на 1-м уровне — мягкий старт", SurvivalRules.soft_start_active())
	GameState._tick_survival(10.0)
	check_near("мягкий старт: голод — по базе владельца", 100.0 - GameState.hunger, base * 10.0)
	check_near("мягкий старт: бодрость — по базе владельца", 100.0 - GameState.stamina, base * 10.0)

	GameState.level = 5
	check("с 5-го уровня мягкий старт кончается и без урока сна (осторожный игрок до 8% не доходит)",
		not SurvivalRules.soft_start_active())
	GameState.level = 1
	GameState.house_tutorial_stage = 1
	check("урок сна без сюжета (дом) тоже кончает мягкий старт", not SurvivalRules.soft_start_active())
	GameState.is_digging = false


func _test_skills_answer_pressure() -> void:
	print("--- Прокачка — ответ на давление ---")
	var effects := UpgradeEffects.new()
	add_child(effects)
	var base := Balance.get_bar_depletion_rate_per_second("hunger", true) * 100.0
	_fresh(100.0, 100.0, true)
	GameState.skill_stages["hunger"] = 5
	GameState.skill_stages["stamina"] = 2
	GameState.is_digging = true
	GameState._tick_survival(10.0)
	effects._refund("hunger", 10.0)
	effects._refund("stamina", 10.0)
	check_near("«Голод» 5 (−40%) возвращает долю от ПОВЫШЕННОГО расхода: ×1.5×0.6",
		100.0 - GameState.hunger, base * 10.0 * 1.5 * 0.6)
	check_near("«Выносливость» 2 (+40% времени) — расход ×1.3/1.4, уже не больше базы",
		100.0 - GameState.stamina, base * 10.0 * 1.3 / 1.4)
	check("2-я ступень выносливости возвращает базовое время до истощения", 1.3 / 1.4 <= 1.0)
	check_near("ступень 1 выносливости экономит 1−1/1.2 расхода",
		effects._saved_fraction("stamina", 1), 1.0 - 1.0 / 1.2, 0.001)
	check_near("ступень 10 голода экономит 80% расхода (потолок прежний)",
		effects._saved_fraction("hunger", 10), 0.8, 0.001)
	effects.queue_free()
	GameState.is_digging = false


func _test_branch_prices() -> void:
	print("--- Ветки «Голод» и «Выносливость» дешевле ---")
	for id in ["hunger", "stamina"]:
		check("%s: первая ступень — 1 очко" % id, Balance.get_upgrade_stage_cost(id, 1) == 1)
		check("%s: вторая ступень — 1 очко" % id, Balance.get_upgrade_stage_cost(id, 2) == 1)
		check("%s: вся ветка — 30 очков" % id, Balance.get_upgrade_total_cost(id, 10) == 30)
		check("%s: пять ступеней — 9 очков" % id, Balance.get_upgrade_total_cost(id, 5) == 9)
	check("«Выносливость» — +20% до истощения за ступень",
		int(Balance.unwrap(Balance.get_upgrade_branch("stamina")["effect"]["percent_per_stage"])) == 20)
	check("«Голод» — −8% расхода за ступень (как было)",
		int(Balance.unwrap(Balance.get_upgrade_branch("hunger")["effect"]["percent_per_stage"])) == 8)
	# Остальные ветки не тронуты (зона раунда 5 — только эти две).
	check("«Сила» по-прежнему 2…11", Balance.get_upgrade_total_cost("strength", 10) == 65)
	check("«HP» по-прежнему 1…10", Balance.get_upgrade_total_cost("hp", 10) == 55)


func _find_cell(world: WorldGen) -> Vector2i:
	for y in range(40, 300):
		for x in range(20, 40):
			var t := world.get_tile(x, y)
			if t == TileTypes.Type.EMPTY or not TileTypes.is_diggable(t) or t == TileTypes.Type.LAVA:
				continue
			if not MineralMap.is_loot(t):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _dig_total(p: Node, cell: Vector2i) -> float:
	p.digging = null
	p._start_dig(cell.x, cell.y)
	var t: float = float(p.digging["total"]) if p.digging != null else -1.0
	p.digging = null
	return t


func _test_dig_time() -> void:
	print("--- Копка: голод и усталость замедляют ---")
	var world := WorldGen.new(4242)
	GameState.world_ref = world
	var cell := _find_cell(world)
	check("нашлась клетка породы", cell.x >= 0)
	_fresh()
	GameState.current_tool = "iron_pickaxe"
	var p = _player(world)
	var t0 := _dig_total(p, cell)
	check("копка идёт", t0 > 0.0)

	_fresh(20.0, 100.0)
	GameState.current_tool = "iron_pickaxe"
	check_near("сытость 20%: клетка дольше в 1/0.85", _dig_total(p, cell), t0 / 0.85)
	_fresh(5.0, 100.0)
	GameState.current_tool = "iron_pickaxe"
	check_near("сытость 5%: в 1/0.7", _dig_total(p, cell), t0 / 0.7)
	_fresh(100.0, 20.0)
	GameState.current_tool = "iron_pickaxe"
	check_near("бодрость 20%: в 1/0.85", _dig_total(p, cell), t0 / 0.85)
	_fresh(100.0, 0.0)
	GameState.current_tool = "iron_pickaxe"
	check_near("бодрость 0: вдвое дольше (−50% владельца)", _dig_total(p, cell), t0 / 0.5)
	_fresh(20.0, 20.0)
	GameState.current_tool = "iron_pickaxe"
	check_near("оба по 20%: штрафы множатся (0.85×0.85)", _dig_total(p, cell), t0 / (0.85 * 0.85))
	p.queue_free()


func _walk_speed(p: Node, t: float = 0.0) -> float:
	p.digging = null
	p.on_ground = true
	p.hold_dx = 1
	p.hold_up = false
	p._jump_buffer_left = 0.0
	p._stagger_t = t
	p._apply_intent(0.0)
	var v: float = absf(float(p.vx))
	p.hold_dx = 0
	return v


func _test_walk_and_stagger() -> void:
	print("--- Ходьба и «шатание» ---")
	var world := WorldGen.new(4242)
	var p = _player(world)
	p.x = 20.5
	p.y = -3.0
	_fresh()
	var v0 := _walk_speed(p)
	check("ходьба идёт", v0 > 0.0)
	_fresh(100.0, 20.0)
	check_near("бодрость 20%: ходьба ×0.85", _walk_speed(p) / v0, 0.85)
	_fresh(100.0, 5.0)
	check_near("бодрость 5%: ходьба ×0.7", _walk_speed(p) / v0, 0.7)
	_fresh(5.0, 100.0)
	check_near("голод ходьбу не трогает", _walk_speed(p) / v0, 1.0)
	_fresh(100.0, 0.0)
	var lo := 1.0
	var hi := 0.0
	for i in range(24):
		var r := _walk_speed(p, 1.2 * float(i) / 24.0) / v0
		lo = minf(lo, r)
		hi = maxf(hi, r)
	check_near("без сил: шаг тянется до половины (−50% владельца)", hi, 0.5, 0.02)
	check_near("без сил: и спотыкается до 60% от половины", lo, 0.5 * 0.6, 0.02)
	check("без сил — шатает", SurvivalRules.is_staggering())
	_fresh(100.0, 1.0)
	check("1% бодрости — ещё не шатает", not SurvivalRules.is_staggering())
	p.queue_free()


func _test_jump() -> void:
	print("--- Прыжок ниже ---")
	var world := WorldGen.new(4242)
	var p = _player(world)
	var vs: Dictionary = {}
	for st in [100.0, 20.0, 5.0, 0.0]:
		_fresh(100.0, st)
		p.x = 20.5
		p.y = -3.0
		p.vy = 0.0
		p.on_ground = true
		p.digging = null
		p.stun_until_msec = 0
		p._jump()
		vs[st] = -float(p.vy)
	check("прыжок есть", float(vs[100.0]) > 0.0)
	# высота прыжка ~ v²
	check_near("бодрость 20%: высота ×0.9", pow(vs[20.0] / vs[100.0], 2.0), 0.9)
	check_near("бодрость 5%: высота ×0.8", pow(vs[5.0] / vs[100.0], 2.0), 0.8)
	check_near("без сил: скорость толчка — корень из 0.7", pow(vs[0.0] / vs[100.0], 2.0), 0.7)
	p.queue_free()

	# Настоящая физика (с зависанием в верхней точке): насколько поднимается центр героя.
	var rise: Dictionary = {}
	for st in [100.0, 20.0, 0.0]:
		_fresh(100.0, st)
		var q = _player(world)
		q.frozen = false
		q.x = 5.5
		q.y = -2.5
		q.vy = 0.0
		for i in range(120):
			q.physics_tick(1.0 / 30.0)
		var y0: float = q.y
		q._jump()
		var top: float = y0
		for i in range(90):
			q.physics_tick(1.0 / 30.0)
			top = minf(top, q.y)
		rise[st] = y0 - top
		q.queue_free()
	print("  подъём центра: бодрый %.2f, 20%% — %.2f, без сил — %.2f клетки" % [rise[100.0], rise[20.0], rise[0.0]])
	check("бодрый берёт уступ в две клетки", float(rise[100.0]) >= 2.0)
	check("на 20% бодрости две клетки уже не взять — только ранцем", float(rise[20.0]) < 2.0)
	check("без сил ступенька в одну клетку по-прежнему берётся (тупика нет)", float(rise[0.0]) >= 1.15)


func _test_flight_untouched() -> void:
	print("--- Подъём (полёт) ступени не трогают ---")
	_fresh(100.0, 20.0)
	check("бодрость 20%: множитель полёта 1", is_equal_approx(GameState.get_speed_multiplier(), 1.0))
	_fresh(5.0, 5.0)
	check("бодрость и сытость 5%: множитель полёта 1", is_equal_approx(GameState.get_speed_multiplier(), 1.0))
	_fresh(100.0, 0.0)
	check("без сил: −50% владельца, как было", is_equal_approx(GameState.get_speed_multiplier(), 0.5))


## Сид, у которого первый бросок (в процентах) попадает в [lo, hi).
func _rng_between(lo: float, hi: float) -> RandomNumberGenerator:
	for s in range(1, 20000):
		var r := RandomNumberGenerator.new()
		r.seed = s
		var v := r.randf() * 100.0
		if v >= lo and v < hi:
			var out := RandomNumberGenerator.new()
			out.seed = s
			return out
	return null


func _test_luck() -> void:
	print("--- Голодному везёт реже ---")
	var world := WorldGen.new(4242)
	var p = _player(world)
	var chance: float = float(Balance.get_luck_chance_percent(5)["resource"])
	for row in [[100.0, true, "сытый: бросок в [шанс/2, шанс) — удача"],
			[20.0, false, "сытость 20%: тот же бросок — мимо (шанс вдвое меньше)"]]:
		_fresh(float(row[0]), 100.0)
		GameState.skill_stages["luck_chance"] = 5
		p._luck_rng = _rng_between(float(chance) * 0.5, float(chance))
		check(String(row[2]), (p._luck_roll(true) > 1) == bool(row[1]))
	_fresh(20.0, 100.0)
	GameState.skill_stages["luck_chance"] = 5
	p._luck_rng = _rng_between(0.0, float(chance) * 0.5)
	check("сытость 20%: бросок ниже половины шанса — удача есть", p._luck_roll(true) > 1)
	_fresh(0.0, 100.0)
	GameState.skill_stages["luck_chance"] = 5
	p._luck_rng = _rng_between(0.0, 0.01)
	check("голод на нуле: удачи нет вовсе", p._luck_roll(true) == 1)
	check_near("доля удачи 25% → 0.5", SurvivalRules.luck_factor(25.0), 0.5)
	check_near("доля удачи 10% → 0.25", SurvivalRules.luck_factor(10.0), 0.25)
	p.queue_free()


func _test_owner_numbers_kept() -> void:
	print("--- Числа владельца на месте ---")
	check("голод на нуле — 1 HP/с", is_equal_approx(Balance.get_hp_drain_per_second(true, false), 1.0))
	check("пустая бодрость HP не трогает", is_equal_approx(Balance.get_hp_drain_per_second(false, true), 0.0))
	check("база: 20 минут копки до нуля", is_equal_approx(
		Balance.get_bar_depletion_rate_per_second("stamina", true), 1.0 / 1200.0))
	check("сон тратит голод по базе (повышенный расход сна не касается)",
		is_equal_approx(HouseSleep.hunger_cost(1.0), 100.0 / 3600.0 * 450.0 * HouseConfig.sleep_hunger_factor()))
	# Голод на нуле при пустой бодрости по-прежнему ест HP вдвое быстрее.
	_fresh(0.0, 0.0)
	var hp0: float = GameState.hp
	GameState._tick_survival(1.0)
	check_near("обе пусты — 2 HP за секунду", hp0 - GameState.hp, 2.0)


func _test_badges() -> void:
	print("--- Значки у полосок ---")
	_fresh()
	var hunger_bar := HudBar.new().setup(Color.RED, null)
	var stamina_bar := HudBar.new().setup(Color.YELLOW, null)
	hunger_bar.bar_width = 62.0
	stamina_bar.bar_width = 62.0
	add_child(hunger_bar)
	add_child(stamina_bar)
	var hb := SurvivalBadge.attach(hunger_bar, "hunger")
	var sb := SurvivalBadge.attach(stamina_bar, "stamina")
	await get_tree().process_frame
	check("сытый и бодрый — значков нет", not hb.visible and not sb.visible)
	check("и в подсказке полоски ничего лишнего", SurvivalBadge.tip_suffix(hunger_bar) == "")

	GameState.set_hunger(20.0)
	check("сытость 20% — значок «слабее»", hb.visible and String(hb.status()["icon"]) == "st_weak")
	check("текст — в подсказке значка", String(hb.get_meta(Tip.META, {}).get("body", "")).contains("копка −15%"))
	check("и в подсказке самой полоски", SurvivalBadge.tip_suffix(hunger_bar).contains("Голоден"))
	GameState.set_hunger(0.0)
	check("голод на нуле — «здоровье тает»", String(hb.status()["icon"]) == "st_drain"
		and String(hb.status()["text"]).contains("1 HP"))
	GameState.set_stamina(20.0)
	check("бодрость 20% — улитка «медленнее»", sb.visible and String(sb.status()["icon"]) == "st_slow")
	GameState.set_stamina(0.0)
	check("без сил — «шатает»", String(sb.status()["icon"]) == "st_dizzy")
	await get_tree().process_frame
	check("значок стоит на правом конце полоски",
		absf(sb.position.x + SurvivalBadge.SIZE + 1.0 - stamina_bar.size.x) < 0.5)
	for n in ["st_slow", "st_weak", "st_dizzy", "st_drain"]:
		check("значок %s нарисован" % n, UiIcons.tex(n) != null)
	GameState.set_hunger(100.0)
	GameState.set_stamina(100.0)
	check("поел и выспался — значки ушли", not hb.visible and not sb.visible)
	hunger_bar.queue_free()
	stamina_bar.queue_free()


func _test_data_marked_proposed() -> void:
	print("--- Новые числа помечены proposed ---")
	var d := SurvivalRules.data()
	check("data/survival.json читается", not d.is_empty())
	var bad: Array = []
	for bar in ["hunger", "stamina"]:
		# множители таяния владелец утвердил на странице разбора чисел (26.10) — обёртка с proposed: false
		var dm = d["drain_multiplier"][bar]
		if typeof(dm) != TYPE_DICTIONARY or dm.get("proposed", true) != false:
			bad.append("drain_multiplier." + bar + " (ждём утверждённую обёртку)")
		# штрафы владелец утвердил 26.10 («можно убавить на 5, 10 и 30»): обёртки с proposed: false
		for t in d[bar + "_tiers"]:
			for k in d[bar + "_tiers"][t]:
				var w = d[bar + "_tiers"][t][k]
				if typeof(w) != TYPE_DICTIONARY or w.get("proposed", true) != false:
					bad.append("%s.%s.%s" % [bar, t, k])
	check("числа survival.json утверждены владельцем — обёртки с proposed: false (%s)" % ", ".join(bad), bad.is_empty())
	for id in ["hunger", "stamina"]:
		var costs: Array = Balance.get_upgrade_branch(id)["cost_points"]
		check("%s: цены ступеней — proposed" % id, costs.all(func(c): return Balance.is_proposed(c)))

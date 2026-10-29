extends Node
## test_tech_balance — границы баланса ветки «Техника» (ГДД п.18 «цена ступеней»).
## Полные таблицы и обоснование — tools/sim_tech.py (python3 tools/sim_tech.py); здесь
## те же инварианты считаются на движке, на тех же данных, чтобы правка tech.json или
## породы не разошлась с расчётом молча:
##  * ступени скважины окупаются за 0.3–12 суток (два забора в сутки по окну до 8 ч);
##  * доход скважины растёт со ступенью, а ролик «×2» не даёт больше окна;
##  * бак держит 120–540 клеток по ступеням и топливо в породе добирается без
##    превращения добычи топлива в основное занятие;
##  * лава: цена клетки по ступеням убывает к нулю, а с 300 HP первая ступень её берёт.
##
## Запуск: godot --headless --path . res://tests/test_tech_balance.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


## Цена материала в монетах для окупаемости: продаваемое — по цене скупки, экзотика без
## цены (геокристалл, древний металл, обсидиан) — как рубин, 600: руками её берут
## по 12–24 с на клетку, дешёвой она не бывает.
func _mat_value(id: String) -> int:
	var p := Balance.get_mineral_price(id)
	return p if p > 0 else 600


func _cost_value(cost) -> int:
	if typeof(cost) != TYPE_DICTIONARY:
		return 0
	var v := int(cost.get("coins", 0))
	for id in cost.get("items", {}).keys():
		v += _mat_value(String(id)) * int(cost["items"][id])
	return v


func _ready() -> void:
	print("=== test_tech_balance ===")
	await get_tree().process_frame
	TechData.reload()
	_well()
	_fuel()
	_lava()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _well() -> void:
	var levels := IdleWell.levels()
	var prev_rate := 0.0
	for i in range(1, levels.size() + 1):
		var rate := IdleWell.income_per_hour(i)
		# Скважина копает на глубине своей ступени, пока игрок её достиг.
		GameState.max_depth_reached = 7000
		rate = IdleWell.income_per_hour(i)
		check("ступень %d: доход растёт (%.0f в час)" % [i, rate], rate > prev_rate)
		if i >= 2:
			var gain := rate - prev_rate
			var window := minf(IdleWell.cap_hours(i), 8.0) * 2.0   # часов копки в сутки при двух заборах
			var days := _cost_value(levels[i - 1]["cost"]) / maxf(gain * window, 1.0)
			check("ступень %d окупается за 0.3–12 суток (%.1f)" % [i, days], days >= 0.3 and days <= 12.0)
		prev_rate = rate
	var build = Balance.balance["idle_well"]["build_cost"]
	var flat: Dictionary = Balance.unwrap(build)
	var build_cost := int(flat.get("coins", 0))
	for id in flat.keys():
		if id != "coins":
			build_cost += _mat_value(String(id)) * int(flat[id])
	var days0 := build_cost / maxf(IdleWell.income_per_hour(1) * 16.0, 1.0)
	# владелец (26.10): скважина дороже ручного бура — окупается дольше, но не больше пяти суток
	check("постройка скважины окупается за 0.5–5 суток (%.1f)" % days0, days0 >= 0.5 and days0 <= 5.0)
	# Кап и ×2: за один заход на последней ступени — не больше суток дохода.
	var max_run := IdleWell.income_per_hour(levels.size()) * IdleWell.cap_hours(levels.size())
	check("окно последней ступени — не больше 24 часов дохода", IdleWell.cap_hours(levels.size()) <= 24.0 and max_run > 0.0)
	check("ролик «×2» — не больше 4 в сутки (владелец 26.10: «можно больше чуть»; удваивает окно, не растит ставку)", TechAds.daily_limit() <= 4)
	# Скважина не конкурирует с рукой: час работы скважины дешевле часа активной игры.
	# Активная игра на глубине 600 ≈ 12 тыс. монет в час (tools/sim_tech.py); скважина ступени 3
	# на той же глубине — на порядок меньше.
	GameState.max_depth_reached = 600
	check("час скважины ступени 3 на 600 — меньше 10%% часа активной игры (%.0f)" % IdleWell.income_per_hour(3),
		IdleWell.income_per_hour(3) < 1200.0)


func _fuel() -> void:
	for tool_id in ["hand_drill", "drill_rig"]:
		var caps := FuelTank.capacities(tool_id)
		var r := FuelTank.rate_per_cell(tool_id)
		var lo := float(caps[0]) / r
		var hi := float(caps[caps.size() - 1]) / r
		check("%s: бак 0 держит 100–150 клеток (%d)" % [tool_id, int(lo)], lo >= 100.0 and lo <= 150.0)
		check("%s: бак 4 держит 450–600 клеток (%d)" % [tool_id, int(hi)], hi >= 450.0 and hi <= 600.0)
	var world := WorldGen.new(1)
	var per_block_peat := float(Balance.balance["fuel_consumption"]["peat_per_fuel_block"])
	var per_block_coal := float(Balance.unwrap(Balance.balance["fuel_consumption"]["coal_per_fuel_block"]))
	for probe in [[450, "hand_drill"], [900, "hand_drill"], [1500, "drill_rig"]]:
		var y := int(probe[0])
		var blocks := 0.0
		for d in world.ore_densities_at(y):
			if d["id"] == "peat":
				blocks += float(d["density"]) / per_block_peat
			elif d["id"] == "coal":
				blocks += float(d["density"]) / per_block_coal
		var need := FuelTank.rate_per_cell(String(probe[1]))
		check("глубина %d, %s: порода даёт %.3f блока на клетку при расходе %.3f — топлива хватает без отдельной добычи"
			% [y, probe[1], blocks, need], blocks >= need * 0.95)
	# Дальше (1100, 3000) топлива из породы не хватает. На 3000 добор не превращается в основное
	# занятие (≤ 35% копки). На 1100 уголь только начинается (владелец 27.10: с 1000 растёт с нуля),
	# и там добор не обязателен: пустой бак копает киркой (владелец 29.10: «когда заканчивается
	# топливо, он берётся за кирку», «с топливом всё ок»).
	var rig_mult := Balance.get_tool_speed_multiplier("drill_rig")
	var pick_mult := Balance.get_best_pickaxe_speed_multiplier()
	for probe in [[1100, -1.0], [3000, 0.35]]:
		var y := int(probe[0])
		var limit := float(probe[1])
		var blocks := 0.0
		var p_fuel := 0.0
		for d in world.ore_densities_at(y):
			if d["id"] == "peat" or d["id"] == "coal":
				var per := per_block_peat if d["id"] == "peat" else per_block_coal
				blocks += float(d["density"]) / per
				p_fuel = maxf(p_fuel, float(d["density"]))
		var deficit := maxf(0.0, FuelTank.rate_per_cell("drill_rig") - blocks)
		var per_cell_yield := 1.0 / per_block_coal
		var extra := deficit / per_cell_yield / maxf(p_fuel, 0.0001)
		if limit >= 0.0:
			check("глубина %d: добор топлива +%.0f%% копки (≤ %.0f%%)" % [y, extra * 100.0, limit * 100.0], extra <= limit)
		else:
			print("  глубина %d: добор топлива +%.0f%% копки — не обязателен, пустой бак копает киркой" % [y, extra * 100.0])
		# Без добора: клетки на топливе из породы — бурмобилем, остальные — киркой.
		var share := clampf(blocks / FuelTank.rate_per_cell("drill_rig"), 0.0, 1.0)
		var eff := 1.0 / (share / rig_mult + (1.0 - share) / pick_mult)
		check("глубина %d: без добора бурмобиль на топливе из породы (%.0f%%) и кирке копает ×%.2f — не медленнее кирки ×%.2f"
			% [y, share * 100.0, eff, pick_mult], eff >= pick_mult - 0.0001)


func _lava() -> void:
	var raw := Heat.lava_cell_cost_hp(0)
	check("клетка лавы без костюма — 100 HP (решение владельца: 5 с × 20 HP/с)", raw == 100.0)
	var prev := raw
	var ok := true
	for t in range(1, 6):
		var c := Heat.lava_cell_cost_hp(t)
		ok = ok and c < prev
		prev = c
	check("цена клетки лавы падает с каждой ступенью костюма", ok)
	check("ступень 1 даёт герою с 300 HP пройти 3 клетки лавы подряд (75 HP/клетка)", Heat.lava_cell_cost_hp(1) * 3.0 < 300.0)
	check("ступень 3 — 9 клеток подряд на 300 HP", Heat.lava_cell_cost_hp(3) * 9.0 < 300.0)
	check("ступень 5 — лава безвредна", Heat.lava_cell_cost_hp(5) == 0.0)
	# Жара: на глубине первой лавы (3000) без костюма бодрость тратится втрое, три ступени снимают штраф.
	check("на 3000 нужна ступень 3, чтобы жара не мешала", Heat.stamina_multiplier(3000, 2) > 1.0 and Heat.stamina_multiplier(3000, 3) == 1.0)

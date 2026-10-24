extends Node
## Экономический симулятор: за сколько игровых минут «добытчик» проходит
## ступени прогресса — рюкзак, кирки, ручной бур, прокачка.
##
## Считает НА НАСТОЯЩЕМ ГЕНЕРАТОРЕ (WorldGen) и НАСТОЯЩИХ ЧИСЛАХ (Balance), а не на
## копии формул: поправил balance.json — перезапусти и сверь.
##
##   godot --headless --path . res://tools/sim_economy.tscn
##   godot --headless --path . res://tools/sim_economy.tscn -- --seeds=8 --policy=lateral --hours=24
##
## Параметры (после «--»):
##   --seeds=N         сколько сидов мира усреднять (по умолчанию 6)
##   --policy=shaft    копать вертикальную шахту и ничего больше (нижняя граница)
##   --policy=lateral  то же + подбирать руду, видимую рядом (радиус обзора ветки «Обзор»)
##   --policy=farm     серпантин по рядам на всю ширину мира: копать каждый ряд от стены до
##                     стены и спускаться на ряд ниже (как копает игрок с обзором 1; глубина
##                     растёт медленно, зато видны скрап и железо верхних 200 клеток)
##   --hours=H         предел игрового времени на прогон (по умолчанию 48)
##   --skills=a,b,c    очерёдность вложения очков прокачки (по умолчанию dig_speed,strength,vision)
##   --bank=iron|start когда начинать откладывать материалы под ручной бур (по умолчанию iron:
##                     после железной кирки)
##   --fill=0.9        доля грузоподъёмности, при которой поднимаемся продавать
##   --smart=1|0       1: подниматься раньше, если проданного хватит на следующую ступень
##   --artifacts=1|0   1 (по умолчанию): находки артефактов платят монетами и опытом, как в игре
##                     (позиции — из ArtifactSpawn по сиду мира); 0 — чистая добыча руды
##   --json=путь       сохранить результат (потом сверять до/после правок баланса)
##   --mech=1|0        1: механики раунда 3 (ГДД §20.1, scripts/mechanics/): тайники, жадность азарта
##                     (копка с первого удара и руда вдвое, пока идёт таймер), двойная добыча мастерства —
##                     той же логикой, что в игре (ChestLogic, StreakLogic, GreedRules, MasteryLogic).
##                     Ветка «Жадность» качается, если её id есть в --skills. По умолчанию 0 — прежние
##                     числа §18 не меняются.
##   --fever_extra=N   сколько штук сверху даёт рудная клетка в жадности (по умолчанию streak.fever_extra
##                     из data/mechanics.json; 0 — жадность без удвоения, только темп)
##
## Модель (всё, что она НЕ учитывает, перечислено — числа это ориентир, не истина):
##  * герой копает колонку x=17 (ствол тоннеля Роберта) вниз от первого уровня под
##    фундаментом; ранец (100 монет) нужен, чтобы подниматься — покупается первым;
##  * время клетки = секунды минерала / (множитель кирки × общий 1.3) × 0.96^ступень «Скорости копки»;
##    ржавая кирка с глубины 80 теряет 25% скорости;
##  * подъём и спуск — на потолке скорости ранца с поправкой на перегруз (последние 15% веса);
##  * добыча: руда кладётся в рюкзак, при заполнении — подъём, продажа, покупки;
##  * материалы под ручной бур (железо, металлолом→бронза, серебро) откладываются на верстак
##    (invest) и вес не занимают — как в магазине;
##  * НЕ учтено: топливо бура, перегрев, голод/сон (заложен фиксированный накладной расход),
##    квесты и мета-награды, обвалы, лава, ходьба по горизонтали сверх бокового забора.

const START_COINS := 550            # 500 за пять самородков + 50 за никчёмный клад (бот онбординга, ГДД §9)
const START_TIME_S := 100.0         # онбординг по боту: интро, автокопка, кирка, золото, смерть (игровые секунды)
const SHAFT_X := WorldGen.TUNNEL_X
const SHAFT_START_Y := 6            # первая клетка под пробитым фундаментом (фундамент y=5)
const TRIP_OVERHEAD_S := 25.0       # дойти до двери, зайти, продать, купить, выйти
const UPKEEP_EVERY_S := 1200.0      # еда/сон: раз в полное истощение полоски при копке (ГДД §7)
const UPKEEP_COST_S := 30.0
const SIDE_TURN_S := 0.4            # тап в сторону

var _opt := {"seeds": 6, "policy": "shaft", "hours": 48.0, "skills": "dig_speed,strength,vision",
	"bank": "iron", "fill": 0.9, "smart": "1", "artifacts": "1", "json": "", "mech": "0", "fever_extra": ""}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_opt[kv[0]] = kv[1]
	var seeds_n := int(_opt["seeds"])
	var results: Array = []
	for i in range(seeds_n):
		results.append(_simulate(1000 + i * 7919))
	_report(results)
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# Один прогон
# ---------------------------------------------------------------------------

func _simulate(seed_value: int) -> Dictionary:
	var world := WorldGen.new(seed_value)
	var lateral: bool = String(_opt["policy"]) == "lateral"
	var limit_s: float = float(_opt["hours"]) * 3600.0
	var skills_order: Array = String(_opt["skills"]).split(",", false)

	var s := {
		"t": START_TIME_S, "depth": SHAFT_START_Y - 1, "coins": START_COINS, "items": {}, "bank": {},
		"tool": "rusty_pickaxe", "gear": "", "stages": {}, "xp": 0, "level": 1, "points": 0,
		"pickaxes": ["rusty_pickaxe"], "next_upkeep": UPKEEP_EVERY_S, "cells": 0, "trips": 0,
		"drill": false, "mile": {}, "max_depth_milestone": 0,
		"artifacts": [], "dollars": 0, "seed": seed_value, "artifact_coins": 0, "sold": 0,
	}
	if String(_opt["mech"]) == "1":
		var mrng := RandomNumberGenerator.new()
		mrng.seed = seed_value * 31 + 7
		s["mech"] = {"streak": StreakLogic.new(), "n": {}, "stars": {}, "opened": {}, "bands": {}, "rng": mrng,
			"val": {"chest": 0, "fever": 0, "mastery": 0}, "chests": 0, "fevers": 0, "greed_cells": 0}
	# Ступени, которые покупает добытчик, — по стоимости, кирки строго по порядку.
	var ladder: Array = _build_ladder()
	var needs: Dictionary = _drill_needs()
	var banking := String(_opt["bank"]) == "start"
	var fill := float(_opt["fill"])
	_shop(s, ladder, needs)  # первым делом — ранец на стартовые монеты

	var farm: bool = String(_opt["policy"]) == "farm"
	var col := SHAFT_X
	var dir := -1
	while s["t"] < limit_s and not s["drill"]:
		var y: int = s["depth"] + 1 if not farm else int(s["depth"])
		if farm:
			# Серпантин: весь ряд от стены до стены, потом ряд ниже. Так копает игрок с радиусом
			# обзора 1: руду видно только вплотную, поэтому он расчищает уровень целиком.
			y = maxi(y, SHAFT_START_Y)
			_dig_cell(s, world, col, y, false)
			s["t"] += 1.0 / 4.2
			col += dir
			if col < 0 or col >= WorldGen.WIDTH:
				col -= dir
				dir = -dir
				s["depth"] = y + 1
			else:
				s["depth"] = y
			y = int(s["depth"])
		else:
			_dig_cell(s, world, SHAFT_X, y, true)
			s["depth"] = y
			if s.has("mech"):
				_mech_peek(s, world, y)
			if lateral:
				var r: int = Balance.get_vision_radius("vision", int(s["stages"].get("vision", 0)))
				_lateral_pick(s, world, y, r)
		_depth_milestones(s)
		_level_up(s, skills_order)

		# upkeep: еда и сон
		while s["t"] >= s["next_upkeep"]:
			s["t"] += UPKEEP_COST_S
			s["next_upkeep"] += UPKEEP_EVERY_S
			if s.has("mech"):
				s["mech"]["streak"].reset()   # поел или поспал — серия прервалась

		var cap: float = Balance.get_max_carry_kg(int(s["stages"].get("strength", 0)))
		if _weight(s) >= cap * fill or _worth_going_home(s, ladder, needs):
			if not banking and _has_pick(s, "iron_pickaxe"):
				banking = true
			_trip(s, cap, needs, banking)
			_shop(s, ladder, needs)
	s["limit_hit"] = not s["drill"]
	return s


## Умный игрок не ждёт полного рюкзака, если проданного хватит на следующую ступень.
func _worth_going_home(s: Dictionary, ladder: Array, _needs: Dictionary) -> bool:
	if String(_opt["smart"]) != "1":
		return false
	var cost := _next_cost(s, ladder)
	if cost <= 0 or int(s["coins"]) >= cost:
		return false  # уже хватало (купили бы при прошлом заходе) или покупать нечего
	var value := 0
	for id in s["items"].keys():
		value += Balance.get_mineral_price(String(id)) * int(s["items"][id])
	return int(s["coins"]) + value >= cost + 20  # запас на мелочь


func _next_cost(s: Dictionary, ladder: Array) -> int:
	for row in ladder:
		var id: String = row["id"]
		if row["kind"] == "gear":
			if Balance.get_gear_fly_multiplier(id) <= Balance.get_gear_fly_multiplier(String(s["gear"])):
				continue
		elif _has_pick(s, id):
			continue
		return int(row["cost"])
	return 0


func _weight(s: Dictionary) -> float:
	var w := 0.0
	for id in s["items"].keys():
		w += float(s["items"][id]) * Balance.get_mineral_weight(String(id))
	return w


## Секунды на клетку: минерал по твёрдости, кирка, общий множитель, прокачка.
func _cell_seconds(s: Dictionary, tile: int, y: int) -> float:
	var mid := MineralMap.mineral_id_for(tile)
	var base: float = Balance.get_mineral_drill_seconds(mid) if not mid.is_empty() \
		else float(Balance.unwrap(Balance.balance.get("digging", {}).get("base_seconds_per_cell", 3.0)))
	var mult: float = Balance.get_tool_speed_multiplier(String(s["tool"]))
	if s["tool"] == "rusty_pickaxe" and y >= 80:
		mult *= float(Balance.unwrap(Balance.get_tool("rusty_pickaxe").get("broken_speed_multiplier", 0.75)))
	var stage := int(s["stages"].get("dig_speed", 0))
	return maxf(base * pow(0.96, float(stage)) / maxf(mult, 0.01) / Balance.get_global_dig_speed_multiplier(), 0.05)


func _dig_cell(s: Dictionary, world: WorldGen, x: int, y: int, in_shaft: bool) -> void:
	var tile := world.get_tile(x, y)
	if tile == TileTypes.Type.EMPTY:
		return
	var sec := _cell_seconds(s, tile, y)
	if s.has("mech"):
		# жадность (ГДД §20.1): клетка — с первого удара; таймер идёт временем копки
		# (ход ×7 по прокопанному здесь не учтён — оценка снизу)
		var st: StreakLogic = s["mech"]["streak"]
		st.set_stage(int(s["stages"].get("greed", 0)))
		if st.in_greed():
			sec = minf(sec, GreedRules.dig_seconds(String(s["tool"])))
			s["mech"]["greed_cells"] += 1
		st.tick(sec, true, true)
	s["t"] += sec
	s["cells"] += 1
	var mid := MineralMap.mineral_id_for(tile)
	var price := Balance.get_mineral_price(mid) if not mid.is_empty() else 0
	if tile == TileTypes.Type.DIRT:
		s["xp"] += 1
	elif tile == TileTypes.Type.STONE:
		s["xp"] += 2
	elif price > 0:
		s["xp"] += int(round(float(price) / 5.0))
	if MineralMap.is_loot(tile):
		s["items"][mid] = int(s["items"].get(mid, 0)) + 1
	if String(_opt["artifacts"]) == "1":
		_artifact_find(s, x, y)
	if s.has("mech"):
		_mech_dug(s, world, x, y, mid, MineralMap.is_loot(tile))


## Находка артефакта в выкопанной клетке: монеты, опыт и награда за закрытую ветку — теми же
## числами, что GameState.collect_artifact.
func _artifact_find(s: Dictionary, x: int, y: int) -> void:
	var id := ArtifactSpawn.artifact_id_at(x, y, int(s["seed"]), Balance.artifacts.get("artifacts", []), s["artifacts"])
	if id.is_empty():
		return
	s["artifacts"].append(id)
	var coins := Balance.get_artifact_find_coins(id)
	s["coins"] += coins
	s["artifact_coins"] += coins
	s["xp"] += Balance.get_artifact_find_xp(id)
	var branch := int(Balance.get_artifact(id).get("branch", -1))
	if branch > 0 and Balance.is_branch_complete(branch, s["artifacts"]):
		for b in Balance.artifacts.get("branches", []):
			if int(b.get("branch", -1)) == branch:
				var reward: Dictionary = b.get("completion_reward", {})
				var rc := int(Balance.unwrap(reward.get("coins", 0)))
				s["coins"] += rc
				s["artifact_coins"] += rc
				s["dollars"] += int(Balance.unwrap(reward.get("premium_currency", 0)))
	if s["artifacts"].size() == 5 and not s["mile"].has("5 артефактов"):
		s["mile"]["5 артефактов"] = s["t"]


## Руда рядом с шахтой: на радиусе обзора. Соседняя клетка берётся «через плечо»
## (копнул в сторону, шаг не нужен), дальше — прокопать и вернуться пешком.
func _lateral_pick(s: Dictionary, world: WorldGen, y: int, radius: int) -> void:
	for side in [-1, 1]:
		for k in range(1, radius + 1):
			var x: int = SHAFT_X + side * k
			if x < WorldGen.GARDEN_X_MIN or x >= WorldGen.WIDTH:
				break
			var tile := world.get_tile(x, y)
			if not TileTypes.is_ore(tile) or not MineralMap.is_loot(tile):
				continue
			# Дойти: клетки 1..k-1 — копаем и проходим, потом руда, потом назад пешком.
			for j in range(1, k):
				_dig_cell(s, world, SHAFT_X + side * j, y, false)
			s["t"] += SIDE_TURN_S
			_dig_cell(s, world, x, y, false)
			s["t"] += 2.0 * float(k - 1) / 4.2
			break  # ближайшая руда в этом направлении — достаточно


# ---------------------------------------------------------------------------
# Механики раунда 3 (--mech=1): та же логика, что у MechDirector в игре
# ---------------------------------------------------------------------------

func _mech_dug(s: Dictionary, world: WorldGen, x: int, y: int, mid: String, loot: bool) -> void:
	var m: Dictionary = s["mech"]
	var price := Balance.get_mineral_price(mid) if mid != "" else 0
	if loot and MasteryLogic.is_kind(mid):
		var n := int(m["n"].get(mid, 0)) + 1
		m["n"][mid] = n
		var stars := MasteryLogic.stars_for(mid, n)
		while int(m["stars"].get(mid, 0)) < stars:
			m["stars"][mid] = int(m["stars"].get(mid, 0)) + 1
			s["xp"] += MasteryLogic.star_xp(mid, int(m["stars"][mid]))
		if (m["rng"] as RandomNumberGenerator).randf() < MasteryLogic.double_chance(int(m["stars"].get(mid, 0))):
			s["items"][mid] = int(s["items"].get(mid, 0)) + 1
			m["val"]["mastery"] += price
	var r: Dictionary = (m["streak"] as StreakLogic).on_dug(y)
	if bool(r["started"]):
		m["fevers"] += 1
	if bool(r["fever_cell"]) and loot and mid != "":
		var extra := int(_opt["fever_extra"]) if String(_opt["fever_extra"]) != "" \
			else int(MechData.num("streak", "fever_extra", 1))
		s["items"][mid] = int(s["items"].get(mid, 0)) + extra
		m["val"]["fever"] += price * extra
	var ch := _mech_chest(s, world, y)
	if not ch.is_empty() and ch["cell"] == Vector2i(x, y) and not m["opened"].has(ch["cell"]):
		_mech_open(s, world, ch)


func _mech_chest(s: Dictionary, world: WorldGen, y: int) -> Dictionary:
	var band := ChestLogic.band_of(y)
	var bands: Dictionary = s["mech"]["bands"]
	if not bands.has(band):
		bands[band] = ChestLogic.chest_in_band(world, int(s["seed"]), band)
	return bands[band]


func _mech_open(s: Dictionary, world: WorldGen, ch: Dictionary) -> void:
	var m: Dictionary = s["mech"]
	m["opened"][ch["cell"]] = true
	m["chests"] += 1
	var loot := ChestLogic.roll_loot(world, int(s["seed"]), ch["cell"], String(ch["tier"]))
	s["xp"] += int(loot["xp"])
	for id in loot["items"].keys():
		if String(id).begins_with("food_"):
			continue   # еда в симуляторе не учитывается (накладной расход на еду фиксирован)
		s["items"][id] = int(s["items"].get(id, 0)) + int(loot["items"][id])
		m["val"]["chest"] += Balance.get_mineral_price(String(id)) * int(loot["items"][id])


## Шахта: сундук в ряду героя виден, если он в радиусе обзора ресурсов (как руда в
## `_lateral_pick`); тогда герой прокапывает к нему ход и возвращается пешком.
func _mech_peek(s: Dictionary, world: WorldGen, y: int) -> void:
	var ch := _mech_chest(s, world, y)
	if ch.is_empty() or s["mech"]["opened"].has(ch["cell"]):
		return
	var c: Vector2i = ch["cell"]
	var r: int = Balance.get_vision_radius("vision", int(s["stages"].get("vision", 0)))
	var k: int = absi(c.x - SHAFT_X)
	if c.y != y or k == 0 or k > r:
		return
	var side: int = signi(c.x - SHAFT_X)
	for j in range(1, k):
		_dig_cell(s, world, SHAFT_X + side * j, y, false)
	s["t"] += SIDE_TURN_S
	_dig_cell(s, world, c.x, y, false)
	s["t"] += 2.0 * float(k - 1) / 4.2


func _depth_milestones(s: Dictionary) -> void:
	var d: int = s["depth"]
	while s["max_depth_milestone"] + 10 <= d:
		s["max_depth_milestone"] += 10
		s["xp"] += 50 * (int(s["max_depth_milestone"]) / 10)
	for mark in [25, 50, 100, 200, 300, 500]:
		if d >= mark and not s["mile"].has("глубина %d" % mark):
			s["mile"]["глубина %d" % mark] = s["t"]


func _level_up(s: Dictionary, order: Array) -> void:
	while int(s["xp"]) >= Balance.xp_required_for_level(int(s["level"])) and int(s["level"]) < 100:
		s["xp"] = int(s["xp"]) - Balance.xp_required_for_level(int(s["level"]))
		s["level"] += 1
		s["points"] += 1 + (2 if int(s["level"]) % 5 == 0 else 0)
		if not s["mile"].has("уровень %d" % int(s["level"])) and int(s["level"]) in [5, 10, 20]:
			s["mile"]["уровень %d" % int(s["level"])] = s["t"]
	var bought := true
	while bought:
		bought = false
		for branch: String in order:
			var st := int(s["stages"].get(branch, 0))
			var cost := Balance.get_upgrade_stage_cost(branch, st + 1)
			if cost > 0 and cost <= int(s["points"]):
				s["points"] -= cost
				s["stages"][branch] = st + 1
				bought = true
				break


# ---------------------------------------------------------------------------
# Подъём, продажа, покупки
# ---------------------------------------------------------------------------

func _trip(s: Dictionary, cap: float, needs: Dictionary, banking: bool) -> void:
	s["trips"] += 1
	if s.has("mech"):
		s["mech"]["streak"].reset()   # подъём на поверхность рвёт серию азарта
	var gear: String = s["gear"]
	var depth: float = float(s["depth"])
	var w := _weight(s)
	var fly := Balance.get_gear_max_speed(gear) if gear != "" else 0.0
	if fly <= 0.0:
		# Без ранца подняться нельзя: в игре это обязательный квест, добытчик берёт его первым.
		fly = Balance.get_gear_base_speed()
	var up_speed := fly * Balance.get_overload_speed_multiplier(w, cap)
	# Разгон — половина времени набора скорости в потерях (PROP_RAMP).
	var ramp := 1.5
	s["t"] += depth / up_speed + ramp + depth / fly + ramp + TRIP_OVERHEAD_S
	# Материалы под бур уходят на верстак (invest) до продажи остального.
	if banking:
		var per_bronze := int(Balance.unwrap(Balance.balance.get("crafting", {}).get("scrap_per_bronze", 1)))
		var want := {"iron_ore": int(needs.get("iron_ore", 0)), "silver": int(needs.get("silver", 0)),
			"scrap": int(needs.get("bronze", 0)) * per_bronze}
		for id: String in want.keys():
			var have := int(s["items"].get(id, 0))
			var room: int = maxi(0, int(want[id]) - int(s["bank"].get(id, 0)))
			var put := mini(have, room)
			if put > 0:
				s["bank"][id] = int(s["bank"].get(id, 0)) + put
				s["items"][id] = have - put
	for id in s["items"].keys():
		s["coins"] += Balance.get_mineral_price(String(id)) * int(s["items"][id])
		s["sold"] += Balance.get_mineral_price(String(id)) * int(s["items"][id])
	s["items"] = {}


func _has_pick(s: Dictionary, id: String) -> bool:
	return s["pickaxes"].has(id)


func _build_ladder() -> Array:
	# Кирки и ранцы — по возрастанию цены, внутри линии строго по порядку.
	var rows: Array = []
	for id in Balance.get_gear_ids():
		rows.append({"kind": "gear", "id": id, "cost": Balance.get_gear_cost_coins(id)})
	for id in Balance.get_tools_in_line("pickaxe"):
		if id == "rusty_pickaxe" or id == "shovel":
			continue
		rows.append({"kind": "tool", "id": id, "cost": Balance.get_tool_cost_coins(id)})
	rows.sort_custom(func(a, b): return a["cost"] < b["cost"])
	return rows


func _drill_needs() -> Dictionary:
	var cost: Dictionary = Balance.get_tool_cost("hand_drill")
	return cost


func _shop(s: Dictionary, ladder: Array, needs: Dictionary) -> void:
	var changed := true
	while changed:
		changed = false
		for row in ladder:
			var id: String = row["id"]
			if row["kind"] == "gear":
				if Balance.get_gear_fly_multiplier(id) <= Balance.get_gear_fly_multiplier(String(s["gear"])):
					continue
			else:
				if _has_pick(s, id):
					continue
			if int(row["cost"]) <= int(s["coins"]):
				s["coins"] -= int(row["cost"])
				if row["kind"] == "gear":
					s["gear"] = id
				else:
					s["pickaxes"].append(id)
					s["tool"] = id
				s["mile"][_ru(id)] = s["t"]
				changed = true
				break
			else:
				break  # следующая ступень по порядку цены ещё не по карману — копим на неё
	# Ручной бур: материалы на верстаке и монеты в кармане.
	var per_bronze := int(Balance.unwrap(Balance.balance.get("crafting", {}).get("scrap_per_bronze", 1)))
	var mats_ok: bool = int(s["bank"].get("iron_ore", 0)) >= int(needs.get("iron_ore", 0)) \
		and int(s["bank"].get("silver", 0)) >= int(needs.get("silver", 0)) \
		and int(s["bank"].get("scrap", 0)) >= int(needs.get("bronze", 0)) * per_bronze
	if mats_ok and not s["mile"].has("материалы бура собраны"):
		s["mile"]["материалы бура собраны"] = s["t"]
	if mats_ok and int(s["coins"]) >= int(needs.get("coins", 0)):
		s["coins"] -= int(needs.get("coins", 0))
		s["drill"] = true
		s["mile"]["Ручной бур"] = s["t"]


func _ru(id: String) -> String:
	if Balance.get_tool(id).is_empty():
		return Balance.get_gear_name_ru(id)
	return Balance.get_tool_name_ru(id)


# ---------------------------------------------------------------------------
# Отчёт
# ---------------------------------------------------------------------------

func _report(results: Array) -> void:
	print("=== sim_economy: политика %s, сидов %d, предел %.0f ч ===" % [_opt["policy"], results.size(), float(_opt["hours"])])
	var keys: Array = []
	for r in results:
		for k in r["mile"].keys():
			if not keys.has(k):
				keys.append(k)
	keys.sort_custom(func(a, b): return _avg(results, a) < _avg(results, b))
	print("%-28s %10s %10s %10s  %s" % ["ступень", "среднее", "мин", "макс", "достигли"])
	for k in keys:
		var vals: Array = []
		for r in results:
			if r["mile"].has(k):
				vals.append(float(r["mile"][k]))
		vals.sort()
		print("%-28s %10s %10s %10s  %d/%d" % [k, _fmt(_mean(vals)), _fmt(vals[0]), _fmt(vals[vals.size() - 1]), vals.size(), results.size()])
	var cells := 0.0
	var trips := 0.0
	for r in results:
		cells += float(r["cells"])
		trips += float(r["trips"])
	print("клеток за прогон в среднем: %.0f, подъёмов: %.0f" % [cells / results.size(), trips / results.size()])
	var art_coins := 0.0
	var art_n := 0.0
	var dollars := 0.0
	for r in results:
		art_coins += float(r["artifact_coins"])
		art_n += float(r["artifacts"].size())
		dollars += float(r["dollars"])
	print("артефакты: в среднем найдено %.1f, монет с них %.0f, премиума %.0f" % [
		art_n / results.size(), art_coins / results.size(), dollars / results.size()])
	var sold := 0.0
	var t_all := 0.0
	for r in results:
		sold += float(r["sold"])
		t_all += float(r["t"])
	print("продано руды: %.0f монет за прогон, %.0f монет в игровой час" % [sold / results.size(), sold / maxf(1.0, t_all / 3600.0)])
	if results[0].has("mech"):
		var v := {"chest": 0.0, "fever": 0.0, "mastery": 0.0}
		var chests := 0.0
		var fevers := 0.0
		var greed_cells := 0.0
		for r in results:
			for k in v.keys():
				v[k] += float(r["mech"]["val"][k])
			chests += float(r["mech"]["chests"])
			fevers += float(r["mech"]["fevers"])
			greed_cells += float(r["mech"].get("greed_cells", 0))
		var n := float(results.size())
		print("механики: сундуков %.1f, жадностей %.1f за прогон (клеток в жадности %.0f, %.1f на раз); добыча сверху (по прайсу): сундуки %.0f, жадность %.0f, мастерство %.0f — %.1f%% проданного" % [
			chests / n, fevers / n, greed_cells / n, greed_cells / maxf(1.0, fevers),
			v["chest"] / n, v["fever"] / n, v["mastery"] / n,
			(v["chest"] + v["fever"] + v["mastery"]) / maxf(1.0, sold) * 100.0])
	var r0: Dictionary = results[0]
	print("конец первого сида: глубина %d, монеты %d, на верстаке %s, прокачка %s, уровень %d, время %s" % [
		r0["depth"], r0["coins"], str(r0["bank"]), str(r0["stages"]), r0["level"], _fmt(float(r0["t"]))])
	var out_path: String = _opt["json"]
	if not out_path.is_empty():
		var rows: Array = []
		for r in results:
			rows.append({"mile": r["mile"], "cells": r["cells"], "trips": r["trips"], "depth": r["depth"]})
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"policy": _opt["policy"], "runs": rows}, "\t"))
		f.close()


func _avg(results: Array, key: String) -> float:
	var vals: Array = []
	for r in results:
		if r["mile"].has(key):
			vals.append(float(r["mile"][key]))
	return _mean(vals) if not vals.is_empty() else 1e18


static func _mean(vals: Array) -> float:
	var sum := 0.0
	for v in vals:
		sum += float(v)
	return sum / maxf(1.0, float(vals.size()))


static func _fmt(seconds: float) -> String:
	if seconds >= 7200.0:
		return "%.1f ч" % (seconds / 3600.0)
	return "%.0f мин" % (seconds / 60.0)

extends Node
## Аудит достижимости прогресса (ветка qa2): для КАЖДОЙ покупки, рецепта и ступени
## в данных проверяет на настоящем WorldGen/Balance, что нужное можно добыть.
##
##   godot --headless --path . res://tools/audit_progression.tscn
##   godot --headless --path . res://tools/audit_progression.tscn -- --verbose --json=/tmp/audit.json
##
## Проверяется (подробности и причины — docs/GDD.md §19, «Аудит достижимости»):
##  * материал есть в minerals.json, у него есть ИСТОЧНИК — руда в мире (ненулевая плотность на
##    реально проверенных клетках), добыча с монстра или плавка — и этот источник не дальше
##    десяти тысяч метров;
##  * материал начинается не слишком глубоко под рубежом, на котором рецепт открывается
##    (разрыв), и клеток породы на нужное количество не безумно много;
##  * материал берётся инструментом, который к этой глубине уже можно получить;
##  * соседние ступени одной лестницы (бак, костюм, скважина, снаряжение) не отличаются
##    по цене в монетах или в породе больше чем в десять раз;
##  * достижения и задания ссылаются на существующую добычу и достижимые числа;
##  * топливо самоокупается на всех глубинах, лаву можно обойти/пройти на каждой ступени костюма.
## Ничего не пишет на диск (кроме --json). Логика отчёта — в run(), тест — tests/test_progression_audit.gd.

const MAX_DEPTH := 10000
const STEP := 1
## Доля клеток, начиная с которой руду уже «ищут»: 1 на 250 клеток породы.
const WORKABLE := 0.004
## Окно копки от рубежа: на какой глубине считаем среднюю плотность.
const BAND := 600
const GAP_WARN := 1500
const CELLS_WARN := 6000.0
const CELLS_ERROR := 30000.0
const RATIO_MAX := 10.0
const SEEDS := [11, 4242, 777001]
const STRIP_ROWS := 12
const STRIP_EVERY := 250

## ступень инструмента, которым берётся минерал
const TOOL_TIER := {"shovel": 0, "pickaxe": 1, "hand_drill": 2, "drill_rig": 3}

var findings: Array = []     # {level: error|warn|info, where, text}
var rows: Array = []         # строки таблицы требований
var ladders: Array = []      # {name, steps: [{label, coins, cells}]}
var verbose := false
var lava_seed_count := 3     # тест берёт один сид: обход лавы дорогой

var _world: WorldGen
var _dens: Dictionary = {}   # id -> PackedFloat32Array по глубине 0..MAX_DEPTH
var _measured: Dictionary = {}   # id -> {strips: n, formula: x, real: y}
var _drops: Dictionary = {}  # id -> [{monster, chance, avg, lo, hi, weight}]


func _ready() -> void:
	# Тест подключает аудит дочерним узлом и сам зовёт run(); печатать и выходить должна только сцена-запускатель.
	if get_tree().current_scene != self:
		return
	for a in OS.get_cmdline_user_args():
		if a == "--verbose":
			verbose = true
	var json_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			json_path = a.substr(7)
	run()
	print_report()
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"findings": findings, "rows": rows, "ladders": ladders}, "\t"))
	var errs := count_level("error")
	print("=== Итог аудита: ошибок %d, предупреждений %d ===" % [errs, count_level("warn")])
	get_tree().quit(1 if errs > 0 else 0)


func count_level(level: String) -> int:
	var n := 0
	for f in findings:
		if f["level"] == level:
			n += 1
	return n


func add(level: String, where: String, text: String) -> void:
	findings.append({"level": level, "where": where, "text": text})


func run() -> void:
	findings.clear()
	rows.clear()
	ladders.clear()
	_world = WorldGen.new(SEEDS[0])
	var steps: Array = [_build_density_profile, _index_drops, _check_minerals_consistency, _measure_real_generation,
		_check_requirements, _check_combat_data, _check_ladders, _check_meta, _check_fuel_selfsufficiency, _check_heat, _check_lava_passable]
	for step: Callable in steps:
		var t0 := Time.get_ticks_msec()
		step.call()
		if verbose:
			print("[аудит] %s: %d мс" % [step.get_method(), Time.get_ticks_msec() - t0])


# ---------------------------------------------------------------------------
# Профиль плотности руд (по формуле генератора) и добыча с монстров
# ---------------------------------------------------------------------------

func _build_density_profile() -> void:
	_dens.clear()
	for y in range(1, MAX_DEPTH + 1, STEP):
		for e in _world.ore_densities_at(y):
			var id := String(e["id"])
			if not _dens.has(id):
				var arr := PackedFloat32Array()
				arr.resize(MAX_DEPTH + 1)
				_dens[id] = arr
			_dens[id][y] = float(e["density"])


func density(id: String, y: int) -> float:
	var arr: PackedFloat32Array = _dens.get(id, PackedFloat32Array())
	if arr.is_empty() or y < 0 or y > MAX_DEPTH:
		return 0.0
	return arr[y]


func _index_drops() -> void:
	_drops.clear()
	for mid in CombatData.monster_ids():
		var m := CombatData.monster(String(mid))
		var d: Array = m.get("depth", [0, 0])
		for dr in m.get("drops", []):
			var id := String(dr.get("id", ""))
			var avg := 0.5 * (float(dr.get("min", 1)) + float(dr.get("max", 1)))
			if not _drops.has(id):
				_drops[id] = []
			_drops[id].append({"monster": String(mid), "chance": float(dr.get("chance", 0.0)), "avg": avg,
				"lo": int(d[0]), "hi": int(d[1]), "weight": float(m.get("weight", 1.0))})
	var boss: Dictionary = CombatData.section("boss")
	for id in boss.get("rewards", {}).get("materials", {}).keys():
		if not _drops.has(String(id)):
			_drops[String(id)] = []
		_drops[String(id)].append({"monster": "BOSS", "chance": 1.0, "avg": float(boss["rewards"]["materials"][id]),
			"lo": MAX_DEPTH, "hi": MAX_DEPTH, "weight": 0.0})


## Первая глубина ≥ from, где плотность руды достигает WORKABLE; -1 — такой нет.
func work_depth(id: String, from: int) -> int:
	for y in range(maxi(from, 1), MAX_DEPTH + 1):
		if density(id, y) >= WORKABLE:
			return y
	return -1


func avg_density(id: String, y0: int, rows_n: int = BAND) -> float:
	var s := 0.0
	var n := 0
	for y in range(y0, mini(y0 + rows_n, MAX_DEPTH) + 1):
		s += density(id, y)
		n += 1
	return s / float(maxi(n, 1))


# ---------------------------------------------------------------------------
# Согласованность minerals.json и world_layers.json
# ---------------------------------------------------------------------------

func _check_minerals_consistency() -> void:
	var ids: Array = []
	for m in Balance.minerals.get("minerals", []):
		var id := String(m["id"])
		ids.append(id)
		var where := "minerals.json/" + id
		var sellable: bool = bool(m.get("sellable", true))
		var price = Balance.unwrap(m.get("price_coins", null))
		var tile0 := MineralMap.tile_type_for(id)
		var is_item := tile0 < 0 or MineralMap.is_loot(tile0)
		if is_item and sellable and (price == null or int(price) <= 0):
			add("warn", where, "помечен как продаваемый, но цены нет")
		if not sellable and price != null and int(price) > 0:
			add("warn", where, "помечен «не продаётся», но цена %d задана" % int(price))
		var in_world := _dens.has(id)
		var in_drops := _drops.has(id)
		var tile := MineralMap.tile_type_for(id)
		if in_world and tile < 0:
			add("error", where, "руда есть в слоях мира, а плитки у неё нет (MineralMap): в мире её не будет")
		if in_world:
			var dmin = Balance.unwrap(m.get("depth_min", null))
			var first := work_depth(id, 1)
			if dmin != null and first >= 0 and int(dmin) > 0 and absi(int(dmin) - _first_nonzero(id)) > 5:
				add("warn", where, "depth_min=%d, а в слоях мира руда начинается с %d" % [int(dmin), _first_nonzero(id)])


func _first_nonzero(id: String) -> int:
	for y in range(1, MAX_DEPTH + 1):
		if density(id, y) > 0.0:
			return y
	return -1


## Реальные клетки: полосы по 12 рядов через каждые 250, три сида. Сверяем с формулой, чтобы
## поймать «в слоях есть, а в мире нет» (формации, лава, события затирают руду).
func _measure_real_generation() -> void:
	_measured.clear()
	var counts: Dictionary = {}
	var total := 0
	var exp: Dictionary = {}
	for seed_value in SEEDS:
		var w := WorldGen.new(int(seed_value))
		for y0 in range(20, MAX_DEPTH, STRIP_EVERY):
			for y in range(y0, y0 + STRIP_ROWS):
				for x in range(WorldGen.WIDTH):
					var id := MineralMap.mineral_id_for(w.get_tile(x, y))
					total += 1
					if id != "":
						counts[id] = int(counts.get(id, 0)) + 1
				for id in _dens.keys():
					exp[id] = float(exp.get(id, 0.0)) + density(id, y) * WorldGen.WIDTH
	for id in _dens.keys():
		var real := float(counts.get(id, 0))
		var want := float(exp.get(id, 0.0))
		_measured[id] = {"real": real, "formula": want}
		if verbose:
			print("[аудит] мир/%s: формула %.0f, реально %.0f (×%.2f)" % [id, want, real, real / maxf(want, 0.001)])
		if want >= 30.0:
			if real < want * 0.35:
				add("error", "world/" + id, "по формуле на проверенных полосах ждали %.0f клеток, в мире нашли %.0f — руду затирает другая генерация" % [want, real])
			elif real > want * 3.0:
				add("info", "world/" + id, "в мире клеток втрое больше формулы (%.0f против %.0f): образования добавляют руду сверх слоёв" % [real, want])
		elif want > 0.0 and verbose:
			add("info", "world/" + id, "мало клеток для сверки: формула %.1f, мир %.0f" % [want, real])


# ---------------------------------------------------------------------------
# Требования рецептов и покупок
# ---------------------------------------------------------------------------

## Все требования: {owner, item, n, gate, tool_cap}. gate — глубина, на которой покупка открыта.
func collect_requirements() -> Array:
	var out: Array = []
	var per_bronze := maxi(1, int(Balance.unwrap(Balance.balance.get("crafting", {}).get("scrap_per_bronze", 1))))
	for r in ShopCatalog.recipes():
		var owner := "recipe:" + String(r["id"])
		var gate := int(r.get("unlock_depth", 0))
		var cap := 1 if String(r["id"]) == "hand_drill" else (2 if String(r["id"]) == "drill_rig" else _tool_tier_at(gate))
		for item in r["inputs"].keys():
			out.append({"owner": owner, "item": String(item), "n": int(r["inputs"][item]), "gate": gate, "cap": cap})
	# баки
	var tanks: Dictionary = TechData.fuel().get("tanks", {})
	for tool_id in tanks.keys():
		var costs: Array = TechData.v(tanks[tool_id].get("upgrade_cost", []))
		var gate := ShopCatalog.unlock_depth(String(tool_id))
		for i in range(costs.size()):
			for item in costs[i].get("items", {}).keys():
				out.append({"owner": "tank:%s:%d" % [tool_id, i + 1], "item": String(item), "n": int(costs[i]["items"][item]),
					"gate": gate, "cap": _tool_tier_at(gate)})
	# костюм
	for row in Heat.suit_tiers():
		for item in row.get("cost", {}).get("items", {}).keys():
			out.append({"owner": "suit:" + String(row["id"]), "item": String(item), "n": int(row["cost"]["items"][item]),
				"gate": int(row.get("unlock_depth", 0)), "cap": _tool_tier_at(int(row.get("unlock_depth", 0)))})
	# скважина: ступень покупают тем, кто дошёл до глубины прежней ступени
	var levels: Array = TechData.v(TechData.well().get("levels", []))
	for i in range(1, levels.size()):
		var gate := int(levels[i - 1].get("depth_cap", 0))
		var cost = levels[i].get("cost", null)
		if cost == null:
			continue
		for item in cost.get("items", {}).keys():
			out.append({"owner": "well:%d" % i, "item": String(item), "n": int(cost["items"][item]), "gate": gate, "cap": _tool_tier_at(gate)})
	# снаряжение боя: открыто с глубины боя
	var war := CombatData.start_depth()
	for gid in CombatData.craftable_ids():
		var inputs: Dictionary = CombatData.recipe(gid).get("inputs", {})
		for item in inputs.keys():
			out.append({"owner": "gear:" + gid, "item": String(item), "n": int(inputs[item]), "gate": war, "cap": 3})
	var socket_cfg: Dictionary = CombatData.section("sockets")
	for s in socket_cfg.get("slots", []):
		out.append({"owner": "socket:" + String(s["id"]), "item": String(s["id"]), "n": int(socket_cfg.get("cost_each", 3)),
			"gate": war, "cap": 3})
	for e in out:
		if e["item"] == "bronze":
			e["item"] = "scrap"
			e["n"] = int(e["n"]) * per_bronze
	return out


func _tool_tier_at(gate: int) -> int:
	if gate >= ShopCatalog.unlock_depth("drill_rig"):
		return 3
	if gate >= ShopCatalog.unlock_depth("hand_drill"):
		return 2
	return 1


func _mineral_tool_tier(id: String) -> int:
	var raw = Balance.unwrap(Balance.get_mineral(id).get("tool_required", "pickaxe"))
	if typeof(raw) != TYPE_STRING:
		return 1
	return int(TOOL_TIER.get(raw, 1))


## Оценка добычи одного материала на рубеже gate: {source, start, gap, cells, kills}.
func evaluate(id: String, n: int, gate: int) -> Dictionary:
	var res := {"id": id, "n": n, "gate": gate, "source": "none", "start": -1, "gap": 0, "cells": 0.0, "kills": 0.0}
	if _dens.has(id):
		var s := work_depth(id, gate)
		if s >= 0:
			var dens := avg_density(id, s)
			res["source"] = "world"
			res["start"] = s
			res["gap"] = s - gate
			res["cells"] = float(n) / maxf(dens, 1e-6)
	if _drops.has(id):
		var best := -1.0
		for d in _drops[id]:
			if d["monster"] == "BOSS":
				continue
			var k := float(n) / maxf(float(d["chance"]) * float(d["avg"]), 1e-6)
			if best < 0.0 or k < best:
				best = k
				res["drop_lo"] = d["lo"]
		if best >= 0.0:
			res["kills"] = best
			if res["source"] == "none":
				res["source"] = "drop"
				res["start"] = maxi(gate, int(res.get("drop_lo", gate)))
				res["gap"] = int(res["start"]) - gate
		elif res["source"] == "none":
			res["source"] = "boss"
			res["start"] = MAX_DEPTH
			res["gap"] = MAX_DEPTH - gate
	if res["source"] == "none" and id == "fuel_block":
		res["source"] = "craft"
		res["start"] = gate
	return res


func _check_requirements() -> void:
	for req in collect_requirements():
		var id: String = req["item"]
		var where := "%s ← %s×%d" % [req["owner"], id, req["n"]]
		var mineral := Balance.get_mineral(id)
		if mineral.is_empty() and not CombatData.section("materials").has(id):
			add("error", where, "материала %s нет в minerals.json" % id)
			continue
		var ev := evaluate(id, int(req["n"]), int(req["gate"]))
		ev["owner"] = req["owner"]
		rows.append(ev)
		if ev["source"] == "none":
			add("error", where, "недостижимо: у материала нет источника на глубинах ≥ %d (ни руды, ни дропа)" % int(req["gate"]))
			continue
		var combat_owner := String(req["owner"]).begins_with("gear:") or String(req["owner"]).begins_with("socket:")
		if int(ev["gap"]) > GAP_WARN and not combat_owner:
			add("warn", where, "рецепт открыт с %d, а материал начинается с %d (разрыв %d)" % [int(req["gate"]), int(ev["start"]), int(ev["gap"])])
		if ev["source"] == "world":
			var cells := float(ev["cells"])
			if cells > CELLS_ERROR:
				add("error", where, "нужно перекопать ~%.0f клеток породы (> %.0f): безумно много" % [cells, CELLS_ERROR])
			elif cells > CELLS_WARN:
				add("warn", where, "нужно перекопать ~%.0f клеток породы" % cells)
		var tier := _mineral_tool_tier(id)
		if ev["source"] == "world" and tier > int(req["cap"]):
			add("warn", where, "минерал помечен как «%s» (ступень %d), а рецепт доступен с инструментом ступени %d" % [
				str(Balance.unwrap(mineral.get("tool_required", "?"))), tier, int(req["cap"])])
		if ev["source"] == "world" and not _sellable_or_gear(mineral) and not _is_recipe_only(mineral):
			add("info", where, "материал не продаётся и не копается за деньги")


func _sellable_or_gear(m: Dictionary) -> bool:
	return bool(m.get("sellable", true))


func _is_recipe_only(_m: Dictionary) -> bool:
	return true


# ---------------------------------------------------------------------------
# Данные боя: ссылки целы, цепочка материалов идёт вглубь
# ---------------------------------------------------------------------------

func _check_combat_data() -> void:
	var war := CombatData.start_depth()
	for mid in CombatData.monster_ids():
		var m := CombatData.monster(String(mid))
		var where := "монстр " + String(mid)
		var d: Array = m.get("depth", [0, 0])
		if int(d[0]) < war or int(d[1]) > MAX_DEPTH or int(d[0]) >= int(d[1]):
			add("error", where, "глубины %s вне [%d, %d]" % [str(d), war, MAX_DEPTH])
		if float(m.get("weight", 0.0)) <= 0.0:
			add("error", where, "вес появления не положителен: монстр не появится")
		for dr in m.get("drops", []):
			var id := String(dr.get("id", ""))
			if Balance.get_mineral(id).is_empty():
				add("error", where, "дроп «%s» не описан в minerals.json" % id)
			if float(dr.get("chance", 0.0)) <= 0.0:
				add("error", where, "дроп «%s» с нулевым шансом" % id)
	# в каждой глубине боя должен быть хоть один монстр
	for y in range(war, MAX_DEPTH + 1, 50):
		var any := false
		for mid in CombatData.monster_ids():
			var d: Array = CombatData.monster(String(mid)).get("depth", [0, 0])
			if y >= int(d[0]) and y <= int(d[1]):
				any = true
		if not any:
			add("error", "бой", "на глубине %d нет ни одного монстра" % y)
			break
	# снаряжение: рецепты, наборы, сокеты, награда босса
	var sets: Dictionary = CombatData.section("sets")
	for set_id in sets.keys():
		for piece in sets[set_id].get("pieces", []):
			if not CombatData.has_gear(String(piece)):
				add("error", "набор " + String(set_id), "нет предмета «%s»" % piece)
	for gid in CombatData.gear_ids():
		var g := CombatData.gear(String(gid))
		if g.has("artifact") and Balance.get_artifact(String(g["artifact"])).is_empty():
			add("error", "снаряжение " + String(gid), "артефакт «%s» не описан в artifacts.json" % g["artifact"])
		if not g.has("recipe") and not g.has("artifact") and not g.has("trophy"):
			add("error", "снаряжение " + String(gid), "нечем получить: ни рецепта, ни артефакта, ни трофея")
	for gid in CombatData.section("boss").get("rewards", {}).get("gear", []):
		if not CombatData.has_gear(String(gid)):
			add("error", "босс", "награда «%s» не описана" % gid)
	var arena: Dictionary = CombatData.section("boss").get("arena", {})
	if int(arena.get("floor_y", 0)) > MAX_DEPTH:
		add("error", "босс", "дно арены %d глубже мира %d" % [int(arena.get("floor_y", 0)), MAX_DEPTH])
	# материалы одной ступени снаряжения лежат рядом по глубине (иначе ступень собирают вдвое дольше)
	for gid in CombatData.craftable_ids():
		var lo := MAX_DEPTH
		var hi := 0
		for item in CombatData.recipe(String(gid)).get("inputs", {}).keys():
			var ev := evaluate(String(item), 1, CombatData.start_depth())
			if ev["source"] == "boss" or ev["source"] == "none":
				continue
			lo = mini(lo, int(ev["start"]))
			hi = maxi(hi, int(ev["start"]))
		if hi - lo > GAP_WARN:
			add("warn", "снаряжение " + String(gid), "материалы рецепта начинаются на глубинах %d и %d (разница > %d)" % [lo, hi, GAP_WARN])
	# ступень предмета: следующая ступень открывается глубже (хоть одним материалом)
	var prev_start := 0
	for t in range(1, 6):
		var start := MAX_DEPTH
		for gid in CombatData.craftable_ids():
			if int(CombatData.gear(String(gid)).get("tier", 0)) != t:
				continue
			for item in CombatData.recipe(String(gid)).get("inputs", {}).keys():
				var ev := evaluate(String(item), 1, CombatData.start_depth())
				if ev["source"] == "world":
					start = mini(start, int(ev["start"]))
		if start < prev_start:
			add("warn", "бой", "ступень %d открывается мировой рудой с %d — раньше предыдущей (%d)" % [t, start, prev_start])
		if start < MAX_DEPTH:
			prev_start = start
	# инструмент с потолком глубины не должен требовать материал глубже потолка для собственного бака
	for tool_id in ["hand_drill"]:
		var cap := Balance.get_tool_max_depth(tool_id)
		if cap <= 0:
			continue
		var costs: Array = TechData.v(TechData.fuel().get("tanks", {}).get(tool_id, {}).get("upgrade_cost", []))
		for i in range(costs.size()):
			for item in costs[i].get("items", {}).keys():
				var ev := evaluate(String(item), int(costs[i]["items"][item]), ShopCatalog.unlock_depth(tool_id))
				if ev["source"] == "world" and int(ev["start"]) > cap:
					add("warn", "бак %s L%d" % [tool_id, i + 1], "требует %s, который начинается с %d, а у инструмента потолок глубины %d (ГДД §5)" % [item, int(ev["start"]), cap])


# ---------------------------------------------------------------------------
# Лестницы: соседние ступени не дальше чем в 10 раз
# ---------------------------------------------------------------------------

func _step_cells(items: Dictionary, gate: int) -> float:
	var total := 0.0
	for item in items.keys():
		var id := String(item)
		if id == "bronze":
			id = "scrap"
		var ev := evaluate(id, int(items[item]), gate)
		if ev["source"] == "world":
			total += float(ev["cells"])
		elif ev["source"] == "drop" or ev["source"] == "boss":
			# убийство монстра ~ 25 клеток породы по времени: оценка порядка, а не точное число
			total += float(ev["kills"]) * 25.0
	return total


func _push_ladder(lname: String, steps: Array) -> void:
	ladders.append({"name": lname, "steps": steps})
	for i in range(1, steps.size()):
		var a: Dictionary = steps[i - 1]
		var b: Dictionary = steps[i]
		for key in ["coins", "cells"]:
			var va := float(a[key])
			var vb := float(b[key])
			if va <= 0.0 or vb <= 0.0:
				continue
			var ratio := maxf(va, vb) / minf(va, vb)
			if ratio > RATIO_MAX:
				add("warn", "лестница " + lname, "%s → %s: %s отличается в %.1f раза (%.0f → %.0f)" % [
					a["label"], b["label"], "цена в монетах" if key == "coins" else "порода (клеток)", ratio, va, vb])


func _check_ladders() -> void:
	var picks: Array = []
	for id in Balance.get_tools_in_line("pickaxe"):
		picks.append({"label": String(id), "coins": Balance.get_tool_cost_coins(String(id)), "cells": 0.0})
	_push_ladder("кирки", picks.filter(func(s): return s["coins"] > 0))
	var gear: Array = []
	for id in Balance.get_gear_ids():
		gear.append({"label": String(id), "coins": Balance.get_gear_cost_coins(String(id)), "cells": 0.0})
	_push_ladder("ранцы", gear)
	var rig_up: Array = []
	for t in range(1, Balance.get_drill_rig_tier_count() + 1):
		rig_up.append({"label": Balance.get_drill_rig_tier_id(t), "coins": Balance.get_drill_rig_tier_cost_coins(t), "cells": 0.0})
	_push_ladder("бур бурмобиля", rig_up)

	var tanks: Dictionary = TechData.fuel().get("tanks", {})
	for tool_id in tanks.keys():
		var costs: Array = TechData.v(tanks[tool_id].get("upgrade_cost", []))
		var steps: Array = []
		var gate := ShopCatalog.unlock_depth(String(tool_id))
		for i in range(costs.size()):
			steps.append({"label": "бак %s L%d" % [tool_id, i + 1], "coins": float(costs[i].get("coins", 0)),
				"cells": _step_cells(costs[i].get("items", {}), gate)})
		_push_ladder("бак " + String(tool_id), steps)
		var caps: Array = TechData.v(tanks[tool_id].get("capacity_blocks", []))
		for i in range(1, caps.size()):
			if float(caps[i]) <= float(caps[i - 1]):
				add("error", "бак " + String(tool_id), "ёмкость не растёт: %s" % str(caps))

	var suits: Array = []
	for row in Heat.suit_tiers():
		suits.append({"label": String(row["id"]), "coins": float(row["cost"].get("coins", 0)),
			"cells": _step_cells(row["cost"].get("items", {}), int(row.get("unlock_depth", 0)))})
	_push_ladder("костюм жары", suits)

	var levels: Array = TechData.v(TechData.well().get("levels", []))
	var wsteps: Array = []
	for i in range(1, levels.size()):
		var cost: Dictionary = levels[i].get("cost", {})
		wsteps.append({"label": "скважина L%d" % (i + 1), "coins": float(cost.get("coins", 0)),
			"cells": _step_cells(cost.get("items", {}), int(levels[i - 1].get("depth_cap", 0)))})
		if int(levels[i].get("depth_cap", 0)) <= int(levels[i - 1].get("depth_cap", 0)):
			add("error", "скважина", "глубина ступени %d не растёт" % (i + 1))
		if float(levels[i].get("cells_per_hour", 0)) < float(levels[i - 1].get("cells_per_hour", 0)):
			add("error", "скважина", "доход ступени %d падает" % (i + 1))
	_push_ladder("скважина", wsteps)

	# снаряжение боя: по слотам, ступени 1..5 (+ клинок бездны отдельной ступенью)
	for slot_kind in ["helm", "armor", "blade", "shield", "charm"]:
		var steps: Array = []
		for t in range(1, 6):
			var gid := "%s_t%d" % [slot_kind, t]
			if not CombatData.has_gear(gid):
				continue
			var r := CombatData.recipe(gid)
			steps.append({"label": gid, "coins": float(r.get("coins", 0)),
				"cells": _step_cells(r.get("inputs", {}), CombatData.start_depth())})
		_push_ladder("бой: " + slot_kind, steps)


# ---------------------------------------------------------------------------
# Достижения и задания
# ---------------------------------------------------------------------------

func _check_meta() -> void:
	var artifacts_n: int = Balance.artifacts.get("artifacts", []).size()
	var kinds_max := 0
	for m in Balance.minerals.get("minerals", []):
		var id := String(m["id"])
		if Achievements.is_kind(id) and (_dens.has(id) or _drops.has(id)):
			kinds_max += 1
	for a in MetaData.achievements():
		var id := String(a["id"])
		var counter := String(a["counter"])
		var target := int(a["target"])
		var where := "достижение " + id
		if counter.begins_with("m:"):
			var mid := counter.substr(2)
			if Balance.get_mineral(mid).is_empty():
				add("error", where, "добыча «%s» не существует" % mid)
				continue
			var ev := evaluate(mid, target, 1)
			if ev["source"] == "none" or ev["source"] == "craft":
				add("error", where, "добыча «%s» нигде не добывается" % mid)
			elif ev["source"] == "world" and float(ev["cells"]) > CELLS_ERROR:
				add("warn", where, "%d × %s ≈ %.0f клеток породы" % [target, mid, float(ev["cells"])])
		match counter:
			"max_depth":
				if target > MAX_DEPTH:
					add("error", where, "глубина %d глубже мира (%d)" % [target, MAX_DEPTH])
			"level":
				if target > 100:
					add("error", where, "уровень %d выше потолка 100" % target)
			"artifacts":
				if target > artifacts_n:
					add("error", where, "артефактов %d, а в игре %d" % [target, artifacts_n])
			"branches":
				if target > 5:
					add("error", where, "веток %d, а их 5" % target)
			"kinds":
				if target > kinds_max:
					add("error", where, "видов добычи %d, а доступных %d" % [target, kinds_max])
	_check_quests()


func _check_quests() -> void:
	var q: Dictionary = MetaData.quests()
	var tier_depth: Array = q.get("tier_by_max_depth", [0])
	var dig_any: Dictionary = MetaData.template("dig_any")
	for t in q.get("templates", []):
		var tid := String(t.get("id", ""))
		var where := "задание " + tid
		var f: Dictionary = t.get("filter", {})
		var targets: Array = t.get("targets", [])
		var min_tier := int(t.get("min_tier", 0))
		var max_tier := mini(int(t.get("max_tier", targets.size() - 1)), targets.size() - 1)
		if targets.size() < tier_depth.size():
			add("error", where, "целей %d, а ступеней игрока %d" % [targets.size(), tier_depth.size()])
		if not f.has("item"):
			continue
		var items: Array = f["item"] if f["item"] is Array else [f["item"]]
		for item in items:
			if Balance.get_mineral(String(item)).is_empty():
				add("error", where, "добыча «%s» не существует" % item)
				continue
			if not _dens.has(String(item)) and not _drops.has(String(item)):
				add("error", where, "добыча «%s» нигде не добывается" % item)
				continue
			for kind in ["daily", "weekly"]:
				if not (t.get("kinds", []) as Array).has(kind):
					continue
				var cfg: Dictionary = q[kind]
				for tier in range(min_tier, max_tier + 1):
					var depth := int(tier_depth[mini(tier, tier_depth.size() - 1)])
					for si in range(cfg["slots"].size()):
						var mine: Dictionary = QuestGen._make(kind, 0, si, t, cfg["slots"][si], cfg, tier, depth)
						var base: Dictionary = QuestGen._make(kind, 0, si, dig_any, cfg["slots"][si], cfg, tier, depth)
						var cells := float(mine["target"]) / maxf(avg_density(String(item), maxi(depth, 1)), 1e-6)
						var ratio := cells / maxf(float(base["target"]), 1.0)
						if cells > CELLS_ERROR or ratio > RATIO_MAX * 3.0:
							add("warn", where, "%s, ступень %d, слот %d: %d × %s ≈ %.0f клеток породы (в %.0f раз больше цели «выкопай» — %d)" % [
								kind, tier, si, int(mine["target"]), item, cells, ratio, int(base["target"])])


# ---------------------------------------------------------------------------
# Топливо, жара, лава
# ---------------------------------------------------------------------------

## Блоков топлива на копаемую клетку из самой породы на глубине y (уголь и торф вместе).
func fuel_yield_per_cell(y: int) -> float:
	var coal_per := float(Balance.unwrap(Balance.balance["fuel_consumption"]["coal_per_fuel_block"]))
	var peat_per := float(Balance.balance["fuel_consumption"]["peat_per_fuel_block"])
	return density("coal", y) / coal_per + density("peat", y) / peat_per


func _check_fuel_selfsufficiency() -> void:
	# Топливо не должно быть основным занятием (ГДД п.5): доля копки на топливо ≤ ~50%.
	for tool_id in ["hand_drill", "drill_rig"]:
		var rate := FuelTank.rate_per_cell(tool_id)
		var from := ShopCatalog.unlock_depth(tool_id)
		var worst := 1e9
		var worst_y := from
		var y := from
		while y <= MAX_DEPTH - 100:
			var yield_per_cell := 0.0
			for yy in range(y, mini(y + 100, MAX_DEPTH)):
				yield_per_cell += fuel_yield_per_cell(yy) / 100.0
			var ratio := yield_per_cell / maxf(rate, 1e-9)
			if ratio < worst:
				worst = ratio
				worst_y = y
			y += 100
		if worst < 0.35:
			add("warn", "топливо " + tool_id, "на глубине ~%d из породы выходит лишь %.0f%% расхода: топливо — основное занятие" % [worst_y, worst * 100.0])
		elif verbose:
			add("info", "топливо " + tool_id, "худший запас топлива из породы — %.0f%% расхода на глубине ~%d" % [worst * 100.0, worst_y])
		if FuelTank.capacities(tool_id).is_empty() or float(FuelTank.capacities(tool_id)[0]) / maxf(rate, 1e-9) < 20.0:
			add("warn", "топливо " + tool_id, "бак 1-го уровня хватает меньше чем на 20 клеток")
	# Блок из торфа/угля: рецепт должен быть доступен там, где нужен
	var bf := ShopCatalog.recipe("fuel_block_coal")
	if bf.is_empty() or int(bf.get("unlock_depth", 0)) > 1000:
		add("error", "топливо", "рецепт блока из угля не открыт к глубине угля")
	var coal_first := work_depth("coal", 1)
	if coal_first < 0 or coal_first > int(bf.get("unlock_depth", 0)) + 50:
		add("warn", "топливо", "уголь (рабочая плотность) начинается с %d, рецепт блока — с %d" % [coal_first, int(bf.get("unlock_depth", 0))])
	if work_depth("peat", 1) < 0:
		add("error", "топливо", "торфа в мире нет")


func _check_heat() -> void:
	# На каждой глубине лучший доступный по unlock_depth костюм не должен перегонять расход бодрости выше потолка.
	var rows_heat: Array = Heat.suit_tiers()
	var worst := 0.0
	var worst_y := 0
	for y in range(0, MAX_DEPTH + 1, 100):
		var best_tier := 0
		for i in range(rows_heat.size()):
			if int(rows_heat[i].get("unlock_depth", 0)) <= y:
				best_tier = i + 1
		var m := Heat.stamina_multiplier(float(y), best_tier)
		if m > worst:
			worst = m
			worst_y = y
	if worst > 3.0:
		add("warn", "жара", "с лучшим доступным костюмом расход бодрости на глубине %d ×%.1f" % [worst_y, worst])
	var unlocks: Array = []
	for r in rows_heat:
		unlocks.append(int(r.get("unlock_depth", 0)))
	for i in range(1, unlocks.size()):
		if unlocks[i] < unlocks[i - 1]:
			add("error", "жара", "глубины открытия костюмов идут не по возрастанию: %s" % str(unlocks))
	if not rows_heat.is_empty() and Heat.lava_resist(rows_heat.size()) < 1.0:
		add("warn", "лава", "последний костюм не делает лаву проходимой (стойкость %.2f)" % Heat.lava_resist(rows_heat.size()))


## Сетка лавы сида на строках [y_from, y_to]: 1 — лава. Считается один раз на сид: LavaField.is_lava
## дорог (9 соседних озёр на вызов), а обход ходит по клетке по нескольку раз.
func lava_grid(world_seed: int, y_from: int, y_to: int) -> PackedByteArray:
	var g := PackedByteArray()
	g.resize((y_to - y_from + 1) * WorldGen.WIDTH)
	for y in range(y_from, y_to + 1):
		for x in range(WorldGen.WIDTH):
			g[(y - y_from) * WorldGen.WIDTH + x] = 1 if LavaField.is_lava(world_seed, x, y) else 0
	return g


## Глубина, до которой герой доберётся от лавового рубежа, если ему можно пройти подряд
## не больше k клеток лавы (дальше он остановится: HP не хватит). Лава всегда обходится по
## любым клеткам, кроме неё самой: всё остальное в шахте копается киркой.
func lava_reach(grid: PackedByteArray, k: int, y_from: int) -> int:
	var w := WorldGen.WIDTH
	var rows_n := grid.size() / w
	var best := PackedByteArray()
	best.resize(rows_n * w)
	best.fill(255)
	var stack: Array = []
	for x in range(w):
		best[x] = 0 if grid[x] == 0 else 1
		if best[x] <= k:
			stack.append(Vector3i(x, 0, best[x]))
	var deepest := 0
	while not stack.is_empty():
		var s: Vector3i = stack.pop_back()
		if s.z > best[s.y * w + s.x]:
			continue
		deepest = maxi(deepest, s.y)
		for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
			var nx: int = s.x + d.x
			var ny: int = s.y + d.y
			if nx < 0 or nx >= w or ny < 0 or ny >= rows_n:
				continue
			var run: int = s.z + 1 if grid[ny * w + nx] == 1 else 0
			if run > k:
				continue
			var idx := ny * w + nx
			if run < best[idx]:
				best[idx] = run
				stack.append(Vector3i(nx, ny, run))
	return y_from + deepest


## Глубже LAVA_SCAN_TO шанс озера не растёт (chance_at зажата на максимуме), поэтому проверяем до неё.
const LAVA_SCAN_TO := 6600


func _check_lava_passable() -> void:
	var tiers: Array = Heat.suit_tiers()
	var hp_lo := Balance.get_max_hp(0)
	var hp_hi := Balance.get_max_hp(10)
	var y_from := Heat.lava_min_depth() - 1
	for seed_value in SEEDS.slice(0, lava_seed_count):
		var grid := lava_grid(int(seed_value), y_from, LAVA_SCAN_TO)
		for t in range(0, tiers.size() + 1):
			var cost := Heat.lava_cell_cost_hp(t)
			var k_hi := 99 if cost <= 0.0 else int(floor((float(hp_hi) - 1.0) / cost))
			var k_lo := 99 if cost <= 0.0 else int(floor((float(hp_lo) - 1.0) / cost))
			var reach_hi := lava_reach(grid, k_hi, y_from)
			# до какой глубины игроку с этим костюмом нужно дойти за материалами следующего
			var need := LAVA_SCAN_TO
			if t < tiers.size():
				need = 0
				for item in tiers[t].get("cost", {}).get("items", {}).keys():
					var ev := evaluate(String(item), int(tiers[t]["cost"]["items"][item]), int(tiers[t].get("unlock_depth", 0)))
					if ev["source"] == "world":
						need = maxi(need, int(ev["start"]) + 150)
			var where := "лава сид %d, костюм %d" % [int(seed_value), t]
			if reach_hi < mini(need, LAVA_SCAN_TO):
				add("error", where, "с %d подряд клетками лавы (HP %d, %.0f HP/клетка) доходишь только до %d, а за материалами следующего костюма нужно до %d" % [k_hi, hp_hi, cost, reach_hi, need])
			elif verbose:
				add("info", where, "k=%d (HP %d): глубина %d; k=%d (HP %d): %d; нужно до %d" % [k_hi, hp_hi, reach_hi, k_lo, hp_lo, lava_reach(grid, k_lo, y_from), need])


# ---------------------------------------------------------------------------
# Отчёт
# ---------------------------------------------------------------------------

func print_report() -> void:
	print("--- Требования (владелец ← материал×N; рубеж → начало добычи; клеток породы / убийств) ---")
	rows.sort_custom(func(a, b): return String(a["owner"]) < String(b["owner"]))
	for r in rows:
		print("%-34s %-14s ×%-4d рубеж %-5d старт %-6d разрыв %-5d %s" % [
			r["owner"], r["id"], r["n"], r["gate"], r["start"], r["gap"],
			("клеток ~%.0f" % r["cells"]) if r["source"] == "world" else ("убийств ~%.0f" % r["kills"] if r["source"] == "drop" else r["source"])])
	print("--- Лестницы (цена в монетах / клеток породы) ---")
	for l in ladders:
		var parts: Array = []
		for s in l["steps"]:
			parts.append("%s %.0f/%.0f" % [s["label"], s["coins"], s["cells"]])
		print("%s: %s" % [l["name"], "  →  ".join(parts)])
	print("--- Находки ---")
	for f in findings:
		if f["level"] == "info" and not verbose:
			continue
		print("[%s] %s: %s" % [String(f["level"]).to_upper(), f["where"], f["text"]])

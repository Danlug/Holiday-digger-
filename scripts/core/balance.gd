extends Node
## Balance — автолоад с игровым балансом.
##
## Грузит data/*.json (balance.json, minerals.json, artifacts.json, upgrades.json)
## и отдаёт типизированные аксессоры + формулы, заданные в docs/GDD.md.
##
## Числа делятся на два вида в JSON:
##   - обычное число / строка / массив — взято из GDD напрямую;
##   - объект {"value": X, "proposed": true, "note": "..."} — число придумано
##     геймдизайнером-агентом, ждёт утверждения. Используй unwrap() чтобы
##     достать значение независимо от того, какой это вид.

const DATA_DIR := "res://data/"

var balance: Dictionary = {}
var minerals: Dictionary = {}
var artifacts: Dictionary = {}
var upgrades: Dictionary = {}

# id минерала -> его словарь из minerals.json, для быстрого доступа
var _minerals_by_id: Dictionary = {}
var _artifacts_by_id: Dictionary = {}


func _ready() -> void:
	balance = _load_json(DATA_DIR + "balance.json")
	minerals = _load_json(DATA_DIR + "minerals.json")
	artifacts = _load_json(DATA_DIR + "artifacts.json")
	upgrades = _load_json(DATA_DIR + "upgrades.json")
	_index_minerals()
	_index_artifacts()


# ---------------------------------------------------------------------------
# Загрузка и служебные функции
# ---------------------------------------------------------------------------

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Balance: файл не найден: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("Balance: не удалось распарсить JSON: %s" % path)
		return {}
	return parsed


## Достаёт числовое/любое значение из "сырого" JSON-узла, независимо от того,
## обычное это значение или обёртка {"value":X,"proposed":true,"note":"..."}.
## Публичная точка входа для других скриптов — используй Balance.unwrap(x).
static func unwrap(node):
	if typeof(node) == TYPE_DICTIONARY and node.has("value") and node.has("proposed"):
		return node["value"]
	return node

static func _v(node):
	return unwrap(node)


## true, если узел — придуманное (не из GDD) значение.
static func is_proposed(node) -> bool:
	return typeof(node) == TYPE_DICTIONARY and node.get("proposed", false) == true


func _index_minerals() -> void:
	_minerals_by_id.clear()
	for m in minerals.get("minerals", []):
		_minerals_by_id[m["id"]] = m


func _index_artifacts() -> void:
	_artifacts_by_id.clear()
	for a in artifacts.get("artifacts", []):
		_artifacts_by_id[a["id"]] = a


# ---------------------------------------------------------------------------
# Минералы
# ---------------------------------------------------------------------------

func get_mineral(id: String) -> Dictionary:
	return _minerals_by_id.get(id, {})


func get_mineral_price(id: String) -> int:
	var m := get_mineral(id)
	return int(_v(m.get("price_coins", 0)))


func get_mineral_weight(id: String) -> float:
	var m := get_mineral(id)
	return float(_v(m.get("weight_kg", 0.0)))


func get_mineral_max_stack(id: String) -> int:
	var m := get_mineral(id)
	return int(m.get("max_stack", 99))


## Плотность минерала на заданной глубине, в процентах (0..100).
## Понимает три формы density из minerals.json: flat, linear_growth, by_depth_table.
## Возвращает -1.0, если density не задана (например, у бронзы — она не добывается).
func get_mineral_density_percent(id: String, depth: int) -> float:
	var m := get_mineral(id)
	var density = m.get("density", null)
	if density == null:
		return -1.0
	density = _v(density)
	if typeof(density) != TYPE_DICTIONARY:
		return -1.0

	match density.get("type", ""):
		"flat":
			var pmin := float(_v(density.get("percent_min", 0)))
			var pmax := float(_v(density.get("percent_max", 0)))
			return (pmin + pmax) * 0.5
		"linear_growth":
			var d0 := int(_v(density.get("depth_start", 0)))
			var d1 := int(_v(density.get("depth_end", 0)))
			var p0 := float(_v(density.get("percent_start", 0)))
			var p1 := float(_v(density.get("percent_end", 0)))
			if depth <= d0:
				return p0
			if depth >= d1 or d1 == d0:
				return p1
			var t := float(depth - d0) / float(d1 - d0)
			return lerp(p0, p1, t)
		"by_depth_table":
			for entry in density.get("entries", []):
				var dmin := int(_v(entry.get("depth_min", 0)))
				var dmax := int(_v(entry.get("depth_max", 0)))
				if depth >= dmin and depth <= dmax:
					if entry.has("percent"):
						return float(_v(entry["percent"]))
					var emin := float(_v(entry.get("percent_min", 0)))
					var emax := float(_v(entry.get("percent_max", 0)))
					return (emin + emax) * 0.5
			return 0.0
		_:
			return -1.0


func mineral_has_hazard(id: String, hazard: String) -> bool:
	var m := get_mineral(id)
	var flags: Array = m.get("hazard", [])
	return flags.has(hazard)


# ---------------------------------------------------------------------------
# Артефакты
# ---------------------------------------------------------------------------

func get_artifact(id: String) -> Dictionary:
	return _artifacts_by_id.get(id, {})


func get_artifacts_in_branch(branch_num: int) -> Array:
	var out: Array = []
	for a in artifacts.get("artifacts", []):
		if int(a.get("branch", -1)) == branch_num:
			out.append(a)
	return out


func get_artifact_find_xp(id: String) -> int:
	var a := get_artifact(id)
	var bonus: Dictionary = a.get("find_bonus", {})
	return int(_v(bonus.get("xp", 0)))


func get_artifact_find_coins(id: String) -> int:
	var a := get_artifact(id)
	var bonus: Dictionary = a.get("find_bonus", {})
	return int(_v(bonus.get("coins", 0)))


func is_branch_complete(branch_num: int, collected_artifact_ids: Array) -> bool:
	for a in get_artifacts_in_branch(branch_num):
		if not collected_artifact_ids.has(a["id"]):
			return false
	return true


# ---------------------------------------------------------------------------
# Прокачка / опыт
# ---------------------------------------------------------------------------

## XP(n) = 100 * n^1.5 — опыт, нужный для перехода с уровня n на n+1.
func xp_required_for_level(n: int) -> int:
	return int(round(100.0 * pow(float(n), 1.5)))


func get_upgrade_branch(id: String) -> Dictionary:
	for b in upgrades.get("branches", []):
		if b.get("id", "") == id:
			return b
	return {}


## Стоимость (в очках прокачки) поднятия ветки id со stage-1 на stage (1-based).
func get_upgrade_stage_cost(id: String, stage: int) -> int:
	var b := get_upgrade_branch(id)
	var costs: Array = b.get("cost_points", [])
	if stage < 1 or stage > costs.size():
		return -1
	return int(_v(costs[stage - 1]))


## Суммарная стоимость прокачки ветки id с 0 до заданной ступени включительно.
func get_upgrade_total_cost(id: String, up_to_stage: int) -> int:
	var b := get_upgrade_branch(id)
	var costs: Array = b.get("cost_points", [])
	var total := 0
	var n: int = min(up_to_stage, costs.size())
	for i in range(n):
		total += int(_v(costs[i]))
	return total


# --- Конкретные формулы эффектов веток (см. GDD раздел 11) ---

## Время копки клетки с учётом ступени "Скорость копки": time = 3.0 * 0.96^stage.
func get_dig_time_seconds(dig_speed_stage: int) -> float:
	var base: float = float(_v(balance.get("digging", {}).get("base_seconds_per_cell", 3.0)))
	return base * pow(0.96, float(dig_speed_stage))


## Радиус клеток тумана войны (рельеф/ресурсы) на заданной ступени.
func get_vision_radius(branch_id: String, stage: int) -> int:
	var b := get_upgrade_branch(branch_id)
	var effect: Dictionary = b.get("effect", {})
	var base := int(_v(effect.get("base", 0)))
	var per_stage := int(_v(effect.get("per_stage", 0)))
	return base + per_stage * stage


## Максимальное HP персонажа на заданной ступени ветки "hp".
func get_max_hp(hp_stage: int) -> int:
	var b := get_upgrade_branch("hp")
	var effect: Dictionary = b.get("effect", {})
	var base := int(_v(effect.get("base", 100)))
	var per_stage := int(_v(effect.get("per_stage", 20)))
	return base + per_stage * hp_stage


## Грузоподъёмность на заданной ступени ветки "strength".
func get_max_carry_kg(strength_stage: int) -> float:
	var b := get_upgrade_branch("strength")
	var effect: Dictionary = b.get("effect", {})
	var base := float(_v(effect.get("base", 60.0)))
	var per_stage := float(_v(effect.get("per_stage", 8.0)))
	return base + per_stage * strength_stage


## Множитель удачи (общий для земли и ресурса) на заданной ступени (0..3).
func get_luck_multiplier(luck_mult_stage: int) -> float:
	if luck_mult_stage <= 0:
		return 1.0
	var b := get_upgrade_branch("luck_multiplier")
	var values: Array = b.get("effect", {}).get("values", [])
	var idx: int = clamp(luck_mult_stage, 1, values.size()) - 1
	return float(_v(values[idx]))


## Базовый шанс удачи на землю/ресурс (в процентах) на заданной ступени (0..5).
func get_luck_chance_percent(luck_chance_stage: int) -> Dictionary:
	var b := get_upgrade_branch("luck_chance")
	var effect: Dictionary = b.get("effect", {})
	var earth: Array = effect.get("earth_percent", [])
	var resource: Array = effect.get("resource_percent", [])
	if luck_chance_stage <= 0:
		return {"earth": 0.0, "resource": 0.0}
	var idx: int = clamp(luck_chance_stage, 1, earth.size()) - 1
	return {"earth": float(_v(earth[idx])), "resource": float(_v(resource[idx]))}


# ---------------------------------------------------------------------------
# Физика: перегруз, падение, ранец, джетпак (см. GDD раздел 6)
# ---------------------------------------------------------------------------

## Множитель скорости от перегруза. load_kg/max_kg — текущий груз и потолок.
func get_overload_speed_multiplier(load_kg: float, max_kg: float) -> float:
	if max_kg <= 0.0:
		return 1.0
	var cc: Dictionary = balance.get("carry_capacity", {})
	var threshold: float = float(_v(cc.get("overload_threshold_fraction", 0.85)))
	var band: float = float(_v(cc.get("overload_band_fraction", 0.15)))
	var min_mult: float = float(_v(cc.get("overload_min_speed_multiplier", 0.35)))
	var fraction: float = load_kg / max_kg
	var t: float = clamp((fraction - threshold) / band, 0.0, 1.0)
	return pow(min_mult, t)


## Урон от падения: 0.154 * height^2.16, ниже min_height урона нет.
func get_fall_damage(height_cells: float) -> float:
	var fd: Dictionary = balance.get("fall_damage", {})
	var min_height: float = float(_v(fd.get("min_height_cells", 5)))
	if height_cells < min_height:
		return 0.0
	var coeff: float = float(_v(fd.get("coefficient", 0.154)))
	var exponent: float = float(_v(fd.get("exponent", 2.16)))
	return coeff * pow(height_cells, exponent)


## Время разгона ранца с пропеллерами: 3 / 0.85^(load_kg/20), с потолком скорости 3 кл/сек.
func get_backpack_accel_time(load_kg: float) -> float:
	var bp: Dictionary = balance.get("backpack", {})
	var base: float = float(_v(bp.get("base_accel_time_seconds", 3.0)))
	return base / pow(0.85, load_kg / 20.0)


func get_backpack_max_speed() -> float:
	return float(_v(balance.get("backpack", {}).get("max_speed_cells_per_sec", 3.0)))


## Урон от удара головой на джетпаке без шлема: 20 * (speed_ratio - 0.8) / 0.2, до 80% безопасно.
func get_jetpack_head_bump_damage(current_speed: float, max_speed: float) -> float:
	if max_speed <= 0.0:
		return 0.0
	var jp: Dictionary = balance.get("jetpack", {})
	var safe_ratio: float = float(_v(jp.get("safe_speed_ratio", 0.8)))
	var coeff: float = float(_v(jp.get("head_bump_damage_coefficient", 20.0)))
	var ratio: float = current_speed / max_speed
	if ratio <= safe_ratio:
		return 0.0
	return coeff * (ratio - safe_ratio) / (1.0 - safe_ratio)


# ---------------------------------------------------------------------------
# Выживание (см. GDD раздел 7)
# ---------------------------------------------------------------------------

## Скорость расхода полоски (доля в секунду), с учётом того, копает ли герой.
func get_bar_depletion_rate_per_second(bar: String, is_digging: bool) -> float:
	var key := "stamina_depletion" if bar == "stamina" else "hunger_depletion"
	var d: Dictionary = balance.get("survival", {}).get(key, {})
	var idle_seconds: float = float(_v(d.get("full_depletion_seconds_idle", 3600.0)))
	var dig_seconds: float = float(_v(d.get("full_depletion_seconds_digging", 1200.0)))
	var total_seconds: float = dig_seconds if is_digging else idle_seconds
	if total_seconds <= 0.0:
		return 0.0
	return 1.0 / total_seconds


func get_hp_drain_per_second_when_depleted() -> float:
	return float(_v(balance.get("survival", {}).get("hp_drain_on_depletion", {}).get("hp_per_second_per_empty_bar", 1.0)))


## Восстановление бодрости за игровой час сна: 12.5% за игровой час.
func get_sleep_restore_percent_per_game_hour() -> float:
	return float(_v(balance.get("game_time", {}).get("sleep", {}).get("stamina_restore_percent_per_game_hour", 12.5)))


func get_min_sleep_game_hours() -> float:
	return float(_v(balance.get("game_time", {}).get("sleep", {}).get("min_sleep_game_hours", 2.0)))


func get_game_hours_per_real_hour() -> float:
	return float(_v(balance.get("game_time", {}).get("game_hours_per_real_hour", 8.0)))


# ---------------------------------------------------------------------------
# Экономика
# ---------------------------------------------------------------------------

func get_coins_per_premium_currency() -> float:
	return float(_v(balance.get("economy", {}).get("coins_per_premium_currency_unit", 100.0)))


func get_black_box_capacity(tier: String) -> int:
	return int(balance.get("black_box", {}).get("tiers", {}).get(tier, 1))


func get_ad_daily_limit(ad_id: String) -> int:
	return int(balance.get("ads", {}).get("daily_limits", {}).get(ad_id, 0))

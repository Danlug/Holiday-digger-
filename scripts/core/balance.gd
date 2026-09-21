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
## Разворачивает {"value": X, "proposed": true, "note": "..."} в X.
##
## Ключа "proposed" НЕ требуем: раньше требовали, и словарь без него молча
## проезжал сквозь unwrap целиком — дальше его брали во float(), получали
## ноль вместо числа, и ни одна сторона не ругалась. Достаточно самого
## "value": в этом файле так записаны только обёрнутые значения.
static func unwrap(node):
	if typeof(node) == TYPE_DICTIONARY and node.has("value"):
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
		"parabola":
			# выше depth_min руды нет; рост к peak_depth; за пиком спад, но не
			# ниже tail_percent — руды не заканчиваются с глубиной
			var dmin := int(_v(density.get("depth_min", 0)))
			if depth < dmin:
				return 0.0
			var peak_depth := int(_v(density.get("peak_depth", dmin)))
			var peak := float(_v(density.get("peak_percent", 0.0)))
			var tail := float(_v(density.get("tail_percent", 0.0)))
			var width := float(peak_depth - dmin) if depth <= peak_depth \
				else float(_v(density.get("fall_width", 1.0)))
			if width <= 0.0:
				return maxf(peak, tail)
			var t := float(depth - peak_depth) / width
			return maxf(peak * (1.0 - t * t), tail)
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
	return base * pow(0.96, float(dig_speed_stage)) / get_global_dig_speed_multiplier()


## Общий множитель темпа копки (решение владельца: со старта в 1.3 раза
## быстрее). Одним числом на всю игру, а не переписанными секундами у каждого
## минерала: те заданы по твёрдости и должны читаться как есть.
func get_global_dig_speed_multiplier() -> float:
	var m: float = float(_v(balance.get("digging", {}).get("global_speed_multiplier", 1.0)))
	return m if m > 0.0 else 1.0


## Радиус клеток тумана войны (рельеф/ресурсы) на заданной ступени.
func get_vision_radius(branch_id: String, stage: int) -> int:
	var b := get_upgrade_branch(branch_id)
	var effect: Dictionary = b.get("effect", {})
	var base := int(_v(effect.get("base", 0)))
	var per_stage := int(_v(effect.get("per_stage", 0)))
	var maximum := int(_v(effect.get("max", 0)))
	var r := base + per_stage * stage
	return mini(r, maximum) if maximum > 0 else r


## На сколько клеток рельеф видно дальше ресурсов (решение владельца: всегда
## на одну). Число лежит в ветке «Обзор», а не в коде: это баланс.
func get_vision_terrain_bonus() -> int:
	var effect: Dictionary = get_upgrade_branch("vision").get("effect", {})
	return int(_v(effect.get("terrain_bonus_cells", 1)))


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


## Урон от падения по СКОРОСТИ удара, а не по высоте (см. GDD раздел 6:
## "урон считается от скорости удара... спуск на пропеллере — не то же самое,
## что падение той же высоты"). Использует те же coefficient/exponent, что и
## get_fall_damage(height), но в реальном времени игрок-контроллер знает
## только скорость удара — height там не отслеживается для полёта.
## gravity — текущее G мира (физическая константа, см. player.gd), передаётся
## аргументом, а не хранится здесь: G — это ощущение движения, а не баланс.
##
## dmg_mult/height_mult — множители бурмобиля (см. get_drill_rig_fall_damage_mult/
## get_drill_rig_fall_damage_height_mult): по умолчанию 1.0 (пеший герой/ранец/
## джетпак — старая формула буквально, ничего не меняется). height_mult растит
## ПОРОГ ВЫСОТЫ (min_height_cells) ДО перевода в безопасную скорость — тройной
## порог высоты даёт безопасную скорость sqrt(3)× больше, не втрое (падение
## по свободному падению: v = sqrt(2*g*h), h кубу не пропорциональна v).
func get_fall_damage_from_speed(speed_cells_per_sec: float, gravity: float,
		dmg_mult: float = 1.0, height_mult: float = 1.0) -> float:
	var fd: Dictionary = balance.get("fall_damage", {})
	var coeff: float = float(_v(fd.get("coefficient", 0.154)))
	var exponent: float = float(_v(fd.get("exponent", 2.16)))
	var min_height: float = float(_v(fd.get("min_height_cells", 5))) * height_mult
	var safe_speed: float = sqrt(2.0 * gravity * min_height)
	if speed_cells_per_sec < safe_speed:
		return 0.0
	var k: float = coeff / pow(2.0 * gravity, exponent)
	return k * pow(speed_cells_per_sec, exponent * 2.0) * dmg_mult


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


## Утечка HP при пустых полосках (ГДД раздел 7, решение владельца).
##
## Голод и бодрость наказывают ПО-РАЗНОМУ, и в этом весь смысл: голод убивает,
## усталость — мешает. Поэтому здесь не «столько-то за каждую пустую полоску»,
## а три отдельных случая.
func get_hp_drain_per_second(hunger_empty: bool, stamina_empty: bool) -> float:
	var d: Dictionary = balance.get("survival", {}).get("hp_drain_on_depletion", {})
	if hunger_empty and stamina_empty:
		return float(_v(d.get("both_empty_hp_per_second", 2.0)))
	if hunger_empty:
		return float(_v(d.get("hunger_hp_per_second", 1.0)))
	if stamina_empty:
		return float(_v(d.get("stamina_hp_per_second", 0.0)))
	return 0.0


## Штраф за пустую бодрость: множитель ко всем скоростям и к расходу голода.
## Обессиленный герой копает вдвое медленнее и ест вдвое больше — усталость
## наказывает сама себя, не отнимая ни единицы HP.
func get_exhausted_speed_multiplier() -> float:
	return float(_v(balance.get("survival", {}).get("exhausted_penalty", {}).get("speed_multiplier", 0.5)))


func get_exhausted_hunger_multiplier() -> float:
	return float(_v(balance.get("survival", {}).get("exhausted_penalty", {}).get(
		"hunger_drain_multiplier_while_working", 1.2)))


## Пороги предупреждений: предупреждать надо ДО того, как поздно — игрок
## должен успеть подняться, а не обнаружить проблему на дне с полным рюкзаком.
func get_warning_percent(severe: bool) -> float:
	var w: Dictionary = balance.get("survival", {}).get("warnings", {})
	return float(_v(w.get("severe_percent", 10.0) if severe else w.get("notice_percent", 25.0)))


func get_warning_red_flash_seconds() -> float:
	return float(_v(balance.get("survival", {}).get("warnings", {}).get("severe_red_flash_seconds", 2.0)))


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


# ---------------------------------------------------------------------------
# Инструменты (см. GDD раздел 5, balance.json -> tools)
# ---------------------------------------------------------------------------

func get_tool(id: String) -> Dictionary:
	return balance.get("tools", {}).get(id, {})


## Скорость копки лучшей кирки прямо сейчас — максимум speed_multiplier
## среди инструментов линии "pickaxe". Живой максимум, а не хардкод «5»:
## подрастёт кирка — подрастёт и бур с бурмобилем без правки кода (см.
## get_tool_speed_multiplier).
func get_best_pickaxe_speed_multiplier() -> float:
	var best := 0.0
	for id in balance.get("tools", {}).keys():
		var t = balance["tools"][id]
		if typeof(t) != TYPE_DICTIONARY or String(t.get("line", "")) != "pickaxe":
			continue
		best = maxf(best, float(_v(t.get("speed_multiplier", 0.0))))
	return best


## Множитель скорости копки инструмента. У кирок и лопаты число лежит прямо
## в balance.json. У бура и бурмобиля числа НЕТ — оно решением владельца
## привязано к другому инструменту («ручной бур копает в 2 раза быстрее, чем
## лучшая кирка»; «бурмобиль — в 2 раза лучше бура»), поэтому считаем здесь,
## одним местом, а не храним 10/20 отдельными числами, которые разъедутся
## при следующей правке линейки кирок (balance.json -> tools.hand_drill
## .speed_vs_best_pickaxe, tools.drill_rig.speed_vs_hand_drill).
func get_tool_speed_multiplier(id: String) -> float:
	if id == "hand_drill":
		var factor := float(_v(get_tool("hand_drill").get("speed_vs_best_pickaxe", 2.0)))
		return get_best_pickaxe_speed_multiplier() * factor
	if id == "drill_rig":
		# Апгрейд бура (титан/платина/алмаз/обсидиан) — ДОПОЛНИТЕЛЬНЫЙ
		# множитель СВЕРХУ базовой скорости бурмобиля, компаундится по
		# ступеням (см. get_drill_rig_tier_multiplier и
		# get_drill_rig_speed_at_tier — та же формула для гипотетического
		# тира, нужна магазину, чтобы показать цену следующей ступени, не
		# трогая текущий тир игрока).
		return get_drill_rig_speed_at_tier(_current_drill_rig_tier())
	return float(_v(get_tool(id).get("speed_multiplier", 1.0)))


## Текущая ступень апгрейда бура игрока — GameState.drill_rig_tier, но БЕЗ
## жёсткой ссылки на автозагрузку по имени: tests/test_balance.gd создаёт
## Balance напрямую (load(...).new()), в обход обычного запуска сцены, а
## headless-запуск через --script не гарантированно поднимает автозагрузки
## до выполнения скрипта (см. докстринг того теста) — простое "GameState." в
## этом файле тогда не компилируется вовсе (ошибка ловится на reload, а не
## только при вызове) и рушит вообще все функции Balance, не только эту.
## Поэтому GameState ищется по пути в дереве, а не по имени автозагрузки:
## нет дерева/узла — тир не апгрейжен (0), ровно как у игрока с чистым сейвом.
func _current_drill_rig_tier() -> int:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var root: Node = (loop as SceneTree).root
		if root != null and root.has_node("GameState"):
			return int(root.get_node("GameState").get("drill_rig_tier"))
	return 0


## Базовая скорость бурмобиля БЕЗ апгрейда (тир 0) — "бурмобиль копает в 2
## раза лучше бура" (решение владельца), она же общий множитель для
## get_drill_rig_speed_at_tier ниже.
func get_drill_rig_base_speed_multiplier() -> float:
	var factor := float(_v(get_tool("drill_rig").get("speed_vs_hand_drill", 2.0)))
	return get_tool_speed_multiplier("hand_drill") * factor


## Скорость бурмобиля НА ПРОИЗВОЛЬНОМ тире апгрейда (0..N), не обязательно
## текущем у игрока — нужна магазину для строки "что купишь дальше", чтобы
## не подставлять GameState.drill_rig_tier и не откатывать его обратно.
func get_drill_rig_speed_at_tier(tier: int) -> float:
	return get_drill_rig_base_speed_multiplier() * get_drill_rig_tier_multiplier(tier)


## Максимальная глубина инструмента (null/отсутствует = без ограничения).
func get_tool_max_depth(id: String) -> int:
	var t := get_tool(id)
	if not t.has("max_depth") or t["max_depth"] == null:
		return -1
	return int(_v(t["max_depth"]))


func get_tool_name_ru(id: String) -> String:
	return String(get_tool(id).get("name_ru", id))


## Цена инструмента в монетах. Кирки стоят ТОЛЬКО монеты (решение владельца:
## "остальные 5 покупаются в магазине"), поэтому у них это вся цена целиком.
func get_tool_cost_coins(id: String) -> int:
	return int(_v(get_tool_cost(id).get("coins", 0)))


## Полная статья цены инструмента: {coins: int, <item_id>: int}. Пустой
## словарь — инструмент бесплатный (лопата, ржавая кирка).
func get_tool_cost(id: String) -> Dictionary:
	var cost = _v(get_tool(id).get("cost", {}))
	return cost if typeof(cost) == TYPE_DICTIONARY else {}


## Нужны ли инструменту материалы помимо монет. Разделительная черта нового
## прогресса: у кирок — нет (только монеты), у техники — да (рецепт остаётся).
func tool_needs_materials(id: String) -> bool:
	for key in get_tool_cost(id).keys():
		if String(key) != "coins" and int(_v(get_tool_cost(id)[key])) > 0:
			return true
	return false


## Путь к иконке инструмента; пустая строка — картинки ещё нет и рисовать
## нечего (владелец присылает арт отдельно).
func get_tool_icon(id: String) -> String:
	return String(get_tool(id).get("icon", ""))


## Идентификаторы одной линейки инструментов ("pickaxe" — шесть кирок,
## "tech" — бур и бурмобиль), отсортированные по ступени.
## Порядок берётся из поля tier, а не из порядка ключей в JSON: линейку будут
## дополнять, и вставленная в середину ступень не должна менять смысл файла.
func get_tools_in_line(line: String) -> Array:
	var rows: Array = []
	for id in balance.get("tools", {}).keys():
		var t = balance["tools"][id]
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if String(t.get("line", "")) != line:
			continue
		rows.append({"id": String(id), "tier": int(_v(t.get("tier", 0)))})
	rows.sort_custom(func(a, b): return int(a["tier"]) < int(b["tier"]))
	var out: Array = []
	for r in rows:
		out.append(String(r["id"]))
	return out


# ---------------------------------------------------------------------------
# Снаряжение: линейка ранцев (balance.json -> gear)
#
# Четыре ступени, одна надета. Множитель ступени умножает ПОТОЛОК скорости
# подъёма базового ранца — см. gear._note в data/balance.json и _move_y в
# scripts/player/player.gd, где он применяется.
# ---------------------------------------------------------------------------

func get_gear(id: String) -> Dictionary:
	var g = balance.get("gear", {}).get(id, {})
	return g if typeof(g) == TYPE_DICTIONARY else {}


## Все ступени линейки по возрастанию tier.
func get_gear_ids() -> Array:
	var rows: Array = []
	for id in balance.get("gear", {}).keys():
		var g = balance["gear"][id]
		if typeof(g) != TYPE_DICTIONARY or not g.has("tier"):
			continue
		rows.append({"id": String(id), "tier": int(_v(g["tier"]))})
	rows.sort_custom(func(a, b): return int(a["tier"]) < int(b["tier"]))
	var out: Array = []
	for r in rows:
		out.append(String(r["id"]))
	return out


## Множитель скорости полёта ступени. 0.0 у пустого id — это не "летать со
## скоростью ноль", а "ранца нет вовсе": так grant_gear() может сравнивать
## новую ступень с надетой одним числом, не проверяя отдельно пустой случай.
func get_gear_fly_multiplier(id: String) -> float:
	if id.is_empty():
		return 0.0
	return float(_v(get_gear(id).get("fly_speed_multiplier", 0.0)))


## Потолок скорости подъёма БАЗОВОГО ранца, клеток/с. Его умножает вся линейка.
func get_gear_base_speed() -> float:
	return float(_v(balance.get("gear", {}).get("base_max_speed_cells_per_sec", 2.5)))


## Фактический потолок скорости подъёма ступени, клеток/с.
func get_gear_max_speed(id: String) -> float:
	return get_gear_base_speed() * get_gear_fly_multiplier(id)


## "prop" — пропеллеры (разгон зависит от груза), "jet" — реактивная тяга
## (свой разгон и своя анимация полёта). Вид, а не отдельная ветка линейки:
## ступени идут подряд, просто верхние две — реактивные.
func get_gear_kind(id: String) -> String:
	return String(get_gear(id).get("kind", "prop"))


func get_gear_cost_coins(id: String) -> int:
	var cost = _v(get_gear(id).get("cost", {}))
	if typeof(cost) != TYPE_DICTIONARY:
		return 0
	return int(_v(cost.get("coins", 0)))


func get_gear_name_ru(id: String) -> String:
	return String(get_gear(id).get("name_ru", id))


## Путь к иконке ступени; пустая строка — арта ещё нет (владелец присылает
## анимации ранцев позже), и UI просто не рисует картинку.
func get_gear_icon(id: String) -> String:
	return String(get_gear(id).get("icon", ""))


## Расход топливных блоков на одну прокопанную клетку у бурмобиля (ГДД
## раздел 5: «если он экипирован бурмобилем, он должен иметь на себе
## топливо» — решение владельца, число расхода не задано, см. balance.json
## -> fuel_consumption.blocks_per_cell.drill_rig, proposed).
func get_drill_rig_fuel_per_cell() -> float:
	return float(_v(balance.get("fuel_consumption", {}).get("blocks_per_cell", {}).get("drill_rig", 0.1)))


# ---------------------------------------------------------------------------
# Бурмобиль: грузоподъёмность и физика прыжка/полёта (задача «Прыжок и полёт
# бурмобиля», числа даны владельцем дословно — proposed: false).
# ---------------------------------------------------------------------------

## Бонус к МАКСИМАЛЬНОЙ переносимой массе, пока бурмобиль надет ("носимый вес
## увеличивается на 200 кг, вдобавок к собственному" — решение владельца).
## Это лимит грузоподъёмности (GameState.get_max_carry_kg()), а НЕ вес самой
## машины в инвентаре — она в инвентарь не кладётся и там ничего не весит.
func get_drill_rig_capacity_bonus_kg() -> float:
	return float(_v(balance.get("tools", {}).get("drill_rig", {}).get("capacity_bonus_kg", 200.0)))


## Множитель предела скорости падения (V_TERM в player.gd), пока бурмобиль
## надет — решение владельца: "скорость падения в бурмобиле на 30% быстрее".
func get_drill_rig_fall_speed_mult() -> float:
	return float(_v(balance.get("tools", {}).get("drill_rig", {}).get("fall_speed_mult", 1.3)))


## Множитель потолка скорости подъёма на тяге, пока бурмобиль надет —
## решение владельца: "полёт на 30% быстрее".
func get_drill_rig_flight_speed_mult() -> float:
	return float(_v(balance.get("tools", {}).get("drill_rig", {}).get("flight_speed_mult", 1.3)))


## Множитель урона от падения, пока бурмобиль надет — решение владельца:
## "урон от падения на 50% меньше" (см. get_fall_damage_from_speed).
func get_drill_rig_fall_damage_mult() -> float:
	return float(_v(balance.get("tools", {}).get("drill_rig", {}).get("fall_damage_mult", 0.5)))


## Множитель порога высоты (min_height_cells в fall_damage), с которой падение
## вообще начинает наносить урон, пока бурмобиль надет — решение владельца:
## "высота, с которой он получает урон, в 3 раза выше" (см.
## get_fall_damage_from_speed).
func get_drill_rig_fall_damage_height_mult() -> float:
	return float(_v(balance.get("tools", {}).get("drill_rig", {}).get("fall_damage_height_mult", 3.0)))


# ---------------------------------------------------------------------------
# Апгрейд бура бурмобиля (задача «Апгрейд бура», решение владельца дословно:
# «в магазине после появления бурмобиля появляется опция улучшить бурмобиль:
# титановый/платиновый/алмазный/обсидиановый бур, каждый на 20% быстрее
# предыдущего»). Тиры лежат в balance.json -> tools.drill_rig.upgrade_tiers —
# единственный источник и процента (speed_bonus), и порядка, и цены; здесь
# только читаем, не хардкодим 1.2 второй раз (см. get_tool_speed_multiplier).
# GameState.drill_rig_tier: 0 — апгрейда ещё нет (обычный серый бур), 1..N —
# индекс купленной ступени (1 = первая строка массива, титан).
# ---------------------------------------------------------------------------

func _drill_rig_upgrade_tiers_raw() -> Array:
	var t = _v(get_tool("drill_rig").get("upgrade_tiers", []))
	return t if typeof(t) == TYPE_ARRAY else []


## Сколько всего ступеней апгрейда бура описано в balance.json (сейчас 4:
## титан/платина/алмаз/обсидиан) — живое число, а не хардкод «4», чтобы
## магазин и GameState.drill_rig_tier не разъехались с JSON, если ступеней
## станет больше или меньше.
func get_drill_rig_tier_count() -> int:
	return _drill_rig_upgrade_tiers_raw().size()


## Строка тира по индексу 1..N (0 — "апгрейда нет", сюда не ходят). Пустой
## словарь — индекс вне диапазона (тира с таким номером не существует).
func get_drill_rig_tier_row(tier: int) -> Dictionary:
	var tiers := _drill_rig_upgrade_tiers_raw()
	if tier < 1 or tier > tiers.size():
		return {}
	var row = tiers[tier - 1]
	return row if typeof(row) == TYPE_DICTIONARY else {}


func get_drill_rig_tier_id(tier: int) -> String:
	return String(get_drill_rig_tier_row(tier).get("id", ""))


func get_drill_rig_tier_name_ru(tier: int) -> String:
	return String(get_drill_rig_tier_row(tier).get("name_ru", ""))


## Цена ЭТОЙ ступени (не накопленная — сколько стоит купить именно её,
## следующую после уже надетой) в монетах.
func get_drill_rig_tier_cost_coins(tier: int) -> int:
	var cost = _v(get_drill_rig_tier_row(tier).get("cost", {}))
	if typeof(cost) != TYPE_DICTIONARY:
		return 0
	return int(_v(cost.get("coins", 0)))


## Собственный множитель СКОРОСТИ этой одной ступени (у владельца — «каждый
## на 20% быстрее предыдущего», то есть 1.2 в каждой строке JSON). Читаем
## число, а не подставляем константу: строки могут когда-нибудь задать разный
## процент на разных ступенях, и здесь единственное место, которое об этом
## узнает.
func get_drill_rig_tier_speed_bonus(tier: int) -> float:
	return float(_v(get_drill_rig_tier_row(tier).get("speed_bonus", 1.0)))


## Накопленный множитель скорости бура НА ЭТОЙ ступени — произведение
## speed_bonus всех ступеней с 1 по tier включительно (компаундится: титан
## ×1.2, платина ×1.2×1.2, алмаз ×1.2³, обсидиан ×1.2⁴ — ровно как просил
## владелец: «каждый на 20% быстрее ПРЕДЫДУЩЕГО», не от базы каждый раз).
## tier<=0 -> 1.0 (апгрейда нет, множитель не действует).
func get_drill_rig_tier_multiplier(tier: int) -> float:
	var mult := 1.0
	var top: int = clampi(tier, 0, get_drill_rig_tier_count())
	for t in range(1, top + 1):
		mult *= get_drill_rig_tier_speed_bonus(t)
	return mult


## Время бурения клетки минерала id базовым инструментом (drill_seconds из
## minerals.json), с запасным значением, если минерал не описан явно.
func get_mineral_drill_seconds(id: String) -> float:
	var m := get_mineral(id)
	if m.is_empty():
		return float(_v(balance.get("digging", {}).get("base_seconds_per_cell", 3.0)))
	return float(_v(m.get("drill_seconds", 3.0)))

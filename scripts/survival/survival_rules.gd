class_name SurvivalRules
extends RefCounted
## SurvivalRules — что голод и усталость делают с героем (решение владельца,
## раунд 5, ГДД §7 «Голод и усталость давят сильнее»): «голод и усталость
## должны влиять больше на игру».
##
## До раунда 5 полоски наказывали только на нуле, и осторожный игрок их не
## замечал (docs/PLAYTEST.md: еда — 4–8% дохода, выживание — фон). Теперь:
##  * расход выше (drain_multiplier), кроме мягкого старта (soft_start);
##  * на тех же 25% и 10%, где приходят предупреждения, начинаются ступени:
##    голод — копка медленнее и удача реже, усталость — ходьба и копка
##    медленнее, прыжок ниже; на нуле бодрости — ещё «шатание».
## Числа — data/survival.json (proposed). Числа владельца (база расхода,
## −50% на нуле бодрости, 1 HP/с от голода) — в data/balance.json, здесь они
## только читаются.

const DATA_PATH := "res://data/survival.json"

const LOW := "low"
const CRITICAL := "critical"
const EMPTY := "empty"

static var _data: Dictionary = {}
static var _loaded := false


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		if FileAccess.file_exists(DATA_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


static func reload() -> void:
	_loaded = false


## Ступень полоски: "" — норма, LOW (≤25%), CRITICAL (≤10%), EMPTY (ноль).
## Пороги — те же, что у предупреждений: значок появляется вместе с тостом.
static func tier(value: float) -> String:
	if value <= 0.0:
		return EMPTY
	if value <= Balance.get_warning_percent(true):
		return CRITICAL
	if value <= Balance.get_warning_percent(false):
		return LOW
	return ""


static func _tier_num(bar: String, t: String, key: String, fallback: float) -> float:
	if t.is_empty():
		return 1.0
	var v = Balance.unwrap(data().get(bar + "_tiers", {}).get(t, {}).get(key, fallback))
	return float(v) if v != null else fallback


# ---------------------------------------------------------------------------
# Расход
# ---------------------------------------------------------------------------

## Во сколько раз полоска тает быстрее базового расхода владельца.
static func drain_multiplier(bar: String) -> float:
	if soft_start_active():
		return 1.0
	var v = Balance.unwrap(data().get("drain_multiplier", {}).get(bar, 1.0))
	return float(v) if v != null else 1.0


## Мягкий старт: до первого урока сна и до until_level — расход как раньше.
static func soft_start_active() -> bool:
	var s: Dictionary = data().get("soft_start", {})
	if s.is_empty():
		return false
	var scene := String(s.get("until_scene", ""))
	if not scene.is_empty() and GameState.story_seen.has(scene):
		return false
	if GameState.house_tutorial_stage >= 1:
		return false   # урок сна без сюжетной системы (дом ведёт его сам)
	return GameState.level < int(Balance.unwrap(s.get("until_level", 0)))


# ---------------------------------------------------------------------------
# Последствия: множители, которые спрашивает герой
# ---------------------------------------------------------------------------

## Копка: голод и усталость множатся (оба плохо — копает совсем вяло).
## Больше 1 — быстрее; время клетки делится на это число.
static func dig_factor(hunger: float = -1.0, stamina: float = -1.0) -> float:
	if hunger < 0.0:
		hunger = GameState.hunger
	if stamina < 0.0:
		stamina = GameState.stamina
	var st := tier(stamina)
	var st_dig := Balance.get_exhausted_speed_multiplier() if st == EMPTY \
		else _tier_num("stamina", st, "dig", 1.0)
	return _tier_num("hunger", tier(hunger), "dig", 1.0) * st_dig


## Ходьба. На нуле — −50% владельца; полёт сюда не входит (см. fly_factor).
static func move_factor(stamina: float = -1.0) -> float:
	if stamina < 0.0:
		stamina = GameState.stamina
	var st := tier(stamina)
	if st == EMPTY:
		return Balance.get_exhausted_speed_multiplier()
	return _tier_num("stamina", st, "move", 1.0)


## Прыжок: множитель ВЫСОТЫ (скорость толчка — его корень).
static func jump_height_factor(stamina: float = -1.0) -> float:
	if stamina < 0.0:
		stamina = GameState.stamina
	return _tier_num("stamina", tier(stamina), "jump", 1.0)


static func jump_velocity_factor(stamina: float = -1.0) -> float:
	return sqrt(maxf(jump_height_factor(stamina), 0.0))


## Удача: во сколько раз реже срабатывает шанс находки ×N.
static func luck_factor(hunger: float = -1.0) -> float:
	if hunger < 0.0:
		hunger = GameState.hunger
	return clampf(_tier_num("hunger", tier(hunger), "luck", 1.0), 0.0, 1.0)


## «Шатание» без сил: доля скорости ходьбы в момент t (секунды). 1 — не шатает.
static func stagger_factor(t: float, stamina: float = -1.0) -> float:
	if stamina < 0.0:
		stamina = GameState.stamina
	if tier(stamina) != EMPTY:
		return 1.0
	var amp := clampf(_tier_num("stamina", EMPTY, "stagger_amplitude", 0.4), 0.0, 0.9)
	var period := maxf(_tier_num("stamina", EMPTY, "stagger_period_seconds", 1.2), 0.1)
	return 1.0 - amp * (0.5 + 0.5 * sin(TAU * t / period))


static func is_staggering(stamina: float = -1.0) -> bool:
	if stamina < 0.0:
		stamina = GameState.stamina
	return tier(stamina) == EMPTY


# ---------------------------------------------------------------------------
# Значок-статус у полоски (HUD): иконка на экране, слова — только в Tip
# ---------------------------------------------------------------------------

## {} — всё в норме; иначе {icon, tier, title, text}.
static func status(bar: String, value: float) -> Dictionary:
	var t := tier(value)
	if t.is_empty():
		return {}
	if bar == "hunger":
		return _hunger_status(t)
	return _stamina_status(t)


static func _pct(f: float) -> int:
	return int(round((1.0 - f) * 100.0))


static func _hunger_status(t: String) -> Dictionary:
	var dig := _pct(_tier_num("hunger", t, "dig", 1.0))
	var luck := _tier_num("hunger", t, "luck", 1.0)
	var luck_text := "удачи нет" if luck <= 0.0 else "удача в %d раза реже" % int(round(1.0 / luck))
	if t == EMPTY:
		return {"icon": "st_drain", "tier": t, "title": "Голодаешь",
			"text": "Здоровье тает по %s HP в секунду, копка −%d%%, %s. Поешь!" % [
				_num_text(Balance.get_hp_drain_per_second(true, false)), dig, luck_text]}
	return {"icon": "st_weak", "tier": t, "title": "Голоден" if t == LOW else "Очень голоден",
		"text": "Слабее: копка −%d%%, %s." % [dig, luck_text]}


static func _stamina_status(t: String) -> Dictionary:
	if t == EMPTY:
		var all := _pct(Balance.get_exhausted_speed_multiplier())
		return {"icon": "st_dizzy", "tier": t, "title": "Без сил",
			"text": "Шатает: все скорости −%d%%, прыжок ниже, голод тает быстрее. Пора спать." % all}
	var move := _pct(_tier_num("stamina", t, "move", 1.0))
	var dig := _pct(_tier_num("stamina", t, "dig", 1.0))
	var jump := _pct(_tier_num("stamina", t, "jump", 1.0))
	return {"icon": "st_slow", "tier": t, "title": "Устал" if t == LOW else "Вымотан",
		"text": "Медленнее: ходьба −%d%%, копка −%d%%, прыжок ниже на %d%%." % [move, dig, jump]}


static func _num_text(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else "%.1f" % v

class_name GreedRules
extends RefCounted
## Числа режима жадности (ГДД §20.1, слова владельца раунда 4): когда шкала азарта
## полна — N секунд любая клетка копается с первого удара, ход, полёт и падение
## в 7 раз быстрее. База — раздел `greed` в data/mechanics.json, ступени — ветка
## «Жадность» в data/upgrades.json (длительность 4–8 с, порог на 5–25% меньше
## streak.fever_s). Один источник для игры, симулятора и тестов.

const BRANCH := "greed"


static func _effect() -> Dictionary:
	var e = Balance.get_upgrade_branch(BRANCH).get("effect", {})
	return e if typeof(e) == TYPE_DICTIONARY else {}


static func _at(key: String, stage: int, default: float) -> float:
	var t = Balance.unwrap(_effect().get(key, []))
	if typeof(t) != TYPE_ARRAY or (t as Array).is_empty() or stage <= 0:
		return default
	return float((t as Array)[mini(stage, (t as Array).size()) - 1])


static func max_stage() -> int:
	return int(Balance.get_upgrade_branch(BRANCH).get("stages", 0))


## Ступень ветки у игрока.
static func stage() -> int:
	return GameState.get_skill_stage(BRANCH)


## Секунд работы до жадности: streak.fever_s минус процент ступени (до 26.10 —
## клетки подряд; почему секунды — streak_logic.gd).
static func threshold(stage_n: int) -> float:
	var base := maxf(1.0, MechData.num("streak", "fever_s", 60.0))
	var less := _at("less_percent", stage_n, 0.0)
	return maxf(1.0, base * (1.0 - less / 100.0))


## Секунд жадности на ступени (0 — база владельца, 3 с).
static func seconds(stage_n: int) -> float:
	return _at("seconds", stage_n, MechData.num("greed", "seconds", 3.0))


## Во сколько раз быстрее ход, полёт и падение.
static func speed_mult() -> float:
	return maxf(1.0, MechData.num("greed", "speed_mult", 7.0))


## «С первого удара»: клетка разбивается в тот миг, когда кирка впервые бьёт по
## породе — через полпериода удара инструмента (так стоят звук и кадр удара:
## JuiceDirector). Кирка — 0.19 с, бурмобиль — 0.06 с.
static func dig_seconds(tool_id: String) -> float:
	var hits := maxf(1.0, MechData.num("greed", "dig_hits", 1.0))
	return Feel.hit_period(tool_id) * (hits - 0.5)

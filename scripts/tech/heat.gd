class_name Heat
extends RefCounted
## Жара и лава (ГДД п.13 «Лава», п.18).
##
## Два независимых эффекта, оба гасятся одним костюмом (ступени в tech.json):
##  * жара породы — плавный рост температуры с глубиной; сверх стойкости костюма
##    расход бодрости растёт (HP жара не трогает, как и пустая бодрость, п.7);
##  * лава — клетка с глубины 3000: копается 5 с и жжёт 20 HP/с (решение
##    владельца, balance.json → survival.hazards.lava); костюм снимает долю урона,
##    пятая ступень делает лаву проходимой.


# ---------------------------------------------------------------------------
# Температура и зоны
# ---------------------------------------------------------------------------

static func temperature(depth: float) -> float:
	var pts: Array = TechData.v(TechData.heat().get("temperature_c", [[0, 16]]))
	if pts.is_empty():
		return 16.0
	if depth <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		var a: Array = pts[i - 1]
		var b: Array = pts[i]
		if depth <= float(b[0]):
			var t := (depth - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1.0)
			return lerpf(float(a[1]), float(b[1]), t)
	return float(pts[pts.size() - 1][1])


## Зона по глубине: {id, name_ru, from, index}.
static func zone(depth: float) -> Dictionary:
	var zones: Array = TechData.heat().get("zones", [])
	var best: Dictionary = {"id": "cool", "name_ru": "", "from": 0, "index": 0}
	for i in range(zones.size()):
		if depth >= float(zones[i].get("from", 0)):
			best = (zones[i] as Dictionary).duplicate()
			best["index"] = i
	return best


# ---------------------------------------------------------------------------
# Костюм
# ---------------------------------------------------------------------------

static func suit_tiers() -> Array:
	return TechData.v(TechData.heat().get("suit_tiers", []))


static func suit_tier() -> int:
	return clampi(TechState.suit(), 0, suit_tiers().size())


static func _tier_row(tier: int) -> Dictionary:
	var rows := suit_tiers()
	return rows[tier - 1] if tier >= 1 and tier <= rows.size() else {}


static func base_tolerance_c() -> float:
	return float(TechData.v(TechData.heat().get("ambient", {}).get("base_tolerance_c", 40)))


static func tolerance_c(tier: int = -1) -> float:
	var t := suit_tier() if tier < 0 else tier
	return float(_tier_row(t).get("tolerance_c", base_tolerance_c())) if t > 0 else base_tolerance_c()


static func lava_resist(tier: int = -1) -> float:
	var t := suit_tier() if tier < 0 else tier
	return clampf(float(_tier_row(t).get("lava_resist", 0.0)), 0.0, 1.0) if t > 0 else 0.0


## Множитель расхода бодрости от жары на этой глубине (1.0 — комфортно).
static func stamina_multiplier(depth: float, tier: int = -1) -> float:
	var amb: Dictionary = TechData.heat().get("ambient", {})
	var per50 := float(TechData.v(amb.get("stamina_extra_per_50c", 1.0)))
	var cap := float(TechData.v(amb.get("max_multiplier", 6.0)))
	var excess := maxf(0.0, temperature(depth) - tolerance_c(tier))
	return minf(1.0 + per50 * excess / 50.0, cap)


## Порог урона от жары (°C): 70 без костюма (владелец 30.10: «температура больше 70 начинает
## делать урон»); костюм сдвигает его на свою прибавку стойкости.
static func damage_from_c(tier: int = -1) -> float:
	var amb: Dictionary = TechData.heat().get("ambient", {})
	var base := float(TechData.v(amb.get("damage_from_c", 70)))
	return base + maxf(0.0, tolerance_c(tier) - base_tolerance_c())


## Урон жары, HP в секунду на этой глубине (0 — ниже порога).
static func damage_per_second(depth: float, tier: int = -1) -> float:
	var amb: Dictionary = TechData.heat().get("ambient", {})
	var excess := temperature(depth) - damage_from_c(tier)
	if excess <= 0.0:
		return 0.0
	return excess / 10.0 * float(TechData.v(amb.get("damage_hp_per_10c", 1.0)))


## Три уровня для значка на HUD: 0 — комфортно, 1 — припекает, 2 — печёт.
static func felt_level(depth: float) -> int:
	var m := stamina_multiplier(depth)
	if m <= 1.001:
		return 0
	return 1 if m < 2.0 else 2


# ---------------------------------------------------------------------------
# Лава
# ---------------------------------------------------------------------------

static func lava_min_depth() -> int:
	return int(TechData.bal(["survival", "hazards", "lava", "depth_min"], 3000))


static func lava_dig_seconds() -> float:
	return float(TechData.bal(["survival", "hazards", "lava", "dig_seconds"], 5.0))


static func lava_raw_dps() -> float:
	return float(TechData.bal(["survival", "hazards", "lava", "hp_damage_per_second"], 20.0))


## Урон в секунду с учётом костюма.
static func lava_dps(tier: int = -1) -> float:
	return lava_raw_dps() * (1.0 - lava_resist(tier))


## Сколько HP стоит одна клетка лавы (копка целиком) с текущим костюмом.
static func lava_cell_cost_hp(tier: int = -1) -> float:
	return lava_dps(tier) * lava_dig_seconds()


## Хватит ли здоровья на клетку лавы целиком. Нет — копка не начинается, лава для
## героя стена (владелец: «до прокачки лава — стена, а не препятствие»), а не
## мгновенная смерть от одного неверного касания.
static func can_dig_lava() -> bool:
	return GameState.debug_invincible or lava_cell_cost_hp() < GameState.hp


## Пока герой копает лаву — жжём. dt — секунды кадра. Возвращает нанесённый урон.
static func burn_digger(dt: float) -> float:
	var dmg := lava_dps() * dt
	if dmg > 0.0:
		GameState.take_damage(dmg, "lava")
	return dmg


# ---------------------------------------------------------------------------
# Крафт костюма: ступени строго по порядку, сделанное надевается сразу
# ---------------------------------------------------------------------------

## {ok, reason, tier, cost}. Следующая ступень после надетой.
static func next_suit() -> Dictionary:
	var tier := suit_tier() + 1
	var row := _tier_row(tier)
	if row.is_empty():
		return {"ok": false, "reason": "Костюм уже лучший", "tier": tier, "cost": null}
	return {"ok": true, "reason": "", "tier": tier, "cost": row.get("cost", null), "row": row}


static func craft_suit() -> Dictionary:
	var n := next_suit()
	if not bool(n["ok"]):
		return {"ok": false, "message": String(n["reason"])}
	var row: Dictionary = n["row"]
	if GameState.max_depth_reached < int(row.get("unlock_depth", 0)):
		return {"ok": false, "message": "Откроется на глубине %d" % int(row.get("unlock_depth", 0))}
	if not TechCost.can_act_here():
		return {"ok": false, "message": TechCost.reason_cannot()}
	if not bool(TechCost.check(n["cost"])["ok"]):
		return {"ok": false, "message": "Не хватает материалов"}
	TechCost.pay(n["cost"])
	TechState.set_suit(int(n["tier"]))
	GameState.emit_event(&"bought", {"id": String(row.get("id", "suit")), "currency": "coins"})
	SaveSystem.save_game()
	return {"ok": true, "message": String(row.get("name_ru", ""))}

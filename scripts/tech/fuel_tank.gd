class_name FuelTank
extends RefCounted
## Бак ручного бура и бурмобиля (ГДД п.5, п.9 «Заправка»).
##
## Топливо живёт в баке, а не в рюкзаке: блок весит (minerals.json → fuel_block),
## и запас блоков отнимал бы место у руды. Бак — вес, который не давит на героя; платой
## за это служит заправка: блоки заливают на станции в огороде (со склада и из
## рюкзака) или прямо в шахте из рюкзака, нажав на полоску топлива.
##
## Единица измерения — топливный блок (дробная). Расход за клетку лежит в
## balance.json (fuel_consumption.blocks_per_cell), ёмкость и цены баков — в
## data/tech.json.
##
## Пустой бак бурмобиля — копать нечем (решение владельца: глохнет под землёй),
## пустой бак ручного бура — бур вхолостую, герой копает киркой (скорость
## лучшей кирки, см. player.gd:_tool_speed_multiplier).

const EPS := 0.0001


static func uses_fuel(tool_id: String) -> bool:
	return (TechData.fuel().get("tools", []) as Array).has(tool_id)


static func block_item() -> String:
	return String(TechData.fuel().get("block_item", "fuel_block"))


static func tool_name(tool_id: String) -> String:
	return String(TechData.fuel().get("tanks", {}).get(tool_id, {}).get("name_ru", tool_id))


static func level(tool_id: String) -> int:
	return clampi(int(TechState.tank(tool_id).get("level", 0)), 0, max_level(tool_id))


static func max_level(tool_id: String) -> int:
	return maxi(0, capacities(tool_id).size() - 1)


static func capacities(tool_id: String) -> Array:
	var t: Dictionary = TechData.fuel().get("tanks", {}).get(tool_id, {})
	return TechData.v(t.get("capacity_blocks", [0.0]))


static func capacity(tool_id: String) -> float:
	var caps := capacities(tool_id)
	return float(caps[level(tool_id)]) if not caps.is_empty() else 0.0


static func fuel(tool_id: String) -> float:
	return clampf(float(TechState.tank(tool_id).get("fuel", 0.0)), 0.0, capacity(tool_id))


static func fraction(tool_id: String) -> float:
	var cap := capacity(tool_id)
	return fuel(tool_id) / cap if cap > 0.0 else 0.0


static func has_fuel(tool_id: String) -> bool:
	return fuel(tool_id) > EPS


static func is_low(tool_id: String) -> bool:
	var low := float(TechData.v(TechData.fuel().get("low_fuel_fraction", 0.2)))
	return fraction(tool_id) <= low


## Блоков на клетку (balance.json — число владельца/предложение прежней ветки).
static func rate_per_cell(tool_id: String) -> float:
	return float(TechData.bal(["fuel_consumption", "blocks_per_cell", tool_id], 0.0))


## Сколько клеток осталось в баке.
static func cells_left(tool_id: String) -> int:
	var r := rate_per_cell(tool_id)
	return int(floor(fuel(tool_id) / r + EPS)) if r > 0.0 else 0


## Выставить заправку напрямую (отладка и тесты); в пределах ёмкости.
static func set_fuel(tool_id: String, blocks: float) -> void:
	TechState.tank(tool_id)["fuel"] = clampf(blocks, 0.0, capacity(tool_id))


# ---------------------------------------------------------------------------
# Расход
# ---------------------------------------------------------------------------

## Клетка реально прокопана инструментом на топливе — сжигаем. Возвращает,
## сколько блоков сгорело (бак не уходит в минус).
static func burn_cell(tool_id: String) -> float:
	if not uses_fuel(tool_id):
		return 0.0
	var rate := rate_per_cell(tool_id)
	var have := fuel(tool_id)
	if rate <= 0.0 or have <= 0.0:
		return 0.0
	var burned := minf(rate, have)
	var left := have - burned
	if left < EPS:
		left = 0.0
	TechState.tank(tool_id)["fuel"] = left
	GameState.emit_event(&"fuel_used", {"amount": burned, "tool": tool_id, "left": left})
	return burned


# ---------------------------------------------------------------------------
# Заправка
# ---------------------------------------------------------------------------

## Целых блоков, которые ещё влезут в бак (дробный хвост не льём: пролитое — зря).
static func room_blocks(tool_id: String) -> int:
	return maxi(0, int(floor(capacity(tool_id) - fuel(tool_id) + EPS)))


static func in_pack() -> int:
	return GameState.get_item_count(block_item())


static func in_storage() -> int:
	return HouseStorage.count(block_item())


## Залить блоки. source — "pack" (рюкзак, откуда угодно) или "storage"
## (склад, только на станции — доступ проверяет вызывающий). amount < 0 —
## сколько влезет. Возвращает, сколько блоков залито.
static func refuel(tool_id: String, source: String, amount: int = -1) -> int:
	if not uses_fuel(tool_id):
		return 0
	var room := room_blocks(tool_id)
	var avail := in_pack() if source == "pack" else in_storage()
	var n := mini(room, avail)
	if amount >= 0:
		n = mini(n, amount)
	if n <= 0:
		return 0
	if source == "pack":
		GameState.remove_item(block_item(), n)
	else:
		HouseStorage.consume(block_item(), n)
	var left := minf(fuel(tool_id) + float(n), capacity(tool_id))
	TechState.tank(tool_id)["fuel"] = left
	GameState.emit_event(&"refueled", {"amount": float(n), "tool": tool_id, "source": source, "left": left})
	return n


# ---------------------------------------------------------------------------
# Уровни бака
# ---------------------------------------------------------------------------

## Цена следующего уровня или null, если бак уже максимальный.
static func next_cost(tool_id: String):
	var lv := level(tool_id)
	if lv >= max_level(tool_id):
		return null
	var costs = TechData.v(TechData.fuel().get("tanks", {}).get(tool_id, {}).get("upgrade_cost", []))
	return costs[lv] if lv < costs.size() else null


## {ok, message}. Бак растёт сразу, но прирост пуст: топливо заливают отдельно.
static func upgrade(tool_id: String) -> Dictionary:
	if not uses_fuel(tool_id):
		return {"ok": false, "message": "Нет такого бака"}
	var cost = next_cost(tool_id)
	if cost == null:
		return {"ok": false, "message": "Бак уже максимальный"}
	if not TechCost.can_act_here():
		return {"ok": false, "message": TechCost.reason_cannot()}
	if not bool(TechCost.check(cost)["ok"]):
		return {"ok": false, "message": "Не хватает материалов"}
	TechCost.pay(cost)
	TechState.tank(tool_id)["level"] = level(tool_id) + 1
	TechState.touch()
	GameState.emit_event(&"bought", {"id": "tank_" + tool_id, "currency": "coins"})
	SaveSystem.save_game()
	return {"ok": true, "message": "Бак растёт"}

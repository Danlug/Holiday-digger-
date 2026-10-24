class_name FuelRefinery
extends RefCounted
## Перегонка на станции заправки: торф и уголь -> топливные блоки (решение
## владельца, раунд 3: «пусть переработка торфа в топливо будет на заправочной
## станции, а не в магазине»). Станция в огороде = перегонка + заправка в одном
## месте; рецептов блока на верстаке больше нет (ГДД п.5, «Станция: перегонка и
## заправка»).
##
## Пропорции — числа владельца в balance.json (fuel_consumption.<сырьё>_per_fuel_block:
## торф 4:1, уголь 2:1 proposed); порядок сырья и глубина, с которой показывается
## уголь, — data/tech.json → refinery. Своего сохраняемого состояния нет: сырьё и
## блоки лежат в рюкзаке и на складе, которые и так входят в сейв.
##
## Откуда и куда. Сырьё берётся сначала из рюкзака (принёс — значит, сюда), потом
## со склада. Блок ложится туда, откуда пришло его сырьё: из рюкзачного торфа — в
## рюкзак (он легче торфа, вес только падает; не влезло в стопку — на склад), из
## складского — на склад. Станция не становится чёрным ходом со склада в рюкзак
## (ГДД п.14: «взять — только подойдя»), а заливать в бак со склада у станции можно
## и так (FuelTank.refuel, source "storage").
##
## Доступ («только у станции») проверяет вызывающий — как у FuelTank.refuel со
## склада: экран знает, открыт ли он у станции.


static func data() -> Dictionary:
	return TechData.data().get("refinery", {})


## Сырьё в порядке показа: ["peat", "coal"].
static func inputs() -> Array:
	var out: Array = []
	for row in (data().get("inputs", []) as Array):
		if typeof(row) == TYPE_DICTIONARY and String(row.get("id", "")) != "":
			out.append(String(row["id"]))
	if out.is_empty():
		out = ["peat", "coal"]
	return out


static func _row(raw: String) -> Dictionary:
	for row in (data().get("inputs", []) as Array):
		if typeof(row) == TYPE_DICTIONARY and String(row.get("id", "")) == raw:
			return row
	return {}


static func is_input(raw: String) -> bool:
	return inputs().has(raw)


## Сколько сырья идёт на один блок (balance.json, число владельца для торфа).
static func per_block(raw: String) -> int:
	return maxi(1, int(TechData.bal(["fuel_consumption", "%s_per_fuel_block" % raw], 0)))


static func unlock_depth(raw: String) -> int:
	return int(TechData.v(_row(raw).get("unlock_depth", 0)))


## Открыто ли сырьё: по рекорду глубины или раз оно уже на руках (скважина
## может принести уголь на склад раньше, чем герой сам до него докопался).
static func is_unlocked(raw: String) -> bool:
	return is_input(raw) and (GameState.max_depth_reached >= unlock_depth(raw) or held(raw) > 0)


static func block_item() -> String:
	return FuelTank.block_item()


static func in_pack(raw: String) -> int:
	return GameState.get_item_count(raw)


static func in_storage(raw: String) -> int:
	return HouseStorage.count(raw)


## Рюкзак + склад: «показать — везде» (ГДД п.14).
static func held(raw: String) -> int:
	return in_pack(raw) + in_storage(raw)


## Сколько блоков можно перегнать прямо сейчас.
static func max_blocks(raw: String) -> int:
	if not is_input(raw):
		return 0
	return held(raw) / per_block(raw)


## Станция стоит: после сцены заправки (флаг сюжета) — или раз у героя уже есть
## техника на топливе. Вторая половина — страховка от тупика «бур есть, станции
## нет» для сейвов, где сцена почему-то не сыграла (в обычной игре сцена идёт на
## той же сотой метке, что открывает рецепт бура, — см. тест test_softlock).
static func station_built() -> bool:
	if GameState.era == "grandpa":
		return false
	if StoryState.has_flag("fuel_station_built"):
		return true
	for tool_id in (TechData.fuel().get("tools", []) as Array):
		if GameState.owns_tool(String(tool_id)):
			return true
	return false


## Перегнать blocks блоков из сырья raw. Возвращает
## {ok, made, used, used_pack, used_storage, to_pack, to_storage, reason}.
## Без сырья ничего не трогает.
static func refine(raw: String, blocks: int) -> Dictionary:
	var res := {"ok": false, "made": 0, "used": 0, "used_pack": 0, "used_storage": 0,
		"to_pack": 0, "to_storage": 0, "reason": ""}
	if not is_input(raw):
		res["reason"] = "Это не перегоняется"
		return res
	if not station_built():
		res["reason"] = "Станции ещё нет"
		return res
	if not is_unlocked(raw):
		res["reason"] = "Откроется на глубине %d" % unlock_depth(raw)
		return res
	var per := per_block(raw)
	var n := mini(blocks, max_blocks(raw))
	if blocks <= 0 or n <= 0:
		res["reason"] = "Мало сырья: нужно %d на блок" % per
		return res
	var need := n * per
	var from_pack := mini(need, in_pack(raw))
	var from_storage := need - from_pack
	if from_pack > 0 and not GameState.remove_item(raw, from_pack):
		res["reason"] = "Сырьё кончилось"
		return res
	if from_storage > 0:
		HouseStorage.consume(raw, from_storage)
	# Блок, целиком сделанный из рюкзачного сырья, — в рюкзак; смешанный и складской — на склад.
	var for_pack := from_pack / per
	var to_pack := GameState.add_item(block_item(), for_pack) if for_pack > 0 else 0
	var to_storage := n - to_pack
	if to_storage > 0:
		HouseStorage.store_directly(block_item(), to_storage)
	res["ok"] = true
	res["made"] = n
	res["used"] = need
	res["used_pack"] = from_pack
	res["used_storage"] = from_storage
	res["to_pack"] = to_pack
	res["to_storage"] = to_storage
	GameState.emit_event(&"fuel_refined", {"raw": raw, "used": need, "blocks": n,
		"to_pack": to_pack, "to_storage": to_storage})
	return res

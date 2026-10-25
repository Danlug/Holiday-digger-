class_name Equipment
extends RefCounted
## Equipment — верстак в мастерской, он же ЭКИПИРОВКА (решение владельца).
##
## Владелец развёл два места по смыслу:
##   магазин у входной двери — только продаёт и покупает;
##   верстак в мастерской — выбираешь, какой киркой копать и какой ранец
##   надеть из УЖЕ КУПЛЕННЫХ; туда же со временем уйдут улучшения и починка.
##
## Здесь только логика, без единого узла интерфейса — ровно по той же причине,
## что и в ShopService: «купил обсидиановую кирку — копка ускорилась в пять
## раз» обязано проверяться headless-тестом, а не кликами по кнопкам. Показ
## живёт в scripts/shop/shop_ui.gd (экран SCREEN_EQUIP).
##
## Своего состояния у верстака НЕТ: что куплено, лежит в GameState
## (owned_tools / owned_gear), что надето — в current_tool / current_gear.
## Второй список «что на верстаке» разъехался бы с первым при первой покупке.


# ---------------------------------------------------------------------------
# Где работает
# ---------------------------------------------------------------------------

## Верстак стоит в мастерской, в подвале дома (ГДД п.5). Переодеться посреди
## шахты нельзя: смена кирки и ранца — это заход домой, а не кнопка на поясе.
static func is_at_workbench() -> bool:
	return ShopService.is_at_workshop()


# ---------------------------------------------------------------------------
# Кирки
# ---------------------------------------------------------------------------

## Все ступени кирок с пометкой, что из них есть у игрока и что в руках.
## Строка каталога плюс {owned, active}. Показываем ВСЮ линейку, а не только
## купленное: верстак заодно отвечает на вопрос «а что дальше и почём».
static func pickaxe_rows() -> Array:
	var out: Array = []
	for row in ShopCatalog.pickaxes():
		var id := String(row["id"])
		var r: Dictionary = row.duplicate()
		r["owned"] = GameState.owns_tool(id)
		r["active"] = GameState.current_tool == id
		out.append(r)
	return out


## Взять кирку в руки. Возвращает {ok, message}.
static func equip_tool(tool_id: String) -> Dictionary:
	if Balance.get_tool(tool_id).is_empty():
		return {"ok": false, "message": "Такого инструмента нет"}
	if not is_at_workbench():
		return {"ok": false, "message": "Верстак дома, в подвале"}
	if not GameState.owns_tool(tool_id):
		return {"ok": false, "message": "Этого ещё нет — купи в магазине"}
	if GameState.current_tool == tool_id:
		return {"ok": false, "message": "Уже в руках"}
	GameState.set_current_tool(tool_id)
	SaveSystem.save_game()
	return {"ok": true, "message": "В руках: %s." % Balance.get_tool_name_ru(tool_id)}


# ---------------------------------------------------------------------------
# Ранцы
# ---------------------------------------------------------------------------

## Все четыре ступени ранца с пометкой, что куплено и что надето.
static func gear_rows() -> Array:
	var out: Array = []
	for row in ShopCatalog.gear_line():
		var id := String(row["id"])
		var r: Dictionary = row.duplicate()
		r["owned"] = GameState.has_gear(id)
		r["active"] = GameState.current_gear == id
		out.append(r)
	return out


## Надеть ранец. Возвращает {ok, message}.
static func equip_gear(gear_id: String) -> Dictionary:
	if Balance.get_gear(gear_id).is_empty():
		return {"ok": false, "message": "Такого ранца нет"}
	if not is_at_workbench():
		return {"ok": false, "message": "Верстак дома, в подвале"}
	if not GameState.has_gear(gear_id):
		return {"ok": false, "message": "Этого ещё нет — купи в магазине"}
	if GameState.current_gear == gear_id:
		return {"ok": false, "message": "Уже надет"}
	if not GameState.set_current_gear(gear_id):
		return {"ok": false, "message": "Не получилось надеть"}
	SaveSystem.save_game()
	return {"ok": true, "message": "Надет: %s." % Balance.get_gear_name_ru(gear_id)}


# ---------------------------------------------------------------------------
# Характеристики надетого — одной строкой для шапки экрана
# ---------------------------------------------------------------------------

## Множитель скорости копки, который герой получает ПРЯМО СЕЙЧАС: ступень
## кирки плюс общий темп игры. Треснувшую дедову кирку сюда не заводим — её
## трещина живёт в player.gd и в сейве не хранится (см. отчёт).
static func current_dig_multiplier() -> float:
	return Balance.get_tool_speed_multiplier(GameState.current_tool)


## Потолок скорости подъёма надетого ранца, клеток в секунду. 0 — летать
## нечем.
static func current_fly_speed() -> float:
	return Balance.get_gear_max_speed(GameState.current_gear)

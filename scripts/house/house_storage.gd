class_name HouseStorage
extends RefCounted
## HouseStorage — склад в мастерской (ГДД п.14, «Склад в мастерской»).
##
## Зачем он есть: железная кирка стоит 25 железа, 10 бронзы и 30 свинца —
## 160 кг при рюкзаке в 60. За одну ходку это не принести, и без места, где
## копить принесённое, ступени инструментов недостижимы в принципе.
##
## Правило доступа — «показать везде, взять только подойдя»:
##   contents() читается откуда угодно, хоть со дна шахты — игрок должен
##   планировать вылазку, зная, чего ему не хватает до кирки;
##   put()/take() работают только у самого склада, в мастерской.
## Иначе рюкзак перестаёт быть ограничением, спуск — решением, а подъём на
## поверхность — событием: со дна шахты нельзя ни продать, ни достать со
## склада, это одна и та же линия.
##
## Склад НЕ теряется при смерти: теряется только рюкзак (ГДД п.7) — склад
## хранит то, что ты уже донёс.

## Комната, в которой стоит склад. Верстак там же, в двух шагах (ГДД п.14).
const ROOM := "workshop"


static func contents() -> Dictionary:
	return GameState.house_storage


static func count(id: String) -> int:
	return int(GameState.house_storage.get(id, 0))


## Сколько всего единиц лежит на складе (для шапки панели).
static func total_items() -> int:
	var total := 0
	for id in GameState.house_storage.keys():
		total += int(GameState.house_storage[id])
	return total


## Вес содержимого. На складе он ничего не ограничивает — это справка,
## по которой видно, сколько ходок ушло бы, чтобы унести это в рюкзаке.
static func total_weight() -> float:
	var total := 0.0
	for id in GameState.house_storage.keys():
		total += Balance.get_mineral_weight(String(id)) * int(GameState.house_storage[id])
	return total


## Стоит ли герой у самого склада. Только в этом случае можно класть и брать.
static func can_access() -> bool:
	return GameState.house_is_indoors and GameState.house_room == ROOM


static func access_reason() -> String:
	if can_access():
		return ""
	if GameState.house_is_indoors:
		return "Склад в мастерской — спустись в подвал."
	return "Отсюда склад только видно. Класть и забирать — дома, в мастерской."


# ---------------------------------------------------------------------------
# Положить и забрать
# ---------------------------------------------------------------------------

## Рюкзак -> склад. Возвращает, сколько единиц переложено.
static func put(id: String, amount: int) -> int:
	if not can_access() or amount <= 0:
		return 0
	var moved: int = mini(amount, GameState.get_item_count(id))
	if moved <= 0:
		return 0
	GameState.remove_item(id, moved)
	GameState.house_storage[id] = count(id) + moved
	GameState.emit_event(&"stored", {"item": id, "count": moved, "dir": "put"})
	return moved


## Припас — то, что остаётся с героем: без еды, аптечки и топлива копать дальше нельзя.
## Еда и лекарства узнаются по category в data/minerals.json (food / medical), топливо — по id.
static func is_supply(id: String) -> bool:
	if id == "fuel_block" or HouseConfig.is_food(id) or Healing.is_medkit(id):
		return true
	return ["food", "medical"].has(String(Balance.get_mineral(id).get("category", "")))


## Что уносят разом «Переложить всё» и премиум-выгрузка: только руды и ресурсы из
## data/minerals.json. Припас и прочий инвентарь (батарейки и т.п.) остаются в рюкзаке —
## по одному их всё ещё можно положить через окно количества.
static func is_haul(id: String) -> bool:
	return not Balance.get_mineral(id).is_empty() and not is_supply(id)


## Выгрузить из рюкзака все руды и ресурсы. Возвращает, сколько единиц переложено.
static func put_all() -> int:
	if not can_access():
		return 0
	var moved := 0
	for id in GameState.inventory.keys().duplicate():
		if is_haul(String(id)):
			moved += put(String(id), GameState.get_item_count(String(id)))
	return moved


## Склад -> рюкзак. Ограничено грузоподъёмностью: склад тем и отличается от
## рюкзака, что на спине его не унести. Возвращает реально взятое количество.
static func take(id: String, amount: int) -> int:
	if not can_access() or amount <= 0:
		return 0
	var available: int = mini(amount, count(id))
	var taken := 0
	while taken < available:
		if GameState.add_item(id, 1) <= 0:
			break
		taken += 1
	if taken > 0:
		_remove(id, taken)
		GameState.emit_event(&"stored", {"item": id, "count": taken, "dir": "take"})
	return taken


## Сколько единиц id реально влезет в рюкзак прямо сейчас (стопка и вес — те
## же правила, что у GameState.add_item). Нужно окну «сколько»: ползунок не
## должен обещать больше, чем take() сможет взять.
static func max_takeable(id: String) -> int:
	var want := count(id)
	if want <= 0:
		return 0
	var room_by_stack: int = maxi(0, Balance.get_mineral_max_stack(id) - GameState.get_item_count(id))
	var weight_each := Balance.get_mineral_weight(id)
	var room_by_weight := want
	if weight_each > 0.0:
		var free_weight: float = GameState.get_max_carry_kg() - GameState.get_total_weight()
		room_by_weight = int(floor(free_weight / weight_each)) if free_weight > 0.0 else 0
	return mini(want, mini(room_by_stack, room_by_weight))


## Забрать всё, что влезет: по позициям от тяжёлых к лёгким (порядок rows()).
## Возвращает, сколько единиц переложено.
static func take_all() -> int:
	if not can_access():
		return 0
	var moved := 0
	for row in rows():
		moved += take(String(row["id"]), int(row["count"]))
	return moved


## Списать со склада напрямую, без рюкзака — этим верстак берёт материалы при
## сборке (ГДД п.14: склад стоит рядом, перекладывать руду в рюкзак ради
## крафта бессмысленно). Возвращает, сколько списано.
static func consume(id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var taken: int = mini(amount, count(id))
	if taken > 0:
		_remove(id, taken)
	return taken


## Положить на склад мимо рюкзака — для систем, которые кладут туда добычу
## сами (например, дистанционная сдача лута). Доступ не проверяется: вызов
## идёт не от пальца игрока, а от уже разрешённой механики.
static func store_directly(id: String, amount: int) -> void:
	if amount > 0:
		GameState.house_storage[id] = count(id) + amount


static func _remove(id: String, amount: int) -> void:
	var left := count(id) - amount
	if left > 0:
		GameState.house_storage[id] = left
	else:
		GameState.house_storage.erase(id)


## Строки для панели склада: [{id, name, count, weight}], тяжёлое сверху —
## именно тяжёлое и определяет, сколько ходок ушло на эту кучу.
static func rows() -> Array:
	var out: Array = []
	for id in GameState.house_storage.keys():
		var n := int(GameState.house_storage[id])
		if n <= 0:
			continue
		out.append({
			"id": String(id),
			"name": String(Balance.get_mineral(String(id)).get("name_ru", id)),
			"count": n,
			"weight": Balance.get_mineral_weight(String(id)) * n,
		})
	out.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	return out

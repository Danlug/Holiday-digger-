class_name HouseConfig
extends RefCounted
## HouseConfig — числа системы дома из data/balance.json (блоки "house" и
## "food"). Отдельный модуль, а не разбросанные по коду константы: всё, что
## ещё не утверждено владельцем, лежит в JSON с пометкой proposed, и правка
## баланса не должна требовать правки логики.
##
## Все геттеры имеют запасное значение: если блок в JSON затёрли или файл не
## загрузился, дом обязан остаться проходимым — иначе игрок запирается в
## огороде без еды и сна, то есть ровно в той дыре, ради которой этот модуль
## и написан.

static func _house() -> Dictionary:
	return Balance.balance.get("house", {})


static func _food() -> Dictionary:
	return Balance.balance.get("food", {})


static func _cell(node, fallback: Vector2i) -> Vector2i:
	var v = Balance.unwrap(node)
	if typeof(v) != TYPE_ARRAY or (v as Array).size() < 2:
		return fallback
	return Vector2i(int(v[0]), int(v[1]))


## Клетка входной двери на поверхности (ГДД п.3 задаёт только диапазон дома
## 0–14; конкретная клетка — предложение, см. note в balance.json).
static func door_cell() -> Vector2i:
	return _cell(_house().get("door_cell", null), Vector2i(12, 0))


## Устье тоннеля Роберта В КООРДИНАТАХ ДВИЖКА — верхняя клетка бетонного
## колодца, которым он заменил лестницу (решение владельца: люк отменён,
## единственный вход в копальню — тоннель по клетке 17).
##
## Настоящий хозяин этой геометрии — scripts/world/world_gen.gd
## (WorldGen.TUNNEL_X и world.tunnel_mouth()): дом спрашивает мир, а сюда
## заглядывает, только когда мира ещё нет. Поэтому значение и запасное:
## разъехаться они не должны, но падать из-за отсутствия мира дом не имеет
## права — иначе игрок запирается в доме без входа в шахту.
static func tunnel_mouth_cell() -> Vector2i:
	return _cell(_house().get("tunnel_mouth_cell", null), Vector2i(17, 1))


## Старое имя времён люка. Отдаёт устье тоннеля: люка больше нет, а чужой
## код и старые вызовы должны получать актуальный вход в шахту, а не клетку,
## которой уже не существует.
static func hatch_cell() -> Vector2i:
	return tunnel_mouth_cell()


## Радиус, в котором появляется кнопка входа в дом и срабатывает устье тоннеля.
static func interact_radius() -> float:
	return float(Balance.unwrap(_house().get("interact_radius_cells", 1.2)))


## Насколько должна просесть бодрость, чтобы кровать пустила спать.
static func sleep_min_deficit_percent() -> float:
	return float(Balance.unwrap(_house().get("sleep_min_deficit_percent", 10.0)))


## Во сколько раз медленнее тратится голод во сне по сравнению с обычным
## простоем (см. note в balance.json: 0 — кровать бесплатна, 1 — полный сон
## убивает спящего).
static func sleep_hunger_factor() -> float:
	return float(Balance.unwrap(_house().get("sleep_hunger_factor", 0.5)))


## Сколько РЕАЛЬНЫХ секунд идёт анимация у кровати (решение владельца:
## «спит быстро, буквально 10 секунд, показывая анимацию»), прежде чем
## применится сам эффект сна (HouseSleep.sleep_now — его числа этот таймер
## не трогает, только откладывает их применение на длину ролика).
static func sleep_animation_seconds() -> float:
	return float(Balance.unwrap(_house().get("sleep_animation_seconds", 10.0)))


# ---------------------------------------------------------------------------
# Еда
# ---------------------------------------------------------------------------

static func delivery_seconds() -> float:
	return float(Balance.unwrap(_food().get("delivery_seconds", 5.0)))


static func free_orders_per_day() -> int:
	return int(Balance.unwrap(_food().get("free_orders_per_day", 3)))


## Все расходники (доставка, магазин, донат) — id, эффект, цена.
static func food_items() -> Array:
	return _food().get("items", [])


static func food_item(id: String) -> Dictionary:
	for item in food_items():
		if String(item.get("id", "")) == id:
			return item
	return {}


## Только то, что можно заказать домой (ГДД п.7: заказ из дома, доставка к
## входной двери). Допинги из магазина сюда не попадают — их продаёт магазин.
static func delivery_menu() -> Array:
	var out: Array = []
	for item in food_items():
		if String(item.get("source", "")) == "delivery":
			out.append(item)
	return out


## Можно ли унести порцию на вылазку (решение владельца: стейк и пельмени —
## нельзя). Непереносимая еда съедается сразу при заказе, дома, и в рюкзак не
## кладётся: нести её некуда, а значит и доставлять к двери незачем.
static func is_portable(id: String) -> bool:
	return bool(Balance.unwrap(food_item(id).get("portable", true)))


static func is_food(id: String) -> bool:
	return not food_item(id).is_empty()


static func food_name(id: String) -> String:
	var item := food_item(id)
	if item.has("name_ru"):
		return String(item["name_ru"])
	return String(Balance.get_mineral(id).get("name_ru", id))


static func food_hunger_percent(id: String) -> float:
	return float(Balance.unwrap(food_item(id).get("hunger_percent", 0.0)))


static func food_stamina_percent(id: String) -> float:
	return float(Balance.unwrap(food_item(id).get("stamina_percent", 0.0)))


static func food_price_coins(id: String) -> int:
	return int(Balance.unwrap(food_item(id).get("price_coins", 0)))

class_name IdleWell
## Буровая скважина — единственная idle-механика в игре (ГДД п.1).
##
## Платит РЕСУРСАМИ И ЗОЛОТОМ, но никогда донатной валютой (решение
## владельца): премиум-валюта, капающая сама, обесценивает и себя, и покупку.
## Скважина буровая — значит, она копает; и отдаёт то же, что игрок выкопал бы
## сам на её глубине, а не абстрактные монеты.
##
## Добытое складывается НА СКЛАД, а не в рюкзак: рюкзак — это то, что герой
## несёт на себе, а скважина стоит у дома (ГДД п.14).

## Формула дохода из balance.json считает монеты в час. Монеты — только мера:
## на них подбирается корзина руды такой же стоимости, и в руки игроку идёт
## руда. Так «доход скважины» остаётся одним числом в балансе, а на экране
## всё равно оказывается добыча.
static func income_coins_for_seconds(seconds: float) -> int:
	if not is_built() or seconds <= 0.0:
		return 0
	var w: Dictionary = Balance.balance.get("idle_well", {})
	var base: float = float(Balance.unwrap(w.get("base_income_coins_per_hour", 50)))
	var cap_h: float = float(Balance.unwrap(w.get("offline_cap_hours", 8)))
	var hours: float = minf(seconds / 3600.0, cap_h)
	var depth_factor: float = 1.0 + float(GameState.max_depth_reached) / 100.0
	var level_factor: float = 1.0 + 0.1 * float(GameState.well_level)
	return int(floor(base * hours * depth_factor * level_factor))


static func is_built() -> bool:
	return GameState.well_level > 0


## Сколько секунд скважина работала с прошлого забора. Первый запуск не
## считается: иначе игрок, впервые собравший скважину, тут же получил бы
## доход за всё время, что он играл до неё.
static func pending_seconds() -> float:
	if not is_built() or GameState.well_last_collect_unix <= 0:
		return 0.0
	return maxf(0.0, float(Time.get_unix_time_from_system() - GameState.well_last_collect_unix))


## Забрать накопленное: кладёт добычу на склад и возвращает отчёт
## {"seconds": float, "items": {id: count}, "coins_value": int}.
## Пустой словарь — забирать нечего.
static func collect() -> Dictionary:
	var seconds := pending_seconds()
	GameState.well_last_collect_unix = int(Time.get_unix_time_from_system())
	var value := income_coins_for_seconds(seconds)
	if value <= 0:
		return {}
	var items := _basket_for_value(value)
	if items.is_empty():
		return {}
	for id in items.keys():
		GameState.house_storage[id] = int(GameState.house_storage.get(id, 0)) + int(items[id])
	return {"seconds": seconds, "items": items, "coins_value": value}


## Сколько РАЗНЫХ минералов может попасть в один отчёт. Список из десяти
## строк читается как накладная, а не как находка.
const MAX_KINDS := 4


## Корзина руды на заданную сумму. Берём то, что встречается на достигнутой
## глубине, от дорогого к дешёвому — так отчёт читается как «накопала чего-то
## стоящего», а не как гора земли. Золото в списке всегда: владелец назвал его
## отдельно, и оно же — самая узнаваемая строка в отчёте.
static func _basket_for_value(value: int) -> Dictionary:
	var pool := _minable_ids()
	if pool.is_empty():
		return {}
	var out: Dictionary = {}
	var left := value
	for id in pool:
		if out.size() >= MAX_KINDS:
			break
		var price: int = maxi(1, Balance.get_mineral_price(id))
		if price > left:
			continue
		# Не больше половины остатка одним минералом: иначе вся корзина
		# схлопывается в один самый дорогой камень.
		var count: int = maxi(1, int(floor(float(left) * 0.5 / float(price))))
		out[id] = int(out.get(id, 0)) + count
		left -= count * price
		if left <= 0:
			break
	# Остаток досыпаем самым дешёвым из уже набранного, чтобы отчёт сходился
	# с обещанной суммой, а не обрывался на «почти».
	if left > 0 and not out.is_empty():
		var cheapest: String = ""
		for id in out.keys():
			if cheapest.is_empty() or Balance.get_mineral_price(id) < Balance.get_mineral_price(cheapest):
				cheapest = String(id)
		var price2: int = maxi(1, Balance.get_mineral_price(cheapest))
		out[cheapest] = int(out[cheapest]) + int(ceil(float(left) / float(price2)))
	return out


## Что скважина вообще может достать: руды, чей слой начинается не глубже
## достигнутой игроком глубины. Порядок — от дорогой к дешёвой.
static func _minable_ids() -> Array:
	var depth: int = maxi(GameState.max_depth_reached, 1)
	var rows: Array = []
	for m in Balance.minerals.get("minerals", []):
		var id := String(m.get("id", ""))
		if id.is_empty() or id in ["earth", "stone"]:
			continue
		var sellable = Balance.unwrap(m.get("sellable", true))
		if typeof(sellable) == TYPE_BOOL and not sellable:
			continue
		# Скважина именно КОПАЕТ: выплавленное и собранное (бронза, топливные
		# блоки) она произвести не может, как бы дорого оно ни стоило.
		# Проверяем и категорию, и профиль плотности: у бронзы ключ density
		# есть, но лежит в нём null — одной проверки has() не хватает.
		if String(m.get("category", "")) == "crafted":
			continue
		if m.get("density", null) == null:
			continue
		# depth_min у части минералов записан не числом, а обёрткой
		# {value, proposed} или вовсе null — приводим бережно, иначе на
		# первом же таком минерале падает конструктор int().
		var dmin := _as_int(Balance.unwrap(m.get("depth_min", 1)), 1)
		if dmin > depth:
			continue
		rows.append({"id": id, "price": Balance.get_mineral_price(id)})
	rows.sort_custom(func(a, b): return int(a["price"]) > int(b["price"]))
	var out: Array = []
	for r in rows:
		out.append(String(r["id"]))
	return out


## Бережное приведение к целому: в minerals.json числа местами обёрнуты в
## {value, proposed}, а местами просто null.
static func _as_int(value, fallback: int) -> int:
	match typeof(value):
		TYPE_INT: return value
		TYPE_FLOAT: return int(value)
		TYPE_STRING: return int(String(value)) if String(value).is_valid_int() else fallback
		_: return fallback

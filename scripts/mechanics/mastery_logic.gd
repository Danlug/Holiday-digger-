class_name MasteryLogic
extends RefCounted
## Мастерство руд: пять звёзд у каждой добываемой породы за число выкопанных
## клеток. Пороги зависят от цены (дешёвое копают тысячами, уран — десятками),
## поэтому у каждой руды звёзды приходят в своём темпе, и журнал всё время
## показывает, к чему ты близко. Чистые функции; состояние — MechState.

const MAX_STARS := 5


static func kinds() -> Array:
	return MechData.section("mastery").get("kinds", [])


static func is_kind(id: String) -> bool:
	return kinds().has(id)


## Класс порогов по цене: cheap / mid / precious.
static func price_class(id: String) -> String:
	var price := Balance.get_mineral_price(id)
	if price <= 0:
		return "mid"   # материалы без цены (экзотика, всё глубже 4000) — редкие, но не самоцветы
	if price >= int(MechData.num("mastery", "price_precious", 300)):
		return "precious"
	if price >= int(MechData.num("mastery", "price_mid", 30)):
		return "mid"
	return "cheap"


static func thresholds(id: String) -> Array:
	var t: Dictionary = MechData.section("mastery").get("thresholds", {})
	var row = MechData.value(t.get(price_class(id), null), [])
	if typeof(row) != TYPE_ARRAY or row.is_empty():
		return [10, 40, 150, 500, 1500]
	return row


static func stars_for(id: String, count: int) -> int:
	var s := 0
	for th in thresholds(id):
		if count >= int(th):
			s += 1
	return mini(s, MAX_STARS)


## Порог следующей звезды (0 — все пять собраны).
static func next_threshold(id: String, count: int) -> int:
	for th in thresholds(id):
		if count < int(th):
			return int(th)
	return 0


## Порог предыдущей звезды (для полосы прогресса между звёздами).
static func prev_threshold(id: String, count: int) -> int:
	var prev := 0
	for th in thresholds(id):
		if count >= int(th):
			prev = int(th)
	return prev


## Шанс двойной добычи этой руды на stars звёздах.
static func double_chance(stars: int) -> float:
	return MechData.num("mastery", "chance_per_star", 0.02) * float(clampi(stars, 0, MAX_STARS))


## Опыт за звезду star (1..5): четверть опыта за все клетки до её порога.
static func star_xp(id: String, star: int) -> int:
	var th: Array = thresholds(id)
	if star < 1 or star > th.size():
		return 0
	var cell_xp := ChestLogic.item_xp(id)
	var xp := int(round(float(th[star - 1]) * cell_xp * MechData.num("mastery", "xp_per_star", 0.25)))
	return maxi(xp, int(MechData.num("mastery", "min_star_xp", 10)))


## Сколько пород журнала уже найдено.
static func discovered_count() -> int:
	var n := 0
	for id in kinds():
		if MechState.mastery_count(String(id)) > 0:
			n += 1
	return n


static func total_stars() -> int:
	var n := 0
	for id in kinds():
		n += stars_for(String(id), MechState.mastery_count(String(id)))
	return n

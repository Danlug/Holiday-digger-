class_name IdleWell
## Буровая скважина — единственная idle-механика в игре (ГДД п.1).
##
## Платит РЕСУРСАМИ, а мерой служат монеты; донатной валютой — никогда
## (решение владельца): премиум-валюта, капающая сама, обесценивает и себя, и
## покупку. Скважина буровая — значит, копает; и отдаёт то же, что игрок выкопал
## бы сам на её глубине, а не абстрактные монеты.
##
## Добытое складывается НА СКЛАД, а не в рюкзак: рюкзак — это то, что герой
## несёт на себе, а скважина стоит у дома (ГДД п.14).
##
## Доход в час = база(balance.json) × (1 + глубина/100) × множитель ступени,
## где глубина — min(рекорд игрока, глубина ступени). Ступени (data/tech.json →
## well.levels) поднимают три вещи разом: на какой глубине копает скважина,
## множитель дохода и офлайн-кап. Расчёт окупаемости — tools/sim_tech.py.
##
## Часы телефона: накопление считается по реальному времени, поэтому от
## перемотки есть защита — отметка «видел время» и офлайн-кап (см. pending_seconds).
## Локально от перемотки ВПЕРЁД между запусками не спастись; это закрывает
## серверная синхронизация (ГДД п.1), здесь выплата ограничена капом.

## Сколько РАЗНЫХ минералов может попасть в один отчёт. Список из десяти
## строк читается как накладная, а не как находка.
const MAX_KINDS := 4

static var _probe_world: WorldGen = null


# ---------------------------------------------------------------------------
# Ступени
# ---------------------------------------------------------------------------

static func is_built() -> bool:
	return GameState.well_level > 0


static func levels() -> Array:
	return TechData.v(TechData.well().get("levels", []))


static func max_level() -> int:
	return levels().size()


## Строка ступени (1..max_level) или пустой словарь.
static func level_row(level: int) -> Dictionary:
	var rows := levels()
	return rows[level - 1] if level >= 1 and level <= rows.size() else {}


static func mult(level: int = -1) -> float:
	var l := GameState.well_level if level < 0 else level
	return float(level_row(l).get("mult", 1.0))


static func depth_cap(level: int = -1) -> int:
	var l := GameState.well_level if level < 0 else level
	return int(level_row(l).get("depth_cap", 100))


static func cap_hours(level: int = -1) -> float:
	var l := GameState.well_level if level < 0 else level
	return float(level_row(l).get("cap_hours", 8.0))


## Глубина, на которой скважина копает прямо сейчас.
static func effective_depth(level: int = -1) -> int:
	return mini(GameState.max_depth_reached, depth_cap(level))


static func base_income() -> float:
	var w: Dictionary = Balance.balance.get("idle_well", {})
	return float(Balance.unwrap(w.get("base_income_coins_per_hour", 50)))


## Монет-эквивалента в час (мера дохода; платят рудой).
static func income_per_hour(level: int = -1) -> float:
	if not is_built() and level < 0:
		return 0.0
	return base_income() * (1.0 + float(effective_depth(level)) / 100.0) * mult(level)


## Цена следующей ступени или null (максимум / не построена).
static func next_cost():
	var next := GameState.well_level + 1
	if not is_built() or next > max_level():
		return null
	return level_row(next).get("cost", {})


static func income_coins_for_seconds(seconds: float) -> int:
	if not is_built() or seconds <= 0.0:
		return 0
	var hours: float = minf(seconds / 3600.0, cap_hours())
	return int(floor(income_per_hour() * hours))


# ---------------------------------------------------------------------------
# Время и защита от перемотки часов
# ---------------------------------------------------------------------------

static func now_unix() -> int:
	return int(Time.get_unix_time_from_system())


static func _skew() -> int:
	return int(TechData.v(TechData.well().get("anti_cheat", {}).get("max_skew_back_seconds", 300)))


## Запомнить «время видел». Отметка только растёт, и только пока часы не ушли
## назад дальше допуска: перемотанное время её не сдвигает.
static func note_time(now: int = -1) -> void:
	var t := now_unix() if now < 0 else now
	var meta := TechState.well_meta()
	var seen := int(meta.get("seen_unix", 0))
	if t > seen or seen - t <= _skew():
		meta["seen_unix"] = maxi(seen, t)


## Часы телефона отстали от отметки «видел время» больше допуска — их перемотали.
static func clock_rolled_back(now: int = -1) -> bool:
	var t := now_unix() if now < 0 else now
	return int(TechState.well_meta().get("seen_unix", 0)) - t > _skew()


## Сколько секунд скважина работала с прошлого забора (до капа не ограничено —
## кап применяет выплата, чтобы окно отчёта могло показать «упёрлась в кап»).
## Первый запуск не считается: иначе игрок, впервые собравший скважину, тут же
## получил бы доход за всё время, что он играл до неё. Откат часов даёт ноль.
static func pending_seconds(now: int = -1) -> float:
	if not is_built() or GameState.well_last_collect_unix <= 0:
		return 0.0
	var t := now_unix() if now < 0 else now
	if clock_rolled_back(t):
		return 0.0
	return maxf(0.0, float(t - GameState.well_last_collect_unix))


## Сколько секунд будет оплачено при заборе прямо сейчас (с капом).
static func payable_seconds(now: int = -1) -> float:
	return minf(pending_seconds(now), cap_hours() * 3600.0)


## Доля накопленного от капа, 0..1 — для полоски на экране скважины.
static func fill_fraction(now: int = -1) -> float:
	return clampf(pending_seconds(now) / maxf(cap_hours() * 3600.0, 1.0), 0.0, 1.0)


# ---------------------------------------------------------------------------
# Забор
# ---------------------------------------------------------------------------

## Забрать накопленное: кладёт добычу на склад и возвращает отчёт
## {seconds, raw_seconds, capped, cap_hours, items:{id:n}, coins_value, per_hour, level}.
## Пустой словарь — забирать нечего (не построена, откат часов, нет добычи).
## Отметка забора ставится ДО выплаты: убитое посреди окна отчёта приложение не
## выплатит дважды.
static func collect(now: int = -1) -> Dictionary:
	var t := now_unix() if now < 0 else now
	if not is_built():
		return {}
	if GameState.well_last_collect_unix <= 0:
		GameState.well_last_collect_unix = t
		note_time(t)
		return {}
	if clock_rolled_back(t):
		# Прощаем давний откат (телефон сам исправил часы): иначе скважина молчала
		# бы, пока реальное время не догонит чужую отметку.
		if int(TechState.well_meta().get("seen_unix", 0)) - t > _forgive_seconds():
			TechState.well_meta()["seen_unix"] = t
			GameState.well_last_collect_unix = mini(GameState.well_last_collect_unix, t)
		return {}
	var raw := pending_seconds(t)
	var secs := minf(raw, cap_hours() * 3600.0)
	# Якорь не уходит назад, даже если часы чуть отстали (в пределах допуска).
	GameState.well_last_collect_unix = maxi(GameState.well_last_collect_unix, t)
	note_time(t)
	var value := income_coins_for_seconds(secs)
	if value <= 0:
		return {}
	var items := _basket_for_value(value)
	if items.is_empty():
		return {}
	for id in items.keys():
		HouseStorage.store_directly(String(id), int(items[id]))
	GameState.emit_event(&"well_collected", {"value": value, "seconds": secs})
	return {
		"seconds": secs,
		"raw_seconds": raw,
		"capped": raw > secs + 1.0,
		"cap_hours": cap_hours(),
		"items": items,
		"coins_value": value,
		"per_hour": int(income_per_hour()),
		"level": GameState.well_level,
	}


static func _forgive_seconds() -> int:
	return 48 * 3600


## Повторить уже выплаченное (ролик «×2»): ещё столько же на склад. Никогда
## не трогает монеты и доллары.
static func double_report(report: Dictionary) -> Dictionary:
	var items: Dictionary = report.get("items", {})
	for id in items.keys():
		HouseStorage.store_directly(String(id), int(items[id]))
	return items


# ---------------------------------------------------------------------------
# Улучшение
# ---------------------------------------------------------------------------

## Улучшить скважину на ступень. Накопленное до улучшения сперва выплачивается по
## старой ставке (иначе выгодно было бы копить до капа и улучшать перед забором).
## Возвращает {ok, message, report}.
static func upgrade() -> Dictionary:
	if not is_built():
		return {"ok": false, "message": "Скважина не построена", "report": {}}
	var cost = next_cost()
	if cost == null:
		return {"ok": false, "message": "Скважина уже лучшая", "report": {}}
	if not TechCost.can_act_here():
		return {"ok": false, "message": TechCost.reason_cannot(), "report": {}}
	if not bool(TechCost.check(cost)["ok"]):
		return {"ok": false, "message": "Не хватает материалов", "report": {}}
	var report := collect()
	TechCost.pay(cost)
	GameState.well_level += 1
	GameState.emit_event(&"bought", {"id": "well_level_%d" % GameState.well_level, "currency": "coins"})
	SaveSystem.save_game()
	return {"ok": true, "message": "Ступень %d" % GameState.well_level, "report": report}


# ---------------------------------------------------------------------------
# Что скважина достаёт
# ---------------------------------------------------------------------------

## Корзина руды на заданную сумму. Состав повторяет породу на глубине скважины:
## доля ценности руды ∝ плотность × цена; берём MAX_KINDS самых весомых, золото
## обязательно (владелец назвал его отдельно, и оно же — узнаваемая строка в
## отчёте). Продаваемое только: экзотика с глубины 3000 (цены нет) нужна на
## ступени костюма и скважины, и её добывает рука игрока, а не простаивающая
## установка — иначе незачем идти к лаве.
static func _basket_for_value(value: int) -> Dictionary:
	var rows := _composition()
	if rows.is_empty():
		return {}
	var total_w := 0.0
	for r in rows:
		total_w += float(r["w"])
	var out: Dictionary = {}
	for r in rows:
		var id := String(r["id"])
		var price: int = maxi(1, int(r["price"]))
		var share: float = float(value) * float(r["w"]) / maxf(total_w, 0.0001)
		out[id] = maxi(1, int(round(share / float(price))))
	return out


## [{id, price, w}] самых весомых руд на глубине скважины, золото — всегда.
static func _composition() -> Array:
	var world: WorldGen = GameState.world_ref
	if world == null:
		if _probe_world == null:
			_probe_world = WorldGen.new(1)
		world = _probe_world
	var depth: int = maxi(effective_depth(), 1)
	var rows: Array = []
	for d in world.ore_densities_at(depth):
		var id := String(d["id"])
		if id.is_empty() or id in ["earth", "stone"]:
			continue
		var price := Balance.get_mineral_price(id)
		if price <= 0:
			continue
		var m := Balance.get_mineral(id)
		# Скважина именно КОПАЕТ: выплавленное и собранное (бронза, топливные
		# блоки) она произвести не может. У бронзы ключ density лежит как null.
		if String(m.get("category", "")) == "crafted" or m.get("density", null) == null:
			continue
		rows.append({"id": id, "price": price, "w": float(d["density"]) * float(price)})
	rows.sort_custom(func(a, b): return float(a["w"]) > float(b["w"]))
	var out: Array = rows.slice(0, MAX_KINDS)
	var has_gold := false
	for r in out:
		if String(r["id"]) == "gold":
			has_gold = true
	if not has_gold:
		for r in rows:
			if String(r["id"]) == "gold":
				out[out.size() - 1] = r
				break
	return out

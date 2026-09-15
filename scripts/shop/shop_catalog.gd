class_name ShopCatalog
extends RefCounted
## ShopCatalog — что мастерская умеет: рецепты верстака, товары лавки,
## рекламные награды и правила скупки.
##
## Числа НЕ дублируются: рецепты собираются из data/balance.json (железная
## кирка и бронза 1:1 заданы ГДД разделом 5 напрямую, топливный блок 4:1 —
## тем же разделом, цены бура и машины лежат там же с пометкой proposed), а
## цены руды — из data/minerals.json через автолоад Balance. Свой файл
## data/shop.json держит только то, чего в них нет: ассортимент лавки,
## величину рекламных наград и список того, что мастерская обратно не
## скупает.
##
## Загружается лениво и кэшируется в статике: каталог читается на каждом
## открытии магазина, а парсить JSON ради каждого клика незачем.

const DATA_PATH := "res://data/shop.json"

static var _data: Dictionary = {}
static var _loaded: bool = false


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = _load_json(DATA_PATH)
	return _data


## Сбрасывает кэш — нужен тестам, которые правят JSON на лету.
static func reload() -> void:
	_loaded = false
	_data = {}


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ShopCatalog: файл не найден: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("ShopCatalog: не удалось распарсить JSON: %s" % path)
		return {}
	return parsed


# ---------------------------------------------------------------------------
# Скупка
# ---------------------------------------------------------------------------

## Что мастерская обратно не принимает (см. data/shop.json -> sell.not_bought).
static func not_bought() -> Array:
	return Balance.unwrap(data().get("sell", {}).get("not_bought", []))


## Продаётся ли вообще этот предмет в мастерской: цена больше нуля, минерал
## помечен sellable и не входит в список того, что мастерская не скупает.
static func is_bought(id: String) -> bool:
	if not_bought().has(id):
		return false
	var m: Dictionary = Balance.get_mineral(id)
	if m.is_empty():
		return false
	if m.get("sellable", true) != true:
		return false
	return Balance.get_mineral_price(id) > 0


static func ad_double_sale_id() -> String:
	return String(data().get("sell", {}).get("ad_double_sale_id", "double_income_on_sale"))


# ---------------------------------------------------------------------------
# Верстак
# ---------------------------------------------------------------------------

## Все рецепты верстака в порядке показа. Каждый:
##   {id, name_ru, kind: "item"|"tool", output: {id, count},
##    inputs: {mineral_id: count}, coins: int, unlock_depth: int, desc_ru}
static func recipes() -> Array:
	var out: Array = []
	out.append(_recipe_bronze())
	out.append(_recipe_fuel_block())
	for tool_id in ["iron_pickaxe", "hand_drill", "drill_rig"]:
		var r := _recipe_tool(tool_id)
		if not r.is_empty():
			out.append(r)
	return out


static func recipe(id: String) -> Dictionary:
	for r in recipes():
		if r["id"] == id:
			return r
	return {}


## Бронза: ГДД раздел 5 — "бронза не добывается, плавится из металлолома,
## 1 металлолом = 1 бронза". Число берём из balance.json (crafting), а не
## из recipe в minerals.json: там лежит 5:1, и это расходится с ГДД.
static func _recipe_bronze() -> Dictionary:
	var per: int = int(Balance.unwrap(Balance.balance.get("crafting", {}).get("scrap_per_bronze", 1)))
	return {
		"id": "bronze",
		"name_ru": "Бронза",
		"desc_ru": "Плавка металлолома",
		"kind": "item",
		"output": {"id": "bronze", "count": 1},
		"inputs": {"scrap": maxi(per, 1)},
		"coins": 0,
		"unlock_depth": 0,
	}


## Топливный блок: ГДД раздел 5 — 4 торфа = 1 блок (торфоперегонка).
static func _recipe_fuel_block() -> Dictionary:
	var per: int = int(Balance.unwrap(Balance.balance.get("fuel_consumption", {}).get("peat_per_fuel_block", 4)))
	return {
		"id": "fuel_block",
		"name_ru": "Топливный блок",
		"desc_ru": "Торфоперегонка",
		"kind": "item",
		"output": {"id": "fuel_block", "count": 1},
		"inputs": {"peat": maxi(per, 1)},
		"coins": 0,
		"unlock_depth": 0,
	}


## Инструмент: состав и цена берутся из balance.json -> tools.<id>.cost.
## Ключ "coins" внутри cost — это монеты, всё остальное — предметы.
static func _recipe_tool(tool_id: String) -> Dictionary:
	var t: Dictionary = Balance.get_tool(tool_id)
	if t.is_empty():
		return {}
	var cost = Balance.unwrap(t.get("cost", {}))
	if typeof(cost) != TYPE_DICTIONARY or cost.is_empty():
		return {}
	var inputs: Dictionary = {}
	var coins := 0
	for key in cost.keys():
		var amount := int(Balance.unwrap(cost[key]))
		if key == "coins":
			coins = amount
		elif amount > 0:
			inputs[key] = amount
	if inputs.is_empty() and coins <= 0:
		return {}  # бесплатные инструменты (лопата, дедова кирка) не крафтятся
	return {
		"id": tool_id,
		"name_ru": Balance.get_tool_name_ru(tool_id),
		"desc_ru": _tool_desc(tool_id),
		"kind": "tool",
		"output": {"id": tool_id, "count": 1},
		"inputs": inputs,
		"coins": coins,
		"unlock_depth": unlock_depth(tool_id),
	}


static func _tool_desc(tool_id: String) -> String:
	var t: Dictionary = Balance.get_tool(tool_id)
	var mult := Balance.get_tool_speed_multiplier(tool_id)
	var max_depth := Balance.get_tool_max_depth(tool_id)
	var parts: Array = ["копка ×%.1f" % mult]
	if max_depth > 0:
		parts.append("до глубины %d" % max_depth)
	if t.has("fuel"):
		parts.append("нужно топливо")
	return ", ".join(parts)


## С какой глубины рецепт вообще показывается (ГДД раздел 6: ручной бур
## открывается на глубине 100). Считается по максимальной достигнутой
## глубине, а не по текущей: рецепт, однажды открывшийся, не закрывается.
static func unlock_depth(recipe_id: String) -> int:
	var table: Dictionary = data().get("craft", {}).get("unlock_depth", {})
	return int(Balance.unwrap(table.get(recipe_id, 0)))


# ---------------------------------------------------------------------------
# Лавка и доллары
# ---------------------------------------------------------------------------

## Товары лавки за монеты. Допинги приходят из balance.json -> food.items
## (source="shop"): их цена и эффект заданы там системой дома, и второй
## список с той же ценой разъехался бы при первой правке. Свои товары из
## data/shop.json добавляются следом и не затирают одноимённые.
static func goods_coins() -> Array:
	var out: Array = _goods_from_balance("price_coins")
	_append_extra(out, data().get("goods_coins", {}).get("extra", []), "price_coins")
	return out


## Товары за доллары: гаджеты из data/shop.json плюс премиум-допинги из
## balance.json -> food.items (батончик "за донат", ГДД раздел 7).
static func goods_dollars() -> Array:
	var out: Array = _goods_from_balance("price_dollars")
	_append_extra(out, data().get("goods_dollars", {}).get("extra", []), "price_dollars")
	return out


## Расходники из balance.json -> food.items, у которых есть цена в нужной
## валюте. Доставка еды (source="delivery") — не лавка, а дом: её товары
## сюда не берём, иначе суп продавался бы из шахты.
static func _goods_from_balance(price_key: String) -> Array:
	var out: Array = []
	for item in Balance.balance.get("food", {}).get("items", []):
		if String(item.get("source", "")) == "delivery":
			continue
		if not item.has(price_key):
			continue
		var price := int(Balance.unwrap(item[price_key]))
		if price <= 0:
			continue
		out.append({
			"id": String(item.get("id", "")),
			"name_ru": String(item.get("name_ru", item.get("id", ""))),
			"desc_ru": _restore_desc(item),
			"effect": "restore",
			"stamina_percent": float(Balance.unwrap(item.get("stamina_percent", 0))),
			"hunger_percent": float(Balance.unwrap(item.get("hunger_percent", 0))),
			price_key: price,
		})
	return out


static func _append_extra(out: Array, extra: Array, price_key: String) -> void:
	for g in extra:
		var id := String(g.get("id", ""))
		var already := false
		for existing in out:
			if String(existing.get("id", "")) == id:
				already = true
				break
		if already or not g.has(price_key):
			continue
		out.append(g)


static func _restore_desc(item: Dictionary) -> String:
	var parts: Array = []
	var stamina := int(Balance.unwrap(item.get("stamina_percent", 0)))
	var hunger := int(Balance.unwrap(item.get("hunger_percent", 0)))
	if stamina > 0:
		parts.append("+%d%% бодрости" % stamina)
	if hunger > 0:
		parts.append("+%d%% сытости" % hunger)
	return ", ".join(parts)


static func good(good_id: String, currency: String) -> Dictionary:
	var list: Array = goods_coins() if currency == "coins" else goods_dollars()
	for g in list:
		if String(g.get("id", "")) == good_id:
			return g
	return {}


static func good_price(g: Dictionary, currency: String) -> int:
	var key := "price_coins" if currency == "coins" else "price_dollars"
	return int(Balance.unwrap(g.get(key, 0)))


static func ad_rewards() -> Array:
	return data().get("ad_rewards", [])


static func ad_reward(ad_id: String) -> Dictionary:
	for a in ad_rewards():
		if String(a.get("id", "")) == ad_id:
			return a
	return {}


## Курс обмена: сколько монет даёт один доллар (balance.json -> economy).
static func coins_per_dollar() -> int:
	return int(Balance.get_coins_per_premium_currency())


## Русское название предмета для списков — минералы знают его сами.
static func item_name(id: String) -> String:
	var m: Dictionary = Balance.get_mineral(id)
	if not m.is_empty():
		return String(m.get("name_ru", id))
	var t: Dictionary = Balance.get_tool(id)
	if not t.is_empty():
		return Balance.get_tool_name_ru(id)
	return id

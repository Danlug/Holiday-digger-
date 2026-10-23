class_name TechCost
extends RefCounted
## Цена ступени: монеты + материалы {coins, items:{id: n}}. Материалы берутся
## со склада И из рюкзака (как у верстака, ГДД п.14: перекладывать руду из рук
## на полку ради крафта бессмысленно); сначала склад — он тяжёлый и нужен дома.

## Улучшать технику можно на поверхности или дома: со дна шахты нельзя ни
## продать, ни собрать — та же линия, что у верстака и склада.
static func can_act_here() -> bool:
	return GameState.house_is_indoors or GameState.player_depth <= 0


static func reason_cannot() -> String:
	return "" if can_act_here() else "Только на поверхности или дома"


static func held(id: String) -> int:
	return HouseStorage.count(id) + GameState.get_item_count(id)


## {ok, missing:{id:n}, missing_coins:int}. cost == null — ступень бесплатна.
static func check(cost) -> Dictionary:
	var missing: Dictionary = {}
	var missing_coins := 0
	if typeof(cost) == TYPE_DICTIONARY:
		var items: Dictionary = cost.get("items", {})
		for id in items.keys():
			var need := int(items[id]) - held(String(id))
			if need > 0:
				missing[String(id)] = need
		missing_coins = maxi(0, int(cost.get("coins", 0)) - GameState.coins)
	return {"ok": missing.is_empty() and missing_coins == 0, "missing": missing, "missing_coins": missing_coins}


## Списать цену. false — ничего не тронуто (не хватило).
static func pay(cost) -> bool:
	if typeof(cost) != TYPE_DICTIONARY:
		return true
	if not bool(check(cost)["ok"]):
		return false
	var items: Dictionary = cost.get("items", {})
	for id in items.keys():
		var left := int(items[id]) - HouseStorage.consume(String(id), int(items[id]))
		if left > 0:
			GameState.remove_item(String(id), left)
	var coins := int(cost.get("coins", 0))
	if coins > 0:
		GameState.spend_coins(coins)
	return true


static func coins_of(cost) -> int:
	return int(cost.get("coins", 0)) if typeof(cost) == TYPE_DICTIONARY else 0


static func items_of(cost) -> Dictionary:
	return cost.get("items", {}) if typeof(cost) == TYPE_DICTIONARY else {}

class_name HouseFood
extends RefCounted
## HouseFood — заказ, доставка и поедание еды (ГДД п.7).
##
## Порядок по ГДД: заказ делается ИЗ ДОМА, доставка приходит К ВХОДНОЙ ДВЕРИ
## за 5 секунд. Поэтому оплаченная порция не падает сразу в рюкзак: она
## сначала лежит у двери (GameState.house_food_at_door), и её нужно забрать.
## Иначе заказ из шахты телепортировал бы обед прямо в руки, и «сбегать
## домой» перестало бы быть решением игрока.
##
## Еда — обычный предмет инвентаря: она весит (minerals.json -> weight_kg) и
## её можно унести с собой на вылазку. Так голод закрывается и в шахте, но
## ценой грузоподъёмности, которая иначе досталась бы руде.

## Возвращает {ok, free, price, reason}: можно ли заказать блюдо прямо сейчас.
static func can_order(id: String) -> Dictionary:
	var item := HouseConfig.food_item(id)
	if item.is_empty() or String(item.get("source", "")) != "delivery":
		return {"ok": false, "free": false, "price": 0, "reason": "Такого в меню нет."}
	var price := HouseConfig.food_price_coins(id)
	if free_orders_left() > 0:
		return {"ok": true, "free": true, "price": 0, "reason": ""}
	if GameState.coins < price:
		return {"ok": false, "free": false, "price": price,
			"reason": "Не хватает монет: нужно %d." % price}
	return {"ok": true, "free": false, "price": price, "reason": ""}


## Сколько бесплатных доставок («деньги, оставленные бабкой») осталось
## сегодня. Лимит считается по реальным суткам — см. game_state.gd.
static func free_orders_left() -> int:
	return maxi(0, HouseConfig.free_orders_per_day() - GameState.house_free_orders_used_today)


## Списывает оплату за заказ. Саму доставку (таймер на 5 секунд и укладку
## порции к двери) ведёт узел системы дома: чистая логика таймеров не держит.
static func pay_for_order(id: String) -> bool:
	var check := can_order(id)
	if not check["ok"]:
		return false
	if bool(check["free"]):
		GameState.house_free_orders_used_today += 1
		return true
	return GameState.spend_coins(int(check["price"]))


## Доставка приехала: порция ложится у входной двери.
static func deliver(id: String, count: int = 1) -> void:
	if count <= 0:
		return
	var at_door: Dictionary = GameState.house_food_at_door
	at_door[id] = int(at_door.get(id, 0)) + count


static func food_at_door_count() -> int:
	var total := 0
	for id in GameState.house_food_at_door.keys():
		total += int(GameState.house_food_at_door[id])
	return total


## Забрать всё, что лежит у двери, в рюкзак. Возвращает, сколько порций
## реально влезло: еда весит, и при полном рюкзаке часть остаётся у двери —
## она никуда не денется, но нести руду и обед одновременно не выйдет.
static func take_from_door() -> int:
	var taken := 0
	for id in GameState.house_food_at_door.keys():
		var count := int(GameState.house_food_at_door[id])
		while count > 0:
			if GameState.add_item(id, 1) <= 0:
				break
			count -= 1
			taken += 1
		if count <= 0:
			GameState.house_food_at_door.erase(id)
		else:
			GameState.house_food_at_door[id] = count
	return taken


## Съесть порцию из рюкзака. Возвращает {ok, hunger, stamina, reason}:
## сколько процентов реально восстановлено (полоски упираются в 100%).
static func eat(id: String) -> Dictionary:
	if GameState.get_item_count(id) <= 0:
		return {"ok": false, "hunger": 0.0, "stamina": 0.0, "reason": "В рюкзаке этого нет."}
	if not HouseConfig.is_food(id):
		return {"ok": false, "hunger": 0.0, "stamina": 0.0, "reason": "Это несъедобно."}
	var hunger_gain: float = minf(HouseConfig.food_hunger_percent(id), 100.0 - GameState.hunger)
	var stamina_gain: float = minf(HouseConfig.food_stamina_percent(id), 100.0 - GameState.stamina)
	GameState.remove_item(id, 1)
	GameState.set_hunger(GameState.hunger + HouseConfig.food_hunger_percent(id))
	GameState.set_stamina(GameState.stamina + HouseConfig.food_stamina_percent(id))
	return {"ok": true, "hunger": hunger_gain, "stamina": stamina_gain, "reason": ""}


## Вся еда, которая сейчас лежит в рюкзаке: [{id, name, count}, ...].
static func food_in_inventory() -> Array:
	var out: Array = []
	for item in HouseConfig.food_items():
		var id := String(item.get("id", ""))
		var count := GameState.get_item_count(id)
		if count > 0:
			out.append({"id": id, "name": HouseConfig.food_name(id), "count": count})
	return out


## Что съесть «одной кнопкой» вне дома: сначала то, что покрывает более
## пустую полоску. Пустая строка — еды нет.
static func best_food_for_now() -> String:
	var best := ""
	var best_score := 0.0
	for entry in food_in_inventory():
		var id: String = entry["id"]
		var score := minf(HouseConfig.food_hunger_percent(id), 100.0 - GameState.hunger) \
			+ minf(HouseConfig.food_stamina_percent(id), 100.0 - GameState.stamina)
		if score > best_score:
			best_score = score
			best = id
	if best.is_empty() and not food_in_inventory().is_empty():
		# Обе полоски полны — есть незачем, но кнопку показываем только тогда,
		# когда еда вообще есть: пустая кнопка на панели хуже отсутствующей.
		return ""
	return best

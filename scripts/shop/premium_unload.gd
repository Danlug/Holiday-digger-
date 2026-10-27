class_name PremiumUnload
extends RefCounted
## PremiumUnload — премиум-выгрузка на склад (раунд 6, слова владельца 27.10:
## «вместо таблетки восстановления за премиум сделай премиум-выгрузку на склад —
## нажал, и всё содержимое сразу отправляется на склад»). Товар за доллары на
## месте таблетки: data/shop.json → goods_dollars.extra[premium_unload].
##
## Срабатывает сразу при покупке, как часы-телепорт и как была таблетка: витрина
## за доллары открывается с HUD где угодно, а запас «выгрузок» в рюкзаке был бы
## ещё одной стопкой ради одной кнопки. Доллары списываются, только если есть что
## отправить (ShopService.buy проверяет can_unload до оплаты).
##
## Что улетает: добыча — руда, материалы, находки боя, всё, что лежит в рюкзаке,
## КРОМЕ припасов (еда и допинги, аптечка, топливные блоки). Выгрузку покупают,
## чтобы не подниматься и копать дальше, а без припасов дальше не докопать:
## отправить батончик домой со дна шахты — ловушка, а не услуга. Надетое
## (инструмент, ранец, бур) в рюкзаке не лежит и не трогается.
## Склад лимита не имеет (ГДД п.14: «на складе вес ничего не ограничивает»),
## поэтому уходит всё, что не припас; сколько ушло, игрок видит «×N» у домика.

const ID := "premium_unload"
const EFFECT := "premium_unload"
## Таблетка восстановления снята с продажи (раунд 6). Сейв, где она почему-то
## лежит в рюкзаке или на складе, при загрузке получает её цену долларами назад.
const LEGACY_PILL := "full_restore_pill"
const LEGACY_PILL_DOLLARS := 25   # последняя цена таблетки (разбор чисел 26.10) — ровно одна выгрузка

## Последний результат unload(): витрина берёт отсюда, что лететь домой.
static var _last: Dictionary = {}


## Припас — то, что остаётся с героем: без еды, аптечки и топлива копать дальше нельзя.
## Еда и лекарства узнаются по category в data/minerals.json (food / medical), топливо — по id.
static func is_supply(id: String) -> bool:
	if id == "fuel_block" or HouseConfig.is_food(id) or Healing.is_medkit(id):
		return true
	return ["food", "medical"].has(String(Balance.get_mineral(id).get("category", "")))


## Что улетит: {id: штук}.
static func movable() -> Dictionary:
	var out: Dictionary = {}
	for id in GameState.inventory.keys():
		var n := int(GameState.inventory[id])
		if n > 0 and not is_supply(String(id)):
			out[String(id)] = n
	return out


static func movable_count() -> int:
	var total := 0
	for n in movable().values():
		total += int(n)
	return total


static func can_unload() -> bool:
	return not movable().is_empty()


## Отправить добычу на склад. Возвращает {ok, moved: {id: n}, count, weight}.
## free — первый раз в обучении (премиум-выгрузка на 150): в событии помечается,
## чтобы задания «потрать доллары» и аналитика не считали его покупкой.
static func unload(free: bool = false) -> Dictionary:
	var moved: Dictionary = {}
	var count := 0
	var weight := 0.0
	var all := movable()
	for id in all.keys():
		var n := int(all[id])
		if not GameState.remove_item(id, n):
			continue
		HouseStorage.store_directly(id, n)
		moved[id] = n
		count += n
		weight += Balance.get_mineral_weight(id) * n
		GameState.emit_event(&"stored", {"item": id, "count": n, "dir": "put", "remote": true})
	_last = {"ok": count > 0, "moved": moved, "count": count, "weight": weight}
	if count > 0:
		GameState.emit_event(&"premium_unload", {"count": count, "weight": weight, "free": free})
		SaveSystem.save_game()
	return _last.duplicate(true)


static func last_result() -> Dictionary:
	return _last.duplicate(true)



## Таблетка восстановления в старом сейве: в рюкзаке или на складе — снимаем и
## возвращаем доллары по её цене (= одна выгрузка). Таблетка срабатывала сразу при
## покупке и в рюкзак не ложилась, так что обычно здесь нечего делать; но отладка и
## ранние сборки могли её туда положить, а предмет без товара — мёртвый слот.
## Возвращает, сколько долларов вернули.
static func migrate_legacy() -> int:
	var n := GameState.get_item_count(LEGACY_PILL)
	if n > 0:
		GameState.inventory.erase(LEGACY_PILL)
		GameState.inventory_changed.emit()
	var stored := int(GameState.house_storage.get(LEGACY_PILL, 0))
	GameState.house_storage.erase(LEGACY_PILL)
	var total := maxi(0, n) + maxi(0, stored)
	if total <= 0:
		return 0
	var refund := total * LEGACY_PILL_DOLLARS
	GameState.add_dollars(refund)
	return refund

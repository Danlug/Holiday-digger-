class_name ShopRemote
extends RefCounted
## ShopRemote — «удалённые» покупки: еду и снаряжение под землёй можно купить
## не более N раз в сутки, каждый раз за просмотр рекламы (заказ владельца,
## ГДД §15 «Где можно покупать»). Здесь только счётчик «осталось сегодня» —
## ОДИН на все такие покупки (кирки, ранцы, ступени бура, еда, допинги, гаджеты).
## Правило «где можно» и сами покупки — в ShopService.can_buy.
##
## Хранится в GameState.ext["shop"]["remote"] = {day, used}: ключ «shop» общий
## с «новинками» витрины (ShopItems), поэтому пишем, не затирая соседей.
##
## Сутки — по РЕАЛЬНОМУ времени (UTC), как все лимиты рекламы, но с защитой от
## перемотки часов назад: в состоянии лежит наибольшая когда-либо виденная
## дата, и «сегодня» не идёт назад (тот же приём, что MetaState.today()).
## Простой сброс по смене календарной даты (GameState.daily_reset) отмотанные
## часы не отличил бы от нового дня и вернул бы счётчик. От перемотки ВПЕРЁД без
## сервера защиты нет — бьёт она только по самому игроку.

const KEY := "shop"
## Точка показа в data/monetization.json -> ad_placements.
const PLACEMENT := "remote_purchase"


## Сколько раз в сутки (число дано владельцем: data/shop.json).
static func limit() -> int:
	return maxi(0, int(Balance.unwrap(ShopCatalog.data().get("remote_purchase_limit_per_day", 3))))


static func used_today() -> int:
	return int(_current()["used"])


static func left_today() -> int:
	return maxi(0, limit() - used_today())


## «Ролик» и списание одной единицы лимита. false — на сегодня лимит исчерпан,
## ничего не списано.
##
## Рекламной сети в сборке нет (см. ad_manager.gd): как у ShopService.claim_ad
## ролик засчитывается сразу. С настоящим SDK именно здесь надо дождаться
## AdManager.ad_reward_earned(PLACEMENT) и только потом списывать.
static func watch_ad() -> bool:
	var cur := _current()
	if int(cur["used"]) >= limit():
		return false
	_write(int(cur["day"]), int(cur["used"]) + 1)
	return true


## Состояние на «сегодня»: {day, used}. Чистое чтение — в сейв ничего не пишет.
static func _current() -> Dictionary:
	var real := MetaClock.real_day()
	var stored := _read()
	# Часы стоят на месте или ушли назад: счётчик остаётся прежним.
	if real <= int(stored["day"]):
		return stored
	return {"day": real, "used": 0}


static func _read() -> Dictionary:
	var shop = GameState.ext_get(KEY, {})
	var r = shop.get("remote", {}) if typeof(shop) == TYPE_DICTIONARY else {}
	if typeof(r) != TYPE_DICTIONARY:
		return {"day": 0, "used": 0}
	# JSON возвращает числа как float.
	return {"day": int(r.get("day", 0)), "used": maxi(0, int(r.get("used", 0)))}


static func _write(day: int, used: int) -> void:
	var shop = GameState.ext_get(KEY, {})
	var cur: Dictionary = (shop as Dictionary).duplicate() if typeof(shop) == TYPE_DICTIONARY else {}
	cur["remote"] = {"day": day, "used": used}
	GameState.ext_set(KEY, cur)

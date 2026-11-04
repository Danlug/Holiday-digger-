class_name BronzeFurnace
extends RefCounted
## Печь мастерской: бронза плавится по таймеру. Слово владельца (разбор чисел,
## 26.10): «Оставь как есть, но бронза делается со скоростью минута штука».
## Число — balance.json → crafting.seconds_per_bronze.
##
## Игрок загружает лом тем же ползунком карточки рецепта (ShopService.craft →
## start): лом списывается сразу, печь плавит по одной штуке и работает, пока
## герой копает, и при закрытой игре — время считается по часам, как у скважины
## (IdleWell): разница unix-времени с отметкой, отметка назад не ходит.
## Готовое копится в печи и само забирается при входе в магазин дома (collect).
##
## Куда ложится готовое — правило мгновенного крафта (ShopService.craft_plan):
## штука из рюкзачного лома — в рюкзак, пока он держит вес и стопку, остальное и
## всё из складского лома — на склад. Склад не становится чёрным ходом в рюкзак
## (ГДД §14), поэтому очередь помнит, сколько штук из какого лома.
##
## Состояние — GameState.ext["bronze_furnace"] (JSON отдаёт float — читаем int()):
##   qs, qp  штук в очереди из складского / рюкзачного лома (первая из них — в работе)
##   at      unix-время, когда пошла штука в работе (0 — печь пуста)
##   rs, rp  готово и ждёт: на склад / в рюкзак
## Плавится сперва складской лом; отмена снимает очередь с хвоста — сперва рюкзачный.

const KEY := "bronze_furnace"
const RECIPE := "bronze"
## Часы отмотали назад дальше этого — прощаем (как IdleWell._forgive_seconds):
## иначе печь стояла бы, пока настоящее время не догонит старую отметку.
const FORGIVE_SECONDS := 48 * 3600

## Подмена часов для тестов и бота: -1 — настоящие часы.
static var override_unix: int = -1


static func now_unix() -> int:
	return override_unix if override_unix >= 0 else int(Time.get_unix_time_from_system())


static func handles(recipe_id: String) -> bool:
	return recipe_id == RECIPE


static func seconds_per_unit() -> int:
	var v = Balance.unwrap(Balance.balance.get("crafting", {}).get("seconds_per_bronze", 60))
	return maxi(1, int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 60)


# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

## Сохранённое как есть, приведённое к int; битое или отсутствующее (старый сейв) — пустая печь.
static func _read() -> Dictionary:
	var d = GameState.ext_get(KEY, null)
	var out := {"qs": 0, "qp": 0, "at": 0, "rs": 0, "rp": 0}
	if typeof(d) != TYPE_DICTIONARY:
		return out
	for k in out.keys():
		var v = d.get(k, 0)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			out[k] = maxi(0, int(v))
	return out


static func _write(s: Dictionary) -> void:
	GameState.ext_set(KEY, {"qs": int(s["qs"]), "qp": int(s["qp"]), "at": int(s["at"]),
		"rs": int(s["rs"]), "rp": int(s["rp"])})


## Состояние на момент now — без записи: сколько штук за прошедшее время
## доплавилось и перешло из очереди в «готово».
@warning_ignore("integer_division")
static func status(now: int = -1) -> Dictionary:
	var t := now_unix() if now < 0 else now
	var s := _read()
	var q: int = s["qs"] + s["qp"]
	if q <= 0:
		s["at"] = 0
		return s
	if int(s["at"]) <= 0:
		s["at"] = t   # очередь без отметки (битый сейв) — считаем, что пошла сейчас
	var elapsed: int = t - int(s["at"])
	if elapsed < 0:
		if -elapsed > FORGIVE_SECONDS:
			s["at"] = t
		return s
	var per := seconds_per_unit()
	var done := mini(q, elapsed / per)
	if done <= 0:
		return s
	var from_store := mini(done, int(s["qs"]))
	s["qs"] = int(s["qs"]) - from_store
	s["rs"] = int(s["rs"]) + from_store
	s["qp"] = int(s["qp"]) - (done - from_store)
	s["rp"] = int(s["rp"]) + (done - from_store)
	s["at"] = int(s["at"]) + done * per if q > done else 0
	return s


## То же, что status, но с записью — перед любым изменением очереди.
static func advance(now: int = -1) -> Dictionary:
	var s := status(now)
	_write(s)
	return s


## Сколько штук в очереди, включая ту, что плавится.
static func queued(now: int = -1) -> int:
	var s := status(now)
	return int(s["qs"]) + int(s["qp"])


## Готово и ждёт, пока заберут.
static func ready_count(now: int = -1) -> int:
	var s := status(now)
	return int(s["rs"]) + int(s["rp"])


## Сколько бронзы уже «в работе» — в очереди и готовой в печи. Цепочки проектов
## считают её своей: лом, загруженный в печь, — уже почти бронза.
static func in_furnace(item: String, now: int = -1) -> int:
	if item != RECIPE:
		return 0
	var s := status(now)
	return int(s["qs"]) + int(s["qp"]) + int(s["rs"]) + int(s["rp"])


static func is_busy(now: int = -1) -> bool:
	return in_furnace(RECIPE, now) > 0


## Не начатые штуки — их отмена возвращает в лом.
static func unstarted(now: int = -1) -> int:
	return maxi(0, queued(now) - 1)


## Секунд до следующей готовой штуки (0 — очередь пуста).
static func next_in(now: int = -1) -> int:
	var t := now_unix() if now < 0 else now
	var s := status(t)
	if int(s["qs"]) + int(s["qp"]) <= 0:
		return 0
	return clampi(seconds_per_unit() - (t - int(s["at"])), 1, seconds_per_unit())


## Секунд до конца всей очереди.
static func all_in(now: int = -1) -> int:
	var q := queued(now)
	return 0 if q <= 0 else next_in(now) + (q - 1) * seconds_per_unit()


## Доля готовности штуки в работе, 0..1.
static func unit_progress(now: int = -1) -> float:
	if queued(now) <= 0:
		return 0.0
	return clampf(1.0 - float(next_in(now)) / float(seconds_per_unit()), 0.0, 1.0)


## «0:42», «12:05», «1:02:03» — для отсчёта на карточке и плитке.
@warning_ignore("integer_division")
static func clock_text(seconds: int) -> String:
	var s := maxi(0, seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------------------
# Действия
# ---------------------------------------------------------------------------

## Загрузить count штук: списать лом (склад, потом рюкзак — как craft_plan) и
## поставить в очередь. Место и материалы уже проверил ShopService.craft
## (check_craft); здесь — повторная сверка перед первым списанием, как у пачки.
## Возвращает ответ крафта: {ok, message, count: 0 (готового пока нет), queued,
## used, seconds, to_pack: 0, to_storage: 0, timed: true}.
static func start(count: int, now: int = -1) -> Dictionary:
	var t := now_unix() if now < 0 else now
	var r := ShopCatalog.recipe(RECIPE)
	if r.is_empty() or count <= 0:
		return {"ok": false, "message": "Нечего плавить", "count": 0}
	var plan := ShopService.craft_plan(RECIPE, count)
	for id in (plan["from_pack"] as Dictionary).keys():
		if GameState.get_item_count(String(id)) < int(plan["from_pack"][id]) \
				or HouseStorage.count(String(id)) < int(plan["from_storage"][id]):
			return {"ok": false, "message": "Материалы кончились", "count": 0}
	if int(plan["coins"]) > 0 and not GameState.spend_coins(int(plan["coins"])):
		return {"ok": false, "message": "Не хватает монет", "count": 0}

	var s := advance(t)
	var used: Dictionary = {}
	for id in (plan["from_pack"] as Dictionary).keys():
		HouseStorage.consume(String(id), int(plan["from_storage"][id]))
		var from_pack := int(plan["from_pack"][id])
		if from_pack > 0:
			GameState.remove_item(String(id), from_pack)
		used[String(id)] = int(plan["from_storage"][id]) + from_pack
	var pack_units := clampi(int(plan.get("pack_units", 0)), 0, count)
	s["qs"] = int(s["qs"]) + count - pack_units
	s["qp"] = int(s["qp"]) + pack_units
	if int(s["at"]) <= 0:
		s["at"] = t
	_write(s)
	var per := seconds_per_unit()
	GameState.emit_event(&"smelt_started", {"recipe": RECIPE, "count": count, "used": used.duplicate(),
		"queued": int(s["qs"]) + int(s["qp"])})
	SaveSystem.save_game()
	return {"ok": true, "message": "В печи: +%d" % count, "count": 0, "queued": count, "used": used,
		"seconds": count * per, "to_pack": 0, "to_storage": 0, "timed": true}


## Забрать готовое — только дома (витрина зовёт при открытии). Штуки из
## рюкзачного лома — в рюкзак, пока влезают; остальное — на склад.
## Возвращает {count, to_pack, to_storage}; событие crafted — как у мгновенного крафта.
static func collect(now: int = -1) -> Dictionary:
	var out := {"count": 0, "to_pack": 0, "to_storage": 0}
	if not ShopService.is_at_workshop():
		return out
	var s := advance(now)
	var n: int = int(s["rs"]) + int(s["rp"])
	if n <= 0:
		return out
	var to_pack := GameState.add_item(RECIPE, int(s["rp"])) if int(s["rp"]) > 0 else 0
	var to_storage := n - to_pack
	if to_storage > 0:
		HouseStorage.store_directly(RECIPE, to_storage)
	s["rs"] = 0
	s["rp"] = 0
	_write(s)
	GameState.emit_event(&"crafted", {"recipe": RECIPE, "item": RECIPE, "count": n,
		"to_pack": to_pack, "to_storage": to_storage})
	SaveSystem.save_game()
	out["count"] = n
	out["to_pack"] = to_pack
	out["to_storage"] = to_storage
	return out


## Остановить очередь: штука в работе доплавится, за не начатые лом (и монеты,
## если рецепт их брал) возвращаются туда, откуда пришли: рюкзачный лом — в
## рюкзак, пока влезает, остальное — на склад. Только дома: вернуть лом в рюкзак
## из шахты значило бы телепортировать его. Возвращает {ok, refunded, message}.
static func cancel(now: int = -1) -> Dictionary:
	if not ShopService.is_at_workshop():
		return {"ok": false, "refunded": 0, "message": "Печь дома, в мастерской"}
	var s := advance(now)
	var qs := int(s["qs"])
	var qp := int(s["qp"])
	if qs + qp <= 1:
		return {"ok": false, "refunded": 0, "message": "Отменять нечего"}
	var keep_s := 1 if qs > 0 else 0
	var back_s := qs - keep_s
	var back_p := qp - (1 - keep_s)
	s["qs"] = keep_s
	s["qp"] = 1 - keep_s
	_write(s)
	var r := ShopCatalog.recipe(RECIPE)
	for id in (r.get("inputs", {}) as Dictionary).keys():
		var per := maxi(1, int(r["inputs"][id]))
		var to_store := back_s * per
		var to_pack := back_p * per
		var fit := GameState.add_item(String(id), to_pack) if to_pack > 0 else 0
		to_store += to_pack - fit
		if to_store > 0:
			HouseStorage.store_directly(String(id), to_store)
	var coins := int(r.get("coins", 0)) * (back_s + back_p)
	if coins > 0:
		GameState.add_coins(coins)
	GameState.emit_event(&"smelt_cancelled", {"recipe": RECIPE, "count": back_s + back_p})
	SaveSystem.save_game()
	return {"ok": true, "refunded": back_s + back_p, "message": ""}

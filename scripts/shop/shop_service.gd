class_name ShopService
extends RefCounted
## ShopService — вся экономика мастерской без единого узла интерфейса:
## продажа сырья, верстак, лавка, обмен долларов и рекламные награды.
##
## Логика отделена от ShopUI намеренно: продажа стопки и списание
## ингредиентов — это то, что должно проверяться headless-тестом
## (tests/test_shop_harness.tscn), а не кликами по кнопкам.
##
## Деньги появляются ТОЛЬКО здесь. Копка даёт опыт и сырьё (ГДД раздел 4),
## монеты — продажа (раздел 15); если бы монеты капали в момент удара,
## шахта оплачивала бы себя сама и подъём с грузом перестал бы быть
## решением игрока.

# ---------------------------------------------------------------------------
# Где вообще можно торговать и собирать
# ---------------------------------------------------------------------------

## Скупка и верстак работают только дома: мастерская стоит в подвале (ГДД
## раздел 5), и весь смысл экономики в том, что лут надо ДОНЕСТИ наверх.
## Если продавать можно со дна шахты, грузоподъёмность, риск смерти с полным
## рюкзаком и сам подъём перестают что-либо значить. Дистанционная сдача лута
## в ГДД есть, но это рекламная награда с лимитом 3 раза в день (раздел 15),
## а не бесплатная кнопка.
static func is_at_workshop() -> bool:
	return GameState.house_is_indoors


# ---------------------------------------------------------------------------
# Где можно покупать снаряжение и еду (заказ владельца, ГДД §15)
#
# «Покупать снаряжение и еду можно только дома у двери, либо до 3 раз за рекламу
# под землёй». Витрину открыть можно откуда угодно (обмен долларов и ролики
# живут в ней же и от места не зависят), но кирки, ранцы, ступени бура, еда и
# допинги за монеты покупаются по правилу места — его и проверяет can_buy.
# Раунд 4: «Покупки за доллары можно делать в любом месте, не нужен просмотр
# рекламы» — всё, что оплачивается долларами, правилом места не держится.
# ---------------------------------------------------------------------------

## Что витрина продаёт «по правилу места» (виды предложений ShopItems): кирки,
## ранцы, ступени бура, доставка еды и товары лавки (допинги, топливо) — если
## платят монетами (товары за доллары — вне правила, is_dollar_purchase).
## Рецепты верстака сюда не входят — это крафт из добытого, он и так только дома
## (check_craft). Обмен долларов, ролики и продажа тоже вне правила.
const GATED_KINDS := ["tool", "gear", "drill", "food", "good"]

const PLACE_DOOR := "door"
const PLACE_HOUSE := "house"
const PLACE_GARDEN := "garden"
const PLACE_UNDERGROUND := "underground"


## Где сейчас игрок: у входной двери (прихожая дома), в доме (другие комнаты),
## на огороде (поверхность) или под землёй (с первой выкопанной клетки).
## Прихожая считается «у двери» целиком: единственная точка магазина там —
## пузырь «Заказать» у самой двери (data/rooms.json), в других местах шторку
## из дома не открыть.
static func purchase_place() -> String:
	if GameState.house_is_indoors:
		return PLACE_DOOR if GameState.house_room == "hall" else PLACE_HOUSE
	return PLACE_UNDERGROUND if GameState.player_depth >= 1 else PLACE_GARDEN


static func is_gated(kind: String) -> bool:
	return GATED_KINDS.has(kind)


## Покупка за доллары (поле "currency" плитки или запроса) — вне правила места
## и без ролика, счётчик удалённых покупок не трогает (решение владельца,
## раунд 4, ГДД §15). Смешанной цены «монеты + доллары разом» у предложения нет:
## товар с ценой в обеих валютах — две плитки, каждая платится одной валютой,
## и монетная по-прежнему идёт по правилу места.
static func is_dollar_purchase(item: Dictionary) -> bool:
	return String(item.get("currency", "")) == "dollars"


## Можно ли купить предложение (item — плитка витрины или любой словарь с
## "kind" и "currency") в том месте, где стоит игрок: {ok, reason, needs_ad,
## place, left, limit}. За доллары и дома у двери — всегда. Под землёй — пока
## есть лимит, и тогда needs_ad: покупка идёт за ролик и спишет единицу лимита.
## В остальных местах и при пустом лимите — отказ с причиной (она же идёт в
## подсказку плитки).
## Деньги и вес здесь не проверяются — это дело самой покупки.
static func can_buy(item: Dictionary) -> Dictionary:
	var place := purchase_place()
	var res := {"ok": true, "reason": "", "needs_ad": false, "place": place,
		"left": ShopRemote.left_today(), "limit": ShopRemote.limit()}
	if not is_gated(String(item.get("kind", ""))) or is_dollar_purchase(item) or place == PLACE_DOOR:
		return res
	if place == PLACE_UNDERGROUND:
		if int(res["left"]) > 0:
			res["needs_ad"] = true
		else:
			res["ok"] = false
			res["reason"] = "Роликов на сегодня не осталось. За монеты — у входной двери дома."
		return res
	res["ok"] = false
	# Раунд 5, слова владельца: «В огороде покупки напоминают, что покупать надо у
	# входной двери». Про ролик здесь не говорим: на огороде он не нужен и не
	# предлагается, путь один — к двери (ShopUI ведёт туда стрелкой).
	res["reason"] = "Покупки за монеты — у входной двери, в прихожей." if place == PLACE_HOUSE \
			else "Покупки за монеты — у входной двери дома."
	return res


## Отказ can_buy из-за места, а не из-за лимита роликов: огород или другая
## комната дома. Витрина отвечает на него не замком, а напоминанием «к двери».
static func is_door_reminder(gate: Dictionary) -> bool:
	return not bool(gate.get("ok", true)) \
			and String(gate.get("place", "")) in [PLACE_GARDEN, PLACE_HOUSE]


## Платная часть удалённой покупки: «ролик» и единица лимита. Зовётся ПОСЛЕ всех
## проверок покупки (деньги, вес, владение) и ПЕРЕД списанием денег — иначе
## игрок тратил бы просмотр на покупку, которая всё равно не состоится.
static func spend_remote_ad(gate: Dictionary) -> bool:
	return not bool(gate.get("needs_ad", false)) or ShopRemote.watch_ad()


## Хватает ли денег (тот же тумблер «бесплатно», что и в GameState.spend_*):
## нужно, чтобы проверить оплату до ролика, а не после.
static func _can_afford(currency: String, price: int) -> bool:
	if GameState.debug_free_shop:
		return true
	return (GameState.coins if currency == "coins" else GameState.dollars) >= price


static func _emit_bought(id: String, currency: String, remote: bool) -> void:
	var data := {"id": id, "currency": currency}
	if remote:
		data["remote"] = true
	GameState.emit_event(&"bought", data)


# ---------------------------------------------------------------------------
# Продажа сырья (ГДД раздел 15)
# ---------------------------------------------------------------------------

## Цена одной единицы при продаже. 0 — мастерская это не покупает.
static func sell_price(id: String) -> int:
	if not ShopCatalog.is_bought(id):
		return 0
	return Balance.get_mineral_price(id)


## Что из рюкзака можно продать прямо сейчас. Строки отсортированы по сумме:
## в шторке продажи игрок в первую очередь смотрит, что тут дорогого.
static func sellable_stacks() -> Array:
	var rows: Array = []
	for id in GameState.inventory.keys():
		var count := int(GameState.inventory[id])
		if count <= 0:
			continue
		var price := sell_price(String(id))
		if price <= 0:
			continue
		rows.append({
			"id": String(id),
			"count": count,
			"price": price,
			"sum": price * count,
			"weight": Balance.get_mineral_weight(String(id)) * count,
		})
	rows.sort_custom(func(a, b): return a["sum"] > b["sum"])
	return rows


## Сколько монет дадут за выбранное, ДО подтверждения (ГДД раздел 15:
## "показ цен и итоговой суммы перед подтверждением"). Удвоение с рекламы
## сюда не входит намеренно — оно применяется к сделке целиком и видно
## отдельной строкой, иначе игрок не понимает, откуда взялась сумма.
static func quote(items: Dictionary) -> Dictionary:
	var coins := 0
	var count := 0
	var weight := 0.0
	for id in items.keys():
		var want := int(items[id])
		var have := GameState.get_item_count(String(id))
		var n: int = mini(want, have)
		if n <= 0:
			continue
		var price := sell_price(String(id))
		if price <= 0:
			continue
		coins += price * n
		count += n
		weight += Balance.get_mineral_weight(String(id)) * n
	return {"coins": coins, "count": count, "weight": weight}


## Продажа. items: {mineral_id: количество}. Возвращает
## {ok, coins, count, weight, doubled}. Списывает ровно то, что продано, —
## рюкзак легчает на вес проданного.
## remote=true — сдача лута дистанционно (рекламная награда, лимит в ГДД).
static func sell(items: Dictionary, remote: bool = false) -> Dictionary:
	if not remote and not is_at_workshop():
		return {"ok": false, "coins": 0, "count": 0, "weight": 0.0, "doubled": false}
	var q := quote(items)
	if int(q["count"]) <= 0:
		return {"ok": false, "coins": 0, "count": 0, "weight": 0.0, "doubled": false}

	for id in items.keys():
		var want := int(items[id])
		var have := GameState.get_item_count(String(id))
		var n: int = mini(want, have)
		if n <= 0 or sell_price(String(id)) <= 0:
			continue
		GameState.remove_item(String(id), n)

	var coins := int(q["coins"])
	var doubled := false
	# Реклама "удвоить доход при продаже" (ГДД раздел 15) действует на одну
	# сделку целиком, а не на каждую стопку отдельно: иначе выгодно было бы
	# продавать по одной стопке и множитель стоил бы один просмотр на всё.
	if GameState.next_sale_doubled:
		coins *= 2
		doubled = true
		GameState.next_sale_doubled = false

	GameState.add_coins(coins)
	GameState.lifetime_coins_from_sales += coins
	GameState.emit_event(&"sold", {"coins": coins, "count": int(q["count"])})
	SaveSystem.save_game()
	return {"ok": true, "coins": coins, "count": int(q["count"]), "weight": float(q["weight"]), "doubled": doubled}


## Продать всё, что мастерская принимает.
static func sell_all(remote: bool = false) -> Dictionary:
	var items: Dictionary = {}
	for row in sellable_stacks():
		items[row["id"]] = row["count"]
	return sell(items, remote)


## Рекламная награда "скинуть лут на продажу дистанционно" (ГДД раздел 15,
## 3 раза в день): единственный способ продать, не поднимаясь наверх.
static func remote_dump_loot() -> Dictionary:
	if sellable_stacks().is_empty():
		return {"ok": false, "message": "Скидывать нечего"}
	if not GameState.try_use_ad_reward("remote_dump_loot_for_sale"):
		return {"ok": false, "message": "На сегодня лимит дистанционных сдач исчерпан"}
	var result := sell_all(true)
	if not bool(result["ok"]):
		return {"ok": false, "message": "Скидывать нечего"}
	return {"ok": true, "message": "Скинуто %d шт: +%d монет, рюкзак легче на %.0f кг." % [
		int(result["count"]), int(result["coins"]), float(result["weight"])]}


# ---------------------------------------------------------------------------
# Верстак (ГДД раздел 5)
# ---------------------------------------------------------------------------

## Открыт ли рецепт по глубине. Считается по максимальной достигнутой
## глубине: рецепт, однажды открывшийся, назад не закрывается.
static func is_recipe_unlocked(recipe_id: String) -> bool:
	return GameState.max_depth_reached >= ShopCatalog.unlock_depth(recipe_id)


## Техника собирается ИЗ СКЛАДА: ручной бур стоит 500 железа при рюкзаке в 60,
## и за одну ходку их не принести. Склад стоит в мастерской рядом с верстаком
## (ГДД п.14), поэтому материал копится там, а не в «проекте»: вложения
## обратно не доставались, а со склада взять можно.
static func is_project(recipe_id: String) -> bool:
	var r := ShopCatalog.recipe(recipe_id)
	return not r.is_empty() and ["tool", "machine"].has(String(r["kind"]))


## Сколько материала id доступно верстаку: склад ПЛЮС рюкзак. Считать только
## склад было бы работой ради работы — заставлять игрока перекладывать руду
## из рук на полку в двух шагах (ГДД п.14 прямо это и отменяет).
static func held_for(_recipe_id: String, id: String) -> int:
	return HouseStorage.count(id) + GameState.get_item_count(id)


## «На склад»: переложить из рюкзака ровно то, чего рецепту не хватает.
## Тонкая обёртка над складом — своей памяти у верстака больше нет.
## Возвращает {ok, moved: {id: сколько}, message}.
static func invest(recipe_id: String) -> Dictionary:
	var r := ShopCatalog.recipe(recipe_id)
	if r.is_empty():
		return {"ok": false, "moved": {}, "message": "Нет такого рецепта"}
	if not HouseStorage.can_access():
		return {"ok": false, "moved": {}, "message": HouseStorage.access_reason()}
	if not is_recipe_unlocked(recipe_id):
		return {"ok": false, "moved": {}, "message": "Рецепт ещё не открыт"}

	var moved: Dictionary = {}
	for id in r["inputs"].keys():
		var need: int = int(r["inputs"][id]) - HouseStorage.count(String(id))
		if need <= 0:
			continue
		var put := HouseStorage.put(String(id), mini(need, GameState.get_item_count(String(id))))
		if put > 0:
			moved[String(id)] = put
	if moved.is_empty():
		return {"ok": false, "moved": {}, "message": "Нечего складывать"}

	var parts: Array = []
	for id in moved.keys():
		parts.append("%s ×%d" % [ShopCatalog.item_name(String(id)), int(moved[id])])
	SaveSystem.save_game()
	return {"ok": true, "moved": moved, "message": "На склад ушло: " + ", ".join(parts)}


## Чего не хватает для рецепта (count — сколько раз подряд, у переработки
## больше одного): {"ok": bool, "missing": {id: сколько ещё},
## "missing_coins": int, "locked": bool, "reason": String}.
static func check_craft(recipe_id: String, count: int = 1) -> Dictionary:
	var r := ShopCatalog.recipe(recipe_id)
	if r.is_empty():
		return {"ok": false, "missing": {}, "missing_coins": 0, "locked": false, "reason": "Нет такого рецепта"}
	if count < 1 or (count > 1 and not is_batch(recipe_id)):
		return {"ok": false, "missing": {}, "missing_coins": 0, "locked": false, "reason": "Это делается по одной"}
	if not is_at_workshop():
		return {"ok": false, "missing": {}, "missing_coins": 0, "locked": false,
			"reason": "Верстак дома, в подвале"}
	if not is_recipe_unlocked(recipe_id):
		return {"ok": false, "missing": {}, "missing_coins": 0, "locked": true,
			"reason": "Откроется на глубине %d" % ShopCatalog.unlock_depth(recipe_id)}
	if String(r["kind"]) == "tool" and GameState.owns_tool(String(r["output"]["id"])):
		return {"ok": false, "missing": {}, "missing_coins": 0, "locked": false, "reason": "Уже собрано"}
	if String(r["kind"]) == "machine" and _machine_built(String(r["output"]["id"])):
		return {"ok": false, "missing": {}, "missing_coins": 0, "locked": false, "reason": "Уже собрано"}

	var missing: Dictionary = {}
	for id in r["inputs"].keys():
		var need := int(r["inputs"][id]) * count
		var have := held_for(recipe_id, String(id))  # склад + рюкзак
		if have < need:
			missing[String(id)] = need - have
	var missing_coins: int = maxi(0, int(r["coins"]) * count - GameState.coins)
	if not missing.is_empty() or missing_coins > 0:
		return {"ok": false, "missing": missing, "missing_coins": missing_coins, "locked": false,
			"reason": "Не хватает материалов"}
	# Места проверять незачем: у переработки то, что не влезло в рюкзак,
	# ложится на склад (craft_plan), а склад предела не имеет.
	return {"ok": true, "missing": {}, "missing_coins": 0, "locked": false, "reason": ""}


static func can_craft(recipe_id: String) -> bool:
	return bool(check_craft(recipe_id)["ok"])


## Переработка — рецепт, который можно повторять сколько угодно (kind "item":
## плавка бронзы и любой будущий слиток). Слово владельца, раунд 4: «тупо
## делать по одному — надо ползунок». Инструмент и машина — разовые, по одной.
static func is_batch(recipe_id: String) -> bool:
	var r := ShopCatalog.recipe(recipe_id)
	return not r.is_empty() and String(r["kind"]) == "item"


## Сколько раз рецепт можно сделать прямо сейчас — верх ползунка. Считают
## материалы (склад + рюкзак, ГДД §14) и монеты; место не считает: результат
## ложится туда, откуда взято сырьё, а лишнее сверх рюкзака — на склад.
## Разовый рецепт — 0 или 1.
static func max_craft(recipe_id: String) -> int:
	if not is_batch(recipe_id):
		return 1 if can_craft(recipe_id) else 0
	var base := check_craft(recipe_id, 1)
	if not bool(base["ok"]):
		return 0
	var r := ShopCatalog.recipe(recipe_id)
	var most := -1
	for id in r["inputs"].keys():
		var fit := held_for(recipe_id, String(id)) / maxi(1, int(r["inputs"][id]))
		most = fit if most < 0 else mini(most, fit)
	var coins := int(r["coins"])
	if coins > 0:
		most = GameState.coins / coins if most < 0 else mini(most, GameState.coins / coins)
	return maxi(most, 0)


## Раскладка пачки из count переработок ДО списания — по ней крафт работает,
## а карточка показывает итог. Сырьё берётся сначала со склада, потом из
## рюкзака (_consume_input). Результат — туда, откуда пришло его сырьё, как у
## перегонки на станции (FuelRefinery): штука, целиком сделанная из рюкзачного
## сырья, — в рюкзак, пока он выдерживает вес и стопку; остальное — на склад.
## Так ползунок не упирается в рюкзак, а склад не становится чёрным ходом в
## рюкзак (ГДД §14). Возвращает {from_storage: {id: n}, from_pack: {id: n},
## made, to_pack, to_storage, coins}.
static func craft_plan(recipe_id: String, count: int) -> Dictionary:
	var r := ShopCatalog.recipe(recipe_id)
	var plan := {"from_storage": {}, "from_pack": {}, "made": 0, "to_pack": 0, "to_storage": 0, "coins": 0}
	if r.is_empty() or count <= 0:
		return plan
	var pack_units := count
	var freed := 0.0
	for id in r["inputs"].keys():
		var per := maxi(1, int(r["inputs"][id]))
		var total := per * count
		var st := mini(total, HouseStorage.count(String(id)))
		plan["from_storage"][String(id)] = st
		plan["from_pack"][String(id)] = total - st
		# Склад тратится первым, значит рюкзачное сырьё — у последних штук пачки.
		pack_units = mini(pack_units, (total - st) / per)
		freed += Balance.get_mineral_weight(String(id)) * float(total - st)
	var out_id := String(r["output"]["id"])
	var per_out := int(r["output"]["count"])
	plan["made"] = per_out * count
	plan["coins"] = int(r["coins"]) * count
	# Сколько из рюкзачной части реально влезет — те же правила, что у
	# GameState.add_item, но на рюкзак, уже облегчённый на списанное сырьё.
	var want := pack_units * per_out
	var room: int = maxi(0, Balance.get_mineral_max_stack(out_id) - GameState.get_item_count(out_id))
	var w := Balance.get_mineral_weight(out_id)
	if w > 0.0:
		var free := GameState.get_max_carry_kg() - GameState.get_total_weight() + freed
		room = mini(room, int(floor(free / w)) if free > 0.0 else 0)
	plan["to_pack"] = mini(want, room)
	plan["to_storage"] = int(plan["made"]) - int(plan["to_pack"])
	return plan


## Крафт: списывает материалы (склад, потом рюкзак) и монеты, выдаёт
## результат. count > 1 — только у переработки (is_batch), и пачка проходит
## целиком или не проходит вовсе: всё проверяется до первого списания.
## Возвращает {ok, message, count (сколько вышло), used {id: n}, to_pack, to_storage}.
## Без материалов не крафтит и ничего не трогает.
static func craft(recipe_id: String, count: int = 1) -> Dictionary:
	var check := check_craft(recipe_id, count)
	if not bool(check["ok"]):
		return {"ok": false, "message": String(check["reason"]), "count": 0}
	if is_batch(recipe_id):
		return _craft_batch(recipe_id, count)

	var r := ShopCatalog.recipe(recipe_id)
	for id in r["inputs"].keys():
		if not _consume_input(String(id), int(r["inputs"][id])):
			# Сюда попасть нельзя (проверка выше), но если попали — лучше
			# честно отказать, чем списать половину рецепта.
			return {"ok": false, "message": "Материалы кончились"}
	var coins := int(r["coins"])
	if coins > 0 and not GameState.spend_coins(coins):
		return {"ok": false, "message": "Не хватает монет"}

	var out_id := String(r["output"]["id"])
	var message := ""
	if String(r["kind"]) == "tool":
		GameState.grant_tool(out_id)
		GameState.set_current_tool(out_id)
		message = "%s собрана и уже в руках." % String(r["name_ru"])
	else:
		# Машина не берётся в руки и не кладётся в рюкзак: она стоит у дома.
		# Собранная скважина сразу начинает отсчёт — иначе первый же забор
		# выдал бы доход за всё время, что игрок прожил до неё.
		GameState.well_level = 1
		GameState.well_last_collect_unix = int(Time.get_unix_time_from_system())
		message = "%s собрана. Теперь она копает сама." % String(r["name_ru"])
	GameState.emit_event(&"crafted", {"recipe": recipe_id, "item": out_id, "count": 1,
		"to_pack": 0, "to_storage": 0})
	SaveSystem.save_game()
	return {"ok": true, "message": message, "count": 1, "used": (r["inputs"] as Dictionary).duplicate(),
		"to_pack": 0, "to_storage": 0}


## Пачка переработки одной транзакцией. Всё, что может отказать (материалы,
## монеты), проверено в check_craft до первого списания, а результату место
## есть всегда (склад) — поэтому отказа посередине пачки не бывает.
static func _craft_batch(recipe_id: String, count: int) -> Dictionary:
	var r := ShopCatalog.recipe(recipe_id)
	var plan := craft_plan(recipe_id, count)
	for id in (plan["from_pack"] as Dictionary).keys():
		if GameState.get_item_count(String(id)) < int(plan["from_pack"][id]) \
				or HouseStorage.count(String(id)) < int(plan["from_storage"][id]):
			return {"ok": false, "message": "Материалы кончились", "count": 0}
	if int(plan["coins"]) > 0 and not GameState.spend_coins(int(plan["coins"])):
		return {"ok": false, "message": "Не хватает монет", "count": 0}

	var used: Dictionary = {}
	for id in (plan["from_pack"] as Dictionary).keys():
		HouseStorage.consume(String(id), int(plan["from_storage"][id]))
		var from_pack := int(plan["from_pack"][id])
		if from_pack > 0:
			GameState.remove_item(String(id), from_pack)
		used[String(id)] = int(plan["from_storage"][id]) + from_pack

	var out_id := String(r["output"]["id"])
	var made := int(plan["made"])
	var to_pack := GameState.add_item(out_id, int(plan["to_pack"])) if int(plan["to_pack"]) > 0 else 0
	var to_storage := made - to_pack
	if to_storage > 0:
		HouseStorage.store_directly(out_id, to_storage)
	GameState.emit_event(&"crafted", {"recipe": recipe_id, "item": out_id, "count": made,
		"to_pack": to_pack, "to_storage": to_storage})
	SaveSystem.save_game()
	return {"ok": true, "message": "+%d %s" % [made, ShopCatalog.item_name(out_id)], "count": made,
		"used": used, "to_pack": to_pack, "to_storage": to_storage}


## Построена ли машина. Скважина — единственная на сегодня, и её состояние
## живёт в GameState.well_level, а не в списке предметов.
static func _machine_built(machine_id: String) -> bool:
	return machine_id == "well" and GameState.well_level > 0


# ---------------------------------------------------------------------------
# Покупка ступеней: кирки и ранцы (решение владельца)
#
# «Больше не нужно ресурсы собирать для крафта» — шесть кирок и четыре ранца
# берутся за монеты в магазине у входной двери. Рецептов у них нет вовсе, и
# ворот по глубине тоже: воротами прогресса стал ценник.
# ---------------------------------------------------------------------------

## Покупка ступени инструмента за монеты. Отказывает всему, у чего в цене
## есть материалы: такое собирается на верстаке, а не покупается, и продать
## его за одни монеты означало бы дыру в обе стороны.
static func buy_tool(tool_id: String) -> Dictionary:
	if Balance.get_tool(tool_id).is_empty():
		return {"ok": false, "message": "Такого инструмента нет"}
	var gate := can_buy({"kind": "tool"})
	if not bool(gate["ok"]):
		return {"ok": false, "message": String(gate["reason"])}
	if GameState.owns_tool(tool_id):
		return {"ok": false, "message": "Уже есть"}
	if Balance.tool_needs_materials(tool_id):
		return {"ok": false, "message": "Это собирается на верстаке, а не покупается"}
	# Под землёй кирку теперь можно купить за ролик, а бурмобиль там бросить
	# нельзя (решение владельца) — иначе покупка чужой кирки прямо в шахте тихо
	# ссаживала бы героя с машины мимо единственной точки проверки
	# (GameState.set_current_tool).
	if GameState.current_tool == "drill_rig" and tool_id != "drill_rig" \
			and GameState.player_depth >= 1 and not GameState.house_is_indoors:
		return {"ok": false, "message": "Бурмобиль под землёй не бросить — сначала наверх или домой."}
	var price := Balance.get_tool_cost_coins(tool_id)
	if price <= 0:
		return {"ok": false, "message": "Это не продаётся"}
	if not _can_afford("coins", price):
		return {"ok": false, "message": "Не хватает монет"}
	if not spend_remote_ad(gate):
		return {"ok": false, "message": "Роликов на сегодня не осталось."}
	if not GameState.spend_coins(price):
		return {"ok": false, "message": "Не хватает монет"}
	GameState.grant_tool(tool_id)
	# Купленная кирка сразу в руках: покупать её и отдельно идти надевать —
	# лишний шаг. Выбор вручную остаётся на верстаке (верстак = экипировка).
	GameState.set_current_tool(tool_id)
	_emit_bought(tool_id, "coins", bool(gate["needs_ad"]))
	SaveSystem.save_game()
	return {"ok": true, "message": "%s куплена — уже в руках." % Balance.get_tool_name_ru(tool_id),
		"remote": bool(gate["needs_ad"])}


## Покупка ступени ранца за монеты. Надевается сразу, если быстрее надетой
## (этим занимается GameState.grant_gear).
static func buy_gear(gear_id: String) -> Dictionary:
	if Balance.get_gear(gear_id).is_empty():
		return {"ok": false, "message": "Такого ранца нет"}
	var gate := can_buy({"kind": "gear"})
	if not bool(gate["ok"]):
		return {"ok": false, "message": String(gate["reason"])}
	if GameState.has_gear(gear_id):
		return {"ok": false, "message": "Уже есть"}
	var price := Balance.get_gear_cost_coins(gear_id)
	if price <= 0:
		return {"ok": false, "message": "Это не продаётся"}
	if not _can_afford("coins", price):
		return {"ok": false, "message": "Не хватает монет"}
	if not spend_remote_ad(gate):
		return {"ok": false, "message": "Роликов на сегодня не осталось."}
	if not GameState.spend_coins(price):
		return {"ok": false, "message": "Не хватает монет"}
	GameState.grant_gear(gear_id)
	_emit_bought(gear_id, "coins", bool(gate["needs_ad"]))
	SaveSystem.save_game()
	return {"ok": true, "message": "%s куплен." % Balance.get_gear_name_ru(gear_id),
		"remote": bool(gate["needs_ad"])}


# ---------------------------------------------------------------------------
# Апгрейд бура бурмобиля (задача «Апгрейд бура») — четыре ступени строго по
# порядку (титан -> платина -> алмаз -> обсидиан), видны только когда бур сам
# уже куплен (GameState.owns_tool("drill_rig")). Списание — тот же
# GameState.spend_coins, что и у кирок/ранцев/крафта: тумблер debug_free_shop
# учтён им самим, отдельно его здесь не проверяем (см. комментарий у
# spend_coins — «единственная точка списания монет во всей игре»).
# ---------------------------------------------------------------------------

## Следующая ещё не купленная ступень апгрейда бура (1..N) — то, что магазин
## продаёт прямо сейчас; GameState.drill_rig_tier + 1. Больше
## get_drill_rig_tier_count() -> апгрейд уже выбран весь (обсидиан куплен).
static func next_drill_upgrade_tier() -> int:
	return GameState.drill_rig_tier + 1


## Покупка ОДНОЙ следующей ступени апгрейда бура за монеты. Строго
## последовательно: нельзя купить платину, не купив титан, — проверяется
## тем же способом, каким считается "следующая ступень" (GameState.drill_rig_tier
## растёт на 1 за покупку, тир нельзя перескочить).
static func buy_drill_upgrade() -> Dictionary:
	if not GameState.owns_tool("drill_rig"):
		return {"ok": false, "message": "Сначала нужен сам бурмобиль"}
	var gate := can_buy({"kind": "drill"})
	if not bool(gate["ok"]):
		return {"ok": false, "message": String(gate["reason"])}
	var tier := next_drill_upgrade_tier()
	if tier > Balance.get_drill_rig_tier_count():
		return {"ok": false, "message": "Все ступени бура уже куплены"}
	var price := Balance.get_drill_rig_tier_cost_coins(tier)
	if price <= 0:
		return {"ok": false, "message": "Эта ступень ещё не готова к продаже"}
	if not _can_afford("coins", price):
		return {"ok": false, "message": "Не хватает монет"}
	if not spend_remote_ad(gate):
		return {"ok": false, "message": "Роликов на сегодня не осталось."}
	if not GameState.spend_coins(price):
		return {"ok": false, "message": "Не хватает монет"}
	GameState.grant_drill_rig_tier(tier)
	_emit_bought(Balance.get_drill_rig_tier_id(tier), "coins", bool(gate["needs_ad"]))
	SaveSystem.save_game()
	return {"ok": true, "message": "%s установлен — бур стал быстрее." % Balance.get_drill_rig_tier_name_ru(tier),
		"remote": bool(gate["needs_ad"])}


## Списать материал на крафт: сначала со склада, потом из рюкзака. Порядок
## именно такой — на складе лежит то, что уже донесено и никуда не денется, а
## рюкзак игрок, скорее всего, хочет сохранить под обратную дорогу.
static func _consume_input(id: String, amount: int) -> bool:
	var left := amount - HouseStorage.consume(id, amount)
	if left <= 0:
		return true
	return GameState.remove_item(id, left)


static func _free_weight() -> float:
	return GameState.get_max_carry_kg() - GameState.get_total_weight()


# ---------------------------------------------------------------------------
# Лавка и магазин долларов (ГДД разделы 7, 15)
# ---------------------------------------------------------------------------

## Покупка товара. currency: "coins" | "dollars".
## Возвращает {ok, message, effect} — effect отдаётся наверх, потому что
## часть эффектов (телепорт домой) трогает героя, а не GameState.
static func buy(good_id: String, currency: String) -> Dictionary:
	var g := ShopCatalog.good(good_id, currency)
	if g.is_empty():
		return {"ok": false, "message": "Такого товара нет", "effect": ""}
	var price := ShopCatalog.good_price(g, currency)
	if price <= 0:
		return {"ok": false, "message": "Товар без цены", "effect": ""}
	var gate := can_buy({"kind": "good", "currency": currency})
	if not bool(gate["ok"]):
		return {"ok": false, "message": String(gate["reason"]), "effect": ""}

	# Товар-предмет (data/shop.json, effect "grant_item") ложится в рюкзак:
	# вес проверяем ДО оплаты, иначе деньги уйдут, а предмет не влезет.
	if String(g.get("effect", "")) == "grant_item":
		var item := String(g.get("item", ""))
		var count := maxi(1, int(g.get("count", 1)))
		if Balance.get_mineral_weight(item) * count > _free_weight():
			return {"ok": false, "message": "Рюкзак не выдержит — разгрузись", "effect": ""}

	var lack := "монет" if currency == "coins" else "долларов"
	if not _can_afford(currency, price):
		return {"ok": false, "message": "Не хватает " + lack, "effect": ""}
	if not spend_remote_ad(gate):
		return {"ok": false, "message": "Роликов на сегодня не осталось.", "effect": ""}
	var paid := GameState.spend_coins(price) if currency == "coins" else GameState.spend_dollars(price)
	if not paid:
		return {"ok": false, "message": "Не хватает " + lack, "effect": ""}

	var effect := String(g.get("effect", ""))
	var message := apply_effect(g)
	_emit_bought(good_id, currency, bool(gate["needs_ad"]))
	SaveSystem.save_game()
	return {"ok": true, "message": message, "effect": effect, "remote": bool(gate["needs_ad"])}


## Эффект расходника применяется сразу при покупке, а не кладётся в
## инвентарь: допинг, который занимает вес и требует второго тапа, на экране
## 224 px превращается в ещё одну шторку ради одной кнопки. Телепорт
## возвращается наверх строкой — героя двигает ShopUI, GameState о нём не знает.
static func apply_effect(g: Dictionary) -> String:
	var name_ru := String(g.get("name_ru", ""))
	match String(g.get("effect", "")):
		"restore":
			var stamina := float(Balance.unwrap(g.get("stamina_percent", 0)))
			var hunger := float(Balance.unwrap(g.get("hunger_percent", 0)))
			if stamina > 0.0:
				GameState.set_stamina(GameState.stamina + stamina)
			if hunger > 0.0:
				GameState.set_hunger(GameState.hunger + hunger)
			var hp := Healing.food_hp_percent(String(g.get("id", "")))   # еда лечит (раунд 4, healing)
			Healing.heal_percent(hp)
			var parts: Array = []
			if stamina > 0.0:
				parts.append("+%d%% бодрости" % int(stamina))
			if hunger > 0.0:
				parts.append("+%d%% сытости" % int(hunger))
			if hp > 0:
				parts.append("+%d%% здоровья" % hp)
			return "%s: %s" % [name_ru, ", ".join(parts)]
		"full_restore":
			GameState.heal(GameState.get_max_hp())
			GameState.set_stamina(100.0)
			GameState.set_hunger(100.0)
			return "Все три полоски на максимуме."
		"teleport_home":
			return "Часы сработали — ты дома."
		"grant_item":
			var item := String(g.get("item", ""))
			var count := maxi(1, int(g.get("count", 1)))
			GameState.add_item(item, count)
			return "%s ×%d" % [ShopCatalog.item_name(item), count]
		_:
			return name_ru


## Обмен долларов на монеты. Обратно не меняем (см. data/shop.json ->
## exchange): иначе премиум-валюта добывается киркой и покупать её незачем.
static func exchange_dollars_to_coins(dollars: int) -> Dictionary:
	if dollars <= 0:
		return {"ok": false, "message": "Нечего менять", "coins": 0}
	if not GameState.spend_dollars(dollars):
		return {"ok": false, "message": "Столько долларов нет", "coins": 0}
	var coins := dollars * ShopCatalog.coins_per_dollar()
	GameState.add_coins(coins)
	SaveSystem.save_game()
	return {"ok": true, "message": "+%d монет" % coins, "coins": coins}


# ---------------------------------------------------------------------------
# Рекламные награды (ГДД раздел 15) — единственный честный источник долларов
# в этой сборке: платежей нет и выдумывать их нельзя, а лимиты "раз в день"
# уже заданы ГДД и живут в GameState (сброс по реальному UTC-дню).
# ---------------------------------------------------------------------------

static func ad_uses_left(ad_id: String) -> int:
	return maxi(0, Balance.get_ad_daily_limit(ad_id) - GameState.get_ad_uses_today(ad_id))


static func claim_ad(ad_id: String) -> Dictionary:
	var a := ShopCatalog.ad_reward(ad_id)
	if a.is_empty():
		return {"ok": false, "message": "Нет такой награды"}
	if not GameState.try_use_ad_reward(ad_id):
		return {"ok": false, "message": "На сегодня лимит исчерпан"}

	var message := ""
	if a.has("coins"):
		var coins := int(Balance.unwrap(a["coins"]))
		GameState.add_coins(coins)
		message = "+%d монет" % coins
	elif a.has("dollars"):
		var dollars := int(Balance.unwrap(a["dollars"]))
		GameState.add_dollars(dollars)
		message = "+%d $" % dollars
	elif String(a.get("effect", "")) == "double_next_sale":
		GameState.next_sale_doubled = true
		message = "Следующая продажа пойдёт в двойном размере."
	SaveSystem.save_game()
	return {"ok": true, "message": message}


# ---------------------------------------------------------------------------
# Первый визит в мастерскую (ГДД разделы 2 и 9)
# ---------------------------------------------------------------------------

## Дедова кирка не покупается и не крафтится — она находится среди швабр и
## грабель при первом спуске в мастерскую. Возвращает true, если кирку
## выдали именно сейчас (UI покажет это сообщением).
##
## Сюжетная система (scripts/story/) проигрывает сцену мастерской и выдаёт
## кирку эффектом сцены; здесь — тот же результат для случая, когда игрок
## дошёл до верстака мимо сцены. Повторно кирка не выдаётся: проверяется
## список выданного, а не факт визита.
static func visit_workshop() -> bool:
	if GameState.workshop_visited or not is_at_workshop():
		return false
	GameState.workshop_visited = true
	# Смотрим именно на список выданного, а не на owns_tool(): дедова кирка
	# бесплатна, и owns_tool() считает её "своей" ещё до находки — иначе
	# герой застревал бы под фундаментом с одной лопатой.
	var granted := not GameState.owned_tools.has("rusty_pickaxe")
	GameState.grant_tool("rusty_pickaxe")
	if GameState.current_tool == "shovel":
		GameState.set_current_tool("rusty_pickaxe")
	SaveSystem.save_game()
	return granted

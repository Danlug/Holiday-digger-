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


## Лавка и магазин долларов работают где угодно: доллары "доступны всегда и
## везде" (ГДД раздел 15), а батончик по сценарию онбординга едят прямо в
## шахте (раздел 9).
static func can_shop_here() -> bool:
	return true


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


## Инструменты собираются ИЗ СКЛАДА: железная кирка стоит 160 кг материалов
## при рюкзаке в 60, и за одну ходку их не принести. Склад стоит в мастерской
## рядом с верстаком (ГДД п.14), поэтому материал копится там, а не в
## «проекте»: вложения обратно не доставались, а со склада взять можно.
static func is_project(recipe_id: String) -> bool:
	var r := ShopCatalog.recipe(recipe_id)
	return not r.is_empty() and String(r["kind"]) == "tool"


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


## Чего не хватает для рецепта: {"ok": bool, "missing": {id: сколько ещё},
## "missing_coins": int, "locked": bool, "reason": String}.
static func check_craft(recipe_id: String) -> Dictionary:
	var r := ShopCatalog.recipe(recipe_id)
	if r.is_empty():
		return {"ok": false, "missing": {}, "missing_coins": 0, "locked": false, "reason": "Нет такого рецепта"}
	if not is_at_workshop():
		return {"ok": false, "missing": {}, "missing_coins": 0, "locked": false,
			"reason": "Верстак дома, в подвале"}
	if not is_recipe_unlocked(recipe_id):
		return {"ok": false, "missing": {}, "missing_coins": 0, "locked": true,
			"reason": "Откроется на глубине %d" % ShopCatalog.unlock_depth(recipe_id)}
	if String(r["kind"]) == "tool" and GameState.owns_tool(String(r["output"]["id"])):
		return {"ok": false, "missing": {}, "missing_coins": 0, "locked": false, "reason": "Уже собрано"}

	var missing: Dictionary = {}
	for id in r["inputs"].keys():
		var need := int(r["inputs"][id])
		var have := held_for(recipe_id, String(id))  # склад + рюкзак
		if have < need:
			missing[String(id)] = need - have
	var missing_coins: int = maxi(0, int(r["coins"]) - GameState.coins)
	if not missing.is_empty() or missing_coins > 0:
		return {"ok": false, "missing": missing, "missing_coins": missing_coins, "locked": false,
			"reason": "Не хватает материалов"}

	# Плавка и перегонка кладут результат в тот же рюкзак, из которого взяли
	# сырьё. Бронза тяжелее металлолома, и на полном рюкзаке крафт может не
	# влезть по весу — это надо поймать ДО списания ингредиентов.
	if String(r["kind"]) == "item" and _weight_delta(r) > _free_weight():
		return {"ok": false, "missing": {}, "missing_coins": 0, "locked": false,
			"reason": "Рюкзак не выдержит — разгрузись"}
	return {"ok": true, "missing": {}, "missing_coins": 0, "locked": false, "reason": ""}


static func can_craft(recipe_id: String) -> bool:
	return bool(check_craft(recipe_id)["ok"])


## Крафт: списывает вложенное (у инструментов) или ингредиенты из рюкзака (у
## расходников) и монеты, выдаёт результат. Возвращает {ok, message}.
## Без материалов не крафтит и ничего не трогает.
static func craft(recipe_id: String) -> Dictionary:
	var check := check_craft(recipe_id)
	if not bool(check["ok"]):
		return {"ok": false, "message": String(check["reason"])}

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
	var out_count := int(r["output"]["count"])
	var message := ""
	if String(r["kind"]) == "tool":
		GameState.grant_tool(out_id)
		GameState.set_current_tool(out_id)
		message = "%s собрана и уже в руках." % String(r["name_ru"])
	else:
		var added := GameState.add_item(out_id, out_count)
		if added < out_count:
			# Вес проверен заранее, значит упёрлись в потолок стака (99).
			return {"ok": false, "message": "Больше в стопку не влезет"}
		message = "+%d %s" % [out_count, ShopCatalog.item_name(out_id)]
	SaveSystem.save_game()
	return {"ok": true, "message": message}


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


## На сколько килограммов потяжелеет рюкзак от одного крафта.
static func _weight_delta(r: Dictionary) -> float:
	var delta := Balance.get_mineral_weight(String(r["output"]["id"])) * int(r["output"]["count"])
	for id in r["inputs"].keys():
		delta -= Balance.get_mineral_weight(String(id)) * int(r["inputs"][id])
	return delta


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

	var paid := GameState.spend_coins(price) if currency == "coins" else GameState.spend_dollars(price)
	if not paid:
		return {"ok": false, "message": "Не хватает " + ("монет" if currency == "coins" else "долларов"), "effect": ""}

	var effect := String(g.get("effect", ""))
	var message := apply_effect(g)
	SaveSystem.save_game()
	return {"ok": true, "message": message, "effect": effect}


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
			var parts: Array = []
			if stamina > 0.0:
				parts.append("+%d%% бодрости" % int(stamina))
			if hunger > 0.0:
				parts.append("+%d%% сытости" % int(hunger))
			return "%s: %s" % [name_ru, ", ".join(parts)]
		"full_restore":
			GameState.heal(GameState.get_max_hp())
			GameState.set_stamina(100.0)
			GameState.set_hunger(100.0)
			return "Все три полоски на максимуме."
		"teleport_home":
			return "Часы сработали — ты дома."
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

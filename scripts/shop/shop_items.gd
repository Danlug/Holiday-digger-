class_name ShopItems
extends RefCounted
## ShopItems — «предложения» витрины. Превращает каталог (ShopCatalog,
## data/shop.json, balance.json) и состояние игрока в плоские словари, из
## которых ShopUI рисует плитки. Узлов здесь нет: всё проверяется тестом.
##
## Предложение (offer) — Dictionary:
##   key      уникальный ключ "<вид>:<id>" (по нему хранится «новинка»)
##   kind     tool | gear | drill | recipe | food | good | ad | exchange | info |
##            sell | nosale | equip_tool | equip_gear
##   ref      id для сервиса (кирка, ранец, рецепт, товар, ролик, предмет)
##   currency "coins" | "dollars" | "" ; price — цена в этой валюте
##   state    available | poor | owned | locked | away | ready | active | nosale
##   tier     0..5 — цвет рамки; icon — Texture2D
##   title/body/extra — текст подсказки Tip (на самой плитке текста нет)
##   pill     {icon, text, color, pips} — бейдж внизу плитки
##   corner   знак в правом верхнем углу: check | lock | cross | home | gift
##   effects  [{icon, text}] — чипы эффекта на карточке подтверждения
##   compare  {icon, from, to} — «было → станет» на карточке
##   inputs   [{id, icon, have, need}] и coins_need/coins_have — материалы рецепта
## Формат записи товара в data/shop.json — в GDD §16 «Витрина».

const COINS := "coins"
const DOLLARS := "dollars"
const SEEN_KEY := "shop"
const TABS := ["food", "picks", "tech", "sell", "premium"]

const COL_GOOD := ShopArt.COL_GOOD
const COL_BAD := ShopArt.COL_BAD


# ---------------------------------------------------------------------------
# Разделы вкладок
# ---------------------------------------------------------------------------

## Разделы вкладки: [{icon: Texture2D, offers: [...]}]. Пустые разделы не
## отдаются. selected/remote нужны только вкладке «Продать».
static func sections(tab: String, selected: Dictionary = {}, remote: bool = false) -> Array:
	var out: Array = []
	match tab:
		"food":
			out.append({"icon": ShopArt.tex("tab_food"), "offers": food_offers()})
			out.append({"icon": ShopArt.ui("icon_stamina"), "offers": goods_offers("food")})
			out.append({"icon": ShopArt.tex("glyph_video"), "offers": ad_offers("food")})
		"picks":
			out.append({"icon": ShopArt.tex("glyph_dig"), "offers": tool_offers()})
			out.append({"icon": ShopArt.ui("icon_backpack"), "offers": gear_offers()})
			out.append({"icon": ShopArt.ui("icon_stamina"), "offers": goods_offers("picks")})
		"tech":
			out.append({"icon": ShopArt.tex("tab_tech"), "offers": recipe_offers()})
			if GameState.owns_tool("drill_rig"):
				out.append({"icon": ShopArt.load_path("res://art/items/drill_rig_icon.png"),
					"offers": drill_offers()})
			out.append({"icon": ShopArt.ui("icon_stamina"), "offers": goods_offers("tech")})
		"sell":
			out.append({"icon": ShopArt.ui("icon_inventory"), "offers": sell_offers(selected, remote)})
			out.append({"icon": ShopArt.tex("glyph_cross"), "offers": nosale_offers()})
		"premium":
			out.append({"icon": ShopArt.tex("tab_premium"), "offers": goods_offers("premium")})
			out.append({"icon": ShopArt.tex("item_exchange"), "offers": dollar_offers()})
		"equip":
			out.append({"icon": ShopArt.tex("glyph_dig"), "offers": equip_tool_offers()})
			out.append({"icon": ShopArt.ui("icon_backpack"), "offers": equip_gear_offers()})
	var filled: Array = []
	for s in out:
		apply_purchase_rules(s["offers"])
		if not (s["offers"] as Array).is_empty():
			filled.append(s)
	return filled


static func offers_flat(tab: String) -> Array:
	var out: Array = []
	for s in sections(tab):
		out.append_array(s["offers"])
	return out


# ---------------------------------------------------------------------------
# Мелочи
# ---------------------------------------------------------------------------

static func can_pay(currency: String, price: int) -> bool:
	if GameState.debug_free_shop:
		return true
	return (GameState.coins if currency == COINS else GameState.dollars) >= price


static func price_line(currency: String, price: int) -> String:
	return "%s %s" % [ShopArt.full(price), "монет" if currency == COINS else "$"]


static func currency_icon(currency: String) -> Texture2D:
	return ShopArt.ui("icon_coin" if currency == COINS else "icon_dollar")


static func _offer(key: String, kind: String, ref: String) -> Dictionary:
	return {"key": key, "kind": kind, "ref": ref, "state": "available", "tier": 0,
		"currency": "", "price": 0, "title": "", "body": "", "extra": "",
		"pill": {}, "corner": "", "effects": [], "new": false}


static func _eff(glyph: String, text: String) -> Dictionary:
	return {"icon": ShopArt.tex(glyph), "text": text}


## Состояние и бейдж для покупки за деньги.
static func _priced(o: Dictionary, currency: String, price: int) -> void:
	o["currency"] = currency
	o["price"] = price
	var ok := can_pay(currency, price)
	o["state"] = "available" if ok else "poor"
	o["pill"] = {"icon": currency_icon(currency), "text": ShopArt.compact(price),
		"color": Color.WHITE if ok else COL_BAD}
	if ok:
		o["extra"] = price_line(currency, price)
	else:
		var have := GameState.coins if currency == COINS else GameState.dollars
		o["extra"] = "%s. Не хватает: %s" % [price_line(currency, price), ShopArt.full(price - have)]


static func _owned(o: Dictionary, text: String = "Уже есть") -> void:
	o["state"] = "owned"
	o["corner"] = "check"
	o["pill"] = {}
	o["extra"] = text


static func _locked(o: Dictionary, text: String, pill: Dictionary = {}) -> void:
	o["state"] = "locked"
	o["pill"] = pill
	o["extra"] = text


# ---------------------------------------------------------------------------
# Где можно покупать (ShopService.can_buy): состояние плитки по месту игрока
# ---------------------------------------------------------------------------

## Дома у двери плитки как были. Под землёй, пока есть ролики: бейдж «осталось
## N/3» на значке и значок ролика в левом углу (покупка спишет один просмотр).
## Вне двери и без роликов: плитка тускнеет, в правом углу замок, причина — в Tip
## (state «away», а не «locked»: «заперто» — это про глубину, и такие плитки
## не считаются виденными, а эти должны остаться «как были» для двери).
## Купленное, запертое по глубине и всё, что вне правила (в том числе любые
## плитки за доллары — их можно купить где угодно), не трогаем.
static func apply_purchase_rules(offers: Array) -> void:
	for o in offers:
		var gate := ShopService.can_buy(o)
		var st := String(o["state"])
		if (st != "available" and st != "poor") or (bool(gate["ok"]) and not bool(gate["needs_ad"])):
			continue
		o["place"] = String(gate["place"])
		if bool(gate["ok"]):
			o["needs_ad"] = true
			o["ad_left"] = int(gate["left"])
			o["ad_limit"] = int(gate["limit"])
			o["count_text"] = "%d/%d" % [int(gate["left"]), int(gate["limit"])]
			o["corner_tl"] = "video"
			o["extra"] = "%s · за ролик, осталось %d из %d" % [String(o["extra"]), int(gate["left"]), int(gate["limit"])]
			continue
		o["state"] = "away"
		o["corner"] = "lock"
		o["new"] = false
		o["lock_reason"] = String(gate["reason"])
		o["extra"] = String(gate["reason"])
		if String(gate["place"]) == ShopService.PLACE_UNDERGROUND:
			o["count_text"] = "0/%d" % int(gate["limit"])


# ---------------------------------------------------------------------------
# Снаряжение: кирки и ранцы за монеты
# ---------------------------------------------------------------------------

static func tool_offers() -> Array:
	var out: Array = []
	var rows := ShopCatalog.pickaxes()
	var cur := Equipment.current_dig_multiplier()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var id := String(r["id"])
		var price := int(r["price_coins"])
		var speed := float(r["speed_multiplier"])
		var o := _offer("tool:" + id, "tool", id)
		o["icon"] = ShopArt.load_path(String(r.get("icon", "")))
		o["tier"] = ShopArt.tier_for(i, rows.size())
		o["title"] = String(r["name_ru"])
		o["body"] = String(r["desc_ru"])
		o["effects"] = [_eff("glyph_dig", "×" + ShopCatalog.mult_text(speed))]
		o["compare"] = {"icon": ShopArt.tex("glyph_dig"), "from": "×" + ShopCatalog.mult_text(cur),
			"to": "×" + ShopCatalog.mult_text(speed)}
		if GameState.owns_tool(id):
			_owned(o)
		elif price <= 0:
			# Ржавая кирка не продаётся: она лежит в мастерской среди удочек и лопат.
			_locked(o, "Не продаётся: лежит в мастерской", {"icon": ShopArt.tex("glyph_house")})
		else:
			_priced(o, COINS, price)
		out.append(o)
	_flag_new(out)
	return out


static func gear_offers() -> Array:
	var out: Array = []
	var rows := ShopCatalog.gear_line()
	var cur := Balance.get_gear_fly_multiplier(GameState.current_gear) if GameState.current_gear != "" else 0.0
	for i in rows.size():
		var r: Dictionary = rows[i]
		var id := String(r["id"])
		var price := int(r["price_coins"])
		var fly := float(r["fly_multiplier"])
		var o := _offer("gear:" + id, "gear", id)
		o["icon"] = ShopArt.load_path(String(r.get("icon", "")))
		o["tier"] = ShopArt.tier_for(i, rows.size())
		o["title"] = String(r["name_ru"])
		o["body"] = String(r["desc_ru"])
		o["effects"] = [_eff("glyph_fly", "×" + ShopCatalog.mult_text(fly))]
		o["compare"] = {"icon": ShopArt.tex("glyph_fly"), "from": "×" + ShopCatalog.mult_text(cur),
			"to": "×" + ShopCatalog.mult_text(fly)}
		if GameState.has_gear(id):
			_owned(o)
		else:
			_priced(o, COINS, price)
		out.append(o)
	_flag_new(out)
	return out


## Ступени апгрейда бурмобиля: покупаются строго по порядку.
static func drill_offers() -> Array:
	var out: Array = []
	for row in ShopCatalog.drill_upgrade_rows():
		var id := String(row["id"])
		var tier := int(row["tier"])
		var o := _offer("drill:" + id, "drill", id)
		o["icon"] = ShopArt.load_path(String(row.get("icon", "")))
		if o["icon"] == null:
			o["icon"] = ShopArt.load_path("res://art/items/drill_rig_icon.png")
		o["tier"] = tier
		o["title"] = String(row["name_ru"])
		o["body"] = String(row["desc_ru"])
		o["effects"] = [_eff("glyph_dig", "×" + ShopCatalog.mult_text(float(row["speed_multiplier"])))]
		match String(row["status"]):
			"owned":
				_owned(o)
			"locked":
				_locked(o, "Сначала %s" % Balance.get_drill_rig_tier_name_ru(tier - 1).to_lower(),
					{"icon": ShopArt.ui("icon_coin"), "text": ShopArt.compact(int(row["price_coins"])),
					"color": Color(0.7, 0.7, 0.75)})
			_:
				_priced(o, COINS, int(row["price_coins"]))
		out.append(o)
	_flag_new(out)
	return out


# ---------------------------------------------------------------------------
# Техника: рецепты из материалов
# ---------------------------------------------------------------------------

const RECIPE_TIER := {"bronze": 0, "hand_drill": 3,
	"drill_rig": 4, "well": 5}


static func recipe_offers() -> Array:
	var out: Array = []
	for r in ShopCatalog.recipes():
		var rid := String(r["id"])
		var check := ShopService.check_craft(rid)
		var o := _offer("recipe:" + rid, "recipe", rid)
		o["icon"] = recipe_icon(r)
		o["tier"] = int(RECIPE_TIER.get(rid, 2))
		o["title"] = String(r["name_ru"])
		o["body"] = String(r["desc_ru"])

		var inputs: Array = []
		var pips: Array = []
		for id in (r["inputs"] as Dictionary).keys():
			var need := int(r["inputs"][id])
			var have := ShopService.held_for(rid, String(id))
			inputs.append({"id": String(id), "icon": ShopArt.item_icon(String(id)), "have": have, "need": need})
			pips.append(have >= need)
		var coins_need := int(r["coins"])
		if coins_need > 0:
			pips.append(GameState.coins >= coins_need or GameState.debug_free_shop)
		o["inputs"] = inputs
		o["coins_need"] = coins_need
		o["coins_have"] = GameState.coins
		o["craft_kind"] = String(r["kind"])
		o["can_invest"] = ShopService.is_project(rid) and bool(not check["ok"]) \
				and not bool(check["locked"]) and String(check["reason"]) != "Уже собрано" \
				and HouseStorage.can_access()

		var reason := String(check["reason"])
		if bool(check["ok"]):
			o["state"] = "ready"
			o["pill"] = {"pips": pips}
			o["extra"] = "Материалов хватает — можно собирать"
		elif bool(check["locked"]):
			_locked(o, reason, {"icon": ShopArt.tex("glyph_depth"),
				"text": ShopArt.compact(ShopCatalog.unlock_depth(rid)), "color": Color.WHITE})
		elif reason == "Уже собрано":
			_owned(o, reason)
		elif reason == "Верстак дома, в подвале":
			o["state"] = "away"
			o["corner"] = "home"
			o["pill"] = {"pips": pips}
			o["extra"] = reason
		else:
			o["state"] = "poor"
			o["pill"] = {"pips": pips}
			o["extra"] = reason
			if reason != "Не хватает материалов":
				o["corner"] = "cross"
		# Переработка (ползунок в карточке): на плитке — на сколько штук хватает.
		if o["state"] == "ready" and ShopService.is_batch(rid):
			var most := ShopService.max_craft(rid)
			o["pill"] = {"pips": pips, "text": "×" + ShopArt.compact(most), "color": COL_GOOD}
			o["extra"] = "Хватит на %s" % ShopArt.full(most)
		out.append(o)
	_flag_new(out)
	return out


static func recipe_icon(r: Dictionary) -> Texture2D:
	var t := ShopArt.tex("item_" + String(r["id"]))
	if t != null:
		return t
	var out_id := String(r["output"]["id"])
	match String(r["kind"]):
		"tool":
			return ShopArt.load_path(Balance.get_tool_icon(out_id))
		"machine":
			return ShopArt.tex("item_" + out_id)
	return ShopArt.item_icon(out_id)


# ---------------------------------------------------------------------------
# Еда, допинги, гаджеты
# ---------------------------------------------------------------------------

static func food_offers() -> Array:
	var out: Array = []
	var menu := HouseConfig.delivery_menu()
	var n := menu.size()
	for i in n:
		var f: Dictionary = menu[i]
		var id := String(f.get("id", ""))
		var check := HouseFood.can_order(id)
		var price := HouseConfig.food_price_coins(id)
		var hunger := int(round(HouseConfig.food_hunger_percent(id)))
		var stamina := int(round(HouseConfig.food_stamina_percent(id)))
		var portable := HouseConfig.is_portable(id)
		var o := _offer("food:" + id, "food", id)
		o["icon"] = ShopArt.item_icon(id)
		o["tier"] = ShopArt.tier_for(i, n)
		o["title"] = HouseConfig.food_name(id)
		var parts: Array = ["голод +%d%%" % hunger]
		if stamina > 0:
			parts.append("бодрость +%d%%" % stamina)
		parts.append("с собой" if portable else "только дома, съедается сразу")
		o["body"] = ", ".join(parts)
		var effects: Array = [{"icon": ShopArt.ui("icon_hunger"), "text": "+%d" % hunger}]
		if stamina > 0:
			effects.append({"icon": ShopArt.ui("icon_stamina"), "text": "+%d" % stamina})
		if not portable:
			effects.append(_eff("glyph_house", ""))
		o["effects"] = effects
		if bool(check.get("free", false)):
			o["currency"] = COINS
			o["price"] = 0
			o["free"] = true
			o["state"] = "available"
			o["pill"] = {"icon": ShopArt.ui("icon_coin"), "text": "0", "color": COL_GOOD}
			o["corner"] = "gift"
			o["extra"] = "Бесплатно: бабка оставила денег"
		else:
			_priced(o, COINS, price)
			if not portable:
				o["corner"] = "home"
		out.append(o)
	_flag_new(out)
	return out


## Товары лавки из каталога. Записи data/shop.json (goods_coins.extra,
## goods_dollars.extra) могут задавать shelf (на какую полку: food, picks, tech,
## premium), icon, tier, unlock_depth, effects, effect "grant_item" (item, count).
static func goods_offers(shelf: String) -> Array:
	var out: Array = []
	for currency in [COINS, DOLLARS]:
		var list: Array = ShopCatalog.goods_coins() if currency == COINS else ShopCatalog.goods_dollars()
		var default_shelf := "food" if currency == COINS else "premium"
		for g in list:
			if String(g.get("shelf", default_shelf)) != shelf:
				continue
			out.append(_good_offer(g, currency))
	_flag_new(out)
	return out


static func _good_offer(g: Dictionary, currency: String) -> Dictionary:
	var id := String(g.get("id", ""))
	var price := ShopCatalog.good_price(g, currency)
	var o := _offer("good:%s:%s" % [currency, id], "good", id)
	var icon_path := String(g.get("icon", ""))
	o["icon"] = ShopArt.load_path(icon_path) if icon_path != "" else ShopArt.item_icon(id)
	if o["icon"] == null:
		o["icon"] = ShopArt.item_icon(id)
	o["tier"] = int(g.get("tier", 4 if currency == DOLLARS else 0))
	o["title"] = String(g.get("name_ru", id))
	o["body"] = String(g.get("desc_ru", ""))
	o["effects"] = good_effects(g)
	_priced(o, currency, price)
	var depth := int(Balance.unwrap(g.get("unlock_depth", 0)))
	if depth > GameState.max_depth_reached:
		_locked(o, "Откроется на глубине %d" % depth, {"icon": ShopArt.tex("glyph_depth"),
			"text": ShopArt.compact(depth), "color": Color.WHITE})
	return o


static func good_effects(g: Dictionary) -> Array:
	var out: Array = []
	for e in g.get("effects", []):
		var icon_path := String(e.get("icon", ""))
		var t: Texture2D = ShopArt.load_path(icon_path) if icon_path.begins_with("res://") \
				else ShopArt.tex(icon_path)
		out.append({"icon": t, "text": String(e.get("text", ""))})
	if not out.is_empty():
		return out
	match String(g.get("effect", "")):
		"restore":
			var stamina := int(Balance.unwrap(g.get("stamina_percent", 0)))
			var hunger := int(Balance.unwrap(g.get("hunger_percent", 0)))
			if stamina > 0:
				out.append({"icon": ShopArt.ui("icon_stamina"), "text": "+%d" % stamina})
			if hunger > 0:
				out.append({"icon": ShopArt.ui("icon_hunger"), "text": "+%d" % hunger})
		"full_restore":
			out.append({"icon": ShopArt.ui("icon_hp"), "text": "100"})
			out.append({"icon": ShopArt.ui("icon_stamina"), "text": "100"})
			out.append({"icon": ShopArt.ui("icon_hunger"), "text": "100"})
		"teleport_home":
			out.append(_eff("glyph_house", ""))
		"grant_item":
			out.append({"icon": ShopArt.item_icon(String(g.get("item", ""))),
				"text": "×%d" % maxi(1, int(g.get("count", 1)))})
	return out


# ---------------------------------------------------------------------------
# Ролики, обмен и закрытая покупка долларов
# ---------------------------------------------------------------------------

## Ролики полки: small_coins лежит на «Еде», small_premium_currency — в премиуме.
## double_income_on_sale живёт на панели «Продать» и плиткой не рисуется.
static func ad_offers(shelf: String) -> Array:
	var out: Array = []
	for a in ShopCatalog.ad_rewards():
		var id := String(a.get("id", ""))
		var home := "premium" if a.has("dollars") else ("food" if a.has("coins") else "")
		if home != shelf:
			continue
		out.append(ad_offer(a))
	return out


static func ad_offer(a: Dictionary) -> Dictionary:
	var id := String(a.get("id", ""))
	var left := ShopService.ad_uses_left(id)
	var limit := Balance.get_ad_daily_limit(id)
	var o := _offer("ad:" + id, "ad", id)
	o["icon"] = ShopArt.tex("item_ad_tv")
	o["tier"] = 2
	o["title"] = String(a.get("name_ru", id))
	o["body"] = "Посмотреть ролик"
	var coins := a.has("coins")
	var amount := int(Balance.unwrap(a.get("coins", a.get("dollars", 0))))
	o["count_text"] = "%d/%d" % [left, limit]
	o["pill"] = {"icon": ShopArt.ui("icon_coin" if coins else "icon_dollar"),
		"text": "+" + ShopArt.compact(amount), "color": COL_GOOD}
	o["extra"] = "Сегодня осталось: %d из %d" % [left, limit]
	o["left"] = left
	o["state"] = "available" if left > 0 else "poor"
	return o


static func dollar_offers() -> Array:
	var out: Array = []
	var ex := _offer("exchange:1", "exchange", "1")
	var per := ShopCatalog.coins_per_dollar()
	ex["icon"] = ShopArt.tex("item_exchange")
	ex["tier"] = 2
	ex["title"] = "Обмен долларов на монеты"
	ex["body"] = "1 $ = %d монет. Обратно не меняем." % per
	ex["effects"] = [{"icon": ShopArt.ui("icon_coin"), "text": "+" + ShopArt.compact(per)}]
	_priced(ex, DOLLARS, 1)
	out.append(ex)
	out.append_array(ad_offers("premium"))
	var buy := _offer("info:buy_dollars", "info", "buy_dollars")
	buy["icon"] = ShopArt.tex("item_buy_dollars")
	buy["tier"] = 4
	buy["title"] = "Купить доллары"
	buy["body"] = "В этой сборке платежей нет. Доллары дают ролики, клады и закрытые ветки коллекции."
	_locked(buy, "Недоступно", {})
	buy["hide_lock"] = false
	out.append(buy)
	return out


# ---------------------------------------------------------------------------
# Продажа: рюкзак
# ---------------------------------------------------------------------------

## Ступень рамки стопки по цене штуки: дешёвый лом серый, алмаз золотой.
static func price_tier(unit_price: int) -> int:
	if unit_price < 10:
		return 0
	if unit_price < 60:
		return 1
	if unit_price < 250:
		return 2
	if unit_price < 1000:
		return 3
	if unit_price < 5000:
		return 4
	return 5


static func sell_offers(selected: Dictionary, remote: bool) -> Array:
	var out: Array = []
	for row in ShopService.sellable_stacks():
		var id := String(row["id"])
		var o := _offer("sell:" + id, "sell", id)
		o["icon"] = ShopArt.item_icon(id)
		o["tier"] = price_tier(int(row["price"]))
		o["title"] = ShopCatalog.item_name(id)
		o["body"] = "%d шт по %s" % [int(row["count"]), ShopArt.full(int(row["price"]))]
		o["extra"] = "За стопку: %s монет" % ShopArt.full(int(row["sum"]))
		o["count"] = int(row["count"])
		o["count_text"] = ShopArt.compact(int(row["count"]))
		o["sum"] = int(row["sum"])
		o["price"] = int(row["price"])
		o["pill"] = {"icon": ShopArt.ui("icon_coin"), "text": ShopArt.compact(int(row["sum"])),
			"color": ShopArt.COL_GOLD}
		if not remote:
			o["selected"] = bool(selected.get(id, false))
		ProjectChain.decorate_offer(o, id)   # «нужно для бура: 40/100» (ветка guidance)
		out.append(o)
	return out


## Что лежит в рюкзаке, но мастерская не берёт: показываем приглушённо, чтобы
## игрок не думал, что продажа сломалась.
static func nosale_offers() -> Array:
	var out: Array = []
	var ids: Array = GameState.inventory.keys()
	ids.sort()
	for id in ids:
		var count := int(GameState.inventory[id])
		if count <= 0 or ShopService.sell_price(String(id)) > 0:
			continue
		var o := _offer("nosale:" + String(id), "nosale", String(id))
		o["icon"] = ShopArt.item_icon(String(id))
		o["state"] = "nosale"
		o["corner"] = "cross"
		o["title"] = ShopCatalog.item_name(String(id))
		o["body"] = "Мастерская не скупает: это материал или то, что она сама делает."
		o["count_text"] = ShopArt.compact(count)
		out.append(o)
	return out


# ---------------------------------------------------------------------------
# Верстак: надеть
# ---------------------------------------------------------------------------

static func equip_tool_offers() -> Array:
	var out: Array = []
	var rows := Equipment.pickaxe_rows()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var id := String(r["id"])
		var o := _offer("equip_tool:" + id, "equip_tool", id)
		o["icon"] = ShopArt.load_path(String(r.get("icon", "")))
		o["tier"] = ShopArt.tier_for(i, rows.size())
		o["title"] = String(r["name_ru"])
		o["body"] = String(r["desc_ru"])
		o["pill"] = {"icon": ShopArt.tex("glyph_dig"), "text": "×" + ShopCatalog.mult_text(float(r["speed_multiplier"])),
			"color": Color.WHITE}
		_equip_state(o, bool(r["owned"]), bool(r["active"]), "В руках", "Тап — взять в руки",
			"Ещё не куплена: магазин у входной двери")
		out.append(o)
	return out


static func equip_gear_offers() -> Array:
	var out: Array = []
	var rows := Equipment.gear_rows()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var id := String(r["id"])
		var o := _offer("equip_gear:" + id, "equip_gear", id)
		o["icon"] = ShopArt.load_path(String(r.get("icon", "")))
		o["tier"] = ShopArt.tier_for(i, rows.size())
		o["title"] = String(r["name_ru"])
		o["body"] = String(r["desc_ru"])
		o["pill"] = {"icon": ShopArt.tex("glyph_fly"), "text": "×" + ShopCatalog.mult_text(float(r["fly_multiplier"])),
			"color": Color.WHITE}
		_equip_state(o, bool(r["owned"]), bool(r["active"]), "Надет", "Тап — надеть",
			"Ещё не куплен: магазин у входной двери")
		out.append(o)
	return out


static func _equip_state(o: Dictionary, owned: bool, active: bool, on_text: String,
		tap_text: String, missing_text: String) -> void:
	if active:
		o["state"] = "active"
		o["corner"] = "check"
		o["extra"] = on_text
	elif owned:
		o["state"] = "available"
		o["extra"] = tap_text if Equipment.is_at_workbench() else "Переодеться можно у верстака в мастерской"
		if not Equipment.is_at_workbench():
			o["state"] = "away"
			o["corner"] = "home"
	else:
		o["state"] = "locked"
		o["extra"] = missing_text


# ---------------------------------------------------------------------------
# «Новинка»: что игрок уже видел
# ---------------------------------------------------------------------------

static func _seen_set() -> Dictionary:
	var d = GameState.ext_get(SEEN_KEY, {})
	var out: Dictionary = {}
	if typeof(d) == TYPE_DICTIONARY:
		for k in d.get("seen", []):
			out[String(k)] = true
	return out


## Плитка с пометкой «новинка»: товар виден, не заперт, не куплен и ни разу не
## показывался игроку.
static func _flag_new(offers: Array) -> void:
	var seen := _seen_set()
	for o in offers:
		var st := String(o["state"])
		o["new"] = (st == "available" or st == "poor" or st == "ready") and not seen.has(String(o["key"]))


static func mark_seen(keys: Array) -> void:
	var d = GameState.ext_get(SEEN_KEY, {})
	var cur: Dictionary = (d as Dictionary).duplicate() if typeof(d) == TYPE_DICTIONARY else {}
	var seen: Array = (cur.get("seen", []) as Array).duplicate()
	var changed := false
	for k in keys:
		if not seen.has(String(k)):
			seen.append(String(k))
			changed = true
	if changed:
		cur["seen"] = seen
		GameState.ext_set(SEEN_KEY, cur)


## Первое открытие магазина: всё, что уже лежит на полках, считается виденным,
## иначе у нового игрока вся витрина горела бы «новинками».
static func seed_seen() -> void:
	var d = GameState.ext_get(SEEN_KEY, {})
	if typeof(d) == TYPE_DICTIONARY and (d as Dictionary).has("seen"):
		return
	var keys: Array = []
	for tab in TABS:
		if tab == "sell":
			continue
		for o in offers_flat(tab):
			if String(o["state"]) != "locked":
				keys.append(String(o["key"]))
	# Ключ «shop» делят «новинки» и счётчик удалённых покупок (ShopRemote): чужое не затираем.
	var cur: Dictionary = (d as Dictionary).duplicate() if typeof(d) == TYPE_DICTIONARY else {}
	cur["seen"] = keys
	GameState.ext_set(SEEN_KEY, cur)


static func new_count(tab: String) -> int:
	if tab == "sell":
		return 0
	var n := 0
	for o in offers_flat(tab):
		if bool(o["new"]):
			n += 1
	return n


static func new_keys(tab: String) -> Array:
	var out: Array = []
	for o in offers_flat(tab):
		if bool(o["new"]):
			out.append(String(o["key"]))
	return out

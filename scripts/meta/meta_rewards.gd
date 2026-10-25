class_name MetaRewards
extends RefCounted
## Выдача наград мета-слоя. Награда — {coins, dollars, xp, item:{id,count}}.
##
## Доллары (ГДД раздел 15): повторяемые источники (ежедневная награда, задания)
## упираются в недельный потолок premium_cap.per_week; одноразовые (достижения,
## дорога трофеев) — нет, их общий размер ограничен самим списком. Из idle
## доллары не идут вовсе: этот класс зовут только по действию игрока.

## Монет за единицу предмета, который не влез в рюкзак: награда не пропадает.
const ITEM_FALLBACK_COINS := 50


static func normalize(r: Dictionary) -> Dictionary:
	var out := {}
	for k in ["coins", "dollars", "xp"]:
		var v := int(r.get(k, 0))
		if v > 0:
			out[k] = v
	var it = r.get("item")
	if typeof(it) == TYPE_DICTIONARY and int(it.get("count", 0)) > 0 and String(it.get("id", "")) != "":
		out["item"] = {"id": String(it["id"]), "count": int(it["count"])}
	return out


## Монеты и опыт умножаются, доллары и предметы — нет (ролик «×2», бонус серии).
static func scaled(r: Dictionary, mult: float) -> Dictionary:
	var out := normalize(r)
	for k in ["coins", "xp"]:
		if out.has(k):
			out[k] = int(round(float(out[k]) * mult))
	return out


## Сколько долларов повторяемые источники ещё могут выдать на этой неделе.
static func dollars_left_this_week() -> int:
	var cap := int(MetaData.daily().get("premium_cap", {}).get("per_week", 0))
	var w := MetaState.sub("wk_dollars")
	var week := MetaClock.week_of(MetaState.today())
	if int(w.get("week", -1)) != week:
		w["week"] = week
		w["n"] = 0
	return maxi(0, cap - int(w.get("n", 0)))


## Выдаёт награду. repeatable — считать доллары в недельный потолок.
## Возвращает то, что реально выдано (доллары могли обрезаться потолком).
static func grant(reward: Dictionary, repeatable: bool = false) -> Dictionary:
	var r := normalize(reward)
	if r.has("dollars") and repeatable:
		var left := dollars_left_this_week()
		var give := mini(int(r["dollars"]), left)
		if give > 0:
			MetaState.sub("wk_dollars")["n"] = int(MetaState.sub("wk_dollars")["n"]) + give
			r["dollars"] = give
		else:
			r.erase("dollars")
	if r.has("item"):
		var added := GameState.add_item(String(r["item"]["id"]), int(r["item"]["count"]))
		var lost := int(r["item"]["count"]) - added
		if lost > 0:
			r["coins"] = int(r.get("coins", 0)) + lost * ITEM_FALLBACK_COINS
		if added <= 0:
			r.erase("item")
		else:
			r["item"]["count"] = added
	if r.has("coins"):
		GameState.add_coins(int(r["coins"]))
	if r.has("dollars"):
		GameState.add_dollars(int(r["dollars"]))
	if r.has("xp"):
		GameState.add_xp(int(r["xp"]))
	return r


## Подпись награды для подсказки: «130 монет · 40 опыта».
static func describe(reward: Dictionary) -> String:
	var r := normalize(reward)
	var parts: Array[String] = []
	if r.has("coins"):
		parts.append("%d монет" % int(r["coins"]))
	if r.has("dollars"):
		parts.append("%d $" % int(r["dollars"]))
	if r.has("xp"):
		parts.append("%d опыта" % int(r["xp"]))
	if r.has("item"):
		parts.append("%s ×%d" % [_item_name(String(r["item"]["id"])), int(r["item"]["count"])])
	return " · ".join(parts)


static func _item_name(id: String) -> String:
	var m: Dictionary = Balance.get_mineral(id)
	return String(m.get("name_ru", id))

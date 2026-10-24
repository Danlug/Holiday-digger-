class_name MetaAds
extends RefCounted
## Rewarded-ролики мета-слоя: «×2» на ежедневной награде и заданиях, замена
## задания дня сверх бесплатной.
##
## Лимиты — по существующей схеме: Balance.get_ad_daily_limit(id) читает
## data/balance.json -> ads.daily_limits, использования копит
## GameState.ad_daily_counts и сбрасывает по UTC-суткам (daily_reset). Наших двух
## точек показа в ГДД раздел 15 пока нет, поэтому, если в balance.json для id
## лимита нет, берётся предложенный (proposed) из наших data-файлов — и счёт
## идёт в те же ad_daily_counts. Появится строка в balance.json — она главнее.
##
## Рекламной сети в сборке нет (см. ad_manager.gd): пока AdManager.is_ad_ready()
## ложно, награда выдаётся сразу — так же, как ShopService.claim_ad. С настоящим
## SDK награда придёт только из ad_reward_earned.

const DAILY := "daily_reward_double"
const QUEST := "quest_reward_double"
const REROLL := "quest_reroll"


static func limit(placement: String) -> int:
	var l := Balance.get_ad_daily_limit(placement)
	if l > 0:
		return l
	var d: Dictionary = MetaData.daily().get("ad_double", {})
	if String(d.get("placement", "")) == placement:
		return int(d.get("daily_limit", 0))
	var q: Dictionary = MetaData.quests().get("ad_double", {})
	if String(q.get("placement", "")) == placement:
		return int(q.get("daily_limit", 0))
	var rr: Dictionary = MetaData.quests().get("daily", {}).get("reroll", {})
	if String(rr.get("ad_placement", "")) == placement:
		return int(rr.get("ad_daily_limit", 0))
	return 0


static func uses_left(placement: String) -> int:
	return maxi(0, limit(placement) - GameState.get_ad_uses_today(placement))


static func can(placement: String) -> bool:
	return uses_left(placement) > 0


static func consume(placement: String) -> bool:
	if not can(placement):
		return false
	GameState.ad_daily_counts[placement] = GameState.get_ad_uses_today(placement) + 1
	return true


## Запускает показ; on_granted зовётся, когда награду пора выдавать. false —
## лимит на сегодня исчерпан (ничего не показано, ничего не списано).
static func request(placement: String, on_granted: Callable) -> bool:
	if not can(placement):
		return false
	if not AdManager.is_ad_ready(placement):
		consume(placement)
		on_granted.call()
		return true
	var holder: Array = []
	var cleanup := func() -> void:
		for c in holder:
			if AdManager.ad_reward_earned.is_connected(c[0]):
				AdManager.ad_reward_earned.disconnect(c[0])
			if AdManager.ad_failed.is_connected(c[1]):
				AdManager.ad_failed.disconnect(c[1])
		holder.clear()
	var on_earned := func(pid: String) -> void:
		if pid != placement:
			return
		cleanup.call()
		if consume(placement):
			on_granted.call()
	var on_failed := func(pid: String, _reason: String) -> void:
		if pid == placement:
			cleanup.call()
	holder.append([on_earned, on_failed])
	AdManager.ad_reward_earned.connect(on_earned)
	AdManager.ad_failed.connect(on_failed)
	AdManager.show_rewarded_ad(placement)
	return true

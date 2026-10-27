class_name TechAds
extends RefCounted
## Ролик «×2» в окне отчёта скважины. Идёт через AdManager (каркас под
## rewarded-видео): когда у него есть готовый ролик, награда выдаётся ТОЛЬКО по
## его сигналу «досмотрено». Пока рекламной сети нет (is_ad_ready всегда false),
## выдаём награду сразу — тем же честным путём, что ShopService.claim_ad
## (docs/MONETIZATION.md): лимит в сутки соблюдается, видео нет.
##
## Удваивает добытое на склад и НИКОГДА — доллары (решение владельца).

const PLACEMENT := "well_report_double"


static func daily_limit() -> int:
	return int(TechData.v(TechData.well().get("ad_double", {}).get("daily_limit", 3)))


static func used_today() -> int:
	return int(GameState.ad_daily_counts.get(PLACEMENT, 0))


static func left_today() -> int:
	return maxi(0, daily_limit() - used_today())


## Просит ролик; on_result(ok: bool) вызывается ровно один раз.
static func request(on_result: Callable) -> void:
	GameState._check_daily_reset()
	if left_today() <= 0:
		on_result.call(false)
		return
	if AdManager.is_ad_ready(PLACEMENT):
		_show_real(on_result)
		return
	_count_use()
	on_result.call(true)


static func _count_use() -> void:
	GameState.ad_daily_counts[PLACEMENT] = used_today() + 1
	GameState.note_ad_watched(PLACEMENT)   # миссии «посмотри рекламу» (ГДД §17.2)


static func _show_real(on_result: Callable) -> void:
	var state := {"done": false}
	var finish := func(ok: bool) -> void:
		if state["done"]:
			return
		state["done"] = true
		if ok:
			_count_use()
		on_result.call(ok)
	var earned := func(id: String) -> void:
		if id == PLACEMENT:
			finish.call(true)
	var failed := func(id: String, _reason: String) -> void:
		if id == PLACEMENT:
			finish.call(false)
	AdManager.ad_reward_earned.connect(earned, CONNECT_ONE_SHOT)
	AdManager.ad_failed.connect(failed, CONNECT_ONE_SHOT)
	AdManager.show_rewarded_ad(PLACEMENT)

class_name DailyReward
extends RefCounted
## Ежедневная награда: 7-дневный цикл с серией.
##
## Защита от накрутки часами: «сегодня» — MetaState.today() (не идёт назад),
## в сейве лежат сутки последней награды (UTC), и запись делается ДО выдачи —
## вторая награда за те же сутки невозможна, как ни крути часы и ни убивай
## процесс посреди выдачи.
##
## Серия считается по числу наград подряд, а не по дате календаря: пропуск не
## больше grace_days суток цепочку не рвёт (и не съедает плитку цикла).


static func cycle() -> Array:
	return MetaData.daily().get("cycle", [])


static func bonus_pct(cycles: int) -> int:
	var b: Dictionary = MetaData.daily().get("streak_bonus", {})
	return mini(int(b.get("max_pct", 0)), cycles * int(b.get("per_cycle_pct", 0)))


## Что будет, если нажать «забрать» сейчас: индекс плитки, серия, можно ли.
static func plan() -> Dictionary:
	var d := MetaState.sub("daily")
	var today := MetaState.today()
	var last := int(d["last"])
	var grace := int(MetaData.daily().get("grace_days", 0))
	var alive := last >= 0 and (today - last) <= 1 + grace
	var pos := int(d["pos"])
	var streak := int(d["streak"])
	var cycles := int(d["cycles"])
	if not alive:
		pos = 0
		streak = 0
		cycles = 0
	return {
		"can_claim": today > last, "pos": pos, "streak": streak, "cycles": cycles,
		"today": today, "last": last, "broken": last >= 0 and not alive,
		"bonus_pct": bonus_pct(cycles),
	}


## Награда плитки pos с учётом бонуса серии (и множителя mult — ролик «×2»).
static func reward_for(pos: int, cycles: int, mult: float = 1.0) -> Dictionary:
	var base: Dictionary = cycle()[pos]["reward"]
	return MetaRewards.scaled(base, (1.0 + float(bonus_pct(cycles)) / 100.0) * mult)


static func can_claim() -> bool:
	return MetaState.is_unlocked() and bool(plan()["can_claim"])


static func claim(mult: float = 1.0) -> Dictionary:
	if not MetaState.is_unlocked():
		return {"ok": false, "reason": "locked"}
	var p := plan()
	if not bool(p["can_claim"]):
		return {"ok": false, "reason": "already"}
	var idx := int(p["pos"])
	var reward := reward_for(idx, int(p["cycles"]), mult)
	var d := MetaState.sub("daily")
	# Запись раньше выдачи: см. шапку файла.
	d["last"] = int(p["today"])
	d["streak"] = int(p["streak"]) + 1
	d["best"] = maxi(int(d["best"]), int(d["streak"]))
	d["pos"] = (idx + 1) % cycle().size()
	d["cycles"] = int(p["cycles"]) + (1 if idx == cycle().size() - 1 else 0)
	MetaState.bump("daily_claims")
	MetaState.set_max("streak_best", int(d["streak"]))
	var granted := MetaRewards.grant(reward, true)
	MetaState.touch()
	return {
		"ok": true, "day": idx + 1, "reward": granted, "streak": int(d["streak"]),
		"grand": idx == cycle().size() - 1, "bonus_pct": int(p["bonus_pct"]),
	}

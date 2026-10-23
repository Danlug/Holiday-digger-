class_name TrophyRoad
extends RefCounted
## Дорога трофеев: ступени по накопленным очкам (достижения и задания).
## Награду ступени забирают нажатием — крупные призы заслуживают отдельного
## «получил».


static func steps() -> Array:
	return MetaData.road()


static func points() -> int:
	return int(MetaState.root()["pts"])


static func is_claimed(i: int) -> bool:
	for v in MetaState.root()["road"]:
		if int(v) == i:
			return true
	return false


static func is_reached(i: int) -> bool:
	return points() >= int(steps()[i]["at"])


static func claimable() -> Array:
	var out: Array = []
	for i in range(steps().size()):
		if is_reached(i) and not is_claimed(i):
			out.append(i)
	return out


## Первая ступень, до которой очков ещё не хватает; -1, если дорога пройдена.
static func next_index() -> int:
	for i in range(steps().size()):
		if not is_reached(i):
			return i
	return -1


static func claim(i: int) -> Dictionary:
	if i < 0 or i >= steps().size() or not is_reached(i) or is_claimed(i):
		return {"ok": false}
	(MetaState.root()["road"] as Array).append(i)  # до выдачи, как и везде
	var granted := MetaRewards.grant(steps()[i]["reward"], false)
	MetaState.touch()
	return {"ok": true, "reward": granted, "index": i}

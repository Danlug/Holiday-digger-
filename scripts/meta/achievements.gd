class_name Achievements
extends RefCounted
## Достижения: список — data/achievements.json, счётчики — MetaState.
## Награда выдаётся сразу при получении; «непросмотренные» (красный бейдж на
## пункте меню) гаснут, когда игрок откроет вкладку достижений.

## Предметы, которые подбираются, но «видом добычи» не считаются.
const NOT_A_KIND := ["energy_bar", "energy_drink", "fuel_block", "bronze", "food_soup", "food_dumplings"]


static func is_kind(id: String) -> bool:
	return id != "" and not NOT_A_KIND.has(id)


## Текущее значение счётчика. Живые читаются прямо из GameState: игрок мог
## накопить глубину и уровень задолго до того, как мета-слой включился.
static func value(counter: String) -> int:
	match counter:
		"max_depth":
			return GameState.max_depth_reached
		"level":
			return GameState.level
		"artifacts":
			return GameState.collected_artifacts.size()
		"branches":
			return GameState.completed_branches.size()
		"kinds":
			var n := 0
			for id in MetaState.sub("minerals").keys():
				if int(MetaState.sub("minerals")[id]) > 0:
					n += 1
			return n
	if counter.begins_with("m:"):
		return int(MetaState.sub("minerals").get(counter.substr(2), 0))
	return MetaState.counter(counter)


static func progress(a: Dictionary) -> Vector2i:
	return Vector2i(mini(value(String(a["counter"])), int(a["target"])), int(a["target"]))


static func is_done(id: String) -> bool:
	return MetaState.sub("ach").has(id)


static func done_count() -> int:
	return MetaState.sub("ach").size()


## Проверяет все достижения, выдаёт награды новым. Возвращает новые (словари из
## data). Идемпотентна: уже полученное второй раз не выдаётся.
static func evaluate() -> Array:
	var fresh: Array = []
	if not MetaState.is_unlocked():
		return fresh
	var got := MetaState.sub("ach")
	for a in MetaData.achievements():
		var id := String(a["id"])
		if got.has(id):
			continue
		if value(String(a["counter"])) < int(a["target"]):
			continue
		got[id] = MetaState.today()  # до выдачи: вложенный evaluate (уровень от опыта) не задвоит
		MetaRewards.grant(a.get("reward", {}), false)
		var s := MetaState.root()
		s["pts"] = int(s["pts"]) + MetaData.points_for_tier(int(a["tier"]))
		fresh.append(a)
	if not fresh.is_empty():
		MetaState.touch()
	return fresh


static func unseen_count() -> int:
	var seen := MetaState.sub("seen")
	var n := 0
	for id in MetaState.sub("ach").keys():
		if not seen.has(id):
			n += 1
	return n


static func is_unseen(id: String) -> bool:
	return is_done(id) and not MetaState.sub("seen").has(id)


static func mark_all_seen() -> void:
	var seen := MetaState.sub("seen")
	var changed := false
	for id in MetaState.sub("ach").keys():
		if not seen.has(id):
			seen[id] = true
			changed = true
	if changed:
		MetaState.touch()

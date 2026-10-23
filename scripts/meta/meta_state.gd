class_name MetaState
extends RefCounted
## Сохраняемое состояние мета-слоя: GameState.ext["meta"] (уходит в сейв вместе
## с ext, без правки SaveSystem). Узел не кэшируется нигде: загрузка сейва
## подменяет весь словарь ext, а reset_progress() его чистит — поэтому каждый
## доступ идёт через root(), которая при необходимости заводит пустое состояние.
##
## JSON возвращает числа как float — все чтения приводятся через int().
##
## Схема:
##   hw        — высшая отметка суток (UTC), «сегодня» не идёт назад
##   unlocked  — онбординг пройден (первая продажа золота), мета включена
##   daily     — last (сутки последней награды), streak, best, pos (индекс
##               следующей плитки 0..6), cycles (пройденных недель подряд)
##   quests    — day, week, daily[], weekly[], bonus_claimed
##   c         — счётчики событий (dug, picked, sold_coins, …)
##   minerals  — добыча по видам {id: штук}
##   ach       — получено {id: сутки}; seen — просмотрено игроком {id: true}
##   pts       — очки дороги трофеев; road — взятые ступени
##   wk_dollars— доллары от повторяемых источников за неделю (потолок)
##   events    — какие события шины хоть раз приходили (для requires_seen)

const KEY := "meta"
const VERSION := 1


static func _fresh() -> Dictionary:
	return {
		"v": VERSION, "hw": 0, "unlocked": false,
		"daily": {"last": -1, "streak": 0, "best": 0, "pos": 0, "cycles": 0},
		"quests": {"day": -1, "week": -1, "daily": [], "weekly": [], "bonus_claimed": false},
		"c": {}, "minerals": {}, "ach": {}, "seen": {}, "pts": 0, "road": [],
		"wk_dollars": {"week": -1, "n": 0}, "events": {},
	}


static func root() -> Dictionary:
	var s = GameState.ext.get(KEY)
	if typeof(s) != TYPE_DICTIONARY:
		s = _fresh()
		GameState.ext[KEY] = s
		return s
	# Сейв старой/частичной схемы: недостающие ветки доливаем, чужое не трогаем.
	var f := _fresh()
	for k in f.keys():
		if not s.has(k) or typeof(s[k]) != typeof(f[k]):
			s[k] = f[k]
	return s


static func sub(name: String) -> Dictionary:
	return root()[name]


static func geti(d: Dictionary, key: String, default: int = 0) -> int:
	return int(d.get(key, default))


## Сегодняшние сутки UTC, не меньше когда-либо виденных (см. MetaClock).
static func today() -> int:
	var s := root()
	var real := MetaClock.real_day()
	var hw := int(s["hw"])
	if real < hw:
		return hw
	s["hw"] = real
	return real


static func is_unlocked() -> bool:
	return bool(root()["unlocked"])


static func counter(name: String) -> int:
	return int(sub("c").get(name, 0))


static func bump(name: String, n: int = 1) -> void:
	var c := sub("c")
	c[name] = int(c.get(name, 0)) + n


static func set_max(name: String, v: int) -> void:
	var c := sub("c")
	c[name] = maxi(int(c.get(name, 0)), v)


static func event_seen(id: String) -> bool:
	return bool(sub("events").get(id, false))


## Сообщает подписчикам ext, что мета-состояние изменилось (UI, сейв).
static func touch() -> void:
	GameState.ext_changed.emit(KEY)

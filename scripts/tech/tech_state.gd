class_name TechState
extends RefCounted
## Сохраняемое состояние ветки «Техника» — в GameState.ext["tech"]:
##   tanks  {tool_id: {level:int, fuel:float}}  баки бура и бурмобиля
##   suit   int                                  ступень костюма (0 — нет)
##   well   {seen_unix:int, ad_day:String}       отметки скважины для защиты часов
## Уровень самой скважины и время забора лежат в GameState.well_* (поля уже
## были и входят в сейв). JSON возвращает числа float — читаем через int()/float().

const KEY := "tech"


static func root() -> Dictionary:
	var d = GameState.ext_get(KEY, null)
	if typeof(d) != TYPE_DICTIONARY:
		d = {}
		GameState.ext[KEY] = d
	return d


## Записать корень обратно: ext_changed — сигнал для тех, кто следит за хранилищем.
static func touch() -> void:
	GameState.ext_set(KEY, root())


static func tank(tool_id: String) -> Dictionary:
	# Сейв с чужой/битой формой («tanks» не словарь) лечится на месте: присвоение числа
	# в типизированную переменную роняло скрипт при каждом чтении бака.
	var tanks = root().get("tanks", null)
	if typeof(tanks) != TYPE_DICTIONARY:
		tanks = {}
		root()["tanks"] = tanks
	var t = tanks.get(tool_id, null)
	if typeof(t) != TYPE_DICTIONARY:
		t = {"level": 0, "fuel": 0.0}
		tanks[tool_id] = t
	return t


static func suit() -> int:
	var v = root().get("suit", 0)
	return int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 0


static func set_suit(tier: int) -> void:
	root()["suit"] = tier
	touch()


static func well_meta() -> Dictionary:
	var w = root().get("well", null)
	if typeof(w) != TYPE_DICTIONARY:
		w = {}
		root()["well"] = w
	return w

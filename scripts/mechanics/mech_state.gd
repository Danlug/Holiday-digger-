class_name MechState
extends RefCounted
## Сохраняемое состояние механик раунда 3 — GameState.ext["mechanics"]:
##   chests  {opened: {"x,y": ступень}, left: {"x,y": {item: n}}} — открытые сундуки и то,
##           что в них осталось (рюкзак был полон);
##   mastery {n: {item: клеток}, stars: {item: звёзд выдано}, seen: {item: звёзд
##           видено в журнале}} — счётчики мастерства;
##   stats   {fevers, bonus_items} — что показывает вкладка «Тайники» журнала.
## Азарт не сохраняется: серия живёт, пока герой копает, и закрытие игры её и так рвёт.
## JSON отдаёт числа float, а сейв могли испортить — каждое чтение приводит типы.

const KEY := "mechanics"


static func root() -> Dictionary:
	var r = GameState.ext.get(KEY, null)
	if typeof(r) != TYPE_DICTIONARY:
		r = {}
		GameState.ext[KEY] = r
	return r


static func _sub(parent: Dictionary, name: String) -> Dictionary:
	var d = parent.get(name, null)
	if typeof(d) != TYPE_DICTIONARY:
		d = {}
		parent[name] = d
	return d


static func cell_key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


# --- тайники -----------------------------------------------------------------

static func chest_opened(c: Vector2i) -> bool:
	return _sub(_sub(root(), "chests"), "opened").has(cell_key(c))


static func mark_chest_opened(c: Vector2i, tier: String = "wood") -> void:
	_sub(_sub(root(), "chests"), "opened")[cell_key(c)] = tier
	GameState.ext_changed.emit(KEY)


## Сколько сундуков открыто (tier = "" — всех ступеней).
static func opened_count(tier: String = "") -> int:
	var opened := _sub(_sub(root(), "chests"), "opened")
	if tier == "":
		return opened.size()
	var n := 0
	for k in opened.keys():
		if typeof(opened[k]) == TYPE_STRING and String(opened[k]) == tier:
			n += 1
	return n


## Что осталось в открытом сундуке (рюкзак был полон): {item: n}.
static func chest_left(c: Vector2i) -> Dictionary:
	var raw = _sub(_sub(root(), "chests"), "left").get(cell_key(c), null)
	var out := {}
	if typeof(raw) == TYPE_DICTIONARY:
		for k in raw.keys():
			var n := _int(raw[k])
			if n > 0:
				out[String(k)] = n
	return out


static func set_chest_left(c: Vector2i, items: Dictionary) -> void:
	var left := _sub(_sub(root(), "chests"), "left")
	var clean := {}
	for k in items.keys():
		if int(items[k]) > 0:
			clean[String(k)] = int(items[k])
	if clean.is_empty():
		left.erase(cell_key(c))
	else:
		left[cell_key(c)] = clean
	GameState.ext_changed.emit(KEY)


## Клетки сундуков, в которых ещё лежит добыча.
static func chests_with_loot() -> Array:
	var out: Array = []
	for k in _sub(_sub(root(), "chests"), "left").keys():
		var parts := String(k).split(",")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var c := Vector2i(int(parts[0]), int(parts[1]))
			if not chest_left(c).is_empty():
				out.append(c)
	return out


# --- мастерство ---------------------------------------------------------------

static func mastery_count(item: String) -> int:
	return _int(_sub(_sub(root(), "mastery"), "n").get(item, 0))


static func add_mastery(item: String, n: int = 1) -> int:
	var counts := _sub(_sub(root(), "mastery"), "n")
	var v := _int(counts.get(item, 0)) + n
	counts[item] = v
	return v


static func stars_granted(item: String) -> int:
	return _int(_sub(_sub(root(), "mastery"), "stars").get(item, 0))


static func set_stars_granted(item: String, s: int) -> void:
	_sub(_sub(root(), "mastery"), "stars")[item] = s
	GameState.ext_changed.emit(KEY)


static func stars_seen(item: String) -> int:
	return _int(_sub(_sub(root(), "mastery"), "seen").get(item, 0))


## Журнал открыт — всё, что в нём есть, игрок видел (бейдж в меню гаснет).
static func mark_all_seen() -> void:
	var m := _sub(root(), "mastery")
	var seen := _sub(m, "seen")
	for item in _sub(m, "n").keys():
		seen[item] = maxi(1, stars_granted(String(item))) if mastery_count(String(item)) > 0 else 0
	GameState.ext_changed.emit(KEY)


## Новое в журнале: впервые добытые породы и звёзды, которых игрок ещё не видел.
static func unseen_count() -> int:
	var m := _sub(root(), "mastery")
	var n := 0
	for item in _sub(m, "n").keys():
		var id := String(item)
		if mastery_count(id) <= 0:
			continue
		if stars_seen(id) < maxi(1, stars_granted(id)):
			n += 1
	return n


# --- счётчики журнала (лихорадки, добыча сверху) ------------------------------

static func stat(name: String) -> int:
	return _int(_sub(root(), "stats").get(name, 0))


static func bump_stat(name: String, n: int = 1) -> void:
	var s := _sub(root(), "stats")
	s[name] = _int(s.get(name, 0)) + n


static func _int(v) -> int:
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT:
		return int(v)
	return 0

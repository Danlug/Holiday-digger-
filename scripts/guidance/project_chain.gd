class_name ProjectChain
extends RefCounted
## Проекты — крупные постройки из материалов (ручной бур, скважина, бурмобиль,
## костюм от жары) и цепочки их материалов: что нужно, сколько есть (рюкзак +
## склад) из скольких, из чего делается промежуточное (лом → бронза) и где это
## копать. Только чтение состояния игры, без узлов — всё проверяется тестом
## (tests/test_guidance.gd). Слова владельца, ради которых это сделано: «нужно
## где-то как-то объяснить, что некоторые ресурсы нужно собирать, чтобы собрать
## бур, бурмобиль, буровую станцию» (ГДД §21).
##
## Составы НЕ дублируются: рецепты — ShopCatalog.recipes() (balance.json),
## костюм — Heat.next_suit() (tech.json); список и порядок проектов —
## data/guidance.json. Сохраняемое — GameState.ext["guidance"]:
##   tracked  String  проект, за которым следит трекер на HUD ("" — ни за каким)
##   manual   bool    игрок сам менял слежку — автоматически больше не берём

const DATA_PATH := "res://data/guidance.json"
const KEY := "guidance"
const SUIT := "heat_suit"

static var _data: Dictionary = {}
static var _loaded := false


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		if FileAccess.file_exists(DATA_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


static func setting(key: String, default):
	var v = Balance.unwrap(data().get(key, default))
	return default if v == null else v


# ---------------------------------------------------------------------------
# Проекты
# ---------------------------------------------------------------------------

## Все проекты, у которых есть состав, в порядке data/guidance.json.
static func ids() -> Array:
	var out: Array = []
	for id in setting("projects", []):
		if not def(String(id)).is_empty():
			out.append(String(id))
	return out


## {id, name, icon, unlock_depth, coins, inputs: {id: n}, where_built: "workshop"|"tech"}.
## Костюм — следующая ещё не сделанная ступень; все сделаны — {}.
static func def(id: String) -> Dictionary:
	if id == SUIT:
		var n := Heat.next_suit()
		if not bool(n.get("ok", false)):
			return {}
		var row: Dictionary = n["row"]
		var cost = n.get("cost", null)
		return {
			"id": id,
			"name": String(row.get("name_ru", "Костюм")),
			"icon": load_icon("res://art/tech/suit_%d.png" % int(n["tier"])),
			"unlock_depth": int(row.get("unlock_depth", 0)),
			"coins": TechCost.coins_of(cost),
			"inputs": _ints(TechCost.items_of(cost)),
			"where_built": "tech",
		}
	var r := ShopCatalog.recipe(id)
	if r.is_empty() or not ["tool", "machine"].has(String(r.get("kind", ""))):
		return {}
	return {
		"id": id,
		"name": String(r["name_ru"]),
		"icon": ShopItems.recipe_icon(r),
		"unlock_depth": int(r.get("unlock_depth", 0)),
		"coins": int(r.get("coins", 0)),
		"inputs": _ints(r.get("inputs", {})),
		"where_built": "workshop",
	}


static func _ints(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		out[String(k)] = int(d[k])
	return out


static func load_icon(path: String) -> Texture2D:
	return ShopArt.load_path(path)


static func icon(id: String) -> Texture2D:
	return def(id).get("icon", null)


static func title(id: String) -> String:
	return String(def(id).get("name", id))


static func is_unlocked(id: String) -> bool:
	var d := def(id)
	return not d.is_empty() and GameState.max_depth_reached >= int(d["unlock_depth"])


static func is_built(id: String) -> bool:
	match id:
		SUIT:
			return def(id).is_empty()
		"well":
			return GameState.well_level > 0
	return GameState.owns_tool(id)


## Открыт и ещё не собран: только такие проекты просят материалы.
static func is_open(id: String) -> bool:
	return is_unlocked(id) and not is_built(id)


static func open_ids() -> Array:
	var out: Array = []
	for id in ids():
		if is_open(String(id)):
			out.append(id)
	return out


# ---------------------------------------------------------------------------
# Материалы и цепочки
# ---------------------------------------------------------------------------

## Сколько есть: склад + рюкзак (верстак и «Техника» берут из обоих).
static func held(item: String) -> int:
	return HouseStorage.count(item) + GameState.get_item_count(item)


## Из чего делается промежуточный материал: рецепты-переработки верстака с этим
## выходом (сегодня — только бронза из металлолома). [{id, per, out}]:
## per штук сырья дают out штук материала.
static func sources(item: String) -> Array:
	var out: Array = []
	for r in ShopCatalog.recipes():
		if String(r.get("kind", "")) != "item" or String(r["output"]["id"]) != item:
			continue
		for src in (r["inputs"] as Dictionary).keys():
			out.append({"id": String(src), "per": maxi(1, int(r["inputs"][src])),
				"out": maxi(1, int(r["output"]["count"]))})
	return out


## Строка материала: {id, need, have, via: [{id, have, per, out, makes}], effective,
## done}. have — сам материал; makes — сколько его выйдет из сырья под рукой;
## effective = have + makes (так полоска честно показывает, что лом — это уже
## почти бронза). done — хватает без переработки.
static func material(item: String, need: int) -> Dictionary:
	var have := held(item)
	var via: Array = []
	var makes_total := 0
	for s: Dictionary in sources(item):
		var src_have := held(String(s["id"]))
		var makes := floori(float(src_have) / float(s["per"])) * int(s["out"])
		makes_total += makes
		via.append({"id": String(s["id"]), "have": src_have, "per": int(s["per"]),
			"out": int(s["out"]), "makes": makes})
	return {"id": item, "need": need, "have": have, "via": via,
		"effective": have + makes_total, "done": have >= need}


static func materials(id: String) -> Array:
	var out: Array = []
	var inputs: Dictionary = def(id).get("inputs", {})
	for item in inputs.keys():
		out.append(material(String(item), int(inputs[item])))
	return out


static func coins_need(id: String) -> int:
	return int(def(id).get("coins", 0))


## Доля готовности 0..1: среднее по материалам (с переработкой) и монетам.
static func progress(id: String) -> float:
	var parts: Array = []
	for m: Dictionary in materials(id):
		parts.append(clampf(float(m["effective"]) / maxf(1.0, float(m["need"])), 0.0, 1.0))
	var c := coins_need(id)
	if c > 0:
		parts.append(clampf(float(GameState.coins) / float(c), 0.0, 1.0))
	if parts.is_empty():
		return 1.0
	var s := 0.0
	for p in parts:
		s += float(p)
	return s / float(parts.size())


## Всё есть прямо сейчас (промежуточное уже переработано, монет хватает).
static func ready(id: String) -> bool:
	if not is_open(id):
		return false
	for m: Dictionary in materials(id):
		if not bool(m["done"]):
			return false
	return GameState.coins >= coins_need(id)


## Сколько материалов (и монеты как одна строка) уже набрано: {done, total}.
static func counts(id: String) -> Dictionary:
	var done := 0
	var total := 0
	for m: Dictionary in materials(id):
		total += 1
		if bool(m["done"]):
			done += 1
	if coins_need(id) > 0:
		total += 1
		if GameState.coins >= coins_need(id):
			done += 1
	return {"done": done, "total": total}


# ---------------------------------------------------------------------------
# Где копать
# ---------------------------------------------------------------------------

## {min, max, best, tool, crafted}: глубина появления, конец слоя (0 — без конца),
## где больше всего, инструмент, без которого не взять (hand_drill/drill_rig или
## ""), и crafted=true, если в породе этого нет вовсе (бронза плавится).
static func where(item: String) -> Dictionary:
	var m: Dictionary = Balance.get_mineral(item)
	if m.is_empty():
		return {"min": 0, "max": 0, "best": 0, "tool": "", "crafted": not sources(item).is_empty()}
	var dmin = Balance.unwrap(m.get("depth_min", null))
	if dmin == null:
		return {"min": 0, "max": 0, "best": 0, "tool": "", "crafted": true}
	var dmax = Balance.unwrap(m.get("depth_max", null))
	var dens = Balance.unwrap(m.get("density", {}))
	var best := int(dmin)
	if typeof(dens) == TYPE_DICTIONARY and dens.has("peak_depth"):
		best = int(Balance.unwrap(dens["peak_depth"]))
	var tool := String(Balance.unwrap(m.get("tool_required", "")))
	if not ["hand_drill", "drill_rig"].has(tool):
		tool = ""
	return {"min": int(dmin), "max": 0 if dmax == null else int(dmax), "best": best,
		"tool": tool, "crafted": false}


## Одна строка для подсказки: «С 5 м, больше всего около 100 м. Нужен ручной бур».
static func where_text(item: String) -> String:
	var w := where(item)
	if bool(w["crafted"]):
		var s := sources(item)
		if s.is_empty():
			return "В породе не встречается."
		return "Не копается: плавится на верстаке из «%s» (%d к %d)." % [
			ShopCatalog.item_name(String(s[0]["id"])), int(s[0]["per"]), int(s[0]["out"])]
	var t := "С %d м" % int(w["min"])
	if int(w["max"]) > 0:
		t = "С %d до %d м" % [int(w["min"]), int(w["max"])]
	if int(w["best"]) > int(w["min"]):
		t += ", больше всего около %d м" % int(w["best"])
	t += "."
	if String(w["tool"]) != "":
		t += " Берётся только: %s." % Balance.get_tool_name_ru(String(w["tool"]))
	return t


# ---------------------------------------------------------------------------
# «Нужно для…» — значки на плитках продажи и склада
# ---------------------------------------------------------------------------

## Открытые проекты, которым ещё не хватает этого предмета (сам материал или
## сырьё промежуточного): [{project, need, have, via}]. via — промежуточный
## материал ("bronze" у лома) или "". Отслеживаемый проект — первым.
static func needed_for(item: String) -> Array:
	var out: Array = []
	var order := open_ids()
	var tr := tracked()
	if order.has(tr):
		order.erase(tr)
		order.push_front(tr)
	for pid in order:
		for m: Dictionary in materials(String(pid)):
			if bool(m["done"]):
				continue
			if String(m["id"]) == item:
				out.append({"project": String(pid), "need": int(m["need"]), "have": int(m["have"]), "via": ""})
				continue
			for s: Dictionary in m["via"]:
				if String(s["id"]) != item:
					continue
				var left := int(m["need"]) - int(m["have"])
				var raw_need := int(ceil(float(left) / float(s["out"]))) * int(s["per"])
				out.append({"project": String(pid), "need": raw_need, "have": int(s["have"]),
					"via": String(m["id"])})
	return out


## Строки подсказки: «Ручной бур: 40/100», «Ручной бур (бронза): 30/60».
static func needed_text(item: String) -> String:
	var lines: Array = []
	for e: Dictionary in needed_for(item):
		var t := title(String(e["project"]))
		if String(e["via"]) != "":
			t += " (%s)" % ShopCatalog.item_name(String(e["via"])).to_lower()
		lines.append("Нужно для: %s — %d/%d" % [t, int(e["have"]), int(e["need"])])
	return "\n".join(lines)


## Дописывает в предложение плитки (ShopTile) значок проекта и строку в Tip.
## Ничего не нужно — предложение не трогается.
static func decorate_offer(o: Dictionary, item: String) -> void:
	var need := needed_for(item)
	if need.is_empty():
		return
	o["need_icon"] = icon(String(need[0]["project"]))
	o["need_project"] = String(need[0]["project"])
	var line := needed_text(item)
	var extra := String(o.get("extra", ""))
	o["extra"] = line if extra == "" else line + "\n" + extra


# ---------------------------------------------------------------------------
# Слежка (трекер на HUD)
# ---------------------------------------------------------------------------

static func state() -> Dictionary:
	var d = GameState.ext_get(KEY, null)
	if typeof(d) != TYPE_DICTIONARY:
		d = {}
		GameState.ext[KEY] = d
	return d


static func tracked() -> String:
	return String(state().get("tracked", ""))


## Игрок сам выбрал (manual=true) — автослежка больше не вмешивается.
static func set_tracked(id: String, manual: bool = true) -> void:
	var s := state()
	s["tracked"] = id
	if manual:
		s["manual"] = true
	GameState.ext_set(KEY, s)


static func is_manual() -> bool:
	return bool(state().get("manual", false))


## Автослежка: ничего не отслеживается (или отслеживаемое уже собрано), игрок не
## снимал слежку руками — берём первый открытый проект. Возвращает новый id или "".
static func auto_track() -> String:
	var cur := tracked()
	if cur != "" and is_built(cur):
		set_tracked("", false)   # собрано — приколотое снимаем и при ручной слежке
		cur = ""
	if not bool(setting("auto_track", true)) or is_manual():
		return ""
	if cur != "" and is_open(cur):
		return ""
	var open := open_ids()
	var next := String(open[0]) if not open.is_empty() else ""
	if next != cur:
		set_tracked(next, false)
		return next
	return ""

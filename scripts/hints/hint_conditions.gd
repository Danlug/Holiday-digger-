class_name HintConditions
extends RefCounted
## Условия правил подсказок (data/hints.json: when / done). Условие — словарь
## {"fn": имя, ...параметры} или {"all": [...]} / {"any": [...]} / {"not": ...}.
## Все функции — только чтение состояния игры, без побочных эффектов, поэтому их
## можно опрашивать сколько угодно и проверять под тестом.
##
## Числа параметров могут быть {value, proposed, note} — разворачиваем HintData.v.
## Незнакомое имя — false и одно предупреждение: правило не должно ронять игру.

## События шины, которые уже случались в этом запуске: ветки, которым нужен
## «разовый» триггер (условие {"fn": "event", "id": "..."}), не заводят своё состояние.
static var latched: Dictionary = {}
static var _warned: Dictionary = {}

## Известные имена условий (тест следит, что правила из JSON не ссылаются на опечатки).
const FUNCTIONS := [
	"skill_points", "artifacts", "menu_new", "daily_ready", "quest_claimable", "achievement_unseen",
	"station_ready", "tank_empty", "heat_over", "well_ready", "grave_news", "diary_unread",
	"load_high", "sellable", "craft_ready", "tool_affordable", "hungry_food", "has_gear",
	"on_surface", "flag", "scene_seen", "depth", "event", "ext_true", "screen_open", "near_world",
]


static func is_known(name: String) -> bool:
	return FUNCTIONS.has(name)


static func test(cond: Dictionary) -> bool:
	if cond.is_empty():
		return true
	if cond.has("all"):
		for c: Dictionary in cond["all"]:
			if not test(c):
				return false
		return true
	if cond.has("any"):
		for c: Dictionary in cond["any"]:
			if test(c):
				return true
		return false
	if cond.has("not"):
		return not test(cond["not"])
	return _fn(String(cond.get("fn", "")), cond)


static func _num(p: Dictionary, key: String, default: float) -> float:
	return float(HintData.v(p.get(key, null), default))


static func _fn(name: String, p: Dictionary) -> bool:
	match name:
		# --- герой, музей ---
		"skill_points":
			return GameState.skill_points_available >= int(_num(p, "min", 1))
		"artifacts":
			return GameState.collected_artifacts.size() >= int(_num(p, "min", 1))
		# --- меню и мета-слой ---
		"menu_new":
			var entry := String(p.get("entry", ""))
			return menu_entry_visible(entry) and not HintState.entry_opened(entry)
		"daily_ready":
			return MetaState.is_unlocked() and DailyReward.can_claim()
		"quest_claimable":
			return MetaState.is_unlocked() and QuestEngine.claimable_count() >= int(_num(p, "min", 1))
		"achievement_unseen":
			return MetaState.is_unlocked() and Achievements.unseen_count() > 0
		# --- техника ---
		"station_ready":
			return StoryState.has_flag("fuel_station_built") and GameState.era != "grandpa" \
				and _owns_fuel_tool()
		"tank_empty":
			var t := GameState.current_tool
			return FuelTank.uses_fuel(t) and not FuelTank.has_fuel(t)
		"heat_over":
			var depth := GameState.player_depth
			return depth >= 1 and not GameState.house_is_indoors \
				and Heat.stamina_multiplier(float(depth)) > 1.001
		"well_ready":
			return IdleWell.is_built() and IdleWell.fill_fraction() >= _num(p, "frac", 1.0)
		# --- сюжет ---
		"grave_news":
			return StoryState.is_seen("grave_call") and not StoryState.has_flag("diary_found") \
				and GameState.era != "grandpa"
		"diary_unread":
			return StoryState.has_flag("diary_found") and not StoryDiary.unread_ids().is_empty()
		# --- рюкзак, мастерская, магазин ---
		"load_high":
			return GameState.get_total_weight() / maxf(GameState.get_max_carry_kg(), 0.001) \
				>= _num(p, "frac", 0.9)
		"sellable":
			var sum := 0
			for row: Dictionary in ShopService.sellable_stacks():
				sum += int(row["sum"])
			return sum >= int(_num(p, "coins", 100))
		"craft_ready":
			return craftable_recipe() != ""
		"tool_affordable":
			return affordable_upgrade() != ""
		"hungry_food":
			return GameState.hunger <= _num(p, "pct", 35.0) and has_food()
		"has_gear":
			return not GameState.owned_gear.is_empty()
		# --- общие ---
		"on_surface":
			return not GameState.house_is_indoors and GameState.player_depth <= int(_num(p, "max", 0))
		"flag":
			return StoryState.has_flag(String(p.get("name", "")))
		"scene_seen":
			return StoryState.is_seen(String(p.get("id", "")))
		"depth":
			return GameState.max_depth_reached >= int(_num(p, "min", 1))
		"event":
			return latched.has(String(p.get("id", "")))
		"ext_true":
			var d = GameState.ext_get(String(p.get("key", "")), {})
			return typeof(d) == TYPE_DICTIONARY and bool(d.get(String(p.get("field", "")), false))
		# --- «игрок уже сделал» (поле done) ---
		"screen_open":
			return screen_open(String(p.get("name", "")))
		"near_world":
			return near_world(String(p.get("target", "")))
	if not _warned.has(name):
		_warned[name] = true
		push_warning("HintConditions: неизвестное условие «%s»" % name)
	return false


# ---------------------------------------------------------------------------
# Вспомогательное — открыто для тестов и для HintTargets
# ---------------------------------------------------------------------------

static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func hud() -> Control:
	var t := tree()
	return t.get_first_node_in_group("hud") as Control if t != null else null


static func player() -> Node:
	var t := tree()
	return t.root.find_child("Player", true, false) if t != null else null


static func menu_entry_visible(entry: String) -> bool:
	for e: Dictionary in MenuRegistry.entries():
		if String(e["id"]) == entry:
			return true
	return false


static func _owns_fuel_tool() -> bool:
	for tool_id in (TechData.fuel().get("tools", []) as Array):
		if GameState.owns_tool(String(tool_id)):
			return true
	return false


static func has_food() -> bool:
	for id in GameState.inventory.keys():
		if int(GameState.inventory[id]) > 0 and HouseConfig.is_food(String(id)):
			return true
	return false


## Первый рецепт техники, на который уже хватает материалов и монет (верстак стоит
## в мастерской, но подсказка нужна раньше — пока игрок ещё не там). "" — нет такого.
static func craftable_recipe() -> String:
	for r: Dictionary in ShopCatalog.recipes():
		var kind := String(r["kind"])
		if kind != "tool" and kind != "machine":
			continue
		var out_id := String(r["output"]["id"])
		if kind == "tool" and GameState.owns_tool(out_id):
			continue
		if kind == "machine" and out_id == "well" and GameState.well_level > 0:
			continue
		if not ShopService.is_recipe_unlocked(String(r["id"])):
			continue
		if GameState.coins < int(r["coins"]):
			continue
		var ok := true
		for id in (r["inputs"] as Dictionary).keys():
			if ShopService.held_for(String(r["id"]), String(id)) < int(r["inputs"][id]):
				ok = false
				break
		if ok:
			return String(r["id"])
	return ""


## Самая дешёвая покупка за монеты (кирка или ранец), на которую уже хватает денег.
## Первые бесплатные ступени и всё, что собирается из материалов, не считаются.
static func affordable_upgrade() -> String:
	var best := ""
	var best_price := 0
	for row: Dictionary in ShopCatalog.pickaxes():
		var id := String(row["id"])
		var price := int(row["price_coins"])
		if price <= 0 or GameState.owns_tool(id) or Balance.tool_needs_materials(id):
			continue
		if GameState.coins >= price and (best == "" or price < best_price):
			best = id
			best_price = price
	for row: Dictionary in ShopCatalog.gear_line():
		var id := String(row["id"])
		var price := int(row["price_coins"])
		if price <= 0 or GameState.has_gear(id):
			continue
		if GameState.coins >= price and (best == "" or price < best_price):
			best = id
			best_price = price
	return best


static func screen_open(name: String) -> bool:
	match name:
		"progress":
			return ProgressScreen.is_open()
		"tech":
			return TechScreen.is_open() or WellReport.is_open()
		"shop":
			return ShopUI.instance != null and ShopUI.instance.is_open()
		"backpack":
			var h := hud()
			var sheet = h.get("_inv_sheet") if h != null else null
			return sheet != null and bool(sheet.visible)
		"settings":
			var h2 := hud()
			return h2 != null and h2.has_method("is_settings_open") and h2.is_settings_open()
		"menu":
			var h3 := hud()
			return h3 != null and h3.has_method("is_more_menu_open") and h3.is_more_menu_open()
		"diary":
			var d := tree().root.find_child("StoryDirector", true, false) if tree() != null else null
			var ui = d.get("diary_ui") if d != null else null
			return ui != null and bool(ui.get("is_open"))
		"meta":
			var m := MetaService.instance
			return m != null and (m.hub.is_open() or m.popup.is_open())
	return false


## Герой рядом с объектом мира на поверхности (те же радиусы, что у кнопок-значков).
static func near_world(target: String) -> bool:
	var p := player()
	if p == null or float(p.get("y")) > 1.5:
		return false
	var x := float(p.get("x"))
	match target:
		"station":
			return absf(x - (WorldGen.FUEL_STATION_X + 1.0)) < 1.7
		"well":
			return absf(x - (WorldGen.WELL_X + 1.0)) < 1.7
		"grave":
			return absf(x - GraveSite.GRAVE_X) <= 1.2
	return false

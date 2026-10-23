extends Node
## test_hints — движок подсказок «знакомство с системами» без игровой сцены: данные
## (data/hints.json), условия каждого правила, очередь и тайминги, однократность,
## сохранение в GameState.ext, снятие (нажатие, условие, время, «потерялась цель»),
## режим «не мешать», пауза на шторках. Привязка к настоящему HUD и меню — в
## test_hints_ui.
##
## Запуск: godot --headless --path . res://tests/test_hints.tscn

var failures := 0
var total := 0
var _btn: Button
var _layer: CanvasLayer
var _dir: HintDirector


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_hints ===")
	Settings.reduce_motion = true   # твины не нужны, состояние — сразу
	Settings.hints_enabled = true
	_layer = CanvasLayer.new()
	add_child(_layer)
	_btn = Button.new()
	_btn.position = Vector2(60, 100)
	_btn.size = Vector2(30, 30)
	_btn.custom_minimum_size = Vector2(30, 30)
	_layer.add_child(_btn)
	HintPulse.attach(_btn, "t_btn")
	await get_tree().process_frame

	_check_data()
	_check_art_and_state()
	_check_every_rule()
	_check_engine()
	_check_busy()
	_check_motion()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# Общее
# ---------------------------------------------------------------------------

func _reset(onboarded: bool = true) -> void:
	GameState.reset_progress()
	GameState.story_flags.clear()
	GameState.story_seen.clear()
	GameState.story_queue.clear()
	GameState.era = "now"
	GameState.house_is_indoors = false
	HintConditions.latched.clear()
	MenuRegistry.clear()
	Settings.hints_enabled = true
	if onboarded:
		GameState.story_flags["food_ordered"] = true


func _new_director(rule_list: Array) -> HintDirector:
	if _dir != null and is_instance_valid(_dir):
		_dir.free()
	_dir = HintDirector.new()
	add_child(_dir)
	_dir.set_rules(rule_list)
	return _dir


func _run(d: HintDirector, seconds: float, step: float = 0.25) -> void:
	for i in range(int(round(seconds / step))):
		d.tick(step)


func _rule(id: String, cond: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var r := {
		"id": id, "prio": 10, "when": cond, "target": ["attached:t_btn"],
		"toast": {"icon": "ui:plus", "text": "тест"}, "tip": ["Тест", "Описание"],
		"hold": 0.5, "ttl": 30.0,
	}
	r.merge(extra, true)
	return r


func _tap_btn(d: HintDirector) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = _btn.get_global_rect().get_center()
	d._input(ev)


# ---------------------------------------------------------------------------
# Данные
# ---------------------------------------------------------------------------

func _walk_fns(cond, out: Array) -> void:
	if typeof(cond) != TYPE_DICTIONARY:
		return
	for k in ["all", "any"]:
		if cond.has(k):
			for c in cond[k]:
				_walk_fns(c, out)
	if cond.has("not"):
		_walk_fns(cond["not"], out)
	if cond.has("fn"):
		out.append(String(cond["fn"]))


func _check_data() -> void:
	HintData.reload()
	var rules := HintData.rules()
	check("data/hints.json: правил не меньше двенадцати (%d)" % rules.size(), rules.size() >= 12)
	var ids := {}
	var bad_text := 0
	var bad_fn := 0
	var bad_target := 0
	var bad_icon := 0
	var bad_tip := 0
	for r: Dictionary in rules:
		var id := String(r.get("id", ""))
		check("правило %s: id уникален" % id, not id.is_empty() and not ids.has(id))
		ids[id] = true
		var words := String(r.get("toast", {}).get("text", "")).split(" ", false)
		if words.is_empty() or words.size() > 3 or String(r["toast"]["text"]).length() > 14:
			bad_text += 1
		var tip: Array = r.get("tip", [])
		if tip.size() != 2 or String(tip[0]).is_empty() or String(tip[1]).length() > 150:
			bad_tip += 1
		var fns: Array = []
		_walk_fns(r.get("when", {}), fns)
		_walk_fns(r.get("done", {}), fns)
		if fns.is_empty():
			bad_fn += 1
		for f in fns:
			if not HintConditions.is_known(String(f)):
				bad_fn += 1
		var targets: Array = r.get("target", [])
		if targets.is_empty():
			bad_target += 1
		for t in targets:
			var kind := String(t).get_slice(":", 0)
			if not ["hud", "menu", "tech_hud", "world", "group", "attached"].has(kind) or String(t).find(":") < 0:
				bad_target += 1
		if HintArt.icon(String(r.get("toast", {}).get("icon", ""))) == null:
			bad_icon += 1
	check("у каждой подсказки тост — 1–3 слова, до 14 букв", bad_text == 0)
	check("у каждой подсказки Tip: заголовок и короткое описание", bad_tip == 0)
	check("условия правил из известных функций", bad_fn == 0)
	check("цели правил разобраны (hud/menu/tech_hud/world/group/attached)", bad_target == 0)
	check("значки тостов найдены в art/", bad_icon == 0)
	var timing: Dictionary = HintData.data().get("timing", {})
	var proposed := true
	for k in timing.keys():
		if not (typeof(timing[k]) == TYPE_DICTIONARY and bool(timing[k].get("proposed", false))):
			proposed = false
	check("числа таймингов помечены proposed", proposed and not timing.is_empty())
	check("тайминги: пауза между подсказками больше нуля, показ больше паузы опроса",
		HintData.timing("gap", 0.0) > 0.0 and HintData.timing("ttl", 0.0) > HintData.timing("poll", 1.0))
	check("метки «new»: заданы пункты меню", HintData.menu_new_entries().size() >= 2)


func _check_art_and_state() -> void:
	for n in ["finger", "arrow", "bang", "new", "bulb_on", "bulb_off", "replay"]:
		check("значок art/hints/%s.png загружается" % n, HintArt.tex(n) != null)
	check("палец-указатель крупнее 12 единиц, «new» — плашка шире высоты",
		HintArt.size_of(HintArt.tex("finger")).y >= 12.0
		and HintArt.size_of(HintArt.tex("new")).x > HintArt.size_of(HintArt.tex("new")).y)
	check("значок без префикса ищется среди общих значков интерфейса", HintArt.icon("plus") != null)
	check("значок с префиксом tech: находится", HintArt.icon("tech:icon_tank") != null)
	check("неизвестный префикс — null, а не падение", HintArt.icon("nope:zzz") == null)

	_reset()
	check("HintState: сначала ничего не показано", not HintState.is_seen("x"))
	HintState.mark_seen("x")
	check("HintState: показана — запомнено", HintState.is_seen("x") and not HintState.was_done("x"))
	HintState.mark_done("x")
	check("HintState: сделано — отличается от просто показанного", HintState.was_done("x"))
	var json := JSON.stringify(GameState.ext)
	GameState.ext = JSON.parse_string(json)
	check("HintState: переживает сохранение в JSON (числа float)", HintState.is_seen("x") and HintState.was_done("x"))
	HintState.mark_entry_opened("tech")
	check("HintState: открытый пункт меню помнится", HintState.entry_opened("tech") and not HintState.entry_opened("zzz"))
	HintState.reset()
	check("HintState.reset: подсказки и метки «new» снова новые",
		not HintState.is_seen("x") and not HintState.entry_opened("tech"))
	GameState.ext.clear()
	check("HintState.root переживает пустой ext", HintState.root().has("seen"))


# ---------------------------------------------------------------------------
# Условия: каждое правило из data/hints.json — срабатывает, однократно, сохраняется, снимается
# ---------------------------------------------------------------------------

func _deepest_hot_depth() -> int:
	for d in range(1, 12000, 5):
		if Heat.stamina_multiplier(float(d)) > 1.001:
			return d
	return -1


func _unlock_diary() -> void:
	GameState.max_depth_reached = 20000
	for p: Dictionary in StoryDiary.pages():
		var w: Dictionary = p.get("when", {})
		if w.has("seen"):
			GameState.story_seen.append(String(w["seen"]))
		if w.has("flag"):
			GameState.story_flags[String(w["flag"])] = true
	GameState.story_flags["diary_found"] = true


## id правила -> {on, off}: как довести игру до условия и как его снять
## (off не задан — условие не пропадает само, подсказка снимается нажатием).
func _scenarios() -> Dictionary:
	var food_id := String(HouseConfig.food_items()[0]["id"])
	var gear_id := String(Balance.get_gear_ids()[0])
	var recipe := ShopCatalog.recipe("hand_drill")
	var hot := _deepest_hot_depth()
	var forge_id := String(CombatData.craftable_ids()[0])
	var forge := CombatData.recipe(forge_id)
	var wear_id := _first_wearable()
	return {
		"skill_points": {
			"on": func() -> void: GameState.skill_points_available = 2,
			"off": func() -> void: GameState.skill_points_available = 0},
		"first_artifact": {
			"on": func() -> void: GameState.collected_artifacts.append("antiquity_1")},
		"menu_tech": {
			"on": func() -> void: MenuRegistry.add("tech", {"title": "Техника"}),
			"off": func() -> void: HintState.mark_entry_opened("tech")},
		"menu_rewards": {
			"on": func() -> void: MenuRegistry.add("meta_rewards", {"title": "Награды"}),
			"off": func() -> void: HintState.mark_entry_opened("meta_rewards")},
		"daily_reward": {
			"on": func() -> void:
				MetaState.root()["unlocked"] = true
				MetaState.sub("daily")["last"] = -1,
			"off": func() -> void: MetaState.sub("daily")["last"] = MetaState.today()},
		"quest_ready": {
			"on": func() -> void:
				MetaState.root()["unlocked"] = true
				MetaState.sub("quests")["daily"] = [
					{"id": "q1", "progress": 5, "target": 5, "claimed": false},
					{"id": "q2", "progress": 0, "target": 5, "claimed": false}],
			"off": func() -> void: MetaState.sub("quests")["daily"][0]["claimed"] = true},
		"achievement_new": {
			"on": func() -> void:
				MetaState.root()["unlocked"] = true
				MetaState.sub("ach")["a1"] = 1
				MetaState.sub("seen").erase("a1"),
			"off": func() -> void: Achievements.mark_all_seen()},
		"station_new": {
			"on": func() -> void:
				GameState.story_flags["fuel_station_built"] = true
				GameState.player_depth = 0
				if not GameState.owned_tools.has("hand_drill"):
					GameState.owned_tools.append("hand_drill"),
			"off": func() -> void: GameState.player_depth = 12},
		"tank_empty": {
			"on": func() -> void:
				GameState.current_tool = "hand_drill"
				FuelTank.set_fuel("hand_drill", 0.0),
			"off": func() -> void: FuelTank.set_fuel("hand_drill", 3.0)},
		"heat_over": {
			"on": func() -> void: GameState.player_depth = hot,
			"off": func() -> void: GameState.player_depth = 0},
		"well_ready": {
			"on": func() -> void:
				GameState.well_level = 1
				GameState.well_last_collect_unix = IdleWell.now_unix() - 30 * 86400,
			"off": func() -> void: GameState.well_last_collect_unix = IdleWell.now_unix()},
		"grave_news": {
			"on": func() -> void:
				GameState.story_flags.erase("diary_found")
				if not GameState.story_seen.has("grave_call"):
					GameState.story_seen.append("grave_call"),
			"off": func() -> void: GameState.story_flags["diary_found"] = true},
		"diary_unread": {
			"on": func() -> void:
				_unlock_diary()
				GameState.ext_get("story", {}).erase("diary_read"),
			"off": func() -> void:
				for id in StoryDiary.unlocked_ids():
					StoryDiary.mark_read(String(id))},
		"load_high": {
			"on": func() -> void: GameState.inventory["lead"] = 100,
			"off": func() -> void: GameState.inventory.clear()},
		"sell_ready": {
			"on": func() -> void: GameState.inventory["gold"] = 200,
			"off": func() -> void: GameState.inventory.clear()},
		"craft_ready": {
			"on": func() -> void:
				GameState.owned_tools.erase("hand_drill")
				GameState.max_depth_reached = int(recipe["unlock_depth"])
				GameState.coins = int(recipe["coins"])
				for id in (recipe["inputs"] as Dictionary).keys():
					GameState.house_storage[String(id)] = int(recipe["inputs"][id]),
			"off": func() -> void: GameState.owned_tools.append("hand_drill")},
		"shop_afford": {
			"on": func() -> void: GameState.coins = 5000000,
			"off": func() -> void: GameState.coins = 0},
		"hungry_food": {
			"on": func() -> void:
				GameState.hunger = 10.0
				GameState.inventory[food_id] = 2,
			"off": func() -> void: GameState.hunger = 100.0},
		"menu_equipment": {
			"on": func() -> void: MenuRegistry.add("equipment", {"title": "Снаряжение"}),
			"off": func() -> void: HintState.mark_entry_opened("equipment")},
		"combat_forge": {
			"on": func() -> void:
				(CombatService.state()["owned"] as Dictionary).erase(forge_id)
				GameState.coins = int(forge.get("coins", 0))
				for id in (forge["inputs"] as Dictionary).keys():
					GameState.house_storage[String(id)] = int(forge["inputs"][id]),
			"off": func() -> void:
				CombatService.give(forge_id)
				GameState.coins = 0
				GameState.house_storage.clear()},
		"combat_wear": {
			"on": func() -> void:
				CombatService.give(wear_id)
				(CombatService.state()["equipped"] as Dictionary).clear(),
			"off": func() -> void: CombatService.equip(wear_id)},
		"gear_new": {
			"on": func() -> void: GameState.owned_gear.append(gear_id),
			"off": func() -> void: GameState.owned_gear.clear()},
	}


## Первый собранный предмет с одним слоем-слотом (броня, шлем, оружие), не аксессуар.
func _first_wearable() -> String:
	for id in CombatData.gear_ids():
		if CombatData.slot_keys_for(String(id)).size() == 1:
			return String(id)
	return ""


func _check_every_rule() -> void:
	var scen := _scenarios()
	check("heat_over: нашлась глубина, где жарче стойкости костюма", _deepest_hot_depth() > 0)
	for r: Dictionary in HintData.rules():
		var id := String(r["id"])
		check("%s: есть сценарий проверки" % id, scen.has(id))
		if not scen.has(id):
			continue
		var on: Callable = scen[id]["on"]
		var off = scen[id].get("off", null)
		var rule := r.duplicate(true)
		rule["target"] = ["attached:t_btn"]
		_reset()
		var d := _new_director([rule])
		check("%s: до события условие ложно" % id, not HintConditions.test(rule["when"]))
		_run(d, 20.0)
		check("%s: без события не показывается" % id, not d.is_active() and not HintState.is_seen(id))

		on.call()
		check("%s: после события условие истинно" % id, HintConditions.test(rule["when"]))
		_run(d, 14.0)
		check("%s: срабатывает" % id, d.active_id() == id)
		check("%s: «показана» сохранена в ext" % id, HintState.is_seen(id) and not HintState.was_done(id))
		check("%s: тост с иконкой и Tip на нём" % id, d.overlay.is_showing()
			and not (d.overlay.chip().get_meta(Tip.META) as Dictionary)["title"].is_empty())

		if off != null:
			(off as Callable).call()
			_run(d, 1.0)
			check("%s: снимается, когда игрок сделал дело (условие пропало)" % id, not d.is_active() and HintState.was_done(id))
			on.call()
		else:
			_tap_btn(d)
			_run(d, 0.5)
			check("%s: снимается нажатием по цели" % id, not d.is_active() and HintState.was_done(id))
		_run(d, 60.0)
		check("%s: второй раз не показывается" % id, not d.is_active())

		HintState.reset()
		_run(d, 14.0)
		check("%s: «показать заново» возвращает подсказку" % id, d.active_id() == id)
		d.dismiss()
		_run(d, 1.0)

		# Сохранение через JSON, как в сейве: помнит и после «перезапуска».
		HintState.mark_seen(id)
		GameState.ext = JSON.parse_string(JSON.stringify(GameState.ext))
		check("%s: «показана» переживает сейв" % id, HintState.is_seen(id))
	_reset()


# ---------------------------------------------------------------------------
# Движок
# ---------------------------------------------------------------------------

func _check_engine() -> void:
	var cond_a := {"fn": "skill_points", "min": 1}
	var cond_b := {"fn": "artifacts", "min": 1}

	# Онбординг неприкосновенен: до флага food_ordered подсказок нет совсем.
	_reset(false)
	var d := _new_director([_rule("a", cond_a)])
	GameState.skill_points_available = 3
	_run(d, 40.0)
	check("до конца онбординга подсказки молчат", not d.is_active() and not HintState.is_seen("a"))
	check("онбординг пройден — только по флагу food_ordered (или второму уроку выживания)",
		not HintBusy.onboarding_done())
	GameState.house_tutorial_stage = 2
	check("второй урок выживания тоже открывает подсказки", HintBusy.onboarding_done())
	GameState.house_tutorial_stage = 0
	GameState.story_flags["food_ordered"] = true
	check("food_ordered открывает подсказки", HintBusy.onboarding_done())

	# Пауза после тишины: не сразу.
	_run(d, 3.0)
	check("первая подсказка не раньше first_delay", not d.is_active())
	_run(d, 3.0)
	check("после first_delay и hold подсказка показалась", d.active_id() == "a")

	# Одна за раз, по приоритету, и пауза между подсказками.
	_reset()
	var ra := _rule("a", cond_a, {"prio": 20})
	var rb := _rule("b", cond_b, {"prio": 10})
	d = _new_director([rb, ra])
	GameState.skill_points_available = 1
	GameState.collected_artifacts.append("antiquity_1")
	_run(d, 8.0)
	check("из двух готовых первой идёт с большим prio", d.active_id() == "a")
	check("вторая ждёт: не больше одной подсказки одновременно", not HintState.is_seen("b"))
	_tap_btn(d)
	d.tick(0.25)
	check("нажатие по цели снимает подсказку", not d.is_active())
	_run(d, 6.0)
	check("пауза между подсказками (gap) держится", not d.is_active() and not HintState.is_seen("b"))
	_run(d, 6.0)
	check("после паузы показывается следующая", d.active_id() == "b")

	# Время жизни.
	_reset()
	d = _new_director([_rule("t", cond_a, {"ttl": 3.0})])
	GameState.skill_points_available = 1
	_run(d, 5.5)
	check("ttl: подсказка висит", d.active_id() == "t")
	_run(d, 4.0)
	check("ttl: через N секунд снимается сама", not d.is_active())
	check("ttl: не заметил — «показана», но не «сделано»", HintState.is_seen("t") and not HintState.was_done("t"))
	check("ttl: больше не возвращается", _stays_hidden(d, 40.0))

	# Событие пропало — игрок сделал или передумал.
	_reset()
	d = _new_director([_rule("c", cond_a)])
	GameState.skill_points_available = 1
	_run(d, 7.0)
	GameState.skill_points_available = 0
	_run(d, 0.5)
	check("условие пропало — подсказка снята как «сделано»", not d.is_active() and HintState.was_done("c"))

	# Устойчивое условие: hold отсекает мелькнувшее состояние.
	_reset()
	d = _new_director([_rule("h", cond_a, {"hold": 2.0})])
	_run(d, 6.0)
	GameState.skill_points_available = 1
	_run(d, 1.0)
	GameState.skill_points_available = 0
	_run(d, 3.0)
	GameState.skill_points_available = 1
	_run(d, 1.5)
	check("hold: мелькнувшее условие не показывает подсказку", not d.is_active())
	_run(d, 2.0)
	check("hold: устойчивое условие показывает", d.active_id() == "h")

	# Цель пропала с экрана.
	_reset()
	var temp := Button.new()
	temp.size = Vector2(30, 30)
	temp.custom_minimum_size = Vector2(30, 30)
	temp.position = Vector2(100, 200)
	_layer.add_child(temp)
	HintPulse.attach(temp, "t_temp")
	d = _new_director([_rule("l", cond_a, {"target": ["attached:t_temp"], "ttl": 60.0})])
	GameState.skill_points_available = 1
	_run(d, 7.0)
	check("цель: подсказка стоит на кнопке", d.active_id() == "l")
	temp.visible = false
	_run(d, 1.0)
	check("цель скрыли — ждём, не снимаем сразу", d.is_active())
	_run(d, 2.0)
	check("цель пропала надолго — подсказка снята, не «сделано»", not d.is_active() and not HintState.was_done("l"))
	temp.free()

	# Нет цели — правило ждёт и не сгорает.
	_reset()
	d = _new_director([_rule("w", cond_a, {"target": ["attached:nothing_here"]})])
	GameState.skill_points_available = 1
	_run(d, 30.0)
	check("нет цели — не показывается и не сгорает", not d.is_active() and not HintState.is_seen("w"))
	HintPulse.attach(_btn, "nothing_here")
	_run(d, 3.0)
	check("цель появилась — подсказка показалась", d.active_id() == "w")
	HintPulse.detach("nothing_here")
	d.dismiss()

	# Цель-список: берётся первая найденная.
	var res := HintTargets.resolve(["attached:absent", "attached:t_btn"])
	check("список целей: берётся первая найденная и видимая", not res.is_empty() and res["node"] == _btn)
	check("цель-кнопка отдаёт её прямоугольник", (res["rect"] as Rect2).size == Vector2(30, 30) and bool(res["final"]))

	# Режим «не мешать».
	_reset()
	d = _new_director([_rule("m", cond_a)])
	GameState.skill_points_available = 1
	Settings.hints_enabled = false
	_run(d, 30.0)
	check("«не мешать»: подсказки молчат", not d.is_active() and not HintState.is_seen("m"))
	Settings.hints_enabled = true
	_run(d, 8.0)
	check("включили подсказки — показались (ничего не потеряно)", d.active_id() == "m")
	Settings.hints_enabled = false
	_run(d, 0.5)
	check("выключили во время показа — снимается", not d.is_active() and not d.overlay.is_showing())
	Settings.hints_enabled = true

	# События шины и сигналы только будят опрос; «разовое» событие помнится.
	_reset()
	d = _new_director([_rule("e", {"fn": "event", "id": "boss_defeated"})])
	_run(d, 10.0)
	check("event: без события правило молчит", not d.is_active())
	GameState.emit_event(&"boss_defeated", {"id": "x"})
	check("event: событие шины запомнено", HintConditions.latched.has("boss_defeated"))
	_run(d, 8.0)
	check("event: после события подсказка показалась", d.active_id() == "e")
	_reset()

	# Условия-комбинаторы и неизвестное имя.
	check("all: оба условия", not HintConditions.test({"all": [{"fn": "skill_points"}, {"fn": "artifacts"}]}))
	GameState.skill_points_available = 1
	check("any: хватает одного", HintConditions.test({"any": [{"fn": "skill_points"}, {"fn": "artifacts"}]}))
	check("not: отрицание", not HintConditions.test({"not": {"fn": "skill_points"}}))
	check("флаг сюжета как условие", not HintConditions.test({"fn": "flag", "name": "zzz"}))
	check("числа вида {value, proposed} разворачиваются",
		HintConditions.test({"fn": "skill_points", "min": {"value": 1, "proposed": true}}))
	GameState.skill_points_available = 0
	_reset()


func _stays_hidden(d: HintDirector, seconds: float) -> bool:
	_run(d, seconds)
	return not d.is_active()


# ---------------------------------------------------------------------------
# Не показывать во время катсцены, шторки, диалога, боя
# ---------------------------------------------------------------------------

func _check_busy() -> void:
	_reset()
	check("свободный игрок не занят", not HintBusy.is_busy())
	GameState.house_is_indoors = true
	check("интерьер дома — занят", HintBusy.is_busy())
	GameState.house_is_indoors = false
	GameState.era = "grandpa"
	check("катсцена в эпохе деда — занят", HintBusy.is_busy())
	GameState.era = "now"
	GameState.is_alive = false
	check("смерть — занят", HintBusy.is_busy())
	GameState.is_alive = true
	GameState.set("in_combat", false)
	check("бой: GameState.in_combat = false — свободен", not HintBusy.is_busy())
	var enemy := Node.new()
	enemy.add_to_group("in_combat")
	add_child(enemy)
	check("бой: узел в группе in_combat — занят", HintBusy.is_busy())
	enemy.free()
	GameState.ext_set("combat", {"active": true})
	check("бой: ext[combat].active — занят", HintBusy.is_busy())
	GameState.ext_set("combat", {"active": false})
	# Ветка боя: пока рядом живые монстры или идёт босс, подсказок нет.
	var fake := Node.new()
	var gd := GDScript.new()
	gd.source_code = "extends Node\nvar monsters: Array = []\nvar boss = null\n"
	gd.reload()
	fake.set_script(gd)
	add_child(fake)
	CombatService.director = fake
	check("бой: директор без монстров — свободен", not HintBusy.is_busy())
	fake.set("monsters", [1])
	check("бой: есть живой монстр рядом — занят", HintBusy.is_busy())
	fake.set("monsters", [])
	fake.set("boss", RefCounted.new())
	check("бой: идёт рейдбосс — занят", HintBusy.is_busy())
	fake.set("boss", null)
	CombatService.director = null
	fake.free()
	var screen := Control.new()
	screen.add_to_group("hint_block")
	_layer.add_child(screen)
	check("чужой экран в группе hint_block — занят", HintBusy.is_busy())
	screen.visible = false
	check("скрытый экран группы hint_block не мешает", not HintBusy.is_busy())
	screen.free()

	# Подсказка прячется на время шторки, и ttl в это время не тикает.
	_reset()
	var d := _new_director([_rule("p", {"fn": "skill_points", "min": 1}, {"ttl": 6.0})])
	GameState.skill_points_available = 1
	_run(d, 7.0)
	check("пауза: подсказка показана", d.active_id() == "p" and d.overlay.is_showing())
	var blocker := Control.new()
	blocker.add_to_group("hint_block")
	_layer.add_child(blocker)
	_run(d, 30.0)
	check("пауза: шторка открыта — подсказка не сгорает по времени", d.active_id() == "p")
	blocker.free()
	_run(d, 2.0)
	check("пауза: шторку закрыли — подсказка снова на месте", d.active_id() == "p")
	_run(d, 3.0)
	check("пауза: после возвращения доживает свой ttl", not d.is_active())

	# Шторка при покое: новая подсказка не начинается, а после закрытия — пауза.
	_reset()
	d = _new_director([_rule("q", {"fn": "skill_points", "min": 1})])
	GameState.skill_points_available = 1
	var blocker2 := Control.new()
	blocker2.add_to_group("hint_block")
	_layer.add_child(blocker2)
	_run(d, 30.0)
	check("шторка открыта — новая подсказка не начинается", not d.is_active())
	blocker2.free()
	_run(d, 2.0)
	check("после закрытия шторки — переводим дух (first_delay)", not d.is_active())
	_run(d, 5.0)
	check("потом показывается", d.active_id() == "q")
	_reset()


# ---------------------------------------------------------------------------
# Движение
# ---------------------------------------------------------------------------

func _check_motion() -> void:
	_reset()
	var d := _new_director([_rule("mo", {"fn": "skill_points", "min": 1})])
	GameState.skill_points_available = 1
	Settings.reduce_motion = true
	_run(d, 7.0)
	check("reduce_motion: подсказка показана без твинов",
		d.active_id() == "mo" and d.overlay._tap_tween == null and d.overlay._tween == null)
	check("reduce_motion: кольцо стоит на месте", d.overlay._ring._tw == null)
	d.dismiss()
	HintState.reset()
	Settings.reduce_motion = false
	_run(d, 14.0)
	check("с движением: палец «тапает» (твин)", d.active_id() == "mo" and d.overlay._tap_tween != null)
	check("с движением: кольцо пульсирует (твин)", d.overlay._ring._tw != null)
	check("палец-указатель показан у кнопки", d.overlay._finger.visible and not d.overlay._arrow.visible)
	var cr: Rect2 = d.overlay.chip().get_global_rect()
	check("тост-иконка на экране и не перекрывает цель", Rect2(Vector2.ZERO, Vector2(224, 480)).encloses(cr)
		and not cr.intersects(_btn.get_global_rect()))
	d.dismiss()
	Settings.reduce_motion = true
	_reset()

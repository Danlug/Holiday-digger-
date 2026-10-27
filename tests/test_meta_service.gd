extends Node
## test_meta_service — узел MetaService в живом дереве: включение после онбординга
## (флаг gold_sold), подписка на шину и сигналы GameState, пункты меню с бейджем,
## экраны (хаб, окно дня, тосты) строятся и работают без окна.
##
## Запуск: godot --headless --path . res://tests/test_meta_service.tscn

var failures := 0
var total := 0
const MONDAY := 20745


func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", label])


func _ready() -> void:
	print("=== test_meta_service ===")
	GameState.reset_progress()
	GameState.world_seed = 4242
	GameState.story_flags.clear()
	MetaClock.override_unix = MONDAY * MetaClock.DAY + 3600
	MenuRegistry.clear()
	await get_tree().process_frame

	var svc := MetaService.attach(self)
	await get_tree().process_frame
	check("сервис подключён и доступен как MetaService.instance", MetaService.instance == svc)
	check("до онбординга пунктов меню нет", MenuRegistry.entries().is_empty())

	GameState.emit_event(&"dug", {"cell": Vector2i(2, 3), "tile": TileTypes.Type.DIRT, "mineral": "", "loot": false})
	check("до онбординга события копятся, а наград и заданий нет",
		MetaState.counter("dug") == 1 and GameState.coins == 0 and (MetaState.sub("quests")["daily"] as Array).is_empty())
	svc._on_bus_event(&"dug", {"cell": Vector2i(2, 4), "tile": TileTypes.Type.DIRT, "mineral": "", "loot": false})

	GameState.story_flags["gold_sold"] = true
	svc._poll()
	check("флаг gold_sold включает мета-слой", MetaState.is_unlocked())
	check("после включения выданы задания дня и недели",
		(MetaState.sub("quests")["daily"] as Array).size() == QuestGen.count_of(MetaData.quests()["daily"])
		and (MetaState.sub("quests")["weekly"] as Array).size() == 3)
	check("накопленное до включения выдано достижениями («Первый комок»)", Achievements.is_done("dug_1") and GameState.coins >= 50)
	var ids: Array = []
	for e in MenuRegistry.entries():
		ids.append(e["id"])
	check("пункты меню «Ежедневный подарок» и «Награды» появились", ids.has("meta_daily") and ids.has("meta_rewards"))
	var daily_entry: Dictionary = {}
	var rewards_entry: Dictionary = {}
	for e in MenuRegistry.entries():
		if e["id"] == "meta_daily":
			daily_entry = e
		elif e["id"] == "meta_rewards":
			rewards_entry = e
	check("бейдж подарка = 1, пока не забран", MenuRegistry.badge_of(daily_entry) == 1)
	check("у пунктов есть иконка и заголовок для подсказки", MenuRegistry.icon_of(daily_entry) != null
		and MenuRegistry.text_of(rewards_entry, "title") != "")

	# --- шина и сигналы GameState ---
	var coins := GameState.coins
	GameState.emit_event(&"picked", {"item": "gold", "count": 1})
	check("picked по шине: «Первый золотой самородок»", Achievements.is_done("gold_1") and GameState.coins > coins)
	check("получение достижения ставит тост в очередь", svc.toast.pending() >= 1)
	GameState.update_max_depth(60)
	check("сигнал max_depth_changed: достижения глубины", Achievements.is_done("depth_15") and Achievements.is_done("depth_50"))
	GameState.die()
	check("сигнал died: «Двоечник пришёл к бабушке»", Achievements.is_done("die_1") and MetaState.counter("deaths") == 1)
	GameState.respawn()
	var lvl_before := GameState.level
	GameState.add_xp(100000)
	check("сигнал leveled_up доходит до движка (уровни растут живьём)", GameState.level > lvl_before and Achievements.is_done("level_5"))
	check("бейдж «Награды» считает непросмотренные достижения", MenuRegistry.badge_of(rewards_entry) >= 4)

	# --- свои закрытия не задваиваются через эхо шины ---
	var qd := {"id": "t:d", "tpl": "dig_any", "kind": "daily", "slot": 0, "event": "dug", "filter": {}, "sum": "", "mode": "",
		"target": 1, "progress": 0, "base": 0, "tier": 0, "glyph": "dig", "reward": {"coins": 10}, "points": 1, "claimed": false}
	var qw := {"id": "t:w", "tpl": "dailies_done", "kind": "weekly", "slot": 0, "event": "quest_done", "filter": {"kind": "daily"},
		"sum": "", "mode": "", "target": 5, "progress": 0, "base": 0, "tier": 0, "glyph": "clipboard",
		"reward": {"coins": 10}, "points": 3, "claimed": false}
	MetaState.sub("quests")["daily"] = [qd]
	MetaState.sub("quests")["weekly"] = [qw]
	GameState.emit_event(&"dug", {"cell": Vector2i(1, 9), "tile": TileTypes.Type.DIRT, "loot": false})
	check("закрытие ежедневного: недельное «N ежедневных» +1 ровно один раз", int(qw["progress"]) == 1 and int(qd["progress"]) == 1)

	# --- экраны ---
	svc.open_hub()
	await get_tree().process_frame
	check("хаб открывается, вкладка «Задания»", svc.hub.is_open() and svc.hub.current_tab() == MetaHub.TAB_TASKS)
	for tab in [MetaHub.TAB_ACH, MetaHub.TAB_ROAD, MetaHub.TAB_TASKS]:
		svc.hub._set_tab(tab)
		await get_tree().process_frame
		check("вкладка «%s» строится" % tab, svc.hub.is_open() and svc.hub._vbox.get_child_count() >= 2)
	svc.hub._set_tab(MetaHub.TAB_ACH)
	await get_tree().process_frame
	var grid: GridContainer = null
	for c in svc.hub._vbox.get_children():
		if c is GridContainer:
			grid = c
	check("сетка достижений — по плитке на каждое", grid != null and grid.get_child_count() == MetaData.achievements().size())
	svc.hub.close()
	check("закрытие хаба гасит бейдж непросмотренных", Achievements.unseen_count() == 0)

	var coins2 := GameState.coins
	svc.open_daily()
	await get_tree().process_frame
	check("окно дня открывается: семь плиток", svc.popup.is_open() and svc.popup._tiles.size() == 7)
	svc.popup._claim(1.0)
	check("«Забрать»: награда дня выдана, серия 1", GameState.coins - coins2 == 150 and int(MetaState.sub("daily")["streak"]) == 1)
	svc.popup._claim(1.0)
	check("повторное нажатие ничего не выдаёт", GameState.coins - coins2 == 150)
	check("после награды бейдж подарка погас", MenuRegistry.badge_of(daily_entry) == 0)
	await get_tree().create_timer(1.6).timeout
	check("окно само закрылось после награды", not svc.popup.is_open())

	svc.open_hub(MetaHub.TAB_ROAD)
	await get_tree().process_frame
	check("хаб открывается сразу на дороге трофеев", svc.hub.current_tab() == MetaHub.TAB_ROAD and svc.hub._road_scroll != null)
	svc.hub.close()

	MetaClock.override_unix = -1
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)

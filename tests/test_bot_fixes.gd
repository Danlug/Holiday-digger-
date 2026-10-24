extends Node
## test_bot_fixes — баги из отчёта бота (docs/PLAYTEST.md, P1), на настоящей main.tscn.
##
## Запуск: godot --headless --path . res://tests/test_bot_fixes.tscn
##
##  1. «Пропустить» в сценах «Смерть → Ранец → Роберт»: все три кончаются в доме, герой
##     заморожен — а ранец всё равно в собственности и надет, витрина его не продаёт.
##  2. Джойстик после катсцены/окна: HUD теряет ввод, отпускание пальца не доходит —
##     первое касание после этого всё равно ведёт героя (и в режиме «палец» тоже).
##  3. Кнопка «Тест» — только в отладочной сборке и без флага --no-debug-panel.
## Сцену «Заправка» (только когда бур в собственности) проверяет tests/test_fuel_station.

var failures := 0
var total := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== test_bot_fixes ===")
	await _test_skip_backpack()
	await _test_stick_after_lock()
	_test_debug_panel_gate()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


## Чистая игра: сейва нет, сюжет пройден до seen (просмотренные сцены не лезут в проверки).
func _clean_state(seen: Array, flags: Array) -> void:
	for f in ["user://save.json", "user://save.json.bak", "user://records.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	GameState.reset_progress()
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	for id in seen:
		StoryState.mark_seen(id)
	for f in flags:
		StoryState.set_flag(f)
	GameState.world_seed = 4242


func _spawn_main() -> Node2D:
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	await _frames(6)
	return m


# ---------------------------------------------------------------------------
# 1. Ранец после «Пропустить»
# ---------------------------------------------------------------------------

func _test_skip_backpack() -> void:
	_clean_state(["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure", "workshop"],
		["intro_seen", "workshop_seen", "gold_taken", "foundation_broken"])
	StoryState.enqueue("death")   # StoryState пишет очередь на диск, а режиссёр читает её оттуда
	var main := await _spawn_main()
	var director := main.find_child("StoryDirector", true, false) as StoryDirector
	var player: Node2D = main.find_child("Player", true, false)
	check("режиссёр и герой найдены", director != null and player != null)
	if director == null or player == null:
		main.free()
		return
	var skipped: Array = []
	for _i in range(300):
		await _frames(1)
		if director.cutscene != null and director.cutscene.is_playing:
			if not skipped.has(director.cutscene.scene_id):
				skipped.append(director.cutscene.scene_id)
			director.cutscene.skip()
		elif StoryState.is_seen("robert"):
			break
	check("пропущены все три сцены: смерть, ранец, Роберт",
		skipped.has("death") and skipped.has("backpack") and skipped.has("robert"), str(skipped))
	await _frames(3)
	check("цепочка кончилась в доме, герой заморожен (как у бота)", GameState.house_is_indoors and bool(player.frozen))
	check("ранец в собственности, хотя герой ещё не выходил", GameState.has_gear("backpack"))
	check("ранец надет — полёт есть", GameState.current_gear == "backpack" and player.has_backpack())
	var offer := {}
	for o in ShopItems.gear_offers():
		if String(o["ref"]) == "backpack":
			offer = o
	check("витрина: плитка ранца «уже есть», без цены", String(offer.get("state", "")) == "owned", str(offer.get("state")))
	var coins := GameState.coins
	check("витрина: купить ранец второй раз нельзя", not bool(ShopService.buy_gear("backpack")["ok"]) and GameState.coins == coins)

	# Сейв до этой правки: флаг сцены стоит, а ранца нет — режиссёр выдаёт его при загрузке.
	GameState.owned_gear.clear()
	GameState.current_gear = ""
	director._sync_story_gear()
	check("старый сейв: флаг ранца превращается в собственность при загрузке",
		GameState.has_gear("backpack") and GameState.current_gear == "backpack")
	main.free()
	await _frames(2)


# ---------------------------------------------------------------------------
# 2. Джойстик после катсцены и окон
# ---------------------------------------------------------------------------

func _touch(hud: Control, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = pressed
	hud.get_viewport().push_input(ev, true)


func _close_daily_popup() -> void:
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms) and ms.popup.is_open():
		ms.popup.close()
		await _frames(3)


func _test_stick_after_lock() -> void:
	_clean_state(["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure",
			"workshop", "death", "backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2"],
		["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "gold_sold", "food_ordered"])
	var main := await _spawn_main()
	await _close_daily_popup()
	var director := main.find_child("StoryDirector", true, false) as StoryDirector
	var player: Node2D = main.find_child("Player", true, false)
	var hud: Control = main.find_child("HUD", true, false)
	check("HUD, герой и режиссёр найдены", hud != null and player != null and director != null)
	if hud == null or player == null or director == null:
		main.free()
		return
	if hud.mode != "stick":
		hud._set_mode("stick")
	var right: Vector2 = hud._stick_center + Vector2(float(hud.stick_r) * 0.9, 0.0)
	check("HUD принимает ввод на старте", hud.is_processing_input() and not bool(player.frozen))

	_touch(hud, right, true)
	await _frames(1)
	check("джойстик: касание вправо ведёт героя", hud._stick_pointer == 0 and int(player.hold_dx) == 1)

	# Катсцена забирает управление посреди касания (как сцены глубины посреди копки);
	# палец отпускают, пока она идёт, — HUD этого не видит.
	director._take_control(false)
	await _frames(2)
	_touch(hud, right, false)
	await _frames(1)
	check("джойстик отпущен, пока HUD без ввода", hud._stick_pointer == -100 and int(player.hold_dx) == 0)
	director._release_control()
	await _frames(1)
	_touch(hud, right, true)
	await _frames(1)
	check("после катсцены первое же касание ведёт героя", hud._stick_pointer == 0 and int(player.hold_dx) == 1,
		"pointer=%d dx=%d" % [hud._stick_pointer, int(player.hold_dx)])
	_touch(hud, right, false)
	await _frames(1)

	# То же для любого окна, которое глушит ввод HUD (окно дня, задания, снаряжение, магазин).
	_touch(hud, right, true)
	await _frames(1)
	hud.set_process_input(false)
	await _frames(2)
	_touch(hud, right, false)
	await _frames(1)
	check("под окном герой не идёт сам по старому касанию", hud._stick_pointer == -100 and int(player.hold_dx) == 0)
	hud.set_process_input(true)
	await _frames(1)
	_touch(hud, right, true)
	await _frames(1)
	check("после окна первое же касание ведёт героя", hud._stick_pointer == 0 and int(player.hold_dx) == 1)
	_touch(hud, right, false)
	await _frames(1)

	# Режим «палец»: тот же залипший указатель удержания.
	hud._set_mode("hold")
	var spot: Vector2 = hud.stage_rect.get_center()
	_touch(hud, spot, true)
	await _frames(1)
	check("палец: удержание поймано", hud._touch_pointer == 0)
	hud.set_process_input(false)
	await _frames(2)
	_touch(hud, spot, false)
	await _frames(1)
	check("палец: удержание отпущено, пока HUD без ввода", hud._touch_pointer == -100 and not hud._has_touch)
	hud.set_process_input(true)
	_touch(hud, spot, true)
	await _frames(1)
	check("палец: после окна первое же касание поймано", hud._touch_pointer == 0 and hud._has_touch)
	_touch(hud, spot, false)
	hud._set_mode("stick")
	main.free()
	await _frames(2)


# ---------------------------------------------------------------------------
# 3. Кнопка «Тест»
# ---------------------------------------------------------------------------

func _test_debug_panel_gate() -> void:
	check("«Тест»: в release-сборке панели нет", not DebugPanel.allowed_for(false, PackedStringArray()))
	check("«Тест»: в release-сборке её не включить и флагами",
		not DebugPanel.allowed_for(false, PackedStringArray(["--debug-panel"])))
	check("«Тест»: в отладочной сборке есть", DebugPanel.allowed_for(true, PackedStringArray()))
	check("«Тест»: флаг --no-debug-panel прячет её и в отладке",
		not DebugPanel.allowed_for(true, PackedStringArray([DebugPanel.NO_PANEL_FLAG])))
	check("«Тест»: этот прогон — отладочный, и ворота смотрят на OS.is_debug_build()",
		DebugPanel.allowed() == (OS.is_debug_build() and not OS.get_cmdline_user_args().has(DebugPanel.NO_PANEL_FLAG)))

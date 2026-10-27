extends Node
## test_death_save — смерть пишется в сейв сразу (владелец, 27.10: «если после смерти быстро
## закрыть окно игры, то он появляется без штрафов на поверхности с последним лутом до спуска»).
## Причина была в том, что смерть в сейв не писалась вовсе: файл обновлял только автосейв раз
## в минуту, и закрытая до него вкладка поднимала прошлую запись — с рюкзаком и без платы.
##  1. Последний автосейв — под землёй с лутом; смерть → через один кадр (без таймера, окно смерти
##     открыто) в файле плата больнице, пустой рюкзак и уже воскресший дома герой.
##  2. Перезапуск из этого файла — дома, со штрафом и без лута.
##  3. Сейв мёртвым (вкладку закрыли до записи респавна) — при загрузке тот же респавн: дома,
##     верхний слой зарос, HP полное; файл тут же переписан живым.
##  4. Доллары (трата и получение) и награда сюжетной сцены — в файле тем же кадром.
##  5. Запись в конце кадра одна, сколько бы событий её ни попросило; вне веба переноса нет.
## Веб-проверка (закрытие вкладки сразу после смерти) — tools/web_death_save.js.
## Сценой — нужны автозагрузки:  godot --headless --path . res://tests/test_death_save.tscn

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
	print("=== test_death_save ===")
	GameState.world_seed = 4243
	Settings.language = "ru"
	_test_coalesce()
	await _test_death_written()
	await _test_dead_file_load()
	await _test_dollars_and_story()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _file() -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.SAVE_PATH))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


func _coins(d: Dictionary) -> int:
	return int(d.get("currency", {}).get("coins", -1))


func _fresh_main(keep_save: bool = false) -> Node2D:
	if not keep_save:
		SaveSystem.delete_save()
		GameState.reset_progress()
		StoryState.delete_from_disk()
		GameState.story_flags = {}
		GameState.story_seen = []
		GameState.story_queue = []
		for id in StoryData.scene_ids():
			StoryState.mark_seen(String(id))
		for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "gold_sold", "food_ordered"]:
			StoryState.set_flag(f)
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	await _frames(6)
	# Таймер автосейва стоит: всё, что попало в файл, записано событием, а не раз в минуту.
	GameState._autosave_timer.stop()
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms):
		ms.set_process(false)
		if ms.popup != null and ms.popup.is_open():
			ms.popup.close()
	return m


func _close(m: Node2D) -> void:
	m.free()
	await _frames(2)


# ---------------------------------------------------------------------------

func _test_coalesce() -> void:
	check("вне веба перенос движка не трогаем (install_web_sync → 0)", SaveSystem.install_web_sync() == 0)
	SaveSystem.save_at_frame_end("a")
	SaveSystem.save_at_frame_end("b")
	check("две просьбы за кадр — одна запись, причина первой", SaveSystem._pending_reason == "a")
	SaveSystem.delete_save()
	check("«Сброс» отменяет запись, заказанную на конец кадра", SaveSystem._pending_reason == "")


func _test_death_written() -> void:
	var main: Node2D = await _fresh_main()
	var p = main.player
	GameState.max_depth_reached = 120
	p.x = 16.5
	p.y = 110.5
	p.frozen = false
	await _frames(1)
	GameState.coins = 2000          # после кадра: награды достижений за глубину уже пришли
	GameState.inventory = {"silver": 4, "iron": 7}
	GameState.inventory_changed.emit()
	SaveSystem.save_game()          # «последний автосейв»: под землёй, с лутом, без платы
	var before := _file()
	check("предусловие: в файле лут и 2000 монет", _coins(before) == 2000
		and int(before.get("inventory", {}).get("silver", 0)) == 4, str(before.get("inventory")))

	# настоящий путь смерти: голод в тике выживания (GameState._process), респавн — main._process
	GameState.set_hunger(0.0)
	GameState.hp = 0.2
	var waited := 0
	while GameState.is_alive and waited < 60:
		await _frames(1)
		waited += 1
	check("герой умер от голода", String(GameState.death_cause.get("source", "")) == "starvation", str(GameState.death_cause))
	await _frames(1)
	var after := _file()
	# монеты в памяти после смерти могли вырасти наградой (достижение за смерть) — файл обязан
	# совпасть с памятью, а плата — быть 5% от 2000
	var coins_dead := GameState.coins
	check("плата больнице 100 (5% от 2000) списана", Healing.last_death_fee == 100, str(Healing.last_death_fee))
	check("через кадр после смерти (таймер стоит): в файле монеты после платы", _coins(after) == coins_dead,
		"в файле %d, в памяти %d" % [_coins(after), coins_dead])
	check("в файле пустой рюкзак", (after.get("inventory", {}) as Dictionary).is_empty(), str(after.get("inventory")))
	check("в файле уже воскресший герой (запись после респавна)", bool(after.get("survival", {}).get("is_alive", false))
		and float(after.get("survival", {}).get("hp", 0.0)) >= GameState.get_max_hp() - 0.01)
	check("в файле рекорд глубины остался", int(after.get("depth", {}).get("max_depth_reached", 0)) == 120)
	await get_tree().create_timer(0.9).timeout
	var win := main.find_child("DeathWindow", true, false) as DeathWindow
	check("окно смерти открыто — запись не ждала его закрытия", win != null and win.is_open())

	# «закрыли вкладку»: сцена уходит без всякого сохранения при выходе; в памяти — мусор
	await _close(main)
	GameState.coins = 777777
	GameState.inventory = {"gold": 9}
	GameState.is_alive = true
	var main2: Node2D = await _fresh_main(true)
	var p2 = main2.player
	check("перезапуск: монеты со штрафом, как в миг смерти", GameState.coins == coins_dead, "монет %d, ждали %d" % [GameState.coins, coins_dead])
	check("перезапуск: рюкзак пуст, лута до спуска нет", GameState.inventory.is_empty(), str(GameState.inventory))
	check("перезапуск: герой жив и дома, на поверхности", GameState.is_alive and p2.y < 1.0
		and absf(p2.x - p2.HOME_X) < 0.01, "x=%.1f y=%.1f" % [p2.x, p2.y])
	await _close(main2)


func _test_dead_file_load() -> void:
	var main: Node2D = await _fresh_main()
	var w: WorldGen = main.world
	var hx := int(main.player.HOME_X)
	GameState.coins = 900
	GameState.is_alive = false
	GameState.hp = 0.0
	GameState.set_hunger(10.0)
	w.diffs[2 * WorldGen.WIDTH + hx] = true   # дыра в верхнем слое под домом
	SaveSystem.save_game()
	await _close(main)
	var main2: Node2D = await _fresh_main(true)
	check("сейв мёртвым: при загрузке жив, HP полное", GameState.is_alive
		and is_equal_approx(GameState.hp, GameState.get_max_hp()))
	check("сейв мёртвым: верхний слой зарос, как при обычной смерти", not main2.world.is_dug(hx, 2))
	check("сейв мёртвым: сытость не ниже 25%", GameState.hunger >= 24.9, "%.1f" % GameState.hunger)
	check("сейв мёртвым: монеты не списаны второй раз", GameState.coins == 900, str(GameState.coins))
	check("сейв мёртвым: файл тут же переписан живым", bool(_file().get("survival", {}).get("is_alive", false)))
	await _close(main2)


func _test_dollars_and_story() -> void:
	var main: Node2D = await _fresh_main()
	GameState.dollars = 0
	GameState.add_dollars(30)
	await _frames(1)
	check("получение долларов — в файле тем же кадром", int(_file().get("currency", {}).get("dollars", -1)) == 30)
	check("трата долларов прошла", GameState.spend_dollars(12))
	await _frames(1)
	check("трата долларов — в файле тем же кадром", int(_file().get("currency", {}).get("dollars", -1)) == 18)
	var res := ShopService.exchange_dollars_to_coins(3)
	await _frames(1)
	var f := _file()
	check("обмен долларов на монеты — в файле", bool(res.get("ok", false)) and int(f.get("currency", {}).get("dollars", -1)) == 15
		and _coins(f) == GameState.coins, str(res))

	var d: StoryDirector = main.find_child("StoryDirector", true, false)
	GameState.owned_gear = []
	GameState.current_gear = ""
	check("предусловие: ранца нет", not GameState.owned_gear.has("backpack"))
	if d != null:
		d._on_cutscene_finished("backpack")
	await _frames(1)
	var gear: Array = _file().get("economy", {}).get("owned_gear", [])
	check("награда сцены (ранец) — в save.json тем же кадром, что «просмотрено» в story.json",
		d != null and gear.has("backpack") and StoryState.is_seen("backpack"), str(gear))

	# запись раньше в том же кадре (SaveHooks: «встал на новом месте», уход страницы) не глотает смерть:
	# save_now пишет не чаще раза в кадр, а смерть случилась после той записи
	GameState.coins = 1000
	GameState.inventory = {"silver": 2}
	SaveSystem.save_now("settled")
	GameState.take_damage(1e6, "fall")
	await _frames(1)
	var f2 := _file()
	check("смерть после save_now того же кадра всё равно в файле", (f2.get("inventory", {}) as Dictionary).is_empty()
		and _coins(f2) == GameState.coins and Healing.last_death_fee == 50, "монет в файле %d, рюкзак %s" % [_coins(f2), str(f2.get("inventory"))])
	await _close(main)

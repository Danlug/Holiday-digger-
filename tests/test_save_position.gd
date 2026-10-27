extends Node
## test_save_position — «закрыл игру под землёй — открыл там же» (владелец, 27.10; HeroSpot, SaveHooks).
##
## Запуск: godot --headless --path . res://tests/test_save_position.tscn
## Каждый сценарий — настоящая main.tscn: спуск, запись, GameState.reset_progress() (как новый процесс),
## новая main.tscn читает сейв с диска.
##  1. Стоит под землёй → та же клетка, на полу, тот же инструмент, глубина, взгляд; камера и туман вокруг.
##  2. Клетка стала породой → ближайшая пустая (не порода, не лава; с полом — первой).
##  3. В воздухе → висит без урона, пока не тронули управление; тронули — обычная физика.
##  4. Бурмобиль под землёй → снова в нём, на той же клетке; мёртвым — дома, машина на парковке.
##  5. Поверхность, дом, онбординг, отложенное землетрясение → как раньше, у дома.
##  6. Запись при закрытии: пауза/сворачивание/закрытие окна пишут место сразу, без автосейва;
##     сцена (frozen) место не переписывает, сейв мёртвого места не несёт.
##  7. Запись «встал на новом месте» (браузер убит без событий): через секунду простоя, не чаще раза в 10 с.
##
## Режим для веб-проверки (tools/smoke_save_position.js): `-- --seed-out КАТАЛОГ` кладёт туда save.json и
## story.json героя над шахтой в 6 клеток (онбординг пройден) и выходит.

var failures := 0
var total := 0
const SEED := 4242


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _key(key: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _story(all_seen: bool) -> void:
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	if all_seen:
		for id in StoryData.scene_ids():
			StoryState.mark_seen(String(id))
		for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "gold_sold", "food_ordered"]:
			StoryState.set_flag(f)
	else:
		# Онбординг в разгаре: мастерская пройдена, золото и фундамент — впереди (ГДД §9).
		for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure", "workshop"]:
			StoryState.mark_seen(id)
		StoryState.set_flag("intro_seen")


func _spawn() -> Node2D:
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	await _frames(6)
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms):
		ms.set_process(false)   # окно дня само замораживает героя через 1.5 с покоя — не в этой проверке
		if ms.popup != null and ms.popup.is_open():
			ms.popup.close()
	return m


## Новая игра (по умолчанию онбординг пройден). Как новый процесс: в доме никто не сидит.
func _fresh(all_seen: bool = true) -> Node2D:
	for f in ["user://save.json", "user://save.json.bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	GameState.reset_progress()
	GameState.house_is_indoors = false
	GameState.world_seed = SEED
	_story(all_seen)
	return await _spawn()


## «Закрыл и открыл»: запись, сцена освобождена, память GameState стёрта, новая сцена читает файл.
func _restart(m: Node2D, save := true) -> Node2D:
	if save:
		SaveSystem.save_game()
	m.free()
	await _frames(2)
	GameState.reset_progress()
	GameState.house_is_indoors = false
	return await _spawn()


func _solid(w, x: int, y: int) -> bool:
	var t: int = w.get_tile(x, y)
	return t != TileTypes.Type.EMPTY and t != TileTypes.Type.LAVA


## Шахта в колонке x от y0 до y1 включительно над природным полом (клетка y1+1 — порода). Ищет колонку
## и сдвигает шахту вниз, пока под ней не найдётся пол: мир от сида, и в нём бывают пустоты.
func _shaft(w: WorldGen, y0: int, length: int, x0: int = 19) -> Vector2i:
	for x in range(x0, WorldGen.WIDTH - 1):
		for shift in range(0, 40):
			var top := y0 + shift
			var bottom := top + length
			if _solid(w, x, bottom + 1):
				for y in range(top, bottom + 1):
					w.diffs[y * WorldGen.WIDTH + x] = true
				w.mark_changed()
				return Vector2i(x, bottom)
	push_error("test_save_position: не нашлось места под шахту")
	return Vector2i(x0, y0)


## Ставит героя на пол клетки, будто он туда дошёл сам.
func _stand(p, c: Vector2i) -> void:
	p.x = float(c.x) + 0.5
	p.y = float(c.y) + 1.0 - p.HH - 0.001
	p.vx = 0.0
	p.vy = 0.0
	p.on_ground = true
	p.frozen = false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--seed-out"):
		await _seed_out(args[args.find("--seed-out") + 1])
		get_tree().quit(0)
		return
	print("=== test_save_position ===")
	await _test_standing()
	await _test_blocked()
	_test_find_safe_cell_fake()
	await _test_air()
	await _test_rig()
	await _test_home_cases()
	await _test_close_hooks()
	await _test_step_save()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# 1. Стоит под землёй
# ---------------------------------------------------------------------------

func _test_standing() -> void:
	var m := await _fresh()
	var p = m.player
	GameState.grant_tool("rusty_pickaxe")
	GameState.set_current_tool("rusty_pickaxe")
	var c := _shaft(m.world, 30, 0)
	_stand(p, c)
	p.facing = -1
	m.fog.reveal_around(26.5, 90.5, 2, 1)   # «разведано когда-то раньше», далеко от героя
	await _frames(3)
	check("стоит под землёй: место пишется в ext", HeroSpot.saved_cell() == c, "%s vs %s" % [GameState.ext.get("hero_spot"), c])
	var m2 := await _restart(m)
	var p2 = m2.player
	await _frames(3)
	check("загрузка: та же клетка %s" % c, p2.cell_x() == c.x and p2.cell_y() == c.y, "(%d, %d)" % [p2.cell_x(), p2.cell_y()])
	await _wait(0.3)
	# on_ground в headless мигает (кадр короче 0.1 мс — шаг падения меньше порога столкновения), поэтому по высоте
	check("загрузка: стоит на полу, не падает", p2.cell_y() == c.y and absf(p2.y - (c.y + 1.0 - p2.HH)) < 0.02,
		"y %.3f vy %.2f" % [p2.y, p2.vy])
	check("загрузка: глубина, инструмент — ржавая кирка, смотрит влево",
		GameState.player_depth == c.y and GameState.current_tool == "rusty_pickaxe" and int(p2.facing) == -1,
		"глубина %d, %s, взгляд %d" % [GameState.player_depth, GameState.current_tool, int(p2.facing)])
	check("загрузка: не в доме, не заморожен, не висит", not GameState.house_is_indoors and not p2.frozen
		and not (m2.get_node("SaveHooks") as SaveHooks).is_hovering())
	var cam: Vector2 = m2.hud.current_cam
	var vc: Vector2i = m2.hud.get_view_cells()
	check("камера сразу у героя (без проезда от дома)",
		p2.y > cam.y and p2.y < cam.y + vc.y and p2.x > cam.x and p2.x < cam.x + vc.x, "камера %s, герой (%.1f, %.1f)" % [cam, p2.x, p2.y])
	check("туман вокруг героя открыт", m2.fog.get_state(c.x, c.y) != FogOfWar.State.BLACK
		and m2.fog.get_state(c.x, c.y + 1) != FogOfWar.State.BLACK)
	check("разведанное раньше осталось открытым", m2.fog.get_state(26, 90) != FogOfWar.State.BLACK)
	m2.free()
	await _frames(2)


# ---------------------------------------------------------------------------
# 2. Клетка стала породой (обвал, другая сборка мира)
# ---------------------------------------------------------------------------

func _test_blocked() -> void:
	var m := await _fresh()
	var p = m.player
	var c := _shaft(m.world, 40, 0)
	var other := _shaft(m.world, c.y - 1, 0, c.x + 2)   # пустая клетка в паре шагов
	_stand(p, c)
	await _frames(3)
	SaveSystem.save_game()
	# Мир изменился между сессиями: клетку героя засыпало (дифф раскопки пропал из сейва).
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://save.json"))
	var dug: Array = data["world"]["gen"]["dug"]
	var key := c.y * WorldGen.WIDTH + c.x
	for i in range(dug.size() - 1, -1, -1):
		if int(dug[i]) == key:
			dug.remove_at(i)
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var m2 := await _restart(m, false)
	var p2 = m2.player
	var w2: WorldGen = m2.world
	var at := Vector2i(p2.cell_x(), p2.cell_y())
	check("засыпано: клетка героя теперь порода", _solid(w2, c.x, c.y))
	check("засыпано: герой рядом, а не дома", at.y >= 1 and (at - c).length() <= 4.0, "%s (была %s, рядом %s)" % [at, c, other])
	check("засыпано: герой в пустой клетке, ни одна его точка не в породе",
		w2.get_tile(at.x, at.y) == TileTypes.Type.EMPTY and not p2._solid_at(p2.x - p2.HW + 0.02, p2.y)
		and not p2._solid_at(p2.x + p2.HW - 0.02, p2.y) and not p2._solid_at(p2.x, p2.y - p2.HH + 0.02)
		and not p2._solid_at(p2.x, p2.y + p2.HH - 0.02))
	m2.free()
	await _frames(2)


class FakeWorld:
	extends RefCounted
	var cells: Dictionary = {}   # Vector2i -> тип; чего нет — камень
	func get_tile(x: int, y: int) -> int:
		return int(cells.get(Vector2i(x, y), TileTypes.Type.STONE))


func _test_find_safe_cell_fake() -> void:
	var fw := FakeWorld.new()
	var c := Vector2i(20, 3000)
	# Герой в камне; вплотную — лава, пустоты в двух клетках: над лавой и над камнем.
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		fw.cells[c + d] = TileTypes.Type.LAVA
	fw.cells[c + Vector2i(0, -2)] = TileTypes.Type.EMPTY   # пол — лава
	fw.cells[c + Vector2i(2, 0)] = TileTypes.Type.EMPTY    # пол — камень
	var got := HeroSpot.find_safe_cell(fw, c)
	check("поиск места: не лава и не порода", got != Vector2i(-1, -1) and fw.get_tile(got.x, got.y) == TileTypes.Type.EMPTY, str(got))
	check("поиск места: из равных по расстоянию — на камне, не на лаве", got == c + Vector2i(2, 0), str(got))
	fw.cells.erase(c + Vector2i(2, 0))
	fw.cells[c + Vector2i(3, 0)] = TileTypes.Type.EMPTY
	fw.cells[c + Vector2i(3, 1)] = TileTypes.Type.EMPTY    # без пола
	check("поиск места: ближняя клетка лучше дальней, даже если у ближней пол — лава",
		HeroSpot.find_safe_cell(fw, c) == c + Vector2i(0, -2), str(HeroSpot.find_safe_cell(fw, c)))
	check("поиск места: вокруг одна порода — места нет (герой пойдёт домой)",
		HeroSpot.find_safe_cell(FakeWorld.new(), c) == Vector2i(-1, -1))
	fw.cells[c] = TileTypes.Type.EMPTY
	check("поиск места: своя клетка свободна — она и есть", HeroSpot.find_safe_cell(fw, c) == c)


# ---------------------------------------------------------------------------
# 3. В воздухе
# ---------------------------------------------------------------------------

func _put_in_air(p, x: int, y: int) -> void:
	p.x = float(x) + 0.5
	p.y = float(y) + 0.5
	p.vx = 0.0
	p.vy = 0.0
	p.on_ground = false
	p.frozen = false


func _test_air() -> void:
	var m := await _fresh()
	GameState.grant_gear("backpack")
	var bottom := _shaft(m.world, 30, 40)   # 40 клеток пустоты: свалиться — серьёзный урон
	var air := Vector2i(bottom.x, bottom.y - 35)
	_put_in_air(m.player, air.x, air.y)
	SaveSystem.save_game()
	check("в воздухе: место записано", HeroSpot.saved_cell() == air, "%s vs %s" % [GameState.ext.get("hero_spot"), air])
	var m2 := await _restart(m, false)
	var p2 = m2.player
	var hooks := m2.get_node("SaveHooks") as SaveHooks
	var hp0 := GameState.hp
	await _wait(1.0)
	check("в воздухе: висит на той же клетке, пока не тронули управление",
		hooks.is_hovering() and p2.cell_x() == air.x and p2.cell_y() == air.y and absf(p2.y - (air.y + 0.5)) < 0.05, "y %.3f" % p2.y)
	check("в воздухе: загрузка не дала урона", is_equal_approx(GameState.hp, hp0), "HP %.1f → %.1f" % [hp0, GameState.hp])
	# Тронул «вверх» с ранцем — летит дальше, как летел.
	_key(KEY_W, true)
	await _wait(0.8)
	_key(KEY_W, false)
	check("в воздухе: «вверх» с ранцем — полёт продолжается от той же точки",
		not hooks.is_hovering() and p2.y < air.y + 0.3, "y %.3f" % p2.y)
	check("в воздухе: урона нет и после первого касания", is_equal_approx(GameState.hp, hp0))
	m2.free()
	await _frames(2)

	# Низко над полом без ранца: тронул — падает как обычно, мягко.
	m = await _fresh()
	bottom = _shaft(m.world, 30, 2)
	air = Vector2i(bottom.x, bottom.y - 2)
	_put_in_air(m.player, air.x, air.y)
	m2 = await _restart(m)
	p2 = m2.player
	hooks = m2.get_node("SaveHooks") as SaveHooks
	hp0 = GameState.hp
	check("низко в воздухе: висит", hooks.is_hovering() and p2.cell_y() == air.y, "клетка %d, ждали %d" % [p2.cell_y(), air.y])
	# «вверх» без ранца в воздухе ничего не делает — только снимает «висение»; вбок копал бы стену
	_key(KEY_W, true)
	await _wait(0.1)
	_key(KEY_W, false)
	await _wait(1.0)
	check("низко в воздухе: тронул — упал на пол шахты без урона",
		p2.cell_y() == bottom.y and absf(p2.y - (bottom.y + 1.0 - p2.HH)) < 0.02 and is_equal_approx(GameState.hp, hp0),
		"клетка %d (пол %d), на полу %s, HP %.1f → %.1f" % [p2.cell_y(), bottom.y, str(p2.on_ground), hp0, GameState.hp])
	m2.free()
	await _frames(2)


# ---------------------------------------------------------------------------
# 4. Бурмобиль
# ---------------------------------------------------------------------------

func _test_rig() -> void:
	var m := await _fresh()
	var p = m.player
	GameState.grant_tool("drill_rig")
	GameState.current_tool = "drill_rig"
	GameState.rig_parked_at = Vector2i(-1, -1)
	var c := _shaft(m.world, 40, 0)
	_stand(p, c)
	await _frames(3)
	var m2 := await _restart(m)
	var p2 = m2.player
	await _frames(3)
	check("бурмобиль: снова за рулём на той же клетке", p2.is_in_rig() and p2.cell_x() == c.x and p2.cell_y() == c.y,
		"%s (%d, %d)" % [GameState.current_tool, p2.cell_x(), p2.cell_y()])
	check("бурмобиль: машина не раздвоилась на парковке", not GameState.is_rig_parked())
	# Умер за рулём (сейв в кадр смерти) — дома, машина на парковке у устья (как было).
	GameState.is_alive = false
	GameState.hp = 0.0
	var m3 := await _restart(m2)
	var p3 = m3.player
	check("умер за рулём: дома, жив", GameState.is_alive and _home(p3), "(%.1f, %.1f)" % [p3.x, p3.y])
	check("умер за рулём: бурмобиль запаркован, в руках не он", GameState.is_rig_parked() and GameState.current_tool != "drill_rig",
		"%s, парковка %s" % [GameState.current_tool, GameState.rig_parked_at])
	m3.free()
	await _frames(2)


# ---------------------------------------------------------------------------
# 5. Поверхность, дом, онбординг, землетрясение — как раньше
# ---------------------------------------------------------------------------

func _home(p) -> bool:
	return p.y < 1.0 and is_equal_approx(p.x, p.HOME_X)


func _test_home_cases() -> void:
	# Поверхность: место не пишется, запуск у дома.
	var m := await _fresh()
	m.player.x = 26.5
	m.player.y = 0.5
	await _frames(3)
	check("поверхность: место не пишется", not GameState.ext.has("hero_spot"))
	var m2 := await _restart(m)
	check("поверхность: запуск у дома, как раньше", _home(m2.player) and not GameState.house_is_indoors)

	# Был под землёй, поднялся и зашёл в дом — запуск у дома, снаружи.
	_stand(m2.player, _shaft(m2.world, 40, 0))
	await _frames(3)
	check("подготовка: под землёй место записано", HeroSpot.saved_cell().y >= 40)
	m2.player.teleport_home()
	await _frames(2)
	HouseSystem.instance.enter_house("hall")
	await _frames(3)
	check("в доме: место стёрто", not GameState.ext.has("hero_spot"))
	var m3 := await _restart(m2)
	check("из дома: запуск у дома, снаружи", _home(m3.player) and not GameState.house_is_indoors)
	m3.free()
	await _frames(2)

	# Онбординг в разгаре (до сцены смерти; копают первые уровни огорода): у дома, как раньше.
	m = await _fresh(false)
	m.world.diffs[3 * WorldGen.WIDTH + 20] = true
	m.world.mark_changed()
	_stand(m.player, Vector2i(20, 3))
	await _frames(3)
	m2 = await _restart(m)
	check("до конца онбординга: у дома, как раньше", _home(m2.player), "(%.1f, %.1f)" % [m2.player.x, m2.player.y])
	m2.free()
	await _frames(2)

	# Отложенное землетрясение: копальню трясёт при запуске, герой просыпается дома (main.gd, как было).
	m = await _fresh()
	_stand(m.player, _shaft(m.world, 40, 0))
	await _frames(3)
	GameState.pending_earthquake = true
	m2 = await _restart(m)
	check("землетрясение ждало: не в перетряхнутой породе, а дома", m2.player.y < 1.0 and not GameState.pending_earthquake,
		"(%.1f, %.1f)" % [m2.player.x, m2.player.y])
	m2.free()
	await _frames(2)


# ---------------------------------------------------------------------------
# 6. Запись при закрытии
# ---------------------------------------------------------------------------

func _saved_spot_on_disk() -> Vector2i:
	var data = JSON.parse_string(FileAccess.get_file_as_string("user://save.json"))
	if typeof(data) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)
	var spot = Dictionary(data.get("ext", {})).get("hero_spot")
	if typeof(spot) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)
	return Vector2i(int(spot.get("x", -1)), int(spot.get("y", -1)))


func _test_close_hooks() -> void:
	var m := await _fresh()
	var hooks := m.get_node("SaveHooks") as SaveHooks
	hooks._since_step = -1.0e9   # запись «встал на новом месте» здесь не нужна: проверяем сами события
	var p = m.player
	SaveSystem.save_game()   # «автосейв» у дома
	check("подготовка: на диске места нет", _saved_spot_on_disk() == Vector2i(-1, -1))
	var a := _shaft(m.world, 40, 0)
	_stand(p, a)
	await _frames(2)
	hooks._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check("пауза/сворачивание: место на диске сразу, без автосейва", _saved_spot_on_disk() == a, str(_saved_spot_on_disk()))
	var b := _shaft(m.world, 50, 0)
	_stand(p, b)
	await _frames(2)
	hooks._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check("закрытие окна: место на диске сразу", _saved_spot_on_disk() == b, str(_saved_spot_on_disk()))
	var c := _shaft(m.world, 60, 0)
	_stand(p, c)
	await _frames(2)
	hooks._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("потеря фокуса: место на диске сразу", _saved_spot_on_disk() == c, str(_saved_spot_on_disk()))
	# Повтор в том же кадре (скрытие и уход страницы приходят подряд) второй раз не пишет.
	var len0 := FileAccess.get_file_as_string("user://save.json").length()
	GameState.coins += 12345
	var wrote_again := SaveSystem.save_now("again")
	check("повтор в том же кадре: ответ «записано», второй записи нет",
		wrote_again and FileAccess.get_file_as_string("user://save.json").length() == len0)

	# Сцена держит героя (frozen) и водит player.x/y за актёром — место не переписывается.
	p.frozen = true
	p.x = 5.5
	p.y = 120.5
	await _frames(2)
	SaveSystem.save_game()
	check("сцена (frozen): место осталось прежним", _saved_spot_on_disk() == c, str(_saved_spot_on_disk()))
	_stand(p, c)
	# Смерть: сейв мёртвого места не несёт, даже записанный в тот же кадр.
	GameState.is_alive = false
	SaveSystem.save_game()
	check("смерть: в сейве мёртвого места нет", _saved_spot_on_disk() == Vector2i(-1, -1))
	GameState.is_alive = true
	m.free()
	await _frames(2)


## Браузер убили без единого события (телефон выгрузил свёрнутый браузер, закрыли окно целиком): спасает
## запись «встал на новом месте» — через SETTLE_S простоя, не чаще раза в STEP_GAP_S.
func _test_step_save() -> void:
	var m := await _fresh()
	var hooks := m.get_node("SaveHooks") as SaveHooks
	var p = m.player
	SaveSystem.save_game()
	var a := _shaft(m.world, 40, 0)
	_stand(p, a)
	await _wait(SaveHooks.SETTLE_S + 0.4)
	check("встал на новом месте: запись сама, без автосейва и событий", _saved_spot_on_disk() == a, str(_saved_spot_on_disk()))
	var b := _shaft(m.world, 50, 0)
	_stand(p, b)
	await _wait(SaveHooks.SETTLE_S + 0.4)
	check("второй раз подряд — не раньше чем через STEP_GAP_S", _saved_spot_on_disk() == a, str(_saved_spot_on_disk()))
	hooks._since_step = SaveHooks.STEP_GAP_S
	await _wait(SaveHooks.SETTLE_S + 0.4)
	check("через STEP_GAP_S — пишет новое место", _saved_spot_on_disk() == b, str(_saved_spot_on_disk()))
	# Копает без остановки — записей нет (рывков посреди копки не будет).
	hooks._since_step = SaveHooks.STEP_GAP_S
	var c := _shaft(m.world, 60, 0)
	_stand(p, c)
	p.digging = {"x": c.x, "y": c.y + 1, "t": 0.0, "total": 1.0e9, "type": TileTypes.Type.STONE}
	await _wait(SaveHooks.SETTLE_S + 0.4)
	check("пока копает — не пишет", _saved_spot_on_disk() == b, str(_saved_spot_on_disk()))
	p.digging = null
	m.free()
	await _frames(2)


# ---------------------------------------------------------------------------
# Веб-проверка: заготовка сейва «в шахте, онбординг пройден»
# ---------------------------------------------------------------------------

func _seed_out(dir: String) -> void:
	var m := await _fresh()
	GameState.grant_tool("rusty_pickaxe")
	GameState.set_current_tool("rusty_pickaxe")
	GameState.coins = 500
	# Герой висит над шахтой в 6 клеток (загрузка его не роняет); «вниз» в браузере — и он внизу.
	var bottom := _shaft(m.world, 20, 6)
	var c := Vector2i(bottom.x, bottom.y - 6)
	_put_in_air(m.player, c.x, c.y)
	SaveSystem.save_game()
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["save.json", "story.json"]:
		DirAccess.copy_absolute(ProjectSettings.globalize_path("user://" + f), dir.path_join(f))
	print("seed: герой %s над шахтой до %d, онбординг пройден → %s" % [c, bottom.y, dir])
	m.free()

extends Node
## test_bot_onboarding — бот проигрывает онбординг (ГДД раздел 9) на ЖИВОЙ сцене.
##
## Запуск (как и все тесты):
##   godot --headless --path . res://tests/test_bot_onboarding.tscn
##   godot --headless --path . res://tests/test_bot_onboarding.tscn -- --seed=777 --scale=4
##
## Бот нажимает настоящие клавиши и тапает мышью (tests/bot/bot_player.gd), а
## всё остальное делает игра сама: интро (тапаем реплики), три ручные копки,
## автокопка, мастерская и кирка, пять самородков, фундамент, сцена смерти,
## респавн в мастерской, «продай золото», «закажи еду». На каждом шаге —
## бюджет игрового времени: если что-то застряло, тест падает с дампом
## состояния, а не висит.
##
## Изоляция. Тест гоняется в дочернем процессе Godot с собственным
## XDG_DATA_HOME: игра пишет user://save.json и story.json по ходу, а соседние
## тесты (run_tests.sh идёт по 4 штуки) читают их на старте. Заодно родитель
## читает весь вывод ребёнка и валит прогон на «SCRIPT ERROR» / «ERROR:».
## Ключ --inproc отключает это (отладка в редакторе).

const DEFAULT_SEED := 20260101
const DEFAULT_SCALE := 4.0
## Заведомо безвредные строки лога (предупреждения движка/игры, не ошибки игры).
const LOG_ALLOW: Array[String] = [
	"story_en.json",
]

var failures := 0
var total := 0

var bot := BotPlayer.new()
var main: Node2D
var player: Node2D
var world: WorldGen
var hud: Control
var director: StoryDirector
var house: HouseSystem

var _seed := DEFAULT_SEED
## --soak=N: после онбординга бот N игровых минут «живёт»: копает шахту, поднимается на
## ранце, продаёт, покупает ступени, ест и спит. 0 — не играть (так идёт run_tests.sh).
var _soak_minutes := 0.0
var _soak_log: Array = []
## Игрок возвращается не только с полным рюкзаком: через TRIP_SECONDS копки бот идёт наверх сам,
## иначе подъём (самое хрупкое место: ранец, ствол тоннеля, выход на поверхность) не проверялся бы.
const TRIP_SECONDS := 150.0
var _soak_force_up := false
var _modals_dismissed := 0
var _scale := DEFAULT_SCALE
var _sim := 0.0
var _frames := 0
var _wall0 := 0
var _last_tap := -10.0
var _dead := false
var _timeline: Array = []
var _lines_seen: Dictionary = {}
var _refusals: Array = []
var _digs: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--seed="):
			_seed = int(a.substr(7))
		elif a.begins_with("--scale="):
			_scale = float(a.substr(8))
		elif a.begins_with("--soak="):
			_soak_minutes = float(a.substr(7))
	if OS.get_environment("RASKOPKI_BOT_CHILD") != "1" and not args.has("--inproc") \
			and OS.get_name() == "Linux":
		_run_isolated(args)
		return
	_run()


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


# ---------------------------------------------------------------------------
# Родитель: дочерний процесс + разбор лога
# ---------------------------------------------------------------------------

func _run_isolated(args: PackedStringArray) -> void:
	print("=== test_bot_onboarding (изолированный дочерний процесс) ===")
	var tmp := "/tmp/raskopki_bot_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(tmp)
	var argv: Array = ["XDG_DATA_HOME=" + tmp, "RASKOPKI_BOT_CHILD=1", OS.get_executable_path(),
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/test_bot_onboarding.tscn", "--"]
	argv.append_array(args)
	var out: Array = []
	var code := OS.execute("env", argv, out, true)
	OS.execute("rm", ["-rf", tmp])
	var text := String(out[0]) if out.size() > 0 else ""
	print(text)

	var bad: Array[String] = []
	for line in text.split("\n"):
		var is_err: bool = line.contains("SCRIPT ERROR") or line.contains("Parse Error") \
			or line.begins_with("ERROR:") or line.contains("Invalid call") or line.contains("Invalid access")
		if not is_err:
			continue
		var allowed := false
		for a in LOG_ALLOW:
			if line.contains(a):
				allowed = true
		if not allowed:
			bad.append(line.strip_edges())
	var ok := code == 0 and bad.is_empty()
	if not bad.is_empty():
		print("[FAIL] в логе игры есть ошибки (%d), первые:" % bad.size())
		for i in range(mini(bad.size(), 8)):
			print("    ", bad[i])
	print("[%s] дочерний прогон: код %d, ошибок в логе %d" % ["OK" if ok else "FAIL", code, bad.size()])
	var child_summary := ""
	for line in text.split("\n"):
		if line.contains("Итог:"):
			child_summary = line.strip_edges()
	# Строку «Итог» ждёт run_tests.sh: берём детский счёт и добавляем свою проверку лога.
	if child_summary.is_empty():
		print("=== Итог: 1 проверок, 1 провалов ===")
	else:
		print(child_summary if ok else child_summary.replace("0 провалов", "1+ провалов"))
	get_tree().quit(0 if ok else 1)


# ---------------------------------------------------------------------------
# Каркас: кадры, ожидания, дамп
# ---------------------------------------------------------------------------

func _step() -> void:
	await get_tree().process_frame
	_frames += 1
	_sim += get_process_delta_time()
	_auto_story()


func _frames_n(n: int) -> void:
	for _i in range(n):
		await _step()


## Бот листает катсцены тапами: обычный тап — дописать реплику / следующий
## кадр, обязательный тап — по подсвеченной цели. Кнопку «Пропустить» не трогаем:
## сцены должны доигрываться ПО-НАСТОЯЩЕМУ (мировые кадры, таймеры, эффекты).
func _auto_story() -> void:
	_dismiss_modals()
	if director == null or director.cutscene == null:
		return
	var cs: CutscenePlayer = director.cutscene
	if not cs.is_playing:
		return
	var text := String(cs._line.text) if cs._line != null else ""
	if not text.is_empty():
		_lines_seen[text] = true
	if _sim - _last_tap < 0.12:
		return
	_last_tap = _sim
	if cs._tap_target != null and cs._tap_target.visible:
		bot.tap(cs._tap_target.get_global_rect().get_center())
	else:
		bot.tap(Vector2(112.0, 300.0))


## Окна, которые сами всплывают в «спокойный момент» и замораживают героя (ежедневная награда
## мета-слоя): человек жмёт «Забрать», бот тоже. Проверяем, что окно закрывается и отпускает героя.
func _dismiss_modals() -> void:
	# Первая настоящая находка открывает витрину музея (ГДД п.9); пока она открыта, HUD не читает ввод.
	if ProgressScreen.is_open():
		ProgressScreen.close_screen()
		_soak_log.append("окно прогресса закрыто на %.0f с" % _sim)
	var meta := MetaService.instance
	if meta == null or not is_instance_valid(meta) or meta.popup == null:
		return
	if meta.popup.is_open():
		var before := GameState.coins
		var btn: Button = meta.popup._claim_btn
		if btn != null and btn.visible and not btn.disabled:
			btn.pressed.emit()
		if meta.popup.is_open():
			meta.popup.close()
		_soak_log.append("окно дня: забрано %d монет на %.0f с" % [GameState.coins - before, _sim])
		_modals_dismissed += 1
	if meta.hub != null and meta.hub.is_open():
		meta.hub.close()


## Ждёт условие не дольше budget секунд ИГРОВОГО времени. Таймаут — провал с
## дампом состояния и остановка прогона (дальше цепочка всё равно не пойдёт).
func _until(cond: Callable, budget: float, label: String) -> bool:
	if _dead:
		return false
	var t0 := _sim
	while _sim - t0 < budget:
		if cond.call():
			_timeline.append([label, _sim - t0])
			check(label, true)
			return true
		await _step()
	check("не застряли: " + label, false, "за %.0f с игрового времени\n%s" % [budget, _dump()])
	_dead = true
	return false


func _dump() -> String:
	var parts: Array[String] = []
	if player != null:
		parts.append("герой (%.2f, %.2f) vx=%.2f vy=%.2f ground=%s frozen=%s digging=%s tool=%s" % [
			player.x, player.y, player.vx, player.vy, player.on_ground, player.frozen,
			str(player.digging), GameState.current_tool])
	if director != null:
		parts.append("катсцена: %s (%s)  автокопка: %s  очередь: %s" % [
			director.cutscene.scene_id, director.cutscene.is_playing, director.auto_dig.running, str(GameState.story_queue)])
		parts.append("задание: «%s»" % director._objective)
	parts.append("флаги: %s  просмотрено: %s" % [str(GameState.story_flags.keys()), str(GameState.story_seen)])
	parts.append("монеты %d, золото %d, hp %.0f, бодрость %.0f, голод %.0f, глубина %d, дом: %s/%s" % [
		GameState.coins, GameState.get_item_count("gold"), GameState.hp, GameState.stamina,
		GameState.hunger, GameState.max_depth_reached, GameState.house_is_indoors, GameState.house_room])
	if player != null and world != null:
		var cx: int = player.cell_x()
		var cy: int = player.cell_y()
		for y in range(cy - 3, cy + 4):
			var row := ""
			for x in range(cx - 8, cx + 9):
				row += "@" if (x == cx and y == cy) else _tile_char(world.get_tile(x, y))
			parts.append("  %3d %s" % [y, row])
	return "\n".join(parts)


static func _tile_char(t: int) -> String:
	match t:
		TileTypes.Type.EMPTY: return "."
		TileTypes.Type.DIRT: return "d"
		TileTypes.Type.STONE: return "s"
		TileTypes.Type.FOUNDATION: return "F"
		TileTypes.Type.STAIRCASE: return "/"
		TileTypes.Type.REINFORCED: return "R"
		TileTypes.Type.GOLD_ORE: return "G"
		_: return "o"


# ---------------------------------------------------------------------------
# Навык «ходить»: клавиши A/D, прыжок через ступени
# ---------------------------------------------------------------------------

## Идёт к центру по x. Упёрся — жмёт ещё и «вверх» (бег с прыжком), так же, как
## человек берёт ступеньки лестницы.
func _walk_to_x(tx: float, label: String, budget: float = 40.0, tol: float = 0.12) -> bool:
	if _dead:
		return false
	var t0 := _sim
	var last_x: float = player.x
	var last_move := _sim
	while _sim - t0 < budget:
		var dx: float = tx - player.x
		if absf(dx) <= tol:
			bot.release_all()
			return true
		var keys: Array = [KEY_D if dx > 0.0 else KEY_A]
		if absf(player.x - last_x) > 0.02:
			last_x = player.x
			last_move = _sim
		elif _sim - last_move > 0.25 and player.on_ground and player.digging == null:
			keys.append(KEY_W)
		bot.hold(keys)
		await _step()
	bot.release_all()
	check("не застряли: " + label, false, "до x=%.1f за %.0f с\n%s" % [tx, budget, _dump()])
	_dead = true
	return false


# ---------------------------------------------------------------------------
# Сценарий
# ---------------------------------------------------------------------------

func _run() -> void:
	print("=== test_bot_onboarding: сид %d, ускорение ×%.1f ===" % [_seed, _scale])
	if OS.get_cmdline_user_args().has("--inject-error"):
		push_error("bot selftest: этой строки родитель обязан испугаться")  # проверка самого сторожа
	_wall0 = Time.get_ticks_msec()
	_clean_slate()
	Engine.time_scale = _scale

	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames_n(6)
	player = main.player
	world = main.world
	hud = main.hud
	director = main.find_child("StoryDirector", true, false)
	house = HouseSystem.instance
	check("игра поднялась: герой, мир, интерфейс, сюжет, дом на месте",
		player != null and world != null and hud != null and director != null and house != null)
	check("изоляция: пользовательский каталог не общий",
		OS.get_environment("RASKOPKI_BOT_CHILD") != "1" or OS.get_environment("XDG_DATA_HOME") in OS.get_user_data_dir())
	if director == null or player == null:
		return _finish()
	player.dig_refused_by_story.connect(func(reason: String): _refusals.append(reason))
	player.dig_finished.connect(func(x: int, y: int, t: int, _m: String, _l: bool, _c: int): _digs.append([x, y, t]))

	await _phase_intro()
	await _phase_manual_digs()
	await _phase_autodig()
	await _phase_shovel_limits()
	await _phase_workshop()
	await _phase_gold()
	await _phase_foundation_and_death()
	await _phase_sell_and_food()
	if _soak_minutes > 0.0:
		await _phase_soak(_soak_minutes)
	_finish()


func _clean_slate() -> void:
	SaveSystem.delete_save()
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	GameState.reset_progress()
	GameState.world_seed = _seed


func _finish() -> void:
	bot.release_all()
	Engine.time_scale = 1.0
	var wall := (Time.get_ticks_msec() - _wall0) / 1000.0
	print("--- хронология (игровые секунды на шаг) ---")
	for row in _timeline:
		print("  %7.1f  %s" % [row[1], row[0]])
	print("кадров %d, игровых секунд %.0f, настенных %.1f" % [_frames, _sim, wall])
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	_quit_quietly(0 if failures == 0 and not _dead else 1)


## Выход сразу после звука (награда задания дня за «поел») оставлял проигрывания
## в аудиосервере: под нагрузкой поток микшера не успевал их убрать, и в логе
## появлялось «resources still in use at exit». Глушим и даём потоку четверть секунды.
func _quit_quietly(code: int) -> void:
	for p in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		(p as AudioStreamPlayer).stop()
	await get_tree().create_timer(0.25, true, false, true).timeout
	get_tree().quit(code)


func _phase_intro() -> void:
	check("новая игра: интро деда встало в очередь и играет",
		director.cutscene.is_playing and director.cutscene.scene_id == "intro_grandpa")
	check("до автокопки огород левее лестницы заперт", world.is_pre_autodig_locked_cell(16, 2))
	check("до автокопки огород правее лестницы копается", not world.is_pre_autodig_locked_cell(20, 2))
	await _until(func(): return StoryState.has_flag("intro_seen") and not director.cutscene.is_playing,
		900.0, "интро деда и внука доиграны тапами")
	if _dead:
		return
	check("управление вернулось игроку", not player.frozen and hud.visible)
	check("катсцены показали текст без «сырых» ключей перевода", _lines_look_translated(),
		str(_untranslated()))


func _untranslated() -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("^[a-z0-9_]+\\.[a-z0-9_.]+$")
	for t in _lines_seen.keys():
		if re.search(String(t)) != null:
			out.append(t)
	return out


func _lines_look_translated() -> bool:
	return _lines_seen.size() > 10 and _untranslated().is_empty()


func _phase_manual_digs() -> void:
	# Копать можно только правее лестницы (x >= 19): идём туда и жмём «вниз».
	if not await _walk_to_x(21.5, "дойти до места первой копки"):
		return
	_digs.clear()
	bot.hold([KEY_S])
	await _until(func(): return _digs.size() >= 3, 90.0, "три ручные копки лопатой")
	bot.release_all()


func _autodig_finished() -> bool:
	return StoryState.is_seen("autodig_done") and not director.cutscene.is_playing \
		and not director.auto_dig.running


func _phase_autodig() -> void:
	if _dead:
		return
	await _until(func(): return StoryState.is_seen("autodig_start"), 30.0, "автокопка запущена после трёх копок")
	await _until(_autodig_finished, 240.0, "автокопка и сцены клада доиграны")
	if _dead:
		return
	check("никчёмный клад: 50 монет, 5 премиума", GameState.coins == 50 and GameState.dollars == 5,
		"монеты %d, доллары %d" % [GameState.coins, GameState.dollars])
	check("гейт огорода снят", not world.is_pre_autodig_locked_cell(16, 2))


## Лопата перед золотом и фундаментом: слова вместо стана (ГДД раздел 9).
func _phase_shovel_limits() -> void:
	if _dead:
		return
	var gold: Array = world.scripted_loot_cells()
	check("сценарного золота ровно пять", gold.size() == 5)
	if gold.size() != 5:
		return
	var row: int = gold[0].y
	await _until(func(): return player.on_ground and player.cell_y() == row, 15.0, "после автокопки герой стоит на четвёртом уровне")
	if _dead:
		return
	# Подходим к самому левому самородку слева и бьём лопатой.
	var left: Vector2i = gold[0]
	for g: Vector2i in gold:
		if g.x < left.x:
			left = g
	_refusals.clear()
	if not await _walk_to_x(float(left.x) - 0.5, "подойти к золоту слева"):
		return
	bot.hold([KEY_D])
	await _until(func(): return _refusals.has("gold_needs_pickaxe"), 8.0, "лопата о золото: объяснение вместо стана")
	bot.release_all()
	check("стана от золота нет", player.stun_until_msec <= Time.get_ticks_msec())

	# Фундамент: под ногами, строго вниз.
	_refusals.clear()
	bot.hold([KEY_S])
	await _until(func(): return _refusals.has("foundation_needs_pickaxe"), 8.0, "лопата о фундамент: «нужна кирка»")
	bot.release_all()




# ---------------------------------------------------------------------------
# Дом: настоящая ходьба клавишами A/D и нажатие кнопок над героем
# ---------------------------------------------------------------------------

func _view() -> Node:
	return house._view


## Нажимает кнопку действия в текущей комнате так, как это делает игрок: идёт
## клавишами к точке, ждёт, пока над героем загорится кнопка, жмёт её.
func _house_press(action: String, label: String) -> bool:
	if _dead:
		return false
	var view := _view()
	var pts: Dictionary = HouseRoomsConfig.points(String(view.room_id()))
	var px := -1.0
	var radius := 0.05
	for id in pts.keys():
		for b in (pts[id].get("buttons", []) as Array):
			if String(b.get("action", "")) == action:
				px = float(pts[id].get("x", 0.5))
				radius = float(pts[id].get("radius", 0.08))
	if px < 0.0:
		check("в комнате %s есть действие %s" % [view.room_id(), action], false)
		_dead = true
		return false
	var t0 := _sim
	while absf(float(view.hero_x_fraction()) - px) > radius * 0.5 and _sim - t0 < 20.0:
		bot.hold([KEY_D if px > float(view.hero_x_fraction()) else KEY_A])
		await _step()
	bot.release_all()
	await _frames_n(2)
	for btn in view._hotspot_buttons:
		if String(btn.get_meta("action", "")) == action:
			btn.pressed.emit()
			await _frames_n(2)
			_timeline.append([label, _sim - t0])
			check(label, true)
			return true
	check("не застряли: " + label, false, "кнопки над героем: %s, вид виден=%s заперт=%s (внешний=%s сон=%s форс='%s') x=%.2f, HUD виден=%s\n%s" % [
		str(view.active_hotspots()), view.visible, view._is_locked(), view._locked, view._sleeping,
		view._forced_mode, view.hero_x_fraction(), hud.visible, _dump()])
	_dead = true
	return false


## Домой: вылезти по лестнице, зайти, взять кирку на стене мастерской, выйти.
func _phase_workshop() -> void:
	if _dead:
		return
	var door := HouseConfig.door_cell()
	if not await _walk_to_x(float(door.x) + 0.5, "вылезти по лестнице и дойти до двери", 90.0):
		return
	await _until(func(): return house.near_door() and house._outdoor_button.visible, 5.0, "у входной двери появляется «Зайти»")
	if _dead:
		return
	house._outdoor_button.pressed.emit()
	await _frames_n(3)
	check("герой в доме, интерфейс шахты спрятан, герой заморожен",
		GameState.house_is_indoors and not hud.visible and player.frozen and _view().room_id() == "hall")
	if not await _house_press("goto:workshop", "салон → мастерская"):
		return
	check("в мастерской пока нет кирки в руках", GameState.current_tool == "shovel")
	if not await _house_press("take_pickaxe", "взять кирку со стены"):
		return
	check("кирка выдана и надета", GameState.current_tool == "rusty_pickaxe" and GameState.owns_tool("rusty_pickaxe"))
	check("мастерская засчитана", StoryState.is_seen("workshop"))
	await _frames_n(3)
	check("задание — собрать золото (5)", director._objective.contains("5") and director._objective.contains("золото"),
		"«%s»" % director._objective)
	check("пять самородков подсвечены в мире", director._quest_cells.size() == 5)
	if not await _house_press("goto:hall", "мастерская → салон"):
		return
	if not await _house_press("exit_door", "выйти на улицу"):
		return
	check("снова на улице: герой свободен, интерфейс виден",
		not GameState.house_is_indoors and hud.visible and not player.frozen)


## Золото киркой: идём по четвёртому уровню слева направо, упёршись — копаем.
func _phase_gold() -> void:
	if _dead:
		return
	var gold: Array = world.scripted_loot_cells()
	var first_x := 99
	for g: Vector2i in gold:
		first_x = mini(first_x, g.x)
	# Вниз по лестнице: идём вправо, герой сам спускается в расчищенный огород.
	if not await _walk_to_x(float(first_x) - 0.5, "дойти до первого самородка", 60.0):
		return
	await _until(func(): return player.on_ground and player.cell_y() == gold[0].y, 10.0, "герой на уровне золота")
	if _dead:
		return
	bot.hold([KEY_D])
	await _until(func(): return StoryState.has_flag("gold_taken"), 90.0, "пять самородков выкопаны киркой")
	bot.release_all()
	if _dead:
		return
	check("золото в рюкзаке", GameState.get_item_count("gold") == 5, "золота: %d" % GameState.get_item_count("gold"))
	await _frames_n(3)
	check("задание — пробить фундамент", director._objective.contains("фундамент"), "«%s»" % director._objective)


## Фундамент: стоим на месте и жмём «вниз» киркой. Пробитие зовёт сцену смерти.
func _phase_foundation_and_death() -> void:
	if _dead:
		return
	var foundation_y: int = world.foundation_y()
	# Встаём туда, где под ногами фундамент (не на яму после автокопки).
	bot.hold([KEY_S])
	await _until(func(): return StoryState.has_flag("foundation_broken"), 60.0, "фундамент пробит киркой")
	bot.release_all()
	if _dead:
		return
	check("сцена смерти встала в очередь или уже идёт",
		GameState.story_queue.has("death") or director.cutscene.scene_id == "death" or StoryState.is_seen("death"))
	await _until(func(): return StoryState.is_seen("death"), 240.0, "сцена смерти доиграна")
	if _dead:
		return
	check("инвентарь пережил смерть (единственный раз): пять золота", GameState.get_item_count("gold") == 5,
		"золота: %d" % GameState.get_item_count("gold"))
	check("полоски выживания введены", StoryState.has_flag("bars_introduced") and hud.are_gauges_visible())
	check("герой жив", GameState.is_alive)
	check("респавн в доме", GameState.house_is_indoors)
	await _until(func(): return StoryState.is_seen("robert") and not director.cutscene.is_playing, 400.0,
		"после смерти доиграны ранец и Роберт")
	if _dead:
		return
	check("Роберт построил тоннель", GameState.house_hatch_built and StoryState.has_flag("hatch_built"))
	check("инвентарь цел после всех сцен", GameState.get_item_count("gold") == 5)
	# Сцены кончаются внутри дома: тот, кто листает комнату клавишами A/D, не должен
	# одновременно водить живого героя по огороду под домом.
	check("после сцен герой остаётся в доме: заморожен, интерфейс шахты спрятан",
		GameState.house_is_indoors and player.frozen and not hud.visible,
		"в доме=%s заморожен=%s HUD=%s" % [GameState.house_is_indoors, player.frozen, hud.visible])


## «Продай золото» → «закажи еду».
func _phase_sell_and_food() -> void:
	if _dead:
		return
	await _frames_n(3)
	check("задание — продать золото", director._objective.contains("продай"), "«%s»" % director._objective)
	check("в доме можно торговать", ShopService.is_at_workshop())
	var before := GameState.coins
	var r := ShopService.sell_all()
	check("золото продано", bool(r["ok"]) and GameState.get_item_count("gold") == 0 and GameState.coins > before,
		"монеты %d → %d" % [before, GameState.coins])
	await _frames_n(3)
	check("продажа закрыла задание", StoryState.has_flag("gold_sold"))
	check("задание — заказать еду", director._objective.contains("еду"), "«%s»" % director._objective)

	# Еда: в прихожей «Заказать» открывает магазин.
	if _view().room_id() != "hall":
		if _view().room_id() == "workshop":
			if not await _house_press("goto:hall", "в салон за едой"):
				return
	if not await _house_press("open_shop", "«Заказать» у входной двери"):
		return
	check("магазин открылся", ShopUI.instance != null and ShopUI.instance.is_open())
	ShopUI.instance.close()
	var menu: Array = HouseConfig.delivery_menu()
	check("в меню доставки есть еда", not menu.is_empty())
	var food_id := ""
	for item in menu:
		if HouseConfig.is_portable(String(item.get("id", ""))):
			food_id = String(item.get("id", ""))
			break
	var order := HouseSystem.order_food(food_id)
	check("заказ принят", bool(order["ok"]), String(order.get("message", "")))
	await _until(func(): return StoryState.has_flag("food_ordered"), HouseConfig.delivery_seconds() * 3.0 + 5.0,
		"курьер привёз еду: обучение закрыто")
	if _dead:
		return
	check("заданий больше нет", director._objective.is_empty(), "«%s»" % director._objective)
	check("«Забрать» у двери доступно", HouseFood.food_at_door_count() > 0)


# ---------------------------------------------------------------------------
# «Первые полчаса»: шахта, подъём на ранце, продажа, покупки, еда, сон
# ---------------------------------------------------------------------------

## Бот ведёт себя как аккуратный игрок: копает вниз, подбирает руду, видимую вплотную (радиус
## обзора 1), поднимается при 80% рюкзака, дома продаёт, покупает следующую ступень, ест и спит.
## Состояние решается заново каждый круг по миру, а не по сценарию: сцена сна у героя посреди
## шахты (бодрость ≤ 8%) телепортирует его домой, и бот обязан это пережить.
func _phase_soak(minutes: float) -> void:
	if _dead:
		return
	var end := _sim + minutes * 60.0
	var start_sim := _sim
	var coins0 := GameState.coins
	var circles := 0
	print("--- «первые %.0f минут» после онбординга ---" % minutes)
	# Все крупные приходы монет — с глубиной и временем: так видно, откуда в «чистой» копке деньги.
	var last_coins := [GameState.coins]
	GameState.coins_changed.connect(func(c: int):
		if c - int(last_coins[0]) >= 100:
			_soak_log.append("монеты +%d на %.0f с, глубина %d" % [c - int(last_coins[0]), _sim, player.cell_y()])
		last_coins[0] = c)
	var branches: Array = []
	var last_circle_sim := _sim
	var stalled := 0
	while _sim < end and not _dead and circles < 400:
		if director.cutscene.is_playing or director.auto_dig.running:
			await _step()
			continue
		circles += 1
		var branch := "дом" if GameState.house_is_indoors else ("устье" if player.cell_y() <= 1 else ("подъём" if _soak_should_go_up() else "копка"))
		branches.append(branch)
		if branches.size() > 12:
			branches.pop_front()
		# Круг, который не двинул игровое время, — холостой: так бот крутился бы вхолостую, а не застревал.
		stalled = stalled + 1 if _sim - last_circle_sim < 0.01 else 0
		last_circle_sim = _sim
		if stalled > 20:
			check("не застряли: бот крутится вхолостую", false, "последние ветки: %s\n%s" % [str(branches), _dump()])
			_dead = true
			break
		match branch:
			"дом": await _soak_home(end)
			"устье": await _soak_to_tunnel_and_descend()
			"подъём": await _soak_ascend()
			_: await _soak_mine(end)
	bot.release_all()
	if _dead:
		return
	check("бот прожил заданное время без застреваний (%d кругов)" % circles, circles < 400)
	check("всплывающие окна не оставили героя замороженным", not player.frozen or GameState.house_is_indoors)
	check("за это время он что-то заработал", GameState.coins > coins0 or GameState.max_depth_reached > 10,
		"монеты %d → %d, глубина %d" % [coins0, GameState.coins, GameState.max_depth_reached])
	print("итог: монеты %d, глубина %d, ступени: инструмент %s, ранец '%s', уровень %d, клеток выкопано %d, подъёмов %d" % [
		GameState.coins, GameState.max_depth_reached, GameState.current_tool, GameState.current_gear,
		GameState.level, _digs.size(), _soak_log.count("подъём")])
	for e in _soak_log:
		if String(e).begins_with("куплено") or String(e).begins_with("монеты") or String(e).begins_with("окно"):
			print("  ", e)
	_timeline.append(["первые %.0f минут: игровых секунд" % minutes, _sim - start_sim])


func _soak_should_go_up() -> bool:
	if _soak_force_up:
		return true
	if GameState.get_total_weight() >= GameState.get_max_carry_kg() * 0.8:
		return true
	# голодный бот поднимается поесть, пока HP не просело
	return GameState.hunger < 25.0 or GameState.stamina < 12.0


## Дом: продать, купить, поесть, поспать, выйти.
func _soak_home(end: float) -> void:
	_soak_force_up = false
	# Игрок сразу после смерти/Роберта может стоять в мастерской: идём в салон.
	var room := String(_view().room_id())
	if room == "workshop":
		if not await _house_press("goto:hall", "из мастерской в салон"):
			return
	elif room == "bedroom":
		if not await _house_press("goto:hall", "из спальни в салон"):
			return

	var sold := ShopService.sell_all()
	if bool(sold["ok"]):
		_soak_log.append("продано на %d" % int(sold["coins"]))
	# Ступени по порядку цены: первый ранец, кирки, улучшенный ранец.
	for tool_id in Balance.get_tools_in_line("pickaxe"):
		if not GameState.owns_tool(tool_id) and not Balance.tool_needs_materials(tool_id) \
				and Balance.get_tool_cost_coins(tool_id) > 0 and GameState.coins >= Balance.get_tool_cost_coins(tool_id):
			if bool(ShopService.buy_tool(tool_id)["ok"]):
				_soak_log.append("куплено %s на %.0f с" % [tool_id, _sim])
				check("покупка %s прошла и кирка надета" % tool_id, GameState.current_tool == tool_id)
	for gear_id in Balance.get_gear_ids():
		if not GameState.has_gear(gear_id) and GameState.coins >= Balance.get_gear_cost_coins(gear_id) \
				and Balance.get_gear_fly_multiplier(gear_id) > Balance.get_gear_fly_multiplier(GameState.current_gear):
			if bool(ShopService.buy_gear(gear_id)["ok"]):
				_soak_log.append("куплено %s на %.0f с" % [gear_id, _sim])
				check("покупка %s прошла и она надета" % gear_id, GameState.current_gear == gear_id)
	if not player.has_backpack() and GameState.coins >= Balance.get_gear_cost_coins("backpack"):
		check("ранец куплен", bool(ShopService.buy_gear("backpack")["ok"]))

	# Еда: порция из рюкзака, иначе заказ к двери и «Забрать».
	if GameState.hunger < 60.0 or GameState.stamina < 40.0:
		await _soak_eat()
	if GameState.stamina < 35.0:
		await _soak_sleep()
	if _dead:
		return
	if String(_view().room_id()) != "hall":
		if not await _house_press("goto:hall", "в салон перед выходом"):
			return
	if not await _house_press("exit_door", "выйти на улицу"):
		return
	await _frames_n(2)


func _soak_eat() -> void:
	var food := HouseFood.best_food_for_now()
	if food.is_empty():
		var menu: Array = HouseConfig.delivery_menu()
		var pick := ""
		for item in menu:
			if HouseConfig.is_portable(String(item.get("id", ""))):
				pick = String(item.get("id", ""))
				break
		if pick.is_empty():
			return
		var order := HouseSystem.order_food(pick)
		if not bool(order["ok"]):
			return
		var t0 := _sim
		while HouseFood.food_at_door_count() == 0 and _sim - t0 < HouseConfig.delivery_seconds() * 3.0 + 5.0:
			await _step()
		if String(_view().room_id()) == "hall" and not await _house_press("take_delivery", "забрать еду у двери"):
			return
		food = HouseFood.best_food_for_now()
	if not food.is_empty():
		var before := GameState.hunger
		var eaten := HouseFood.eat(food)
		check("поел: голод вырос", bool(eaten["ok"]) and GameState.hunger >= before)
		_soak_log.append("поел %s" % food)


func _soak_sleep() -> void:
	if not await _house_press("goto:bedroom", "в спальню"):
		return
	var before := GameState.stamina
	if not await _house_press("sleep", "лечь спать"):
		return
	var t0 := _sim
	while String(_view().room_id()) == "bedroom" and _view().is_sleeping() and _sim - t0 < 40.0:
		await _step()
	await _frames_n(3)
	check("после сна бодрости больше", GameState.stamina > before, "%.0f → %.0f" % [before, GameState.stamina])
	_soak_log.append("поспал")


func _soak_to_tunnel_and_descend() -> void:
	var mouth := world.tunnel_mouth()
	if mouth.x < 0:
		check("тоннель Роберта построен (вход в шахту)", false)
		_dead = true
		return
	# Колодец в одну клетку: тело героя 0.76, и он падает, лишь когда левый край съехал с
	# бетонной кромки (x ≥ 17.38). Поэтому, как человек, подходим и ДЕРЖИМ вправо, пока не провалимся.
	if not await _walk_to_x(float(mouth.x) - 0.6, "дойти до устья тоннеля", 60.0, 0.3):
		return
	bot.hold([KEY_D])
	await _until(func(): return player.y > 1.6, 8.0, "герой падает в устье тоннеля")
	bot.release_all()
	# Дальше — ствол, прорытый прошлым заходом: падение с него убивает (урон ~ высота^2.16), поэтому
	# тормозим тягой ранца, как игрок, который держит «вверх», пока скорость падения не упала.
	var hp_before: float = GameState.hp
	var t0 := _sim
	while _sim - t0 < 90.0 and not _dead:
		if player.on_ground and player.cell_y() >= 5:
			break
		bot.hold([KEY_W] if (player.vy > 6.0 and player.has_backpack()) else [])
		await _step()
	bot.release_all()
	# Дно ствола может оказаться и на фундаменте: обвал (раз в ~90 с, ГДД §8) пересыпает прорытое ниже.
	check("спуск по стволу до дна без смерти и без потери здоровья", player.on_ground and player.cell_y() >= 5
		and GameState.is_alive and GameState.hp >= hp_before - 15.0,
		"глубина %d, hp %.0f → %.0f, жив=%s\n%s" % [player.cell_y(), hp_before, GameState.hp, GameState.is_alive, _dump()])


## Копаем вниз; руда вплотную слева/справа — берём «через плечо».
func _soak_mine(end: float) -> void:
	var t0 := _sim
	var last_progress := _sim
	var last_depth: int = player.cell_y()
	var last_weight: float = GameState.get_total_weight()
	var last_digs: int = _digs.size()
	while _sim < end and not _dead:
		if _sim - t0 >= TRIP_SECONDS:
			_soak_force_up = true
		if director.cutscene.is_playing or GameState.house_is_indoors or player.cell_y() <= 1 or _soak_should_go_up():
			bot.release_all()
			return
		if not player.on_ground:
			bot.release_all()
		else:
			bot.hold(_mine_keys())
		await _step()
		if player.cell_y() != last_depth or GameState.get_total_weight() != last_weight or _digs.size() != last_digs:
			last_progress = _sim
			last_depth = player.cell_y()
			last_weight = GameState.get_total_weight()
			last_digs = _digs.size()
		elif _sim - last_progress > 60.0:
			bot.release_all()
			check("не застряли: копка в шахте", false, "60 с без единой выкопанной клетки\n" + _dump())
			_dead = true
			return
	bot.release_all()


func _mine_keys() -> Array:
	var cx: int = player.cell_x()
	var cy: int = player.cell_y()
	for dir in [-1, 1]:
		var x: int = cx + dir
		if x < 0 or x >= WorldGen.WIDTH:
			continue
		var t := world.get_tile(x, cy)
		if TileTypes.is_ore(t) and MineralMap.is_loot(t):
			return [KEY_D if dir > 0 else KEY_A]
	return [KEY_S]


## Вверх по стволу на ранце, на поверхности — в сторону от шахты и к двери.
func _soak_ascend() -> void:
	await _soak_ascend_inner()
	Engine.time_scale = _scale


func _soak_ascend_inner() -> void:
	_soak_log.append("подъём")
	if not player.has_backpack():
		check("у бота есть ранец для подъёма", false)
		_dead = true
		return
	var door_x := float(HouseConfig.door_cell().x) + 0.5
	var t0 := _sim
	var best_y: float = player.y
	var best_t := _sim
	var trace: Array = []
	while _sim - t0 < 180.0 and not _dead:
		# Тяга включается через JUMP_TO_FLY_MS по РЕАЛЬНОМУ времени (Time.get_ticks_msec), а ускоренная
		# игра успевает приземлиться раньше: на ×4-5 герой бесконечно «прыгает» у дна. Пока тяга не
		# включилась, идём в реальном времени, потом снова ускоряемся.
		Engine.time_scale = _scale if player.thrust != "" or player.cell_y() <= 1 else 1.0
		if player.y < best_y - 0.5:
			best_y = player.y
			best_t = _sim
		elif _sim - best_t > 25.0 and player.cell_y() > 1:
			bot.release_all()
			check("не застряли: подъём на ранце (25 с без высоты)", false, "след: %s\nгаз=%s тяга='%s' предмет=%s\n%s" % [
				str(trace), GameState.current_gear, player.thrust, str(GameState.get_total_weight()), _dump()])
			_dead = true
			return
		if int(_sim * 2.0) % 4 == 0 and (trace.is_empty() or absf(float(trace[-1][0]) - _sim) > 1.5):
			trace.append([snappedf(_sim, 0.1), snappedf(player.x, 0.01), snappedf(player.y, 0.01), snappedf(player.vy, 0.1), player.thrust])
			if trace.size() > 8:
				trace.pop_front()
		if GameState.house_is_indoors or director.cutscene.is_playing:
			bot.release_all()
			return
		var keys: Array = []
		if player.cell_y() > 1:
			keys = [KEY_W]
			# уйти из колонки, если вылезли выше устья
		else:
			var dx: float = door_x - player.x
			if absf(dx) <= 0.3 and player.on_ground:
				bot.release_all()
				await _until(func(): return house.near_door() and house._outdoor_button.visible, 5.0, "у двери после подъёма")
				if not _dead:
					house._outdoor_button.pressed.emit()
					await _frames_n(3)
				return
			keys = [KEY_D if dx > 0.0 else KEY_A]
			if player.x > 15.0 and not player.on_ground:
				keys.append(KEY_W)  # не упасть обратно в устье
		bot.hold(keys)
		await _step()
	bot.release_all()
	check("не застряли: подъём на ранце", false, "180 с\n" + _dump())
	_dead = true

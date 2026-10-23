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
	var summary := ""
	for line in text.split("\n"):
		if line.contains("Итог:"):
			summary = line
	print("=== Итог: %d проверок, %d провалов ===" % [1, 0 if ok else 1] if summary.is_empty() else summary.replace("===", "===").strip_edges())
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
	get_tree().quit(0 if failures == 0 and not _dead else 1)


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


func _phase_autodig() -> void:
	if _dead:
		return
	await _until(func(): return StoryState.is_seen("autodig_start"), 30.0, "автокопка запущена после трёх копок")
	await _until(func(): return StoryState.is_seen("autodig_done") and not director.cutscene.is_playing
		and not director.auto_dig.running, 240.0, "автокопка и сцены клада доиграны")
	if _dead:
		return
	check("никчёмный клад: 50 монет, 5 премиума", GameState.coins == 50 and GameState.dollars == 5,
		"монеты %d, доллары %d" % [GameState.coins, GameState.dollars])
	check("гейт огорода снят", not world.is_pre_autodig_locked_cell(16, 2))

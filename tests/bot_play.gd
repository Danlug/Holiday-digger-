extends Node
## bot_play — бот-игрок на живой main.tscn (ветка playtest-bot; отчёт docs/PLAYTEST.md).
##
## Играет как разумный человек: онбординг (катсцены тапами, три копки, мастерская, золото,
## фундамент, смерть, Роберт, продажа, еда), дальше свободная игра — шахта вниз и в стороны,
## подъём на ранце, дом (продажа, покупки у двери плитками витрины, еда, сон, прокачка,
## верстак), сюжетные сцены и могила, всплывающие окна. Герой ведётся настоящими клавишами
## WASD (BotPlayer), кнопки дома — кнопкой над героем, покупки — плиткой витрины и «Купить».
##
## Время. Запуск с --fixed-fps 31: кадр = 1/31 игровой секунды, а кадры идут так быстро, как
## тянет процессор (в headless ×20 к реальному времени). Там, где игра меряет НАСТОЯЩЕЕ время
## (тяга ранца через 300 мс после прыжка, стан 1 с, анти-дребезг тапа), бот честно досыпает
## реальные миллисекунды (OS.delay_msec), а не правит игру.
##
##   godot --headless --fixed-fps 31 --path . res://tests/bot_play.tscn -- \
##       --seed=7 --minutes=90 --char=cautious --out=build/bot/run [--shots] [--short]
##
## Характеры: cautious (осторожный), greedy (жадный), hasty (торопливый) — см. CHARS.
## Итог: <out>/telemetry.json (+ снимки в <out>/shots при --shots под настоящим рендером).
## Обёртка с разбором лога и текстовым итогом: tools/bot_play.sh [сид] [минуты] [характер].
## Код возврата: 0 — без находок P0 (тупик, застревание, падение), 1 — есть.

const Telemetry := preload("res://tests/bot/bot_telemetry.gd")
const Nav := preload("res://tests/bot/bot_nav.gd")
const Stick := preload("res://tests/bot/bot_stick.gd")

const CHARS := {
	# ret_* — когда возвращаться домой; side — на сколько клеток в сторону идти за видимой
	# рудой; branch_every/branch_len — боковые штреки «на разведку»; trip_max — максимум
	# игровых секунд одной ходки; eat_below/sleep_below — пороги дома; skip — жмёт «пропустить».
	"cautious": {"ret_weight": 0.6, "ret_hunger": 45.0, "ret_stamina": 30.0, "ret_hp": 60.0,
		"side": 3, "branch_every": 0, "branch_len": 0, "trip_max": 300.0,
		"eat_below": 75.0, "sleep_below": 55.0, "food_stock": 2, "skip": false, "tap": 0.7,
		"buy": "next", "reserve": 300, "skills": ["hp", "stamina", "hunger", "vision", "strength", "dig_speed", "luck_chance", "luck_multiplier"]},
	"greedy": {"ret_weight": 0.97, "ret_hunger": 18.0, "ret_stamina": 8.0, "ret_hp": 30.0,
		"side": 8, "branch_every": 5, "branch_len": 6, "trip_max": 900.0,
		"eat_below": 45.0, "sleep_below": 30.0, "food_stock": 0, "skip": false, "tap": 0.45,
		"buy": "next", "reserve": 0, "skills": ["strength", "luck_chance", "luck_multiplier", "vision", "dig_speed", "hunger", "stamina", "hp"]},
	"hasty": {"ret_weight": 0.85, "ret_hunger": 25.0, "ret_stamina": 12.0, "ret_hp": 40.0,
		"side": 1, "branch_every": 0, "branch_len": 0, "trip_max": 600.0,
		"eat_below": 50.0, "sleep_below": 22.0, "food_stock": 1, "skip": true, "tap": 0.2,
		"buy": "best", "reserve": 0, "skills": ["dig_speed", "strength", "stamina", "hunger", "hp", "vision", "luck_chance", "luck_multiplier"]},
}

## Стратегии-цели (раунд 4, «ночной прогон»): поверх характера задают, ЧТО бот хочет от игры —
## порядок прокачки, покупок и проектов, радиус охоты за рудой, особое поведение и метрику успеха.
## «Застрял» для цели — метрика не растёт stall_min игровых минут. Ветки навыков, которых нет в
## data/upgrades.json, просто пропускаются; незнакомые (новые) — добавляются в конец списка.
const GOALS := {
	"deep": {"char": "hasty", "skills": ["dig_speed", "greed", "fever", "vision", "strength", "stamina", "hunger", "hp"],
		"buy": "best", "side": 1, "branch_every": 0, "projects": ["hand_drill", "drill_rig"], "suits": true,
		"metric": "max_depth", "stall_min": 45.0},
	"achiever": {"char": "cautious", "skills": ["luck_chance", "luck_multiplier", "vision", "dig_speed", "strength", "hp", "stamina", "hunger", "greed", "fever"],
		"buy": "next", "side": 4, "branch_every": 0, "projects": ["well", "hand_drill"], "quests": true, "die_once": true,
		"metric": "achievements", "stall_min": 60.0},
	"tycoon": {"char": "greedy", "skills": ["luck_chance", "luck_multiplier", "strength", "vision", "dig_speed", "greed", "fever", "stamina", "hunger", "hp"],
		"buy": "next", "side": 6, "branch_every": 6, "projects": ["well", "hand_drill"], "quests": true, "well_upgrade": true,
		"metric": "earned", "stall_min": 30.0},
	"collector": {"char": "greedy", "skills": ["vision", "luck_chance", "luck_multiplier", "strength", "dig_speed", "stamina", "hunger", "hp", "greed", "fever"],
		"buy": "next", "side": 8, "branch_every": 5, "projects": [], "screens": true,
		"metric": "collection", "stall_min": 45.0},
	"fighter": {"char": "cautious", "skills": ["hp", "dig_speed", "stamina", "strength", "greed", "fever", "vision", "hunger"],
		"buy": "best", "side": 2, "branch_every": 0, "projects": ["hand_drill", "drill_rig"], "suits": true, "combat_gear": true,
		"metric": "fight", "stall_min": 60.0, "ret_hp": 45.0},
}

const SHAFT_X := 17
const STUCK_SEC := 120.0        # без прогресса столько игровых секунд — «застрял»
const MODAL_STUCK_SEC := 20.0   # окно не закрылось за столько — находка
const SAMPLE_SEC := 30.0

var T = Telemetry.new()
var nav = Nav.new()
var bot: BotPlayer = BotPlayer.new()
var _input_mode := "keys"         # keys — WASD; stick — экранный джойстик пальцем (tests/bot/bot_stick.gd)
var C: Dictionary = {}
var char_name := "cautious"
var goal_name := ""               # пусто — без стратегии (как раунд 3); deep|achiever|tycoon|collector|fighter
var G: Dictionary = {}
var _char_given := false
var _skip_onb := false
var _start_depth := 0             # FAST-старт сразу на глубине (DEPTH=… в tools/bot_play.sh): полости и стражи с 1500 (раунд 5)
var _cp_sec := 0.0                # сейв-«снимок» каждые N игровых секунд (для снимков рендером утром)
var _next_cp := 0.0
var _flush_sec := 600.0           # телеметрия на диск каждые N игровых секунд (ночной прогон не теряет итог)
var _next_flush := 600.0
var _metric_best := -1.0
var _metric_t := 0.0
var _earned := 0
var _coins_seen := 0
var _coins_frame := 0
var _ach_frame: Array = []   # достижения на прошлом кадре: награда за смерть приходит раньше нашего обработчика
var _no_brake := false             # намеренная смерть (достижение «умри»): не тормозить тягой
var _die_tries := 0
var _death_entry: Dictionary = {}
var _die_lift := false             # эксперимент «смерть вместо подъёма» (--die-lift, раунд 5, death-cost)
var _die_lift_pack := 400          # умирать вместо подъёма, только если рюкзак дешевле стольких монет
var _ascents: Array = []           # [глубина начала подъёма, игровых секунд до поверхности] — для death_lift
var _heal_seen := false            # HP хоть раз выросло от сна/еды/аптечки — лечение в игре есть
var _greed_t := 0.0
var _craft_args := -1
var _prev_cell := Vector2i(-99, -99)
var main: Node2D
var player
var world: WorldGen
var hud: Control
var director: StoryDirector
var house: HouseSystem

var _seed := 20260101
var _minutes := 30.0
var _out := ""
var _shots_on := false
var _short := false
var _resume := false              # продолжить с сейва в XDG_DATA_HOME (tools/bot_play.sh RESUME=…)
var _wall_cap := 1800.0
var _max_depth_stop := 0

var _sim := 0.0
var _frames := 0
var _wall0 := 0
var _end := 0.0
var _stop := false
var _activity := "start"
var _last_us := 0
var _burn_us_frame := 0
var _last_tap := -10.0
var _last_tap_real := 0
var _last_sample := -100.0
var _scene_cur := ""
var _scene_t0 := 0.0
var _skip_tries := 0
var _digs := 0
var _refusals: Array = []
var _lava_refused := 0
var _dig_blocked := 0
var _shaft_x := SHAFT_X

var _last_hp := 100.0
var _last_fall_sim := -100.0
var _last_fall_dmg := 0.0
var _died_pending := false
var _pack_before_death: Dictionary = {}
var _progress_sig := ""
var _progress_t := 0.0
var _stuck_level := 0
var _modal_since: Dictionary = {}
var _owned_since: Dictionary = {}   # предмет -> sim покупки (для «бессмысленных трат»)
var _coins_peak_idle := 0.0
var _home_visits := 0
var _ui_buy_fail := 0
var _shot_count := 0
var _next_periodic_shot := 300.0
var _rng := RandomNumberGenerator.new()
var _trace := 0.0
var _death_card: Node = null
var _from_house := false
var _frame_events: Array = []
var _mech: Object = null
var _session_min := 0.0           # каждые N игровых минут — «закрыл игру, вернулся завтра»
var _next_session := 0.0
var _sessions := 0
var _input_lost_t := 0.0
var _resume_us := 0
var _next_trace := 0.0


# ---------------------------------------------------------------------------
# Запуск
# ---------------------------------------------------------------------------

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			_seed = int(a.substr(7))
		elif a.begins_with("--minutes="):
			_minutes = float(a.substr(10))
		elif a.begins_with("--char="):
			char_name = a.substr(7)
			_char_given = true
		elif a.begins_with("--goal="):
			goal_name = a.substr(7)
		elif a == "--skip-onboarding":
			_skip_onb = true
		elif a.begins_with("--depth="):
			_start_depth = int(a.substr(8))
		elif a.begins_with("--checkpoint="):
			_cp_sec = float(a.substr(13)) * 60.0
		elif a.begins_with("--flush="):
			_flush_sec = float(a.substr(8)) * 60.0
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--shots":
			_shots_on = true
		elif a == "--short":
			_short = true
		elif a.begins_with("--input="):
			_input_mode = a.substr(8)
		elif a == "--resume":
			_resume = true
		elif a.begins_with("--wall="):
			_wall_cap = float(a.substr(7))
		elif a.begins_with("--session="):
			_session_min = float(a.substr(10))
		elif a.begins_with("--trace="):
			_trace = float(a.substr(8))
		elif a.begins_with("--max-depth="):
			_max_depth_stop = int(a.substr(12))
		elif a == "--die-lift":
			_die_lift = true
		elif a.begins_with("--die-lift-pack="):
			_die_lift = true
			_die_lift_pack = int(a.substr(16))
	if goal_name != "" and not GOALS.has(goal_name):
		push_warning("bot: неизвестная стратегия %s — без стратегии" % goal_name)
		goal_name = ""
	if goal_name != "":
		G = (GOALS[goal_name] as Dictionary).duplicate(true)
		if not _char_given:
			char_name = String(G["char"])
	if not CHARS.has(char_name):
		push_warning("bot: неизвестный характер %s — беру cautious" % char_name)
		char_name = "cautious"
	C = (CHARS[char_name] as Dictionary).duplicate(true)
	for k in ["skills", "buy", "side", "branch_every", "ret_hp"]:
		if G.has(k):
			C[k] = G[k]
	if G.has("skills"):
		C["skills"] = _skill_order(G["skills"])
	if _short:
		C["trip_max"] = 150.0   # короткий прогон обязан успеть круг «шахта → дом → шахта»
		if goal_name != "":
			C["trip_max"] = 35.0   # тест стратегий: за ~1,3 игровой минуты — домой, прокачка и покупки по цели
	if _out.is_empty():
		_out = OS.get_user_data_dir().path_join("bot_run")
	DirAccess.make_dir_recursive_absolute(_out)
	if _shots_on:
		DirAccess.make_dir_recursive_absolute(_out.path_join("shots"))
		if _resume:
			_next_periodic_shot = 20.0   # снимок с копии сейва (ночной прогон): кадр состояния сразу
	_run()


func _run() -> void:
	print("=== bot_play: сид %d, характер %s, %.0f игровых минут, fixed-fps %s ===" % [
		_seed, char_name, _minutes, str(Engine.get_frames_per_second())])
	_wall0 = Time.get_ticks_msec()
	_rng.seed = _seed
	if not _resume:
		_clean_slate()
	if _skip_onb and not _resume:
		# состояние «сразу после онбординга» — до main.tscn: режиссёр читает сюжет при старте
		for id in ["intro_grandpa", "intro_boy", "autodig_start", "dud_treasure", "autodig_done", "workshop", "death", "backpack", "robert"]:
			StoryState.mark_seen(id)
		for f in ["intro_seen", "dud_treasure_found", "autodig_done", "workshop_seen", "gold_taken", "foundation_broken",
				"bars_introduced", "death_seen", "backpack_owned", "robert_seen", "hatch_built", "gold_sold", "food_ordered"]:
			StoryState.set_flag(f)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames_n(4)
	# Сид глобального ГСЧ (обвалы, спавн) — после randomize() в main._ready: прогон повторяем.
	seed(_seed)
	player = main.player
	world = main.world
	hud = main.hud
	director = main.find_child("StoryDirector", true, false)
	house = HouseSystem.instance
	if player == null or world == null or director == null or house == null:
		T.finding("P0", "boot", "игра не поднялась: нет героя/мира/сюжета/дома", _sim)
		_finish()
		return
	nav.world = world
	nav.dig_cost = _nav_dig_cost
	if _input_mode == "stick":
		Settings.control_mode = "stick"
		bot = Stick.new(hud)
	_end = _minutes * 60.0
	_next_session = _session_min * 60.0 if _session_min > 0.0 else INF
	T.meta = {"seed": _seed, "character": char_name, "goal": goal_name, "input": _input_mode, "minutes_target": _minutes, "short": _short,
		"build": _build_label(), "fixed_fps_hint": "--fixed-fps 31", "started_utc": Time.get_datetime_string_from_system(true)}
	_connect_signals()
	_last_us = Time.get_ticks_usec()
	_resume_us = _last_us
	_progress_t = 0.0

	_coins_seen = GameState.coins
	_next_flush = _flush_sec
	_next_cp = _cp_sec if _cp_sec > 0.0 else INF
	if _resume and StoryState.is_seen("robert"):
		T.mark("resumed", _sim)
		T.meta["resumed_from"] = {"max_depth": GameState.max_depth_reached, "coins": GameState.coins, "tool": GameState.current_tool}
	elif _skip_onb:
		_fast_start()
		if _start_depth > 0:
			_deep_start(_start_depth)
		await _frames_n(3)
		T.mark("onboarding_done", _sim)
	else:
		await _onboarding()
	if not _stop:
		await _free_play()
	_finish()


func _build_label() -> String:
	var f := FileAccess.open("res://data/build_info.json", FileAccess.READ)
	if f == null:
		return ""
	var d = JSON.parse_string(f.get_as_text())
	return String(d.get("build", "")) if d is Dictionary else ""


func _clean_slate() -> void:
	SaveSystem.delete_save()
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	GameState.reset_progress()
	GameState.world_seed = _seed


func _connect_player() -> void:
	player.dig_finished.connect(_on_dig_finished)
	player.dig_refused_by_story.connect(func(r: String) -> void: _refusals.append(r))
	player.dig_blocked.connect(func(_t: int) -> void: _dig_blocked += 1)
	if player.has_signal("dig_refused_by_lava"):
		player.dig_refused_by_lava.connect(func(_c: float) -> void: _lava_refused += 1)
	player.fell.connect(_on_fell)


func _connect_signals() -> void:
	_connect_player()
	GameState.max_depth_changed.connect(_on_max_depth)
	GameState.died.connect(_on_died)
	GameState.respawned.connect(_on_respawned)
	GameState.leveled_up.connect(func(lv: int, _p: int) -> void: T.mark("level_%d" % lv, _sim))
	GameState.artifact_collected.connect(func(id: String) -> void:
		T.event(_sim, "artifact", id)
		T.mark("first_artifact", _sim))
	GameState.tool_changed.connect(func(id: String) -> void: T.mark("tool:" + id, _sim))
	GameState.gear_changed.connect(func(id: String) -> void:
		if id != "":
			T.mark("gear:" + id, _sim))
	GameState.game_event.connect(_on_game_event)
	GameState.inventory_changed.connect(_on_inventory)


func _finish() -> void:
	bot.release_all()
	var wall := (Time.get_ticks_msec() - _wall0) / 1000.0
	if GameState.is_alive:
		SaveSystem.save_game()   # с этого сейва можно продолжить: tools/bot_play.sh RESUME=…
	_final_checks()
	T.meta["sim_seconds"] = snappedf(_sim, 0.1)
	T.meta["wall_seconds"] = snappedf(wall, 0.1)
	T.meta["frames"] = _frames
	T.meta["speedup"] = snappedf(_sim / maxf(wall, 0.001), 0.1)
	T.meta["game_days"] = snappedf(_sim / 3600.0 * Balance.get_game_hours_per_real_hour() / 24.0, 0.01)
	T.meta["end_state"] = _state_dict()
	T.meta["home_visits"] = _home_visits
	T.meta["partial"] = false
	if goal_name != "":
		T.meta["goal_metric"] = snappedf(_goal_metric(), 0.1)
		T.meta["achievements_done"] = int(_ach_done())
		T.meta["coins_earned_total"] = _earned
		T.meta["monsters"] = MetaState.counter("monsters")
	var path := _out.path_join("telemetry.json")
	T.write_json(path, _sim)
	var p0 := 0
	for f in T.findings:
		if String(f["sev"]) == "P0":
			p0 += 1
	print("--- итог бота ---")
	print("игровых минут %.1f, настенных секунд %.0f (×%.1f), кадров %d" % [_sim / 60.0, wall, _sim / maxf(wall, 0.001), _frames])
	print("глубина %d, монеты %d, уровень %d, кирка %s, ранец %s, смертей %d, ходок %d, находок %d (P0: %d)" % [
		GameState.max_depth_reached, GameState.coins, GameState.level, GameState.current_tool,
		GameState.current_gear, T.deaths.size(), T.trips.size(), T.findings.size(), p0])
	for f in T.findings:
		print("  [%s] %s: %s (×%d, t=%.0f)" % [f["sev"], f["kind"], f["text"], int(f["count"]), float(f["t"])])
	print("телеметрия: ", ProjectSettings.globalize_path(path))
	print("=== Итог: бот %s, P0 %d ===" % ["OK" if p0 == 0 else "FAIL", p0])
	get_tree().quit(0 if p0 == 0 else 1)


# ---------------------------------------------------------------------------
# Кадр: время, катсцены, окна, детекторы
# ---------------------------------------------------------------------------

func _step() -> void:
	# Всё, что бот делал с прошлого кадра (план, детекторы, досыпание реального времени), —
	# не время кадра игры: вычитаем. Остаток — кадр движка и скриптов игры (и соседи по CPU).
	var bot_us := Time.get_ticks_usec() - _resume_us
	await get_tree().process_frame
	var now_us := Time.get_ticks_usec()
	var cpu_ms := float(now_us - _last_us - bot_us) / 1000.0
	T.bot_ms += float(bot_us) / 1000.0
	_coins_frame = GameState.coins
	if MetaState.sub("ach").size() != _ach_frame.size():
		_ach_frame = MetaState.sub("ach").keys().duplicate()
	_last_us = now_us
	_burn_us_frame = 0
	_frames += 1
	var dt := get_process_delta_time()
	_sim += dt
	T.add_activity(_activity, dt)
	if _frames > 10:
		T.frame(cpu_ms, _sim, _activity + "@" + str(_depth()) + ("" if _frame_events.is_empty() else " " + ",".join(_frame_events)))
		if cpu_ms > 1000.0:
			print("[bot] кадр %.0f мс на t=%.1f: %s, события кадра %s" % [cpu_ms, _sim, _activity, str(_frame_events)])
	_frame_events.clear()
	_real_time_waits()
	_check_tunneling()
	_auto_story()
	_dismiss_modals()
	bot.resync()
	_detectors()
	if GameState.coins > _coins_seen:
		_earned += GameState.coins - _coins_seen
	_coins_seen = GameState.coins
	if _sim >= _next_flush and _flush_sec > 0.0:
		_next_flush = _sim + _flush_sec
		T.meta["sim_seconds"] = snappedf(_sim, 0.1)
		T.meta["end_state"] = _state_dict()
		T.meta["partial"] = true
		T.write_json(_out.path_join("telemetry.json"), _sim)
	if _sim - _last_sample >= SAMPLE_SEC:
		_goal_tick()
		_last_sample = _sim
		T.sample(_sim, GameState.coins, GameState.xp, GameState.level, _depth(), GameState.max_depth_reached,
			GameState.hp, GameState.hunger, GameState.stamina, GameState.get_total_weight(), GameState.get_max_carry_kg())
	if _trace > 0.0 and _sim >= _next_trace and player != null:
		_next_trace = _sim + _trace
		print("[trace] ", _dump().split("\n")[0], " | ", _dump_rows(2), " | путь ", str(_dbg_path.slice(0, 4)), " цель-ряд ", _goal_row, " клавиши ", str(bot._down.keys()))
	if _shots_on and _sim >= _next_periodic_shot:
		_next_periodic_shot += 300.0
		_shot("periodic_%04d" % int(_sim / 60.0))
	if (Time.get_ticks_msec() - _wall0) / 1000.0 > _wall_cap and not _stop:
		if _minutes >= 9999.0:
			T.event(_sim, "wall_end", "ночной прогон: настенное время %.0f с вышло" % _wall_cap)   # плановый конец
		else:
			T.finding("P2", "wall_cap", "прогон упёрся в лимит настенного времени %.0f с" % _wall_cap, _sim)
		_stop = true
	if _sim >= _end + 600.0 and not _stop:
		_stop = true   # страховка: свободная игра должна была кончиться раньше
	_resume_us = _last_us


## Тап в координатах вьюпорта: BotPlayer.tap шлёт событие как есть, а движок считает его
## координатами окна (headless — 64×64) — переводим, иначе тап по цели катсцены мажет.
func _tap(pos: Vector2) -> void:
	bot.tap(get_viewport().get_final_transform() * pos)


func _frames_n(n: int) -> void:
	for _i in range(n):
		await _step()


func _wait(sec: float) -> void:
	var t0 := _sim
	while _sim - t0 < sec and not _stop:
		await _step()


func _burn(ms: int) -> void:
	if ms <= 0:
		return
	ms = mini(ms, 1200)
	OS.delay_msec(ms)
	_burn_us_frame += ms * 1000
	T.burned_ms += ms


## Прошёл сквозь породу: за кадр герой сдвинулся вниз больше чем на клетку, а между старой и новой
## клеткой по его колонке есть твёрдая порода (быстрое падение, режим жадности ×7).
func _check_tunneling() -> void:
	if player == null or GameState.house_is_indoors or not GameState.is_alive:
		_prev_cell = Vector2i(-99, -99)
		return
	var c := Vector2i(player.cell_x(), player.cell_y())
	if _prev_cell.x == c.x and c.y > _prev_cell.y + 1 and c.y - _prev_cell.y < 40 and not player.frozen:
		for y in range(_prev_cell.y + 1, c.y):
			if world.get_tile(c.x, y) != TileTypes.Type.EMPTY and not _died_pending:
				T.finding("P1", "tunneling", "герой прошёл сквозь породу (%d,%d)→(%d,%d)%s" % [_prev_cell.x, _prev_cell.y,
					c.x, c.y, " в режиме жадности" if _greed_active() else ""], _sim, {"dump": _dump()}, "greed" if _greed_active() else "fall")
				break
	_prev_cell = c


## Места, где игра считает настоящие миллисекунды: проживаем их честно.
func _real_time_waits() -> void:
	if player == null:
		return
	var now := Time.get_ticks_msec()
	# Тяга ранца после прыжка включается не раньше JUMP_TO_FLY_MS реального времени.
	if bot.is_down(KEY_W) and not player.on_ground and player.thrust == "" and player.vy >= -0.5 \
			and player.has_backpack() and float(player._fly_arm_at_msec) > now:
		_burn(int(float(player._fly_arm_at_msec) - now) + 2)
	# Стан (лопата о камень, удар монстра) — тоже по настоящим часам.
	if float(player.stun_until_msec) > now:
		_burn(int(float(player.stun_until_msec) - now) + 2)


func _depth() -> int:
	return int(GameState.player_depth) if not GameState.house_is_indoors else 0


## Бот листает катсцены тапами: обычный — дописать реплику / дальше, обязательный — по
## подсвеченной цели. Торопливый жмёт «Пропустить» (двойной тап по кнопке).
func _auto_story() -> void:
	if director == null or director.cutscene == null:
		return
	var cs: CutscenePlayer = director.cutscene
	var playing: bool = cs.is_playing
	var sid := String(cs.scene_id) if playing else ""
	if sid != _scene_cur:
		if _scene_cur != "":
			T.scenes.append({"id": _scene_cur, "start": snappedf(_scene_t0, 0.1), "sec": snappedf(_sim - _scene_t0, 0.1),
				"skipped": _skip_tries > 0})
		if sid != "":
			_scene_t0 = _sim
			_skip_tries = 0
			T.mark("scene:" + sid, _sim)
			if _shots_on:
				_shot_later("scene_" + sid, 2.5)
		_scene_cur = sid
	if not playing:
		return
	var text := String(cs._line.text) if cs._line != null else ""
	if not text.is_empty() and not bool(cs._typing):   # только допечатанные реплики
		T.add_line(sid, text)
	if _sim - _last_tap < float(C["tap"]):
		return
	# Анти-дребезг катсцены (90 мс) меряется настоящими часами.
	var since := Time.get_ticks_msec() - _last_tap_real
	if since < 100:
		_burn(100 - since)
	_last_tap = _sim
	_last_tap_real = Time.get_ticks_msec()
	var skip: Control = cs._skip_btn
	if bool(C["skip"]) and skip != null and skip.visible and skip.is_visible_in_tree() and _skip_tries < 6:
		_skip_tries += 1
		var c := skip.get_global_rect().get_center()
		_tap(c)
		_tap(c)
		return
	if cs._tap_target != null and cs._tap_target.visible:
		_tap(cs._tap_target.get_global_rect().get_center())
	else:
		_tap(Vector2(112.0, 300.0))


## Окна, которые всплывают сами и держат героя: человек их закрывает, бот тоже — и меряет,
## сколько каждое продержалось. Окно, которое не закрывается, — находка.
func _dismiss_modals() -> void:
	if _frames % 4 != 0:
		return
	var open: Array = []
	if ProgressScreen.is_open() and _activity != "screens":
		open.append("progress")
		ProgressScreen.close_screen()
	var meta = MetaService.instance
	if meta != null and is_instance_valid(meta):
		if meta.popup != null and meta.popup.is_open():
			open.append("daily_popup")
			var before := GameState.coins
			var btn: Button = meta.popup._claim_btn
			if btn != null and btn.visible and not btn.disabled:
				btn.pressed.emit()
			if meta.popup.is_open():
				meta.popup.close()
			T.event(_sim, "daily", "окно дня: +%d монет" % (GameState.coins - before))
		if meta.hub != null and meta.hub.is_open():
			open.append("meta_hub")
			meta.hub.close()
	if hud != null and hud.has_method("is_more_menu_open") and hud.is_more_menu_open():
		open.append("more_menu")
		hud.close_more_menu()
	if WellReport.is_open() and is_instance_valid(hud):
		open.append("well_report")
		hud.close_well_report()
	if TechScreen.is_open() and _activity != "tech":
		open.append("tech_screen")
		TechScreen.close_screen()
	if director == null:
		return
	if director.diary_ui != null and director.diary_ui.is_open and _activity != "diary":
		open.append("diary")
		director.diary_ui.close_diary()
	if _death_card == null:
		_death_card = main.find_child("DeathCard", true, false)
	var card = _death_card
	if card != null and card.has_method("is_open") and card.is_open() and DeathRide.riding():
		pass   # скорая ещё везёт: карточка не закрывается до приезда (раунд 5) — ждём, как человек
	elif card != null and card.has_method("is_open") and card.is_open():
		open.append("death_card")
		# под рендером карточку сначала снимаем, закрываем через секунду
		if not _shots_on or (_modal_since.has("death_card") and _sim - float(_modal_since["death_card"]) > 1.0):
			card.close()
		elif not _modal_since.has("death_card"):
			_shot_later("death_card", 0.4)
	if ShopUI.instance != null and ShopUI.instance.is_open() and _activity != "shop":
		open.append("shop_stray")
		ShopUI.instance.close()
	for k in open:
		if not _modal_since.has(k):
			_modal_since[k] = _sim
			T.modals.append({"t": snappedf(_sim, 0.1), "kind": k})
		elif _sim - float(_modal_since[k]) > MODAL_STUCK_SEC:
			T.finding("P1", "modal_stuck", "окно «%s» не закрывается %.0f с" % [k, _sim - float(_modal_since[k])], _sim, {}, k)
	for k in _modal_since.keys():
		if not open.has(k):
			_modal_since.erase(k)


## Застревание: ни клетки, ни монеты, ни позиции, ни комнаты, ни сцены за STUCK_SEC.
func _detectors() -> void:
	if player == null or _frames % 8 != 0:
		return
	var sig := "%d|%d|%d|%d|%s|%s|%s|%d" % [player.cell_x(), player.cell_y(), _digs, GameState.coins,
		str(GameState.house_is_indoors), GameState.house_room, _scene_cur, GameState.inventory.size()]
	if sig != _progress_sig:
		_progress_sig = sig
		_progress_t = _sim
		_stuck_level = 0
	elif _sim - _progress_t > STUCK_SEC * (1 + _stuck_level):
		_stuck_level += 1
		var d := _dump()
		T.stuck.append({"t": snappedf(_sim, 0.1), "activity": _activity, "level": _stuck_level, "dump": d})
		T.finding("P0", "stuck", "нет прогресса %.0f с (занятие «%s»)" % [_sim - _progress_t, _activity], _sim,
			{"dump": d}, _activity)
		if _shots_on:
			_shot("stuck_%s_%d" % [_activity, int(_sim)])
	# Ввод не доходит до героя: бот держит клавишу, окон и сцен нет, а намерение героя пустое.
	var want_dir := 1 if bot.is_down(KEY_D) else (-1 if bot.is_down(KEY_A) else 0)
	var want_down := bot.is_down(KEY_S)
	var lost_input: bool = not GameState.house_is_indoors and not player.frozen and not _busy_story() \
		and hud.visible and _modal_since.is_empty() and ((want_dir != 0 and not want_down and player.hold_dx != want_dir) \
		or (want_down and not player.hold_down and want_dir == 0))
	if lost_input:
		_input_lost_t += 8.0 / 31.0
		if _input_lost_t > 3.0:
			T.finding("P1", "input_lost", "клавиши зажаты, а намерение героя пустое > 3 с (занятие «%s»)" % _activity,
				_sim, {"dump": _dump()}, _activity)
			_input_lost_t = 0.0
	else:
		_input_lost_t = 0.0
	if _greed_active():
		if _greed_t == 0.0:
			T.mark("first_greed", _sim)
		_greed_t += 8.0 / 31.0
		T.meta["greed_seconds"] = snappedf(_greed_t, 0.1)
	# Герой внутри твёрдой клетки — зажат.
	if not GameState.house_is_indoors and GameState.is_alive and not player.frozen and not _busy_story() \
			and player._solid_at(player.x, player.y):
		T.finding("P1", "inside_solid", "герой внутри твёрдой клетки (%.2f, %.2f)" % [player.x, player.y], _sim,
			{"dump": _dump()}, "%d,%d" % [player.cell_x(), player.cell_y()])


func _dump() -> String:
	var parts: Array[String] = []
	parts.append("t=%.0f занятие=%s герой (%.2f, %.2f) vx=%.2f vy=%.2f ground=%s frozen=%s digging=%s thrust='%s' tool=%s gear=%s" % [
		_sim, _activity, player.x, player.y, player.vx, player.vy, player.on_ground, player.frozen,
		str(player.digging != null), player.thrust, GameState.current_tool, GameState.current_gear])
	parts.append("катсцена: %s (%s) автокопка: %s очередь: %s задание: «%s»" % [
		director.cutscene.scene_id, director.cutscene.is_playing, director.auto_dig.running,
		str(GameState.story_queue), director._objective])
	parts.append("монеты %d hp %.0f голод %.0f бодрость %.0f вес %.1f/%.1f глубина %d (макс %d) дом %s/%s клавиши %s HUD %s" % [
		GameState.coins, GameState.hp, GameState.hunger, GameState.stamina, GameState.get_total_weight(),
		GameState.get_max_carry_kg(), _depth(), GameState.max_depth_reached, GameState.house_is_indoors,
		GameState.house_room, str(bot._down.keys()), hud.visible])
	if not GameState.house_is_indoors:
		var cx: int = player.cell_x()
		var cy: int = player.cell_y()
		for y in range(cy - 4, cy + 5):
			var row := ""
			for x in range(maxi(0, cx - 8), mini(WorldGen.WIDTH, cx + 9)):
				row += "@" if (x == cx and y == cy) else _tile_char(world.get_tile(x, y))
			parts.append("  %5d %s" % [y, row])
	return "\n".join(parts)


func _dump_rows(r: int) -> String:
	if player == null or GameState.house_is_indoors:
		return "дом:" + GameState.house_room
	var cx: int = player.cell_x()
	var cy: int = player.cell_y()
	var rows: Array[String] = []
	for y in range(cy - r, cy + r + 1):
		var row := ""
		for x in range(maxi(0, cx - 4), mini(WorldGen.WIDTH, cx + 5)):
			row += "@" if (x == cx and y == cy) else _tile_char(world.get_tile(x, y))
		rows.append(row)
	return " / ".join(rows)


static func _tile_char(t: int) -> String:
	match t:
		TileTypes.Type.EMPTY: return "."
		TileTypes.Type.DIRT: return "d"
		TileTypes.Type.STONE: return "s"
		TileTypes.Type.FOUNDATION: return "F"
		TileTypes.Type.STAIRCASE: return "/"
		TileTypes.Type.REINFORCED: return "R"
		TileTypes.Type.LAVA: return "~"
	return "o" if TileTypes.is_ore(t) else "#"


func _state_dict() -> Dictionary:
	return {"coins": GameState.coins, "dollars": GameState.dollars, "level": GameState.level, "xp": GameState.xp,
		"max_depth": GameState.max_depth_reached, "tool": GameState.current_tool, "gear": GameState.current_gear,
		"tools": GameState.owned_tools if "owned_tools" in GameState else [], "artifacts": GameState.collected_artifacts.size(),
		"skill_points_left": GameState.skill_points_available, "well_level": GameState.well_level,
		"story_seen": GameState.story_seen.duplicate(), "hp": GameState.hp, "hunger": GameState.hunger,
		"stamina": GameState.stamina}


# ---------------------------------------------------------------------------
# Сигналы → телеметрия
# ---------------------------------------------------------------------------

func _on_dig_finished(x: int, y: int, _t: int, mineral: String, loot: bool, _c: int) -> void:
	_digs += 1
	T.trip_dig(y, loot)
	if _digs == 1:
		T.mark("first_dig", _sim)


func _on_fell(dmg: float, v: float) -> void:
	if dmg <= 0.0:
		return
	if _greed_active():
		T.finding("P1", "greed_fall", "урон от падения в режиме жадности: −%.0f HP на скорости %.1f" % [dmg, v], _sim, {}, "greed_fall")
	_last_fall_sim = _sim
	_last_fall_dmg = dmg
	T.event(_sim, "fall", "падение: −%.0f HP (скорость %.1f)" % [dmg, v], false)


func _on_max_depth(d: int) -> void:
	for m in Telemetry.DEPTH_MARKS:
		if d >= int(m):
			if T.mark("depth_%d" % int(m), _sim) and _shots_on and int(m) >= 25:
				_shot_later("depth_%d" % int(m), 0.5)
	if _max_depth_stop > 0 and d >= _max_depth_stop and not _stop:
		T.event(_sim, "stop", "достигнута глубина %d" % d)
		_stop = true


func _on_died() -> void:
	var cause := "unknown"
	# died приходит из take_damage раньше, чем player.fell: падение видно по скорости удара
	if _sim - _last_fall_sim < 1.0 or float(player.vy) > 12.0 or _activity == "descend" and GameState.hunger > 0.0:
		cause = "fall"
	elif GameState.hunger <= 0.0:
		cause = "hunger"
	elif _near_tile(TileTypes.Type.LAVA):
		cause = "lava"
	elif CombatService.in_war_zone(_depth()):
		cause = "monster"
	var value := 0
	for id in _pack_before_death.keys():
		value += Balance.get_mineral_price(String(id)) * int(_pack_before_death[id])
	var d := {"t": snappedf(_sim, 0.1), "cause": cause, "depth": _depth(), "activity": _activity,
		"lost_items": _pack_before_death.duplicate(), "lost_value": value, "scripted": not StoryState.is_seen("death"),
		"coins_before": _coins_frame, "deliberate": _no_brake,
		"ach_before": _ach_frame.duplicate()}
	_no_brake = false
	_death_entry = d
	T.deaths.append(d)
	T.event(_sim, "death", "смерть: %s на глубине %d, потеряно на %d" % [cause, _depth(), value])
	if StoryState.is_seen("death"):
		T.finding("P2", "death", "смерть (%s) на глубине %d в занятии «%s», потеряно на %d монет" % [
			cause, _depth(), _activity, value], _sim, d, cause + "@" + _activity)
	_died_pending = true
	bot.release_all()
	_branch_goal = Vector2i(-1, -1)


func _on_respawned() -> void:
	_died_pending = false
	if T.in_trip():
		T.trip_end(_sim, "death", 0, 0.0)
	# Цена смерти (владелец, раунд 5): весь лут и 5% монет, от 50 до 5000 («скорая забрала»),
	# и поездка скорой (respawned приходит по приезде). Сверяем через секунду игры.
	var d := _death_entry
	if d.is_empty() or bool(d.get("scripted", false)):
		return
	_check_death_lift(d)
	var t := get_tree().create_timer(1.0, true, false, false)
	t.timeout.connect(func() -> void:
		# Смерть сама открывает достижения («Двоечник пришёл к бабушке» +100): их монеты не цена смерти.
		var bonus := 0
		var before_ach: Array = d.get("ach_before", [])
		for a in MetaData.achievements():
			var aid := String(a.get("id", ""))
			if MetaState.sub("ach").has(aid) and not before_ach.has(aid):
				bonus += int((a.get("reward", {}) as Dictionary).get("coins", 0))
		var lost := int(d.get("coins_before", 0)) - GameState.coins + bonus
		d["coins_lost"] = lost
		var expect := _expected_fee(int(d.get("coins_before", 0)))
		if lost != expect:
			T.finding("P1", "death_cost", "смерть отняла %d монет, а по правилу — %d (5%%, от 50 до 5000)" % [lost, expect],
				_sim, d, str(lost == 0)))


## Правило владельца (раунд 5), посчитанное заново, а не взятое у игры: 5% вниз до целого,
## не меньше 50 и не больше 5000, но не больше, чем есть.
static func _expected_fee(coins: int) -> int:
	if coins <= 0:
		return 0
	return mini(coins, clampi(coins * 5 / 100, 50, 5000))


## «Умер нарочно, чтобы не лететь» (раунд 5): выгадал ли бот на смерти. Выигрыш — подъём,
## которого не было (его собственная скорость подъёма с этой глубины), минус поездка скорой;
## в монетах — по доходу прогона. Цена — рюкзак и плата. Выигрыш больше цены — P1 death_lift.
func _check_death_lift(d: Dictionary) -> void:
	var depth := int(d.get("depth", 0))
	var ride := DeathRide.total_seconds() if depth >= 3 else 0.0
	var ascent := _ascent_estimate(depth)
	var rate := _income_rate()
	var fee := _expected_fee(int(d.get("coins_before", 0)))
	var saved := ascent - ride
	var gain := saved * rate
	var cost := float(int(d.get("lost_value", 0)) + fee)
	d["ride_s"] = snappedf(ride, 0.1)
	d["ascent_est_s"] = snappedf(ascent, 0.1)
	d["lift_gain"] = int(gain)
	d["lift_cost"] = int(cost)
	d["hp_after"] = snappedf(GameState.hp, 0.1)
	T.event(_sim, "death_ride", "скорая %.0f с с глубины %d (подъём бота ~%.0f с), выгода %d против цены %d" % [
		ride, depth, ascent, int(gain), int(cost)], false)
	if depth >= 60 and saved > 0.0 and gain > cost:
		T.finding("P1", "death_lift", "смерть на глубине %d выгоднее подъёма: скорая %.0f с против подъёма ~%.0f с, выгода %d монет против цены %d (рюкзак + плата)" % [
			depth, ride, ascent, int(gain), int(cost)], _sim, d, "deliberate" if bool(d.get("deliberate", false)) else "accident")


func _on_inventory() -> void:
	if GameState.is_alive and not GameState.inventory.is_empty():
		_pack_before_death = GameState.inventory.duplicate()


func _on_game_event(id: StringName, data: Dictionary) -> void:
	var k := String(id)
	T.event_counts[k] = int(T.event_counts.get(k, 0)) + 1
	if _frame_events.size() < 6 and k != "dug" and k != "picked":
		_frame_events.append(k)
	match k:
		"picked":
			var item := String(data.get("item", ""))
			if item != "" and not T.minerals_first.has(item):
				T.minerals_first[item] = snappedf(_sim, 0.1)
				T.event(_sim, "new_mineral", item)
		"quest_done":
			T.event(_sim, "quest", String(data.get("id", "")))
		"bought":
			T.event(_sim, "bought", String(data.get("id", "")))
		"slept":
			T.event(_sim, "slept", "сон %.1f ч" % float(data.get("hours", 0.0)), false)


func _near_tile(tile: int) -> bool:
	if player == null:
		return false
	var cx: int = player.cell_x()
	var cy: int = player.cell_y()
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if world.get_tile(cx + dx, cy + dy) == tile:
				return true
	return false


# ---------------------------------------------------------------------------
# Снимки (только под настоящим рендером)
# ---------------------------------------------------------------------------

func _can_shoot() -> bool:
	return _shots_on and DisplayServer.get_name() != "headless" and _shot_count < 160


func _shot(tag: String) -> void:
	if not _can_shoot():
		return
	_shot_count += 1
	var path := _out.path_join("shots").path_join("%03d_%s.png" % [_shot_count, tag])
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	img.save_png(path)
	T.shots.append({"t": snappedf(_sim, 0.1), "tag": tag, "path": path, "depth": _depth(), "activity": _activity})


func _shot_later(tag: String, sec: float) -> void:
	if not _can_shoot():
		return
	var t := get_tree().create_timer(sec, true, false, false)
	t.timeout.connect(func() -> void: _shot(tag))


# ---------------------------------------------------------------------------
# Навыки: ходьба, кнопки дома
# ---------------------------------------------------------------------------

func _busy_story() -> bool:
	return director.cutscene.is_playing or director.auto_dig.running


## Идёт по поверхности к x. Упёрся — жмёт ещё «вверх» (прыжок через уступ).
func _walk_to_x(tx: float, budget: float = 40.0, tol: float = 0.15) -> bool:
	var t0 := _sim
	var last_x: float = player.x
	var last_move := _sim
	var surface: bool = player.y < 1.5
	while _sim - t0 < budget and not _stop:
		if _busy_story() or GameState.house_is_indoors or not GameState.is_alive:
			bot.release_all()
			return false
		if surface and player.y >= 1.6:
			bot.release_all()   # провалился (устье, яма) — пусть решает основной цикл
			return false
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
	return false


func _view() -> Node:
	return house._view


## Нажимает кнопку действия в комнате, как игрок: идёт к точке клавишами, ждёт кнопку, жмёт.
func _house_press(action: String, budget: float = 25.0) -> bool:
	if not GameState.house_is_indoors:
		return false
	var view := _view()
	if view.forced_mode() != "":
		view._on_forced_pressed()
		await _frames_n(3)
	var pts: Dictionary = HouseRoomsConfig.points(String(view.room_id()))
	var px := -1.0
	var radius := 0.05
	for id in pts.keys():
		for b in (pts[id].get("buttons", []) as Array):
			if String(b.get("action", "")) == action:
				px = float(pts[id].get("x", 0.5))
				radius = float(pts[id].get("radius", 0.08))
	if px < 0.0:
		T.finding("P1", "house_action_missing", "в комнате %s нет действия %s" % [view.room_id(), action], _sim, {}, action)
		return false
	var t0 := _sim
	while absf(float(view.hero_x_fraction()) - px) > radius * 0.5 and _sim - t0 < budget and not _stop:
		bot.hold([KEY_D if px > float(view.hero_x_fraction()) else KEY_A])
		await _step()
	bot.release_all()
	await _frames_n(2)
	for btn in view._hotspot_buttons:
		if String(btn.get_meta("action", "")) == action and btn.visible:
			btn.pressed.emit()
			await _frames_n(2)
			return true
	T.finding("P1", "house_button", "кнопка «%s» не появилась над героем (комната %s, x=%.2f, заперт=%s)" % [
		action, view.room_id(), view.hero_x_fraction(), view._is_locked()], _sim, {"dump": _dump()}, action)
	return false


func _go_room(room: String) -> bool:
	var cur := String(_view().room_id())
	if cur == room:
		return true
	if cur != "hall" and not await _house_press("goto:hall"):
		return false
	if room == "hall":
		return true
	return await _house_press("goto:" + room)


# ---------------------------------------------------------------------------
# Онбординг (ГДД §9): тот же путь, что у человека
# ---------------------------------------------------------------------------

func _until(cond: Callable, budget: float, label: String, hold: Array = []) -> bool:
	var t0 := _sim
	while _sim - t0 < budget and not _stop:
		if cond.call():
			bot.release_all()
			T.mark("onb:" + label, _sim)
			return true
		if not hold.is_empty() and not _busy_story():
			bot.hold(hold)
		elif _busy_story():
			bot.release_all()
		await _step()
	bot.release_all()
	T.finding("P0", "onboarding", "онбординг застрял: «%s» за %.0f с" % [label, budget], _sim, {"dump": _dump()}, label)
	return false


func _onboarding() -> void:
	_activity = "onboarding"
	if not await _until(func(): return StoryState.has_flag("intro_seen") and not director.cutscene.is_playing,
			900.0, "интро"):
		return _abort()
	_shot("after_intro")
	if not await _walk_to_x(21.5):
		T.finding("P0", "onboarding", "не дошёл до места первой копки", _sim, {"dump": _dump()})
		return _abort()
	var d0 := _digs
	if not await _until(func(): return _digs >= d0 + 3 or StoryState.is_seen("autodig_start"), 90.0, "три копки", [KEY_S]):
		return _abort()
	if not await _until(func(): return StoryState.is_seen("autodig_done") and not _busy_story(), 300.0, "автокопка"):
		return _abort()
	_shot("after_autodig")
	# Мастерская: к двери, зайти, кирка со стены, наружу.
	var door := HouseConfig.door_cell()
	await _walk_to_x(float(door.x) + 0.5, 90.0)
	if not await _enter_door():
		return _abort()
	await _go_room("workshop")
	if not await _house_press("take_pickaxe"):
		return _abort()
	_shot("workshop")
	await _go_room("hall")
	await _house_press("exit_door")
	await _frames_n(3)
	# Пять самородков на четвёртом уровне.
	var gold: Array = world.scripted_loot_cells()
	if gold.is_empty():
		T.finding("P1", "onboarding", "нет сценарного золота", _sim)
	else:
		var first_x := 99
		for g: Vector2i in gold:
			first_x = mini(first_x, g.x)
		await _walk_to_x(float(first_x) - 0.5, 60.0)
		if not await _until(func(): return StoryState.has_flag("gold_taken"), 120.0, "пять самородков", [KEY_D]):
			return _abort()
	if not await _until(func(): return StoryState.has_flag("foundation_broken"), 90.0, "фундамент", [KEY_S]):
		return _abort()
	if not await _until(func(): return StoryState.is_seen("robert") and not _busy_story(), 700.0, "смерть, ранец и Роберт"):
		return _abort()
	_shot("after_robert")
	# «Продай золото» и «закажи еду» — обычный визит домой с этим заданием.
	if GameState.house_is_indoors:
		await _go_room("hall")
		_sell()
		await _order_and_take_food(true)
	T.mark("onboarding_done", _sim)
	_activity = "free"


## Короткий тест стратегий: без 2 минут онбординга — сразу «после Роберта» (кирка, ранец, тоннель, 750 монет).
func _fast_start() -> void:
	GameState.grant_tool("rusty_pickaxe")
	GameState.set_current_tool("rusty_pickaxe")
	GameState.grant_gear("backpack")
	GameState.coins = 750
	GameState.dollars = 5
	GameState.coins_changed.emit(GameState.coins)
	_coins_seen = GameState.coins
	house.robert_finished_garden()
	if world.has_method("unlock_pre_autodig_garden"):
		world.unlock_pre_autodig_garden()
	player.teleport_home()
	_activity = "free"


## Старт на глубине (раунд 5, полости и стражи с 1500): шахта от поверхности до
## кармана (иначе боту не подняться продавать — первый прогон встал «ascent_stuck»),
## карман над ближайшей полостью по её центру: копая вниз, бот входит к стражам.
func _deep_start(depth: int) -> void:
	var col := 16
	var top := depth
	var caves := Caves.caves_between(world, depth, depth + 400)
	if not caves.is_empty():
		var c: Dictionary = caves[0]
		col = int(c.cx)
		top = int(c.y0) - 4
	# шахта и через торфяной пласт (450–455): игрок прокопал бы его по пути вниз, а бот
	# на подъёме не копает — второй прогон встал под пластом на 48 минут
	for y in range(6, top + 1):
		world.diffs[y * WorldGen.WIDTH + col] = true
	for x in range(col - 1, col + 2):
		for y in range(top - 1, top + 1):
			world.diffs[y * WorldGen.WIDTH + x] = true
	world.mark_changed()
	player.x = float(col) + 0.5
	player.y = float(top) + 0.6
	player.vx = 0.0
	player.vy = 0.0
	player.on_ground = true
	GameState.house_is_indoors = false
	GameState.max_depth_reached = maxi(GameState.max_depth_reached, depth)
	if main != null and main.fog != null:
		main.fog.reveal_around(player.x, player.y, 6, 6)
	T.event(_sim, "deep_start", "старт на глубине %d" % depth)


func _abort() -> void:
	# Без онбординга свободная игра бессмысленна: дальше смотрим только то, что успели.
	_stop = true


func _enter_door() -> bool:
	var t0 := _sim
	while _sim - t0 < 8.0 and not _stop:
		if house.near_door() and house._outdoor_button.visible:
			house._outdoor_button.pressed.emit()
			await _frames_n(3)
			return GameState.house_is_indoors
		await _step()
	T.finding("P1", "door", "у двери нет кнопки «Зайти»", _sim, {"dump": _dump()})
	return false


# ---------------------------------------------------------------------------
# Свободная игра
# ---------------------------------------------------------------------------

func _free_play() -> void:
	var idle_loops := 0
	var last_sim := _sim
	while _sim < _end and not _stop:
		if _busy_story() or not GameState.is_alive:
			_activity = "story" if _busy_story() else "dead"
			bot.release_all()
			await _step()
			continue
		if _sim - last_sim < 0.001:
			idle_loops += 1
			if idle_loops > 50:
				T.finding("P0", "bot_idle", "бот крутится вхолостую", _sim, {"dump": _dump()})
				await _step()
		else:
			idle_loops = 0
		last_sim = _sim
		if GameState.house_is_indoors:
			await _home_visit()
		elif player.y < 1.5:
			await _surface()
		else:
			if _should_return() != "":
				if not await _maybe_die_lift():
					await _ascend()
			else:
				await _mine()


## На поверхности: могила (задание сюжета), домой (продать/поесть) или в шахту.
func _surface() -> void:
	_activity = "surface"
	if T.in_trip():
		T.trip_end(_sim, "surface", _pack_value(), GameState.get_total_weight())
	if StoryState.is_seen("grave_call") and not StoryState.has_flag("diary_found"):
		await _visit_grave()
		return
	if _from_house and _fuel_tool() != "" and FuelTank.fraction(_fuel_tool()) < 0.6:
		await _visit_station()
	_maybe_die_once()
	# Только что из дома — сразу в шахту: иначе то, что дома не решилось (нет денег на еду,
	# материалы на проект), гоняло бы героя туда-обратно у двери.
	if not _from_house and _needs_home():
		var door := HouseConfig.door_cell()
		if await _walk_to_x(float(door.x) + 0.5, 60.0):
			await _enter_door()
		return
	await _descend()


## Станция в огороде (ветка fuel-station): перегнать торф/уголь в блоки и залить бак.
func _visit_station() -> void:
	_activity = "station"
	var tool := _fuel_tool()
	var ref = load("res://scripts/tech/fuel_refinery.gd") if ResourceLoader.exists("res://scripts/tech/fuel_refinery.gd") else null
	if ref == null or not _has_static(ref, "refine"):
		return
	# Станция стоит правее устья тоннеля: пешком от двери герой проваливается в шахту —
	# перепрыгиваем устье, как человек (прыжок с тягой).
	var mouth_x := float(world.tunnel_mouth().x)
	if player.x < mouth_x:
		if not await _walk_to_x(mouth_x - 1.0, 40.0, 0.2):
			return
		var t0 := _sim
		while player.x < mouth_x + 1.3 and _sim - t0 < 6.0 and player.y < 1.6:
			bot.hold([KEY_D, KEY_W] if player.x < mouth_x + 0.9 else [KEY_D])
			await _step()
		bot.release_all()
		if player.y >= 1.6:
			T.finding("P2", "station_path", "до станции заправки не дойти пешком: путь от двери идёт через устье тоннеля", _sim)
			return
	if not await _walk_to_x(float(WorldGen.FUEL_STATION_X) + 1.0, 40.0, 0.4):
		return
	var made := 0
	for raw in ["peat", "coal"]:
		var r: Dictionary = ref.call("refine", raw, 99)
		made += int(r.get("made", 0))
	var n := FuelTank.refuel(tool, "pack") + FuelTank.refuel(tool, "storage")
	T.event(_sim, "station", "перегнано %d, залито %d (бак %.0f%%)" % [made, n, FuelTank.fraction(tool) * 100.0], false)
	if made > 0 or n > 0:
		T.mark("first_station", _sim)
	elif FuelTank.fraction(tool) < 0.2:
		# Глубина в находке: выше 450 торф ещё редок и бур в минусе по замыслу (ГДД п.5), за пластом — нет.
		T.finding("P2", "no_fuel", "бак %s почти пуст, а перегонять нечего (торфа %d, угля %d, глубина %d)" % [tool,
			GameState.get_item_count("peat") + HouseStorage.count("peat"), GameState.get_item_count("coal") + HouseStorage.count("coal"),
			GameState.max_depth_reached], _sim, {}, "no_fuel")
	_activity = "surface"


## «Охотник за достижениями»: одно достижение — умереть. Раз за прогон, с пустым рюкзаком и запасом
## монет: спуск по своему стволу без тормоза. Заодно проверяет цену смерти (200 монет, весь лут).
func _maybe_die_once() -> void:
	if not bool(G.get("die_once", false)) or _die_tries >= 3 or GameState.max_depth_reached < 60 or GameState.coins < 260:
		return
	var ach = load("res://scripts/meta/achievements.gd")
	if ach != null and _has_static(ach, "is_done") and bool(ach.call("is_done", "die_1")):
		return
	_die_tries += 1
	_no_brake = true
	T.event(_sim, "die_once", "спуск без тормоза ради достижения «умри»")


func _needs_home() -> bool:
	for id in GameState.inventory.keys():
		if not HouseConfig.is_food(String(id)) and String(id) != FuelTank.block_item():
			return true
	if GameState.hunger < float(C["eat_below"]) or GameState.stamina < float(C["sleep_below"]):
		return true
	if GameState.skill_points_available > 0 and _skill_affordable():
		return true   # очки навыков тратятся дома — игрок с новым уровнем идёт качаться
	return GameState.hp < GameState.get_max_hp() * 0.5 and _can_heal()


## Есть ли ветка по порядку цели, на которую хватает очков (копим — не повод бегать домой).
func _skill_affordable() -> bool:
	for b in C["skills"]:
		var br := Balance.get_upgrade_branch(String(b))
		if br.is_empty() or GameState.get_skill_stage(String(b)) >= int(br.get("stages", 0)):
			continue
		var cost := Balance.get_upgrade_stage_cost(String(b), GameState.get_skill_stage(String(b)) + 1)
		if cost < 0:
			continue
		return cost <= GameState.skill_points_available
	return false


func _visit_grave() -> void:
	_activity = "grave"
	var g = director.grave
	if g == null:
		return
	await _walk_to_x(GraveSite.GRAVE_X, 40.0, 0.3)
	await _frames_n(3)
	var btn: Button = g._button
	if btn != null and btn.visible:
		btn.pressed.emit()
		T.event(_sim, "grave", "нажата могила")
		var t0 := _sim
		while not _busy_story() and not StoryState.has_flag("diary_found") and _sim - t0 < 30.0 and not _stop:
			await _step()
		await _until(func(): return not _busy_story(), 300.0, "сцена у могилы")
		if director.diary_ui != null and director.diary_ui.is_open:
			await _shot("diary")
			director.diary_ui.close_diary()
	else:
		T.finding("P1", "grave_button", "у могилы нет кнопки, хотя задание «%s»" % director._objective, _sim, {"dump": _dump()})
		await _wait(2.0)
	if not StoryState.has_flag("diary_found"):
		T.finding("P1", "grave", "дневник у могилы не найден после нажатия", _sim, {"dump": _dump()})
		await _wait(5.0)


## Спуск: к устью тоннеля, провалиться, тормозить тягой до дна ствола.
func _descend() -> void:
	_activity = "descend"
	var mouth := world.tunnel_mouth()
	if mouth.x < 0:
		T.finding("P0", "tunnel", "нет тоннеля Роберта (входа в шахту)", _sim)
		_stop = true
		return
	_shaft_x = mouth.x
	if not await _walk_to_x(float(mouth.x) - 0.6, 60.0, 0.3):
		return
	bot.hold([KEY_D])
	var t0 := _sim
	while player.y <= 1.6 and _sim - t0 < 8.0 and not _stop and not _busy_story():
		await _step()
	bot.release_all()
	if player.y <= 1.6 and _busy_story():
		return   # у устья началась сцена сюжета (зов к могиле): ждём её в общем цикле, это не баг тоннеля
	if player.y <= 1.6:
		T.finding("P1", "tunnel_drop", "герой не проваливается в устье тоннеля", _sim, {"dump": _dump()})
		await _wait(1.0)
		return
	_from_house = false
	T.trip_start(_sim, _depth())
	if _shots_on and T.trips.is_empty():
		_shot("first_descent")
	var hp0 := GameState.hp
	t0 = _sim
	while _sim - t0 < 120.0 and not _stop and GameState.is_alive:
		if player.on_ground and player.cell_y() >= 5:
			break
		if _busy_story() or GameState.house_is_indoors:
			break
		bot.hold(_brake_keys())
		if _trace > 0.0 and _trace < 0.2:
			print("[desc] t=%.2f y=%.3f vy=%.2f thrust='%s' keys=%s gap=%d tool=%s ground=%s" % [_sim, player.y, player.vy,
				player.thrust, str(bot._down.keys()), _floor_gap(), GameState.current_tool, str(player.on_ground)])
		await _step()
	bot.release_all()
	if GameState.hp < hp0 - 20.0:
		T.finding("P2", "descent_damage", "спуск по стволу отнял %.0f HP (тормоз тягой)" % (hp0 - GameState.hp), _sim)


## Тормоз тягой в свободном падении — только если до дна далеко: у самого пола зажатое
## «вверх» в момент касания становится прыжком, и герой скачет на месте.
func _brake_keys() -> Array:
	# Урона нет до высоты 5 клеток (balance.json → fall_damage): скорость удара ≤ √(2·16·5) ≈ 12.6.
	# Как человек: падать свободно и тормозить тягой (−26 кл/с²) так, чтобы у пола было ≤ ~12:
	# тормозить, если без тяги удар вышел бы сильнее (v² + 2·G·зазор > 150) и до пола уже не
	# дальше тормозного пути (v² − 100)/52 плюс запас.
	if _no_brake or not player.has_backpack() or player.vy <= 8.0:
		return []
	var v: float = player.vy
	var gap: float = float(_floor_gap()) + (float(player.cell_y()) + 1.0 - (float(player.y) + 1.0 / 3.0))
	if v * v + 32.0 * gap > 150.0 and gap <= (v * v - 100.0) / 52.0 + 2.5:
		return [KEY_W]
	return []


func _floor_gap() -> int:
	var cx: int = player.cell_x()
	var cy: int = player.cell_y()
	var n := 0
	while n < 40 and world.get_tile(cx, cy + 1 + n) == TileTypes.Type.EMPTY:
		n += 1
	return n


func _pack_value() -> int:
	var v := 0
	for row in ShopService.sellable_stacks():
		v += int(row["sum"])
	return v


## Почему пора наверх ("" — не пора).
func _should_return() -> String:
	var w := GameState.get_total_weight()
	var mw := GameState.get_max_carry_kg()
	if w >= mw * float(C["ret_weight"]):
		return "weight"
	if GameState.hunger < float(C["ret_hunger"]):
		if HouseFood.best_food_for_now() != "":
			return ""   # еда в рюкзаке — съест на месте (_eat_in_mine)
		return "hunger"
	if GameState.stamina < float(C["ret_stamina"]):
		return "stamina"
	if GameState.hp < GameState.get_max_hp() * float(C["ret_hp"]) / 100.0 and _can_heal():
		return "hp"
	if T.in_trip() and _sim - float(T._trip["start"]) > float(C["trip_max"]):
		return "trip_time"
	if _sim >= _end:
		return "end"
	return ""


## Чем дома поднять HP: с раунда 4 лечат сон и еда, аптечка продаётся за монеты, таблетка за
## доллары — полное восстановление (ГДД §7 «Лечение»). Сон есть всегда — лечиться есть чем.
func _can_heal() -> bool:
	return true


func _hp_low() -> bool:
	return GameState.hp < GameState.get_max_hp() * float(C["ret_hp"]) / 100.0


func _eat_in_mine() -> void:
	if GameState.hunger >= float(C["ret_hunger"]) + 10.0:
		return
	var id := HouseFood.best_food_for_now()
	if id == "":
		return
	var before := GameState.hunger
	hud._eat_from_inventory(id)
	T.meals.append({"t": snappedf(_sim, 0.1), "id": id, "where": "mine", "hunger_before": snappedf(before, 0.1)})
	T.event(_sim, "eat", "съел %s в шахте" % id, false)


## Копка. Каждую новую клетку — новый план навигатора (tests/bot/bot_nav.gd): к видимой
## руде в радиусе C.side, к концу штрека (жадный), иначе на клетку глубже. Цель, к которой
## 10 с нет продвижения, уходит в чёрный список на две минуты.
func _mine() -> void:
	_activity = "mine"
	if not T.in_trip():
		T.trip_start(_sim, _depth())
	var path: Array = []
	var path_cell := Vector2i(-99, -99)
	var path_t := -100.0
	var goal := Vector2i(-1, -1)
	var last_progress := _sim
	var last_digs := _digs
	var visited: Dictionary = {}
	_goal_row = player.cell_y()
	_tgt = Vector2i(-1, -1)
	_tgt_row = -1
	while not _stop and GameState.is_alive and not GameState.house_is_indoors and not _busy_story():
		_eat_in_mine()
		var why := _should_return()
		if why != "":
			bot.release_all()
			if T.in_trip():
				T._trip["return_reason"] = why
			return
		if player.y < 1.5:
			bot.release_all()
			return
		var cell := Vector2i(player.cell_x(), player.cell_y())
		if _digs != last_digs or not visited.has(cell):
			visited[cell] = true
			last_progress = _sim
			last_digs = _digs
		elif _sim - last_progress > 10.0:
			_bad[goal] = _sim + 120.0
			T.event(_sim, "unstick", "10 с без продвижения к %s" % str(goal), false)
			path = []
			last_progress = _sim
			if _branch_goal == goal:
				_branch_goal = Vector2i(-1, -1)
			_tgt = Vector2i(-1, -1)
			_tgt_row = -1
		if path.is_empty() or cell != path_cell or _sim - path_t > 2.0:
			path = _plan_mine(cell)
			path_cell = cell
			path_t = _sim
			goal = path.back() if not path.is_empty() else Vector2i(-1, -1)
			_dbg_path = path
		var keys: Array = [KEY_S]
		if path.size() >= 2:
			keys = _keys_for_step(cell, path[1])
		if not player.on_ground:
			keys.erase(KEY_S)
			if not keys.has(KEY_W) and not _brake_keys().is_empty():
				keys.append(KEY_W)   # падение (ствол, каверна, обвал) — тормоз тягой до безопасной скорости
		bot.hold(keys)
		if _trace > 0.0 and _trace < 0.2 and not player.on_ground:
			print("[fly] t=%.2f y=%.3f vy=%.2f up=%s thrust='%s' keys=%s step=%s" % [_sim, player.y, player.vy,
				str(player.hold_up), player.thrust, str(keys), str(path.slice(0, 2))])
		await _step()
	bot.release_all()


var _bad: Dictionary = {}               # клетка -> до какого sim не пытаться
var _branch_goal := Vector2i(-1, -1)
var _goal_row := 0
var _dbg_path: Array = []
var _branched: Dictionary = {}          # ряд -> сколько штреков начато


func _is_bad(c: Vector2i) -> bool:
	return _bad.has(c) and float(_bad[c]) > _sim


## Цель держится, пока не достигнута или не отброшена: если выбирать её заново с каждой
## клетки, набор «видимой руды рядом» и «ряд глубже меня» меняется вместе с героем, и он
## зависает на тяге между двумя рядами (с ряда r путь вверх к одной руде, с r−1 — вниз к другой).
var _tgt := Vector2i(-1, -1)          # клетка-цель (руда, конец штрека) или x=-1
var _tgt_row := -1                    # цель «глубже ряда N» (спуск)


func _plan_mine(cell: Vector2i) -> Array:
	# 1) держим текущую цель
	if _tgt.x >= 0:
		var t := world.get_tile(_tgt.x, _tgt.y)
		var still := not _is_bad(_tgt) and cell != _tgt and (t != TileTypes.Type.EMPTY or _tgt == _branch_goal)
		if still:
			var tg := _tgt
			var p := nav.plan(cell, func(c: Vector2i) -> bool: return c == tg, mini(cell.y, tg.y) - 4, maxi(cell.y, tg.y) + 4, 160)
			if not p.is_empty():
				return p
			_bad[_tgt] = _sim + 120.0
		if _tgt == _branch_goal:
			_branch_goal = Vector2i(-1, -1)
		_tgt = Vector2i(-1, -1)
	if _tgt_row >= 0:
		if cell.y > _tgt_row:
			_tgt_row = -1   # спустились — выберем заново (может, рядом руда)
		else:
			var gr := _tgt_row
			var p2 := nav.plan(cell, func(c: Vector2i) -> bool: return c.y > gr and not _is_bad(c), cell.y - 6, gr + 6, 160)
			if not p2.is_empty():
				return p2
			_tgt_row = -1
	# 2) новая цель: видимая руда в радиусе C.side (ближайшая по пути)
	var r := int(C["side"])
	var loot: Dictionary = {}
	for y in range(cell.y - r, cell.y + r + 1):
		for x in range(maxi(0, cell.x - r), mini(WorldGen.WIDTH, cell.x + r + 1)):
			var c := Vector2i(x, y)
			if absi(x - cell.x) + absi(y - cell.y) <= r and _is_loot_visible(x, y) and not _is_bad(c):
				loot[c] = true
	if not loot.is_empty():
		var p3 := nav.plan(cell, func(c: Vector2i) -> bool: return loot.has(c), cell.y - r - 2, cell.y + r + 2, r * 6 + 6)
		if not p3.is_empty():
			_tgt = p3.back()
			return p3
	# 3) штрек на разведку (жадный): каждые N рядов — в обе стороны на branch_len
	var every := int(C["branch_every"])
	if every > 0 and cell.y >= 8 and cell.y % every == 0 and int(_branched.get(cell.y, 0)) < 2:
		var n := int(_branched.get(cell.y, 0))
		_branched[cell.y] = n + 1
		var dir := -1 if n == 0 else 1
		var bg := Vector2i(clampi(cell.x + dir * int(C["branch_len"]), 0, WorldGen.WIDTH - 1), cell.y)
		if not _is_bad(bg) and bg != cell:
			var p4 := nav.plan(cell, func(c: Vector2i) -> bool: return c == bg, cell.y - 2, cell.y + 3, 60)
			if not p4.is_empty():
				_branch_goal = bg
				_tgt = bg
				return p4
	# 4) вниз: на ряд глубже, чем самый глубокий ряд этой ходки
	_goal_row = maxi(_goal_row, cell.y)
	_tgt_row = _goal_row
	var gr2 := _tgt_row
	return nav.plan(cell, func(c: Vector2i) -> bool: return c.y > gr2 and not _is_bad(c), cell.y - 6, gr2 + 6, 160)


## Клавиши для шага c → n пути. Вниз в пустоту — к центру клетки и упасть, вниз в породу —
## «вниз»; вверх — тяга с подруливанием к центру; вбок — направление (копка вбок сама
## начнётся у стены), а в воздухе ещё и тяга, чтобы не просесть ниже ряда.
func _keys_for_step(c: Vector2i, n: Vector2i) -> Array:
	var off: float = player.x - (float(c.x) + 0.5)
	var t := world.get_tile(n.x, n.y)
	if n.y > c.y:
		if t == TileTypes.Type.EMPTY:
			return [] if absf(off) < 0.12 else [KEY_A if off > 0.0 else KEY_D]
		return [KEY_S]
	if n.y < c.y:
		var k: Array = [KEY_W]
		if absf(off) > 0.12:
			k.append(KEY_A if off > 0.0 else KEY_D)
		return k
	var k2: Array = [_dirkey(n.x - c.x)]
	if not player.on_ground and world.get_tile(c.x, c.y + 1) == TileTypes.Type.EMPTY \
			and player.y > float(c.y) + 0.55:
		k2.append(KEY_W)
	return k2


func _dirkey(d: int) -> Key:
	return KEY_D if d > 0 else KEY_A


func _nav_dig_cost(x: int, y: int) -> int:
	if x < 0 or x >= WorldGen.WIDTH or world.is_house_locked_cell(x, y):
		return -1
	var t := world.get_tile(x, y)
	if t == TileTypes.Type.LAVA:
		return 14 if _lava_ok() else -1
	if not (TileTypes.is_diggable(t) and player._can_dig(t)):
		return -1
	if _is_bad(Vector2i(x, y)):
		return 30
	return 4 if t == TileTypes.Type.STONE else 2


func _is_loot_visible(x: int, y: int) -> bool:
	if x < 0 or x >= WorldGen.WIDTH or y < 1:
		return false
	if main.fog.get_state(x, y) != FogOfWar.State.FULL:
		return false
	var t := world.get_tile(x, y)
	if TileTypes.is_ore(t) and MineralMap.is_loot(t):
		return true
	# тайник (ветка aaa-mechanics): сундук виден в полном обзоре, как руда
	return t != TileTypes.Type.EMPTY and _chest_at(Vector2i(x, y))


func _chest_at(c: Vector2i) -> bool:
	if _mech == null:
		_mech = main.get_node_or_null("MechDirector")
		if _mech == null:
			_mech = self   # нет механики — больше не искать
	if _mech == self or not _mech.has_method("chest_at"):
		return false
	return not (_mech.chest_at(c) as Dictionary).is_empty()


func _diggable(x: int, y: int) -> bool:
	if x < 0 or x >= WorldGen.WIDTH:
		return false
	var t := world.get_tile(x, y)
	if t == TileTypes.Type.EMPTY:
		return true
	if t == TileTypes.Type.LAVA and not _lava_ok():
		return false
	return TileTypes.is_diggable(t) and player._can_dig(t)


func _lava_ok() -> bool:
	return Heat.can_dig_lava() and GameState.hp > Heat.lava_cell_cost_hp() * 2.5


## Подъём: тяга ранца вверх по стволу; потолок — в сторону к ближайшей открытой колонке.
func _ascend() -> void:
	_activity = "ascend"
	var why := _should_return()
	if not player.has_backpack():
		T.finding("P0", "no_backpack", "под землёй без ранца: подняться нечем", _sim, {"dump": _dump()})
		await _wait(5.0)
		return
	var t0 := _sim
	var d0: int = player.cell_y()
	var best_y: float = player.y
	var best_t := _sim
	var mouth_x := float(world.tunnel_mouth().x)
	var up_cell := Vector2i(-99, -99)
	var up_path: Array = []
	var up_top := -1
	while not _stop and GameState.is_alive and not GameState.house_is_indoors and not _busy_story():
		if player.y < 1.6 and absf(player.x - (mouth_x + 0.5)) < 1.2:
			# Устье: долететь выше кромки бетона и боком на огород, не упав обратно.
			if player.on_ground and player.y < 0.9 and player.x < mouth_x - 0.3:
				bot.release_all()
				_note_ascent(d0, t0)
				if T.in_trip():
					T.trip_end(_sim, why, _pack_value(), GameState.get_total_weight())
				if _shots_on and GameState.get_total_weight() >= GameState.get_max_carry_kg() * 0.8:
					_shot("surface_full_pack")
				var door := HouseConfig.door_cell()
				if await _walk_to_x(float(door.x) + 0.5, 40.0):
					await _enter_door()
				return
			var k2: Array = [KEY_W] if player.y > 0.45 and player.x > mouth_x - 0.5 else []
			if player.y < 0.75 or player.x < mouth_x - 0.3:
				k2.append(KEY_A)
			bot.hold(k2)
			await _step()
			continue
		if player.y < 1.0:
			bot.release_all()
			_note_ascent(d0, t0)
			return   # уже на поверхности (не у устья) — дальше решает _surface
		if player.y < best_y - 0.5:
			best_y = player.y
			best_t = _sim
		elif _sim - best_t > 40.0:
			T.finding("P0", "ascent_stuck", "подъём: 40 с без высоты на глубине %d" % player.cell_y(), _sim,
				{"dump": _dump()}, str(player.cell_y() / 50))
			best_t = _sim
			best_y = player.y
			await _unstick_ascent()
		var cell := Vector2i(player.cell_x(), player.cell_y())
		if cell != up_cell:
			up_cell = cell
			# цель — на 12 рядов выше (у тоннеля — сам тоннель), держится до достижения; по пустоте
			# дешевле, копать — можно
			if up_top < 0 or cell.y <= up_top:
				up_top = maxi(1, cell.y - 12)
			var top := up_top
			up_path = nav.plan(cell, func(c: Vector2i) -> bool: return c.y <= top, top, cell.y + 4, 200)
		var keys: Array = _ascend_keys()
		if up_path.size() >= 2:
			# вбок под потолком тягу не держим: герой упирался бы макушкой в соседнюю породу
			keys = _keys_for_step(cell, up_path[1])
		bot.hold(keys)
		await _step()
	bot.release_all()
	if _sim - t0 > 0.0:
		pass


func _ascend_keys() -> Array:
	var cx: int = player.cell_x()
	var cy: int = player.cell_y()
	var above_free := world.get_tile(cx, cy - 1) == TileTypes.Type.EMPTY
	if above_free:
		var off: float = player.x - (float(cx) + 0.5)
		if absf(off) > 0.1:
			return [KEY_W, KEY_A if off > 0.0 else KEY_D]
		return [KEY_W]
	# Потолок: ближайшая колонка с пустотой сверху, до которой можно дойти по ряду.
	for d in range(1, 8):
		for dir in [-1, 1]:
			var x: int = cx + dir * d
			if x < 0 or x >= WorldGen.WIDTH:
				continue
			var ok := true
			var xx: int = cx + dir
			while xx != x + dir:
				if world.get_tile(xx, cy) != TileTypes.Type.EMPTY:
					ok = false
					break
				xx += dir
			if ok and world.get_tile(x, cy - 1) == TileTypes.Type.EMPTY:
				return [KEY_W, KEY_D if dir > 0 else KEY_A]
	# Ни одной: копать в сторону ствола устья (вверх копать нельзя).
	var back := 1 if SHAFT_X > cx else -1
	if cx == SHAFT_X:
		back = 1
	return [KEY_D if back > 0 else KEY_A]


## Подъём от глубины d0 до поверхности за (_sim - t0) игровых секунд: по ним детектор
## death_lift оценивает, сколько бот на самом деле летит с глубины смерти.
func _note_ascent(d0: int, t0: float) -> void:
	if d0 >= 30 and _sim - t0 > 0.5:
		_ascents.append([d0, snappedf(_sim - t0, 0.1)])
		if _ascents.size() > 40:
			_ascents.pop_front()


## Сколько игровых секунд бот летел бы наверх с глубины depth: медиана «секунд на клетку» его
## последних подъёмов с 30+ клеток. Нет истории — прямой полёт на текущем ранце (DeathRide).
func _ascent_estimate(depth: int) -> float:
	var per: Array = []
	for a in _ascents:
		per.append(float(a[1]) / maxf(1.0, float(a[0])))
	if per.is_empty():
		return DeathRide.flight_seconds(depth, GameState.current_gear, false)
	per.sort()
	return float(per[per.size() / 2]) * float(depth)


## Монет в игровую секунду за весь прогон (продажи; для death_lift — во что обходится время).
func _income_rate() -> float:
	return float(_earned) / maxf(60.0, _sim)


## Эксперимент «смерть вместо подъёма» (--die-lift; раунд 5, слова владельца: «смерть не должна
## быть удобным способом копать вниз и потом, чтобы не лететь, — умирать»). Пора наверх, рюкзак
## почти пуст, глубоко — бот не летит, а «взлетает и отпускает тягу»: 4 с на взлёт, затем
## смертельный удар (как падение с 32+ клеток). Цену (рюкзак, плата, поездка скорой) считает
## детектор death_lift; итог эксперимента — метрика цели против прогона без флага.
func _maybe_die_lift() -> bool:
	if not _die_lift or _depth() < 60 or _pack_value() >= _die_lift_pack or not StoryState.has_flag("gold_sold"):
		return false
	_activity = "die_lift"
	_no_brake = true
	T.event(_sim, "die_lift", "смерть вместо подъёма с глубины %d (рюкзак %d монет)" % [_depth(), _pack_value()])
	T.event_counts["die_lift"] = int(T.event_counts.get("die_lift", 0)) + 1
	bot.release_all()
	await _wait(4.0)
	if GameState.is_alive:
		GameState.take_damage(1e6, "fall")
	await _step()
	return true


func _unstick_ascent() -> void:
	bot.release_all()
	await _wait(0.5)
	bot.hold([KEY_A])
	await _wait(0.4)
	bot.hold([KEY_D])
	await _wait(0.4)
	bot.release_all()


# ---------------------------------------------------------------------------
# Дом: продажа, верстак, покупки у двери, еда, сон, прокачка, задания
# ---------------------------------------------------------------------------

func _home_visit() -> void:
	_activity = "home"
	_home_visits += 1
	if T.in_trip():
		T.trip_end(_sim, "home", _pack_value(), GameState.get_total_weight())
	var t0 := _sim
	await _frames_n(2)
	if not await _go_room("hall"):
		await _wait(1.0)
		if GameState.house_is_indoors and not await _go_room("hall"):
			T.finding("P0", "house_nav", "не выйти в прихожую", _sim, {"dump": _dump()})
			_stop = true
			return
	_sell()
	if not _reserved_in_pack().is_empty() or _any_craftable() or _fuel_raw_in_pack():
		# склад и верстак — в мастерской (ГДД §14): несём туда то, что копим на проект
		if await _go_room("workshop"):
			_stash_fuel_raw()
			_workbench()
		await _go_room("hall")
	else:
		_workbench()
	await _shop()
	_spend_skills()
	_claim_meta()
	if bool(G.get("quests", false)):
		await _do_quests()
	if bool(G.get("screens", false)) and (_home_visits % 5 == 2 or (_short and _home_visits == 1)):
		await _visit_screens()
	if GameState.hunger < float(C["eat_below"]) or _food_in_pack() < int(C["food_stock"]) \
			or (_hp_low() and GameState.hunger < 60.0):
		await _order_and_take_food(GameState.hunger < float(C["eat_below"]) or _hp_low())
	# сон лечит (раунд 4): раненый ложится и с полной бодростью
	if (GameState.stamina < float(C["sleep_below"]) or _hp_low()) and not _stop:
		await _sleep()
	if _stop or not GameState.house_is_indoors:
		return
	await _go_room("hall")
	_heal_at_home()   # после сна: если HP всё ещё мало — аптечка, потом таблетка
	if _sim >= _next_cp and not _stop:
		_next_cp = _sim + _cp_sec
		_checkpoint()
	if _sim >= _next_session and not _stop:
		await _session_restart()
		return   # новая сессия начинается у дома снаружи — дальше решает основной цикл
	_from_house = true
	if not await _house_press("exit_door"):
		await _wait(1.0)
		if GameState.house_is_indoors and not await _house_press("exit_door"):
			T.finding("P0", "house_exit", "из дома не выйти", _sim, {"dump": _dump()})
			_stop = true
	await _frames_n(3)
	if _sim - t0 > 120.0:
		T.finding("P2", "slow_home", "визит домой занял %.0f с" % (_sim - t0), _sim)


## Продать всё, кроме еды, топлива и того, что копится на проект верстака.
func _sell() -> void:
	var keep := _reserved_materials()
	var items: Dictionary = {}
	for row in ShopService.sellable_stacks():
		var id := String(row["id"])
		if HouseConfig.is_food(id) or id == FuelTank.block_item():
			continue
		if (id == "peat" or id == "coal") and _fuel_tool() != "":
			continue   # сырьё для станции: бак бура
		var n := int(row["count"]) - int(keep.get(id, 0))
		if n > 0:
			items[id] = n
	if items.is_empty():
		return
	var r := ShopService.sell(items)
	if bool(r["ok"]):
		T.sales.append({"t": snappedf(_sim, 0.1), "coins": int(r["coins"]), "count": int(r["count"])})
		T.mark("first_sale", _sim)
		T.event(_sim, "sale", "продано на %d" % int(r["coins"]), int(r["coins"]) >= 200)


## Материалы под ближайший незавершённый проект верстака (ручной бур, бурмобиль, скважина).
## Рецепты-проекты в порядке стратегии (G.projects: бур → бурмобиль у «глубокого», скважина у «магната»);
## пустой список — ничего не копить (коллекционер продаёт всё). Без стратегии — порядок каталога.
func _project_recipes() -> Array:
	var all: Array = ShopCatalog.recipes()
	if not G.has("projects"):
		return all
	var out: Array = []
	for want in G["projects"]:
		for r in all:
			if String(r.get("id", "")) == String(want) or String(r.get("output", {}).get("id", "")) == String(want):
				out.append(r)
	return out


func _reserved_materials() -> Dictionary:
	var keep: Dictionary = {}
	for r in _project_recipes():
		var kind := String(r.get("kind", ""))
		if not ["tool", "machine"].has(kind):
			continue
		if not ShopService.is_recipe_unlocked(String(r["id"])):
			continue
		var out_id := String(r["output"]["id"])
		if (kind == "tool" and GameState.owns_tool(out_id)) or (kind == "machine" and GameState.well_level > 0):
			continue
		for id in r["inputs"].keys():
			var need := int(r["inputs"][id]) - HouseStorage.count(String(id))
			if need > 0:
				keep[String(id)] = int(keep.get(String(id), 0)) + need
				# материал, который не копают, а плавят (бронза из металлолома), — копим сырьё
				for r2 in ShopCatalog.recipes():
					if String(r2.get("kind", "")) == "item" and String(r2["output"]["id"]) == String(id):
						var per := maxi(1, int(r2["output"]["count"]))
						for in_id in r2["inputs"].keys():
							keep[String(in_id)] = int(keep.get(String(in_id), 0)) + int(ceil(float(need) / per)) * int(r2["inputs"][in_id])
		break   # копим на один проект за раз — как человек
	return keep


func _workbench() -> void:
	for r in ShopCatalog.recipes():
		var rid := String(r.get("id", ""))
		var kind := String(r.get("kind", ""))
		if not ShopService.is_recipe_unlocked(rid):
			continue
		if ShopService.is_project(rid):
			var inv := ShopService.invest(rid)
			if bool(inv.get("ok", false)):
				T.event(_sim, "invest", "%s: %s" % [rid, str(inv.get("moved", {}))], false)
		if kind == "item":
			# Бронза под проект и топливо, если бак есть.
			var out_id := String(r["output"]["id"])
			var want := false
			if out_id == "bronze" and int(_reserved_or_need("bronze")) > 0:
				want = true
			if out_id == FuelTank.block_item() and _fuel_tool() != "":
				want = FuelTank.in_pack() < 6
			var n := 0
			if want and ShopService.can_craft(rid) and _craft_qty_args() >= 2:
				# ползунок количества (ветка craft-qty, раунд 4): одна сделка на N штук — проверяем, что пришло N
				var need := clampi(int(_reserved_or_need(out_id)) if out_id == "bronze" else 6, 1, 40)
				var have0 := GameState.get_item_count(out_id) + HouseStorage.count(out_id)
				var ss = load("res://scripts/shop/shop_service.gd")
				if _has_static(ss, "max_craft"):
					need = mini(need, int(ss.call("max_craft", rid)))   # верх ползунка: пачка проходит целиком или никак
				var rq: Dictionary = ss.call("craft", rid, need) if need >= 1 else {}
				var got := GameState.get_item_count(out_id) + HouseStorage.count(out_id) - have0
				if bool(rq.get("ok", false)):
					n = need
					T.mark("craft_qty_used", _sim)
					var per := maxi(1, int(r["output"]["count"]))
					if got != need * per and got > 0:
						T.finding("P1", "craft_qty", "заказано %d × «%s», пришло %d (ждали %d)" % [need, rid, got, need * per], _sim, {}, rid)
					elif got <= 0:
						T.finding("P1", "craft_qty", "крафт %d × «%s» сказал «готово», а предметов не прибавилось" % [need, rid], _sim, {}, rid)
			while want and ShopService.can_craft(rid) and n < 40:
				ShopService.craft(rid)
				n += 1
			if n > 0:
				T.event(_sim, "craft", "%s ×%d" % [rid, n], false)
			continue
		if ShopService.can_craft(rid):
			var res := ShopService.craft(rid)
			if bool(res.get("ok", false)):
				T.mark("craft:" + rid, _sim)
				T.event(_sim, "craft", rid)
				_shot("craft_" + rid)
	var tool := _fuel_tool()
	if tool != "":
		var n2 := FuelTank.refuel(tool, "pack")
		n2 += FuelTank.refuel(tool, "storage")
		if n2 > 0:
			T.event(_sim, "refuel", "%s +%d" % [tool, n2], false)
			T.mark("first_refuel", _sim)
	_goal_workbench()


## Верстак по стратегии: костюм жары, снаряжение боя, ступени скважины и баков.
func _goal_workbench() -> void:
	if bool(G.get("suits", false)) and GameState.max_depth_reached >= 1500:
		var r: Dictionary = Heat.craft_suit()
		if bool(r.get("ok", false)):
			T.mark("suit_%d" % Heat.suit_tier(), _sim)
			T.event(_sim, "suit", String(r.get("message", "")))
	if bool(G.get("combat_gear", false)) and GameState.max_depth_reached >= 2500:
		for id in CombatData.craftable_ids():
			if CombatService.can_craft(String(id)):
				var c: Dictionary = CombatService.craft(String(id))
				if bool(c.get("ok", false)):
					T.mark("gear:" + String(id), _sim)
					T.event(_sim, "combat_gear", String(id))
	if bool(G.get("well_upgrade", false)) and GameState.well_level > 0:
		var w: Dictionary = IdleWell.upgrade()
		if bool(w.get("ok", false)):
			T.mark("well_level_%d" % GameState.well_level, _sim)
			T.event(_sim, "well", "скважина: уровень %d" % GameState.well_level)
	for t in ["hand_drill", "drill_rig"]:
		if GameState.owns_tool(t) and FuelTank.uses_fuel(t) and G.has("projects") and (G["projects"] as Array).has(t):
			var u: Dictionary = FuelTank.upgrade(t)
			if bool(u.get("ok", false)):
				T.event(_sim, "tank", "бак %s: уровень %d" % [t, FuelTank.level(t)])


## Сколько аргументов у ShopService.craft (2+ — есть количество: ветка craft-qty).
func _craft_qty_args() -> int:
	if _craft_args < 0:
		_craft_args = 1
		var ss: Script = load("res://scripts/shop/shop_service.gd")
		for m in ss.get_script_method_list():
			if String(m.get("name", "")) == "craft":
				_craft_args = (m.get("args", []) as Array).size()
	return _craft_args


## Режим жадности (ветка greed, раунд 4): имени API заранее не знаем — пробуем вероятные.
func _greed_active() -> bool:
	if _mech == null or _mech == self:
		_chest_at(Vector2i(-1, -1))   # найдёт MechDirector
	var objs: Array = [player]
	if _mech != null and _mech != self:
		objs.push_front(_mech)
	for o in objs:
		for mname in ["is_greed_active", "greed_active", "is_greed"]:
			if o.has_method(mname):
				return bool(o.call(mname))
		for prop in ["greed_active", "greed"]:
			if prop in o:
				var v = o.get(prop)
				if v is bool:
					return v
	return false


## Торф и уголь для станции — на склад, а не в рюкзак (раунд 5, ветка peat): за пластом 450 торфа
## ~4 на ряд, и бот, носивший всё сырьё в рюкзаке до визита на станцию (а та — только при баке
## ниже 60%), забивал рюкзак торфом до порога возврата: 51 кг из 60 — и ходки кончались, не
## начавшись (сид 7, deep и achiever). Станция перегоняет и со склада (FuelRefinery.held).
func _fuel_raw_in_pack() -> bool:
	return _fuel_tool() != "" and (GameState.get_item_count("peat") > 0 or GameState.get_item_count("coal") > 0)


func _stash_fuel_raw() -> void:
	if _fuel_tool() == "":
		return
	for raw in ["peat", "coal"]:
		var n := HouseStorage.put(raw, GameState.get_item_count(raw))
		if n > 0:
			T.event(_sim, "stash", "%s ×%d на склад" % [raw, n], false)


func _reserved_in_pack() -> Dictionary:
	var out: Dictionary = {}
	var keep := _reserved_materials()
	for id in keep.keys():
		if GameState.get_item_count(String(id)) > 0:
			out[id] = mini(int(keep[id]), GameState.get_item_count(String(id)))
	return out


func _any_craftable() -> bool:
	for r in ShopCatalog.recipes():
		if ["tool", "machine"].has(String(r.get("kind", ""))) and ShopService.can_craft(String(r["id"])):
			return true
	return false


func _reserved_or_need(id: String) -> int:
	return int(_reserved_materials().get(id, 0))


func _fuel_tool() -> String:
	for t in ["drill_rig", "hand_drill"]:
		if GameState.owns_tool(t) and FuelTank.uses_fuel(t):
			return t
	return ""


## Покупки у входной двери: плитка витрины → карточка → «Купить» (как человек), а если
## интерфейс не дал — та же логика напрямую с находкой. Правило места проверяет игра.
func _shop() -> void:
	var targets := _purchase_targets()
	if targets.is_empty() and not _shots_on:
		return
	_activity = "shop"
	if not await _house_press("open_shop"):
		_activity = "home"
		return
	await _frames_n(3)
	var ui := ShopUI.instance
	if ui == null or not ui.is_open():
		T.finding("P1", "shop_open", "«Заказать» не открыл витрину", _sim)
		_activity = "home"
		return
	if _shots_on and _home_visits % 6 == 1:
		ui._set_tab(ShopUI.TAB_PICKS, false)
		await _frames_n(4)
		await _shot("shop_picks")
	for tgt in targets:
		var before := GameState.coins
		var ok := await _ui_buy(ui, String(tgt["tab"]), String(tgt["ref"]), String(tgt["kind"]))
		if not ok:
			var r: Dictionary = ShopService.buy_tool(tgt["ref"]) if tgt["kind"] == "tool" else ShopService.buy_gear(tgt["ref"])
			ok = bool(r.get("ok", false))
			if not ok:
				T.event(_sim, "buy_fail", "%s: %s" % [tgt["ref"], r.get("message", "")], false)
		if ok:
			var price := Balance.get_tool_cost_coins(String(tgt["ref"])) if tgt["kind"] == "tool" else Balance.get_gear_cost_coins(String(tgt["ref"]))
			T.purchases.append({"t": snappedf(_sim, 0.1), "id": tgt["ref"], "kind": tgt["kind"], "price": price, "coins_before": before})
			T.mark("buy:" + String(tgt["ref"]), _sim)
			_check_pointless(String(tgt["kind"]), String(tgt["ref"]))
			_owned_since[String(tgt["ref"])] = _sim
	ui.close()
	await _frames_n(2)
	_activity = "home"


func _ui_buy(ui: ShopUI, tab: String, ref: String, kind: String) -> bool:
	ui._set_tab(tab, false)
	await _frames_n(3)
	var tile: ShopTile = null
	for key in ui._tiles.keys():
		var t: ShopTile = ui._tiles[key]
		if t != null and String(t.offer.get("ref", "")) == ref and String(t.offer.get("kind", "")) == kind:
			tile = t
	if tile == null:
		_ui_buy_fail += 1
		T.finding("P1", "shop_tile", "на вкладке %s нет плитки %s/%s" % [tab, kind, ref], _sim, {}, ref)
		return false
	tile.pressed.emit()
	await _frames_n(3)
	if ui._card == null or ui._card_ok == null:
		T.finding("P1", "shop_card", "плитка %s не открыла карточку (состояние %s)" % [ref, tile.offer.get("state", "")], _sim, {}, ref)
		return false
	if _shots_on and not T.milestones.has("shot_card"):
		T.mark("shot_card", _sim)
		await _shot("shop_card_" + ref)
	ui._card_ok.pressed.emit()
	await _frames_n(3)
	var owned := GameState.owns_tool(ref) if kind == "tool" else GameState.has_gear(ref)
	if not owned:
		T.finding("P1", "shop_confirm", "«Купить» в карточке %s не купил" % ref, _sim, {}, ref)
	return owned


## Что купить сейчас: кирки и ранцы за монеты, по характеру — следующая ступень или лучшая по карману.
func _purchase_targets() -> Array:
	var out: Array = []
	var budget := GameState.coins - int(C["reserve"])
	# кирки
	var cur_speed := Balance.get_tool_speed_multiplier(GameState.current_tool)
	var picks: Array = []
	for tool_id in Balance.get_tools_in_line("pickaxe"):
		if GameState.owns_tool(tool_id) or Balance.tool_needs_materials(tool_id):
			continue
		var price := Balance.get_tool_cost_coins(tool_id)
		if price <= 0 or Balance.get_tool_speed_multiplier(tool_id) <= cur_speed:
			continue
		picks.append({"ref": tool_id, "kind": "tool", "tab": ShopUI.TAB_PICKS, "price": price})
	# ранцы
	var gears: Array = []
	for gear_id in Balance.get_gear_ids():
		if GameState.has_gear(gear_id):
			continue
		if Balance.get_gear_fly_multiplier(gear_id) <= Balance.get_gear_fly_multiplier(GameState.current_gear):
			continue
		var gp := Balance.get_gear_cost_coins(gear_id)
		if gp > 0:
			gears.append({"ref": gear_id, "kind": "gear", "tab": ShopUI.TAB_PICKS, "price": gp})
	for line in [gears, picks]:
		line.sort_custom(func(a, b): return int(a["price"]) < int(b["price"]))
		if line.is_empty():
			continue
		var pick: Dictionary = {}
		if String(C["buy"]) == "best":
			for o in line:
				if int(o["price"]) <= budget:
					pick = o
		elif int(line[0]["price"]) <= budget:
			pick = line[0]
		if not pick.is_empty():
			out.append(pick)
			budget -= int(pick["price"])
	return out


func _check_pointless(kind: String, ref: String) -> void:
	# Ступень, купленная, пока предыдущая служила меньше 3 минут, — деньги почти на ветер.
	for id in _owned_since.keys():
		var same_kind := (kind == "tool" and Balance.get_tools_in_line("pickaxe").has(id)) \
			or (kind == "gear" and Balance.get_gear_ids().has(id))
		if same_kind and id != ref and _sim - float(_owned_since[id]) < 180.0:
			T.finding("P2", "short_lived", "%s прослужил %.0f с до покупки %s" % [id, _sim - float(_owned_since[id]), ref],
				_sim, {}, id)


func _food_in_pack() -> int:
	var n := 0
	for e in HouseFood.food_in_inventory():
		n += int(e["count"])
	return n


## Еда: заказ у двери → курьер → «Забрать» → съесть (если голоден) или с собой.
func _order_and_take_food(eat: bool) -> void:
	if not GameState.house_is_indoors:
		return
	await _go_room("hall")
	var pick := ""
	var cheapest := 1 << 30
	for item in HouseConfig.delivery_menu():
		var id := String(item.get("id", ""))
		if not HouseConfig.is_portable(id):
			continue
		var chk := HouseFood.can_order(id)
		if not bool(chk.get("ok", false)):
			continue
		var price := 0 if bool(chk.get("free", false)) else int(chk.get("price", 0))
		# голодный берёт сытное, на запас — дешёвое
		var score := price - (int(HouseConfig.food_hunger_percent(id)) * 3 if eat else 0)
		if score < cheapest:
			cheapest = score
			pick = id
	if pick == "":
		if eat and _food_in_pack() == 0:
			T.finding("P2", "no_food", "голоден (%.0f%%), а еды не купить: монет %d" % [GameState.hunger, GameState.coins], _sim)
		return
	var chk2 := HouseFood.can_order(pick)
	var paid := 0 if bool(chk2.get("free", false)) else int(chk2.get("price", 0))
	var order := HouseSystem.order_food(pick)
	if not bool(order.get("ok", false)):
		T.event(_sim, "food_fail", String(order.get("message", "")), false)
		return
	T.mark("first_food_order", _sim)
	var t0 := _sim
	while HouseFood.food_at_door_count() == 0 and _sim - t0 < HouseConfig.delivery_seconds() * 3.0 + 5.0 and not _stop:
		await _step()
	if HouseFood.food_at_door_count() == 0:
		T.finding("P1", "delivery", "курьер не привёз еду за %.0f с" % (_sim - t0), _sim)
		return
	if not await _house_press("take_delivery"):
		return
	T.meals.append({"t": snappedf(_sim, 0.1), "id": pick, "where": "order", "price": paid,
		"hunger_before": snappedf(GameState.hunger, 0.1)})
	if eat:
		var id := HouseFood.best_food_for_now()
		if id != "":
			_eat_tracked(id, "home")
			T.event(_sim, "eat", "съел %s дома" % id, false)


func _sleep() -> void:
	_activity = "sleep"
	if not await _go_room("bedroom"):
		_activity = "home"
		return
	var before := GameState.stamina
	var hp_before := GameState.hp
	if not await _house_press("sleep"):
		_activity = "home"
		return
	var t0 := _sim
	await _frames_n(3)
	if _shots_on and T.sleeps.is_empty():
		await _shot("sleep")
	while _view().is_sleeping() and _sim - t0 < 60.0 and not _stop:
		await _step()
	await _frames_n(3)
	if _view().forced_mode() != "":
		_view()._on_forced_pressed()
		await _frames_n(3)
	T.sleeps.append({"t": snappedf(_sim, 0.1), "before": snappedf(before, 0.1), "after": snappedf(GameState.stamina, 0.1),
		"sec": snappedf(_sim - t0, 0.1), "hp_before": snappedf(hp_before, 0.1), "hp_after": snappedf(GameState.hp, 0.1)})
	T.mark("first_sleep", _sim)
	if GameState.hp > hp_before + 0.5:
		_heal_seen = true
		T.mark("first_heal_by_sleep", _sim)
		T.event(_sim, "heal", "сон: HP %.0f → %.0f" % [hp_before, GameState.hp])
	await _check_heal_rule(hp_before)
	if GameState.stamina <= before and GameState.hp <= hp_before:
		var plan := HouseSleep.plan(before, GameState.hunger)
		if not bool(plan.get("ok", true)):
			# отказ по правилу сна (голодным не уснёшь / бодрость почти полная) — не баг, а событие
			T.event(_sim, "sleep_refused", String(plan.get("reason", "")))
		else:
			T.finding("P1", "sleep", "сон не прибавил бодрости (%.0f → %.0f)" % [before, GameState.stamina], _sim)
	_activity = "home"
	await _go_room("hall")


## Правило владельца (раунд 4): «при полном сне и еде здоровье восстанавливается до 90–100%».
## После полного сна доедаем до сытости (что есть в рюкзаке) и сверяем HP — с допуском 85%.
func _check_heal_rule(hp_before: float) -> void:
	if GameState.stamina < 95.0 or hp_before >= GameState.get_max_hp() * 0.85:
		return
	var guard := 0
	while GameState.hunger < 90.0 and HouseFood.best_food_for_now() != "" and guard < 4:
		guard += 1
		_eat_tracked(HouseFood.best_food_for_now(), "rule")
	if GameState.hunger >= 85.0 and GameState.hp < GameState.get_max_hp() * 0.85:
		T.finding("P1", "heal_rule", "после полного сна и еды HP %.0f%% (было %.0f%%), а по правилу — 90–100%%" % [
			100.0 * GameState.hp / GameState.get_max_hp(), 100.0 * hp_before / GameState.get_max_hp()], _sim, {}, "heal_rule")
	else:
		T.mark("heal_rule_ok", _sim)


## Съесть с учётом HP: еда лечит (раунд 4) — фиксируем прибавку.
func _eat_tracked(id: String, where: String) -> void:
	var hp0 := GameState.hp
	var h0 := GameState.hunger
	HouseFood.eat(id)
	if GameState.hp > hp0 + 0.5:
		_heal_seen = true
		T.mark("first_heal_by_food", _sim)
	T.meals.append({"t": snappedf(_sim, 0.1), "id": id, "where": where, "hunger_before": snappedf(h0, 0.1),
		"hp_gain": snappedf(GameState.hp - hp0, 0.1)})


## Копия сейва в <out>/cp_<минута>/xdg/… — с неё ночной сценарий снимает кадры настоящим рендером
## (tools/bot_night.sh → RESUME=… SHOTS=1). Структура повторяет XDG_DATA_HOME.
func _checkpoint() -> void:
	SaveSystem.save_game()
	var ud := OS.get_user_data_dir()
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if xdg.is_empty() or not ud.begins_with(xdg):
		return
	var dst := _out.path_join("cp_%04d" % int(_sim / 60.0)).path_join("xdg") + ud.substr(xdg.length())
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(ud)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".json") or f.ends_with(".bak") or f.ends_with(".cfg"):
			DirAccess.copy_absolute(ud.path_join(f), dst.path_join(f))
	T.event(_sim, "checkpoint", "сейв для снимков: глубина %d" % GameState.max_depth_reached, false)


## «Закрыл игру и вернулся завтра»: сейв, освобождение main.tscn, мета-часы на сутки
## вперёд (ежедневная награда и задания), новая main.tscn с загрузкой. Прогресс обязан
## пережить это без потерь — иначе P0.
func _session_restart() -> void:
	_activity = "session"
	_sessions += 1
	_next_session = _sim + _session_min * 60.0
	var snap := {"coins": GameState.coins, "max_depth": GameState.max_depth_reached, "tool": GameState.current_tool,
		"gear": GameState.current_gear, "level": GameState.level, "artifacts": GameState.collected_artifacts.size(),
		"seen": GameState.story_seen.size(), "items": GameState.inventory.duplicate(), "dollars": GameState.dollars}
	bot.release_all()
	SaveSystem.save_game()
	main.free()
	await get_tree().process_frame
	# Новый процесс начал бы с чистого GameState; то, что в сейв не пишется (герой в доме),
	# обнуляем сами — как при настоящем запуске.
	GameState.house_is_indoors = false
	var now_unix := int(Time.get_unix_time_from_system())
	MetaClock.override_unix = maxi(MetaClock.override_unix, now_unix) + MetaClock.DAY
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames_n(4)
	player = main.player
	world = main.world
	hud = main.hud
	director = main.find_child("StoryDirector", true, false)
	house = HouseSystem.instance
	nav.world = world
	_death_card = null
	_mech = null
	if bot is Stick:
		bot.release_all()
		bot.hud = hud
	_connect_player()
	var after := {"coins": GameState.coins, "max_depth": GameState.max_depth_reached, "tool": GameState.current_tool,
		"gear": GameState.current_gear, "level": GameState.level, "artifacts": GameState.collected_artifacts.size(),
		"seen": GameState.story_seen.size(), "items": GameState.inventory.duplicate(), "dollars": GameState.dollars}
	var lost: Array = []
	for d in [snap, after]:
		var norm: Dictionary = {}
		for id in (d["items"] as Dictionary).keys():
			norm[id] = int(d["items"][id])   # JSON отдаёт числа float — сравниваем как целые
		d["items"] = norm
	for k in snap.keys():
		if k == "coins" or k == "dollars":
			if int(after[k]) < int(snap[k]):
				lost.append("%s %s → %s" % [k, str(snap[k]), str(after[k])])
		elif k == "items":
			# словарь сравниваем по содержимому: после загрузки порядок ключей другой, и str() их различал
			var a: Dictionary = after[k]
			var b: Dictionary = snap[k]
			var same := a.size() == b.size()
			for id in b.keys():
				same = same and a.has(id) and int(a[id]) == int(b[id])
			if not same:
				lost.append("%s %s → %s" % [k, str(snap[k]), str(after[k])])
		elif str(after[k]) != str(snap[k]):
			lost.append("%s %s → %s" % [k, str(snap[k]), str(after[k])])
	T.event(_sim, "session", "перезапуск игры №%d (сейв → загрузка, мета-день +1)" % _sessions)
	if not lost.is_empty():
		T.finding("P0", "save_load", "после перезапуска игры потеряно: " + "; ".join(lost), _sim, {"before": snap, "after": after})
	_activity = "home"


func _heal_at_home() -> void:
	if not _hp_low():
		return
	if String(_view().room_id()) == "hall":
		var before := GameState.hp
		var price := ShopCatalog.good_price(ShopCatalog.good("medkit", "coins"), "coins")
		if bool(ShopService.buy("medkit", "coins").get("ok", false)):
			T.purchases.append({"t": snappedf(_sim, 0.1), "id": "medkit", "kind": "good", "price": price})
			if bool(HouseFood.eat("medkit").get("ok", false)):
				T.event(_sim, "heal", "аптечка: HP %.0f → %.0f" % [before, GameState.hp])
				T.mark("first_medkit", _sim)
				if GameState.hp <= before:
					T.finding("P1", "medkit", "аптечка применена, а HP не выросло (%.0f → %.0f)" % [before, GameState.hp], _sim)
				return
		var r := ShopService.buy("full_restore_pill", "dollars")
		if bool(r.get("ok", false)):
			T.event(_sim, "heal", "таблетка: HP %.0f → %.0f" % [before, GameState.hp])
			T.purchases.append({"t": snappedf(_sim, 0.1), "id": "full_restore_pill", "kind": "good", "price": 0, "dollars": true})
			return
	T.finding("P2", "no_heal", "HP %.0f/%.0f после сна, а лечиться нечем: на аптечку нет монет (%d), на таблетку — долларов (%d)" % [
		GameState.hp, GameState.get_max_hp(), GameState.coins, GameState.dollars], _sim, {}, "no_heal")


## Порядок веток навыков стратегии: только существующие в data/upgrades.json, остальные — в конце
## (новые ветки других агентов, например «Жадность», бот прокачает, даже не зная их имени).
func _skill_order(pref: Array) -> Array:
	var ids: Array = []
	var f := FileAccess.open("res://data/upgrades.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			var br = d.get("branches", [])
			if br is Array:
				for b in br:
					if b is Dictionary and b.has("id"):
						ids.append(String(b["id"]))
			elif br is Dictionary:
				ids = (br as Dictionary).keys()
	var out: Array = []
	for id in pref:
		if ids.is_empty() or ids.has(id):
			out.append(id)
	for id in ids:
		if not out.has(id):
			out.append(id)
	return out


## Метрика успеха стратегии (растёт — цель движется).
func _goal_metric() -> float:
	match String(G.get("metric", "")):
		"max_depth":
			return float(GameState.max_depth_reached)
		"achievements":
			var ach = load("res://scripts/meta/achievements.gd")
			return float(ach.call("done_count")) if ach != null and _has_static(ach, "done_count") else 0.0
		"earned":
			return float(_earned)
		"collection":
			return float(GameState.collected_artifacts.size() * 10 + int(T.event_counts.get("chest_opened", 0)) * 3
				+ int(T.event_counts.get("mastery_star", 0)) + T.minerals_first.size())
		"fight":
			return float(MetaState.counter("monsters") * 10 + GameState.max_depth_reached / 100)
	return 0.0


func _goal_tick() -> void:
	if G.is_empty():
		return
	var m := _goal_metric()
	if m > _metric_best:
		_metric_best = m
		_metric_t = _sim
	elif _sim - _metric_t > float(G.get("stall_min", 45.0)) * 60.0:
		T.finding("P2", "goal_stall", "цель «%s» не растёт %.0f игровых минут (метрика %.0f)" % [goal_name,
			(_sim - _metric_t) / 60.0, m], _sim, {"dump": _dump()}, goal_name)
		_metric_t = _sim
	T.goal_curve.append([snappedf(_sim, 0.1), snappedf(m, 0.1)])


## Очки — по приоритету стратегии: первая не прокачанная до конца ветка, если по карману; если
## дороже, чем есть, но копится за пару уровней, — копим (не тратим на младшую); если ветку не даёт
## требование (новое дерево навыков) — следующая.
func _spend_skills() -> void:
	var guard := 0
	while GameState.skill_points_available > 0 and guard < 40:
		guard += 1
		var spent := false
		for b in C["skills"]:
			var br := Balance.get_upgrade_branch(String(b))
			if br.is_empty() or GameState.get_skill_stage(String(b)) >= int(br.get("stages", 0)):
				continue
			var cost := Balance.get_upgrade_stage_cost(String(b), GameState.get_skill_stage(String(b)) + 1)
			if cost < 0:
				continue
			if GameState.skill_points_available < cost:
				if cost <= GameState.skill_points_available + 3:
					T.mark("skill_saving:" + String(b), _sim)
					break   # копим на приоритетную
				continue
			if GameState.spend_skill_point(String(b)):
				T.event(_sim, "skill", String(b), false)
				T.mark("first_skill", _sim)
				T.mark("skill:" + String(b), _sim)
				spent = true
				break
		if not spent:
			break


## Задания дня, которые копкой сами не закрываются: «поешь N раз», «выспись», «потрать/купи».
## Бот делает их дома, как игрок с открытым списком заданий.
func _do_quests() -> void:
	var qe = load("res://scripts/meta/quest_engine.gd")
	if qe == null or not _has_static(qe, "all_quests"):
		return
	for q in qe.call("all_quests"):
		if not (q is Dictionary) or bool(qe.call("is_done", q)):
			continue
		match String(q.get("event", "")):
			"ate":
				if _food_in_pack() == 0:
					await _order_and_take_food(false)
				var id := HouseFood.best_food_for_now()
				if id == "" and _food_in_pack() > 0:
					id = String(HouseFood.food_in_inventory()[0]["id"])
				if id != "" and GameState.hunger < 99.0:
					_eat_tracked(id, "quest")
					T.event(_sim, "quest_do", "съел ради задания", false)
			"slept":
				if bool(HouseSleep.plan(GameState.stamina, GameState.hunger).get("ok", false)):
					await _sleep()
					await _go_room("hall")
			"spent", "bought":
				await _order_and_take_food(false)
				T.event(_sim, "quest_do", "покупка ради задания", false)


## Коллекционер заглядывает в музей, журнал и дневник (открыть и закрыть, как игрок).
func _visit_screens() -> void:
	_activity = "screens"
	ProgressScreen.open()
	await _frames_n(5)
	if ProgressScreen.is_open():
		T.mark("opened:progress", _sim)
		if _shots_on and not T.milestones.has("shot_progress"):
			T.mark("shot_progress", _sim)
			await _shot("progress_screen")
		ProgressScreen.close_screen()
	else:
		T.finding("P1", "screen_open", "экран прогресса/музея не открылся из дома", _sim, {}, "progress")
	var md = main.get_node_or_null("MechDirector")
	if md != null and md.has_method("open_journal"):
		md.open_journal()
		await _frames_n(5)
		T.mark("opened:journal", _sim)
		for n in main.find_children("*", "", true, false):
			if n.has_method("is_open") and n.has_method("close") and String(n.get_script().resource_path if n.get_script() else "").ends_with("journal_screen.gd") and n.is_open():
				n.close()
	await _frames_n(3)
	_activity = "home"


## Мета-слой: забрать готовые задания (через тот же код, что кнопка «Забрать»).
func _claim_meta() -> void:
	var qe = load("res://scripts/meta/quest_engine.gd")
	if qe == null:
		return
	if not _has_static(qe, "all_quests") or not _has_static(qe, "is_claimable") or not _has_static(qe, "claim"):
		return
	for q in qe.call("all_quests"):
		if q is Dictionary and bool(qe.call("is_claimable", q)):
			var before := GameState.coins
			qe.call("claim", String(q.get("id", "")))
			T.event(_sim, "quest_claim", "%s +%d" % [String(q.get("id", "")), GameState.coins - before])
			T.mark("first_quest_claim", _sim)
	if _has_static(qe, "bonus_ready") and bool(qe.call("bonus_ready")):
		qe.call("claim_bonus")
		T.event(_sim, "quest_bonus", "бонус дня")


static func _has_static(s: Script, method: String) -> bool:
	for m in s.get_script_method_list():
		if String(m.get("name", "")) == method:
			return true
	return false


# ---------------------------------------------------------------------------
# Итоговые проверки: недостижимое, траты, темп
# ---------------------------------------------------------------------------

func _final_checks() -> void:
	_check_lines()
	if _sim < 60.0:
		return
	# Чего так и не случилось из ожидаемого за эту длину.
	var expect := {"first_sale": 900.0, "buy:iron_pickaxe": 1800.0, "depth_50": 1800.0, "depth_100": 3600.0,
		"first_sleep": 5400.0, "depth_500": 10800.0, "depth_1000": 18000.0}
	for k in expect.keys():
		if _sim >= float(expect[k]) and not T.milestones.has(k) and not _stop_early():
			T.finding("P2", "milestone_missing", "за %.0f мин не случилось «%s»" % [_sim / 60.0, k], _sim, {}, k)
	# Доход и следующая цель: сколько ждать до следующей ступени при нынешнем темпе.
	var earned := 0
	for s in T.sales:
		earned += int(s["coins"])
	var rate := earned / maxf(_sim / 3600.0, 0.01)
	T.meta["income_per_hour"] = int(rate)
	var nxt := _next_goal()
	if not nxt.is_empty():
		var lack: int = int(nxt["price"]) - GameState.coins
		T.meta["next_goal"] = {"id": nxt["ref"], "price": nxt["price"], "lack": lack,
			"hours_at_current_rate": snappedf(lack / maxf(rate, 1.0), 0.01)}
		if lack > 0 and lack / maxf(rate, 1.0) > 3.0:
			T.finding("P2", "far_goal", "до %s (%d) при доходе %d/ч ещё %.1f ч игры" % [nxt["ref"], nxt["price"], int(rate),
				lack / maxf(rate, 1.0)], _sim)
	var projects: Array = []
	for r in ShopCatalog.recipes():
		if not ["tool", "machine"].has(String(r.get("kind", ""))):
			continue
		var rid := String(r["id"])
		var chk := ShopService.check_craft(rid) if GameState.house_is_indoors else {}
		var have: Dictionary = {}
		for id in r["inputs"].keys():
			have[id] = "%d/%d" % [HouseStorage.count(String(id)) + GameState.get_item_count(String(id)), int(r["inputs"][id])]
		projects.append({"id": rid, "unlocked": ShopService.is_recipe_unlocked(rid), "unlock_depth": ShopCatalog.unlock_depth(rid),
			"coins": int(r.get("coins", 0)), "materials": have, "done": T.milestones.has("craft:" + rid)})
	T.meta["projects"] = projects
	var spent_food := 0
	for m in T.meals:
		spent_food += int(m.get("price", 0))
	T.meta["coins_earned"] = earned
	T.meta["coins_on_food"] = spent_food
	if earned > 0 and spent_food > earned * 0.25:
		T.finding("P2", "food_cost", "еда съела %d%% дохода" % int(100.0 * spent_food / earned), _sim)


## Реплики катсцен, которые бот видел: сырые ключи перевода, подстановки, мусор.
func _check_lines() -> void:
	var raw := RegEx.new()
	raw.compile("^[a-z0-9_]+\\.[a-z0-9_.]+$")
	var latin := RegEx.new()
	latin.compile("[A-Za-z]{4,}")
	for sid in T.lines.keys():
		for line in T.lines[sid]:
			var t := String(line)
			var why := ""
			if raw.search(t) != null:
				why = "сырой ключ перевода"
			elif t.contains("%s") or t.contains("%d") or t.contains("{") or t.contains("}"):
				why = "неподставленный шаблон"
			elif t.contains("  ") or t.begins_with(" ") or t.ends_with(" "):
				why = "лишние пробелы"
			elif latin.search(t) != null and not t.contains("SOS"):
				why = "латиница в русской реплике"
			if why != "":
				T.finding("P3", "story_text", "%s: «%s» (сцена %s)" % [why, t.left(80), sid], _sim, {}, t.left(40))


func _ach_done() -> int:
	var ach = load("res://scripts/meta/achievements.gd")
	return int(ach.call("done_count")) if ach != null and _has_static(ach, "done_count") else 0


func _stop_early() -> bool:
	return _stop and _sim < _end - 1.0


func _next_goal() -> Dictionary:
	var saved = C["reserve"]
	C["reserve"] = -(1 << 30)
	var t := _purchase_targets()
	C["reserve"] = saved
	var best: Dictionary = {}
	for o in t:
		if best.is_empty() or int(o["price"]) < int(best["price"]):
			best = o
	return best

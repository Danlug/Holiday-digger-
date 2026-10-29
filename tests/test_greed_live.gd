extends Node
## test_greed_live — жадность у живого игрока (жалоба владельца 26.10: «у меня вообще не
## сработала жадность»). Настоящая main.tscn, герой ведётся настоящими клавишами (BotPlayer:
## Input → HUD → Player), рюкзак открывается тапом по кнопке, шаг игры — вручную по 1/60 с.
## Ветка «Жадность» не куплена: жадность обязана быть и без прокачки (3 с, слова владельца).
##
## Что было (поймано этим тестом до исправления): шкала считала 60 клеток подряд, а любая
## пауза дольше 2.5 с обнуляла её целиком. Клетка железной киркой — 1.8 с земля, 5.9 с камень,
## поэтому 60 клеток — 2.5–3 минуты копки без единой паузы; человек с телефоном отрывает палец
## (огляделся, вернулся по штреку, заглянул в рюкзак) — и за 3 минуты жадность не наступала
## ни разу. Сценарий человека ниже — шахта вниз отрезками по 3–6 клеток, между ними палец
## отрывается от стекла на 0.5–3.2 с, каждый третий отрезок — штрек вбок за рудой и назад.
##
## Запуск:  godot --headless --path . res://tests/test_greed_live.tscn [-- --probe]
## --probe — печатать каждую жадность и каждое сгорание шкалы.

const DT := 1.0 / 60.0
const SEED := 20261026
const SHAFT_X := 22
const START_Y := 7

var failures := 0
var total := 0
var probe := false

var main: Node2D
var player
var world: WorldGen
var mech: MechDirector
var bot := BotPlayer.new()
var rng := RandomNumberGenerator.new()

var t := 0.0
var fevers := 0
var fever_times: Array = []
var burns: Array = []           # [секунда, шкала до сгорания, чем был занят]
var _dug_total := 0
var _what := ""                 # чем занят «человек» сейчас (для отчёта о сгорании)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _ready() -> void:
	print("=== test_greed_live ===")
	probe = OS.get_cmdline_user_args().has("--probe")
	await get_tree().process_frame
	await _boot()
	if mech == null:
		check("игра поднялась", false)
		_quit()
		return
	check("ветка «Жадность» не куплена — жадность всё равно есть (3 с)",
		GameState.get_skill_stage("greed") == 0 and is_equal_approx(mech.streak.greed_s, 3.0))
	await _pause_and_backpack()
	await _phone_session(180.0)
	_quit()


func _quit() -> void:
	bot.release_all()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------------------
# Игра «сразу после онбординга», герой на дне своей шахты
# ---------------------------------------------------------------------------

func _boot() -> void:
	for f in ["user://save.json", "user://save.json.bak", "user://records.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	GameState.reset_progress()
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	GameState.world_seed = SEED
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "dud_treasure", "autodig_done", "workshop", "death",
			"backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2"]:
		StoryState.mark_seen(id)
	for f in ["intro_seen", "dud_treasure_found", "autodig_done", "workshop_seen", "gold_taken", "foundation_broken",
			"bars_introduced", "death_seen", "backpack_owned", "robert_seen", "hatch_built", "gold_sold", "food_ordered"]:
		StoryState.set_flag(f)
	GameState.house_tutorial_stage = 2
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 6:
		await get_tree().process_frame
	player = main.player
	world = main.world
	mech = main.get_node_or_null("MechDirector") as MechDirector
	if mech == null:
		return
	# шаг игры — наш: кадр 1/60 с, сколько бы ни шли настоящие кадры headless
	main.set_process(false)
	mech.set_process(false)
	mech.fever_started.connect(func() -> void:
		fevers += 1
		fever_times.append(snappedf(t, 0.1))
		if probe:
			print("  %6.1f с  ЖАДНОСТЬ (%s)" % [t, _what]))
	GameState.game_event.connect(_on_event)
	await _close_popups()
	GameState.grant_tool("rusty_pickaxe")
	GameState.grant_tool("iron_pickaxe")
	GameState.set_current_tool("iron_pickaxe")
	GameState.grant_gear("backpack")
	if HouseSystem.instance != null:
		HouseSystem.instance.robert_finished_garden()
	if world.has_method("unlock_pre_autodig_garden"):
		world.unlock_pre_autodig_garden()
	# шахта от поверхности до START_Y: герой стоит на её дне, дальше копает сам
	for y in range(0, START_Y + 1):
		world.diffs[y * WorldGen.WIDTH + SHAFT_X] = true
	world.mark_changed()
	GameState.house_is_indoors = false
	player.frozen = false
	player.x = float(SHAFT_X) + 0.5
	player.y = float(START_Y) + 0.6
	player.vx = 0.0
	player.vy = 0.0
	for i in 20:
		await _step()


func _on_event(id: StringName, _data: Dictionary) -> void:
	if id == &"dug":
		_dug_total += 1


## Само всплывающее: окно дня мета-слоя (ГДД §19) и музей на первой находке (ГДД §9) —
## человек смотрит и закрывает.
func _close_popups() -> void:
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms) and ms.popup.is_open():
		ms.popup.close()
		for i in 3:
			await get_tree().process_frame
	if ProgressScreen.is_open():
		ProgressScreen.close_screen()
		for i in 20:
			await get_tree().process_frame


# ---------------------------------------------------------------------------
# Кадр
# ---------------------------------------------------------------------------

func _step() -> void:
	main._process(DT)
	var before: float = mech.streak.work
	mech.step(DT)
	t += DT
	if before > 0.0 and not mech.streak.active():
		burns.append([snappedf(t, 0.1), snappedf(before, 0.1), _what])
		if probe:
			print("  %6.1f с  шкала сгорела (%.1f с работы): %s" % [t, before, _what])
	GameState.hunger = maxf(GameState.hunger, 60.0)   # сценарий не про голод и сон
	GameState.stamina = maxf(GameState.stamina, 60.0)
	await get_tree().process_frame
	if ProgressScreen.is_open() or (MetaService.instance != null and MetaService.instance.popup.is_open()):
		await _close_popups()


## Держать клавиши, пока не выкопано cells клеток (или max_s секунд).
func _dig(keys: Array, cells: int, max_s: float, what: String) -> int:
	_what = what
	var start := _dug_total
	var t0 := t
	while _dug_total - start < cells and t - t0 < max_s:
		bot.hold(keys)
		await _step()
	return _dug_total - start


## Палец оторван от стекла на sec секунд.
func _pause(sec: float, what: String) -> void:
	_what = what
	bot.release_all()
	var t0 := t
	while t - t0 < sec:
		await _step()


## Идти к колонке x по уже прорытому (без копки).
func _walk_to(x: int, max_s: float, what: String) -> void:
	_what = what
	var t0 := t
	while t - t0 < max_s:
		var dx: float = (float(x) + 0.5) - float(player.x)
		if absf(dx) < 0.25:
			break
		bot.hold([KEY_D] if dx > 0.0 else [KEY_A])
		await _step()
	bot.release_all()


## Тап по кнопке рюкзака в HUD, как пальцем.
func _tap_backpack() -> void:
	var btn: Control = main.hud.get("_inv_button")
	bot.tap(get_viewport().get_final_transform() * btn.get_global_rect().get_center())
	for i in 3:
		await get_tree().process_frame


# ---------------------------------------------------------------------------
# Сценарии
# ---------------------------------------------------------------------------

## Причина №1: пауза. До 26.10 2.5 с без копки обнуляли шкалу, а рюкзак (ввод HUD
## выключен, герой стоит) — тем же простоем. Теперь пауза держит шкалу, потом шкала тает
## понемногу; окно — замораживает её.
func _pause_and_backpack() -> void:
	await _dig([KEY_S], 3, 30.0, "копает вниз")
	var w0: float = mech.streak.work
	check("копка копит шкалу секундами (%.1f с за 3 клетки)" % w0, w0 > 3.0)
	await _pause(3.2, "огляделся 3.2 с")
	var w1: float = mech.streak.work
	check("огляделся 3.2 с — шкала жива (%.1f → %.1f с)" % [w0, w1], w1 > w0 * 0.5 and mech.streak.active())
	await _dig([KEY_S], 2, 30.0, "копает вниз")
	var w2: float = mech.streak.work
	await _tap_backpack()
	var opened: bool = main.hud._inv_sheet.visible
	await _pause(6.0, "смотрит в рюкзак")
	var w3: float = mech.streak.work
	await _tap_backpack()
	check("рюкзак открыт тапом по кнопке", opened and not main.hud._inv_sheet.visible)
	check("6 с в рюкзаке — шкала замерла (%.1f → %.1f с)" % [w2, w3], absf(w3 - w2) < 0.7)
	mech.streak.reset()
	burns.clear()


## Человек с телефоном: 3 минуты обычной работы в шахте.
func _phone_session(seconds: float) -> void:
	rng.seed = SEED
	fevers = 0
	fever_times.clear()
	var t_start := t
	var end := t + seconds
	var run := 0
	var dug0 := _dug_total
	while t < end:
		run += 1
		await _dig([KEY_S], rng.randi_range(3, 6), 40.0, "копает вниз")
		if t >= end:
			break
		# палец отрывается: огляделся, посмотрел на полоски (как правило — меньше секунды-полутора)
		var look := rng.randf_range(0.5, 1.6)
		if rng.randf() < 0.2:
			look = rng.randf_range(2.0, 3.2)   # прочитал тост, глянул на рюкзак
		await _pause(look, "огляделся %.1f с" % look)
		if run % 3 == 0:
			# штрек вбок за рудой и назад к шахте
			var side := KEY_D if rng.randf() < 0.5 else KEY_A
			var n := await _dig([side], rng.randi_range(2, 4), 30.0, "штрек вбок")
			await _pause(rng.randf_range(0.4, 1.0), "развернулся")
			if n > 0:
				await _walk_to(SHAFT_X, 4.0, "назад к шахте")
	var first: float = (float(fever_times[0]) - t_start) if not fever_times.is_empty() else -1.0
	print("за %.0f игровых секунд: %d клеток, жадность %d раз (первая на %.0f с), сгораний шкалы %d" % [
		seconds, _dug_total - dug0, fevers, first, burns.size()])
	check("3 минуты копки с паузами человека — жадность хотя бы 2 раза (%d)" % fevers, fevers >= 2)
	check("первая жадность — не позже 2 минут (%.0f с)" % first, first > 0.0 and first <= 120.0)

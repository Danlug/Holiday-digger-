extends Node
## test_rig_jump_fly — проверка задачи «Прыжок и полёт бурмобиля»:
##   1. порядок фаз анимации прыжка/приземления/полёта в CharacterView
##      (RIG_JUMP_UP/RIG_JUMP_DOWN/RIG_FLY_START/RIG_FLY_LOOP/RIG_FLY_STOP,
##      см. scripts/player/character_view.gd:_rig_move_frame), по образцу
##      tests/test_dig_phases.gd;
##   2. +200 кг к лимиту переноски, пока бурмобиль надет (GameState.
##      get_max_carry_kg());
##   3. коэффициенты падения/полёта бурмобиля (предел скорости падения ×1.3,
##      потолок скорости подъёма на тяге ×1.3) — сравнение с пешим, а не
##      абсолютные числа, как просил владелец.
##
## Запуск:  godot --headless --path . res://tests/test_rig_jump_fly.tscn
## Код возврата — 0 (всё ок) или 1 (есть провалы).

var failures := 0
var total := 0
var world: WorldGen
var player
var view


func _ready() -> void:
	print("=== test_rig_jump_fly ===")
	world = WorldGen.new(4242)
	GameState.world_ref = world
	GameState.reset_progress()
	# Бурмобиль требует владения — set_current_tool отказал бы без этого (см.
	# GameState.owns_tool). Тест проверяет отрисовку/физику, не магазин,
	# поэтому инструмент присваивается напрямую, в обход магазина (тот же
	# приём, что в test_dig_phases.gd).
	GameState.current_tool = "drill_rig"

	player = load("res://scripts/player/player.gd").new()
	player.world = world
	player.on_ground = true
	player.y = 0.5   # поверхность (cell_y() == 0) — весь тест про наземный/воздушный бурмобиль
	add_child(player)

	view = load("res://scripts/player/character_view.gd").new()
	view.player = player
	add_child(view)

	_test_jump_up_then_landing()
	_test_fly_start_loop_stop()
	_test_landing_interrupts_flight()
	_test_capacity_bonus_200kg()
	_test_fall_and_flight_speed_multipliers()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


## Кадр, который view сейчас показывает, и имя листа — 0-based индекс внутри
## текущей текстуры (тот же приём, что _shown_frame в test_dig_phases.gd).
func _shown_frame() -> Dictionary:
	view._process(0.0)
	var fw: float = view._sprite.region_rect.size.x
	var frame: int = int(round(view._sprite.region_rect.position.x / fw)) if fw > 0.0 else -1
	var sheet := ""
	if view._sprite.texture != null:
		sheet = String(view._sprite.texture.resource_path).get_file().get_basename()
	return {"sheet": sheet, "frame": frame}


func _advance_one_frame() -> void:
	player.anim += view.ANIM_DIV


func _reset_state() -> void:
	view._rig_move_phase = "none"
	view._rig_move_t0 = 0.0
	view._rig_was_on_ground = true
	view._rig_was_thrust = false
	view._dig_phase = "none"
	view._dig_was_active = false
	player.digging = null
	player.anim = 0.0
	player.on_ground = true
	player.vy = 0.0
	player.thrust = ""
	player.y = 0.5
	_shown_frame()   # синхронизирует _rig_was_on_ground/_rig_was_thrust с этим состоянием


## Прыжок (толчок вверх, vy<0, без тяги) -> rig_jump 0..7 вперёд один раз ->
## держит закрытый кадр (7), пока летит -> приземление (on_ground true) ->
## rig_jump 7..0 назад один раз -> снова закрытый кадр (7).
func _test_jump_up_then_landing() -> void:
	_reset_state()

	player.on_ground = false
	player.vy = -8.1   # JUMP_V — толчок вверх
	var f: Dictionary = _shown_frame()
	check("прыжок начался: rig_jump, кадр 1 (idx0)", f.sheet == "rig_jump" and f.frame == 0)

	for expected in [1, 2, 3, 4, 5, 6, 7]:
		_advance_one_frame()
		f = _shown_frame()
		check("подъём бурмобиля: rig_jump, кадр idx=%d" % expected,
			f.sheet == "rig_jump" and f.frame == expected)

	# Анимация подъёма доиграна, машина ещё в воздухе (падает после апекса) —
	# держит закрытый кадр (7), не проваливается в пешую анимацию падения.
	_advance_one_frame()
	f = _shown_frame()
	check("после подъёма, всё ещё в воздухе — закрытый кадр (idx7)",
		f.sheet == "rig_jump" and f.frame == 7)

	# Приземление — on_ground false->true, без тяги.
	player.on_ground = true
	f = _shown_frame()
	check("приземление началось: rig_jump, кадр idx7 (8, начало реверса)",
		f.sheet == "rig_jump" and f.frame == 7)

	for expected in [6, 5, 4, 3, 2, 1, 0]:
		_advance_one_frame()
		f = _shown_frame()
		check("посадка бурмобиля: rig_jump, кадр idx=%d" % expected,
			f.sheet == "rig_jump" and f.frame == expected)

	# Реверс доигран -> закрытый кадр на поверхности (решение владельца:
	# машина закрыта, а не с торчащим буром, пока не началась копка).
	_advance_one_frame()
	f = _shown_frame()
	check("после посадки — закрытый кадр (idx7), не dig_rig_side",
		f.sheet == "rig_jump" and f.frame == 7)


## Тяга включилась (в воздухе) -> rig_fly 0..5 один раз -> цикл 6,7,6,7... ->
## тяга выключилась (ещё в воздухе) -> rig_fly 5..0 один раз -> закрытый кадр.
func _test_fly_start_loop_stop() -> void:
	_reset_state()
	player.on_ground = false

	player.thrust = "prop"
	var f: Dictionary = _shown_frame()
	check("начало полёта: rig_fly, кадр idx0", f.sheet == "rig_fly" and f.frame == 0)

	for expected in [1, 2, 3, 4, 5]:
		_advance_one_frame()
		f = _shown_frame()
		check("розжиг турбины: rig_fly, кадр idx=%d" % expected,
			f.sheet == "rig_fly" and f.frame == expected)

	# Старт доигран -> без паузы в цикл (6,7) — тот же приём, что у DIG_PHASES.
	_advance_one_frame()
	f = _shown_frame()
	check("старт полёта доигран -> цикл, кадр idx6", f.sheet == "rig_fly" and f.frame == 6)
	_advance_one_frame()
	f = _shown_frame()
	check("цикл полёта, кадр idx7", f.sheet == "rig_fly" and f.frame == 7)
	_advance_one_frame()
	f = _shown_frame()
	check("цикл полёта крутится по кругу (снова idx6)", f.sheet == "rig_fly" and f.frame == 6)

	# Тяга кончилась, машина ещё в воздухе — реверс 5..0.
	player.thrust = ""
	f = _shown_frame()
	check("остановка полёта началась: rig_fly, кадр idx5", f.sheet == "rig_fly" and f.frame == 5)

	for expected in [4, 3, 2, 1, 0]:
		_advance_one_frame()
		f = _shown_frame()
		check("остановка полёта: rig_fly, кадр idx=%d" % expected,
			f.sheet == "rig_fly" and f.frame == expected)

	_advance_one_frame()
	f = _shown_frame()
	check("остановка полёта доиграна — закрытый кадр (rig_jump idx7)",
		f.sheet == "rig_jump" and f.frame == 7)


## Приземление всегда перебивает середину полёта (решение владельца:
## "приземление... после прыжка ИЛИ полёта" — общий случай для обоих путей).
func _test_landing_interrupts_flight() -> void:
	_reset_state()
	player.on_ground = false
	player.thrust = "jet"
	_shown_frame()
	for i in range(3):
		_advance_one_frame()
		_shown_frame()   # где-то в середине "старта" или "цикла" полёта

	player.thrust = ""
	player.on_ground = true   # приземлился прямо во время полёта
	var f: Dictionary = _shown_frame()
	check("приземление во время полёта перебивает его — сразу посадка (rig_jump idx7)",
		f.sheet == "rig_jump" and f.frame == 7)


## Балансная часть — вес: "когда он обретает бурмобиль, его носимый вес
## увеличивается на 200 кг, вдобавок к собственному" (решение владельца).
func _test_capacity_bonus_200kg() -> void:
	GameState.reset_progress()
	GameState.current_tool = "shovel"
	var base_kg: float = GameState.get_max_carry_kg()

	GameState.current_tool = "drill_rig"
	var rig_kg: float = GameState.get_max_carry_kg()

	check("бонус бурмобиля к лимиту переноски — ровно число владельца (200 кг)",
		absf((rig_kg - base_kg) - 200.0) < 0.0001)
	check("бонус бурмобиля совпадает с Balance.get_drill_rig_capacity_bonus_kg()",
		absf((rig_kg - base_kg) - Balance.get_drill_rig_capacity_bonus_kg()) < 0.0001)

	GameState.current_tool = "shovel"


## Физика падения/полёта — коэффициенты (не абсолютные числа, как просил
## владелец): предел скорости падения и потолок скорости подъёма на тяге
## должны быть РОВНО в 1.3 раза больше в бурмобиле, чем пешком.
##
## Изолированный player без world (world=null): _solid_at() тогда всегда
## возвращает false (см. player.gd), герой падает/летит свободно без
## столкновений — чистое измерение потолков скорости, без шахты нужной длины.
func _test_fall_and_flight_speed_multipliers() -> void:
	GameState.reset_progress()

	var p = load("res://scripts/player/player.gd").new()
	add_child(p)
	p.world = null
	p.on_ground = false
	p.vy = 0.0
	p.digging = null
	p.hold_dx = 0; p.hold_up = false; p.hold_down = false

	# --- предел скорости падения (V_TERM) ---
	GameState.current_tool = "shovel"
	for i in range(240):   # 8 секунд свободного падения — с запасом до предела
		p.physics_tick(1.0 / 30.0)
	var v_term_foot: float = p.vy

	p.vy = 0.0
	GameState.current_tool = "drill_rig"
	for i in range(240):
		p.physics_tick(1.0 / 30.0)
	var v_term_rig: float = p.vy

	var fall_mult: float = Balance.get_drill_rig_fall_speed_mult()
	check("предел скорости падения в бурмобиле — тот же коэффициент, что дал владелец (×%.1f)" % fall_mult,
		v_term_foot > 0.0 and absf(v_term_rig / v_term_foot - fall_mult) < 0.01)

	# --- потолок скорости подъёма на тяге ---
	GameState.grant_gear("jetpack_top")   # самая быстрая ступень — надёжнее выйти на потолок
	p.on_ground = false
	p.vy = 0.0

	GameState.current_tool = "shovel"
	for i in range(300):   # 10 секунд подъёма — с запасом до потолка джетпака (JET_RAMP=5с)
		p.set_intent(0, true, false)
		p._fly_arm_at_msec = 0.0   # снимаем паузу прыжок->тяга (не прыгали) — как test_sky_ceiling
		p.physics_tick(1.0 / 30.0)
	var v_max_foot: float = -p.vy   # vy отрицательна при подъёме

	p.vy = 0.0
	GameState.current_tool = "drill_rig"
	for i in range(300):
		p.set_intent(0, true, false)
		p._fly_arm_at_msec = 0.0
		p.physics_tick(1.0 / 30.0)
	var v_max_rig: float = -p.vy

	var flight_mult: float = Balance.get_drill_rig_flight_speed_mult()
	check("потолок скорости подъёма на тяге в бурмобиле — тот же коэффициент, что дал владелец (×%.1f)" % flight_mult,
		v_max_foot > 0.0 and absf(v_max_rig / v_max_foot - flight_mult) < 0.01)

	p.queue_free()
	GameState.current_tool = "shovel"
	GameState.reset_progress()

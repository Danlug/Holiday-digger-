extends Node
## test_day_cycle — проверка автозагрузки DayCycle (scripts/core/day_cycle.gd)
## и звёздного атласа (art/env/stars.png, см. tools/import_stars.py).
##
## Запускается СЦЕНОЙ (обращается к автозагрузкам GameState/DayCycle, а в
## режиме --script их нет, см. docs/BUILD.md и tests/test_house.gd):
##   godot --headless --path . res://tests/test_day_cycle.tscn
##
## Время в тесте идёт МОНОТОННО ВПЕРЁД одним проходом через сутки (как и
## положено set_hour() — он не отматывает назад, см. day_cycle.gd), поэтому
## проверки сгруппированы не по функции, а по часу: на каждой остановке
## спрашиваем всё, что относится именно к этому моменту.

const EPS := 0.01

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func check_close(name: String, actual: float, expected: float, eps: float = EPS) -> void:
	check("%s (%.4f ~ %.4f)" % [name, actual, expected], absf(actual - expected) <= eps)


func _ready() -> void:
	print("=== test_day_cycle ===")
	await _run()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _run() -> void:
	# _test_start_hour/_test_sleep_shifts_hour ждут кадр движка (см. их тела)
	# — ОБЯЗАТЕЛЬНО через await, иначе _run() (сам без await в своём теле —
	# не короутина) отпускает их "в фоне" и завершается раньше их
	# продолжения; _ready() тогда зовёт get_tree().quit() до того, как их
	# check() успеет напечататься, и три проверки бесследно пропадают.
	await _test_start_hour()
	await _test_sleep_shifts_hour()
	_test_set_hour_forward_only()
	_test_time_scale()
	_test_grade_and_sky_and_stars_and_sun_moon()
	_test_star_atlas()
	_test_star_async_phases()


# ---------------------------------------------------------------------------
# Часы
# ---------------------------------------------------------------------------

func _test_start_hour() -> void:
	GameState.reset_progress()
	await get_tree().process_frame
	await get_tree().process_frame
	check_close("час на старте — 6 утра", DayCycle.hour, 6.0)
	check("день на старте — 1", DayCycle.day == 1)


func _test_sleep_shifts_hour() -> void:
	var before: float = DayCycle.hour
	GameState.sleep(8.0)
	await get_tree().process_frame
	await get_tree().process_frame
	# 6 + 8 = 14, без переворота суток — проверяем именно сдвиг на 8 часов,
	# а не абсолютное число (тест выживает, если порядок тестов поменяют).
	check_close("после GameState.sleep(8) час сдвинулся на 8", DayCycle.hour - before, 8.0)


func _test_set_hour_forward_only() -> void:
	var day_before: int = DayCycle.day
	DayCycle.set_hour(22.0)
	check_close("set_hour(22) даёт 22:00", DayCycle.hour, 22.0)
	check("set_hour(22) не откатывает день назад", DayCycle.day >= day_before)


func _test_time_scale() -> void:
	# Числа считаем напрямую через _tick_game_clock с фиксированным dt —
	# без ожидания реальных секунд движка (нестабильно в headless), см.
	# шапку файла про монотонный проход.
	DayCycle.set_time_scale(1.0)
	var before: float = GameState.game_clock_hours
	GameState._tick_game_clock(1.0)
	var normal_delta: float = GameState.game_clock_hours - before

	DayCycle.set_time_scale(100.0)
	before = GameState.game_clock_hours
	GameState._tick_game_clock(1.0)
	var fast_delta: float = GameState.game_clock_hours - before
	DayCycle.set_time_scale(1.0)

	check("time_scale=100 ускоряет ход часов минимум в 50 раз",
		normal_delta > 0.0 and fast_delta > normal_delta * 50.0)


# ---------------------------------------------------------------------------
# Освещение/небо/звёзды/светила — один монотонный проход по часам суток,
# начиная с текущего момента (после предыдущих тестов — 22:00).
# ---------------------------------------------------------------------------

func _test_grade_and_sky_and_stars_and_sun_moon() -> void:
	DayCycle.set_hour(12.0)
	var g := DayCycle.grade()
	check_close("grade().exposure в полдень = 1.0", g.exposure, 1.0)
	check_close("grade().saturation в полдень = 1.0", g.saturation, 1.0)
	check_close("grade().contrast в полдень = 1.0", g.contrast, 1.0)
	check_close("sky_dark() в полдень = 0", DayCycle.sky_dark(), 0.0)

	DayCycle.set_hour(19.0)
	g = DayCycle.grade()
	check_close("grade().exposure в 19:00 = 0.6", g.exposure, 0.6)
	check_close("grade().saturation в 19:00 = 0.6", g.saturation, 0.6)
	check_close("grade().contrast в 19:00 = 1.25", g.contrast, 1.25)

	DayCycle.set_hour(20.0)
	check_close("sky_dark() в 20:00 = 0.9", DayCycle.sky_dark(), 0.9)
	check_close("stars_alpha() в 20:00 = 0", DayCycle.stars_alpha(), 0.0)
	check_close("sun_t() в 20:00 = 1.1 (уходит за правый край)", DayCycle.sun_t(), 1.1)
	check_close("moon_t() в 20:00 = -0.1 (входит слева)", DayCycle.moon_t(), -0.1)

	DayCycle.set_hour(20.0 + 10.0 / 60.0)
	check_close("stars_alpha() в 20:10 = 1 (проявились за 10 игровых минут)",
		DayCycle.stars_alpha(), 1.0)

	DayCycle.set_hour(21.0)
	g = DayCycle.grade()
	check_close("grade().exposure в 21:00 = 0.2", g.exposure, 0.2)
	check_close("grade().saturation в 21:00 = 0.2", g.saturation, 0.2)
	check_close("grade().contrast в 21:00 = 1.5", g.contrast, 1.5)

	DayCycle.set_hour(3.0 + 50.0 / 60.0)
	check_close("stars_alpha() в 03:50 = 1 (ещё держатся)", DayCycle.stars_alpha(), 1.0)

	DayCycle.set_hour(4.0)
	check_close("stars_alpha() в 04:00 = 0 (погасли за 10 минут до рассвета)",
		DayCycle.stars_alpha(), 0.0)

	DayCycle.set_hour(5.0)
	g = DayCycle.grade()
	check_close("grade().exposure в 05:00 = 0.6 (симметрично вечеру)", g.exposure, 0.6)
	check_close("grade().saturation в 05:00 = 0.6", g.saturation, 0.6)
	check_close("grade().contrast в 05:00 = 1.25", g.contrast, 1.25)
	check_close("sky_dark() в 05:00 = 0.45", DayCycle.sky_dark(), 0.45)

	DayCycle.set_hour(6.0)
	check_close("sun_t() в 06:00 = -0.1 (восход из-за левого края)", DayCycle.sun_t(), -0.1)

	DayCycle.set_hour(13.0)
	check_close("sun_t() в 13:00 = 0.5 (середина неба)", DayCycle.sun_t(), 0.5)

	DayCycle.set_hour(20.0)
	check_close("sun_t() в 20:00 = 1.1 (повторно, после полного оборота)", DayCycle.sun_t(), 1.1)

	DayCycle.set_hour(1.0)
	check_close("moon_t() в 01:00 = 0.5 (середина ночи)", DayCycle.moon_t(), 0.5)

	DayCycle.set_hour(6.0)
	check_close("moon_t() в 06:00 = 1.1 (заходит за правый край на рассвете)",
		DayCycle.moon_t(), 1.1)


# ---------------------------------------------------------------------------
# Атлас звёзд
# ---------------------------------------------------------------------------

func _test_star_atlas() -> void:
	check("атлас art/env/stars.png существует", ResourceLoader.exists("res://art/env/stars.png"))
	check("метаданные art/env/stars.json существуют",
		FileAccess.file_exists("res://art/env/stars.json"))
	if not FileAccess.file_exists("res://art/env/stars.json"):
		return
	var f := FileAccess.open("res://art/env/stars.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		check("stars.json — валидный JSON-словарь", false)
		return
	var regions: Array = parsed.get("regions", [])
	check("в атласе минимум 15 звёзд (%d)" % regions.size(), regions.size() >= 15)
	var all_small := true
	for r in regions:
		if int(r.get("w", 0)) > 21 or int(r.get("h", 0)) > 21:
			all_small = false
			break
	check("каждый регион звезды ≤ 21 px по стороне", all_small)


# ---------------------------------------------------------------------------
# Асинхронность мерцания
# ---------------------------------------------------------------------------

func _test_star_async_phases() -> void:
	var sky := preload("res://scripts/world/sky_view.gd").new()
	add_child(sky)
	sky.set_scene_rect(224.0, 300.0, 0.0)
	check("SkyView заспавнил звёзды", sky.debug_star_count() > 0)
	if sky.debug_star_count() >= 2:
		var t0: float = sky.debug_star_timer(0)
		var t1: float = sky.debug_star_timer(1)
		check("у двух звёзд разные фазовые сдвиги (не синхронны)", absf(t0 - t1) > 0.01)
	sky.queue_free()

extends Node
## test_clouds — слой облаков (scripts/world/clouds_view.gd): файлы на месте,
## облака существуют для нескольких дней, видимость по часам суток,
## покрытие в разумных пределах, раскладка не повторяется день в день, но
## детерминирована для одного и того же дня.
##
## Запуск: godot --headless --path . res://tests/test_clouds.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_clouds ===")
	for _i in range(3):
		await get_tree().process_frame

	_check_textures()
	await _check_layout_across_days()
	_check_visibility_by_hour()
	await _check_drift()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check_textures() -> void:
	var count := 0
	for i in range(1, 13):
		var path := "res://art/env/clouds/cloud_%d.png" % i
		var tex := load(path) as Texture2D
		if tex != null:
			count += 1
			check("%s: непустая текстура" % path, tex.get_width() > 0 and tex.get_height() > 0)
	check("найдено 10-12 отдельных спрайтов облаков (%d)" % count, count >= 10 and count <= 12)

	check("art/env/sun.png существует", ResourceLoader.exists("res://art/env/sun.png"))
	check("art/env/moon.png существует", ResourceLoader.exists("res://art/env/moon.png"))


func _check_layout_across_days() -> void:
	var clouds := preload("res://scripts/world/clouds_view.gd").new()
	add_child(clouds)
	await get_tree().process_frame

	var signatures: Array = []
	var coverages: Array = []
	for day in range(1, 11):
		clouds.debug_regenerate_for_day(day)
		var n := clouds.debug_cloud_count()
		var cov: float = clouds.debug_coverage()
		check("день %d: число облаков в пределах 3-9 (%d)" % [day, n], n >= 3 and n <= 9)
		check("день %d: покрытие в пределах 0-0.25 (%.3f)" % [day, cov], cov >= 0.0 and cov <= 0.25 + 0.001)
		signatures.append("%d:%.4f" % [n, cov])
		coverages.append(cov)

	# "не слишком повторяющимися" — из 9 соседних пар хотя бы несколько
	# обязаны отличаться (число облаков и/или покрытие); требуем большинство
	# пар разными, не каждую — иначе тест ловил бы редкое случайное
	# совпадение числа облаков у двух дней подряд как провал.
	var differing_neighbors := 0
	for i in range(1, signatures.size()):
		if signatures[i] != signatures[i - 1]:
			differing_neighbors += 1
	check("соседние дни не выглядят одинаково (%d/%d пар отличаются)" %
		[differing_neighbors, signatures.size() - 1], differing_neighbors >= signatures.size() - 2)

	# Хотя бы один день с более облачной погодой (HEAVY_COVERAGE) и хотя бы
	# один почти ясный — на горизонте 10 дней при HEAVY_CHANCE=0.25 это
	# почти наверняка (P(ни разу за 10 дней) = 0.75^10 ≈ 0.056), а тест не
	# должен быть жёстко детерминирован под конкретные дни, поэтому просто
	# проверяем разброс, а не конкретные значения.
	var has_light := false
	var has_notable := false
	for cov in coverages:
		if cov <= 0.05 + 0.001:
			has_light = true
		if cov >= 0.1:
			has_notable = true
	check("на 10 днях встречаются и ясная, и заметно облачная погода",
		has_light and has_notable)

	# Детерминизм: тот же день -> та же раскладка (число + покрытие), иначе
	# облака "мигали" бы при перезаходе в тот же игровой день.
	clouds.debug_regenerate_for_day(5)
	var n5a := clouds.debug_cloud_count()
	var cov5a: float = clouds.debug_coverage()
	clouds.debug_regenerate_for_day(3)  # сбить состояние
	clouds.debug_regenerate_for_day(5)
	var n5b := clouds.debug_cloud_count()
	var cov5b: float = clouds.debug_coverage()
	check("одинаковый день даёт одинаковую раскладку (детерминизм)",
		n5a == n5b and absf(cov5a - cov5b) < 0.0001)

	clouds.queue_free()


## Дрейф (решение владельца 2026-09-21): скорость своя у каждого облака
## (0.1..0.5 клетки/с), направление — общее на день (право/лево), позиция
## оборачивается по ширине полосы, не убегает насовсем.
func _check_drift() -> void:
	var clouds := preload("res://scripts/world/clouds_view.gd").new()
	add_child(clouds)
	await get_tree().process_frame
	clouds.debug_regenerate_for_day(7)

	var n := clouds.debug_cloud_count()
	var speeds: Array = []
	var signs: Array = []
	for i in range(n):
		var s: float = clouds.debug_cloud_drift_px_s(i)
		speeds.append(absf(s))
		signs.append(signf(s))
		var tiles_per_sec: float = absf(s) / clouds.TILE
		check("облако %d: скорость дрейфа в 0.1..0.5 кл/с (%.3f)" % [i, tiles_per_sec],
			tiles_per_sec >= clouds.DRIFT_SPEED_MIN_TILES - 0.0001
				and tiles_per_sec <= clouds.DRIFT_SPEED_MAX_TILES + 0.0001)

	var all_same_sign := true
	for sgn in signs:
		if sgn != signs[0]:
			all_same_sign = false
	check("направление дрейфа общее на весь день (%d облаков, один знак)" % n, all_same_sign)

	var distinct_speeds := {}
	for sp in speeds:
		distinct_speeds[snappedf(sp, 0.01)] = true
	check("скорость у облаков разная, не одна на всех (%d уникальных из %d)" %
		[distinct_speeds.size(), n], n < 2 or distinct_speeds.size() > 1)

	var x0: float = clouds.debug_cloud_x(0)
	clouds.debug_advance(2.0)
	var x1: float = clouds.debug_cloud_x(0)
	var moved: float = x1 - x0
	if moved > clouds.CLOUDS_W_LOGICAL * 0.5:
		moved -= clouds.CLOUDS_W_LOGICAL
	elif moved < -clouds.CLOUDS_W_LOGICAL * 0.5:
		moved += clouds.CLOUDS_W_LOGICAL
	var expected: float = clouds.debug_cloud_drift_px_s(0) * 2.0
	check("за 2 реальные секунды облако сдвинулось на своей скорости (%.2f ~ %.2f)" %
		[moved, expected], absf(moved - expected) < 0.5)

	# Оборот по ширине полосы: гоним долго вперёд — x должен остаться в
	# [0, CLOUDS_W_LOGICAL), а не улететь в бесконечность.
	clouds.debug_advance(600.0)
	var x_far: float = clouds.debug_cloud_x(0)
	check("после долгого дрейфа x завёрнут в пределы полосы (%.1f)" % x_far,
		x_far >= -0.001 and x_far <= clouds.CLOUDS_W_LOGICAL + 0.001)

	clouds.queue_free()


func _check_visibility_by_hour() -> void:
	var clouds := preload("res://scripts/world/clouds_view.gd").new()
	add_child(clouds)
	DayCycle.set_hour(12.0)
	check("облака видны днём (12:00): alpha=1", absf(clouds.debug_visibility_alpha() - 1.0) < 0.001)

	DayCycle.set_hour(2.0)
	check("облаков не видно глубокой ночью (02:00): alpha=0", clouds.debug_visibility_alpha() < 0.001)

	DayCycle.set_hour(6.0)
	check("на границе видимости (06:00) alpha=0 (плавный вход ещё не начался)",
		clouds.debug_visibility_alpha() < 0.001)
	DayCycle.set_hour(6.25)
	check("через 15 игровых минут после 06:00 alpha=1 (плавный вход завершён)",
		absf(clouds.debug_visibility_alpha() - 1.0) < 0.01)

	DayCycle.set_hour(19.875)
	var mid_out: float = clouds.debug_visibility_alpha()
	check("на середине выходного затухания (19:52) alpha примерно 0.5 (%.2f)" % mid_out,
		absf(mid_out - 0.5) < 0.05)
	DayCycle.set_hour(20.0)
	check("ровно в 20:00 alpha=0 (плавное затухание, начавшееся в 19:45, завершено)",
		clouds.debug_visibility_alpha() < 0.001)

	DayCycle.set_hour(6.125)
	var mid_in: float = clouds.debug_visibility_alpha()
	check("на середине входного затухания (06:07) alpha примерно 0.5 (%.2f)" % mid_in,
		absf(mid_in - 0.5) < 0.05)

	clouds.queue_free()

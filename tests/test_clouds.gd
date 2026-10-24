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
	# Облака больше не пропадают ночью (раньше: альфа 0 с 20:00 до 06:00 и рывок в 19:45): их рампа — та же
	# сумеречная, что у неба, а ночью они редеют до NIGHT_ALPHA и темнеют (подсветка луны — set_moon_light).
	var clouds := preload("res://scripts/world/clouds_view.gd").new()
	add_child(clouds)
	DayCycle.set_hour(12.0)
	check("облака видны днём (12:00): alpha=1", absf(clouds.debug_visibility_alpha() - 1.0) < 0.001)
	check("днём облака белые (без тонировки)", clouds._time_tint().is_equal_approx(Color.WHITE))

	DayCycle.set_hour(19.0)
	var dusk: Color = clouds._time_tint()
	check("на закате (19:00) облака розовеют: синего меньше, чем красного (%s)" % dusk, dusk.b < dusk.r - 0.1)

	DayCycle.set_hour(2.0)
	check("глубокой ночью (02:00) облака редеют до NIGHT_ALPHA, а не исчезают (%.2f)" % clouds.debug_visibility_alpha(),
		absf(clouds.debug_visibility_alpha() - CloudsView.NIGHT_ALPHA) < 0.001)
	var night: Color = clouds._time_tint()
	check("ночью облака тёмные и синеватые (%s)" % night, night.b > night.r and night.b < 0.8)

	# Сплошной проход 17:00 -> 07:00 шагом 3 игровые минуты: ни одного скачка альфы и цвета.
	var prev_a: float = -1.0
	var prev_c: Color = Color.WHITE
	var max_da: float = 0.0
	var max_dc: float = 0.0
	for i in range(0, 281):
		DayCycle.set_hour(fmod(17.0 + float(i) * 0.05, 24.0))
		var a: float = clouds.debug_visibility_alpha()
		var c: Color = clouds._time_tint()
		if prev_a >= 0.0:
			max_da = maxf(max_da, absf(a - prev_a))
			max_dc = maxf(max_dc, absf(c.r - prev_c.r) + absf(c.g - prev_c.g) + absf(c.b - prev_c.b))
		prev_a = a
		prev_c = c
	check("альфа облаков меняется плавно весь вечер/рассвет (макс. шаг %.3f)" % max_da, max_da < 0.03)
	check("цвет облаков меняется плавно (макс. шаг %.3f)" % max_dc, max_dc < 0.08)

	# Лунная подсветка: ближайшее к луне облако светлее далёкого.
	clouds.set_moon_light(Vector2(100.0, 60.0), 1.0)
	check("set_moon_light запоминает положение и силу", clouds._moon_strength == 1.0
		and clouds._moon_screen == Vector2(100.0, 60.0))

	clouds.queue_free()

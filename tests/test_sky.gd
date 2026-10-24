extends Node
## test_sky — небо: математика часов в DayCycle (фазы луны, сумерки, видимость звёзд), графика
## tools/gen_sky.py (слои звёзд, Млечный Путь, атлас луны без «мусора») и поведение SkyView.
##
##   godot --headless --path . res://tests/test_sky.tscn
##
## Время идёт вперёд одним проходом (DayCycle.set_hour умеет только вперёд), поэтому проверки сгруппированы
## по часам, как в tests/test_day_cycle.gd.

var failures := 0
var total := 0

const MOON_FRAME := 112
const MOON_R := 51.0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_sky ===")
	_test_textures()
	await _test_clock_math()
	await _test_sky_view()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# Графика
# ---------------------------------------------------------------------------

func _load_img(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


func _test_textures() -> void:
	var meta = JSON.parse_string(FileAccess.get_file_as_string("res://art/env/sky/sky.json"))
	check("sky.json — валидный словарь со слоями", typeof(meta) == TYPE_DICTIONARY and meta.has("layers"))
	var phases_seen: Dictionary = {}
	var temps_seen: Dictionary = {}
	for layer in ["far", "mid", "near"]:
		var img := _load_img("res://art/env/sky/stars_%s.png" % layer)
		check("слой звёзд %s загружается" % layer, img != null and not img.is_empty())
		if img == null or img.is_empty():
			continue
		var lit := 0
		var data := img.get_data()
		var fmt_ok: bool = img.get_format() == Image.FORMAT_RGB8
		check("слой %s — RGB8 без альфы: данные в каналах, импорт ничего не портит (%d)" % [layer, img.get_format()], fmt_ok)
		var stride: int = 3 if fmt_ok else 4
		for i in range(0, data.size(), stride):
			if data[i] > 0:
				lit += 1
				phases_seen[data[i + 1]] = true
				temps_seen[data[i + 2] / 16] = true
		var stars: int = int(meta["layers"][layer]["stars"])
		check("слой %s: звёзд %d, светящихся текселей %d" % [layer, stars, lit], stars > 10 and lit >= stars)
	check("фазы мерцания разные у многих звёзд (%d значений) — мерцание не в унисон" % phases_seen.size(),
		phases_seen.size() > 100)
	check("температуры звёзд покрывают холодные, белые, жёлтые и красноватые (%d корзин из 16)" % temps_seen.size(),
		temps_seen.size() >= 12 and temps_seen.has(0) and temps_seen.has(15))

	var nb := _load_img("res://art/env/sky/milkyway.png")
	check("Млечный Путь загружается", nb != null and not nb.is_empty())
	_test_moon_atlas()


func _frame_stats(img: Image, frame: int) -> Dictionary:
	var inside := 0
	var stray := 0
	var lit := 0
	var c := float(MOON_FRAME) * 0.5
	for y in range(MOON_FRAME):
		for x in range(MOON_FRAME):
			var px := img.get_pixel(frame * MOON_FRAME + x, y)
			if px.a <= 0.0:
				continue
			var d := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length()
			if d > MOON_R + 1.0:
				stray += 1
			else:
				inside += 1
				if px.a > 0.5 and (px.r + px.g + px.b) / 3.0 > 0.45:
					lit += 1
	return {"inside": inside, "stray": stray, "lit": lit}


func _test_moon_atlas() -> void:
	var img := _load_img("res://art/env/moon.png")
	check("атлас луны 8 кадров по %d px" % MOON_FRAME, img != null and img.get_width() == MOON_FRAME * 8
		and img.get_height() == MOON_FRAME)
	if img == null:
		return
	var lits: Array = []
	var all_clean := true
	for f in range(8):
		var st := _frame_stats(img, f)
		if int(st.stray) != 0:
			all_clean = false
		lits.append(int(st.lit))
	check("вокруг луны нет ни одного постороннего пикселя (мусор вырезки листа) во всех 8 кадрах", all_clean)
	check("новолуние: светлых пикселей почти нет (%d)" % lits[0], lits[0] < 60)
	check("полнолуние: светится почти весь диск (%d)" % lits[4], lits[4] > 5200)
	check("освещённость растёт до полнолуния %s" % [lits.slice(0, 5)],
		lits[0] < lits[1] and lits[1] < lits[2] and lits[2] < lits[3] and lits[3] < lits[4])
	check("и убывает после него %s" % [lits.slice(4)],
		lits[4] > lits[5] and lits[5] > lits[6] and lits[6] > lits[7])
	# Прибывающая луна освещена справа, убывающая слева.
	var right_waxing := _side_light(img, 2, true) > _side_light(img, 2, false) * 3
	var left_waning := _side_light(img, 6, false) > _side_light(img, 6, true) * 3
	check("первая четверть светится справа", right_waxing)
	check("последняя четверть светится слева", left_waning)


func _side_light(img: Image, frame: int, right: bool) -> int:
	var n := 0
	for y in range(MOON_FRAME):
		for x in range(MOON_FRAME):
			if (x >= MOON_FRAME / 2) != right:
				continue
			var px := img.get_pixel(frame * MOON_FRAME + x, y)
			if px.a > 0.5 and (px.r + px.g + px.b) / 3.0 > 0.45:
				n += 1
	return n


# ---------------------------------------------------------------------------
# Математика часов
# ---------------------------------------------------------------------------

func _test_clock_math() -> void:
	GameState.reset_progress()
	await get_tree().process_frame
	await get_tree().process_frame
	# Игра стартует в 6:00 дня 1. Первая ночь — молодой месяц (1), и фаза держится ВСЮ ночь,
	# хотя в полночь счётчик дней меняется.
	DayCycle.set_hour(21.0)
	check("день 1, 21:00 — фаза 1 (молодой месяц)", DayCycle.moon_phase() == 1)
	DayCycle.set_hour(23.99)
	var late_phase: int = DayCycle.moon_phase()
	var day_before: int = DayCycle.day
	DayCycle.set_hour(1.0)
	check("перелом через полночь не меняет фазу ночи (день %d -> %d)" % [day_before, DayCycle.day],
		DayCycle.day == day_before + 1 and DayCycle.moon_phase() == late_phase)
	DayCycle.set_hour(5.5)
	check("перед рассветом та же фаза", DayCycle.moon_phase() == late_phase)
	DayCycle.set_hour(21.0)
	check("следующая ночь — следующая фаза (%d)" % DayCycle.moon_phase(), DayCycle.moon_phase() == 2)

	# Восемь ночей — восемь разных фаз, на девятой цикл замкнулся.
	var seen: Dictionary = {}
	var first_phase: int = DayCycle.moon_phase()
	for i in range(8):
		seen[DayCycle.moon_phase()] = true
		DayCycle.set_hour(12.0)
		DayCycle.set_hour(21.0)
	check("за 8 ночей видны все 8 фаз", seen.size() == 8)
	check("на 9-й ночи цикл замыкается", DayCycle.moon_phase() == first_phase)

	check("освещённость диска: новолуние 0, полнолуние 1, четверть 0.5",
		absf(DayCycle.moon_illumination(0)) < 0.001 and absf(DayCycle.moon_illumination(4) - 1.0) < 0.001
		and absf(DayCycle.moon_illumination(2) - 0.5) < 0.001 and absf(DayCycle.moon_illumination(6) - 0.5) < 0.001)

	# Видимость звёзд — плавная рампа сумерек, без скачков, весь вечер и весь рассвет.
	var prev: float = -1.0
	var max_step: float = 0.0
	var sample: Dictionary = {}
	for i in range(0, 301):
		var h: float = 17.0 + float(i) * 0.01
		DayCycle.set_hour(h)
		var g: float = DayCycle.star_glow()
		sample[int(round(h * 100.0))] = g
		if prev >= 0.0:
			max_step = maxf(max_step, absf(g - prev))
		prev = g
	# Шаг 0.01 игрового часа — 4.5 секунды реального времени (8 игровых часов на реальный час).
	check("star_glow на закате растёт плавно (макс. шаг за 4.5 с %.4f)" % max_step, max_step < 0.02)
	check("звёзды 18:00 — нет, 19:00 — первые, 19:30 — многие, 20:00 — все (%.2f / %.2f / %.2f / %.2f)" %
		[sample[1800], sample[1900], sample[1930], sample[2000]],
		sample[1800] < 0.001 and sample[1900] > 0.05 and sample[1900] < 0.3 and sample[1930] > 0.3 and sample[2000] > 0.99)
	DayCycle.set_hour(3.0)
	check("глубокой ночью star_glow = 1", DayCycle.star_glow() > 0.999)
	DayCycle.set_hour(4.5)
	var dawn_g: float = DayCycle.star_glow()
	check("в 4:30 звёзды уже гаснут (%.2f)" % dawn_g, dawn_g < 0.95 and dawn_g > 0.05)
	DayCycle.set_hour(5.6)
	check("к 5:36 звёзд нет", DayCycle.star_glow() < 0.05)
	DayCycle.set_hour(12.0)
	check("днём star_glow = 0, twilight = 0", DayCycle.star_glow() == 0.0 and DayCycle.twilight() < 0.001)
	DayCycle.set_hour(19.0)
	check("пик зари в 19:00 (twilight %.2f)" % DayCycle.twilight(), DayCycle.twilight() > 0.97)
	DayCycle.set_hour(5.0)
	check("и в 5:00, и это рассвет", DayCycle.twilight() > 0.97 and DayCycle.is_dawn())
	DayCycle.set_hour(23.0)
	check("глубокой ночью зари нет", DayCycle.twilight() < 0.001 and not DayCycle.is_dawn())

	DayCycle.set_hour(13.0)
	check("солнце в 13:00 в зените, луны нет", DayCycle.sun_alt() > 0.99 and DayCycle.moon_alt() < 0.0)
	DayCycle.set_hour(1.0)
	check("луна в 01:00 в зените, солнца нет", DayCycle.moon_alt() > 0.99 and DayCycle.sun_alt() < 0.0)
	DayCycle.set_hour(20.0)
	check("в 20:00 солнце у кромки, луна восходит", absf(DayCycle.sun_alt()) < 0.01 and absf(DayCycle.moon_alt()) < 0.01)


# ---------------------------------------------------------------------------
# SkyView
# ---------------------------------------------------------------------------

func _test_sky_view() -> void:
	var sky: SkyView = preload("res://scripts/world/sky_view.gd").new()
	add_child(sky)
	await get_tree().process_frame
	check("шейдер неба загружен", sky.debug_has_shader())
	check("звёзд в слоях сотни (%d)" % sky.debug_star_count(), sky.debug_star_count() > 500)
	sky.set_camera(Vector2(10.0, -6.5), 7)

	DayCycle.set_hour(12.0)
	await get_tree().process_frame
	check("днём небо ровное голубое: низ = середина = верх",
		sky.debug_uniform("col_horizon") == sky.debug_uniform("col_zenith")
		and sky.debug_uniform("col_horizon") == SkyView.COLOR_DAY)
	check("днём звёзд нет", float(sky.debug_uniform("star_vis")) == 0.0)
	var sun: Vector4 = sky.debug_uniform("sun_glow")
	check("днём у солнца есть свечение (%.2f)" % sun.w, sun.w > 0.2)
	check("в полдень солнце посреди экрана (x=%.0f) и высоко (y=%.0f)" % [sun.x, sun.y],
		absf(sun.x - 7.0 * 32.0 * 0.5) < 40.0 and sun.y < 100.0)
	check("луны днём нет", (sky.debug_uniform("moon_glow") as Vector4).w == 0.0)

	DayCycle.set_hour(19.0)
	await get_tree().process_frame
	check("на закате включается тёплая полоса (%.2f)" % float(sky.debug_uniform("twilight")),
		float(sky.debug_uniform("twilight")) > 0.9)
	check("на закате заря справа, на рассвете слева",
		float(sky.debug_uniform("tw_x")) > 112.0)
	DayCycle.set_hour(1.0)
	await get_tree().process_frame
	check("ночью звёзды в полную силу", float(sky.debug_uniform("star_vis")) > 0.99)
	var moon: Vector4 = sky.debug_uniform("moon_glow")
	check("в 01:00 луна высоко (y=%.0f) и светит (%.2f)" % [moon.y, moon.w], moon.y < 80.0 and moon.w > 0.05)
	check("фаза луны в небе совпадает с DayCycle (%d)" % sky.debug_moon_phase(),
		sky.debug_moon_phase() == DayCycle.moon_phase())

	# Луна восходит ЗА лесом: в 20:00 центр диска ниже кромки леса (экранный y≈125) на радиус диска.
	DayCycle.set_hour(20.0)
	await get_tree().process_frame
	var rise: Vector4 = sky.debug_uniform("moon_glow")
	check("в 20:00 луна ещё за лесом (y=%.0f)" % rise.y, rise.y >= 140.0)
	DayCycle.set_hour(5.99)
	await get_tree().process_frame
	check("и заходит за лес на рассвете (y=%.0f)" % (sky.debug_uniform("moon_glow") as Vector4).y,
		(sky.debug_uniform("moon_glow") as Vector4).y >= 140.0)

	# Палитра по часам: ни одного скачка цвета (шаг 0.01 игрового часа — 4.5 с реального времени).
	var prev_h := Color.BLACK
	var prev_z := Color.BLACK
	var max_d := 0.0
	var first := true
	for i in range(0, 2401):
		DayCycle.set_hour(fmod(6.0 + float(i) * 0.01, 24.0))
		sky._update_state()
		var ch: Color = sky.debug_uniform("col_horizon")
		var cz: Color = sky.debug_uniform("col_zenith")
		if not first:
			max_d = maxf(max_d, maxf(absf(ch.r - prev_h.r) + absf(ch.g - prev_h.g) + absf(ch.b - prev_h.b),
				absf(cz.r - prev_z.r) + absf(cz.g - prev_z.g) + absf(cz.b - prev_z.b)))
		first = false
		prev_h = ch
		prev_z = cz
	check("цвета неба сутки напролёт меняются плавно (макс. шаг за 4.5 с %.4f)" % max_d, max_d < 0.03)

	# reduce_motion: мерцание тише, падающие звёзды не запускаются.
	var was: bool = Settings.reduce_motion
	DayCycle.set_hour(23.0)
	Settings.reduce_motion = false
	sky._update_state()
	var tw_full: float = float(sky.debug_uniform("twinkle"))
	Settings.reduce_motion = true
	sky._update_state()
	var tw_calm: float = float(sky.debug_uniform("twinkle"))
	check("reduce_motion делает мерцание тише (%.2f -> %.2f)" % [tw_full, tw_calm], tw_calm < tw_full * 0.5)
	sky.debug_spawn_meteor()
	check("при reduce_motion падающая звезда не запускается", sky.debug_meteor_count() == 0)
	Settings.reduce_motion = false
	sky.debug_spawn_meteor()
	check("ночью падающая звезда запускается", sky.debug_meteor_count() == 1)
	sky._tick_meteors(5.0)
	check("и через 5 секунд её уже нет", sky.debug_meteor_count() == 0)
	Settings.reduce_motion = was
	sky.queue_free()

	# Катсцена: тот же узел в чужих координатах не падает и держит дугу над горизонтом сцены.
	var scene_sky: SkyView = preload("res://scripts/world/sky_view.gd").new()
	add_child(scene_sky)
	await get_tree().process_frame
	scene_sky.set_scene_rect(224.0, 300.0, 0.0)
	DayCycle.set_hour(1.0)
	await get_tree().process_frame
	var sm: Vector4 = scene_sky.debug_uniform("moon_glow")
	check("в катсцене луна ночью над горизонтом сцены (y=%.0f при горизонте 300)" % sm.y, sm.y < 250.0 and sm.w > 0.0)
	scene_sky.queue_free()

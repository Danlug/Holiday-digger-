extends Node
## test_hero_anim — слой движения героя (scripts/player/hero_anim.gd и
## CharacterView): математика фаз, пружины, шаг по пути, привязка кадра удара к
## ударам JuiceDirector, остановка в проходной позе, и что кадры новых листов
## стоят над той же осью (голова не шатается — ГДД §15.1).
##
## Запуск:  godot --headless --path . res://tests/test_hero_anim.tscn

var failures := 0
var total := 0
var player
var view


func _ready() -> void:
	print("=== test_hero_anim ===")
	var world := WorldGen.new(4242)
	GameState.world_ref = world
	GameState.reset_progress()
	GameState.current_tool = "pickaxe"

	player = load("res://scripts/player/player.gd").new()
	player.world = world
	player.on_ground = true
	add_child(player)
	view = load("res://scripts/player/character_view.gd").new()
	view.player = player
	add_child(view)

	_test_math()
	_test_spring()
	_test_dig_sync()
	_test_dig_follow_through()
	_test_walk_by_distance()
	_test_air_pose()
	_test_art_anchor()
	_test_idle_extras()
	_test_reduce_motion()
	_test_death_cycle()
	_test_cost()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


## Листы мальчика по эталону — в несколько рядов (HeroSheets): номер кадра
## читаем у самого CharacterView, а не по region_rect.x.
func _frame() -> int:
	return view.shown_frame


func _sheet() -> String:
	return String(view._sprite.texture.resource_path).get_file().get_basename() if view._sprite.texture != null else ""


# ---------------------------------------------------------------------------

func _test_math() -> void:
	var w: Array = HeroAnim.nums("dig.pick.weights", [])
	check("у кирки 8 весов кадров", w.size() == 8)
	var s := 0.0
	for i in 8:
		var p: float = HeroAnim.phase_start(w, i)
		check("начало кадра %d не раньше предыдущего" % i, p >= s - 1e-9)
		check("кадр %d находится по собственной фазе" % i, HeroAnim.phase_frame(w, p + 1e-4) == i)
		s = p
	check("кадр упора держится дольше кадра удара", float(w[4]) > float(w[3]) * 1.5)
	var imp: float = HeroAnim.phase_mid(w, 3)
	var period := 0.38
	for k in 4:
		var t: float = (float(k) + 0.5) * period + 0.002
		var fr := HeroAnim.phase_frame(w, HeroAnim.dig_target_phase(t, period, imp))
		check("удар %d: на звуке Juice показан кадр удара" % k, fr == 3)
	check("фаза цикла в [0,1)", HeroAnim.dig_target_phase(12.34, 0.38, 0.3) < 1.0)

	# ведомая фаза: идёт только вперёд и догоняет цель
	var cur := 0.9
	var target := 0.2
	var back := false
	for i in 120:
		var nxt := HeroAnim.chase_phase(cur, target, 1.0 / 60.0, 0.38, 6.0)
		if fposmod(nxt - cur, 1.0) > 0.5:
			back = true
		cur = nxt
		target = fposmod(target + (1.0 / 60.0) / 0.38, 1.0)
	check("ведомая фаза не откатывается назад", not back)
	var err := absf(fposmod(target - cur + 0.5, 1.0) - 0.5)
	check("ведомая фаза догоняет цель (ошибка %.3f)" % err, err < 0.06)

	check("до проходной позы: после кадра 4 ждать почти целый шаг", absf(HeroAnim.frames_to_passing(4.1) - 3.9) < 0.01)
	check("в проходной позе ждать нечего", HeroAnim.frames_to_passing(8.0) < 0.001)
	var half := HeroAnim.stride_advance(0.0, 1.0, 5.0)
	var slow := HeroAnim.stride_advance(0.0, 0.5, 5.0)
	check("шаг пропорционален пути (медленнее вдвое — вдвое меньше кадров)", absf(half - 2.0 * slow) < 1e-6)
	check("подъём корпуса: 1 в проходной, 0 в контакте", HeroAnim.step_lift(0.0) > 0.99 and HeroAnim.step_lift(2.0) < 0.01)
	check("bounce в конце ровно 1", absf(HeroAnim.ease_out_bounce(1.0) - 1.0) < 1e-6)
	check("уменьшить движение смягчает", HeroAnim.motion_scale(true) < 0.5 and HeroAnim.motion_scale(false) == 1.0)


func _test_spring() -> void:
	var sp := HeroAnim.Spring.new(5.2, 0.32)
	sp.x = 0.25
	var peak := 0.0
	for i in 600:
		sp.step(1.0 / 30.0)
		peak = maxf(peak, absf(sp.x))
	check("пружина сходится к нулю", absf(sp.x) < 0.001 and absf(sp.v) < 0.01)
	check("пружина не раскачивается (пик не выше старта)", peak <= 0.25 + 1e-6)
	var sp2 := HeroAnim.Spring.new(5.2, 0.32)
	sp2.x = 0.25
	var min_x := 0.0
	for i in 60:
		sp2.step(1.0 / 60.0)
		min_x = minf(min_x, sp2.x)
	check("приземление «отскакивает» в растяжение (есть возврат)", min_x < -0.02)
	var big := HeroAnim.Spring.new(5.2, 0.32)
	big.x = 0.25
	big.step(0.5)
	check("устойчива и на длинном кадре", absf(big.x) < 0.5)


## Кирка: кадр удара показан именно на ударах JuiceDirector; скорость копки не меняется.
func _test_dig_sync() -> void:
	GameState.current_tool = "pickaxe"
	player.x = 20.0
	player.y = 5.0
	player.on_ground = true
	player.vx = 0.0
	player.digging = {"x": player.cell_x() + 1, "y": player.cell_y(), "t": 0.0, "total": 3.0, "type": TileTypes.Type.DIRT}
	view._reset_motion()
	view._process(0.0)
	var period: float = Juice.num("dig.hit_period_s", 0.38)
	var t := 0.0
	var dt := 1.0 / 60.0
	var hit_steps: Array[int] = []
	var frames_seen: Array[int] = []
	var next_hit := period * 0.5
	for i in 400:
		t += dt
		player.digging["t"] = t
		view._process(dt)
		frames_seen.append(_frame() if _sheet() == "dig_pick" else -1)
		# Juice бьёт в первый кадр, где t >= следующего удара.
		if t >= next_hit:
			next_hit += period
			if t > 0.2:
				hit_steps.append(i)
	var hits := 0
	var strike_seen_at_hit := 0
	for h in hit_steps:
		if h + 2 >= frames_seen.size():
			continue
		hits += 1
		# Juice бьёт в первый кадр после момента удара, кадр удара держится ~2 кадра:
		# допуск ±2 шага (33 мс) — ниже порога, на котором звук отстаёт от картинки
		if frames_seen.slice(h - 2, h + 3).has(3):
			strike_seen_at_hit += 1
		else:
			print("  промах на шаге %d: %s" % [h, str(frames_seen.slice(h - 3, h + 4))])
	check("прошло несколько ударов (%d)" % hits, hits >= 5)
	check("на каждом ударе показан кадр удара (%d из %d)" % [strike_seen_at_hit, hits], strike_seen_at_hit == hits)
	check("тайминг копки не тронут (total остался 3.0)", float(player.digging["total"]) == 3.0)
	check("лист копки — dig_pick", _sheet() == "dig_pick")
	player.digging = null


func _test_dig_follow_through() -> void:
	# копка оборвана посреди замаха — рука доигрывает до «готов», а не дёргается в стойку
	GameState.current_tool = "pickaxe"
	player.digging = {"x": player.cell_x() + 1, "y": player.cell_y(), "t": 0.0, "total": 3.0, "type": TileTypes.Type.DIRT}
	view._reset_motion()
	var dt := 1.0 / 60.0
	var t := 0.0
	for i in 12:
		t += dt
		player.digging["t"] = t
		view._process(dt)
	player.digging = null
	view._process(dt)
	check("сразу после конца копки лист ещё копки (доигрывание)", _sheet() == "dig_pick")
	var guard := 0
	while _sheet() == "dig_pick" and guard < 120:
		view._process(dt)
		guard += 1
	check("доигрывание конечно (%d кадров)" % guard, guard < 60)
	check("после доигрывания — стойка", _sheet() == "idle")


func _test_walk_by_distance() -> void:
	view._reset_motion()
	player.digging = null
	player.facing = 1
	player.x = 20.0
	player.y = 0.5
	player.on_ground = true
	var dt := 1.0 / 60.0
	view._process(dt)
	var stride0: float = view._stride
	# ход на полной скорости: 1 секунда
	for i in 60:
		player.x += 4.2 * dt
		player.vx = 4.2
		view._process(dt)
	var d_full: float = absf(float(view._stride) - stride0)
	check("при ходьбе лист ходьбы", _sheet() == "walk")
	var full_frames: float = 4.2 * 4.0 / maxf(Juice.num("steps.distance_cells", 0.85), 0.2)
	check("кадры идут по пути, ~%.0f кадров за секунду ходьбы" % full_frames, absf(fposmod(d_full - full_frames + 8.0, 16.0) - 8.0) < 2.5)
	# останавливаемся: доходим до проходной позы и встаём в idle
	player.vx = 0.0
	var guard := 0
	# Между ходьбой (профиль) и стойкой (вполоборота) — миг поворота walk_turn.
	while (_sheet() == "walk" or _sheet() == "walk_turn") and guard < 60:
		view._process(dt)
		guard += 1
	check("после остановки лист стойки (%d кадров)" % guard, _sheet() == "idle")
	check("остановка на проходной позе", fposmod(view._stride, 4.0) < 0.01 or fposmod(view._stride, 4.0) > 3.99)

	# медленнее вдвое — шаг ровно вдвое реже (ноги не скользят)
	view._reset_motion()
	view._process(dt)
	var s1: float = view._stride
	for i in 60:
		player.x += 2.1 * dt
		view._process(dt)
	var d_half: float = absf(float(view._stride) - s1)
	check("вдвое медленнее — вдвое меньше кадров", absf(fposmod(d_half - full_frames * 0.5 + 8.0, 16.0) - 8.0) < 2.5)


func _test_air_pose() -> void:
	view._reset_motion()
	player.x = 20.0
	player.y = 0.5
	player.facing = 1
	player.on_ground = false
	player.thrust = ""
	player.vy = -8.0
	var dt := 1.0 / 60.0
	for i in 8:
		view._process(dt)
	var rise := _frame()
	check("в воздухе лист прыжка/падения", _sheet() == "jump" or _sheet() == "fall")
	player.vy = 9.5
	for i in 4:
		view._process(dt)
	var fall := _frame()
	check("кадр падения отличается от кадра подъёма", rise != fall)
	player.on_ground = true
	player.vy = 0.0
	for i in 3:
		view._process(dt)
	check("приземление: корпус сжимается (scale.y < 1)", view._body.scale.y < 0.99)
	for i in 120:
		view._process(dt)
	check("потом пружина возвращает рост", absf(view._body.scale.y - 1.0) < 0.03)


## Кадры всех листов стоят на одной оси с головой (допуск по ширине тела) и не пустые.
## Геометрия листов мальчика — HeroSheets (раунд 4: 8 текселей на точку, ряды);
## допуск — в логических точках (прежние 5,5 текселя при ×3 ≈ 1,8 точки).
func _test_art_anchor() -> void:
	var ref := _head_x("idle", 0)
	check("есть эталон головы idle", ref > -900.0)
	for sheet in ["walk", "jump", "hurt", "idle_x"]:
		var path := "res://art/character/%s.png" % sheet
		if not ResourceLoader.exists(path):
			continue
		var inf: Dictionary = HeroSheets.info(sheet)
		if inf.is_empty():
			continue
		var img: Image = (load(path) as Texture2D).get_image()
		var n: int = HeroSheets.frames_of(inf)
		var cols: int = int(inf["cols"])
		var rows: int = int(ceil(float(n) / float(cols)))
		check("%s: лист вмещает %d кадров" % [sheet, n],
				img.get_width() == cols * int(inf["fw"]) and img.get_height() == rows * int(inf["fh"]))
		var worst := 0.0
		var empty := 0
		for i in n:
			var hx := _head_x(sheet, i)
			if hx < -900.0:
				empty += 1
				continue
			worst = maxf(worst, absf(hx - ref))
		check("%s: пустых кадров нет" % sheet, empty == 0)
		var tol := 4.4 if sheet == "hurt" else 1.85
		check("%s: голова не уходит с оси (макс. %.2f из %.2f точки)" % [sheet, worst, tol], worst <= tol)


## Центр головы кадра относительно оси кадра, в логических точках (-1000 — пусто).
func _head_x(sheet: String, frame: int) -> float:
	var inf: Dictionary = HeroSheets.info(sheet)
	if inf.is_empty():
		return -1000.0
	var img: Image = (load("res://art/character/%s.png" % sheet) as Texture2D).get_image()
	var r: Rect2 = HeroSheets.region(inf, frame)
	var x0 := int(r.position.x)
	var y0 := int(r.position.y)
	var fw := int(r.size.x)
	var fh := int(r.size.y)
	var sc: float = HeroSheets.scale_of(inf)
	var top := -1
	for y in fh:
		for x in fw:
			if img.get_pixel(x0 + x, y0 + y).a > 0.5:
				top = y
				break
		if top >= 0:
			break
	if top < 0:
		return -1000.0
	var sum := 0.0
	var cnt := 0
	for y in range(top, mini(top + int(16.0 / 3.0 * sc), fh)):
		for x in fw:
			if img.get_pixel(x0 + x, y0 + y).a > 0.5:
				sum += float(x)
				cnt += 1
	return (sum / float(cnt) - fw * 0.5) / sc if cnt > 0 else -1000.0


## Слой движения не должен отнимать кадр: средняя цена _process по состояниям.
## Порог — на порядок выше ожидаемого (≈50 мкс), чтобы загруженная машина не краснила тест.
func _test_cost() -> void:
	var dt := 1.0 / 60.0
	for state in ["walk", "dig", "fly"]:
		view._reset_motion()
		player.digging = null
		player.thrust = ""
		player.on_ground = true
		player.facing = 1
		player.x = 20.0
		player.y = 5.0
		if state == "fly":
			GameState.current_gear = "jetpack"
			player.on_ground = false
		var t0 := Time.get_ticks_usec()
		var n := 600
		for i in n:
			if state == "walk":
				player.x += 4.2 * dt
				if player.x > 40.0:
					player.x = 20.0
			elif state == "dig":
				player.digging = {"x": player.cell_x() + 1, "y": player.cell_y(), "t": float(i) * dt, "total": 99.0, "type": TileTypes.Type.DIRT}
			elif state == "fly":
				player.thrust = "jet"
				player.vy = -2.0
			view._process(dt)
		var us := float(Time.get_ticks_usec() - t0) / float(n)
		print("  _process (%s): %.0f мкс/кадр" % [state, us])
		check("цена кадра героя (%s) %.0f мкс < 2000" % [state, us], us < 2000.0)
	player.digging = null
	player.thrust = ""
	GameState.current_gear = ""


## Простой: дыхание всегда, моргание изредка, оглядывание и постукивание после долгого простоя.
func _test_idle_extras() -> void:
	view._reset_motion()
	player.digging = null
	player.x = 20.0
	player.y = 5.0
	player.on_ground = true
	player.vx = 0.0
	view._rng.seed = 7
	var dt := 1.0 / 60.0
	view._process(dt)
	var blink := 0
	var look := 0
	var tap := 0
	var total_frames := 0
	var frames_seen := {}
	for i in 60 * 24:
		view._process(dt)
		total_frames += 1
		if _sheet() == "idle_x":
			var f := _frame()
			frames_seen[f] = true
			if f == 0:
				blink += 1
			elif f <= 2:
				look += 1
			else:
				tap += 1
	check("за 24 с простоя герой моргал (%d кадров)" % blink, blink > 6)
	check("моргание короткое (%.1f%% времени)" % [100.0 * blink / total_frames], blink < total_frames / 10)
	check("после долгого простоя оглядывался (%d кадров)" % look, look > 20)
	check("после долгого простоя постукивал ногой (%d кадров)" % tap, tap > 20)
	check("кадр стойки — исходный idle.png в большинстве кадров", _sheet() == "idle" or _sheet() == "idle_x")


func _test_reduce_motion() -> void:
	var dt := 1.0 / 60.0
	view._reset_motion()
	player.x = 20.0
	player.y = 0.5
	player.on_ground = true
	player.digging = null
	var worst := 1.0
	var worst_soft := 1.0
	for soft in [false, true]:
		Settings.reduce_motion = soft
		view._reset_motion()
		view._process(dt)
		view._on_landed(18.0)
		var low := 1.0
		for i in 20:
			view._process(dt)
			low = minf(low, view._body.scale.y)
		if soft:
			worst_soft = low
		else:
			worst = low
	Settings.reduce_motion = false
	check("«Уменьшить движение» смягчает сжатие при приземлении (%.3f против %.3f)" % [worst_soft, worst], (1.0 - worst_soft) < (1.0 - worst) * 0.6)


func _test_death_cycle() -> void:
	var dt := 1.0 / 60.0
	view._reset_motion()
	player.x = 20.0
	player.y = 0.5
	player.on_ground = true
	GameState.is_alive = true
	view._process(dt)
	view.on_died()
	GameState.is_alive = false
	check("в headless смерть не задерживает возрождение", not view.death_playing())
	for i in 40:
		view._process(dt)
	check("после падения корпус лежит (поворот > 60°)", absf(view._body.rotation) > deg_to_rad(60.0))
	GameState.is_alive = true
	view._process(dt)
	check("воскрес мимо сигнала — герой снова на ногах", view._death_t < 0.0)
	for i in 40:
		view._process(dt)
	check("после воскрешения поза обычная", absf(view._body.rotation) < deg_to_rad(8.0) and view._body.scale.x > 0.95)

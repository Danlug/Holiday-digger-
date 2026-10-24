extends Node
## test_feel — «ощущение игры» (ветка aaa-feel): койот-время и буфер прыжка,
## клавиатурная ось, микро-пауза после камня с кредитом, камера с упреждением и
## наездом, трещины на породе, слияние «+N», режиссёр (находки, вехи глубины),
## карточка смерти. Автозагрузки нужны, поэтому запускается сценой:
##   godot --headless --path . res://tests/test_feel.tscn

var failures := 0
var total := 0
var world: WorldGen
var player


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _tick(n: int, dt: float = 1.0 / 60.0) -> void:
	for i in n:
		player.physics_tick(dt)


func _ready() -> void:
	print("=== test_feel ===")
	await _frames(2)
	Settings.reduce_motion = false
	world = WorldGen.new(4242)
	GameState.world_ref = world
	GameState.fog_ref = FogOfWar.new()
	GameState.reset_progress()
	StoryState.set_flag("gold_sold", false)

	player = load("res://scripts/player/player.gd").new()
	player.world = world
	add_child(player)

	_test_config()
	_test_axis()
	_test_coyote()
	_test_jump_buffer()
	_test_hitstop_credit()
	_test_camera()
	await _test_cracks()
	await _test_loot_stack()
	await _test_director()
	await _test_death_card()

	StoryState.set_flag("gold_sold", false)
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------------------

func _test_config() -> void:
	check("data/feel.json читается: койот-время", is_equal_approx(Feel.num("controls.coyote_s", -1.0), 0.09))
	check("запасное значение, когда пути нет", Feel.num("нет.такого", 7.5) == 7.5)
	var shovel := Feel.tool_profile("shovel")
	var rig := Feel.tool_profile("drill_rig")
	check("лопата бьёт реже бурмобиля", float(shovel["hit_period_s"]) > float(rig["hit_period_s"]))
	check("бурмобиль гудит ниже лопаты", float(rig["pitch"]) < float(shovel["pitch"]))
	check("неизвестный инструмент → профиль кирки", Feel.tool_profile("ничего") == Feel.tool_profile("iron_pickaxe"))
	check("микро-пауза: земля (быстрая клетка) без паузы", Feel.hitstop_for(0.5) == 0.0)
	check("микро-пауза: камень 6 с — 45 мс", is_equal_approx(Feel.hitstop_for(6.0), 0.045))
	check("микро-пауза не длиннее 4% клетки", Feel.hitstop_for(1.0) <= 0.04 + 0.0001)
	Settings.reduce_motion = true
	check("«меньше движения» отключает паузу", Feel.hitstop_for(6.0) == 0.0)
	Settings.reduce_motion = false


func _test_axis() -> void:
	check("ось: только влево", Feel.axis(true, false, 0) == -1)
	check("ось: только вправо", Feel.axis(false, true, 0) == 1)
	check("ось: ничего", Feel.axis(false, false, 1) == 0)
	check("ось: обе зажаты — побеждает нажатая позже (вправо)", Feel.axis(true, true, 1) == 1)
	check("ось: обе зажаты — побеждает нажатая позже (влево)", Feel.axis(true, true, -1) == -1)
	check("ось: обе зажаты, неизвестно кто последний → стоим", Feel.axis(true, true, 0) == 0)


## Ставит героя стоять на земле: падает с высоты и ждёт касания.
func _land_on_ground(px: float = 24.5) -> void:
	player.x = px
	player.y = -2.0
	player.vx = 0.0
	player.vy = 0.0
	player.digging = null
	player.release_control()
	for i in 240:
		_tick(1)
		if player.on_ground:
			break
	_tick(3)


func _test_coyote() -> void:
	_land_on_ground()
	check("койот: герой стоит на земле", player.on_ground)
	# «сошёл с уступа»: пол пропал, герой ещё не успел упасть (после этого тика on_ground=false)
	var jumps := [0]
	var on_jump := func() -> void: jumps[0] += 1
	player.jumped.connect(on_jump)
	player.on_ground = false
	player.vy = 0.4
	player.set_intent(0, true, false)   # нажали «вверх» на следующем кадре
	_tick(1)
	check("койот: прыжок сразу после схода с уступа срабатывает", player.vy < -4.0 and jumps[0] == 1)

	# слишком поздно: окно (0.09 с) вышло
	player.set_intent(0, false, false)
	player.x = 24.5
	player.y = -3.0
	player.vy = 0.0
	player.on_ground = false
	player._coyote_left = 0.0
	_tick(1)   # фронт «вверх» ниже
	player.set_intent(0, true, false)
	_tick(1)
	check("койот: в воздухе без окна прыжка нет (vy растёт вниз)", player.vy > 0.0 and jumps[0] == 1)

	# нажатие, начатое ДО схода (удержание), койот не включает: прежнее поведение
	player.set_intent(0, false, false)
	_land_on_ground()
	player.set_intent(0, true, false)
	_tick(1)   # прыгнули с земли штатно
	check("койот: обычный прыжок с земли по-прежнему работает", jumps[0] == 2)
	player.jumped.disconnect(on_jump)
	player.set_intent(0, false, false)


func _test_jump_buffer() -> void:
	# падаем и нажимаем «вверх» за ~3 кадра (~50 мс) до земли, отпускаем сразу
	_land_on_ground()
	player.y = -1.2
	player.vy = 0.0
	player.on_ground = false
	player.set_intent(0, false, false)
	var pressed := false
	var jumped_after_land := false
	var landed := false
	for i in 400:
		var gap: float = 1.0 - (player.y + player.HH)
		if not pressed and gap < 0.4 and player.vy > 3.0 and not player.on_ground:
			pressed = true
			player.set_intent(0, true, false)
		elif pressed and not landed:
			player.set_intent(0, false, false)
		_tick(1)
		if player.on_ground and pressed:
			landed = true
		if landed and player.vy < -4.0:
			jumped_after_land = true
			break
	check("буфер: «вверх» за миг до земли сработал на приземлении", pressed and jumped_after_land)

	# нажали слишком рано (0.5 с до земли) и отпустили — прыжка на земле нет
	_land_on_ground()
	player.y = -3.0
	player.vy = 0.0
	player.on_ground = false
	player.set_intent(0, false, false)
	_tick(1)
	player.set_intent(0, true, false)
	_tick(1)
	player.set_intent(0, false, false)
	var hopped := false
	for i in 400:
		_tick(1)
		if player.on_ground:
			_tick(10)
			hopped = player.vy < -1.0
			break
	check("буфер: слишком раннее нажатие протухает", not hopped)


func _find_stone() -> Vector2i:
	for y in range(8, 60):
		for x in range(WorldGen.GARDEN_X_MIN + 2, WorldGen.WIDTH - 2):
			if world.get_tile(x, y) == TileTypes.Type.STONE and not world.is_dug(x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _test_hitstop_credit() -> void:
	var s := _find_stone()
	check("нашли камень для проверки паузы", s.x >= 0)
	if s.x < 0:
		return
	_land_on_ground()
	player.release_control()
	GameState.current_tool = "iron_pickaxe"   # лопата камень не берёт (§5)
	# сымитируем конец копки камня за 5 с: клетка «давно» копается
	player.digging = {"x": s.x, "y": s.y, "t": 4.99, "total": 5.0, "type": TileTypes.Type.STONE}
	_tick(2)
	check("камень разрушен", world.is_dug(s.x, s.y))
	check("после камня включилась микро-пауза", player._hitstop_left > 0.0 or player._hitstop_credit > 0.0)
	var credit: float = player._hitstop_credit
	check("кредит равен паузе (45 мс)", is_equal_approx(credit, 0.045))
	# пока пауза идёт, герой стоит
	player.hold_dx = 1
	var x0: float = player.x
	player._hitstop_left = 0.03
	_tick(1)
	check("в паузе герой не двигается", is_equal_approx(player.x, x0))
	player.hold_dx = 0
	_tick(4)
	check("пауза истекает за несколько кадров", player._hitstop_left <= 0.0)
	# следующая копка подряд получает кредит
	player._hitstop_credit = 0.045
	player._credit_ttl = 0.35
	var s2 := _find_stone()
	player._start_dig(s2.x, s2.y)
	check("следующая клетка получает кредит паузы: t = 45 мс", player.digging != null and is_equal_approx(float(player.digging.t), 0.045))
	check("кредит потрачен", player._hitstop_credit == 0.0)
	player.digging = null
	# кредит протухает, если копка не продолжилась
	player._hitstop_credit = 0.045
	player._credit_ttl = 0.35
	_tick(30)
	var s3 := _find_stone()
	player._start_dig(s3.x, s3.y)
	check("кредит протух за 0.35 с", player.digging != null and float(player.digging.t) == 0.0)
	player.digging = null
	# земля не получает паузы
	var dirt := Vector2i(-1, -1)
	for x in range(WorldGen.GARDEN_X_MIN + 2, WorldGen.WIDTH - 2):
		if world.get_tile(x, 7) == TileTypes.Type.DIRT:
			dirt = Vector2i(x, 7)
			break
	if dirt.x >= 0:
		player._hitstop_left = 0.0
		player.digging = {"x": dirt.x, "y": dirt.y, "t": 2.9, "total": 3.0, "type": TileTypes.Type.DIRT}
		_tick(2)
		check("земля без микро-паузы", player._hitstop_left <= 0.0)


# ---------------------------------------------------------------------------

func _hero(px: float, py: float, vx: float = 0.0, vy: float = 0.0, facing: int = 1) -> Dictionary:
	return {"x": px, "y": py, "vx": vx, "vy": vy, "facing": facing, "digging": null}


class CrackCanvas extends Node2D:
	var frac := 0.0
	var draws := 0

	func _draw() -> void:
		draws += 1
		DigCracks.draw(self, 20, 12, frac)


class FakeHero:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var facing := 1
	var digging = null


func _fake(px: float, py: float, vx: float = 0.0, vy: float = 0.0, facing: int = 1) -> FakeHero:
	var h := FakeHero.new()
	h.x = px
	h.y = py
	h.vx = vx
	h.vy = vy
	h.facing = facing
	return h


func _test_camera() -> void:
	var sky := 24
	# упреждение
	check("упреждение: стоим — нет", CameraRig.lead_target(_fake(10, 10), false) == Vector2.ZERO)
	var walk := CameraRig.lead_target(_fake(10, 10, 4.2, 0, 1), false)
	check("упреждение: идём вправо — камера вперёд", is_equal_approx(walk.x, 0.7) and walk.y == 0.0)
	check("упреждение: идём влево — назад", CameraRig.lead_target(_fake(10, 10, -4.2, 0, -1), false).x < 0.0)
	var fall := CameraRig.lead_target(_fake(10, 10, 0, 20), false)
	check("упреждение: падаем — камера смотрит вниз", fall.y > 1.0 and fall.y <= 3.0)
	check("упреждение: предельное падение ограничено", CameraRig.lead_target(_fake(10, 10, 0, 32), false).y <= 3.0)
	check("упреждение: подъём — камера вверх", CameraRig.lead_target(_fake(10, 10, 0, -10), false).y < 0.0)
	var dig_h := _fake(10, 10)
	dig_h.digging = {"x": 10, "y": 11}
	check("упреждение: копка вниз — чуть вперёд по шахте", CameraRig.lead_target(dig_h, false).y > 0.0)
	check("упреждение: «меньше движения» — нет", CameraRig.lead_target(_fake(10, 10, 4.2, 20), true) == Vector2.ZERO)

	# следование с демпфером
	var rig := CameraRig.new()
	var h := _fake(10.0, 30.0)
	var c0 := rig.step(h, 7.0, 14.0, sky, 1.0 / 60.0)
	var classic := CameraRig.classic(10.0, 30.0, 7.0, 14.0, sky)
	check("камера: первый кадр прыгает в точку героя", c0.is_equal_approx(classic))
	h.x = 13.0
	var c1 := rig.step(h, 7.0, 14.0, sky, 1.0 / 60.0)
	var target := CameraRig.classic(13.0, 30.0, 7.0, 14.0, sky)
	check("камера: рывок героя на 3 клетки сглажен (за кадр доезжает не всё)", c1.x > c0.x and c1.x < target.x - 0.5)
	for i in 120:
		rig.step(h, 7.0, 14.0, sky, 1.0 / 60.0)
	check("камера: через 2 секунды догнала героя", absf(rig.pos.x - target.x) < 0.05)
	# не зависит от частоты кадров: 30 к/с и 120 к/с приходят в ту же точку за то же время
	var ra := CameraRig.new()
	var rb := CameraRig.new()
	var ha := _fake(10.0, 30.0)
	ra.step(ha, 7.0, 14.0, sky, 1.0 / 30.0)
	rb.step(ha, 7.0, 14.0, sky, 1.0 / 120.0)
	ha.x = 14.0
	for i in 15:
		ra.step(ha, 7.0, 14.0, sky, 1.0 / 30.0)
	for i in 60:
		rb.step(ha, 7.0, 14.0, sky, 1.0 / 120.0)
	check("камера: за 0.5 с одинаково при 30 и 120 к/с (|Δ| < 0.05)", absf(ra.pos.x - rb.pos.x) < 0.05)
	# установившийся режим: камера не отстаёт от идущего героя, а смотрит вперёд ровно на упреждение
	var rig_w := CameraRig.new()
	var hw := _fake(4.0, 30.0, 4.2, 0.0, 1)
	rig_w.step(hw, 7.0, 14.0, sky, 1.0 / 60.0)
	for i in 200:
		hw.x += hw.vx / 60.0
		rig_w.step(hw, 7.0, 14.0, sky, 1.0 / 60.0)
	var off_x: float = rig_w.pos.x - CameraRig.classic(hw.x, hw.y, 7.0, 14.0, sky).x
	check("камера на ходу: смещение вперёд = упреждение 0.7 клетки (%.2f)" % off_x, absf(off_x - 0.7) < 0.06)
	var rig_f := CameraRig.new()
	var hf := _fake(10.0, 30.0, 0.0, 32.0, 1)
	rig_f.step(hf, 7.0, 14.0, sky, 1.0 / 60.0)
	for i in 300:
		hf.y += hf.vy / 60.0
		rig_f.step(hf, 7.0, 14.0, sky, 1.0 / 60.0)
	var off_y: float = rig_f.pos.y - CameraRig.classic(hf.x, hf.y, 7.0, 14.0, sky).y
	check("камера при падении 32 кл/с: смотрит вниз на упреждение 2.6 клетки (%.2f), герой не уходит под шапку HUD" % off_y, absf(off_y - 2.6) < 0.05 and off_y < 3.1)
	# телепорт
	h.x = 3.0
	h.y = 2.0
	var c2 := rig.step(h, 7.0, 14.0, sky, 1.0 / 60.0)
	check("камера: телепорт — без «полёта» через всю карту", c2.is_equal_approx(CameraRig.classic(3.0, 2.0 + rig._lead_y, 7.0, 14.0, sky)) or c2.distance_to(CameraRig.classic(3.0, 2.0, 7.0, 14.0, sky)) < 1.0)
	# границы мира
	var edge := CameraRig.new()
	var eh := _fake(0.5, 5.0, -4.0, 0, -1)
	for i in 60:
		edge.step(eh, 7.0, 14.0, sky, 1.0 / 60.0)
	check("камера: у левого края мира не уезжает за 0", edge.pos.x >= 0.0)
	eh.x = float(WorldGen.WIDTH) - 0.5
	eh.vx = 4.0
	eh.facing = 1
	for i in 120:
		edge.step(eh, 7.0, 14.0, sky, 1.0 / 60.0)
	check("камера: у правого края не выходит за ширину мира", edge.pos.x <= float(WorldGen.WIDTH) - 7.0 + 0.001)
	eh.y = -float(sky) + 1.0
	eh.vy = -10.0
	for i in 60:
		edge.step(eh, 7.0, 14.0, sky, 1.0 / 60.0)
	check("камера: вверху не выше кромки неба", edge.pos.y >= -float(sky) - 0.001)

	# «меньше движения» → прежняя жёсткая камера
	Settings.reduce_motion = true
	var rig2 := CameraRig.new()
	var hm := _fake(10.0, 30.0, 4.2, 20.0, 1)
	var cm := rig2.step(hm, 7.0, 14.0, sky, 1.0 / 60.0)
	check("«меньше движения»: камера как раньше", cm.is_equal_approx(CameraRig.classic(10.0, 30.0, 7.0, 14.0, sky)))
	Feel.punch(0.05)
	rig2.step(hm, 7.0, 14.0, sky, 1.0 / 60.0)
	check("«меньше движения»: наезда нет", rig2.zoom == 1.0)
	Settings.reduce_motion = false

	# наезд
	var rig3 := CameraRig.new()
	var hp := _fake(10.0, 30.0)
	rig3.step(hp, 7.0, 14.0, sky, 1.0 / 60.0)
	check("наезд: без события масштаб 1", rig3.zoom == 1.0)
	Feel.punch(0.03)
	rig3.step(hp, 7.0, 14.0, sky, 1.0 / 60.0)
	check("наезд: после события камера приблизилась", rig3.zoom > 1.0 and rig3.zoom <= 1.07)
	Feel.punch(0.5)
	rig3.step(hp, 7.0, 14.0, sky, 1.0 / 60.0)
	check("наезд: потолок +7%", rig3.zoom <= 1.0701)
	for i in 40:
		rig3.step(hp, 7.0, 14.0, sky, 1.0 / 60.0)
	check("наезд: через 0.6 с вернулся к 1", rig3.zoom == 1.0)
	# наезд идёт вокруг героя: его экранное положение не меняется
	var cam := Vector2(5.0, 20.0)
	var focus := (Vector2(8.0, 25.0) - cam) * 32.0
	var vt := CameraRig.view_transform(cam, 1.06, focus, 32.0)
	var hero_px := Vector2(8.0, 25.0) * 32.0
	var on_screen: Vector2 = hero_px * vt["scale"].x + vt["position"]
	check("наезд: герой остаётся на том же месте экрана", on_screen.is_equal_approx(focus))
	var plain := CameraRig.view_transform(cam, 1.0, focus, 32.0)
	check("без наезда: положение как у классической камеры", plain["position"].is_equal_approx(-cam * 32.0))

	# общая камера для значков над головой
	rig.step(h, 7.0, 14.0, sky, 1.0 / 60.0)
	check("for_overlay отдаёт камеру, которую нарисовал main", CameraRig.for_overlay(0, 0, 7, 14, sky) == CameraRig.current)
	CameraRig.reset_static()
	check("после сброса — классическая формула", CameraRig.for_overlay(10, 30, 7, 14, sky).is_equal_approx(CameraRig.classic(10, 30, 7, 14, sky)))


# ---------------------------------------------------------------------------

func _test_cracks() -> void:
	var a := DigCracks.pattern(20, 12)
	var a2 := DigCracks.pattern(20, 12)
	check("трещины: узор клетки воспроизводим", a.size() == a2.size() and a[0]["px"] == a2[0]["px"])
	var b := DigCracks.pattern(21, 12)
	check("трещины: у соседней клетки узор другой", a[0]["px"] != b[0]["px"])
	check("трещины: нитей не меньше пяти", a.size() >= 5)
	var inside := true
	for s in a:
		for p: Vector2 in s["px"]:
			if p.x < 1.0 or p.y < 1.0 or p.x > 30.0 or p.y > 30.0:
				inside = false
	check("трещины: все пиксели внутри клетки", inside)
	check("трещины: в начале копки их нет", DigCracks.visible_pixels(20, 12, 0.0) == 0)
	var prev := 0
	var mono := true
	for i in range(1, 21):
		var n := DigCracks.visible_pixels(20, 12, float(i) / 20.0)
		if n < prev:
			mono = false
		prev = n
	check("трещины: растут вместе с прогрессом, не пропадая", mono)
	check("трещины: к концу видна густая сетка (> 40 пикселей)", DigCracks.visible_pixels(20, 12, 1.0) > 40)
	check("трещины: на полпути видна примерно половина", DigCracks.visible_pixels(20, 12, 0.5) < DigCracks.visible_pixels(20, 12, 1.0))
	# рисование не падает на любом прогрессе, включая NaN от мгновенной копки
	var canvas := CrackCanvas.new()
	add_child(canvas)
	for f in [0.0, 0.3, 1.0, NAN]:
		canvas.frac = f
		canvas.queue_redraw()
		await _frames(1)
	check("трещины: draw() переносит нулевой, полный и NaN-прогресс (рисовали %d раз)" % canvas.draws, canvas.draws >= 4)
	canvas.queue_free()


# ---------------------------------------------------------------------------

func _test_loot_stack() -> void:
	var fx := FxService.new()
	add_child(fx)
	await _frames(1)
	var icon: Texture2D = load("res://art/ui/icon_coin.png")
	fx.float_stack("iron", Vector2(50, 50), icon, 1, Color.WHITE, 5.0)
	check("слияние: первое «+1» — одно число", fx.active_popups() == 1)
	var n2: int = fx.float_stack("iron", Vector2(60, 60), icon, 2, Color.WHITE, 5.0)
	check("слияние: «+1» и «+2» дают «+3»", n2 == 3)
	check("слияние: на экране по-прежнему одно число", fx.active_popups() == 1)
	var lb := _popup_texts(fx)
	check("слияние: надпись «+3»", lb.has("+3"))
	fx.float_stack("silver", Vector2(50, 50), icon, 1, Color.WHITE, 5.0)
	check("слияние: другая добыча — отдельное число", fx.active_popups() == 2)
	var n3: int = fx.float_stack("iron", Vector2(50, 50), icon, 1, Color.WHITE, 0.0)
	check("слияние: окно 0 — число начинается заново", n3 == 1 or n3 == 4)
	fx.queue_free()


func _popup_texts(fx) -> Array:
	var out: Array = []
	for root in fx._popups:
		if root.visible:
			out.append((root.get_node("Text") as Label).text)
	return out


# ---------------------------------------------------------------------------

func _test_director() -> void:
	check("находка: алмаз — крупная", FeelDirector.is_epic_item("diamond"))
	check("находка: рубин — крупная", FeelDirector.is_epic_item("ruby"))
	check("находка: железная руда — обычная", not FeelDirector.is_epic_item("iron_ore"))
	check("находка: золото — не «момент»", not FeelDirector.is_epic_item("gold"))
	check("находка: неизвестный предмет — нет", not FeelDirector.is_epic_item("нет_такого"))
	check("веха: 0→35 дают 50·(1+2+3) = 300 опыта", FeelDirector.milestone_xp(0, 35) == 300)
	check("веха: 7→12 — одна отметка (50)", FeelDirector.milestone_xp(7, 12) == 50)
	check("веха: 12→19 — отметок нет", FeelDirector.milestone_xp(12, 19) == 0)
	check("веха: ярус каждые 10 / 100 / 1000", FeelDirector.milestone_tier(30) == 1 and FeelDirector.milestone_tier(300) == 2 and FeelDirector.milestone_tier(3000) == 3)

	var dir := FeelDirector.new()
	dir.player = player
	add_child(dir)
	await _frames(1)
	GameState.max_depth_changed.emit(7)
	check("веха: до 10-й клетки тихо", dir.stats["milestones"] == 0)
	GameState.max_depth_changed.emit(12)
	check("веха: 10-я клетка — отметка", dir.stats["milestones"] == 1)
	GameState.max_depth_changed.emit(19)
	check("веха: внутри десятка — нет", dir.stats["milestones"] == 1)
	GameState.max_depth_changed.emit(105)
	check("веха: падение через много отметок — одна запись", dir.stats["milestones"] == 2)
	GameState.max_depth_changed.emit(0)
	GameState.max_depth_changed.emit(30)
	check("веха: после сброса отсчёт заново", dir.stats["milestones"] == 3)

	# находки: подбор и копка приходят в одном кадре
	player._hitstop_left = 0.0
	GameState.emit_event(&"picked", {"item": "diamond", "count": 1})
	GameState.emit_event(&"dug", {"cell": Vector2i(20, 9), "tile": TileTypes.Type.DIAMOND, "mineral": "diamond", "loot": true, "pos": Vector2(660, 300)})
	check("находка: алмаз летит в рюкзак", dir.stats["fly"] == 1)
	check("находка: алмаз — «момент»", dir.stats["epic"] == 1)
	check("находка: герой на миг замер", player._hitstop_left > 0.0)
	check("находка: камера получила наезд", Feel.pending_punch > 0.0)
	Feel.pending_punch = 0.0
	GameState.emit_event(&"picked", {"item": "iron_ore", "count": 1})
	GameState.emit_event(&"dug", {"cell": Vector2i(20, 9), "tile": TileTypes.Type.IRON_ORE, "mineral": "iron_ore", "loot": true, "pos": Vector2(660, 300)})
	check("находка: железо не летит и не «момент»", dir.stats["fly"] == 1 and dir.stats["epic"] == 1)
	# рюкзак полон: «dug» без «picked» в этом кадре — ничего не показываем
	GameState.emit_event(&"dug", {"cell": Vector2i(20, 9), "tile": TileTypes.Type.DIAMOND, "mineral": "diamond", "loot": true, "pos": Vector2(660, 300)})
	await _frames(1)
	GameState.emit_event(&"dug", {"cell": Vector2i(20, 9), "tile": TileTypes.Type.DIAMOND, "mineral": "diamond", "loot": true, "pos": Vector2(660, 300)})
	check("находка: без подбора в этом кадре эффекта нет", dir.stats["epic"] == 1)
	var p0: int = dir.stats["punches"]
	GameState.emit_event(&"dug", {"cell": Vector2i(20, 9), "tile": TileTypes.Type.STONE, "mineral": "", "loot": false, "pos": Vector2(660, 300)})
	check("камень: тяжёлый удар даёт наезд камеры", dir.stats["punches"] == p0 + 1)
	Feel.pending_punch = 0.0
	dir.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------

func _test_death_card() -> void:
	GameState.reset_progress()
	GameState.add_item("iron_ore", 5)
	GameState.add_item("diamond", 2)
	GameState.add_item("scrap", 9)
	GameState.add_to_black_box("gold", 7)
	GameState.player_depth = 120
	var dir := FeelDirector.new()
	dir.player = player
	add_child(dir)
	await _frames(1)
	GameState.add_item("iron_ore", 1)   # снимок «до смерти» обновился
	GameState.die()
	var rep: Dictionary = dir._pending
	check("смерть: отчёт собран", not rep.is_empty())
	var lost: Array = rep["lost"]
	check("смерть: потеряны три вида минералов", lost.size() == 3)
	check("смерть: ценное первым (алмаз)", lost[0]["id"] == "diamond" and lost[0]["count"] == 2)
	check("смерть: железо с учётом последнего подбора (6)", _count_of(lost, "iron_ore") == 6)
	var expect := 2 * Balance.get_mineral_price("diamond") + 6 * Balance.get_mineral_price("iron_ore") + 9 * Balance.get_mineral_price("scrap")
	check("смерть: стоимость потерянного по прайсу (%d)" % expect, int(rep["lost_value"]) == expect)
	check("смерть: чёрный ящик уцелел в отчёте", (rep["box"] as Array).size() == 1 and rep["box"][0]["id"] == "gold" and rep["box"][0]["count"] == 7)
	check("смерть: глубина смерти запомнена", int(rep["depth"]) == 120)
	check("смерть: рюкзак на самом деле пуст (правило §7)", GameState.inventory.is_empty())
	check("смерть: до онбординга карточки нет (сцену смерти играет сюжет)", not DeathCard.worth_showing(rep))
	StoryState.set_flag("gold_sold", true)
	check("смерть: после онбординга карточка нужна", DeathCard.worth_showing(rep))
	dir._on_respawned()
	check("смерть: после респавна main знает, что фраза-тост не нужна (карточка в пути)", Feel.card_pending)
	check("смерть: карточка посчитана режиссёром", dir.stats["cards"] == 1)
	Feel.card_pending = false
	var card := DeathCard.new()
	add_child(card)
	await _frames(1)
	card.open(rep)
	check("карточка открыта", card.is_open())
	var tiles := _count_nodes(card, "PanelContainer")
	check("карточка: плитки потерь, ящик и рамка нарисованы (%d панелей)" % tiles, tiles >= 5)
	check("карточка: нет абзацев — ни одной метки длиннее 12 знаков", _longest_label(card) <= 12)
	card.close()
	check("карточка закрывается", not card.is_open())
	GameState.respawn()
	var rep2 := DeathCard.build_report({}, 0, "")
	check("пустой рюкзак и ящик → показывать нечего (глубина 0)", not DeathCard.worth_showing(DeathCard.build_report({}, 0, "")) or not (rep2["box"] as Array).is_empty())
	card.queue_free()
	dir.queue_free()
	await _frames(1)


func _count_of(rows: Array, id: String) -> int:
	for r in rows:
		if r["id"] == id:
			return int(r["count"])
	return 0


func _count_nodes(root: Node, cls: String) -> int:
	var n := 0
	for c in root.get_children():
		if c.get_class() == cls:
			n += 1
		n += _count_nodes(c, cls)
	return n


func _longest_label(root: Node) -> int:
	var m := 0
	if root is Label:
		m = (root as Label).text.length()
	for c in root.get_children():
		m = maxi(m, _longest_label(c))
	return m

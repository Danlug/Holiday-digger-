extends Node
## test_luck_juice — отклик удачной находки (владелец, 27.10): «размер иконки выкопанного
## с надписью множителя на 20 процентов больше, чем обычно, и звук получения громче на 50,
## вспышка 15 процентов, сотрясение + зум камеры 5 процентов». Настоящий Player и
## JuiceDirector, сервисы звука и эффектов — записывающая заглушка; камера шагает вручную
## (CameraKick.tick), реальное время не нужно. Обычная находка — без изменений.
##
## Запуск: godot --headless --path . res://tests/test_luck_juice.tscn

var failures := 0
var total := 0
var rec: _Rec
var director: JuiceDirector


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_luck_juice ===")
	for _i in range(4):
		await get_tree().process_frame
	_test_numbers()
	rec = _Rec.new()
	rec.add_to_group(Sfx.GROUP)
	rec.add_to_group(Fx.GROUP)
	add_child(rec)
	_test_normal_find()
	_test_lucky_find()
	_test_zoom_return()
	_test_earth_luck()
	_test_reduce_motion()
	rec.queue_free()
	if is_instance_valid(director):
		director.queue_free()
	await get_tree().process_frame
	await _test_popup_scale()
	_test_sound_service()
	CameraKick.reset()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_numbers() -> void:
	check("значок и «×N» крупнее в 1.2 раза", is_equal_approx(LuckJuice.icon_scale(), 1.2))
	check("звук подбора: амплитуда ×1.5 (%.2f дБ)" % LuckJuice.sound_db(),
			absf(db_to_linear(LuckJuice.sound_db()) - 1.5) < 0.001 and absf(LuckJuice.sound_db() - 3.52) < 0.01)
	check("вспышка — непрозрачность 0.15", is_equal_approx(LuckJuice.flash_color().a, 0.15))
	check("вспышка — цвет удачи", LuckJuice.flash_color().is_equal_approx(Color(Color8(0xFF, 0xD8, 0x4A), 0.15)))
	check("наезд камеры 5%", is_equal_approx(Juice.num("luck.zoom", 0.0), 0.05))


# ---------------------------------------------------------------------------
# Копка: настоящий Player, режиссёр «сока» и записывающая заглушка сервисов
# ---------------------------------------------------------------------------

func _fresh() -> void:
	GameState.reset_progress()
	GameState.is_alive = true
	GameState.house_is_indoors = false
	GameState.debug_invincible = false
	GameState.current_tool = "iron_pickaxe"
	GameState.skill_stages["luck_chance"] = 5
	GameState.skill_stages["luck_multiplier"] = 2
	Settings.reduce_motion = false
	CameraKick.reset()
	rec.clear()


func _player(world: WorldGen) -> Node:
	var p = preload("res://scripts/player/player.gd").new()
	p.world = world
	add_child(p)
	if director == null:
		director = JuiceDirector.new()
		director.player = p
		add_child(director)
	director.player = p
	return p


## Сид, у которого первый бросок попадает (или не попадает) в percent.
func _rng(percent: float, hit: bool) -> RandomNumberGenerator:
	for s in range(1, 5000):
		var r := RandomNumberGenerator.new()
		r.seed = s
		if (r.randf() * 100.0 < percent) == hit:
			var out := RandomNumberGenerator.new()
			out.seed = s
			return out
	return null


func _find(world: WorldGen, want_loot: bool, want_type: int = -1) -> Vector2i:
	for y in range(30, 400):
		for x in range(0, 40):
			var t := world.get_tile(x, y)
			if t == TileTypes.Type.EMPTY or not TileTypes.is_diggable(t):
				continue
			if want_type >= 0 and t != want_type:
				continue
			if MineralMap.is_loot(t) == want_loot and (not want_loot or not MineralMap.mineral_id_for(t).is_empty()):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _dig(lucky: bool, want_loot: bool = true, want_type: int = -1) -> void:
	var world := WorldGen.new(4242)
	var cell := _find(world, want_loot, want_type)
	var p = _player(world)
	p._luck_rng = _rng(10.0 if not want_loot else 5.0, lucky)
	p.digging = {"x": cell.x, "y": cell.y, "t": 0.0, "total": 1.0, "type": world.get_tile(cell.x, cell.y)}
	p._finish_dig()
	p.queue_free()


func _test_normal_find() -> void:
	_fresh()
	_dig(false)
	var pick := rec.last("play")
	check("обычная находка: звук подбора обычной громкости", not pick.is_empty() and float(pick[3]) == 0.0)
	var st := rec.last("float_stack")
	check("обычная находка: «+1» обычного размера", not st.is_empty() and float(st[6]) == 1.0)
	check("обычная находка: нет «×N»", rec.count("float_text") == 0)
	check("обычная находка: без вспышки, толчка и наезда",
			rec.count("flash") == 0 and rec.count("shake") == 0 and is_zero_approx(CameraKick.zoom_extra()))
	check("после копки удача не «взведена»", not LuckJuice.is_armed(String(st[1]) if not st.is_empty() else "x"))


func _test_lucky_find() -> void:
	_fresh()
	_dig(true)
	var plays := rec.all("play").filter(func(c: Array) -> bool: return String(c[1]).begins_with("pickup"))
	check("удача: звук подбора есть", not plays.is_empty())
	check("удача: тот же звук подбора громче на 50%% (%.2f дБ)" % (float(plays[0][3]) if not plays.is_empty() else 0.0),
			not plays.is_empty() and absf(db_to_linear(float(plays[0][3])) - 1.5) < 0.001)
	check("удача: отдельного второго звука удачи нет (громче — значит тот же звук)", plays.size() == 1
			or plays.all(func(c: Array) -> bool: return c[1] == plays[0][1]))
	var stacks := rec.all("float_stack")
	check("удача: «+N» с значком в 1.2 раза крупнее (%d)" % stacks.size(), stacks.size() == 2
			and stacks.all(func(c: Array) -> bool: return is_equal_approx(float(c[6]), 1.2)))
	var txt := rec.last("float_text")
	check("удача: «×3» в цвете удачи и в 1.2 раза крупнее", not txt.is_empty() and String(txt[2]) == "×3"
			and is_equal_approx(float(txt[4]), 1.2))
	var fl := rec.last("flash")
	check("удача: вспышка 0.15 цвета удачи", rec.count("flash") == 1 and is_equal_approx((fl[1] as Color).a, 0.15))
	check("удача: толчок камеры — 5%% клетки (%.1f px)" % CameraKick.last_shake_px, rec.count("shake") == 1
			and is_equal_approx(CameraKick.last_shake_px, 0.05 * 32.0))
	check("удача: наезд камеры +5%% (%.3f)" % CameraKick.zoom_extra(), is_equal_approx(CameraKick.zoom_extra(), 0.05))


func _test_zoom_return() -> void:
	var z0 := CameraKick.zoom_extra()
	check("масштаб камеры в пике — 1.05", is_equal_approx(1.0 + z0, 1.05))
	var prev := z0
	var monotonic := true
	var t := 0.0
	while t < 2.0:
		CameraKick.tick(1.0 / 60.0)
		t += 1.0 / 60.0
		var z := CameraKick.zoom_extra()
		if z > prev + 1e-6:
			monotonic = false
		prev = z
	check("наезд возвращается плавно, без рывков вверх", monotonic)
	check("через 2 с камера в норме (1.0)", is_zero_approx(CameraKick.zoom_extra()))
	# та же огибающая — в настоящем масштабе камеры (CameraRig.step тикает CameraKick)
	var rig := CameraRig.new()
	var fp := _FakeP.new()
	rig.step(fp, 7.0, 15.0, 10, 1.0 / 60.0)
	CameraKick.zoom_punch(Juice.num("luck.zoom", 0.05), Juice.num("luck.zoom_hold_s", 0.08),
			Juice.num("luck.zoom_return_s", 0.6), "luck", Juice.num("luck.zoom", 0.05))
	rig.step(fp, 7.0, 15.0, 10, 1.0 / 60.0)
	var peak := rig.zoom
	var mid := 0.0
	for i in 120:
		rig.step(fp, 7.0, 15.0, 10, 1.0 / 60.0)
		if i == 20:
			mid = rig.zoom
	check("камера: наезд 1.05 (%.3f), посреди возврата между (%.3f), через 2 с — 1.0 (%.3f)" % [peak, mid, rig.zoom],
			is_equal_approx(peak, 1.05) and mid > 1.0 and mid < 1.05 and is_equal_approx(rig.zoom, 1.0))
	# две удачи подряд не раздувают наезд выше 5%
	_fresh()
	_dig(true)
	_dig(true)
	check("две удачи подряд — наезд всё равно не выше 5%% (%.3f)" % CameraKick.zoom_extra(),
			CameraKick.zoom_extra() <= 0.05 + 1e-6)


func _test_earth_luck() -> void:
	_fresh()
	_dig(true, false, TileTypes.Type.DIRT)
	var txt := rec.last("float_text")
	check("удача на земле: «×2» крупнее", not txt.is_empty() and is_equal_approx(float(txt[4]), 1.2))
	check("удача на земле: без вспышки, толчка и наезда (до 10% клеток)",
			rec.count("flash") == 0 and rec.count("shake") == 0 and is_zero_approx(CameraKick.zoom_extra()))


func _test_reduce_motion() -> void:
	_fresh()
	Settings.reduce_motion = true
	_dig(true)
	check("«меньше движения»: наезда нет", is_zero_approx(CameraKick.zoom_extra()))
	var fl := rec.last("flash")
	check("«меньше движения»: вспышку гасит сам сервис (заказ — те же 0.15)", not fl.is_empty())
	Settings.reduce_motion = false


# ---------------------------------------------------------------------------
# Настоящие сервисы: размер всплывашки и громкость голоса
# ---------------------------------------------------------------------------

func _test_popup_scale() -> void:
	var fx := FxService.new()
	add_child(fx)
	await get_tree().process_frame
	var icon: Texture2D = UiIcons.item("iron_ore")
	fx.float_stack("iron_ore", Vector2(10, 10), icon, 1, Color.WHITE, 0.75)
	var normal: Node2D = fx._stack["iron_ore"]["root"]
	fx.float_stack("ruby", Vector2(40, 10), icon, 1, Color.WHITE, 0.75, LuckJuice.icon_scale())
	var lucky: Node2D = fx._stack["ruby"]["root"]
	fx.float_stack("ruby", Vector2(40, 10), icon, 2, Color.WHITE, 0.75)
	var merged: Node2D = fx._stack["ruby"]["root"]
	await get_tree().create_timer(0.3).timeout
	check("обычное «+1» встаёт в масштаб 1", normal.scale.is_equal_approx(Vector2.ONE))
	check("удачное «+N» встаёт в масштаб 1.2 (%s)" % str(merged.scale), merged.scale.is_equal_approx(Vector2.ONE * 1.2))
	check("обычная добавка следом не съёживает удачное «+N»", (merged.get_node("Text") as Label).text == "+3"
			and float(fx._stack["ruby"]["size"]) == 1.2)
	check("подпись и значок растут вместе (масштаб узла целиком)", merged.get_node("Icon").scale == normal.get_node("Icon").scale)
	fx.float_text(Vector2(0, 0), "×3", Color.YELLOW, 1.2)
	await get_tree().create_timer(0.3).timeout
	var any_text := false
	for r: Node2D in fx._popups:
		if r.visible and (r.get_node("Text") as Label).text == "×3":
			any_text = r.scale.is_equal_approx(Vector2.ONE * 1.2)
	check("«×N» встаёт в масштаб 1.2", any_text)
	check("удачное «+1» сразу после удара — больше обычного в 1.2 раза",
			lucky.get_meta("size", 1.0) == 1.2 and normal.get_meta("size", 1.0) == 1.0)
	fx.queue_free()
	await get_tree().process_frame


func _test_sound_service() -> void:
	var sfx := SfxService.new()
	add_child(sfx)
	sfx.require_gesture = false
	sfx.unlocked = true
	var ok_normal := sfx.play("pickup", 1.0, 0.0)
	var db_normal := _voice_db(sfx, "pickup")
	sfx._last_ms.clear()
	var ok_lucky := sfx.play("pickup_rare", 1.0, LuckJuice.sound_db())
	var db_lucky := _voice_db(sfx, "pickup_rare")
	check("голос удачи громче обычного ровно на ×1.5 по амплитуде (%.2f → %.2f дБ)" % [db_normal, db_lucky],
			ok_normal and ok_lucky and absf(db_to_linear(db_lucky - db_normal) - 1.5) < 0.001)
	check("громкость настроек не обходится: голос на шине SFX", _voice_bus(sfx, "pickup_rare") == Settings.BUS_SFX)
	for p in sfx._pool:
		p.stop()
	sfx.queue_free()


func _voice_db(sfx: SfxService, id: String) -> float:
	for i in sfx._pool.size():
		if sfx._meta[i]["id"] == id:
			return sfx._pool[i].volume_db
	return -999.0


func _voice_bus(sfx: SfxService, id: String) -> StringName:
	for i in sfx._pool.size():
		if sfx._meta[i]["id"] == id:
			return sfx._pool[i].bus
	return &""


class _FakeP extends RefCounted:
	var x := 20.5
	var y := 60.5
	var vx := 0.0
	var vy := 0.0
	var facing := 1
	var digging = null
	var frozen := false
	var thrust := ""
	var rig_transition := ""


class _Rec extends Node:
	var calls: Array = []

	func clear() -> void:
		calls.clear()

	func all(kind: String) -> Array:
		return calls.filter(func(c: Array) -> bool: return c[0] == kind)

	func count(kind: String) -> int:
		return all(kind).size()

	func last(kind: String) -> Array:
		var a := all(kind)
		return a[-1] if not a.is_empty() else []

	func play(id: String, pitch: float = 1.0, vol: float = 0.0) -> void:
		calls.append(["play", id, pitch, vol])

	func music(_id: String, _fade: float) -> void:
		pass

	func stop_music(_fade: float) -> void:
		pass

	func current_music() -> String:
		return ""

	func loop_start(_id: String, _vol: float, _pitch: float) -> void:
		pass

	func loop_stop(_id: String, _fade: float) -> void:
		pass

	func burst(kind: String, pos: Vector2, amount: float, tint = null) -> void:
		calls.append(["burst", kind, pos, amount, tint])

	func float_text(p: Vector2, t: String, c: Color, size: float = 1.0) -> void:
		calls.append(["float_text", p, t, c, size])

	func float_icon(p: Vector2, i, t: String, c: Color, size: float = 1.0) -> void:
		calls.append(["float_icon", p, i, t, c, size])

	func float_stack(k: String, p: Vector2, i, add: int, c: Color, w: float, size: float = 1.0) -> int:
		calls.append(["float_stack", k, p, i, add, c, size, w])
		return add

	func shake(s: float, d: float) -> void:
		calls.append(["shake", s, d])

	func shake_add(s: float, d: float, _cap: float = 8.0) -> void:
		calls.append(["shake", s, d])

	func flash(c: Color, d: float) -> void:
		calls.append(["flash", c, d])

	func fly_to(_i, _a: Vector2, _b: Vector2, _n: int) -> void:
		pass

	func world_to_screen(p: Vector2) -> Vector2:
		return p

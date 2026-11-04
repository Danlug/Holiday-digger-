extends Node
## test_hurt_juice — отклик на урон (владелец, 27.10): тряска 10% клетки, наезд
## камеры +10% (стопкой, потолок), задержка 0.3 с и возврат за 3 с; краснота экрана
## держится 0.3 с и уходит за 3 с, каждый удар краснее; голод не пульсирует; общий
## CameraKick складывает урон и удачу. Время — только ручные шаги (без часов сцены).
##   godot --headless --path . res://tests/test_hurt_juice.tscn

const DT := 0.01

var failures := 0
var total := 0
var hj: HurtJuice
var rig: CameraRig
var hero: FakeHero
var fx: FxService


class FakeHero:
	var x := 10.0
	var y := 30.0
	var vx := 0.0
	var vy := 0.0
	var facing := 1
	var digging = null
	var frozen := false
	var thrust := ""
	var rig_transition := ""
	var in_rig := false

	func is_in_rig() -> bool:
		return in_rig


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _ready() -> void:
	print("=== test_hurt_juice ===")
	await get_tree().process_frame
	Settings.reduce_motion = false
	GameState.reset_progress()
	GameState.debug_invincible = false
	# голод и бодрость не должны таять сами во время теста
	GameState.set_process(false)
	fx = FxService.new()
	add_child(fx)
	hj = HurtJuice.new()
	add_child(hj)
	hj.set_process(false)
	hero = FakeHero.new()
	rig = CameraRig.new()

	_test_config()
	_test_one_hit()
	_test_second_hit()
	_test_caps()
	_test_quiet()
	_test_lava()
	_test_blocks()
	_test_reduce_motion()
	_test_death()
	_test_luck_sum()
	_test_shake_add()

	Settings.reduce_motion = false
	GameState.set_process(true)
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


## Шаг времени: камера (CameraRig → CameraKick) и краснота.
func _adv(seconds: float) -> void:
	for i in int(round(seconds / DT)):
		rig.step(hero, 7.0, 15.0, 24, DT)
		hj.tick(DT)


func _fresh() -> void:
	hj.reset()
	CameraKick.reset()
	rig.reset()
	hero.frozen = false
	hero.thrust = ""
	hero.in_rig = false
	if not GameState.is_alive:
		GameState.respawn()
	GameState.hp = GameState.get_max_hp()
	hj.stats = {"hits": 0, "held": 0, "quiet": 0}
	_adv(DT)


func _near(a: float, b: float, eps: float = 0.002) -> bool:
	return absf(a - b) <= eps


func _test_config() -> void:
	check("числа: зум +10%", _near(HurtJuice.num("zoom_step", 0.0), 0.10, 1e-6))
	check("числа: задержка 0.3 с", _near(HurtJuice.num("hold_s", 0.0), 0.3, 1e-6))
	check("числа: возврат 3 с", _near(HurtJuice.num("return_s", 0.0), 3.0, 1e-6))
	check("числа: тряска 10% клетки", _near(HurtJuice.num("shake_cells", 0.0), 0.10, 1e-6))
	var node: Variant = Feel.node("hurt.zoom_step")
	check("числа: слова владельца помечены (proposed: false)", typeof(node) == TYPE_DICTIONARY
		and node.get("proposed") == false and String(node.get("note", "")).contains("владелец (27.10)"))


func _test_one_hit() -> void:
	_fresh()
	var shakes := CameraKick.shakes
	GameState.take_damage(10.0, "monster:cave_bat")
	check("удар: тряска 10% клетки (3.2 px)", CameraKick.shakes == shakes + 1 and _near(CameraKick.last_shake_px, 3.2, 1e-4))
	var peak := hj.alpha()
	var share := 10.0 / GameState.get_max_hp()
	check("удар: краснота «как сейчас» (0.18 + доля × 1.2)", _near(peak, clampf(0.18 + share * 1.2, 0.18, 0.36)))
	_adv(DT)
	check("удар: зум мгновенно 1.10", _near(rig.zoom, 1.10, 1e-4))
	_adv(0.27)
	check("удар: к 0.28 с зум всё ещё 1.10", _near(rig.zoom, 1.10, 1e-4))
	check("удар: краснота держится 0.3 с", _near(hj.alpha(), peak, 1e-4))
	_adv(0.32)
	var z06 := rig.zoom
	check("удар: к 0.6 с возврат пошёл (1.0 < зум < 1.10)", z06 > 1.0 and z06 < 1.099)
	check("удар: краснота пошла на убыль", hj.alpha() < peak - 0.005 and hj.alpha() > 0.0)
	_adv(1.0)
	check("удар: возврат плавный, без рывка назад", rig.zoom < z06 and rig.zoom > 1.0)
	_adv(1.68)   # всего ≈ 3.29 с
	check("удар: к 3.3 с зум почти 1.0", rig.zoom - 1.0 < 0.001)
	check("удар: к 3.3 с краснота почти ушла", hj.alpha() < 0.003)
	_adv(0.03)
	check("удар: после 3.3 с зум ровно 1.0", rig.zoom == 1.0)
	check("удар: после 3.3 с красноты нет", hj.alpha() == 0.0 and not hj._rect.visible)


func _test_second_hit() -> void:
	_fresh()
	GameState.take_damage(10.0, "monster:cave_bat")
	var first_red := hj.alpha()
	_adv(1.0)
	var z1 := rig.zoom
	check("второй удар: к 1 с первый возвращается", z1 > 1.0 and z1 < 1.10)
	GameState.take_damage(10.0, "monster:cave_bat")
	_adv(DT)
	check("второй удар: зум = текущий + 10%", _near(rig.zoom, z1 + 0.10, 0.003) and rig.zoom > 1.10)
	check("второй удар: краснее первого", hj.alpha() > first_red + 0.02)
	var z2 := rig.zoom
	_adv(0.27)
	check("второй удар: задержка 0.3 с заново", _near(rig.zoom, z2, 1e-4))
	_adv(3.1)
	check("второй удар: через 0.3 + 3 с всё вернулось", rig.zoom == 1.0 and hj.alpha() == 0.0)


func _test_caps() -> void:
	_fresh()
	for i in 8:
		GameState.take_damage(5.0, "monster:cave_bat")
		_adv(0.05)
	check("потолок: зум не выше +40%", rig.zoom <= 1.40 + 1e-4 and rig.zoom >= 1.39)
	check("потолок: краснота не выше 0.5 (экран не сплошь красный)", hj.alpha() <= 0.5 + 1e-4 and hj.alpha() >= 0.45)
	GameState.take_damage(30.0, "boss:slam")
	check("потолок: один сильный удар — не больше 0.5", hj.alpha() <= 0.5 + 1e-4)
	_fresh()
	GameState.take_damage(GameState.get_max_hp() * 0.6, "boss:slam")
	check("потолок: один удар краснит не больше 0.36 (есть куда краснеть)", hj.alpha() <= 0.36 + 1e-4)


func _test_quiet() -> void:
	_fresh()
	var shakes := CameraKick.shakes
	var samples: Array[float] = []
	# голод: 1 HP/с каплями каждый кадр, 6 секунд
	for i in 600:
		GameState.take_damage(1.0 * DT, "starvation" if i < 300 else "exhaustion")
		_adv(DT)
		if i >= 200:
			samples.append(hj.alpha())
	check("голод: ни тряски, ни наезда", CameraKick.shakes == shakes and rig.zoom == 1.0)
	check("голод: не удар (hits = 0)", hj.stats["hits"] == 0 and hj.stats["quiet"] == 600)
	var lo: float = samples.min()
	var hi: float = samples.max()
	check("голод: краснит слабо (≤ 0.07)", hi <= 0.07 + 1e-4 and lo > 0.03)
	check("голод: ровный фон, без пульсации", hi - lo < 0.002)
	_adv(0.28)
	check("голод кончился: фон держится 0.3 с", hj.alpha() > 0.065)
	_adv(3.1)
	check("голод кончился: за 3 с фон ушёл", hj.alpha() == 0.0)
	# удар поверх голода — обычный удар
	for i in 60:
		GameState.take_damage(1.0 * DT, "starvation")
		_adv(DT)
	GameState.take_damage(10.0, "fall", {"cells": 5})
	_adv(DT)
	check("удар поверх голода: наезд и краснота удара", _near(rig.zoom, 1.10, 1e-4) and hj.alpha() > 0.2)


func _test_lava() -> void:
	_fresh()
	var shakes := CameraKick.shakes
	# лава: 20 HP/с каплями каждый кадр, 2 секунды
	var a0 := -1.0
	for i in 200:
		GameState.take_damage(20.0 * DT, "lava")
		_adv(DT)
		if i == 0:
			a0 = hj.alpha()
	check("лава: один удар на начало, дальше только держит", hj.stats["hits"] == 1 and hj.stats["held"] >= 190)
	check("лава: одна тряска, наезд не накачан до потолка", CameraKick.shakes == shakes + 1 and _near(rig.zoom, 1.10, 1e-4))
	check("лава: краснота держится, не растёт", a0 > 0.15 and _near(hj.alpha(), a0, 1e-4))
	_adv(3.4)
	check("лава кончилась: через 0.3 + 3 с всё вернулось", rig.zoom == 1.0 and hj.alpha() == 0.0)
	# капли после затишья — снова удар
	GameState.take_damage(20.0 * DT, "lava")
	check("лава после затишья: снова удар", hj.stats["hits"] == 2)


func _test_blocks() -> void:
	_fresh()
	hero.thrust = "jet"
	_adv(DT)
	var shakes := CameraKick.shakes
	GameState.take_damage(10.0, "projectile:spit")
	_adv(DT)
	check("полёт: без наезда", rig.zoom == 1.0)
	check("полёт: тряска и краснота есть", CameraKick.shakes == shakes + 1 and hj.alpha() > 0.2)
	_fresh()
	GameState.take_damage(10.0, "monster:cave_bat")
	_adv(0.1)
	hero.in_rig = true
	_adv(0.2)
	check("начатый наезд в бурмобиле уходит быстро и плавно", rig.zoom > 1.0 and rig.zoom < 1.10)
	_adv(0.25)
	check("…и за ~0.4 с ушёл совсем", rig.zoom == 1.0)
	GameState.take_damage(10.0, "monster:cave_bat")
	_adv(DT)
	check("бурмобиль: новый удар без наезда", rig.zoom == 1.0)
	_fresh()
	hero.frozen = true   # сцена сюжета / меню
	_adv(DT)
	shakes = CameraKick.shakes
	GameState.take_damage(10.0, "monster:cave_bat")
	_adv(DT)
	check("сцена: ни наезда, ни тряски", rig.zoom == 1.0 and CameraKick.shakes == shakes)


func _test_reduce_motion() -> void:
	_fresh()
	Settings.reduce_motion = true
	var shakes := CameraKick.shakes
	GameState.take_damage(10.0, "monster:cave_bat")
	_adv(DT)
	check("«меньше движения»: ни наезда, ни тряски", rig.zoom == 1.0 and CameraKick.shakes == shakes)
	var share := 10.0 / GameState.get_max_hp()
	check("«меньше движения»: краснота ×0.3", _near(hj.alpha(), (0.18 + share * 1.2) * 0.3, 0.003))
	Settings.reduce_motion = false


func _test_death() -> void:
	_fresh()
	GameState.take_damage(10.0, "monster:cave_bat")
	_adv(DT)
	check("перед смертью: наезд и краснота есть", rig.zoom > 1.05 and hj.alpha() > 0.1)
	GameState.take_damage(GameState.hp + 5.0, "monster:cave_bat")
	check("смерть: герой умер", not GameState.is_alive)
	_adv(DT)
	check("смерть: краснота и наезд урона сняты сразу", hj.alpha() == 0.0 and not CameraKick.has_channel("hurt") and rig.zoom == 1.0)
	GameState.respawn()
	_adv(DT)


func _test_luck_sum() -> void:
	_fresh()
	GameState.take_damage(10.0, "monster:cave_bat")
	_adv(0.1)
	var ok := CameraKick.zoom_punch(0.05, 0.08, 0.6, "luck", 0.05)
	_adv(DT)
	check("удача поверх урона: вклады складываются (≈ +15%)", ok and _near(CameraKick.zoom_extra(), 0.15, 0.002))
	check("удача не перетёрла канал урона", _near(CameraKick.channel_value("hurt"), 0.10, 1e-4))
	_adv(0.8)
	check("удача ушла — остался урон", not CameraKick.has_channel("luck") and _near(rig.zoom, 1.0 + CameraKick.channel_value("hurt"), 1e-4))
	CameraKick.zoom_punch(0.05, 0.08, 0.6, "luck", 0.05)
	CameraKick.zoom_punch(0.05, 0.08, 0.6, "luck", 0.05)
	check("удача: свой потолок канала (+5%)", CameraKick.channel_value("luck") <= 0.05 + 1e-6)


func _test_shake_add() -> void:
	Settings.reduce_motion = false
	CameraKick.reset()
	fx._reset_shake()
	CameraKick.shake(0.10, 0.2)
	CameraKick.shake(0.05, 0.2)
	check("тряска складывается с остатком (3.2 + 1.6 px)", _near(fx._shake_amp, 4.8, 1e-3))
	for i in 5:
		CameraKick.shake(0.10, 0.2)
	check("тряска: потолок 25% клетки (8 px)", fx._shake_amp <= 8.0 + 1e-4)
	fx._reset_shake()

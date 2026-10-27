class_name CameraRig
extends RefCounted
## Камера «как в играх»: плавное следование с демпфером, упреждение по ходу
## героя, взгляд вниз при падении и наезд («punch zoom») на крупных событиях.
##
## Было: камера намертво приклеена к герою (`main._camera()`), любой рывок героя
## — рывок всего экрана, а при падении видно ровно столько же вниз, сколько
## вверх. Стало: цель камеры — герой плюс небольшое упреждение, сама камера
## подтягивается к цели экспонентой (не зависит от частоты кадров). Пределы мира
## (края карты, верх неба) те же, что у классической камеры, и сглаживание их не
## нарушает: точка между двумя допустимыми допустима.
##
## «Меньше движения» (`Settings.reduce_motion`) → прежняя жёсткая камера без
## упреждения и без наезда: меньше всего покачивания.
##
## Остальные места, считающие «где герой на экране» сами (кнопка над головой в
## доме, у могилы, у станции), берут камеру из `CameraRig.current` — иначе
## значок уезжал бы от героя на величину упреждения.

## Последняя камера, с которой main.gd нарисовал кадр, в клетках. valid=false —
## кадров ещё не было (тесты, --script): вызывающий считает по-старому.
static var current: Vector2 = Vector2.ZERO
static var valid: bool = false

var pos: Vector2 = Vector2.ZERO
var zoom: float = 1.0                  # ≥ 1: во сколько раз наехали на героя

var _has: bool = false
var _lead_x: float = 0.0
var _lead_y: float = 0.0
var _punch: float = 0.0                # текущая «добавка» к масштабу, 0..punch_max
var _punch_age: float = 1.0e9
var _legacy: float = 0.0               # текущая добавка старого Feel.punch (без CameraKick)


## Классическая жёсткая камера (прежняя формула main._camera()) для героя в
## точке (px, py) при поле зрения vw×vh клеток.
static func classic(px: float, py: float, vw: float, vh: float, sky_height: int) -> Vector2:
	return Vector2(
		clampf(px - vw / 2.0, 0.0, maxf(0.0, float(WorldGen.WIDTH) - vw)),
		maxf(py - vh / 2.0, -float(sky_height)))


## Камера для сторонних слоёв (кнопка над головой): последняя нарисованная, а
## если кадров ещё не было — классическая.
static func for_overlay(px: float, py: float, vw: float, vh: float, sky_height: int) -> Vector2:
	if valid:
		return current
	return classic(px, py, vw, vh, sky_height)


static func reset_static() -> void:
	current = Vector2.ZERO
	valid = false
	Feel.pending_punch = 0.0
	CameraKick.reset()


func reset() -> void:
	_has = false
	_lead_x = 0.0
	_lead_y = 0.0
	_punch = 0.0
	_punch_age = 1.0e9
	_legacy = 0.0
	zoom = 1.0


## Упреждение камеры от героя p: (dx, dy) в клетках. Чистая функция состояния
## героя — тестируется отдельно от времени.
static func lead_target(p, rigid: bool) -> Vector2:
	if rigid:
		return Vector2.ZERO
	var lx := 0.0
	if absf(float(p.vx)) > 0.5:
		lx = float(p.facing) * Feel.num("camera.lead_x_cells", 0.55)
	var ly := 0.0
	var vy: float = float(p.vy)
	var from: float = Feel.num("camera.fall_look_from", 6.0)
	if vy > from:
		ly = minf((vy - from) * Feel.num("camera.fall_look_gain", 0.10), Feel.num("camera.fall_look_max", 3.0))
	elif vy < -3.0:
		ly = -minf((-vy - 3.0) * Feel.num("camera.rise_look_gain", 0.06), Feel.num("camera.rise_look_max", 1.5))
	elif p.digging != null and int(p.digging.y) > int(floor(float(p.y))):
		ly = Feel.num("camera.dig_look_down", 0.6)
	return Vector2(lx, ly)


## Один кадр: возвращает камеру в клетках. `p` — герой (x, y, vx, vy, facing,
## digging), `vw/vh` — поле зрения в клетках, `sky_height` — высота неба
## (верхний предел камеры).
func step(p, vw: float, vh: float, sky_height: int, dt: float) -> Vector2:
	var rigid := Settings.reduce_motion
	var lead_t := lead_target(p, rigid)
	# упреждение сглаживаем отдельно и помедленнее: старт и остановка героя не
	# дёргают камеру
	var kx := 1.0 - exp(-dt / maxf(Feel.num("camera.lead_x_tau_s", 0.30), 0.001))
	var ky := 1.0 - exp(-dt / maxf(Feel.num("camera.lead_y_tau_s", 0.22), 0.001))
	_lead_x = lerpf(_lead_x, lead_t.x, kx)
	_lead_y = lerpf(_lead_y, lead_t.y, ky)
	# Упреждение скорости: без него демпфер вечно отставал бы на v·τ (ходьба — 0.4 клетки,
	# падение — 2.2), и «взгляд вперёд» съедался бы лагом. С ним установившееся смещение камеры
	# равно ровно упреждению, а рывки героя всё равно сглажены.
	var ff := Vector2.ZERO
	if not rigid:
		# дискретный шаг сглаживания отстаёт ровно на v·dt/(e^(dt/τ)−1) — не на v·τ: берём точную поправку,
		# чтобы смещение не зависело от частоты кадров
		var tx := maxf(Feel.num("camera.follow_tau_x_s", 0.10), 0.001)
		var ty := maxf(Feel.num("camera.follow_tau_y_s", 0.07), 0.001)
		# жадность (scripts/mechanics/): герой проходит за кадр greed_mult шагов — и поправка во столько же раз
		var gm: float = maxf(1.0, float(p.greed_mult)) if p is Object and "greed_mult" in p else 1.0
		ff = Vector2(
			clampf(float(p.vx) * gm * dt / maxf(exp(dt / tx) - 1.0, 1.0e-6), -3.0, 3.0),
			clampf(float(p.vy) * gm * dt / maxf(exp(dt / ty) - 1.0, 1.0e-6), -3.0, 3.0))
	var target := classic(float(p.x) + _lead_x + ff.x, float(p.y) + _lead_y + ff.y, vw, vh, sky_height)

	if rigid or not _has or pos.distance_to(target) > Feel.num("camera.snap_cells", 6.0):
		pos = target
		_has = true
	else:
		var fx := 1.0 - exp(-dt / maxf(Feel.num("camera.follow_tau_x_s", 0.10), 0.001))
		var fy := 1.0 - exp(-dt / maxf(Feel.num("camera.follow_tau_y_s", 0.07), 0.001))
		pos = Vector2(lerpf(pos.x, target.x, fx), lerpf(pos.y, target.y, fy))
	_tick_punch(dt, rigid, p if p is Object else null)
	current = pos
	valid = true
	return pos


func _tick_punch(dt: float, rigid: bool, p: Object = null) -> void:
	CameraKick.tick(dt, p)
	if rigid:
		_punch = 0.0
		_legacy = 0.0
		zoom = 1.0
		Feel.pending_punch = 0.0
		return
	if Feel.pending_punch > 0.0:
		# новый наезд добавляется к тому, что ещё не затухло, но не выше потолка
		_punch = minf(_legacy + Feel.pending_punch, Feel.num("camera.punch_max", 0.07))
		_punch_age = 0.0
		Feel.pending_punch = 0.0
	if _punch > 0.0:
		_punch_age += dt
		var d := maxf(Feel.num("camera.punch_decay_s", 0.34), 0.05)
		var k := clampf(1.0 - _punch_age / d, 0.0, 1.0)
		# быстро наезжаем, плавно возвращаемся (квадратичное затухание)
		_legacy = _punch * k * k
		if k <= 0.0:
			_punch = 0.0
			_legacy = 0.0
	else:
		_legacy = 0.0
	# толчки CameraKick (урон, удача) складываются со старым коротким наездом
	zoom = 1.0 + minf(_legacy + CameraKick.zoom_extra(), CameraKick.max_total())


## Положение и масштаб `view_root` для камеры `cam` (клетки), масштаба `z` и
## точки на экране `focus_px` (где стоит герой), в пикселях вьюпорта. Масштаб идёт
## вокруг героя: он остаётся на месте, мир на него «наезжает».
static func view_transform(cam: Vector2, z: float, focus_px: Vector2, tile: float) -> Dictionary:
	var base := -cam * tile
	return {"position": focus_px + (base - focus_px) * z, "scale": Vector2(z, z)}

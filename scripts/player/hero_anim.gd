class_name HeroAnim
extends RefCounted
## HeroAnim — математика анимации героя без узлов и сцены: числа из
## data/hero_anim.json, пружины, кривые сглаживания, фаза замаха при копке,
## шаг ходьбы по пройденному пути. CharacterView только применяет результат
## к спрайту — поэтому всё здесь проверяется headless (tests/test_hero_anim.gd).

const CONFIG_PATH := "res://data/hero_anim.json"

static var _cfg: Dictionary = {}
static var _cfg_loaded: bool = false


static func config() -> Dictionary:
	if not _cfg_loaded:
		_cfg_loaded = true
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f != null:
			var raw = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(raw) == TYPE_DICTIONARY:
				_cfg = raw
	return _cfg


static func _node(path: String) -> Variant:
	var node: Variant = config()
	for part in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(part):
			return null
		node = node[part]
	return node


## Число по пути "раздел.ключ" (понимает {value, proposed, note}).
static func num(path: String, default: float) -> float:
	var node: Variant = _node(path)
	if typeof(node) == TYPE_DICTIONARY:
		node = node.get("value", default)
	if typeof(node) == TYPE_INT or typeof(node) == TYPE_FLOAT:
		return float(node)
	return default


## Список чисел по пути (например, веса кадров копки).
static func nums(path: String, default: Array) -> Array:
	var node: Variant = _node(path)
	if typeof(node) == TYPE_ARRAY:
		return node
	return default


# ---------------------------------------------------------------------------
# Кривые
# ---------------------------------------------------------------------------

static func ease_out_cubic(t: float) -> float:
	var u := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - u * u * u


static func ease_in_out(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## Перелёт и возврат: нужен «выскоку» при возрождении.
static func ease_out_back(t: float, overshoot: float = 1.70158) -> float:
	var u := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + (overshoot + 1.0) * u * u * u + overshoot * u * u


## Отскок мяча: падение героя при смерти.
static func ease_out_bounce(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	if u < 1.0 / 2.75:
		return 7.5625 * u * u
	if u < 2.0 / 2.75:
		u -= 1.5 / 2.75
		return 7.5625 * u * u + 0.75
	if u < 2.5 / 2.75:
		u -= 2.25 / 2.75
		return 7.5625 * u * u + 0.9375
	u -= 2.625 / 2.75
	return 7.5625 * u * u + 0.984375


## Плавное приближение к цели, не зависящее от частоты кадров.
static func damp(current: float, target: float, rate: float, dt: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * dt))


# ---------------------------------------------------------------------------
# Пружина: сжатие и растяжение, наклон, толчок — «вторичное» движение
# ---------------------------------------------------------------------------

class Spring:
	var x: float = 0.0
	var v: float = 0.0
	var target: float = 0.0
	var freq: float = 5.0     # Гц
	var zeta: float = 0.5     # 1 — без колебаний

	func _init(p_freq: float = 5.0, p_zeta: float = 0.5) -> void:
		freq = p_freq
		zeta = p_zeta

	func step(dt: float) -> void:
		if dt <= 0.0:
			return
		var w := TAU * freq
		# Мелкие подшаги: пружина обязана быть устойчивой и на рваном кадре.
		var n := maxi(1, ceili(dt / 0.006))
		var h := dt / float(n)
		for i in n:
			v += (-w * w * (x - target) - 2.0 * zeta * w * v) * h
			x += v * h

	func reset(value: float = 0.0) -> void:
		x = value
		v = 0.0
		target = value


# ---------------------------------------------------------------------------
# Копка: замах — удар — отдача по ФАЗЕ цикла 0..1
# ---------------------------------------------------------------------------

## Доля цикла, с которой начинается кадр index (веса — сколько держится кадр).
static func phase_start(weights: Array, index: int) -> float:
	var total := 0.0
	var before := 0.0
	for i in weights.size():
		if i < index:
			before += float(weights[i])
		total += float(weights[i])
	return before / total if total > 0.0 else 0.0


## Середина кадра index в долях цикла: именно в неё ставится момент удара,
## чтобы кадр удара был на экране и чуть раньше, и чуть позже звука.
static func phase_mid(weights: Array, index: int) -> float:
	var a: float = phase_start(weights, index)
	var b: float = phase_start(weights, index + 1) if index + 1 < weights.size() else 1.0
	return (a + b) * 0.5


## Кадр, который показывает фаза p (0..1).
static func phase_frame(weights: Array, p: float) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0 or weights.is_empty():
		return 0
	var cut := fposmod(p, 1.0) * total
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if cut < acc:
			return i
	return weights.size() - 1


## Фаза, в которой кадр удара начинается ровно в моменты (k + 0.5) * period
## после начала копки: именно в эти моменты JuiceDirector играет звук и пыль
## удара (juice.json -> dig.hit_period_s), поэтому глаз и ухо сходятся.
static func dig_target_phase(t: float, period: float, impact_start: float) -> float:
	if period <= 0.0:
		return 0.0
	return fposmod(t / period - 0.5 + impact_start, 1.0)


## Один шаг «ведомой» фазы: она идёт вперёд сама, но подтягивается к целевой,
## а не прыгает (нужно, когда следующая клетка начала копаться посреди
## доигрывания замаха). Назад не идёт никогда.
static func chase_phase(current: float, target: float, dt: float, period: float, gain: float) -> float:
	var step := dt / maxf(period, 0.05)
	# Ошибка считается от того места, куда фаза придёт сама за этот кадр, —
	# иначе она всегда опережает цель ровно на один кадр.
	var err := fposmod(target - (current + step), 1.0)
	if err > 0.5:
		err -= 1.0   # отстала цель — мы впереди: притормаживаем
	var mult := clampf(1.0 + err * gain, 0.3, 3.0)
	return fposmod(current + step * mult, 1.0)


# ---------------------------------------------------------------------------
# Ходьба по пройденному пути
# ---------------------------------------------------------------------------

## Шаг цикла ходьбы (16 кадров = 4 шага) по пройденному расстоянию в клетках.
static func stride_advance(stride: float, dist_cells: float, frames_per_cell: float) -> float:
	return fposmod(stride + absf(dist_cells) * frames_per_cell, 16.0)


## Ближайшая вперёд проходная поза (узкая стойка: кадры 0, 4, 8, 12) — в ней
## можно остановиться без дёрганья ног. Возвращает, сколько кадров до неё.
static func frames_to_passing(stride: float) -> float:
	return fposmod(4.0 - fposmod(stride, 4.0), 4.0)


## Доля подъёма корпуса: 1 в проходной позе, 0 — в контакте.
static func step_lift(stride: float) -> float:
	return 0.5 + 0.5 * cos(TAU * stride / 4.0)


## Размах движения с поправкой на «Уменьшить движение».
static func motion_scale(reduce: bool) -> float:
	return num("reduce_motion_factor", 0.35) if reduce else 1.0

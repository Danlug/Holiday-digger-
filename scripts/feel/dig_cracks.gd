class_name DigCracks
extends RefCounted
## Трещины на копаемой клетке: прогресс разрушения виден на самой породе, а не
## только полоской внизу. Рисуются поверх тайла (через слой overlay мира), сам
## тайл и его текстуры не трогаются. Узор у каждой клетки свой, но одинаковый
## при каждой попытке (зерно — координаты клетки), и растёт от центра к краям:
## чем ближе разрушение, тем гуще сетка. Пиксель-арт: трещина — это отдельные
## пиксели 1×1 (а не линии), чтобы в любом масштабе окна она оставалась чёткой.

const TILE := 32
const MAIN_STRANDS := 5

static var _cache_key: int = -1
static var _cache: Array = []

const COL_CRACK := Color(0.05, 0.035, 0.03, 0.95)
const COL_CRACK_SOFT := Color(0.05, 0.035, 0.03, 0.7)
const COL_EDGE := Color(1.0, 0.95, 0.85, 0.34)


## Узор клетки: массив нитей. Нить: {"px": PackedVector2Array (пиксели от центра
## к краю), "start": доля прогресса, с которой нить начинает расти, "main": true у
## основных трещин (их корень рисуется в два пикселя толщиной)}.
static func pattern(cx: int, cy: int) -> Array:
	var key := (cx * 73856093) ^ (cy * 19349663)
	if key == _cache_key and not _cache.is_empty():
		return _cache
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(key) + 7
	var strands: Array = []
	var origin := Vector2(15.5 + rng.randf_range(-4.0, 4.0), 15.5 + rng.randf_range(-4.0, 4.0))
	var base_a := rng.randf() * TAU
	for i in MAIN_STRANDS:
		var a := base_a + float(i) * TAU / float(MAIN_STRANDS) + rng.randf_range(-0.45, 0.45)
		var length := rng.randi_range(15, 24)
		var px := _walk(rng, origin, a, length)
		strands.append({"px": px, "start": 0.0, "main": true})
		# ответвления: из первой трети, середины и «третьей четверти» основной трещины
		for frac_at in [0.28, 0.5, 0.75]:
			if rng.randf() < 0.7 and px.size() > 6:
				var k := int(float(px.size()) * frac_at)
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				var sub := _walk(rng, px[k], a + side * rng.randf_range(0.8, 1.25), rng.randi_range(5, 9))
				strands.append({"px": sub, "start": float(k) / float(px.size()) * 0.9, "main": false})
	_cache_key = key
	_cache = strands
	return strands


static func _walk(rng: RandomNumberGenerator, from: Vector2, angle: float, length: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var pos := from
	var a := angle
	var last := Vector2(-99, -99)
	for _i in length:
		a += rng.randf_range(-0.22, 0.22)
		pos += Vector2(cos(a), sin(a))
		var p := Vector2(floorf(pos.x), floorf(pos.y))
		if p.x < 1.0 or p.y < 1.0 or p.x > float(TILE - 2) or p.y > float(TILE - 2):
			break
		if p != last:
			out.append(p)
			last = p
	return out


## Сколько пикселей трещины видно при прогрессе frac (0..1). Нужна тестам и
## отрисовке — одна и та же арифметика.
static func visible_pixels(cx: int, cy: int, frac: float) -> int:
	var f := clampf(frac, 0.0, 1.0)
	var total := 0
	for s in pattern(cx, cy):
		total += _strand_visible(s, f)
	return total


static func _strand_visible(s: Dictionary, f: float) -> int:
	var px: PackedVector2Array = s["px"]
	var start: float = s["start"]
	if f <= start:
		return 0
	var t := clampf((f - start) / maxf(1.0 - start, 0.001), 0.0, 1.0)
	return mini(px.size(), int(ceil(float(px.size()) * t)))


## Рисует трещины и затемнение клетки (cx, cy) на холсте `ci`; клетка лежит в
## мировых пикселях (cx*32, cy*32). `frac` — доля пройденной копки.
static func draw(ci: CanvasItem, cx: int, cy: int, frac: float) -> void:
	var f := 1.0 if is_nan(frac) else clampf(frac, 0.0, 1.0)   # мгновенная копка (отладка): total = 0
	var ox := float(cx * TILE)
	var oy := float(cy * TILE)
	# затемнение растёт с прогрессом, но тайл остаётся читаемым (раньше: сплошные 44 %)
	var dark := lerpf(Feel.num("dig.crack_dark_from", 0.10), Feel.num("dig.crack_dark_to", 0.34), f)
	ci.draw_rect(Rect2(ox, oy, TILE, TILE), Color(0, 0, 0, dark))
	if f <= 0.0:
		return
	var strands := pattern(cx, cy)
	# сначала световая кромка со сдвигом (выпуклость скола), поверх — сама трещина
	for pass_i in 2:
		for s in strands:
			var n := _strand_visible(s, f)
			var px: PackedVector2Array = s["px"]
			var thick_to := int(float(px.size()) * 0.6) if bool(s.get("main", false)) else 0
			for i in n:
				var p := px[i]
				if pass_i == 0:
					ci.draw_rect(Rect2(ox + p.x + 1.0, oy + p.y + 1.0, 1, 1), COL_EDGE)
				else:
					ci.draw_rect(Rect2(ox + p.x, oy + p.y, 1, 1), COL_CRACK)
					if i < thick_to:
						ci.draw_rect(Rect2(ox + p.x + 1.0, oy + p.y, 1, 1), COL_CRACK_SOFT)
	# перед самым разрушением клетка «вспыхивает» — сигнал, что удар на подходе
	if f > 0.88:
		var k := (f - 0.88) / 0.12
		ci.draw_rect(Rect2(ox, oy, TILE, TILE), Color(1.0, 0.95, 0.8, 0.16 * k))

class_name Caves
extends RefCounted
## Полости-фигуры (раунд 5, слова владельца): с 1500 в породе встречаются пустоты
## ровной пиксельной формы — круг, ромб, звезда, сердце — с сундуком в центре и
## стражами (scripts/combat/cave_guards.gd). Чистая функция от (сид, x, y), как
## образования: мир нигде не хранит клетки полости, в сейв идут только раскопки.
##
## Раскладка — слотами по slot_h рядов от y_min (data/caves.json): в слоте не
## больше одной полости и целиком внутри слота, поэтому проверка клетки — один
## поиск в кэше слотов (WorldGen._cave_cache). Место проверяется по «природному»
## миру (соль 0): полость не кладётся на лаву, зафиксированные клетки и поверх
## образований (каверн, руин, жил) — их габариты сравниваются по слотам.
## Внутри фигуры — воздух, под центром одна клетка камня («алтарь» под сундуком),
## вокруг фигуры — кольцо камня в одну клетку: ровная кромка, которую слой
## cave_layer.gd подсвечивает цветом формы.

const PATH := "res://data/caves.json"
const KINDS := ["circle", "rhombus", "star", "heart"]

static var _cfg: Dictionary = {}
static var _loaded: bool = false
static var _y_min: int = 1500
static var _y_max: int = 3999
static var _slot_h: int = 48


static func cfg() -> Dictionary:
	if not _loaded:
		_loaded = true
		_cfg = {}
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				_cfg = parsed
		_y_min = int(num("y_min", 1500))
		_y_max = int(num("y_max", 3999))
		_slot_h = maxi(12, int(num("slot_h", 48)))
	return _cfg


static func reload() -> void:
	_loaded = false


## Число из конфига: голое или {value, proposed, note} (как Balance.unwrap, но без автозагрузок).
static func unwrap(node, default = null):
	if typeof(node) == TYPE_DICTIONARY and node.has("value"):
		return node["value"]
	return default if node == null else node


static func num(key: String, default: float) -> float:
	var v = unwrap(cfg().get(key), default)
	return float(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else default


static func section(name: String) -> Dictionary:
	var s = cfg().get(name, {})
	return s if typeof(s) == TYPE_DICTIONARY else {}


static func y_min() -> int:
	cfg()
	return _y_min


static func y_max() -> int:
	cfg()
	return _y_max


static func slot_h() -> int:
	cfg()
	return _slot_h


static func slot_of(y: int) -> int:
	return (y - y_min()) / slot_h()


# ---------------------------------------------------------------------------
# Генерация
# ---------------------------------------------------------------------------

## Применить полости к клетке: воздух внутри фигуры, камень алтаря и кромки, иначе base.
static func apply(w: WorldGen, x: int, y: int, base: int) -> int:
	cfg()
	if y < _y_min or y > _y_max:
		return base
	var c := slot_params(w, (y - _y_min) / _slot_h)
	if c.is_empty() or x < int(c.x0) or x > int(c.x1) or y < int(c.y0) or y > int(c.y1):
		return base
	var dx := x - int(c.cx)
	var dy := y - int(c.cy)
	if in_shape(c, dx, dy):
		if dx == 0 and dy == 1:
			return TileTypes.Type.STONE   # алтарь под сундуком
		if w.protect_cell.is_valid() and bool(w.protect_cell.call(x, y)):
			return base   # клетка-кандидат артефакта: артефакт выдаётся при раскопке
		return TileTypes.Type.EMPTY
	if is_rim(c, dx, dy):
		if base == TileTypes.Type.LAVA:
			return base   # озеро не трогаем: у глубокой полости край местами огненный
		return TileTypes.from_name(String(cfg().get("rim_tile", "STONE")), TileTypes.Type.STONE)
	return base


## Полость слота s или {} (кэш в WorldGen._cave_cache; сбрасывается с кэшем клеток).
static func slot_params(w: WorldGen, s: int) -> Dictionary:
	if w._cave_cache.has(s):
		return w._cave_cache[s]
	var c := _make_slot(w, s)
	w._cave_cache[s] = c
	return c


static func _make_slot(w: WorldGen, s: int) -> Dictionary:
	if s < 0:
		return {}
	var y_lo := _y_min + s * _slot_h
	var y_hi := mini(y_lo + _slot_h - 1, _y_max)
	if y_lo > _y_max or y_hi > w.max_depth - 40:
		return {}
	var mid_y := (y_lo + y_hi) / 2
	var t := clampf(float(mid_y - _y_min) / float(maxi(1, _y_max - _y_min)), 0.0, 1.0)
	var chance := lerpf(num("chance_top", 0.38), num("chance_bottom", 0.7), t)
	if w._roll(s, 1, "cave_has", 0) >= chance:
		return {}
	var kind := _pick_kind(w, s)
	var rr := _radius_range(mid_y)
	var r := int(rr[0]) + int(w._roll(s, 3, "cave_r", 0) * float(int(rr[1]) - int(rr[0]) + 1))
	r += int(section("shapes").get(kind, {}).get("r_add", 0))
	if (y_hi - y_lo + 1) < 2 * (r + 2) + 1:
		return {}   # обрезанный последний слот: фигура с кромкой не влезает
	var tries := maxi(1, int(num("tries", 4)))
	for i in range(tries):
		var cx := r + 1 + int(w._roll(s, 4, "cave_cx", i) * float(maxi(1, WorldGen.WIDTH - 2 * r - 2)))
		var span := maxi(1, (y_hi - y_lo + 1) - 2 * (r + 2))
		var cy := y_lo + r + 2 + int(w._roll(s, 5, "cave_cy", i) * float(span))
		var c := {"kind": kind, "s": s, "cx": cx, "cy": cy, "r": r,
			"x0": cx - r - 1, "x1": cx + r + 1, "y0": cy - r - 1, "y1": cy + r + 1,
			"seed": int(w._roll(s, 6, "cave_seed", i) * 1000000.0)}
		if kind == "star":
			c["poly"] = _star_poly(4, float(r) + 0.5, 0.5)
		if _footprint_ok(w, c):
			return c
	return {}


static func _pick_kind(w: WorldGen, s: int) -> String:
	var shapes := section("shapes")
	var total := 0.0
	for k in KINDS:
		total += float(shapes.get(k, {}).get("weight", 0.0))
	if total <= 0.0:
		return "circle"
	var pick := w._roll(s, 2, "cave_kind", 0) * total
	for k in KINDS:
		pick -= float(shapes.get(k, {}).get("weight", 0.0))
		if pick < 0.0:
			return k
	return KINDS[KINDS.size() - 1]


static func _radius_range(y: int) -> Array:
	var out: Array = [3, 4]
	for row in cfg().get("radius", []):
		if y >= int(row.get("y_min", 0)):
			out = row.get("r", out)
	return out


## Место свободно: нет зафиксированных клеток, природной лавы и габаритов образований.
static func _footprint_ok(w: WorldGen, c: Dictionary) -> bool:
	var x0 := int(c.x0)
	var x1 := int(c.x1)
	var y0 := int(c.y0)
	var y1 := int(c.y1)
	if x0 < 0 or x1 >= WorldGen.WIDTH or y0 < 1:
		return false
	var lava_from := LavaField.min_depth()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if w.is_permanent_feature(x, y):
				return false
			# лава (с 3000) не вырывается: внутри фигуры её быть не должно, а в кромке
			# она остаётся лавой (см. apply) — иначе озёра отнимали бы две трети мест
			if y >= lava_from and in_shape(c, x - int(c.cx), y - int(c.cy)) and LavaField.is_lava(w.world_seed, x, y, 0):
				return false
	# образования: их габариты не пересекаются с нашим (жила — просто руда в породе,
	# её полость режет без вреда; каверны, провалы, гроты и руины — нет)
	if not w._form_cfg.is_empty():
		var s0 := (y0 - 1) / w._form_slot_h
		var s1 := (y1 - 1) / w._form_slot_h
		for s in range(s0, s1 + 1):
			var f := Formations.slot_params(w, s)
			if f.is_empty() or int(f.kind) == Formations.K.VEIN:
				continue
			if int(f.x1) >= x0 and int(f.x0) <= x1 and int(f.y1) >= y0 and int(f.y0) <= y1:
				return false
	return true


# ---------------------------------------------------------------------------
# Формы
# ---------------------------------------------------------------------------

static func _star_poly(n: int, radius: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(2 * n):
		var a := -PI / 2.0 + float(i) * PI / float(n)
		var rr := radius if i % 2 == 0 else radius * inner
		pts.append(Vector2(cos(a) * rr, sin(a) * rr))
	return pts


## Клетка (dx, dy) от центра — внутри фигуры?
static func in_shape(c: Dictionary, dx: int, dy: int) -> bool:
	var r := int(c.r)
	match String(c.kind):
		"circle":
			return dx * dx + dy * dy <= int((float(r) + 0.5) * (float(r) + 0.5))
		"rhombus":
			return absi(dx) + absi(dy) <= r
		"star":
			if absi(dx) > r or absi(dy) > r:
				return false
			return Geometry2D.is_point_in_polygon(Vector2(dx, dy), c.poly)
		"heart":
			var x := float(dx) / (float(r) + 0.5) * 1.25
			var y := -float(dy) / (float(r) + 0.5) * 1.15 + 0.05
			var q := x * x + y * y - 1.0
			return q * q * q - x * x * y * y * y <= 0.0
	return false


## Клетка кромки: не в фигуре, но касается её (8 соседей).
static func is_rim(c: Dictionary, dx: int, dy: int) -> bool:
	if in_shape(c, dx, dy):
		return false
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if (ox != 0 or oy != 0) and in_shape(c, dx + ox, dy + oy):
				return true
	return false


# ---------------------------------------------------------------------------
# Запросы для слоёв, стражей и тестов
# ---------------------------------------------------------------------------

static func id_of(c: Dictionary) -> String:
	return "%d,%d" % [int(c.cx), int(c.cy)]


static func chest_cell(c: Dictionary) -> Vector2i:
	return Vector2i(int(c.cx), int(c.cy))


static func center(c: Dictionary) -> Vector2:
	return Vector2(float(c.cx) + 0.5, float(c.cy) + 0.5)


static func color_of(c: Dictionary) -> Color:
	return Color(String(section("shapes").get(String(c.kind), {}).get("color", "FFFFFF")))


## Полость, чей габарит накрывает клетку, или {}.
static func cave_at(w: WorldGen, x: int, y: int) -> Dictionary:
	cfg()
	if y < _y_min or y > _y_max:
		return {}
	var c := slot_params(w, (y - _y_min) / _slot_h)
	if c.is_empty() or x < int(c.x0) or x > int(c.x1) or y < int(c.y0) or y > int(c.y1):
		return {}
	return c


## Полости, чьи слоты пересекают ряды [y0, y1].
static func caves_between(w: WorldGen, y0: int, y1: int) -> Array:
	cfg()
	var out: Array = []
	if y1 < _y_min or y0 > _y_max:
		return out
	var s0 := maxi(0, (maxi(y0, _y_min) - _y_min) / _slot_h)
	var s1 := (mini(y1, _y_max) - _y_min) / _slot_h
	for s in range(s0, s1 + 1):
		var c := slot_params(w, s)
		if not c.is_empty():
			out.append(c)
	return out


## Клетки воздуха фигуры (кроме алтаря), один раз на полость.
static func air_cells(c: Dictionary) -> Array:
	if c.has("air"):
		return c["air"]
	var out: Array = []
	var r := int(c.r)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if (dx != 0 or dy != 1) and in_shape(c, dx, dy):
				out.append(Vector2i(int(c.cx) + dx, int(c.cy) + dy))
	c["air"] = out
	return out


## Клетки пола: воздух, под которым не воздух (кромка или алтарь).
static func floor_cells(c: Dictionary) -> Array:
	if c.has("floor"):
		return c["floor"]
	var out: Array = []
	for cell: Vector2i in air_cells(c):
		var dx := cell.x - int(c.cx)
		var dy := cell.y - int(c.cy)
		var below_air := in_shape(c, dx, dy + 1) and not (dx == 0 and dy + 1 == 1)
		if not below_air:
			out.append(cell)
	c["floor"] = out
	return out


## Сколько клеток воздуха подряд по горизонтали через cell (для места ходячим стражам).
static func run_width(c: Dictionary, cell: Vector2i) -> int:
	var dy := cell.y - int(c.cy)
	var dx := cell.x - int(c.cx)
	var n := 1
	var k := dx - 1
	while in_shape(c, k, dy) and not (k == 0 and dy == 1):
		n += 1
		k -= 1
	k = dx + 1
	while in_shape(c, k, dy) and not (k == 0 and dy == 1):
		n += 1
		k += 1
	return n


static func leash(c: Dictionary) -> float:
	return float(c.r) + float(unwrap(section("guards").get("leash_extra"), 3.0))


static func aggro(c: Dictionary) -> float:
	return float(c.r) + float(unwrap(section("guards").get("aggro_extra"), 4.0))


static func guard_count(y: int) -> int:
	var n := 2
	for row in section("guards").get("count", []):
		if y >= int(row.get("y_min", 0)):
			n = int(row.get("n", n))
	return n


## Стражи полости: [{index, id, cell: Vector2i, air: bool}] — детерминированно от сида
## полости. Стреляющих не больше max_shooters; летуны — в верхней половине воздуха,
## ходячие и прыгуны — на самых широких участках пола, по одному на клетку.
static func guards(c: Dictionary) -> Array:
	if c.has("guards"):
		return c["guards"]
	var g := section("guards")
	var kinds: Dictionary = g.get("kinds", {})
	var max_shooters := int(g.get("max_shooters", 2))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.seed) * 7919 + int(c.cx) * 131 + int(c.cy)
	var n := guard_count(int(c.cy))
	var out: Array = []
	var shooters := 0
	var floors := floor_cells(c).duplicate()
	# широкие участки пола первыми: ходячему нужно место для патруля
	floors.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var wa := run_width(c, a)
		var wb := run_width(c, b)
		return wa > wb if wa != wb else (a.y != b.y and a.y > b.y) or (a.y == b.y and a.x < b.x))
	var air: Array = []
	for cell: Vector2i in air_cells(c):
		if cell.y < int(c.cy) and absi(cell.x - int(c.cx)) + absi(cell.y - int(c.cy)) >= 2:
			air.append(cell)
	var used := {}
	for i in range(n):
		var total := 0.0
		for k in kinds.keys():
			if String(k) == "acid_spitter" and shooters >= max_shooters:
				continue
			total += float(kinds[k])
		var pick := rng.randf() * total
		var mid := ""
		for k in kinds.keys():
			if String(k) == "acid_spitter" and shooters >= max_shooters:
				continue
			pick -= float(kinds[k])
			if pick < 0.0:
				mid = String(k)
				break
		if mid == "":
			mid = String(kinds.keys()[0])
		if mid == "acid_spitter":
			shooters += 1
		var flying := mid == "cave_bat"
		var cell := chest_cell(c)
		if flying and not air.is_empty():
			cell = air[rng.randi() % air.size()]
		else:
			var j := 0
			while j < floors.size() and used.has(floors[j]):
				j += 1
			if j < floors.size():
				cell = floors[j]
				used[cell] = true
			elif not floors.is_empty():
				cell = floors[rng.randi() % floors.size()]
		out.append({"index": i, "id": mid, "cell": cell, "air": flying})
	c["guards"] = out
	return out

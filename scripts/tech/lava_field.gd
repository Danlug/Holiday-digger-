class_name LavaField
extends RefCounted
## Где лежит лава. Чистая функция от (seed, x, y, salt) — мир не хранит ни
## одной клетки лавы, как и остальная генерация (см. шапку world_gen.gd).
##
## Лава — озерцо-эллипс вокруг случайной точки в ячейке SIZE×SIZE; доля ячеек
## с озером растёт с глубиной. Соседние ячейки проверяются тоже: озеро вылезает
## за границу своей ячейки. salt — соль события сброса (обвал перетряхивает и
## лаву, как всё остальное в чанке).

const MIX_A := -7046029254386353131
const MIX_B := -4417276706812531889

static var _p: Dictionary = {}
static var _min_depth: int = -1


static func _params() -> Dictionary:
	if _p.is_empty():
		_p = TechData.v(TechData.heat().get("lava", {}).get("field", {}))
		_min_depth = Heat.lava_min_depth()
	return _p


static func min_depth() -> int:
	_params()
	return _min_depth


static func chance_at(depth: float) -> float:
	var p := _params()
	var t := clampf((depth - float(_min_depth)) / maxf(float(p.get("max_depth", 6500)) - float(_min_depth), 1.0), 0.0, 1.0)
	return lerpf(float(p.get("chance_at_start", 0.2)), float(p.get("chance_at_max", 0.5)), t)


static func is_lava(world_seed: int, x: int, y: int, salt: int = 0) -> bool:
	var p := _params()
	if y < _min_depth:
		return false
	var size := int(p.get("cell", 8))
	var gx := int(floor(float(x) / float(size)))
	var gy := int(floor(float(y) / float(size)))
	var rmin := float(p.get("radius_min", 1.3))
	var rmax := float(p.get("radius_max", 3.0))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cx := gx + dx
			var cy := gy + dy
			var h := _hash(world_seed, cx, cy, salt)
			var depth_mid := float((cy + 0.5) * size)
			if _unit(h, 0) >= chance_at(depth_mid):
				continue
			# Центр — не у самого края ячейки, иначе озёра слипались бы в линии.
			var px := (float(cx) + 0.25 + 0.5 * _unit(h, 1)) * size
			var py := (float(cy) + 0.25 + 0.5 * _unit(h, 2)) * size
			var r := lerpf(rmin, rmax, _unit(h, 3))
			# Озеро шире, чем выше: лава растекается, а не торчит столбом.
			var ex := (float(x) + 0.5 - px) / (r * 1.3)
			var ey := (float(y) + 0.5 - py) / (r * 0.8)
			if ex * ex + ey * ey < 1.0:
				return true
	return false


static func _hash(world_seed: int, gx: int, gy: int, salt: int) -> int:
	var h := (0x1F3D5B79 * MIX_A) ^ (world_seed * MIX_B)
	h = (h ^ (gx * 0x27D4EB2F)) * MIX_A
	h = (h ^ (gy * 0x165667B1)) * MIX_B
	h = (h ^ (salt * 0x85EBCA6B)) * MIX_A
	h ^= h >> 29
	h *= MIX_B
	h ^= h >> 32
	return h


## Независимые числа [0,1) из одного хеша: каждый номер k перемешивается заново,
## иначе четыре числа одной ячейки оказались бы связаны.
static func _unit(h: int, k: int) -> float:
	var v := (h + (k + 1) * 0x9E3779B1) * MIX_B
	v ^= v >> 31
	v *= MIX_A
	v ^= v >> 29
	return float((v & 0x3FFFFFFFFFFFFFFF) % 1000003) / 1000003.0

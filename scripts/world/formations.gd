class_name Formations
extends RefCounted
## Особые образования мира (ГДД §4.3): каверны, провалы, кристаллические гроты,
## руины глубже 4000, жилы. Чистая функция от (сид, x, y, соль): мир нигде не
## хранит их клетки, в сохранение идут только диффы раскопок.
##
## Раскладка: мир режется на слоты по slot_h рядов, в слоте не больше одного
## образования и целиком внутри слота — проверка клетки это один поиск в кэше
## слотов, а не перебор соседей. Геометрия зависит только от сида (каверны и
## стены руин переживают обвалы), добыча внутри — ещё и от соли события.
## Статические функции, а не узел с состоянием: состояние (кэш слотов) живёт в
## WorldGen, иначе WorldGen и помощник держали бы друг друга (цикл RefCounted).

const NONE := ""
const NOT_AFFECTED := -2

enum K { CAVERN, PIT, GROTTO, RUIN, VEIN }
const NAMES := ["cavern", "pit", "grotto", "ruin", "vein"]


## Применить образования к клетке: итоговый тип или base, если клетку они не трогают.
static func apply(w: WorldGen, x: int, y: int, salt: int, base: int) -> int:
	var cfg: Dictionary = w._form_cfg
	if cfg.is_empty() or y < w._form_min_y:
		return base
	var f := slot_params(w, (y - 1) / w._form_slot_h)
	if f.is_empty():
		return base
	if x < f.x0 or x > f.x1 or y < f.y0 or y > f.y1:
		return base
	var r := _cell(w, f, x, y, salt, base)
	return base if r == NOT_AFFECTED else r


## Вид образования, чей габарит накрывает клетку, или "" — для эффектов (блики грота).
static func kind_at(w: WorldGen, x: int, y: int) -> String:
	if w._form_cfg.is_empty() or y < w._form_min_y:
		return NONE
	var f := slot_params(w, (y - 1) / w._form_slot_h)
	if f.is_empty() or x < f.x0 or x > f.x1 or y < f.y0 or y > f.y1:
		return NONE
	return NAMES[f.kind]


## Параметры образования слота s или {} (кэшируется в WorldGen).
static func slot_params(w: WorldGen, s: int) -> Dictionary:
	if w._slot_cache.has(s):
		return w._slot_cache[s]
	var f := _make_slot(w, s)
	w._slot_cache[s] = f
	return f


static func _make_slot(w: WorldGen, s: int) -> Dictionary:
	var cfg: Dictionary = w._form_cfg
	var slot_h: int = w._form_slot_h
	var y_lo := 1 + s * slot_h
	var y_hi := y_lo + slot_h - 1
	if y_hi < w._form_min_y or y_lo > w.max_depth:
		return {}
	var mid_y := (y_lo + y_hi) / 2
	if w._roll(s, 1, "form_has", 0) >= float(cfg.get("slot_chance", 0.8)):
		return {}

	# вид — по весам среди подходящих по глубине
	var kinds: Dictionary = cfg.get("kinds", {})
	var weights: Array = []
	var total := 0.0
	for i in range(NAMES.size()):
		var k: Dictionary = kinds.get(NAMES[i], {})
		var wt := _kind_weight(k, mid_y)
		weights.append(wt)
		total += wt
	if total <= 0.0:
		return {}
	var pick := w._roll(s, 2, "form_kind", 0) * total
	var kind := 0
	for i in range(weights.size()):
		pick -= weights[i]
		if pick < 0.0:
			kind = i
			break
	var kc: Dictionary = kinds.get(NAMES[kind], {})

	var f := {"kind": kind, "s": s, "seed": int(w._roll(s, 3, "form_seed", 0) * 1000000.0)}
	match kind:
		K.CAVERN, K.GROTTO:
			var rx := _rng_i(w, s, 4, kc.get("rx", [3, 6]))
			var ry := _rng_i(w, s, 5, kc.get("ry", [2, 4]))
			var cy := _place_y(w, s, 6, y_lo, y_hi, ry + 2)
			var cx := int(w._roll(s, 7, "form_cx", 0) * float(WorldGen.WIDTH))
			f.merge({"rx": rx, "ry": ry, "cx": cx, "cy": cy, "x0": cx - rx - 2, "x1": cx + rx + 2,
					"y0": cy - ry - 2, "y1": cy + ry + 2,
					"treasure": kind == K.CAVERN and w._roll(s, 8, "form_tr", 0) < float(kc.get("treasure_chance", 0.0))})
		K.PIT:
			var pw := _rng_i(w, s, 4, kc.get("w", [2, 3]))
			var ph := _rng_i(w, s, 5, kc.get("h", [6, 10]))
			var top := _place_y(w, s, 6, y_lo, y_hi, 1)
			top = clampi(top, y_lo + 1, y_hi - ph - 1)
			var cx := int(w._roll(s, 7, "form_cx", 0) * float(WorldGen.WIDTH - pw))
			f.merge({"pw": pw, "ph": ph, "cx": cx, "cy": top, "x0": cx - 1, "x1": cx + pw, "y0": top - 1, "y1": top + ph + 1})
		K.RUIN:
			var rw := _rng_i(w, s, 4, kc.get("w", [9, 13]))
			var rh := _rng_i(w, s, 5, kc.get("h", [6, 8]))
			var top := clampi(y_lo + 2 + int(w._roll(s, 6, "form_cy", 0) * float(slot_h - rh - 4)), y_lo + 1, y_hi - rh)
			var left := int(w._roll(s, 7, "form_cx", 0) * float(maxi(1, WorldGen.WIDTH - rw)))
			f.merge({"rw": rw, "rh": rh, "x0": left, "x1": left + rw - 1, "y0": top, "y1": top + rh - 1,
					"door": 1 + int(w._roll(s, 9, "form_door", 0) * 2.0)})
		K.VEIN:
			var length := _rng_i(w, s, 4, kc.get("len", [8, 16]))
			var thick := _rng_i(w, s, 5, kc.get("thick", [2, 3]))
			var cy2 := _place_y(w, s, 6, y_lo, y_hi, 5)
			var x0 := int(w._roll(s, 7, "form_cx", 0) * float(maxi(1, WorldGen.WIDTH - length)))
			var tile := _vein_tile(w, mid_y, w._roll(s, 10, "form_ore", 0))
			if tile < 0:
				return {}
			f.merge({"len": length, "thick": thick, "cy": cy2, "x0": x0, "x1": x0 + length, "y0": cy2 - 5, "y1": cy2 + 5,
					"slope": (w._roll(s, 11, "form_sl", 0) - 0.5) * 0.9, "phase": w._roll(s, 12, "form_ph", 0) * TAU,
					"amp": 0.8 + w._roll(s, 13, "form_amp", 0) * 1.4, "tile": tile})
	return f


static func _kind_weight(k: Dictionary, y: int) -> float:
	if k.is_empty() or y < int(k.get("y_min", 0)):
		return 0.0
	if k.has("y_max") and y > int(k["y_max"]):
		return 0.0
	var wt := float(k.get("weight", 0.0))
	# руины набирают вес плавно, а не появляются стеной на 4000
	var ramp := int(k.get("ramp", 0))
	if ramp > 0:
		wt *= clampf(float(y - int(k.get("y_min", 0))) / float(ramp), 0.0, 1.0)
	return wt


static func _rng_i(w: WorldGen, s: int, salt_i: int, range_arr: Array) -> int:
	var lo := int(range_arr[0])
	var hi := int(range_arr[1])
	return lo + int(w._roll(s, salt_i, "form_r%d" % salt_i, 0) * float(hi - lo + 1))


static func _place_y(w: WorldGen, s: int, salt_i: int, y_lo: int, y_hi: int, half: int) -> int:
	var span := maxi(1, (y_hi - y_lo + 1) - 2 * half)
	return y_lo + half + int(w._roll(s, salt_i, "form_y", 0) * float(span))


## Взвешенный выбор тайла из таблицы JSON по глубине; rv in [0,1).
static func _pick(table: Array, y: int, rv: float) -> int:
	var total := 0.0
	for e in table:
		if y >= int(e.get("y_min", 0)):
			total += float(e.get("w", 1.0))
	if total <= 0.0:
		return -1
	var t := rv * total
	for e in table:
		if y >= int(e.get("y_min", 0)):
			t -= float(e.get("w", 1.0))
			if t < 0.0:
				return TileTypes.from_name(String(e.get("tile", "")), TileTypes.Type.STONE)
	return -1


## Руда жилы: среди руд с положительной плотностью на этой глубине, вес — корень
## из плотности (жилы не должны быть сплошным углём, но и не перекашивать состав).
static func _vein_tile(w: WorldGen, y: int, rv: float) -> int:
	var excl: Array = w._form_cfg.get("vein_exclude", [])
	var total := 0.0
	var ws: Array = []
	for o in w._ores:
		var wt := 0.0
		if not excl.has(String(o.get("id", ""))) and not (o.has("y_max") and y > int(o["y_max"]) and o.get("curve", "") != "parabola"):
			wt = sqrt(w._ore_density(o, y))
		ws.append(wt)
		total += wt
	if total <= 0.0:
		return -1
	var t := rv * total
	for i in range(ws.size()):
		t -= ws[i]
		if t < 0.0:
			return TileTypes.from_name(String(w._ores[i].get("tile", "")), TileTypes.Type.STONE)
	return -1


static func _protected(w: WorldGen, x: int, y: int) -> bool:
	return w.protect_cell.is_valid() and bool(w.protect_cell.call(x, y))


static func _cell(w: WorldGen, f: Dictionary, x: int, y: int, salt: int, base: int) -> int:
	match int(f.kind):
		K.CAVERN, K.GROTTO:
			return _cell_cavern(w, f, x, y, salt, base)
		K.PIT:
			return _cell_pit(w, f, x, y, salt, base)
		K.RUIN:
			return _cell_ruin(w, f, x, y, salt, base)
		K.VEIN:
			return _cell_vein(w, f, x, y, salt, base)
	return NOT_AFFECTED


static func _noise(w: WorldGen, f: Dictionary, x: int, y: int) -> float:
	return w._roll(x, y, "form_noise", int(f.seed))


static func _cell_cavern(w: WorldGen, f: Dictionary, x: int, y: int, salt: int, base: int) -> int:
	var dx := float(x - f.cx) / float(f.rx)
	var dy := float(y - f.cy) / float(f.ry)
	var d2 := dx * dx + dy * dy
	var n := _noise(w, f, x, y)
	var is_grotto: bool = int(f.kind) == K.GROTTO
	# пол плоский: ниже 55% высоты эллипса — порода; потолок свод
	var floor_dy := 0.55
	var air: bool = d2 < 0.78 + 0.34 * n and dy <= floor_dy
	if air:
		if _protected(w, x, y):
			return NOT_AFFECTED
		# сокровищница: на полу каверны несколько самоцветов
		if f.get("treasure", false) and dy > floor_dy - 0.45 and dy <= floor_dy and w._roll(x, y, "form_loot", salt) < 0.34:
			var t := _pick(w.layers.get("formations", {}).get("treasure", []), y, w._roll(x, y, "form_lootkind", salt))
			if t >= 0:
				return t
		return TileTypes.Type.EMPTY
	# обод: рудные карманы (каверна) или самоцветы (грот)
	if d2 < 1.7:
		var kc: Dictionary = w._form_cfg.get("kinds", {}).get(NAMES[f.kind], {})
		if is_grotto:
			if w._roll(x, y, "form_rim", salt) < float(kc.get("rim_gem_chance", 0.3)):
				var g := _pick(w.layers.get("formations", {}).get("gems", []), y, w._roll(x, y, "form_gemkind", salt))
				if g >= 0:
					return g
		elif w._roll(x, y, "form_rim", salt) < float(kc.get("rim_ore_chance", 0.2)):
			var o := _vein_tile(w, y, w._roll(x, y, "form_rimkind", salt))
			if o >= 0:
				return o
	return NOT_AFFECTED


static func _cell_pit(w: WorldGen, f: Dictionary, x: int, y: int, salt: int, base: int) -> int:
	if x >= f.cx and x < f.cx + f.pw and y >= f.cy and y < f.cy + f.ph:
		if _protected(w, x, y):
			return NOT_AFFECTED
		# на дне провала — клад
		if y == f.cy + f.ph - 1 and w._roll(x, y, "form_loot", salt) < 0.6:
			var t := _pick(w.layers.get("formations", {}).get("treasure", []), y, w._roll(x, y, "form_lootkind", salt))
			if t >= 0:
				return t
		return TileTypes.Type.EMPTY
	return NOT_AFFECTED


static func _cell_ruin(w: WorldGen, f: Dictionary, x: int, y: int, salt: int, base: int) -> int:
	var i: int = x - f.x0
	var j: int = y - f.y0
	var rw: int = f.rw
	var rh: int = f.rh
	var decay := float(w._form_cfg.get("kinds", {}).get("ruin", {}).get("decay", 0.12))
	var brick := TileTypes.Type.RUIN_BRICK
	var edge := i == 0 or i == rw - 1 or j == 0 or j == rh - 1
	if edge:
		# крошащиеся стены: часть кладки осыпалась (геометрия — от сида, не от соли)
		if _noise(w, f, x, y) < decay:
			return NOT_AFFECTED
		# дверной проём в нижней части боковой стены
		if (i == 0 or i == rw - 1) and j == rh - 2:
			return TileTypes.Type.EMPTY
		return brick
	# внутренняя перегородка с проёмом и колонны
	if i == rw / 2 and j != rh - 2 and j != rh - 3:
		if _noise(w, f, x, y) < decay * 1.5:
			return TileTypes.Type.EMPTY
		return brick
	if (i == 2 or i == rw - 3) and j >= 1 and j <= rh - 3 and (j % 2 == 1):
		return brick
	if _protected(w, x, y):
		return NOT_AFFECTED
	# на полу комнат — добыча руин (материалы брони и оружия)
	if j == rh - 2 and w._roll(x, y, "form_loot", salt) < 0.4:
		var t := _pick(w.layers.get("formations", {}).get("ruin_loot", []), y, w._roll(x, y, "form_lootkind", salt))
		if t >= 0:
			return t
	return TileTypes.Type.EMPTY


static func _cell_vein(w: WorldGen, f: Dictionary, x: int, y: int, salt: int, base: int) -> int:
	var u: int = x - f.x0
	if u < 0 or u > f.len:
		return NOT_AFFECTED
	var cy := float(f.cy) + float(f.slope) * float(u - f.len / 2) + float(f.amp) * sin(float(u) * 0.55 + float(f.phase))
	var half := float(f.thick) * 0.5
	if absf(float(y) - cy) > half + 0.25:
		return NOT_AFFECTED
	if w._roll(x, y, "form_fill", salt) > float(w._form_cfg.get("kinds", {}).get("vein", {}).get("fill", 0.9)):
		return NOT_AFFECTED
	return int(f.tile)

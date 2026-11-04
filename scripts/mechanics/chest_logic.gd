class_name ChestLogic
extends RefCounted
## Тайники: где лежат сундуки и что в них. Чистые функции от сида мира — как
## артефакты (ArtifactSpawn), в сейв идёт только «какие открыты».
##
## ПОЧЕМУ меткой поверх породы, а не новым типом клетки: генератор пород проверен
## статистикой и атласом тайлов, новый тип клетки тронул бы и то и другое. Сундук —
## метка на координате: клетка остаётся той породой, что сгенерировал мир (её
## копают как обычно и получают её руду), а сундук открывается в момент, когда
## клетку выкопали.
##
## ПОЧЕМУ место считается по исходной породе (соль 0), а не по нынешней: обвал и
## землетрясение перетряхивают породу, и проверка «клетка не пустая» по нынешней
## переносила бы сундук в другую клетку полосы — после землетрясения в той же
## полосе вырастал бы второй. По исходной — место одно на всю игру.

const MIX_A := -7046029254386353131   # 0x9E3779B97F4A7C15
const MIX_B := -4417276706812531889   # 0xC2B2AE3D27D4EB4F
const SALT := 0x7C3A_51ED

## Клетки, в которых сундука не бывает: пустота, лава, несокрушимое и кладка руин.
const BAD_TILES := [
	TileTypes.Type.EMPTY, TileTypes.Type.LAVA, TileTypes.Type.REINFORCED,
	TileTypes.Type.STAIRCASE, TileTypes.Type.FOUNDATION, TileTypes.Type.RUIN_BRICK,
]


static func y_min() -> int:
	return int(MechData.num("chests", "y_min", 20))


static func band_rows() -> int:
	return maxi(1, int(MechData.num("chests", "band_rows", 12)))


static func band_of(y: int) -> int:
	if y < y_min():
		return -1
	return (y - y_min()) / band_rows()


## Детерминированный неотрицательный хеш (тот же приём, что у ArtifactSpawn).
static func mix(a: int, b: int, c: int) -> int:
	var h := (a * MIX_A) ^ (b * MIX_B)
	h = (h ^ (c * 0x27D4EB2F)) * MIX_A
	h ^= h >> 29
	h *= MIX_B
	h ^= h >> 32
	return h & 0x3FFFFFFFFFFFFFFF


static func unit(a: int, b: int, c: int) -> float:
	return float(mix(a ^ SALT, b, c) % 1000003) / 1000003.0


## Сундук полосы: {cell: Vector2i, tier: String} или {} — в этой полосе его нет.
## world нужен для проверки породы (исходной, без раскопок и событий).
static func chest_in_band(world: WorldGen, world_seed: int, band: int) -> Dictionary:
	if band < 0:
		return {}
	if unit(world_seed, band, 0) >= MechData.num("chests", "chance", 0.6):
		return {}
	var rows := band_rows()
	var y0 := y_min() + band * rows
	var tries := maxi(1, int(MechData.num("chests", "tries", 4)))
	for t in range(tries):
		var h := mix(world_seed ^ SALT, band, 11 + t * 2)
		var c := Vector2i(int(h % WorldGen.WIDTH), y0 + int((h >> 8) % rows))
		if is_valid_cell(world, c):
			return {"cell": c, "tier": pick_tier(world_seed, band, c.y)}
	return {}


static func is_valid_cell(world: WorldGen, c: Vector2i) -> bool:
	if c.x < 0 or c.x >= WorldGen.WIDTH or c.y < y_min():
		return false
	if world == null:
		return true
	if c.y > world.max_depth - 40:
		return false   # дно мира: там арена рейдбосса (overlay) и несокрушимое дно
	if world.is_permanent_feature(c.x, c.y) or world.is_house_locked_cell(c.x, c.y):
		return false
	if world.protect_cell.is_valid() and bool(world.protect_cell.call(c.x, c.y)):
		return false   # клетка-кандидат артефакта: два клада в одной клетке — путаница
	var t: int = world._generate_layered(c.x, c.y, 0)
	return not BAD_TILES.has(t)


## Ступень сундука по весам из данных: глубже — чаще железо и золото.
static func pick_tier(world_seed: int, band: int, y: int) -> String:
	var tiers: Array = MechData.section("chests").get("tiers", [])
	var shift: Array = MechData.arr("chests", "deep_shift_per_1000", [])
	var weights: Array = []
	var total := 0.0
	for i in range(tiers.size()):
		var t: Dictionary = tiers[i]
		var w := 0.0
		if y >= int(t.get("y_min", 0)):
			w = float(MechData.value(t.get("weight", 0), 0))
			if i < shift.size():
				w += float(shift[i]) * float(y) / 1000.0
			if i == 0:
				w = maxf(w, 30.0)
			w = maxf(w, 0.0)
		weights.append(w)
		total += w
	if total <= 0.0 or tiers.is_empty():
		return "wood"
	var r := unit(world_seed, band, 1) * total
	for i in range(tiers.size()):
		r -= float(weights[i])
		if r < 0.0:
			return String(tiers[i].get("id", "wood"))
	return String(tiers[tiers.size() - 1].get("id", "wood"))


## Запись ступени: обычные (tiers, их разыгрывает pick_tier) и назначаемые явно
## (extra_tiers — сундук полости-фигуры, раунд 5).
static func tier_row(tier: String) -> Dictionary:
	for t in MechData.section("chests").get("tiers", []):
		if String(t.get("id", "")) == tier:
			return t
	for t in MechData.section("chests").get("extra_tiers", []):
		if String(t.get("id", "")) == tier:
			return t
	return {}


## Ценность ступени в «клетках» на глубине y: value_cells плюс value_per_1000 за
## каждую 1000 ниже y_min ступени (у тайников нуль — их ценность не зависит от глубины).
static func tier_value_cells(row: Dictionary, y: int) -> float:
	var base := float(MechData.value(row.get("value_cells", 20), 20))
	var per := float(MechData.value(row.get("value_per_1000", 0), 0))
	if per <= 0.0:
		return base
	return base + per * maxf(0.0, float(y - int(row.get("y_min", 0)))) / 1000.0


## Добыча сундука: {tier, items: {id: n}, xp: int}. Детерминирована от сида и
## клетки: перезапуск и сейв-скам сундук не перебрасывают.
##
## ПОЧЕМУ ценность в «клетках», а не в штуках: на сотне клетка породы стоит ~3
## монеты, на двух тысячах — ~90. Сундук из N штук был бы на мелководье кошельком,
## а внизу — мелочью; «value_cells клеток копки» весит одинаково на любой глубине.
static func roll_loot(world: WorldGen, world_seed: int, cell: Vector2i, tier: String) -> Dictionary:
	var row := tier_row(tier)
	var rng := RandomNumberGenerator.new()
	rng.seed = mix(world_seed ^ SALT, cell.x * 7919 + 13, cell.y)
	var items := {}
	var pool := _ore_pool(world, cell.y)
	var limits: Array = row.get("items", [3, 12])
	var lo := int(limits[0])
	var hi := int(limits[limits.size() - 1])
	var spread := MechData.num("chests", "value_spread", 0.25)
	var target := tier_value_cells(row, cell.y) * cell_value(world, cell.y) \
		* rng.randf_range(1.0 - spread, 1.0 + spread)
	# владелец (26.10): «важно, чтобы в сундуке не было больше 60 кг руды» — столько
	# держит рюкзак. Самоцвет золотого сундука — тоже руда: место под него оставляем заранее.
	var max_kg := MechData.num("chests", "max_ore_kg", 60.0)
	var gem := _gem_for(cell.y) if bool(row.get("gem", false)) else {}
	if not gem.is_empty():
		var gem_kg := Balance.get_mineral_weight(String(gem["id"]))
		if gem_kg > 0.0:
			gem["count"] = clampi(int(gem["count"]), 1, maxi(1, int(floor(max_kg / gem_kg))))
		max_kg -= gem_kg * int(gem["count"])
	if not pool.is_empty():
		var total := 0.0
		for p in pool:
			total += float(p["w"])
		var cap := target * (1.0 + spread)
		var got := 0.0
		var got_kg := 0.0
		var n := 0
		var misses := 0
		# тянем руду, пока ценность не набрана; штуку, с которой сундук перевалил бы
		# за верх разброса, перетягиваем (алмаз в деревянном сундуке на 300 — это
		# два «сундука» сразу), и после нескольких промахов останавливаемся. Поэтому
		# самоцветы глубины попадают в окованные и золотые сундуки, а не в деревянные
		while n < hi and (n < lo or got < target) and misses < 6:
			var pick := _draw(pool, total, rng)
			var price := float(pick["price"])
			var kg := Balance.get_mineral_weight(String(pick["id"]))
			if got + price > cap or got_kg + kg > max_kg:
				misses += 1
				continue
			items[pick["id"]] = int(items.get(pick["id"], 0)) + 1
			got += price
			got_kg += kg
			n += 1
		if n == 0:
			# всё в породе дороже ценности сундука: одна штука самого дешёвого
			var cheap: Dictionary = pool[0]
			for p in pool:
				if float(p["price"]) < float(cheap["price"]):
					cheap = p
			items[cheap["id"]] = 1
	if not gem.is_empty():
		items[gem["id"]] = int(items.get(gem["id"], 0)) + int(gem["count"])
	var xp := 0.0
	for id in items.keys():
		xp += float(items[id]) * item_xp(String(id))
	# еда — после опыта: её не копают, опыта за неё нет
	var food := String(row.get("food", ""))
	if food != "" and rng.randf() < float(MechData.value(row.get("food_chance", 0.0), 0.0)):
		items[food] = int(items.get(food, 0)) + 1
	var total_xp := int(round(xp * MechData.num("chests", "xp_share", 0.5))) \
		+ int(MechData.value(row.get("xp_bonus", 0), 0))
	return {"tier": tier, "items": items, "xp": total_xp}


## Вес руды в добыче (еда не руда — не считается).
static func ore_kg(items: Dictionary) -> float:
	var kg := 0.0
	for id in items.keys():
		if String(id).begins_with("food_"):
			continue
		kg += Balance.get_mineral_weight(String(id)) * int(items[id])
	return kg


static func _draw(pool: Array, total: float, rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf() * total
	for p in pool:
		r -= float(p["w"])
		if r <= 0.0:
			return p
	return pool[pool.size() - 1]


## Средняя выручка клетки породы на глубине y: Σ доля руды × цена (материалы без
## цены — по unpriced_weight_price). Та же величина, что «монет с клетки» в ГДД §4.1.
static func cell_value(world: WorldGen, y: int) -> float:
	if world == null:
		return 1.0
	var unpriced := MechData.num("chests", "unpriced_weight_price", 100.0)
	var v := 0.0
	for d in world.ore_densities_at(y):
		var id := String(d["id"])
		var m := Balance.get_mineral(id)
		if id.is_empty() or m.is_empty() or String(m.get("category", "")) == "crafted":
			continue
		var price := float(Balance.get_mineral_price(id))
		if price <= 0.0:
			price = unpriced
		v += float(d["density"]) * price
	return maxf(v, 1.0)


## Опыт за штуку, как за её копку (ГДД §11: руда = цена/5); у материалов без цены — из данных.
static func item_xp(id: String) -> float:
	var price := Balance.get_mineral_price(id)
	if price > 0:
		return float(price) / 5.0
	return MechData.num("chests", "unpriced_xp", 10.0)


## Из чего сундук выбирает добычу: руды этой глубины по настоящему составу
## породы, вес — плотность × цена^0.35 (дорогое попадается заметно, но не вытесняет
## руду). Сколько штук — решает ценность (roll_loot), а не вес.
static func _ore_pool(world: WorldGen, y: int) -> Array:
	var out: Array = []
	if world == null:
		return out
	var exclude: Array = MechData.section("chests").get("exclude", [])
	var unpriced := MechData.num("chests", "unpriced_weight_price", 100.0)
	for d in world.ore_densities_at(y):
		var id := String(d["id"])
		if id.is_empty() or exclude.has(id):
			continue
		var m := Balance.get_mineral(id)
		if m.is_empty() or String(m.get("category", "")) == "crafted":
			continue
		var dens := float(d["density"])
		if dens <= 0.0:
			continue
		var price := float(Balance.get_mineral_price(id))
		if price <= 0.0:
			price = unpriced
		out.append({"id": id, "w": dens * pow(price, 0.35), "price": price})
	return out


static func _gem_for(y: int) -> Dictionary:
	var best := {}
	for g in MechData.section("chests").get("gems_by_depth", []):
		if y >= int(g.get("y_min", 0)):
			best = {"id": String(g.get("id", "")), "count": int(g.get("count", 1))}
	if best.is_empty():
		var fb: Dictionary = MechData.section("chests").get("gem_fallback", {})
		if not fb.is_empty():
			best = {"id": String(fb.get("id", "gold")), "count": int(fb.get("count", 1))}
	return best


## Цена добычи в монетах (для расчётов и тестов: сколько сундук «стоит»).
static func loot_value(items: Dictionary) -> int:
	var v := 0
	for id in items.keys():
		v += Balance.get_mineral_price(String(id)) * int(items[id])
	return v

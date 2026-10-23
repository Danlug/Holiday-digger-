extends SceneTree
## Глубина мира: экономика руд (ГДД §4.1), пояса-биомы, особые образования.
## Только чистые классы (WorldGen, Biomes, TileTypes), без автозагрузок.
##   godot --headless --path . --script res://tests/test_world_deep.gd

var checks := 0
var failures := 0

var _price := {}
var _kg := {}


func _init() -> void:
	print("=== test_world_deep: старт ===")
	_load_minerals()
	test_ore_layers_no_cliffs()
	test_ore_layers_rarity_law()
	test_economy_reference()
	test_economy_growth_smooth()
	test_ore_never_vanishes_and_no_anomalies()
	print("=== Итог: %d проверок, %d провалов ===" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("  OK    ", label)
	else:
		failures += 1
		print("  FAIL  ", label)


func _unwrap(v):
	if typeof(v) == TYPE_DICTIONARY and v.has("value"):
		return v["value"]
	return v


func _load_minerals() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/minerals.json"))
	for m in data["minerals"]:
		var p = _unwrap(m.get("price_coins", 0))
		_price[m["id"]] = float(p) if p != null else 0.0
		_kg[m["id"]] = float(_unwrap(m.get("weight_kg", 0.0)))


func _ore(w: WorldGen, id: String) -> Dictionary:
	for o in w.layers["ores"]:
		if o["id"] == id:
			return o
	return {}


## Ожидаемая доля руды id в породе на глубине y: бросок независим, клетка
## достаётся первой совпавшей руде из списка, пустоты 10% отсекаются раньше.
func _shares(w: WorldGen, y: int) -> Dictionary:
	var out := {}
	var rest := 1.0 - float(w._deep.get("void_chance", 0.0))
	for o in w._ores:
		if o.has("y_max") and y > int(o["y_max"]) and o.get("curve", "") != "parabola":
			continue
		var d := w._ore_density(o, y)
		out[o["id"]] = rest * d
		rest *= (1.0 - d)
	return out


func _coins_and_kg(w: WorldGen, y: int) -> Vector2:
	var coins := 0.0
	var kg := 0.0
	var s := _shares(w, y)
	for id in s.keys():
		coins += s[id] * float(_price.get(id, 0.0))
		kg += s[id] * float(_kg.get(id, 0.0))
	return Vector2(coins, kg)


const RISE_ORES := ["copper", "nickel", "platinum", "titanium", "lithium", "mercury", "uranium",
		"ruby", "emerald", "geocrystal", "ancient_metal", "obsidian"]


func test_ore_layers_no_cliffs() -> void:
	print("-- Руды ГДД §18: плотность растёт с нуля, без ступеньки на y_min --")
	var w := WorldGen.new(1)
	for id in RISE_ORES:
		var o := _ore(w, id)
		check("%s: слой задан и подъём с нуля (rise=zero)" % id, not o.is_empty() and o.get("rise", "") == "zero")
		var y_min := int(o["y_min"])
		var peak: float = o["peak"]
		check("%s: выше y_min руды нет" % id, w._ore_density(o, y_min - 1) == 0.0)
		check("%s: на y_min плотность ~0 (нет ступеньки)" % id, w._ore_density(o, y_min) < 0.02 * peak + 1e-9)
		var y_peak := int(o["peak_y"])
		check("%s: в пике плотность = peak" % id, absf(w._ore_density(o, y_peak) - peak) < 1e-9)
		var y_mid := (y_min + y_peak) / 2
		var d_mid := w._ore_density(o, y_mid)
		check("%s: на полпути к пику плотность между краями (парабола, не плато)" % id,
				d_mid > 0.5 * peak and d_mid < 0.9 * peak)
		# хвост: у ранних руд (медь) — четверть пика, у глубинных — три четверти
		var tail_lo := 0.2 if id == "copper" else 0.7
		check("%s: хвост на дне в [%.0f%%; 100%%] пика" % [id, tail_lo * 100.0],
				w._ore_density(o, 9999) >= tail_lo * peak and w._ore_density(o, 9999) <= peak + 1e-9)
		# и в самом генераторе: выше y_min ни одной клетки на 120 сидах
		var found := 0
		for s in range(40):
			var gw := WorldGen.new(s * 31 + 7)
			for y in range(maxi(6, y_min - 30), y_min):
				for x in range(WorldGen.WIDTH):
					if TileTypes.from_name(o["tile"]) == gw.get_tile(x, y):
						found += 1
		check("%s: в генераторе выше y_min руды нет (найдено %d)" % [id, found], found == 0)


## Закон редкости: пик глубинных руд падает с ценой, peak ~ 7.6% * (20/цена)^0.22
## (никель — опора: пик 7.6% при 20 монетах, задан владельцем).
func test_ore_layers_rarity_law() -> void:
	print("-- Руды: закон редкости peak ~ 7.6%% * (20/цена)^0.22 --")
	var w := WorldGen.new(1)
	var ids := ["nickel", "titanium", "lithium", "mercury", "platinum", "emerald", "ruby", "uranium"]
	var prev_price := 0.0
	var prev_peak := 1.0
	var ordered := true
	for id in ids:
		var price: float = _price[id]
		var peak: float = _ore(w, id)["peak"]
		var law := 0.076 * pow(20.0 / price, 0.22)
		check("%s: пик %.2f%% в пределах 30%% от закона (%.2f%%)" % [id, peak * 100.0, law * 100.0],
				absf(peak - law) <= 0.3 * law)
		if price >= prev_price and peak > prev_peak + 1e-9:
			ordered = false
		prev_price = price
		prev_peak = peak
	check("чем дороже руда, тем реже её пик (никель -> уран)", ordered)
	# непродаваемые материалы: геокристалл -> древний металл -> обсидиан не частят друг друга
	var geo: float = _ore(w, "geocrystal")["peak"]
	var anc: float = _ore(w, "ancient_metal")["peak"]
	var obs: float = _ore(w, "obsidian")["peak"]
	check("лестница редкости: геокристалл >= древний металл >= обсидиан", geo >= anc and anc >= obs)


## Ориентир ГДД §15: доллар = два полных рюкзака руды с первой сотни, алмаз = пол-доллара.
func test_economy_reference() -> void:
	print("-- Экономика: ориентир «доллар = два рюкзака руды с первой сотни» --")
	var w := WorldGen.new(1)
	var sum_coins := 0.0
	var sum_kg := 0.0
	for y in range(6, 101):
		var ck := _coins_and_kg(w, y)
		sum_coins += ck.x
		sum_kg += ck.y
	var pack_coins := 60.0 * sum_coins / sum_kg
	print("     полный рюкзак (60 кг) руды с первой сотни: %.0f монет" % pack_coins)
	check("два рюкзака с первой сотни ~ 1 доллар (1000 монет): рюкзак %.0f в [350; 800]" % pack_coins,
			pack_coins >= 350.0 and pack_coins <= 800.0)
	check("алмаз стоит пол-доллара (500 монет)", _price["diamond"] == 500.0)
	# рюкзак с глубины 3000 — на порядок богаче («на той же спине вдесятеро больше денег»)
	var deep := _coins_and_kg(w, 3000)
	var deep_pack := 60.0 * deep.x / deep.y
	print("     рюкзак руды на глубине 3000: %.0f монет (x%.1f)" % [deep_pack, deep_pack / pack_coins])
	check("рюкзак на 3000 богаче рюкзака первой сотни в 6-20 раз", deep_pack / pack_coins >= 6.0 and deep_pack / pack_coins <= 20.0)


func test_economy_growth_smooth() -> void:
	print("-- Экономика: доход с клетки растёт плавно, без обрывов --")
	var w := WorldGen.new(1)
	# от 200: между 100 и 200 золото и медь (заданы владельцем) входят ступенькой, x2
	var prev := _coins_and_kg(w, 200).x
	var worst := 1.0
	var monotone := true
	var y := 300
	while y <= 3000:
		var cur := _coins_and_kg(w, y).x
		worst = maxf(worst, cur / prev)
		if cur < prev * 0.9:
			monotone = false
		prev = cur
		y += 100
	print("     максимальный скачок дохода/клетку за 100 рядов: x%.2f" % worst)
	check("доход с клетки не падает на 200-3000 (допуск 10%)", monotone)
	check("скачок дохода за 100 рядов не больше x1.5 (прежний обрыв урана был x3.7)", worst <= 1.5)


func test_ore_never_vanishes_and_no_anomalies() -> void:
	print("-- Руды не кончаются, аномалий нет --")
	var w := WorldGen.new(1)
	for id in RISE_ORES:
		var o := _ore(w, id)
		var tile: int = TileTypes.from_name(o["tile"])
		var hit := 0
		var cnt := 0
		for s in range(6):
			var gw := WorldGen.new(s * 17 + 3)
			for y in range(9500, 9800):
				for x in range(WorldGen.WIDTH):
					cnt += 1
					if gw.get_tile(x, y) == tile:
						hit += 1
		check("%s: на глубине 9500+ руда по-прежнему есть (%.2f%%)" % [id, 100.0 * hit / cnt], hit > 0)
	for yc in [200, 800, 1500, 2500, 3500, 5000, 8000]:
		var total := 0.0
		var s := _shares(w, yc)
		for id in s.keys():
			total += s[id]
		check("глубина %d: все руды вместе <= 62%% породы (%.1f%%)" % [yc, total * 100.0], total <= 0.62)

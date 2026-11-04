extends Node
## Внешний вид руды (раунд 6, зона ore-look): три варианта тайла на руду и их выбор по координатам
## (TileArt.ore_variant — детерминированно, все три в ходу, соседи не повторяются), наличие вариантов в
## art/tiles и в атласах поясов, искры OreSparkle (собирает только разведанные клетки искристой руды, у каждой
## клетки свой ритм, при Settings.reduce_motion — молчит). Мир и туман — настоящие, без main.tscn.

const WV := preload("res://scripts/world/world_view.gd")
const ORES := ["iron", "lead", "silver", "copper", "aluminium", "gold", "diamond", "peat", "coal", "nickel", "mercury",
		"platinum", "titanium", "lithium", "uranium", "ruby", "emerald", "scrap", "geocrystal", "ancient_metal", "obsidian",
		"hellstone", "dark_matter", "universalium", "angelstone", "divine_heart"]

var checks := 0
var failures := 0
var _plant: Dictionary = {}


class FakePlayer extends Node:
	var x: float = 16.5
	var y: float = 301.5
	var digging = null
	var rig_transition: String = ""


func _ready() -> void:
	print("=== test_ore_look: старт ===")
	test_variant_choice()
	test_variant_files()
	await test_sparkle()
	print("=== Итог: %d проверок, %d провалов ===" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("  OK    ", label)
	else:
		failures += 1
		print("  FAIL  ", label)


func test_variant_choice() -> void:
	print("-- выбор варианта по координатам --")
	var counts := [0, 0, 0]
	var same_neighbour := 0
	var pairs := 0
	var in_range := true
	var stable := true
	for y in range(1, 400):
		for x in range(WorldGen.WIDTH):
			var v := TileArt.ore_variant(x, y)
			if v < 0 or v >= TileArt.ORE_VARIANTS:
				in_range = false
				continue
			counts[v] += 1
			if TileArt.ore_variant(x, y) != v:
				stable = false
			if x > 0:
				pairs += 1
				if TileArt.ore_variant(x - 1, y) == v:
					same_neighbour += 1
	check("вариант всегда 0..2", in_range)
	check("выбор детерминирован (повторный вызов тот же)", stable)
	var total: int = counts[0] + counts[1] + counts[2]
	var min_share: float = float(counts.min()) / float(total)
	check("все три варианта в ходу, самый редкий не реже 25%% (доли %s)" % [str(counts)], min_share >= 0.25)
	var same := float(same_neighbour) / float(pairs)
	check("соседи по горизонтали совпадают примерно в трети случаев (%.2f), не штампом" % same, same > 0.25 and same < 0.42)
	# не совпадает с узором земли: иначе руда одного варианта ложилась бы на землю одного варианта
	var corr := 0
	for y in range(1, 200):
		for x in range(WorldGen.WIDTH):
			if TileArt.ore_variant(x, y) == TileArt.dirt_variant(x, y) % TileArt.ORE_VARIANTS:
				corr += 1
	var corr_share := float(corr) / float(199 * WorldGen.WIDTH)
	check("хеш варианта руды не повторяет хеш земли (совпадений %.2f ≈ 1/3)" % corr_share, corr_share > 0.25 and corr_share < 0.42)


func test_variant_files() -> void:
	print("-- файлы вариантов и атласы --")
	var missing: Array = []
	for n in ORES:
		for v in range(1, TileArt.ORE_VARIANTS):
			var path := "res://art/tiles/ore_%s_%d.png" % [n, v + 1]
			if not ResourceLoader.exists(path):
				missing.append(path)
	check("для каждой из 26 руд есть ore_x_2.png и ore_x_3.png (нет: %s)" % ", ".join(missing), missing.is_empty())
	var meta = JSON.parse_string(FileAccess.get_file_as_string("res://art/tiles/deep/atlas.json"))
	var names: Array = meta.get("names", []) if typeof(meta) == TYPE_DICTIONARY else []
	var in_atlas := true
	for n in ORES:
		for v in range(TileArt.ORE_VARIANTS):
			var nm := "ore_%s" % n if v == 0 else "ore_%s_%d" % [n, v + 1]
			if not names.has(nm):
				in_atlas = false
	check("все варианты всех руд есть в атласе поясов (atlas.json)", in_atlas)
	# три разных текстуры у золота на поясе 0 и на поясе «Кристаллы» (2500)
	for depth in [300, 2500]:
		var seen := {}
		var found := [false, false, false]
		for x in range(WorldGen.WIDTH):
			var v := TileArt.ore_variant(x, depth)
			var t := TileArt.texture_for(TileTypes.Type.GOLD_ORE, x, depth)
			if t == null:
				continue
			found[v] = true
			seen[v] = _region_key(t)
		check("глубина %d: все три варианта золота встречаются в ряду" % depth, found[0] and found[1] and found[2])
		check("глубина %d: три варианта — три разные вырезки атласа" % depth,
			seen.size() == 3 and seen[0] != seen[1] and seen[1] != seen[2] and seen[0] != seen[2])


func _region_key(t: Texture2D) -> String:
	if t is AtlasTexture:
		return "%s:%s" % [(t as AtlasTexture).atlas.resource_path, str((t as AtlasTexture).region)]
	return t.resource_path


func test_sparkle() -> void:
	print("-- искры на самоцветах и золоте --")
	var w := WorldGen.new(4242)
	var f := FogOfWar.new()
	var p := FakePlayer.new()
	add_child(p)
	# золото слева от героя, алмазы справа, земля вокруг — через overlay (мир не меняется)
	_plant.clear()
	for dy in range(-2, 3):
		for dx in range(1, 4):
			_plant[Vector2i(16 - dx, 301 + dy)] = TileTypes.Type.GOLD_ORE
			_plant[Vector2i(16 + dx, 301 + dy)] = TileTypes.Type.DIAMOND
	w.overlay_y_min = 290
	w.overlay = _overlay_tile
	var v: Node2D = WV.new()
	add_child(v)
	v.world = w
	v.fog = f
	v.player = p
	v.set_view_size(7, 14)
	v.validate_every = 0
	var sp: Node = v._overlay.get_node_or_null("OreSparkle")
	check("OreSparkle — ребёнок overlay WorldView (поверх тайлов)", sp != null and sp is OreSparkle)
	if sp == null:
		return
	var was_rm := Settings.reduce_motion
	Settings.reduce_motion = true
	f.reveal_around(p.x, p.y, 5, 4)
	v.render(Vector2(p.x - 3.5, p.y - 7.0))
	check("окно камеры известно после render", v.window_rect().size.x > 0 and v.window_rect().size.y > 0)
	sp._process(0.3)
	sp._process(0.3)
	check("reduce_motion: клеток для искр не собирается, рисовать нечего", sp._cells.is_empty() and sp._drawn == 0)
	Settings.reduce_motion = false
	sp._process(0.3)
	var types := {}
	var all_full := true
	for c in sp._cells:
		types[w.get_tile(c[0], c[1])] = true
		if f.get_state(c[0], c[1]) != FogOfWar.State.FULL:
			all_full = false
	check("без reduce_motion собраны разведанные клетки золота и алмаза (%d шт.)" % sp._cells.size(),
		sp._cells.size() >= 12 and types.has(TileTypes.Type.GOLD_ORE) and types.has(TileTypes.Type.DIAMOND))
	check("в списке только разведанные (FULL) клетки", all_full)
	check("земля и камень искр не дают", not types.has(TileTypes.Type.DIRT) and not types.has(TileTypes.Type.STONE))
	# ритм: за период каждая клетка вспыхивает ровно одним окном длиной FLASH, фазы 0..3 по порядку
	var ok_rhythm := true
	var distinct_starts := {}
	for c in sp._cells:
		var on_steps := 0
		var last := -1
		var first_on := -1
		var step := 0.02
		var n := int(OreSparkle.PERIOD / step)
		for i in range(n):
			sp._t = float(i) * step
			var ph: int = sp._phase(c[0], c[1])
			if ph >= 0:
				on_steps += 1
				if first_on < 0:
					first_on = i
				if ph < last and last != 3:
					ok_rhythm = false
			last = ph
		distinct_starts[first_on] = true
		var want := int(OreSparkle.FLASH / step)
		if absi(on_steps - want) > 2 or first_on < 0:
			ok_rhythm = false
	check("каждая клетка вспыхивает раз за период на %.2f с, фазы по порядку" % OreSparkle.FLASH, ok_rhythm)
	check("клетки не мигают хором: у %d клеток не меньше 6 разных моментов вспышки" % sp._cells.size(), distinct_starts.size() >= 6)
	check("у искры есть цвет для каждой драгоценной руды", OreSparkle.COLORS.has(TileTypes.Type.GOLD_ORE)
		and OreSparkle.COLORS.has(TileTypes.Type.RUBY) and OreSparkle.COLORS.has(TileTypes.Type.EMERALD)
		and OreSparkle.COLORS.has(TileTypes.Type.DIAMOND))
	# руды в окне не осталось (всё земля) — клетки выпадают из списка
	_all_dirt = true
	sp._process(0.3)
	check("после смены мира (руды нет) список искр пуст", sp._cells.is_empty())
	Settings.reduce_motion = was_rm


var _all_dirt := false


func _overlay_tile(x: int, y: int) -> int:
	if _all_dirt:
		return TileTypes.Type.DIRT
	return int(_plant.get(Vector2i(x, y), -1))

extends SceneTree
## Глубина мира: пояса-биомы и особые образования (ГДД §4.2-4.3).
## Только чистые классы (WorldGen, Biomes, Formations), без автозагрузок.
##   godot --headless --path . --script res://tests/test_world_deep_formations.gd

var checks := 0
var failures := 0


func _init() -> void:
	print("=== test_world_deep_formations: старт ===")
	test_biomes_cover_depth()
	test_formations_kinds_and_depths()
	test_formations_content()
	test_formations_events_and_save()
	test_protect_cell_and_cache()
	test_art_complete()
	print("=== Итог: %d проверок, %d провалов ===" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("  OK    ", label)
	else:
		failures += 1
		print("  FAIL  ", label)


# ============================== ПОЯСА ==============================

func test_biomes_cover_depth() -> void:
	print("-- Пояса глубины --")
	check("поясов 8", Biomes.count() == 8)
	var contiguous := true
	var widths_ok := true
	var prev_to := 0
	for i in range(Biomes.count()):
		var b := Biomes.get_biome(i)
		if int(b["y_from"]) != prev_to + 1:
			contiguous = false
		var width := int(b["y_to"]) - int(b["y_from"]) + 1
		if width < 999 or width > 1501:
			widths_ok = false
		prev_to = int(b["y_to"])
	check("пояса идут встык от 1 до 10000", contiguous and prev_to == 10000)
	check("каждый пояс 1000-1500 клеток (последний с дном 1501)", widths_ok)
	var mono := true
	var last := 0
	for y in range(1, 10001, 7):
		var i := Biomes.index_at(y)
		if i < last:
			mono = false
		last = i
	check("пояс не убывает с глубиной", mono)
	check("y=1 — корни, y=3500 — недра, y=9999 — небесное ядро",
			Biomes.index_at(1) == 0 and Biomes.index_at(3500) == 3 and Biomes.index_at(9999) == 7)
	var inside_ok := true
	var edge_ok := true
	var mixed := 0
	for x in range(WorldGen.WIDTH):
		if Biomes.index_at_cell(x, 500) != 0:
			inside_ok = false
		for dy in range(-Biomes.transition(), Biomes.transition()):
			var b := Biomes.index_at_cell(x, 1000 + dy)
			if b != 0 and b != 1:
				edge_ok = false
			if b == 1 and dy < 0:
				mixed += 1
	check("далеко от границы пояс чистый", inside_ok)
	check("у границы только два соседних пояса", edge_ok)
	check("до границы тайлы следующего пояса уже подмешиваются (дизеринг, %d клеток)" % mixed, mixed > 100)
	var fields_ok := true
	for i in range(Biomes.count()):
		var b := Biomes.get_biome(i)
		for k in ["aura_relief", "aura_res", "gray_solid", "gray_empty"]:
			if String(b.get(k, "")).length() != 6:
				fields_ok = false
		for k in ["ambient", "wall", "soil", "name_ru"]:
			if not b.has(k):
				fields_ok = false
	check("у каждого пояса заданы цвета, ambient, стена, цель тона", fields_ok)
	var bl := Biomes.blend_at(1000.0)
	check("на границе кроссфейд ~50/50", absf(float(bl["t"]) - 0.5) < 0.05 and bl["a"] == 0 and bl["b"] == 1)
	check("вдали от границы кроссфейда нет", Biomes.blend_at(500.0)["t"] == 0.0)


# ============================== ОБРАЗОВАНИЯ ==============================

func _scan_kinds(seeds: int, y0: int, y1: int) -> Dictionary:
	var out := {}
	for s in range(seeds):
		var w := WorldGen.new(s * 101 + 5)
		for y in range(y0, y1, 3):
			for x in range(0, WorldGen.WIDTH, 2):
				var k := Formations.kind_at(w, x, y)
				if k != "":
					var lo: int = out.get(k + "_min", 1 << 30)
					var hi: int = out.get(k + "_max", 0)
					out[k + "_min"] = mini(lo, y)
					out[k + "_max"] = maxi(hi, y)
					out[k] = int(out.get(k, 0)) + 1
	return out


func test_formations_kinds_and_depths() -> void:
	print("-- Образования: виды и глубины --")
	var st := _scan_kinds(10, 1, 10000)
	for k in ["cavern", "pit", "grotto", "ruin", "vein"]:
		check("%s встречается (проб %d)" % [k, int(st.get(k, 0))], int(st.get(k, 0)) > 0)
	check("жилы от 150", int(st.get("vein_min", 0)) >= 150 - 20)
	check("каверны от 700 (слот, чья середина глубже 700)", int(st.get("cavern_min", 0)) >= 700 - 20)
	check("провалы от 800", int(st.get("pit_min", 0)) >= 800 - 20)
	check("гроты только в кристаллах 2000-3400 (%d..%d)" % [int(st.get("grotto_min", 0)), int(st.get("grotto_max", 0))],
			int(st.get("grotto_min", 0)) >= 2000 - 6 and int(st.get("grotto_max", 0)) <= 3400 + 6)
	check("руины только глубже 4000 (с %d)" % int(st.get("ruin_min", 0)), int(st.get("ruin_min", 0)) >= 4000 - 6)
	check("выше 150 образований нет совсем", _scan_kinds(6, 1, 148).is_empty())
	var covered := 0
	var total := 0
	for s in range(6):
		var w := WorldGen.new(s * 13 + 1)
		for y in range(700, 4700, 2):
			for x in range(WorldGen.WIDTH):
				total += 1
				if Formations.kind_at(w, x, y) != "":
					covered += 1
	var frac := float(covered) / float(total)
	check("габариты образований покрывают 5-30%% породы (%.1f%%)" % (frac * 100.0), frac >= 0.05 and frac <= 0.30)


func test_formations_content() -> void:
	print("-- Образования: содержимое --")
	var cav_air := 0
	var cav_total := 0
	var bricks := 0
	var empties_in_ruin := 0
	var ruin_loot := 0
	var grotto_gems := 0
	var pit_cells := 0
	var treasure := 0
	var ruin_loot_set := [TileTypes.Type.ANCIENT_METAL, TileTypes.Type.HELLSTONE, TileTypes.Type.OBSIDIAN,
			TileTypes.Type.GEOCRYSTAL, TileTypes.Type.DARK_MATTER, TileTypes.Type.UNIVERSALIUM]
	var gems := [TileTypes.Type.DIAMOND, TileTypes.Type.RUBY, TileTypes.Type.EMERALD]
	for s in range(14):
		var w := WorldGen.new(s * 77 + 9)
		for y in range(150, 6000):
			for x in range(WorldGen.WIDTH):
				var k := Formations.kind_at(w, x, y)
				if k == "":
					continue
				var t := w.get_tile(x, y)
				match k:
					"cavern":
						cav_total += 1
						if t == TileTypes.Type.EMPTY:
							cav_air += 1
						elif gems.has(t) or t == TileTypes.Type.GOLD_ORE or t == TileTypes.Type.PLATINUM_ORE:
							treasure += 1
					"pit":
						if t == TileTypes.Type.EMPTY:
							pit_cells += 1
					"grotto":
						if gems.has(t):
							grotto_gems += 1
					"ruin":
						if t == TileTypes.Type.RUIN_BRICK:
							bricks += 1
						elif t == TileTypes.Type.EMPTY:
							empties_in_ruin += 1
						elif ruin_loot_set.has(t):
							ruin_loot += 1
	print("     каверны: воздух %d из %d, самоцветы/золото %d; провалы: %d; гроты: самоцветов %d; руины: кладка %d, комнаты %d, добыча %d"
			% [cav_air, cav_total, treasure, pit_cells, grotto_gems, bricks, empties_in_ruin, ruin_loot])
	check("каверны пустые внутри (воздух > 25% габарита)", cav_total > 0 and float(cav_air) / float(cav_total) > 0.25)
	check("в каверн-сокровищницах лежат самоцветы", treasure > 0)
	check("провалы вырыты", pit_cells > 0)
	check("гроты облицованы самоцветами", grotto_gems > 0)
	check("руины сложены из кладки", bricks > 50)
	check("в руинах есть комнаты", empties_in_ruin > 50)
	check("в руинах лежат материалы брони/оружия", ruin_loot > 0)

	var w2 := WorldGen.new(4242)
	var best := 0
	var vein_runs := 0
	for s in range(0, 400):
		var f := Formations.slot_params(w2, s)
		if f.is_empty() or int(f.kind) != Formations.K.VEIN:
			continue
		var cnt := 0
		for y in range(int(f.y0), int(f.y1) + 1):
			for x in range(int(f.x0), int(f.x1) + 1):
				if w2.get_tile(x, y) == int(f.tile):
					cnt += 1
		best = maxi(best, cnt)
		vein_runs += 1
	check("жилы встретились (%d)" % vein_runs, vein_runs > 3)
	check("самая крупная жила — не меньше 12 клеток одной руды (%d)" % best, best >= 12)


func _brick_set(w: WorldGen, y0: int, y1: int) -> Dictionary:
	var out := {}
	for y in range(y0, y1):
		for x in range(WorldGen.WIDTH):
			if w.get_tile(x, y) == TileTypes.Type.RUIN_BRICK:
				out[y * WorldGen.WIDTH + x] = true
	return out


func test_formations_events_and_save() -> void:
	print("-- Образования: события и сохранение --")
	var w := WorldGen.new(31337)
	var before := _brick_set(w, 4000, 6000)
	check("кладка руин есть на этом сиде (%d)" % before.size(), before.size() > 40)
	w.apply_global_event(987654)
	var after := _brick_set(w, 4000, 6000)
	var same := 0
	for k in before.keys():
		if after.has(k):
			same += 1
	check("после землетрясения кладка руин на месте (%d из %d)" % [same, before.size()], same == before.size())
	var w_a := WorldGen.new(31337)
	var w_b := WorldGen.new(31337)
	w_b.apply_global_event(555)
	var diff := 0
	for y in range(4000, 5500):
		for x in range(WorldGen.WIDTH):
			if w_a.get_tile(x, y) != w_b.get_tile(x, y):
				diff += 1
	check("землетрясение перетасовало породу (%d клеток иначе)" % diff, diff > 3000)

	var w2 := WorldGen.new(99)
	var target := Vector2i(-1, -1)
	for y in range(4100, 5400):
		for x in range(WorldGen.WIDTH):
			if w2.get_tile(x, y) == TileTypes.Type.RUIN_BRICK:
				target = Vector2i(x, y)
				break
		if target.x >= 0:
			break
	check("нашлась клетка кладки", target.x >= 0)
	check("кладка копается", w2.dig_cell(target.x, target.y))
	check("выкопанная кладка — пустота", w2.get_tile(target.x, target.y) == TileTypes.Type.EMPTY)
	var saved := w2.get_save_data()
	check("формат сохранения прежний: dug/events/garden_locked",
			saved.has("dug") and saved.has("events") and saved.has("garden_locked") and saved.size() == 3)
	var w3 := WorldGen.new(99)
	w3.load_save_data(saved)
	check("после загрузки дыра на месте", w3.get_tile(target.x, target.y) == TileTypes.Type.EMPTY)
	var mism := 0
	for y in range(4100, 4300):
		for x in range(WorldGen.WIDTH):
			if w2.get_tile(x, y) != w3.get_tile(x, y):
				mism += 1
	check("загруженный мир совпадает с исходным", mism == 0)


func test_protect_cell_and_cache() -> void:
	print("-- Защита клеток артефактов и кэш --")
	var free := WorldGen.new(2024)
	var guarded := WorldGen.new(2024)
	guarded.set_protect_cell(func(_x, _y): return true)
	var air_free := 0
	var air_guard := 0
	for y in range(700, 2000):
		for x in range(WorldGen.WIDTH):
			var k := Formations.kind_at(free, x, y)
			if k == "cavern" or k == "pit":
				if free.get_tile(x, y) == TileTypes.Type.EMPTY:
					air_free += 1
				if guarded.get_tile(x, y) == TileTypes.Type.EMPTY:
					air_guard += 1
	print("     воздух в кавернах/провалах: без защиты %d, с защитой %d" % [air_free, air_guard])
	check("защита клеток не даёт образованиям вырыть воздух", air_guard < air_free / 3)
	guarded.set_protect_cell(Callable())

	var w := WorldGen.new(777)
	var bad := 0
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in range(3000):
		var x := r.randi_range(0, WorldGen.WIDTH - 1)
		var y := r.randi_range(6, 9000)
		var a := w.get_tile(x, y)
		var b := w._generate_layered(x, y, 0)
		if a != b and not w.is_permanent_feature(x, y):
			bad += 1
		if w.get_tile(x, y) != a:
			bad += 1
	check("get_tile из кэша == прямой расчёт (расхождений %d)" % bad, bad == 0)
	var t1 := w.get_tile(5, 3000)
	var changed := false
	for s in range(1, 30):
		w.world_seed = 777 + s
		if w.get_tile(5, 3000) != t1:
			changed = true
			break
	check("смена world_seed сбрасывает кэш", changed)


# ============================== ГРАФИКА ==============================

func test_art_complete() -> void:
	print("-- Графика поясов --")
	var missing := []
	for t in TileTypes.Type.values():
		if t == TileTypes.Type.EMPTY or t == TileTypes.Type.STAIRCASE or t == TileTypes.Type.REINFORCED:
			continue
		if TileArt.texture_for(t, 3, 100) == null:
			missing.append(TileTypes.type_name(t))
	check("у каждого типа клетки есть тайл пояса 0 (нет: %s)" % ", ".join(missing), missing.is_empty())
	var bad_belts := []
	for belt in range(1, Biomes.count()):
		var y := int(Biomes.get_biome(belt).y_from) + Biomes.transition() + 5
		for t in TileTypes.Type.values():
			if t == TileTypes.Type.EMPTY or t == TileTypes.Type.STAIRCASE or t == TileTypes.Type.REINFORCED \
					or t == TileTypes.Type.FOUNDATION:
				continue
			var tex := TileArt.texture_for(t, 7, y)
			if tex == null or tex.get_width() != 96 or tex.get_height() != 96:
				bad_belts.append("%d:%s" % [belt, TileTypes.type_name(t)])
	check("в каждом поясе у каждого типа есть тайл 96x96 из атласа (проблемы: %s)" % ", ".join(bad_belts), bad_belts.is_empty())
	var tex1 := TileArt.texture_for(TileTypes.Type.DIRT, 5, 1500)
	var tex0 := TileArt.texture_for(TileTypes.Type.DIRT, 5, 500)
	# Раньше пояс 0 был отдельными файлами. Теперь все пояса — вырезки одного атласа мира
	# (tools/gen_world_atlas.py), чтобы слой мира рисовался одним пакетом; без атласа — по-старому.
	check("земля поясов 0 и 1 — разные вырезки одного атласа мира",
			tex1 is AtlasTexture and tex0 is AtlasTexture and tex0 != tex1
			and (tex0 as AtlasTexture).atlas == (tex1 as AtlasTexture).atlas)
	var walls_ok := true
	for i in range(Biomes.count()):
		if not ResourceLoader.exists("res://art/env/deep/wall_%s.png" % Biomes.get_biome(i).wall):
			walls_ok = false
	check("у каждого пояса есть стена-фон", walls_ok)
	# цвет земли внутри пояса одной светлоты: средняя яркость вариантов не разъезжается
	var spread_ok := true
	for belt in range(1, Biomes.count()):
		var lo := 1000.0
		var hi := 0.0
		for v in range(8):
			var tex: AtlasTexture = TileArt._belt_tile(belt, "dirt_%d" % (v + 1))
			var img: Image = tex.atlas.get_image().get_region(Rect2i(tex.region))
			var sum := 0.0
			for yy in range(0, 96, 4):
				for xx in range(0, 96, 4):
					var c := img.get_pixel(xx, yy)
					sum += 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			var m := sum / 576.0 * 255.0
			lo = minf(lo, m)
			hi = maxf(hi, m)
		if hi - lo > 7.0:
			spread_ok = false
			print("     пояс %d: разброс средней яркости вариантов земли %.1f" % [belt, hi - lo])
	check("варианты земли внутри пояса одной светлоты (разброс <= 7 из 255)", spread_ok)

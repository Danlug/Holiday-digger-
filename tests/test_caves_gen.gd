extends SceneTree
## Полости-фигуры (раунд 5, ГДД «Полости и стражи»): формы, частота, детерминизм,
## неприкосновенность сюжета/лавы/образований, расстановка стражей.
## Только чистые классы (WorldGen, Caves, Formations, ChestLogic), без автозагрузок.
##   godot --headless --path . --script res://tests/test_caves_gen.gd

var checks := 0
var failures := 0


func _init() -> void:
	print("=== test_caves_gen: старт ===")
	test_shapes()
	test_frequency_and_depth()
	test_world_content()
	test_determinism_and_events()
	test_no_damage_to_world()
	test_guards_layout()
	print("=== Итог: %d проверок, %d провалов ===" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("  OK    ", label)
	else:
		failures += 1
		print("  FAIL  ", label)


func _fake(kind: String, r: int) -> Dictionary:
	var c := {"kind": kind, "s": 0, "cx": 16, "cy": 2000, "r": r, "seed": 77,
		"x0": 16 - r - 1, "x1": 16 + r + 1, "y0": 2000 - r - 1, "y1": 2000 + r + 1}
	if kind == "star":
		c["poly"] = Caves._star_poly(4, float(r) + 0.5, 0.5)
	return c


func _ascii(c: Dictionary) -> void:
	var r := int(c.r)
	for dy in range(-r - 1, r + 2):
		var row := "     "
		for dx in range(-r - 1, r + 2):
			if dx == 0 and dy == 0:
				row += "@"
			elif Caves.in_shape(c, dx, dy):
				row += "." if not (dx == 0 and dy == 1) else "="
			elif Caves.is_rim(c, dx, dy):
				row += "#"
			else:
				row += " "
		print(row)


# ============================== ФОРМЫ ==============================

func test_shapes() -> void:
	print("-- Формы --")
	for kind in Caves.KINDS:
		var all_sym := true
		var all_closed := true
		var all_center := true
		var grows := true
		var prev := 0
		for r in range(3, 7):
			var c := _fake(kind, r)
			if r == 4:
				_ascii(c)
			var n := 0
			for dy in range(-r - 1, r + 2):
				for dx in range(-r - 1, r + 2):
					var a := Caves.in_shape(c, dx, dy)
					if a != Caves.in_shape(c, -dx, dy):
						all_sym = false
					if a:
						n += 1
						# кольцо кромки замкнуто: любой сосед воздуха — воздух или кромка
						for oy in range(-1, 2):
							for ox in range(-1, 2):
								var nx := dx + ox
								var ny := dy + oy
								if not Caves.in_shape(c, nx, ny) and not Caves.is_rim(c, nx, ny):
									all_closed = false
			if not Caves.in_shape(c, 0, 0) or not Caves.in_shape(c, 0, 1):
				all_center = false
			if n <= prev:
				grows = false
			prev = n
			# фигура не вылезает за радиус
			for dx in range(-r - 2, r + 3):
				if Caves.in_shape(c, dx, -r - 1) or Caves.in_shape(c, dx, r + 1) \
						or Caves.in_shape(c, -r - 1, dx) or Caves.in_shape(c, r + 1, dx):
					all_closed = false
		check("%s симметрична слева-направо" % kind, all_sym)
		check("%s: кромка замкнута и форма в пределах радиуса" % kind, all_closed)
		check("%s: центр и клетка алтаря внутри фигуры" % kind, all_center)
		check("%s: площадь растёт с радиусом" % kind, grows)
	var circ := _fake("circle", 4)
	check("круг: горизонтальный и вертикальный диаметры равны 2r+1",
			Caves.in_shape(circ, 4, 0) and not Caves.in_shape(circ, 5, 0) and Caves.in_shape(circ, 0, 4) and not Caves.in_shape(circ, 0, 5))
	var rh := _fake("rhombus", 4)
	check("ромб: вершина — одна клетка", Caves.in_shape(rh, 0, -4) and not Caves.in_shape(rh, 1, -4))
	var st := _fake("star", 5)
	check("звезда: лучи по осям длинные, по диагонали — короткие",
			Caves.in_shape(st, 0, -5) and Caves.in_shape(st, 5, 0) and not Caves.in_shape(st, 3, 3) and Caves.in_shape(st, 1, 1))
	var he := _fake("heart", 5)
	check("сердце: две доли сверху, острие снизу",
			Caves.in_shape(he, -3, -4) and Caves.in_shape(he, 3, -4) and not Caves.in_shape(he, 0, -5) and Caves.in_shape(he, 0, 5))


# ============================== ЧАСТОТА И ГЛУБИНА ==============================

func test_frequency_and_depth() -> void:
	print("-- Частота и глубина --")
	var seeds := 10
	var total := 0
	var kinds := {}
	var out_of_belt := 0
	var r_shallow := 0.0
	var n_shallow := 0
	var r_deep := 0.0
	var n_deep := 0
	var shallow_count := 0
	var deep_count := 0
	var widest := 0
	for s in range(seeds):
		var w := WorldGen.new(s * 101 + 5)
		for c in Caves.caves_between(w, 1, 10000):
			total += 1
			kinds[String(c.kind)] = int(kinds.get(String(c.kind), 0)) + 1
			if int(c.y0) < Caves.y_min() or int(c.y1) > Caves.y_max() or int(c.x0) < 0 or int(c.x1) >= WorldGen.WIDTH:
				out_of_belt += 1
			widest = maxi(widest, int(c.x1) - int(c.x0) + 1)
			if int(c.cy) < 2300:
				r_shallow += float(c.r)
				n_shallow += 1
			elif int(c.cy) >= 3100:
				r_deep += float(c.r)
				n_deep += 1
			if int(c.cy) < 2750:
				shallow_count += 1
			else:
				deep_count += 1
	var per_seed := float(total) / float(seeds)
	print("     полостей на сид: %.1f; виды: %s; самая широкая %d клеток" % [per_seed, str(kinds), widest])
	check("полостей на мир 10–40 (%.1f)" % per_seed, per_seed >= 10.0 and per_seed <= 40.0)
	check("все четыре формы встречаются", kinds.size() == 4)
	check("полости только в поясе 1500–3999 и внутри ширины мира", out_of_belt == 0)
	check("выше 1500 полостей нет совсем", Caves.caves_between(WorldGen.new(5), 1, 1499).is_empty())
	check("радиус растёт с глубиной (%.2f → %.2f)" % [r_shallow / maxf(1.0, n_shallow), r_deep / maxf(1.0, n_deep)],
			n_shallow > 0 and n_deep > 0 and r_deep / float(n_deep) > r_shallow / float(n_shallow))
	check("глубже полости чаще (%d против %d)" % [shallow_count, deep_count], deep_count > shallow_count)
	check("полость помещается в ширину мира с кромкой", widest <= WorldGen.WIDTH)


# ============================== СОДЕРЖИМОЕ ==============================

func test_world_content() -> void:
	print("-- Содержимое в настоящем мире --")
	var w := WorldGen.new(4242)
	var caves := Caves.caves_between(w, 1, 10000)
	check("на сиде 4242 есть полости (%d)" % caves.size(), caves.size() > 3)
	var air_ok := true
	var rim_ok := true
	var altar_ok := true
	var chest_ok := true
	var floor_ok := true
	for c in caves:
		for cell: Vector2i in Caves.air_cells(c):
			if w.get_tile(cell.x, cell.y) != TileTypes.Type.EMPTY:
				air_ok = false
		var r := int(c.r)
		for dy in range(-r - 1, r + 2):
			for dx in range(-r - 1, r + 2):
				if Caves.is_rim(c, dx, dy):
					var rt := w.get_tile(int(c.cx) + dx, int(c.cy) + dy)
					if rt != TileTypes.Type.STONE and rt != TileTypes.Type.LAVA:
						rim_ok = false
		if w.get_tile(int(c.cx), int(c.cy) + 1) != TileTypes.Type.STONE:
			altar_ok = false
		var ch := Caves.chest_cell(c)
		if w.get_tile(ch.x, ch.y) != TileTypes.Type.EMPTY or ch != Vector2i(int(c.cx), int(c.cy)):
			chest_ok = false
		for f: Vector2i in Caves.floor_cells(c):
			if w.get_tile(f.x, f.y) != TileTypes.Type.EMPTY or w.get_tile(f.x, f.y + 1) == TileTypes.Type.EMPTY:
				floor_ok = false
	check("внутри фигуры — воздух", air_ok)
	check("кромка — кольцо камня (у глубоких местами лава озера)", rim_ok)
	check("под центром — клетка камня (алтарь)", altar_ok)
	check("клетка сундука — центр, воздух", chest_ok)
	check("клетки пола: воздух, под ними твёрдое", floor_ok)
	# cave_at находит полость по любой клетке габарита и не находит снаружи
	var c0: Dictionary = caves[0]
	check("cave_at находит полость по клетке габарита", Caves.id_of(Caves.cave_at(w, int(c0.cx), int(c0.cy))) == Caves.id_of(c0)
			and Caves.id_of(Caves.cave_at(w, int(c0.x0), int(c0.y0))) == Caves.id_of(c0))
	check("cave_at вне габарита — пусто", Caves.cave_at(w, int(c0.cx), int(c0.y1) + 2).is_empty())


# ============================== ДЕТЕРМИНИЗМ ==============================

func test_determinism_and_events() -> void:
	print("-- Детерминизм и события --")
	var a := WorldGen.new(31337)
	var b := WorldGen.new(31337)
	var la := Caves.caves_between(a, 1, 10000)
	var lb := Caves.caves_between(b, 1, 10000)
	var same := la.size() == lb.size()
	for i in range(mini(la.size(), lb.size())):
		if Caves.id_of(la[i]) != Caves.id_of(lb[i]) or la[i].kind != lb[i].kind or la[i].r != lb[i].r:
			same = false
	check("один сид — те же полости (%d)" % la.size(), same and la.size() > 0)
	var other := Caves.caves_between(WorldGen.new(31338), 1, 10000)
	var diff := other.size() != la.size()
	for i in range(mini(la.size(), other.size())):
		if Caves.id_of(la[i]) != Caves.id_of(other[i]):
			diff = true
	check("другой сид — другие полости", diff)
	# землетрясение и обвал перетряхивают породу, но не полость
	var c: Dictionary = la[0]
	b.apply_global_event(555)
	b.apply_chunk_event(int(c.x0) - 2, int(c.y0) - 2, 20, 20, 777)
	var intact := true
	for cell: Vector2i in Caves.air_cells(c):
		if b.get_tile(cell.x, cell.y) != TileTypes.Type.EMPTY:
			intact = false
	var r := int(c.r)
	for dy in range(-r - 1, r + 2):
		for dx in range(-r - 1, r + 2):
			if Caves.is_rim(c, dx, dy):
				var rt := b.get_tile(int(c.cx) + dx, int(c.cy) + dy)
				if rt != TileTypes.Type.STONE and rt != TileTypes.Type.LAVA:
					intact = false
	check("после землетрясения и обвала полость на месте", intact)
	# раскопка кромки сохраняется и переживает загрузку
	var rim := Vector2i(int(c.cx), int(c.cy) - r - 1)
	check("кромка копается", b.dig_cell(rim.x, rim.y))
	var saved := b.get_save_data()
	check("формат сохранения прежний", saved.has("dug") and saved.has("events") and saved.size() == 3)
	var c2 := WorldGen.new(31337)
	c2.load_save_data(saved)
	check("после загрузки дыра в кромке на месте, полость та же",
			c2.get_tile(rim.x, rim.y) == TileTypes.Type.EMPTY and Caves.id_of(Caves.caves_between(c2, 1, 10000)[0]) == Caves.id_of(c))
	# кэш клеток и прямой расчёт согласны
	var bad := 0
	for cave in la:
		for y in range(int(cave.y0), int(cave.y1) + 1):
			for x in range(int(cave.x0), int(cave.x1) + 1):
				if a.get_tile(x, y) != a._generate_layered(x, y, 0):
					bad += 1
	check("get_tile из кэша == прямой расчёт в габаритах полостей (%d)" % bad, bad == 0)


# ============================== НЕ ЛОМАЕТ МИР ==============================

func test_no_damage_to_world() -> void:
	print("-- Сюжет, лава, образования, тайники --")
	var perm := 0
	var lava := 0
	var forms := 0
	var checked := 0
	for s in range(8):
		var w := WorldGen.new(s * 77 + 9)
		for c in Caves.caves_between(w, 1, 10000):
			checked += 1
			for y in range(int(c.y0), int(c.y1) + 1):
				for x in range(int(c.x0), int(c.x1) + 1):
					if w.is_permanent_feature(x, y):
						perm += 1
					var k := Formations.kind_at(w, x, y)
					if k != "" and k != "vein":
						forms += 1
					if y >= LavaField.min_depth() and LavaField.is_lava(w.world_seed, x, y, 0) \
							and Caves.in_shape(c, x - int(c.cx), y - int(c.cy)):
						lava += 1
	check("проверено полостей на 8 сидах: %d" % checked, checked > 60)
	check("в габаритах нет зафиксированных клеток (фундамент, торф, сюжет)", perm == 0)
	check("внутри фигуры нет природной лавы", lava == 0)
	check("габариты не пересекают каверны, провалы, гроты и руины", forms == 0)
	# тайники (ChestLogic) не попадают в воздух полости — проверяет test_caves (сцена: ему нужны автозагрузки)
	# защищённые клетки (кандидаты артефактов) остаются породой
	var g := WorldGen.new(4242)
	var c0: Dictionary = Caves.caves_between(g, 1, 10000)[0]
	var target := Vector2i(int(c0.cx) - 1, int(c0.cy) - 1)
	g.set_protect_cell(func(x, y): return x == target.x and y == target.y)
	check("защищённая клетка внутри полости не вырыта", g.get_tile(target.x, target.y) != TileTypes.Type.EMPTY
			and g.get_tile(int(c0.cx) + 1, int(c0.cy) - 1) == TileTypes.Type.EMPTY)
	g.set_protect_cell(Callable())
	# выше 1500 мир не тронут: сравнение с генерацией без полостей невозможно напрямую,
	# но apply вне пояса обязан вернуть base
	check("apply выше пояса возвращает base", Caves.apply(g, 5, 1200, TileTypes.Type.DIRT) == TileTypes.Type.DIRT
			and Caves.apply(g, 5, 4500, TileTypes.Type.COAL) == TileTypes.Type.COAL)


# ============================== СТРАЖИ ==============================

func test_guards_layout() -> void:
	print("-- Расстановка стражей --")
	check("стражей по глубине: 2 / 3 / 4", Caves.guard_count(1500) == 2 and Caves.guard_count(2500) == 3 and Caves.guard_count(3500) == 4)
	var kinds := {}
	var count_ok := true
	var place_ok := true
	var shooters_ok := true
	var distinct_ok := true
	var deterministic := true
	for s in range(8):
		var w := WorldGen.new(s * 13 + 1)
		for c in Caves.caves_between(w, 1, 10000):
			var gs := Caves.guards(c)
			if gs.size() != Caves.guard_count(int(c.cy)):
				count_ok = false
			var shooters := 0
			var used := {}
			var air := {}
			for cell: Vector2i in Caves.air_cells(c):
				air[cell] = true
			var floors := {}
			for cell: Vector2i in Caves.floor_cells(c):
				floors[cell] = true
			for g in gs:
				kinds[String(g.id)] = int(kinds.get(String(g.id), 0)) + 1
				if String(g.id) == "acid_spitter":
					shooters += 1
				var cell: Vector2i = g.cell
				if bool(g.air):
					if not air.has(cell):
						place_ok = false
				else:
					if not floors.has(cell):
						place_ok = false
					if used.has(cell):
						distinct_ok = false
					used[cell] = true
			if shooters > 2:
				shooters_ok = false
			# та же полость из другого экземпляра мира — те же стражи
			var w2 := WorldGen.new(w.world_seed)
			var c2 := Caves.cave_at(w2, int(c.cx), int(c.cy))
			var gs2 := Caves.guards(c2)
			for i in range(gs.size()):
				if gs[i].id != gs2[i].id or gs[i].cell != gs2[i].cell:
					deterministic = false
	print("     виды стражей: %s" % str(kinds))
	check("число стражей по глубине", count_ok)
	check("все четыре вида стражей встречаются", kinds.size() == 4)
	check("летуны в воздухе, остальные на полу, по одному на клетку", place_ok and distinct_ok)
	check("стреляющих не больше двух", shooters_ok)
	check("стражи детерминированы от сида", deterministic)
	var w3 := WorldGen.new(4242)
	var c3: Dictionary = Caves.caves_between(w3, 1, 10000)[0]
	check("поводок шире полости, агро шире поводка", Caves.leash(c3) > float(c3.r) and Caves.aggro(c3) > Caves.leash(c3))

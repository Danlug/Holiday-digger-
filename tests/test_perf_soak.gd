extends Node
## Подвисания на событиях и утечки за долгую сессию (ветка «perf»), на настоящей сцене, headless.
##
## Часть A — «пробы»: разовые события (открытие каждого экрана меню, всплывашка, окно подсказки,
## частицы, обвал, землетрясение, пересечение поясов, бой) — сколько мс занимает вызов и первый
## кадр после него. Порог мягкий: ловит возврат к подвису в десятки миллисекунд.
## Часть B — «сессия»: бот-имитатор роет, продаёт, роняет обвалы и землетрясения, прыгает по
## поясам и глубинам, спавнит частицы и всплывашки; каждые 10 игровых секунд пишем число узлов,
## объектов и сирот. После разогрева ничего не должно расти.
##
##   godot --headless --path . res://tests/test_perf_soak.tscn                  # ~1 игровая минута
##   godot --headless --path . res://tests/test_perf_soak.tscn -- --minutes=5 --scale=6   # 5 минут
##
## --scale — ускорение игрового времени (Engine.time_scale): кадр headless и так ~7 мс, а 5 минут
## игры на 60 к/с это 18 000 кадров; с ускорением 6 хватает ~70 секунд стены.

const HITCH_LIMIT_MS := 150.0       # одна проба дороже — провал (на нормальной машине 1-45; run_tests гонит по 4 параллельно)
const FRAME_FLOOR_MS := 7.0         # пустой кадр headless-движка
const SAMPLE_EVERY := 10.0          # игровых секунд между отсчётами
const DEPTHS := [20, 700, 1500, 2500, 3400, 4300, 5500, 6400, 7600, 8400, 9500]
const SEGMENT := 12.0               # игровых секунд на одну глубину
const GROWTH_NODES := 45            # допустимый рост числа узлов после разогрева
const GROWTH_OBJECTS_PCT := 8.0

var checks := 0
var failures := 0
var _minutes := 1.0
var _scale := 3.0
var _wall_budget_s := 400.0
var main: Node2D
var player: Node2D
var world: WorldGen
var fog: FogOfWar
var hud: Control
var _frame_ms := 0.0
var _probes: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--minutes="):
			_minutes = float(a.substr(10))
		elif a.begins_with("--scale="):
			_scale = float(a.substr(8))
		elif a.begins_with("--wall="):
			_wall_budget_s = float(a.substr(7))
	print("=== test_perf_soak: %.1f игровых минут, ускорение x%.0f ===" % [_minutes, _scale])
	await _boot()
	await _probes_part()
	await _soak_part()
	print("=== Итог: %d проверок, %d провалов ===" % [checks, failures])
	Engine.time_scale = 1.0
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("  OK    ", label)
	else:
		failures += 1
		print("  FAIL  ", label)


func _boot() -> void:
	GameState.world_seed = 424242
	for id in ["intro_grandpa", "intro_boy"]:
		StoryState.mark_seen(id)
	StoryState.set_flag("intro_seen")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _i in range(4):
		await get_tree().process_frame
	player = main.player
	world = main.world
	fog = main.fog
	hud = main.hud
	main.set_process(false)   # кадр мира зовём руками (см. _probe), на сессии включим обратно
	_place(20, 30)


## Герой в пустом кармане на глубине d, туман раскрыт, окно прогрето.
func _place(x: int, d: int) -> void:
	for dx in range(-1, 3):
		for dy in range(0, 4):
			world.dig_cell(x + dx, d + dy)
	player.x = float(x) + 0.5
	player.y = float(d) + 1.5
	player.vx = 0.0
	player.vy = 0.0
	GameState.player_depth = d
	fog.reveal_around(player.x, player.y, 9, 7)


## Кадр целиком по стене (в нём и отложенная отрисовка узлов): пустой кадр движка — ~7 мс.
func _frame() -> void:
	var t := Time.get_ticks_usec()
	await get_tree().process_frame
	_frame_ms = float(Time.get_ticks_usec() - t) / 1000.0


# ---------------------------------------------------------------------------
# Часть A. Пробы событий
# ---------------------------------------------------------------------------

## Проба: вызов события, затем кадр мира main._process вручную (на холодном кэше именно он платит за
## перекраску окна), затем кадр движка (отложенная отрисовка узлов). Из кадра вычитаем пустой ~7 мс.
func _probe(label: String, fn: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	fn.call()
	var call_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var t1 := Time.get_ticks_usec()
	main._process(0.016)
	var main_ms := float(Time.get_ticks_usec() - t1) / 1000.0
	await _frame()
	var first := maxf(_frame_ms - FRAME_FLOOR_MS, 0.0)
	await _frame()
	var cost := call_ms + main_ms + first
	_probes.append([label, call_ms, main_ms, first, cost])
	print("   проба %-44s вызов %6.1f + кадр мира %6.1f + кадр движка %5.1f = %6.1f мс" % [label, call_ms, main_ms, first, cost])
	check("%s: подвис %.0f мс (порог %.0f)" % [label, cost, HITCH_LIMIT_MS], cost < HITCH_LIMIT_MS)


func _probes_part() -> void:
	print("-- Часть A: разовые события --")
	# экраны меню: открыть каждый (кроме сброса) и спрятать новые слои
	for e in MenuRegistry.entries():
		var id := String(e.id)
		if id == "reset":
			continue
		var before := _visible_layers()
		var press: Callable = e.on_press
		await _probe("меню «%s»" % id, press)
		for c in _visible_layers():
			if not before.has(c):
				c.visible = false
		await _frame()
	await _probe("всплывашка hud.toast", func(): hud.toast("Проверка всплывающей строки", 2.0))
	await _probe("частицы levelup", func(): Fx.burst("levelup", player.position, 1.0))
	await _probe("частицы dig_gold + число", func():
		Fx.burst("dig_gold", player.position, 1.0)
		Fx.float_text(player.position, "+12", Color.WHITE))
	await _probe("вспышка и тряска", func():
		Fx.flash()
		Fx.shake(4.0, 0.2))
	var hd := HintDirector.instance()
	if hd != null:
		await _probe("окно подсказки (overlay.show_hint)", func():
			hd.overlay.show_hint(Rect2(60, 200, 40, 24), false, null, "Копай", [], ""))
		hd.overlay.hide_hint(true)
		await _frame()
	# обвал и землетрясение на разведанной шахте: у поверхности и глубоко (там генерация клетки дороже,
	# а обвал сбрасывает весь кэш клеток мира — окно перекрашивается на холодном кэше)
	for base_y in [80, 6000]:
		for i in range(60):
			for k in range(40):
				world.dig_cell(15 + (k % 17), base_y - 40 + i * 2 + k / 17)
		_place(20, base_y)
		fog.reveal_around(player.x, player.y, 9, 7)
		main._process(0.016)
		await _frame()
		await _probe("обвал на глубине %d (apply_planned + impact)" % base_y, func():
			var plan := CollapseEvents.plan_chunk_collapse(world, null, base_y - 20)
			if not plan.is_empty():
				var rect := CollapseEvents.apply_planned(world, fog, plan)
				main.collapse_fx.impact(rect)
				GameState.emit_event(&"collapse", {"rect": rect}))
		# хвост: окно доперекрашивается по частям, каждый кадр в пределах бюджета
		var worst_tail := 0.0
		for i in range(30):
			var t3 := Time.get_ticks_usec()
			main._process(0.016)
			worst_tail = maxf(worst_tail, float(Time.get_ticks_usec() - t3) / 1000.0)
		check("после обвала на %d кадры хвоста не дороже порога (худший %.1f мс)" % [base_y, worst_tail], worst_tail < HITCH_LIMIT_MS * 0.4)
		await _probe("землетрясение на глубине %d" % base_y, func():
			CollapseEvents.trigger_earthquake(world, fog)
			main.collapse_fx.impact({"x0": 14, "y0": 1, "w": 8, "h": 15})
			GameState.emit_event(&"quake", {}))
	# пояса: идём через каждую границу по клетке за кадр — как падает или копает герой; самый дорогой
	# кадр на пути и есть «подвис перехода». Холодный телепорт (кэш мира пуст) — отдельной строкой.
	var edges: Array = []
	for i in range(1, Biomes.count()):
		edges.append(int(Biomes.get_biome(i).y_from))
	for y in edges:
		var cold := 0.0
		var t0 := Time.get_ticks_usec()
		_place(20, y - 8)
		main._process(0.016)
		cold = float(Time.get_ticks_usec() - t0) / 1000.0
		await _frame()
		var worst := 0.0
		var sum := 0.0
		for step in range(16):
			player.y += 1.0
			var t1 := Time.get_ticks_usec()
			main._process(0.016)
			var ms := float(Time.get_ticks_usec() - t1) / 1000.0
			worst = maxf(worst, ms)
			sum += ms
			await _frame()
		print("   пояс на глубине %5d: холодный телепорт %5.1f мс; шаг по клетке за кадр — средний %4.1f, худший %4.1f мс" % [
			y, cold, sum / 16.0, worst])
		check("пояс %d: переход шагом, худший кадр мира %.0f мс (порог %.0f)" % [y, worst, HITCH_LIMIT_MS], worst < HITCH_LIMIT_MS)
		check("пояс %d: холодный телепорт %.0f мс (порог %.0f)" % [y, cold, 3.0 * HITCH_LIMIT_MS], cold < 3.0 * HITCH_LIMIT_MS)
	# бой: монстры появляются глубже start_depth; ждём стаю и меряем кадры с ней (стена, с полом ~7 мс)
	var cd = CombatService.director
	if cd != null:
		var start: int = CombatData.start_depth()
		_place(20, start + 20)
		main.set_process(true)
		Engine.time_scale = 4.0
		# своя стая: ждать, пока спавнер расщедрится, долго; нам нужен кадр с монстрами на экране
		var ids: Array = CombatData.monster_ids()
		for i in range(mini(5, ids.size())):
			cd.spawn({"id": String(ids[i]), "x": player.x + 1.0 + float(i) * 0.5, "y": player.y, "group": 0})
		for i in range(30):
			GameState.hp = GameState.get_max_hp()
			await get_tree().process_frame
		var count: int = cd.monsters.size()
		var worst := 0.0
		var sum := 0.0
		for i in range(60):
			GameState.hp = GameState.get_max_hp()
			await _frame()
			worst = maxf(worst, _frame_ms)
			sum += _frame_ms
		Engine.time_scale = 1.0
		print("   бой: %d монстров, кадр движка в среднем %.1f мс, худший %.1f мс (пустой ~%.0f)" % [count, sum / 60.0, worst, FRAME_FLOOR_MS])
		check("бой: монстры появились (%d)" % count, count >= 1)
		check("бой: худший кадр с монстрами %.0f мс (порог %.0f)" % [worst, HITCH_LIMIT_MS], worst < HITCH_LIMIT_MS)
		main.set_process(false)


func _visible_layers() -> Array:
	var out: Array = []
	for c in get_tree().root.get_children():
		_collect_layers(c, out, 0)
	return out


func _collect_layers(n: Node, out: Array, depth: int) -> void:
	if n is CanvasLayer and (n as CanvasLayer).visible:
		out.append(n)
	if depth < 3:
		for c in n.get_children():
			_collect_layers(c, out, depth + 1)


# ---------------------------------------------------------------------------
# Часть B. Сессия
# ---------------------------------------------------------------------------

func _soak_part() -> void:
	print("-- Часть B: сессия %.1f мин. --" % _minutes)
	main.set_process(true)
	Engine.time_scale = _scale
	var wall0 := Time.get_ticks_msec()
	var game_t := 0.0
	var next_sample := SAMPLE_EVERY
	var next_dig := 0.0
	var seg_t := 0.0
	var seg := 0
	var next_toast := 3.0
	var next_fx := 1.0
	var next_coin := 2.0
	var next_sale := 15.0
	var next_collapse := 18.0
	var next_quake := 70.0
	var next_pick := 1.0
	var samples: Array = []
	var worst_frame := 0.0
	var total := _minutes * 60.0
	_place(20, DEPTHS[0])
	while game_t < total:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		game_t += dt
		seg_t += dt
		GameState.hp = GameState.get_max_hp()
		GameState.stamina = 100.0
		GameState.hunger = 100.0
		if float(Time.get_ticks_msec() - wall0) / 1000.0 > _wall_budget_s:
			print("   (бюджет стены %.0f с исчерпан на игровой секунде %.0f)" % [_wall_budget_s, game_t])
			break
		if seg_t >= SEGMENT:
			seg_t = 0.0
			seg += 1
			_place(20 + (seg % 5), DEPTHS[seg % DEPTHS.size()])
		if game_t >= next_dig:
			next_dig = game_t + 0.4
			var cx := int(player.x)
			var cy := int(player.y)
			world.dig_cell(cx, cy + 1)
			world.dig_cell(cx + 1, cy + 1)
			GameState.emit_event(&"dug", {"cell": Vector2i(cx, cy + 1), "tile": TileTypes.Type.DIRT,
				"mineral": "", "loot": false, "pos": Vector2((cx + 0.5) * 32.0, (cy + 1.5) * 32.0)})
			player.vx = 0.0
			player.y += 1.0
		if game_t >= next_pick:
			next_pick = game_t + 1.0
			GameState.emit_event(&"picked", {"item": "iron_ore", "count": 1})
		if game_t >= next_fx:
			next_fx = game_t + 1.5
			Fx.burst("dig_dirt", player.position, 1.0)
			Fx.float_text(player.position, "+1", Color.WHITE)
		if game_t >= next_coin:
			next_coin = game_t + 2.0
			GameState.add_coins(25)
		if game_t >= next_sale:
			next_sale = game_t + 15.0
			GameState.emit_event(&"sold", {"coins": 100, "count": 4})
		if game_t >= next_toast:
			next_toast = game_t + 6.0
			hud.toast("Сессия: %d" % int(game_t), 2.0)
		if game_t >= next_collapse:
			next_collapse = game_t + 20.0
			if main._planned_collapse.is_empty():
				var plan := CollapseEvents.plan_chunk_collapse(world, null, player.cell_y())
				if not plan.is_empty():
					main._planned_collapse = plan
					main._planned_left = 1.6
					main.collapse_fx.warn(plan, 1.6)
		if game_t >= next_quake:
			next_quake = game_t + 90.0
			CollapseEvents.trigger_earthquake(world, fog)
			main.collapse_fx.impact({"x0": 14, "y0": 1, "w": 8, "h": 15})
			GameState.emit_event(&"quake", {})
			_place(20, DEPTHS[seg % DEPTHS.size()])
		if game_t >= next_sample:
			next_sample += SAMPLE_EVERY
			samples.append(_sample(game_t))
			_debug_orphans(game_t)
		worst_frame = maxf(worst_frame, get_process_delta_time() * 1000.0 / maxf(Engine.time_scale, 1.0))
	Engine.time_scale = 1.0
	_report_soak(samples)


func _sample(t: float) -> Dictionary:
	return {
		"t": t,
		"nodes": get_tree().get_node_count(),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"mem_mb": float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
		"ambient": main.ambient_fx.particle_count(),
		"fx": 0,
	}


## Отладка сирот: на отсчёте, где они появились, печатаем, кто это.
func _debug_orphans(t: float) -> void:
	if int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) > 0 and OS.is_debug_build():
		print("   сироты на t=%.0f:" % t)
		print_orphan_nodes()


func _report_soak(samples: Array) -> void:
	for s in samples:
		print("   t=%5.0f с  узлов %5d  объектов %6d  сирот %3d  ресурсов %4d  память %6.1f МБ  ambient %2d" % [
			s.t, s.nodes, s.objects, s.orphans, s.resources, s.mem_mb, s.ambient])
	check("снято не меньше 5 отсчётов (%d)" % samples.size(), samples.size() >= 5)
	if samples.size() < 5:
		return
	# базис: максимум за вторую четверть (разогрев позади), итог: максимум за последнюю четверть
	var n := samples.size()
	var base_nodes := 0
	var base_obj := 0
	for i in range(n / 4, n / 2):
		base_nodes = maxi(base_nodes, int(samples[i].nodes))
		base_obj = maxi(base_obj, int(samples[i].objects))
	var end_nodes := 0
	var end_obj := 0
	var end_orph := 0
	for i in range(n * 3 / 4, n):
		end_nodes = maxi(end_nodes, int(samples[i].nodes))
		end_obj = maxi(end_obj, int(samples[i].objects))
		end_orph = maxi(end_orph, int(samples[i].orphans))
	check("узлы не растут: %d -> %d (допуск +%d)" % [base_nodes, end_nodes, GROWTH_NODES], end_nodes <= base_nodes + GROWTH_NODES)
	var pct := 100.0 * float(end_obj - base_obj) / maxf(float(base_obj), 1.0)
	check("объекты не растут: %d -> %d (%.1f%%, допуск %.0f%%)" % [base_obj, end_obj, pct, GROWTH_OBJECTS_PCT], pct <= GROWTH_OBJECTS_PCT)
	check("сирот-узлов не больше 10 (%d)" % end_orph, end_orph <= 10)
	var amb := 0
	for s in samples:
		amb = maxi(amb, int(s.ambient))
	check("частиц AmbientFx не больше лимита %d (максимум %d)" % [AmbientFx.MAX_PARTICLES, amb], amb <= AmbientFx.MAX_PARTICLES)
	var fx := get_tree().get_first_node_in_group(Fx.GROUP) as FxService
	if fx != null:
		check("FxService: живых частиц не больше лимита %d (сейчас %d)" % [fx.max_particles, fx.active_particles()],
			fx.active_particles() <= fx.max_particles)
		check("FxService: пул эмиттеров не вырос (%d)" % fx.pool_size(), fx.pool_size() == int(Juice.num("fx.emitters", 14.0)))

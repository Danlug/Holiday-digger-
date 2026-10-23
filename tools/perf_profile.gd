extends Node
## Профиль кадра игры по скриптам: сколько микросекунд на кадр уходит в `_process` каждого скрипта
## (по сумме всех узлов этого скрипта) и сколько узлов вообще обрабатывается. Плюс, в настоящем
## рендере, число draw calls / объектов за кадр.
##
##   godot --headless --path . res://tools/perf_profile.tscn
##   xvfb-run -a godot --path . res://tools/perf_profile.tscn --rendering-driver opengl3 -- --json=/tmp/p.json
##
## Почему вручную, а не «замером кадра движка»: пустой кадр headless-движка занимает ≈ 7 мс сам
## по себе (внутренняя задержка цикла), TIME_PROCESS обновляется раз в секунду, а вычитание узлов
## по одному тонет в шуме. Поэтому выключаем авто-обработку и зовём `_process` сами с таймером:
## цифры — чистая стоимость скриптов, как в вебе (там один поток). `_draw` и работа сервера
## отрисовки сюда не входят: они в `perf_report` (WorldView) и в draw calls.
##
## Состояния: поверхность; исследованная шахта на 100; лава на 3100; бой на 6000.

const STATES := [["поверхность", 0], ["шахта 100", 100], ["лава 3100", 3100], ["бой 6000", 6000]]
const WARMUP := 20
const FRAMES := 120

var _out: Dictionary = {}


func _ready() -> void:
	var json_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			json_path = a.substr(7)
	for id in ["intro_grandpa", "intro_boy"]:
		StoryState.mark_seen(id)
	StoryState.set_flag("intro_seen")
	GameState.world_seed = 20260101
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _i in range(3):
		await get_tree().process_frame
	var real := DisplayServer.get_name() != "headless"
	print("=== perf_profile (%s) ===" % DisplayServer.get_name())
	for st in STATES:
		await _go(main, int(st[1]))
		var res: Dictionary = {}
		if real:
			for _i in range(30):
				await get_tree().process_frame
			res["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			res["render_objects"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
			res["primitives"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			res["draw_by_subtree"] = await _draw_ablation(main)
		res["nodes"] = get_tree().get_node_count()
		res["objects"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		var per_script: Dictionary = _manual_frames(main)
		var total := 0.0
		for k in per_script:
			total += float(per_script[k].us)
		res["scripts_us_per_frame"] = total
		res["top"] = _top(per_script, 14)
		res["main_segments"] = _main_segments(main)
		_out[st[0]] = res
		print("%s: скрипты %.2f мс/кадр, узлов %d, объектов %d%s" % [
			st[0], total / 1000.0, res.nodes, res.objects,
			(", draw calls %d, объектов рендера %d, примитивов %d" % [res.draw_calls, res.render_objects, res.primitives]) if real else ""])
		for row in res.top:
			print("    %7.0f мкс (худший кадр %6.0f)  x%-3d %s" % [row[1], row[3], row[2], row[0]])
		print("  main._process по частям (мкс): ", res.main_segments)
		if real:
			print("  draw calls / объектов рендера, которые даёт поддерево (разность при скрытии): ", res.draw_by_subtree)
	var hidden := _hidden_but_processing(main)
	_out["скрыты, но обрабатываются"] = hidden
	print("Скрытые узлы, у которых включён _process (зря тратят кадр): ", hidden)
	if not json_path.is_empty():
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(_out, "\t"))
		f.close()
	get_tree().quit(0)


## Ставит героя на глубину и раскрывает окно целиком (худший честный случай: серый туман везде).
func _go(main: Node2D, depth: int) -> void:
	var p = main.player
	p.x = 20.5
	p.y = float(depth) + 0.5
	p.vx = 0.0
	p.vy = 0.0
	GameState.player_depth = depth
	if depth > 0:
		for y in range(depth - 3, depth + 18):
			for x in range(WorldGen.WIDTH):
				main.fog.reveal_around_cell(x, y, 1, 0)
		main.fog.reveal_around(p.x, p.y, 9, 7)
	for _i in range(WARMUP):
		await get_tree().process_frame


## Сколько draw calls и объектов рендера даёт каждое поддерево: прячем его и смотрим разность.
func _draw_ablation(main: Node) -> Dictionary:
	var base := await _draw_stats()
	var res := {"всего": base}
	var subs: Array = []
	for c in main.get_children():
		subs.append(c)
	for c in main.view_root.get_children():
		subs.append(c)
	for c in subs:
		if not (c is CanvasItem or c is CanvasLayer):
			continue
		if c == main.view_root:
			continue
		var was: bool = c.visible
		if not was:
			continue
		c.visible = false
		var s := await _draw_stats()
		c.visible = true
		var d_calls: int = int(base[0]) - int(s[0])
		var d_obj: int = int(base[1]) - int(s[1])
		if d_calls != 0 or d_obj != 0:
			res[String(c.name)] = [d_calls, d_obj]
	return res


func _draw_stats() -> Array:
	for _i in range(4):
		await get_tree().process_frame
	return [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))]


## Кадры вручную: все узлы с включённой обработкой гасим и зовём их _process сами, с таймером.
func _manual_frames(main: Node) -> Dictionary:
	var nodes: Array = []
	_collect(main, nodes)
	for n in nodes:
		n.set_process(false)
	var per_script := {}
	for _f in range(FRAMES):
		for n in nodes:
			var t0 := Time.get_ticks_usec()
			n._process(1.0 / 60.0)
			var dt := Time.get_ticks_usec() - t0
			var key: String = n.get_script().resource_path if n.get_script() != null else n.get_class()
			if not per_script.has(key):
				per_script[key] = {"us": 0.0, "max": 0.0, "nodes": {}}
			per_script[key].us += float(dt) / float(FRAMES)
			per_script[key].max = maxf(float(per_script[key].max), float(dt))
			per_script[key].nodes[n.get_instance_id()] = true
	for n in nodes:
		n.set_process(true)
	return per_script


## Части main._process по отдельности — те же вызовы, в том же порядке.
func _main_segments(main: Node) -> Dictionary:
	main.set_process(false)
	var cam: Vector2 = main._camera()
	var vw: int = main._view_w()
	var vh: int = main._view_h()
	var acc := {}
	var calls := {
		"physics_tick": func(): main.player.physics_tick(0.016),
		"fog_reveal": func(): main._reveal_around_player(),
		"backdrop": func(): main.backdrop.update(cam),
		"clouds": func(): main.clouds_view.update(cam),
		"world_view.render": func(): main.world_view.render(cam),
		"deep_backdrop": func(): main.deep_backdrop.update(cam, vw, vh),
		"ambient_fx": func(): main.ambient_fx.update(cam, vw, vh, 0.016),
		"surface_life": func(): main.surface_life.update(cam, vw, vh, 0.016),
		"collapse_fx": func(): main.collapse_fx.update(cam, vw, vh, 0.016),
		"sky_set_camera": func(): main.sky_view.set_camera(cam, vw),
	}
	var tw: Node = main.view_root.get_node_or_null("TechWorld")
	if tw != null and tw.has_method("_rebuild_lava"):
		calls["tech_world.lava_rebuild (раз в 0,2 с)"] = func(): tw._rebuild_lava()
	for k in calls:
		var fn: Callable = calls[k]
		var t0 := Time.get_ticks_usec()
		for _i in range(FRAMES):
			fn.call()
		acc[k] = snappedf(float(Time.get_ticks_usec() - t0) / float(FRAMES), 1.0)
	main.set_process(true)
	return acc


## Узлы интерфейса, которые скрыты, но у которых _process включён: скрипт -> число узлов.
func _hidden_but_processing(root: Node) -> Dictionary:
	var res := {}
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is CanvasItem and n.is_processing() and not (n as CanvasItem).is_visible_in_tree() \
				and n.get_script() != null and n.has_method("_process"):
			var key: String = String(n.get_script().resource_path).trim_prefix("res://scripts/")
			res[key] = int(res.get(key, 0)) + 1
	return res


func _collect(root: Node, into: Array) -> void:
	if root.is_processing() and root.get_script() != null and root.has_method("_process"):
		into.append(root)
	for c in root.get_children():
		_collect(c, into)


func _top(per_script: Dictionary, n: int) -> Array:
	var rows: Array = []
	for k in per_script:
		rows.append([String(k).trim_prefix("res://scripts/"), float(per_script[k].us), per_script[k].nodes.size(), float(per_script[k].max)])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	return rows.slice(0, n)

extends Node
## Замеры производительности на CPU без окна: создание мира, get_tile, кадр сцены по
## частям, число узлов, запись сейва. Нужен для веб-версии: там один поток, и всё, что
## дорого в GDScript, дорого вдвойне.
##
##   godot --headless --path . res://tools/perf_report.tscn
##   godot --headless --path . res://tools/perf_report.tscn -- --json=/tmp/perf.json
##
## Рендер здесь пустышка (headless): цифры — НИЖНЯЯ граница стоимости скриптов и вызовов
## сервера, не реальное время кадра. Сравнивать их стоит «до/после» правок, а не с 16 мс.
## Каждая часть кадра меряется отдельно тем же вызовом, что делает main.gd:_process.

var _out: Dictionary = {}


func _ready() -> void:
	var json_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			json_path = a.substr(7)
	_clean_slate()
	_world_numbers()
	await _scene_numbers()
	_save_numbers()
	_print_report()
	if not json_path.is_empty():
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(_out, "\t"))
		f.close()
	get_tree().quit(0)


func _clean_slate() -> void:
	SaveSystem.delete_save()
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	GameState.reset_progress()
	GameState.world_seed = 20260101
	# интро и обучение к замерам отношения не имеют
	for id in ["intro_grandpa", "intro_boy"]:
		StoryState.mark_seen(id)
	StoryState.set_flag("intro_seen")


## Среднее время вызова в микросекундах.
func _bench(n: int, fn: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	for i in range(n):
		fn.call(i)
	return float(Time.get_ticks_usec() - t0) / float(n)


# ---------------------------------------------------------------------------
# Мир
# ---------------------------------------------------------------------------

func _world_numbers() -> void:
	var t0 := Time.get_ticks_usec()
	var w := WorldGen.new(777)
	_out["world_new_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	for depth in [10, 500, 3000, 6000]:
		var us := _bench(20000, func(i): w.get_tile(i % WorldGen.WIDTH, depth + (i / WorldGen.WIDTH) % 200))
		_out["get_tile_us_depth_%d" % depth] = us
	# Дифф-нагрузка: игрок выкопал много клеток — get_tile не должен дорожать.
	for i in range(8000):
		w.dig_cell(WorldGen.GARDEN_X_MIN + i % 17, 6 + i / 17)
	_out["get_tile_us_with_8000_diffs"] = _bench(20000, func(i): w.get_tile(i % WorldGen.WIDTH, 6 + (i / 32) % 470))
	var fog := FogOfWar.new()
	_out["fog_get_state_us"] = _bench(20000, func(i): fog.get_state(i % 32, 6 + i % 400))
	# События мира на большой шахте (20 000 выкопанных клеток): разовые подвисы кадра.
	var ev := WorldGen.new(778)
	for i in range(20000):
		ev.diffs[(6 + i / 17) * WorldGen.WIDTH + WorldGen.GARDEN_X_MIN + i % 17] = true
	var t1 := Time.get_ticks_usec()
	ev.apply_chunk_event(18, 300, 8, 8, 5)
	_out["event_collapse_ms_20k_diffs"] = float(Time.get_ticks_usec() - t1) / 1000.0
	t1 = Time.get_ticks_usec()
	ev.apply_global_event(6)
	_out["event_earthquake_ms_20k_diffs"] = float(Time.get_ticks_usec() - t1) / 1000.0
	t1 = Time.get_ticks_usec()
	fog.reset_all()
	_out["event_fog_reset_all_ms"] = float(Time.get_ticks_usec() - t1) / 1000.0


# ---------------------------------------------------------------------------
# Живая сцена: части кадра, узлы
# ---------------------------------------------------------------------------

func _scene_numbers() -> void:
	var t0 := Time.get_ticks_usec()
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _i in range(4):
		await get_tree().process_frame
	_out["boot_to_4_frames_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	main.set_process(false)  # кадр гоним сами, по частям

	var hud = main.hud
	var player = main.player
	var wv = main.world_view
	var world: WorldGen = main.world
	# Герой в середине огорода на глубине: туман и камера как в игре.
	player.x = 20.5
	player.y = 40.5
	var cam: Vector2 = main._camera()
	var cells: Vector2i = hud.get_view_cells()
	_out["view_cells"] = "%dx%d" % [cells.x, cells.y]
	_out["sprite_pool"] = wv._pool.size()

	var n := 300
	_out["frame_world_view_render_us"] = _bench(n, func(_i): wv.render(cam))
	_out["frame_player_tick_us"] = _bench(n, func(_i): player.physics_tick(0.016))
	_out["frame_hud_intent_us"] = _bench(n, func(_i): hud.update_input_intent())
	_out["frame_fog_reveal_us"] = _bench(n, func(_i): main._reveal_around_player())
	_out["frame_fog_reveal_radii_us"] = _bench(n, func(_i): GameState.get_vision_terrain_radius() + GameState.get_vision_resource_radius())
	var tr: int = GameState.get_vision_terrain_radius()
	var rr: int = GameState.get_vision_resource_radius()
	_out["frame_fog_reveal_circles_us"] = _bench(n, func(_i): main.fog.reveal_around(player.x, player.y, tr, rr))
	_out["frame_sky_set_camera_us"] = _bench(n, func(_i): main.sky_view.set_camera(cam, 7))
	_out["frame_backdrop_us"] = _bench(n, func(_i): main.backdrop.update(cam))
	_out["frame_clouds_us"] = _bench(n, func(_i): main.clouds_view.update(cam))
	_out["frame_hud_camera_us"] = _bench(n, func(_i): hud.set_camera(cam))
	_out["frame_main_process_us"] = _bench(n, func(_i): main._process(0.016))

	# Худший честный случай: шахта вокруг героя уже исследована (серый туман), поэтому render()
	# дёргает world.get_tile на каждую видимую клетку каждый кадр, а не только на «живую» ауру.
	var fog: FogOfWar = main.fog
	for y in range(30, 56):
		for x in range(WorldGen.WIDTH):
			fog.reveal_around_cell(x, y, 1, 0)
	_out["frame_world_view_render_explored_us"] = _bench(n, func(_i): wv.render(cam))
	var tile_n := 0
	var tile_us := Time.get_ticks_usec()
	for r in range(int(cam.y) - 1, int(cam.y) + cells.y + 2):
		for c in range(int(cam.x) - 1, int(cam.x) + cells.x + 2):
			if fog.get_state(c, r) != FogOfWar.State.BLACK:
				world.get_tile(c, r)
				tile_n += 1
	_out["explored_cells_needing_get_tile"] = tile_n
	_out["explored_get_tile_total_us"] = float(Time.get_ticks_usec() - tile_us)
	_out["tile_art_texture_for_us"] = _bench(20000, func(i): TileArt.texture_for(TileTypes.Type.DIRT, i % 32, 6 + i % 90))

	# Широкий вид: в браузере 16:9 сетка в 3-4 раза больше телефонной.
	var narrow_pool: int = wv._pool.size()
	wv.set_view_size(26, 15)
	await get_tree().process_frame
	_out["wide_view_sprite_pool"] = wv._pool.size()
	_out["wide_view_render_us"] = _bench(n, func(_i): wv.render(cam))
	wv.set_view_size(cells.x, cells.y)
	await get_tree().process_frame

	# Узлы: всего и по верхним поддеревьям.
	var counts := {}
	for child in get_tree().root.get_children():
		counts[child.name] = _count_nodes(child)
	_out["nodes_total"] = get_tree().get_node_count()
	_out["nodes_by_root_child"] = counts
	var view_root_children := {}
	for c in main.view_root.get_children():
		view_root_children[c.name] = _count_nodes(c)
	_out["nodes_view_root"] = view_root_children
	_out["objects"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_out["resources"] = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	_out["orphan_nodes"] = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_out["static_memory_mb"] = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	_out["narrow_pool_before"] = narrow_pool
	main.queue_free()
	await get_tree().process_frame


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


# ---------------------------------------------------------------------------
# Сейв
# ---------------------------------------------------------------------------

func _save_numbers() -> void:
	var w := WorldGen.new(777)
	GameState.world_ref = w
	GameState.fog_ref = FogOfWar.new()
	for size in [0, 2000, 20000]:
		w.diffs.clear()
		for i in range(size):
			w.diffs[(6 + i / 17) * WorldGen.WIDTH + WorldGen.GARDEN_X_MIN + i % 17] = true
		var t0 := Time.get_ticks_usec()
		SaveSystem.save_game()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var bytes := FileAccess.get_file_as_string(SaveSystem.SAVE_PATH).length()
		_out["save_%d_diffs_ms" % size] = ms
		_out["save_%d_diffs_kb" % size] = float(bytes) / 1024.0
		t0 = Time.get_ticks_usec()
		SaveSystem.load_game()
		_out["load_%d_diffs_ms" % size] = float(Time.get_ticks_usec() - t0) / 1000.0
	GameState.world_ref = null
	GameState.fog_ref = null
	SaveSystem.delete_save()


# ---------------------------------------------------------------------------

func _print_report() -> void:
	print("=== perf_report (headless: рендер-пустышка, цифры — нижняя граница) ===")
	for k in _out.keys():
		var v = _out[k]
		if v is float:
			print("%-34s %10.2f" % [k, v])
		else:
			print("%-34s %s" % [k, str(v)])

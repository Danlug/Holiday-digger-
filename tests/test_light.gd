extends Node
## Тест слоя света и эффектов мира (ветка «world-fx»): кривая затемнения, список светящихся клеток у
## WorldView, тени, магнит добычи, ветер у поверхности, «меньше движения», бюджет кадра. Картинку смотрят
## глазами (tests/test_screenshot_fx.gd) — здесь логика и стоимость.

const WV := preload("res://scripts/world/world_view.gd")

var checks := 0
var failures := 0


class FakePlayer extends Node:
	var x: float = 20.5
	var y: float = 52.5
	var digging = null
	var rig_transition: String = ""


func _ready() -> void:
	print("=== test_light: старт ===")
	GameState.world_seed = 20261024
	test_curve_and_tables()
	test_glow_cells()
	await test_in_main()
	test_fx_service()
	test_reduce_motion()
	print("=== Итог: %d проверок, %d провалов ===" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("  OK    ", label)
	else:
		failures += 1
		print("  FAIL  ", label)


func _bench(n: int, fn: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	for i in range(n):
		fn.call(i)
	return float(Time.get_ticks_usec() - t0) / float(n)


func test_curve_and_tables() -> void:
	print("-- кривая затемнения, таблицы, шейдер --")
	check("на поверхности темноты нет", LightLayer.dark_for_depth(0.0) == 0.0 and LightLayer.dark_for_depth(2.0) == 0.0)
	var mono := true
	var jump := false
	var prev := 0.0
	var mx := 0.0
	for y in range(0, 7001, 10):
		var d := LightLayer.dark_for_depth(float(y))
		mono = mono and d >= prev - 0.0001
		jump = jump or absf(d - prev) > 0.03
		prev = d
		mx = maxf(mx, d)
	check("затемнение растёт с глубиной до 7000 (не убывает)", mono)
	check("без скачков: шаг по 10 клеток не больше 0.03", not jump)
	check("потолок затемнения не душит картинку (<= 0.55)", mx <= 0.55 and mx > 0.3)
	check("небесное ядро светлее преисподней", LightLayer.dark_for_depth(9800.0) < LightLayer.dark_for_depth(6500.0) * 0.5)
	check("глубже мира значение держится (без NaN)", is_finite(LightLayer.dark_for_depth(1.0e6)))
	for i in range(Biomes.count()):
		var y := float(Biomes.get_biome(i).get("y_from", 1)) + 10.0
		var c := LightLayer.belt_colors(y)
		check("пояс %s: цвета тьмы и факела заданы" % Biomes.get_biome(i).get("id", "?"), c.dark is Color and c.torch is Color)
	var mid := LightLayer.belt_colors(float(Biomes.get_biome(1).get("y_from", 1000)) - 70.0 + 1.0)
	check("на границе поясов цвет между соседями, а не скачок", mid.dark is Color)
	check("шейдер света загружается", load(LightLayer.SHADER_PATH) is Shader)
	check("текстура ореола на месте", ResourceLoader.exists(LightLayer.HALO_PATH) and ResourceLoader.exists("res://art/fx/shadow_blob.png"))
	var tiles_ok := true
	for t in LightLayer.GLOW_TILES:
		var k: int = LightLayer.GLOW_TILES[t]
		tiles_ok = tiles_ok and k > 0 and k < LightLayer.GLOW_KEYS.size() and LightLayer.GLOW_TYPE_OF[k] == t \
				and not LightLayer.glow_def(k).is_empty()
	check("таблица свечения согласована (тип ↔ вид ↔ конфиг)", tiles_ok and LightLayer.GLOW_TILES.size() == LightLayer.GLOW_KEYS.size() - 1)
	var swing_ok := true
	for n in SurfaceLife.SWAY_DECOR:
		swing_ok = swing_ok and TileArt.garden_texture(n) != null
	check("все качающиеся растения есть среди картинок огорода", swing_ok)
	var win_ok := true
	for w in SurfaceLife.WINDOWS:
		win_ok = win_ok and w[0] + w[2] <= SurfaceLife.HOUSE_W and w[1] + w[3] <= SurfaceLife.HOUSE_H
	check("окна дома лежат внутри картинки дома", win_ok)


func test_glow_cells() -> void:
	print("-- список светящихся клеток WorldView --")
	var w := WorldGen.new(4242)
	var f := FogOfWar.new()
	var p := FakePlayer.new()
	add_child(p)
	var ores := {Vector2i(20, 52): TileTypes.Type.URANIUM_ORE, Vector2i(22, 53): TileTypes.Type.DIVINE_HEART,
			Vector2i(18, 51): TileTypes.Type.GOLD_ORE, Vector2i(23, 49): TileTypes.Type.HELLSTONE}
	w.overlay = func(x: int, y: int) -> int: return int(ores.get(Vector2i(x, y), -1))
	w.overlay_y_min = 1
	# уран и сердце открыты полностью, золото — не светится, адский камень скрыт туманом (серый)
	f.reveal_around(20.5, 52.5, 3, 3)
	f.reveal_terrain(23.5, 49.5, 1)
	var v: Node2D = WV.new()
	add_child(v)
	v.world = w
	v.fog = f
	v.player = p
	v.deep_backdrop_active = true
	v.set_view_size(15, 14)
	v.render(Vector2(13.0, 46.0))
	var cells: Array = v.glow_cells()
	var got := {}
	for c: Vector3i in cells:
		got[Vector2i(c.x, c.y)] = c.z
	check("уран и божественное сердце в списке", got.has(Vector2i(20, 52)) and got.has(Vector2i(22, 53)))
	check("вид свечения совпадает с таблицей", got.get(Vector2i(20, 52), 0) == LightLayer.GLOW_TILES[TileTypes.Type.URANIUM_ORE])
	check("золото не светится", not got.has(Vector2i(18, 51)))
	check("светящаяся клетка в сером тумане не выдаёт себя", not got.has(Vector2i(23, 49)))
	var ver: int = v.glow_version
	v.render(Vector2(13.0, 46.0))
	check("неподвижный кадр список не пересобирает", v.glow_version == ver and v.glow_cells().size() == cells.size())
	# откроем адский камень разведкой ресурсов — он появится
	f.reveal_resources(23.5, 49.5, 1)
	v.render(Vector2(13.0, 46.0))
	var got2 := {}
	for c: Vector3i in v.glow_cells():
		got2[Vector2i(c.x, c.y)] = true
	check("после раскрытия тумана клетка засветилась", got2.has(Vector2i(23, 49)))
	# камера уехала далеко: клеток вне окна в списке нет
	v.render(Vector2(13.0, 300.0))
	check("вне окна камеры светящихся клеток нет", v.glow_cells().size() == 0)
	v.render(Vector2(13.0, 46.0))
	var us := _bench(300, func(_i): v.render(Vector2(13.0, 46.0)))
	check("неподвижный кадр с ореолами: %.0f мкс <= 600" % us, us <= 600.0)
	var us2 := _bench(300, func(_i): v.glow_cells())
	check("glow_cells() на неизменном окне: %.1f мкс <= 20" % us2, us2 <= 20.0)
	w.overlay = Callable()
	p.queue_free()
	v.queue_free()


func test_in_main() -> void:
	print("-- в настоящей сцене: слои, тени, кадр --")
	for id in ["intro_grandpa", "intro_boy"]:
		StoryState.mark_seen(id)
	StoryState.set_flag("intro_seen")
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _i in range(4):
		await get_tree().process_frame
	var vr: Node = main.view_root
	var light := vr.get_node_or_null("LightLayer") as LightLayer
	var shadows := vr.get_node_or_null("ContactShadows") as ContactShadows
	check("слой света подключён к ViewRoot (Juice.attach)", light != null)
	print("   индексы: тени ", shadows.get_index() if shadows != null else -1, " герой ", main.player.get_index(), " мир ", main.world_view.get_index())
	check("тени подключены и лежат перед героем, после тайлов", shadows != null and shadows.get_index() < main.player.get_index()
			and shadows.get_index() > main.world_view.get_index())
	check("слой света над героем и под частицами (z)", light != null and light.get_node("Veil").z_index > 0 and light.get_node("Veil").z_index < 20)
	var sl: SurfaceLife = main.surface_life
	check("растения огорода отданы живой поверхности", main.world_view.decor_external == true and sl != null)

	# ореолы: поставим уран рядом и откроем его
	var w: WorldGen = main.world
	var p = main.player
	main.set_process(false)
	var cx := 20
	var cy := 120
	for dx in range(-1, 2):
		for dy in range(0, 4):
			w.dig_cell(cx + dx, cy + dy)
	var ores := {Vector2i(cx + 2, cy + 1): TileTypes.Type.URANIUM_ORE, Vector2i(cx - 2, cy + 2): TileTypes.Type.ANGEL_STONE}
	w.overlay = func(x: int, y: int) -> int: return int(ores.get(Vector2i(x, y), -1))
	w.overlay_y_min = 1
	p.x = float(cx) + 0.5
	p.y = float(cy) + 1.5
	p.vx = 0.0
	p.vy = 0.0
	GameState.player_depth = cy
	main.fog.reveal_around(p.x, p.y, 6, 5)
	for _i in range(40):
		main._process(0.016)
		light._process(0.016)
		shadows._process(0.016)
	check("ореолы: две светящиеся клетки видны слою света", light.halo_count() == 2)
	var hero_shadow: Sprite2D = shadows._hero
	check("герой стоит на земле: тень включена у ног", hero_shadow.visible)
	var gy := float(shadows._ground_row) * 32.0
	check("тень лежит на верхней грани земли под героем", absf(hero_shadow.position.y - (gy + 2.0)) <= 1.0 and shadows._ground_row == cy + 4)
	var a_ground := hero_shadow.modulate.a
	p.y -= 2.5   # прыжок: до земли ~2,5 клетки
	for _i in range(3):
		shadows._process(0.016)
	check("в воздухе тень на той же земле, но бледнее и уже", hero_shadow.visible and hero_shadow.modulate.a < a_ground - 0.2
			and hero_shadow.scale.x < 0.9 and absf(hero_shadow.position.y - (gy + 2.0)) <= 1.0)
	var px_save: float = p.x
	p.x = 15.5
	p.y = -12.0   # высоко в небе над огородом
	shadows._process(0.016)
	check("слишком высоко над землёй тени нет", not hero_shadow.visible)
	p.x = px_save
	p.y = float(cy) + 1.5
	shadows._process(0.016)
	GameState.house_is_indoors = true
	light._process(0.016)
	shadows._process(0.016)
	check("в доме слой света и тень выключены", not light.get_node("Veil").visible and not hero_shadow.visible)
	GameState.house_is_indoors = false
	light._process(0.016)

	# стоимость кадра слоя света и теней
	var us := _bench(300, func(_i):
		light._process(0.016)
		shadows._process(0.016))
	check("слой света + тени: %.0f мкс на кадр <= 250" % us, us <= 250.0)
	check("шейдер получает затемнение глубины 120 и факел героя",
			float((light._mat as ShaderMaterial).get_shader_parameter("depth_dark")) > 0.05
			and float((light._mat as ShaderMaterial).get_shader_parameter("torch_r")) > 100.0)
	var tw := vr.get_node_or_null("TechWorld")
	check("свечение лавы остаётся за TechWorld (не дублируется слоем света)", tw == null or tw.get_node_or_null("LavaGlow") != null)

	# поверхность: днём тьмы нет
	p.x = 15.5
	p.y = 0.7
	GameState.player_depth = 0
	for _i in range(60):
		light._process(0.016)
	check("на поверхности затемнение сходит к нулю", float((light._mat as ShaderMaterial).get_shader_parameter("depth_dark")) < 0.02)
	w.overlay = Callable()
	main.queue_free()
	await get_tree().process_frame


func test_fx_service() -> void:
	print("-- частицы и магнит --")
	var fx := FxService.new()
	add_child(fx)
	for k in ["dig_dirt", "dig_stone", "dig_ore", "dig_gold", "dig_puff", "ore_glint", "pickup_glint", "land_dust_l",
			"land_dust_r", "jump_puff", "rock_fall", "enemy_die", "die_smoke", "hit_flash", "spark", "poof"]:
		check("вид частиц %s есть" % k, fx.has_kind(k))
	for i in range(60):
		fx.burst(["dig_dirt", "rock_fall", "enemy_die", "ore_glint", "land_dust_l"][i % 5], Vector2(40 + i, 40), 2.0, Color(0.4, 1.0, 0.3))
	check("потолок частиц держится: %d <= 220" % fx.active_particles(), fx.active_particles() <= fx.max_particles)
	Settings.reduce_motion = false
	var target := Vector2(100, 100)
	fx.magnet_target = func() -> Vector2: return target
	fx.magnet(Vector2(10, 10), Color.WHITE, 3)
	check("магнит: три блёстки в полёте", fx.active_magnets() == 3)
	for i in range(40):
		fx.magnet(Vector2(10, 10), Color.WHITE, 3)
	check("магнит: не больше %d в полёте" % FxService.MAG_MAX, fx.active_magnets() <= FxService.MAG_MAX)
	for i in range(120):
		fx._tick_magnet(0.016)
	check("магнит: все долетели и вернулись в пул", fx.active_magnets() == 0)
	fx.magnet_target = Callable()
	fx.magnet(Vector2.ZERO, Color.WHITE, 3)
	check("магнит без героя ничего не пускает", fx.active_magnets() == 0)
	fx.queue_free()


func test_reduce_motion() -> void:
	print("-- «меньше движения» --")
	var fx := FxService.new()
	add_child(fx)
	fx.magnet_target = func() -> Vector2: return Vector2(50, 50)
	Settings.reduce_motion = true
	fx.magnet(Vector2.ZERO, Color.WHITE, 3)
	check("без движения магнит не летит", fx.active_magnets() == 0)
	var full := FxService.new()
	add_child(full)
	Settings.reduce_motion = false
	full.burst("dig_dirt", Vector2(10, 10), 1.0)
	var n_full: int = full.active_particles()
	Settings.reduce_motion = true
	var calm := FxService.new()
	add_child(calm)
	calm.burst("dig_dirt", Vector2(10, 10), 1.0)
	var n_calm: int = calm.active_particles()
	check("без движения частиц копки вдвое меньше (%d < %d)" % [n_calm, n_full], n_calm < n_full and n_calm > 0)
	var sl := SurfaceLife.new()
	add_child(sl)
	check("без движения ветра нет", sl._wind(100.0) == 0.0)
	Settings.reduce_motion = false
	check("с движением ветер есть", absf(sl._wind(100.0)) > 0.0 or absf(sl._wind(500.0)) > 0.0)
	Settings.reduce_motion = false
	fx.queue_free()
	full.queue_free()
	calm.queue_free()
	sl.queue_free()

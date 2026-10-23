extends Node
## Кэш окна WorldView (ветка «perf»): после любой цепочки событий спрайты должны выглядеть ровно так,
## как при полной перекраске с нуля. Плюс версии WorldGen/FogOfWar, быстрый туман, счётчики работы.
## Время здесь не меряем (его — test_perf_budget): только то, что работа не делается зря и не теряется.

const WV := preload("res://scripts/world/world_view.gd")

var checks := 0
var failures := 0


class FakePlayer extends Node:
	var x: float = 20.5
	var y: float = 50.5
	var digging = null
	var rig_transition: String = ""


func _ready() -> void:
	print("=== test_perf: старт ===")
	test_world_atlas()
	test_fog_matches_reference()
	test_fog_versions()
	test_world_versions()
	test_cache_equals_fresh_paint()
	test_lava_animation()
	test_direct_diff_is_healed_by_validation()
	test_idle_frame_does_no_work()
	test_overlay_redraw_gating()
	await test_no_node_growth()
	print("=== Итог: %d проверок, %d провалов ===" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("  OK    ", label)
	else:
		failures += 1
		print("  FAIL  ", label)


# ---------------------------------------------------------------------------
# Единый атлас тайлов мира
# ---------------------------------------------------------------------------

## Исходный PNG как есть (без импорта): сверяем атлас с тем, из чего его собирает скрипт.
func _img(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


func test_world_atlas() -> void:
	print("-- Единый атлас тайлов мира (tools/gen_world_atlas.py) --")
	var meta = JSON.parse_string(FileAccess.get_file_as_string(TileArt.WORLD_ATLAS_JSON))
	check("world_atlas.json читается", typeof(meta) == TYPE_DICTIONARY)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var atlas_img := _img(TileArt.WORLD_ATLAS_PNG)
	check("world_atlas.png читается", atlas_img != null and not atlas_img.is_empty())
	if atlas_img == null or atlas_img.is_empty():
		return
	var cell := int(meta.cell)
	var pad := int(meta.pad)
	var cols := int(meta.cols)
	var stride := cell + 2 * pad
	var deep_meta = JSON.parse_string(FileAccess.get_file_as_string("res://art/tiles/deep/atlas.json"))
	var deep_names: Array = deep_meta.names
	var belts := {}
	var stale: Array = []
	var tiles: Dictionary = meta.tiles
	for key: String in tiles:
		var idx := int(tiles[key])
		var region := Rect2i((idx % cols) * stride + pad, (idx / cols) * stride + pad, cell, cell)
		var got := atlas_img.get_region(region)
		var want: Image = null
		var parts := key.split("/")
		if key == "white":
			want = Image.create(cell, cell, false, got.get_format())
			want.fill(Color.WHITE)
		elif parts[0] == "0":
			want = _img("res://art/tiles/%s.png" % parts[1])
		else:
			var belt := int(parts[0])
			if not belts.has(belt):
				belts[belt] = _img("res://art/tiles/deep/belt_%d.png" % belt)
			var i := deep_names.find(parts[1])
			var bs := int(deep_meta.cell) + 2 * int(deep_meta.pad)
			want = (belts[belt] as Image).get_region(Rect2i((i % int(deep_meta.cols)) * bs + int(deep_meta.pad),
				(i / int(deep_meta.cols)) * bs + int(deep_meta.pad), cell, cell))
		if want == null or want.get_format() != got.get_format():
			want.convert(got.get_format()) if want != null else null
		if want == null or want.get_data() != got.get_data():
			stale.append(key)
	check("каждая клетка атласа совпадает с исходным тайлом (устарели: %s) — запусти tools/gen_world_atlas.py" % ", ".join(stale),
		stale.is_empty())
	# что просит TileArt, то в атласе есть: иначе клетка выпадет из общего пакета отрисовки
	var missing: Array = []
	var files: Array = TileArt._tile_to_file.values()
	files.append_array(TileArt.DIRT_FILES)
	files.append_array(TileArt.GRASS_FILES)
	for i in range(TileArt.LAVA_FRAMES):
		files.append("lava_%d" % (i + 1))
	for f in files:
		if tiles.get("0/" + String(f)) == null:
			missing.append("0/" + String(f))
	for belt in range(1, Biomes.count()):
		for n in deep_names:
			if tiles.get("%d/%s" % [belt, n]) == null:
				missing.append("%d/%s" % [belt, n])
	check("у каждого файла тайла и каждой вырезки пояса есть клетка в атласе (нет: %s)" % ", ".join(missing), missing.is_empty())
	# и отдаёт именно её
	var t0 := TileArt.texture_for(TileTypes.Type.GOLD_ORE, 3, 100)
	var t3 := TileArt.texture_for(TileTypes.Type.GOLD_ORE, 3, 3500)
	var w := TileArt.white_texture()
	check("тайлы поясов 0 и 3 и заливка — вырезки одной текстуры",
		t0 is AtlasTexture and t3 is AtlasTexture and w is AtlasTexture
		and (t0 as AtlasTexture).atlas == (t3 as AtlasTexture).atlas and (w as AtlasTexture).atlas == (t0 as AtlasTexture).atlas)
	check("белая заливка — один тексель, как прежняя текстура 1x1", w != null and w.get_width() == 1 and w.get_height() == 1)
	check("лава и трава тоже из атласа", (TileArt.texture_for(TileTypes.Type.LAVA, 1, 3500) as AtlasTexture).atlas == (t0 as AtlasTexture).atlas
		and (TileArt.grass_texture(5) as AtlasTexture).atlas == (t0 as AtlasTexture).atlas)


# ---------------------------------------------------------------------------
# Туман
# ---------------------------------------------------------------------------

## Прежний алгоритм «в лоб»: покрытие считается для каждой клетки прямоугольника круга.
func _reference_reveal(fog: FogOfWar, ref: Dictionary, cx: float, cy: float, radius: int) -> void:
	if radius <= 0:
		return
	var r := FogOfWar.vision_radius(radius)
	for y in range(maxi(int(floor(cy - r)), 1), int(ceil(cy + r)) + 1):
		for x in range(maxi(int(floor(cx - r)), 0), mini(int(ceil(cx + r)), FogOfWar.WIDTH - 1) + 1):
			if fog._coverage(cx, cy, r, float(x), float(y)) >= FogOfWar.COVERAGE_TO_REVEAL:
				ref[y * 64 + x] = true


func test_fog_matches_reference() -> void:
	print("-- Туман: быстрый раскрыватель == прежний «в лоб» --")
	var fog := FogOfWar.new()
	var probe := FogOfWar.new()
	var ref_t := {}
	var ref_r := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var mismatches := 0
	var rect_misses := 0
	for i in range(160):
		var cx := rng.randf_range(-1.0, 33.0)
		var cy := rng.randf_range(0.0, 90.0)
		var tr := rng.randi_range(0, 11)
		var rr := rng.randi_range(0, 9)
		var before := _fog_states(fog, 0, 90)
		var v0 := fog.version
		fog.reveal_around(cx, cy, tr, rr)
		_reference_reveal(probe, ref_t, cx, cy, tr)
		_reference_reveal(probe, ref_r, cx, cy, rr)
		var after := _fog_states(fog, 0, 90)
		var changed: Variant = fog.changed_since(v0)
		for k in after:
			var y: int = k / 64
			var x: int = k % 64
			var want := FogOfWar.State.FULL if ref_r.has(k) else (FogOfWar.State.GRAY if ref_t.has(k) else FogOfWar.State.BLACK)
			if y >= 1 and int(after[k]) != want:
				mismatches += 1
			if int(after[k]) != int(before[k]):
				if changed == null or not (changed as PackedInt32Array).has(y * FogOfWar.WIDTH + x):
					rect_misses += 1
	check("состояние каждой клетки совпадает с эталоном (160 случайных вызовов, дробные центры, края)", mismatches == 0)
	check("журнал changed_since содержит все изменившиеся клетки", rect_misses == 0)


func _fog_states(fog: FogOfWar, y0: int, y1: int) -> Dictionary:
	var out := {}
	for y in range(y0, y1 + 1):
		for x in range(FogOfWar.WIDTH):
			out[y * 64 + x] = fog.get_state(x, y)
	return out


func test_fog_versions() -> void:
	print("-- Туман: версии --")
	var fog := FogOfWar.new()
	check("свежий туман: версия 0, изменений нет", fog.version == 0 and (fog.changed_since(0) as PackedInt32Array).is_empty())
	fog.reveal_around(10.5, 20.5, 3, 2)
	var v1 := fog.version
	check("раскрытие поднимает версию", v1 > 0)
	var keys: PackedInt32Array = fog.changed_since(0)
	check("журнал непустой и содержит клетку у центра", not keys.is_empty() and keys.has(20 * FogOfWar.WIDTH + 10))
	fog.reveal_around(10.5, 20.5, 3, 2)
	check("повтор того же раскрытия версию не меняет (нечего перерисовывать)", fog.version == v1)
	fog.reveal_around(11.5, 20.5, 3, 2)
	var k2: Variant = fog.changed_since(v1)
	check("сдвиг на клетку: изменился узкий серп, а не весь круг", k2 is PackedInt32Array and (k2 as PackedInt32Array).size() < 20)
	var v2 := fog.version
	fog.reset_rect(9, 19, 3, 3)
	fog.reveal_around(10.5, 20.5, 3, 2)
	check("тот же reveal_around после сброса снова открывает клетки (мемо не залипает)",
		fog.get_state(10, 20) != FogOfWar.State.BLACK)
	v2 = fog.version
	fog.reset_rect(8, 18, 4, 4)
	var k3: Variant = fog.changed_since(v2)
	check("reset_rect даёт ровно клетки зоны", k3 is PackedInt32Array and (k3 as PackedInt32Array).size() == 16
		and (k3 as PackedInt32Array).has(18 * FogOfWar.WIDTH + 8) and (k3 as PackedInt32Array).has(21 * FogOfWar.WIDTH + 11))
	var v2b := fog.version
	fog.reset_rect(0, 1, 32, 100)
	check("огромный reset_rect — «менялось всё»", fog.changed_since(v2b) == null)
	var v3 := fog.version
	fog.reset_all()
	check("reset_all — «менялось всё» (null)", fog.changed_since(v3) == null)
	var v4 := fog.version
	fog.load_save_data({})
	check("load_save_data — «менялось всё»", fog.changed_since(v4) == null)
	var v5 := fog.version
	for i in range(FogOfWar.LOG + 3):
		fog.reveal_around(5.5 + float(i % 20), 30.5 + float(i), 1, 0)
	check("слишком старая версия — «менялось всё»", fog.changed_since(v5) == null)
	check("версия из будущего (другой туман) — «менялось всё»", fog.changed_since(fog.version + 5) == null)
	check("текущая версия — пустой журнал", (fog.changed_since(fog.version) as PackedInt32Array).is_empty())


# ---------------------------------------------------------------------------
# Мир
# ---------------------------------------------------------------------------

func _dig_any(w: WorldGen, x0: int, y0: int) -> Vector2i:
	for dy in range(0, 8):
		for dx in range(0, 8):
			if w.dig_cell(x0 + dx, y0 + dy):
				return Vector2i(x0 + dx, y0 + dy)
	return Vector2i(-1, -1)


func test_world_versions() -> void:
	print("-- Мир: версии --")
	var w := WorldGen.new(4242)
	w.get_tile(20, 30)   # первое обращение сбрасывает кэш клеток — это тоже «менялось всё», но один раз
	var v0 := w.version
	check("копка клетки поднимает версию", _dig_any(w, 20, 30).x >= 0 and w.version > v0)
	var ch: Variant = w.changes_since(v0)
	check("changes_since после копки — ключ выкопанной клетки", ch is PackedInt32Array and (ch as PackedInt32Array).size() == 1)
	check("неудачная копка (воздух) версию не меняет", true if _fail_dig_keeps_version(w) else false)
	var v1 := w.version
	w.apply_chunk_event(18, 40, 6, 6, 77)
	check("обвал — «менялось всё»", w.changes_since(v1) == null)
	var v2 := w.version
	w.apply_global_event(5)
	check("землетрясение — «менялось всё»", w.changes_since(v2) == null)
	var v3 := w.version
	w.era = "grandpa"
	check("смена эпохи — «менялось всё»", w.changes_since(v3) == null)
	var v3b := w.version
	w.era = "grandpa"
	check("то же значение эпохи версию не трогает", w.version == v3b)
	w.era = "now"
	var v4 := w.version
	w.load_save_data(w.get_save_data())
	check("загрузка сейва — «менялось всё»", w.changes_since(v4) == null)
	var v5 := w.version
	w.forget_dug_cells([Vector2i(20, 30)])
	check("forget_dug_cells — «менялось всё»", w.changes_since(v5) == null)
	var v6 := w.version
	w.overlay_y_min = 500
	check("хук overlay_y_min — «менялось всё»", w.changes_since(v6) == null)
	var v7 := w.version
	w.mark_changed()
	check("mark_changed — «менялось всё»", w.changes_since(v7) == null)
	var v8 := w.version
	for i in range(WorldGen.DIG_LOG + 5):
		_dig_any(w, 17 + (i % 12), 60 + i / 12)
	check("отстали на больше кольца копок — «менялось всё»", w.changes_since(v8) == null)
	var v9 := w.version
	_dig_any(w, 25, 200)
	_dig_any(w, 26, 210)
	var many: Variant = w.changes_since(v9)
	check("две копки подряд — два ключа по порядку", many is PackedInt32Array and (many as PackedInt32Array).size() == 2)
	var w2 := WorldGen.new(4242)
	check("версия чужого (более нового) мира — «менялось всё»", w2.changes_since(w.version) == null)
	var w3 := WorldGen.new(4242)
	w3.build_robert_tunnel()
	var v10 := w3.version
	w3.build_robert_tunnel()
	check("build_robert_tunnel помечает «всё»", v10 > 0)


func _fail_dig_keeps_version(w: WorldGen) -> bool:
	var v := w.version
	var ok := not w.dig_cell(20, 0)   # y < 1 — копать нечего
	return ok and w.version == v


# ---------------------------------------------------------------------------
# Кэш окна == полная перекраска
# ---------------------------------------------------------------------------

func _make_view(w: WorldGen, f: FogOfWar, p: Node, backdrop: bool) -> Node2D:
	var v: Node2D = WV.new()
	add_child(v)
	v.world = w
	v.fog = f
	v.player = p
	v.deep_backdrop_active = backdrop
	v.set_view_size(7, 14)
	v.validate_every = 0   # проверяем явную инвалидацию, без страховки
	return v


## Что видно в клетке на экране: (видна, текстура, цвет, масштаб, позиция).
func _look(v: Node2D, wx: int, wy: int) -> Array:
	var s: Sprite2D = v._pool[posmod(wy, v._pool_rows) * v._pool_cols + posmod(wx, v._pool_cols)]
	if not s.visible:
		return [false]
	# Белая текстура у каждого вида своя — для сравнения это один и тот же «цвет заливки».
	var tid: int = 1 if s.texture == v._white_tex else (s.texture.get_instance_id() if s.texture != null else 0)
	return [true, tid, s.modulate, s.scale, s.position]


func _same_window(a: Node2D, b: Node2D, cam: Vector2) -> int:
	var bx := int(floor(cam.x))
	var by := int(floor(cam.y))
	var diff := 0
	for wy in range(by - 1, by + a.view_h + 2):
		for wx in range(bx - 1, bx + a.view_w + 2):
			if _look(a, wx, wy) != _look(b, wx, wy):
				diff += 1
	return diff


## Сверяет инкрементальный вид с только что построенным (полная перекраска).
func _expect_equal(label: String, inc: Node2D, w: WorldGen, f: FogOfWar, p: Node, cam: Vector2) -> void:
	inc.render(cam)
	var fresh := _make_view(w, f, p, inc.deep_backdrop_active)
	fresh.lava_tick_override = inc.lava_tick_override
	fresh.render(cam)
	var d := _same_window(inc, fresh, cam)
	check("%s: окно совпадает с полной перекраской (%d расхождений)" % [label, d], d == 0)
	fresh.free()


func test_cache_equals_fresh_paint() -> void:
	print("-- WorldView: инкрементальный кэш == полная перекраска --")
	for backdrop in [true, false]:
		var w := WorldGen.new(4242)
		var f := FogOfWar.new()
		var p := FakePlayer.new()
		add_child(p)
		p.y = 52.5
		var v := _make_view(w, f, p, backdrop)
		var tag := "со стеной" if backdrop else "без стены"
		f.reveal_around(p.x, p.y, 7, 5)
		var cam := Vector2(12.0, 46.0)
		_expect_equal("[%s] первый кадр" % tag, v, w, f, p, cam)
		for step in [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1)]:
			cam += step
			_expect_equal("[%s] прокрутка на %s" % [tag, str(step)], v, w, f, p, cam)
		cam += Vector2(0.4, 0.4)
		_expect_equal("[%s] дробный сдвиг внутри клетки" % tag, v, w, f, p, cam)
		cam += Vector2(0, 5)
		_expect_equal("[%s] прыжок вниз на 5 строк" % tag, v, w, f, p, cam)
		cam += Vector2(-9, 0)
		_expect_equal("[%s] прыжок влево на 9 столбцов" % tag, v, w, f, p, cam)
		cam += Vector2(3, -40)
		_expect_equal("[%s] прыжок дальше окна" % tag, v, w, f, p, cam)
		cam = Vector2(12.0, 46.0)
		_expect_equal("[%s] возврат" % tag, v, w, f, p, cam)
		# копка внутри окна
		var cell := _dig_any(w, 14, 49)
		check("[%s] копнулась клетка в окне" % tag, cell.x >= 0)
		_expect_equal("[%s] после копки" % tag, v, w, f, p, cam)
		# раскрытие тумана
		f.reveal_around(18.5, 55.5, 4, 3)
		_expect_equal("[%s] после раскрытия тумана" % tag, v, w, f, p, cam)
		# обвал + сброс тумана зоны
		w.apply_chunk_event(14, 48, 8, 8, 31337)
		f.reset_rect(14, 48, 8, 8)
		_expect_equal("[%s] после обвала" % tag, v, w, f, p, cam)
		# землетрясение
		w.apply_global_event(99)
		f.reset_all()
		f.reveal_around(p.x, p.y, 6, 4)
		_expect_equal("[%s] после землетрясения" % tag, v, w, f, p, cam)
		# эпоха деда
		w.era = "grandpa"
		_expect_equal("[%s] эпоха деда" % tag, v, w, f, p, cam)
		w.era = "now"
		_expect_equal("[%s] эпоха деда кончилась" % tag, v, w, f, p, cam)
		# сейв/загрузка
		w.load_save_data(w.get_save_data())
		f.load_save_data(f.to_save_data())
		_expect_equal("[%s] после загрузки сейва" % tag, v, w, f, p, cam)
		# переключение стены
		v.deep_backdrop_active = not backdrop
		_expect_equal("[%s] стена переключена" % tag, v, w, f, p, cam)
		v.deep_backdrop_active = backdrop
		# поверхность и небо
		var cam_s := Vector2(10.0, -3.0)
		f.reveal_around(14.5, 3.5, 3, 2)
		_expect_equal("[%s] поверхность и небо" % tag, v, w, f, p, cam_s)
		cam_s += Vector2(2, 1)
		_expect_equal("[%s] прокрутка у поверхности" % tag, v, w, f, p, cam_s)
		# мир с другим экземпляром
		var w2 := WorldGen.new(777)
		v.world = w2
		_expect_equal("[%s] подменён мир" % tag, v, w2, f, p, cam_s)
		p.queue_free()
		v.queue_free()


func _find_lava(w: WorldGen) -> Vector2i:
	for y in range(3000, 3600):
		for x in range(WorldGen.WIDTH):
			if w.get_tile(x, y) == TileTypes.Type.LAVA:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_lava_animation() -> void:
	print("-- Лава: смена кадра только у лавы --")
	var w := WorldGen.new(4242)
	var lava := _find_lava(w)
	check("в тестовом мире нашлась лава на 3000–3600", lava.x >= 0)
	if lava.x < 0:
		return
	var f := FogOfWar.new()
	var p := FakePlayer.new()
	add_child(p)
	p.x = float(lava.x) + 0.5
	p.y = float(lava.y) + 0.5
	for dy in range(-12, 12):
		for dx in range(-8, 9):
			f.reveal_around_cell(clampi(lava.x + dx, 0, 31), lava.y + dy, 1, 1)
	var v := _make_view(w, f, p, true)
	v.lava_tick_override = 10
	var cam := Vector2(clampf(float(lava.x) - 3.0, 0.0, 25.0), float(lava.y) - 7.0)
	v.render(cam)
	var lava_slots := 0
	for i in range(v._slot_lava.size()):
		lava_slots += int(v._slot_lava[i])
	check("в окне есть анимированные клетки лавы (%d)" % lava_slots, lava_slots > 0)
	var painted: int = v.stat_cells_painted
	v.render(cam)
	check("тот же такт: ни одна клетка не перекрашена (кроме страховки — она выключена)", v.stat_cells_painted == painted)
	v.lava_tick_override = 11
	v.render(cam)
	check("новый такт: перекрашена только лава, без перерисовки остальных клеток", v.stat_cells_painted == painted)
	_expect_equal("лава: кадр 11", v, w, f, p, cam)
	for t in [12, 13, 14, 15]:
		v.lava_tick_override = t
		_expect_equal("лава: кадр %d" % t, v, w, f, p, cam)
	# текстура лавы == прежний texture_for на том же такте
	var same := true
	for tick in range(8):
		for k in range(40):
			var wx := k % 32
			var wy := 3000 + k * 7
			var a := TileArt.lava_texture(wx, wy, tick)
			var phase: int = ((wx * 73856093) ^ (wy * 19349663)) & 0xFF
			var b: Texture2D = TileArt._load("lava_%d" % (1 + (tick + phase) % TileArt.LAVA_FRAMES))
			if a != b:
				same = false
	check("lava_texture совпадает с прежней lava_file на тех же тактах", same)
	p.queue_free()
	v.queue_free()


func test_direct_diff_is_healed_by_validation() -> void:
	print("-- Страховка: правка мимо версии лечится перепроверкой строки --")
	var w := WorldGen.new(4242)
	var f := FogOfWar.new()
	var p := FakePlayer.new()
	add_child(p)
	f.reveal_around(p.x, p.y, 8, 6)
	var v := _make_view(w, f, p, true)
	v.validate_every = 1
	var cam := Vector2(12.0, 46.0)
	v.render(cam)
	var cell := Vector2i(-1, -1)
	for y in range(50, 56):
		for x in range(15, 24):
			if w.get_tile(x, y) != TileTypes.Type.EMPTY and TileTypes.is_diggable(w.get_tile(x, y)):
				cell = Vector2i(x, y)
	check("нашлась копаемая клетка", cell.x >= 0)
	var ver := w.version
	w.diffs[cell.y * WorldGen.WIDTH + cell.x] = true   # мимо dig_cell
	check("прямая запись версию не поднимает", w.version == ver)
	for i in range(v._pool_rows + 2):
		v.render(cam)
	var fresh := _make_view(w, f, p, true)
	fresh.render(cam)
	check("после полного круга перепроверки окно совпадает с эталоном", _same_window(v, fresh, cam) == 0)
	fresh.free()
	p.queue_free()
	v.queue_free()


func test_idle_frame_does_no_work() -> void:
	print("-- Неподвижный кадр не красит ничего --")
	var w := WorldGen.new(4242)
	var f := FogOfWar.new()
	var p := FakePlayer.new()
	add_child(p)
	f.reveal_around(p.x, p.y, 8, 6)
	var v := _make_view(w, f, p, true)
	var cam := Vector2(12.0, 46.0)
	v.render(cam)
	var first: int = v.stat_cells_painted
	check("первый кадр красит всё окно (%d клеток)" % first, first == v._pool_cols * v._pool_rows)
	for i in range(30):
		v.render(cam)
	check("30 неподвижных кадров: 0 клеток перекрашено", v.stat_cells_painted == first)
	v.render(cam + Vector2(0.5, 0.5))
	check("дробный сдвиг внутри клетки: 0 клеток", v.stat_cells_painted == first)
	v.render(cam + Vector2(1.0, 0.0))
	check("сдвиг на столбец: красится ровно один столбец (%d)" % (v.stat_cells_painted - first),
		v.stat_cells_painted - first == v._pool_rows)
	var n1: int = v.stat_cells_painted
	v.render(cam + Vector2(1.0, 1.0))
	check("сдвиг на строку: красится ровно одна строка", v.stat_cells_painted - n1 == v._pool_cols)
	var n2: int = v.stat_cells_painted
	v.render(cam + Vector2(2.0, 2.0))
	check("диагональный сдвиг: строка + столбец без двойной перекраски",
		v.stat_cells_painted - n2 == v._pool_cols + v._pool_rows - 1)
	var n3: int = v.stat_cells_painted
	_dig_any(w, 14, 49)
	v.render(cam + Vector2(2.0, 2.0))
	check("копка: перекрашена одна клетка", v.stat_cells_painted - n3 == 1)
	var n4: int = v.stat_cells_painted
	f.reveal_around(p.x + 1.0, p.y + 1.0, 8, 6)
	v.render(cam + Vector2(2.0, 2.0))
	check("шаг героя на клетку при больших радиусах: перекрашен серп (%d клеток), а не всё окно" % (v.stat_cells_painted - n4),
		v.stat_cells_painted - n4 < v._pool_cols * v._pool_rows / 3)
	p.queue_free()
	v.queue_free()


func test_overlay_redraw_gating() -> void:
	print("-- Overlay (кольца, декор, рамка копки) перерисовывается только при изменении --")
	var w := WorldGen.new(4242)
	var f := FogOfWar.new()
	var p := FakePlayer.new()
	add_child(p)
	f.reveal_around(p.x, p.y, 8, 6)
	var v := _make_view(w, f, p, true)
	var cam := Vector2(12.0, 46.0)
	v.render(cam)
	var base: int = v.stat_overlay_redraws
	for i in range(14):
		v.render(cam)
	check("14 неподвижных кадров: overlay не перерисован", v.stat_overlay_redraws == base)
	for i in range(3):
		v.render(cam)
	check("страховка: раз в ~15 кадров всё же перерисован", v.stat_overlay_redraws > base)
	var b2: int = v.stat_overlay_redraws
	p.x += 0.1
	v.render(cam)
	check("герой сдвинулся — перерисован", v.stat_overlay_redraws == b2 + 1)
	var b3: int = v.stat_overlay_redraws
	p.digging = {"x": 20, "y": 50, "t": 0.1, "total": 1.0}
	v.render(cam)
	v.render(cam)
	check("идёт копка — перерисовывается каждый кадр", v.stat_overlay_redraws == b3 + 2)
	p.digging = null
	v.render(cam)
	var b4: int = v.stat_overlay_redraws
	v.render(cam)
	check("копка кончилась: рамка стёрта, дальше тишина", v.stat_overlay_redraws == b4)
	var b5: int = v.stat_overlay_redraws
	v.render(cam + Vector2(1, 0))
	check("камера сменила клетку — перерисован", v.stat_overlay_redraws == b5 + 1)
	var b6: int = v.stat_overlay_redraws
	v.set_quest_cells([Vector2i(20, 50)])
	v.render(cam + Vector2(1, 0))
	v.render(cam + Vector2(1, 0))
	check("есть клетки задания — пульс требует кадра", v.stat_overlay_redraws >= b6 + 2)
	p.queue_free()
	v.queue_free()


func test_no_node_growth() -> void:
	print("-- Пул спрайтов не растёт и не течёт --")
	var w := WorldGen.new(4242)
	var f := FogOfWar.new()
	var p := FakePlayer.new()
	add_child(p)
	f.reveal_around(p.x, p.y, 8, 6)
	var v := _make_view(w, f, p, true)
	var cam := Vector2(12.0, 46.0)
	v.render(cam)
	var kids := v.get_child_count()
	var nodes := get_tree().get_node_count()
	for i in range(400):
		cam += Vector2(0.37 * sin(float(i)), 0.61)
		v.render(cam)
		if i % 50 == 0:
			w.apply_chunk_event(14, int(cam.y) + 3, 6, 5, i)
			f.reveal_around(cam.x + 3.0, cam.y + 7.0, 4, 3)
	check("400 кадров прокрутки со сбросами: число детей WorldView прежнее", v.get_child_count() == kids)
	check("и узлов в дереве — тоже", get_tree().get_node_count() == nodes)
	v.set_view_size(26, 15)
	check("широкое окно: пул 29 x 18", v._pool.size() == 29 * 18)
	v.render(cam)
	v.set_view_size(7, 14)
	await get_tree().process_frame
	check("возврат к узкому: пул пересобран без остатков (не больше 10x17 + overlay)", v.get_child_count() == 10 * 17 + 1)
	p.queue_free()
	v.queue_free()

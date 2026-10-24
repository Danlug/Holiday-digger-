extends Node
## test_walls — подземные стены-фоны (ветка «walls», tools/walls_deep.py, scripts/world/deep_backdrop.gd):
## у каждого пояса есть квадратная стена одного размера, она тёмная и низкоконтрастная, шов по краям не
## заметнее обычной разности соседних пикселей; DeepBackdrop считает тени кромок вокруг выкопанной клетки.
## Зрение (контактный лист, мощение, кадры мира) — tests/test_screenshot_walls и tools/walls_check.py.
##
## Запуск: godot --headless --path . res://tests/test_walls.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_walls ===")
	_check_textures()
	await _check_edge_shade()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _luma(c: Color) -> float:
	return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) * 255.0


func _check_textures() -> void:
	var size0 := -1
	for i in range(Biomes.count()):
		var wall := String(Biomes.get_biome(i).get("wall", ""))
		var path := "res://art/env/deep/wall_%s.png" % wall
		check("стена пояса %d (%s) есть" % [i, wall], ResourceLoader.exists(path))
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		var img := tex.get_image()
		var w := img.get_width()
		if size0 < 0:
			size0 = w
		check("%s: квадрат, сторона кратна 8, как у остальных" % wall, w == img.get_height() and w % 8 == 0 and w == size0)
		var sum := 0.0
		var sum2 := 0.0
		for y in range(0, w, 2):
			for x in range(0, w, 2):
				var l := _luma(img.get_pixel(x, y))
				sum += l
				sum2 += l * l
		var n := float((w / 2) * (w / 2))
		var mean := sum / n
		var sd := sqrt(maxf(sum2 / n - mean * mean, 0.0))
		check("%s: тёмная (средняя яркость %.0f <= 66)" % [wall, mean], mean <= 66.0)
		check("%s: низкоконтрастная (σ %.0f <= 34)" % [wall, sd], sd <= 34.0)
		# шов: разность через край не больше 98-го перцентиля разностей внутри (как tools/walls_check.py)
		var inner_x := PackedFloat32Array()
		for x in range(w - 1):
			var acc := 0.0
			for y in range(w):
				acc += absf(_luma(img.get_pixel(x, y)) - _luma(img.get_pixel(x + 1, y)))
			inner_x.append(acc / w)
		var seam := 0.0
		for y in range(w):
			seam += absf(_luma(img.get_pixel(0, y)) - _luma(img.get_pixel(w - 1, y)))
		seam /= w
		inner_x.sort()
		var p98 := inner_x[int(inner_x.size() * 0.98)]
		check("%s: шов по X бесшовный (%.2f <= %.2f)" % [wall, seam, p98 * 1.15], seam <= p98 * 1.15 + 0.01)


func _check_edge_shade() -> void:
	GameState.world_seed = 777
	var world := WorldGen.new(777)
	var holder := Node2D.new()
	add_child(holder)
	var wv = preload("res://scripts/world/world_view.gd").new()
	wv.name = "WorldView"
	wv.world = world
	holder.add_child(wv)
	var db := DeepBackdrop.new()
	holder.add_child(db)
	var x := 20
	var y := 800
	world.dig_cell(x, y)
	db.update(Vector2(x - 3, y - 6), 7, 14)
	await get_tree().process_frame
	await get_tree().process_frame
	var idx := -1
	for n in range(db._shade_rects.size()):
		if db._shade_rects[n] == Vector2(x, y):
			idx = n
	check("выкопанная клетка получила тени кромок", idx >= 0)
	if idx >= 0:
		var m: int = db._shade_masks[idx]
		var up := world.get_tile(x, y - 1) != TileTypes.Type.EMPTY
		var lf := world.get_tile(x - 1, y) != TileTypes.Type.EMPTY
		var rt := world.get_tile(x + 1, y) != TileTypes.Type.EMPTY
		var dn := world.get_tile(x, y + 1) != TileTypes.Type.EMPTY
		check("тень сверху — если над клеткой порода", (m & 1 != 0) == up)
		check("тень слева — если слева порода", (m & 2 != 0) == lf)
		check("тень справа — если справа порода", (m & 4 != 0) == rt)
		check("тень снизу — если под клеткой порода", (m & 8 != 0) == dn)
	check("тени есть только у пустых клеток (у каждой записи есть бит)", db._shade_masks.size() == db._shade_rects.size() and not (0 in db._shade_masks))
	var far := Vector2(x + 40, y + 40)
	check("далёкая порода без пустот теней не даёт", not db._shade_rects.has(far))
	holder.queue_free()

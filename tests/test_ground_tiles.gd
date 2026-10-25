extends SceneTree
## test_ground_tiles.gd — земля и камень пояса 0 (tools/ground_tiles.py): размер, сетка 32x3, одна светлота
## вариантов, бесшовность при случайных соседях (числовой тест шва), камень отличим от земли.
##
## Запуск: godot --headless --script res://tests/test_ground_tiles.gd

var failures := 0
var total := 0

const G := 32
const S := 3


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _init() -> void:
	print("=== test_ground_tiles ===")
	var imgs: Array[Image] = []
	for i in range(1, 9):
		imgs.append(_img("dirt_%d" % i))
	var stone := _img("stone")

	var sized := stone.get_width() == 96 and stone.get_height() == 96
	for im in imgs:
		sized = sized and im.get_width() == 96 and im.get_height() == 96
	check("8 вариантов земли и камень — тайлы 96x96", sized)

	var grid := _on_grid(stone)
	for im in imgs:
		grid = grid and _on_grid(im)
	check("рисунок на сетке 32 (каждый блок 3x3 одного цвета): ближайший сосед читает честные пиксели", grid)

	var lum: Array = []   # [вариант] -> PackedFloat32Array 32x32 (яркость 0..255)
	for im in imgs:
		lum.append(_luma(im))
	var means: Array = []
	for l in lum:
		means.append(_mean(l))
	var lo := 1000.0
	var hi := 0.0
	for m in means:
		lo = minf(lo, m)
		hi = maxf(hi, m)
	check("варианты земли одной светлоты (разброс средней яркости %.2f <= 2 из 255)" % (hi - lo), hi - lo <= 2.0)

	var stds_ok := true
	for l in lum:
		var s := _std(l)
		stds_ok = stds_ok and s >= 8.0 and s <= 24.0
	check("у земли есть фактура, но это не шум (разброс яркости пикселей 8..24 из 255)", stds_ok)

	var distinct := true
	for a in range(8):
		for b in range(a + 1, 8):
			var same := 0
			for k in range(G * G):
				if absf(lum[a][k] - lum[b][k]) < 0.5:
					same += 1
			if same > G * G * 0.30:
				distinct = false
	check("варианты не копии друг друга (совпадающих пикселей < 30%)", distinct)

	# шов: |разность| через стык двух соседних вариантов против стыка двух ПРОИЗВОЛЬНЫХ рядов разных тайлов
	var base := 0.0
	var nb := 0
	for a in range(8):
		for b in range(8):
			for ra in range(0, G, 4):
				for rb in range(2, G, 4):
					base += _row_diff(lum[a], ra, lum[b], rb)
					nb += 1
	base /= nb
	var seam_v := 0.0
	var seam_h := 0.0
	for a in range(8):
		for b in range(8):
			seam_v += _row_diff(lum[a], G - 1, lum[b], 0)
			seam_h += _col_diff(lum[a], G - 1, lum[b], 0)
	seam_v /= 64.0
	seam_h /= 64.0
	check("шов вверх/вниз не заметнее обычного стыка рядов (%.2f / %.2f)" % [seam_v / base, seam_h / base],
			seam_v <= base * 1.25 and seam_h <= base * 1.25)

	# рамки нет: средняя яркость крайних рядов/столбцов = средней по тайлу, и у всех вариантов одна
	var edge_lo := 1000.0
	var edge_hi := 0.0
	var frame_ok := true
	for v in range(8):
		var l: PackedFloat32Array = lum[v]
		var edges := [_row_mean(l, 0), _row_mean(l, G - 1), _col_mean(l, 0), _col_mean(l, G - 1)]
		for e in edges:
			edge_lo = minf(edge_lo, e)
			edge_hi = maxf(edge_hi, e)
			if absf(e - means[v]) > 4.0:
				frame_ok = false
	check("нет «рамки клетки»: крайние ряды той же яркости, что тайл (ряды %.1f..%.1f)" % [edge_lo, edge_hi], frame_ok)
	check("крайние ряды всех вариантов одной яркости (разброс %.2f <= 3)" % (edge_hi - edge_lo), edge_hi - edge_lo <= 3.0)

	var sl := _luma(stone)
	var sm := _mean(sl)
	var dm := 0.0
	for m in means:
		dm += m / 8.0
	check("камень светлее земли (%.0f против %.0f)" % [sm, dm], sm - dm >= 12.0)
	check("камень серый, земля тёплая (насыщенность %.2f против %.2f)" % [_sat(stone), _sat(imgs[0])],
			_sat(stone) < 0.5 * _sat(imgs[0]))
	check("у камня резкий рельеф: швы и грани (разброс яркости %.1f >= 12)" % _std(sl), _std(sl) >= 12.0)
	var wrap_h := 0.0
	var inner_h := 0.0
	for y in range(G):
		wrap_h += absf(sl[y * G + G - 1] - sl[y * G])
		for x in range(G - 1):
			inner_h += absf(sl[y * G + x] - sl[y * G + x + 1])
	wrap_h /= G
	inner_h /= float(G * (G - 1))
	check("камень стыкуется сам с собой (разрыв у края %.1f <= 1.5 x внутри %.1f)" % [wrap_h, inner_h], wrap_h <= 1.5 * inner_h)

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	quit(0 if failures == 0 else 1)


func _img(name: String) -> Image:
	var tex: Texture2D = load("res://art/tiles/%s.png" % name)
	var im := tex.get_image()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGB8)
	return im


func _on_grid(im: Image) -> bool:
	for gy in range(G):
		for gx in range(G):
			var c := im.get_pixel(gx * S, gy * S)
			for dy in range(S):
				for dx in range(S):
					if im.get_pixel(gx * S + dx, gy * S + dy) != c:
						return false
	return true


func _luma(im: Image) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(G * G)
	for gy in range(G):
		for gx in range(G):
			var c := im.get_pixel(gx * S + 1, gy * S + 1)
			out[gy * G + gx] = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * 255.0
	return out


func _sat(im: Image) -> float:
	var s := 0.0
	for gy in range(G):
		for gx in range(G):
			var c := im.get_pixel(gx * S + 1, gy * S + 1)
			s += maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
	return s / float(G * G)


func _mean(l: PackedFloat32Array) -> float:
	var s := 0.0
	for v in l:
		s += v
	return s / l.size()


func _std(l: PackedFloat32Array) -> float:
	var m := _mean(l)
	var s := 0.0
	for v in l:
		s += (v - m) * (v - m)
	return sqrt(s / l.size())


func _row_mean(l: PackedFloat32Array, y: int) -> float:
	var s := 0.0
	for x in range(G):
		s += l[y * G + x]
	return s / G


func _col_mean(l: PackedFloat32Array, x: int) -> float:
	var s := 0.0
	for y in range(G):
		s += l[y * G + x]
	return s / G


func _row_diff(a: PackedFloat32Array, ya: int, b: PackedFloat32Array, yb: int) -> float:
	var s := 0.0
	for x in range(G):
		s += absf(a[ya * G + x] - b[yb * G + x])
	return s / G


func _col_diff(a: PackedFloat32Array, xa: int, b: PackedFloat32Array, xb: int) -> float:
	var s := 0.0
	for y in range(G):
		s += absf(a[y * G + xa] - b[y * G + xb])
	return s / G

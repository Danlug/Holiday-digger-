extends SceneTree
## Замер скорости генератора: микросекунд на get_tile на разных глубинах и время
## полного прохода по миру. Нужен, чтобы новые слои (каверны, жилы, руины) не
## ухудшали кадр: окно экрана — это ~300 вызовов за кадр.
##   godot --headless --path . --script res://tools/bench_world.gd

const DEPTHS := [10, 300, 1200, 3000, 4000, 6000, 9000]
const CELLS := 40000


func _init() -> void:
	var w := WorldGen.new(20260915)
	print("get_tile: микросекунд на вызов (холодный мир, без раскопок)")
	for d in DEPTHS:
		var t0 := Time.get_ticks_usec()
		var acc := 0
		for i in range(CELLS):
			acc += w.get_tile(i % WorldGen.WIDTH, d + (i / WorldGen.WIDTH) % 200)
		var dt := Time.get_ticks_usec() - t0
		print("  y~%5d: %.2f мкс/клетка  (контрольная сумма %d)" % [d, float(dt) / CELLS, acc])
	var t1 := Time.get_ticks_usec()
	var n := 0
	for y in range(1, 10001):
		for x in range(WorldGen.WIDTH):
			n += w.get_tile(x, y)
	var total := Time.get_ticks_usec() - t1
	print("полный проход 32x10000: %.0f мс (%.2f мкс/клетка)" % [total / 1000.0, float(total) / 320000.0])
	quit(0)

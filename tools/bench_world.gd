extends SceneTree
## Замер скорости генератора: микросекунд на get_tile на разных глубинах —
## холодный (клетка считается впервые) и тёплый (из кэша, как каждый кадр на
## экране) — и время полного прохода по миру. Окно экрана — это ~170 вызовов за кадр.
##   godot --headless --path . --script res://tools/bench_world.gd

const DEPTHS := [10, 300, 1200, 3000, 4000, 6000, 9000]
const ROWS := 120


func _init() -> void:
	print("get_tile: микросекунд на вызов, холодный / тёплый (кэш)")
	for d in DEPTHS:
		var w := WorldGen.new(20260915)
		var t0 := Time.get_ticks_usec()
		var acc := 0
		for y in range(d, d + ROWS):
			for x in range(WorldGen.WIDTH):
				acc += w.get_tile(x, y)
		var cold := Time.get_ticks_usec() - t0
		var t1 := Time.get_ticks_usec()
		for rep in range(10):
			for y in range(d, d + ROWS):
				for x in range(WorldGen.WIDTH):
					acc += w.get_tile(x, y)
		var warm := Time.get_ticks_usec() - t1
		var n := float(ROWS * WorldGen.WIDTH)
		print("  y~%5d: %6.2f / %5.2f мкс  (сумма %d)" % [d, float(cold) / n, float(warm) / (n * 10.0), acc])
	var w2 := WorldGen.new(20260915)
	var t2 := Time.get_ticks_usec()
	var s := 0
	for y in range(1, 10001):
		for x in range(WorldGen.WIDTH):
			s += w2.get_tile(x, y)
	var total := Time.get_ticks_usec() - t2
	print("полный холодный проход 32x10000: %.0f мс (%.2f мкс/клетка)" % [total / 1000.0, float(total) / 320000.0])
	quit(0)

extends Node
## Замер стоимости кадра мира в настоящей сцене (CPU, без GPU): WorldView.render,
## DeepBackdrop.update, AmbientFx.update на разных глубинах. render — три случая: неподвижный кадр
## (кэш окна), шаг камеры на клетку и полная перекраска окна с тёплым кэшем клеток мира и с холодным
## (кэш get_tile обнулён: каждая клетка считается заново, как первый показ места). Запуск:
##   XDG_DATA_HOME=$PWD/.godot/xdg godot --headless --path . res://tools/bench_render.tscn

const DEPTHS := [10, 1200, 3000, 4300, 6000, 9000]


func _ready() -> void:
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	print("мкс на кадр: render неподвижный | шаг камеры на клетку | перекраска окна тёплая | холодная || стена | ambient")
	for d in DEPTHS:
		var p = main.player
		p.x = 20.5
		p.y = float(d) + 0.5
		p.vx = 0.0
		p.vy = 0.0
		main.fog.reveal_around(p.x, p.y, 9, 7)
		for i in range(4):
			await get_tree().process_frame
		var cam: Vector2 = main._camera()
		var vw: int = main._view_w()
		var vh: int = main._view_h()
		main.world_view.render(cam)
		var n := 60
		var t_render := 0
		var t_wall := 0
		var t_amb := 0
		for i in range(n):
			var t0 := Time.get_ticks_usec()
			main.world_view.render(cam)
			var t1 := Time.get_ticks_usec()
			main.deep_backdrop.update(cam, vw, vh)
			var t2 := Time.get_ticks_usec()
			main.ambient_fx.update(cam, vw, vh, 0.016)
			var t3 := Time.get_ticks_usec()
			t_render += t1 - t0
			t_wall += t2 - t1
			t_amb += t3 - t2
		var t_scroll := 0
		for i in range(n):
			var t4 := Time.get_ticks_usec()
			main.world_view.render(cam + Vector2(float(i % 2), 0.0))
			t_scroll += Time.get_ticks_usec() - t4
		main.world_view.render(cam)
		var t_warm := 0
		for i in range(10):
			main.world_view._win_ok = false
			var t5 := Time.get_ticks_usec()
			main.world_view.render(cam)
			t_warm += Time.get_ticks_usec() - t5
		var saved: PackedByteArray = main.world._cells
		main.world._cells = PackedByteArray()
		main.world._cells.resize(saved.size())
		main.world._cells.fill(255)
		main.world_view._win_ok = false
		var t6 := Time.get_ticks_usec()
		main.world_view.render(cam)
		var t_cold := Time.get_ticks_usec() - t6
		main.world._cells = saved
		print("  y=%5d: %5d | %5d | %6d | %6d || %4d | %4d" % [d, t_render / n, t_scroll / n, t_warm / 10, t_cold, t_wall / n, t_amb / n])
	get_tree().quit(0)

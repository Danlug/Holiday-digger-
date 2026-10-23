extends Node
## Замер стоимости кадра мира в настоящей сцене (CPU, без GPU): WorldView.render,
## DeepBackdrop.update, AmbientFx.update на разных глубинах — с кэшем клеток и без
## него (кэш выключается обнулением массива, get_tile тогда считает каждую клетку заново,
## как было до кэша). Запуск:
##   XDG_DATA_HOME=$PWD/.godot/xdg godot --headless --path . res://tools/bench_render.tscn

const DEPTHS := [10, 1200, 3000, 4300, 6000, 9000]


func _ready() -> void:
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	print("мкс на кадр: render мира | стена | ambient (кэш)  /  render без кэша")
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
		var saved: PackedByteArray = main.world._cells
		main.world._cells = PackedByteArray()
		var t_nocache := 0
		for i in range(10):
			var t4 := Time.get_ticks_usec()
			main.world_view.render(cam)
			t_nocache += Time.get_ticks_usec() - t4
		main.world._cells = saved
		print("  y=%5d: %5d | %4d | %4d   /  %6d" % [d, t_render / n, t_wall / n, t_amb / n, t_nocache / 10])
	get_tree().quit(0)

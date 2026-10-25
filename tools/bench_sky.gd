extends Node
## bench_sky — замер CPU-стоимости неба за кадр без окна (рендер здесь пустышка, цифры — нижняя граница):
## set_camera при движении камеры и _process днём и ночью (сам рисунок светил в headless не вызывается). Сравнивать «до/после» правок, а не с 16 мс.
##
##   godot --headless --path . res://tools/bench_sky.tscn

const N := 4000


func _ready() -> void:
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	GameState.world_seed = 20260921
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var sky: SkyView = main.sky_view
	for h in [12.0, 23.0]:
		DayCycle.set_hour(h)
		sky._update_state()
		var t0 := Time.get_ticks_usec()
		for i in range(N):
			sky.set_camera(Vector2(10.0 + float(i) * 0.01, -6.5), 7)
		var t1 := Time.get_ticks_usec()
		for i in range(N):
			sky._process(0.016)
		var t2 := Time.get_ticks_usec()
		print("час %.0f: set_camera при движении камеры %.2f мкс, _process %.2f мкс" % [
			h, float(t1 - t0) / N, float(t2 - t1) / N])
	get_tree().quit(0)

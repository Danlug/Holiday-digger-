extends Node
## Профиль запуска: куда уходит время между созданием главной сцены и первым кадром. Код сцены не
## трогаем: слушаем child_entered_tree у корня сцены и у ViewRoot и смотрим паузы между соседними
## событиями — пауза после узла = его _ready и работа родителя до следующего add_child.
##
##   godot --headless --path . res://tools/perf_boot.tscn
##
## Цифры — стена в headless; в вебе (WASM) всё в 3-5 раз дольше, поэтому именно запуск там самый
## заметный. Печатает самые дорогие паузы и общее время до первого кадра.

var _events: Array = []   # [t_usec, путь]
var _t0 := 0


func _ready() -> void:
	for id in ["intro_grandpa", "intro_boy"]:
		StoryState.mark_seen(id)
	StoryState.set_flag("intro_seen")
	GameState.world_seed = 20260101
	var t_load0 := Time.get_ticks_usec()
	var scene: PackedScene = load("res://scenes/main.tscn")
	var load_ms := float(Time.get_ticks_usec() - t_load0) / 1000.0
	var main: Node2D = scene.instantiate()
	main.child_entered_tree.connect(func(n: Node):
		_events.append([Time.get_ticks_usec(), "main/" + str(n.name)])
		if n.name == "ViewRoot":
			n.child_entered_tree.connect(func(c: Node): _events.append([Time.get_ticks_usec(), "ViewRoot/" + str(c.name)])))
	_t0 = Time.get_ticks_usec()
	add_child(main)
	var t_ready := Time.get_ticks_usec()
	_events.append([t_ready, "(конец main._ready)"])
	await get_tree().process_frame
	var t_frame := Time.get_ticks_usec()
	var rows: Array = []
	for i in range(_events.size() - 1):
		rows.append([float(int(_events[i + 1][0]) - int(_events[i][0])) / 1000.0, String(_events[i][1])])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("=== perf_boot: load(main.tscn) %.0f мс (разбор сцены и всех preload-скриптов и ресурсов), instantiate + _ready %.0f мс, первый кадр ещё +%.0f мс ===" % [
		load_ms, float(t_ready - _t0) / 1000.0, float(t_frame - t_ready) / 1000.0])
	print("Паузы после появления узла (его _ready + работа родителя), самые дорогие:")
	for i in range(mini(14, rows.size())):
		print("  %7.1f мс  %s" % [rows[i][0], rows[i][1]])
	get_tree().quit(0)

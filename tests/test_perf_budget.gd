extends Node
## Бюджет времени кадра мира (ветка «perf»): мягкие пороги на стоимость WorldView.render и
## main._process на исследованной шахте. Headless-время нестабильно, поэтому пороги — с запасом
## в 3-10 раз над измеренным, но ниже прежних значений (до кэша окна render стоил 0,9-2,9 мс на
## КАЖДЫЙ кадр, на телефоне и в вебе в 3-5 раз больше): возврат к перекраске всего окна каждый кадр
## тест поймает. Точные цифры и их сравнение «до/после» — в ГДД §19 и tools/perf_report, perf_profile.

const WV := preload("res://scripts/world/world_view.gd")

# Пороги в микросекундах на вызов (среднее по серии). Измерено на настольном CPU: в скобках.
const STATIC_RENDER_US := 600.0      # неподвижный кадр (~50-90); прежний код: 850-2900
const SCROLL_RENDER_US := 1800.0     # камера меняет клетку каждый кадр (~300-500)
const WALK_FRAME_US := 2500.0        # шаг героя 0,1 клетки за кадр: туман + render (~300-600)
const REPAINT_US := 14000.0          # полная перекраска окна (~2000-3000, холодный кэш ~12000)
const MAIN_FRAME_US := 2000.0        # main._process целиком на исследованной шахте (~400-900)

var checks := 0
var failures := 0


class FakePlayer extends Node:
	var x: float = 20.5
	var y: float = 52.5
	var digging = null
	var rig_transition: String = ""


func _ready() -> void:
	print("=== test_perf_budget: старт ===")
	test_world_view_budget()
	await test_main_frame_budget()
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


func test_world_view_budget() -> void:
	print("-- WorldView.render на исследованной шахте --")
	var w := WorldGen.new(4242)
	var f := FogOfWar.new()
	var p := FakePlayer.new()
	add_child(p)
	for y in range(40, 80):
		for x in range(WorldGen.WIDTH):
			f.reveal_around_cell(x, y, 1, 0)
	f.reveal_around(p.x, p.y, 9, 7)
	var v: Node2D = WV.new()
	add_child(v)
	v.world = w
	v.fog = f
	v.player = p
	v.deep_backdrop_active = true
	v.set_view_size(15, 14)
	var cam := Vector2(12.0, 46.0)
	v.render(cam)

	var static_us := _bench(300, func(_i): v.render(cam))
	print("   неподвижный кадр: %.0f мкс" % static_us)
	check("неподвижный кадр %.0f мкс <= %.0f" % [static_us, STATIC_RENDER_US], static_us <= STATIC_RENDER_US)

	# камера уходит на строку за вызов (раз в 8 вызовов возвращается): в среднем ~2 новые строки за кадр
	var scroll_us := _bench(300, func(i): v.render(cam + Vector2(float(i % 3), float(i % 8))))
	print("   камера меняет клетку каждый кадр: %.0f мкс" % scroll_us)
	check("смена клетки камеры каждый кадр %.0f мкс <= %.0f" % [scroll_us, SCROLL_RENDER_US], scroll_us <= SCROLL_RENDER_US)

	var walk_us := _bench(300, func(i):
		p.y = 52.5 + float(i) * 0.1
		p.x = 20.5 + sin(float(i) * 0.05) * 3.0
		f.reveal_around(p.x, p.y, 9, 7)
		v.render(Vector2(clampf(p.x - 7.5, 0.0, 17.0), p.y - 7.0)))
	print("   ходьба 0,1 клетки за кадр (туман + render): %.0f мкс" % walk_us)
	check("ходьба: кадр %.0f мкс <= %.0f" % [walk_us, WALK_FRAME_US], walk_us <= WALK_FRAME_US)

	var repaint_us := _bench(20, func(_i):
		v._win_ok = false
		v.render(cam))
	print("   полная перекраска окна: %.0f мкс" % repaint_us)
	check("полная перекраска %.0f мкс <= %.0f" % [repaint_us, REPAINT_US], repaint_us <= REPAINT_US)

	var w2 := WorldGen.new(4242)
	var cold_us := 0.0
	v.world = w2
	var t0 := Time.get_ticks_usec()
	v.render(cam)
	cold_us = float(Time.get_ticks_usec() - t0)
	print("   перекраска на холодном кэше мира: %.0f мкс" % cold_us)
	check("холодная перекраска %.0f мкс <= %.0f" % [cold_us, REPAINT_US * 3.0], cold_us <= REPAINT_US * 3.0)
	p.queue_free()
	v.queue_free()


func test_main_frame_budget() -> void:
	print("-- main._process целиком на исследованной шахте --")
	GameState.world_seed = 20260101
	for id in ["intro_grandpa", "intro_boy"]:
		StoryState.mark_seen(id)
	StoryState.set_flag("intro_seen")
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _i in range(3):
		await get_tree().process_frame
	main.set_process(false)
	var p = main.player
	for depth in [100, 3100]:
		p.x = 20.5
		p.y = float(depth) + 0.5
		p.vx = 0.0
		p.vy = 0.0
		for y in range(depth - 3, depth + 18):
			for x in range(WorldGen.WIDTH):
				main.fog.reveal_around_cell(x, y, 1, 0)
		main.fog.reveal_around(p.x, p.y, 9, 7)
		for _i in range(30):
			main._process(0.016)
		var us := _bench(200, func(_i): main._process(0.016))
		print("   глубина %d: main._process %.0f мкс" % [depth, us])
		check("глубина %d: main._process %.0f мкс <= %.0f" % [depth, us, MAIN_FRAME_US], us <= MAIN_FRAME_US)
	main.queue_free()

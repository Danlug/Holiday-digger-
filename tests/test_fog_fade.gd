extends Node
## Плавное раскрытие тумана (FogFade, ветка fog-projects; владелец, разбор чисел 26.10: «плавность
## раскрытия, минимальная, но приятная для глаз»). Проверяем: число в data/feel.json, кривую (0 → 1 за
## заданное время, монотонно, ease-out), что проявляются ровно открывшиеся клетки и из своего прежнего
## вида, что уже открытое не мигает повторно, и что загрузка, сброс, телепорт и эпоха деда не
## запускают анимацию. Часы проявления ведёт тест (manual_clock) — от скорости машины не зависит.

const WV := preload("res://scripts/world/world_view.gd")
const DT := 1.0 / 60.0

var checks := 0
var failures := 0


class FakePlayer extends Node:
	var x: float = 12.5
	var y: float = 50.5
	var digging = null
	var rig_transition: String = ""


func _ready() -> void:
	print("=== test_fog_fade: старт ===")
	test_config()
	test_curve()
	for backdrop in [true, false]:
		test_reveal_in_view(backdrop)
	test_no_fade_on_bulk_changes()
	test_stacked_change()
	test_zero_duration()
	print("=== Итог: %d проверок, %d провалов ===" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("  OK    ", label)
	else:
		failures += 1
		print("  FAIL  ", label)


func _make_view(w: WorldGen, f: FogOfWar, p: Node, backdrop: bool) -> Node2D:
	var v: Node2D = WV.new()
	add_child(v)
	v.world = w
	v.fog = f
	v.player = p
	v.deep_backdrop_active = backdrop
	v.set_view_size(7, 14)
	v.validate_every = 0
	v.stale_budget_us = 1000000000
	v.fog_fade.manual_clock = true
	return v


func _cam_for(p: Node) -> Vector2:
	return Vector2(p.x - 3.5, p.y - 7.0)


func _new_entries(fade: FogFade) -> Array:
	var out: Array = []
	for i in range(fade._x.size()):
		if fade._t[i] == 0.0:
			out.append(Vector2i(fade._x[i], fade._y[i]))
	return out


# ---------------------------------------------------------------------------

func test_config() -> void:
	print("-- число в data/feel.json --")
	var n: Variant = Feel.node("fog.reveal_fade_s")
	check("feel.json → fog.reveal_fade_s есть и обёрнуто {value, proposed, note}", typeof(n) == TYPE_DICTIONARY and n.has("value") and n.has("note"))
	if typeof(n) != TYPE_DICTIONARY:
		return
	check("решение владельца: proposed = false", n.get("proposed", true) == false)
	check("в заметке — слова владельца", String(n.get("note", "")).contains("владелец"))
	var d := Feel.num("fog.reveal_fade_s", -1.0)
	check("длительность в пределах 0.15–0.3 с (сейчас %.2f)" % d, d >= 0.15 and d <= 0.3)
	var fade := FogFade.new()
	check("FogFade берёт длительность из feel.json", is_equal_approx(fade.duration, d))
	fade.free()


func test_curve() -> void:
	print("-- кривая проявления --")
	var fade := FogFade.new()
	fade.duration = 0.2
	check("t = 0: клетка ещё не проявилась (0)", fade.reveal_at(0.0) == 0.0)
	check("t = длительность: проявилась целиком (1)", is_equal_approx(fade.reveal_at(0.2), 1.0))
	check("после длительности — 1, не больше", fade.reveal_at(0.5) == 1.0)
	var mono := true
	var prev := -1.0
	for i in range(0, 101):
		var r := fade.reveal_at(0.2 * float(i) / 100.0)
		if r < prev or r < 0.0 or r > 1.0:
			mono = false
		prev = r
	check("монотонно растёт от 0 до 1", mono)
	check("ease-out: к середине времени проявилось больше половины", fade.reveal_at(0.1) > 0.75)
	check("без резкого конца: к 80% времени ещё не целиком", fade.reveal_at(0.16) < 0.995)
	fade.free()


func test_reveal_in_view(backdrop: bool) -> void:
	var tag := "со стеной" if backdrop else "без стены"
	print("-- проявление в окне [%s] --" % tag)
	var w := WorldGen.new(4242)
	var f := FogOfWar.new()
	var p := FakePlayer.new()
	add_child(p)
	for x in range(8, 24):
		w.dig_cell(x, 50)
	var v := _make_view(w, f, p, backdrop)
	var fade: FogFade = v.fog_fade
	check("[%s] FogFade — ребёнок overlay, рисуется позади него (над тайлами, под кольцами)" % tag,
		fade.get_parent() == v._overlay and fade.show_behind_parent)
	f.reveal_around(p.x, p.y, 2, 1)
	v.render(_cam_for(p))
	check("[%s] первый кадр рисуется сразу, без проявления" % tag, fade.active_count() == 0)
	v.render(_cam_for(p))
	check("[%s] кадр без изменений — проявлять нечего" % tag, fade.active_count() == 0)

	# Шаг на клетку вправо: камеру держим на месте, чтобы клетки остались в окне.
	var cam := _cam_for(p)
	var before := {}
	for y in range(46, 56):
		for x in range(8, 20):
			before[Vector2i(x, y)] = [f.get_state(x, y), _slot_color(v, x, y)]
	p.x += 1.0
	f.reveal_around(p.x, p.y, 2, 1)
	v.render(cam)
	var started := _new_entries(fade)
	check("[%s] шаг открыл клетки — они проявляются (%d)" % [tag, started.size()], started.size() > 0)
	var only_opened := true
	var from_prev := true
	for c: Vector2i in started:
		var was: Array = before.get(c, [-1, null])
		if int(was[0]) < 0 or f.get_state(c.x, c.y) <= int(was[0]):
			only_opened = false
		var idx := -1
		for i in range(fade._x.size()):
			if fade._x[i] == c.x and fade._y[i] == c.y:
				idx = i
		if idx < 0 or was[1] == null or fade._c[idx] != was[1]:
			from_prev = false
	check("[%s] проявляются только клетки, которые туман открыл сейчас" % tag, only_opened)
	check("[%s] проявление начинается с прежнего вида клетки (без скачка)" % tag, from_prev)
	var all_opened_animated := true
	for c: Vector2i in before.keys():
		if f.get_state(c.x, c.y) > int(before[c][0]) and not started.has(c):
			# клетка, у которой вид не сменился (пустота без стены), может и не проявляться
			if _slot_color(v, c.x, c.y) != before[c][1]:
				all_opened_animated = false
	check("[%s] каждая открывшаяся клетка со сменой вида проявляется" % tag, all_opened_animated)

	# Монотонно и ровно за длительность.
	var cells := started.duplicate()
	var prev := {}
	for c: Vector2i in cells:
		prev[c] = fade.cover_at(c.x, c.y)
	var opaque0 := true
	for c: Vector2i in cells:
		if prev[c] < 0.5:
			opaque0 = false
	check("[%s] в первый кадр клетка ещё закрыта прежним видом (прозрачность нового ≈ 0)" % tag, opaque0)
	var mono := true
	var t := 0.0
	var steps := int(ceil(fade.duration / DT))
	var still_before_end := true
	for i in range(steps):
		fade.advance(DT)
		t += DT
		for c: Vector2i in cells:
			var cv := fade.cover_at(c.x, c.y)
			if cv > prev[c] + 1e-6:
				mono = false
			if t < fade.duration - 1e-4 and cv <= 0.0:
				still_before_end = false
			prev[c] = cv
		v.render(cam)
		if not _new_entries(fade).is_empty():
			mono = false
	check("[%s] закрытость только убывает, повторных вспышек нет" % tag, mono)
	check("[%s] до конца длительности клетка ещё проявляется (не скачок)" % tag, still_before_end)
	check("[%s] через длительность (%.2f с) всё проявилось и узел затих" % [tag, fade.duration],
		fade.active_count() == 0 and not fade.is_processing())

	# Повторно не мигает: обход туда-обратно по уже открытому.
	var opened_twice := 0
	var counts := {}
	for dx in [1.0, 1.0, 1.0, -1.0, -1.0, -1.0, -1.0, 1.0]:
		p.x += dx
		f.reveal_around(p.x, p.y, 2, 1)
		v.render(_cam_for(p))
		for c: Vector2i in _new_entries(fade):
			counts[c] = int(counts.get(c, 0)) + 1
		fade.advance(1.0)
	for c in counts.keys():
		if int(counts[c]) > 2:   # чёрное → серое → руда: не больше двух проявлений за жизнь клетки
			opened_twice += 1
	check("[%s] клетка проявляется не больше двух раз (туман → порода → руда)" % tag, opened_twice == 0)
	var back := 0
	for dx in [1.0, -1.0, 1.0, -1.0]:
		p.x += dx
		f.reveal_around(p.x, p.y, 2, 1)
		v.render(_cam_for(p))
		back += _new_entries(fade).size()
		fade.advance(1.0)
	check("[%s] по уже открытому — ни одного нового проявления" % tag, back == 0)
	v.queue_free()
	p.queue_free()


## Цвет заливки клетки на экране (null — текстура или клетка не видна).
func _slot_color(v: Node2D, wx: int, wy: int) -> Variant:
	var s: Sprite2D = v._pool[posmod(wy, v._pool_rows) * v._pool_cols + posmod(wx, v._pool_cols)]
	if not s.visible or s.texture != v._white_tex:
		return null
	return s.modulate


func test_no_fade_on_bulk_changes() -> void:
	print("-- загрузка, сброс, телепорт, эпоха деда — без анимации всего экрана --")
	var w := WorldGen.new(777)
	var f := FogOfWar.new()
	var p := FakePlayer.new()
	add_child(p)
	var v := _make_view(w, f, p, true)
	var fade: FogFade = v.fog_fade
	f.reveal_around(p.x, p.y, 2, 1)
	v.render(_cam_for(p))
	var cam := _cam_for(p)

	var saved := f.to_save_data()
	var wider := FogOfWar.new()
	wider.load_save_data(saved)
	wider.reveal_around(p.x, p.y, 4, 3)
	f.load_save_data(wider.to_save_data())
	v.render(cam)
	check("загрузка сейва: видимое появляется сразу", fade.active_count() == 0)

	f.reset_all()
	f.reveal_around(p.x, p.y, 2, 1)
	v.render(cam)
	check("землетрясение (сброс всего тумана): без проявления", fade.active_count() == 0)

	f.reset_rect(int(p.x) - 2, int(p.y) - 2, 5, 5)
	v.render(cam)
	check("обвал гасит клетки — не «проявление»", fade.active_count() == 0)

	# Телепорт/смерть: герой и камера сразу далеко, раскрытие — до кадра (как в main._process).
	p.x = 20.5
	p.y = 140.5
	f.reveal_around(p.x, p.y, 2, 1)
	v.render(_cam_for(p))
	check("телепорт: окно на новом месте рисуется сразу, без проявления", fade.active_count() == 0)

	# Проявление шло — и тут загрузка: старые заливки не висят над новой картинкой.
	p.x += 1.0
	f.reveal_around(p.x, p.y, 2, 1)
	v.render(_cam_for(p) - Vector2(1, 0))
	check("(шаг после телепорта проявляется)", fade.active_count() > 0)
	f.load_save_data(f.to_save_data())
	v.render(_cam_for(p) - Vector2(1, 0))
	check("загрузка посреди проявления: заливки сняты", fade.active_count() == 0)

	w.era = "grandpa"
	v.render(_cam_for(p))
	p.x += 1.0
	f.reveal_around(p.x, p.y, 2, 1)
	v.render(_cam_for(p) - Vector2(1, 0))
	check("эпоха деда (тумана нет): проявлять нечего", fade.active_count() == 0)
	w.era = "now"
	v.queue_free()
	p.queue_free()


## Клетка за доли секунды проходит чёрное → серое → руда: первое проявление не обрывается, второе
## ложится под него — картинка не прыгает.
func test_stacked_change() -> void:
	print("-- два открытия подряд --")
	var w := WorldGen.new(4242)
	var f := FogOfWar.new()
	var p := FakePlayer.new()
	add_child(p)
	var v := _make_view(w, f, p, false)
	var fade: FogFade = v.fog_fade
	var cam := _cam_for(p)
	f.reveal_around(p.x, p.y, 1, 0)
	v.render(cam)
	var cx := int(p.x) + 2
	var cy := int(p.y)
	f.reveal_terrain(p.x + 1.0, p.y, 1)
	v.render(cam)
	var n1 := 0
	for i in range(fade._x.size()):
		if fade._x[i] == cx and fade._y[i] == cy:
			n1 += 1
	check("клетка открылась до рельефа — одно проявление из тумана", n1 == 1)
	fade.advance(0.05)
	var t_first := -1.0
	for i in range(fade._x.size()):
		if fade._x[i] == cx and fade._y[i] == cy:
			t_first = fade._t[i]
	f.reveal_resources(p.x + 1.0, p.y, 1)
	v.render(cam)
	var n2 := 0
	var t_kept := false
	for i in range(fade._x.size()):
		if fade._x[i] == cx and fade._y[i] == cy:
			n2 += 1
			if is_equal_approx(fade._t[i], t_first):
				t_kept = true
	check("открылась до руды — добавилось второе проявление", n2 == 2)
	check("первое не перезапустилось (часы те же)", t_kept)
	v.queue_free()
	p.queue_free()


func test_zero_duration() -> void:
	print("-- длительность 0 — скачком, как раньше --")
	var w := WorldGen.new(4242)
	var f := FogOfWar.new()
	var p := FakePlayer.new()
	add_child(p)
	var v := _make_view(w, f, p, true)
	v.fog_fade.duration = 0.0
	var cam := _cam_for(p)
	f.reveal_around(p.x, p.y, 2, 1)
	v.render(cam)
	p.x += 1.0
	f.reveal_around(p.x, p.y, 2, 1)
	v.render(cam)
	check("при 0 ничего не проявляется", v.fog_fade.active_count() == 0)
	v.queue_free()
	p.queue_free()

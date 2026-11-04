class_name FogFade
extends Node2D
## Плавное раскрытие тумана войны. Владелец (разбор чисел, 26.10): «Сделай плавность раскрытия,
## минимальную, но приятную для глаз». Раньше клетка, в которую входил круг обзора, меняла вид
## скачком: чёрное → серая порода → руда.
##
## WorldView по-прежнему сразу перекрашивает открывшуюся клетку в новый вид, а этот узел кладёт поверх
## неё прежний (чёрный туман или серую породу) и гасит его за duration с замедлением к концу (ease-out):
## клетка проявляется от прозрачности 0 к 1. Не прозрачностью самого тайла — под тайлами лежит стена
## пояса (DeepBackdrop), и полупрозрачная порода показала бы её, а не туман.
##
## Анимируются только клетки, которые туман открыл сейчас (журнал FogOfWar.changed_since): уже открытое
## не трогается, а «менялось всё» (загрузка сейва, землетрясение, конец сцены) и прыжок окна на новое
## место (телепорт, смерть) рисуются сразу. Узел — ребёнок overlay «позади родителя»: поверх тайлов, но
## под кольцами обзора и рамкой копки.

const TILE := 32
## Больше разом не бывает даже при прыжке окна (экран ~7×15 клеток); лишнее просто открывается сразу.
const MAX_CELLS := 256

## Длительность проявления, с (data/feel.json → fog.reveal_fade_s). 0 — раскрытие скачком, как раньше.
var duration: float = 0.2
## Тест ведёт часы сам (advance), _process не двигает проявление.
var manual_clock: bool = false

var _x := PackedInt32Array()
var _y := PackedInt32Array()
var _c := PackedColorArray()     # прежний вид клетки: цвет заливки с его прозрачностью
var _t := PackedFloat32Array()   # сколько прошло с открытия


func _init() -> void:
	show_behind_parent = true
	duration = Feel.num("fog.reveal_fade_s", 0.2)
	set_process(false)


## Клетка (wx, wy) только что открылась; from — как она выглядела до этого (заливка тумана).
func start(wx: int, wy: int, from: Color) -> void:
	if duration <= 0.0 or from.a <= 0.0 or _x.size() >= MAX_CELLS:
		return
	_x.append(wx)
	_y.append(wy)
	_c.append(from)
	_t.append(0.0)
	set_process(not manual_clock)
	queue_redraw()


func _process(delta: float) -> void:
	if not manual_clock:
		advance(delta)


## Сдвинуть часы проявления; догоревшие клетки выбывают.
func advance(dt: float) -> void:
	if _t.is_empty():
		set_process(false)
		return
	var keep := 0
	for i in range(_t.size()):
		var t := _t[i] + dt
		if t >= duration:
			continue
		_x[keep] = _x[i]
		_y[keep] = _y[i]
		_c[keep] = _c[i]
		_t[keep] = t
		keep += 1
	_x.resize(keep)
	_y.resize(keep)
	_c.resize(keep)
	_t.resize(keep)
	if keep == 0:
		set_process(false)
	queue_redraw()


## Проявленность клетки за время t (0..1): ease-out — быстро вначале, мягко к концу.
func reveal_at(t: float) -> float:
	if duration <= 0.0:
		return 1.0
	var k := clampf(t / duration, 0.0, 1.0)
	return 1.0 - pow(1.0 - k, 3.0)


## Насколько клетка (wx, wy) сейчас ещё закрыта прежним видом (0 — проявилась целиком). Для тестов.
func cover_at(wx: int, wy: int) -> float:
	var clear := 1.0
	for i in range(_x.size()):
		if _x[i] == wx and _y[i] == wy:
			clear *= 1.0 - _c[i].a * (1.0 - reveal_at(_t[i]))
	return 1.0 - clear


func active_count() -> int:
	return _x.size()


func clear() -> void:
	if _x.is_empty():
		return
	_x.resize(0)
	_y.resize(0)
	_c.resize(0)
	_t.resize(0)
	set_process(false)
	queue_redraw()


func _draw() -> void:
	# С конца: открытая позже заливка (серая порода) ложится под раньшую (чёрный туман) — когда клетка за
	# доли секунды проходит чёрное → серое → руда, картинка не прыгает ни на одном шаге.
	for i in range(_x.size() - 1, -1, -1):
		var c := _c[i]
		c.a *= 1.0 - reveal_at(_t[i])
		draw_rect(Rect2(_x[i] * TILE, _y[i] * TILE, TILE, TILE), c)

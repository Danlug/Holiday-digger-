class_name DragScroll
extends Node
## Прокрутка списка перетаскиванием самого списка, а не только ползунком
## справа (решение владельца).
##
## Почему отдельный узел, а не gui_input у самого ScrollContainer: события,
## которые забрал ребёнок, до контейнера не доходят, а внутри списков лежат
## кнопки — потянуть список за кнопку было бы нельзя, и прокрутка работала бы
## через раз, в зависимости от того, куда попал палец. Слушаем _input, то есть
## всё подряд, и сами решаем, что это было.
##
## Клик от перетаскивания отличаем по порогу: пока палец не уехал на
## DRAG_THRESHOLD, это ещё нажатие, и кнопка под пальцем сработает как обычно
## (Button срабатывает на отпускании). Уехал — это прокрутка, и кнопку мы уже
## не трогаем.

## Сколько точек палец должен проехать, чтобы это считалось прокруткой.
const DRAG_THRESHOLD := 6.0
## Инерция после отпускания: доля скорости, гасимая за кадр, и порог остановки.
const FLING_DAMPING := 0.88
const FLING_STOP := 4.0

var _scroll: ScrollContainer
var _pointer: int = -100
var _start_pos: Vector2 = Vector2.ZERO
var _last_pos: Vector2 = Vector2.ZERO
var _start_scroll: int = 0
var _dragging: bool = false
var _velocity: float = 0.0


static func attach(scroll: ScrollContainer) -> DragScroll:
	var d := DragScroll.new()
	d.name = "DragScroll"
	d._scroll = scroll
	scroll.add_child(d)
	return d


func _process(delta: float) -> void:
	if _dragging or _scroll == null or absf(_velocity) < FLING_STOP:
		_velocity = 0.0
		return
	_scroll.scroll_vertical = int(round(float(_scroll.scroll_vertical) - _velocity * delta))
	_velocity *= FLING_DAMPING


func _input(event: InputEvent) -> void:
	if _scroll == null or not _scroll.is_visible_in_tree():
		return
	var e := _pointer_event(event)
	if e.is_empty():
		return
	match String(e["kind"]):
		"press":
			if _pointer != -100:
				return
			if not Rect2(_scroll.global_position, _scroll.size).has_point(e["pos"]):
				return
			_pointer = int(e["pid"])
			_start_pos = e["pos"]
			_last_pos = e["pos"]
			_start_scroll = _scroll.scroll_vertical
			_dragging = false
			_velocity = 0.0
		"move":
			if int(e["pid"]) != _pointer:
				return
			var dy: float = e["pos"].y - _start_pos.y
			if not _dragging and absf(dy) < DRAG_THRESHOLD:
				return
			_dragging = true
			_scroll.scroll_vertical = _start_scroll - int(round(dy))
			# Скорость — по последнему отрезку, а не по всему жесту: иначе
			# остановленный у края палец всё равно улетал бы по инерции.
			_velocity = (e["pos"].y - _last_pos.y) * 60.0
			_last_pos = e["pos"]
			get_viewport().set_input_as_handled()
		"release":
			if int(e["pid"]) != _pointer:
				return
			_pointer = -100
			if _dragging:
				get_viewport().set_input_as_handled()
			_dragging = false


static func _pointer_event(event: InputEvent) -> Dictionary:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return {}
		return {"kind": "press" if mb.pressed else "release", "pos": mb.position, "pid": -1}
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		return {"kind": "press" if st.pressed else "release", "pos": st.position, "pid": st.index}
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			return {}
		return {"kind": "move", "pos": mm.position, "pid": -1}
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		return {"kind": "move", "pos": sd.position, "pid": sd.index}
	return {}

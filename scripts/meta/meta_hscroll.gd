class_name MetaHScroll
extends ScrollContainer
## Горизонтальная лента (дорога трофеев), которую тянут пальцем или мышью.
## Плитки внутри — с mouse_filter = PASS: нажатие доходит до них, а движение
## всплывает сюда. dragged показывает плиткам, что это была прокрутка, а не
## нажатие — иначе каждый свайп по ленте забирал бы награду.

const DRAG_THRESHOLD := 6.0

var dragged: bool = false
var _down: bool = false
var _start_x: float = 0.0
var _start_scroll: int = 0


func _ready() -> void:
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
			dragged = false
			_start_x = (event as InputEventMouseButton).global_position.x
			_start_scroll = scroll_horizontal
		else:
			_down = false
	elif event is InputEventMouseMotion and _down:
		var dx := (event as InputEventMouseMotion).global_position.x - _start_x
		if absf(dx) > DRAG_THRESHOLD:
			dragged = true
		if dragged:
			scroll_horizontal = _start_scroll - int(dx)

class_name BotPlayer
extends RefCounted
## Эмулятор игрока для интеграционных тестов (tests/test_bot_*.gd).
##
## Ввод идёт тем же путём, что у человека: настоящие нажатия клавиш WASD
## (hud._apply_keyboard → Player.set_intent) и тапы мышью (CutscenePlayer._input),
## а не прямые вызовы методов Player. Поэтому тест ловит и поломки проводки ввода
## — HUD, который перестал слушать клавиши, катсцену, которая перестала листаться.
##
## Класс ничего не знает про сюжет: только «нажми / отпусти / тапни». Сценарий —
## в самих тестах.

var _down: Dictionary = {}


## Клавиша «нажата». Input.parse_input_event кладёт событие в буфер; без
## flush Input.is_key_pressed() увидит его только в следующем кадре, а HUD
## опрашивает клавиши как раз раз за кадр.
func key_down(k: Key) -> void:
	if _down.has(k):
		return
	_down[k] = true
	_send_key(k, true)


func key_up(k: Key) -> void:
	if not _down.has(k):
		return
	_down.erase(k)
	_send_key(k, false)


func release_all() -> void:
	for k in _down.keys():
		_send_key(k, false)
	_down.clear()


## Нужные клавиши зажаты, остальные отпущены (идемпотентно, зовётся каждый кадр).
func hold(keys: Array) -> void:
	for k in _down.keys():
		if not keys.has(k):
			key_up(k)
	for k in keys:
		key_down(k)


func is_down(k: Key) -> bool:
	return _down.has(k)


func _send_key(k: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## Тап по точке экрана (в координатах вьюпорта 224×480).
func tap(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(ev)
		Input.flush_buffered_events()

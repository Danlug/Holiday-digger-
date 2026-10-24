extends BotPlayer
## Бот-игрок «пальцем»: тот же интерфейс, что у BotPlayer (hold/release_all/is_down), но вместо
## клавиш WASD — нажатие и ведение экранного джойстика HUD (режим «stick», главный на телефоне).
## Набор «клавиш» переводится в точку на круге джойстика: S — вниз, A/D — вбок, W — вверх,
## W+A/D — вверх под 55° (бег с прыжком; зона «вверх» в player.resolve_dir от 45° до 67.5°).
## Так проверяется проводка касаний: HUD._input → _handle_stick_input → resolve_dir.
## В доме джойстика нет (HUD спрятан) — там ходим клавишами, как на ПК.

var hud: Control
var kb := BotPlayer.new()
var _pressed := false
var _pos := Vector2.ZERO


func _init(h: Control) -> void:
	hud = h


func hold(keys: Array) -> void:
	_down.clear()
	for k in keys:
		_down[k] = true
	if GameState.house_is_indoors or not hud.visible:
		_release()
		kb.hold(keys)
		return
	kb.release_all()
	var v := _vector(keys)
	if v == Vector2.ZERO:
		_release()
		return
	var target: Vector2 = hud._stick_center + v * float(hud.stick_r) * 0.9
	if not _pressed:
		_send_button(target, true)
		_pressed = true
	elif target.distance_to(_pos) > 0.5:
		_send_motion(target)
	_pos = target


func key_down(k: Key) -> void:
	var keys: Array = _down.keys()
	if not keys.has(k):
		keys.append(k)
	hold(keys)


func key_up(k: Key) -> void:
	var keys: Array = _down.keys()
	keys.erase(k)
	hold(keys)


func release_all() -> void:
	_down.clear()
	kb.release_all()
	_release()


func _release() -> void:
	if _pressed:
		_send_button(_pos, false)
		_pressed = false


static func _vector(keys: Array) -> Vector2:
	var dx := 0.0
	if keys.has(KEY_D):
		dx += 1.0
	if keys.has(KEY_A):
		dx -= 1.0
	if keys.has(KEY_S):
		return Vector2(0, 1)
	if keys.has(KEY_W):
		if dx == 0.0:
			return Vector2(0, -1)
		var a := deg_to_rad(55.0)
		return Vector2(dx * cos(a), -sin(a))
	return Vector2(dx, 0)


## parse_input_event ждёт координаты ОКНА, а джойстик живёт в координатах вьюпорта 224×480:
## окно растянуто (headless — 64×64, под рендером 448×960), поэтому переводим через
## итоговое преобразование вьюпорта. Без этого «палец» попадал в точку ×7.5 мимо джойстика.
func _to_window(pos: Vector2) -> Vector2:
	return hud.get_viewport().get_final_transform() * pos


func _send_button(pos: Vector2, pressed: bool) -> void:
	pos = _to_window(pos)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _send_motion(pos: Vector2) -> void:
	var rel := _to_window(pos) - _to_window(_pos)
	pos = _to_window(pos)
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

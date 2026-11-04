class_name LuckJuice
extends RefCounted
## Отклик удачной находки. Владелец, 27.10: «Когда срабатывает удача, размер иконки
## выкопанного с надписью множителя на 20 процентов больше, чем обычно, и звук получения
## громче на 50, вспышка 15 процентов, сотрясение + зум камеры 5 процентов».
## Числа — data/juice.json → luck.
##
## Порядок в Player._finish_dig: arm(руда) → находка ложится в рюкзак (события picked:
## JuiceDirector, видя arm, играет тот же звук подбора громче и рисует «+N» крупнее) →
## disarm() → Player._lucky_find: крупное «×N» и moment() — вспышка, толчок и наезд камеры.
## Обычная находка ничего из этого не получает: arm живёт один кадр и только для своей руды.

static var _armed_item: String = ""
static var _armed_frame: int = -1


static func arm(item: String) -> void:
	_armed_item = item
	_armed_frame = Engine.get_process_frames()


static func disarm() -> void:
	_armed_item = ""
	_armed_frame = -1


## Подбор item сейчас — часть удачной находки (тот же кадр, та же руда).
static func is_armed(item: String) -> bool:
	return not item.is_empty() and item == _armed_item and _armed_frame == Engine.get_process_frames()


## Во сколько раз значок с «+N» и подпись «×N» крупнее обычных.
static func icon_scale() -> float:
	return maxf(Juice.num("luck.icon_scale", 1.2), 0.1)


## Прибавка громкости звука подбора, дБ: амплитуда ×sound_gain (1.5 → +3.52 дБ).
static func sound_db() -> float:
	return linear_to_db(maxf(Juice.num("luck.sound_gain", 1.5), 0.01))


static func flash_color() -> Color:
	var c := Color.html(String(_val("flash_color", "FFD84A")))
	c.a = clampf(Juice.num("luck.flash_alpha", 0.15), 0.0, 1.0)
	return c


## Вспышка, толчок и наезд камеры. Удача на земле (mineral_id пуст) случается до
## 10% клеток — ей по умолчанию хватает крупного «×N» (luck.earth_moment).
static func moment(cell_pos: Vector2, mineral_id: String) -> void:
	if mineral_id.is_empty() and not bool(_val("earth_moment", false)):
		return
	if not mineral_id.is_empty():
		Fx.burst("pickup_glint", cell_pos, 0.9)
		Haptics.tap()
	Fx.flash(flash_color(), Juice.num("luck.flash_s", 0.25))
	var z := Juice.num("luck.zoom", 0.05)
	# канал «luck» с потолком в те же 5%: удачи подряд не раздувают наезд
	CameraKick.zoom_punch(z, Juice.num("luck.zoom_hold_s", 0.08), Juice.num("luck.zoom_return_s", 0.6), "luck", z)
	CameraKick.shake(Juice.num("luck.shake_cells", 0.05), Juice.num("luck.shake_s", 0.18))


static func _val(key: String, default: Variant) -> Variant:
	var sec: Variant = Juice.config().get("luck", {})
	if typeof(sec) != TYPE_DICTIONARY or not sec.has(key):
		return default
	var v: Variant = sec[key]
	if typeof(v) == TYPE_DICTIONARY:
		return v.get("value", default)
	return v

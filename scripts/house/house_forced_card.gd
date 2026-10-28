class_name HouseForcedCard
extends Control
## HouseForcedCard — «принудительная» подсказка обучения (ГДД п.9, п.16): держит
## героя замороженным и ждёт ровно одного действия. Абзаца нет: большой значок
## в пульсирующей рамке и одна зелёная кнопка. Объяснение правил лежит в Tip
## значка (долгое нажатие / наведение) и один раз показывается само, чтобы
## новичок, не знающий про долгое нажатие, всё равно прочитал его.
##
## Окно намеренно не закрывается тапом за границей: у него нет «за границей»,
## оно закрывается только нужным действием (сигнал confirmed).

signal confirmed

const FRAME := 88.0
const AUTO_TIP_DELAY := 0.55
const AUTO_TIP_SECONDS := 5.0

var _frame: Control
var _glow: TextureRect
var _rim: NinePatchRect
var _icon: TextureRect
var _button: Button
var _pulse: Tween
var _token := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.02, 0.84)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)

	_frame = Control.new()
	_frame.custom_minimum_size = Vector2(FRAME, FRAME)
	_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_frame)
	_glow = ShopArt.rect(ShopArt.tex("glow"), Vector2(-20, -20), Vector2(FRAME + 40, FRAME + 40))
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.modulate = Color(1, 0.9, 0.5, 0.5)
	_frame.add_child(_glow)
	_frame.add_child(HouseArt.nine("tile_body", 5, Color.WHITE, Vector2(FRAME, FRAME)))
	_rim = HouseArt.nine("tile_rim", 5, HouseArt.GOLD, Vector2(FRAME, FRAME))
	_frame.add_child(_rim)
	_icon = ShopArt.rect(null, Vector2(12, 12), Vector2(FRAME - 24, FRAME - 24))
	_frame.add_child(_icon)

	_button = UiBtn.texture_button("green", ShopArt.tex("glyph_check"), Vector2(112, 38), 22.0)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.pressed.connect(_on_pressed)
	col.add_child(_button)


## icon_px — размер значка внутри рамки (24-пиксельный значок рисуем в 48,
## 32-пиксельный предмет — в 64: целое число раз, без «мыла»).
func setup(icon: Texture2D, icon_px: float, title: String, body: String, button_title: String) -> void:
	_icon.texture = icon
	_icon.size = Vector2(icon_px, icon_px)
	_icon.position = (Vector2(FRAME, FRAME) - _icon.size) * 0.5
	Tip.bind(_frame, title, body)
	Tip.bind(_button, button_title)


func open() -> void:
	visible = true
	_token += 1
	Sfx.play("ui_open")
	Haptics.tap()
	_start_pulse()
	var token := _token
	await get_tree().create_timer(AUTO_TIP_DELAY).timeout
	if token != _token or not visible:
		return
	Tip.show_now(_frame)
	await get_tree().create_timer(AUTO_TIP_SECONDS).timeout
	if token == _token and visible and Tip.is_showing():
		Tip.hide_all()


func close() -> void:
	_token += 1
	if _pulse != null:
		_pulse.kill()
	if visible:
		Tip.hide_all()
	visible = false


func _start_pulse() -> void:
	if _pulse != null:
		_pulse.kill()
	_frame.pivot_offset = Vector2(FRAME, FRAME) * 0.5
	_button.pivot_offset = _button.size * 0.5
	_rim.modulate = HouseArt.GOLD_BRIGHT
	_glow.modulate.a = 0.5
	if Settings.reduce_motion or not is_inside_tree():
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_rim, "modulate", Color.WHITE, 0.55).set_trans(Tween.TRANS_SINE)
	_pulse.parallel().tween_property(_glow, "modulate:a", 0.8, 0.55).set_trans(Tween.TRANS_SINE)
	_pulse.parallel().tween_property(_frame, "scale", Vector2(1.04, 1.04), 0.55).set_trans(Tween.TRANS_SINE)
	_pulse.parallel().tween_property(_button, "scale", Vector2(1.05, 1.05), 0.55).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(_rim, "modulate", HouseArt.GOLD, 0.55).set_trans(Tween.TRANS_SINE)
	_pulse.parallel().tween_property(_glow, "modulate:a", 0.3, 0.55).set_trans(Tween.TRANS_SINE)
	_pulse.parallel().tween_property(_frame, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE)
	_pulse.parallel().tween_property(_button, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE)


func _on_pressed() -> void:
	if Tip.swallowed():
		return
	Tip.hide_all()
	confirmed.emit()

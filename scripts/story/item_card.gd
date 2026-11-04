class_name ItemCard
extends Control
## Карточка найденной вещи («Ранец с двумя пропеллерами», «Ржавая кирка деда»):
## скруглённая рамка с тенью, иконка в золотом свечении, название и короткая
## подпись. Появляется с лёгким «хлопком» масштаба.

const ICON_SIZE := 56.0
const PAD := 16.0

var _panel: Panel
var _glow: Control
var _icon: TextureRect
var _name: Label
var _text: Label
var _tween: Tween = null
var _vp: Vector2 = Vector2(224, 480)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func _build() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", DialogueStyle.panel_box(12, 2, 8))
	add_child(_panel)

	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.draw.connect(func() -> void:
		var c := _glow.size * 0.5
		for i in 6:
			var r := 36.0 - 5.0 * float(i)
			_glow.draw_circle(c, r, Color(DialogueStyle.GOLD, 0.05 + 0.03 * float(i))))
	add_child(_glow)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_name = Label.new()
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	DialogueStyle.shadowed(_name, UiTheme.FS_HEAD, DialogueStyle.GOLD)
	add_child(_name)

	_text = Label.new()
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_text.add_theme_constant_override("line_spacing", 2)
	DialogueStyle.shadowed(_text, UiTheme.FS_BODY, DialogueStyle.TEXT_NARR)
	add_child(_text)


## Карточка растёт под текст: подпись предмета бывает и в одну строку, и в шесть.
func layout(vp: Vector2) -> void:
	_vp = vp
	var w := vp.x - 32.0
	var inner := w - 24.0
	_name.size = Vector2(inner, 20)
	_text.size = Vector2(inner, 20)
	var name_h := 0.0
	var text_h := 0.0
	if is_inside_tree():
		name_h = float(maxi(1, _name.get_line_count())) * (_name.get_line_height() + 1.0)
		text_h = float(maxi(1, _text.get_line_count())) * (_text.get_line_height() + float(_text.get_theme_constant("line_spacing")))
	var h := PAD + ICON_SIZE + 10.0 + name_h + 8.0 + text_h + PAD
	size = Vector2(w, maxf(h, 120.0))
	position = Vector2(16.0, clampf(vp.y * 0.4 - size.y * 0.5, 34.0, vp.y * 0.6 - size.y))
	pivot_offset = size * 0.5
	_glow.position = Vector2(w * 0.5 - 40.0, PAD + ICON_SIZE * 0.5 - 40.0)
	_glow.size = Vector2(80, 80)
	_icon.position = Vector2(w * 0.5 - ICON_SIZE * 0.5, PAD)
	_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	_name.position = Vector2(12.0, PAD + ICON_SIZE + 10.0)
	_name.size = Vector2(inner, name_h)
	_text.position = Vector2(12.0, PAD + ICON_SIZE + 10.0 + name_h + 8.0)
	_text.size = Vector2(inner, text_h)


func show_item(icon: Texture2D, item_name: String, item_text: String) -> void:
	_icon.texture = icon
	_name.text = item_name
	_text.text = item_text
	visible = true
	layout(_vp)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	scale = Vector2.ONE
	modulate.a = 1.0
	if DialogueStyle.reduced() or not is_inside_tree():
		return
	scale = Vector2.ONE * 0.9
	modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.16)


## Вернуть карточку без анимации (подсветка тапа целится в неё).
func reshow() -> void:
	visible = true
	scale = Vector2.ONE
	modulate.a = 1.0


func hide_item() -> void:
	visible = false

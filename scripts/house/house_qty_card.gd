class_name HouseQtyCard
extends Control
## HouseQtyCard — окно «сколько»: положить на склад или забрать N штук. Вид как
## у карточки покупки магазина: снизу выезжает панель, сверху большая плитка и
## числа, дальше ползунок с «−» и «+», внизу красный крестик, «MAX» и зелёная
## галочка. Тап за границей панели закрывает окно (решение владельца: окна
## закрываются тапом за границей).
##
## Окно ничего не двигает само: confirmed(amount) уходит наружу, а склад
## (HouseStorage) решает, сколько реально влезло.

signal confirmed(amount: int)
signal cancelled

const SLIDER_MIN_W := 80.0

var _dim: ColorRect
var _panel: PanelContainer
var _preview_box: Control
var _count_label: Label
var _weight_label: Label
var _limit_row: Control
var _limit_label: Label
var _slider: HSlider
var _minus: Button
var _plus: Button
var _max_btn: Button
var _ok: Button
var _max := 1
var _unit_weight := 0.0
var _open := false


func _init() -> void:
	name = "QtyCard"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.62)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 10.0
	_panel.offset_right = -10.0
	_panel.offset_bottom = -12.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", HouseArt.panel_style(9))
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	_panel.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(top)
	_preview_box = Control.new()
	_preview_box.custom_minimum_size = Vector2(ShopTile.W, ShopTile.H)
	top.add_child(_preview_box)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(side)
	_count_label = ShopArt.label("1", 20, Color.WHITE, HouseArt.INK, 4)
	side.add_child(_count_label)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 3)
	wrow.add_child(_icon(UiIcons.tex("weight"), 14))
	_weight_label = ShopArt.label("0", 11, Color(0.82, 0.82, 0.88), HouseArt.INK, 3)
	wrow.add_child(_weight_label)
	side.add_child(wrow)
	_limit_row = HBoxContainer.new()
	_limit_row.add_theme_constant_override("separation", 3)
	_limit_row.add_child(_icon(ShopArt.ui("icon_backpack"), 14))
	_limit_label = ShopArt.label("", 11, ShopArt.COL_BAD, HouseArt.INK, 3)
	_limit_row.add_child(_limit_label)
	side.add_child(_limit_row)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 5)
	col.add_child(srow)
	_minus = HouseArt.button("gray", HouseArt.tex("glyph_minus"), Vector2(30, 28), 14.0)
	_minus.pressed.connect(func() -> void: _step(-1))
	srow.add_child(_minus)
	_slider = HSlider.new()
	_slider.min_value = 1
	_slider.step = 1
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.custom_minimum_size = Vector2(SLIDER_MIN_W, 28)
	_style_slider(_slider)
	_slider.value_changed.connect(_on_slider)
	srow.add_child(_slider)
	_plus = HouseArt.button("gray", ShopArt.tex("glyph_plus"), Vector2(30, 28), 14.0)
	_plus.pressed.connect(func() -> void: _step(1))
	srow.add_child(_plus)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 6)
	col.add_child(btns)
	var cancel := HouseArt.button("red", ShopArt.tex("glyph_cross"), Vector2(42, 32), 18.0)
	cancel.pressed.connect(func() -> void:
		if not Tip.swallowed():
			cancel_card())
	Tip.bind(cancel, "Отмена")
	btns.add_child(cancel)
	_max_btn = HouseArt.button("gold", null, Vector2(46, 32))
	var ml := ShopArt.label("MAX", 11, Color.WHITE, Color8(0x6A, 0x3E, 0x0A), 3)
	ml.position = Vector2(0, 0)
	ml.size = Vector2(46, 30)
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_max_btn.add_child(ml)
	_max_btn.pressed.connect(func() -> void: _slider.value = _max)
	btns.add_child(_max_btn)
	_ok = HouseArt.button("green", ShopArt.tex("glyph_check"), Vector2(80, 32), 20.0)
	_ok.pressed.connect(_on_ok)
	btns.add_child(_ok)


static func _icon(t: Texture2D, px: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Ползунок в пиксельном стиле: тёмная дорожка, золотая заливка и квадратный
## «язычок» вместо стандартной круглой ручки темы.
static func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color8(0x14, 0x10, 0x1B)
	track.border_color = Color8(0x4A, 0x3F, 0x5C)
	track.set_border_width_all(1)
	track.set_content_margin_all(0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = HouseArt.GOLD
	fill.set_content_margin_all(0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var img := Image.create(10, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color8(0x0E, 0x0B, 0x12))
	img.fill_rect(Rect2i(1, 1, 8, 14), Color8(0xFF, 0xE0, 0x80))
	img.fill_rect(Rect2i(1, 1, 8, 2), Color8(0xFF, 0xF6, 0xCC))
	img.fill_rect(Rect2i(1, 12, 8, 3), Color8(0xD9, 0x96, 0x2A))
	var tex := ImageTexture.create_from_image(img)
	s.add_theme_icon_override("grabber", tex)
	s.add_theme_icon_override("grabber_highlight", tex)
	s.add_theme_icon_override("grabber_disabled", tex)


## offer — словарь плитки (см. ShopTile.setup), max_amount — сколько можно
## переложить, count — сколько всего в источнике, limit_text — причина, по
## которой влезает меньше (пусто — предел только остаток).
func open(offer: Dictionary, max_amount: int, count: int, unit_weight: float, limit_text: String = "",
		verb: String = "Готово") -> void:
	for c in _preview_box.get_children():
		_preview_box.remove_child(c)
		c.queue_free()
	var po := offer.duplicate()
	po["pill"] = {}
	po["corner"] = ""
	po["state"] = "available"
	po["count_text"] = ""
	var preview := ShopTile.new()
	preview.setup(po)
	preview.disabled = true
	_preview_box.add_child(preview)

	_max = maxi(1, max_amount)
	_unit_weight = unit_weight
	_slider.max_value = _max
	_slider.editable = _max > 1
	_slider.value = _max
	_limit_row.visible = limit_text != ""
	_limit_label.text = limit_text
	if limit_text != "":
		Tip.bind(_limit_row, "Влезет только %s" % limit_text, "Мешает вес рюкзака или стопка в 99 штук.")
	Tip.bind(_ok, verb, String(offer.get("title", "")))
	Tip.bind(_max_btn, "Максимум")
	Tip.bind(_minus, "Меньше")
	Tip.bind(_plus, "Больше")
	_minus.disabled = _max <= 1
	_plus.disabled = _max <= 1
	_max_btn.disabled = _max <= 1
	_update_numbers()
	visible = true
	_open = true
	Sfx.play("ui_open")
	Haptics.tap()
	_animate_in()


func is_open() -> bool:
	return _open


func amount() -> int:
	return clampi(int(_slider.value), 1, _max)


func set_amount(n: int) -> void:
	_slider.value = clampi(n, 1, _max)


func cancel_card() -> void:
	if not _open:
		return
	_close()
	Sfx.play("ui_close")
	cancelled.emit()


func _close() -> void:
	_open = false
	visible = false
	Tip.hide_all()


func _animate_in() -> void:
	if Settings.reduce_motion or not is_inside_tree():
		return
	_panel.pivot_offset = Vector2(_panel.size.x * 0.5, _panel.size.y)
	_panel.scale = Vector2(0.92, 0.92)
	_dim.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dim, "modulate:a", 1.0, 0.14)


func _step(d: int) -> void:
	if Tip.swallowed():
		return
	_slider.value = clampi(int(_slider.value) + d, 1, _max)


func _on_slider(_v: float) -> void:
	_update_numbers()
	Sfx.play("ui_slider")


func _update_numbers() -> void:
	var n := amount()
	_count_label.text = "%s / %s" % [ShopArt.compact(n), ShopArt.compact(_max)] if _max > 1 else ShopArt.compact(n)
	_weight_label.text = ShopArt.compact(int(round(_unit_weight * float(n))))


func _on_ok() -> void:
	if Tip.swallowed():
		return
	var n := amount()
	_close()
	confirmed.emit(n)


func _on_dim_input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
		if not Tip.swallowed():
			cancel_card()

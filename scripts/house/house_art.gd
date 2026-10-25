class_name HouseArt
extends RefCounted
## HouseArt — картинки и мелкие общие приёмы интерфейса дома. Графика лежит в
## art/house_ui/ (tools/gen_house_icons.py); плитки, рамки и значки еды —
## общие с магазином (art/ui/shop/), чтобы дом выглядел той же игрой.
## Чего нет на диске — возвращает null: вызывающий решает сам, а не падает.

const DIR := "res://art/house_ui/"

const GOLD := Color8(0xE0, 0xA9, 0x3B)
const GOLD_BRIGHT := Color8(0xFF, 0xD8, 0x5A)
const INK := Color(0.05, 0.04, 0.08)


static func tex(icon_name: String) -> Texture2D:
	return ShopArt.load_path(DIR + icon_name + ".png")


## Значок еды: тот же, что рисует витрина магазина.
static func food_icon(id: String) -> Texture2D:
	return ShopArt.item_icon(id)


## Девятизонник из картинки магазина. Без rect_size — на всю родительскую
## область (якоря); с rect_size — фиксированного размера в левом верхнем углу:
## размер, заданный до add_child при якорях «вся область», потом складывается
## с размером родителя и рамка раздувается вдвое.
static func nine(texture_name: String, margin: int, tint: Color = Color.WHITE,
		rect_size: Vector2 = Vector2.ZERO) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = ShopArt.tex(texture_name)
	n.patch_margin_left = margin
	n.patch_margin_right = margin
	n.patch_margin_top = margin
	n.patch_margin_bottom = margin
	if rect_size == Vector2.ZERO:
		n.set_anchors_preset(Control.PRESET_FULL_RECT)
	else:
		n.size = rect_size
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.modulate = tint
	return n


## Кнопка в стиле магазина: цветной девятизонник (green/red/gold/gray) и значок.
## Нажатие даёт звук и вибро (UiBtn), «проседание» — как у остальных кнопок.
static func button(kind: String, glyph: Texture2D, size: Vector2, glyph_px: float = 16.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	var texture := ShopArt.tex("btn_" + kind)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var sb := StyleBoxTexture.new()
		sb.texture = texture
		sb.texture_margin_left = 5
		sb.texture_margin_right = 5
		sb.texture_margin_top = 5
		sb.texture_margin_bottom = 5
		match st:
			"pressed", "hover_pressed":
				sb.modulate_color = Color(0.78, 0.78, 0.78)
			"disabled":
				sb.modulate_color = Color(0.45, 0.45, 0.5)
		b.add_theme_stylebox_override(st, sb)
	if glyph != null:
		var ic := ShopArt.rect(glyph, (size - Vector2(glyph_px, glyph_px)) * 0.5, Vector2(glyph_px, glyph_px))
		ic.name = "Glyph"
		b.add_child(ic)
	UiBtn.wire_feedback(b)
	return b


## Рамка-панель магазина (тёмная с золотым верхом) для карточек и окон.
static func panel_style(margin: int = 9) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = ShopArt.tex("panel")
	for m in ["left", "right", "top", "bottom"]:
		sb.set("texture_margin_" + m, 6)
		sb.set("content_margin_" + m, margin)
	return sb


## Пузырёк «+12» / «−30» над значком: всплывает вверх и гаснет. Рисуется на
## host, поэтому работает и поверх непрозрачных слоёв дома.
static func float_number(host: Control, at: Vector2, text: String, color: Color, rise: float = 18.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	var l := ShopArt.label(text, 11, color, INK, 4)
	l.position = at
	l.z_index = 120
	host.add_child(l)
	if Settings.reduce_motion:
		l.create_tween().tween_callback(l.queue_free).set_delay(0.9)
		return
	var tw := host.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", at.y - rise, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)

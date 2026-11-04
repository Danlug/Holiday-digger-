class_name SceneCard
extends Control
## Карточка сцены: титр, заглавный кадр, «Позапрошлое лето.», титры конца игры.
## Затемнение с виньеткой поверх кадра (читается и на живой карте), заголовок
## крупно, остальные строки мельче и приглушённо, орнамент-ромбик сверху и снизу,
## плавное появление и затухание по времени кадра. «Меньше движения» оставляет
## текст сразу видимым, без подъёма.

const FADE_IN := 0.4
const FADE_OUT := 0.3
const RISE := 6.0
const DIM_ALPHA := 0.6
const TITLE_COLOR := Color8(0xF6, 0xE6, 0xB4)
const SUB_COLOR := Color8(0xC9, 0xBA, 0x9C)

var text: String = ""

var _dim: ColorRect
var _vig: TextureRect
var _col: VBoxContainer
var _title: Label
var _sub: Label
var _orn_top: Control
var _orn_bot: Control
var _vp: Vector2 = Vector2(224, 480)
var _base_y: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.015, 0.012, DIM_ALPHA)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.1), Color(0, 0, 0, 0.85)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 128
	_vig = TextureRect.new()
	_vig.texture = gt
	_vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vig.stretch_mode = TextureRect.STRETCH_SCALE
	_vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vig)

	_col = VBoxContainer.new()
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_col.add_theme_constant_override("separation", 9)
	add_child(_col)

	_orn_top = _make_ornament()
	_col.add_child(_orn_top)

	_title = Label.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	_title.add_theme_constant_override("line_spacing", 3)
	_col.add_child(_title)

	_sub = Label.new()
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	_sub.add_theme_constant_override("line_spacing", 4)
	DialogueStyle.shadowed(_sub, UiTheme.FS_LABEL, SUB_COLOR)
	_col.add_child(_sub)

	_orn_bot = _make_ornament()
	_col.add_child(_orn_bot)


func _make_ornament() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(0, 12)
	c.draw.connect(func() -> void:
		var cx := c.size.x * 0.5
		var cy := 6.0
		var gold := DialogueStyle.GOLD
		for i in 4:
			var a := 0.75 - 0.18 * float(i)
			var x0 := 9.0 + 11.0 * float(i)
			c.draw_line(Vector2(cx - x0 - 10.0, cy), Vector2(cx - x0, cy), Color(gold, a), 1.0)
			c.draw_line(Vector2(cx + x0, cy), Vector2(cx + x0 + 10.0, cy), Color(gold, a), 1.0)
		var d := PackedVector2Array([Vector2(cx, cy - 4), Vector2(cx + 4, cy), Vector2(cx, cy + 4), Vector2(cx - 4, cy)])
		c.draw_colored_polygon(d, gold)
		c.draw_polyline(PackedVector2Array([d[0], d[1], d[2], d[3], d[0]]), Color(0, 0, 0, 0.5), 1.0))
	return c


func layout(vp: Vector2) -> void:
	_vp = vp
	size = vp
	_base_y = vp.y * 0.2
	_col.position = Vector2(18.0, _base_y)
	_col.size = Vector2(vp.x - 36.0, vp.y * 0.46)


## Показать текст карточки. Первая строка — заголовок (крупно), остальные — мельче.
## total — длительность кадра в секундах: от неё считаются появление и затухание.
func show_text(card_text: String, total: float = 3.0) -> void:
	text = card_text
	var parts := card_text.split("\n", false, 1)
	var head: String = parts[0] if parts.size() > 0 else ""
	var rest: String = parts[1] if parts.size() > 1 else ""
	var size_px := 18 if head.length() <= 24 else (15 if head.length() <= 60 else 13)
	if rest.is_empty() and head.length() > 24:
		size_px = mini(size_px, 14)
	DialogueStyle.shadowed(_title, size_px, TITLE_COLOR)
	_title.text = head
	_sub.text = rest
	_sub.visible = not rest.is_empty()
	_orn_bot.visible = true
	visible = true
	layout(_vp)
	set_progress(0.0, total)


func hide_card() -> void:
	visible = false
	text = ""


## elapsed/total — сколько кадр уже идёт и сколько будет идти.
func set_progress(elapsed: float, total: float) -> void:
	if DialogueStyle.reduced():
		modulate.a = 1.0
		_col.position.y = _base_y
		return
	var fin := minf(FADE_IN, total * 0.35)
	var fout := minf(FADE_OUT, total * 0.3)
	var a_in := clampf(elapsed / maxf(fin, 0.001), 0.0, 1.0)
	var a_out := clampf((total - elapsed) / maxf(fout, 0.001), 0.0, 1.0)
	modulate.a = minf(a_in, a_out)
	var ease_in := 1.0 - pow(1.0 - a_in, 3.0)
	_col.position.y = _base_y + (1.0 - ease_in) * RISE

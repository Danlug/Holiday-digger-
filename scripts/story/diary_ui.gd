class_name DiaryUI
extends CanvasLayer
## Экран дневника деда: листаемая тетрадь, открывается у могилы (GraveSite).
##
## На странице — рисунок-набросок, две-три строки деда и пометка на полях
## карандашом (подсказка по игре). Закрытая страница показывает печать и
## короткое «не вскрывать»; точки внизу — страницы по порядку, у непрочитанных
## золотое кольцо. Названий страниц нет: тексты и подсказки — только внутри
## самой страницы или в Tip на точке (решение владельца: текст на экране —
## по наведению).

signal closed
signal page_shown(id: String)

const LAYER := 30
const PAPER := Color8(0xE8, 0xD8, 0xB0)
const PAPER_EDGE := Color8(0xA4, 0x83, 0x5A)
const INK := Color8(0x2E, 0x20, 0x14)
const NOTE := Color8(0x3C, 0x50, 0x7A)
const GOLD := Color8(0xE0, 0xA9, 0x3B)
const MARGIN_RED := Color8(0xC2, 0x5A, 0x4A)
const PANEL_W := 200.0

const ICON_DIARY := "res://art/story/icon_diary.png"
const ICON_SEAL := "res://art/story/icon_seal.png"
const ICON_PENCIL := "res://art/story/icon_pencil.png"

var current: int = 0
var is_open: bool = false

var _root: Control
var _panel: PanelContainer
var _sketch: TextureRect
var _text: Label
var _note_row: HBoxContainer
var _note: Label
var _sealed_box: VBoxContainer
var _sealed_text: Label
var _body: VBoxContainer
var _prev: Button
var _next: Button
var _dots_row: HBoxContainer
var _dots: Array = []
var _tween: Tween = null


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build()
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	_root.name = "Diary"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.01, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = PAPER_EDGE
	sb.set_border_width_all(2)
	sb.border_width_left = 4
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 6
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)

	col.add_child(_build_header())
	col.add_child(_build_body())
	col.add_child(_build_pager())


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.texture = load(ICON_DIARY)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	row.add_child(icon)
	var title := Label.new()
	title.text = StoryText.get_text("diary.title")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var close := _icon_button(UiIcons.tex("close"))
	close.custom_minimum_size = Vector2(28, 28)
	close.pressed.connect(close_diary)
	Tip.bind(close, StoryText.get_text("diary.close"))
	row.add_child(close)
	return row


func _build_body() -> Control:
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(0, 200)
	_body.add_theme_constant_override("separation", 6)

	_sketch = TextureRect.new()
	_sketch.custom_minimum_size = Vector2(48, 48)
	_sketch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sketch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sketch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(_sketch)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_text.add_theme_font_size_override("font_size", 11)
	_text.add_theme_color_override("font_color", INK)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_text)

	_note_row = HBoxContainer.new()
	_note_row.add_theme_constant_override("separation", 4)
	var pencil := TextureRect.new()
	pencil.texture = load(ICON_PENCIL)
	pencil.custom_minimum_size = Vector2(12, 12)
	pencil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pencil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pencil.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_note_row.add_child(pencil)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_note.add_theme_font_size_override("font_size", 10)
	_note.add_theme_color_override("font_color", NOTE)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_row.add_child(_note)
	_body.add_child(_note_row)

	_sealed_box = VBoxContainer.new()
	_sealed_box.add_theme_constant_override("separation", 8)
	_sealed_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_sealed_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var seal := TextureRect.new()
	seal.texture = load(ICON_SEAL)
	seal.custom_minimum_size = Vector2(72, 72)
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sealed_box.add_child(seal)
	_sealed_text = Label.new()
	_sealed_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_sealed_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sealed_text.add_theme_font_size_override("font_size", 10)
	_sealed_text.add_theme_color_override("font_color", INK)
	_sealed_box.add_child(_sealed_text)
	_body.add_child(_sealed_box)
	return _body


func _build_pager() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	_prev = _arrow_button(Vector2.LEFT)
	_prev.pressed.connect(func() -> void: _flip(-1))
	Tip.bind(_prev, StoryText.get_text("diary.prev"))
	row.add_child(_prev)

	_dots_row = HBoxContainer.new()
	_dots_row.add_theme_constant_override("separation", 0)
	_dots_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_dots_row)
	for i in StoryDiary.page_count():
		var dot := _make_dot(i)
		_dots.append(dot)
		_dots_row.add_child(dot)

	_next = _arrow_button(Vector2.RIGHT)
	_next.pressed.connect(func() -> void: _flip(1))
	Tip.bind(_next, StoryText.get_text("diary.next"))
	row.add_child(_next)
	return row


func _flat_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	return sb


func _icon_button(tex: Texture2D) -> Button:
	var b := Button.new()
	b.flat = true
	b.icon = tex
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _flat_style())
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0, 0, 0, 0.12)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover", pressed)
	b.add_theme_stylebox_override("focus", _flat_style())
	b.add_theme_color_override("icon_normal_color", INK)
	b.add_theme_color_override("icon_hover_color", INK)
	b.add_theme_color_override("icon_pressed_color", INK)
	return b


func _arrow_button(dir: Vector2) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(24, 28)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0.08)
	normal.set_corner_radius_all(3)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0, 0, 0, 0.22)
	pressed.set_corner_radius_all(3)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", _flat_style())
	b.add_theme_stylebox_override("focus", _flat_style())
	var arrow := ArrowIcon.new()
	arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	arrow.set_dir(dir)
	arrow.set_color(INK)
	b.add_child(arrow)
	return b


## Точка-страница: кнопка 9×26 (цель нажатия по высоте с запасом), внутри
## кружок. Отдельный класс не нужен — кружок рисует StyleBoxFlat.
func _make_dot(i: int) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(9, 26)
	b.add_theme_stylebox_override("normal", _flat_style())
	b.add_theme_stylebox_override("hover", _flat_style())
	b.add_theme_stylebox_override("pressed", _flat_style())
	b.add_theme_stylebox_override("focus", _flat_style())
	var dot := Panel.new()
	dot.name = "Dot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size = Vector2(7, 7)
	dot.position = Vector2(1, 9.5)
	b.add_child(dot)
	b.pressed.connect(func() -> void: _goto(i, true))
	return b


func _style_dot(i: int) -> void:
	var b: Button = _dots[i]
	var dot: Panel = b.get_node("Dot")
	var p := StoryDiary.page(i)
	var unlocked := StoryDiary.is_unlocked(p)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	if i == current:
		sb.bg_color = INK
		sb.border_color = INK
	elif unlocked:
		sb.bg_color = PAPER_EDGE
		sb.border_color = PAPER_EDGE
	else:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = PAPER_EDGE
	sb.set_border_width_all(1)
	if unlocked and not StoryDiary.is_read(String(p.get("id", ""))) and i != current:
		sb.border_color = GOLD
		sb.bg_color = GOLD
	dot.add_theme_stylebox_override("panel", sb)
	if unlocked:
		Tip.bind(b, StoryText.get_text("diary.page_n") % (i + 1))
	else:
		Tip.bind(b, StoryText.get_text("diary.page_n") % (i + 1),
			StoryText.get_text("diary.sealed_" + StoryDiary.sealed_kind(p)))


# ---------------------------------------------------------------------------
# Публичное API
# ---------------------------------------------------------------------------

## Первая непрочитанная открытая страница; если все прочитаны — последняя
## открытая; если ни одной — нулевая (печать).
func default_page() -> int:
	var last_unlocked := 0
	for i in StoryDiary.page_count():
		var p := StoryDiary.page(i)
		if StoryDiary.is_unlocked(p):
			last_unlocked = i
			if not StoryDiary.is_read(String(p.get("id", ""))):
				return i
	return last_unlocked


func open_diary(index: int = -1) -> void:
	if _root == null:
		_build()
	is_open = true
	_root.visible = true
	_goto(default_page() if index < 0 else index, false)
	Sfx.play("ui_open")
	Haptics.tap()
	if _tween != null:
		_tween.kill()
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2(0.92, 0.92)
	_panel.modulate.a = 0.0
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "scale", Vector2.ONE, 0.2)
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.14)


func close_diary() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	Sfx.play("ui_close")
	closed.emit()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close_diary()
	elif event is InputEventScreenTouch and event.pressed:
		close_diary()


func _flip(step: int) -> void:
	var n := StoryDiary.page_count()
	if n == 0:
		return
	_goto(clampi(current + step, 0, n - 1), true)


func _goto(index: int, animate: bool) -> void:
	var n := StoryDiary.page_count()
	if n == 0:
		return
	var changed := index != current
	current = clampi(index, 0, n - 1)
	var p := StoryDiary.page(current)
	var id := String(p.get("id", ""))
	var unlocked := StoryDiary.is_unlocked(p)

	_sketch.texture = load(String(p.get("icon", ""))) if unlocked and ResourceLoader.exists(String(p.get("icon", ""))) else null
	_sketch.visible = unlocked
	_text.visible = unlocked
	_note_row.visible = unlocked
	_sealed_box.visible = not unlocked
	if unlocked:
		_text.text = StoryText.get_text(StoryDiary.text_key(id, "text"))
		_note.text = StoryText.get_text(StoryDiary.text_key(id, "note"))
		StoryDiary.mark_read(id)
		page_shown.emit(id)
	else:
		_sealed_text.text = StoryText.get_text("diary.sealed_" + StoryDiary.sealed_kind(p))

	_prev.disabled = current <= 0
	_next.disabled = current >= n - 1
	_prev.modulate.a = 0.35 if _prev.disabled else 1.0
	_next.modulate.a = 0.35 if _next.disabled else 1.0
	for i in _dots.size():
		_style_dot(i)

	if animate and changed:
		Sfx.play("ui_tab")
		Haptics.tap()
		_body.modulate.a = 0.0
		create_tween().tween_property(_body, "modulate:a", 1.0, 0.16)
	else:
		_body.modulate.a = 1.0

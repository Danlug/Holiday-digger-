extends Control
## HUD — весь интерфейс поверх игрового экрана (см. задание п.9): полоски
## HP/голод/усталость слева сверху, кошелёк справа сверху, глубина справа на
## уровне героя, нижняя однострочная полоса (инвентарь/инструмент/снаряжение/
## режим/сброс), шторка инвентаря, джойстик и подсказка режима удержания —
## обе ПОВЕРХ игрового экрана, а не отдельной панелью (портировано из
## web/index.html).

const TILE := 32
const STRIP_H := 40.0
# Джойстик задаётся долей ширины экрана, а не пикселями из web-демо: там
# интерфейс живёт в пикселях устройства (118px на экране в 390), а здесь — в
# проектных единицах вьюпорта (224 в ширину), и те же 118 занимали половину
# экрана. 15% полуширины дают ту же долю экрана, что и в демо.
const STICK_FRACTION := 0.15
const STICK_R_MIN := 30.0
var stick_r := 34.0
var knob_r := 13.0
const STICK_DEAD := 0.26

var player: Node = null      # Player, назначает main.gd

# --- режим управления ---
var mode: String = "stick"   # "stick" | "hold"

# --- джойстик: активный указатель (-1 = нет) ---
var _stick_pointer: int = -100
var _stick_center: Vector2 = Vector2.ZERO

# --- удержание пальца на экране ---
var _touch_pointer: int = -100
var _touch_pos: Vector2 = Vector2.ZERO
var _has_touch: bool = false

var stage_rect: Rect2 = Rect2()
var current_cam: Vector2 = Vector2.ZERO  # выставляет main.gd каждый кадр (см. camera() в web-демо)

# --- узлы ---
var _gauges_box: Control
var _hp_fill: ColorRect
var _hunger_fill: ColorRect
var _stamina_fill: ColorRect
var _coins_label: Label
var _dollars_label: Label
var _load_label: Label
var _depth_box: Control
var _depth_label: Label
var _toast_panel: Panel
var _toast_label: Label
var _toast_timer: Timer
var _stick: Control
var _knob: Control
var _hold_hint: Label
var _tool_button: Button
var _tool_name_panel: PanelContainer
var _tool_name_label: Label
var _tool_name_timer: Timer
var _gear_pack: TextureRect
var _gear_jet: TextureRect
var _mode_button: Button
var _inv_button: Button
var _inv_sheet: Control
var _inv_list: VBoxContainer
var _inv_load_label: Label
var _inv_total_label: Label
var _drop_panel: Control
var _drop_title: Label
var _drop_slider: HSlider
var _drop_field: LineEdit
var _drop_id: String = ""
var _drop_max: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Якоря корня намеренно не растягивающие: размер выставляется вручную в
	# _update_layout (Control под CanvasLayer не наследует размер вьюпорта).
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_build_ui()
	_connect_game_state()
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	_sync_all()


## Три полоски выживания (HP/голод/усталость) вводятся не сразу: до сцены
## смерти их на экране нет (ГДД п.9), прячет их режиссура сюжета. Метод нужен
## именно ей: без него story_director искал коробку, шагая вверх по дереву от
## заливки HP, промахивался на один уровень и гасил ВЕСЬ игровой слой —
## вместе с джойстиком, кошельком, глубиной и шторкой инвентаря.
func set_gauges_visible(v: bool) -> void:
	if _gauges_box != null:
		_gauges_box.visible = v


func are_gauges_visible() -> bool:
	return _gauges_box != null and _gauges_box.visible


func set_player(p: Node) -> void:
	player = p
	player.fell.connect(_on_fell)
	player.dig_blocked.connect(_on_dig_blocked)
	player.dig_finished.connect(_on_dig_finished)
	player.gear_unlocked.connect(_on_gear_unlocked)
	player.tool_auto_switched.connect(_on_tool_switched)
	_sync_tool()


# ---------------------------------------------------------------------------
# Построение интерфейса
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var stage := Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.offset_bottom = -STRIP_H
	add_child(stage)

	_build_gauges(stage)
	_build_purse(stage)
	_build_depth(stage)
	_build_toast(stage)
	_build_stick(stage)
	_build_hold_hint(stage)
	_build_inventory_sheet(stage)
	_build_strip()


func _build_gauges(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "Gauges"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(8, 8)
	box.add_theme_constant_override("separation", 3)
	parent.add_child(box)
	_gauges_box = box

	_hp_fill = _make_gauge_row(box, Color8(0xB8, 0x5A, 0x52), "res://art/ui/icon_hp.png")
	_hunger_fill = _make_gauge_row(box, Color8(0xC4, 0x70, 0x6A), "res://art/ui/icon_hunger.png")
	_stamina_fill = _make_gauge_row(box, Color8(0x6E, 0x93, 0xA8), "res://art/ui/icon_stamina.png")


func _make_gauge_row(parent: Control, fill_color: Color, icon_path: String) -> ColorRect:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)

	if ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(13, 13)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(icon_path)
		row.add_child(icon)

	var track := Panel.new()
	track.custom_minimum_size = Vector2(72, 8)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.035, 0.027, 0.75)
	sb.border_color = Color(0, 0, 0, 0.55)
	sb.set_border_width_all(1)
	track.add_theme_stylebox_override("panel", sb)
	row.add_child(track)

	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = Vector2.ZERO
	fill.size = Vector2(72, 8)
	track.add_child(fill)
	return fill


func _build_purse(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 1.0; box.anchor_right = 1.0
	box.offset_left = -100; box.offset_right = -8
	box.offset_top = 8
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	parent.add_child(box)

	_coins_label = _make_purse_row(box, Color8(0xE0, 0xA9, 0x3B), "res://art/ui/icon_coin.png")
	_dollars_label = _make_purse_row(box, Color8(0x7F, 0xB8, 0x6B), "res://art/ui/icon_dollar.png")
	_load_label = _make_purse_row(box, Color8(0x8F, 0xA3, 0x5C), "res://art/ui/icon_inventory.png")


func _make_purse_row(parent: Control, color: Color, icon_path: String) -> Label:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)

	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)

	if ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(14, 14)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(icon_path)
		row.add_child(icon)
	return l


func _build_depth(parent: Control) -> void:
	_depth_box = Control.new()
	_depth_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_depth_box.anchor_left = 1.0; _depth_box.anchor_right = 1.0
	_depth_box.custom_minimum_size = Vector2(46, 22)
	_depth_box.offset_left = -46
	parent.add_child(_depth_box)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.071, 0.055, 0.043, 0.85)
	sb.border_color = Color8(0x3E, 0x31, 0x25)
	sb.set_border_width_all(1)
	sb.border_width_right = 0
	panel.add_theme_stylebox_override("panel", sb)
	_depth_box.add_child(panel)

	_depth_label = Label.new()
	_depth_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_depth_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_depth_label.add_theme_font_size_override("font_size", 13)
	_depth_box.add_child(_depth_label)
	_depth_box.visible = false


func _build_toast(parent: Control) -> void:
	_toast_panel = Panel.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.anchor_left = 0.0; _toast_panel.anchor_right = 1.0
	_toast_panel.anchor_top = 1.0; _toast_panel.anchor_bottom = 1.0
	_toast_panel.offset_left = 8; _toast_panel.offset_right = -8
	_toast_panel.offset_top = -160; _toast_panel.offset_bottom = -132
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.071, 0.055, 0.043, 0.93)
	sb.border_color = Color8(0xE0, 0xA9, 0x3B)
	sb.border_width_left = 3
	_toast_panel.add_theme_stylebox_override("panel", sb)
	_toast_panel.visible = false
	parent.add_child(_toast_panel)

	_toast_label = Label.new()
	_toast_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast_label.offset_left = 10; _toast_label.offset_top = 6
	_toast_label.add_theme_font_size_override("font_size", 12)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_toast_panel.add_child(_toast_label)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): _toast_panel.visible = false)
	add_child(_toast_timer)


func _build_stick(parent: Control) -> void:
	_stick = Control.new()
	_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick.custom_minimum_size = Vector2(stick_r * 2, stick_r * 2)
	_stick.draw.connect(func():
		_stick.draw_circle(Vector2(stick_r, stick_r), stick_r, Color(0.11, 0.09, 0.07, 0.68))
		_stick.draw_arc(Vector2(stick_r, stick_r), stick_r, 0, TAU, 40, Color(0.42, 0.34, 0.25, 0.6), 1.0)
	)
	parent.add_child(_stick)

	var hint := Label.new()
	hint.text = "ВВЕРХ — ПРЫЖОК"
	# Кегль под уменьшившийся стик: при 8 подпись вылезала за круг.
	hint.add_theme_font_size_override("font_size", 6)
	hint.add_theme_color_override("font_color", Color8(0x8F, 0xA3, 0x5C))
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 4
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stick.add_child(hint)

	_knob = Control.new()
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_knob.custom_minimum_size = Vector2(knob_r * 2, knob_r * 2)
	_knob.position = Vector2(stick_r - knob_r, stick_r - knob_r)
	_knob.draw.connect(func():
		var live: bool = hold_active()
		_knob.draw_circle(Vector2(knob_r, knob_r), knob_r, Color8(0x3A, 0x2C, 0x20))
		_knob.draw_arc(Vector2(knob_r, knob_r), knob_r - 1, 0, TAU, 32,
			Color8(0xE0, 0xA9, 0x3B) if live else Color8(0x9D, 0x8B, 0x73), 2.0)
	)
	_stick.add_child(_knob)


func hold_active() -> bool:
	return player != null and (player.hold_dx != 0 or player.hold_up or player.hold_down)


func _build_hold_hint(parent: Control) -> void:
	_hold_hint = Label.new()
	_hold_hint.text = "Зажми экран в нужную сторону — герой пойдёт туда и будет копать.\nОтпустил — остановился."
	_hold_hint.add_theme_font_size_override("font_size", 11)
	_hold_hint.add_theme_color_override("font_color", Color8(0x9D, 0x8B, 0x73))
	_hold_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hold_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hold_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hold_hint.offset_left = 10; _hold_hint.offset_right = -10
	_hold_hint.offset_top = -40; _hold_hint.offset_bottom = -8
	_hold_hint.visible = false
	parent.add_child(_hold_hint)


func _build_inventory_sheet(parent: Control) -> void:
	_inv_sheet = Control.new()
	_inv_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inv_sheet.visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.071, 0.055, 0.043, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inv_sheet.add_child(bg)
	parent.add_child(_inv_sheet)

	var head := HBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 10; head.offset_right = -10
	head.offset_top = 8; head.offset_bottom = 30
	_inv_sheet.add_child(head)

	var title := Label.new()
	title.text = "Инвентарь"
	title.add_theme_font_size_override("font_size", 12)
	head.add_child(title)

	_inv_load_label = Label.new()
	_inv_load_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_inv_load_label.add_theme_color_override("font_color", Color8(0x8F, 0xA3, 0x5C))
	_inv_load_label.add_theme_font_size_override("font_size", 10)
	head.add_child(_inv_load_label)

	var close_btn := Button.new()
	# Именно × (U+00D7), а не ✕ (U+2715): последнего в шрифте темы по
	# умолчанию нет, и он рисуется пустым квадратом (та же ловушка, что со
	# стрелкой ↺ на кнопке сброса).
	close_btn.text = "×"
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.custom_minimum_size = Vector2(20, 20)
	close_btn.pressed.connect(close_inventory)
	head.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 10; scroll.offset_right = -10
	scroll.offset_top = 36; scroll.offset_bottom = -30
	_inv_sheet.add_child(scroll)

	_inv_list = VBoxContainer.new()
	_inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inv_list)

	var foot := HBoxContainer.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_left = 10; foot.offset_right = -10
	foot.offset_top = -26; foot.offset_bottom = -6
	_inv_sheet.add_child(foot)
	var foot_label := Label.new()
	foot_label.text = "К продаже:"
	foot_label.add_theme_font_size_override("font_size", 11)
	foot.add_child(foot_label)
	_inv_total_label = Label.new()
	_inv_total_label.add_theme_color_override("font_color", Color8(0xE0, 0xA9, 0x3B))
	_inv_total_label.add_theme_font_size_override("font_size", 11)
	foot.add_child(_inv_total_label)

	_build_drop_panel(_inv_sheet)


## Окно «выбросить N штук»: ползунок и то же число полем ввода — на телефоне
## ползунком трудно попасть в «ровно 7 из 240», а руками неудобно набирать
## «120». Поле открывает цифровую клавиатуру, буквы в нём не принимаются.
func _build_drop_panel(parent: Control) -> void:
	_drop_panel = Control.new()
	_drop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drop_panel.visible = false
	parent.add_child(_drop_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drop_panel.add_child(dim)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(196, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0x1A, 0x14, 0x0F)
	sb.border_color = Color8(0x3E, 0x31, 0x25)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sb)
	_drop_panel.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	_drop_title = Label.new()
	_drop_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	_drop_title.add_theme_font_size_override("font_size", 11)
	box.add_child(_drop_title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	_drop_slider = HSlider.new()
	_drop_slider.min_value = 1
	_drop_slider.step = 1
	_drop_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_slider.value_changed.connect(_on_drop_slider_changed)
	row.add_child(_drop_slider)

	_drop_field = LineEdit.new()
	_drop_field.custom_minimum_size = Vector2(46, 0)
	_drop_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drop_field.max_length = 6
	# Только цифровая клавиатура: количество — всегда целое, буквам тут
	# делать нечего (то же, что inputmode="numeric" в web-демо).
	_drop_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_drop_field.text_changed.connect(_on_drop_field_changed)
	_drop_field.text_submitted.connect(func(_t): _apply_drop())
	row.add_child(_drop_field)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)

	var all_btn := Button.new()
	all_btn.text = "Всё"
	all_btn.add_theme_font_size_override("font_size", 10)
	all_btn.pressed.connect(func(): _drop_slider.value = _drop_max)
	buttons.add_child(all_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Отмена"
	cancel_btn.add_theme_font_size_override("font_size", 10)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_close_drop)
	buttons.add_child(cancel_btn)

	var ok_btn := Button.new()
	ok_btn.text = "Выбросить"
	ok_btn.add_theme_font_size_override("font_size", 10)
	ok_btn.add_theme_color_override("font_color", Color8(0xC4, 0x70, 0x6A))
	ok_btn.pressed.connect(_apply_drop)
	buttons.add_child(ok_btn)


func _open_drop(id: String, count: int) -> void:
	if count <= 0:
		return
	_drop_id = id
	_drop_max = count
	_drop_title.text = "Выбросить «%s» (в рюкзаке %d)" % [
		String(Balance.get_mineral(id).get("name_ru", id)), count]
	_drop_slider.max_value = count
	_drop_slider.value = count
	_drop_field.text = str(count)
	_drop_panel.visible = true


func _close_drop() -> void:
	_drop_panel.visible = false
	_drop_id = ""


func _drop_amount() -> int:
	return clampi(int(_drop_slider.value), 1, maxi(1, _drop_max))


func _on_drop_slider_changed(v: float) -> void:
	var n := clampi(int(v), 1, maxi(1, _drop_max))
	if _drop_field.text != str(n):
		_drop_field.text = str(n)


func _on_drop_field_changed(t: String) -> void:
	# Чистим ввод на месте: на телефоне цифровая клавиатура всё равно может
	# отдать минус или запятую, а каретку при этом терять нельзя.
	var digits := ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits != t:
		var caret := _drop_field.caret_column - (t.length() - digits.length())
		_drop_field.text = digits
		_drop_field.caret_column = maxi(0, caret)
	if digits.is_empty():
		return
	var n := clampi(int(digits), 1, maxi(1, _drop_max))
	if int(_drop_slider.value) != n:
		_drop_slider.set_value_no_signal(n)
	if str(n) != digits:
		_drop_field.text = str(n)
		_drop_field.caret_column = _drop_field.text.length()


func _apply_drop() -> void:
	if _drop_id.is_empty():
		return
	var n := _drop_amount()
	var id := _drop_id
	GameState.remove_item(id, n)
	_close_drop()
	_render_inventory()
	_sync_purse()
	toast("Выброшено: %s ×%d" % [
		String(Balance.get_mineral(id).get("name_ru", id)), n], 2.0)


var _more_panel: PanelContainer
var _more_button: Button


func _build_strip() -> void:
	# Подложка — отдельный слой под рядом кнопок. Если положить Panel внутрь
	# HBoxContainer, контейнер разложит её как обычный элемент ряда нулевой
	# ширины, и фона у полосы не будет вовсе.
	var root := Control.new()
	root.name = "Strip"
	root.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	root.offset_top = -STRIP_H
	root.offset_bottom = 0
	add_child(root)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0x16, 0x12, 0x0E)
	var bg_panel := Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_panel.add_theme_stylebox_override("panel", sb)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg_panel)

	var strip := HBoxContainer.new()
	strip.name = "Row"
	strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	strip.add_theme_constant_override("separation", 5)
	root.add_child(strip)

	# Систем стало пять, и каждая честно попросила себе кнопку — в ряду
	# шириной 224 их девять, а нужно им около 315. Ряд делится по тому,
	# нужна ли кнопка ВО ВРЕМЯ КОПКИ: инвентарь, склад, инструмент и
	# снаряжение остаются на виду, всё остальное уходит под «⋯». Прятать
	# по важности, а не по алфавиту: игрок сидит в шахте, а не в меню.
	var more_menu := _build_more_menu()
	_build_tool_name_popup()

	# Иконкой, а не словом: ряд шириной 224 не вмещает подпись «Инвентарь»
	# вместе с названием инструмента, снаряжением, режимом и сбросом.
	_inv_button = _make_chip("")
	if ResourceLoader.exists("res://art/ui/icon_inventory.png"):
		_inv_button.icon = load("res://art/ui/icon_inventory.png")
		_inv_button.expand_icon = true
		_inv_button.custom_minimum_size = Vector2(26, STRIP_H)
	else:
		_inv_button.text = "Инв"
	_inv_button.tooltip_text = "Инвентарь"
	_inv_button.toggle_mode = true
	_inv_button.pressed.connect(_on_inv_button_pressed)
	strip.add_child(_inv_button)

	# Инструмент — одна иконка без подписи. Название всплывает НАД полосой по
	# нажатию (и подсказкой при наведении на компьютере): слово «Лопата»
	# держало в ряду шириной 224 почти сорок точек, а нужно оно раз в час —
	# когда игрок сам не помнит, чем копает.
	_tool_button = _make_chip("")
	_tool_button.custom_minimum_size = Vector2(26, STRIP_H)
	_tool_button.expand_icon = true
	_tool_button.pressed.connect(_show_tool_name)
	strip.add_child(_tool_button)

	var gear_box := HBoxContainer.new()
	_gear_pack = _make_gear_icon(gear_box, "res://art/items/backpack_propeller.png")
	_gear_jet = _make_gear_icon(gear_box, "res://art/items/jetpack.png")
	strip.add_child(gear_box)

	# Пустая распорка: слева — то, чем копают, справа — куда ходят. Раньше
	# слабину ряда забирала подпись инструмента, теперь её держит она.
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(spacer)

	# --- экономика: кнопка мастерской (scripts/shop/) ---
	# Одна кнопка на всю экономику: шторка внутри сама делится на продажу,
	# верстак и лавку. Из комнаты мастерской она же открывается вызовом
	# ShopUI.open_workshop() — кнопка нужна, пока дома как сцены нет.
	var shop_btn := _make_chip("")
	if ResourceLoader.exists("res://art/ui/icon_coin.png"):
		shop_btn.icon = load("res://art/ui/icon_coin.png")
		shop_btn.expand_icon = true
		shop_btn.custom_minimum_size = Vector2(24, STRIP_H)
	else:
		shop_btn.text = "Лавка"
	shop_btn.tooltip_text = "Мастерская: продажа, верстак, лавка"
	shop_btn.pressed.connect(func(): ShopUI.open_workshop())
	shop_btn.text = "Мастерская"
	shop_btn.custom_minimum_size = Vector2(0, STRIP_H)
	more_menu.add_child(shop_btn)
	# --- конец блока экономики ---

	# --- прокачка и музей: кнопка экрана героя (scripts/progress/) ---
	# Одна кнопка на три вкладки: прокачка, музей, рекорды. Витрина музея
	# открывается и отдельно — ProgressScreen.open("museum").
	var hero_btn := ProgressScreen.make_hud_button(_make_chip(""))
	if hero_btn.text.is_empty():
		hero_btn.text = "Герой"
	more_menu.add_child(hero_btn)
	# --- конец блока прокачки ---

	# --- дом: контекстная кнопка (scripts/house/) ---
	# Одна кнопка на все действия у дома: войти в дверь, спуститься в люк,
	# съесть еду в шахте. По умолчанию скрыта и занимает место в ряду только
	# когда есть что сделать — постоянной кнопки ряд шириной 224 уже не
	# выдерживает. Текст, видимость и обработку ведёт HouseSystem, поэтому
	# кнопка кладётся в группу, а не связывается здесь.
	var house_btn := _make_chip("Дом")
	house_btn.visible = false
	house_btn.add_to_group("house_button")
	strip.add_child(house_btn)

	# Склад (ГДД п.14) виден ОТКУДА УГОДНО, хоть со дна шахты, — но только
	# на просмотр: игрок должен планировать вылазку, зная, чего не хватает до
	# кирки. Поэтому кнопка постоянная, а не контекстная. Иконкой и без
	# подписи: в ряду шириной 224 на восемь кнопок каждое слово на счету.
	var storage_btn := _make_chip("")
	if ResourceLoader.exists("res://art/ui/icon_blackbox.png"):
		storage_btn.icon = load("res://art/ui/icon_blackbox.png")
		storage_btn.expand_icon = true
		storage_btn.custom_minimum_size = Vector2(20, STRIP_H)
	else:
		storage_btn.text = "Скл"
	storage_btn.tooltip_text = "Склад в мастерской"
	storage_btn.add_to_group("house_storage_button")
	strip.add_child(storage_btn)
	# --- конец блока дома ---

	_mode_button = _make_chip("")
	_mode_button.pressed.connect(_on_mode_button_pressed)
	more_menu.add_child(_mode_button)

	# Стрелка ↺ (U+21BA) отсутствует в шрифте темы по умолчанию и рисуется
	# пустым квадратом — подписываем словом.
	var reset_btn := _make_chip("Сброс")
	reset_btn.pressed.connect(_on_reset_pressed)
	more_menu.add_child(reset_btn)

	# «⋯» встаёт последним, чтобы контекстная кнопка дома, появляясь и
	# исчезая, не сдвигала его под пальцем.
	_more_button = _make_chip("•••")
	_more_button.tooltip_text = "Ещё"
	_more_button.custom_minimum_size = Vector2(26, STRIP_H)
	_more_button.pressed.connect(_toggle_more_menu)
	strip.add_child(_more_button)

	# Любой пункт меню закрывает меню: иначе шторка мастерской открывается
	# поверх ещё раскрытого списка, и он ждёт игрока под ней.
	for item in more_menu.get_children():
		if item is Button:
			(item as Button).pressed.connect(close_more_menu)

	_set_mode("stick")


## Меню «⋯»: то, что нужно на поверхности, а не в шахте.
##
## Всплывает НАД полосой и прижато к правому краю, к своей кнопке. Пока оно
## открыто, ввод в мир глушится (см. _input и update_hold_intent) — иначе
## палец, метящий в пункт меню, попадает в джойстик под ним и герой копает
## под открытым меню.
func _build_more_menu() -> VBoxContainer:
	_more_panel = PanelContainer.new()
	_more_panel.name = "MoreMenu"
	_more_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0x1A, 0x14, 0x0F)
	sb.border_color = Color8(0x3E, 0x31, 0x25)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	_more_panel.add_theme_stylebox_override("panel", sb)
	_more_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_more_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_more_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_more_panel.offset_bottom = -STRIP_H - 2
	_more_panel.offset_right = -4
	add_child(_more_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_more_panel.add_child(box)
	return box


## Всплывающая подпись инструмента: панелька над полосой, по центру, гаснет
## сама через пару секунд. Отдельный узел, а не тост: тост
## занимает всю ширину и перекрывает игровой экран, а тут нужно одно слово
## ровно над кнопкой, по которой ткнули.
func _build_tool_name_popup() -> void:
	_tool_name_panel = PanelContainer.new()
	_tool_name_panel.name = "ToolName"
	_tool_name_panel.visible = false
	_tool_name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0x1A, 0x14, 0x0F)
	sb.border_color = Color8(0x3E, 0x31, 0x25)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	_tool_name_panel.add_theme_stylebox_override("panel", sb)
	# По центру, а не над самой кнопкой: слева внизу лежит джойстик, и
	# подпись садилась ему на край — ровно туда, где в этот момент палец.
	_tool_name_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tool_name_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tool_name_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tool_name_panel.offset_bottom = -STRIP_H - 4
	add_child(_tool_name_panel)

	_tool_name_label = Label.new()
	_tool_name_label.add_theme_font_size_override("font_size", 11)
	_tool_name_panel.add_child(_tool_name_label)

	_tool_name_timer = Timer.new()
	_tool_name_timer.one_shot = true
	_tool_name_timer.wait_time = 2.0
	_tool_name_timer.timeout.connect(func(): _tool_name_panel.visible = false)
	add_child(_tool_name_timer)


func _show_tool_name() -> void:
	_tool_name_label.text = Balance.get_tool_name_ru(GameState.current_tool)
	_tool_name_panel.visible = true
	_tool_name_timer.start()


func _toggle_more_menu() -> void:
	_more_panel.visible = not _more_panel.visible
	if _more_panel.visible:
		# Иначе палец, уже «зажавший» мир, остаётся зажатым под открытым меню:
		# в режиме стика — ручка, в режиме пальца — удержание.
		_release_stick()
		_touch_pointer = -100
		_has_touch = false
		if player != null:
			player.release_control()
			player.digging = null


func close_more_menu() -> void:
	if _more_panel != null:
		_more_panel.visible = false


func is_more_menu_open() -> bool:
	return _more_panel != null and _more_panel.visible


# Кнопка нижней полосы: у темы Godot по умолчанию минимальная высота около
# 40px, а полоса ровно в одну кнопку толщиной (STRIP_H). Поджимаем отступы и
# кегль, иначе ряд вылезает за нижний край экрана.
func _make_chip(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 9)
	b.custom_minimum_size = Vector2(0, STRIP_H)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color8(0x3E, 0x31, 0x25)
		sb.set_border_width_all(1)
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		if state == "pressed" or state == "hover":
			sb.border_color = Color8(0xE0, 0xA9, 0x3B)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color8(0x9D, 0x8B, 0x73))
	b.add_theme_color_override("font_pressed_color", Color8(0xE0, 0xA9, 0x3B))
	b.add_theme_color_override("font_hover_color", Color8(0xE0, 0xA9, 0x3B))
	return b


func _make_gear_icon(parent: Control, path: String) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(17, 17)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(path):
		t.texture = load(path)
	t.modulate = Color(1, 1, 1, 0.22)
	parent.add_child(t)
	return t


# ---------------------------------------------------------------------------
# Layout (пересчитывается при смене размера окна)
# ---------------------------------------------------------------------------

func _update_layout() -> void:
	var vp := get_viewport_rect().size
	# Control, лежащий прямо в CanvasLayer, не наследует размер вьюпорта от
	# родителя — якоря считаются от нулевого прямоугольника, и всё, что
	# прижато к правому краю или к низу, уезжает за экран (кошелёк уходил на
	# x=-100, нижняя полоса — на y=-32). Размер задаём явно.
	position = Vector2.ZERO
	size = vp
	stick_r = maxf(STICK_R_MIN, vp.x * STICK_FRACTION)
	knob_r = stick_r * 0.39
	stage_rect = Rect2(0, 0, vp.x, vp.y - STRIP_H)
	_stick.custom_minimum_size = Vector2(stick_r * 2, stick_r * 2)
	_stick.size = Vector2(stick_r * 2, stick_r * 2)
	_knob.custom_minimum_size = Vector2(knob_r * 2, knob_r * 2)
	_knob.size = Vector2(knob_r * 2, knob_r * 2)
	_knob.position = Vector2(stick_r - knob_r, stick_r - knob_r)
	_stick.position = Vector2(12, stage_rect.size.y - 12 - stick_r * 2)
	_stick_center = _stick.position + Vector2(stick_r, stick_r)
	_stick.queue_redraw()
	_knob.queue_redraw()


func get_view_cells() -> Vector2i:
	var vp := get_viewport_rect().size
	var w: int = maxi(5, int(round(vp.x / TILE)))
	var h: int = maxi(9, int(round((vp.y - STRIP_H) / TILE)))
	return Vector2i(w, h)


# ---------------------------------------------------------------------------
# Игровой цикл: синхронизация полосок/кошелька/глубины/снаряжения
# ---------------------------------------------------------------------------

func _process(_dt: float) -> void:
	if player != null:
		_stick.queue_redraw()
		_knob.queue_redraw()
		_update_depth()


func _connect_game_state() -> void:
	GameState.hp_changed.connect(func(hp, max_hp): _hp_fill.size.x = 72.0 * clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0))
	GameState.hunger_changed.connect(func(h): _hunger_fill.size.x = 72.0 * clampf(h / 100.0, 0.0, 1.0))
	GameState.stamina_changed.connect(func(s): _stamina_fill.size.x = 72.0 * clampf(s / 100.0, 0.0, 1.0))
	GameState.coins_changed.connect(func(_c): _sync_purse())
	GameState.dollars_changed.connect(func(_d): _sync_purse())
	GameState.inventory_changed.connect(func():
		_sync_purse()
		if _inv_sheet.visible:
			_render_inventory()
	)
	GameState.tool_changed.connect(func(_t): _sync_tool())


func _sync_all() -> void:
	_hp_fill.size.x = 72.0
	_hunger_fill.size.x = 72.0
	_stamina_fill.size.x = 72.0
	_sync_purse()
	_sync_tool()


func _sync_purse() -> void:
	_coins_label.text = str(GameState.coins)
	_dollars_label.text = str(GameState.dollars)
	var load_kg := GameState.get_total_weight()
	var max_kg := GameState.get_max_carry_kg()
	_load_label.text = "%.1f / %.0f кг" % [load_kg, max_kg]
	_load_label.add_theme_color_override("font_color",
		Color8(0xB8, 0x5A, 0x52) if load_kg > max_kg * 0.85 else Color8(0x8F, 0xA3, 0x5C))


func _sync_tool() -> void:
	var tool_id := GameState.current_tool
	var tool_name := Balance.get_tool_name_ru(tool_id)
	_tool_button.tooltip_text = tool_name
	var icon_path := "res://art/items/" + _tool_icon_file(tool_id) + ".png"
	if ResourceLoader.exists(icon_path):
		_tool_button.icon = load(icon_path)
	else:
		# Без картинки кнопка была бы пустым прямоугольником — тогда пусть
		# уж подписью, как раньше.
		_tool_button.text = tool_name
	# Инструмент сменился сам (упёрлись в фундамент, дошли до глубины) —
	# показываем название, не дожидаясь, пока игрок ткнёт в иконку.
	if _tool_name_panel != null and _tool_name_panel.visible:
		_tool_name_label.text = tool_name
	if player != null:
		_gear_pack.modulate = Color(1, 1, 1, 1.0 if player.has_backpack() else 0.22)
		_gear_jet.modulate = Color(1, 1, 1, 1.0 if player.has_jetpack() else 0.22)


func _tool_icon_file(tool_id: String) -> String:
	match tool_id:
		"shovel": return "shovel"
		"rusty_pickaxe": return "pickaxe_rusty_cracked" if (player != null and player.rusty_pickaxe_cracked) else "pickaxe_rusty"
		"iron_pickaxe": return "pickaxe_iron"
		"hand_drill": return "hand_drill"
		# Своей иконки у буровой машины нет — на полосе остаётся бур: машина
		# и есть бур, только с кабиной и гусеницами.
		"drill_rig": return "hand_drill"
		_: return "shovel"


func _update_depth() -> void:
	var d: int = player.cell_y()
	if d <= 0:
		_depth_box.visible = false
		return
	_depth_box.visible = true
	_depth_label.text = str(d)
	# см. placeDepth в web-демо: метка стоит на уровне героя на экране.
	var screen_y: float = (player.y - current_cam.y) * TILE
	_depth_box.position.y = clampf(screen_y - 11.0, 0.0, stage_rect.size.y - 22.0)


# ---------------------------------------------------------------------------
# Тосты
# ---------------------------------------------------------------------------

func toast(text: String, seconds: float = 2.6) -> void:
	_toast_label.text = text
	_toast_panel.visible = true
	_toast_timer.start(seconds)


func _on_fell(damage: float, speed: float) -> void:
	if damage > 0.0:
		toast("Удар на скорости %.1f кл/с — минус %d HP" % [speed, int(damage)])


func _on_dig_blocked(tile_type: int) -> void:
	var mineral_id := MineralMap.mineral_id_for(tile_type)
	var name_ru: String = "породу"
	if not mineral_id.is_empty():
		name_ru = String(Balance.get_mineral(mineral_id).get("name_ru", "породу"))
	toast(Balance.get_tool_name_ru(GameState.current_tool) + " звенит о " + name_ru.to_lower() + ". Стан от вибрации.")


func _on_dig_finished(_x: int, _y: int, tile_type: int, mineral_id: String, was_loot: bool, coins: int) -> void:
	if was_loot and coins == 0 and not mineral_id.is_empty():
		toast(Balance.get_mineral(mineral_id).get("name_ru", "Находка") + " — рюкзак полон, пришлось оставить.")
	elif was_loot and coins >= 100:
		toast("%s! +%d монет" % [Balance.get_mineral(mineral_id).get("name_ru", ""), coins])
	if _y == 80 and tile_type == TileTypes.Type.DIAMOND:
		toast("Алмаз замурован в камне. Дедова кирка трескается — минус 25% скорости.", 4.0)


func _on_gear_unlocked(gear_id: String) -> void:
	_sync_tool()
	if gear_id == "backpack":
		toast("Глубина 10. Пригодился ранец с пропеллерами — держи стик вверх в воздухе.", 5.0)
	elif gear_id == "jetpack":
		toast("Глубина 100. Собраны джетпак и ручной бур.", 5.0)
	elif gear_id == "drill_rig":
		toast("Глубина 1000. Собрана буровая машина — копает втрое быстрее бура.", 5.0)


func _on_tool_switched(tool_id: String) -> void:
	_sync_tool()
	_show_tool_name()
	if tool_id == "rusty_pickaxe":
		toast("Лопата упёрлась в старый фундамент. В мастерской нашлась дедова кирка.", 3.6)


# ---------------------------------------------------------------------------
# Кнопки нижней полосы
# ---------------------------------------------------------------------------

func _on_inv_button_pressed() -> void:
	if _inv_sheet.visible:
		close_inventory()
	else:
		open_inventory()


func open_inventory() -> void:
	_release_stick()
	_has_touch = false
	if player != null:
		player.digging = null
		player.release_control()
	_render_inventory()
	_inv_sheet.visible = true
	_inv_button.button_pressed = true


func close_inventory() -> void:
	_close_drop()
	_inv_sheet.visible = false
	_inv_button.button_pressed = false


func _render_inventory() -> void:
	for c in _inv_list.get_children():
		c.queue_free()
	var rows: Array = []
	for id in GameState.inventory.keys():
		var count: int = int(GameState.inventory[id])
		if count <= 0:
			continue
		var price := Balance.get_mineral_price(id)
		rows.append({"id": id, "count": count, "sum": price * count})
	rows.sort_custom(func(a, b): return a.sum > b.sum)

	if rows.is_empty():
		var empty := Label.new()
		empty.text = "Рюкзак пуст.\nЗемля и камень в него не кладутся — только руда и находки."
		empty.add_theme_font_size_override("font_size", 10)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_inv_list.add_child(empty)
		_inv_total_label.text = "0"
	else:
		var total := 0
		for row in rows:
			total += row.sum
			var line := HBoxContainer.new()
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(16, 16)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var tex := TileArt.texture_for(MineralMap.tile_type_for(row.id), 0, 0)
			if tex != null:
				icon.texture = tex
			line.add_child(icon)
			var name_label := Label.new()
			name_label.text = String(Balance.get_mineral(row.id).get("name_ru", row.id))
			name_label.add_theme_font_size_override("font_size", 10)
			name_label.clip_text = true
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(name_label)
			var count_label := Label.new()
			count_label.text = "×%d" % row.count
			count_label.add_theme_font_size_override("font_size", 10)
			line.add_child(count_label)
			var sum_label := Label.new()
			sum_label.text = str(row.sum)
			sum_label.add_theme_font_size_override("font_size", 10)
			sum_label.custom_minimum_size = Vector2(34, 0)
			sum_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			sum_label.add_theme_color_override("font_color", Color8(0xE0, 0xA9, 0x3B))
			line.add_child(sum_label)
			# Выбросить: рюкзак заполняется задолго до подъёма, и без этого
			# единственный способ освободить место под алмаз — идти домой.
			var drop_btn := Button.new()
			drop_btn.text = "×"  # ✕ (U+2715) в шрифте темы отсутствует, см. выше
			drop_btn.tooltip_text = "Выбросить"
			drop_btn.add_theme_font_size_override("font_size", 10)
			drop_btn.custom_minimum_size = Vector2(22, 20)
			var rid: String = row.id
			var rcount: int = row.count
			drop_btn.pressed.connect(func(): _open_drop(rid, rcount))
			line.add_child(drop_btn)
			_inv_list.add_child(line)
		_inv_total_label.text = str(total)

	var load_kg := GameState.get_total_weight()
	var max_kg := GameState.get_max_carry_kg()
	_inv_load_label.text = "%.1f / %.0f кг" % [load_kg, max_kg]


func _on_mode_button_pressed() -> void:
	_set_mode("hold" if mode == "stick" else "stick")


func _set_mode(m: String) -> void:
	mode = m
	_release_stick()
	_has_touch = false
	if player != null:
		player.release_control()
	var is_stick := mode == "stick"
	# Коротко: полная подпись («Джойстик»/«Удержание») не помещается в ряд
	# шириной 224 вместе с инвентарём, инструментом и снаряжением.
	_mode_button.text = "Стик" if is_stick else "Палец"
	_stick.visible = is_stick
	_hold_hint.visible = not is_stick


func _on_reset_pressed() -> void:
	close_inventory()
	GameState.reset_progress()
	if GameState.world_ref != null:
		GameState.world_ref.diffs.clear()
		GameState.world_ref.events.clear()
	if GameState.fog_ref != null:
		GameState.fog_ref.reset_all()
	if player != null:
		player.teleport_home()
		player.rusty_pickaxe_cracked = false
	toast("Бабка улетела в Таиланд. Огород твой.")


# ---------------------------------------------------------------------------
# Ввод: джойстик и удержание пальца (портировано из web/index.html)
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if player == null or _inv_sheet.visible or ProgressScreen.is_open() or is_more_menu_open():
		return

	if mode == "stick":
		_handle_stick_input(event)
	else:
		_handle_hold_input(event)


## Приводит мышь/тач-события к одному виду: {kind:"press"|"release"|"move",
## pos:Vector2, pid:int}. kind="" — событие не касается указателя (игнорируем).
## Нужно, чтобы не завязываться на статическое сужение типов GDScript при
## разборе разных подклассов InputEvent в одной ветке if.
static func _normalize_pointer_event(event: InputEvent) -> Dictionary:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return {"kind": ""}
		return {"kind": "press" if mb.pressed else "release", "pos": mb.position, "pid": -1}
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		return {"kind": "press" if st.pressed else "release", "pos": st.position, "pid": st.index}
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		return {"kind": "move", "pos": mm.position, "pid": -1}
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		return {"kind": "move", "pos": sd.position, "pid": sd.index}
	return {"kind": ""}


func _handle_stick_input(event: InputEvent) -> void:
	var e := _normalize_pointer_event(event)
	match e.kind:
		"press":
			if _stick_pointer != -100:
				return
			if e.pos.distance_to(_stick_center) > stick_r * 1.6:
				return
			_stick_pointer = e.pid
			_apply_stick(e.pos)
			get_viewport().set_input_as_handled()
		"release":
			if e.pid == _stick_pointer:
				_release_stick()
				get_viewport().set_input_as_handled()
		"move":
			if e.pid == _stick_pointer:
				_apply_stick(e.pos)
				get_viewport().set_input_as_handled()


func _apply_stick(screen_pos: Vector2) -> void:
	var v: Vector2 = (screen_pos - _stick_center) / stick_r
	if v.length() > 1.0:
		v = v.normalized()
	var snap = player.resolve_dir(v.x, v.y, STICK_DEAD)
	_position_knob(snap)
	player.cancel_wrong_dig()


func _position_knob(snap) -> void:
	var base: Vector2 = Vector2(stick_r - knob_r, stick_r - knob_r)
	if snap == null:
		_knob.position = base
	else:
		_knob.position = base + Vector2(snap.x, snap.y) * 34.0


func _release_stick() -> void:
	_stick_pointer = -100
	if player != null:
		player.release_control()
	_position_knob(null)


func _handle_hold_input(event: InputEvent) -> void:
	var e := _normalize_pointer_event(event)
	match e.kind:
		"press":
			if _touch_pointer != -100:
				return
			if not stage_rect.has_point(e.pos):
				return
			_touch_pointer = e.pid
			_touch_pos = e.pos
			_has_touch = true
			get_viewport().set_input_as_handled()
		"release":
			if e.pid == _touch_pointer:
				_touch_pointer = -100
				_has_touch = false
				player.release_control()
				player.digging = null
				get_viewport().set_input_as_handled()
		"move":
			if e.pid == _touch_pointer:
				_touch_pos = e.pos
				get_viewport().set_input_as_handled()


## Пересчитывает намерение удержания каждый физический кадр (см.
## readHoldIntent в web-демо) — вызывается из main.gd перед player.physics_tick.
func update_hold_intent() -> void:
	if mode != "hold" or player == null or ProgressScreen.is_open() or is_more_menu_open():
		return
	if not _has_touch:
		player.resolve_dir(0.0, 0.0, 1.0)
		return
	var wx: float = current_cam.x + _touch_pos.x / TILE
	var wy: float = current_cam.y + _touch_pos.y / TILE
	player.resolve_dir(wx - player.x, wy - player.y, 0.45)
	player.cancel_wrong_dig()


func set_camera(cam: Vector2) -> void:
	current_cam = cam

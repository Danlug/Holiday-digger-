class_name BackpackSheet
extends Control
## BackpackSheet — шторка рюкзака: сетка плиток-слотов вместо списка строк.
##
## Слот — иконка предмета, число штук значком в углу, цвет рамки — редкость
## (по цене за штуку). Название, вес и стоимость — в подсказке Tip (наведение
## мышью или долгое нажатие пальцем). Нажатие выбирает слот; внизу — итог
## «к продаже» (иконка монеты и число с накруткой) и кнопки выбранной стопки:
## «съесть» (для еды) и «выбросить» (корзина). «Сколько выбросить» — отдельное
## окно: ползунок, шаги ± и то же число полем с цифровой клавиатурой.
##
## Правила ГДД п.14/16, которые здесь соблюдены: пока шторка открыта, герой
## стоит (HUD глушит ввод); список прокручивается перетаскиванием (DragScroll);
## окно «сколько» закрывается тапом за границей (HUD спрашивает drop_card_rect()).
##
## Сам рюкзак шторка не меняет: «съесть» и «выбросить» — сигналы, а действие и
## тост делает HUD.

signal closed
signal eat_pressed(id: String)
signal drop_confirmed(id: String, count: int)

const SLOT := 44.0
const COLS := 4
const MIN_SLOTS := 12
const MAX_BADGE := 999

## Цвета редкости: обычная, необычная, редкая, эпическая, легендарная.
const TIER_COLORS: Array[Color] = [
	Color8(0x75, 0x6B, 0x5E), Color8(0x6E, 0xA8, 0x5A), Color8(0x5B, 0x8F, 0xD0),
	Color8(0xA2, 0x6B, 0xD6), Color8(0xE0, 0xA9, 0x3B)]
const GOLD := Color8(0xE0, 0xA9, 0x3B)
const CARD_BG := Color8(0x1A, 0x14, 0x0F)
const EDGE := Color8(0x52, 0x40, 0x2D)

var _dim: ColorRect
var _card: PanelContainer
var _grid: GridContainer
var _scroll: ScrollContainer
var _weight_bar: HudBar
var _weight_text: Label
var _total_pill: HudPill
var _eat_btn: Button
var _drop_btn: Button
var _empty_hint: TextureRect

var _selected: String = ""
var _rows: Array = []
var _slot_buttons: Dictionary = {}

# --- окно «сколько» ---
var _drop_panel: Control
var _drop_card: PanelContainer
var _drop_icon: TextureRect
var _drop_count_label: Label
var _drop_slider: HSlider
var _drop_field: LineEdit
var _drop_id: String = ""
var _drop_max: int = 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


# ---------------------------------------------------------------------------
# Публичное
# ---------------------------------------------------------------------------

func is_open() -> bool:
	return visible


func open() -> void:
	refresh()
	visible = true
	Sfx.play("ui_open")
	if _card != null and is_inside_tree():
		UiAnim.slide_up(_card, 28.0, 0.2)
		_dim.modulate.a = 1.0


func close() -> void:
	close_drop()
	var was := visible
	visible = false
	_selected = ""
	if was:
		Sfx.play("ui_close")
	closed.emit()


func is_drop_open() -> bool:
	return _drop_panel != null and _drop_panel.visible


func drop_card_rect() -> Rect2:
	return Rect2(_drop_card.global_position, _drop_card.size)


func selected_id() -> String:
	return _selected


func slot_count() -> int:
	return _slot_buttons.size()


## Перерисовывает слоты и итоги по GameState.inventory.
func refresh() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_slot_buttons.clear()
	_rows.clear()
	for id in GameState.inventory.keys():
		var count: int = int(GameState.inventory[id])
		if count <= 0:
			continue
		var price := Balance.get_mineral_price(id)
		_rows.append({"id": id, "count": count, "price": price, "sum": price * count,
			"weight": Balance.get_mineral_weight(id)})
	_rows.sort_custom(func(a, b): return a.sum > b.sum if a.sum != b.sum else String(a.id) < String(b.id))

	if _selected != "" and not _rows.any(func(r): return r.id == _selected):
		_selected = ""

	var total := 0
	for row in _rows:
		total += int(row.sum)
		var slot := _make_slot(row)
		_grid.add_child(slot)
		_slot_buttons[row.id] = slot
	var slots := maxi(MIN_SLOTS, int(ceil(float(_rows.size()) / COLS)) * COLS)
	for i in range(_rows.size(), slots):
		_grid.add_child(_make_empty_slot())
	_empty_hint.visible = _rows.is_empty()

	var load_kg := GameState.get_total_weight()
	var max_kg := maxf(GameState.get_max_carry_kg(), 0.001)
	var frac := load_kg / max_kg
	_weight_bar.set_fraction(minf(frac, 1.0))
	_weight_bar.fill_color = Color8(0x7F, 0xB8, 0x6B) if frac < 0.6 \
		else (Color8(0xE0, 0xA9, 0x3B) if frac < 0.85 else Color8(0xD9, 0x4F, 0x4A))
	_weight_text.text = "%.1f/%.0f" % [load_kg, max_kg]
	Tip.bind(_weight_bar, "Вес рюкзака", "%.1f из %.0f кг" % [load_kg, max_kg])
	_total_pill.set_value(total)
	Tip.bind(_total_pill, "К продаже", CountLabel.group_digits(total) + " монет в мастерской")
	_refresh_actions()


## Окно «выбросить N штук». Ползунок и то же число полем ввода — на телефоне
## ползунком трудно попасть в «ровно 7 из 240», а руками неудобно набирать
## «120». Поле открывает цифровую клавиатуру, буквы в нём не принимаются.
func open_drop(id: String, count: int) -> void:
	if count <= 0:
		return
	_drop_id = id
	_drop_max = count
	_drop_icon.texture = UiIcons.item(id)
	Tip.bind(_drop_icon, String(Balance.get_mineral(id).get("name_ru", id)),
		"В рюкзаке: %d" % count)
	_drop_count_label.text = "×%d" % count
	_drop_slider.max_value = count
	_drop_slider.value = count
	_drop_field.text = str(count)
	_drop_panel.visible = true
	Sfx.play("ui_open")
	if is_inside_tree():
		UiAnim.appear(_drop_card, 0.9, 0.14)


func close_drop() -> void:
	if _drop_panel != null and _drop_panel.visible:
		Sfx.play("ui_close")
	if _drop_panel != null:
		_drop_panel.visible = false
	_drop_id = ""


func drop_amount() -> int:
	return clampi(int(_drop_slider.value), 1, maxi(1, _drop_max))


func apply_drop() -> void:
	if _drop_id.is_empty():
		return
	var n := drop_amount()
	var id := _drop_id
	close_drop()
	drop_confirmed.emit(id, n)


## Редкость 0..4 по цене за штуку; у находок без цены (артефактные материалы
## глубин) — эпическая, у еды и топлива — обычная.
static func tier_of(id: String) -> int:
	if HouseConfig.is_food(id) or id == "fuel_block":
		return 0
	var p := Balance.get_mineral_price(id)
	if p <= 0:
		return 3
	if p <= 10:
		return 0
	if p <= 40:
		return 1
	if p <= 200:
		return 2
	if p <= 800:
		return 3
	return 4


# ---------------------------------------------------------------------------
# Сборка
# ---------------------------------------------------------------------------

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_card = PanelContainer.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.offset_top = 22.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = EDGE
	sb.border_width_top = 2
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 6
	_card.add_theme_stylebox_override("panel", sb)
	add_child(_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_card.add_child(box)

	# --- шапка: рюкзак, вес, закрыть ---
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	var bag := TextureRect.new()
	bag.texture = UiIcons.tex("backpack")
	bag.custom_minimum_size = Vector2(20, 20)
	bag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(bag)
	_weight_bar = HudBar.new().setup(Color8(0x7F, 0xB8, 0x6B), UiIcons.tex("weight"))
	_weight_bar.bar_width = 84.0
	_weight_bar.pulse_above = 1.0
	_weight_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_weight_bar)
	_weight_text = Label.new()
	_weight_text.add_theme_font_size_override("font_size", 10)
	_weight_text.add_theme_color_override("font_color", Color8(0xB4, 0xA3, 0x88))
	_weight_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_weight_text)
	var close_btn := UiBtn.icon_button(UiIcons.tex("close"), Vector2(28, 26), UiBtn.Kind.GHOST)
	Tip.bind(close_btn, "Закрыть")
	close_btn.pressed.connect(func():
		if Tip.swallowed():
			return
		close())
	head.add_child(close_btn)

	# --- сетка слотов ---
	# Область — обычный Control: ScrollContainer сам раскладывает детей и
	# подсказке «пусто» в нём не место, а поверх прокрутки она встаёт якорями.
	var area := Control.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(area)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	area.add_child(_scroll)
	# Прокрутка перетаскиванием списка, а не только ползунком (решение владельца).
	DragScroll.attach(_scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	center.add_child(_grid)

	_empty_hint = TextureRect.new()
	_empty_hint.texture = UiIcons.tex("backpack")
	_empty_hint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_empty_hint.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_empty_hint.modulate = Color(1, 1, 1, 0.32)
	_empty_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	_empty_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_empty_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_empty_hint.offset_left = -16.0
	_empty_hint.offset_right = 16.0
	_empty_hint.offset_top = 56.0
	_empty_hint.offset_bottom = 88.0
	Tip.bind(_empty_hint, "Рюкзак пуст", "Земля и камень в него не кладутся — только руда и находки")
	area.add_child(_empty_hint)
	_empty_hint.visible = false

	# --- низ: итог и кнопки выбранной стопки ---
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	foot.custom_minimum_size = Vector2(0, 32)
	box.add_child(foot)
	_total_pill = HudPill.new().setup(UiIcons.tex("coin"), GOLD)
	_total_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_total_pill)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(sp)
	_eat_btn = UiBtn.icon_button(UiIcons.tex("eat"), Vector2(34, 30), UiBtn.Kind.ACCENT)
	Tip.bind(_eat_btn, "Съесть", "Голод и бодрость вернутся")
	_eat_btn.pressed.connect(func():
		if Tip.swallowed() or _selected == "":
			return
		eat_pressed.emit(_selected))
	foot.add_child(_eat_btn)
	_drop_btn = UiBtn.icon_button(UiIcons.tex("trash"), Vector2(34, 30), UiBtn.Kind.DANGER)
	Tip.bind(_drop_btn, "Выбросить", "Выбери стопку, потом корзину")
	_drop_btn.pressed.connect(func():
		if Tip.swallowed():
			return
		if _selected == "":
			UiAnim.shake(_drop_btn)
			Sfx.play("ui_deny")
			return
		open_drop(_selected, int(GameState.inventory.get(_selected, 0))))
	foot.add_child(_drop_btn)

	_build_drop_panel()


func _make_slot(row: Dictionary) -> Button:
	var id: String = row.id
	var tier := tier_of(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(SLOT, SLOT)
	b.focus_mode = Control.FOCUS_NONE
	b.icon = UiIcons.item(id)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 32)
	_style_slot(b, tier, id == _selected)
	UiBtn.wire_feedback(b)

	if int(row.count) > 1:
		var badge := Label.new()
		badge.text = str(row.count) if int(row.count) <= MAX_BADGE else "%d+" % MAX_BADGE
		badge.add_theme_font_size_override("font_size", 10)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		badge.add_theme_constant_override("outline_size", 3)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
		badge.offset_right = -3.0
		badge.offset_bottom = 0.0
		b.add_child(badge)

	var name_ru := String(Balance.get_mineral(id).get("name_ru", id))
	if HouseConfig.is_food(id):
		name_ru = HouseConfig.food_name(id)
	var weight := float(row.weight)
	Tip.bind(b, name_ru,
		"%d шт · %.1f кг" % [row.count, weight * int(row.count)],
		("%s за штуку · всего %s" % [CountLabel.group_digits(int(row.price)),
			CountLabel.group_digits(int(row.sum))]) if int(row.price) > 0 else "Не продаётся")
	b.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		_select(id))
	return b


func _style_slot(b: Button, tier: int, selected: bool) -> void:
	var col := TIER_COLORS[tier]
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.bg_color = Color(col.r * 0.28 + 0.05, col.g * 0.28 + 0.04, col.b * 0.28 + 0.03)
		sb.border_color = col
		sb.set_border_width_all(1)
		sb.set_content_margin_all(2)
		if selected:
			sb.border_color = GOLD
			sb.set_border_width_all(2)
			sb.bg_color = sb.bg_color.lightened(0.18)
		elif state == "hover" or state == "pressed" or state == "hover_pressed":
			sb.border_color = col.lightened(0.35)
			sb.bg_color = sb.bg_color.lightened(0.1)
		b.add_theme_stylebox_override(state, sb)


func _make_empty_slot() -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(SLOT, SLOT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.06)
	sb.border_color = Color(0.2, 0.16, 0.12)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _select(id: String) -> void:
	_selected = "" if _selected == id else id
	for rid in _slot_buttons.keys():
		_style_slot(_slot_buttons[rid], tier_of(rid), rid == _selected)
	_refresh_actions()


func _refresh_actions() -> void:
	var has := _selected != ""
	_drop_btn.modulate = Color(1, 1, 1, 1.0 if has else 0.4)
	_eat_btn.visible = has and HouseConfig.is_food(_selected)


# --- окно «сколько» -------------------------------------------------------

func _build_drop_panel() -> void:
	_drop_panel = Control.new()
	_drop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drop_panel.visible = false
	add_child(_drop_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drop_panel.add_child(dim)

	_drop_card = PanelContainer.new()
	_drop_card.set_anchors_preset(Control.PRESET_CENTER)
	_drop_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_drop_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_drop_card.custom_minimum_size = Vector2(190, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = Color8(0xB8, 0x5A, 0x52)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 6
	_drop_card.add_theme_stylebox_override("panel", sb)
	_drop_panel.add_child(_drop_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_drop_card.add_child(box)

	# Предмет и сколько его всего: иконка, «×N» и корзина — без слов.
	var title := HBoxContainer.new()
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_theme_constant_override("separation", 6)
	box.add_child(title)
	var trash := TextureRect.new()
	trash.texture = UiIcons.tex("trash")
	trash.custom_minimum_size = Vector2(16, 16)
	trash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	trash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(trash)
	_drop_icon = TextureRect.new()
	_drop_icon.custom_minimum_size = Vector2(32, 32)
	_drop_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drop_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drop_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	title.add_child(_drop_icon)
	_drop_count_label = Label.new()
	_drop_count_label.add_theme_font_size_override("font_size", 14)
	_drop_count_label.add_theme_color_override("font_color", GOLD)
	_drop_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_child(_drop_count_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var minus := UiBtn.icon_button(UiIcons.tex("minus"), Vector2(26, 26))
	minus.pressed.connect(func(): _drop_slider.value = maxf(1.0, _drop_slider.value - 1.0))
	row.add_child(minus)
	_drop_slider = HSlider.new()
	_drop_slider.min_value = 1
	_drop_slider.step = 1
	_drop_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_drop_slider.custom_minimum_size = Vector2(0, 22)
	UiBtn.style_slider(_drop_slider, Color8(0xB8, 0x5A, 0x52))
	_drop_slider.value_changed.connect(_on_drop_slider_changed)
	row.add_child(_drop_slider)
	var plus := UiBtn.icon_button(UiIcons.tex("plus"), Vector2(26, 26))
	plus.pressed.connect(func(): _drop_slider.value = minf(float(_drop_max), _drop_slider.value + 1.0))
	row.add_child(plus)

	var field_row := HBoxContainer.new()
	field_row.add_theme_constant_override("separation", 6)
	box.add_child(field_row)
	_drop_field = LineEdit.new()
	_drop_field.custom_minimum_size = Vector2(0, 28)
	_drop_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drop_field.max_length = 6
	_drop_field.add_theme_font_size_override("font_size", 14)
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.06, 0.05, 0.04)
	fsb.border_color = EDGE
	fsb.set_border_width_all(1)
	fsb.set_corner_radius_all(6)
	fsb.set_content_margin_all(4)
	_drop_field.add_theme_stylebox_override("normal", fsb)
	var fsb2 := fsb.duplicate() as StyleBoxFlat
	fsb2.border_color = GOLD
	_drop_field.add_theme_stylebox_override("focus", fsb2)
	# Только цифровая клавиатура: количество — всегда целое, буквам тут
	# делать нечего (то же, что inputmode="numeric" в web-демо).
	_drop_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_drop_field.text_changed.connect(_on_drop_field_changed)
	_drop_field.text_submitted.connect(func(_t): apply_drop())
	field_row.add_child(_drop_field)
	var all_btn := UiBtn.icon_button(null, Vector2(40, 28))
	all_btn.text = "Всё"
	all_btn.add_theme_font_size_override("font_size", 10)
	Tip.bind(all_btn, "Все", "Выбросить всю стопку")
	all_btn.pressed.connect(func(): _drop_slider.value = _drop_max)
	field_row.add_child(all_btn)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var cancel := UiBtn.icon_button(UiIcons.tex("close"), Vector2(0, 30))
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Tip.bind(cancel, "Отмена")
	cancel.pressed.connect(func():
		if Tip.swallowed():
			return
		close_drop())
	buttons.add_child(cancel)
	var ok := UiBtn.icon_button(UiIcons.tex("trash"), Vector2(0, 30), UiBtn.Kind.DANGER)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Tip.bind(ok, "Выбросить")
	ok.pressed.connect(func():
		if Tip.swallowed():
			return
		apply_drop())
	buttons.add_child(ok)


func _on_drop_slider_changed(v: float) -> void:
	var n := clampi(int(v), 1, maxi(1, _drop_max))
	if _drop_field.text != str(n):
		_drop_field.text = str(n)
	Haptics.tap()


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

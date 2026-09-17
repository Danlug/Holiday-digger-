extends CanvasLayer
## HouseStorageView — панель склада (сцена scenes/house_storage.tscn).
##
## Одна и та же панель работает в двух режимах, и переключает их не вызывающий
## код, а само правило ГДД п.14: «показать везде, взять только подойдя».
##   — открыта из шахты: список только читается, кнопки погашены и подписано,
##     почему. Смотреть издалека нужно, чтобы планировать вылазку, зная,
##     чего не хватает до следующей кирки;
##   — открыта у самого склада в мастерской: работают «Сложить всё» и «Взять».
##
## Панель выше интерьера дома, но ниже сюжетных модалок: она обычный экран,
## а не событие.

signal closed

const BG := Color8(0x14, 0x0F, 0x0B)
const PANEL_BG := Color8(0x1E, 0x18, 0x11)
const PANEL_BORDER := Color8(0x3E, 0x31, 0x25)
const ACCENT := Color8(0xE0, 0xA9, 0x3B)
const DIM := Color8(0x9D, 0x8B, 0x73)
const FAINT := Color8(0x6B, 0x5B, 0x45)

var _root: Control
var _summary: Label
var _hint: Label
var _list: VBoxContainer
var _put_all: Button
var _signature: String = ""


func _ready() -> void:
	layer = 12
	_build()
	visible = false


func _build() -> void:
	_root = _need(self, "Root", Control) as Control
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := _need(_root, "Backdrop", ColorRect) as ColorRect
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(BG.r, BG.g, BG.b, 0.97)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var head := _need(_root, "Head", HBoxContainer) as HBoxContainer
	head.anchor_right = 1.0
	head.offset_left = 8
	head.offset_right = -8
	head.offset_top = 6
	head.offset_bottom = 28

	var title := _need(head, "Title", Label) as Label
	title.text = "СКЛАД"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var close := _need(head, "Close", Button) as Button
	# Словом, а не крестиком: символа ✕ в шрифте темы нет, вместо него
	# рисуется пустой квадрат с кодом.
	close.text = "Назад"
	close.custom_minimum_size = Vector2(44, 22)
	_style_button(close)
	close.pressed.connect(func(): close_panel())

	_summary = _need(_root, "Summary", Label) as Label
	_summary.anchor_right = 1.0
	_summary.offset_left = 8
	_summary.offset_right = -8
	_summary.offset_top = 30
	_summary.add_theme_font_size_override("font_size", 9)
	_summary.add_theme_color_override("font_color", DIM)

	_hint = _need(_root, "Hint", Label) as Label
	_hint.anchor_right = 1.0
	_hint.offset_left = 8
	_hint.offset_right = -8
	_hint.offset_top = 44
	_hint.offset_bottom = 70
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint.add_theme_font_size_override("font_size", 8)
	_hint.add_theme_color_override("font_color", FAINT)

	var scroll := _need(_root, "Scroll", ScrollContainer) as ScrollContainer
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8
	scroll.offset_right = -8
	scroll.offset_top = 72
	scroll.offset_bottom = -34
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Прокрутка перетаскиванием списка (решение владельца). _need переиспользует
	# узел между открытиями, поэтому вешаем один раз.
	if scroll.get_node_or_null("DragScroll") == null:
		DragScroll.attach(scroll)

	_list = _need(scroll, "List", VBoxContainer) as VBoxContainer
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)

	_put_all = _need(_root, "PutAll", Button) as Button
	_put_all.anchor_top = 1.0
	_put_all.anchor_bottom = 1.0
	_put_all.anchor_right = 1.0
	_put_all.offset_left = 8
	_put_all.offset_right = -8
	_put_all.offset_top = -30
	_put_all.offset_bottom = -6
	_style_button(_put_all)
	_put_all.text = "Сложить весь рюкзак"
	_put_all.pressed.connect(_on_put_all)


func open() -> void:
	visible = true
	_signature = ""
	refresh()


func close_panel() -> void:
	visible = false
	closed.emit()


func refresh() -> void:
	if not visible:
		return
	var accessible := HouseStorage.can_access()
	_summary.text = "Позиций: %d  ·  вес: %.0f кг  ·  рюкзак: %.0f/%.0f кг" % [
		HouseStorage.total_items(), HouseStorage.total_weight(),
		GameState.get_total_weight(), GameState.get_max_carry_kg()]
	_hint.text = "Верстак берёт материалы прямо отсюда." if accessible \
		else HouseStorage.access_reason()
	_put_all.disabled = not accessible or GameState.inventory.is_empty()

	# Список пересобирается только при изменениях: кнопка «Взять», удалённая
	# и созданная заново между нажатием и отпусканием пальца, не срабатывает.
	var rows := HouseStorage.rows()
	var signature := "%s|%s|%s" % [str(rows), accessible, str(GameState.inventory)]
	if signature == _signature:
		return
	_signature = signature

	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	if rows.is_empty():
		var empty := Label.new()
		empty.text = "Склад пуст.\nПринеси руду домой и сложи её здесь — из рюкзака в 60 кг кирку не собрать."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.add_theme_font_size_override("font_size", 9)
		empty.add_theme_color_override("font_color", FAINT)
		_list.add_child(empty)
		return

	for row in rows:
		_list.add_child(_make_row(row, accessible))


func _make_row(row: Dictionary, accessible: bool) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = String(row["name"])
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(60, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 9)
	line.add_child(name_label)

	var count_label := Label.new()
	count_label.text = "×%d" % int(row["count"])
	count_label.add_theme_font_size_override("font_size", 9)
	count_label.add_theme_color_override("font_color", ACCENT)
	line.add_child(count_label)

	var weight_label := Label.new()
	weight_label.text = "%.0f кг" % float(row["weight"])
	weight_label.custom_minimum_size = Vector2(36, 0)
	weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weight_label.add_theme_font_size_override("font_size", 8)
	weight_label.add_theme_color_override("font_color", FAINT)
	line.add_child(weight_label)

	var id := String(row["id"])
	var take_one := Button.new()
	take_one.text = "Взять"
	take_one.custom_minimum_size = Vector2(38, 18)
	_style_button(take_one)
	take_one.disabled = not accessible
	take_one.pressed.connect(func(): _on_take(id, 1))
	line.add_child(take_one)

	var take_all := Button.new()
	take_all.text = "всё"
	take_all.custom_minimum_size = Vector2(28, 18)
	_style_button(take_all)
	take_all.disabled = not accessible
	take_all.pressed.connect(func(): _on_take(id, int(row["count"])))
	line.add_child(take_all)
	return line


func _on_take(id: String, amount: int) -> void:
	var taken := HouseStorage.take(id, amount)
	if taken <= 0:
		_hint.text = HouseStorage.access_reason() if not HouseStorage.can_access() \
			else "Рюкзак больше не тянет."
	_signature = ""
	refresh()


func _on_put_all() -> void:
	var moved := HouseStorage.put_all()
	if moved > 0:
		_hint.text = "На склад ушло позиций: %d." % moved
	_signature = ""
	refresh()


func _need(parent: Node, name: String, type) -> Node:
	var existing := parent.get_node_or_null(NodePath(name))
	if existing != null:
		return existing
	var node = type.new()
	node.name = name
	parent.add_child(node)
	return node


func _style_button(b: Button) -> void:
	b.add_theme_font_size_override("font_size", 9)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = PANEL_BORDER if state != "pressed" else ACCENT
		sb.set_border_width_all(1)
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", FAINT)

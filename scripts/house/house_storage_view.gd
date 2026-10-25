extends CanvasLayer
## HouseStorageView — склад в мастерской (сцена scenes/house_storage.tscn).
##
## Вид как у витрины магазина: сверху фишки «сколько на складе» и «рюкзак N/M»,
## красный крестик справа; в середине — сетка плиток склада и, у склада, сетка
## плиток рюкзака; снизу две большие кнопки «забрать всё» и «сложить рюкзак».
## Текста нет: название, вес и «что будет по тапу» — в подсказке Tip плитки.
## Тап по плитке открывает окно «сколько» (HouseQtyCard).
##
## Одна и та же панель работает в двух режимах, и переключает их не вызывающий
## код, а само правило ГДД п.14: «показать везде, взять только подойдя».
##   — открыта из шахты: склад только смотрят. Плитки приглушены с замком,
##     рюкзака нет, кнопки закрыты замком, причина — в Tip. Смотреть издалека
##     нужно, чтобы планировать вылазку, зная, чего не хватает до кирки;
##   — открыта у самого склада в мастерской: работают плитки и обе кнопки.
##
## Панель выше интерьера дома, но ниже сюжетных модалок: она обычный экран,
## а не событие. Всё строится кодом в _ready (сцена — голый корень со скриптом):
## в .tscn узлы со скриптом при загрузке собрали бы себя повторно.

signal closed

const HEAD_H := 32.0
const ACTION_H := 46.0
const LINE_COL := Color8(0x4A, 0x3F, 0x5C)

var _root: Control
var _scroll: ScrollContainer
var _list: VBoxContainer
var _drag: DragScroll
var _chip_items: Dictionary = {}
var _chip_load: Dictionary = {}
var _close_btn: Button
var _take_btn: Button
var _put_btn: Button
var _take_lock: TextureRect
var _put_lock: TextureRect
var _qty: HouseQtyCard
var _signature: String = ""
var _head_sig: String = ""
var _tiles: Dictionary = {}
var _qty_target: Dictionary = {}
var _take_ok := false
var _put_ok := false


func _ready() -> void:
	layer = 12
	_build()
	visible = false


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color8(0x26, 0x1E, 0x30), Color8(0x14, 0x0F, 0x1B)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 64
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = HEAD_H + 2.0
	_scroll.offset_bottom = -ACTION_H
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 10)
	_scroll.add_child(margin)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	margin.add_child(_list)
	_drag = DragScroll.attach(_scroll)

	_build_header()
	_build_actions()

	_qty = HouseQtyCard.new()
	_root.add_child(_qty)
	_qty.confirmed.connect(_on_qty_confirmed)
	_qty.cancelled.connect(func() -> void: _drag.set_process_input(true))


func _build_header() -> void:
	var line := ColorRect.new()
	line.color = LINE_COL
	line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	line.offset_top = HEAD_H
	line.offset_bottom = HEAD_H + 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(line)

	_chip_items = _make_chip(UiIcons.tex("inventory"), 84.0, Vector2(6, 6))
	_chip_load = _make_chip(ShopArt.ui("icon_backpack"), 78.0, Vector2(94, 6))

	_close_btn = HouseArt.button("red", ShopArt.tex("glyph_cross"), Vector2(32, 24), 14.0)
	_close_btn.anchor_left = 1.0
	_close_btn.anchor_right = 1.0
	_close_btn.offset_left = -38.0
	_close_btn.offset_right = -6.0
	_close_btn.offset_top = 4.0
	_close_btn.offset_bottom = 28.0
	_close_btn.pressed.connect(func() -> void:
		if not Tip.swallowed():
			close_panel())
	Tip.bind(_close_btn, "Закрыть")
	_root.add_child(_close_btn)


func _make_chip(icon: Texture2D, w: float, pos: Vector2) -> Dictionary:
	var root := Control.new()
	root.position = pos
	root.size = Vector2(w, 20)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(HouseArt.nine("pill", 4))
	var ic := ShopArt.rect(icon, Vector2(3, 3), Vector2(14, 14))
	root.add_child(ic)
	var lb := ShopArt.label("", 10)
	lb.position = Vector2(20, 1)
	lb.size = Vector2(w - 24.0, 18)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.clip_text = true
	root.add_child(lb)
	_root.add_child(root)
	return {"root": root, "icon": ic, "label": lb}


func _build_actions() -> void:
	var bar := Control.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -ACTION_H
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bar)
	var line := ColorRect.new()
	line.color = LINE_COL
	line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	line.offset_bottom = 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(line)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.offset_top = 6.0
	bar.add_child(row)

	_take_btn = HouseArt.button("gold", HouseArt.tex("take_all"), Vector2(96, 34), 24.0)
	_take_btn.pressed.connect(_on_take_all)
	row.add_child(_take_btn)
	_take_lock = ShopArt.rect(ShopArt.tex("glyph_lock"), Vector2(78, 16), Vector2(16, 16))
	_take_btn.add_child(_take_lock)
	_put_btn = HouseArt.button("green", HouseArt.tex("put_all"), Vector2(96, 34), 24.0)
	_put_btn.pressed.connect(_on_put_all)
	row.add_child(_put_btn)
	_put_lock = ShopArt.rect(ShopArt.tex("glyph_lock"), Vector2(78, 16), Vector2(16, 16))
	_put_btn.add_child(_put_lock)


# ---------------------------------------------------------------------------
# Открытие и закрытие
# ---------------------------------------------------------------------------

func open() -> void:
	visible = true
	_signature = ""
	_head_sig = ""
	_qty.visible = false
	_drag.set_process_input(true)
	_scroll.scroll_vertical = 0
	Sfx.play("ui_open")
	Haptics.tap()
	refresh()


func close_panel() -> void:
	if not visible:
		return
	if _qty != null:
		_qty.visible = false
	visible = false
	Tip.hide_all()
	Sfx.play("ui_close")
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _qty != null and _qty.is_open():
		_qty.cancel_card()
	else:
		close_panel()


# ---------------------------------------------------------------------------
# Содержимое
# ---------------------------------------------------------------------------

func refresh() -> void:
	if not visible:
		return
	var accessible := HouseStorage.can_access()
	var rows := HouseStorage.rows()
	var carried := GameState.get_total_weight()
	var cap := GameState.get_max_carry_kg()

	# Фишки и кнопки обновляем, только когда поменялись числа: refresh() зовут
	# каждый кадр, а Tip.bind перерисовывает показанную подсказку при каждом вызове.
	var head_sig := "%d|%d|%d|%d|%s|%d|%d" % [HouseStorage.total_items(), int(round(HouseStorage.total_weight())),
		int(round(carried)), int(round(cap)), accessible, rows.size(), GameState.inventory.size()]
	if head_sig != str(_head_sig):
		_head_sig = head_sig
		(_chip_items["label"] as Label).text = ShopArt.compact(HouseStorage.total_items())
		Tip.bind(_chip_items["root"], "Склад", "Что лежит в мастерской. Верстак берёт материалы прямо отсюда.",
			"%s шт · %s кг" % [ShopArt.full(HouseStorage.total_items()), ShopArt.full(int(round(HouseStorage.total_weight())))])
		var load_label := _chip_load["label"] as Label
		load_label.text = "%s/%s" % [ShopArt.compact(int(round(carried))), ShopArt.compact(int(round(cap)))]
		load_label.label_settings.font_color = ShopArt.COL_BAD if carried >= cap - 0.001 else Color.WHITE
		Tip.bind(_chip_load["root"], "Рюкзак", "Сколько несёшь из скольки можно унести.",
			"%s из %s кг" % [ShopArt.full(int(round(carried))), ShopArt.full(int(round(cap)))])
		_update_actions(accessible, rows)

	# Список пересобирается только при изменениях: плитка, удалённая и созданная
	# заново между нажатием и отпусканием пальца, не срабатывает.
	var signature := "%s|%s|%s" % [str(rows), accessible, str(GameState.inventory)]
	if signature == _signature:
		return
	_signature = signature
	_rebuild(rows, accessible)


func _rebuild(rows: Array, accessible: bool) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_tiles.clear()

	_list.add_child(_section(UiIcons.tex("inventory"), not accessible))
	if rows.is_empty():
		_list.add_child(_empty_state())
	else:
		var grid := _grid()
		for row in rows:
			var id := String(row["id"])
			var t := ShopTile.new()
			t.setup(_offer(id, int(row["count"]), true, accessible))
			t.pressed.connect(func() -> void: _on_tile(true, id, t))
			_tiles["store:" + id] = t
			grid.add_child(t)
		_list.add_child(grid)

	# Рюкзак показываем только у самого склада: издалека класть всё равно нечем.
	if accessible and not GameState.inventory.is_empty():
		_list.add_child(_section(ShopArt.ui("icon_backpack"), false))
		var bag := _grid()
		var ids: Array = GameState.inventory.keys()
		ids.sort_custom(func(a, b) -> bool:
			return Balance.get_mineral_weight(String(a)) * GameState.get_item_count(String(a)) \
				> Balance.get_mineral_weight(String(b)) * GameState.get_item_count(String(b)))
		for id_v in ids:
			var id := String(id_v)
			var count := GameState.get_item_count(id)
			if count <= 0:
				continue
			var t := ShopTile.new()
			t.setup(_offer(id, count, false, accessible))
			t.pressed.connect(func() -> void: _on_tile(false, id, t))
			_tiles["bag:" + id] = t
			bag.add_child(t)
		_list.add_child(bag)


func _offer(id: String, count: int, store: bool, accessible: bool) -> Dictionary:
	var unit := Balance.get_mineral_weight(id)
	var total_w := unit * float(count)
	var o := {
		"icon": ShopArt.item_icon(id),
		"tier": ShopItems.price_tier(Balance.get_mineral_price(id)),
		"state": "available" if accessible else "away",
		"title": ShopCatalog.item_name(id),
		"body": "%s шт · %s кг" % [ShopArt.full(count), ShopArt.full(int(round(total_w)))],
		"extra": "",
		"count_text": ShopArt.compact(count),
		"pill": {"icon": UiIcons.tex("weight"), "text": ShopArt.compact(int(round(total_w))), "color": Color.WHITE},
	}
	if not accessible:
		o["extra"] = HouseStorage.access_reason()
	elif store:
		o["extra"] = "Тап — забрать в рюкзак"
	else:
		o["extra"] = "Тап — сложить на склад"
	ProjectChain.decorate_offer(o, id)   # «нужно для бура: 40/100» (ветка guidance)
	return o


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	return grid


func _section(icon: Texture2D, locked: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.custom_minimum_size = Vector2(0, 18)
	var ic := TextureRect.new()
	ic.texture = icon
	ic.custom_minimum_size = Vector2(16, 16)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var line := ColorRect.new()
	line.color = LINE_COL
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	if locked:
		var lock := TextureRect.new()
		lock.texture = ShopArt.tex("glyph_lock")
		lock.custom_minimum_size = Vector2(16, 16)
		lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lock)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		Tip.bind(row, "Склад: только смотреть", "Класть и забирать можно только у самого склада.",
			HouseStorage.access_reason())
	return row


func _empty_state() -> Control:
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(0, 150)
	var ic := TextureRect.new()
	ic.texture = UiIcons.tex("inventory")
	ic.custom_minimum_size = Vector2(64, 64)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = Color(0.6, 0.6, 0.68, 0.7)
	ic.mouse_filter = Control.MOUSE_FILTER_PASS
	Tip.bind(ic, "Склад пуст", "Принеси руду домой и сложи её здесь: из рюкзака в 60 кг кирку не собрать.")
	box.add_child(ic)
	return box


# ---------------------------------------------------------------------------
# Кнопки «забрать всё» и «сложить рюкзак»
# ---------------------------------------------------------------------------

func _update_actions(accessible: bool, rows: Array) -> void:
	var reason := HouseStorage.access_reason()
	var can_take := false
	if accessible:
		for row in rows:
			if HouseStorage.max_takeable(String(row["id"])) > 0:
				can_take = true
				break
	_take_ok = accessible and can_take
	_put_ok = accessible and not GameState.inventory.is_empty()

	var take_extra := reason
	if accessible and rows.is_empty():
		take_extra = "Склад пуст"
	elif accessible and not can_take:
		take_extra = "Рюкзак полон: больше не влезет"
	var put_extra := reason
	if accessible and GameState.inventory.is_empty():
		put_extra = "Рюкзак пуст"
	Tip.bind(_take_btn, "Забрать всё", "Всё, что влезет в рюкзак.", take_extra)
	Tip.bind(_put_btn, "Сложить рюкзак", "Весь рюкзак — на склад.", put_extra)
	_take_btn.modulate = Color.WHITE if _take_ok else Color(0.62, 0.62, 0.68)
	_put_btn.modulate = Color.WHITE if _put_ok else Color(0.62, 0.62, 0.68)
	_take_lock.visible = not accessible
	_put_lock.visible = not accessible


func _on_take_all() -> void:
	if Tip.swallowed():
		return
	if not _take_ok:
		_deny(_take_btn)
		return
	var moved := HouseStorage.take_all()
	_after_move(moved, _take_btn, "pickup")


func _on_put_all() -> void:
	if Tip.swallowed():
		return
	if not _put_ok:
		_deny(_put_btn)
		return
	var moved := HouseStorage.put_all()
	_after_move(moved, _put_btn, "ui_toggle")


# ---------------------------------------------------------------------------
# Плитки и окно «сколько»
# ---------------------------------------------------------------------------

func _deny(c: Control) -> void:
	Sfx.play("ui_deny")
	Haptics.tap()
	ShopFx.wiggle(c)
	Tip.show_now(c)


func _on_tile(store: bool, id: String, tile: ShopTile) -> void:
	if Tip.swallowed():
		return
	if not HouseStorage.can_access():
		_deny(tile)
		return
	var count := HouseStorage.count(id) if store else GameState.get_item_count(id)
	if count <= 0:
		return
	var limit := count
	var limit_text := ""
	if store:
		limit = HouseStorage.max_takeable(id)
		if limit <= 0:
			tile.deny()
			Sfx.play("ui_deny")
			Haptics.tap()
			Tip.bind(tile, String(tile.offer.get("title", "")), String(tile.offer.get("body", "")),
				"Рюкзак полон: больше не влезет")
			Tip.show_now(tile)
			return
		if limit < count:
			limit_text = ShopArt.compact(limit)
	if limit == 1:
		_move(store, id, 1, tile)
		return
	_qty_target = {"store": store, "id": id, "tile": tile}
	_drag.set_process_input(false)
	_qty.open(tile.offer, limit, count, Balance.get_mineral_weight(id), limit_text,
		"Забрать" if store else "Положить")


func _on_qty_confirmed(amount: int) -> void:
	_drag.set_process_input(true)
	if _qty_target.is_empty():
		return
	var t: Dictionary = _qty_target
	_qty_target = {}
	_move(bool(t["store"]), String(t["id"]), amount, t["tile"])


func _move(store: bool, id: String, amount: int, tile: Control) -> void:
	var moved := HouseStorage.take(id, amount) if store else HouseStorage.put(id, amount)
	var center := tile.get_global_rect().get_center() - _root.get_global_rect().position \
		if is_instance_valid(tile) and tile.is_inside_tree() else Vector2(112, 200)
	if moved <= 0:
		Sfx.play("ui_deny")
		if is_instance_valid(tile):
			ShopFx.wiggle(tile)
		return
	Sfx.play("pickup" if store else "ui_toggle")
	Haptics.tap()
	ShopFx.sparkles(_root, center, ShopArt.COL_GOLD if store else ShopArt.COL_GOOD, 12, 28.0)
	HouseArt.float_number(_root, center + Vector2(-8, -18), ("+%s" if store else "−%s") % ShopArt.compact(moved),
		ShopArt.COL_GOOD if store else ShopArt.COL_GOLD)
	_signature = ""
	_head_sig = ""
	refresh()


func _after_move(moved: int, button: Control, sound: String) -> void:
	if moved <= 0:
		_deny(button)
		return
	Sfx.play(sound)
	Haptics.tap()
	var center := button.get_global_rect().get_center() - _root.get_global_rect().position
	ShopFx.sparkles(_root, center, ShopArt.COL_GOLD, 16, 34.0)
	HouseArt.float_number(_root, center + Vector2(-10, -26), "×%s" % ShopArt.compact(moved), ShopArt.COL_GOOD)
	_signature = ""
	_head_sig = ""
	refresh()


## Для снимков экрана: открыть окно «сколько» на плитке без тапа.
func debug_open_qty(id: String, store: bool) -> void:
	var tile: ShopTile = _tiles.get(("store:" if store else "bag:") + id)
	if tile != null:
		_on_tile(store, id, tile)

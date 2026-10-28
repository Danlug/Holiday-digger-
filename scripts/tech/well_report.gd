class_name WellReport
extends Control
## Окно отчёта скважины при возвращении в игру (ГДД п.1, решение владельца):
## «за сколько времени и что накопала». Плитки-иконки с числами, добыча
## «ссыпается» на склад (иконки летят в ящик, счётчик растёт), кнопка «×2» за
## ролик (TechAds → AdManager). Текст — только в подсказках Tip.
##
## Добыча УЖЕ лежит на складе к моменту показа (IdleWell.collect ставит отметку и
## выплачивает до окна): убитое посреди анимации приложение ничего не теряет и не
## выплачивает дважды. Окно — только показ и «×2».

static var _instance: WellReport = null

var _report: Dictionary = {}
var _card: PanelContainer = null
var _tiles: Array = []            # [{id, count, icon, label}]
var _crate: TextureRect = null
var _total_label: Label = null
var _total: int = 0
var _double_btn: Button = null
var _doubled: bool = false
var _run: int = 0
var _closing: bool = false   # окно гаснет (анимация): по смыслу уже закрыто


static func attach(host: Node) -> WellReport:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var layer := CanvasLayer.new()
	layer.name = "WellReportLayer"
	layer.layer = UiLayers.HERO_CARD   # выше экрана героя (95), ниже катсцен (100)
	host.add_child(layer)
	var w := WellReport.new()
	w.name = "WellReport"
	layer.add_child(w)
	return w


static func instance() -> WellReport:
	return _instance if _instance != null and is_instance_valid(_instance) else null


static func is_open() -> bool:
	var w := instance()
	return w != null and w.visible and not w._closing


func _ready() -> void:
	_instance = self
	add_to_group("well_report")
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(_fit)
	_fit()
	visible = false


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


# ---------------------------------------------------------------------------
# Показ
# ---------------------------------------------------------------------------

func show_report(report: Dictionary) -> void:
	if report.is_empty():
		return
	_run += 1
	_report = report
	_doubled = false
	_total = 0
	_tiles.clear()
	for c in get_children():
		c.queue_free()
	_build()
	_closing = false
	visible = true
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("close_inventory"):
		hud.close_inventory()
	_play(_run)


func close() -> void:
	if not visible or _closing:
		return
	_run += 1
	_closing = true
	UiAnim.close(_card, UiAnim.Kind.POP, self, func() -> void: _closing = false)
	Sfx.play("ui_close")


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		var st := e as InputEventScreenTouch
		if (mb != null and mb.pressed) or (st != null and st.pressed):
			close())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(196, 0)
	_card.add_theme_stylebox_override("panel", ProgressUiKit.popup_box(TechUi.GOLD, ProgressUiKit.SHEET_BG, 10))
	_card.modulate.a = 0.0   # _play проявит карточку через два кадра; без этого она мигала полной
	center.add_child(_card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_card.add_child(v)

	# Шапка: скважина и ступень.
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var well := TechUi.icon_rect(TechUi.tex("icon_well"), 40)
	well.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind(well, "Буровая скважина", "Копала, пока тебя не было", "ступень %d" % int(_report.get("level", GameState.well_level)))
	head.add_child(well)
	var pips := VBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.add_theme_constant_override("separation", 3)
	head.add_child(pips)
	var lvl := int(_report.get("level", GameState.well_level))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	pips.add_child(row)
	for i in range(IdleWell.max_level()):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(6, 6)
		pip.color = TechUi.GOLD if i < lvl else Color(0.22, 0.17, 0.12)
		row.add_child(pip)

	# Время работы.
	var time_row := HBoxContainer.new()
	time_row.alignment = BoxContainer.ALIGNMENT_CENTER
	time_row.add_theme_constant_override("separation", 5)
	time_row.mouse_filter = Control.MOUSE_FILTER_STOP
	v.add_child(time_row)
	time_row.add_child(TechUi.icon_rect(TechUi.tex("icon_hourglass"), 22))
	var capped := bool(_report.get("capped", false))
	time_row.add_child(TechUi.label(TechUi.hm(float(_report.get("seconds", 0.0))), 15,
		TechUi.RED if capped else TechUi.GOLD))
	var secs_txt := TechUi.hm(float(_report.get("raw_seconds", _report.get("seconds", 0.0))))
	if capped:
		var lk := TechUi.icon_rect(TechUi.tex("icon_lock"), 14)
		time_row.add_child(lk)
		Tip.bind(time_row, "Упёрлась в кап", "Дольше %d ч скважина не копит — заглядывай почаще" % int(_report.get("cap_hours", 8)),
			"отсутствовал %s" % secs_txt)
	else:
		Tip.bind(time_row, "Работала без тебя", "Сколько времени накопилось с прошлого раза")

	# Плитки добычи.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var gwrap := CenterContainer.new()
	gwrap.add_child(grid)
	v.add_child(gwrap)
	var items: Dictionary = _report.get("items", {})
	var ids := items.keys()
	ids.sort_custom(func(a, b): return Balance.get_mineral_price(String(a)) * int(items[a]) > Balance.get_mineral_price(String(b)) * int(items[b]))
	for id in ids:
		grid.add_child(_make_tile(String(id), int(items[id])))

	# Склад — куда всё ссыпается.
	var stock := HBoxContainer.new()
	stock.alignment = BoxContainer.ALIGNMENT_CENTER
	stock.add_theme_constant_override("separation", 6)
	v.add_child(stock)
	_crate = TechUi.icon_rect(TechUi.tex("icon_storage"), 34)
	_crate.mouse_filter = Control.MOUSE_FILTER_STOP
	_crate.pivot_offset = Vector2(17, 17)
	Tip.bind(_crate, "Склад в мастерской", "Вся добыча уже лежит там", "~%d монет по цене скупки" % int(_report.get("coins_value", 0)))
	stock.add_child(_crate)
	_total_label = TechUi.label("+0", 14, TechUi.GREEN)
	stock.add_child(_total_label)

	# Кнопки: ×2 за ролик и «готово».
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	v.add_child(buttons)
	_double_btn = UiBtn.icon_button(TechUi.tex("icon_ad"), Vector2(86, 32), UiBtn.Kind.ACCENT, 22)
	_double_btn.text = "×2"
	_double_btn.add_theme_font_size_override("font_size", 14)
	_double_btn.add_theme_color_override("font_color", TechUi.GOLD)
	_double_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_double_btn.add_theme_constant_override("h_separation", 6)
	Tip.bind(_double_btn, "Удвоить добычу", "Посмотри ролик — столько же ляжет на склад. Доллары скважина не даёт.",
		"сегодня осталось %d" % TechAds.left_today())
	_double_btn.pressed.connect(_on_double)
	buttons.add_child(_double_btn)
	var ok := UiBtn.icon_button(TechUi.tex("icon_check"), Vector2(62, 32), UiBtn.Kind.NORMAL, 22)
	Tip.bind(ok, "Готово")
	ok.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		close())
	buttons.add_child(ok)
	_double_btn.disabled = TechAds.left_today() <= 0


func _make_tile(id: String, count: int) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(86, 62)
	tile.add_theme_stylebox_override("panel", TechUi.box(UiTheme.ROW, TechUi.BORDER, 6, 4))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	tile.add_child(col)
	var icon := TechUi.icon_rect(TechUi.item_icon(id), 32)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon)
	var label := TechUi.label("×0", 13, TechUi.GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(label)
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	var price := Balance.get_mineral_price(id)
	Tip.bind(tile, TechUi.item_name(id), "Добыто скважиной", "≈ %d монет" % (price * count))
	tile.modulate.a = 0.0
	_tiles.append({"id": id, "count": count, "icon": icon, "label": label, "tile": tile})
	return tile


# ---------------------------------------------------------------------------
# Анимация: плитки всплывают по очереди, потом добыча «ссыпается» на склад
# ---------------------------------------------------------------------------

func _wait(seconds: float) -> void:
	if UiAnim.reduced():
		return
	await get_tree().create_timer(seconds).timeout


func _play(run: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if run != _run:
		return
	if _card != null:
		UiAnim.open(_card, UiAnim.Kind.POP)
	Sfx.play("ui_open")
	await _wait(0.25)
	for i in range(_tiles.size()):
		if run != _run:
			return
		var t: Dictionary = _tiles[i]
		var tile: Control = t["tile"]
		tile.modulate.a = 1.0
		UiAnim.appear(tile, 0.6, 0.18)
		Sfx.play("pickup", 1.0 + 0.06 * i)
		_count_up(t["label"], 0, int(t["count"]), 0.5)
		await _wait(0.16)
	await _wait(0.45)
	for t in _tiles:
		if run != _run:
			return
		_pour_tile(t, int(t["count"]))
		await _wait(0.12)
	await _wait(0.7)
	if run == _run:
		Sfx.play("reward")
		Haptics.thud()
		UiAnim.pulse(_crate, 0.3, 0.3)


func _count_up(label: Label, from: int, to: int, duration: float) -> void:
	if UiAnim.reduced() or not label.is_inside_tree():
		label.text = "×%d" % to
		return
	var tw := label.create_tween()
	tw.tween_method(func(v: float) -> void: label.text = "×%d" % int(round(v)), float(from), float(to), duration)


## Иконки одной плитки летят в ящик; число склада растёт по прилёту.
func _pour_tile(t: Dictionary, amount: int) -> void:
	var icon: Control = t["icon"]
	var from := icon.get_global_rect().get_center()
	var to := _crate.get_global_rect().get_center()
	var flights := clampi(amount, 1, 5)
	var per := int(ceil(float(amount) / float(flights)))
	var left := amount
	for i in range(flights):
		var part := mini(per, left)
		left -= part
		var arrive := func() -> void:
			_total += part
			_total_label.text = "+%d" % _total
			UiAnim.pulse(_crate, 0.14, 0.14)
			Sfx.play("coin", 1.0 + randf() * 0.2, -6.0)
		TechUi.fly(self, icon.texture, from, to, 0.07 * i, arrive, 20.0)


# ---------------------------------------------------------------------------
# «×2» за ролик
# ---------------------------------------------------------------------------

func _on_double() -> void:
	if Tip.swallowed() or _doubled:
		return
	var run := _run
	_double_btn.disabled = true
	TechAds.request(func(ok: bool) -> void:
		if run != _run or not is_inside_tree():
			return
		if not ok:
			_double_btn.disabled = TechAds.left_today() <= 0
			_deny()
			return
		_doubled = true
		IdleWell.double_report(_report)
		SaveSystem.save_game()
		Sfx.play("reward")
		Haptics.thud()
		Fx.flash(Color(1.0, 0.85, 0.4, 0.25), 0.2)
		UiAnim.pulse(_double_btn, 0.25, 0.3)
		_double_btn.modulate = Color(1, 1, 1, 0.45)
		for t in _tiles:
			var n := int(t["count"])
			_count_up(t["label"], n, n * 2, 0.5)
			UiAnim.pulse(t["tile"], 0.18, 0.3)
			_pour_tile(t, n))


func _deny() -> void:
	UiAnim.shake(_double_btn)
	Sfx.play("ui_deny")
	Haptics.buzz(30)

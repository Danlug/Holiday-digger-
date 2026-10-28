class_name NewbieStreakPanel
extends CanvasLayer
## Экран стрика новичка: календарь из 30 плиток-дней (6 × 5), под ним — карточка
## выбранного дня (награда, «Забрать» или «Вернуть за 50 $») и в самом низу —
## закрытая карточка крупного подарка за все 30 дней («скоро»). Миссий нет:
## день отмечается за вход (NewbieStreak.refresh).
##
## Плитки: сегодня — золотая рамка; отмечен — галочка (или подарок, пока
## награда не забрана); пропущен — красноватая с долларом; закрыт — номер и
## замок. Описания — только в Tip (правило владельца), у плиток — долгим нажатием.
## Окно пересобирается целиком при каждом изменении: состояние живёт в
## GameState.ext, а не в узлах.

signal closed

const CARD_W := 212.0
const COLS := 6
const TILE := Vector2(30, 32)
## Карточка дня одной высоты (строка дня и кнопка) — календарь не прыгает при выборе другого дня.
const DETAIL_H := 72.0

const BG_TODAY := Color8(0x2E, 0x26, 0x12)
const BG_DONE := Color8(0x1B, 0x2A, 0x1C)
const BG_MISSED := Color8(0x33, 0x17, 0x1A)
const BG_LOCKED := Color8(0x1A, 0x16, 0x1E)
const RED_EDGE := Color8(0x8A, 0x2E, 0x35)
const PURPLE := Color8(0x2A, 0x1A, 0x33)
const DOLLAR_GREEN := Color8(0x4D, 0xE0, 0x94)

var _root: Control = null
var _card: PanelContainer = null
var _box: VBoxContainer = null
var _grid: GridContainer = null
var _timer_label: Label = null
var _selected: int = 0
var _shown_index: int = -1
var _tick: float = 0.0
var _closing: bool = false
var _pulses: Array = []
## Широкие кнопки «мерцают» яркостью, а не масштабом: увеличенная, она вылезала бы за карточку.
var _glows: Array = []


func _ready() -> void:
	layer = UiLayers.MODAL  # как окно заданий дня: выше хаба (92), HUD и шторок; ниже подарка дня (94) и экрана героя (95)
	visible = false
	add_to_group("meta_hub")   # тост идёт снизу, не закрывая шапку


func is_open() -> bool:
	return visible and not _closing


func open() -> void:
	_closing = false
	_selected = _default_day()
	_shown_index = NewbieStreak.current_index()
	_build()
	visible = true
	Sfx.play("ui_open")
	UiAnim.open(_card, UiAnim.Kind.POP, _root)
	if _grid != null:
		UiAnim.stagger(_grid.get_children(), 0.012, 0.85, 0.3)


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	Sfx.play("ui_close")
	var closing_root := _root
	var finish := func() -> void:
		if _root != closing_root:
			return
		visible = false
		_closing = false
		if _root != null:
			_root.queue_free()
			_root = null
		closed.emit()
	UiAnim.close(_card, UiAnim.Kind.POP, _root, finish)


func refresh() -> void:
	if is_open():
		_fill()


func select(n: int) -> void:
	if n < 1 or n > NewbieStreak.days_total():
		return
	_selected = n
	refresh()


func selected() -> int:
	return _selected


## Сегодняшний день; после 30-х суток — первый пропущенный (его можно вернуть), иначе последний.
func _default_day() -> int:
	var n := NewbieStreak.today_n()
	if n > 0:
		return n
	for i in range(1, NewbieStreak.days_total() + 1):
		if NewbieStreak.status(i) == NewbieStreak.St.MISSED:
			return i
	return NewbieStreak.days_total()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open():
		return
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	var idx := NewbieStreak.current_index()
	if idx != _shown_index:
		# Полночь при открытом окне: вчерашний день стал пропущенным, открылся новый.
		var was_today := _selected == _shown_index
		_shown_index = idx
		if was_today:
			_selected = _default_day()
		_fill()
	_update_timer()


# ---------------------------------------------------------------------------
# Каркас
# ---------------------------------------------------------------------------

func _build() -> void:
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "NewbieStreakRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.74)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			if Tip.dismissed_by_tap():
				return   # тап закрыл подсказку миссии — окно остаётся
			close())
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_card = PanelContainer.new()
	var sb := ProgressUiKit.popup_box(MetaUiKit.GOLD, MetaUiKit.CARD, 6)
	sb.set_border_width_all(2)
	_card.add_theme_stylebox_override("panel", sb)
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_card)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 5)
	_card.add_child(_box)
	_fill()


func _fill() -> void:
	_pulses.clear()
	_glows.clear()
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_box.add_child(_header())
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	for n in range(1, NewbieStreak.days_total() + 1):
		_grid.add_child(_tile(n))
	_box.add_child(_grid)
	_box.add_child(_detail(_selected))
	_box.add_child(_grand())
	_update_timer()
	_start_pulses()


# ---------------------------------------------------------------------------
# Шапка: значок, «выполнено N/30», таймер дня, доллары, закрыть
# ---------------------------------------------------------------------------

func _header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)

	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 2)
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.add_child(MetaUiKit.icon_rect(MetaUiKit.tex("newbie"), 22))
	var cnt := MetaUiKit.label("%d/%d" % [NewbieStreak.done_count(), NewbieStreak.days_total()], 12, MetaUiKit.GOLD_LIGHT)
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_child(cnt)
	Tip.bind(title, NewbieStreak.text("title"), NewbieStreak.text("about"),
		"%s: %d/%d" % [NewbieStreak.text("progress"), NewbieStreak.done_count(), NewbieStreak.days_total()])
	h.add_child(title)

	if NewbieStreak.today_n() > 0:
		var tm := MetaUiKit.chip(MetaUiKit.tex("clock"), "", MetaUiKit.MUTED, 12, 9)
		tm.mouse_filter = Control.MOUSE_FILTER_PASS
		_timer_label = tm.get_child(1)
		Tip.bind(tm, NewbieStreak.text("timer"), NewbieStreak.text("today_body"))
		h.add_child(tm)
	else:
		_timer_label = null

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(gap)

	var wallet := MetaUiKit.chip(MetaUiKit.tex("dollar"), str(GameState.dollars), DOLLAR_GREEN, 12, 10)
	wallet.mouse_filter = Control.MOUSE_FILTER_PASS
	wallet.name = "Wallet"
	Tip.bind(wallet, NewbieStreak.text("wallet"))
	h.add_child(wallet)

	h.add_child(UiBtn.close_button(close, null, NewbieStreak.text("close")))
	return h


func _update_timer() -> void:
	if _timer_label != null and is_instance_valid(_timer_label):
		_timer_label.text = MetaClock.hms(MetaClock.seconds_to_next_day())


# ---------------------------------------------------------------------------
# Плитка дня
# ---------------------------------------------------------------------------

func _tile(n: int) -> Control:
	var st := NewbieStreak.status(n)
	var claimable := NewbieStreak.can_claim(n)
	var b := Button.new()
	b.name = "Day%d" % n
	b.custom_minimum_size = TILE
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	var bg := BG_LOCKED
	var edge := MetaUiKit.BORDER
	var edge_w := 1
	match st:
		NewbieStreak.St.TODAY:
			bg = BG_TODAY
			edge = MetaUiKit.GOLD
			edge_w = 2
		NewbieStreak.St.DONE:
			bg = BG_DONE
			edge = MetaUiKit.GOLD if claimable else MetaUiKit.GREEN.darkened(0.35)
			edge_w = 2 if claimable else 1
		NewbieStreak.St.MISSED:
			bg = BG_MISSED
			edge = RED_EDGE
	if n == _selected:
		edge = Color.WHITE
		edge_w = 2
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := MetaUiKit.box(bg.lightened(0.08) if state_name == "hover" else bg, edge, edge_w, 4)
		sb.set_content_margin_all(0)
		b.add_theme_stylebox_override(state_name, sb)

	var num_col := MetaUiKit.MUTED
	match st:
		NewbieStreak.St.TODAY:
			num_col = MetaUiKit.GOLD_LIGHT
		NewbieStreak.St.DONE:
			num_col = MetaUiKit.GREEN
		NewbieStreak.St.MISSED:
			num_col = Color8(0xE0, 0x8A, 0x8A)
		NewbieStreak.St.LOCKED:
			num_col = MetaUiKit.DIM

	if st == NewbieStreak.St.TODAY:   # миг до отметки (она — в ближайшую секунду): крупный номер
		var big := _num_label(n, 11, num_col)
		big.position = Vector2(0, 8)
		big.size = Vector2(TILE.x, 14)
		b.add_child(big)
	else:
		var num := _num_label(n, 9, num_col)
		num.position = Vector2(0, 1)
		num.size = Vector2(TILE.x, 11)
		b.add_child(num)
		var icon_name := "lock"
		match st:
			NewbieStreak.St.DONE:
				icon_name = "gift" if claimable else "check"
			NewbieStreak.St.MISSED:
				icon_name = "dollar"
		var ic := MetaUiKit.icon_rect(MetaUiKit.tex(icon_name), 14)
		ic.position = Vector2((TILE.x - 14) * 0.5, 14)
		if st == NewbieStreak.St.LOCKED:
			ic.modulate = Color(1, 1, 1, 0.55)
		b.add_child(ic)
		if claimable:
			_pulses.append(ic)

	b.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		Sfx.play("ui_tab")
		Haptics.tap()
		select(n))
	Tip.bind(b, NewbieStreak.text("day") % n, _status_body(n), _status_extra(n))
	return b


func _num_label(n: int, size: int, col: Color) -> Label:
	var l := MetaUiKit.label(str(n), size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _status_body(n: int) -> String:
	match NewbieStreak.status(n):
		NewbieStreak.St.TODAY:
			return "%s. %s" % [NewbieStreak.text("today"), NewbieStreak.text("today_body")]
		NewbieStreak.St.DONE:
			return NewbieStreak.text("done_bought") if NewbieStreak.was_bought(n) else NewbieStreak.text("done")
		NewbieStreak.St.MISSED:
			return "%s. %s" % [NewbieStreak.text("missed"), NewbieStreak.text("missed_body")]
	return NewbieStreak.text("locked_body") % NewbieStreak.days_until(n)


func _status_extra(n: int) -> String:
	if NewbieStreak.status(n) == NewbieStreak.St.LOCKED:
		return ""
	return NewbieStreak.text("reward") % NewbieStreak.describe_reward(NewbieStreak.reward(n))


# ---------------------------------------------------------------------------
# Карточка выбранного дня
# ---------------------------------------------------------------------------

func _detail(n: int) -> Control:
	var st := NewbieStreak.status(n)
	var card := PanelContainer.new()
	card.name = "Detail"
	card.custom_minimum_size = Vector2(0, DETAIL_H)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var edge := MetaUiKit.BORDER
	match st:
		NewbieStreak.St.TODAY:
			edge = MetaUiKit.GOLD
		NewbieStreak.St.MISSED:
			edge = RED_EDGE
		NewbieStreak.St.DONE:
			edge = MetaUiKit.GREEN.darkened(0.35)
	var sb := MetaUiKit.box(MetaUiKit.SLOT, edge, 1, 5)
	sb.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)

	# Строка: «День N» · значок состояния … награда дня.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var day := MetaUiKit.label(NewbieStreak.text("day") % n, 11, MetaUiKit.GOLD_LIGHT if st == NewbieStreak.St.TODAY else ProgressUiKit.TEXT_HI)
	day.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(day)
	var st_icon := ""
	match st:
		NewbieStreak.St.DONE:
			st_icon = "dollar" if NewbieStreak.was_bought(n) else "check"
		NewbieStreak.St.LOCKED:
			st_icon = "lock"
	if st_icon != "":
		var si := MetaUiKit.icon_rect(MetaUiKit.tex(st_icon), 14)
		si.mouse_filter = Control.MOUSE_FILTER_PASS
		Tip.bind(si, NewbieStreak.text("day") % n, _status_body(n))
		top.add_child(si)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	if st != NewbieStreak.St.LOCKED:
		var rw := _reward_row(NewbieStreak.reward(n))
		rw.mouse_filter = Control.MOUSE_FILTER_PASS
		Tip.bind(rw, NewbieStreak.text("reward") % NewbieStreak.describe_reward(NewbieStreak.reward(n)))
		if NewbieStreak.is_claimed(n):
			rw.modulate = Color(0.6, 0.6, 0.6)
		top.add_child(rw)
	v.add_child(top)

	if st == NewbieStreak.St.LOCKED:
		v.add_child(_locked_body(n))
		return card

	if NewbieStreak.can_claim(n):
		v.add_child(_claim_button(n))
	elif st == NewbieStreak.St.MISSED:
		v.add_child(_restore_button(n))
	return card


func _locked_body(n: int) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 6)
	h.custom_minimum_size = Vector2(0, 44)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL   # замок — посередине карточки дня
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lk := MetaUiKit.icon_rect(MetaUiKit.tex("lock"), 32)
	lk.modulate = Color(1, 1, 1, 0.8)
	h.add_child(lk)
	var cl := MetaUiKit.chip(MetaUiKit.tex("clock"), "+%d" % NewbieStreak.days_until(n), MetaUiKit.MUTED, 14, 11)
	cl.mouse_filter = Control.MOUSE_FILTER_PASS
	Tip.bind(cl, NewbieStreak.text("locked"), NewbieStreak.text("locked_body") % NewbieStreak.days_until(n))
	h.add_child(cl)
	return h


func _reward_row(r: Dictionary) -> HBoxContainer:
	r = MetaRewards.normalize(r)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if r.has("coins"):
		row.add_child(MetaUiKit.chip(MetaUiKit.tex("coin"), UiFmt.short(int(r["coins"])), MetaUiKit.GOLD_LIGHT, 12, 9))
	if r.has("dollars"):
		row.add_child(MetaUiKit.chip(MetaUiKit.tex("dollar"), str(int(r["dollars"])), DOLLAR_GREEN, 12, 9))
	if r.has("xp"):
		row.add_child(MetaUiKit.chip(MetaUiKit.tex("xp"), UiFmt.short(int(r["xp"])), MetaUiKit.BLUE, 12, 9))
	if r.has("item"):
		var t := ShopArt.tex("item_" + String(r["item"]["id"]))
		if t == null:
			t = MetaUiKit.reward_tex("item", String(r["item"]["id"]))
		row.add_child(MetaUiKit.chip(t, "×%d" % int(r["item"]["count"]), Color.WHITE, 12, 9))
	return row


## Широкая кнопка действия: содержимое (подпись, значки) — по центру, вплотную друг к другу.
func _cta(color: Color, parts: Array) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 26)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := MetaUiKit.box(color, MetaUiKit.GOLD if st == "hover" else color.lightened(0.25), 1, 5)
		if st == "pressed":
			sb.bg_color = color.darkened(0.2)
		sb.set_content_margin_all(3)
		b.add_theme_stylebox_override(st, sb)
	b.focus_mode = Control.FOCUS_NONE
	var h := HBoxContainer.new()
	h.name = "Content"
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in parts:
		h.add_child(c)
	b.add_child(h)
	UiBtn.wire_feedback(b)
	return b


func _claim_button(n: int) -> Button:
	var parts: Array = [MetaUiKit.icon_rect(MetaUiKit.tex("check"), 18), _reward_row(NewbieStreak.reward(n))]
	var b := _cta(MetaUiKit.GREEN_BTN, parts)
	b.name = "Claim"
	b.pressed.connect(func() -> void: _claim(n, b))
	Tip.bind(b, NewbieStreak.text("claim"), "", NewbieStreak.text("reward") % NewbieStreak.describe_reward(NewbieStreak.reward(n)))
	_glows.append(b)
	return b


## «Вернуть за 50 $»: зелёная, когда долларов хватает; серая — когда нет (нажатие
## трясёт кнопку и показывает, сколько не хватает, — покупки нет).
func _restore_button(n: int) -> Button:
	var price := NewbieStreak.restore_price()
	var afford := GameState.dollars >= price
	var cap := MetaUiKit.label(NewbieStreak.text("restore") % price, 10, Color.WHITE if afford else MetaUiKit.MUTED)
	cap.name = "Caption"
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ic := MetaUiKit.icon_rect(MetaUiKit.tex("dollar"), 14)
	if not afford:
		ic.modulate = Color(0.7, 0.7, 0.7)
	var b := _cta(Color8(0x2F, 0x6B, 0x3B) if afford else Color8(0x3A, 0x34, 0x30), [cap, ic])
	b.name = "Restore"
	b.pressed.connect(func() -> void: _restore(n, b))
	Tip.bind(b, NewbieStreak.text("restore_tip") % price, NewbieStreak.text("missed_body"),
		"" if afford else NewbieStreak.text("no_dollars") % [GameState.dollars, price])
	if afford:
		_glows.append(b)
	return b


# ---------------------------------------------------------------------------
# Крупный подарок за все 30 дней — заглушка «скоро»
# ---------------------------------------------------------------------------

func _grand() -> Control:
	var total := NewbieStreak.days_total()
	var done := NewbieStreak.done_count()
	var card := PanelContainer.new()
	card.name = "Grand"
	card.custom_minimum_size = Vector2(0, 58)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := MetaUiKit.box(PURPLE, MetaUiKit.GOLD, 2, 6)
	sb.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(48, 48)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.85, 0.35, 0.10)
	glow.position = Vector2(4, 4)
	glow.size = Vector2(40, 40)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glow)
	var chest := MetaUiKit.icon_rect(MetaUiKit.tex("newbie_grand"), 48)
	chest.name = "GrandChest"
	holder.add_child(chest)
	h.add_child(holder)
	_pulses.append(chest)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 4)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(MetaUiKit.icon_rect(MetaUiKit.tex("newbie"), 16))
	var cnt := MetaUiKit.label("%d" % total, 13, MetaUiKit.GOLD_LIGHT)
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(cnt)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(gap)
	var soon := PanelContainer.new()
	var ssb := MetaUiKit.box(Color8(0x4A, 0x2E, 0x58), MetaUiKit.GOLD.darkened(0.2), 1, 3)
	ssb.content_margin_left = 4
	ssb.content_margin_right = 4
	ssb.content_margin_top = 0
	ssb.content_margin_bottom = 1
	soon.add_theme_stylebox_override("panel", ssb)
	soon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	soon.add_child(MetaUiKit.label(NewbieStreak.text("grand_soon"), 9, MetaUiKit.GOLD_LIGHT))
	line.add_child(soon)
	mid.add_child(line)
	var bar := MetaBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(40, 13)
	bar.font_size = 9
	bar.frac = float(done) / float(maxi(1, total))
	bar.text = "%d/%d" % [done, total]
	bar.fill_color = MetaUiKit.GOLD
	mid.add_child(bar)
	h.add_child(mid)

	Tip.bind(card, NewbieStreak.text("grand_title"), NewbieStreak.text("grand_body"),
		"%s: %d/%d" % [NewbieStreak.text("progress"), done, total])
	return card


# ---------------------------------------------------------------------------
# Действия
# ---------------------------------------------------------------------------

func _claim(n: int, from: Control) -> void:
	if Tip.swallowed():
		return
	var origin := _center(from)
	var res := NewbieStreak.claim(n)
	if not bool(res["ok"]):
		return
	MetaFx.claim(get_tree(), origin, res["reward"], n == NewbieStreak.days_total(), {}, true)
	_after_change()


func _restore(n: int, from: Control) -> void:
	if Tip.swallowed():
		return
	if not NewbieStreak.can_restore(n):
		UiAnim.shake(from)
		Sfx.play("ui_deny")
		Haptics.buzz()
		Tip.show_now(from)
		return
	var origin := _center(from)
	var res := NewbieStreak.restore(n)
	if not bool(res["ok"]):
		UiAnim.shake(from)
		Sfx.play("ui_deny")
		return
	Sfx.play("ui_buy")
	MetaFx.claim(get_tree(), origin, res["reward"], true, {}, true)
	_after_change()


func _after_change() -> void:
	var svc := MetaService.instance
	if svc != null:
		svc.after_change()
	elif GameState.world_ref != null:
		SaveSystem.save_game()
	_fill()


## Готовое к получению покачивается — глаз сразу находит, что нажать.
func _start_pulses() -> void:
	if UiAnim.reduced():
		return
	for c in _pulses:
		var ctl := c as Control
		if ctl == null or not is_instance_valid(ctl):
			continue
		ctl.resized.connect(func() -> void: ctl.pivot_offset = ctl.size * 0.5)
		ctl.pivot_offset = (ctl.size if ctl.size != Vector2.ZERO else ctl.custom_minimum_size) * 0.5
		var tw := ctl.create_tween().set_loops()
		tw.tween_property(ctl, "scale", Vector2.ONE * 1.06, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(ctl, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_interval(0.6)
	for c in _glows:
		var ctl := c as Control
		if ctl == null or not is_instance_valid(ctl):
			continue
		var tw := ctl.create_tween().set_loops()
		tw.tween_property(ctl, "modulate", Color(1.25, 1.25, 1.15), 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_property(ctl, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(0.6)


func _center(c: Control) -> Vector2:
	return c.global_position + c.size * 0.5

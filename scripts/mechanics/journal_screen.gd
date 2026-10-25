class_name JournalScreen
extends CanvasLayer
## «Журнал добытчика»: мастерство руд и найденные тайники. Две вкладки-значка
## внизу (зона большого пальца, тот же вид, что у экранов героя и наград):
##   руды    — сетка всех пород по глубине появления: значок, пять звёзд, полоска
##             до следующей звезды; ненайденная — чёрный силуэт;
##   тайники — открытые сундуки по ступеням, сколько раз была жадность, добыча сверху.
## На плитках только значки и числа; название, сколько добыто, бонус и порог
## следующей звезды — в Tip (наведение, долгое нажатие или тап по плитке).

signal closed

const TAB_ORES := "ores"
const TAB_CHESTS := "chests"
const COLS := 5
const TILE_W := 40.0
const TILE_H := 48.0

var director: MechDirector = null

var _root: Control
var _tab := TAB_ORES
var _tab_buttons: Dictionary = {}
var _scroll: ScrollContainer
var _body: Control
var _head: HBoxContainer
var _closing := false
var _locked := false
var _was_frozen := false
var _hud_input_was_on := true


func _ready() -> void:
	layer = 92   # как хаб наград: выше HUD, дома и шторок, ниже окна дня и экрана героя
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible and not _closing


func open(tab: String = "") -> void:
	if tab != "":
		_tab = tab
	for k in _tab_buttons.keys():
		(_tab_buttons[k] as HeroTabButton).set_selected(k == _tab)
	_closing = false
	_root.visible = true
	_lock(true)
	UiAnim.open(_root, UiAnim.Kind.FADE)
	Sfx.play("ui_open")
	refresh()
	if _body != null:
		UiAnim.stagger(_body.get_children(), 0.02, 0.9)
	MechState.mark_all_seen()


func close() -> void:
	if not is_open():
		return
	_closing = true
	_lock(false)
	UiAnim.close(_root, UiAnim.Kind.FADE, null, func() -> void: _closing = false)
	Sfx.play("ui_close")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Пока журнал открыт, герой стоит, а ввод HUD выключен (как у хаба наград):
## иначе джойстик под экраном ловит касания раньше плиток.
func _lock(on: bool) -> void:
	if on == _locked:
		return
	_locked = on
	var tree := get_tree()
	if tree == null:
		return
	var player := director.player if director != null else null
	var hud := tree.get_first_node_in_group("hud")
	if player != null and is_instance_valid(player):
		if on:
			_was_frozen = bool(player.get("frozen"))
			player.set("frozen", true)
			player.set("digging", null)
			if player.has_method("release_control"):
				player.call("release_control")
		else:
			player.set("frozen", _was_frozen)
	if hud != null:
		if on:
			_hud_input_was_on = hud.is_processing_input()
			hud.set_process_input(false)
		else:
			hud.set_process_input(_hud_input_was_on)
	Tip.hide_all()


# ---------------------------------------------------------------------------
# Каркас
# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "JournalRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_to_group("hint_block")
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = ProgressUiKit.BG_SOLID
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	_head = HBoxContainer.new()
	_head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_head.offset_left = 8
	_head.offset_right = -8
	_head.offset_top = 8
	_head.offset_bottom = 30
	_head.alignment = BoxContainer.ALIGNMENT_CENTER
	_head.add_theme_constant_override("separation", 10)
	_root.add_child(_head)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 6
	_scroll.offset_right = -6
	_scroll.offset_top = 36
	_scroll.offset_bottom = -(ProgressUiKit.TAB_BAR_H + 10)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(_scroll)
	DragScroll.attach(_scroll)

	var specs := [
		[TAB_ORES, UiIcons.item_small("gold", 16), "Руды", "Мастерство: звёзды за добычу каждой породы"],
		[TAB_CHESTS, Mechanics.tex("chest_gold_icon"), "Тайники", "Открытые сундуки и жадность"],
	]
	var bar := HeroTabButton.make_bar(specs, _tab, _set_tab, close)
	_tab_buttons = bar.get_meta("buttons")
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 6
	bar.offset_right = -6
	bar.offset_top = -(ProgressUiKit.TAB_BAR_H + 4)
	bar.offset_bottom = -4
	_root.add_child(bar)


func _set_tab(t: String) -> void:
	_tab = t
	for k in _tab_buttons.keys():
		(_tab_buttons[k] as HeroTabButton).set_selected(k == t)
	refresh()
	if _body != null:
		UiAnim.stagger(_body.get_children(), 0.02, 0.9)


func refresh() -> void:
	_fill_head()
	if _body != null:
		_body.queue_free()
		_body = null
	if _tab == TAB_CHESTS:
		_body = _build_chests()
	else:
		_body = _build_ores()
	_scroll.add_child(_body)


# --- шапка: найдено пород, звёзд, сундуков -------------------------------------

func _fill_head() -> void:
	for c in _head.get_children():
		c.queue_free()
	var kinds := MasteryLogic.kinds()
	_chip(Mechanics.tex("journal"), "%d/%d" % [MasteryLogic.discovered_count(), kinds.size()],
		"Найдено пород", "Сколько пород из журнала ты уже добывал.")
	_chip(Mechanics.tex("star_on"), "%d/%d" % [MasteryLogic.total_stars(), kinds.size() * MasteryLogic.MAX_STARS],
		"Звёзды мастерства", "Звезда — за число выкопанных клеток одной породы. Каждая даёт опыт и +2% двойной добычи этой руды.")
	_chip(Mechanics.tex("chest_wood_icon"), str(MechState.opened_count()),
		"Тайники", "Сундуков открыто за игру.")


func _chip(icon: Texture2D, text: String, title: String, body: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var tr := TextureRect.new()
	tr.texture = icon
	tr.custom_minimum_size = Vector2(18, 18)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tr)
	var l := ProgressUiKit.make_label(text, 11, ProgressUiKit.TEXT_HI)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	_head.add_child(box)
	Tip.bind_tap(box, title, body)


# --- вкладка «руды» -------------------------------------------------------------

func _build_ores() -> Control:
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 4)
	for id in MasteryLogic.kinds():
		var t := JournalTile.new()
		t.item = String(id)
		t.fresh = MechState.mastery_count(t.item) > 0 \
			and MechState.stars_seen(t.item) < maxi(1, MechState.stars_granted(t.item))
		t.custom_minimum_size = Vector2(TILE_W, TILE_H)
		grid.add_child(t)
		_bind_tile_tip(t, String(id))
	return grid


func _bind_tile_tip(t: Control, id: String) -> void:
	var n := MechState.mastery_count(id)
	if n <= 0:
		var y0 := _depth_of(id)
		Tip.bind_tap(t, "Неизвестная порода", "Ещё не добывал." + ("" if y0 <= 0 else " Встречается глубже %d." % y0))
		return
	var stars := MasteryLogic.stars_for(id, n)
	var nxt := MasteryLogic.next_threshold(id, n)
	var body := "Добыто: %d · звёзд %d из 5" % [n, stars]
	if stars > 0:
		body += "\nДвойная добыча: +%d%%" % int(round(MasteryLogic.double_chance(stars) * 100.0))
	var extra := "До звезды: %d" % (nxt - n) if nxt > 0 else "Мастер: все звёзды"
	Tip.bind_tap(t, String(Balance.get_mineral(id).get("name_ru", id)), body, extra)


func _depth_of(id: String) -> int:
	if director != null and director.world != null:
		for ore in director.world._ores:
			if String(ore.get("id", "")) == id:
				return int(ore.get("y_min", 0))
	return 0


# --- вкладка «тайники» ----------------------------------------------------------

func _build_chests() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(212, 0)
	var rows := [
		[Mechanics.tex("chest_wood_icon"), str(MechState.opened_count("wood")), "Деревянный сундук",
			"Лежит в породе с глубины 20. Несколько руд этой глубины, иногда еда."],
		[Mechanics.tex("chest_iron_icon"), str(MechState.opened_count("iron")), "Окованный сундук",
			"С глубины 120. Вдвое богаче деревянного."],
		[Mechanics.tex("chest_gold_icon"), str(MechState.opened_count("gold")), "Золотой сундук",
			"С глубины 300, редкий. Много руды, самоцвет и обед."],
		[Mechanics.tex("fever"), str(MechState.stat("fevers")), "Жадность",
			"Сколько раз шкала азарта доходила до жадности."],
		[UiIcons.tex("plus"), str(MechState.stat("bonus_items")), "Добыча сверху",
			"Сколько штук руды дали жадность и мастерство сверх обычной копки."],
	]
	for r in rows:
		v.add_child(_stat_row(r[0], r[1], r[2], r[3]))
	return v


func _stat_row(icon: Texture2D, num: String, title: String, body: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ProgressUiKit.box(ProgressUiKit.CARD_BG, ProgressUiKit.BORDER, ProgressUiKit.R_TILE))
	p.custom_minimum_size = Vector2(0, 40)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var tr := TextureRect.new()
	tr.texture = icon
	tr.custom_minimum_size = Vector2(32, 32)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tr)
	var l := ProgressUiKit.make_label(num, 16, ProgressUiKit.TEXT_HI)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	Tip.bind_tap(p, title, body)
	return p

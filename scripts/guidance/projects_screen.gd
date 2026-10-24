class_name ProjectsScreen
extends CanvasLayer
## Экран «Проекты»: крупные постройки из материалов и цепочки их материалов.
## Внизу — вкладки-значки проектов (бур, скважина, бурмобиль, костюм) и крестик;
## в теле — карточка проекта (значок, общая полоска, «следить») и строки
## материалов: значок, полоска «есть/нужно» (рюкзак + склад), где копать
## (значок глубины и число, значок бура, если киркой не взять). Промежуточное
## (бронза) — с подстрокой сырья: значок лома → стрелка → бронза и «+N», сколько
## выйдет из лома под рукой. Слов на экране нет: всё — в Tip (тап по строке).
##
## Открывается из меню «•••» (MenuRegistry "projects"), с трекера на HUD и с
## карточки рецепта в мастерской (decorate_card). Пока открыт — герой стоит,
## ввод HUD выключен (как у журнала добытчика).

signal closed
signal track_changed(id: String)

const BAR_W := 104.0
const ROW_H := 34.0
const COL_FILL := Color8(0xE0, 0xA9, 0x3B)
const COL_FILL_VIA := Color8(0xE0, 0xA9, 0x3B, 0x70)
const COL_DONE := Color8(0x7F, 0xD0, 0x6B)
const COL_TRACK := Color8(0x0E, 0x0B, 0x08)

static var _instance: ProjectsScreen = null

var _root: Control
var _scroll: ScrollContainer
var _body: VBoxContainer
var _head: HBoxContainer
var _bar: HBoxContainer
var _tab_buttons: Dictionary = {}
var _current := ""
var _track_btn: Button = null
var _closing := false
var _locked := false
var _was_frozen := false
var _hud_input_was_on := true


static func instance() -> ProjectsScreen:
	return _instance if _instance != null and is_instance_valid(_instance) else null


static func is_open_any() -> bool:
	var s := instance()
	return s != null and s.is_open()


## Открыть экран на проекте id ("" — отслеживаемый или первый открытый).
static func open_for(id: String = "") -> void:
	var s := instance()
	if s != null:
		s.open(id)


func _ready() -> void:
	_instance = self
	layer = 93   # выше мастерской (20) и HUD, рядом с журналом и хабом наград
	_build()
	_root.visible = false


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func is_open() -> bool:
	return _root != null and _root.visible and not _closing


func current() -> String:
	return _current


func open(id: String = "") -> void:
	var list := ProjectChain.ids()
	if list.is_empty():
		return
	if id == "" or not list.has(id):
		id = ProjectChain.tracked()
	if id == "" or not list.has(id):
		var open_ids := ProjectChain.open_ids()
		id = String(open_ids[0]) if not open_ids.is_empty() else String(list[0])
	_current = id
	_build_tabs()
	_closing = false
	_root.visible = true
	_lock(true)
	UiAnim.open(_root, UiAnim.Kind.FADE)
	Sfx.play("ui_open")
	refresh()
	UiAnim.stagger(_body.get_children(), 0.03, 0.9)


func close() -> void:
	if not is_open():
		return
	_closing = true
	_lock(false)
	UiAnim.close(_root, UiAnim.Kind.FADE, null, func() -> void:
		_closing = false
		_root.visible = false)
	Sfx.play("ui_close")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Как у журнала: герой стоит, ввод HUD выключен (иначе джойстик под экраном
## ловит касания раньше строк). Открыли поверх мастерской — она уже всё
## заморозила, и «как было» вернётся ей же.
func _lock(on: bool) -> void:
	if on == _locked:
		return
	_locked = on
	var tree := get_tree()
	if tree == null:
		return
	var player := tree.root.find_child("Player", true, false)
	var hud := tree.get_first_node_in_group("hud")
	if player != null:
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
	_root.name = "ProjectsRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_to_group("hint_block")
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = ProgressUiKit.BG_SOLID
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_head = HBoxContainer.new()
	_head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_head.offset_left = 8
	_head.offset_right = -8
	_head.offset_top = 8
	_head.offset_bottom = 30
	_head.alignment = BoxContainer.ALIGNMENT_CENTER
	_head.add_theme_constant_override("separation", 12)
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

	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(212, 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 5)
	_scroll.add_child(_body)


func _build_tabs() -> void:
	if _bar != null:
		_bar.queue_free()
	var specs: Array = []
	for id in ProjectChain.ids():
		specs.append([String(id), ProjectChain.icon(String(id)), ProjectChain.title(String(id)),
			"Цепочка материалов и где их копать"])
	_bar = HeroTabButton.make_bar(specs, _current, _set_project, close)
	_tab_buttons = _bar.get_meta("buttons")
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_left = 6
	_bar.offset_right = -6
	_bar.offset_top = -(ProgressUiKit.TAB_BAR_H + 4)
	_bar.offset_bottom = -4
	_root.add_child(_bar)


func _set_project(id: String) -> void:
	_current = id
	refresh()
	UiAnim.stagger(_body.get_children(), 0.03, 0.9)


func refresh() -> void:
	for k in _tab_buttons.keys():
		var b: HeroTabButton = _tab_buttons[k]
		b.set_selected(k == _current)
		b.set_badge(1 if ProjectChain.ready(String(k)) else 0)
	_fill_head()
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if _current == "":
		return
	_body.add_child(_project_card(_current))
	for m: Dictionary in ProjectChain.materials(_current):
		_body.add_child(_material_row(m))
		for v: Dictionary in m["via"]:
			_body.add_child(_via_row(m, v))
	if ProjectChain.coins_need(_current) > 0:
		_body.add_child(_coins_row(ProjectChain.coins_need(_current)))


# --- шапка: собрано проектов, монеты ---------------------------------------------

func _fill_head() -> void:
	for c in _head.get_children():
		_head.remove_child(c)
		c.queue_free()
	var all := ProjectChain.ids()
	var built := 0
	for id in all:
		if ProjectChain.is_built(String(id)):
			built += 1
	_chip(Guidance.tex("projects"), "%d/%d" % [built, all.size()], "Проекты",
		"Большие постройки из материалов: бур, скважина, бурмобиль, костюм. Руду для них не продавай — копи на складе.")
	_chip(UiIcons.tex("coin"), ShopArt.compact(GameState.coins), "Монеты", "Сколько монет у тебя сейчас.")


func _chip(icon: Texture2D, text: String, title: String, body: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(_icon_rect(icon, 18))
	var l := ProgressUiKit.make_label(text, 11, ProgressUiKit.TEXT_HI)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	_head.add_child(box)
	Tip.bind_tap(box, title, body)


# --- карточка проекта ------------------------------------------------------------

func _project_card(id: String) -> Control:
	var p := _panel(ProgressUiKit.GOLD if ProjectChain.ready(id) else ProgressUiKit.EDGE)
	p.custom_minimum_size = Vector2(0, 62)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)

	var unlocked := ProjectChain.is_unlocked(id)
	var built := ProjectChain.is_built(id)
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(48, 48)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fr := Panel.new()
	fr.add_theme_stylebox_override("panel", ProgressUiKit.box(ProgressUiKit.INSET_BG,
		ProgressUiKit.GOLD if unlocked else ProgressUiKit.BORDER, ProgressUiKit.R_TILE, 2))
	fr.set_anchors_preset(Control.PRESET_FULL_RECT)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(fr)
	var ic := _icon_rect(ProjectChain.icon(id), 36)
	ic.position = Vector2(6, 6)
	ic.size = Vector2(36, 36)
	if not unlocked:
		ic.modulate = Color(0.12, 0.1, 0.14)
	frame.add_child(ic)
	if not unlocked:
		var lock := _icon_rect(ShopArt.tex("glyph_lock"), 16)
		lock.position = Vector2(16, 16)
		lock.size = Vector2(16, 16)
		frame.add_child(lock)
	elif built:
		var ok := _icon_rect(ShopArt.tex("glyph_check"), 16)
		ok.position = Vector2(34, -2)
		ok.size = Vector2(16, 16)
		frame.add_child(ok)
	h.add_child(frame)

	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 4)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(mid)
	var frac := 1.0 if built else ProjectChain.progress(id)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 4)
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(_bar_ctrl(BAR_W - 8.0, 10.0, frac, 0.0, built or ProjectChain.ready(id)))
	var pct := ProgressUiKit.make_label("%d%%" % int(floor(frac * 100.0)), 11, ProgressUiKit.TEXT_HI)
	pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(pct)
	mid.add_child(bar_row)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(chips)
	if not unlocked:
		chips.add_child(_mini_chip(ShopArt.tex("glyph_depth"), str(int(ProjectChain.def(id)["unlock_depth"])),
			"Откроется глубже", "Рецепт откроется, когда спустишься до %d м. Материалы можно копить уже сейчас." % int(ProjectChain.def(id)["unlock_depth"])))
	var place := String(ProjectChain.def(id).get("where_built", "workshop"))
	if place == "tech":
		chips.add_child(_mini_chip(ProjectChain.load_icon("res://art/tech/icon_tech.png"), "",
			"Где собирать", "Меню «•••» → «Техника», на поверхности или дома."))
	else:
		chips.add_child(_mini_chip(UiIcons.tex("workshop"), "",
			"Где собирать", "Верстак в мастерской (подвал дома), вкладка «Техника». Материалы берутся со склада и из рюкзака."))
	var cnt := ProjectChain.counts(id)
	chips.add_child(_mini_chip(ShopArt.tex("glyph_check"), "%d/%d" % [int(cnt["done"]), int(cnt["total"])],
		"Готово строк", "Сколько материалов (и монеты) уже набрано полностью."))

	_track_btn = UiBtn.icon_button(Guidance.tex("track" if ProjectChain.tracked() == id else "track_off"),
		Vector2(30, 30), UiBtn.Kind.NORMAL, 22)
	_track_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_track_btn.disabled = built
	_track_btn.pressed.connect(func() -> void: _toggle_track(id))
	Tip.bind(_track_btn, "Следить", "Приколоть проект к экрану: маленький значок под кошельком покажет, сколько материалов уже набрано.")
	HintPulse.attach(_track_btn, "projects_track")
	h.add_child(_track_btn)

	var body := "Собран." if built else ("Откроется на глубине %d м." % int(ProjectChain.def(id)["unlock_depth"]) if not unlocked
		else ("Всё есть — собирай!" if ProjectChain.ready(id) else "Копи материалы: не продавай их в мастерской."))
	Tip.bind_tap(p, ProjectChain.title(id), body, "Готово на %d%%" % int(floor(frac * 100.0)))
	return p


func _toggle_track(id: String) -> void:
	if Tip.swallowed():
		return
	var on := ProjectChain.tracked() != id
	ProjectChain.set_tracked(id if on else "", true)
	Sfx.play("ui_toggle")
	Haptics.tap()
	if _track_btn != null:
		_track_btn.icon = Guidance.tex("track" if on else "track_off")
		ShopFx.pop(_track_btn, 0.25, 0.3)
		if on:
			ShopFx.sparkles(_root, _track_btn.get_global_rect().get_center(), ProgressUiKit.GOLD, 10, 26.0)
	track_changed.emit(ProjectChain.tracked())


# --- строки материалов -------------------------------------------------------------

func _material_row(m: Dictionary) -> Control:
	var id := String(m["id"])
	var need := int(m["need"])
	var have := int(m["have"])
	var done := bool(m["done"])
	var p := _panel(ProgressUiKit.GREEN if done else ProgressUiKit.BORDER)
	p.custom_minimum_size = Vector2(0, ROW_H)
	var h := _row_box(p)
	h.add_child(_icon_rect(UiIcons.item_small(id, 24), 24))
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 1)
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var via_frac := clampf(float(int(m["effective"])) / maxf(1.0, float(need)), 0.0, 1.0)
	mid.add_child(_bar_ctrl(BAR_W, 8.0, clampf(float(have) / maxf(1.0, float(need)), 0.0, 1.0), via_frac, done))
	var nums := ProgressUiKit.make_label("%s/%s" % [ShopArt.compact(have), ShopArt.compact(need)], 10,
		COL_DONE if done else ProgressUiKit.TEXT)
	nums.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(nums)
	h.add_child(mid)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	h.add_child(_where_chip(id))

	var bag := GameState.get_item_count(id)
	var store := HouseStorage.count(id)
	var body := "Есть %d из %d: в рюкзаке %d, на складе %d." % [have, need, bag, store]
	if not done and int(m["effective"]) > have:
		body += "\nЕщё %d выйдет из сырья под рукой." % (int(m["effective"]) - have)
	Tip.bind_tap(p, ShopCatalog.item_name(id), body, ProjectChain.where_text(id))
	return p


## Подстрока сырья промежуточного материала: лом → бронза, «+N» и где копать лом.
func _via_row(m: Dictionary, v: Dictionary) -> Control:
	var src := String(v["id"])
	var p := _panel(ProgressUiKit.BORDER)
	p.custom_minimum_size = Vector2(0, 28)
	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 16)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(p)
	var h := _row_box(p)
	h.add_child(_arrow(Vector2(10, 18), true))
	h.add_child(_icon_rect(UiIcons.item_small(src, 18), 18))
	var cnt := ProgressUiKit.make_label(ShopArt.compact(int(v["have"])), 10, ProgressUiKit.TEXT)
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(cnt)
	h.add_child(_arrow(Vector2(14, 18), false))
	h.add_child(_icon_rect(UiIcons.item_small(String(m["id"]), 16), 16))
	var plus := ProgressUiKit.make_label("+%s" % ShopArt.compact(int(v["makes"])), 10,
		ProgressUiKit.GOLD if int(v["makes"]) > 0 else ProgressUiKit.DIM)
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(plus)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	h.add_child(_where_chip(src))
	var name_src := ShopCatalog.item_name(src)
	var name_out := ShopCatalog.item_name(String(m["id"]))
	Tip.bind_tap(p, "%s → %s" % [name_src, name_out],
		"%s плавится в %s на верстаке в мастерской: %d к %d. Не продавай %s — он нужен для «%s»." % [
			name_src, name_out.to_lower(), int(v["per"]), int(v["out"]), name_src.to_lower(), ProjectChain.title(_current)],
		ProjectChain.where_text(src))
	return outer


func _coins_row(need: int) -> Control:
	var have := GameState.coins
	var done := have >= need
	var p := _panel(ProgressUiKit.GREEN if done else ProgressUiKit.BORDER)
	p.custom_minimum_size = Vector2(0, ROW_H)
	var h := _row_box(p)
	h.add_child(_icon_rect(UiIcons.tex("coin"), 22))
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 1)
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(_bar_ctrl(BAR_W, 8.0, clampf(float(have) / maxf(1.0, float(need)), 0.0, 1.0), 0.0, done))
	var nums := ProgressUiKit.make_label("%s/%s" % [ShopArt.compact(have), ShopArt.compact(need)], 10,
		COL_DONE if done else ProgressUiKit.TEXT)
	nums.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(nums)
	h.add_child(mid)
	Tip.bind_tap(p, "Монеты", "Сборка стоит ещё и монет: %s из %s." % [ShopArt.full(mini(have, need)), ShopArt.full(need)])
	return p


## Где копать: значок глубины и число (где больше всего), значок бура — если
## киркой не взять; у переплавляемого — молоток верстака.
func _where_chip(item: String) -> Control:
	var w := ProjectChain.where(item)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if bool(w["crafted"]):
		box.add_child(_icon_rect(ShopArt.tex("glyph_hammer"), 14))
		return box
	box.add_child(_icon_rect(ShopArt.tex("glyph_depth"), 12))
	var reached := GameState.max_depth_reached >= int(w["min"])
	var l := ProgressUiKit.make_label(ShopArt.compact(int(w["best"])), 10,
		ProgressUiKit.TEXT_HI if reached else ProgressUiKit.DIM)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	if String(w["tool"]) != "":
		var t := _icon_rect(ShopArt.load_path(Balance.get_tool_icon(String(w["tool"]))), 14)
		if not GameState.owns_tool(String(w["tool"])):
			t.modulate = Color(1, 0.55, 0.5)
		box.add_child(t)
	return box


# --- кирпичики ---------------------------------------------------------------------

func _panel(border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := ProgressUiKit.box(ProgressUiKit.CARD_BG, border, ProgressUiKit.R_TILE)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _row_box(p: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	return h


func _icon_rect(tex: Texture2D, px: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _mini_chip(icon: Texture2D, text: String, title: String, body: String) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(_icon_rect(icon, 14))
	if text != "":
		var l := ProgressUiKit.make_label(text, 10, ProgressUiKit.TEXT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	Tip.bind_tap(box, title, body)
	return box


## Полоска «есть/нужно»: сплошная — сам материал, полупрозрачная — сколько ещё
## выйдет из сырья (лом → бронза). done — зелёная.
func _bar_ctrl(w: float, h: float, frac: float, via_frac: float, done: bool) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, c.size)
		c.draw_rect(r, COL_TRACK)
		var inner := r.grow(-1.0)
		if via_frac > frac:
			c.draw_rect(Rect2(inner.position, Vector2(floorf(inner.size.x * via_frac), inner.size.y)), COL_FILL_VIA)
		if frac > 0.0:
			var col := COL_DONE if done else COL_FILL
			c.draw_rect(Rect2(inner.position, Vector2(maxf(1.0, floorf(inner.size.x * frac)), inner.size.y)), col)
			c.draw_rect(Rect2(inner.position, Vector2(maxf(1.0, floorf(inner.size.x * frac)), 1.0)), col.lightened(0.35))
		c.draw_rect(r, ProgressUiKit.EDGE, false, 1.0))
	return c


## Стрелка цепочки: «↳» в начале подстроки (hook) или «→» между сырьём и материалом.
func _arrow(sz: Vector2, hook: bool) -> Control:
	var c := Control.new()
	c.custom_minimum_size = sz
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var col := ProgressUiKit.GOLD
		var y := sz.y * 0.5
		if hook:
			c.draw_line(Vector2(2, 1), Vector2(2, y), col, 2.0)
			c.draw_line(Vector2(2, y), Vector2(sz.x - 1, y), col, 2.0)
		else:
			c.draw_line(Vector2(1, y), Vector2(sz.x - 2, y), col, 2.0)
			c.draw_line(Vector2(sz.x - 6, y - 4), Vector2(sz.x - 2, y), col, 2.0)
			c.draw_line(Vector2(sz.x - 6, y + 4), Vector2(sz.x - 2, y), col, 2.0))
	return c


# ---------------------------------------------------------------------------
# Вход с карточки рецепта в мастерской
# ---------------------------------------------------------------------------

## Кнопка «цепочка» в правом верхнем углу карточки рецепта-проекта (мастерская):
## открывает этот экран на нужном проекте. Одна строка в ShopUI._open_card —
## саму карточку (её правит ветка craft-qty) не трогаем.
static func decorate_card(panel: Control, offer: Dictionary) -> void:
	if panel == null or String(offer.get("kind", "")) != "recipe":
		return
	var id := String(offer.get("ref", ""))
	if not ProjectChain.ids().has(id) or instance() == null:
		return
	var host := panel.get_parent() as Control
	if host == null:
		return
	# Плашка — контейнер и сама раскладывает детей, поэтому кнопка живёт рядом с
	# ней (в слое карточки) и едет за её правым верхним углом.
	var b := UiBtn.icon_button(Guidance.tex("projects"), Vector2(26, 26), UiBtn.Kind.NORMAL, 18)
	b.name = "ProjectsChainButton"
	var place := func() -> void:
		if is_instance_valid(b) and is_instance_valid(panel):
			b.position = panel.position + Vector2(panel.size.x - 24.0, -13.0)
	panel.item_rect_changed.connect(place)
	b.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		open_for(id))
	Tip.bind(b, "Цепочка материалов", "Из чего собирается, что уже есть и где копать.")
	host.add_child(b)
	place.call()

class_name DeathWindow
extends CanvasLayer
## Окно смерти (ГДД §7 «Цена смерти»). Владелец, разбор чисел 26.10: «Просто когда
## умираешь, покажи окно в котором написано, ты умер — причина смерти (с голоду, от
## падения, сгорел, убит мобом…), потеряно — список и изображения предметов,
## потрачено на больницу денег».
##
## Сверху вниз: «Ты умер», причина (значок + фраза, под ней глубина), потерянный
## рюкзак плитками (значок и ×N, название — в Tip), плата больнице, кнопка «Дальше».
## Правила смерти окно только показывает: рюкзак и 5% монет (от 50 до 5000) забрал
## GameState.die(), причину назвал добивший удар (DeathCause), полоски после смерти —
## Healing.respawn_after_death(). Сюжетная смерть онбординга (§9) — своя сцена.
## Открывает FeelDirector, когда герой уже дома; закрывается только кнопкой, тапом
## мимо окна или Esc — текст надо успеть прочитать.

signal closed

const PER_ROW := 4
const MAX_TILES := 12
const TILE := 42.0
const WIDTH := 204.0
## Тап, которым игрок ещё «добивал» породу, не должен сразу закрыть окно.
const CLOSE_GUARD_MS := 400

## Открыто ли окно где-то в игре: HUD не ведёт героя пальцем под ним.
static var _open_any := false

var _root: Control = null
var _card: PanelContainer = null
var _closing := false   # окно уходит: закрыто по смыслу, но ещё видно
var _report: Dictionary = {}
var _opened_ms := 0


## Отчёт о смерти — чистые данные (их проверяет тест): cause — GameState.death_cause,
## lost — «предмет → штук» (GameState.death_lost), fee — плата больнице.
static func build_report(lost: Dictionary, death_depth: int, cause: Dictionary, fee: int) -> Dictionary:
	var rows: Array = []
	for id in lost.keys():
		var n := int(lost[id])
		if n <= 0:
			continue
		var price := Balance.get_mineral_price(String(id))
		rows.append({"id": String(id), "count": n, "value": price * n})
	# дорогое первым: что обиднее всего потерять, видно сразу
	rows.sort_custom(func(a, b): return a["value"] > b["value"] or (a["value"] == b["value"] and String(a["id"]) < String(b["id"])))
	return {
		"lost": rows,
		"depth": maxi(death_depth, 0),
		"cause": cause.duplicate(),
		"phrase": DeathCause.phrase(cause),
		"fee": maxi(fee, 0),
	}


## Отчёт последней смерти прямо из GameState и Healing.
static func report_now() -> Dictionary:
	return build_report(GameState.death_lost, GameState.player_depth, GameState.death_cause, Healing.last_death_fee)


static func is_open_any() -> bool:
	return _open_any


func _ready() -> void:
	layer = UiLayers.DEATH   # выше HUD и шторок, ниже окна дня (94) и катсцен (100)
	visible = false
	add_to_group("hint_block")


func _exit_tree() -> void:
	if visible:
		_open_any = false   # статика переживает перезагрузку сцены


func is_open() -> bool:
	return visible and not _closing


func report() -> Dictionary:
	return _report


func open(report_data: Dictionary) -> void:
	_report = report_data
	Tip.hide_all()   # подсказка, открытая до смерти, не светится поверх окна
	_build()
	_closing = false
	visible = true
	_open_any = true
	_opened_ms = Time.get_ticks_msec()
	Sfx.play("ui_open", 0.9)
	if _card != null:
		UiAnim.open(_card, UiAnim.Kind.POP, _root)


func close() -> void:
	if not is_open():
		return
	_open_any = false
	_closing = true
	var finish := func() -> void:
		if not _closing:
			return
		_closing = false
		visible = false
		if _root != null:
			_root.queue_free()
			_root = null
	if _card != null and _root != null:
		UiAnim.close(_card, UiAnim.Kind.POP, _root, finish)
	else:
		finish.call()
	closed.emit()


func _close_by_player() -> void:
	if Time.get_ticks_msec() - _opened_ms < CLOSE_GUARD_MS:
		return
	close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close_by_player()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Вёрстка
# ---------------------------------------------------------------------------

func _build() -> void:
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "DeathRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.0, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_close_by_player())
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_card = PanelContainer.new()
	_card.name = "Card"
	var sb := MetaUiKit.box(MetaUiKit.CARD, MetaUiKit.RED, 2, 6)
	sb.set_content_margin_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 4
	_card.add_theme_stylebox_override("panel", sb)
	_card.custom_minimum_size = Vector2(WIDTH, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_card.add_child(box)
	box.add_child(_build_title())
	box.add_child(_divider())
	box.add_child(_build_cause())
	box.add_child(_build_lost())
	box.add_child(_divider())
	box.add_child(_build_hospital())
	box.add_child(_build_button())


func _build_title() -> Control:
	var h := HBoxContainer.new()
	h.name = "Title"
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 6)
	h.add_child(MetaUiKit.icon_rect(MetaUiKit.tex("skull"), 26))
	var t := MetaUiKit.label(DeathCause.text("title"), UiTheme.FS_HERO_L, Color8(0xFF, 0x8A, 0x9A))
	t.name = "TitleText"
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t)
	return h


func _section(text: String) -> Label:
	return MetaUiKit.label(text, UiTheme.FS_SMALL, MetaUiKit.MUTED)


func _divider() -> Control:
	var r := ColorRect.new()
	r.color = MetaUiKit.BORDER
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _build_cause() -> Control:
	var cause: Dictionary = _report.get("cause", {})
	var v := VBoxContainer.new()
	v.name = "Cause"
	v.add_theme_constant_override("separation", 3)
	v.add_child(_section(DeathCause.text("cause")))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(h)
	var slot := PanelContainer.new()
	slot.name = "CauseIcon"
	slot.custom_minimum_size = Vector2(34, 34)
	slot.add_theme_stylebox_override("panel", MetaUiKit.box(MetaUiKit.SLOT, MetaUiKit.RED.darkened(0.15), 1, 3))
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic := MetaUiKit.icon_rect(DeathCause.icon(cause), 28)
	slot.add_child(ic)
	h.add_child(slot)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(texts)
	var phrase := MetaUiKit.label(_typo(DeathCause.phrase(cause, true)), UiTheme.FS_LABEL, Color.WHITE)
	phrase.name = "CauseText"
	phrase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phrase.custom_minimum_size = Vector2(WIDTH - 16 - 4 - 34 - 6, 0)
	texts.add_child(phrase)
	var depth := int(_report.get("depth", 0))
	if depth > 0:
		var d := MetaUiKit.label(DeathCause.text("depth") % depth, UiTheme.FS_SMALL, MetaUiKit.MUTED)
		d.name = "CauseDepth"
		texts.add_child(d)
	var hint := DeathCause.hint(cause)
	if hint != "":
		Tip.bind(slot, DeathCause.text("cause"), hint)
	return v


## Короткий предлог не остаётся в конце строки («с / высоты»): неразрывный пробел после него.
static func _typo(s: String) -> String:
	var re := RegEx.create_from_string("(^|\\s)(с|в|к|о|у|от|из|на|по|при|of|a) ")
	var out := s
	for _i in 3:   # соседние предлоги перекрываются: «при падении с высоты»
		out = re.sub(out, "$1$2\u00a0", true)
	return out


func _build_lost() -> Control:
	var lost: Array = _report.get("lost", [])
	var v := VBoxContainer.new()
	v.name = "Lost"
	v.add_theme_constant_override("separation", 3)
	v.add_child(_section(DeathCause.text("lost")))
	if lost.is_empty():
		var h := HBoxContainer.new()
		h.name = "Empty"
		h.add_theme_constant_override("separation", 5)
		h.add_child(MetaUiKit.icon_rect(UiIcons.tex("backpack"), 18))
		h.add_child(MetaUiKit.label(DeathCause.text("empty_pack"), UiTheme.FS_LABEL, Color.WHITE))
		v.add_child(h)
		return v
	var grid := GridContainer.new()
	grid.name = "Items"
	grid.columns = PER_ROW
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var overflow := lost.size() > MAX_TILES
	var shown := MAX_TILES - 1 if overflow else lost.size()
	for i in shown:
		var e: Dictionary = lost[i]
		grid.add_child(_item_tile(String(e["id"]), int(e["count"])))
	if overflow:
		var more := PanelContainer.new()
		more.name = "More"
		more.custom_minimum_size = Vector2(TILE, TILE)
		more.add_theme_stylebox_override("panel", MetaUiKit.box(MetaUiKit.SLOT, MetaUiKit.BORDER, 1, 3))
		var cc := CenterContainer.new()
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(MetaUiKit.label("+%d" % (lost.size() - shown), UiTheme.FS_TITLE, Color.WHITE))
		more.add_child(cc)
		var rest: Array = []
		for i in range(shown, lost.size()):
			rest.append("%s ×%d" % [_item_name(String(lost[i]["id"])), int(lost[i]["count"])])
		Tip.bind(more, DeathCause.text("lost"), ", ".join(rest))
		grid.add_child(more)
	return v


func _item_tile(id: String, count: int) -> Control:
	var tile := PanelContainer.new()
	tile.name = "Item_" + id
	tile.custom_minimum_size = Vector2(TILE, TILE)
	tile.add_theme_stylebox_override("panel", MetaUiKit.box(MetaUiKit.SLOT, MetaUiKit.RED.darkened(0.15), 1, 3))
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(holder)
	var ic := MetaUiKit.icon_rect(UiIcons.item(id), 26)
	ic.position = Vector2(7, 3)
	ic.size = Vector2(26, 26)
	holder.add_child(ic)
	var n := MetaUiKit.label("×%d" % count, UiTheme.FS_BODY, Color.WHITE)
	n.name = "Count"
	n.position = Vector2(2, 26)
	n.size = Vector2(36, 12)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(n)
	Tip.bind(tile, _item_name(id), "×%d" % count)
	return tile


static func _item_name(id: String) -> String:
	var m := Balance.get_mineral(id)
	if DeathCause.lang() != "ru" and String(m.get("name_" + DeathCause.lang(), "")) != "":
		return String(m["name_" + DeathCause.lang()])
	return String(m.get("name_ru", id))


## «Потрачено на больницу  −214»: плата 5% монет, от 50 до 5000 (Healing).
func _build_hospital() -> Control:
	var fee := int(_report.get("fee", 0))
	var h := HBoxContainer.new()
	h.name = "Hospital"
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(MetaUiKit.icon_rect(UiIcons.tex("hospital"), 20))
	var l := MetaUiKit.label(DeathCause.text("hospital"), UiTheme.FS_BODY, Color.WHITE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	# число целиком: плата не больше 5000, четыре цифры влезают, а «−5k» читается хуже
	var chip := MetaUiKit.chip(MetaUiKit.tex("coin"), ("−%d" % fee) if fee > 0 else "0",
			MetaUiKit.RED.lightened(0.45) if fee > 0 else MetaUiKit.MUTED, 14, UiTheme.FS_TITLE)
	chip.name = "Fee"
	h.add_child(chip)
	var lo := Healing.death_fee_min()
	var tip := DeathCause.text("hospital_none") if fee <= 0 else \
			DeathCause.text("hospital_tip") % [_pct_text(), lo, Healing.death_fee_max(), lo]
	Tip.bind(h, DeathCause.text("hospital"), tip, ("−%d" % fee) if fee > 0 else "0")
	return h


static func _pct_text() -> String:
	var p := Healing.death_fee_percent()
	return str(int(p)) if is_equal_approx(p, roundf(p)) else str(snappedf(p, 0.1))


func _build_button() -> Control:
	var b := Button.new()
	b.name = "Next"
	b.text = DeathCause.text("next")
	b.icon = MetaUiKit.tex("check")
	b.add_theme_constant_override("icon_max_width", 18)
	b.add_theme_font_size_override("font_size", UiTheme.FS_TITLE_L)
	b.custom_minimum_size = Vector2(0, 32)
	UiBtn.style(b, UiBtn.Kind.ACCENT)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		close())
	Tip.bind(b, DeathCause.text("next"), DeathCause.text("next_tip"))
	return b

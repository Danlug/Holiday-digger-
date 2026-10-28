class_name MetaHub
extends CanvasLayer
## Экран «Награды»: три вкладки-значка — задания, достижения, дорога трофеев.
## На плитках только значки и числа; названия, описания и размер награды — в
## подсказке Tip (мышь: наведение; палец: долгое нажатие).
##
## Весь экран пересобирается при каждом изменении (refresh): состояние живёт в
## MetaState, а не в узлах, так что рассинхрона не бывает. Позиция прокрутки
## сохраняется.

signal closed

const TAB_TASKS := "tasks"
const TAB_ACH := "ach"
const TAB_ROAD := "road"
const TAB_ICONS := {TAB_TASKS: "clipboard", TAB_ACH: "medal", TAB_ROAD: "trophy"}
const TAB_TIPS := {
	TAB_TASKS: ["Задания", "Три ежедневных и два недельных. Выполнил — забери награду."],
	TAB_ACH: ["Достижения", "Награда приходит сразу, как только условие выполнено."],
	TAB_ROAD: ["Дорога трофеев", "Очки за достижения и задания открывают ступени с наградами."],
}
const ACH_COLS := 4
const ACH_W := 48.0
const ACH_H := 56.0
const STEP_W := 56.0

var _root: Control = null
var _tab: String = TAB_TASKS
var _tab_buttons: Dictionary = {}
var _scroll: ScrollContainer = null
var _vbox: VBoxContainer = null
var _chips: Dictionary = {}
var _wallet_labels: Dictionary = {}
var _timers: Array = []
var _tick: float = 0.0
var _new_ach: Dictionary = {}
var _road_scroll: MetaHScroll = null
var _road_centered: bool = false
var _closing: bool = false   # хаб гаснет (анимация): по смыслу уже закрыт


func _ready() -> void:
	add_to_group("meta_hub")
	layer = UiLayers.META  # выше HUD, дома и шторок; ниже окна ежедневной награды (94) и экрана героя (95)
	_build()
	_root.visible = false
	GameState.coins_changed.connect(_on_wallet_changed)
	GameState.dollars_changed.connect(_on_wallet_changed)


func _on_wallet_changed(_v: int) -> void:
	_sync_wallet()


func is_open() -> bool:
	return _root != null and _root.visible and not _closing


func current_tab() -> String:
	return _tab


func open(tab: String = "") -> void:
	if tab != "":
		_tab = tab
	_new_ach.clear()
	for a in MetaData.achievements():
		if Achievements.is_unseen(String(a["id"])):
			_new_ach[String(a["id"])] = true
	_road_centered = false
	_closing = false
	_root.visible = true
	UiAnim.open(_root, UiAnim.Kind.FADE)
	Sfx.play("ui_open")
	refresh()
	UiAnim.stagger(_vbox.get_children(), 0.045, 0.92)


func close() -> void:
	if not is_open():
		return
	Achievements.mark_all_seen()
	_closing = true
	UiAnim.close(_root, UiAnim.Kind.FADE, null, func() -> void: _closing = false)
	Sfx.play("ui_close")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open():
		return
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_update_timers()


# ---------------------------------------------------------------------------
# Каркас
# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "MetaRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = ProgressUiKit.BG_SOLID
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	# Вкладки внизу, в зоне большого пальца и в том же виде, что у экрана героя.
	var specs: Array = []
	for t in [TAB_TASKS, TAB_ACH, TAB_ROAD]:
		specs.append([t, MetaUiKit.tex(TAB_ICONS[t]), TAB_TIPS[t][0], TAB_TIPS[t][1]])
	var bar := HeroTabButton.make_bar(specs, _tab, _set_tab)
	var sb := HudSafeArea.bottom(get_viewport())
	_tab_buttons = bar.get_meta("buttons")
	for t in _tab_buttons.keys():
		(_tab_buttons[t] as HeroTabButton).badge_color = Color8(0xD0, 0x45, 0x3C)   # красный: есть что забрать
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 6
	bar.offset_right = -6
	bar.offset_top = -(ProgressUiKit.TAB_BAR_H + 4 + sb)
	bar.offset_bottom = -4 - sb
	_root.add_child(bar)

	var wallet := HBoxContainer.new()
	wallet.set_anchors_preset(Control.PRESET_TOP_WIDE)
	wallet.offset_left = 8
	wallet.offset_right = -UiBtn.CLOSE_ROW
	wallet.offset_top = 8
	wallet.offset_bottom = 26
	wallet.add_theme_constant_override("separation", 10)
	_root.add_child(wallet)
	for k in [["coins", "coin", "Монеты"], ["dollars", "dollar", "Доллары"], ["points", "star", "Очки трофеев"]]:
		var chip := MetaUiKit.chip(MetaUiKit.tex(k[1]), "0", MetaUiKit.GOLD_LIGHT, 14, 10)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		Tip.bind(chip, k[2])
		wallet.add_child(chip)
		_chips[k[0]] = chip
		_wallet_labels[k[0]] = chip.get_child(1)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 8
	_scroll.offset_right = -8
	_scroll.offset_top = UiBtn.CLOSE_ROW
	_scroll.offset_bottom = -(ProgressUiKit.TAB_BAR_H + 10 + sb)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(_scroll)
	DragScroll.attach(_scroll)
	UiBtn.close_button(close, _root)
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 5)
	_scroll.add_child(_vbox)


func _set_tab(t: String) -> void:
	if t == _tab:
		return
	if _tab == TAB_ACH:
		Achievements.mark_all_seen()
	_tab = t
	_road_centered = false
	_scroll.scroll_vertical = 0
	refresh()   # звук и вибро вкладки — в HeroTabButton.make_bar
	UiAnim.stagger(_vbox.get_children(), 0.035, 0.94)


func refresh() -> void:
	if _root == null or not is_open():
		return
	var keep := _scroll.scroll_vertical
	var keep_h := _road_scroll.scroll_horizontal if _road_scroll != null and is_instance_valid(_road_scroll) else -1
	for c in _vbox.get_children():
		_vbox.remove_child(c)
		c.queue_free()
	_timers.clear()
	_road_scroll = null
	match _tab:
		TAB_TASKS:
			_build_tasks()
		TAB_ACH:
			_build_ach()
		TAB_ROAD:
			_build_road()
	for t in _tab_buttons.keys():
		(_tab_buttons[t] as HeroTabButton).set_selected(t == _tab)
	(_tab_buttons[TAB_TASKS] as HeroTabButton).set_badge(QuestEngine.claimable_count())
	(_tab_buttons[TAB_ACH] as HeroTabButton).set_badge(Achievements.unseen_count() if _tab != TAB_ACH else 0)
	(_tab_buttons[TAB_ROAD] as HeroTabButton).set_badge(TrophyRoad.claimable().size())
	_sync_wallet()
	_update_timers()
	_scroll.scroll_vertical = keep
	if _road_scroll != null and keep_h >= 0:
		_road_scroll.scroll_horizontal = keep_h


func _sync_wallet() -> void:
	if _wallet_labels.is_empty():
		return
	(_wallet_labels["coins"] as Label).text = UiFmt.short(GameState.coins)
	(_wallet_labels["dollars"] as Label).text = str(GameState.dollars)
	(_wallet_labels["points"] as Label).text = str(TrophyRoad.points())


## Куда лететь наградам внутри хаба: HUD под экраном закрыт, летим в свой кошелёк.
func _anchors() -> Dictionary:
	var out := {}
	for k in ["coins", "dollars"]:
		var c: Control = _chips[k]
		out[k] = c.global_position + Vector2(8, c.size.y * 0.5)
	out["xp"] = out["coins"]
	return out


func _center(c: Control) -> Vector2:
	return c.global_position + c.size * 0.5


@warning_ignore("integer_division")
func _update_timers() -> void:
	for t in _timers:
		var l: Label = t["label"]
		if not is_instance_valid(l):
			continue
		if t["kind"] == "day":
			var s := MetaClock.seconds_to_next_day()
			l.text = "%02d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
		else:
			l.text = "%dд" % MetaClock.days_left_in_week(MetaState.today())


func _section_head(glyph: String, tip_title: String, tip_body: String, kind: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var ic := MetaUiKit.icon_rect(MetaUiKit.tex(glyph), 20)
	h.add_child(ic)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(gap)
	var chip := MetaUiKit.chip(MetaUiKit.tex("clock"), "", MetaUiKit.MUTED, 13, 9)
	h.add_child(chip)
	_timers.append({"label": chip.get_child(1), "kind": kind})
	Tip.bind(h, tip_title, tip_body)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h


func _cta(icon_name: String, size: Vector2, color: Color, text: String = "") -> Button:
	var b := Button.new()
	b.icon = MetaUiKit.tex(icon_name)
	b.text = text
	b.add_theme_constant_override("icon_max_width", 16)
	b.add_theme_font_size_override("font_size", 10)
	b.custom_minimum_size = size
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := MetaUiKit.box(color, MetaUiKit.GOLD if st == "hover" else color.lightened(0.25), 1, 5)
		if st == "pressed":
			sb.bg_color = color.darkened(0.2)
		sb.set_content_margin_all(3)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.focus_mode = Control.FOCUS_NONE
	UiBtn.wire_feedback(b)
	return b


# ---------------------------------------------------------------------------
# Вкладка «Задания»
# ---------------------------------------------------------------------------

func _build_tasks() -> void:
	var qs := MetaState.sub("quests")
	var daily: Array = qs["daily"]
	var weekly: Array = qs["weekly"]
	if daily.is_empty() and weekly.is_empty():
		var lock := MetaUiKit.icon_rect(MetaUiKit.tex("lock"), 32)
		lock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_vbox.add_child(lock)
		return
	_vbox.add_child(_section_head("calendar", "Ежедневные", "Новые задания каждый день в полночь. Справа — время до обновления.", "day"))
	_vbox.add_child(_bonus_card())
	for q in daily:
		_vbox.add_child(_quest_card(q))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 4)
	_vbox.add_child(sp)
	_vbox.add_child(_section_head("chest", "Недельные", "Крупнее и щедрее. Обновляются в понедельник. Справа — дней до обновления.", "week"))
	for q in weekly:
		_vbox.add_child(_quest_card(q))


func _quest_card(q: Dictionary) -> Control:
	var done := QuestEngine.is_done(q)
	var claimed := bool(q["claimed"])
	var claimable := done and not claimed
	var target := maxi(1, int(q["target"]))
	var frac := float(mini(int(q["progress"]), target)) / float(target)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 46)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := MetaUiKit.box(MetaUiKit.CARD, MetaUiKit.GOLD if claimable else MetaUiKit.BORDER, 2 if claimable else 1, 4)
	sb.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	card.add_child(h)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(38, 38)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := MetaRing.new()
	ring.size = Vector2(38, 38)
	ring.ring_color = MetaUiKit.GREEN if done else MetaUiKit.GOLD
	holder.add_child(ring)
	ring.value = frac
	var g := MetaUiKit.icon_rect(MetaUiKit.tex(String(q["glyph"])), 32)
	g.position = Vector2(3, 3)
	if claimed:
		g.modulate = Color(0.55, 0.55, 0.55)
	holder.add_child(g)
	if claimed:
		# Забранная миссия дня — её звезда (как в окне заданий), недельная — галочка.
		var ck := MetaUiKit.icon_rect(MetaUiKit.tex("star" if String(q["kind"]) == "daily" else "check"), 18)
		ck.position = Vector2(20, 20)
		holder.add_child(ck)
	h.add_child(holder)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 3)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := MetaBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.frac = frac
	bar.text = "%s/%s" % [UiFmt.short(mini(int(q["progress"]), target)), UiFmt.short(target)]
	bar.fill_color = MetaUiKit.GREEN if done else MetaUiKit.GOLD
	mid.add_child(bar)
	# Награда с долларом (недельное) рядом с «Забрать» и «×2» не влезает в ширину
	# экрана: ряд значков обрезается справа, а не раздвигает плитку за край
	# (полностью она — в подсказке).
	var rr_box := ScrollContainer.new()
	rr_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	rr_box.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rr_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rr_box.add_child(MetaUiKit.reward_row(q["reward"], 12, 9))
	mid.add_child(rr_box)
	h.add_child(mid)

	var qid := String(q["id"])
	if claimable:
		var claim := _cta("check", Vector2(30, 34), MetaUiKit.GREEN_BTN)
		claim.pressed.connect(func() -> void: _claim_quest(qid, 1.0, claim))
		Tip.bind(claim, "Забрать награду")
		h.add_child(claim)
		if MetaAds.can(MetaAds.QUEST):
			var ad := _cta("ad", Vector2(36, 34), Color8(0x3C, 0x3A, 0x1A), "×2")
			ad.pressed.connect(func() -> void: _claim_quest_ad(qid, ad))
			Tip.bind(ad, "Удвоить за ролик", "Монеты и опыт ×2. Доллары и очки не удваиваются.",
				"Осталось сегодня: %d" % MetaAds.uses_left(MetaAds.QUEST))
			h.add_child(ad)

	var tip_extra := MetaRewards.describe(q["reward"])
	Tip.bind(card, QuestGen.title(q), QuestGen.description(q), "Награда: %s" % tip_extra)
	return card


func _claim_quest(qid: String, mult: float, from: Control) -> void:
	if Tip.swallowed():
		return
	var origin := _center(from)
	var res := QuestEngine.claim(qid, mult)
	if not bool(res["ok"]):
		return
	MetaFx.claim(get_tree(), origin, res["reward"], false, _anchors(), true)
	_after_claim()


func _claim_quest_ad(qid: String, from: Control) -> void:
	if Tip.swallowed():
		return
	if not MetaAds.request(MetaAds.QUEST, func() -> void: _claim_quest(qid, 2.0, from)):
		UiAnim.shake(from)
		Sfx.play("ui_deny")


## Сундук звёзд: шкала звёзд дня (0…13, засечка на 10) и что в сундуке.
func _bonus_card() -> Control:
	var ds: Array = MetaState.sub("quests")["daily"]
	var ready := QuestEngine.bonus_ready()
	var taken := bool(MetaState.sub("quests")["bonus_claimed"])
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 40)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := MetaUiKit.box(MetaUiKit.CARD, MetaUiKit.GOLD if ready else MetaUiKit.BORDER, 2 if ready else 1, 4)
	sb.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	card.add_child(h)
	var ic := MetaUiKit.icon_rect(MetaUiKit.tex("chest_open" if (ready or taken) else "chest"), 32)
	if taken:
		ic.modulate = Color(0.55, 0.55, 0.55)
	h.add_child(ic)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 3)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := MetaStarTrack.new()
	track.custom_minimum_size = Vector2(0, 13)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.total = maxi(1, ds.size())
	track.needed = QuestEngine.stars_needed()
	track.stars = QuestEngine.stars_today()
	mid.add_child(track)
	var reward := QuestEngine.bonus_reward()
	mid.add_child(MetaUiKit.reward_row(reward, 12, 9))
	h.add_child(mid)
	if ready:
		var claim := _cta("check", Vector2(30, 32), MetaUiKit.GREEN_BTN)
		claim.pressed.connect(func() -> void:
			if Tip.swallowed():
				return
			var origin := _center(claim)
			var res := QuestEngine.claim_bonus()
			if bool(res["ok"]):
				MetaFx.claim(get_tree(), origin, res["reward"], true, _anchors(), true)
				_after_claim())
		Tip.bind(claim, "Открыть сундук звёзд")
		h.add_child(claim)
	elif taken:
		h.add_child(MetaUiKit.icon_rect(MetaUiKit.tex("check"), 22))
	Tip.bind(card, "Сундук звёзд", "За каждую забранную миссию дня — звезда. %d звёзд открывают сундук." % QuestEngine.stars_needed(),
		MetaRewards.describe(reward))
	return card


func _after_claim() -> void:
	var svc := MetaService.instance
	if svc != null:
		svc.after_change()
	refresh()


# ---------------------------------------------------------------------------
# Вкладка «Достижения»
# ---------------------------------------------------------------------------

func _build_ach() -> void:
	var all := MetaData.achievements()
	var done := Achievements.done_count()

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(46, 46)
	var ring := MetaRing.new()
	ring.size = Vector2(46, 46)
	ring.width = 3.0
	holder.add_child(ring)
	ring.value = float(done) / float(maxi(1, all.size()))
	var medal := MetaUiKit.icon_rect(MetaUiKit.tex("medal"), 32)
	medal.position = Vector2(7, 7)
	holder.add_child(medal)
	top.add_child(holder)
	var count := MetaUiKit.label("%d/%d" % [done, all.size()], 16, MetaUiKit.GOLD_LIGHT)
	top.add_child(count)
	Tip.bind(top, "Достижения", "Получено из всех.", "%d из %d" % [done, all.size()])
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	_vbox.add_child(top)

	var grid := GridContainer.new()
	grid.columns = ACH_COLS
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_vbox.add_child(grid)
	for a in all:
		grid.add_child(_ach_tile(a))


func _ach_tile(a: Dictionary) -> Control:
	var id := String(a["id"])
	var tier := clampi(int(a["tier"]), 1, 3)
	var tcol: Color = MetaUiKit.TIER_COL[tier - 1]
	var got := Achievements.is_done(id)
	var pr := Achievements.progress(a)
	var started := pr.x > 0
	var frac := float(pr.x) / float(maxi(1, pr.y))

	var t := Panel.new()
	t.custom_minimum_size = Vector2(ACH_W, ACH_H)
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	var border := tcol if got else (MetaUiKit.GOLD.darkened(0.45) if started else MetaUiKit.BORDER)
	t.add_theme_stylebox_override("panel", MetaUiKit.box(Color8(0x2C, 0x24, 0x34) if got else MetaUiKit.SLOT, border, 2 if got else 1, 4))

	var ring := MetaRing.new()
	ring.size = Vector2(44, 44)
	ring.position = Vector2(2, 2)
	ring.ring_color = tcol if got else MetaUiKit.GOLD
	ring.track_color = Color(0, 0, 0, 0.35)
	t.add_child(ring)
	ring.value = 1.0 if got else frac

	var g := MetaUiKit.icon_rect(MetaUiKit.tex(String(a["glyph"])), 32)
	g.position = Vector2(8, 8)
	if got:
		g.modulate = Color.WHITE
	elif started:
		g.modulate = Color(0.62, 0.62, 0.62)
	else:
		g.modulate = Color(0.16, 0.14, 0.13)
	t.add_child(g)

	if got:
		var ck := MetaUiKit.icon_rect(MetaUiKit.tex("check"), 16)
		ck.position = Vector2(30, 28)
		t.add_child(ck)
		var pts := MetaUiKit.chip(MetaUiKit.tex("star"), str(MetaData.points_for_tier(tier)), MetaUiKit.GOLD_LIGHT, 10, 8)
		pts.position = Vector2(12, 44)
		t.add_child(pts)
		if _new_ach.has(id):
			var dot := Panel.new()
			dot.add_theme_stylebox_override("panel", MetaUiKit.box(MetaUiKit.RED, Color8(0xFF, 0xD0, 0xD0), 1, 4))
			dot.size = Vector2(9, 9)
			dot.position = Vector2(ACH_W - 7, -2)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			t.add_child(dot)
	else:
		if not started:
			var lk := MetaUiKit.icon_rect(MetaUiKit.tex("lock"), 16)
			lk.position = Vector2(30, 28)
			t.add_child(lk)
		var n := MetaUiKit.label("%s/%s" % [UiFmt.short(pr.x), UiFmt.short(pr.y)], 8, MetaUiKit.MUTED)
		n.custom_minimum_size.x = ACH_W
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.position = Vector2(0, 43)
		t.add_child(n)

	Tip.bind(t, String(a["name_ru"]), String(a["desc_ru"]), "Награда: %s" % MetaRewards.describe(a.get("reward", {})))
	return t


# ---------------------------------------------------------------------------
# Вкладка «Дорога трофеев»
# ---------------------------------------------------------------------------

func _build_road() -> void:
	var steps := TrophyRoad.steps()
	var pts := TrophyRoad.points()
	var next := TrophyRoad.next_index()

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(68, 68)
	var ring := MetaRing.new()
	ring.size = Vector2(68, 68)
	ring.width = 4.0
	holder.add_child(ring)
	var prev_at := 0 if next <= 0 else int(steps[next - 1]["at"])
	var frac := 1.0
	if next >= 0:
		frac = float(pts - prev_at) / float(maxi(1, int(steps[next]["at"]) - prev_at))
	ring.value = frac
	var trophy := MetaUiKit.icon_rect(MetaUiKit.tex("trophy"), 32)
	trophy.position = Vector2(18, 18)
	holder.add_child(trophy)
	top.add_child(holder)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(MetaUiKit.chip(MetaUiKit.tex("star"), str(pts), MetaUiKit.GOLD_LIGHT, 20, 18))
	if next >= 0:
		col.add_child(MetaUiKit.chip(MetaUiKit.tex("star"), "%d/%d" % [pts, int(steps[next]["at"])], MetaUiKit.MUTED, 10, 9))
	top.add_child(col)
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	Tip.bind(top, "Очки трофеев", "Копятся за достижения и выполненные задания.",
		("До следующей ступени: %d" % (int(steps[next]["at"]) - pts)) if next >= 0 else "Дорога пройдена")
	_vbox.add_child(top)

	_road_scroll = MetaHScroll.new()
	_road_scroll.custom_minimum_size = Vector2(0, 106)
	_road_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_road_scroll)
	# Поля сверху и снизу: пульсирующая плитка (масштаб 1.05) иначе упирается в обрез ленты.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 7)
	pad.add_theme_constant_override("margin_bottom", 7)
	_road_scroll.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	pad.add_child(row)
	var focus_x := 0.0
	var claimable := TrophyRoad.claimable()
	for i in range(steps.size()):
		var tile := _step_tile(i)
		row.add_child(tile)
		if (claimable.is_empty() and i == next) or (not claimable.is_empty() and i == int(claimable[0])):
			focus_x = float(i) * (STEP_W + 8.0)
		if i < steps.size() - 1:
			var dash := Control.new()
			dash.custom_minimum_size = Vector2(8, 0)
			dash.mouse_filter = Control.MOUSE_FILTER_PASS
			var bar := ColorRect.new()
			bar.color = MetaUiKit.GOLD if TrophyRoad.is_reached(i + 1) else Color(0.25, 0.2, 0.15)
			bar.position = Vector2(0, 22)
			bar.size = Vector2(8, 3)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dash.add_child(bar)
			row.add_child(dash)
	if not _road_centered:
		_road_centered = true
		_road_scroll.scroll_horizontal = int(maxf(0.0, focus_x - 70.0))

	_vbox.add_child(_next_prize_card(steps, pts))
	_vbox.add_child(_road_stats())


func _step_tile(i: int) -> Control:
	var steps := TrophyRoad.steps()
	var s: Dictionary = steps[i]
	var reward := MetaRewards.normalize(s["reward"])
	var big := bool(s.get("big", false))
	var reached := TrophyRoad.is_reached(i)
	var taken := TrophyRoad.is_claimed(i)
	var ready := reached and not taken

	var t := Panel.new()
	t.custom_minimum_size = Vector2(STEP_W, 92)
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	var border := MetaUiKit.GOLD if (ready or big) else MetaUiKit.BORDER
	var bg := Color8(0x3A, 0x2C, 0x14) if ready else MetaUiKit.SLOT
	t.add_theme_stylebox_override("panel", MetaUiKit.box(bg, border if (ready or reached or big) else MetaUiKit.BORDER, 2 if ready else 1, 4))

	var icon_name := "chest" if big else ("gift" if (reward.has("item") and reward.get("coins", 0) == 0) else "coins")
	var ic := MetaUiKit.icon_rect(MetaUiKit.tex(icon_name), 32)
	ic.position = Vector2((STEP_W - 32) * 0.5, 6)
	t.add_child(ic)
	var rr := MetaUiKit.reward_row(reward, 10, 8)
	rr.position = Vector2(2, 42)
	rr.custom_minimum_size.x = STEP_W - 4
	rr.alignment = BoxContainer.ALIGNMENT_CENTER
	t.add_child(rr)
	var pill := MetaUiKit.chip(MetaUiKit.tex("star"), str(int(s["at"])), MetaUiKit.GOLD_LIGHT if reached else MetaUiKit.MUTED, 11, 9)
	pill.position = Vector2(STEP_W * 0.5 - 14, 72)
	t.add_child(pill)

	if taken:
		for c in t.get_children():
			c.modulate = Color(0.55, 0.55, 0.55)
		var ck := MetaUiKit.icon_rect(MetaUiKit.tex("check"), 28)
		ck.position = Vector2((STEP_W - 28) * 0.5, 8)
		t.add_child(ck)
	elif not reached:
		ic.modulate = Color(0.5, 0.5, 0.5)
		var lk := MetaUiKit.icon_rect(MetaUiKit.tex("lock"), 14)
		lk.position = Vector2(STEP_W - 18, 3)
		t.add_child(lk)
	if ready and not UiAnim.reduced():
		t.pivot_offset = Vector2(STEP_W, 92) * 0.5
		var tw := t.create_tween().set_loops()
		tw.tween_property(t, "scale", Vector2(1.05, 1.05), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(t, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var hint := "Забрать" if ready else ("Получено" if taken else "Нужно очков: %d" % int(s["at"]))
	Tip.bind(t, "Ступень %d" % (i + 1), hint, "Награда: %s" % MetaRewards.describe(reward))
	t.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and not ev.pressed and ready and not Tip.swallowed() \
				and (_road_scroll == null or not _road_scroll.dragged):
			var origin := _center(t)
			var res := TrophyRoad.claim(i)
			if bool(res["ok"]):
				MetaFx.claim(get_tree(), origin, res["reward"], big, _anchors(), true)
				_after_claim())
	return t


func _next_prize_card(steps: Array, pts: int) -> Control:
	var idx := -1
	for i in range(steps.size()):
		if bool(steps[i].get("big", false)) and not TrophyRoad.is_claimed(i):
			idx = i
			break
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 44)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := MetaUiKit.box(MetaUiKit.CARD, MetaUiKit.GOLD.darkened(0.45), 1, 4)
	sb.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", sb)
	if idx < 0:
		card.add_child(MetaUiKit.icon_rect(MetaUiKit.tex("crown"), 32))
		return card
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	card.add_child(h)
	h.add_child(MetaUiKit.icon_rect(MetaUiKit.tex("chest"), 32))
	var rr := MetaUiKit.reward_row(steps[idx]["reward"], 13, 10)
	rr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(rr)
	var need := maxi(0, int(steps[idx]["at"]) - pts)
	if need > 0:
		h.add_child(MetaUiKit.chip(MetaUiKit.tex("star"), str(need), MetaUiKit.GOLD_LIGHT, 13, 11))
	else:
		h.add_child(MetaUiKit.icon_rect(MetaUiKit.tex("check"), 22))
	Tip.bind(card, "Ближайший крупный приз", "Ступень %d" % (idx + 1),
		("Не хватает очков: %d" % need) if need > 0 else "Можно забрать")
	return card


## Итоги жизни в числах: достижений, заданий, лучшая серия.
func _road_stats() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var items := [
		["medal", "%d/%d" % [Achievements.done_count(), MetaData.achievements().size()], "Достижения", "Получено из всех."],
		["clipboard", str(MetaState.counter("quests")), "Задания", "Выполнено и забрано за всё время."],
		["flame", str(MetaState.counter("streak_best")), "Лучшая серия", "Дней подряд за ежедневной наградой."],
	]
	for it in items:
		var chip := MetaUiKit.chip(MetaUiKit.tex(it[0]), it[1], MetaUiKit.GOLD_LIGHT, 22, 12)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		Tip.bind(chip, it[2], it[3])
		row.add_child(chip)
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", 10)
	wrap.add_child(row)
	return wrap

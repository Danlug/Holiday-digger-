class_name DailyTasksPanel
extends CanvasLayer
## Окно ежедневных миссий — его открывает кнопка на экране игры
## (DailyTasksButton). Тринадцать миссий дня (владелец, 27.10): значок в кольце
## со звездой, полоска «312/500», награда; готовое забирают нажатием (и «×2» за
## ролик), невыполненное можно заменить (одно в день бесплатно, ещё два — за
## ролик). За каждую забранную миссию — звезда; сверху шкала звёзд дня (0…13,
## засечка на 10) и сундук звёзд: десятая звезда открывает его — 5 долларов.
## Список прокручивается (миссий больше, чем влезает на экран): готовое к
## получению — сверху, забранное — внизу.
##
## Текста на плитках нет: значок, число, полоска. Название, описание и размер
## награды — в подсказке Tip (мышь: наведение; палец: долгое нажатие).
## Окно пересобирается целиком при каждом изменении: состояние живёт в
## MetaState, а не в узлах.

signal closed

const CARD_W := 212.0
const TILE_H := 38.0
const TILE_GAP := 3.0
const GLYPH := 24.0
const RING := 32.0
## Высота всего, что в окне не список: шапка, звёзды, низ, зазоры, поля окна
## и отступ от краёв экрана — остальное отдаём прокрутке.
const CHROME_H := 24.0 + 46.0 + 26.0 + 15.0 + 16.0 + 24.0

var _root: Control = null
var _card: PanelContainer = null
var _box: VBoxContainer = null
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _track: MetaStarTrack = null
var _timer_label: Label = null
var _wallet_label: Label = null
var _wallet_icon: Control = null
var _wallet_shown: int = 0
var _tick: float = 0.0
var _closing: bool = false
var _pulses: Array = []


func _ready() -> void:
	# Пока окно открыто, тост мета-слоя идёт снизу (MetaToast ищет эту группу).
	add_to_group("meta_hub")
	layer = UiLayers.MODAL  # выше хаба (92), HUD и шторок; ниже окна подарка дня (94) и экрана героя (95)
	visible = false


func is_open() -> bool:
	return visible and not _closing


func open() -> void:
	QuestEngine.refresh()
	QuestEngine.mark_opened()
	_closing = false
	_wallet_shown = GameState.coins
	_build()
	visible = true
	Sfx.play("ui_open")
	UiAnim.open(_card, UiAnim.Kind.POP, _root)
	UiAnim.stagger(_list.get_children(), 0.04, 0.9)


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	Sfx.play("ui_close")
	var closing_root := _root
	var finish := func() -> void:
		if _root != closing_root:
			return   # пока гасло, окно открыли заново — новое не трогаем
		visible = false
		_closing = false
		if _root != null:
			_root.queue_free()
			_root = null
		closed.emit()
	UiAnim.close(_card, UiAnim.Kind.POP, _root, finish)


## Перерисовать (новое событие, смена суток, вернулись из хаба).
func refresh() -> void:
	if is_open():
		_fill()


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
	if QuestEngine.refresh():
		QuestEngine.mark_opened()
		_fill()   # полночь наступила при открытом окне — новый набор
	_update_timer()


# ---------------------------------------------------------------------------
# Каркас
# ---------------------------------------------------------------------------

func _build() -> void:
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "DailyTasksRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Тап мимо окна закрывает его — как у шторок.
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
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
	var keep_scroll := _scroll.scroll_vertical if _scroll != null and is_instance_valid(_scroll) else 0
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_track = null
	_box.add_child(_header())
	var ds := QuestEngine.daily()
	if not ds.is_empty():
		_box.add_child(_stars_row())
	_scroll = ScrollContainer.new()
	_scroll.name = "TasksScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, _list_height(ds.size()))
	_box.add_child(_scroll)
	DragScroll.attach(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", int(TILE_GAP))
	_scroll.add_child(_list)
	if ds.is_empty():
		var lock := MetaUiKit.icon_rect(MetaUiKit.tex("lock"), 32)
		lock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_list.add_child(lock)
	for q in _display_order(ds):
		_list.add_child(_tile(q))
	_box.add_child(_footer())
	_update_timer()
	_start_pulses()
	if keep_scroll > 0:
		_scroll.set_deferred("scroll_vertical", keep_scroll)


## Список во весь остаток экрана, но не выше, чем нужно самим плиткам.
func _list_height(n: int) -> float:
	var natural := maxf(32.0, float(n) * (TILE_H + TILE_GAP) - TILE_GAP)
	var vh := get_viewport().get_visible_rect().size.y if get_viewport() != null else 480.0
	return clampf(vh - CHROME_H, minf(140.0, natural), natural)


## Готовое к получению — сверху, в работе — в порядке слотов, забранное — внизу:
## тринадцать плиток не влезают в экран, и то, что нажать, не должно прятаться.
func _display_order(ds: Array) -> Array:
	var ready: Array = []
	var going: Array = []
	var taken: Array = []
	for q in ds:
		if bool(q["claimed"]):
			taken.append(q)
		elif QuestEngine.is_done(q):
			ready.append(q)
		else:
			going.append(q)
	return ready + going + taken


# ---------------------------------------------------------------------------
# Шапка: серия, таймер, кошелёк, закрыть
# ---------------------------------------------------------------------------

func _header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)

	var streak := QuestEngine.streak_now()
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 1)
	st.mouse_filter = Control.MOUSE_FILTER_PASS
	var fl := MetaUiKit.icon_rect(MetaUiKit.tex("flame"), 18)
	if streak <= 0:
		fl.modulate = Color(0.5, 0.5, 0.5)
	st.add_child(fl)
	var sl := MetaUiKit.label(str(streak), UiTheme.FS_TITLE_L, MetaUiKit.GOLD_LIGHT if streak > 0 else MetaUiKit.MUTED)
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	st.add_child(sl)
	var best := int(MetaState.sub("quests").get("streak", {}).get("best", 0))
	Tip.bind(st, "Серия", "Дней подряд с открытым сундуком звёзд. Со второго дня сундук добавляет монеты и опыт (+10% за день, до +50%), каждый седьмой — ещё доллар. Пропуск одного дня серию не рвёт, двух — рвёт.",
		"Рекорд: %d" % best)
	h.add_child(st)

	var tm := MetaUiKit.chip(MetaUiKit.tex("clock"), "", MetaUiKit.MUTED, 12, UiTheme.FS_SMALL)
	tm.mouse_filter = Control.MOUSE_FILTER_PASS
	_timer_label = tm.get_child(1)
	Tip.bind(tm, "Новые задания", "Набор дня обновляется в полночь по твоим часам. Невзятые награды сгорают.")
	h.add_child(tm)

	# Звёзды дня числом: до сундука — «из 10», потом — «из 13».
	var stars := QuestEngine.stars_today()
	var need := QuestEngine.stars_needed()
	if need > 0:
		var past := stars >= need or bool(MetaState.sub("quests")["bonus_claimed"])
		var sc := MetaUiKit.chip(MetaUiKit.tex("star"), "%d/%d" % [stars, QuestEngine.daily().size() if past else need],
			MetaUiKit.GOLD_LIGHT if past else Color.WHITE, 13, UiTheme.FS_LABEL)
		sc.name = "StarsCount"
		sc.mouse_filter = Control.MOUSE_FILTER_PASS
		Tip.bind(sc, "Звёзды дня", "Звезда — за каждую забранную миссию. %d звёзд открывают сундук." % need)
		h.add_child(sc)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(gap)

	var wallet := MetaUiKit.chip(MetaUiKit.tex("coin"), UiFmt.short(_wallet_shown), MetaUiKit.GOLD_LIGHT, 12, UiTheme.FS_BODY)
	wallet.mouse_filter = Control.MOUSE_FILTER_PASS
	_wallet_icon = wallet.get_child(0)
	_wallet_label = wallet.get_child(1)
	Tip.bind(wallet, "Монеты")
	h.add_child(wallet)

	h.add_child(UiBtn.close_button(close))
	return h


func _update_timer() -> void:
	if _timer_label != null and is_instance_valid(_timer_label):
		_timer_label.text = MetaClock.hms(MetaClock.seconds_to_next_day())


# ---------------------------------------------------------------------------
# Плитка задания
# ---------------------------------------------------------------------------

func _tile(q: Dictionary) -> Control:
	var done := QuestEngine.is_done(q)
	var claimed := bool(q["claimed"])
	var claimable := done and not claimed
	var target := maxi(1, int(q["target"]))
	var prog := mini(int(q["progress"]), target)
	var frac := float(prog) / float(target)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, TILE_H)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := UiTheme.GOLD_BG if claimable else MetaUiKit.CARD
	var sb := MetaUiKit.box(bg, MetaUiKit.GOLD if claimable else MetaUiKit.BORDER, 2 if claimable else 1, 4)
	sb.set_content_margin_all(3)
	card.add_theme_stylebox_override("panel", sb)
	if claimed:
		card.modulate = Color(0.72, 0.72, 0.72)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(RING, RING)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := MetaRing.new()
	ring.size = Vector2(RING, RING)
	ring.ring_color = MetaUiKit.GREEN if done else MetaUiKit.GOLD
	holder.add_child(ring)
	ring.value = frac
	var g := MetaUiKit.icon_rect(MetaUiKit.tex(String(q["glyph"])), GLYPH)
	g.position = Vector2((RING - GLYPH) * 0.5, (RING - GLYPH) * 0.5)
	if claimed:
		g.modulate = Color(0.6, 0.6, 0.6)
	holder.add_child(g)
	# Звезда миссии в углу кольца: тёмная — в работе, полупрозрачная — выполнена,
	# золотая — забрана (она же клетка шкалы звёзд наверху).
	var star := MetaUiKit.icon_rect(MetaUiKit.tex("star"), 14)
	star.name = "Star"
	star.position = Vector2(RING - 13, RING - 13)
	if not claimed:
		star.modulate = Color(1, 1, 1, 0.5) if done else Color(0.25, 0.22, 0.18)
	holder.add_child(star)
	h.add_child(holder)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 3)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := MetaBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(40, 13)
	bar.font_size = UiTheme.FS_SMALL
	bar.frac = frac
	bar.text = "%s/%s" % [UiFmt.short(prog), UiFmt.short(target)]
	bar.fill_color = MetaUiKit.GREEN if done else MetaUiKit.GOLD
	mid.add_child(bar)
	mid.add_child(MetaUiKit.reward_row(q["reward"], 11, UiTheme.FS_SMALL))
	h.add_child(mid)

	var qid := String(q["id"])
	if claimable:
		var claim := UiBtn.fill_button(MetaUiKit.tex("check"), Vector2(30, 30), MetaUiKit.GREEN_BTN)
		claim.pressed.connect(func() -> void: _claim(qid, 1.0, claim))
		Tip.bind(claim, "Забрать награду", "И звезду дня.")
		h.add_child(claim)
		_pulses.append(claim)
		if MetaAds.can(MetaAds.QUEST):
			var ad := UiBtn.fill_button(MetaUiKit.tex("ad"), Vector2(34, 30), UiTheme.AD_BG, "×2")
			ad.pressed.connect(func() -> void: _claim_ad(qid, ad))
			Tip.bind(ad, "Удвоить за ролик", "Монеты и опыт ×2. Доллары и очки не удваиваются.",
				"Осталось сегодня: %d" % MetaAds.uses_left(MetaAds.QUEST))
			h.add_child(ad)
	elif not claimed and QuestEngine.can_reroll(q):
		var free := QuestEngine.free_rerolls_left() > 0
		var placement := QuestEngine.ad_placement_reroll()
		if free or MetaAds.can(placement):
			h.add_child(_reroll_button(qid, free, placement))

	var tip_body := QuestGen.description(q)
	if not done:
		tip_body += "\nОсталось: %d" % (target - prog)
	Tip.bind(card, QuestGen.title(q), tip_body, "Награда: %s · звезда" % MetaRewards.describe(q["reward"]))
	card.set_meta("qid", qid)
	return card


func _reroll_button(qid: String, free: bool, placement: String) -> Button:
	var b := UiBtn.icon_button(MetaUiKit.tex("reroll"), Vector2(26, 30), UiBtn.Kind.GHOST, 16)
	if not free:
		var mark := MetaUiKit.icon_rect(MetaUiKit.tex("ad"), 11)
		mark.position = Vector2(14, 18)
		b.add_child(mark)
	b.pressed.connect(func() -> void: _reroll(qid, free, placement, b))
	if free:
		Tip.bind(b, "Заменить задание", "Другое задание того же рода. Прогресс этого пропадёт.", "Бесплатно: 1 в день")
	else:
		Tip.bind(b, "Заменить за ролик", "Бесплатная замена на сегодня потрачена.",
			"Осталось роликов: %d" % MetaAds.uses_left(placement))
	return b


# ---------------------------------------------------------------------------
# Звёзды дня и сундук
# ---------------------------------------------------------------------------

## Сундук слева — он же кнопка (покачивается, когда десятая звезда получена);
## справа шкала звёзд 0…13 с засечкой на 10, под ней — что в сундуке и «7/10».
func _stars_row() -> Control:
	var ready := QuestEngine.bonus_ready()
	var taken := bool(MetaState.sub("quests")["bonus_claimed"])
	var stars := QuestEngine.stars_today()
	var need := QuestEngine.stars_needed()
	var card := PanelContainer.new()
	card.name = "StarsRow"
	card.custom_minimum_size = Vector2(0, 46)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := MetaUiKit.box(UiTheme.GOLD_BG if ready else MetaUiKit.SLOT,
		MetaUiKit.GOLD if ready else MetaUiKit.GOLD.darkened(0.45), 2, 5)
	sb.set_content_margin_all(3)
	sb.content_margin_right = 6
	card.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	var chest := Button.new()
	chest.name = "Chest"
	chest.flat = true
	chest.focus_mode = Control.FOCUS_NONE
	chest.custom_minimum_size = Vector2(36, 36)
	chest.icon = MetaUiKit.tex("chest_open" if (ready or taken) else "chest")
	chest.expand_icon = true
	chest.add_theme_constant_override("icon_max_width", 34)
	if taken:
		chest.modulate = Color(0.55, 0.55, 0.55)
	elif not ready:
		chest.modulate = Color(0.8, 0.8, 0.8)
	chest.pressed.connect(func() -> void: _press_chest(chest))
	UiBtn.wire_feedback(chest)
	h.add_child(chest)
	if ready:
		_pulses.append(chest)
	if taken:
		var ck := MetaUiKit.icon_rect(MetaUiKit.tex("check"), 16)
		ck.position = Vector2(20, 20)
		chest.add_child(ck)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 3)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track = MetaStarTrack.new()
	_track.name = "StarTrack"
	_track.custom_minimum_size = Vector2(0, 14)
	_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track.total = QuestEngine.daily().size()
	_track.needed = need
	_track.stars = stars
	var done_unclaimed := 0
	for q in QuestEngine.daily():
		if QuestEngine.is_claimable(q):
			done_unclaimed += 1
	_track.done = done_unclaimed
	mid.add_child(_track)
	var reward := QuestEngine.bonus_reward()
	var rr := MetaUiKit.reward_row(reward, 11, UiTheme.FS_SMALL)
	rr.add_theme_constant_override("separation", 3)
	mid.add_child(rr)
	h.add_child(mid)

	var n := QuestEngine.streak_if_claimed()
	var extra := MetaRewards.describe(reward)
	var pct := QuestEngine.streak_pct(n)
	if pct > 0:
		extra += "\nСерия %d: +%d%%" % [n, pct]
	var body := "За каждую забранную миссию — звезда. %d звёзд открывают сундук." % need
	if taken:
		body = "Сундук сегодня уже открыт. Новые миссии и звёзды — в полночь."
	Tip.bind(card, "Звёзды дня: %d из %d" % [stars, QuestEngine.daily().size()], body, extra)
	Tip.bind(chest, "Сундук звёзд", "Открывается на %d-й звезде." % need, extra)
	return card


func _press_chest(chest: Control) -> void:
	if Tip.swallowed():
		return
	if QuestEngine.bonus_ready():
		_claim_chest(chest)
	else:
		UiAnim.shake(chest)
		Sfx.play("ui_deny")


# ---------------------------------------------------------------------------
# Низ: недельные задания и замены
# ---------------------------------------------------------------------------

func _footer() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var wk := UiBtn.icon_button(MetaUiKit.tex("calendar"), Vector2(34, 26), UiBtn.Kind.NORMAL, 18)
	var weekly_ready := 0
	for q in MetaState.sub("quests")["weekly"]:
		if QuestEngine.is_claimable(q):
			weekly_ready += 1
	UiBtn.set_badge(wk, weekly_ready)
	Tip.bind(wk, "Недельные задания", "Крупнее и щедрее, обновляются в понедельник.")
	wk.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		var svc := MetaService.instance
		if svc != null:
			svc.open_hub("tasks"))
	h.add_child(wk)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(gap)
	var free := QuestEngine.free_rerolls_left()
	var rr := MetaUiKit.chip(MetaUiKit.tex("reroll"), "×%d" % free, MetaUiKit.BLUE if free > 0 else MetaUiKit.MUTED, 14, UiTheme.FS_BODY)
	rr.mouse_filter = Control.MOUSE_FILTER_PASS
	Tip.bind(rr, "Замены заданий", "Одна замена в день бесплатно, ещё две — за ролик.",
		"Роликов осталось: %d" % MetaAds.uses_left(QuestEngine.ad_placement_reroll()))
	h.add_child(rr)
	return h


# ---------------------------------------------------------------------------
# Действия
# ---------------------------------------------------------------------------

func _claim(qid: String, mult: float, from: Control) -> void:
	if Tip.swallowed():
		return
	var origin := _center(from)
	var before := GameState.coins
	var res := QuestEngine.claim(qid, mult)
	if not bool(res["ok"]):
		return
	MetaFx.claim(get_tree(), origin, res["reward"], false, _anchors(), true)
	_after_change(before)
	_fly_star(origin)


## Звезда забранной миссии летит из плитки в свою клетку шкалы наверху.
func _fly_star(origin: Vector2) -> void:
	if _track == null or not is_instance_valid(_track):
		return
	var i := clampi(QuestEngine.stars_today() - 1, 0, maxi(0, _track.total - 1))
	var tr := _track
	var to := func() -> Vector2: return tr.global_position + tr.cell_center(i)
	# Шкала встаёт на место только после раскладки нового окна — берём точку кадром позже.
	await get_tree().process_frame
	if not is_instance_valid(tr):
		return
	MetaFx.fly(get_tree(), MetaUiKit.tex("star"), origin, to.call(), 1)


func _claim_ad(qid: String, from: Control) -> void:
	if Tip.swallowed():
		return
	if not MetaAds.request(MetaAds.QUEST, func() -> void: _claim(qid, 2.0, from)):
		UiAnim.shake(from)
		Sfx.play("ui_deny")


func _claim_chest(chest: Control) -> void:
	if Tip.swallowed():
		return
	var origin := _center(chest)
	var before := GameState.coins
	var res := QuestEngine.claim_bonus()
	if not bool(res["ok"]):
		return
	UiAnim.shake(chest, 4.0, 0.3)
	MetaFx.claim(get_tree(), origin, res["reward"], true, _anchors(), true)
	_after_change(before)


func _reroll(qid: String, free: bool, placement: String, from: Control) -> void:
	if Tip.swallowed():
		return
	var apply := func(via_ad: bool) -> void:
		var res := QuestEngine.reroll(qid, via_ad)
		if not bool(res["ok"]):
			UiAnim.shake(from)
			Sfx.play("ui_deny")
			return
		Sfx.play("ui_tab")
		Haptics.tap()
		_after_change(GameState.coins)
		var tile := tile_of(String(res["quest"]["id"]))
		if tile != null:
			UiAnim.appear(tile, 0.7, 0.22)
	if free:
		apply.call(false)
	elif not MetaAds.request(placement, func() -> void: apply.call(true)):
		UiAnim.shake(from)
		Sfx.play("ui_deny")


## Плитка миссии в списке (порядок плиток — не порядок слотов: готовое сверху).
func tile_of(qid: String) -> Control:
	if _list == null or not is_instance_valid(_list):
		return null
	for c in _list.get_children():
		if c.has_meta("qid") and String(c.get_meta("qid")) == qid:
			return c
	return null


## Сохранить, оповестить, перерисовать — и докрутить монеты в шапке, когда
## прилетят значки (полёт ~0.5 с).
func _after_change(coins_before: int) -> void:
	var svc := MetaService.instance
	if svc != null:
		svc.after_change()
	_wallet_shown = coins_before
	_fill()
	var to := GameState.coins
	if to != coins_before and _wallet_label != null:
		var lbl := _wallet_label
		var icon := _wallet_icon
		var tw := lbl.create_tween()
		tw.tween_interval(0.45)
		tw.tween_method(func(v: float) -> void:
			_wallet_shown = int(v)
			if is_instance_valid(lbl):
				lbl.text = UiFmt.short(int(v)), float(coins_before), float(to), 0.5)
		tw.tween_callback(func() -> void:
			if is_instance_valid(icon):
				UiAnim.pulse(icon, 0.4, 0.25))


## Готовое к получению покачивается — глаз сразу находит, что нажать.
func _start_pulses() -> void:
	if UiAnim.reduced():
		return
	for c in _pulses:
		var ctl := c as Control
		if ctl == null or not is_instance_valid(ctl):
			continue
		ctl.resized.connect(func() -> void: ctl.pivot_offset = ctl.size * 0.5)
		ctl.pivot_offset = ctl.custom_minimum_size * 0.5
		var tw := ctl.create_tween().set_loops()
		tw.tween_property(ctl, "scale", Vector2.ONE * 1.08, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(ctl, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_interval(0.5)


## Куда лететь наградам: монеты — в кошелёк шапки окна (HUD под затемнением).
func _anchors() -> Dictionary:
	var out := {}
	if _wallet_icon != null and is_instance_valid(_wallet_icon):
		out["coins"] = _center(_wallet_icon)
		out["xp"] = out["coins"]
	out["dollars"] = MetaUiKit.anchor("dollars")
	return out


func _center(c: Control) -> Vector2:
	return c.global_position + c.size * 0.5

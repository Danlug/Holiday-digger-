class_name DailyPopup
extends CanvasLayer
## Окно ежедневной награды: семь плиток-дней, сегодняшняя подсвечена, седьмой
## день — крупный приз. Показывается при первом входе за день (решает
## MetaService), но открывается и из меню «•••». Текста на плитках нет — только
## значки и числа; описание дня — в Tip.

signal claimed(result: Dictionary)
signal closed

const TILE_W := 44.0
const TILE_H := 58.0

var _root: Control = null
var _card: PanelContainer = null
var _streak_label: Label = null
var _tiles: Array = []
var _claim_btn: Button = null
var _ad_btn: Button = null
var _plan: Dictionary = {}
var _done: bool = false
var _hero: TextureRect = null


func _ready() -> void:
	layer = 94  # выше HUD (1), дома (9), шторок (20) и нашего хаба (92), но ниже экрана героя (95) и катсцен (100)
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	_plan = DailyReward.plan()
	_done = false
	_build()
	visible = true
	Sfx.play("ui_open")
	if _card != null:
		UiAnim.appear(_card, 0.85, 0.22)


func close() -> void:
	if not visible:
		return
	visible = false
	if _root != null:
		_root.queue_free()
		_root = null
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	if _root != null:
		_root.queue_free()
	_tiles.clear()
	_root = Control.new()
	_root.name = "DailyRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_card = PanelContainer.new()
	var sb := MetaUiKit.box(MetaUiKit.CARD, MetaUiKit.GOLD, 2, 6)
	sb.set_content_margin_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 4
	_card.add_theme_stylebox_override("panel", sb)
	_card.custom_minimum_size = Vector2(208, 0)
	center.add_child(_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_card.add_child(box)

	box.add_child(_build_header())
	box.add_child(_build_hero())
	box.add_child(_build_grid())
	box.add_child(_build_buttons())


func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.add_child(MetaUiKit.icon_rect(MetaUiKit.tex("flame"), 24))
	_streak_label = MetaUiKit.label(str(int(_plan["streak"])), 18, MetaUiKit.GOLD_LIGHT)
	h.add_child(_streak_label)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(gap)
	var pct := int(_plan["bonus_pct"])
	if pct > 0:
		var chip := MetaUiKit.chip(MetaUiKit.tex("up"), "+%d%%" % pct, MetaUiKit.GREEN, 14, 9)
		Tip.bind(chip, "Бонус серии", "Каждая пройденная неделя подряд добавляет к монетам и опыту.", "+%d%%" % pct)
		h.add_child(chip)
	var x := Button.new()
	x.text = "×"
	x.add_theme_font_size_override("font_size", 16)
	x.custom_minimum_size = Vector2(28, 28)
	UiBtn.style(x, UiBtn.Kind.GHOST)
	x.pressed.connect(close)
	h.add_child(x)
	Tip.bind(h.get_child(0) as Control, "Серия", "Дней подряд. Пропуск в один день серию не рвёт, два — рвёт.", str(int(_plan["streak"])))
	return h


func _build_hero() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 70)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero = TextureRect.new()
	_hero.texture = MetaUiKit.tex("gift")
	_hero.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.size = Vector2(64, 64)
	_hero.position = Vector2(64, 3)
	_hero.pivot_offset = Vector2(32, 32)
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_hero)
	if not UiAnim.reduced():
		var tw := _hero.create_tween().set_loops()
		tw.tween_property(_hero, "position:y", -1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_hero, "position:y", 5.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return holder


func _build_grid() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 5)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 5)
	v.add_child(r1)
	v.add_child(r2)
	var n := DailyReward.cycle().size()
	for i in range(n):
		var t := _make_tile(i)
		_tiles.append(t)
		(r1 if i < 4 else r2).add_child(t)
	return v


func _make_tile(i: int) -> Control:
	var grand := i == DailyReward.cycle().size() - 1
	var pos := int(_plan["pos"])
	var today := i == pos and bool(_plan["can_claim"])
	var past := i < pos or (i == pos and not bool(_plan["can_claim"]))
	var w := TILE_W * 2.0 + 6.0 if grand else TILE_W
	var reward := DailyReward.reward_for(i, int(_plan["cycles"]))

	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(w, TILE_H)
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var border := MetaUiKit.GOLD if today else (MetaUiKit.GOLD.darkened(0.45) if grand else MetaUiKit.BORDER)
	var bg := Color8(0x3A, 0x2C, 0x14) if today else MetaUiKit.SLOT
	var sb := MetaUiKit.box(bg, border, 2 if (today or grand) else 1, 4)
	sb.set_content_margin_all(2)
	tile.add_theme_stylebox_override("panel", sb)

	var lay := Control.new()
	lay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(lay)
	var day_l := MetaUiKit.label(str(i + 1), 9, MetaUiKit.GOLD if today else MetaUiKit.MUTED)
	day_l.position = Vector2(3, 0)
	lay.add_child(day_l)

	var icon_name := "chest" if grand else "coins"
	var ic := MetaUiKit.icon_rect(MetaUiKit.tex(icon_name), 32)
	ic.position = Vector2(5, 11) if not grand else Vector2(6, 12)
	lay.add_child(ic)

	if grand:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		col.position = Vector2(44, 9)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rr := reward
		col.add_child(MetaUiKit.chip(MetaUiKit.reward_tex("coins"), str(int(rr.get("coins", 0))), MetaUiKit.GOLD_LIGHT, 12, 9))
		if rr.has("dollars"):
			col.add_child(MetaUiKit.chip(MetaUiKit.reward_tex("dollars"), str(int(rr["dollars"])), Color8(0x4D, 0xE0, 0x94), 12, 9))
		if rr.has("xp"):
			col.add_child(MetaUiKit.chip(MetaUiKit.reward_tex("xp"), str(int(rr["xp"])), MetaUiKit.BLUE, 12, 9))
		lay.add_child(col)
		var crown := MetaUiKit.icon_rect(MetaUiKit.tex("crown"), 14)
		crown.position = Vector2(w - 21, 0)
		lay.add_child(crown)
	else:
		var amt := MetaUiKit.label(MetaUiKit.compact(int(reward.get("coins", 0))), 9, MetaUiKit.GOLD_LIGHT)
		amt.custom_minimum_size.x = TILE_W - 4
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amt.position = Vector2(0, TILE_H - 16)
		lay.add_child(amt)
		var ex := 0
		for key in ["xp", "item", "dollars"]:
			if reward.has(key):
				var item_id := String(reward["item"]["id"]) if key == "item" else ""
				var small := MetaUiKit.icon_rect(MetaUiKit.reward_tex(key, item_id), 14)
				small.position = Vector2(TILE_W - 19, 1 + 12 * ex)
				lay.add_child(small)
				ex += 1

	if past:
		tile.modulate = Color(0.62, 0.62, 0.62)
		var ck := MetaUiKit.icon_rect(MetaUiKit.tex("check"), 24)
		ck.position = Vector2((w - 4) * 0.5 - 12, 18)
		lay.add_child(ck)

	var title := "День %d" % (i + 1)
	if grand:
		title += " — крупный приз"
	Tip.bind(tile, title, "Серия — награды каждый день подряд.", MetaRewards.describe(reward))
	if today and not UiAnim.reduced():
		tile.pivot_offset = Vector2(w, TILE_H) * 0.5
		var tw := tile.create_tween().set_loops()
		tw.tween_property(tile, "scale", Vector2(1.06, 1.06), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(tile, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tile


func _build_buttons() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	_claim_btn = Button.new()
	_claim_btn.text = "Забрать"
	_claim_btn.icon = MetaUiKit.tex("check")
	_claim_btn.add_theme_constant_override("icon_max_width", 16)
	_claim_btn.add_theme_font_size_override("font_size", 11)
	_claim_btn.custom_minimum_size = Vector2(112, 34)
	_claim_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_cta(_claim_btn, MetaUiKit.GREEN_BTN)
	_claim_btn.pressed.connect(func() -> void: _claim(1.0))
	h.add_child(_claim_btn)

	_ad_btn = Button.new()
	_ad_btn.text = "×2"
	_ad_btn.icon = MetaUiKit.tex("ad")
	_ad_btn.add_theme_constant_override("icon_max_width", 16)
	_ad_btn.add_theme_font_size_override("font_size", 11)
	_ad_btn.custom_minimum_size = Vector2(62, 34)
	_style_cta(_ad_btn, Color8(0x3C, 0x3A, 0x1A))
	_ad_btn.pressed.connect(_claim_ad)
	Tip.bind(_ad_btn, "Удвоить за ролик", "Монеты и опыт сегодняшнего приза ×2. Доллары не удваиваются.",
		"Осталось сегодня: %d" % MetaAds.uses_left(MetaAds.DAILY))
	_ad_btn.visible = MetaAds.can(MetaAds.DAILY)
	h.add_child(_ad_btn)

	if not bool(_plan["can_claim"]):
		_claim_btn.disabled = true
		_ad_btn.disabled = true
	return h


func _style_cta(b: Button, bg: Color) -> void:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := MetaUiKit.box(bg, MetaUiKit.GOLD if st == "hover" else bg.lightened(0.25), 1, 5)
		if st == "pressed":
			sb.bg_color = bg.darkened(0.2)
		if st == "disabled":
			sb.bg_color = Color(0.15, 0.13, 0.11)
			sb.border_color = MetaUiKit.BORDER
		sb.set_content_margin_all(4)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", MetaUiKit.DIM)
	b.focus_mode = Control.FOCUS_NONE
	UiBtn.wire_feedback(b)


func _claim_ad() -> void:
	if Tip.swallowed() or _done:
		return
	if not MetaAds.request(MetaAds.DAILY, func() -> void: _claim(2.0)):
		UiAnim.shake(_ad_btn)
		Sfx.play("ui_deny")


func _claim(mult: float) -> void:
	if Tip.swallowed() or _done:
		return
	var res := DailyReward.claim(mult)
	if not bool(res["ok"]):
		return
	_done = true
	_claim_btn.disabled = true
	_ad_btn.disabled = true
	_ad_btn.visible = false
	var idx := int(res["day"]) - 1
	var tile: Control = _tiles[idx]
	var origin := tile.global_position + tile.size * 0.5
	var grand := bool(res["grand"])
	MetaFx.claim(get_tree(), origin, res["reward"], grand)
	_streak_label.text = str(int(res["streak"]))
	UiAnim.pulse(_streak_label, 0.5, 0.4)
	UiAnim.pulse(_hero, 0.25, 0.4)
	tile.modulate = Color(0.62, 0.62, 0.62)
	var ck := MetaUiKit.icon_rect(MetaUiKit.tex("check"), 24)
	ck.position = Vector2((tile.size.x - 4) * 0.5 - 12, 18)
	tile.get_child(0).add_child(ck)
	UiAnim.appear(ck, 2.2, 0.25)
	claimed.emit(res)
	await get_tree().create_timer(1.3).timeout
	close()

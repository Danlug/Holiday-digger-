extends CanvasLayer
## EquipmentScreen — экран «Снаряжение» отдельным слоем: куклу героя (шесть
## слотов), характеристики, ультимативный сет с сокетами Перчатки Мироздания и
## ковку из глубинных материалов. Плитки-иконки и числа; названия и описания —
## только в подсказке Tip (решение владельца). Ковка — свой простой экран до
## интеграции с визуальным магазином: «есть/нужно» у каждого материала.
##
## Пока экран открыт, герой стоит и ввод HUD выключен — так же, как у
## магазина (ShopUI): джойстик под плиткой иначе забирал бы нажатия раньше.

const GOLD := Color8(0xE0, 0xA9, 0x3B)
const MUTED := Color8(0x9D, 0x8B, 0x73)
const DIM := Color8(0x5A, 0x50, 0x44)
const RED := Color8(0xC4, 0x52, 0x4A)
const GREEN := Color8(0x7F, 0xB8, 0x6B)
const BG := ProgressUiKit.BG_SOLID
const TILE_BG := Color8(0x26, 0x1E, 0x16)
const TIER_COLORS := {
	0: Color8(0xF2, 0xD9, 0x9B),
	1: Color8(0xC4, 0x62, 0x2A),
	2: Color8(0x8E, 0x6C, 0xD8),
	3: Color8(0x4D, 0xC4, 0xC0),
	4: Color8(0xE8, 0xC8, 0x6A),
	5: Color8(0xE8, 0x6C, 0xA8),
	6: Color8(0xF0, 0xF0, 0xF0),
}
const SLOT_TITLES := {
	"helmet": "Шлем", "armor": "Броня", "weapon": "Оружие",
	"shield": "Щит", "acc1": "Аксессуар", "acc2": "Аксессуар",
}

var director: CombatDirector = null

var _root: Control
var _body: VBoxContainer
var _scroll: ScrollContainer
var _tab: String = "gear"
var _open: bool = false
var _was_frozen: bool = false
var _hud_input_was_on: bool = true
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	layer = UiLayers.META
	_root = Control.new()
	_root.name = "Root"
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	if _root == null:
		return
	_root.position = Vector2.ZERO
	_root.size = get_viewport().get_visible_rect().size


func is_open() -> bool:
	return _open


func open(tab: String = "gear") -> void:
	if _open:
		return
	_open = true
	_tab = tab
	_freeze(true)
	_fit()
	_root.visible = true
	_rebuild()
	Sfx.play("ui_open")
	UiAnim.open(_root, UiAnim.Kind.FADE)


func close() -> void:
	if not _open:
		return
	_open = false
	UiAnim.close(_root, UiAnim.Kind.FADE)
	_freeze(false)
	Tip.hide_all()
	Sfx.play("ui_close")


func _freeze(on: bool) -> void:
	var player: Node = director.player if director != null else null
	var hud: Node = director.hud if director != null else null
	if player != null and is_instance_valid(player):
		if on:
			_was_frozen = bool(player.frozen)
			player.frozen = true
			player.digging = null
			player.release_control()
		else:
			player.frozen = _was_frozen
	if hud != null and is_instance_valid(hud):
		if on:
			_hud_input_was_on = hud.is_processing_input()
			hud.set_process_input(false)
			if hud.has_method("close_inventory"):
				hud.close_inventory()
		else:
			hud.set_process_input(_hud_input_was_on)


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Сборка экрана
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	if _root == null:
		return
	for c in _root.get_children():
		if c is ColorRect:
			continue
		c.queue_free()
	_tab_buttons.clear()

	var page := VBoxContainer.new()
	page.name = "Page"
	page.position = Vector2(8, 6)
	page.size = _root.size - Vector2(16, 12)
	page.add_theme_constant_override("separation", 5)
	_root.add_child(page)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	page.add_child(_scroll)
	DragScroll.attach(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	_scroll.add_child(_body)

	if _tab == "gear":
		_build_gear_tab()
	else:
		_build_forge_tab()
	page.add_child(_build_header())   # вкладки внизу, в зоне большого пальца — как на экране героя


func _build_header() -> Control:
	var specs := [["gear", CombatData.ui_icon("equip"), "Снаряжение", "Что надето и что есть"],
		["forge", UiIcons.tex("workshop"), "Ковка", "Собрать броню и оружие из глубинных материалов. Верстак дома"]]
	var bar := HeroTabButton.make_bar(specs, _tab, func(key: String) -> void:
		if _tab == key:
			return
		_tab = key
		_rebuild(), close)
	_tab_buttons = bar.get_meta("buttons")
	return bar


# ---------------------------------------------------------------------------
# Вкладка «Снаряжение»
# ---------------------------------------------------------------------------

func _tier_color(tier: int) -> Color:
	return TIER_COLORS.get(tier, MUTED)


func _tile(icon: Texture2D, tier_color: Color, size: Vector2, dim: bool = false, icon_px: int = 32) -> Button:
	var b := Button.new()
	b.icon = icon
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", icon_px)
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = TILE_BG if st != "pressed" else Color8(0x1B, 0x15, 0x10)
		sb.border_color = tier_color if not dim else Color(tier_color, 0.35)
		sb.set_border_width_all(2 if st in ["hover", "pressed", "hover_pressed"] else 1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(2)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0.38) if dim else Color.WHITE)
	b.add_theme_color_override("icon_hover_color", Color(1, 1, 1, 0.5) if dim else Color.WHITE)
	b.add_theme_color_override("icon_pressed_color", Color(1, 1, 1, 0.8) if dim else Color(0.9, 0.9, 0.9))
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.3))
	UiBtn.wire_feedback(b)
	return b


func _small_label(text: String, size: int = 9, color: Color = MUTED) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Подпись-число в нижнем правом углу плитки.
func _corner_number(b: Control, text: String, color: Color = Color.WHITE) -> void:
	var l := _small_label(text, 9, color)
	l.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.offset_right = -2
	l.offset_bottom = 1
	b.add_child(l)


func _gear_tip(id: String) -> String:
	var g := CombatData.gear(id)
	var s: Dictionary = g.get("stats", {})
	var parts: Array = []
	if s.has("dmg"):
		parts.append("урон %d, удар раз в %.2f с" % [int(s["dmg"]), float(s.get("cd", 0.6))])
	if s.has("def"):
		parts.append("защита %d" % int(s["def"]))
	if s.has("dmg_pct"):
		parts.append("урон +%d%%" % int(s["dmg_pct"]))
	if s.has("spd_pct"):
		parts.append("скорость удара +%d%%" % int(s["spd_pct"]))
	if s.has("res_pct"):
		parts.append("сопротивление огню и тени %d%%" % int(s["res_pct"]))
	if s.has("regen"):
		parts.append("восстановление %.1f HP/с" % float(s["regen"]))
	return "; ".join(parts)


func _build_gear_tab() -> void:
	# --- слоты ---
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(grid)
	for key in CombatData.slots():
		var k := String(key)
		var id := CombatService.equipped(k)
		var tier := int(CombatData.gear(id).get("tier", 0)) if id != "" else -1
		var icon: Texture2D = CombatData.icon(id) if id != "" else CombatData.ui_icon("slot_" + k.rstrip("12"))
		var t := _tile(icon, _tier_color(tier) if id != "" else Color8(0x52, 0x40, 0x2D), Vector2(60, 60), id == "", 32)
		if id != "":
			Tip.bind(t, CombatData.item_name(id), _gear_tip(id), "Тап — снять")
		else:
			Tip.bind(t, String(SLOT_TITLES.get(k, k)), "Пусто. Надень предмет из списка ниже")
		t.pressed.connect(func() -> void:
			if Tip.swallowed() or id == "":
				return
			CombatService.unequip(k)
			Sfx.play("ui_toggle")
			_rebuild())
		grid.add_child(t)

	# --- характеристики ---
	var st := CombatService.stats()
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 4)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(chips)
	var spec := [
		["def", "%d" % int(round(float(st["defense"]))), "Защита",
			"Срезает %d%% урона монстров" % int(round(float(st["reduction"]) * 100.0))],
		["dmg", "%d" % int(round(float(st["damage"]))), "Урон",
			"Один удар. В секунду — %.0f" % float(st["dps"])],
		["spd", "%.1f" % (1.0 / float(st["cd"])), "Скорость удара", "Ударов в секунду"],
		["res", "%d%%" % int(round(float(st["res_pct"]))), "Сопротивление",
			"Ещё срезает урон огня и тени"],
		["regen", "%.1f" % float(CombatService.regen_per_sec()), "Восстановление",
			"HP в секунду после %d с без урона. Только глубже 4000" % int(CombatData.player_cfg("regen_delay_sec", 6.0))],
	]
	for sp in spec:
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.11, 0.09, 0.07, 1.0)
		sb.border_color = Color8(0x3E, 0x31, 0x25)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.set_content_margin_all(2)
		chip.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		chip.add_child(v)
		var ic := TextureRect.new()
		ic.texture = CombatData.ui_icon(sp[0])
		ic.custom_minimum_size = Vector2(16, 16)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
		var num := _small_label(sp[1], 10, Color8(0xF2, 0xD9, 0x9B))
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(num)
		chip.custom_minimum_size = Vector2(38, 0)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		Tip.bind(chip, sp[2], sp[3])
		chips.add_child(chip)

	# --- ультимативный сет ---
	_body.add_child(_build_set_row())
	_body.add_child(_build_socket_row())

	# --- что есть ---
	var owned: Array = []
	for oid in CombatService.owned_ids():
		if String(CombatData.gear(String(oid)).get("set", "")) == "":
			owned.append(oid)   # части ультимативного сета уже в своём ряду выше
	var inv := GridContainer.new()
	inv.columns = 5
	inv.add_theme_constant_override("h_separation", 4)
	inv.add_theme_constant_override("v_separation", 4)
	_body.add_child(inv)
	for id in owned:
		var gid := String(id)
		var g := CombatData.gear(gid)
		var worn := CombatService.slot_of(gid) != ""
		var t := _tile(CombatData.icon(gid), _tier_color(int(g.get("tier", 0))), Vector2(38, 38), false, 32)
		Tip.bind(t, CombatData.item_name(gid), _gear_tip(gid), "Надето" if worn else "Тап — надеть")
		if worn:
			_corner_number(t, "●", GREEN)
		t.pressed.connect(func() -> void:
			if Tip.swallowed():
				return
			if CombatService.slot_of(gid) != "":
				CombatService.unequip(CombatService.slot_of(gid))
			else:
				CombatService.equip(gid)
			Sfx.play("ui_toggle")
			Haptics.tap()
			_rebuild())
		inv.add_child(t)
	if owned.is_empty():
		var hint := TextureRect.new()
		hint.texture = UiIcons.tex("workshop")
		hint.custom_minimum_size = Vector2(32, 32)
		hint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hint.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hint.modulate = Color(1, 1, 1, 0.4)
		hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		hint.mouse_filter = Control.MOUSE_FILTER_PASS
		Tip.bind(hint, "Пока пусто", "Собери снаряжение на верстаке из материалов глубже 4000 или найди артефакты ультимативного сета")
		_body.add_child(hint)


func _build_set_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var pieces: Array = CombatData.section("sets").get("ultimate", {}).get("pieces", [])
	for pid in pieces:
		var id := String(pid)
		var have := CombatService.is_owned(id)
		var worn := CombatService.slot_of(id) != ""
		var t := _tile(CombatData.icon(id), _tier_color(0), Vector2(36, 36), not have, 32)
		Tip.bind(t, CombatData.item_name(id), _gear_tip(id) if have else "Артефакт ещё не найден. Он лежит в музее, когда найдёшь",
			"Ультимативный сет %d/5" % CombatService.set_pieces_worn())
		if worn:
			_corner_number(t, "●", GREEN)
		t.pressed.connect(func() -> void:
			if Tip.swallowed() or not have:
				return
			if CombatService.slot_of(id) != "":
				CombatService.unequip(CombatService.slot_of(id))
			else:
				CombatService.equip(id)
			Sfx.play("ui_toggle")
			_rebuild())
		row.add_child(t)
	return row


func _build_socket_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var glove_ok := CombatService.is_owned(String(CombatData.section("sockets").get("gear", "ult_glove")))
	for s in CombatService.socket_defs():
		var mid := String(s["id"])
		var filled := CombatService.socket_filled(mid)
		var chk := CombatService.check_socket(mid)
		var t := _tile(CombatData.icon(mid), GOLD if filled else Color8(0x52, 0x40, 0x2D), Vector2(36, 36), not filled and not glove_ok, 32)
		var bonus := _socket_text(s)
		if filled:
			Tip.bind(t, CombatData.material_name(mid), "Сокет заполнен: " + bonus)
			_corner_number(t, "●", GREEN)
		else:
			Tip.bind(t, "Сокет Перчатки Мироздания", "%s: %s. Вставить — %d шт. Верстак дома" % [CombatData.material_name(mid), bonus, CombatService.socket_cost()],
				String(chk["reason"]))
			var have := int(chk["have"])
			var need := int(chk["need"])
			_corner_number(t, "%d/%d" % [mini(have, 99), need], GREEN if have >= need else RED)
		t.pressed.connect(func() -> void:
			if Tip.swallowed() or filled:
				return
			var r := CombatService.fill_socket(mid)
			if bool(r["ok"]):
				Sfx.play("ui_buy")
				Haptics.thud()
				_rebuild()
			else:
				Sfx.play("ui_deny")
				_deny(t))
		row.add_child(t)
	return row


func _socket_text(s: Dictionary) -> String:
	var parts: Array = []
	if s.has("dmg_pct"):
		parts.append("урон +%d%%" % int(s["dmg_pct"]))
	if s.has("spd_pct"):
		parts.append("скорость удара +%d%%" % int(s["spd_pct"]))
	if s.has("def"):
		parts.append("защита +%d" % int(s["def"]))
	if s.has("res_pct"):
		parts.append("сопротивление +%d%%" % int(s["res_pct"]))
	if s.has("regen"):
		parts.append("восстановление +%.1f" % float(s["regen"]))
	return ", ".join(parts)


func _deny(c: Control) -> void:
	if UiAnim.reduced() or not c.is_inside_tree():
		return
	var x0 := c.position.x
	var tw := c.create_tween()
	for d in [3.0, -3.0, 2.0, -2.0, 0.0]:
		tw.tween_property(c, "position:x", x0 + d, 0.035)


# ---------------------------------------------------------------------------
# Вкладка «Ковка»
# ---------------------------------------------------------------------------

func _build_forge_tab() -> void:
	var at_bench := CombatService.at_workbench()
	if not at_bench:
		var warn := HBoxContainer.new()
		warn.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := TextureRect.new()
		ic.texture = UiIcons.tex("workshop")
		ic.custom_minimum_size = Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.modulate = Color(1, 1, 1, 0.5)
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		Tip.bind(ic, "Верстак дома", "Собирать можно только в подвале у верстака. Материалы берутся со склада и из рюкзака")
		warn.add_child(ic)
		_body.add_child(warn)
	var last_tier := -99
	for rid in CombatData.craftable_ids():
		var tier := int(CombatData.gear(rid).get("tier", 0))
		if tier != last_tier:
			last_tier = tier
			_body.add_child(_tier_bar(tier))
		_body.add_child(_recipe_row(rid))


func _tier_bar(tier: int) -> Control:
	var bar := ColorRect.new()
	bar.color = Color(_tier_color(tier), 0.55)
	bar.custom_minimum_size = Vector2(0, 2)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


func _recipe_row(id: String) -> Control:
	var chk := CombatService.check_craft(id)
	var g := CombatData.gear(id)
	var r := CombatData.recipe(id)
	var owned := CombatService.is_owned(id)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.09, 0.07, 1.0) if not owned else Color(0.08, 0.1, 0.07, 1.0)
	sb.border_color = Color8(0x3E, 0x31, 0x25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	Tip.bind(panel, CombatData.item_name(id), _gear_tip(id), String(chk["reason"]) if not bool(chk["ok"]) else "Тап — собрать")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)

	var res := TextureRect.new()
	res.texture = CombatData.icon(id)
	res.custom_minimum_size = Vector2(32, 32)
	res.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	res.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(res)

	var mats := VBoxContainer.new()
	mats.add_theme_constant_override("separation", 0)
	mats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mats.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(mats)
	var inputs: Dictionary = r.get("inputs", {})
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 3)
	mats.add_child(line)
	for mid in inputs.keys():
		var need := int(inputs[mid])
		var have := CombatService.held(String(mid))
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 0)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		var ic := TextureRect.new()
		ic.texture = CombatData.icon(String(mid))
		ic.custom_minimum_size = Vector2(16, 16)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(ic)
		var num := _small_label("%d/%d" % [mini(have, 999), need], 9, GREEN if have >= need else RED)
		chip.add_child(num)
		Tip.bind(chip, CombatData.material_name(String(mid)), "Есть %d, нужно %d (склад и рюкзак)" % [have, need])
		line.add_child(chip)
	var coins := int(r.get("coins", 0))
	if coins > 0:
		var cl := HBoxContainer.new()
		cl.add_theme_constant_override("separation", 0)
		cl.mouse_filter = Control.MOUSE_FILTER_PASS
		var ci := TextureRect.new()
		ci.texture = UiIcons.tex("coin")
		ci.custom_minimum_size = Vector2(12, 12)
		ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(ci)
		var enough := GameState.debug_free_shop or GameState.coins >= coins
		cl.add_child(_small_label(UiFmt.short(coins), 9, GREEN if enough else RED))
		Tip.bind(cl, "Монеты", "%d монет за работу кузнеца" % coins)
		mats.add_child(cl)

	var btn := UiBtn.icon_button(UiIcons.tex("check") if owned else UiIcons.tex("workshop"), Vector2(28, 28),
		UiBtn.Kind.ACCENT if bool(chk["ok"]) else UiBtn.Kind.NORMAL, 16)
	btn.disabled = owned
	if not bool(chk["ok"]) and not owned:
		btn.modulate = Color(1, 1, 1, 0.55)
	btn.pressed.connect(func() -> void:
		if Tip.swallowed() or owned:
			return
		var out := CombatService.craft(id)
		if bool(out["ok"]):
			Sfx.play("ui_buy")
			Sfx.play("quest_done", 1.2, -6.0)
			Haptics.thud()
			_rebuild()
		else:
			Sfx.play("ui_deny")
			_deny(btn)
			Tip.show_now(panel))
	row.add_child(btn)
	return panel

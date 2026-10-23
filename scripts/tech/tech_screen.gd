class_name TechScreen
extends Control
## Экран техники: три вкладки-иконки — бак (топливо), костюм (жара и лава),
## скважина. Станция заправки в огороде открывает его на вкладке бака с доступом
## к складу; из меню «•••» — на любой вкладке «посмотреть», а улучшать можно на
## поверхности и дома (TechCost.can_act_here).
##
## Текста на плитках нет: иконка и число; названия и описания — в подсказках Tip.
## Экран пересобирается целиком при каждом действии — он маленький, а состояние
## (бак, костюм, склад) читается из общих хранилищ, своего у экрана нет.
##
## Пока экран открыт, герой стоит, а HUD не ловит ввод (TechSystem.is_modal_open).

const TAB_TANK := "tank"
const TAB_SUIT := "suit"
const TAB_WELL := "well"

const TOOL_ICONS := {
	"hand_drill": "res://art/items/hand_drill.png",
	"drill_rig": "res://art/items/drill_rig_icon.png",
}
const TOOL_TIPS := {
	"hand_drill": ["Бак ручного бура", "Жжёт топливо за каждую прокопанную клетку. Пустой — копаешь киркой."],
	"drill_rig": ["Бак бурмобиля", "Пустой бак — бурмобиль глохнет под землёй."],
}

static var _instance: TechScreen = null

var _player: Node = null
var _tab: String = TAB_TANK
var _tool: String = "hand_drill"
var _station: bool = false
var _tier_sel: int = 0
var _tab_buttons: Dictionary = {}
var _content: VBoxContainer = null
var _fx_layer: Control = null
var _gauge_from: float = -1.0


# ---------------------------------------------------------------------------
# Точка входа
# ---------------------------------------------------------------------------

static func attach(host: Node, player: Node) -> TechScreen:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var layer := CanvasLayer.new()
	layer.name = "TechLayer"
	# 94: выше HUD и дома, ниже экрана героя (95), окна отчёта (96) и катсцен (100).
	layer.layer = 94
	host.add_child(layer)
	var screen := TechScreen.new()
	screen.name = "TechScreen"
	screen._player = player
	layer.add_child(screen)
	return screen


static func instance() -> TechScreen:
	return _instance if _instance != null and is_instance_valid(_instance) else null


static func open(tab: String = TAB_TANK, station: bool = false) -> void:
	var s := instance()
	if s != null:
		s.open_tab(tab, station)


static func is_open() -> bool:
	var s := instance()
	return s != null and s.visible


static func close_screen() -> void:
	var s := instance()
	if s != null:
		s.close()


# ---------------------------------------------------------------------------
# Жизненный цикл
# ---------------------------------------------------------------------------

func _ready() -> void:
	_instance = self
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(_fit)
	_fit()
	var bg := ColorRect.new()
	bg.color = Color(0.071, 0.055, 0.043, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 6
	column.offset_right = -6
	column.offset_top = 6
	column.offset_bottom = -6
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	column.add_child(_build_tabs())
	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	column.add_child(_content)
	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)
	visible = false
	GameState.game_event.connect(_on_game_event)


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var defs := [
		[TAB_TANK, "icon_tank", "Топливо", "Бак бура и бурмобиля, заправка"],
		[TAB_SUIT, "suit_1", "Костюм", "Защита от жары и лавы"],
		[TAB_WELL, "icon_well", "Скважина", "Копает сама, пока тебя нет"],
	]
	for d in defs:
		var b := UiBtn.icon_button(TechUi.tex(String(d[1])), Vector2(44, 32), UiBtn.Kind.NORMAL, 24)
		Tip.bind(b, String(d[2]), String(d[3]))
		b.pressed.connect(func() -> void:
			if Tip.swallowed():
				return
			open_tab(String(d[0]), _station))
		row.add_child(b)
		_tab_buttons[String(d[0])] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var x := UiBtn.icon_button(UiIcons.tex("close"), Vector2(32, 32), UiBtn.Kind.NORMAL, 16)
	Tip.bind(x, "Закрыть")
	x.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		close())
	row.add_child(x)
	return row


func open_tab(tab: String, station: bool = false) -> void:
	_tab = tab
	_station = station or (visible and _station and tab == TAB_TANK)
	if not visible:
		_station = station
		_enter()
	refresh()


func _enter() -> void:
	visible = true
	Sfx.play("ui_open")
	if _player != null:
		_player.digging = null
		_player.release_control()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("close_inventory"):
		hud.close_inventory()
	UiAnim.appear(self, 0.97, 0.12)
	if not FuelTank.uses_fuel(_tool) or not GameState.owns_tool(_tool):
		_tool = GameState.current_tool if FuelTank.uses_fuel(GameState.current_tool) else "hand_drill"


## Выбрать бак бура или бурмобиля (экран при этом уже открыт).
func select_tool(tool_id: String) -> void:
	_tool = tool_id
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play("ui_close")
	SaveSystem.save_game()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_game_event(id: StringName, _data: Dictionary) -> void:
	# Золото, топливо и склад меняются и без экрана (скважина, сбор); открытый
	# экран подхватывает это на следующем действии, а не дёргается каждый кадр.
	if visible and id == &"well_collected":
		refresh()


func refresh() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	for key in _tab_buttons.keys():
		var b: Button = _tab_buttons[key]
		UiBtn.set_kind(b, UiBtn.Kind.ACCENT if key == _tab else UiBtn.Kind.NORMAL)
	match _tab:
		TAB_SUIT: _build_suit()
		TAB_WELL: _build_well()
		_: _build_tank()


# ---------------------------------------------------------------------------
# Общие детали
# ---------------------------------------------------------------------------

func _card() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", TechUi.box(TechUi.PANEL, TechUi.BORDER, 6, 6))
	_content.add_child(p)
	return p


func _vbox(parent: Node, sep: int = 5) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v


func _hbox(parent: Node, sep: int = 4, center: bool = true) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	if center:
		h.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(h)
	return h


func _pips(parent: Node, total: int, filled: int, color: Color = TechUi.GOLD) -> void:
	var row := _hbox(parent, 2)
	for i in range(total):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(maxf(4.0, floorf(150.0 / float(total)) - 3.0), 5)
		pip.color = color if i < filled else Color(0.2, 0.16, 0.12)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)


func _text_button(text: String, kind: int = UiBtn.Kind.NORMAL, width: float = 40.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 9)
	b.custom_minimum_size = Vector2(width, 24)
	UiBtn.style(b, kind)
	return b


## Цена: монеты и материалы «есть/нужно» — красным то, чего не хватает.
func _cost_row(parent: Node, cost) -> void:
	if cost == null:
		return
	var check := TechCost.check(cost)
	var row := _hbox(parent, 6)
	var coins := TechCost.coins_of(cost)
	if coins > 0:
		var lack: bool = int(check["missing_coins"]) > 0
		var c := TechUi.chip(UiIcons.tex("coin"), TechUi.short(coins), TechUi.RED if lack else TechUi.GOLD)
		Tip.bind(c, "Монеты", "Есть: %d" % GameState.coins)
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(c)
	var items := TechCost.items_of(cost)
	for id in items.keys():
		var need := int(items[id])
		var have := TechCost.held(String(id))
		var chip := TechUi.chip(TechUi.item_icon(String(id)), "%d/%d" % [have, need],
			TechUi.GREEN if have >= need else TechUi.RED, 16)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		Tip.bind(chip, TechUi.item_name(String(id)), "Склад и рюкзак", "есть %d из %d" % [have, need])
		row.add_child(chip)


func _deny(b: Control) -> void:
	UiAnim.shake(b)
	Sfx.play("ui_deny")
	Haptics.buzz(30)


func _bought(b: Control) -> void:
	UiAnim.pulse(b, 0.3, 0.3)
	Sfx.play("ui_buy")
	Haptics.thud()
	Fx.flash(Color(1.0, 0.85, 0.4, 0.22), 0.18)


# ---------------------------------------------------------------------------
# Вкладка «Бак»
# ---------------------------------------------------------------------------

func _build_tank() -> void:
	var tools_row := _hbox(_content, 6)
	for t in TOOL_ICONS.keys():
		var owned := GameState.owns_tool(t)
		var kind := UiBtn.Kind.ACCENT if t == _tool else UiBtn.Kind.NORMAL
		var b := UiBtn.icon_button(load(TOOL_ICONS[t]), Vector2(44, 40), kind, 28)
		b.modulate = Color(1, 1, 1, 1.0 if owned else 0.45)
		Tip.bind(b, String(TOOL_TIPS[t][0]), String(TOOL_TIPS[t][1]), "" if owned else "ещё не собран")
		b.pressed.connect(func() -> void:
			if Tip.swallowed():
				return
			_tool = t
			refresh())
		tools_row.add_child(b)

	var card := _card()
	var v := _vbox(card, 6)
	# Полоска топлива с числом поверх.
	var gauge := _hbox(v, 4)
	gauge.add_child(TechUi.icon_rect(TechUi.tex("icon_flame"), 22))
	var bar := TechUi.make_bar(166, 18, TechUi.FIRE)
	gauge.add_child(bar)
	var frac := FuelTank.fraction(_tool)
	var color: Color = TechUi.RED if FuelTank.is_low(_tool) else TechUi.FIRE
	if _gauge_from >= 0.0:
		TechUi.set_fill(bar, _gauge_from, color)
		TechUi.set_fill(bar, frac, color, true)
		_gauge_from = -1.0
	else:
		TechUi.set_fill(bar, frac, color)
	var num := TechUi.label("%.1f/%d" % [FuelTank.fuel(_tool), int(FuelTank.capacity(_tool))], 9, Color.WHITE)
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(num)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind(bar, "Топливо в баке", "Блоки в баке / ёмкость. Каждая прокопанная клетка сжигает долю блока.")

	var facts := _hbox(v, 10)
	var cells := TechUi.chip(UiIcons.tex("depth"), str(FuelTank.cells_left(_tool)), TechUi.MUTED)
	cells.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind(cells, "Хватит на клеток", "Сколько клеток можно прокопать на этом топливе")
	facts.add_child(cells)
	var rate := TechUi.chip(TechUi.tex("fuel_block"), "%d" % int(round(1.0 / maxf(FuelTank.rate_per_cell(_tool), 0.001))),
		TechUi.MUTED, 16)
	rate.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind(rate, "Клеток на блок", "Один топливный блок — столько клеток")
	facts.add_child(rate)

	_pips(v, FuelTank.max_level(_tool) + 1, FuelTank.level(_tool) + 1)
	var next = FuelTank.next_cost(_tool)
	if next != null:
		var up := _hbox(v, 6)
		var ub := UiBtn.icon_button(TechUi.tex("icon_up"), Vector2(34, 26), UiBtn.Kind.ACCENT, 18)
		Tip.bind(ub, "Улучшить бак", "Ёмкость вырастет до %d блоков" % int(FuelTank.capacities(_tool)[FuelTank.level(_tool) + 1]),
			TechCost.reason_cannot())
		ub.pressed.connect(func() -> void:
			if Tip.swallowed():
				return
			var r := FuelTank.upgrade(_tool)
			if bool(r["ok"]):
				_bought(ub)
				refresh()
			else:
				_deny(ub))
		up.add_child(ub)
		_cost_row(up, next)
	else:
		var maxed := TechUi.icon_rect(TechUi.tex("icon_check"), 18)
		maxed.mouse_filter = Control.MOUSE_FILTER_STOP
		Tip.bind(maxed, "Бак максимальный")
		_hbox(v).add_child(maxed)

	# Источники блоков: рюкзак (откуда угодно) и склад (на станции).
	var src := _card()
	var sv := _vbox(src, 6)
	_source_row(sv, "pack", UiIcons.tex("backpack"), FuelTank.in_pack(), true, "Рюкзак", "Блоки в рюкзаке — заливать можно и в шахте")
	_source_row(sv, "storage", TechUi.tex("icon_storage"), FuelTank.in_storage(), _station or HouseStorage.can_access(),
		"Склад", "Блоки со склада — только у станции заправки или в мастерской")


func _source_row(parent: Node, source: String, icon: Texture2D, have: int, allowed: bool, title: String, body: String) -> void:
	var row := _hbox(parent, 6)
	var ic := TechUi.icon_rect(icon, 24)
	ic.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind(ic, title, body)
	ic.name = "Src_" + source
	row.add_child(ic)
	var cnt := TechUi.chip(TechUi.tex("fuel_block"), "×%d" % have, TechUi.GOLD if have > 0 else TechUi.DIM, 20)
	cnt.custom_minimum_size = Vector2(60, 0)
	row.add_child(cnt)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var one := _text_button("+1", UiBtn.Kind.NORMAL, 34)
	var all := _text_button("МАКС", UiBtn.Kind.ACCENT, 48)
	for b in [one, all]:
		(b as Button).disabled = not allowed
		Tip.bind(b, "Залить %s" % ("один блок" if b == one else "сколько влезет"), title,
			"" if allowed else "Недоступно отсюда")
		(b as Button).pressed.connect(func() -> void:
			if Tip.swallowed():
				return
			_pour(source, 1 if b == one else -1, ic, b))
	row.add_child(one)
	row.add_child(all)


func _pour(source: String, amount: int, from_ctrl: Control, btn: Control) -> void:
	var before := FuelTank.fraction(_tool)
	var n := FuelTank.refuel(_tool, source, amount)
	if n <= 0:
		_deny(btn)
		return
	Sfx.play("ui_buy")
	Haptics.tap()
	_gauge_from = before
	var from := from_ctrl.get_global_rect().get_center()
	var to := Vector2(size.x * 0.5, from_ctrl.get_global_rect().position.y - 100.0)
	for i in range(mini(n, 6)):
		TechUi.fly(_fx_layer, TechUi.tex("fuel_block"), from, to, 0.05 * i, Callable(), 18.0)
	SaveSystem.save_game()
	refresh()


# ---------------------------------------------------------------------------
# Вкладка «Костюм»
# ---------------------------------------------------------------------------

func _build_suit() -> void:
	var worn := Heat.suit_tier()
	var depth := maxf(float(GameState.max_depth_reached), 0.0)
	if _tier_sel <= 0 or _tier_sel > Heat.suit_tiers().size():
		_tier_sel = mini(worn + 1, Heat.suit_tiers().size())

	var head := _card()
	var hv := _hbox(head, 10)
	var cur_depth := float(maxi(GameState.player_depth, 0))
	var lvl := Heat.felt_level(cur_depth)
	var th := TechUi.icon_rect(TechUi.tex("icon_thermo_%d" % lvl), 30)
	th.mouse_filter = Control.MOUSE_FILTER_STOP
	var z := Heat.zone(cur_depth)
	Tip.bind(th, String(z.get("name_ru", "")), "Температура породы на твоей глубине", "%d °C" % int(Heat.temperature(cur_depth)))
	hv.add_child(th)
	hv.add_child(TechUi.label("%d°" % int(Heat.temperature(cur_depth)), 12,
		[TechUi.GREEN, TechUi.FIRE, TechUi.RED][lvl]))
	var arrow := TechUi.icon_rect(TechUi.tex("icon_down"), 14)
	hv.add_child(arrow)
	var worn_icon := TechUi.tex("suit_%d" % worn) if worn > 0 else UiIcons.tex("hero")
	var wi := TechUi.icon_rect(worn_icon, 34)
	wi.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind(wi, "Надето", String(Heat.suit_tiers()[worn - 1].get("name_ru", "")) if worn > 0 else "Без костюма")
	hv.add_child(wi)

	# Ряд ступеней.
	var tiers_card := _card()
	var tr := _hbox(tiers_card, 4)
	var tiers := Heat.suit_tiers()
	for i in range(tiers.size()):
		tr.add_child(_suit_tile(i + 1, tiers[i], worn, depth))

	# Подробности выбранной ступени.
	var row: Dictionary = tiers[_tier_sel - 1]
	var detail := _card()
	var dv := _vbox(detail, 6)
	var stats := _hbox(dv, 10)
	var s1 := TechUi.chip(TechUi.tex("icon_thermo_1"), "%d°" % int(row["tolerance_c"]), TechUi.MUTED, 18)
	s1.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind(s1, "Держит жару", "До этой температуры породы бодрость не тратится быстрее")
	stats.add_child(s1)
	var resist := float(row["lava_resist"])
	var s2 := TechUi.chip(TechUi.tex("icon_flame"), "−%d%%" % int(round(resist * 100.0)), TechUi.FIRE, 18)
	s2.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind(s2, "Урон лавы", "Доля урона лавы, которую снимает костюм")
	stats.add_child(s2)
	var hp_cost := Heat.lava_cell_cost_hp(_tier_sel)
	var s3 := TechUi.chip(UiIcons.tex("hp"), "%d" % int(round(hp_cost)), TechUi.RED if hp_cost >= GameState.get_max_hp() else TechUi.MUTED, 18)
	s3.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind(s3, "Цена клетки лавы", "Столько здоровья уходит, пока копаешь одну клетку лавы", "у тебя %d HP" % int(GameState.get_max_hp()))
	stats.add_child(s3)

	if _tier_sel <= worn:
		var done := TechUi.icon_rect(TechUi.tex("icon_check"), 22)
		done.mouse_filter = Control.MOUSE_FILTER_STOP
		Tip.bind(done, "Уже сделано")
		_hbox(dv).add_child(done)
	else:
		_cost_row(dv, row.get("cost", null))
		var actions := _hbox(dv, 8)
		var unlock := int(row.get("unlock_depth", 0))
		var locked_depth := GameState.max_depth_reached < unlock
		var order_ok := _tier_sel == worn + 1
		var cb := UiBtn.icon_button(TechUi.tex("icon_lock") if (locked_depth or not order_ok) else TechUi.tex("icon_up"),
			Vector2(60, 28), UiBtn.Kind.ACCENT if not (locked_depth or not order_ok) else UiBtn.Kind.NORMAL, 20)
		var reason := ""
		if not order_ok:
			reason = "Сначала предыдущая ступень"
		elif locked_depth:
			reason = "Откроется на глубине %d" % unlock
		else:
			reason = TechCost.reason_cannot()
		Tip.bind(cb, "Сделать и надеть", String(row.get("name_ru", "")), reason)
		cb.pressed.connect(func() -> void:
			if Tip.swallowed():
				return
			var r := Heat.craft_suit()
			if bool(r["ok"]):
				_bought(cb)
				_tier_sel = mini(Heat.suit_tier() + 1, tiers.size())
				refresh()
			else:
				_deny(cb))
		actions.add_child(cb)
		if locked_depth:
			actions.add_child(TechUi.chip(UiIcons.tex("depth"), str(unlock), TechUi.RED))


func _suit_tile(tier: int, row: Dictionary, worn: int, depth: float) -> Control:
	var locked := GameState.max_depth_reached < int(row.get("unlock_depth", 0)) and tier > worn
	var kind := UiBtn.Kind.ACCENT if tier == _tier_sel else UiBtn.Kind.NORMAL
	var b := UiBtn.icon_button(TechUi.tex("suit_%d" % tier), Vector2(38, 46), kind, 28)
	b.modulate = Color(1, 1, 1, 0.5 if locked else 1.0)
	Tip.bind(b, String(row.get("name_ru", "")),
		"Держит жару до %d°, снимает %d%% урона лавы" % [int(row["tolerance_c"]), int(round(float(row["lava_resist"]) * 100.0))],
		"надето" if tier == worn else ("сделано" if tier < worn else ""))
	b.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		_tier_sel = tier
		refresh())
	if tier <= worn:
		var mark := TechUi.icon_rect(TechUi.tex("icon_check"), 12)
		mark.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		mark.position = Vector2(24, 33)
		b.add_child(mark)
	elif locked:
		var lk := TechUi.icon_rect(TechUi.tex("icon_lock"), 12)
		lk.position = Vector2(24, 33)
		b.add_child(lk)
	return b


# ---------------------------------------------------------------------------
# Вкладка «Скважина»
# ---------------------------------------------------------------------------

func _build_well() -> void:
	var card := _card()
	var v := _vbox(card, 7)
	var top := _hbox(v, 10)
	var big := TechUi.icon_rect(TechUi.tex("icon_well"), 44)
	big.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind(big, "Буровая скважина", "Копает сама, пока тебя нет. Добыча ложится на склад.")
	big.modulate = Color(1, 1, 1, 1.0 if IdleWell.is_built() else 0.4)
	top.add_child(big)
	if not IdleWell.is_built():
		var lk := TechUi.icon_rect(TechUi.tex("icon_lock"), 22)
		lk.mouse_filter = Control.MOUSE_FILTER_STOP
		Tip.bind(lk, "Скважина не построена", "Собирается на верстаке в мастерской (откроется на глубине %d)" % ShopCatalog.unlock_depth("well"))
		top.add_child(lk)
		return

	_pips(v, IdleWell.max_level(), GameState.well_level)
	var stats := _hbox(v, 8)
	stats.add_child(_stat_chip(UiIcons.tex("depth"), str(IdleWell.effective_depth()), "Глубина копки",
		"До какой глубины копает скважина (рекорд героя или предел ступени)", "предел %d" % IdleWell.depth_cap()))
	stats.add_child(_stat_chip(UiIcons.tex("coin"), TechUi.short(int(IdleWell.income_per_hour())), "Доход в час",
		"В монетах-эквиваленте; платит рудой на склад", "%d клеток в час" % int(IdleWell.cells_per_hour())))
	stats.add_child(_stat_chip(TechUi.tex("icon_hourglass"), "%dч" % int(IdleWell.cap_hours()), "Офлайн-кап",
		"Дольше этого скважина не копит — заглядывай почаще"))

	# Накоплено.
	var acc := _hbox(v, 6)
	acc.add_child(TechUi.icon_rect(TechUi.tex("icon_hourglass"), 20))
	var frac := IdleWell.fill_fraction()
	var bar := TechUi.make_bar(112, 14, TechUi.GREEN if frac < 1.0 else TechUi.GOLD)
	TechUi.set_fill(bar, frac)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind(bar, "Накоплено", "Полная полоска — скважина упёрлась в кап и стоит", TechUi.hm(IdleWell.pending_seconds()))
	acc.add_child(bar)
	var collect := UiBtn.icon_button(TechUi.tex("icon_storage"), Vector2(40, 28), UiBtn.Kind.ACCENT, 22)
	Tip.bind(collect, "Забрать добычу", "Руда ляжет на склад в мастерской")
	collect.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		var rep := IdleWell.collect()
		if rep.is_empty():
			_deny(collect)
			return
		var host := get_tree().get_first_node_in_group("well_report")
		if host != null and host.has_method("show_report"):
			host.call("show_report", rep)
		refresh())
	acc.add_child(collect)

	# Следующая ступень.
	var next = IdleWell.next_cost()
	if next == null:
		var maxed := TechUi.icon_rect(TechUi.tex("icon_check"), 18)
		maxed.mouse_filter = Control.MOUSE_FILTER_STOP
		Tip.bind(maxed, "Скважина лучшая")
		_hbox(v).add_child(maxed)
		return
	var nrow := IdleWell.level_row(GameState.well_level + 1)
	var preview := _hbox(v, 8)
	preview.add_child(_stat_chip(UiIcons.tex("depth"), str(int(nrow["depth_cap"])), "Следующая ступень: глубина", "Предел копки"))
	preview.add_child(_stat_chip(load(TOOL_ICONS["hand_drill"]), str(int(nrow["cells_per_hour"])), "Следующая ступень: скорость", "Клеток породы в час"))
	preview.add_child(_stat_chip(TechUi.tex("icon_hourglass"), "%dч" % int(nrow["cap_hours"]), "Следующая ступень: кап", "Офлайн-кап"))
	var up := _hbox(v, 6)
	var ub := UiBtn.icon_button(TechUi.tex("icon_up"), Vector2(34, 26), UiBtn.Kind.ACCENT, 18)
	Tip.bind(ub, "Улучшить скважину", "Накопленное сперва выплатится по старой ставке", TechCost.reason_cannot())
	ub.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		var r := IdleWell.upgrade()
		if bool(r["ok"]):
			_bought(ub)
			var rep: Dictionary = r.get("report", {})
			if not rep.is_empty():
				var host := get_tree().get_first_node_in_group("well_report")
				if host != null and host.has_method("show_report"):
					host.call("show_report", rep)
			refresh()
		else:
			_deny(ub))
	up.add_child(ub)
	_cost_row(up, next)


func _stat_chip(icon: Texture2D, number: String, title: String, body: String, extra: String = "") -> Control:
	var c := TechUi.chip(icon, number, TechUi.MUTED, 16)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind(c, title, body, extra)
	return c

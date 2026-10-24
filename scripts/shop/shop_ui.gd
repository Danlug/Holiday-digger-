class_name ShopUI
extends CanvasLayer
## ShopUI — витрина мобильной игры: магазин у входной двери и экипировка
## (верстак) в мастерской. Текста на экране нет: плитки с иконкой и числом, а
## название, описание и цена — в подсказке Tip (наведение / долгое нажатие).
##
## Вкладки внизу, в зоне большого пальца: Еда, Снаряга, Техника, Продать и
## отдельная заметная вкладка «магазин за доллары». Тап по плитке открывает
## компактную карточку подтверждения (зелёная галочка / красный крестик) —
## случайная покупка невозможна; «Продать» — крупная кнопка с суммой.
##
## Состав плиток считает ShopItems (из data/shop.json, balance.json и состояния
## игрока), рисует ShopTile, эффекты — ShopFx. Торговая логика — ShopService,
## ShopCatalog и Equipment — здесь не дублируется.
##
## Точки входа:
##   ShopUI.open_shop()      — от входной двери, открывает «Еду»;
##   ShopUI.open_workshop()  — верстак: экипировка надетого (не магазин);
##   ShopUI.open_premium()   — витрина за доллары.
##
## Пока шторка открыта, герой заморожен, а ввод HUD выключен: джойстик лежит
## под шторкой на всю ширину экрана и иначе перехватывал бы нажатия.

const TAB_PICKS := "picks"
const TAB_TECH := "tech"
const TAB_FOOD := "food"
const TAB_SELL := "sell"
## Экипировка — не вкладка магазина, а отдельный экран со своей дверью.
const SCREEN_EQUIP := "equip"
## Витрина за доллары — вкладка, но заметная: шире остальных и с ореолом.
const SCREEN_PREMIUM := "premium"

const NAV_TABS := [TAB_FOOD, TAB_PICKS, TAB_TECH, TAB_SELL, SCREEN_PREMIUM]
const NAV_ICONS := {TAB_FOOD: "tab_food", TAB_PICKS: "tab_picks", TAB_TECH: "tab_tech",
	TAB_SELL: "tab_sell", SCREEN_PREMIUM: "tab_premium"}
const NAV_TIPS := {TAB_FOOD: ["Еда", "Заказ с доставкой к двери и допинги"],
	TAB_PICKS: ["Снаряжение", "Кирки и ранцы за монеты"],
	TAB_TECH: ["Техника", "Собирается на верстаке из материалов"],
	TAB_SELL: ["Продать", "Сдать руду из рюкзака"],
	SCREEN_PREMIUM: ["Магазин за доллары", "Гаджеты, обмен и ролики"]}

const CARD_INFO_KEY := "shop_confirm"   # GameState.ext: {tapped: bool} — игрок уже знает про тап по значку
const NAV_H := 38.0
const HEAD_H := 32.0
const ACTION_H := 46.0

const GOLD := Color8(0xE0, 0xA9, 0x3B)
const INK := Color(0.05, 0.04, 0.08)

## Единственный живой экземпляр — чтобы дом мог открыть магазин одной
## строкой, не протаскивая ссылку через полдерева сцен.
static var instance: ShopUI = null

var _tab: String = TAB_FOOD
## "sell" — обычная скупка дома, "remote" — дистанционная сдача за ролик.
var _footer_mode: String = "sell"
var _selected: Dictionary = {}   # mineral_id -> true, что отмечено к продаже
var _busy: bool = false
var _shown_new: Array = []

var _root: Control
var _scroll: ScrollContainer
var _list: VBoxContainer
var _drag: DragScroll
var _tiles: Dictionary = {}      # key предложения -> ShopTile

var _chips: Dictionary = {}      # "coins" / "dollars" / "dig" / "fly" -> {root, icon, label}
var _shown_coins: int = 0
var _shown_dollars: int = 0
var _wallet_hold: bool = false
var _wallet_tween: Dictionary = {}
var _close_btn: Button

var _nav: Control
var _nav_tabs: Control
var _nav_done: Button
var _tab_buttons: Dictionary = {}
var _tab_badges: Dictionary = {}
var _marker: NinePatchRect
var _premium_glow: TextureRect

var _action: Control
var _sell_btn: Button
var _sell_label: Label
var _sell_x2: TextureRect
var _sell_uses: Label
var _sell_lead: TextureRect
var _ad_btn: Button
var _ad_label: Label

var _card: Control = null
var _card_offer: Dictionary = {}
var _card_ok: Button = null
var _card_panel: Control = null   # плашка карточки: над ней встаёт описание по тапу
var _info_pulse: Tween = null     # пульсация «i», пока игрок не научился тапать

var _notice_panel: Panel
var _notice_label: Label
var _notice_timer: Timer

var _player: Node = null
var _hud: Node = null
var _was_frozen: bool = false
var _hud_input_was_on: bool = true


# ---------------------------------------------------------------------------
# Точки входа
# ---------------------------------------------------------------------------

## Верстак из комнаты мастерской (scripts/house/) — одна строка на их стороне.
## Открывает ЭКИПИРОВКУ: магазин переехал к входной двери.
static func open_workshop() -> void:
	if instance == null:
		push_warning("ShopUI: магазин не подключён к сцене (см. scripts/main.gd)")
		return
	instance.open(SCREEN_EQUIP)


## Магазин у входной двери (подсказку «заказать» рисует scripts/house/).
static func open_shop() -> void:
	if instance == null:
		push_warning("ShopUI: магазин не подключён к сцене (см. scripts/main.gd)")
		return
	instance.open(TAB_FOOD)


## Витрина за доллары: открывается откуда угодно (обмен, ролики-награды), но
## гаджеты в ней покупаются по правилу места — ShopService.can_buy (ГДД §15).
static func open_premium() -> void:
	if instance == null:
		push_warning("ShopUI: магазин не подключён к сцене (см. scripts/main.gd)")
		return
	instance.open(SCREEN_PREMIUM)


func _ready() -> void:
	instance = self
	layer = 20  # выше HUD: шторка обязана перекрывать джойстик и нижнюю полосу
	_build()
	_root.visible = false
	GameState.tool_purchase_required.connect(_on_tool_purchase_required)
	GameState.coins_changed.connect(func(_c): _sync_wallet(true))
	GameState.dollars_changed.connect(func(_d): _sync_wallet(true))
	# Новые сутки вернули ролики на покупки под землёй: открытая витрина обновляет бейджи.
	GameState.daily_reset.connect(func() -> void:
		if is_open():
			_render())


func _exit_tree() -> void:
	if instance == self:
		instance = null


func is_open() -> bool:
	return _root != null and _root.visible


func open(tab: String = TAB_FOOD) -> void:
	_resolve_refs()
	# Повторное open() при открытой шторке (из вкладки в экипировку) мир второй
	# раз не замораживает: иначе «как было» запомнилось бы уже замороженным.
	if not is_open():
		_freeze_world(true)
	ShopItems.seed_seen()
	_selected.clear()
	# По умолчанию отмечено всё: типовой сценарий — поднялся с полным рюкзаком
	# и сдал его целиком, а снимать отметки нужно в порядке исключения.
	for row in ShopService.sellable_stacks():
		_selected[row["id"]] = true
	_busy = false
	_close_card(false)
	_root.visible = true
	_root.modulate.a = 1.0
	Sfx.play("ui_open")
	if tab == SCREEN_EQUIP:
		# Ржавая кирка находится в мастерской среди удочек, лопат и палок (слова
		# владельца) — то есть ровно здесь, у верстака, а не в магазине.
		if ShopService.visit_workshop():
			notice("Среди удочек, лопат и палок нашлась ржавая кирка.", 4.0)
	_set_tab(tab, false)
	_announce_place(tab)


## Витрину открыли вне двери и не под землёй (меню или «Магазин» на огороде):
## плитки заперты, и сразу говорим почему. Под землёй не нужно — там плитки с
## бейджем роликов, а отказ при пустом лимите объясняет сама плитка.
func _announce_place(tab: String) -> void:
	if tab == SCREEN_EQUIP or tab == TAB_SELL:
		return
	var gate := ShopService.can_buy({"kind": "good"})
	if not bool(gate["ok"]) and String(gate["place"]) != ShopService.PLACE_UNDERGROUND:
		notice(String(gate["reason"]), 3.2)


func close() -> void:
	if _root == null or not _root.visible:
		return
	_close_card(false)
	_leave_tab()
	_root.visible = false
	Tip.hide_all()
	Sfx.play("ui_close")
	_freeze_world(false)


func _resolve_refs() -> void:
	# Ссылки ищутся по имени, а не передаются из main.gd: подключение магазина
	# к сцене — одна строка, и протаскивать в неё героя с HUD незачем.
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().root.find_child("Player", true, false)
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().root.find_child("HUD", true, false)


## Пока шторка открыта, герой стоит (ГДД раздел 16), а ввод HUD выключен —
## иначе джойстик, лежащий под шторкой, перехватывает нажатия раньше плиток.
func _freeze_world(frozen: bool) -> void:
	if _player != null and is_instance_valid(_player):
		if frozen:
			# Запоминаем, как было: внутри дома герой уже заморожен домом, и
			# снять заморозку на закрытии значило бы отпустить его копать
			# где-то под домом, пока игрок смотрит на интерьер.
			_was_frozen = bool(_player.frozen)
			_player.frozen = true
			_player.digging = null
			_player.release_control()
		else:
			_player.frozen = _was_frozen
	if _hud != null and is_instance_valid(_hud):
		if frozen:
			_hud_input_was_on = _hud.is_processing_input()
			_hud.set_process_input(false)
			if _hud.has_method("close_inventory"):
				_hud.close_inventory()
		else:
			_hud.set_process_input(_hud_input_was_on)


func _input(event: InputEvent) -> void:
	if not is_open() or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _card != null:
		_close_card(true)
	else:
		close()


# ---------------------------------------------------------------------------
# Построение каркаса
# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "ShopRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color8(0x26, 0x1E, 0x30), Color8(0x14, 0x0F, 0x1B)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 64
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_build_scroll()
	_build_header()
	_build_action_bar()
	_build_nav()
	_build_notice()


func _build_scroll() -> void:
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = HEAD_H + 2.0
	_scroll.offset_bottom = -NAV_H
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_root.add_child(_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 10)
	_scroll.add_child(margin)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	margin.add_child(_list)
	_drag = DragScroll.attach(_scroll)


func _build_header() -> void:
	var line := ColorRect.new()
	line.color = Color8(0x4A, 0x3F, 0x5C)
	line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	line.offset_top = HEAD_H
	line.offset_bottom = HEAD_H + 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(line)

	_chips["coins"] = _make_chip(ShopArt.ui("icon_coin"), 80.0, Vector2(6, 6))
	_chips["dollars"] = _make_chip(ShopArt.ui("icon_dollar"), 64.0, Vector2(90, 6))
	_chips["dig"] = _make_chip(ShopArt.tex("glyph_dig"), 56.0, Vector2(6, 6))
	_chips["fly"] = _make_chip(ShopArt.tex("glyph_fly"), 56.0, Vector2(66, 6))

	_close_btn = _make_btn("red", "glyph_cross", Vector2(32, 24), 14.0)
	_close_btn.position = Vector2(224.0 - 32.0 - 6.0, 4.0)
	_close_btn.anchor_left = 1.0
	_close_btn.anchor_right = 1.0
	_close_btn.offset_left = -38.0
	_close_btn.offset_right = -6.0
	_close_btn.pressed.connect(func() -> void:
		if not Tip.swallowed():
			close())
	Tip.bind(_close_btn, "Закрыть")
	_root.add_child(_close_btn)


func _make_chip(icon: Texture2D, w: float, pos: Vector2) -> Dictionary:
	var root := Control.new()
	root.position = pos
	root.size = Vector2(w, 20)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := NinePatchRect.new()
	bg.texture = ShopArt.tex("pill")
	for m in ["left", "right", "top", "bottom"]:
		bg.set("patch_margin_" + m, 4)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var ic := ShopArt.rect(icon, Vector2(3, 3), Vector2(14, 14))
	root.add_child(ic)
	var lb := ShopArt.label("", 10)
	lb.position = Vector2(20, 1)
	lb.size = Vector2(w - 24.0, 18)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.clip_text = true
	root.add_child(lb)
	_root.add_child(root)
	return {"root": root, "icon": ic, "label": lb}


## Кнопка-картинка: рамка из девятизонника, знак по центру.
func _make_btn(kind: String, glyph: String, sz: Vector2, icon_px: float = 16.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = sz
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	var tex := ShopArt.tex("btn_" + kind)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = 5
		sb.texture_margin_right = 5
		sb.texture_margin_top = 5
		sb.texture_margin_bottom = 5
		match st:
			"pressed", "hover_pressed":
				sb.modulate_color = Color(0.78, 0.78, 0.78)
			"disabled":
				sb.modulate_color = Color(0.45, 0.45, 0.5)
		b.add_theme_stylebox_override(st, sb)
	if glyph != "":
		var ic := ShopArt.rect(ShopArt.tex(glyph), (sz - Vector2(icon_px, icon_px)) * 0.5, Vector2(icon_px, icon_px))
		ic.name = "Glyph"
		b.add_child(ic)
	b.button_down.connect(func() -> void:
		if b.disabled:
			return
		b.pivot_offset = b.size * 0.5
		b.create_tween().tween_property(b, "scale", Vector2(0.94, 0.94), 0.05))
	b.button_up.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	return b


func _build_nav() -> void:
	_nav = Control.new()
	_nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_nav.offset_top = -NAV_H
	_nav.offset_bottom = 0.0
	_nav.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_nav)
	var back := NinePatchRect.new()
	back.texture = ShopArt.tex("bar")
	for m in ["left", "right", "top", "bottom"]:
		back.set("patch_margin_" + m, 3)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav.add_child(back)

	_nav_tabs = Control.new()
	_nav_tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	_nav_tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav.add_child(_nav_tabs)

	_marker = NinePatchRect.new()
	_marker.texture = ShopArt.tex("tab_marker")
	for m in ["left", "right", "top", "bottom"]:
		_marker.set("patch_margin_" + m, 5)
	_marker.size = Vector2(40, NAV_H - 6.0)
	_marker.position = Vector2(2, 3)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav_tabs.add_child(_marker)

	var widths := {TAB_FOOD: 42.0, TAB_PICKS: 42.0, TAB_TECH: 42.0, TAB_SELL: 42.0, SCREEN_PREMIUM: 56.0}
	var x := 0.0
	for id in NAV_TABS:
		var w: float = widths[id]
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.position = Vector2(x, 0)
		b.size = Vector2(w, NAV_H)
		b.custom_minimum_size = b.size
		for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		if id == SCREEN_PREMIUM:
			_premium_glow = ShopArt.rect(ShopArt.tex("glow"), Vector2(0, -2), Vector2(w, NAV_H + 4.0))
			_premium_glow.stretch_mode = TextureRect.STRETCH_SCALE
			_premium_glow.modulate = Color(0.4, 1.0, 0.65, 0.5)
			b.add_child(_premium_glow)
		var isz := 30.0 if id == SCREEN_PREMIUM else 26.0
		var ic := ShopArt.rect(ShopArt.tex(String(NAV_ICONS[id])),
			Vector2((w - isz) * 0.5, (NAV_H - isz) * 0.5), Vector2(isz, isz))
		ic.name = "Icon"
		ic.pivot_offset = ic.size * 0.5
		b.add_child(ic)
		var badge := ShopArt.rect(ShopArt.tex("glyph_new"), Vector2(w - 15.0, 2), Vector2(11, 11))
		badge.visible = false
		b.add_child(badge)
		_tab_badges[id] = badge
		b.pressed.connect(func() -> void:
			if Tip.swallowed():
				return
			if _tab != id:
				_set_tab(id, true)
			else:
				_scroll.scroll_vertical = 0)
		var tip: Array = NAV_TIPS[id]
		Tip.bind(b, String(tip[0]), String(tip[1]))
		_nav_tabs.add_child(b)
		_tab_buttons[id] = b
		x += w
	_marker.get_parent().move_child(_marker, 0)

	# На экране верстака вкладок нет: одна большая кнопка «готово» под большим пальцем.
	_nav_done = _make_btn("green", "glyph_check", Vector2(96, 28), 18.0)
	_nav_done.anchor_left = 0.5
	_nav_done.anchor_right = 0.5
	_nav_done.offset_left = -48.0
	_nav_done.offset_right = 48.0
	_nav_done.offset_top = 5.0
	_nav_done.offset_bottom = 33.0
	_nav_done.pressed.connect(func() -> void:
		if not Tip.swallowed():
			close())
	Tip.bind(_nav_done, "Готово")
	_nav.add_child(_nav_done)


func _build_action_bar() -> void:
	_action = Control.new()
	_action.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_action.offset_top = -(NAV_H + ACTION_H)
	_action.offset_bottom = -NAV_H
	_action.mouse_filter = Control.MOUSE_FILTER_STOP
	_action.visible = false
	_root.add_child(_action)
	var back := NinePatchRect.new()
	back.texture = ShopArt.tex("bar")
	for m in ["left", "right", "top", "bottom"]:
		back.set("patch_margin_" + m, 3)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action.add_child(back)

	# Ролик «×2»: слева, маленькая кнопка; справа — крупная «Продать».
	_ad_btn = _make_btn("gray", "", Vector2(48, 36))
	_ad_btn.position = Vector2(6, 5)
	_ad_btn.add_child(ShopArt.rect(ShopArt.tex("glyph_video"), Vector2(4, 3), Vector2(14, 14)))
	_ad_btn.add_child(ShopArt.rect(ShopArt.tex("glyph_x2"), Vector2(14, 8), Vector2(30, 24)))
	_ad_label = ShopArt.label("", 9)
	_ad_label.position = Vector2(2, 20)
	_ad_label.size = Vector2(44, 14)
	_ad_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ad_btn.add_child(_ad_label)
	_ad_btn.pressed.connect(_on_ad_x2_pressed)
	_action.add_child(_ad_btn)

	_sell_btn = _make_btn("gold", "", Vector2(158, 38))
	_sell_btn.position = Vector2(60, 4)
	_sell_lead = ShopArt.rect(ShopArt.ui("icon_inventory"), Vector2(8, 5), Vector2(28, 28))
	_sell_btn.add_child(_sell_lead)
	_sell_btn.add_child(ShopArt.rect(ShopArt.ui("icon_coin"), Vector2(42, 11), Vector2(18, 18)))
	_sell_label = ShopArt.label("0", 14, Color.WHITE, Color8(0x6A, 0x3E, 0x0A), 4)
	_sell_label.position = Vector2(62, 6)
	_sell_label.size = Vector2(70, 26)
	_sell_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sell_label.clip_text = true
	_sell_btn.add_child(_sell_label)
	_sell_x2 = ShopArt.rect(ShopArt.tex("glyph_x2"), Vector2(134, 8), Vector2(22, 22))
	_sell_x2.visible = false
	_sell_btn.add_child(_sell_x2)
	_sell_uses = ShopArt.label("", 9, Color.WHITE, Color(0.2, 0.12, 0.02), 4)
	_sell_uses.position = Vector2(2, 20)
	_sell_uses.size = Vector2(36, 16)
	_sell_uses.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sell_uses.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sell_uses.visible = false
	_sell_btn.add_child(_sell_uses)
	_sell_btn.pressed.connect(_on_sell_pressed)
	_action.add_child(_sell_btn)


## Сообщение магазина. Живёт ВНЕ шторки: о том, что бур теперь собирается на
## верстаке, игрок узнаёт на глубине 100, когда никакого магазина не открыто.
func _build_notice() -> void:
	_notice_panel = Panel.new()
	_notice_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_notice_panel.offset_left = 10
	_notice_panel.offset_right = -10
	_notice_panel.offset_top = HEAD_H + 6.0
	_notice_panel.offset_bottom = HEAD_H + 46.0
	_notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.035, 0.027, 0.94)
	sb.border_color = GOLD
	sb.set_border_width_all(1)
	_notice_panel.add_theme_stylebox_override("panel", sb)
	add_child(_notice_panel)

	_notice_label = Label.new()
	_notice_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_notice_label.offset_left = 6
	_notice_label.offset_right = -6
	_notice_label.add_theme_font_size_override("font_size", 9)
	_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_panel.add_child(_notice_label)

	_notice_timer = Timer.new()
	_notice_timer.one_shot = true
	_notice_timer.timeout.connect(func() -> void: _notice_panel.visible = false)
	add_child(_notice_timer)


## Короткая плашка. Нужна для отказов («не хватает», «под землёй не бросить») и
## для сообщений игры вне магазина; об успешной покупке рассказывают анимация и звук.
func notice(text: String, seconds: float = 2.4) -> void:
	_notice_label.text = text
	_notice_panel.visible = true
	_notice_timer.start(seconds)


# ---------------------------------------------------------------------------
# Кошелёк
# ---------------------------------------------------------------------------

## Число в плашке кошелька: целиком, пока влезает, дальше 1.23M. Плашка с
## долларами уже монетной, поэтому ей «длинно» наступает раньше.
static func wallet_text(n: int, compact_from: int = 1000000) -> String:
	return ShopArt.full(n) if n < compact_from else ShopArt.compact(n)


func _chip_fmt(n: int, which: String) -> String:
	return wallet_text(n, 1000000 if which == "coins" else 10000)


func _sync_wallet(animate: bool) -> void:
	if _chips.is_empty():
		return
	if _wallet_hold:
		return
	_set_chip_value("coins", GameState.coins, animate)
	_set_chip_value("dollars", GameState.dollars, animate)
	Tip.bind(_chips["coins"]["root"], "Монеты", "", ShopArt.full(GameState.coins))
	Tip.bind(_chips["dollars"]["root"], "Доллары", "", ShopArt.full(GameState.dollars))


func _set_chip_value(which: String, value: int, animate: bool) -> void:
	var chip: Dictionary = _chips[which]
	var label: Label = chip["label"]
	var shown: int = _shown_coins if which == "coins" else _shown_dollars
	if _wallet_tween.has(which) and _wallet_tween[which] != null:
		(_wallet_tween[which] as Tween).kill()
		_wallet_tween[which] = null
	if animate and is_open() and shown != value:
		_wallet_tween[which] = ShopFx.count_up(self, label, shown, value, 0.45, 0.0, _chip_fmt.bind(which))
		ShopFx.pop(chip["root"], 0.12, 0.2)
	else:
		label.text = _chip_fmt(value, which)
	if which == "coins":
		_shown_coins = value
	else:
		_shown_dollars = value


## Кошелёк в шапке ждёт долёта монет: цифры добавляются, когда монеты прилетают.
func _sync_equip_chips() -> void:
	var dig: Dictionary = _chips["dig"]
	var fly: Dictionary = _chips["fly"]
	(dig["label"] as Label).text = "×" + ShopCatalog.mult_text(Equipment.current_dig_multiplier())
	var speed := Equipment.current_fly_speed()
	(fly["label"] as Label).text = ShopCatalog.mult_text(speed) if speed > 0.0 else "0"
	Tip.bind(dig["root"], "Скорость копки", "Кирка в руках")
	Tip.bind(fly["root"], "Скорость подъёма", "Ранец на спине, клеток в секунду")


# ---------------------------------------------------------------------------
# Вкладки
# ---------------------------------------------------------------------------

func _set_tab(tab: String, animate: bool) -> void:
	var old_index := NAV_TABS.find(_tab)
	if animate:
		_leave_tab()
		Sfx.play("ui_tab")
		Haptics.tap()
	_tab = tab
	_close_card(false)
	var equip := tab == SCREEN_EQUIP
	_nav_tabs.visible = not equip
	_nav_done.visible = equip
	_chips["coins"]["root"].visible = not equip
	_chips["dollars"]["root"].visible = not equip
	_chips["dig"]["root"].visible = equip
	_chips["fly"]["root"].visible = equip
	_scroll.scroll_vertical = 0
	_render()
	_move_marker(animate)
	if animate and not ShopFx.reduced():
		var dir := 1.0 if NAV_TABS.find(tab) >= old_index else -1.0
		_scroll.modulate.a = 0.0
		_scroll.offset_left = 18.0 * dir
		_scroll.offset_right = 18.0 * dir
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_scroll, "modulate:a", 1.0, 0.16)
		tw.tween_property(_scroll, "offset_left", 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_scroll, "offset_right", 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_scroll.modulate.a = 1.0
		_scroll.offset_left = 0.0
		_scroll.offset_right = 0.0


## Покидая вкладку, всё, что на ней светилось «новинкой», считаем увиденным.
func _leave_tab() -> void:
	if not _shown_new.is_empty():
		ShopItems.mark_seen(_shown_new)
		_shown_new = []


func _move_marker(animate: bool) -> void:
	var b: Button = _tab_buttons.get(_tab)
	for id in _tab_buttons.keys():
		var btn: Button = _tab_buttons[id]
		var ic: Control = btn.get_node("Icon")
		var on: bool = id == _tab
		ic.modulate = Color.WHITE if on else Color(0.7, 0.7, 0.78, 0.8)
		var target := Vector2.ONE * (1.14 if on else 1.0)
		if animate:
			ic.create_tween().tween_property(ic, "scale", target, 0.14).set_trans(Tween.TRANS_BACK)
		else:
			ic.scale = target
	if b == null:
		_marker.visible = false
		return
	_marker.visible = true
	var pos := Vector2(b.position.x + 2.0, 3.0)
	_marker.size = Vector2(b.size.x - 4.0, NAV_H - 6.0)
	if animate:
		create_tween().tween_property(_marker, "position", pos, 0.18) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_marker.position = pos
	if _premium_glow != null:
		_premium_glow.visible = true


func _update_badges() -> void:
	for id in NAV_TABS:
		var badge: TextureRect = _tab_badges[id]
		badge.visible = id != _tab and ShopItems.new_count(id) > 0


# ---------------------------------------------------------------------------
# Содержимое вкладки
# ---------------------------------------------------------------------------

func _clear_content() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_tiles.clear()


func _render() -> void:
	_sync_wallet(false)
	_shown_coins = GameState.coins
	_shown_dollars = GameState.dollars
	_clear_content()
	_footer_mode = "sell"
	if _tab == TAB_SELL and not ShopService.is_at_workshop():
		# Скупка работает только дома: иначе «продать со дна шахты» убило бы
		# решение игрока подниматься с грузом. Отсюда — только ролик.
		_footer_mode = "remote"
	if _tab == SCREEN_EQUIP:
		_sync_equip_chips()
	var sections := ShopItems.sections(_tab, _selected, _footer_mode == "remote")
	_shown_new = []
	var first := true
	for s in sections:
		var offers: Array = s["offers"]
		var extra := ""
		if first and _tab == TAB_FOOD and HouseFood.free_orders_left() > 0:
			extra = str(HouseFood.free_orders_left())
		_list.add_child(_make_section_header(s["icon"], extra))
		_list.add_child(_make_grid(offers))
		first = false
		for o in offers:
			if bool(o.get("new", false)):
				_shown_new.append(String(o["key"]))
	if _tab == TAB_SELL and ShopService.sellable_stacks().is_empty():
		_list.add_child(_make_empty_state())
	_update_badges()
	_update_action_bar()


func _make_section_header(icon: Texture2D, badge_text: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.custom_minimum_size = Vector2(0, 18)
	var ic := TextureRect.new()
	ic.texture = icon
	ic.custom_minimum_size = Vector2(16, 16)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var line := ColorRect.new()
	line.color = Color8(0x4A, 0x3F, 0x5C)
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	if badge_text != "":
		var gift := TextureRect.new()
		gift.texture = ShopArt.tex("glyph_gift")
		gift.custom_minimum_size = Vector2(16, 16)
		gift.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gift.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gift.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(gift)
		row.add_child(ShopArt.label(badge_text, 10, ShopArt.COL_GOOD))
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		Tip.bind(row, "Бесплатные заказы", "Бабка оставила денег: сегодня еда даром", "Осталось: " + badge_text)
	return row


func _make_grid(offers: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for o in offers:
		var t := ShopTile.new()
		t.setup(o)
		var offer: Dictionary = o
		t.pressed.connect(func() -> void: _on_tile_pressed(offer, t))
		_tiles[String(o["key"])] = t
		grid.add_child(t)
	return grid


func _make_empty_state() -> Control:
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(0, 150)
	var ic := TextureRect.new()
	ic.texture = ShopArt.ui("icon_backpack")
	ic.custom_minimum_size = Vector2(64, 64)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = Color(0.6, 0.6, 0.68, 0.7)
	ic.mouse_filter = Control.MOUSE_FILTER_PASS
	Tip.bind(ic, "Рюкзак пуст", "Руду и находки продают в мастерской: сначала накопай.")
	box.add_child(ic)
	return box


# ---------------------------------------------------------------------------
# Нажатие на плитку
# ---------------------------------------------------------------------------

func _on_tile_pressed(offer: Dictionary, tile: ShopTile) -> void:
	if Tip.swallowed() or _busy:
		return
	var state := String(offer["state"])
	match String(offer["kind"]):
		"sell":
			_toggle_sell(offer, tile)
		"nosale", "info":
			Sfx.play("ui_deny")
			tile.deny()
		"ad":
			_claim_ad(offer, tile)
		"equip_tool", "equip_gear":
			_equip(offer, tile)
		_:
			match state:
				"owned":
					Sfx.play("ui_tap")
					ShopFx.pop(tile, 0.08, 0.18)
				"locked", "away":
					Sfx.play("ui_deny")
					Haptics.tap()
					tile.deny()
					if offer.has("lock_reason"):
						notice(String(offer["lock_reason"]))
				"poor":
					if String(offer["kind"]) == "recipe":
						Sfx.play("ui_tap")
						_open_card(offer, tile)
					else:
						Sfx.play("ui_deny")
						Haptics.tap()
						tile.deny()
				_:
					Sfx.play("ui_tap")
					Haptics.tap()
					_open_card(offer, tile)
					_mark_remote_card(offer)


## Покупка за ролик (под землёй): значок ролика в углу зелёной кнопки
## подтверждения. Накладывается поверх готовой кнопки — вид самого окна не меняется.
func _mark_remote_card(offer: Dictionary) -> void:
	if _card_ok == null or not bool(offer.get("needs_ad", false)):
		return
	var ic := ShopArt.rect(ShopArt.tex("glyph_video"), Vector2(6, 8), Vector2(16, 16))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_ok.add_child(ic)


func _toggle_sell(offer: Dictionary, tile: ShopTile) -> void:
	if _footer_mode == "remote":
		Sfx.play("ui_deny")
		tile.deny()
		return
	var id := String(offer["ref"])
	var on := not bool(_selected.get(id, false))
	_selected[id] = on
	offer["selected"] = on
	tile.setup(offer)
	Sfx.play("ui_toggle")
	ShopFx.pop(tile, 0.1, 0.16)
	_update_action_bar()


func _equip(offer: Dictionary, tile: ShopTile) -> void:
	var state := String(offer["state"])
	if state == "active":
		Sfx.play("ui_tap")
		ShopFx.pop(tile, 0.06, 0.16)
		return
	if state == "locked":
		Sfx.play("ui_deny")
		tile.deny()
		return
	if state == "away":
		Sfx.play("ui_deny")
		tile.deny()
		notice("Верстак дома, в подвале")
		return
	var id := String(offer["ref"])
	var kind := String(offer["kind"])
	var result := Equipment.equip_tool(id) if kind == "equip_tool" else Equipment.equip_gear(id)
	if not bool(result["ok"]):
		Sfx.play("ui_deny")
		tile.deny()
		notice(String(result["message"]))
		return
	Sfx.play("ui_toggle")
	Haptics.tap()
	_render()
	var t: ShopTile = _tiles.get(String(offer["key"]))
	if t != null:
		_after_snap(t, ShopArt.COL_GOLD)


## Плитка «щёлкнула» в новое состояние: упругий скачок, искры, короткая вспышка.
func _after_snap(tile: ShopTile, color: Color) -> void:
	ShopFx.pop(tile, 0.22, 0.32)
	var rect := tile.get_global_rect()
	ShopFx.sparkles(_root, rect.get_center(), color, 14, 32.0)
	ShopFx.flash(_root, rect, Color(1, 1, 1, 0.55), 0.22)


# ---------------------------------------------------------------------------
# Карточка подтверждения
# ---------------------------------------------------------------------------

func _close_card(animate: bool) -> void:
	if _card == null:
		return
	var c := _card
	_card = null
	_card_ok = null
	_card_panel = null
	_drag.set_process_input(true)
	Tip.hide_all()
	if animate and c.is_inside_tree():
		Sfx.play("ui_close")
		var tw := create_tween()
		tw.tween_property(c, "modulate:a", 0.0, 0.1)
		tw.tween_callback(c.queue_free)
	else:
		c.queue_free()


func _open_card(offer: Dictionary, tile: ShopTile) -> void:
	_close_card(false)
	_card_offer = offer
	var kind := String(offer["kind"])
	var is_recipe := kind == "recipe"
	_card = Control.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_card)
	_drag.set_process_input(false)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed or ev is InputEventScreenTouch and ev.pressed:
			# Тап мимо открытого описания гасит только описание, окно остаётся.
			if not Tip.swallowed() and not Tip.dismissed_by_tap():
				_close_card(true))
	_card.add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 10.0
	panel.offset_right = -10.0
	panel.offset_bottom = -(NAV_H + 8.0)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxTexture.new()
	sb.texture = ShopArt.tex("panel")
	for m in ["left", "right", "top", "bottom"]:
		sb.set("texture_margin_" + m, 6)
		sb.set("content_margin_" + m, 9)
	panel.add_theme_stylebox_override("panel", sb)
	_card.add_child(panel)
	_card_panel = panel

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	panel.add_child(col)

	# Верх: большая плитка товара и чипы эффекта справа.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(top)
	var preview := ShopTile.new()
	var po: Dictionary = offer.duplicate()
	po["pill"] = {}
	po["new"] = false
	if String(po["state"]) == "poor":
		po["state"] = "available"
	po["count_text"] = ""
	preview.setup(po)
	preview.disabled = false
	top.add_child(preview)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(side)
	if offer.has("compare"):
		side.add_child(_make_compare_row(offer["compare"]))
	else:
		for e in offer.get("effects", []):
			side.add_child(_make_chip_row(e["icon"], String(e["text"]), Color.WHITE))
	_bind_card_info(preview, side, offer)

	if is_recipe:
		col.add_child(_make_inputs_grid(offer))
	else:
		col.add_child(_make_price_row(offer))

	# Низ: красный крестик слева, зелёная галочка справа — под большим пальцем.
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 8)
	col.add_child(btns)
	var cancel := _make_btn("red", "glyph_cross", Vector2(52, 32), 18.0)
	cancel.pressed.connect(func() -> void:
		if not Tip.swallowed():
			_close_card(true))
	Tip.bind(cancel, "Отмена")
	if is_recipe and bool(offer.get("can_invest", false)):
		var inv := _make_btn("gray", "glyph_storage", Vector2(52, 32), 18.0)
		inv.pressed.connect(func() -> void: _invest(offer))
		Tip.bind(inv, "На склад", "Переложить из рюкзака то, чего рецепту не хватает")
		btns.add_child(inv)
	btns.add_child(cancel)
	btns.move_child(cancel, 0)
	var ok_glyph := "glyph_hammer" if is_recipe else "glyph_check"
	_card_ok = _make_btn("green", ok_glyph, Vector2(96, 32), 20.0)
	var can_do := _card_can_confirm(offer)
	_card_ok.disabled = not can_do
	_card_ok.pressed.connect(_confirm_card)
	Tip.bind(_card_ok, String(offer["title"]), String(offer["body"]), String(offer["extra"]))
	btns.add_child(_card_ok)

	if ShopFx.reduced():
		return
	_card.modulate.a = 0.0
	await get_tree().process_frame
	if _card == null or not is_instance_valid(panel):
		return
	_card.modulate.a = 1.0
	panel.pivot_offset = Vector2(panel.size.x * 0.5, panel.size.y)
	panel.scale = Vector2(0.9, 0.9)
	panel.modulate.a = 0.0
	dim.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.12)
	tw.tween_property(dim, "modulate:a", 1.0, 0.15)


## Тап по значку товара (и по чипам эффекта) раскрывает описание тут же над
## карточкой; значок «i» на углу — намёк, что значок нажимается. Пока игрок ни
## разу не тапнул, «i» пару раз пульсирует; выучил — пульсация больше не нужна.
func _bind_card_info(preview: ShopTile, side: Control, offer: Dictionary) -> void:
	var title := String(offer["title"])
	var body := String(offer["body"])
	var extra := String(offer["extra"])
	Tip.bind_tap(preview, title, body, extra, _card_panel)
	side.mouse_filter = Control.MOUSE_FILTER_STOP
	Tip.bind_tap(side, title, body, extra, _card_panel)
	var badge := ShopArt.rect(ShopArt.tex("glyph_info"),
		Vector2(ShopTile.W - 17.0, ShopTile.H - 17.0), Vector2(14, 14))
	preview.add_child(badge)
	preview.pressed.connect(func() -> void:
		if not Tip.swallowed():
			_learn_card_info(badge))
	if _card_info_learned() or ShopFx.reduced():
		return
	badge.pivot_offset = badge.size * 0.5
	_info_pulse = badge.create_tween()
	_info_pulse.tween_interval(0.4)
	for i in 3:
		_info_pulse.tween_property(badge, "scale", Vector2(1.3, 1.3), 0.22).set_trans(Tween.TRANS_SINE)
		_info_pulse.tween_property(badge, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE)
		_info_pulse.tween_interval(0.25)


func _card_info_learned() -> bool:
	return bool((GameState.ext_get(CARD_INFO_KEY, {}) as Dictionary).get("tapped", false))


func _learn_card_info(badge: Control) -> void:
	if _info_pulse != null and _info_pulse.is_valid():
		_info_pulse.kill()
	if is_instance_valid(badge):
		badge.scale = Vector2.ONE
	if not _card_info_learned():
		var st: Dictionary = GameState.ext_get(CARD_INFO_KEY, {})
		st["tapped"] = true
		GameState.ext_set(CARD_INFO_KEY, st)


func _card_can_confirm(offer: Dictionary) -> bool:
	if String(offer["kind"]) == "recipe":
		return String(offer["state"]) == "ready"
	return String(offer["state"]) == "available"


func _make_chip_row(icon: Texture2D, text: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	if icon != null:
		var ic := TextureRect.new()
		ic.texture = icon
		ic.custom_minimum_size = Vector2(16, 16)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	if text != "":
		row.add_child(ShopArt.label(text, 12, color))
	return row


## «Было → станет»: значок, текущее значение, стрелка и новое.
func _make_compare_row(cmp: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var ic := TextureRect.new()
	ic.texture = cmp["icon"]
	ic.custom_minimum_size = Vector2(18, 18)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	row.add_child(ShopArt.label(String(cmp["from"]), 11, Color(0.7, 0.7, 0.76)))
	var arrow := TextureRect.new()
	arrow.texture = ShopArt.tex("glyph_arrow")
	arrow.custom_minimum_size = Vector2(14, 14)
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(arrow)
	row.add_child(ShopArt.label(String(cmp["to"]), 13, ShopArt.COL_GOOD))
	return row


func _make_price_row(offer: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	var cur := String(offer.get("currency", ""))
	var price := int(offer.get("price", 0))
	var ok := ShopItems.can_pay(cur, price)
	var ic := TextureRect.new()
	ic.texture = ShopItems.currency_icon(cur if cur != "" else ShopItems.COINS)
	ic.custom_minimum_size = Vector2(20, 20)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	row.add_child(ShopArt.label("0" if bool(offer.get("free", false)) else ShopArt.full(price), 15,
		Color.WHITE if ok else ShopArt.COL_BAD, INK, 4))
	return row


## Значок материала нажимается: тап — название и сколько есть. Строка не ниже
## 22 точек, чтобы попадал палец.
func _make_chip_tappable(row: Control, title: String, have: int, need: int) -> void:
	row.custom_minimum_size.y = 22.0
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	for c in row.get_children():
		if c is Label:
			(c as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var short := need - have
	Tip.bind_tap(row, title, "Есть: %s из %s" % [ShopArt.full(have), ShopArt.full(need)],
		"Не хватает: %s" % ShopArt.full(short) if short > 0 else "Хватает", _card_panel)


## Материалы рецепта значками: «есть/нужно», зелёное — хватает, красное — нет.
func _make_inputs_grid(offer: Dictionary) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	var wrap := CenterContainer.new()
	for inp in offer.get("inputs", []):
		var have := int(inp["have"])
		var need := int(inp["need"])
		var chip := _make_chip_row(inp["icon"], "%s/%s" % [ShopArt.compact(have), ShopArt.compact(need)],
			ShopArt.COL_GOOD if have >= need else ShopArt.COL_BAD)
		_make_chip_tappable(chip, ShopCatalog.item_name(String(inp["id"])), have, need)
		grid.add_child(chip)
	var coins_need := int(offer.get("coins_need", 0))
	if coins_need > 0:
		var have := int(offer.get("coins_have", 0))
		var coin_chip := _make_chip_row(ShopArt.ui("icon_coin"),
			"%s/%s" % [ShopArt.compact(have), ShopArt.compact(coins_need)],
			ShopArt.COL_GOOD if have >= coins_need or GameState.debug_free_shop else ShopArt.COL_BAD)
		_make_chip_tappable(coin_chip, "Монеты", have, coins_need)
		grid.add_child(coin_chip)
	wrap.add_child(grid)
	return wrap


func _confirm_card() -> void:
	if Tip.swallowed() or _card == null:
		return
	var offer := _card_offer
	var result := _perform(offer)
	if not bool(result.get("ok", false)):
		Sfx.play("ui_deny")
		Haptics.tap()
		if _card_ok != null:
			ShopFx.wiggle(_card_ok)
		notice(String(result.get("message", "Не получилось")))
		return
	_close_card(false)
	Sfx.play("ui_buy")
	Haptics.tap()
	if String(offer["kind"]) == "food":
		notice(String(result.get("message", "")), 3.0)
	if bool(result.get("ok", false)) and String(result.get("effect", "")) == "teleport_home":
		_teleport_home()
	_render()
	var t: ShopTile = _tiles.get(String(offer["key"]))
	if t != null:
		_after_snap(t, ShopArt.COL_GOLD if String(offer["kind"]) != "recipe" else ShopArt.COL_GOOD)


## Единая точка вызова торговой логики для всех видов плиток.
func _perform(offer: Dictionary) -> Dictionary:
	var ref := String(offer["ref"])
	match String(offer["kind"]):
		"tool":
			return ShopService.buy_tool(ref)
		"gear":
			return ShopService.buy_gear(ref)
		"drill":
			return ShopService.buy_drill_upgrade()
		"recipe":
			return ShopService.craft(ref)
		"food":
			return HouseSystem.order_food(ref)
		"good":
			return ShopService.buy(ref, String(offer["currency"]))
		"exchange":
			return ShopService.exchange_dollars_to_coins(1)
	return {"ok": false, "message": ""}


func _invest(offer: Dictionary) -> void:
	if Tip.swallowed():
		return
	var result := ShopService.invest(String(offer["ref"]))
	if not bool(result["ok"]):
		Sfx.play("ui_deny")
		notice(String(result["message"]))
		return
	Sfx.play("ui_tap")
	Haptics.tap()
	var key := String(offer["key"])
	_close_card(false)
	_render()
	var t: ShopTile = _tiles.get(key)
	if t != null:
		ShopFx.pop(t, 0.16, 0.26)
		t.pressed.emit()


## Часы-телепорт: единственный товар, который трогает не GameState, а героя.
func _teleport_home() -> void:
	_resolve_refs()
	if _player != null and is_instance_valid(_player) and _player.has_method("teleport_home"):
		_player.teleport_home()


# ---------------------------------------------------------------------------
# Ролики и продажа
# ---------------------------------------------------------------------------

func _claim_ad(offer: Dictionary, tile: ShopTile) -> void:
	if int(offer.get("left", 0)) <= 0:
		Sfx.play("ui_deny")
		tile.deny()
		return
	var r := ShopService.claim_ad(String(offer["ref"]))
	if not bool(r["ok"]):
		Sfx.play("ui_deny")
		tile.deny()
		notice(String(r["message"]))
		return
	Sfx.play("reward")
	Haptics.tap()
	_render()
	var t: ShopTile = _tiles.get(String(offer["key"]))
	if t != null:
		_after_snap(t, ShopArt.COL_GOLD)


func _on_ad_x2_pressed() -> void:
	if Tip.swallowed() or _busy:
		return
	var ad_id := ShopCatalog.ad_double_sale_id()
	if GameState.next_sale_doubled or ShopService.ad_uses_left(ad_id) <= 0:
		Sfx.play("ui_deny")
		ShopFx.wiggle(_ad_btn)
		return
	var r := ShopService.claim_ad(ad_id)
	if not bool(r["ok"]):
		Sfx.play("ui_deny")
		return
	Sfx.play("reward")
	Haptics.tap()
	_update_action_bar()
	ShopFx.pop(_sell_btn, 0.1, 0.3)
	ShopFx.sparkles(_root, _sell_btn.get_global_rect().get_center(), ShopArt.COL_GOLD, 12, 36.0)


func _all_sellable_items() -> Dictionary:
	var items: Dictionary = {}
	for row in ShopService.sellable_stacks():
		items[row["id"]] = row["count"]
	return items


func _selection_items() -> Dictionary:
	var items: Dictionary = {}
	for row in ShopService.sellable_stacks():
		if bool(_selected.get(row["id"], false)):
			items[row["id"]] = row["count"]
	return items


## Панель продажи: крупная кнопка с суммой (итог пересчитывается до нажатия,
## ГДД раздел 15) и значок ролика «×2».
func _update_action_bar() -> void:
	_action.visible = _tab == TAB_SELL
	_scroll.offset_bottom = -(NAV_H + (ACTION_H if _tab == TAB_SELL else 0.0))
	if _tab != TAB_SELL:
		return
	var remote := _footer_mode == "remote"
	var items := _all_sellable_items() if remote else _selection_items()
	var q := ShopService.quote(items)
	var coins := int(q["coins"])
	var doubled := GameState.next_sale_doubled and coins > 0
	_sell_label.text = ShopArt.full(coins * 2 if doubled else coins) if coins < 100000000 else ShopArt.compact(coins)
	_sell_x2.visible = doubled
	_sell_uses.visible = remote
	_sell_uses.text = "%d/%d" % [ShopService.ad_uses_left("remote_dump_loot_for_sale"),
		Balance.get_ad_daily_limit("remote_dump_loot_for_sale")]
	_sell_lead.texture = ShopArt.tex("item_ad_tv") if remote else ShopArt.ui("icon_inventory")
	var btn_disabled := coins <= 0
	if remote:
		btn_disabled = btn_disabled or ShopService.ad_uses_left("remote_dump_loot_for_sale") <= 0
	_sell_btn.disabled = btn_disabled
	var tip_title := "Сдать за ролик" if remote else "Продать"
	var tip_body := "Мастерская в подвале дома. Отсюда весь лут уходит за ролик (%d/%d сегодня)." % [
		ShopService.ad_uses_left("remote_dump_loot_for_sale"), Balance.get_ad_daily_limit("remote_dump_loot_for_sale")] \
		if remote else "Выбранное уходит в скупку. Тап по плитке — убрать из продажи."
	Tip.bind(_sell_btn, tip_title, tip_body, "Выручка: %s монет%s" % [ShopArt.full(coins * 2 if doubled else coins),
		" (×2 за ролик)" if doubled else ""])
	# ролик ×2: золотой — можно смотреть, зелёный — уже включён, серый — лимит
	var ad_id := ShopCatalog.ad_double_sale_id()
	var left := ShopService.ad_uses_left(ad_id)
	var kind := "gold" if left > 0 and not GameState.next_sale_doubled else \
			("green" if GameState.next_sale_doubled else "gray")
	var tex := ShopArt.tex("btn_" + kind)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var sbx := _ad_btn.get_theme_stylebox(st) as StyleBoxTexture
		if sbx != null:
			sbx.texture = tex
	_ad_label.text = str(left)
	_ad_label.visible = not GameState.next_sale_doubled
	Tip.bind(_ad_btn, "Удвоить выручку", "Ролик удвоит следующую продажу целиком.",
		"Включено" if GameState.next_sale_doubled else "Сегодня осталось: %d из %d" % [
			left, Balance.get_ad_daily_limit(ad_id)])


func _on_sell_pressed() -> void:
	if Tip.swallowed() or _busy:
		return
	if _footer_mode == "remote":
		_do_sell(true)
	else:
		_do_sell(false)


## Продажа с анимацией: плитки схлопываются, монеты разлетаются и летят в
## кошелёк, цифры в шапке накручиваются по мере долёта.
func _do_sell(remote: bool) -> void:
	var items := _all_sellable_items() if remote else _selection_items()
	var coins_before := GameState.coins
	var sold_tiles: Array = []
	for id in items.keys():
		var t: ShopTile = _tiles.get("sell:" + String(id))
		if t != null:
			sold_tiles.append(t)
	var result: Dictionary
	if remote:
		var r := ShopService.remote_dump_loot()
		result = {"ok": bool(r["ok"]), "coins": GameState.coins - coins_before, "doubled": false,
			"message": String(r["message"])}
	else:
		result = ShopService.sell(items)
	if not bool(result["ok"]):
		Sfx.play("ui_deny")
		Haptics.tap()
		ShopFx.wiggle(_sell_btn)
		if result.has("message"):
			notice(String(result["message"]))
		return
	_busy = true
	var gained := int(result["coins"])
	var doubled := bool(result.get("doubled", false))
	Sfx.play("sell")
	Haptics.tap()
	if gained >= 1000 or doubled:
		Sfx.play("coins_big")

	var coin_tex := ShopArt.ui("icon_coin")
	var wallet: Vector2 = (_chips["coins"]["icon"] as Control).get_global_rect().get_center()
	_wallet_hold = true
	_shown_coins = coins_before
	var per_tile := 3 if sold_tiles.size() <= 4 else 2
	var arrived := 0
	var total := mini(sold_tiles.size() * per_tile, 14)
	var n_total := maxi(total, 1)
	var on_arrive := func(_i: int) -> void:
		arrived += 1
		Sfx.play("coin", 1.0 + 0.04 * float(arrived % 6))
		var part := coins_before + int(round(float(gained) * float(arrived) / float(n_total)))
		(_chips["coins"]["label"] as Label).text = _chip_fmt(mini(part, coins_before + gained), "coins")
		ShopFx.pop(_chips["coins"]["root"], 0.1, 0.12)
	var spawned := 0
	for t in sold_tiles:
		var tile: ShopTile = t
		var c := tile.get_global_rect().get_center() - Vector2(0, 6)
		var k := mini(per_tile, total - spawned)
		if k > 0:
			ShopFx.coins(_root, coin_tex, c, wallet, k, on_arrive)
			spawned += k
		tile.pivot_offset = tile.size * 0.5
		var tw := tile.create_tween()
		tw.tween_interval(0.04 * float(sold_tiles.find(t)))
		tw.tween_property(tile, "scale", Vector2(1.12, 1.12), 0.08)
		tw.tween_property(tile, "scale", Vector2(0.0, 0.0), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if spawned == 0:
		on_arrive.call(0)
	if doubled:
		ShopFx.sparkles(_root, _sell_btn.get_global_rect().get_center(), ShopArt.COL_GOLD, 16, 44.0)
		ShopFx.pop(_sell_btn, 0.2, 0.4)

	# дождаться долёта последней монеты, потом перерисовать вкладку
	var wait := 0.04 * float(maxi(sold_tiles.size(), 1)) + 0.85 + 0.04 * float(per_tile)
	await get_tree().create_timer(wait).timeout
	_wallet_hold = false
	_busy = false
	_selected.clear()
	for row in ShopService.sellable_stacks():
		_selected[row["id"]] = true
	if is_open():
		_sync_wallet(false)
		_render()


# ---------------------------------------------------------------------------
# Реакции
# ---------------------------------------------------------------------------

## Игра попыталась надеть инструмент, которого у игрока нет. Объясняем, где он
## берётся, — иначе игрок видит, что «ничего не произошло». Ответ зависит от
## того, что это: кирку покупают, технику собирают.
func _on_tool_purchase_required(tool_id: String) -> void:
	var name_ru := Balance.get_tool_name_ru(tool_id)
	if Balance.tool_needs_materials(tool_id):
		notice("%s собирается на верстаке в мастерской, из материалов." % name_ru, 4.5)
	else:
		notice("%s продаётся в магазине у входной двери — %d монет." % [
			name_ru, Balance.get_tool_cost_coins(tool_id)], 4.5)

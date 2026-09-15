class_name ShopUI
extends CanvasLayer
## ShopUI — шторка мастерской: продажа сырья, верстак, лавка и магазин
## долларов (ГДД разделы 5, 7, 15).
##
## Лежит поверх игрового экрана отдельным слоем, как и весь остальной
## интерфейс (ГДД раздел 16): отдельных панелей вокруг экрана нет, на
## телефоне каждая такая панель съедает высоту, которой и так мало.
##
## Вся арифметика — в ShopService: здесь только показ и нажатия. Открыть
## магазин можно двумя способами, и оба нужны:
##   ShopUI.open_workshop()  — из комнаты мастерской (scripts/house/), одна строка;
##   кнопка в нижней полосе HUD — пока дома как сцены нет.
##
## Пока шторка открыта, герой заморожен, а ввод HUD выключен: джойстик лежит
## под шторкой на всю ширину экрана и иначе перехватывал бы нажатия у кнопок.

const TAB_SELL := "sell"
const TAB_CRAFT := "craft"
const TAB_SHOP := "shop"
const TAB_PREMIUM := "premium"

const GOLD := Color8(0xE0, 0xA9, 0x3B)
const GREEN := Color8(0x7F, 0xB8, 0x6B)
const DIM := Color8(0x9D, 0x8B, 0x73)
const BAD := Color8(0xB8, 0x5A, 0x52)

## Единственный живой экземпляр — чтобы дом мог открыть магазин одной
## строкой, не протаскивая ссылку через полдерева сцен.
static var instance: ShopUI = null

var _tab: String = TAB_SELL
## "sell" — обычная скупка дома, "remote" — дистанционная сдача за ролик.
var _footer_mode: String = "sell"
var _selected: Dictionary = {}   # mineral_id -> true, что отмечено к продаже

var _root: Control
var _title: Label
var _purse: Label
var _tab_buttons: Dictionary = {}
var _list: VBoxContainer
var _footer: HBoxContainer
var _footer_total: Label
var _footer_button: Button
var _notice_panel: Panel
var _notice_label: Label
var _notice_timer: Timer

var _player: Node = null
var _hud: Node = null

## Состояние мира до открытия шторки — чтобы вернуть его как было, а не
## "разморозить всё" (в доме и в катсценах герой заморожен не нами).
var _was_frozen: bool = false
var _hud_input_was_on: bool = true


# ---------------------------------------------------------------------------
# Точки входа
# ---------------------------------------------------------------------------

## Из комнаты мастерской (scripts/house/) — ровно одна строка на их стороне.
static func open_workshop() -> void:
	if instance == null:
		push_warning("ShopUI: магазин не подключён к сцене (см. scripts/main.gd)")
		return
	instance.open(TAB_SELL)


## Магазин долларов доступен всегда и везде (ГДД раздел 15).
static func open_premium() -> void:
	if instance == null:
		push_warning("ShopUI: магазин не подключён к сцене (см. scripts/main.gd)")
		return
	instance.open(TAB_PREMIUM)


func _ready() -> void:
	instance = self
	layer = 20  # выше HUD: шторка обязана перекрывать джойстик и нижнюю полосу
	_build()
	_root.visible = false
	GameState.tool_purchase_required.connect(_on_tool_purchase_required)
	GameState.coins_changed.connect(func(_c): _sync_purse())
	GameState.dollars_changed.connect(func(_d): _sync_purse())


func _exit_tree() -> void:
	if instance == self:
		instance = null


func is_open() -> bool:
	return _root != null and _root.visible


func open(tab: String = TAB_SELL) -> void:
	_resolve_refs()
	_freeze_world(true)
	_selected.clear()
	# По умолчанию отмечено всё: типовой сценарий — поднялся с полным рюкзаком
	# и сдал его целиком, а снимать галочки нужно в порядке исключения.
	for row in ShopService.sellable_stacks():
		_selected[row["id"]] = true
	_root.visible = true
	if tab != TAB_PREMIUM:
		# Первый спуск в мастерскую — та самая сцена с дедовой киркой среди
		# швабр и грабель (ГДД раздел 2).
		if ShopService.visit_workshop():
			notice("Среди швабр и грабель нашлась дедова кирка.", 4.0)
	_set_tab(tab)


func close() -> void:
	_root.visible = false
	_freeze_world(false)


func _resolve_refs() -> void:
	# Ссылки ищутся по имени, а не передаются из main.gd: подключение магазина
	# к сцене — одна строка, и протаскивать в неё героя с HUD незачем.
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().root.find_child("Player", true, false)
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().root.find_child("HUD", true, false)


## Пока шторка открыта, герой стоит (ГДД раздел 16: "пока шторка открыта,
## герой стоит"), а ввод HUD выключен — иначе джойстик, лежащий под шторкой,
## перехватывает нажатия раньше кнопок магазина.
func _freeze_world(frozen: bool) -> void:
	if _player != null and is_instance_valid(_player):
		if frozen:
			# Запоминаем, как было. Магазин открывается и из комнаты
			# мастерской, а внутри дома герой уже заморожен домом — снять
			# заморозку на закрытии значило бы отпустить его копать где-то
			# под домом, пока игрок смотрит на интерьер.
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


# ---------------------------------------------------------------------------
# Построение интерфейса
# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "ShopRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.071, 0.055, 0.043, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var head := HBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 8; head.offset_right = -8
	head.offset_top = 6; head.offset_bottom = 26
	_root.add_child(head)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 12)
	head.add_child(_title)

	_purse = Label.new()
	_purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_purse.add_theme_font_size_override("font_size", 10)
	_purse.add_theme_color_override("font_color", GOLD)
	head.add_child(_purse)

	var close_btn := Button.new()
	# Именно × (U+00D7), а не ✕: последнего в шрифте темы нет, и он рисуется
	# пустым квадратом — та же ловушка, что со стрелкой ↺ в нижней полосе HUD.
	close_btn.text = "×"
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.custom_minimum_size = Vector2(22, 20)
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var tabs := HBoxContainer.new()
	tabs.set_anchors_preset(Control.PRESET_TOP_WIDE)
	tabs.offset_left = 8; tabs.offset_right = -8
	tabs.offset_top = 28; tabs.offset_bottom = 46
	tabs.add_theme_constant_override("separation", 3)
	_root.add_child(tabs)
	_tab_buttons[TAB_SELL] = _make_tab(tabs, TAB_SELL, "Продать")
	_tab_buttons[TAB_CRAFT] = _make_tab(tabs, TAB_CRAFT, "Верстак")
	_tab_buttons[TAB_SHOP] = _make_tab(tabs, TAB_SHOP, "Лавка")
	_tab_buttons[TAB_PREMIUM] = _make_tab(tabs, TAB_PREMIUM, "$")

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8; scroll.offset_right = -8
	scroll.offset_top = 50; scroll.offset_bottom = -30
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)

	_footer = HBoxContainer.new()
	_footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.offset_left = 8; _footer.offset_right = -8
	_footer.offset_top = -26; _footer.offset_bottom = -4
	_root.add_child(_footer)

	_footer_total = Label.new()
	_footer_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_total.add_theme_font_size_override("font_size", 10)
	_footer_total.add_theme_color_override("font_color", GOLD)
	_footer.add_child(_footer_total)

	_footer_button = Button.new()
	_footer_button.add_theme_font_size_override("font_size", 10)
	_footer_button.pressed.connect(_on_footer_pressed)
	_footer.add_child(_footer_button)

	_build_notice()


## Сообщение магазина. Живёт ВНЕ шторки: о том, что бур теперь собирается на
## верстаке, игрок узнаёт на глубине 100, когда никакого магазина не открыто.
func _build_notice() -> void:
	_notice_panel = Panel.new()
	_notice_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_notice_panel.offset_left = 10; _notice_panel.offset_right = -10
	_notice_panel.offset_top = -76; _notice_panel.offset_bottom = -32
	_notice_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.035, 0.027, 0.94)
	sb.border_color = GOLD
	sb.set_border_width_all(1)
	sb.content_margin_left = 6; sb.content_margin_right = 6
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	_notice_panel.add_theme_stylebox_override("panel", sb)
	add_child(_notice_panel)

	_notice_label = Label.new()
	_notice_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_notice_label.offset_left = 6; _notice_label.offset_right = -6
	_notice_label.add_theme_font_size_override("font_size", 9)
	_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_panel.add_child(_notice_label)

	_notice_timer = Timer.new()
	_notice_timer.one_shot = true
	_notice_timer.timeout.connect(func(): _notice_panel.visible = false)
	add_child(_notice_timer)


func notice(text: String, seconds: float = 2.6) -> void:
	_notice_label.text = text
	_notice_panel.visible = true
	_notice_timer.start(seconds)


func _make_tab(parent: Control, id: String, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 9)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 18)
	b.toggle_mode = true
	b.pressed.connect(func(): _set_tab(id))
	parent.add_child(b)
	return b


## Строка-переключатель: выбранная подсвечивается золотой рамкой, невыбранная
## гаснет. Тема Godot по умолчанию различает состояния слишком слабо.
func _style_row_button(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.11, 0.09, 0.06, 1.0) if state == "pressed" else Color(0, 0, 0, 0)
		sb.border_color = GOLD if state == "pressed" else Color8(0x3E, 0x31, 0x25)
		sb.set_border_width_all(1)
		sb.content_margin_left = 2
		sb.content_margin_right = 2
		b.add_theme_stylebox_override(state, sb)


func _make_button(text: String, font_size: int = 9) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	return b


func _sync_purse() -> void:
	if _purse == null:
		return
	_purse.text = "%d монет · %d $" % [GameState.coins, GameState.dollars]


# ---------------------------------------------------------------------------
# Вкладки
# ---------------------------------------------------------------------------

func _set_tab(tab: String) -> void:
	_tab = tab
	for id in _tab_buttons.keys():
		_tab_buttons[id].button_pressed = (id == tab)
	match tab:
		TAB_SELL: _title.text = "Скупка сырья"
		TAB_CRAFT: _title.text = "Верстак"
		TAB_SHOP: _title.text = "Лавка"
		TAB_PREMIUM: _title.text = "Доллары"
	_render()


func _render() -> void:
	_sync_purse()
	for c in _list.get_children():
		c.queue_free()
	match _tab:
		TAB_SELL: _render_sell()
		TAB_CRAFT: _render_craft()
		TAB_SHOP: _render_shop()
		TAB_PREMIUM: _render_premium()


func _add_hint(text: String, color: Color = DIM) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(l)


# --- Продажа -----------------------------------------------------------------

func _render_sell() -> void:
	var rows := ShopService.sellable_stacks()
	_footer.visible = true
	# Скупка работает только дома. Иначе кнопка магазина превращается в
	# "продать со дна шахты", и подъём с грузом — то самое решение игрока,
	# ради которого монеты за копку и убраны, — перестаёт существовать.
	_footer_mode = "sell" if ShopService.is_at_workshop() else "remote"
	if _footer_mode == "remote":
		_add_hint("Мастерская в подвале дома — сюда лут надо донести. Отсюда можно только скинуть его на продажу дистанционно, за ролик (ГДД раздел 15, %d раза в день)."
			% Balance.get_ad_daily_limit("remote_dump_loot_for_sale"))
	if rows.is_empty():
		_add_hint("Продавать нечего. Мастерская принимает только руду и находки — земля и камень не добыча (ГДД раздел 4).")
		_footer_total.text = "0 монет"
		_footer_button.text = "Продать"
		_footer_button.disabled = true
		_show_unsellable_hint()
		return

	for row in rows:
		var r := _make_sell_row(row)
		# Вне дома строки показываем как прайс-лист: выбирать нечего, ролик
		# скидывает весь лут целиком.
		if _footer_mode == "remote":
			# Вне дома это прайс-лист, а не выбор: галочки убираем, чтобы не
			# обещать выбор, которого нет — ролик скидывает весь лут целиком.
			r.disabled = true
			r.button_pressed = false
		_list.add_child(r)
	_show_unsellable_hint()
	_update_sell_footer()


## Отдельной строкой — что мастерская НЕ покупает. Иначе игрок, принёсший
## бронзу, видит пустой список и решает, что продажа сломана.
func _show_unsellable_hint() -> void:
	var stuck: Array = []
	for id in GameState.inventory.keys():
		if int(GameState.inventory[id]) > 0 and ShopService.sell_price(String(id)) <= 0:
			stuck.append(ShopCatalog.item_name(String(id)))
	if stuck.is_empty():
		return
	_add_hint("Не скупается: " + ", ".join(stuck) + ". Это либо материал для брони, либо то, что мастерская сама и делает.")


func _make_sell_row(row: Dictionary) -> Button:
	var id := String(row["id"])
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = bool(_selected.get(id, false))
	b.custom_minimum_size = Vector2(0, 22)
	_style_row_button(b)
	var mark := Label.new()
	b.toggled.connect(func(on: bool):
		_selected[id] = on
		# Галочку рисуем сами: у кнопки темы по умолчанию нажатое состояние
		# отличается едва заметно, и на списке из пяти строк непонятно, что
		# именно уйдёт в продажу.
		mark.text = "v" if on else " "
		_update_sell_footer()
	)

	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 4; line.offset_right = -4
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(line)

	mark.text = "v" if b.button_pressed else " "
	mark.custom_minimum_size = Vector2(9, 0)
	mark.add_theme_font_size_override("font_size", 9)
	mark.add_theme_color_override("font_color", GOLD)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(mark)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := TileArt.texture_for(MineralMap.tile_type_for(id), 0, 0)
	if tex != null:
		icon.texture = tex
	line.add_child(icon)

	var name_label := Label.new()
	name_label.text = "%s ×%d" % [ShopCatalog.item_name(id), int(row["count"])]
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)

	var price_label := Label.new()
	price_label.text = "%d/шт" % int(row["price"])
	price_label.add_theme_font_size_override("font_size", 8)
	price_label.add_theme_color_override("font_color", DIM)
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(price_label)

	var sum_label := Label.new()
	sum_label.text = str(int(row["sum"]))
	sum_label.add_theme_font_size_override("font_size", 10)
	sum_label.add_theme_color_override("font_color", GOLD)
	sum_label.custom_minimum_size = Vector2(40, 0)
	sum_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sum_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(sum_label)
	return b


## Итог к продаже пересчитывается до подтверждения (ГДД раздел 15: "показ
## цен и итоговой суммы перед подтверждением").
func _update_sell_footer() -> void:
	var remote := _footer_mode == "remote"
	var items := _selection_items() if not remote else _all_sellable_items()
	var q := ShopService.quote(items)
	var coins := int(q["coins"])
	var text := "%d монет · %.0f кг" % [coins, float(q["weight"])]
	if GameState.next_sale_doubled and coins > 0:
		text = "%d монет (×2 по рекламе) · %.0f кг" % [coins * 2, float(q["weight"])]
	_footer_total.text = text
	if remote:
		var left := ShopService.ad_uses_left("remote_dump_loot_for_sale")
		_footer_button.text = "Ролик %d/%d" % [left, Balance.get_ad_daily_limit("remote_dump_loot_for_sale")]
		_footer_button.disabled = coins <= 0 or left <= 0
	else:
		_footer_button.text = "Продать"
		_footer_button.disabled = coins <= 0


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


func _do_sell() -> void:
	var result := ShopService.sell(_selection_items())
	if not bool(result["ok"]):
		notice("Нечего продавать.")
		return
	var text := "Продано %d шт: +%d монет, рюкзак легче на %.0f кг." % [
		int(result["count"]), int(result["coins"]), float(result["weight"])]
	if bool(result["doubled"]):
		text += " Реклама удвоила выручку."
	notice(text, 3.4)
	_selected.clear()
	_render()


# --- Верстак -----------------------------------------------------------------

func _render_craft() -> void:
	_footer.visible = false
	if not ShopService.is_at_workshop():
		_add_hint("Верстак стоит в подвале дома (ГДД раздел 5) — складывать и собирать можно только там. Отсюда видно только, чего ещё не хватает.", GOLD)
	_add_hint("Материалы копятся на складе в мастерской: железная кирка весит 160 кг при рюкзаке в 60, за одну ходку её не принести. Верстак берёт со склада и из рюкзака.")
	for r in ShopCatalog.recipes():
		_list.add_child(_make_craft_row(r))


func _make_craft_row(r: Dictionary) -> Control:
	var recipe_id := String(r["id"])
	var check := ShopService.check_craft(recipe_id)
	var project := ShopService.is_project(recipe_id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	var head := HBoxContainer.new()
	box.add_child(head)

	var title := Label.new()
	title.text = String(r["name_ru"])
	title.add_theme_font_size_override("font_size", 10)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	# «На склад» — та же кнопка, что раньше была «Вложить», но теперь это
	# тонкая обёртка над складом (ГДД п.14): переложить из рюкзака ровно то,
	# чего рецепту не хватает. Со склада это можно забрать обратно.
	if project and not bool(check["ok"]) and not bool(check["locked"]) and String(check["reason"]) != "Уже собрано":
		var invest_btn := _make_button("На склад")
		invest_btn.custom_minimum_size = Vector2(52, 18)
		invest_btn.pressed.connect(func(): _do_invest(recipe_id))
		head.add_child(invest_btn)

	var btn := _make_button("Собрать")
	btn.disabled = not bool(check["ok"])
	btn.custom_minimum_size = Vector2(48, 18)
	btn.pressed.connect(func(): _do_craft(recipe_id))
	head.add_child(btn)

	var desc := Label.new()
	desc.text = String(r["desc_ru"])
	desc.add_theme_font_size_override("font_size", 8)
	desc.add_theme_color_override("font_color", DIM)
	box.add_child(desc)

	var parts: Array = []
	for id in r["inputs"].keys():
		var want := int(r["inputs"][id])
		var have := ShopService.held_for(recipe_id, String(id))
		parts.append(_need_part("%s %d/%d" % [ShopCatalog.item_name(String(id)), have, want], have >= want))
	if int(r["coins"]) > 0:
		parts.append(_need_part("монет %d/%d" % [GameState.coins, int(r["coins"])],
			GameState.coins >= int(r["coins"])))
	box.add_child(_need_line("  ".join(parts)))

	if not bool(check["ok"]) and String(check["reason"]) != "Не хватает материалов":
		var reason := Label.new()
		reason.text = String(check["reason"])
		reason.add_theme_font_size_override("font_size", 8)
		reason.add_theme_color_override("font_color", GREEN if String(check["reason"]) == "Уже собрано" else DIM)
		box.add_child(reason)

	box.add_child(HSeparator.new())
	return box


func _do_invest(recipe_id: String) -> void:
	var result := ShopService.invest(recipe_id)
	notice(String(result["message"]), 3.0)
	_render()


## Список материалов рецепта — ОДНОЙ переносимой строкой, а не рядом меток:
## ряд из пяти-шести пунктов ("Железо 0/500  Бронза 0/100  ...") шире экрана
## в 224 точки, и вместе с ним за правый край уезжает вся строка рецепта
## вместе с кнопкой "Собрать".
func _need_line(bbcode: String) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.custom_minimum_size = Vector2(0, 10)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 8)
	rt.text = bbcode
	return rt


func _need_part(text: String, ok: bool) -> String:
	return "[color=#%s]%s[/color]" % [(GREEN if ok else BAD).to_html(false), text]


func _do_craft(recipe_id: String) -> void:
	var result := ShopService.craft(recipe_id)
	notice(String(result["message"]), 3.0)
	_render()


# --- Лавка и доллары ---------------------------------------------------------

func _render_shop() -> void:
	_footer.visible = false
	var goods := ShopCatalog.goods_coins()
	if goods.is_empty():
		_add_hint("Лавка пока пуста.")
	for g in goods:
		_list.add_child(_make_good_row(g, "coins"))

	_add_hint("Ролики (лимит на сегодня, ГДД раздел 15):")
	for a in ShopCatalog.ad_rewards():
		if String(a.get("id", "")) == "small_premium_currency":
			continue  # доллары — во вкладке долларов, чтобы не дублировать кнопку
		_list.add_child(_make_ad_row(a))


func _render_premium() -> void:
	_footer.visible = false
	_add_hint("Доллары в игре нельзя купить: платежей в этой сборке нет. Их дают ролики, клады и закрытые ветки коллекции.", DIM)
	for g in ShopCatalog.goods_dollars():
		_list.add_child(_make_good_row(g, "dollars"))

	_add_hint("Обмен (курс из data/balance.json, помечен как предложенный):")
	var ex := HBoxContainer.new()
	var ex_label := Label.new()
	ex_label.text = "1 $ = %d монет" % ShopCatalog.coins_per_dollar()
	ex_label.add_theme_font_size_override("font_size", 9)
	ex_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ex.add_child(ex_label)
	var ex_btn := _make_button("Обменять")
	ex_btn.disabled = GameState.dollars < 1
	ex_btn.pressed.connect(func():
		var r := ShopService.exchange_dollars_to_coins(1)
		notice(String(r["message"]))
		_render()
	)
	ex.add_child(ex_btn)
	_list.add_child(ex)

	var ad := ShopCatalog.ad_reward("small_premium_currency")
	if not ad.is_empty():
		_list.add_child(_make_ad_row(ad))


func _make_good_row(g: Dictionary, currency: String) -> Control:
	var price := ShopCatalog.good_price(g, currency)
	var box := HBoxContainer.new()

	var text := Label.new()
	text.text = "%s — %s" % [String(g.get("name_ru", "")), String(g.get("desc_ru", ""))]
	text.add_theme_font_size_override("font_size", 9)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(text)

	var btn := _make_button("%d %s" % [price, "монет" if currency == "coins" else "$"])
	btn.disabled = (GameState.coins < price) if currency == "coins" else (GameState.dollars < price)
	btn.pressed.connect(func(): _do_buy(String(g.get("id", "")), currency))
	box.add_child(btn)
	return box


func _do_buy(good_id: String, currency: String) -> void:
	var result := ShopService.buy(good_id, currency)
	notice(String(result["message"]), 3.0)
	if bool(result["ok"]) and String(result["effect"]) == "teleport_home":
		_teleport_home()
	_render()


## Часы-телепорт: единственный товар, который трогает не GameState, а героя.
func _teleport_home() -> void:
	_resolve_refs()
	if _player != null and is_instance_valid(_player) and _player.has_method("teleport_home"):
		_player.teleport_home()


func _make_ad_row(a: Dictionary) -> Control:
	var ad_id := String(a.get("id", ""))
	var left := ShopService.ad_uses_left(ad_id)
	var box := HBoxContainer.new()

	var text := Label.new()
	text.text = String(a.get("name_ru", ad_id))
	text.add_theme_font_size_override("font_size", 9)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(text)

	var btn := _make_button("Ролик %d/%d" % [left, Balance.get_ad_daily_limit(ad_id)])
	btn.disabled = left <= 0
	btn.pressed.connect(func():
		var r := ShopService.claim_ad(ad_id)
		notice(String(r["message"]), 3.0)
		_render()
	)
	box.add_child(btn)
	return box


# ---------------------------------------------------------------------------
# Реакции
# ---------------------------------------------------------------------------

func _on_footer_pressed() -> void:
	if _tab != TAB_SELL:
		return
	if _footer_mode == "remote":
		var r := ShopService.remote_dump_loot()
		notice(String(r["message"]), 3.4)
		_render()
	else:
		_do_sell()


## Игра попыталась надеть инструмент, которого у игрока нет (например, бур на
## глубине 100). Объясняем, где он теперь берётся, — иначе игрок видит, что
## "ничего не произошло".
func _on_tool_purchase_required(tool_id: String) -> void:
	notice("%s не выдаётся по глубине — его собирают на верстаке в мастерской." %
		Balance.get_tool_name_ru(tool_id), 4.5)

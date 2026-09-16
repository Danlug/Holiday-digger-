extends CanvasLayer
## HouseView — интерьер дома (сцена scenes/house.tscn).
##
## Дом показан РАЗРЕЗОМ: второй этаж, первый этаж, подвал — сверху вниз одной
## колонкой комнат. Ходьбы внутри дома нет намеренно: физика героя живёт в
## мире-сетке (scripts/player), и пускать его ходить по интерьеру значило бы
## заводить вторую, отдельную физику ради трёх дверей. Вместо этого герой
## «переезжает» в комнату, по которой ткнули, — место в доме остаётся
## читаемым, а действий ровно столько, сколько их есть.
##
## Структура узлов строится кодом (_ensure_structure) и ровно этим же кодом
## сгенерирована сама сцена: так файл сцены можно открыть и доработать в
## редакторе, но потеря или порча сцены не ломает дом — узлы создадутся
## заново при загрузке.
##
## Все действия уходят наружу сигналом action_requested: сама по себе панель
## ничего не меняет в состоянии игры. Логика сна/еды/переходов — в
## scripts/house/house_system.gd и house_sleep/house_food.

signal action_requested(action: String, arg: String)

const BG := Color8(0x14, 0x0F, 0x0B)
const PANEL_BG := Color8(0x1E, 0x18, 0x11)
const PANEL_BORDER := Color8(0x3E, 0x31, 0x25)
const ACCENT := Color8(0xE0, 0xA9, 0x3B)
const DIM := Color8(0x9D, 0x8B, 0x73)
const FLOOR_LABEL := Color8(0x6B, 0x5B, 0x45)

## Комнаты дома (ГДД п.2, 9, 10): спальня наверху, прихожая с входной дверью
## и музей на первом этаже, мастерская, торфоперегонка и ход к тоннелю
## Роберта — в подвале.
## Мастерская и музей заведены пустыми: их наполняют другие системы, дому
## достаточно, чтобы туда можно было войти.
const ROOMS := [
	{"id": "bedroom", "floor": "Второй этаж", "title": "Спальня",
		"icon": "res://art/env/bed.png",
		"desc": "Кровать. Сон восстанавливает бодрость — 12.5% за игровой час."},
	{"id": "hall", "floor": "Первый этаж", "title": "Прихожая",
		"icon": "res://art/env/house_exterior.png",
		"desc": "Входная дверь. Сюда привозят заказанную еду."},
	{"id": "museum", "floor": "Первый этаж", "title": "Музей",
		"icon": "res://art/ui/slot_frame.png",
		"desc": "Витрины под коллекцию артефактов (ГДД п.10)."},
	{"id": "workshop", "floor": "Подвал", "title": "Мастерская",
		"icon": "res://art/env/workbench.png",
		"desc": "Верстак деда, лавка и склад: сюда носят материалы на кирку (ГДД п.2, 14, 15)."},
	{"id": "peat_still", "floor": "Подвал", "title": "Торфоперегонка",
		"icon": "res://art/ui/slot_frame.png",
		"desc": "Торф → топливные блоки и удобрение (ГДД п.5)."},
	{"id": "basement", "floor": "Подвал", "title": "Ход в шахту",
		"icon": "res://art/env/hatch.png",
		"desc": "Ход из подвала к устью тоннеля Роберта — другого входа в копальню нет."},
]

# Комнаты, которые наполняют другие системы. Ключ — id комнаты, значение —
# группа узла, который туда встраивается. Контракт для соседних систем:
# добавить свой узел в группу и реализовать метод open() — дом сам покажет
# кнопку «Открыть» вместо надписи «пока пусто».
const EXTERNAL_PANELS := {
	"workshop": "house_workshop_panel",
	"museum": "house_museum_panel",
	"peat_still": "house_peat_still_panel",
}

# Уже существующие соседние системы, у которых есть статическая точка входа.
# Загружаются ПО ПУТИ, а не через глобальное имя класса: если соседнюю
# систему выкинут или она не соберётся, дом обязан остаться рабочим — еда и
# сон не должны зависеть от того, доехал ли магазин.
const EXTERNAL_STATIC := {
	"workshop": {"path": "res://scripts/shop/shop_ui.gd", "method": "open_workshop", "arg": null},
	"museum": {"path": "res://scripts/progress/progress_screen.gd", "method": "open", "arg": "museum"},
}

var _root: Control
var _title: Label
var _clock: Label
var _bars: Dictionary = {}       # "hp"|"hunger"|"stamina" -> ColorRect (заливка)
var _rooms_box: VBoxContainer
var _cards: Dictionary = {}      # room_id -> PanelContainer
var _forced: Control
var _forced_text: Label
var _forced_button: Button

var _menu_open: bool = false
var _forced_mode: String = ""    # "" | "sleep"
var _hero_tex: Texture2D
var _notice: Label
var _notice_until_msec: float = 0.0
# Слепок содержимого прихожей: список блюд и рюкзак пересобираются только
# когда что-то изменилось. Пересборка каждый кадр убивала бы нажатие —
# кнопка исчезала бы раньше, чем палец успевал отпустить её.
var _hall_signature: String = ""


func _ready() -> void:
	# Выше HUD (его слой 1), но НИЖЕ экранов соседних систем (магазин 20,
	# экран героя 10): их окна открываются из комнат дома и обязаны лечь
	# поверх интерьера, а не под него.
	layer = 9
	_ensure_structure()
	_wire_actions()
	visible = false


# ---------------------------------------------------------------------------
# Сборка интерьера
# ---------------------------------------------------------------------------

## Создаёт недостающие узлы. Вызывается и при загрузке сцены (где всё уже
## есть — тогда функция только находит узлы), и генератором сцены.
func _ensure_structure() -> void:
	_root = _need(self, "Root", Control)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := _need(_root, "Backdrop", ColorRect) as ColorRect
	backdrop.color = BG
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_header()
	_build_rooms()
	_build_forced()


func _build_header() -> void:
	var header := _need(_root, "Header", Panel) as Panel
	header.anchor_right = 1.0
	header.offset_bottom = 52
	header.add_theme_stylebox_override("panel", _box(PANEL_BG, PANEL_BORDER))

	_title = _need(header, "Title", Label) as Label
	_title.position = Vector2(8, 3)
	_title.add_theme_font_size_override("font_size", 12)
	_title.add_theme_color_override("font_color", ACCENT)
	_title.text = "ДОМ"

	_clock = _need(header, "Clock", Label) as Label
	_clock.anchor_left = 1.0
	_clock.anchor_right = 1.0
	_clock.offset_left = -112
	_clock.offset_right = -8
	_clock.offset_top = 5
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.add_theme_font_size_override("font_size", 9)
	_clock.add_theme_color_override("font_color", DIM)

	# Полоски выживания дублируются здесь, потому что HUD на время дома
	# скрывается: иначе его джойстик и нижняя полоса торчали бы поверх
	# интерьера. А смотреть, как поднимается бодрость, игрок должен именно
	# в тот момент, когда он на неё и жмёт.
	var bars := _need(header, "Bars", HBoxContainer) as HBoxContainer
	bars.position = Vector2(8, 24)
	bars.add_theme_constant_override("separation", 6)
	_bars["hp"] = _bar_row(bars, "Hp", Color8(0xB8, 0x5A, 0x52), "res://art/ui/icon_hp.png")
	_bars["hunger"] = _bar_row(bars, "Hunger", Color8(0xC4, 0x70, 0x6A), "res://art/ui/icon_hunger.png")
	_bars["stamina"] = _bar_row(bars, "Stamina", Color8(0x6E, 0x93, 0xA8), "res://art/ui/icon_stamina.png")

	# Своя строка сообщений: HUD с его тостами на время дома скрыт, а «заказ
	# принят» и «проспал 8 часов» игрок обязан прочитать именно в доме.
	_notice = _need(header, "Notice", Label) as Label
	_notice.anchor_right = 1.0
	_notice.offset_left = 8
	_notice.offset_right = -8
	_notice.offset_top = 38
	_notice.add_theme_font_size_override("font_size", 8)
	_notice.add_theme_color_override("font_color", ACCENT)
	_notice.clip_text = true


func _bar_row(parent: Control, name: String, color: Color, icon_path: String) -> ColorRect:
	var row := _need(parent, name, HBoxContainer) as HBoxContainer
	row.add_theme_constant_override("separation", 3)
	if ResourceLoader.exists(icon_path):
		var icon := _need(row, "Icon", TextureRect) as TextureRect
		icon.custom_minimum_size = Vector2(11, 11)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(icon_path)
	var track := _need(row, "Track", Panel) as Panel
	track.custom_minimum_size = Vector2(48, 7)
	track.add_theme_stylebox_override("panel", _box(Color(0.043, 0.035, 0.027, 0.85), Color(0, 0, 0, 0.55)))
	var fill := _need(track, "Fill", ColorRect) as ColorRect
	fill.color = color
	fill.position = Vector2(1, 1)
	fill.size = Vector2(46, 5)
	return fill


func _build_rooms() -> void:
	var scroll := _need(_root, "Scroll", ScrollContainer) as ScrollContainer
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 56
	scroll.offset_left = 6
	scroll.offset_right = -6
	scroll.offset_bottom = -6
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Прокрутка перетаскиванием списка, а не только ползунком (решение
	# владельца). _need переиспользует узел, поэтому вешаем один раз.
	if scroll.get_node_or_null("DragScroll") == null:
		DragScroll.attach(scroll)

	_rooms_box = _need(scroll, "Rooms", VBoxContainer) as VBoxContainer
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_box.add_theme_constant_override("separation", 5)

	var last_floor := ""
	for room in ROOMS:
		if String(room["floor"]) != last_floor:
			last_floor = String(room["floor"])
			var floor_label := _need(_rooms_box, "Floor_" + String(room["id"]), Label) as Label
			floor_label.text = last_floor.to_upper()
			floor_label.add_theme_font_size_override("font_size", 8)
			floor_label.add_theme_color_override("font_color", FLOOR_LABEL)
		_build_card(room)


func _build_card(room: Dictionary) -> void:
	var id := String(room["id"])
	var card := _need(_rooms_box, id.capitalize().replace(" ", ""), PanelContainer) as PanelContainer
	card.add_theme_stylebox_override("panel", _box(PANEL_BG, PANEL_BORDER))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_cards[id] = card

	var box := _need(card, "Box", VBoxContainer) as VBoxContainer
	box.add_theme_constant_override("separation", 2)

	var head := _need(box, "Head", HBoxContainer) as HBoxContainer
	head.add_theme_constant_override("separation", 5)

	var icon := _need(head, "Icon", TextureRect) as TextureRect
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(String(room["icon"])):
		icon.texture = load(String(room["icon"]))

	var title := _need(head, "Title", Label) as Label
	title.text = String(room["title"])
	title.add_theme_font_size_override("font_size", 11)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Герой стоит в той комнате, где он сейчас: без него дом читается как
	# меню, а не как место.
	var hero := _need(head, "Hero", TextureRect) as TextureRect
	hero.custom_minimum_size = Vector2(24, 24)
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.visible = false

	var desc := _need(box, "Desc", Label) as Label
	desc.text = String(room["desc"])
	desc.custom_minimum_size = Vector2(80, 0)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_font_size_override("font_size", 8)
	desc.add_theme_color_override("font_color", DIM)

	# Место под содержимое комнаты для соседних систем (мастерская, музей,
	# торфоперегонка). Пустой контейнер — это и есть «явное место»: чужой
	# узел кладётся сюда, и дом его не трогает.
	var slot := _need(box, "Slot", VBoxContainer) as VBoxContainer
	slot.add_theme_constant_override("separation", 2)

	# Ряд действий переносится на вторую строку: три кнопки в строку шире
	# экрана (224 точки), а ScrollContainer по горизонтали намеренно не
	# крутится — карточку комнаты игрок должен видеть целиком.
	var actions := _need(box, "Actions", HFlowContainer) as HFlowContainer
	actions.add_theme_constant_override("h_separation", 4)
	actions.add_theme_constant_override("v_separation", 3)

	var note := _need(box, "Note", Label) as Label
	note.custom_minimum_size = Vector2(80, 0)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_font_size_override("font_size", 8)
	note.add_theme_color_override("font_color", FLOOR_LABEL)
	note.visible = false


func _build_forced() -> void:
	# Экран принудительного действия обучения (ГДД п.9): первое истощение
	# ведёт героя в спальню и не отпускает, пока он не ляжет.
	_forced = _need(_root, "Forced", Control) as Control
	_forced.set_anchors_preset(Control.PRESET_FULL_RECT)
	_forced.mouse_filter = Control.MOUSE_FILTER_STOP
	_forced.visible = false

	var shade := _need(_forced, "Shade", ColorRect) as ColorRect
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.02, 0.02, 0.88)

	var panel := _need(_forced, "Panel", PanelContainer) as PanelContainer
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.anchor_right = 1.0
	panel.offset_left = 14
	panel.offset_right = -14
	panel.offset_top = -70
	panel.offset_bottom = 70
	panel.add_theme_stylebox_override("panel", _box(PANEL_BG, ACCENT))

	var box := _need(panel, "Box", VBoxContainer) as VBoxContainer
	box.add_theme_constant_override("separation", 8)

	_forced_text = _need(box, "Text", Label) as Label
	_forced_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_forced_text.add_theme_font_size_override("font_size", 10)
	_forced_text.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_forced_button = _need(box, "Button", Button) as Button
	_style_button(_forced_button)
	_forced_button.text = "Лечь спать"


# ---------------------------------------------------------------------------
# Действия
# ---------------------------------------------------------------------------

func _wire_actions() -> void:
	_hero_tex = load("res://art/character/idle.png") if ResourceLoader.exists("res://art/character/idle.png") else null

	for room in ROOMS:
		var id := String(room["id"])
		var card: PanelContainer = _cards[id]
		# Тап по самой карточке переводит героя в эту комнату: комната без
		# действий (пустой музей) всё равно должна быть местом, куда можно
		# войти — этого требует задание и это нужно соседним системам.
		card.gui_input.connect(func(event: InputEvent): _on_card_input(event, id))

	_add_button("bedroom", "Спать", "sleep")
	_add_button("hall", "Заказать", "toggle_menu")
	_add_button("hall", "Забрать", "take_delivery")
	_add_button("hall", "На улицу", "exit_door")
	_add_button("basement", "В шахту", "exit_tunnel")
	_add_button("workshop", "Склад", "storage")
	for room_id in EXTERNAL_PANELS.keys():
		_add_button(String(room_id), "Открыть", "open_panel:" + String(room_id))

	if _forced_button != null:
		_forced_button.pressed.connect(func(): action_requested.emit("forced_confirm", _forced_mode))


func _on_card_input(event: InputEvent, room_id: String) -> void:
	var pressed := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if pressed:
		action_requested.emit("goto", room_id)


func _add_button(room_id: String, text: String, action: String) -> Button:
	var actions := _cards[room_id].get_node("Box/Actions") as HFlowContainer
	var name := action.replace(":", "_").capitalize().replace(" ", "") + "Btn"
	var b := _need(actions, name, Button) as Button
	b.text = text
	_style_button(b)
	b.pressed.connect(func(): _emit_action(action))
	return b


func _emit_action(action: String) -> void:
	var parts := action.split(":", true, 1)
	if action == "toggle_menu":
		_menu_open = not _menu_open
		_hall_signature = ""
		refresh()
		return
	if parts.size() == 2:
		action_requested.emit(parts[0], parts[1])
	else:
		action_requested.emit(action, "")


# ---------------------------------------------------------------------------
# Открытие/закрытие и обновление
# ---------------------------------------------------------------------------

func open(room: String) -> void:
	_menu_open = false
	_hall_signature = ""
	visible = true
	go_to_room(room)


func close() -> void:
	visible = false
	_menu_open = false


func go_to_room(room: String) -> void:
	for id in _cards.keys():
		var hero := _cards[id].get_node("Box/Head/Hero") as TextureRect
		hero.visible = (id == room)
		if hero.visible and _hero_tex != null:
			# idle.png — горизонтальная лента кадров 48×48; берём первый кадр.
			var atlas := AtlasTexture.new()
			atlas.atlas = _hero_tex
			atlas.region = Rect2(0, 0, 48, 48)
			hero.texture = atlas
	refresh()


## Сообщение в шапке дома (замена тостов HUD, который на время дома скрыт).
func notify(text: String, seconds: float = 3.0) -> void:
	if _notice == null:
		return
	_notice.text = text
	_notice_until_msec = Time.get_ticks_msec() + seconds * 1000.0


func forced_mode() -> String:
	return _forced_mode


## Принудительный режим обучения: mode="" — обычный дом, mode="sleep" —
## экран поверх интерьера, который отпускает только после сна.
func set_forced(mode: String, text: String = "", button_text: String = "") -> void:
	_forced_mode = mode
	_forced.visible = mode != ""
	if mode != "":
		_forced_text.text = text
		_forced_button.text = button_text


## Перерисовывает подписи и доступность кнопок по текущему состоянию.
## Вызывается системой дома каждый кадр, пока интерьер открыт: полоски
## поднимаются и доставка приезжает в реальном времени.
func refresh() -> void:
	if not visible:
		return
	_refresh_bars()
	_refresh_clock()
	_refresh_bedroom()
	_refresh_hall()
	_refresh_basement()
	_refresh_external_rooms()
	_refresh_storage()
	if _notice != null and Time.get_ticks_msec() > _notice_until_msec:
		_notice.text = ""


func _refresh_bars() -> void:
	_set_bar("hp", GameState.hp / maxf(1.0, GameState.get_max_hp()))
	_set_bar("hunger", GameState.hunger / 100.0)
	_set_bar("stamina", GameState.stamina / 100.0)


func _set_bar(id: String, fraction: float) -> void:
	var fill: ColorRect = _bars.get(id)
	if fill != null:
		fill.size = Vector2(46.0 * clampf(fraction, 0.0, 1.0), 5)


func _refresh_clock() -> void:
	var total: float = GameState.game_clock_hours
	var day := int(total / 24.0) + 1
	var hour := int(total) % 24
	var minute := int((total - floor(total)) * 60.0)
	_clock.text = "День %d, %02d:%02d" % [day, hour, minute]


func _refresh_bedroom() -> void:
	var plan := HouseSleep.plan(GameState.stamina, GameState.hunger)
	var button := _button("bedroom", "sleep")
	button.disabled = not bool(plan["ok"])
	button.text = "Спать %d ч" % int(round(float(plan["hours"])))
	var note := _note("bedroom")
	if bool(plan["ok"]):
		note.text = "+%d%% бодрости, −%d%% сытости" % [
			int(round(float(plan["stamina_gain"]))), int(round(float(plan["hunger_cost"])))]
	else:
		note.text = String(plan["reason"])
	note.visible = true


func _refresh_hall() -> void:
	var at_door := HouseFood.food_at_door_count()
	var take := _button("hall", "take_delivery")
	take.disabled = at_door <= 0
	take.text = "Забрать (%d)" % at_door if at_door > 0 else "Забрать"

	var menu_button := _button("hall", "toggle_menu")
	menu_button.text = "Закрыть" if _menu_open else "Заказать"

	var signature := "%s|%d|%d|%d|%s" % [_menu_open, at_door, HouseFood.free_orders_left(),
		GameState.coins, str(HouseFood.food_in_inventory())]
	if signature == _hall_signature:
		return
	_hall_signature = signature

	var slot := _cards["hall"].get_node("Box/Slot") as VBoxContainer
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()

	if _menu_open:
		var left := HouseFood.free_orders_left()
		var head := _slot_label(slot, "Доставка к двери за %d сек. Бесплатных заказов сегодня: %d."
			% [int(HouseConfig.delivery_seconds()), left])
		head.add_theme_color_override("font_color", ACCENT)
		for item in HouseConfig.delivery_menu():
			var id := String(item["id"])
			var check := HouseFood.can_order(id)
			var row := HBoxContainer.new()
			slot.add_child(row)
			var label := Label.new()
			label.text = "%s +%d%%" % [HouseConfig.food_name(id), int(HouseConfig.food_hunger_percent(id))]
			label.add_theme_font_size_override("font_size", 9)
			label.clip_text = true
			label.custom_minimum_size = Vector2(70, 0)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var order := Button.new()
			_style_button(order)
			order.text = "бесплатно" if bool(check["free"]) else "%d монет" % HouseConfig.food_price_coins(id)
			order.disabled = not bool(check["ok"])
			order.pressed.connect(func(): action_requested.emit("order", id))
			row.add_child(order)

	# Еда, которую уже носит герой: съесть можно прямо здесь, не открывая
	# инвентарь — в доме это самое частое действие после сна.
	for entry in HouseFood.food_in_inventory():
		var row2 := HBoxContainer.new()
		slot.add_child(row2)
		var label2 := Label.new()
		label2.text = "В рюкзаке: %s ×%d" % [entry["name"], entry["count"]]
		label2.add_theme_font_size_override("font_size", 9)
		label2.clip_text = true
		label2.custom_minimum_size = Vector2(70, 0)
		label2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(label2)
		var eat := Button.new()
		_style_button(eat)
		eat.text = "Съесть"
		var food_id: String = entry["id"]
		eat.pressed.connect(func(): action_requested.emit("eat", food_id))
		row2.add_child(eat)


func _slot_label(slot: VBoxContainer, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 8)
	slot.add_child(l)
	return l


func _refresh_basement() -> void:
	var button := _button("basement", "exit_tunnel")
	# Флаг остался с прежним именем (house_hatch_built), но значит он теперь
	# одно: Роберт пробил тоннель. Переименование поля — за scripts/core.
	button.disabled = not GameState.house_hatch_built
	var note := _note("basement")
	note.visible = true
	if GameState.house_hatch_built:
		var mouth := HouseConfig.tunnel_mouth_cell()
		note.text = "Ход выводит в устье тоннеля — клетка (%d, %d). Вниз только по колодцу: стенки бетонные." % [mouth.x, mouth.y]
	else:
		note.text = "Тоннеля ещё нет: его пробьёт Роберт, которого пришлёт бабка (ГДД п.9)."


## Строка склада в мастерской: сколько там лежит и сколько это весит. Вес
## важнее числа позиций — по нему видно, сколько ходок в эту кучу вложено.
func _refresh_storage() -> void:
	var note := _note("workshop")
	note.visible = true
	var items := HouseStorage.total_items()
	if items <= 0:
		note.text = "Склад пуст. Материалы на кирку копятся здесь: 160 кг за один рюкзак не принести."
	else:
		note.text = "На складе: %d шт, %.0f кг. Верстак берёт материалы отсюда." % [
			items, HouseStorage.total_weight()]


func _refresh_external_rooms() -> void:
	for room_id in EXTERNAL_PANELS.keys():
		var id := String(room_id)
		var button := _button(id, "open_panel:" + id)
		var available := has_external_panel(id)
		button.visible = available
		if id == "workshop":
			continue  # у мастерской своя подпись — про склад, см. _refresh_storage
		var note := _note(id)
		note.visible = not available
		note.text = "Комната есть, содержимого пока нет — место под систему, которая её наполнит."


## Есть ли кому открыть эту комнату: либо чужой узел в группе (контракт
## EXTERNAL_PANELS), либо статическая точка входа соседней системы.
func has_external_panel(room_id: String) -> bool:
	var group := String(EXTERNAL_PANELS.get(room_id, ""))
	if not group.is_empty():
		var node := get_tree().get_first_node_in_group(group)
		if node != null and node.has_method("open"):
			return true
	return _external_static_script(room_id) != null


func _external_static_script(room_id: String):
	var entry: Dictionary = EXTERNAL_STATIC.get(room_id, {})
	if entry.is_empty():
		return null
	var path := String(entry["path"])
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## Открывает комнату, которую наполняет соседняя система. Возвращает false,
## если открывать пока нечего — тогда дом сам скажет, что комната пустая.
func open_external_panel(room_id: String) -> bool:
	var group := String(EXTERNAL_PANELS.get(room_id, ""))
	if not group.is_empty():
		var node := get_tree().get_first_node_in_group(group)
		if node != null and node.has_method("open"):
			node.call("open")
			return true
	var script = _external_static_script(room_id)
	if script == null:
		return false
	var entry: Dictionary = EXTERNAL_STATIC[room_id]
	var method := String(entry["method"])
	if entry["arg"] == null:
		script.call(method)
	else:
		script.call(method, entry["arg"])
	return true


func _button(room_id: String, action: String) -> Button:
	var name := action.replace(":", "_").capitalize().replace(" ", "") + "Btn"
	return _cards[room_id].get_node("Box/Actions/" + name) as Button


func _note(room_id: String) -> Label:
	return _cards[room_id].get_node("Box/Note") as Label


# ---------------------------------------------------------------------------
# Мелочи сборки
# ---------------------------------------------------------------------------

## Находит дочерний узел по имени или создаёт его. Благодаря этому один и тот
## же код и строит сцену с нуля, и подхватывает готовую из .tscn.
func _need(parent: Node, name: String, type) -> Node:
	var existing := parent.get_node_or_null(NodePath(name))
	if existing != null:
		return existing
	var node = type.new()
	node.name = name
	parent.add_child(node)
	return node


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _style_button(b: Button) -> void:
	b.add_theme_font_size_override("font_size", 9)
	b.custom_minimum_size = Vector2(0, 22)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = PANEL_BORDER if state != "pressed" else ACCENT
		sb.set_border_width_all(1)
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", FLOOR_LABEL)

extends Control
## HUD — весь интерфейс поверх игрового экрана (см. задание п.9): полоски
## HP/голод/усталость слева сверху, кошелёк справа сверху, глубина справа на
## уровне героя, нижняя однострочная полоса (инвентарь/инструмент/снаряжение/
## режим/сброс), шторка инвентаря, джойстик и подсказка режима удержания —
## обе ПОВЕРХ игрового экрана, а не отдельной панелью (портировано из
## web/index.html).

const TILE := 32
const STRIP_H := 40.0
# Джойстик задаётся долей ширины экрана, а не пикселями из web-демо: там
# интерфейс живёт в пикселях устройства (118px на экране в 390), а здесь — в
# проектных единицах вьюпорта (224 в ширину), и те же 118 занимали половину
# экрана. 15% полуширины дают ту же долю экрана, что и в демо.
const STICK_FRACTION := 0.15
const STICK_R_MIN := 30.0

# Порог «редкой находки» для отдельного тоста и сколько раз его вообще
# показывать за игру (решение владельца: 5-10, взято 6 — дальше это уже не
# событие). Цена в монетах в самом тосте не пишется: монет за копку не дают.
const RARE_FIND_COINS := 100
const RARE_FIND_TOAST_LIMIT := 6
var stick_r := 34.0
var knob_r := 13.0
const STICK_DEAD := 0.26

var player: Node = null      # Player, назначает main.gd

# --- режим управления ---
var mode: String = "stick"   # "stick" | "hold"

# --- джойстик: активный указатель (-1 = нет) ---
var _stick_pointer: int = -100
var _stick_center: Vector2 = Vector2.ZERO

# --- удержание пальца на экране ---
var _touch_pointer: int = -100
var _touch_pos: Vector2 = Vector2.ZERO
var _has_touch: bool = false

# --- клавиатура ---
## WASD и стрелки работают в обоих режимах управления и имеют приоритет над
## пальцем: кто держит клавишу, тот и ведёт героя. Нужны и для игры на
## компьютере, и для отладки — мышью не покажешь «влево и вверх одновременно».
const KEYS_LEFT: Array[Key] = [KEY_A, KEY_LEFT]
const KEYS_RIGHT: Array[Key] = [KEY_D, KEY_RIGHT]
const KEYS_UP: Array[Key] = [KEY_W, KEY_UP]
const KEYS_DOWN: Array[Key] = [KEY_S, KEY_DOWN]
var _keyboard_active: bool = false

var stage_rect: Rect2 = Rect2()
var current_cam: Vector2 = Vector2.ZERO  # выставляет main.gd каждый кадр (см. camera() в web-демо)

# --- узлы ---
var _gauges_box: Control
var _xp_fill: ColorRect
var _level_label: Label
var _hero_button: Button
var _hero_plus: Label
var _hp_fill: ColorRect
var _hunger_fill: ColorRect
var _stamina_fill: ColorRect
var _coins_label: Label
var _dollars_label: Label
var _load_label: Label
var _depth_box: Control
var _depth_label: Label
var _toast_panel: Panel
var _toast_label: Label
var _toast_timer: Timer
var _stick: Control
var _knob: Control
var _hold_hint: Label

# --- третий режим: экранные стрелки ---
## Шесть кнопок ровно по шести направлениям магнетизма: ↖ ↑ ↗ / ← → / ↓.
## Вниз по диагонали нет — копка всегда строго под собой, и кнопки под неё
## быть не должно, иначе игрок ищет её и не находит.
## Четыре стрелки крестом (решение владельца), диагональных кнопок нет.
## Диагонали при этом никуда не делись: ↑ вместе с ← или → дают ↖ и ↗, как на
## любой крестовине. Без этого в режиме стрелок нельзя прыгнуть вперёд — а в
## двух других режимах можно, и одно и то же движение требовало бы разных
## навыков в зависимости от режима.
##
## Стрелки РИСУЮТСЯ треугольниками (см. scripts/ui/arrow_icon.gd), а не
## пишутся символами: ↑ ← → ↓ (U+2190…U+2193) в шрифте темы по умолчанию
## отсутствуют и выходят пустыми квадратами с шестнадцатеричным кодом
## внутри — та же ловушка, что с ✕ и ↺, и та же, что была у кнопок хода в
## доме (house_view.gd) с ◀/▶. Вектор здесь — направление острия.
const ARROW_CELLS: Array = [
	{"dir": "up", "col": 1, "row": 0, "v": Vector2(0, -1)},
	{"dir": "left", "col": 0, "row": 1, "v": Vector2(-1, 0)},
	{"dir": "right", "col": 2, "row": 1, "v": Vector2(1, 0)},
	{"dir": "down", "col": 1, "row": 2, "v": Vector2(0, 1)},
]
var _arrows_panel: Control
var _arrow_buttons: Dictionary = {}   # dir -> Button
## Какие стрелки зажаты прямо сейчас. Именно НАБОР, а не одна: две кнопки
## под двумя пальцами — это диагональ.
var _arrows_held: Dictionary = {}
var _tool_button: Button
## Число брикетов топлива у бурмобиля — видно только пока он надет (решение
## владельца: «если он экипирован бурмобилем, он должен иметь на себе
## топливо», см. отчёт агента «Бурмобиль — транспорт»).
var _fuel_label: Label
var _well_panel: Control
var _objective_panel: PanelContainer
var _objective_label: Label
var _quest_button: Button
var _objective_text: String = ""
var _objective_hide_at_msec: float = 0.0

## Сколько секунд держать баннер задания, прежде чем свернуть его в кнопку.
const OBJECTIVE_SHOW_SECONDS := 6.0
var _tool_name_panel: PanelContainer
var _tool_name_label: Label
var _tool_name_timer: Timer
var _gear_pack: TextureRect
var _gear_jet: TextureRect
var _mode_button: Button
var _inv_button: Button
var _inv_sheet: Control
var _inv_list: VBoxContainer
var _inv_load_label: Label
var _inv_total_label: Label
var _drop_panel: Control
var _drop_title: Label
var _drop_slider: HSlider
var _drop_field: LineEdit
var _drop_id: String = ""
var _drop_max: int = 0
## Тестовая панель отладки (scripts/ui/debug_panel.gd) — НЕ для релиза
## игрокам, см. её собственный файл. Живёт отдельным классом, а не куском
## кода здесь, — не завязана на раскладку остального HUD, добавляется в
## HUD последней (см. _build_ui), поэтому видна и кликабельна поверх всего.
var _debug_panel: DebugPanel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Якоря корня намеренно не растягивающие: размер выставляется вручную в
	# _update_layout (Control под CanvasLayer не наследует размер вьюпорта).
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_build_ui()
	_connect_game_state()
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	_sync_all()


## Три полоски выживания (HP/голод/усталость) вводятся не сразу: до сцены
## смерти их на экране нет (ГДД п.9), прячет их режиссура сюжета. Метод нужен
## именно ей: без него story_director искал коробку, шагая вверх по дереву от
## заливки HP, промахивался на один уровень и гасил ВЕСЬ игровой слой —
## вместе с джойстиком, кошельком, глубиной и шторкой инвентаря.
func set_gauges_visible(v: bool) -> void:
	if _gauges_box != null:
		_gauges_box.visible = v
	_place_objective()


func are_gauges_visible() -> bool:
	return _gauges_box != null and _gauges_box.visible


func set_player(p: Node) -> void:
	player = p
	player.fell.connect(_on_fell)
	player.dig_blocked.connect(_on_dig_blocked)
	player.dig_finished.connect(_on_dig_finished)
	player.gear_unlocked.connect(_on_gear_unlocked)
	player.tool_auto_switched.connect(_on_tool_switched)
	if player.has_signal("entered_rig"):
		player.entered_rig.connect(_on_entered_rig)
	if player.has_signal("rig_fuel_warning"):
		player.rig_fuel_warning.connect(_on_rig_fuel_warning)
	_sync_tool()


# ---------------------------------------------------------------------------
# Построение интерфейса
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var stage := Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.offset_bottom = -STRIP_H
	add_child(stage)

	_build_gauges(stage)
	_build_purse(stage)
	_build_depth(stage)
	_build_toast(stage)
	_build_stick(stage)
	_build_hold_hint(stage)
	_build_arrows(stage)
	_build_inventory_sheet(stage)
	_build_strip()
	_build_debug_panel()


## Левый верхний угол сверху вниз: уровень и опыт, три полоски выживания,
## кнопка «Герой». Один столбец — потому что всё это про самого героя, и
## глазу не приходится собирать его состояние по разным углам экрана.
func _build_gauges(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "Gauges"
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # кнопка «Герой» внутри
	box.position = Vector2(8, 8)
	box.add_theme_constant_override("separation", 3)
	parent.add_child(box)
	_gauges_box = box

	_build_xp_row(box)
	_hp_fill = _make_gauge_row(box, Color8(0xB8, 0x5A, 0x52), "res://art/ui/icon_hp.png")
	_hunger_fill = _make_gauge_row(box, Color8(0xC4, 0x70, 0x6A), "res://art/ui/icon_hunger.png")
	_stamina_fill = _make_gauge_row(box, Color8(0x6E, 0x93, 0xA8), "res://art/ui/icon_stamina.png")
	_build_hero_button(box)


## Уровень и опыт — над полосками выживания. Полоска опыта тоньше остальных:
## она про долгую перспективу, а те три — про «доживу ли до поверхности», и
## путать их по важности нельзя.
func _build_xp_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 10)
	_level_label.add_theme_color_override("font_color", Color8(0xE0, 0xA9, 0x3B))
	_level_label.custom_minimum_size = Vector2(13, 0)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_level_label)

	var track := Panel.new()
	track.custom_minimum_size = Vector2(72, 5)
	# Без этого HBoxContainer растягивает подложку на всю высоту ряда (её
	# задаёт иконка слева), и под заливкой висит чёрный хвост.
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.035, 0.027, 0.75)
	sb.border_color = Color(0, 0, 0, 0.55)
	sb.set_border_width_all(1)
	track.add_theme_stylebox_override("panel", sb)
	row.add_child(track)

	_xp_fill = ColorRect.new()
	_xp_fill.color = Color8(0xE0, 0xA9, 0x3B)
	_xp_fill.position = Vector2.ZERO
	_xp_fill.size = Vector2(72, 5)
	track.add_child(_xp_fill)


## Кнопка «Герой» переехала из меню «•••» под полоски (решение владельца): она
## про то же, про что и они, и открывать её оттуда, где показано состояние
## героя, естественнее, чем из общего ящика.
##
## Когда есть непотраченные очки — подпись золотом и зелёный плюс: иначе
## игрок копит очки и не знает об этом.
func _build_hero_button(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)

	_hero_button = Button.new()
	_hero_button.text = "Герой"
	_hero_button.add_theme_font_size_override("font_size", 9)
	_hero_button.focus_mode = Control.FOCUS_NONE
	_hero_button.custom_minimum_size = Vector2(44, 16)
	_hero_button.pressed.connect(func(): ProgressScreen.open("progress"))
	row.add_child(_hero_button)

	_hero_plus = Label.new()
	_hero_plus.text = "+"
	_hero_plus.add_theme_font_size_override("font_size", 13)
	_hero_plus.add_theme_color_override("font_color", Color8(0x6E, 0xC6, 0x4B))
	_hero_plus.visible = false
	row.add_child(_hero_plus)

	_build_quest_button(parent)


## Кнопка «Задания» под «Героем» (решение владельца). Баннер задания висел на
## экране всё время — он закрывал треть огорода и переставал читаться уже на
## втором взгляде. Теперь новое задание показывается ненадолго и сворачивается
## сюда; нажатие разворачивает его обратно.
func _build_quest_button(parent: Control) -> void:
	_quest_button = Button.new()
	_quest_button.text = "Задания"
	_quest_button.add_theme_font_size_override("font_size", 9)
	_quest_button.focus_mode = Control.FOCUS_NONE
	_quest_button.custom_minimum_size = Vector2(52, 16)
	_quest_button.visible = false
	_quest_button.pressed.connect(_on_quest_button_pressed)
	parent.add_child(_quest_button)


func _make_gauge_row(parent: Control, fill_color: Color, icon_path: String) -> ColorRect:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)

	if ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(13, 13)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(icon_path)
		row.add_child(icon)

	var track := Panel.new()
	track.custom_minimum_size = Vector2(72, 8)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.035, 0.027, 0.75)
	sb.border_color = Color(0, 0, 0, 0.55)
	sb.set_border_width_all(1)
	track.add_theme_stylebox_override("panel", sb)
	row.add_child(track)

	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = Vector2.ZERO
	fill.size = Vector2(72, 8)
	track.add_child(fill)
	return fill


func _build_purse(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # кнопка «Магазин» внутри
	box.anchor_left = 1.0; box.anchor_right = 1.0
	box.offset_left = -100; box.offset_right = -8
	box.offset_top = 8
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	parent.add_child(box)

	_coins_label = _make_purse_row(box, Color8(0xE0, 0xA9, 0x3B), "res://art/ui/icon_coin.png")
	_dollars_label = _make_purse_row(box, Color8(0x7F, 0xB8, 0x6B), "res://art/ui/icon_dollar.png")
	_load_label = _make_purse_row(box, Color8(0x8F, 0xA3, 0x5C), "res://art/ui/icon_inventory.png")

	# Кнопка «Магазин» под кошельком (решение владельца): премиум-витрина
	# открывается откуда угодно — и дома, и со дна шахты. Кладётся в тот же
	# столбик, поэтому не спорит за место с монетами и глубиной.
	var shop_row := HBoxContainer.new()
	shop_row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(shop_row)
	var shop_btn := Button.new()
	shop_btn.text = "Магазин"
	shop_btn.add_theme_font_size_override("font_size", 9)
	shop_btn.focus_mode = Control.FOCUS_NONE
	shop_btn.custom_minimum_size = Vector2(52, 16)
	shop_btn.pressed.connect(func(): ShopUI.open_premium())
	shop_row.add_child(shop_btn)


func _make_purse_row(parent: Control, color: Color, icon_path: String) -> Label:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)

	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)

	if ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(14, 14)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(icon_path)
		row.add_child(icon)
	return l


func _build_depth(parent: Control) -> void:
	_depth_box = Control.new()
	_depth_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_depth_box.anchor_left = 1.0; _depth_box.anchor_right = 1.0
	_depth_box.custom_minimum_size = Vector2(46, 22)
	_depth_box.offset_left = -46
	parent.add_child(_depth_box)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.071, 0.055, 0.043, 0.85)
	sb.border_color = Color8(0x3E, 0x31, 0x25)
	sb.set_border_width_all(1)
	sb.border_width_right = 0
	panel.add_theme_stylebox_override("panel", sb)
	_depth_box.add_child(panel)

	_depth_label = Label.new()
	_depth_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_depth_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_depth_label.add_theme_font_size_override("font_size", 13)
	_depth_box.add_child(_depth_label)
	_depth_box.visible = false


func _build_toast(parent: Control) -> void:
	_toast_panel = Panel.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.anchor_left = 0.0; _toast_panel.anchor_right = 1.0
	_toast_panel.anchor_top = 1.0; _toast_panel.anchor_bottom = 1.0
	_toast_panel.offset_left = 8; _toast_panel.offset_right = -8
	_toast_panel.offset_top = -160; _toast_panel.offset_bottom = -132
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.071, 0.055, 0.043, 0.93)
	sb.border_color = Color8(0xE0, 0xA9, 0x3B)
	sb.border_width_left = 3
	_toast_panel.add_theme_stylebox_override("panel", sb)
	_toast_panel.visible = false
	parent.add_child(_toast_panel)

	_toast_label = Label.new()
	_toast_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast_label.offset_left = 10; _toast_label.offset_top = 6
	_toast_label.add_theme_font_size_override("font_size", 12)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_toast_panel.add_child(_toast_label)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): _toast_panel.visible = false)
	add_child(_toast_timer)


func _build_stick(parent: Control) -> void:
	_stick = Control.new()
	_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick.custom_minimum_size = Vector2(stick_r * 2, stick_r * 2)
	_stick.draw.connect(func():
		_stick.draw_circle(Vector2(stick_r, stick_r), stick_r, Color(0.11, 0.09, 0.07, 0.68))
		_stick.draw_arc(Vector2(stick_r, stick_r), stick_r, 0, TAU, 40, Color(0.42, 0.34, 0.25, 0.6), 1.0)
	)
	parent.add_child(_stick)

	var hint := Label.new()
	hint.text = ""
	# Кегль под уменьшившийся стик: при 8 подпись вылезала за круг.
	hint.add_theme_font_size_override("font_size", 6)
	hint.add_theme_color_override("font_color", Color8(0x8F, 0xA3, 0x5C))
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 4
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stick.add_child(hint)

	_knob = Control.new()
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_knob.custom_minimum_size = Vector2(knob_r * 2, knob_r * 2)
	_knob.position = Vector2(stick_r - knob_r, stick_r - knob_r)
	_knob.draw.connect(func():
		var live: bool = hold_active()
		_knob.draw_circle(Vector2(knob_r, knob_r), knob_r, Color8(0x3A, 0x2C, 0x20))
		_knob.draw_arc(Vector2(knob_r, knob_r), knob_r - 1, 0, TAU, 32,
			Color8(0xE0, 0xA9, 0x3B) if live else Color8(0x9D, 0x8B, 0x73), 2.0)
	)
	_stick.add_child(_knob)


func hold_active() -> bool:
	return player != null and (player.hold_dx != 0 or player.hold_up or player.hold_down)


func _build_hold_hint(parent: Control) -> void:
	_hold_hint = Label.new()
	_hold_hint.text = "Зажми экран в нужную сторону — герой пойдёт туда и будет копать.\nОтпустил — остановился."
	_hold_hint.add_theme_font_size_override("font_size", 11)
	_hold_hint.add_theme_color_override("font_color", Color8(0x9D, 0x8B, 0x73))
	_hold_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hold_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hold_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hold_hint.offset_left = 10; _hold_hint.offset_right = -10
	_hold_hint.offset_top = -40; _hold_hint.offset_bottom = -8
	_hold_hint.visible = false
	parent.add_child(_hold_hint)


## Экранные стрелки — третий режим управления (решение владельца). Шесть
## кнопок в сетке 3×3 справа внизу, там же, где джойстик: рука не переучивается
## при переключении режима.
##
## Кнопки держат намерение, а не «нажимают шаг»: удержание — единственный
## способ вести героя, который есть у остальных двух режимов, и третий не
## должен вести себя иначе.
func _build_arrows(parent: Control) -> void:
	_arrows_panel = Control.new()
	_arrows_panel.name = "Arrows"
	_arrows_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrows_panel.visible = false
	parent.add_child(_arrows_panel)

	for cell in ARROW_CELLS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		var dir := String(cell["dir"])
		b.button_down.connect(func(): _on_arrow_down(dir))
		b.button_up.connect(func(): _on_arrow_up(dir))
		_arrows_panel.add_child(b)

		# Треугольник, а не текстовый символ — общий хелпер, см.
		# scripts/ui/arrow_icon.gd (шрифт темы не содержит стрелок-глифов).
		var glyph := ArrowIcon.new()
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.dir = cell["v"]
		b.add_child(glyph)

		_arrow_buttons[dir] = b


func _layout_arrows() -> void:
	if _arrows_panel == null or _arrow_buttons.is_empty():
		return
	# Сетка садится ровно на место джойстика — та же рука, то же место.
	var cell_size: float = maxf(22.0, stick_r * 0.66)
	var gap := 3.0
	var grid: float = cell_size * 3.0 + gap * 2.0
	var origin := Vector2(size.x - 12.0 - grid, stage_rect.size.y - 12.0 - grid)
	_arrows_panel.position = origin
	_arrows_panel.size = Vector2(grid, grid)
	for cell in ARROW_CELLS:
		var b: Button = _arrow_buttons[String(cell["dir"])]
		b.custom_minimum_size = Vector2(cell_size, cell_size)
		b.size = Vector2(cell_size, cell_size)
		b.position = Vector2(float(cell["col"]) * (cell_size + gap),
			float(cell["row"]) * (cell_size + gap))
		for g in b.get_children():
			(g as Control).queue_redraw()


func _on_arrow_down(dir: String) -> void:
	_arrows_held[dir] = true
	_apply_arrows()


func _on_arrow_up(dir: String) -> void:
	_arrows_held.erase(dir)
	if _arrows_held.is_empty() and player != null:
		player.release_control()
		player.digging = null
		return
	_apply_arrows()


## Стрелки — это уже выбранные направления, магнетизм им не нужен: он против
## неточного пальца, а кнопка неточной не бывает.
##
## Правила те же, что у джойстика после магнетизма: вниз всегда строго под
## собой (↓ перебивает всё остальное — копка это осознанное действие), вверх
## можно вместе с шагом.
func _apply_arrows() -> void:
	if player == null or _arrows_held.is_empty():
		return
	var dx := 0
	if _arrows_held.has("left"):
		dx -= 1
	if _arrows_held.has("right"):
		dx += 1
	if _arrows_held.has("down"):
		player.set_intent(0, false, true)
	elif _arrows_held.has("up"):
		player.set_intent(dx, true, false)
	else:
		player.set_intent(dx, false, false)
	player.cancel_wrong_dig()


func _build_inventory_sheet(parent: Control) -> void:
	_inv_sheet = Control.new()
	_inv_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inv_sheet.visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.071, 0.055, 0.043, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inv_sheet.add_child(bg)
	parent.add_child(_inv_sheet)

	var head := HBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 10; head.offset_right = -10
	head.offset_top = 8; head.offset_bottom = 30
	_inv_sheet.add_child(head)

	var title := Label.new()
	title.text = "Инвентарь"
	title.add_theme_font_size_override("font_size", 12)
	head.add_child(title)

	_inv_load_label = Label.new()
	_inv_load_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_inv_load_label.add_theme_color_override("font_color", Color8(0x8F, 0xA3, 0x5C))
	_inv_load_label.add_theme_font_size_override("font_size", 10)
	head.add_child(_inv_load_label)

	var close_btn := Button.new()
	# Именно × (U+00D7), а не ✕ (U+2715): последнего в шрифте темы по
	# умолчанию нет, и он рисуется пустым квадратом (та же ловушка, что со
	# стрелкой ↺ на кнопке сброса).
	close_btn.text = "×"
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.custom_minimum_size = Vector2(20, 20)
	close_btn.pressed.connect(close_inventory)
	head.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 10; scroll.offset_right = -10
	scroll.offset_top = 36; scroll.offset_bottom = -30
	_inv_sheet.add_child(scroll)
	# Прокрутка перетаскиванием списка, а не только ползунком (решение владельца).
	DragScroll.attach(scroll)

	_inv_list = VBoxContainer.new()
	_inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inv_list)

	var foot := HBoxContainer.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_left = 10; foot.offset_right = -10
	foot.offset_top = -26; foot.offset_bottom = -6
	_inv_sheet.add_child(foot)
	var foot_label := Label.new()
	foot_label.text = "К продаже:"
	foot_label.add_theme_font_size_override("font_size", 11)
	foot.add_child(foot_label)
	_inv_total_label = Label.new()
	_inv_total_label.add_theme_color_override("font_color", Color8(0xE0, 0xA9, 0x3B))
	_inv_total_label.add_theme_font_size_override("font_size", 11)
	foot.add_child(_inv_total_label)

	_build_drop_panel(_inv_sheet)


## Окно «выбросить N штук»: ползунок и то же число полем ввода — на телефоне
## ползунком трудно попасть в «ровно 7 из 240», а руками неудобно набирать
## «120». Поле открывает цифровую клавиатуру, буквы в нём не принимаются.
func _build_drop_panel(parent: Control) -> void:
	_drop_panel = Control.new()
	_drop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drop_panel.visible = false
	parent.add_child(_drop_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drop_panel.add_child(dim)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(196, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0x1A, 0x14, 0x0F)
	sb.border_color = Color8(0x3E, 0x31, 0x25)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sb)
	_drop_panel.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	_drop_title = Label.new()
	_drop_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	_drop_title.add_theme_font_size_override("font_size", 11)
	box.add_child(_drop_title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	_drop_slider = HSlider.new()
	_drop_slider.min_value = 1
	_drop_slider.step = 1
	_drop_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_slider.value_changed.connect(_on_drop_slider_changed)
	row.add_child(_drop_slider)

	_drop_field = LineEdit.new()
	_drop_field.custom_minimum_size = Vector2(46, 0)
	_drop_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drop_field.max_length = 6
	# Только цифровая клавиатура: количество — всегда целое, буквам тут
	# делать нечего (то же, что inputmode="numeric" в web-демо).
	_drop_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_drop_field.text_changed.connect(_on_drop_field_changed)
	_drop_field.text_submitted.connect(func(_t): _apply_drop())
	row.add_child(_drop_field)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)

	var all_btn := Button.new()
	all_btn.text = "Всё"
	all_btn.add_theme_font_size_override("font_size", 10)
	all_btn.pressed.connect(func(): _drop_slider.value = _drop_max)
	buttons.add_child(all_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Отмена"
	cancel_btn.add_theme_font_size_override("font_size", 10)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_close_drop)
	buttons.add_child(cancel_btn)

	var ok_btn := Button.new()
	ok_btn.text = "Выбросить"
	ok_btn.add_theme_font_size_override("font_size", 10)
	ok_btn.add_theme_color_override("font_color", Color8(0xC4, 0x70, 0x6A))
	ok_btn.pressed.connect(_apply_drop)
	buttons.add_child(ok_btn)


func _open_drop(id: String, count: int) -> void:
	if count <= 0:
		return
	_drop_id = id
	_drop_max = count
	_drop_title.text = "Выбросить «%s» (в рюкзаке %d)" % [
		String(Balance.get_mineral(id).get("name_ru", id)), count]
	_drop_slider.max_value = count
	_drop_slider.value = count
	_drop_field.text = str(count)
	_drop_panel.visible = true


func _close_drop() -> void:
	_drop_panel.visible = false
	_drop_id = ""


func _drop_amount() -> int:
	return clampi(int(_drop_slider.value), 1, maxi(1, _drop_max))


func _on_drop_slider_changed(v: float) -> void:
	var n := clampi(int(v), 1, maxi(1, _drop_max))
	if _drop_field.text != str(n):
		_drop_field.text = str(n)


func _on_drop_field_changed(t: String) -> void:
	# Чистим ввод на месте: на телефоне цифровая клавиатура всё равно может
	# отдать минус или запятую, а каретку при этом терять нельзя.
	var digits := ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits != t:
		var caret := _drop_field.caret_column - (t.length() - digits.length())
		_drop_field.text = digits
		_drop_field.caret_column = maxi(0, caret)
	if digits.is_empty():
		return
	var n := clampi(int(digits), 1, maxi(1, _drop_max))
	if int(_drop_slider.value) != n:
		_drop_slider.set_value_no_signal(n)
	if str(n) != digits:
		_drop_field.text = str(n)
		_drop_field.caret_column = _drop_field.text.length()


func _apply_drop() -> void:
	if _drop_id.is_empty():
		return
	var n := _drop_amount()
	var id := _drop_id
	GameState.remove_item(id, n)
	_close_drop()
	_render_inventory()
	_sync_purse()
	toast("Выброшено: %s ×%d" % [
		String(Balance.get_mineral(id).get("name_ru", id)), n], 2.0)


var _more_panel: PanelContainer
var _more_button: Button


func _build_strip() -> void:
	# Подложка — отдельный слой под рядом кнопок. Если положить Panel внутрь
	# HBoxContainer, контейнер разложит её как обычный элемент ряда нулевой
	# ширины, и фона у полосы не будет вовсе.
	var root := Control.new()
	root.name = "Strip"
	root.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	root.offset_top = -STRIP_H
	root.offset_bottom = 0
	add_child(root)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0x16, 0x12, 0x0E)
	var bg_panel := Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_panel.add_theme_stylebox_override("panel", sb)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg_panel)

	var strip := HBoxContainer.new()
	strip.name = "Row"
	strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	strip.add_theme_constant_override("separation", 5)
	root.add_child(strip)

	# Систем стало пять, и каждая честно попросила себе кнопку — в ряду
	# шириной 224 их девять, а нужно им около 315. Ряд делится по тому,
	# нужна ли кнопка ВО ВРЕМЯ КОПКИ: инвентарь, склад, инструмент и
	# снаряжение остаются на виду, всё остальное уходит под «⋯». Прятать
	# по важности, а не по алфавиту: игрок сидит в шахте, а не в меню.
	var more_menu := _build_more_menu()
	_build_tool_name_popup()
	_build_objective_line()

	# Иконкой, а не словом: ряд шириной 224 не вмещает подпись «Инвентарь»
	# вместе с названием инструмента, снаряжением, режимом и сбросом.
	_inv_button = _make_chip("")
	if ResourceLoader.exists("res://art/ui/icon_backpack.png"):
		_inv_button.icon = load("res://art/ui/icon_backpack.png")
		_inv_button.expand_icon = true
		_inv_button.custom_minimum_size = Vector2(26, STRIP_H)
	else:
		_inv_button.text = "Инв"
	_inv_button.tooltip_text = "Инвентарь"
	_inv_button.toggle_mode = true
	_inv_button.pressed.connect(_on_inv_button_pressed)
	strip.add_child(_inv_button)

	# Инструмент — одна иконка без подписи. Название всплывает НАД полосой по
	# нажатию (и подсказкой при наведении на компьютере): слово «Лопата»
	# держало в ряду шириной 224 почти сорок точек, а нужно оно раз в час —
	# когда игрок сам не помнит, чем копает.
	_tool_button = _make_flat(_make_chip(""))
	_tool_button.custom_minimum_size = Vector2(26, STRIP_H)
	_tool_button.expand_icon = true
	_tool_button.pressed.connect(_show_tool_name)
	strip.add_child(_tool_button)

	# Брикеты топлива — числом, рядом с иконкой инструмента. Спрятан, пока
	# бурмобиль не надет: у остальных инструментов топлива нет, и пустая
	# метка на полосе шириной 224 только крала бы место зря.
	_fuel_label = Label.new()
	_fuel_label.add_theme_font_size_override("font_size", 9)
	_fuel_label.visible = false
	_fuel_label.tooltip_text = "Брикеты угля для бурмобиля"
	_fuel_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(_fuel_label)

	var gear_box := HBoxContainer.new()
	_gear_pack = _make_gear_icon(gear_box, "")
	_gear_jet = null
	strip.add_child(gear_box)

	# Пустая распорка: слева — то, чем копают, справа — куда ходят. Раньше
	# слабину ряда забирала подпись инструмента, теперь её держит она.
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(spacer)

	# --- экономика: кнопка мастерской (scripts/shop/) ---
	# Одна кнопка на всю экономику: шторка внутри сама делится на продажу,
	# верстак и лавку. Из комнаты мастерской она же открывается вызовом
	# ShopUI.open_shop() — верстак в мастерской теперь экипировка, а магазин
	# живёт у входной двери; эта кнопка — запасной вход, пока дом как сцена
	# не доделан.
	var shop_btn := _make_chip("")
	if ResourceLoader.exists("res://art/ui/icon_coin.png"):
		shop_btn.icon = load("res://art/ui/icon_coin.png")
		shop_btn.expand_icon = true
		shop_btn.custom_minimum_size = Vector2(24, STRIP_H)
	else:
		shop_btn.text = "Лавка"
	shop_btn.tooltip_text = "Мастерская: продажа, верстак, лавка"
	shop_btn.pressed.connect(func(): ShopUI.open_shop())
	shop_btn.text = "Мастерская"
	shop_btn.custom_minimum_size = Vector2(0, STRIP_H)
	more_menu.add_child(shop_btn)
	# --- конец блока экономики ---

	# --- прокачка и музей (scripts/progress/) ---
	# Кнопки «Герой» в «⋯» больше нет: экран героя открывается кнопкой под
	# полосками жизни (_build_hero_button), где её видно, не раскрывая меню,
	# и где она золотится, когда есть что прокачать.
	# --- конец блока прокачки ---

	# --- дом (scripts/house/) ---
	# Контекстной кнопки «Дом» на полосе больше нет: дом — пространство, и
	# «Зайти» всплывает над героем у окна веранды (HouseSystem).
	# Склад (ГДД п.14) виден ОТКУДА УГОДНО, хоть со дна шахты, — но только
	# на просмотр: игрок должен планировать вылазку, зная, чего не хватает до
	# кирки. Поэтому кнопка постоянная, а не контекстная. Иконкой и без
	# подписи: в ряду шириной 224 на восемь кнопок каждое слово на счету.
	var storage_btn := _make_chip("")
	if ResourceLoader.exists("res://art/ui/icon_inventory.png"):
		storage_btn.icon = load("res://art/ui/icon_inventory.png")
		storage_btn.expand_icon = true
		storage_btn.custom_minimum_size = Vector2(22, STRIP_H)
	else:
		storage_btn.text = "Скл"
	storage_btn.tooltip_text = "Склад в мастерской"
	storage_btn.add_to_group("house_storage_button")
	strip.add_child(storage_btn)
	# --- конец блока дома ---

	_mode_button = _make_chip("")
	_mode_button.pressed.connect(_on_mode_button_pressed)
	more_menu.add_child(_mode_button)

	# Стрелка ↺ (U+21BA) отсутствует в шрифте темы по умолчанию и рисуется
	# пустым квадратом — подписываем словом.
	var reset_btn := _make_chip("Сброс")
	reset_btn.pressed.connect(_on_reset_pressed)
	more_menu.add_child(reset_btn)

	# Метка сборки. Владелец несколько раз открывал игру и не видел изменений,
	# и по переписке нельзя было отличить «раздача отстала» от «браузер отдал
	# старую копию из кэша». Теперь версия видна на экране, и один взгляд
	# отвечает на вопрос. Пишется tools/make_build_info.py перед экспортом.
	var build_label := Label.new()
	build_label.text = _build_stamp()
	build_label.add_theme_font_size_override("font_size", 7)
	build_label.add_theme_color_override("font_color", Color8(0x6B, 0x5D, 0x4C))
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	more_menu.add_child(build_label)

	# «⋯» встаёт последним, чтобы контекстная кнопка дома, появляясь и
	# исчезая, не сдвигала его под пальцем.
	_more_button = _make_chip("•••")
	_more_button.tooltip_text = "Ещё"
	_more_button.custom_minimum_size = Vector2(26, STRIP_H)
	_more_button.pressed.connect(_toggle_more_menu)
	strip.add_child(_more_button)

	# Любой пункт меню закрывает меню: иначе шторка мастерской открывается
	# поверх ещё раскрытого списка, и он ждёт игрока под ней.
	for item in more_menu.get_children():
		if item is Button:
			(item as Button).pressed.connect(close_more_menu)

	_set_mode("stick")


## Тестовая панель отладки (scripts/ui/debug_panel.gd) — добавляется в HUD
## САМОЙ ПОСЛЕДНЕЙ (после основной нижней полосы), поэтому её триггер рисуется
## и кликается поверх всего остального. Не в общей нижней полосе (задание
## владельца: там уже инструмент/«•••»/топливо, и рядом другой агент двигает
## стрелки по бокам) — свой маленький триггер «Тест» стоит НАД полосой слева,
## зеркально «•••» справа, и раскрывается вверх, не занимая места, пока закрыт.
func _build_debug_panel() -> void:
	_debug_panel = DebugPanel.new()
	_debug_panel.name = "DebugPanel"
	add_child(_debug_panel)


## Меню «⋯»: то, что нужно на поверхности, а не в шахте.
##
## Всплывает НАД полосой и прижато к правому краю, к своей кнопке. Пока оно
## открыто, ввод в мир глушится (см. _input и update_input_intent) — иначе
## палец, метящий в пункт меню, попадает в джойстик под ним и герой копает
## под открытым меню.
func _build_more_menu() -> VBoxContainer:
	_more_panel = PanelContainer.new()
	_more_panel.name = "MoreMenu"
	_more_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0x1A, 0x14, 0x0F)
	sb.border_color = Color8(0x3E, 0x31, 0x25)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	_more_panel.add_theme_stylebox_override("panel", sb)
	_more_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_more_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_more_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_more_panel.offset_bottom = -STRIP_H - 2
	_more_panel.offset_right = -4
	add_child(_more_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_more_panel.add_child(box)
	return box


## Всплывающая надпись над выкопанной клеткой: «Золото +1». Живёт секунду,
## поднимается и тает. Это не тост: тост занимает всю ширину и перебивает
## экран, а тут нужна отметка ровно там, где копнули, — иначе на каждую
## клетку земли экран мигал бы полосой.
func float_pickup(cell_x: int, cell_y: int, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color8(0xE0, 0xA9, 0x3B))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)

	var from := Vector2(
		(float(cell_x) + 0.5 - current_cam.x) * TILE - 40.0,
		(float(cell_y) - current_cam.y) * TILE - 6.0)
	label.size = Vector2(80, 14)
	label.position = from

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", from.y - 18.0, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)


## Отчёт скважины при возвращении в игру (решение владельца): показать, что
## накопала за время отсутствия. Карточка со списком и одной кнопкой —
## закрывается ею же и тапом мимо, как остальные меню.
func show_well_report(report: Dictionary) -> void:
	if report.is_empty() or _well_panel != null:
		return
	_well_panel = Control.new()
	_well_panel.name = "WellReport"
	_well_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_well_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_well_panel.add_child(dim)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(200, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0x1A, 0x14, 0x0F)
	sb.border_color = Color8(0xE0, 0xA9, 0x3B)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sb)
	_well_panel.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)

	var title := Label.new()
	title.text = "Скважина работала без тебя"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color8(0xE0, 0xA9, 0x3B))
	box.add_child(title)

	var since := Label.new()
	since.text = "За %s накопала:" % _humanize_seconds(float(report.get("seconds", 0.0)))
	since.add_theme_font_size_override("font_size", 10)
	box.add_child(since)

	for id in report.get("items", {}).keys():
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = String(Balance.get_mineral(String(id)).get("name_ru", id))
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var count_label := Label.new()
		count_label.text = "×%d" % int(report["items"][id])
		count_label.add_theme_font_size_override("font_size", 10)
		count_label.add_theme_color_override("font_color", Color8(0xE0, 0xA9, 0x3B))
		row.add_child(count_label)
		box.add_child(row)

	var note := Label.new()
	note.text = "Всё сложено на склад в мастерской."
	note.add_theme_font_size_override("font_size", 9)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_color_override("font_color", Color8(0x8F, 0xA3, 0x5C))
	box.add_child(note)

	var ok := Button.new()
	ok.text = "Хорошо"
	ok.add_theme_font_size_override("font_size", 10)
	ok.pressed.connect(close_well_report)
	box.add_child(ok)


func close_well_report() -> void:
	if _well_panel == null:
		return
	_well_panel.queue_free()
	_well_panel = null


static func _humanize_seconds(seconds: float) -> String:
	var total := int(seconds)
	var h := total / 3600
	var m := (total % 3600) / 60
	if h > 0:
		return "%d ч %d мин" % [h, m]
	return "%d мин" % maxi(m, 1)


## Строка текущего обучающего задания — над полосой, поверх экрана. Держится,
## пока задание не выполнено: это не подсказка, а условие, без которого игра
## дальше не пускает (ГДД п.9). Тостом её сделать нельзя — тост гаснет, а
## задание надо видеть всё время, пока копаешь.
func _build_objective_line() -> void:
	_objective_panel = PanelContainer.new()
	_objective_panel.name = "Objective"
	_objective_panel.visible = false
	_objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.071, 0.055, 0.043, 0.92)
	sb.border_color = Color8(0xE0, 0xA9, 0x3B)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(5)
	_objective_panel.add_theme_stylebox_override("panel", sb)
	_objective_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_objective_panel.offset_left = 8
	_objective_panel.offset_right = -8
	add_child(_objective_panel)
	_place_objective()

	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", 10)
	_objective_label.add_theme_color_override("font_color", Color8(0xE0, 0xA9, 0x3B))
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_objective_panel.add_child(_objective_label)


## Строка задания встаёт ПОД левым столбиком (опыт, полоски, «Герой»), а не
## на фиксированной высоте: столбик то появляется целиком, то исчезает на
## время обучения, и жёсткая координата либо накрывала полоски, либо висела
## в пустоте. Высоту берём минимальную — она известна до раскладки.
func _place_objective() -> void:
	if _objective_panel == null:
		return
	var top := 12.0
	if _gauges_box != null and _gauges_box.visible:
		top = _gauges_box.position.y + _gauges_box.get_combined_minimum_size().y + 6.0
	_objective_panel.offset_top = top


## Ставит текст задания. Зовётся каждый кадр, поэтому разворачивает баннер
## только когда задание СМЕНИЛОСЬ: иначе он снова висел бы всё время.
func set_objective(text: String) -> void:
	if _objective_panel == null:
		return
	if text == _objective_text:
		return
	_objective_text = text
	_objective_label.text = text
	if text.is_empty():
		_objective_panel.visible = false
		if _quest_button != null:
			_quest_button.visible = false
		return
	_show_objective_banner()
	if _quest_button != null:
		_quest_button.visible = true


func _show_objective_banner() -> void:
	if _objective_panel == null or _objective_text.is_empty():
		return
	_objective_panel.visible = true
	_objective_hide_at_msec = Time.get_ticks_msec() + OBJECTIVE_SHOW_SECONDS * 1000.0
	_place_objective()


func _on_quest_button_pressed() -> void:
	# Повторное нажатие сворачивает: кнопка — переключатель, а не «показать
	# ещё раз», иначе баннер нечем убрать досрочно.
	if _objective_panel != null and _objective_panel.visible:
		_objective_panel.visible = false
		return
	_show_objective_banner()


## Всплывающая подпись инструмента: панелька над полосой, по центру, гаснет
## сама через пару секунд. Отдельный узел, а не тост: тост
## занимает всю ширину и перекрывает игровой экран, а тут нужно одно слово
## ровно над кнопкой, по которой ткнули.
func _build_tool_name_popup() -> void:
	_tool_name_panel = PanelContainer.new()
	_tool_name_panel.name = "ToolName"
	_tool_name_panel.visible = false
	_tool_name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0x1A, 0x14, 0x0F)
	sb.border_color = Color8(0x3E, 0x31, 0x25)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	_tool_name_panel.add_theme_stylebox_override("panel", sb)
	# По центру, а не над самой кнопкой: слева внизу лежит джойстик, и
	# подпись садилась ему на край — ровно туда, где в этот момент палец.
	_tool_name_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tool_name_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tool_name_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tool_name_panel.offset_bottom = -STRIP_H - 4
	add_child(_tool_name_panel)

	_tool_name_label = Label.new()
	_tool_name_label.add_theme_font_size_override("font_size", 11)
	_tool_name_panel.add_child(_tool_name_label)

	_tool_name_timer = Timer.new()
	_tool_name_timer.one_shot = true
	_tool_name_timer.wait_time = 2.0
	_tool_name_timer.timeout.connect(func(): _tool_name_panel.visible = false)
	add_child(_tool_name_timer)


func _show_tool_name() -> void:
	_tool_name_label.text = Balance.get_tool_name_ru(GameState.current_tool)
	_tool_name_panel.visible = true
	_tool_name_timer.start()


func _toggle_more_menu() -> void:
	_more_panel.visible = not _more_panel.visible
	if _more_panel.visible:
		# Иначе палец, уже «зажавший» мир, остаётся зажатым под открытым меню:
		# в режиме стика — ручка, в режиме пальца — удержание.
		_release_stick()
		_touch_pointer = -100
		_has_touch = false
		if player != null:
			player.release_control()
			player.digging = null


func close_more_menu() -> void:
	if _more_panel != null:
		_more_panel.visible = false


func is_more_menu_open() -> bool:
	return _more_panel != null and _more_panel.visible


# Кнопка нижней полосы: у темы Godot по умолчанию минимальная высота около
# 40px, а полоса ровно в одну кнопку толщиной (STRIP_H). Поджимаем отступы и
# кегль, иначе ряд вылезает за нижний край экрана.
## «сборка 17.09 04:13 · 32b66e5» — или пусто, если файла нет: метка
## необязательна, из редактора игра запускается и без неё.
func _build_stamp() -> String:
	var f := FileAccess.open("res://data/build_info.json", FileAccess.READ)
	if f == null:
		return ""
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		return ""
	var build := String(raw.get("build", ""))
	if build.length() < 13:
		return build
	# 20260917-0413 -> 17.09 04:13
	var pretty := "%s.%s %s:%s" % [build.substr(6, 2), build.substr(4, 2),
		build.substr(9, 2), build.substr(11, 2)]
	var commit := String(raw.get("commit", ""))
	return "сборка %s%s" % [pretty, (" · " + commit) if not commit.is_empty() else ""]


func _make_chip(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 9)
	b.custom_minimum_size = Vector2(0, STRIP_H)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color8(0x3E, 0x31, 0x25)
		sb.set_border_width_all(1)
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		if state == "pressed" or state == "hover":
			sb.border_color = Color8(0xE0, 0xA9, 0x3B)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color8(0x9D, 0x8B, 0x73))
	b.add_theme_color_override("font_pressed_color", Color8(0xE0, 0xA9, 0x3B))
	b.add_theme_color_override("font_hover_color", Color8(0xE0, 0xA9, 0x3B))
	return b


# Кнопка-иконка без рамки: рамка обещает нажатие, которое что-то переключит,
# а инструмент по нажатию всего лишь называет себя. Отступы оставляем от
# _make_chip — иначе иконка липнет к соседям.
func _make_flat(b: Button) -> Button:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		b.add_theme_stylebox_override(state, sb)
	return b


func _make_gear_icon(parent: Control, path: String) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(17, 17)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(path):
		t.texture = load(path)
	t.visible = false
	parent.add_child(t)
	return t


# ---------------------------------------------------------------------------
# Layout (пересчитывается при смене размера окна)
# ---------------------------------------------------------------------------

func _update_layout() -> void:
	var vp := get_viewport_rect().size
	# Control, лежащий прямо в CanvasLayer, не наследует размер вьюпорта от
	# родителя — якоря считаются от нулевого прямоугольника, и всё, что
	# прижато к правому краю или к низу, уезжает за экран (кошелёк уходил на
	# x=-100, нижняя полоса — на y=-32). Размер задаём явно.
	position = Vector2.ZERO
	size = vp
	stick_r = maxf(STICK_R_MIN, vp.x * STICK_FRACTION)
	knob_r = stick_r * 0.39
	stage_rect = Rect2(0, 0, vp.x, vp.y - STRIP_H)
	_stick.custom_minimum_size = Vector2(stick_r * 2, stick_r * 2)
	_stick.size = Vector2(stick_r * 2, stick_r * 2)
	_knob.custom_minimum_size = Vector2(knob_r * 2, knob_r * 2)
	_knob.size = Vector2(knob_r * 2, knob_r * 2)
	_knob.position = Vector2(stick_r - knob_r, stick_r - knob_r)
	# Джойстик справа внизу (решение владельца): большой палец правой руки
	# сам ложится туда, а левый край экрана остаётся под кошелёк и подсказки.
	_stick.position = Vector2(vp.x - 12 - stick_r * 2, stage_rect.size.y - 12 - stick_r * 2)
	_stick_center = _stick.position + Vector2(stick_r, stick_r)
	_stick.queue_redraw()
	_knob.queue_redraw()
	_layout_arrows()
	_place_objective()


func get_view_cells() -> Vector2i:
	var vp := get_viewport_rect().size
	var w: int = maxi(5, int(round(vp.x / TILE)))
	var h: int = maxi(9, int(round((vp.y - STRIP_H) / TILE)))
	return Vector2i(w, h)


# ---------------------------------------------------------------------------
# Игровой цикл: синхронизация полосок/кошелька/глубины/снаряжения
# ---------------------------------------------------------------------------

func _process(_dt: float) -> void:
	if _objective_panel != null and _objective_panel.visible \
			and Time.get_ticks_msec() > _objective_hide_at_msec:
		_objective_panel.visible = false
	if player != null:
		_stick.queue_redraw()
		_knob.queue_redraw()
		_update_depth()


func _connect_game_state() -> void:
	GameState.hp_changed.connect(func(hp, max_hp): _hp_fill.size.x = 72.0 * clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0))
	GameState.hunger_changed.connect(func(h): _hunger_fill.size.x = 72.0 * clampf(h / 100.0, 0.0, 1.0))
	GameState.stamina_changed.connect(func(s): _stamina_fill.size.x = 72.0 * clampf(s / 100.0, 0.0, 1.0))
	GameState.coins_changed.connect(func(_c): _sync_purse())
	GameState.dollars_changed.connect(func(_d): _sync_purse())
	GameState.gear_changed.connect(func(_g): _sync_gear_icon())
	GameState.inventory_changed.connect(func():
		_sync_purse()
		_sync_fuel()
		if _inv_sheet.visible:
			_render_inventory()
	)
	GameState.tool_changed.connect(func(_t): _sync_tool())
	GameState.rig_dismount_blocked.connect(func(_id):
		toast("Бурмобиль под землёй не бросить — сначала наверх или домой."))
	GameState.xp_changed.connect(func(_xp, _lvl): _sync_xp())
	GameState.leveled_up.connect(func(_lvl, _pts): _sync_xp())
	GameState.skill_points_changed.connect(func(_p): _sync_hero_button())


func _sync_all() -> void:
	_hp_fill.size.x = 72.0
	_hunger_fill.size.x = 72.0
	_stamina_fill.size.x = 72.0
	_sync_xp()
	_sync_hero_button()
	_sync_purse()
	_sync_fuel()
	_sync_tool()


func _sync_xp() -> void:
	if _xp_fill == null:
		return
	_level_label.text = str(GameState.level)
	var need: float = float(Balance.xp_required_for_level(GameState.level))
	var frac: float = clampf(float(GameState.xp) / maxf(need, 1.0), 0.0, 1.0)
	_xp_fill.size.x = 72.0 * frac
	_sync_hero_button()


## Есть непотраченные очки — подпись золотом и зелёный плюс. Без этого игрок
## копит очки и не знает об этом: экран героя сам о себе не напоминает.
func _sync_hero_button() -> void:
	if _hero_button == null:
		return
	var has_points := GameState.skill_points_available > 0
	_hero_plus.visible = has_points
	_hero_button.add_theme_color_override("font_color",
		Color8(0xE0, 0xA9, 0x3B) if has_points else Color8(0x9D, 0x8B, 0x73))


func _sync_purse() -> void:
	_coins_label.text = str(GameState.coins)
	_dollars_label.text = str(GameState.dollars)
	var load_kg := GameState.get_total_weight()
	var max_kg := GameState.get_max_carry_kg()
	_load_label.text = "%.1f / %.0f кг" % [load_kg, max_kg]
	_load_label.add_theme_color_override("font_color",
		Color8(0xB8, 0x5A, 0x52) if load_kg > max_kg * 0.85 else Color8(0x8F, 0xA3, 0x5C))


func _sync_tool() -> void:
	var tool_id := GameState.current_tool
	var tool_name := Balance.get_tool_name_ru(tool_id)
	_tool_button.tooltip_text = tool_name
	var icon_path := _tool_icon_path(tool_id)
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		_tool_button.icon = load(icon_path)
	else:
		# Без картинки кнопка была бы пустым прямоугольником — тогда пусть
		# уж подписью, как раньше.
		_tool_button.text = tool_name
	# Инструмент сменился сам (упёрлись в фундамент, дошли до глубины) —
	# показываем название, не дожидаясь, пока игрок ткнёт в иконку.
	if _tool_name_panel != null and _tool_name_panel.visible:
		_tool_name_label.text = tool_name
	_sync_gear_icon()
	_sync_fuel()


## Индикатор брикетов: виден только когда бурмобиль надет. Красный на нуле —
## того же цвета, что перегруз рюкзака (BAD в остальных экранах), чтобы
## тревожный цвет читался одинаково по всему интерфейсу.
func _sync_fuel() -> void:
	if _fuel_label == null:
		return
	var in_rig := GameState.current_tool == "drill_rig"
	_fuel_label.visible = in_rig
	if not in_rig:
		return
	var n := GameState.get_item_count("fuel_block")
	_fuel_label.text = "Топливо %d" % n
	_fuel_label.add_theme_color_override("font_color",
		Color8(0xB8, 0x5A, 0x52) if n <= 0 else Color8(0x9D, 0x8B, 0x73))


## На полосе — один значок: то, что надето. Тёмная иконка недоступного
## снаряжения читалась как сломанная кнопка, а не как «ещё не куплено», а с
## четырьмя ступенями и две фиксированные картинки отстали бы от линейки.
func _sync_gear_icon() -> void:
	if _gear_pack == null:
		return
	var gear_id := GameState.current_gear
	var path := Balance.get_gear_icon(gear_id) if not gear_id.is_empty() else ""
	if not path.is_empty() and not path.begins_with("res://"):
		path = "res://" + path
	if path.is_empty() or not ResourceLoader.exists(path):
		_gear_pack.visible = false
		return
	_gear_pack.texture = load(path)
	_gear_pack.tooltip_text = Balance.get_gear_name_ru(gear_id)
	_gear_pack.visible = true


## Путь к иконке инструмента — из данных (balance.json -> tools.icon), а не
## из перечисления здесь: с шестью кирками перечисление отставало бы от
## линейки при каждом добавлении. Исключение одно — трещина на дедовой кирке,
## это состояние героя, а не инструмента.
func _tool_icon_path(tool_id: String) -> String:
	if tool_id == "rusty_pickaxe" and player != null and player.rusty_pickaxe_cracked:
		return "res://art/items/pickaxe_rusty_cracked.png"
	var path := Balance.get_tool_icon(tool_id)
	if path.is_empty():
		# Своей иконки у бурмобиля в data/balance.json быть обязано
		# (tools.drill_rig.icon) — но если её всё же нет, лучше показать бур,
		# чем пустую кнопку: бурмобиль это и есть бур, только с кабиной.
		if tool_id == "drill_rig":
			return "res://art/items/hand_drill.png"
		return ""
	return path if path.begins_with("res://") else "res://" + path


func _update_depth() -> void:
	var d: int = player.cell_y()
	if d <= 0:
		_depth_box.visible = false
		return
	_depth_box.visible = true
	_depth_label.text = str(d)
	# см. placeDepth в web-демо: метка стоит на уровне героя на экране.
	var screen_y: float = (player.y - current_cam.y) * TILE
	_depth_box.position.y = clampf(screen_y - 11.0, 0.0, stage_rect.size.y - 22.0)


# ---------------------------------------------------------------------------
# Тосты
# ---------------------------------------------------------------------------

func toast(text: String, seconds: float = 2.6) -> void:
	_toast_label.text = text
	_toast_panel.visible = true
	_toast_timer.start(seconds)


func _on_fell(damage: float, speed: float) -> void:
	if damage > 0.0:
		toast("Удар на скорости %.1f кл/с — минус %d HP" % [speed, int(damage)])


func _on_dig_blocked(tile_type: int) -> void:
	var mineral_id := MineralMap.mineral_id_for(tile_type)
	var name_ru: String = "породу"
	if not mineral_id.is_empty():
		name_ru = String(Balance.get_mineral(mineral_id).get("name_ru", "породу"))
	toast(Balance.get_tool_name_ru(GameState.current_tool) + " звенит о " + name_ru.to_lower() + ". Стан от вибрации.")


func _on_dig_finished(x: int, y: int, tile_type: int, mineral_id: String, was_loot: bool, coins: int) -> void:
	if was_loot and coins == 0 and not mineral_id.is_empty():
		toast(Balance.get_mineral(mineral_id).get("name_ru", "Находка") + " — рюкзак полон, пришлось оставить.")
	elif was_loot and not mineral_id.is_empty():
		var name_ru := String(Balance.get_mineral(mineral_id).get("name_ru", ""))
		float_pickup(x, y, "%s +1" % name_ru)
		# Крупная находка отмечается тостом — но БЕЗ суммы в монетах: монет
		# за копку не дают вовсе, их дают при продаже, а «+100 монет» читается
		# как «уже на счету» (решение владельца). И не больше нескольких раз
		# за игру: на десятый раз это уже не событие, а помеха.
		if coins >= RARE_FIND_COINS and GameState.rare_find_toasts_shown < RARE_FIND_TOAST_LIMIT:
			GameState.rare_find_toasts_shown += 1
			toast("%s! Редкая находка." % name_ru)
	if y == 80 and tile_type == TileTypes.Type.DIAMOND:
		toast("Алмаз замурован в камне. Дедова кирка трескается — минус 25% скорости.", 4.0)


func _on_gear_unlocked(gear_id: String) -> void:
	_sync_tool()
	# Ранцы и джетпаки больше не выдаются глубиной — их покупают, и о покупке
	# говорит магазин. Здесь остались только вещи, которые открывает глубина.
	if gear_id == "drill_rig":
		toast("Глубина 1000. Собран бурмобиль — копает вдвое быстрее бура.", 5.0)


func _on_tool_switched(tool_id: String) -> void:
	_sync_tool()
	_show_tool_name()
	if tool_id == "rusty_pickaxe":
		toast("Лопата упёрлась в старый фундамент. В мастерской нашлась дедова кирка.", 3.6)


## Герой сам сел за руль, войдя в тоннель с машиной в собственности, но не в
## руках (решение владельца: «спускаясь под землю он должен быть только в
## нём»). tool_changed уже пересинхронизировал иконку — здесь только тост.
func _on_entered_rig() -> void:
	toast("Ты сел в бурмобиль.", 2.6)


## Бурмобиль без топлива: либо не пускает в тоннель с поверхности, либо
## глохнет прямо под землёй. Текст сообщения решает player.gd — здесь он
## просто показывается (см. player.gd:_move_y и :_start_dig).
func _on_rig_fuel_warning(message: String) -> void:
	toast(message)


# ---------------------------------------------------------------------------
# Кнопки нижней полосы
# ---------------------------------------------------------------------------

func _on_inv_button_pressed() -> void:
	if _inv_sheet.visible:
		close_inventory()
	else:
		open_inventory()


func open_inventory() -> void:
	_release_stick()
	_has_touch = false
	if player != null:
		player.digging = null
		player.release_control()
	_render_inventory()
	_inv_sheet.visible = true
	_inv_button.button_pressed = true


func close_inventory() -> void:
	_close_drop()
	_inv_sheet.visible = false
	_inv_button.button_pressed = false


func _render_inventory() -> void:
	for c in _inv_list.get_children():
		c.queue_free()
	var rows: Array = []
	for id in GameState.inventory.keys():
		var count: int = int(GameState.inventory[id])
		if count <= 0:
			continue
		var price := Balance.get_mineral_price(id)
		rows.append({"id": id, "count": count, "sum": price * count})
	rows.sort_custom(func(a, b): return a.sum > b.sum)

	if rows.is_empty():
		var empty := Label.new()
		empty.text = "Рюкзак пуст.\nЗемля и камень в него не кладутся — только руда и находки."
		empty.add_theme_font_size_override("font_size", 10)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_inv_list.add_child(empty)
		_inv_total_label.text = "0"
	else:
		var total := 0
		for row in rows:
			total += row.sum
			var line := HBoxContainer.new()
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(16, 16)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var tex := TileArt.texture_for(MineralMap.tile_type_for(row.id), 0, 0)
			if tex != null:
				icon.texture = tex
			line.add_child(icon)
			var name_label := Label.new()
			name_label.text = String(Balance.get_mineral(row.id).get("name_ru", row.id))
			name_label.add_theme_font_size_override("font_size", 10)
			name_label.clip_text = true
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(name_label)
			var count_label := Label.new()
			count_label.text = "×%d" % row.count
			count_label.add_theme_font_size_override("font_size", 10)
			line.add_child(count_label)
			var sum_label := Label.new()
			sum_label.text = str(row.sum)
			sum_label.add_theme_font_size_override("font_size", 10)
			sum_label.custom_minimum_size = Vector2(34, 0)
			sum_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			sum_label.add_theme_color_override("font_color", Color8(0xE0, 0xA9, 0x3B))
			line.add_child(sum_label)
			# Съесть прямо из рюкзака: кнопку «Еда» с нижней полосы убрали, и
			# голод в шахте закрывается там, где еда лежит.
			if HouseConfig.is_food(row.id):
				var eat_btn := Button.new()
				eat_btn.text = "Съесть"
				eat_btn.add_theme_font_size_override("font_size", 9)
				eat_btn.custom_minimum_size = Vector2(38, 20)
				var fid: String = row.id
				eat_btn.pressed.connect(func(): _eat_from_inventory(fid))
				line.add_child(eat_btn)
			# Выбросить: рюкзак заполняется задолго до подъёма, и без этого
			# единственный способ освободить место под алмаз — идти домой.
			var drop_btn := Button.new()
			drop_btn.text = "×"  # ✕ (U+2715) в шрифте темы отсутствует, см. выше
			drop_btn.tooltip_text = "Выбросить"
			drop_btn.add_theme_font_size_override("font_size", 10)
			drop_btn.custom_minimum_size = Vector2(22, 20)
			var rid: String = row.id
			var rcount: int = row.count
			drop_btn.pressed.connect(func(): _open_drop(rid, rcount))
			line.add_child(drop_btn)
			_inv_list.add_child(line)
		_inv_total_label.text = str(total)

	var load_kg := GameState.get_total_weight()
	var max_kg := GameState.get_max_carry_kg()
	_inv_load_label.text = "%.1f / %.0f кг" % [load_kg, max_kg]


func _eat_from_inventory(id: String) -> void:
	var res := HouseFood.eat(id)
	if not bool(res.get("ok", false)):
		toast(String(res.get("reason", "")))
		return
	toast("%s: голод +%d%%, бодрость +%d%%" % [
		HouseConfig.food_name(id), int(res.get("hunger", 0.0)), int(res.get("stamina", 0.0))])
	_render_inventory()
	_sync_all()


## Три режима по кругу: джойстик → палец → стрелки (решение владельца).
const MODES: Array[String] = ["stick", "hold", "arrows"]


func _on_mode_button_pressed() -> void:
	var i := MODES.find(mode)
	_set_mode(MODES[(i + 1) % MODES.size()])


func _set_mode(m: String) -> void:
	mode = m
	_release_stick()
	_has_touch = false
	_arrows_held.clear()
	if player != null:
		player.release_control()
	# Одна подпись на все три режима: название текущего («Стик»/«Палец»/
	# «Стрелки») игроку ничего не говорило — кнопка читалась как состояние, а
	# не как переключатель. Что именно включено, видно на экране.
	_mode_button.text = "Управление"
	_stick.visible = mode == "stick"
	_hold_hint.visible = mode == "hold"
	if _arrows_panel != null:
		_arrows_panel.visible = mode == "arrows"
		_layout_arrows()


func _on_reset_pressed() -> void:
	close_inventory()
	GameState.reset_progress()
	if GameState.world_ref != null:
		GameState.world_ref.diffs.clear()
		GameState.world_ref.events.clear()
	if GameState.fog_ref != null:
		GameState.fog_ref.reset_all()
	if player != null:
		player.teleport_home()
		player.rusty_pickaxe_cracked = false
	toast("Бабка улетела в Таиланд. Огород твой.")


# ---------------------------------------------------------------------------
# Ввод: джойстик и удержание пальца (портировано из web/index.html)
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Тап мимо меню закрывает меню (решение владельца). Разбирается ДО общей
	# заглушки ввода: пока меню открыто, мир ввод не получает, и закрыть его
	# иначе было бы нечем, кроме повторного попадания в ту же кнопку.
	if _dismiss_on_outside_press(event):
		return
	if player == null or _inv_sheet.visible or ProgressScreen.is_open() or is_more_menu_open():
		return

	match mode:
		"stick": _handle_stick_input(event)
		"hold": _handle_hold_input(event)
		# «Стрелки» ловятся самими кнопками (Control-ами), здесь ничего не
		# перехватываем — иначе тап по стрелке ушёл бы ещё и в мир.
		_: pass


## Закрывает открытое меню, если нажатие пришлось за его границей.
## Возвращает true, если событие на этом и закончилось.
##
## Касается только меню, у которых эта граница есть: всплывающего «•••» и
## окна выброса. Шторка инвентаря, мастерская, экран героя и дом занимают
## экран целиком — «за границей» у них нет места, и закрывает их крестик.
##
## Принудительная подсказка дома (батончик в шахте) намеренно не закрывается:
## она замораживает героя и ждёт одного конкретного действия — закрыть её
## мимо значило бы оставить игрока замороженным.
func _dismiss_on_outside_press(event: InputEvent) -> bool:
	var e := _normalize_pointer_event(event)
	if e.kind != "press":
		return false
	if _well_panel != null:
		if not _panel_card_rect(_well_panel).has_point(e.pos):
			close_well_report()
			get_viewport().set_input_as_handled()
			return true
		return false
	if _drop_panel != null and _drop_panel.visible:
		if not _drop_card_rect().has_point(e.pos):
			_close_drop()
			get_viewport().set_input_as_handled()
			return true
		return false
	if is_more_menu_open():
		if not Rect2(_more_panel.global_position, _more_panel.size).has_point(e.pos):
			close_more_menu()
			get_viewport().set_input_as_handled()
			return true
	return false


## Карточка окна — не сама панель (та во весь экран, это затемнение), а её
## внутренний PanelContainer.
func _panel_card_rect(panel: Control) -> Rect2:
	for child in panel.get_children():
		if child is PanelContainer:
			var c := child as PanelContainer
			return Rect2(c.global_position, c.size)
	return Rect2()


func _drop_card_rect() -> Rect2:
	return _panel_card_rect(_drop_panel)


## Приводит мышь/тач-события к одному виду: {kind:"press"|"release"|"move",
## pos:Vector2, pid:int}. kind="" — событие не касается указателя (игнорируем).
## Нужно, чтобы не завязываться на статическое сужение типов GDScript при
## разборе разных подклассов InputEvent в одной ветке if.
static func _normalize_pointer_event(event: InputEvent) -> Dictionary:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return {"kind": ""}
		return {"kind": "press" if mb.pressed else "release", "pos": mb.position, "pid": -1}
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		return {"kind": "press" if st.pressed else "release", "pos": st.position, "pid": st.index}
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		return {"kind": "move", "pos": mm.position, "pid": -1}
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		return {"kind": "move", "pos": sd.position, "pid": sd.index}
	return {"kind": ""}


func _handle_stick_input(event: InputEvent) -> void:
	var e := _normalize_pointer_event(event)
	match e.kind:
		"press":
			if _stick_pointer != -100:
				return
			if e.pos.distance_to(_stick_center) > stick_r * 1.6:
				return
			_stick_pointer = e.pid
			_apply_stick(e.pos)
			get_viewport().set_input_as_handled()
		"release":
			if e.pid == _stick_pointer:
				_release_stick()
				get_viewport().set_input_as_handled()
		"move":
			if e.pid == _stick_pointer:
				_apply_stick(e.pos)
				get_viewport().set_input_as_handled()


func _apply_stick(screen_pos: Vector2) -> void:
	var v: Vector2 = (screen_pos - _stick_center) / stick_r
	if v.length() > 1.0:
		v = v.normalized()
	var snap = player.resolve_dir(v.x, v.y, STICK_DEAD)
	_position_knob(snap)
	player.cancel_wrong_dig()


func _position_knob(snap) -> void:
	var base: Vector2 = Vector2(stick_r - knob_r, stick_r - knob_r)
	if snap == null:
		_knob.position = base
	else:
		_knob.position = base + Vector2(snap.x, snap.y) * 34.0


func _release_stick() -> void:
	_stick_pointer = -100
	if player != null:
		player.release_control()
	_position_knob(null)


func _handle_hold_input(event: InputEvent) -> void:
	var e := _normalize_pointer_event(event)
	match e.kind:
		"press":
			if _touch_pointer != -100:
				return
			if not stage_rect.has_point(e.pos):
				return
			_touch_pointer = e.pid
			_touch_pos = e.pos
			_has_touch = true
			get_viewport().set_input_as_handled()
		"release":
			if e.pid == _touch_pointer:
				_touch_pointer = -100
				_has_touch = false
				player.release_control()
				player.digging = null
				get_viewport().set_input_as_handled()
		"move":
			if e.pid == _touch_pointer:
				_touch_pos = e.pos
				get_viewport().set_input_as_handled()


## Пересчитывает намерение игрока каждый физический кадр (см. readHoldIntent
## в web-демо) — вызывается из main.gd перед player.physics_tick. Сначала
## клавиатура, потом палец: клавиша главнее, иначе лежащий на стекле палец
## перебивал бы её каждый кадр.
func update_input_intent() -> void:
	if player == null or ProgressScreen.is_open() or is_more_menu_open():
		return
	if _apply_keyboard():
		return
	if mode == "arrows":
		_apply_arrows()
		return
	if mode != "hold":
		return
	if not _has_touch:
		player.resolve_dir(0.0, 0.0, 1.0)
		return
	var wx: float = current_cam.x + _touch_pos.x / TILE
	var wy: float = current_cam.y + _touch_pos.y / TILE
	player.resolve_dir(wx - player.x, wy - player.y, 0.45)
	player.cancel_wrong_dig()


## Клавиатура: WASD и стрелки. Возвращает true, если клавиша держится и
## намерение уже выставлено ею.
##
## Углового магнетизма здесь нет намеренно. Он придуман против неточного
## пальца на стекле — «чуть-чуть вниз» вместо «влево», — а клавиша дискретна:
## нажал S, значит копать под собой. Поэтому правила простые и те же, что
## читает палец после магнетизма: вниз — строго под собой, без шага; вверх —
## можно бежать и прыгать одновременно.
func _apply_keyboard() -> bool:
	var dx := 0
	if _any_key(KEYS_LEFT):
		dx -= 1
	if _any_key(KEYS_RIGHT):
		dx += 1
	var up := _any_key(KEYS_UP)
	var down := _any_key(KEYS_DOWN)

	if dx == 0 and not up and not down:
		if _keyboard_active:
			_keyboard_active = false
			player.release_control()
			_position_knob(null)
		return false

	_keyboard_active = true
	if down:
		player.set_intent(0, false, true)
		_position_knob(Vector2(0, 1))
	elif up:
		player.set_intent(dx, true, false)
		_position_knob(Vector2(dx * 0.55, -1))
	else:
		player.set_intent(dx, false, false)
		_position_knob(Vector2(dx, 0))
	player.cancel_wrong_dig()
	return true


static func _any_key(keys: Array[Key]) -> bool:
	for k: Key in keys:
		if Input.is_key_pressed(k):
			return true
	return false


func set_camera(cam: Vector2) -> void:
	current_cam = cam

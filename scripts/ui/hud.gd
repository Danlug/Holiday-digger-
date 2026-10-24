extends Control
## HUD — весь интерфейс поверх игрового экрана (см. задание п.9): полоски
## HP/голод/усталость слева сверху, кошелёк справа сверху, глубина справа на
## уровне героя, нижняя однострочная полоса (инвентарь/инструмент/снаряжение/
## режим/сброс), шторка инвентаря, джойстик и подсказка режима удержания —
## обе ПОВЕРХ игрового экрана, а не отдельной панелью (портировано из
## web/index.html).

const TILE := 32
const STRIP_H := 40.0
const STRIP_BTN_W := 38.0   # кнопки нижней полосы одного размера, значки 32 (раньше: 34 с 16 и инструмент 38 с 32)
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
const PILL_W := 78.0    # ширина таблеток кошелька (монеты, доллары, вес)
const GAUGE_W := 62.0   # ширина полоски: правее остаётся место кошельку
var _xp_bar: HudBar
var _level_label: Label
var _hero_button: Button
var _hero_plus: TextureRect
var _hp_bar: HudBar
var _hunger_bar: HudBar
var _stamina_bar: HudBar
var _coins_pill: HudPill
var _dollars_pill: HudPill
var _shop_btn: Button   # «Магазин» под кошельком: подсказка и цифра роликов — ShopPlaceHint
var _load_pill: PanelContainer
var _load_bar: HudBar
var _clock_label: Label
var _clock_box: Control
var _purse_box: VBoxContainer
var _vignette: HpVignette
var _depth_box: Control
var _depth_label: Label
var _toast_panel: PanelContainer
var _toast_row: HBoxContainer
var _toast_timer: Timer
var _toast_tween: Tween
var _stick: Control
var _knob: Control
var _hold_hint: TextureRect

# --- третий режим: экранные стрелки ---
## Четыре кнопки, разнесённые по двум бортам (решение владельца): слева пара
## ◀ ▶ (шаг), справа пара ▲ ▼ (вверх/копка вниз) — каждая рука ведёт своей
## осью, как на геймпаде, а не тычет в одну кучку кнопок под одним пальцем.
## Диагональных кнопок нет и не было: ↖ и ↗ получаются одновременным
## удержанием ▲ и ◀/▶ — левая и правая рука жмут разные кнопки одновременно,
## это даже естественнее, чем было в кресте под одним пальцем. Без этого в
## режиме стрелок нельзя прыгнуть вперёд — а в двух других режимах можно, и
## одно и то же движение требовало бы разных навыков в зависимости от режима.
## Вниз по диагонали нет — копка всегда строго под собой (см. _apply_arrows).
##
## Стрелки РИСУЮТСЯ треугольниками (см. scripts/ui/arrow_icon.gd), а не
## пишутся символами: ↑ ← → ↓ (U+2190…U+2193) в шрифте темы по умолчанию
## отсутствуют и выходят пустыми квадратами с шестнадцатеричным кодом
## внутри — та же ловушка, что с ✕ и ↺, и та же, что была у кнопок хода в
## доме (house_view.gd) с ◀/▶. Вектор здесь — направление острия.
## "side"/"slot" — какой борт и какое место в паре (0 — первая/верхняя кнопка,
## 1 — вторая/нижняя), раскладку из них строит _layout_arrows.
const ARROW_CELLS: Array = [
	{"dir": "left", "side": "left", "slot": 0, "v": Vector2(-1, 0)},
	{"dir": "right", "side": "left", "slot": 1, "v": Vector2(1, 0)},
	{"dir": "up", "side": "right", "slot": 0, "v": Vector2(0, -1)},
	{"dir": "down", "side": "right", "slot": 1, "v": Vector2(0, 1)},
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
var _fuel_box: Control
var _well_panel: Control
var _objective_panel: PanelContainer
var _objective_label: Label
var _quest_button: Button
var _objective_text: String = ""
var _objective_hide_at_msec: float = 0.0

## Сколько секунд держать баннер задания, прежде чем свернуть его в кнопку.
const OBJECTIVE_SHOW_SECONDS := 6.0
var _tool_tip_token: int = 0
var _gear_pack: TextureRect
var _gear_jet: TextureRect
var _inv_button: Button
## id → узел, центр которого отдаёт get_anchor() (кошелёк, рюкзак, полоски…).
var _anchors: Dictionary = {}
## Шторка рюкзака (scripts/ui/backpack_sheet.gd): сетка слотов и окно «сколько».
var _inv_sheet: BackpackSheet
## Тестовая панель отладки (scripts/ui/debug_panel.gd) — НЕ для релиза
## игрокам, см. её собственный файл. Живёт отдельным классом, а не куском
## кода здесь, — не завязана на раскладку остального HUD, добавляется в
## HUD последней (см. _build_ui), поэтому видна и кликабельна поверх всего.
var _debug_panel: DebugPanel

## Шторка настроек (scripts/ui/settings_sheet.gd): звук/музыка, вибро, управление,
## радиус обзора, язык, восстановление покупок. Тот же приём full-screen шторки,
## что у рюкзака, — регуляторам (ползунки громкости) нужна ширина экрана, узкая
## popup-панель «•••» для них тесна.
var _settings_sheet: SettingsSheet


func _ready() -> void:
	# Группа "hud": по ней Fx.fly_to и пункты меню находят HUD, не зная его пути.
	add_to_group("hud")
	HudMenuEntries.register()
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


## Экранная позиция (проектные единицы вьюпорта) центра элемента HUD — её
## берёт Fx.fly_to, чтобы монеты и предметы летели ровно в кошелёк/рюкзак.
## id: "coins", "dollars", "backpack", "hp", "hunger", "stamina", "menu",
## "depth". Неизвестный id — центр экрана.
##
## Назван не get_anchor: у Control такой метод уже есть (get_anchor(Side) ->
## float), и GDScript не даёт его переопределить. Снаружи удобнее статический
## HudAnchors.get_anchor(id) — он сам находит HUD по группе "hud".
func anchor_of(id: String) -> Vector2:
	var node: Control = null
	match id:
		"backpack":
			node = _inv_button
		"menu":
			node = _more_button
		"depth":
			node = _depth_box
		_:
			node = _anchors.get(id, null)
	if id == "depth" and (node == null or not node.visible):
		return Vector2(size.x - 23.0, stage_rect.size.y * 0.4)
	if node == null or not is_instance_valid(node):
		return size * 0.5
	return node.get_global_rect().get_center()


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

	_vignette = HpVignette.new()
	_vignette.name = "HpVignette"
	stage.add_child(_vignette)
	_build_gauges(stage)
	_build_purse(stage)
	_build_depth(stage)
	_build_toast(stage)
	_build_stick(stage)
	_build_hold_hint(stage)
	_build_arrows(stage)
	_build_inventory_sheet(stage)
	_build_settings_sheet(stage)
	_build_strip()
	_build_debug_panel()


## Левый верхний угол: портрет героя (кнопка «Герой», уровень и опыт под ним)
## и справа от него три анимированные полоски — HP, голод, бодрость. Один
## кластер — потому что всё это про самого героя, и глазу не приходится
## собирать его состояние по разным углам экрана. Под ним — кнопка задания.
## Названия и числа полосок живут в подсказках (Tip), на экране — иконки.
func _build_gauges(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "Gauges"
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # кнопка «Герой» внутри
	box.position = Vector2(8, 8)
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	_gauges_box = box

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 5)
	box.add_child(top)

	_build_hero_button(top)

	var bars := VBoxContainer.new()
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_theme_constant_override("separation", 3)
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(bars)

	_hp_bar = _make_gauge(bars, Color8(0xD9, 0x4F, 0x4A), "hp", "hp")
	_hunger_bar = _make_gauge(bars, Color8(0xE8, 0x7E, 0x6E), "hunger", "hunger")
	_stamina_bar = _make_gauge(bars, Color8(0xE8, 0xC5, 0x47), "stamina", "stamina")

	_build_quest_button(box)


func _make_gauge(parent: Control, color: Color, icon_name: String, anchor_id: String) -> HudBar:
	var bar := HudBar.new().setup(color, UiIcons.tex(icon_name))
	bar.bar_width = GAUGE_W
	parent.add_child(bar)
	_anchors[anchor_id] = bar
	return bar


## Кнопка «Герой» — портрет-иконка. Уровень — значком в правом нижнем углу,
## опыт — тонкой полоской под кнопкой, непотраченные очки — зелёный «+» в
## правом верхнем углу, который покачивается: иначе игрок копит очки и не знает
## об этом (экран героя сам о себе не напоминает).
func _build_hero_button(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 3)
	parent.add_child(col)

	_hero_button = UiBtn.icon_button(UiIcons.tex("hero"), Vector2(36, 36), UiBtn.Kind.NORMAL, 32)
	_hero_button.pressed.connect(func():
		if Tip.swallowed():
			return
		Sfx.play("ui_open")
		ProgressScreen.open("progress"))
	Tip.bind(_hero_button, "Герой", "Прокачка, музей, рекорды")
	col.add_child(_hero_button)

	var lvl := PanelContainer.new()
	lvl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0xE0, 0xA9, 0x3B)
	sb.border_color = Color8(0x1A, 0x10, 0x0C)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	lvl.add_theme_stylebox_override("panel", sb)
	lvl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	lvl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lvl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lvl.offset_right = 4
	lvl.offset_bottom = 3
	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 9)
	_level_label.add_theme_color_override("font_color", Color8(0x1A, 0x10, 0x0C))
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.custom_minimum_size = Vector2(9, 0)
	lvl.add_child(_level_label)
	_hero_button.add_child(lvl)

	_hero_plus = TextureRect.new()
	_hero_plus.texture = UiIcons.tex("plus")
	_hero_plus.custom_minimum_size = Vector2(14, 14)
	_hero_plus.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_plus.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero_plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_plus.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hero_plus.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hero_plus.offset_right = 6
	_hero_plus.offset_top = -6
	_hero_plus.visible = false
	_hero_button.add_child(_hero_plus)

	_xp_bar = HudBar.new().setup(Color8(0xE0, 0xA9, 0x3B), null)
	_xp_bar.bar_h = 4.0
	_xp_bar.bar_width = 36.0
	col.add_child(_xp_bar)


## Кнопка задания под героем (решение владельца). Баннер задания висел на
## экране всё время — он закрывал треть огорода и переставал читаться уже на
## втором взгляде. Теперь новое задание показывается ненадолго и сворачивается
## сюда; нажатие разворачивает его обратно.
func _build_quest_button(parent: Control) -> void:
	_quest_button = UiBtn.icon_button(UiIcons.tex("quest"), Vector2(28, 24))
	_quest_button.visible = false
	Tip.bind(_quest_button, "Задание")
	_quest_button.pressed.connect(func():
		if Tip.swallowed():
			return
		_on_quest_button_pressed())
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_quest_button)
	parent.add_child(row)


## Кошелёк справа сверху: часы, монеты, доллары, вес рюкзака и витрина.
## Плашки-«таблетки» с иконкой и числом с накруткой; точные суммы и названия —
## в подсказках. Вес — полоска, которая краснеет и пульсирует на перегрузе.
func _build_purse(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "Purse"
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # кнопка «Магазин» внутри
	box.anchor_left = 1.0; box.anchor_right = 1.0
	box.offset_left = -110; box.offset_right = -8
	box.offset_top = 8
	box.add_theme_constant_override("separation", 3)
	parent.add_child(box)
	_purse_box = box

	# Часы (решение владельца, отчёт агента про "время не течёт во дворе"):
	# DayCycle.hour и раньше честно тикал на поверхности, но нигде не
	# показывался — без часов игрок не мог заметить, что время вообще идёт.
	# Источник — /root/DayCycle, тот же, что у домашних часов (house_view.gd);
	# слово «День N» — в подсказке.
	var clock := HBoxContainer.new()
	clock.mouse_filter = Control.MOUSE_FILTER_PASS
	clock.size_flags_horizontal = Control.SIZE_SHRINK_END
	clock.add_theme_constant_override("separation", 3)
	box.add_child(clock)
	var clock_icon := TextureRect.new()
	clock_icon.texture = UiIcons.tex("clock")
	clock_icon.custom_minimum_size = Vector2(12, 12)
	clock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	clock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	clock_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock_icon.modulate = Color(1, 1, 1, 0.75)
	clock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.add_child(clock_icon)
	_clock_label = Label.new()
	_clock_label.add_theme_color_override("font_color", Color8(0xB4, 0xA3, 0x88))
	_clock_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_clock_label.add_theme_constant_override("outline_size", 2)
	_clock_label.add_theme_font_size_override("font_size", 9)
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.add_child(_clock_label)
	_clock_box = clock

	_coins_pill = _make_pill(box, "coin", Color8(0xE0, 0xA9, 0x3B), "coins")
	_dollars_pill = _make_pill(box, "dollar", Color8(0x7F, 0xB8, 0x6B), "dollars")
	Tip.bind(_coins_pill, "Монеты")
	Tip.bind(_dollars_pill, "Доллары", "Премиум-валюта")
	# Три таблетки одной ширины: ровный правый и левый край столбика (раньше 72/64/58).
	_coins_pill.custom_minimum_size.x = PILL_W
	_dollars_pill.custom_minimum_size.x = PILL_W

	_load_pill = PanelContainer.new()
	_load_pill.add_theme_stylebox_override("panel", HudPill.pill_style(Color8(0x8F, 0xA3, 0x5C)))
	_load_pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	_load_pill.custom_minimum_size.x = PILL_W
	_load_pill.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_load_pill)
	_load_bar = HudBar.new().setup(Color8(0x7F, 0xB8, 0x6B), UiIcons.tex("weight"))
	_load_bar.bar_width = 48.0
	_load_bar.pulse_above = 1.0
	_load_pill.add_child(_load_bar)
	_load_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Tip.bind(_load_pill, "Рюкзак")

	# Кнопка «Магазин» под кошельком (решение владельца): премиум-витрина
	# открывается откуда угодно — и дома, и со дна шахты. Иконка-самоцвет, слово
	# «Магазин» — в подсказке.
	var shop_btn := UiBtn.icon_button(UiIcons.tex("shop"), Vector2(30, 24))
	shop_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	Tip.bind(shop_btn, "Магазин", "Премиум-витрина")
	shop_btn.pressed.connect(func():
		if Tip.swallowed():
			return
		ShopUI.open_premium())
	box.add_child(shop_btn)
	_shop_btn = shop_btn
	ShopPlaceHint.sync_button(_shop_btn)


func _make_pill(parent: Control, icon_name: String, color: Color, anchor_id: String) -> HudPill:
	var p := HudPill.new().setup(UiIcons.tex(icon_name), color)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	parent.add_child(p)
	_anchors[anchor_id] = p.icon_rect
	return p


## Индикатор глубины справа на уровне героя: «язычок» с иконкой и числом,
## прижатый к правому краю. Над землёй не показывается (ГДД п.16).
func _build_depth(parent: Control) -> void:
	var panel := PanelContainer.new()
	_depth_box = panel
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.071, 0.055, 0.043, 0.82)
	sb.border_color = Color8(0x52, 0x40, 0x2D)
	sb.set_border_width_all(1)
	sb.border_width_right = 0
	sb.corner_radius_top_left = ProgressUiKit.R_CARD
	sb.corner_radius_bottom_left = ProgressUiKit.R_CARD
	sb.content_margin_left = 5
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	parent.add_child(panel)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UiIcons.tex("depth")
	icon.custom_minimum_size = Vector2(12, 12)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	_depth_label = Label.new()
	_depth_label.add_theme_font_size_override("font_size", 12)
	_depth_label.add_theme_color_override("font_color", Color8(0xF2, 0xE6, 0xC8))
	_depth_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_depth_label.add_theme_constant_override("outline_size", 2)
	_depth_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_depth_label)
	_depth_box.visible = false


## Тост — «таблетка» над полосой по центру: иконка + число/слово, ширина по
## содержимому, выезжает и гаснет. Длинные фразы чужих систем (сюжет, дом) по-
## прежнему переносятся по словам, но панель всегда по размеру текста: раньше
## высота была двумя фиксированными числами, и многострочный тост обрезался
## снизу или вылезал за рамку (задание владельца: «фон контекстного окна не
## соответствует по высоте реальному размеру текста»). Низ панели стоит на месте
## (TOAST_BOTTOM_OFFSET), верх считается по фактической высоте — см. _place_toast.
const TOAST_BOTTOM_OFFSET := -132.0
const TOAST_MAX_W := 200.0      # шире не бывает: длинный текст переносится
const TOAST_PAD := Vector2(9, 5)
const TOAST_FONT := 12
const TOAST_COLORS := {
	"info": Color8(0xE0, 0xA9, 0x3B),
	"good": Color8(0x7F, 0xB8, 0x6B),
	"bad": Color8(0xD9, 0x4F, 0x4A),
	"rare": Color8(0xFF, 0xD0, 0x5A),
}


func _build_toast(parent: Control) -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.anchor_left = 0.5; _toast_panel.anchor_right = 0.5
	_toast_panel.anchor_top = 1.0; _toast_panel.anchor_bottom = 1.0
	_toast_panel.visible = false
	parent.add_child(_toast_panel)

	_toast_row = HBoxContainer.new()
	_toast_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_row.add_theme_constant_override("separation", 5)
	_toast_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_toast_panel.add_child(_toast_row)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(_hide_toast)
	add_child(_toast_timer)


func _build_stick(parent: Control) -> void:
	_stick = Control.new()
	_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick.custom_minimum_size = Vector2(stick_r * 2, stick_r * 2)
	_stick.draw.connect(func():
		# Плоское «стекло» с золотистым ободком и засечками по сторонам света:
		# видно, где центр и куда тянуть.
		var c := Vector2(stick_r, stick_r)
		_stick.draw_circle(c, stick_r, Color(0.09, 0.07, 0.05, 0.5))
		_stick.draw_arc(c, stick_r - 1.0, 0, TAU, 48, Color(0.82, 0.66, 0.38, 0.55), 2.0)
		_stick.draw_arc(c, stick_r * 0.5, 0, TAU, 32, Color(0.82, 0.66, 0.38, 0.16), 1.0)
		for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			_stick.draw_circle(c + dir * (stick_r - 6.0), 1.4, Color(0.82, 0.66, 0.38, 0.55))
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
		var c := Vector2(knob_r, knob_r)
		var rim := Color8(0xE0, 0xA9, 0x3B) if live else Color8(0xB8, 0xA3, 0x84)
		_knob.draw_circle(c + Vector2(0, 1.5), knob_r, Color(0, 0, 0, 0.4))
		_knob.draw_circle(c, knob_r, Color8(0x3A, 0x2C, 0x20))
		_knob.draw_circle(c, knob_r - 2.5, rim.darkened(0.35))
		_knob.draw_arc(c, knob_r - 1.0, 0, TAU, 32, rim, 2.0)
		_knob.draw_arc(c, knob_r * 0.55, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.45), 1.5)
	)
	_stick.add_child(_knob)


func hold_active() -> bool:
	return player != null and (player.hold_dx != 0 or player.hold_up or player.hold_down)


## Подсказка режима «нажатия»: вместо абзаца текста — иконка руки с «кругом»
## от касания. При включении режима пульсирует несколько секунд, потом
## остаётся бледным напоминанием; слова — в подсказке Tip. «Зажми экран в
## нужную сторону — герой пойдёт туда и будет копать. Отпустил — остановился.»
func _build_hold_hint(parent: Control) -> void:
	_hold_hint = TextureRect.new()
	_hold_hint.texture = UiIcons.tex("ctl_hold")
	_hold_hint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hold_hint.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hold_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	_hold_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hold_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hold_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hold_hint.offset_left = -16
	_hold_hint.offset_right = 16
	_hold_hint.offset_top = -48
	_hold_hint.offset_bottom = -16
	_hold_hint.pivot_offset = Vector2(16, 16)
	_hold_hint.visible = false
	Tip.bind(_hold_hint, "Зажми экран", "Герой идёт и копает туда, где палец. Отпустил — остановился")
	parent.add_child(_hold_hint)


## Показывает подсказку режима: яркий пульс, затем бледный значок.
func _flash_hold_hint() -> void:
	if _hold_hint == null:
		return
	_hold_hint.visible = true
	_hold_hint.modulate.a = 1.0
	_hold_hint.scale = Vector2.ONE
	if Settings.reduce_motion or not _hold_hint.is_inside_tree():
		_hold_hint.modulate.a = 0.5
		return
	var tw := _hold_hint.create_tween()
	for i in 3:
		tw.tween_property(_hold_hint, "scale", Vector2.ONE * 1.25, 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_hold_hint, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_hold_hint, "modulate:a", 0.35, 0.6)


## Экранные стрелки — третий режим управления (решение владельца). Слева
## внизу — ◀ ▶ (левая рука ведёт шаг), справа внизу — ▲ ▼ (правая рука ведёт
## вверх/копку вниз, там же, где в двух других режимах живёт джойстик — рука
## не переучивается при переключении режима).
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
		# Плитки в общем стиле, но без звука: стрелки держат намерение, а не
		# «нажимают» — «ui_tap» на каждый шаг был бы шумом. Вибро — на касании.
		UiBtn.style(b, UiBtn.Kind.NORMAL, false)
		b.button_down.connect(Haptics.tap)
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


## Две пары кнопок на разных бортах экрана, а не одна сетка под одним
## пальцем: ◀▶ горизонтально слева (там же, куда в режиме "палец" ложится
## подсказка удержания), ▲▼ вертикально справа — на месте джойстика, чтобы
## рука не переучивалась при переключении режима. Вертикальная стопка у
## правого борта уже горизонтальной пары вдвое — при ширине экрана в 224px
## это меньше мешает кнопке инструмента/«•••»/индикатору топлива в нижней
## полосе (она отдельная лента под stage_rect, но узкий правый борт всё равно
## оставляет им больше воздуха, чем широкая сетка).
func _layout_arrows() -> void:
	if _arrows_panel == null or _arrow_buttons.is_empty():
		return
	_arrows_panel.position = Vector2.ZERO
	_arrows_panel.size = Vector2(size.x, stage_rect.size.y)
	var cell_size: float = maxf(22.0, stick_r * 0.66)
	var gap := 3.0
	var margin := 12.0
	# Левый борт: ◀ ▶ рядом по горизонтали.
	var left_origin := Vector2(margin, stage_rect.size.y - margin - cell_size)
	# Правый борт: ▲ над ▼, столбиком — там же, где в других режимах джойстик.
	var right_h: float = cell_size * 2.0 + gap
	var right_origin := Vector2(size.x - margin - cell_size, stage_rect.size.y - margin - right_h)
	for cell in ARROW_CELLS:
		var b: Button = _arrow_buttons[String(cell["dir"])]
		b.custom_minimum_size = Vector2(cell_size, cell_size)
		b.size = Vector2(cell_size, cell_size)
		var slot: float = float(cell["slot"])
		if String(cell["side"]) == "left":
			b.position = left_origin + Vector2(slot * (cell_size + gap), 0.0)
		else:
			b.position = right_origin + Vector2(0.0, slot * (cell_size + gap))
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
	_inv_sheet = BackpackSheet.new()
	_inv_sheet.name = "Backpack"
	_inv_sheet.eat_pressed.connect(_eat_from_inventory)
	_inv_sheet.drop_confirmed.connect(_on_drop_confirmed)
	_inv_sheet.closed.connect(func(): _inv_button.button_pressed = false)
	parent.add_child(_inv_sheet)


# ---------------------------------------------------------------------------
# Настройки (Settings — scripts/core/settings.gd): шторка SettingsSheet
# (scripts/ui/settings_sheet.gd) — звук, музыка, вибро, управление, язык.
# ---------------------------------------------------------------------------

func _build_settings_sheet(parent: Control) -> void:
	_settings_sheet = SettingsSheet.new()
	_settings_sheet.name = "Settings"
	_settings_sheet.mode_chosen.connect(_set_mode)
	_settings_sheet.restore_pressed.connect(func():
		toast_icon("restore", "Покупок нет", 2.2))
	parent.add_child(_settings_sheet)


## Перечитывает Settings и красит все контролы шторки.
func _refresh_settings_panel() -> void:
	if _settings_sheet != null:
		_settings_sheet.refresh()


func open_settings() -> void:
	close_more_menu()
	_settings_sheet.open()


func close_settings() -> void:
	_settings_sheet.close()


func is_settings_open() -> bool:
	return _settings_sheet != null and _settings_sheet.visible


## Окно «выбросить N штук» живёт в BackpackSheet; здесь — его прежние имена.
func _open_drop(id: String, count: int) -> void:
	_inv_sheet.open_drop(id, count)


func _close_drop() -> void:
	_inv_sheet.close_drop()


func _on_drop_confirmed(id: String, n: int) -> void:
	GameState.remove_item(id, n)
	_inv_sheet.refresh()
	_sync_purse()
	toast_parts([
		{"icon_tex": UiIcons.item_small(id), "text": "−%d" % n, "color": Color8(0xE8, 0x8C, 0x80)},
	], 1.6)


var _more_panel: PanelContainer
var _more_grid: GridContainer
var _more_button: Button
var _more_closing: bool = false   # меню гаснет (анимация): по смыслу уже закрыто
var _menu_badge_timer: float = 0.0
var _menu_armed_id: String = ""
var _menu_armed_until_msec: int = 0


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
	sb.border_color = ProgressUiKit.EDGE
	sb.border_width_top = 2
	var bg_panel := Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_panel.add_theme_stylebox_override("panel", sb)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg_panel)

	var strip := HBoxContainer.new()
	strip.name = "Row"
	strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	strip.offset_left = 5
	strip.offset_right = -5
	strip.offset_top = 3
	strip.offset_bottom = -1
	strip.add_theme_constant_override("separation", 3)
	root.add_child(strip)

	# Систем стало пять, и каждая честно попросила себе кнопку — в ряду
	# шириной 224 их девять, а нужно им около 315. Ряд делится по тому,
	# нужна ли кнопка ВО ВРЕМЯ КОПКИ: инвентарь, склад, инструмент и
	# снаряжение остаются на виду, всё остальное уходит под «•••». Прятать
	# по важности, а не по алфавиту: игрок сидит в шахте, а не в меню.
	_build_more_menu()
	_build_objective_line()

	# Только иконки: слова («Инвентарь», «Склад», название инструмента) — в
	# подсказке Tip. Кнопка рюкзака — переключатель: при открытой шторке она
	# «вдавлена» и подсвечена золотом.
	_inv_button = UiBtn.icon_button(UiIcons.tex("backpack"), Vector2(STRIP_BTN_W, 36), UiBtn.Kind.NORMAL, 32)
	Tip.bind(_inv_button, "Рюкзак", "Что несёшь и сколько это стоит")
	_inv_button.toggle_mode = true
	_inv_button.pressed.connect(_on_inv_button_pressed)
	strip.add_child(_inv_button)

	# Инструмент — одна иконка без подписи, чуть крупнее остальных: это то, чем
	# копают. Название всплывает НАД полосой по нажатию (и при наведении на
	# компьютере), и само — когда инструмент сменился (ГДД п.16).
	_tool_button = UiBtn.icon_button(null, Vector2(STRIP_BTN_W, 36), UiBtn.Kind.NORMAL, 32)
	_tool_button.pressed.connect(func():
		if Tip.swallowed():
			return
		_show_tool_name())
	strip.add_child(_tool_button)

	# Брикеты топлива — иконка и число рядом с инструментом. Спрятан, пока
	# бурмобиль не надет: у остальных инструментов топлива нет, и пустое место
	# на полосе шириной 224 только крало бы пространство зря.
	_fuel_box = HBoxContainer.new()
	_fuel_box.add_theme_constant_override("separation", 1)
	_fuel_box.visible = false
	_fuel_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_fuel_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fuel_icon := TextureRect.new()
	fuel_icon.texture = UiIcons.tex("fuel")
	fuel_icon.custom_minimum_size = Vector2(14, 14)
	fuel_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fuel_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fuel_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuel_box.add_child(fuel_icon)
	_fuel_label = Label.new()
	_fuel_label.add_theme_font_size_override("font_size", 11)
	_fuel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuel_box.add_child(_fuel_label)
	Tip.bind(_fuel_box, "Топливо", "Брикеты угля для бурмобиля")
	strip.add_child(_fuel_box)

	var gear_box := HBoxContainer.new()
	gear_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_pack = _make_gear_icon(gear_box, "")
	_gear_jet = null
	strip.add_child(gear_box)

	# Пустая распорка: слева — то, чем копают, справа — куда ходят.
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(spacer)

	# Мастерская, режим управления, настройки и сброс живут в реестре меню
	# (scripts/ui/menu_entries.gd), а не в полосе.

	# --- дом (scripts/house/) ---
	# Контекстной кнопки «Дом» на полосе больше нет: дом — пространство, и
	# «Зайти» всплывает над героем у окна веранды (HouseSystem).
	# Склад (ГДД п.14) виден ОТКУДА УГОДНО, хоть со дна шахты, — но только
	# на просмотр: игрок должен планировать вылазку, зная, чего не хватает до
	# кирки. Поэтому кнопка постоянная, а не контекстная. Нажатие подключает
	# сама система дома по группе "house_storage_button".
	var storage_btn := UiBtn.icon_button(UiIcons.tex("inventory"), Vector2(STRIP_BTN_W, 36), UiBtn.Kind.NORMAL, 32)
	Tip.bind(storage_btn, "Склад", "В мастерской: можно смотреть откуда угодно")
	storage_btn.add_to_group("house_storage_button")
	strip.add_child(storage_btn)
	# --- конец блока дома ---

	# «•••» встаёт последним, чтобы контекстная кнопка дома, появляясь и
	# исчезая, не сдвигала его под пальцем. Красный бейдж — сумма бейджей
	# пунктов меню (новые задания и т.п.).
	_more_button = UiBtn.icon_button(UiIcons.tex("more"), Vector2(STRIP_BTN_W, 36), UiBtn.Kind.NORMAL, 32)
	Tip.bind(_more_button, "Меню")
	_more_button.pressed.connect(func():
		if Tip.swallowed():
			return
		_toggle_more_menu())
	strip.add_child(_more_button)

	# Схема управления — сохранённая настройка игрока (Settings.control_mode),
	# а не всегда "stick" по умолчанию (задание владельца: «Управление —
	# джойстик, стрелки, нажатия» в панели настроек).
	_set_mode(Settings.control_mode if Settings.control_mode in MODES else "stick")


## Тестовая панель отладки (scripts/ui/debug_panel.gd) — добавляется в HUD
## САМОЙ ПОСЛЕДНЕЙ (после основной нижней полосы), поэтому её триггер рисуется
## и кликается поверх всего остального. Не в общей нижней полосе (задание
## владельца: там уже инструмент/«•••»/топливо, и рядом другой агент двигает
## стрелки по бокам) — свой маленький триггер «Тест» стоит НАД полосой слева,
## зеркально «•••» справа, и раскрывается вверх, не занимая места, пока закрыт.
##
## Релиз-гейт (задание владельца, релиз-харденинг 2026-09-21): панель даёт
## бесплатные монеты/бессмертие/телепорт/мгновенную копку — реальный игрок
## никогда не должен её увидеть. OS.has_feature("debug") истинно в редакторе
## и debug-экспортах (в том числе headless-тестах — годо-бинарь без шаблонов
## релиза сам по себе debug), и ложно в release-экспорте (App Store/Google
## Play). Поэтому в release-сборке _debug_panel остаётся null — единственное
## место, где на неё ссылаются (_input ниже), уже проверяет на null.
func _build_debug_panel() -> void:
	if not OS.has_feature("debug"):
		return
	_debug_panel = DebugPanel.new()
	_debug_panel.name = "DebugPanel"
	add_child(_debug_panel)


## Меню «•••»: плитки-иконки из реестра MenuRegistry (мастерская, настройки,
## задания, достижения…) — каждая подсистема кладёт свой пункт у себя, а HUD
## их не знает. Название и описание — в подсказке Tip, на плитке только
## иконка и красный бейдж.
##
## Всплывает НАД полосой и прижато к правому краю, к своей кнопке. Пока оно
## открыто, ввод в мир глушится (см. _input и update_input_intent) — иначе
## палец, метящий в пункт меню, попадает в джойстик под ним и герой копает
## под открытым меню. Собирается заново при каждом открытии: подсистемы
## регистрируются позже HUD, а видимость и бейджи меняются по ходу игры.
func _build_more_menu() -> void:
	_more_panel = PanelContainer.new()
	_more_panel.name = "MoreMenu"
	_more_panel.visible = false
	_more_panel.add_theme_stylebox_override("panel",
		ProgressUiKit.popup_box(ProgressUiKit.EDGE, Color8(0x1A, 0x14, 0x0F, 0xF5), 5))
	_more_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	add_child(_more_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_more_panel.add_child(box)

	_more_grid = GridContainer.new()
	_more_grid.add_theme_constant_override("h_separation", 4)
	_more_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_more_grid)

	# Метка сборки. Владелец несколько раз открывал игру и не видел изменений,
	# и по переписке нельзя было отличить «раздача отстала» от «браузер отдал
	# старую копию из кэша». Версия видна в меню, и один взгляд отвечает на
	# вопрос. Пишется tools/make_build_info.py перед экспортом.
	var build_label := Label.new()
	build_label.text = _build_stamp()
	build_label.add_theme_font_size_override("font_size", 8)
	build_label.add_theme_color_override("font_color", Color8(0x86, 0x76, 0x60))
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(build_label)


func _rebuild_more_menu() -> void:
	for c in _more_grid.get_children():
		_more_grid.remove_child(c)
		c.queue_free()
	_menu_armed_id = ""
	var entries := MenuRegistry.entries()
	_more_grid.columns = 3 if entries.size() <= 6 else 4
	for e: Dictionary in entries:
		_more_grid.add_child(_make_menu_button(e))
	_place_more_panel()


## Прижимает меню к правому нижнему углу над полосой. Смещения считаем сами по
## минимальному размеру: reset_size() сбивает направление роста у якорей.
func _place_more_panel() -> void:
	var sz := _more_panel.get_combined_minimum_size()
	_more_panel.offset_right = -4.0
	_more_panel.offset_left = -4.0 - sz.x
	_more_panel.offset_bottom = -STRIP_H - 2.0
	_more_panel.offset_top = -STRIP_H - 2.0 - sz.y
	_more_panel.pivot_offset = sz


func _make_menu_button(e: Dictionary) -> Button:
	var id := String(e["id"])
	var confirm := bool(e.get("confirm", false))
	var b := UiBtn.icon_button(MenuRegistry.icon_of(e), Vector2(30, 30),
		UiBtn.Kind.DANGER if confirm else UiBtn.Kind.NORMAL)
	Tip.bind(b, MenuRegistry.text_of(e, "title"), MenuRegistry.text_of(e, "body"))
	UiBtn.set_badge(b, MenuRegistry.badge_of(e))
	b.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		# Опасный пункт срабатывает со второго нажатия в течение трёх секунд.
		if confirm and not (_menu_armed_id == id and Time.get_ticks_msec() < _menu_armed_until_msec):
			_menu_armed_id = id
			_menu_armed_until_msec = Time.get_ticks_msec() + 3000
			b.modulate = Color(1.0, 0.7, 0.65)
			Tip.set_text(b, MenuRegistry.text_of(e, "title"), "Нажми ещё раз — точно сбросить")
			Tip.show_now(b)
			Haptics.buzz(30)
			Sfx.play("ui_toggle")
			return
		close_more_menu()
		var cb = e.get("on_press", null)
		if cb is Callable:
			(cb as Callable).call())
	return b


## Всплывающая отметка над выкопанной клеткой: иконка предмета и «+1». Живёт
## секунду, поднимается и тает. Это не тост: тост — «таблетка» у полосы, а тут
## нужна отметка ровно там, где копнули, — иначе на каждую клетку земли экран
## мигал бы плашкой.
func float_item(cell_x: int, cell_y: int, mineral_id: String, count: int = 1) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 2)
	var icon := TextureRect.new()
	icon.texture = UiIcons.item(mineral_id)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := Label.new()
	label.text = "+%d" % count
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color8(0xF5, 0xD0, 0x6B))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	add_child(row)
	_float_away(row, cell_x, cell_y, Vector2(row.get_combined_minimum_size().x * 0.5, 0.0))


## То же, но текстом — для тех, кто зовёт старое имя float_pickup.
func float_pickup(cell_x: int, cell_y: int, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color8(0xE0, 0xA9, 0x3B))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80, 14)
	add_child(label)
	_float_away(label, cell_x, cell_y, Vector2(40.0, 0.0))


func _float_away(node: Control, cell_x: int, cell_y: int, half: Vector2) -> void:
	var from := Vector2(
		(float(cell_x) + 0.5 - current_cam.x) * TILE - half.x,
		(float(cell_y) - current_cam.y) * TILE - 6.0)
	node.position = from
	if Settings.reduce_motion:
		get_tree().create_timer(0.6).timeout.connect(node.queue_free)
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "position:y", from.y - 18.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tween.chain().tween_callback(node.queue_free)


## Отчёт скважины при возвращении в игру (решение владельца): показать, что
## накопала за время отсутствия. Окно рисует ветка «Техника»
## (scripts/tech/well_report.gd): плитки-иконки, ссыпание на склад, «×2».
func show_well_report(report: Dictionary) -> void:
	var w := get_tree().get_first_node_in_group("well_report")
	if w != null and not report.is_empty():
		w.call("show_report", report)


func close_well_report() -> void:
	var w := get_tree().get_first_node_in_group("well_report")
	if w != null:
		w.call("close")


## «45 мин», «2 ч» — коротко, для плашки отчёта.
static func _humanize_short(seconds: float) -> String:
	var total := int(seconds)
	var h := total / 3600
	var m := (total % 3600) / 60
	if h > 0:
		return "%d ч" % h if m == 0 else "%d:%02d" % [h, m]
	return "%d мин" % maxi(m, 1)


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
	var sb := ProgressUiKit.popup_box(ProgressUiKit.GOLD, Color(0.071, 0.055, 0.043, 0.94))
	sb.content_margin_left = 7
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_objective_panel.add_theme_stylebox_override("panel", sb)
	_objective_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_objective_panel.offset_left = 8
	_objective_panel.offset_right = -8
	add_child(_objective_panel)
	_place_objective()

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	_objective_panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UiIcons.tex("quest")
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", 10)
	_objective_label.add_theme_color_override("font_color", Color8(0xF2, 0xD9, 0x9B))
	_objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_objective_label)


## Строка задания встаёт ПОД обоими верхними кластерами (герой с полосками слева,
## кошелёк справа), а не на фиксированной высоте: левый столбик то появляется
## целиком, то исчезает на время обучения, и жёсткая координата либо накрывала
## полоски, либо висела в пустоте. Высоту берём минимальную — она известна до
## раскладки.
func _place_objective() -> void:
	if _objective_panel == null:
		return
	var top := 12.0
	if _purse_box != null:
		top = _purse_box.position.y + _purse_box.get_combined_minimum_size().y + 6.0
	if _gauges_box != null and _gauges_box.visible:
		top = maxf(top, _gauges_box.position.y + _gauges_box.get_combined_minimum_size().y + 6.0)
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
	if _quest_button != null:
		_quest_button.visible = true
	_show_objective_banner()


func _show_objective_banner() -> void:
	if _objective_panel == null or _objective_text.is_empty():
		return
	_objective_panel.visible = true
	_objective_hide_at_msec = Time.get_ticks_msec() + OBJECTIVE_SHOW_SECONDS * 1000.0
	_place_objective()
	UiAnim.appear(_objective_panel, UiAnim.POP_FROM, UiAnim.D_IN)


func _on_quest_button_pressed() -> void:
	# Повторное нажатие сворачивает: кнопка — переключатель, а не «показать
	# ещё раз», иначе баннер нечем убрать досрочно.
	if _objective_panel != null and _objective_panel.visible:
		_objective_panel.visible = false
		return
	_show_objective_banner()


## Название инструмента — подсказкой Tip над кнопкой: по нажатию и само, когда
## инструмент сменился. Гаснет через пару секунд. Отдельной панельки для одного
## слова больше нет: «Лопата» — это подсказка, а не элемент экрана.
func _show_tool_name() -> void:
	if _tool_button == null or not _tool_button.is_inside_tree():
		return
	Tip.show_now(_tool_button)
	_tool_tip_token += 1
	var token := _tool_tip_token
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if token == _tool_tip_token and Tip.is_showing():
			Tip.hide_all())


func _toggle_more_menu() -> void:
	if is_more_menu_open():
		close_more_menu()
		return
	_rebuild_more_menu()
	_more_closing = false
	_more_panel.visible = true
	UiAnim.open(_more_panel, UiAnim.Kind.POP)
	_more_panel.pivot_offset = _more_panel.get_combined_minimum_size()
	Sfx.play("ui_open")
	# Иначе палец, уже «зажавший» мир, остаётся зажатым под открытым меню:
	# в режиме стика — ручка, в режиме пальца — удержание.
	_release_stick()
	_touch_pointer = -100
	_has_touch = false
	if player != null:
		player.release_control()
		player.digging = null


func close_more_menu() -> void:
	if _more_panel != null and _more_panel.visible and not _more_closing:
		Sfx.play("ui_close")
		_more_closing = true
		UiAnim.close(_more_panel, UiAnim.Kind.POP, null, func() -> void: _more_closing = false)


func is_more_menu_open() -> bool:
	return _more_panel != null and _more_panel.visible and not _more_closing


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
	return UiBtn.style(b)


# Кнопка-иконка без рамки: рамка обещает нажатие, которое что-то переключит,
# а подпись по нажатию всего лишь называет себя.
func _make_flat(b: Button) -> Button:
	return UiBtn.style(b, UiBtn.Kind.GHOST)


func _make_gear_icon(parent: Control, path: String) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(20, 20)
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
	_update_clock()
	_menu_badge_timer -= _dt
	if _menu_badge_timer <= 0.0:
		_menu_badge_timer = 0.5
		_sync_menu_badge()


## Красный бейдж на «•••» — сумма бейджей пунктов меню: новые задания, награды
## и т.п. видны, не раскрывая меню.
func _sync_menu_badge() -> void:
	ShopPlaceHint.sync_button(_shop_btn)   # правило «где можно покупать»: подсказка и остаток роликов
	if _more_button == null:
		return
	var total := 0
	for e: Dictionary in MenuRegistry.entries():
		total += MenuRegistry.badge_of(e)
	UiBtn.set_badge(_more_button, total)


func _connect_game_state() -> void:
	GameState.hp_changed.connect(func(hp, max_hp): _sync_hp(hp, max_hp))
	GameState.hunger_changed.connect(func(h): _sync_gauge(_hunger_bar, h / 100.0, "Голод", h))
	GameState.stamina_changed.connect(func(st): _sync_gauge(_stamina_bar, st / 100.0, "Бодрость", st))
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
	# Апгрейд бура (задача «Апгрейд бура»): смена тира не трогает
	# current_tool, поэтому GameState.tool_changed не сработает — своя точка.
	GameState.drill_rig_tier_changed.connect(func(_tier): _sync_tool())
	GameState.rig_dismount_blocked.connect(func(_id):
		# Бурмобиль под землёй не бросить — сначала наверх: машина и стрелка вверх.
		toast_parts([
			{"icon_tex": load("res://art/items/drill_rig_icon.png"), "icon_px": 24},
			{"icon": "arrow_up"},
		], 2.4, "bad")
		Sfx.play("ui_deny"))
	GameState.xp_changed.connect(func(_xp, _lvl): _sync_xp())
	GameState.leveled_up.connect(func(lvl, pts):
		_sync_xp()
		toast_parts([
			{"icon": "star"}, {"text": str(lvl), "color": TOAST_COLORS["rare"]},
			{"icon": "plus"}, {"text": "+%d" % pts, "color": Color8(0xB4, 0xE0, 0x9C)},
		], 2.6, "rare"))
	GameState.survival_warning.connect(_on_survival_warning)
	GameState.respawned.connect(func(): _sync_all())
	GameState.exhausted_changed.connect(func(on: bool):
		if on:
			toast_parts([{"icon": "stamina"}, {"text": "−50%", "color": Color8(0xE8, 0x8C, 0x80)}], 2.4, "bad"))
	GameState.skill_points_changed.connect(func(_p): _sync_hero_button())


func _sync_all() -> void:
	_sync_hp(GameState.hp, GameState.get_max_hp(), true)
	_sync_gauge(_hunger_bar, GameState.hunger / 100.0, "Голод", GameState.hunger, true)
	_sync_gauge(_stamina_bar, GameState.stamina / 100.0, "Бодрость", GameState.stamina, true)
	_sync_xp()
	_sync_hero_button()
	_sync_purse(true)
	_sync_fuel()
	_sync_tool()


## Полоска + подсказка с числом. Текст подсказки обновляем только когда
## меняется целая часть: голод и бодрость сигналят каждый тик.
func _sync_gauge(bar: HudBar, frac: float, title: String, value: float, instant: bool = false) -> void:
	if bar == null:
		return
	bar.set_fraction(frac, instant)
	var iv := int(round(value))
	if int(bar.get_meta(&"_iv", -1)) != iv:
		bar.set_meta(&"_iv", iv)
		Tip.bind(bar, title, "%d%%" % iv)


func _sync_hp(hp: float, max_hp: float, instant: bool = false) -> void:
	if _hp_bar == null:
		return
	var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var prev := _hp_bar.fraction()
	_hp_bar.set_fraction(frac, instant)
	var iv := int(ceil(hp))
	if int(_hp_bar.get_meta(&"_iv", -1)) != iv:
		_hp_bar.set_meta(&"_iv", iv)
		Tip.bind(_hp_bar, "Здоровье", "%d / %d" % [iv, int(max_hp)])
	if _vignette != null:
		_vignette.set_level(frac)
	if not instant and frac < prev - 0.001:
		UiAnim.shake(_gauges_box, 2.5, 0.22)


func _sync_xp() -> void:
	if _xp_bar == null:
		return
	var need: float = float(Balance.xp_required_for_level(GameState.level))
	var frac: float = clampf(float(GameState.xp) / maxf(need, 1.0), 0.0, 1.0)
	var new_level := str(GameState.level)
	var first := _level_label.text == ""
	var leveled := not first and _level_label.text != new_level
	_level_label.text = new_level
	_xp_bar.set_fraction(frac, first or leveled)
	Tip.bind(_xp_bar, "Опыт", "Уровень %d: %d / %d" % [GameState.level, GameState.xp, int(need)])
	if leveled:
		UiAnim.pulse(_hero_button, 0.3, 0.4)
	_sync_hero_button()


## Есть непотраченные очки — зелёный «+» над портретом, он покачивается: без
## этого игрок копит очки и не знает об этом.
func _sync_hero_button() -> void:
	if _hero_button == null:
		return
	var points := GameState.skill_points_available
	var had := _hero_plus.visible
	_hero_plus.visible = points > 0
	Tip.bind(_hero_button, "Герой", "Уровень %d. Очков прокачки: %d" % [GameState.level, points] \
		if points > 0 else "Уровень %d. Прокачка, музей, рекорды" % GameState.level)
	if points > 0 and not had and not Settings.reduce_motion and _hero_plus.is_inside_tree():
		var tw := _hero_plus.create_tween().set_loops()
		tw.tween_property(_hero_plus, "position:y", _hero_plus.position.y - 2.0, 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_hero_plus, "position:y", _hero_plus.position.y, 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_hero_plus.set_meta(&"_bob", tw)
	elif points <= 0 and _hero_plus.has_meta(&"_bob"):
		var old = _hero_plus.get_meta(&"_bob")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		_hero_plus.remove_meta(&"_bob")


## Единственный источник правды о часе — DayCycle (см. scripts/core/
## day_cycle.gd и house_view.gd:_refresh_header, тот же узел — часы снаружи и в
## доме обязаны показывать одно и то же время). На экране «ЧЧ:ММ», «День N» —
## в подсказке.
func _update_clock() -> void:
	if _clock_label == null:
		return
	var day_cycle := get_node_or_null("/root/DayCycle")
	var day: int = day_cycle.day if day_cycle != null else 1
	var hour_f: float = day_cycle.hour if day_cycle != null else 6.0
	var hour := int(hour_f)
	var minute := int((hour_f - floor(hour_f)) * 60.0)
	var t := "%02d:%02d" % [hour, minute]
	if _clock_label.text != t:
		_clock_label.text = t
		Tip.bind(_clock_box, "День %d" % day)


func _sync_purse(instant: bool = false) -> void:
	_coins_pill.set_value(GameState.coins, instant)
	_dollars_pill.set_value(GameState.dollars, instant)
	Tip.bind(_coins_pill, "Монеты", CountLabel.group_digits(GameState.coins))
	Tip.bind(_dollars_pill, "Доллары", CountLabel.group_digits(GameState.dollars) + " · премиум-валюта")
	var load_kg := GameState.get_total_weight()
	var max_kg := maxf(GameState.get_max_carry_kg(), 0.001)
	var frac := load_kg / max_kg
	_load_bar.set_fraction(minf(frac, 1.0), instant)
	# Зелёный -> янтарь -> красный: тот же красный, что у перегруза в остальных экранах.
	_load_bar.fill_color = Color8(0x7F, 0xB8, 0x6B) if frac < 0.6 \
		else (Color8(0xE0, 0xA9, 0x3B) if frac < 0.85 else Color8(0xD9, 0x4F, 0x4A))
	Tip.bind(_load_pill, "Рюкзак", "%.1f / %.0f кг" % [load_kg, max_kg])


func _sync_tool() -> void:
	var tool_id := GameState.current_tool
	var tool_name := Balance.get_tool_name_ru(tool_id)
	Tip.bind(_tool_button, tool_name)
	var icon_path := _tool_icon_path(tool_id)
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		_tool_button.icon = load(icon_path)
		_tool_button.text = ""
	else:
		# Без картинки кнопка была бы пустым прямоугольником — тогда пусть
		# уж подписью, как раньше.
		_tool_button.text = tool_name
	_sync_gear_icon()
	_sync_fuel()


## Индикатор брикетов: виден только когда бурмобиль надет. Красный на нуле —
## того же цвета, что перегруз рюкзака (BAD в остальных экранах), чтобы
## тревожный цвет читался одинаково по всему интерфейсу.
func _sync_fuel() -> void:
	if _fuel_label == null:
		return
	# Топливо теперь в баке и показывает его значок ветки «Техника» (TechHud);
	# число блоков в рюкзаке — не то, чем копает бур.
	_fuel_box.visible = false


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
	Tip.bind(_gear_pack, Balance.get_gear_name_ru(gear_id), "Снаряжение")
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
	path = path if path.begins_with("res://") else "res://" + path
	# Апгрейд бура (задача «Апгрейд бура»): та же подмена по суффиксу, что у
	# анимаций бурмобиля в character_view.gd (_rig_tier_suffix) — тот же тир,
	# то же имя файла + суффикс. Состояние героя (тир), а не данные
	# инструмента, поэтому решается здесь же, рядом с трещиной ржавой кирки
	# выше — обе подмены одной формы: "обычная иконка -> иконка под текущее
	# состояние, если файл для него есть".
	if tool_id == "drill_rig" and GameState.drill_rig_tier > 0:
		var suffixes: Array = ["", "_titanium", "_platinum", "_diamond", "_obsidian"]
		var suffix: String = suffixes[clampi(GameState.drill_rig_tier, 0, 4)]
		var tiered: String = path.get_basename() + suffix + "." + path.get_extension()
		if ResourceLoader.exists(tiered):
			return tiered
	return path


func _update_depth() -> void:
	var d: int = player.cell_y()
	if d <= 0:
		_depth_box.visible = false
		return
	_depth_box.visible = true
	_depth_label.text = str(d)
	# см. placeDepth в web-демо: метка стоит на уровне героя на экране.
	var screen_y: float = (player.y - current_cam.y) * TILE
	var h := _depth_box.size.y
	# Плашка на две клетки выше героя: на его уровне она закрывала монстров, подходящих справа.
	_depth_box.position.y = clampf(screen_y - h * 0.5 - 2.0 * TILE, 116.0, stage_rect.size.y - h)


# ---------------------------------------------------------------------------
# Тосты
# ---------------------------------------------------------------------------

## Текстовый тост. Совместим со старым API: текст, секунды. Короткие тосты
## лучше делать через toast_icon/toast_parts — иконка и число вместо фразы.
func toast(text: String, seconds: float = 2.6) -> void:
	_show_toast([{"text": text, "wrap": true}], seconds, "info")


## Иконка (имя из art/ui) + короткое слово или число.
func toast_icon(icon_name: String, text: String = "", seconds: float = 2.4,
		color: Color = Color.WHITE, kind: String = "info") -> void:
	_show_toast([{"icon": icon_name, "text": text, "color": color}], seconds, kind)


## Несколько пар «иконка + текст» в одной таблетке. Часть — словарь:
## icon (имя в art/ui) или icon_tex (Texture2D), text, color, icon_px.
func toast_parts(parts: Array, seconds: float = 2.4, kind: String = "info") -> void:
	_show_toast(parts, seconds, kind)


func _show_toast(parts: Array, seconds: float, kind: String) -> void:
	if _toast_panel == null:
		return
	for c in _toast_row.get_children():
		_toast_row.remove_child(c)
		c.queue_free()
	var border: Color = TOAST_COLORS.get(kind, TOAST_COLORS["info"])
	var sb := ProgressUiKit.popup_box(border, Color(0.071, 0.055, 0.043, 0.94))
	sb.set_border_width_all(2 if kind == "rare" else 1)
	sb.content_margin_left = TOAST_PAD.x
	sb.content_margin_right = TOAST_PAD.x
	sb.content_margin_top = TOAST_PAD.y
	sb.content_margin_bottom = TOAST_PAD.y
	_toast_panel.add_theme_stylebox_override("panel", sb)

	var font: Font = ThemeDB.fallback_font
	var max_text_w := TOAST_MAX_W - TOAST_PAD.x * 2.0
	for part: Dictionary in parts:
		var tex: Texture2D = part.get("icon_tex", null)
		if tex == null and part.has("icon"):
			tex = UiIcons.tex(String(part["icon"]))
		if tex != null:
			var px := float(part.get("icon_px", 16))
			var r := TextureRect.new()
			r.texture = tex
			r.custom_minimum_size = Vector2(px, px)
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_toast_row.add_child(r)
		var text := String(part.get("text", ""))
		if text.is_empty():
			continue
		var wrap: bool = bool(part.get("wrap", false))
		var l := Label.new()
		l.text = text
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", TOAST_FONT if wrap else TOAST_FONT + 1)
		l.add_theme_color_override("font_color", part.get("color", Color.WHITE))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("outline_size", 2)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var fs := l.get_theme_font_size("font_size")
		# Размер считаем сами, шрифтовыми метриками: у Label с переносом высота
		# узнаётся только после раскладки, а панель нужна по размеру уже сейчас.
		var one_line := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if wrap and one_line > max_text_w:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, max_text_w, fs).y
			l.custom_minimum_size = Vector2(max_text_w, h)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		else:
			l.custom_minimum_size = Vector2(one_line + 1.0, 0)
		_toast_row.add_child(l)

	_toast_panel.modulate.a = 1.0
	_toast_panel.visible = true
	_place_toast()
	_toast_timer.start(seconds)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	UiAnim.appear(_toast_panel, UiAnim.POP_FROM, UiAnim.D_IN)
	if kind == "rare" and not Settings.reduce_motion:
		UiAnim.pulse(_toast_panel, 0.1, 0.5)


## Низ панели стоит на месте, верх и бока — по фактическому размеру. reset_size()
## сбивает смещения у якорей, поэтому считаем их сами.
func _place_toast() -> void:
	var sz := _toast_panel.get_combined_minimum_size()
	_toast_panel.offset_left = -sz.x * 0.5
	_toast_panel.offset_right = sz.x * 0.5
	_toast_panel.offset_bottom = TOAST_BOTTOM_OFFSET
	_toast_panel.offset_top = TOAST_BOTTOM_OFFSET - sz.y
	_toast_panel.pivot_offset = sz * 0.5


func _hide_toast() -> void:
	if _toast_panel == null or not _toast_panel.visible:
		return
	if Settings.reduce_motion or not _toast_panel.is_inside_tree():
		_toast_panel.visible = false
		return
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.2)
	_toast_tween.tween_callback(func() -> void:
		_toast_panel.visible = false
		_toast_panel.modulate.a = 1.0)


## Короткие тосты событий: иконка + слово или число, фразы убраны (текст только
## по наведению, заказ владельца). Что именно произошло, видно по иконкам.
## Предупреждение о голоде/бодрости (ГДД п.7): на 25% — значок и вспышка полоски,
## на 10% — ещё и встряска экрана и две секунды красного мигания. Раньше сигнал
## никто не слушал, и «предупреждение на экране» из ГДД не показывалось.
func _on_survival_warning(bar_name: String, severe: bool) -> void:
	var bar: HudBar = _hunger_bar if bar_name == "hunger" else _stamina_bar
	if bar == null:
		return
	toast_parts([{"icon": bar_name}, {"text": "!!" if severe else "!", "color": Color8(0xE8, 0x8C, 0x80)}],
		2.0, "bad")
	Sfx.play("warn_low")
	if severe:
		bar.alert(2.0)
		Fx.shake(3.0, 0.3)
		Haptics.buzz(80)
	else:
		bar.alert(0.6)
		Haptics.tap()


func _on_fell(damage: float, _speed: float) -> void:
	if damage > 0.0:
		toast_icon("hp", "−%d" % int(damage), 1.6, Color8(0xE8, 0x8C, 0x80), "bad")


func _on_dig_blocked(tile_type: int) -> void:
	# «Инструмент звенит о породу, стан от вибрации»: кирка, порода, «Звон!».
	var mineral_id := MineralMap.mineral_id_for(tile_type)
	var parts: Array = []
	var tool_path := _tool_icon_path(GameState.current_tool)
	if not tool_path.is_empty() and ResourceLoader.exists(tool_path):
		parts.append({"icon_tex": load(tool_path)})
	if not mineral_id.is_empty():
		parts.append({"icon_tex": UiIcons.item_small(mineral_id)})
	parts.append({"text": "Звон!", "color": Color8(0xE8, 0x8C, 0x80)})
	toast_parts(parts, 2.0, "bad")
	Sfx.play("ui_deny")


func _on_dig_finished(x: int, y: int, tile_type: int, mineral_id: String, was_loot: bool, coins: int) -> void:
	if was_loot and coins == 0 and not mineral_id.is_empty():
		# Рюкзак полон, находку пришлось оставить: предмет, рюкзак, «Полно».
		toast_parts([
			{"icon_tex": UiIcons.item_small(mineral_id)},
			{"icon": "weight"},
			{"text": "Полно", "color": Color8(0xE8, 0x8C, 0x80)},
		], 2.2, "bad")
		Sfx.play("ui_deny")
		UiAnim.shake(_load_pill, 3.0, 0.3)
	elif was_loot and not mineral_id.is_empty():
		float_item(x, y, mineral_id)
		UiAnim.pulse(_inv_button, 0.12, 0.2)
		# Крупная находка отмечается тостом — но БЕЗ суммы в монетах: монет
		# за копку не дают вовсе, их дают при продаже, а «+100 монет» читается
		# как «уже на счету» (решение владельца). И не больше нескольких раз
		# за игру: на десятый раз это уже не событие, а помеха.
		if coins >= RARE_FIND_COINS and GameState.rare_find_toasts_shown < RARE_FIND_TOAST_LIMIT:
			GameState.rare_find_toasts_shown += 1
			show_rare_find(mineral_id)
	if y == 80 and tile_type == TileTypes.Type.DIAMOND:
		# Алмаз замурован в камне, дедова кирка трескается (−25% скорости).
		toast_parts([
			{"icon_tex": UiIcons.item_small("diamond")},
			{"icon_tex": load("res://art/items/pickaxe_rusty_cracked.png")},
			{"text": "−25%", "color": Color8(0xE8, 0x8C, 0x80)},
		], 4.0, "bad")


## Тост редкой находки: звезда, предмет покрупнее и название золотом, золотая
## рамка, «подпрыгивает». Название — единственное слово: что нашёл, важно знать.
func show_rare_find(mineral_id: String) -> void:
	var name_ru := String(Balance.get_mineral(mineral_id).get("name_ru", ""))
	toast_parts([
		{"icon": "star"},
		{"icon_tex": UiIcons.item_small(mineral_id, 24), "icon_px": 24},
		{"text": name_ru, "color": TOAST_COLORS["rare"]},
	], 2.8, "rare")
	Sfx.play("pickup_rare")


func _on_gear_unlocked(gear_id: String) -> void:
	_sync_tool()
	# Ранцы и джетпаки больше не выдаются глубиной — их покупают, и о покупке
	# говорит магазин. Здесь остались только вещи, которые открывает глубина —
	# и один контрол-хинт: player.gd эмитит "backpack" ОДИН раз (см. его же
	# _announced_backpack), что бы ни сделало has_backpack() истинным —
	# сюжетная сцена «Ящик» (data/story.json:backpack, эффект backpack_owned)
	# или покупка в магазине, — и до сих пор ни тот, ни другой путь ни разу
	# не объяснял игроку, что ранец вообще поднимает в воздух. Задание
	# владельца (новый сюжет ранца): "покажи, что удержание ВВЕРХ теперь даёт
	# полёт" — теперь без слов: ранец с винтом и стрелка вверх.
	if gear_id == "backpack":
		toast_parts([
			{"icon_tex": load("res://art/items/backpack_propeller.png")},
			{"icon": "arrow_up"},
			{"text": "Полёт", "color": Color8(0xF2, 0xD9, 0x9B)},
		], 4.0, "good")
	if gear_id == "drill_rig":
		# Глубина 1000, собран бурмобиль: копает вдвое быстрее бура.
		toast_parts([
			{"icon_tex": load("res://art/items/drill_rig_icon.png"), "icon_px": 24},
			{"text": "×2", "color": Color8(0xF2, 0xD9, 0x9B)},
		], 4.0, "good")


func _on_tool_switched(tool_id: String) -> void:
	_sync_tool()
	_show_tool_name()
	if tool_id == "rusty_pickaxe":
		# Лопата упёрлась в старый фундамент, нашлась дедова кирка.
		toast_parts([
			{"icon_tex": load("res://art/items/pickaxe_rusty.png"), "icon_px": 24},
			{"text": "Дедова кирка", "color": Color8(0xF2, 0xD9, 0x9B)},
		], 3.4, "info")


## Герой сам сел за руль, войдя в тоннель с машиной в собственности, но не в
## руках (решение владельца: «спускаясь под землю он должен быть только в
## нём»). tool_changed уже пересинхронизировал иконку — здесь только тост.
func _on_entered_rig() -> void:
	toast_parts([{"icon_tex": load("res://art/items/drill_rig_icon.png"), "icon_px": 24}], 1.8, "good")


## Бурмобиль без топлива: либо не пускает в тоннель с поверхности, либо
## глохнет прямо под землёй. Текст сообщения решает player.gd (см. player.gd:
## _move_y и :_start_dig); на экране — топливо «0», а если надо идти на
## верстак — ещё и значок верстака.
func _on_rig_fuel_warning(message: String) -> void:
	var parts: Array = [{"icon": "fuel", "text": "0", "color": Color8(0xE8, 0x8C, 0x80)}]
	if message.contains("верстак"):
		parts.append({"icon": "workshop"})
	toast_parts(parts, 2.8, "bad")
	Sfx.play("ui_deny")


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
	_inv_sheet.open()
	_inv_button.button_pressed = true


func close_inventory() -> void:
	_inv_sheet.close()
	_inv_button.button_pressed = false


func _render_inventory() -> void:
	_inv_sheet.refresh()


func _eat_from_inventory(id: String) -> void:
	var res := HouseFood.eat(id)
	if not bool(res.get("ok", false)):
		toast(String(res.get("reason", "")))
		Sfx.play("ui_deny")
		return
	toast_parts([
		{"icon": "hunger", "text": "+%d" % int(res.get("hunger", 0.0)), "color": Color8(0xE8, 0x7E, 0x6E)},
		{"icon": "stamina", "text": "+%d" % int(res.get("stamina", 0.0)), "color": Color8(0xE8, 0xC5, 0x47)},
	], 2.0)
	Sfx.play("eat")
	_render_inventory()
	_sync_all()


## Три режима по кругу: джойстик → палец → стрелки (решение владельца).
const MODES: Array[String] = ["stick", "hold", "arrows"]


func _on_mode_button_pressed() -> void:
	cycle_mode()


## Следующий режим управления по кругу — пункт «Управление» в меню «•••».
func cycle_mode() -> void:
	var i := MODES.find(mode)
	_set_mode(MODES[(i + 1) % MODES.size()])


func _set_mode(m: String) -> void:
	mode = m
	Settings.set_control_mode(m)
	_release_stick()
	_has_touch = false
	_arrows_held.clear()
	if player != null:
		player.release_control()
	_stick.visible = mode == "stick"
	if mode == "hold":
		_flash_hold_hint()
	else:
		_hold_hint.visible = false
	if _arrows_panel != null:
		_arrows_panel.visible = mode == "arrows"
		_layout_arrows()
	_refresh_settings_panel()


## «Сброс» раньше чистил только diffs/fog/GameState-числа поверх ЖИВОГО
## мира — оставляя нетронутыми StoryState (флаги «сцена уже видена») и
## приватные поля WorldGen (_garden_locked и весь тоннель Роберта,
## era, ворота автокопки, разложенное сценарное золото...). Результат:
## тоннель после «сброса» никуда не девался — Роберт «уже построил» его
## навсегда, хотя прогресс игрока обнулился (задание владельца: «кнопка
## сброс пусть реально сбрасывает весь кэш игры, и тоннель пусть
## пропадает снова, пока Роберт не построит его»).
##
## Вместо ручного перечисления всех этих полей — стираем сейв и файл
## сюжета с диска и перезагружаем ВСЮ сцену: main.gd создаёт мир/туман/
## игрока/режиссёра сюжета заново, начисто, тем же путём, что при первом
## запуске без сейва. GameState — автозагрузка, реалоад сцены её не
## трогает, поэтому её ещё и reset_progress() явно (иначе цифры в памяти
## пережили бы стёртый файл). Рекорды (records.json) НЕ трогаем —
## RecordsStore задуман как трофеи поперёк забегов, а не часть прогресса.
func reset_game() -> void:
	_on_reset_pressed()


func _on_reset_pressed() -> void:
	close_more_menu()
	close_inventory()
	GameState.reset_progress()
	StoryState.clear_all()
	StoryState.delete_from_disk()
	SaveSystem.delete_save()
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# Ввод: джойстик и удержание пальца (портировано из web/index.html)
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Тап мимо меню закрывает меню (решение владельца). Разбирается ДО общей
	# заглушки ввода: пока меню открыто, мир ввод не получает, и закрыть его
	# иначе было бы нечем, кроме повторного попадания в ту же кнопку.
	if _dismiss_on_outside_press(event):
		return
	if player == null or _inv_sheet.visible or _settings_sheet.visible or ProgressScreen.is_open() or is_more_menu_open() or TechSystem.is_modal_open():
		return

	# Тестовая панель (debug_panel.gd) плавает НАД нижней полосой, то есть
	# физически внутри stage_rect — без этой проверки тап по её кнопкам
	# сперва ловил «режим пальца» (_handle_hold_input: любая точка внутри
	# stage_rect) или джойстик, событие помечалось обработанным, и кнопка
	# так и не получала свой клик (задание владельца: «тестовые кнопки не
	# получается нажать, так как они проживают фоновые кнопки»).
	if _debug_panel != null:
		var dbg_e := _normalize_pointer_event(event)
		if dbg_e.kind == "press" and _debug_panel.hit_test(dbg_e.pos):
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
	if _inv_sheet != null and _inv_sheet.is_drop_open():
		if not _inv_sheet.drop_card_rect().has_point(e.pos):
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
	return _inv_sheet.drop_card_rect()


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
	if player == null or ProgressScreen.is_open() or is_more_menu_open() or TechSystem.is_modal_open():
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

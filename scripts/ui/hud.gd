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
var _load_pill: PanelContainer
var _load_bar: HudBar
var _clock_label: Label
var _clock_box: Control
var _vignette: HpVignette
var _depth_box: Control
var _depth_label: Label
var _toast_panel: Panel
var _toast_label: Label
var _toast_timer: Timer
var _stick: Control
var _knob: Control
var _hold_hint: Label

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

## Панель настроек (Settings — scripts/core/settings.gd): звук/музыка,
## управление, радиус обзора, язык. Тот же приём full-screen шторки, что у
## инвентаря (_inv_sheet), — регуляторам (ползунки громкости) нужна ширина
## экрана, узкая popup-панель «⋯» для них тесна.
var _settings_sheet: Control
var _sound_slider: HSlider
var _sound_mute_btn: Button
var _music_slider: HSlider
var _music_mute_btn: Button
var _vision_toggle_btn: Button
var _control_mode_buttons: Dictionary = {}   # mode:String -> Button
var _language_buttons: Dictionary = {}       # code:String -> Button

## Точка входа в покупки (scripts/core/iap_manager.gd) — см. _build_settings_iap_row.
var _restore_purchases_btn: Button


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

	_load_pill = PanelContainer.new()
	_load_pill.add_theme_stylebox_override("panel", HudPill.pill_style(Color8(0x8F, 0xA3, 0x5C)))
	_load_pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	_load_pill.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_load_pill)
	_load_bar = HudBar.new().setup(Color8(0x7F, 0xB8, 0x6B), UiIcons.tex("weight"))
	_load_bar.bar_width = 44.0
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
	sb.corner_radius_top_left = 9
	sb.corner_radius_bottom_left = 9
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


## Высота панели раньше была двумя фиксированными числами (top=-160,
## bottom=-132 → ровно 28px всегда), а текст внутри переносился по словам
## без ограничения по высоте — двух-трёхстрочный тост обрезался снизу или
## вылезал за рамку (задание владельца: «фон контекстного окна не
## соответствует по высоте реальному размеру текста»). Низ панели остаётся
## фиксированным (offset_bottom), а верх toast() пересчитывает под
## фактическую обёрнутую высоту текста при каждом вызове — см. ниже.
const TOAST_BOTTOM_OFFSET := -132.0
const TOAST_PAD_V := 12.0       # запас сверху+снизу вокруг текста
const TOAST_MIN_H := 28.0       # короткая строка не сжимается в полоску
const TOAST_MAX_H := 200.0      # запас на случай очень длинного текста


func _build_toast(parent: Control) -> void:
	_toast_panel = Panel.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Подстраховка сверх TOAST_MAX_H: если когда-нибудь текст тоста всё равно
	# не влезет (перевод длиннее оригинала, склеенный текст и т.п.), лишние
	# строки обрежутся по границе панели, а не повиснут поверх игрового мира
	# без фона — так и было до этой правки на очень длинной строке (см. отчёт
	# QA-прохода).
	_toast_panel.clip_contents = true
	_toast_panel.anchor_left = 0.0; _toast_panel.anchor_right = 1.0
	_toast_panel.anchor_top = 1.0; _toast_panel.anchor_bottom = 1.0
	_toast_panel.offset_left = 8; _toast_panel.offset_right = -8
	_toast_panel.offset_bottom = TOAST_BOTTOM_OFFSET
	_toast_panel.offset_top = TOAST_BOTTOM_OFFSET - TOAST_MIN_H
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
	_toast_label.offset_right = -8
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


# ---------------------------------------------------------------------------
# Настройки (Settings — scripts/core/settings.gd): звук/музыка, управление,
# радиус обзора, язык.
# ---------------------------------------------------------------------------

func _build_settings_sheet(parent: Control) -> void:
	_settings_sheet = Control.new()
	_settings_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_sheet.visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.071, 0.055, 0.043, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_sheet.add_child(bg)
	parent.add_child(_settings_sheet)

	var head := HBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 10; head.offset_right = -10
	head.offset_top = 8; head.offset_bottom = 30
	_settings_sheet.add_child(head)

	var title := Label.new()
	title.text = "Настройки"
	title.add_theme_font_size_override("font_size", 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	var close_btn := Button.new()
	# × (U+00D7), не ✕ (U+2715) — та же ловушка шрифта темы, что у остальных
	# закрывающих крестиков в этом файле (см. _build_inventory_sheet).
	close_btn.text = "×"
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.custom_minimum_size = Vector2(20, 20)
	close_btn.pressed.connect(close_settings)
	head.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 10; scroll.offset_right = -10
	scroll.offset_top = 36; scroll.offset_bottom = -6
	# Без этого ScrollContainer по умолчанию разрешает содержимому расти и
	# ВПРАВО (SCROLL_MODE_AUTO), а не только вниз — строка из трёх кнопок
	# «Джойстик/Нажатия/Стрелки» вместо равного деления ширины считала себя
	# свободной шириться, и третья кнопка уезжала за край экрана.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_sheet.add_child(scroll)
	DragScroll.attach(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)

	_build_settings_sound_row(body)
	_build_settings_music_row(body)
	_build_settings_control_row(body)
	_build_settings_vision_row(body)
	_build_settings_language_row(body)
	_build_settings_iap_row(body)


func _settings_section_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color8(0x9D, 0x8B, 0x73))
	parent.add_child(lbl)


func _build_settings_sound_row(parent: Control) -> void:
	_settings_section_label(parent, "ЗВУК")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var icon := Label.new()
	icon.text = "🔊"
	icon.add_theme_font_size_override("font_size", 16)
	icon.custom_minimum_size = Vector2(24, 0)
	row.add_child(icon)

	_sound_slider = HSlider.new()
	_sound_slider.min_value = 0.0
	_sound_slider.max_value = 100.0
	_sound_slider.step = 1.0
	_sound_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sound_slider.value_changed.connect(func(v: float): Settings.set_sound_volume(v / 100.0))
	row.add_child(_sound_slider)

	_sound_mute_btn = Button.new()
	_sound_mute_btn.custom_minimum_size = Vector2(28, 24)
	_sound_mute_btn.add_theme_font_size_override("font_size", 14)
	_sound_mute_btn.focus_mode = Control.FOCUS_NONE
	_sound_mute_btn.pressed.connect(func(): Settings.set_sound_muted(not Settings.sound_muted); _refresh_settings_panel())
	row.add_child(_sound_mute_btn)


func _build_settings_music_row(parent: Control) -> void:
	_settings_section_label(parent, "МУЗЫКА")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var icon := Label.new()
	icon.text = "🎵"
	icon.add_theme_font_size_override("font_size", 16)
	icon.custom_minimum_size = Vector2(24, 0)
	row.add_child(icon)

	_music_slider = HSlider.new()
	_music_slider.min_value = 0.0
	_music_slider.max_value = 100.0
	_music_slider.step = 1.0
	_music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_slider.value_changed.connect(func(v: float): Settings.set_music_volume(v / 100.0))
	row.add_child(_music_slider)

	_music_mute_btn = Button.new()
	_music_mute_btn.custom_minimum_size = Vector2(28, 24)
	_music_mute_btn.add_theme_font_size_override("font_size", 14)
	_music_mute_btn.focus_mode = Control.FOCUS_NONE
	_music_mute_btn.pressed.connect(func(): Settings.set_music_muted(not Settings.music_muted); _refresh_settings_panel())
	row.add_child(_music_mute_btn)


## Джойстик / стрелки / удержание — те же три режима, что кнопка «⋯ →
## Управление» (_set_mode), тремя явными кнопками вместо цикла по кругу:
## в настройках понятнее видеть все варианты сразу, чем гадать, что будет
## следующим нажатием.
const _CONTROL_MODE_LABELS := {
	"stick": "Джойстик",
	"arrows": "Стрелки",
	"hold": "Нажатия",
}


func _build_settings_control_row(parent: Control) -> void:
	_settings_section_label(parent, "УПРАВЛЕНИЕ")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	for m in MODES:
		var btn := Button.new()
		btn.text = String(_CONTROL_MODE_LABELS.get(m, m))
		btn.add_theme_font_size_override("font_size", 10)
		btn.custom_minimum_size = Vector2(0, 26)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_set_mode.bind(m))
		row.add_child(btn)
		_control_mode_buttons[m] = btn


func _build_settings_vision_row(parent: Control) -> void:
	_settings_section_label(parent, "ОТОБРАЖЕНИЕ")
	_vision_toggle_btn = Button.new()
	_vision_toggle_btn.add_theme_font_size_override("font_size", 10)
	_vision_toggle_btn.custom_minimum_size = Vector2(0, 26)
	_vision_toggle_btn.focus_mode = Control.FOCUS_NONE
	_vision_toggle_btn.pressed.connect(func():
		Settings.set_show_vision_radius(not Settings.show_vision_radius)
		_refresh_settings_panel())
	parent.add_child(_vision_toggle_btn)


func _build_settings_language_row(parent: Control) -> void:
	_settings_section_label(parent, "ЯЗЫК")
	# HFlowContainer, не HBoxContainer: шесть языковых чипов в один ряд не
	# помещаются на портретных 224px — этот контейнер сам переносит лишние
	# на следующую строку, а не сжимает всех до нечитаемой ширины и не
	# уезжает вбок (тем более что горизонтальная прокрутка шторки настроек
	# выключена — см. scroll.horizontal_scroll_mode выше).
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	parent.add_child(row)
	for entry in Settings.LANGUAGES:
		var code := String(entry.get("code", ""))
		var available := bool(entry.get("available", false))
		var btn := Button.new()
		btn.text = String(entry.get("name", code))
		btn.add_theme_font_size_override("font_size", 10)
		btn.custom_minimum_size = Vector2(0, 24)
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = not available
		if not available:
			# Языки ждут перевода (задание владельца: "дальше, после моего
			# разрешения, будет...") — видны сразу, но серые и некликабельные,
			# а не появляются позже с нуля собранной панелью.
			btn.tooltip_text = "Скоро"
			btn.add_theme_color_override("font_disabled_color", Color8(0x5A, 0x50, 0x44))
		else:
			btn.pressed.connect(func(): Settings.set_language(code); _refresh_settings_panel())
		row.add_child(btn)
		_language_buttons[code] = btn


## Единственная точка входа в покупки, подключённая к IAPManager (см.
## scripts/core/iap_manager.gd) — решение владельца держать её в «Настройках»,
## а не заводить отдельный полноэкранный магазин косметики прямо сейчас:
## каталог (data/monetization.json) ещё черновой и ждёт утверждения, а
## кнопка «Восстановить покупки» всё равно обязана быть где-то в игре для
## будущей публикации в App Store (Apple отклоняет сборки с покупками без
## неё). IAPManager.request_purchase()/restore_purchases() — честные
## заглушки: они не покупают и не восстанавливают ничего по-настоящему, а
## сразу сообщают об этом тостом — ту же фразу уже показывает премиум-магазин
## для долларов (см. shop_ui.gd:_render_premium_screen). Когда появится
## платёжный SDK, эта кнопка не изменится — изменится только тело
## IAPManager.request_purchase().
func _build_settings_iap_row(parent: Control) -> void:
	_settings_section_label(parent, "ПОКУПКИ")
	var hint := Label.new()
	hint.text = "Платежи не подключены в этой сборке."
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color8(0x9D, 0x8B, 0x73))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(hint)

	_restore_purchases_btn = Button.new()
	_restore_purchases_btn.text = "Восстановить покупки"
	_restore_purchases_btn.add_theme_font_size_override("font_size", 10)
	_restore_purchases_btn.custom_minimum_size = Vector2(0, 26)
	_restore_purchases_btn.focus_mode = Control.FOCUS_NONE
	_restore_purchases_btn.pressed.connect(func():
		IAPManager.restore_purchases()
		toast("Покупок для восстановления нет — платежи не подключены."))
	parent.add_child(_restore_purchases_btn)


## Перечитывает Settings и красит все контролы панели — вызывается при
## открытии и после любого изменения (мьют/режим/язык/радиус), чтобы кнопки
## сразу отражали новое состояние, а не только реальный эффект в игре.
func _refresh_settings_panel() -> void:
	if _sound_slider == null:
		return
	_sound_slider.value = Settings.sound_volume * 100.0
	_sound_mute_btn.text = "🔇" if Settings.sound_muted else "🔊"
	_music_slider.value = Settings.music_volume * 100.0
	_music_mute_btn.text = "🔇" if Settings.music_muted else "🎵"
	_vision_toggle_btn.text = "Радиус обзора: показан" if Settings.show_vision_radius \
		else "Радиус обзора: скрыт"

	for m in _control_mode_buttons.keys():
		var btn: Button = _control_mode_buttons[m]
		var on: bool = m == mode
		btn.add_theme_color_override("font_color",
			Color8(0xE0, 0xA9, 0x3B) if on else Color8(0x9D, 0x8B, 0x73))
		btn.disabled = on

	for code in _language_buttons.keys():
		var lbtn: Button = _language_buttons[code]
		if not lbtn.disabled:
			var lon: bool = code == Settings.language
			lbtn.add_theme_color_override("font_color",
				Color8(0xE0, 0xA9, 0x3B) if lon else Color8(0x9D, 0x8B, 0x73))


func open_settings() -> void:
	close_more_menu()
	_refresh_settings_panel()
	_settings_sheet.visible = true


func close_settings() -> void:
	_settings_sheet.visible = false


func is_settings_open() -> bool:
	return _settings_sheet != null and _settings_sheet.visible


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
var _more_grid: GridContainer
var _more_button: Button
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
	sb.border_color = Color8(0x4A, 0x3B, 0x2C)
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
	_inv_button = UiBtn.icon_button(UiIcons.tex("backpack"), Vector2(34, 34), UiBtn.Kind.NORMAL, 16)
	Tip.bind(_inv_button, "Рюкзак", "Что несёшь и сколько это стоит")
	_inv_button.toggle_mode = true
	_inv_button.pressed.connect(_on_inv_button_pressed)
	strip.add_child(_inv_button)

	# Инструмент — одна иконка без подписи, чуть крупнее остальных: это то, чем
	# копают. Название всплывает НАД полосой по нажатию (и при наведении на
	# компьютере), и само — когда инструмент сменился (ГДД п.16).
	_tool_button = UiBtn.icon_button(null, Vector2(38, 36), UiBtn.Kind.NORMAL, 32)
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
	var storage_btn := UiBtn.icon_button(UiIcons.tex("inventory"), Vector2(34, 34))
	Tip.bind(storage_btn, "Склад", "В мастерской: можно смотреть откуда угодно")
	storage_btn.add_to_group("house_storage_button")
	strip.add_child(storage_btn)
	# --- конец блока дома ---

	# «•••» встаёт последним, чтобы контекстная кнопка дома, появляясь и
	# исчезая, не сдвигала его под пальцем. Красный бейдж — сумма бейджей
	# пунктов меню (новые задания и т.п.).
	_more_button = UiBtn.icon_button(UiIcons.tex("more"), Vector2(34, 34))
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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0x1A, 0x14, 0x0F, 0xF5)
	sb.border_color = Color8(0x52, 0x40, 0x2D)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	sb.set_content_margin_all(5)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 3
	_more_panel.add_theme_stylebox_override("panel", sb)
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
	build_label.add_theme_font_size_override("font_size", 7)
	build_label.add_theme_color_override("font_color", Color8(0x6B, 0x5D, 0x4C))
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
	if _more_panel.visible:
		close_more_menu()
		return
	_rebuild_more_menu()
	_more_panel.visible = true
	UiAnim.appear(_more_panel, 0.85, 0.14)
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
	if _more_panel != null:
		if _more_panel.visible:
			Sfx.play("ui_close")
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
		toast("Бурмобиль под землёй не бросить — сначала наверх или домой."))
	GameState.xp_changed.connect(func(_xp, _lvl): _sync_xp())
	GameState.leveled_up.connect(func(_lvl, _pts): _sync_xp())
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
	var in_rig := GameState.current_tool == "drill_rig"
	_fuel_box.visible = in_rig
	if not in_rig:
		return
	var n := GameState.get_item_count("fuel_block")
	_fuel_label.text = str(n)
	_fuel_label.add_theme_color_override("font_color",
		Color8(0xD9, 0x4F, 0x4A) if n <= 0 else Color8(0xF2, 0xE6, 0xC8))


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
	_depth_box.position.y = clampf(screen_y - h * 0.5, 0.0, stage_rect.size.y - h)


# ---------------------------------------------------------------------------
# Тосты
# ---------------------------------------------------------------------------

func toast(text: String, seconds: float = 2.6) -> void:
	_toast_label.text = text
	_resize_toast_panel()
	_toast_panel.visible = true
	_toast_timer.start(seconds)


## Меряет фактическую (обёрнутую по словам) высоту текста тем же шрифтом,
## что рисует сам Label, и растягивает панель под неё снизу вверх — низ
## (offset_bottom) не трогаем, чтобы тост не прыгал по вертикали при смене
## текста. Считаем ширину от вьюпорта, а не от _toast_panel.size: та не
## гарантированно свежая при первом же вызове toast() (см. hud.gd:
## _update_layout — панель, как и весь HUD, отзывается на резайз вьюпорта
## реактивно, а не мгновенно в конструкторе).
func _resize_toast_panel() -> void:
	var font := _toast_label.get_theme_font("font")
	var font_size := _toast_label.get_theme_font_size("font_size")
	if font == null:
		return
	var margins: float = _toast_panel.offset_left - _toast_panel.offset_right \
		+ _toast_label.offset_left - _toast_label.offset_right
	var wrap_width: float = maxf(40.0, get_viewport_rect().size.x - margins)
	var text_h: float = font.get_multiline_string_size(
		_toast_label.text, HORIZONTAL_ALIGNMENT_LEFT, wrap_width, font_size).y
	var panel_h: float = clampf(text_h + TOAST_PAD_V, TOAST_MIN_H, TOAST_MAX_H)
	_toast_panel.offset_top = TOAST_BOTTOM_OFFSET - panel_h


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
	# говорит магазин. Здесь остались только вещи, которые открывает глубина —
	# и один контрол-хинт: player.gd эмитит "backpack" ОДИН раз (см. его же
	# _announced_backpack), что бы ни сделало has_backpack() истинным —
	# сюжетная сцена «Ящик» (data/story.json:backpack, эффект backpack_owned)
	# или покупка в магазине, — и до сих пор ни тот, ни другой путь ни разу
	# не объяснял игроку, что ранец вообще поднимает в воздух. Задание
	# владельца (новый сюжет ранца): "покажи, что удержание ВВЕРХ теперь даёт
	# полёт" — тот же toast(), которым HUD уже объявляет любую другую находку.
	if gear_id == "backpack":
		toast("Ранец на плечах. Держи ВВЕРХ в прыжке — и полетишь.", 4.0)
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
	_hold_hint.visible = mode == "hold"
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
	if player == null or _inv_sheet.visible or _settings_sheet.visible or ProgressScreen.is_open() or is_more_menu_open():
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

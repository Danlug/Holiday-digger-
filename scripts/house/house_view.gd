extends CanvasLayer
## HouseView — интерьер дома как НАСТОЯЩЕЕ пространство (сцена scenes/house.tscn).
##
## Решение владельца (2026-09-16): «Дом» отменяется как контекстное меню с
## карточками комнат — герой физически заходит внутрь и ходит по комнате
## вдоль линии пола, камера едет за ним по горизонтали, а кнопки действий
## всплывают НАД ГЕРОЕМ, когда он подошёл к нужному месту (дверь, кровать,
## верстак, сундук...), и гаснут, когда отошёл. Если в радиусе сразу
## несколько точек — показываются кнопки ВСЕХ них (см. рядом стоящие верстак
## и сундук в мастерской) — это общий механизм (_update_hotspots), а не
## частный случай одной пары точек.
##
## Комнат три: hall (салон), bedroom (спальня), workshop (мастерская, бывший
## подвал). Прыжка и полёта внутри дома нет — герой только идёт влево-вправо,
## поэтому у своя, упрощённая (не player.gd) физика: одна координата,
## клавиатура (A/D, ←/→ — те же клавиши, что двигают героя в шахте, см.
## scripts/ui/hud.gd:KEYS_LEFT/KEYS_RIGHT) и две кнопки ◀/▶ на экране.
##
## Геометрия комнат (доли точек, радиусы, переходы) — данные, не код, см.
## data/rooms.json и scripts/house/house_rooms_config.gd. Фона art/env/room_*
## пока нет — комната рисуется плашкой в тех же пропорциях, дом остаётся
## полностью играбельным без художника.
##
## Структура узлов строится кодом (_ensure_structure) и им же сгенерирована
## сама сцена (см. tools/gen_house_scenes.gd): открыть и доработать в
## редакторе можно как обычно, а потеря сцены дом не ломает — узлы
## создадутся заново при загрузке.
##
## Все действия уходят наружу сигналом action_requested: сама по себе панель
## ничего не меняет в состоянии игры (кроме собственного положения героя в
## комнате — это чисто визуальное состояние вида). Логика сна/еды/переходов —
## в scripts/house/house_system.gd и house_sleep/house_food.

signal action_requested(action: String, arg: String)

const BG := Color8(0x14, 0x0F, 0x0B)
const PANEL_BG := Color8(0x1E, 0x18, 0x11)
const PANEL_BORDER := Color8(0x3E, 0x31, 0x25)
const ACCENT := Color8(0xE0, 0xA9, 0x3B)
const DIM := Color8(0x9D, 0x8B, 0x73)

## Высота игрового поля дома — вся высота экрана (480) минус тонкая шапка со
## статами (HUD на время дома скрыт целиком, см. house_system.enter_house).
const HEADER_HEIGHT := 40.0
const STAGE_HEIGHT := 440.0
const VIEW_W := 224.0  # project.godot: window/size/viewport_width

## Скорость ходьбы по комнате — тот же порядок величины, что WALK*TILE в
## шахте (player.gd: 4.2 * 32 = 134.4 px/c), чтобы «те же органы управления»
## ощущались так же и внутри дома.
const WALK_SPEED_PX_S := 130.0
const HERO_W := 48.0
const HERO_H := 48.0

## Герой в доме крупнее, чем в шахте (решение владельца: «в доме он должен
## быть в 5 раз больше»). Комнаты нарисованы в другом масштабе — дверь в
## салоне высотой почти в половину экрана, — и кадр 48×48 рядом с ней читался
## как игрушечный. Пиксель героя при этом становится крупнее пикселя фона:
## это цена того, чтобы он был одного роста с мебелью.
const HERO_SCALE := 5.0

## Кадр героя на диске в ART_SCALE раз крупнее логических 48×48 (см.
## tools/import_art.py). В доме он к тому же увеличен впятеро, поэтому
## подробность текстуры здесь нужнее всего.
const ART_SCALE := 3.0
## Запас от низа кадра до подошвы — то же число, что GROUND_Y в
## character_view.gd (48 - 46 = 2): кадр героя шире тела, и без этого запаса
## подошва повисала бы над полом.
const FOOT_PAD := 2.0
const WALK_FPS := 8.0

const IDLE_SHEET := "res://art/character/idle.png"
const WALK_SHEET := "res://art/character/walk.png"
## Спрайт-лист сна готовит другой агент (задание владельца): здесь только
## проигрывается. Нет файла — играем статичную позу art/character/sleep.png
## (уже есть в репозитории), нет и её — просто держим паузу без падения.
const SLEEP_SHEET := "res://art/anim/sleep_sheet.png"
const SLEEP_SHEET_META := "res://art/anim/sleep_sheet.json"
const SLEEP_STATIC_POSE := "res://art/character/sleep.png"

const KEY_LEFT_A: Key = KEY_A
const KEY_LEFT_ARROW: Key = KEY_LEFT
const KEY_RIGHT_D: Key = KEY_D
const KEY_RIGHT_ARROW: Key = KEY_RIGHT

var _root: Control
var _title: Label
var _clock: Label
var _bars: Dictionary = {}       # "hp"|"hunger"|"stamina" -> ColorRect (заливка)
var _notice: Label
var _notice_until_msec: float = 0.0

var _stage: Control
var _bg: TextureRect
var _bg_fallback: ColorRect
var _hero: TextureRect
var _hotspot_layer: Control
var _walk_left_btn: Button
var _walk_right_btn: Button

var _forced: Control
var _forced_text: Label
var _forced_button: Button
var _forced_mode: String = ""    # "" | "sleep"

var _sleep_overlay: Control
var _sleep_sprite: TextureRect
var _sleep_label: Label

var _idle_sheet: Texture2D
var _walk_sheet: Texture2D
var _sleep_sheet_tex: Texture2D
var _sleep_meta: Dictionary = {}
var _sleep_static_tex: Texture2D
var _cur_frame_sheet: Texture2D = null
var _cur_frame_idx: int = -1

var _room_id: String = ""
var _room_def: Dictionary = {}
var _room_width_px: float = float(VIEW_W)
var _floor_y_px: float = STAGE_HEIGHT * 0.86
var _hero_x_px: float = 0.0
var _facing: int = 1
var _walk_dir: int = 0
var _walk_frame_t: float = 0.0
var _hold_left: bool = false
var _hold_right: bool = false

var _hotspot_buttons: Array = []
var _hotspot_signature: String = ""
var _locked: bool = false        # внешняя блокировка (форс-режим/сон — своя)

var _sleeping: bool = false
var _sleep_t: float = 0.0
var _sleep_total: float = 10.0


func _ready() -> void:
	# Выше HUD (его слой 1), но НИЖЕ экранов соседних систем (магазин 20,
	# экран героя 10): их окна открываются из комнат дома и обязаны лечь
	# поверх интерьера, а не под него.
	layer = 9
	_ensure_structure()
	visible = false


# ---------------------------------------------------------------------------
# Сборка интерьера
# ---------------------------------------------------------------------------

## Создаёт недостающие узлы. Вызывается и при загрузке сцены (где всё уже
## есть — тогда функция только находит узлы), и генератором сцены
## (tools/gen_house_scenes.gd) — поэтому НЕ обращается к get_tree()/автолоадам
## сверх того, что доступно узлу вне дерева.
func _ensure_structure() -> void:
	_root = _need(self, "Root", Control)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := _need(_root, "Backdrop", ColorRect) as ColorRect
	backdrop.color = BG
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_header()
	_build_stage()
	_build_forced()
	_load_hero_sheets()


func _build_header() -> void:
	var header := _need(_root, "Header", Panel) as Panel
	header.anchor_right = 1.0
	header.offset_bottom = HEADER_HEIGHT
	header.add_theme_stylebox_override("panel", _box(PANEL_BG, PANEL_BORDER))

	_title = _need(header, "Title", Label) as Label
	_title.position = Vector2(8, 2)
	_title.add_theme_font_size_override("font_size", 10)
	_title.add_theme_color_override("font_color", ACCENT)
	_title.text = "ДОМ"

	_clock = _need(header, "Clock", Label) as Label
	_clock.anchor_left = 1.0
	_clock.anchor_right = 1.0
	_clock.offset_left = -122
	_clock.offset_right = -62
	_clock.offset_top = 3
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.add_theme_font_size_override("font_size", 8)
	_clock.add_theme_color_override("font_color", DIM)

	# Кнопка «Магазин» есть и дома (решение владельца: «и дома и вне дома»).
	# На время дома HUD скрыт целиком, поэтому его кнопку сюда не дотянуть —
	# в шапке комнаты стоит своя, зовущая ту же премиум-витрину.
	var premium := _need(header, "Premium", Button) as Button
	premium.text = "Магазин"
	premium.add_theme_font_size_override("font_size", 8)
	premium.focus_mode = Control.FOCUS_NONE
	premium.anchor_left = 1.0
	premium.anchor_right = 1.0
	# Верхняя строка, справа: ниже идут полоски выживания на всю ширину, и
	# кнопка там налезала на бодрость.
	premium.offset_left = -56
	premium.offset_right = -6
	premium.offset_top = 1
	premium.offset_bottom = 15
	if not premium.pressed.is_connected(_on_premium_pressed):
		premium.pressed.connect(_on_premium_pressed)

	# Полоски выживания дублируются здесь: HUD на время дома скрыт целиком
	# (его джойстик и нижняя полоса иначе торчали бы поверх комнаты), а
	# видеть, как поднимается бодрость, игрок должен именно в доме.
	var bars := _need(header, "Bars", HBoxContainer) as HBoxContainer
	bars.position = Vector2(8, 18)
	bars.add_theme_constant_override("separation", 6)
	_bars["hp"] = _bar_row(bars, "Hp", Color8(0xB8, 0x5A, 0x52), "res://art/ui/icon_hp.png")
	_bars["hunger"] = _bar_row(bars, "Hunger", Color8(0xC4, 0x70, 0x6A), "res://art/ui/icon_hunger.png")
	_bars["stamina"] = _bar_row(bars, "Stamina", Color8(0x6E, 0x93, 0xA8), "res://art/ui/icon_stamina.png")

	# Уведомление — пузырь над кнопками ходьбы, на всю ширину и с переносом.
	# В шапке справа ему доставалось ~120 px с обрезкой, и отказ «Не хочется
	# спать: бодрость полная…» терял и начало, и конец.
	_notice = _need(_root, "Notice", Label) as Label
	_notice.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_notice.offset_left = 8
	_notice.offset_right = -8
	_notice.offset_top = -92
	_notice.offset_bottom = -48
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD
	_notice.add_theme_font_size_override("font_size", 9)
	_notice.add_theme_color_override("font_color", ACCENT)
	_notice.add_theme_stylebox_override("normal", _box(Color(0.07, 0.055, 0.043, 0.92), ACCENT))
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.visible = false
	# Пузырь строится вместе с шапкой, раньше комнаты, — а комната (Stage)
	# занимает весь экран и рисуется поверх всего, что в дереве выше неё.
	# Без переноса в конец пузырь показывался, но его не было видно.
	_root.move_child(_notice, _root.get_child_count() - 1)


func _bar_row(parent: Control, bar_name: String, color: Color, icon_path: String) -> ColorRect:
	var row := _need(parent, bar_name, HBoxContainer) as HBoxContainer
	row.add_theme_constant_override("separation", 3)
	if ResourceLoader.exists(icon_path):
		var icon := _need(row, "Icon", TextureRect) as TextureRect
		icon.custom_minimum_size = Vector2(10, 10)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(icon_path)
	var track := _need(row, "Track", Panel) as Panel
	track.custom_minimum_size = Vector2(44, 6)
	track.add_theme_stylebox_override("panel", _box(Color(0.043, 0.035, 0.027, 0.85), Color(0, 0, 0, 0.55)))
	var fill := _need(track, "Fill", ColorRect) as ColorRect
	fill.color = color
	fill.position = Vector2(1, 1)
	fill.size = Vector2(42, 4)
	return fill


## Комната как пространство: плашка/фон, герой, слой хотспотов, кнопки хода.
func _build_stage() -> void:
	_stage = _need(_root, "Stage", Control) as Control
	_stage.anchor_right = 1.0
	_stage.anchor_bottom = 1.0
	_stage.offset_top = HEADER_HEIGHT
	_stage.clip_contents = true
	# Тап по самому фону ничего не делает — ходьба только с кнопок ◀/▶ и
	# клавиатуры (решение по аналогии с шахтой: там тоже не тапом ходят).
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bg_fallback = _need(_stage, "BgFallback", ColorRect) as ColorRect
	_bg_fallback.color = Color8(0x2A, 0x22, 0x18)
	_bg_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bg = _need(_stage, "Bg", TextureRect) as TextureRect
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hero = _need(_stage, "Hero", TextureRect) as TextureRect
	_hero.stretch_mode = TextureRect.STRETCH_KEEP
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.size = Vector2(HERO_W * ART_SCALE, HERO_H * ART_SCALE)
	_hero.scale = Vector2(HERO_SCALE / ART_SCALE, HERO_SCALE / ART_SCALE)

	_hotspot_layer = _need(_stage, "Hotspots", Control) as Control
	_hotspot_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hotspot_layer.mouse_filter = Control.MOUSE_FILTER_PASS

	_build_walk_buttons()
	_build_sleep_overlay()


func _build_walk_buttons() -> void:
	_walk_left_btn = _need(_stage, "WalkLeft", Button) as Button
	_walk_left_btn.text = "◀"
	_style_button(_walk_left_btn)
	_walk_left_btn.anchor_top = 1.0
	_walk_left_btn.anchor_bottom = 1.0
	_walk_left_btn.offset_left = 6
	_walk_left_btn.offset_right = 44
	_walk_left_btn.offset_top = -40
	_walk_left_btn.offset_bottom = -6

	_walk_right_btn = _need(_stage, "WalkRight", Button) as Button
	_walk_right_btn.text = "▶"
	_style_button(_walk_right_btn)
	_walk_right_btn.anchor_left = 1.0
	_walk_right_btn.anchor_right = 1.0
	_walk_right_btn.anchor_top = 1.0
	_walk_right_btn.anchor_bottom = 1.0
	_walk_right_btn.offset_left = -44
	_walk_right_btn.offset_right = -6
	_walk_right_btn.offset_top = -40
	_walk_right_btn.offset_bottom = -6


func _build_sleep_overlay() -> void:
	# Оверлей живёт в _root, а не в _stage: _stage — это комната, она едет за
	# камерой по x, и кадр сна, положенный туда, уезжал вместе с ней — у
	# кровати (треть ширины комнаты) лицо оказывалось наполовину за правым
	# краем экрана. Экранный слой стоит на месте.
	_sleep_overlay = _need(_root, "SleepOverlay", Control) as Control
	_sleep_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.move_child(_sleep_overlay, _root.get_child_count() - 1)
	_sleep_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_sleep_overlay.visible = false

	var shade := _need(_sleep_overlay, "Shade", ColorRect) as ColorRect
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.02, 0.02, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_sleep_sprite = _need(_sleep_overlay, "Sprite", TextureRect) as TextureRect
	# Кадр авторской анимации — 224×258, ровно ширина экрана: коробка под
	# него на всю ширину, по высоте с запасом; вписываем с сохранением
	# пропорций, чтобы на другом экране он ужался, а не обрезался.
	_sleep_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sleep_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sleep_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sleep_sprite.anchor_left = 0.0
	_sleep_sprite.anchor_right = 1.0
	_sleep_sprite.anchor_top = 0.5
	_sleep_sprite.anchor_bottom = 0.5
	_sleep_sprite.offset_left = 0
	_sleep_sprite.offset_right = 0
	_sleep_sprite.offset_top = -150
	_sleep_sprite.offset_bottom = 110

	_sleep_label = _need(_sleep_overlay, "Label", Label) as Label
	_sleep_label.text = "Спит..."
	_sleep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sleep_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sleep_label.anchor_left = 0.0
	_sleep_label.anchor_right = 1.0
	_sleep_label.anchor_top = 1.0
	_sleep_label.anchor_bottom = 1.0
	_sleep_label.offset_top = -40
	_sleep_label.offset_bottom = -10
	_sleep_label.add_theme_color_override("font_color", ACCENT)


func _build_forced() -> void:
	# Экран принудительного действия обучения (ГДД п.9): первое истощение
	# ведёт героя в спальню и не отпускает, пока он не ляжет. Поведение и имя
	# методов не менялись — house_system.gd зовёт их как раньше.
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
	if not _forced_button.pressed.is_connected(_on_forced_pressed):
		_forced_button.pressed.connect(_on_forced_pressed)


func _on_forced_pressed() -> void:
	action_requested.emit("forced_confirm", _forced_mode)


func _load_hero_sheets() -> void:
	_idle_sheet = load(IDLE_SHEET) if ResourceLoader.exists(IDLE_SHEET) else null
	_walk_sheet = load(WALK_SHEET) if ResourceLoader.exists(WALK_SHEET) else null
	if ResourceLoader.exists(SLEEP_SHEET):
		_sleep_sheet_tex = load(SLEEP_SHEET)
		_sleep_meta = HouseRoomsConfig.read_json(SLEEP_SHEET_META)
	elif ResourceLoader.exists(SLEEP_STATIC_POSE):
		_sleep_static_tex = load(SLEEP_STATIC_POSE)


# ---------------------------------------------------------------------------
# Открытие/закрытие/переходы между комнатами
# ---------------------------------------------------------------------------

## enter_x — доля 0..1, где герой появится в комнате (обычно дверь, из
## которой он вышел в предыдущей); -1 (по умолчанию) — spawn_x комнаты.
func open(room: String, enter_x: float = -1.0) -> void:
	visible = true
	_sleeping = false
	if _sleep_overlay != null:
		_sleep_overlay.visible = false
	go_to_room(room, enter_x)


func close() -> void:
	visible = false
	_sleeping = false
	if _sleep_overlay != null:
		_sleep_overlay.visible = false


func go_to_room(id: String, enter_x: float = -1.0) -> void:
	var changed := id != _room_id
	_room_id = id
	_room_def = HouseRoomsConfig.room(id)
	if changed:
		_load_background()
	var frac: float = enter_x if enter_x >= 0.0 else float(_room_def.get("spawn_x", 0.5))
	_hero_x_px = clampf(frac, 0.0, 1.0) * _room_width_px
	_hold_left = false
	_hold_right = false
	_walk_dir = 0
	_hotspot_signature = ""  # гарантированно пересобрать кнопки на новом месте
	refresh()


## Фон комнаты. Настоящей картинки может не быть (художник ещё не положил
## art/env/room_<id>.png) — тогда рисуем плашку тех же пропорций: хотспоты и
## переходы работают одинаково что с картинкой, что без.
func _load_background() -> void:
	var path := HouseRoomsConfig.bg_path(_room_id)
	var size := HouseRoomsConfig.declared_size(_room_id)
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		_bg.texture = tex
		size = tex.get_size()
		_bg.visible = true
		_bg_fallback.visible = false
	else:
		_bg.texture = null
		_bg.visible = false
		_bg_fallback.visible = true
	var h: float = maxf(1.0, size.y)
	var scale_to_stage: float = STAGE_HEIGHT / h
	_room_width_px = maxf(float(VIEW_W), size.x * scale_to_stage)
	_bg.size = Vector2(_room_width_px, STAGE_HEIGHT)
	_bg_fallback.size = Vector2(_room_width_px, STAGE_HEIGHT)
	_floor_y_px = HouseRoomsConfig.floor_y(_room_id) * STAGE_HEIGHT


# ---------------------------------------------------------------------------
# Кадр: ходьба, камера, хотспоты, заголовок
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible:
		return
	if _sleeping:
		_sleep_t += delta
		_update_sleep_frame()

	if _is_locked():
		_walk_dir = 0
		_hold_left = false
		_hold_right = false
	else:
		_hold_left = _walk_left_btn != null and _walk_left_btn.is_pressed()
		_hold_right = _walk_right_btn != null and _walk_right_btn.is_pressed()
		_update_walk(delta)

	refresh()


func _is_locked() -> bool:
	return _locked or _sleeping or _forced_mode != ""


func _update_walk(delta: float) -> void:
	var dir := 0
	if Input.is_key_pressed(KEY_LEFT_A) or Input.is_key_pressed(KEY_LEFT_ARROW) or _hold_left:
		dir -= 1
	if Input.is_key_pressed(KEY_RIGHT_D) or Input.is_key_pressed(KEY_RIGHT_ARROW) or _hold_right:
		dir += 1
	_walk_dir = dir
	if dir != 0:
		_facing = dir
		_hero_x_px = clampf(_hero_x_px + float(dir) * WALK_SPEED_PX_S * delta, 0.0, _room_width_px)
		_walk_frame_t += delta
	else:
		_walk_frame_t = 0.0


## Перерисовывает камеру/героя/хотспоты/шапку по текущему состоянию. Вызывается
## и из _process (пока комната открыта), и напрямую — при go_to_room() и из
## тестов, которым нужен результат без ожидания кадра движка.
func refresh() -> void:
	if not visible:
		return
	_refresh_header()
	_update_camera_and_hero()
	if _is_locked():
		_clear_hotspots()
		_hotspot_signature = "@locked"
	else:
		_update_hotspots()


func _refresh_header() -> void:
	_set_bar("hp", GameState.hp / maxf(1.0, GameState.get_max_hp()))
	_set_bar("hunger", GameState.hunger / 100.0)
	_set_bar("stamina", GameState.stamina / 100.0)

	var total: float = GameState.game_clock_hours
	var day := int(total / 24.0) + 1
	var hour := int(total) % 24
	var minute := int((total - floor(total)) * 60.0)
	_clock.text = "День %d, %02d:%02d" % [day, hour, minute]

	if _notice != null and Time.get_ticks_msec() > _notice_until_msec:
		_notice.text = ""
		_notice.visible = false


func _set_bar(id: String, fraction: float) -> void:
	var fill: ColorRect = _bars.get(id)
	if fill != null:
		fill.size = Vector2(42.0 * clampf(fraction, 0.0, 1.0), 4)


func _update_camera_and_hero() -> void:
	var cam_x: float = clampf(_hero_x_px - VIEW_W / 2.0, 0.0, maxf(0.0, _room_width_px - VIEW_W))
	_bg.position.x = -cam_x
	_bg_fallback.position.x = -cam_x

	_update_hero_frame()
	var screen_x: float = _hero_x_px - cam_x
	# Масштаб растёт от левого верхнего угла, поэтому и ширина, и высота, и
	# отступ подошвы считаются уже увеличенными — иначе герой уедет вправо и
	# провалится под пол.
	_hero.position = Vector2(screen_x - HERO_W * HERO_SCALE / 2.0,
		_floor_y_px - (HERO_H - FOOT_PAD) * HERO_SCALE)
	_hero.flip_h = _facing < 0


func _update_hero_frame() -> void:
	var moving := _walk_dir != 0 and not _is_locked()
	var sheet: Texture2D = _walk_sheet if (moving and _walk_sheet != null) else _idle_sheet
	if sheet == null:
		_hero.texture = null
		return
	var frame_w := int(HERO_W * ART_SCALE)
	var frame_count: int = maxi(1, int(sheet.get_width()) / frame_w)
	var idx := 0
	if moving:
		idx = int(_walk_frame_t * WALK_FPS) % frame_count
	if sheet == _cur_frame_sheet and idx == _cur_frame_idx:
		return
	_cur_frame_sheet = sheet
	_cur_frame_idx = idx
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(idx * frame_w, 0, frame_w, int(HERO_H * ART_SCALE))
	_hero.texture = atlas


# ---------------------------------------------------------------------------
# Хотспоты — общий механизм (ГДД: «кнопка загорается над героем»)
# ---------------------------------------------------------------------------

## Точки текущей комнаты, в радиусе которых сейчас стоит герой, со всеми их
## кнопками разом (несколько точек в радиусе — несколько кнопок, как просил
## владелец про сундук и верстак).
func _collect_active_buttons() -> Array:
	var active: Array = []
	var points: Dictionary = _room_def.get("points", {})
	for key in points.keys():
		var p: Dictionary = points[key]
		var px: float = float(p.get("x", 0.5)) * _room_width_px
		var radius: float = float(p.get("radius", 0.08)) * _room_width_px
		if absf(_hero_x_px - px) > radius:
			continue
		for b in (p.get("buttons", []) as Array):
			if _condition_met(String(b.get("condition", ""))):
				active.append(b)
	return active


func _condition_met(id: String) -> bool:
	match id:
		"":
			return true
		"food_at_door":
			return HouseFood.food_at_door_count() > 0
		"tunnel_built":
			return GameState.house_hatch_built
		"pickaxe_available":
			# GameState.owns_tool() тут не годится: ржавая кирка — бесплатная
			# сюжетная ступень (is_tool_free), и owns_tool() на неё всегда
			# отвечает true, ещё до того, как её вообще взяли. Просмотр сцены
			# "workshop" — тот самый момент, когда кирка попадает в руки (см.
			# house_system.take_starting_pickaxe), и после него хотспот больше
			# не нужен.
			return not StoryState.is_seen("workshop")
		_:
			return true


func _update_hotspots() -> void:
	var active := _collect_active_buttons()
	var sig := _signature_for(active)
	if sig != _hotspot_signature:
		_hotspot_signature = sig
		_clear_hotspots()
		for def in active:
			_hotspot_buttons.append(_make_hotspot_button(def))
	_position_hotspot_buttons()


func _signature_for(active: Array) -> String:
	var parts: Array = []
	for def in active:
		parts.append(String(def.get("action", "")))
	return "|".join(parts)


func _clear_hotspots() -> void:
	for b in _hotspot_buttons:
		if is_instance_valid(b):
			b.queue_free()
	_hotspot_buttons.clear()


func _make_hotspot_button(def: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = String(def.get("label", ""))
	_style_button(btn)
	btn.custom_minimum_size = Vector2(0, 22)
	btn.set_meta("action", String(def.get("action", "")))
	btn.set_meta("label", String(def.get("label", "")))
	btn.pressed.connect(func(): _fire(def))
	_hotspot_layer.add_child(btn)
	return btn


## Кнопки всегда всплывают НАД ГЕРОЕМ (решение владельца), не над самой
## точкой на фоне: несколько кнопок ложатся в ряд вокруг его макушки.
func _position_hotspot_buttons() -> void:
	var n := _hotspot_buttons.size()
	if n == 0:
		return
	var hero_center_x: float = _hero.position.x + HERO_W * HERO_SCALE / 2.0
	# Над макушкой, а не над рамкой кадра: в кадре 48×48 у героя сверху шесть
	# пустых пикселей, и после увеличения это уже тридцать — кнопка висела бы
	# заметно выше головы.
	var top_y: float = _hero.position.y + 6.0 * HERO_SCALE - 26.0
	var gap := 4.0
	var widths: Array = []
	var total := 0.0
	for b in _hotspot_buttons:
		var w: float = maxf(56.0, b.get_minimum_size().x + 16.0)
		widths.append(w)
		total += w
	total += gap * float(maxi(0, n - 1))
	var hi: float = maxf(4.0, VIEW_W - total - 4.0)
	var start_x: float = clampf(hero_center_x - total / 2.0, 4.0, hi)
	var x := start_x
	for i in range(n):
		var b: Button = _hotspot_buttons[i]
		var w: float = widths[i]
		b.position = Vector2(x, top_y)
		b.size = Vector2(w, 22)
		x += w + gap


## Нажатие кнопки хотспота. "goto:<room>" дом решает сам (это чисто вид —
## переезд героя между комнатами), остальные действия уходят наружу сигналом.
func _fire(def: Dictionary) -> void:
	var action := String(def.get("action", ""))
	var parts := action.split(":", true, 1)
	if parts.size() == 2 and parts[0] == "goto":
		# Точка входа — по имени точки в целевой комнате, а не долей: доли
		# переопределяет разметка арта, и число здесь отстало бы от картинки
		# при первой же пересборке. Старый ключ enter_x понимаем по-прежнему.
		var enter_x: float = float(def.get("enter_x", -1.0))
		var enter_at: String = String(def.get("enter_at", ""))
		if not enter_at.is_empty():
			var target_points: Dictionary = HouseRoomsConfig.points(parts[1])
			if target_points.has(enter_at):
				enter_x = float(target_points[enter_at].get("x", enter_x))
		go_to_room(parts[1], enter_x)
		action_requested.emit("goto", parts[1])
		return
	action_requested.emit(action, "")


# ---------------------------------------------------------------------------
# Публичные хуки для тестов (tests/test_house.gd) и отладки
# ---------------------------------------------------------------------------

func room_id() -> String:
	return _room_id


func hero_x_fraction() -> float:
	return _hero_x_px / maxf(1.0, _room_width_px)


func room_width_px() -> float:
	return _room_width_px


## Ставит героя в долю ширины комнаты напрямую — тестам незачем ждать
## реального движения, чтобы проверить появление/исчезновение хотспотов.
func set_hero_x_fraction(f: float) -> void:
	_hero_x_px = clampf(f, 0.0, 1.0) * _room_width_px
	refresh()


func active_hotspots() -> Array:
	var out: Array = []
	for b in _hotspot_buttons:
		out.append({"action": String(b.get_meta("action", "")), "label": String(b.get_meta("label", ""))})
	return out


## Нажимает кнопку точки напрямую (мимо расстояния до героя) — тот же
## _fire(), которым отвечает настоящий тап, так что тест проверяет ровно то,
## что происходит по нажатию, а не имитацию.
func trigger_point_button(point_id: String, index: int = 0) -> void:
	var pts: Dictionary = _room_def.get("points", {})
	if not pts.has(point_id):
		return
	var buttons: Array = pts[point_id].get("buttons", [])
	if index < 0 or index >= buttons.size():
		return
	_fire(buttons[index])


func is_sleeping() -> bool:
	return _sleeping


## Внешняя блокировка ходьбы/хотспотов (форс-режим обучения и т.п.) — своя,
## отдельная от _forced_mode, потому что тому её незачем знать про сон.
func set_locked(value: bool) -> void:
	_locked = value


# ---------------------------------------------------------------------------
# Сон по кнопке «Спать» — короткая анимация вместо мгновенного эффекта
# ---------------------------------------------------------------------------

## house_system.gd отсчитывает реальные ~10 секунд отдельным таймером и в
## это время держит комнату «на паузе» (see set_locked); здесь только
## визуальная часть — оверлей и проигрывание кадров.
func play_sleep_animation(seconds: float) -> void:
	_sleeping = true
	_sleep_t = 0.0
	_sleep_total = maxf(0.1, seconds)
	if _sleep_overlay != null:
		_sleep_overlay.visible = true
	_hotspot_signature = "@sleeping"
	_clear_hotspots()
	_update_sleep_frame()


func stop_sleep_animation() -> void:
	_sleeping = false
	if _sleep_overlay != null:
		_sleep_overlay.visible = false


func _update_sleep_frame() -> void:
	if _sleep_sprite == null:
		return
	if _sleep_sheet_tex != null:
		var fw: int = int(_sleep_meta.get("frame_width", 48))
		var fh: int = int(_sleep_meta.get("frame_height", 48))
		var frames: int = maxi(1, int(_sleep_meta.get("frames", 1)))
		var fps: float = maxf(0.1, float(_sleep_meta.get("fps", 4.0)))
		var idx: int = int(_sleep_t * fps) % frames
		var atlas := AtlasTexture.new()
		atlas.atlas = _sleep_sheet_tex
		atlas.region = Rect2(idx * fw, 0, fw, fh)
		_sleep_sprite.texture = atlas
	elif _sleep_static_tex != null:
		_sleep_sprite.texture = _sleep_static_tex
	else:
		_sleep_sprite.texture = null


# ---------------------------------------------------------------------------
# Форс-режим обучения и сообщения (имена/сигнатуры не менялись — их зовёт
# house_system.gd)
# ---------------------------------------------------------------------------

## Сообщение в шапке дома (замена тостов HUD, который на время дома скрыт).
## Премиум-витрина открывается и из комнаты. Зовём по пути, а не по классу:
## магазин — чужая система, и дом не должен падать в сборке без неё.
func _on_premium_pressed() -> void:
	var path := "res://scripts/shop/shop_ui.gd"
	if ResourceLoader.exists(path):
		load(path).call("open_premium")


func notify(text: String, seconds: float = 3.0) -> void:
	if _notice == null:
		return
	_notice.text = text
	_notice.visible = not text.is_empty()
	_notice_until_msec = Time.get_ticks_msec() + seconds * 1000.0


func forced_mode() -> String:
	return _forced_mode


## Принудительный режим обучения: mode="" — обычный дом, mode="sleep" —
## экран поверх интерьера, который отпускает только после сна.
func set_forced(mode: String, text: String = "", button_text: String = "") -> void:
	_forced_mode = mode
	if _forced != null:
		_forced.visible = mode != ""
	if mode != "":
		_forced_text.text = text
		_forced_button.text = button_text
	refresh()


# ---------------------------------------------------------------------------
# Мелочи сборки
# ---------------------------------------------------------------------------

## Находит дочерний узел по имени или создаёт его. Благодаря этому один и тот
## же код и строит сцену с нуля, и подхватывает готовую из .tscn.
func _need(parent: Node, node_name: String, type) -> Node:
	var existing := parent.get_node_or_null(NodePath(node_name))
	if existing != null:
		return existing
	var node = type.new()
	node.name = node_name
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
		sb.bg_color = Color(0.06, 0.05, 0.04, 0.82)
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
	b.add_theme_color_override("font_disabled_color", PANEL_BORDER)

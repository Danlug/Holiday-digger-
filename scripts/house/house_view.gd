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
## project.godot: window/size/viewport_width — запасное значение на случай,
## когда узел ещё вне дерева и вьюпорт спросить не у кого (сборка сцены
## tools/gen_house_scenes.gd, первый кадр до add_child). ФАКТИЧЕСКАЯ ширина
## живёт в _view_w ниже и обновляется по-настоящему живому вьюпорту — этот
## constant отныне НЕ читают напрямую нигде в расчётах камеры/хотспотов/
## ширины комнаты, только как начальное значение _view_w и _room_width_px.
##
## Баг (отчёт владельца, реальный iPhone, живая веб-сборка): фон комнаты дома
## не дотягивался до правого края экрана — вертикальная чёрная полоса
## неизменной ширины у правого края, той же ширины что бы ни делала камера, а
## шапка HUD над ним (полоски/«Магазин») экран заполняла честно. Причина —
## этот файл везде считал ширину экрана ЖЁСТКО 224 (project.godot:
## window/size/viewport_width), а project.godot держит
## stretch/mode="canvas_items" + stretch/aspect="expand": на реальном
## устройстве, чьё физическое соотношение сторон шире дизайнерского портрета
## 224×480, движок сам РАСШИРЯЕТ логический вьюпорт вбок сверх 224 — то есть
## настоящая ширина экрана в вебе/на телефоне может быть больше 224, а не
## равна ему. HUD (scripts/ui/hud.gd) той же ловушки не ловит: его элементы —
## anchor-based Control на PRESET_FULL_RECT, они тянутся сами при ресайзе;
## этот файл, наоборот, считает камеру/ширину комнаты/клампинг хотспотов
## вручную в пикселях против константы — и без живого чтения вьюпорта не
## узнаёт, что экран стал шире. Тот же класс бага (жёсткая ширина вместо
## живого вьюпорта) чинит cutscene_player.gd своим _relayout_if_resized()
## (см. его _last_vp) — здесь тот же приём под другим именем поля.
const VIEW_W := 224.0

## Скорость ходьбы по комнате — решение владельца (2026-09-21): «ходить он
## должен в 2 раза быстрее». Было 130 (тот же порядок, что WALK*TILE в шахте:
## player.gd 4.2 * 32 = 134.4 px/c) — то есть быстрее не только шахтной
## скорости, а этого же дома до правки.
const WALK_SPEED_PX_S := 260.0
const HERO_W := 48.0
const HERO_H := 48.0

## Герой в доме крупнее, чем в шахте, но решением владельца (2026-09-21)
## уменьшен на 25% от прежних 5.0 («в доме можно... сделать на 25 процентов
## меньше»): 5.0 * 0.75 = 3.75. Раньше герой ростом уходил в 1.6 раза выше
## дверного проёма — теперь примерно в 1.2, читается как "крупный, но
## человеческий", а не как великан в кукольном домике.
const HERO_SCALE := 3.75

## Кадр героя на диске в ART_SCALE раз крупнее логических 48×48 (см.
## tools/import_art.py). В доме он к тому же увеличен впятеро, поэтому
## подробность текстуры здесь нужнее всего.
const ART_SCALE := 3.0
## Запас от низа кадра до подошвы — то же число, что GROUND_Y в
## character_view.gd (48 - 46 = 2): кадр героя шире тела, и без этого запаса
## подошва повисала бы над полом.
const FOOT_PAD := 2.0
## Темп смены кадров ходьбы — держим тем же отношением к WALK_SPEED_PX_S, что
## было раньше (8 / 130), иначе при удвоенной скорости ноги переступают
## вдвое реже, чем нужно для пройденного расстояния, и герой едет "на
## коньках", а не идёт (см. отчёт агента про анимации катсцен — тот же
## эффект, что ловит cutscene_player.ANIM_FPS, только здесь считанный от
## скорости явно).
const WALK_FPS := 8.0 * (WALK_SPEED_PX_S / 130.0)

## Ширина кадра героя и высота линии земли от верха кадра, в логических точках
## (у листов по эталону кадр обрезан по рисунку — см. _update_hero_frame).
var _hero_frame_u := Vector2(48.0, 46.0)

const IDLE_SHEET := "res://art/character/idle.png"
const WALK_SHEET := "res://art/character/walk.png"

## Названия комнат — только для подсказки значка в шапке.
## Длина ролика «курьер стучит в дверь»: въезжает, три удара, уезжает.
const KNOCK_TOTAL := 2.1
const KNOCK_BEATS := [0.55, 0.95, 1.35]

const ROOM_NAMES := {"hall": "Салон", "bedroom": "Спальня", "workshop": "Мастерская"}

const KEY_LEFT_A: Key = KEY_A
const KEY_LEFT_ARROW: Key = KEY_LEFT
const KEY_RIGHT_D: Key = KEY_D
const KEY_RIGHT_ARROW: Key = KEY_RIGHT

var _root: Control
var _clock: Label
var _day: Label
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

var _forced: HouseForcedCard
var _forced_mode: String = ""    # "" | "sleep"

var _sleep_fx: HouseSleepFx
var _door_pack: TextureRect     # пакет у входной двери (только в салоне)
var _courier: TextureRect
var _knock_icon: TextureRect
var _knock_t: float = -1.0      # <0 — стука нет; иначе секунды ролика
var _knock_beats: int = 0
var _pack_shown: bool = false
var _bar_icons: Dictionary = {}  # "hp"|"hunger"|"stamina" -> TextureRect
var _room_icon: TextureRect

var _idle_sheet: Texture2D
var _walk_sheet: Texture2D
var _cur_frame_sheet: Texture2D = null
var _cur_frame_idx: int = -1

var _room_id: String = ""
var _room_def: Dictionary = {}
## Живая ширина вьюпорта в логических px — см. VIEW_W выше и _refresh_view_w().
var _view_w: float = VIEW_W
var _room_width_px: float = float(VIEW_W)
## Естественный размер картинки комнаты (или заглушки), масштабированной к
## STAGE_HEIGHT, — см. _load_background()/_apply_room_width(). Держим
## отдельно от _room_width_px, чтобы ресайз вьюпорта (_refresh_view_w) мог
## пересчитать ширину комнаты БЕЗ перезагрузки текстуры с диска.
var _bg_declared_size: Vector2 = Vector2(VIEW_W, STAGE_HEIGHT)
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

## --- Сюжетный NPC-гость (не герой игрока) в открытой комнате ---------------
## Тот же визуальный приём, что герой (те же лист/масштаб/пол), но x/pose
## ведёт СЮЖЕТ (scripts/story/cutscene_player.gd:"house_npc_show"/
## "house_npc_walk"), не собственный ввод игрока: та же роль, что WorldActor
## на живой карте (scripts/story/world_actor.gd), только внутри комнаты дома.
## Один слот, не словарь: гостит ровно один сюжетный персонаж за раз (сейчас —
## докладывающий и уходящий Роберт, data/story.json:robert).
var _npc: TextureRect = null
var _npc_idle_tex: Texture2D = null
var _npc_walk_tex: Texture2D = null
var _npc_x_px: float = 0.0
var _npc_from_px: float = 0.0
var _npc_target_px: float = -1.0
var _npc_walk_total: float = 0.0
var _npc_walk_left: float = 0.0
var _npc_facing: int = 1
var _npc_frame_t: float = 0.0

var _sleeping: bool = false


func _ready() -> void:
	# Выше HUD (его слой 1), но НИЖЕ экранов соседних систем (магазин 20,
	# экран героя 10): их окна открываются из комнат дома и обязаны лечь
	# поверх интерьера, а не под него.
	layer = 9
	_ensure_structure()
	_build_live_overlays()
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
	_load_hero_sheets()


func _build_header() -> void:
	var header := _need(_root, "Header", Panel) as Panel
	header.anchor_right = 1.0
	header.offset_bottom = HEADER_HEIGHT
	header.add_theme_stylebox_override("panel", _box(PANEL_BG, PANEL_BORDER))

	# Старое слово «ДОМ» из прежней сцены: теперь это значок.
	var stale_title := header.get_node_or_null("Title")
	if stale_title != null:
		header.remove_child(stale_title)
		stale_title.queue_free()

	# Значок комнаты вместо слова «ДОМ»: название комнаты — в его подсказке.
	_room_icon = _need(header, "RoomIcon", TextureRect) as TextureRect
	_room_icon.texture = ShopArt.tex("glyph_house")
	_room_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_room_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_room_icon.position = Vector2(6, 2)
	_room_icon.size = Vector2(16, 16)
	_room_icon.mouse_filter = Control.MOUSE_FILTER_PASS

	# Часы: календарь + номер дня, часы + «ЧЧ:ММ». Один числовой ярлык на пару.
	var cal := _need(header, "CalIcon", TextureRect) as TextureRect
	cal.texture = HouseArt.tex("calendar")
	cal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cal.position = Vector2(28, 2)
	cal.size = Vector2(16, 16)
	cal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_day = _need(header, "Day", Label) as Label
	_day.position = Vector2(45, 3)
	_day.add_theme_font_size_override("font_size", 9)
	_day.add_theme_color_override("font_color", ACCENT)
	_day.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clk := _need(header, "ClockIcon", TextureRect) as TextureRect
	clk.texture = UiIcons.tex("clock")
	clk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	clk.position = Vector2(66, 3)
	clk.size = Vector2(14, 14)
	clk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock = _need(header, "Clock", Label) as Label
	_clock.position = Vector2(83, 3)
	_clock.add_theme_font_size_override("font_size", 9)
	_clock.add_theme_color_override("font_color", DIM)
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Кнопка магазина есть и дома (решение владельца: «и дома и вне дома»).
	# На время дома HUD скрыт целиком, поэтому его кнопку сюда не дотянуть —
	# в шапке комнаты стоит своя, зовущая ту же премиум-витрину. Значком, не
	# словом: название и что внутри — в подсказке.
	var premium := _need(header, "Premium", Button) as Button
	premium.text = ""
	premium.icon = UiIcons.tex("shop")
	premium.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	premium.expand_icon = false
	premium.add_theme_constant_override("icon_max_width", 16)
	premium.focus_mode = Control.FOCUS_NONE
	premium.anchor_left = 1.0
	premium.anchor_right = 1.0
	# Верхняя строка, справа: ниже идут полоски выживания на всю ширину, и
	# кнопка там налезала на бодрость.
	premium.offset_left = -34
	premium.offset_right = -6
	premium.offset_top = 1
	premium.offset_bottom = 21

	# Полоски выживания дублируются здесь: HUD на время дома скрыт целиком
	# (его джойстик и нижняя полоса иначе торчали бы поверх комнаты), а
	# видеть, как поднимается бодрость, игрок должен именно в доме.
	var bars := _need(header, "Bars", HBoxContainer) as HBoxContainer
	bars.position = Vector2(8, 22)
	bars.add_theme_constant_override("separation", 6)
	_bars["hp"] = _bar_row(bars, "Hp", Color8(0xB8, 0x5A, 0x52), "res://art/ui/icon_hp.png")
	_bars["hunger"] = _bar_row(bars, "Hunger", Color8(0xC4, 0x70, 0x6A), "res://art/ui/icon_hunger.png")
	_bars["stamina"] = _bar_row(bars, "Stamina", Color8(0x6E, 0x93, 0xA8), "res://art/ui/icon_stamina.png")
	for id in ["hp", "hunger", "stamina"]:
		var row: Control = (_bars[id] as Node).get_parent().get_parent()
		_bar_icons[id] = row.get_node_or_null("Icon")

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
	# expand_mode по умолчанию — EXPAND_KEEP_SIZE: Control не даёт задать
	# .size МЕНЬШЕ размера текстуры (минимальный размер = размер текстуры,
	# см. _load_background — там .size выставляется явно). Картинки комнат
	# 800×448, а _room_width_px/STAGE_HEIGHT всегда чуть уже (масштаб под
	# высоту стейджа 440 < 448), поэтому без этого фон незаметно раздувало
	# обратно до 800×448 — на 14px шире расчёта, и камера у правого края
	# останавливалась раньше, чем фон реально кончался (задание владельца:
	# «в спальне фон нужно... приклеить к правому краю» — тот же баг
	# наверняка и в остальных комнатах, текстуры у всех одного размера).
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
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


func _build_walk_buttons() -> void:
	_walk_left_btn = _need(_stage, "WalkLeft", Button) as Button
	_style_button(_walk_left_btn)
	_walk_left_btn.anchor_top = 1.0
	_walk_left_btn.anchor_bottom = 1.0
	_walk_left_btn.offset_left = 6
	_walk_left_btn.offset_right = 44
	_walk_left_btn.offset_top = -40
	_walk_left_btn.offset_bottom = -6
	_arrow_icon(_walk_left_btn, Vector2.LEFT)

	_walk_right_btn = _need(_stage, "WalkRight", Button) as Button
	_style_button(_walk_right_btn)
	_walk_right_btn.anchor_left = 1.0
	_walk_right_btn.anchor_right = 1.0
	_walk_right_btn.anchor_top = 1.0
	_walk_right_btn.anchor_bottom = 1.0
	_walk_right_btn.offset_left = -44
	_walk_right_btn.offset_right = -6
	_walk_right_btn.offset_top = -40
	_walk_right_btn.offset_bottom = -6
	_arrow_icon(_walk_right_btn, Vector2.RIGHT)


## Кнопки хода были подписаны текстом "◀"/"▶" — в шрифте темы этих символов
## нет, и кнопка показывала пустоту вместо стрелки (та же ловушка, что и у
## стрелок режима "стрелки" в hud.gd, см. её же комментарий). Треугольник
## общим хелпером ArrowIcon вместо текста — исправление, а не смена
## поведения: кнопка по-прежнему просто "шаг влево/вправо".
func _arrow_icon(btn: Button, dir: Vector2) -> void:
	# text у кнопки — на случай, если в сцене остался старый "◀"/"▶" (тофу-
	# прямоугольник шрифта поверх/под треугольником ArrowIcon), см. коммент
	# класса выше. ArrowIcon рисует стрелку сам — подписи кнопке не нужны.
	btn.text = ""
	var icon := _need(btn, "Arrow", ArrowIcon) as ArrowIcon
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Анкоры одни, без явного size, кнопку не догоняют: в момент этого вызова
	# (внутри _ready() дома, той же сборки узлов) у btn ещё не было ни одного
	# ресайза — Control пересчитывает прямоугольник ребёнка по анкорам НА
	# уведомление о ресайзе родителя, а не заново при каждом обращении к
	# .size, и без этого уведомления треугольник застывал нулевого размера
	# (отчёт владельца: кнопки хода — "какие-то юникодовские картинки", то
	# есть даже без текста стрелки не было видно вовсе). Догоняем размер
	# сразу и держим синхронно на будущее — на случай, если кнопку когда-то
	# станут пересобирать динамически.
	icon.size = btn.size
	btn.resized.connect(func(): icon.size = btn.size)
	icon.set_dir(dir)


## Узлы с собственным кодом строятся только в живом дереве (_ready), а не в
## _ensure_structure: сцену дома снимает tools/gen_house_scenes.gd, и узлы со
## скриптом, снятые в .tscn, при загрузке собрали бы себя ещё раз (_init).
func _build_live_overlays() -> void:
	_wire_header()
	# Остатки старой сцены (текстовые «Спит...» и окно с абзацем) выбрасываем.
	for stale in ["SleepOverlay", "Forced"]:
		var old := _root.get_node_or_null(stale)
		if old != null:
			_root.remove_child(old)
			old.queue_free()

	# Сон — экранный слой, а не часть комнаты: комната едет за камерой по x, и
	# кадр сна, положенный в неё, уезжал бы вместе с ней.
	_sleep_fx = HouseSleepFx.new()
	_root.add_child(_sleep_fx)
	_sleep_fx.skip_requested.connect(func(): action_requested.emit("sleep_skip", ""))

	# Пакет у входной двери и курьер, который его принёс (сцена доставки).
	_door_pack = ShopArt.rect(HouseArt.tex("act_package"), Vector2.ZERO, Vector2(48, 48))
	_door_pack.visible = false
	_courier = ShopArt.rect(HouseArt.tex("courier"), Vector2.ZERO, Vector2(64, 64))
	_courier.visible = false
	_knock_icon = ShopArt.rect(HouseArt.tex("knock"), Vector2.ZERO, Vector2(40, 40))
	_knock_icon.visible = false
	_knock_icon.pivot_offset = Vector2(20, 20)
	for n in [_door_pack, _courier]:
		_stage.add_child(n)
		_stage.move_child(n, _hero.get_index())
	_stage.add_child(_knock_icon)

	# Принудительный экран обучения (ГДД п.9): первое истощение ведёт героя в
	# спальню и не отпускает, пока он не ляжет. Поведение и имена методов не
	# менялись — house_system.gd зовёт их как раньше.
	_forced = HouseForcedCard.new()
	_forced.name = "Forced"
	_root.add_child(_forced)
	_forced.confirmed.connect(_on_forced_pressed)


## Подсказки, звук нажатия и обработчик кнопки магазина в шапке. Это живая
## «проводка»: метаданные Tip и UiBtn попали бы в снимок сцены, и при загрузке
## сцены Tip.bind принял бы узел за уже подключённый.
func _wire_header() -> void:
	var header := _root.get_node("Header")
	Tip.bind(_room_icon, "Дом")
	var premium := header.get_node("Premium") as Button
	UiBtn.style(premium)
	Tip.bind(premium, "Магазин за доллары", "Гаджеты, обмен и ролики.")
	if not premium.pressed.is_connected(_on_premium_pressed):
		premium.pressed.connect(_on_premium_pressed)
	for id in ["hp", "hunger", "stamina"]:
		var row: Control = (_bars[id] as Node).get_parent().get_parent()
		Tip.bind(row, {"hp": "Здоровье", "hunger": "Сытость", "stamina": "Бодрость"}[id])


func _on_forced_pressed() -> void:
	action_requested.emit("forced_confirm", _forced_mode)


func _load_hero_sheets() -> void:
	_idle_sheet = load(IDLE_SHEET) if ResourceLoader.exists(IDLE_SHEET) else null
	_walk_sheet = load(WALK_SHEET) if ResourceLoader.exists(WALK_SHEET) else null


# ---------------------------------------------------------------------------
# Открытие/закрытие/переходы между комнатами
# ---------------------------------------------------------------------------

## enter_x — доля 0..1, где герой появится в комнате (обычно дверь, из
## которой он вышел в предыдущей); -1 (по умолчанию) — spawn_x комнаты.
func open(room: String, enter_x: float = -1.0) -> void:
	visible = true
	_sleeping = false
	# Замок сна снимается вместе с самим сном: тап посреди ролика «house_sleep»
	# пролистывал сцену мимо stop_sleep_animation(), и комната оставалась
	# запертой навсегда (бот-прохождение, tests/test_bot_onboarding.gd).
	_locked = false
	if _sleep_fx != null:
		_sleep_fx.stop()
	go_to_room(room, enter_x)


func close() -> void:
	visible = false
	_sleeping = false
	_locked = false
	_knock_t = -1.0
	if _sleep_fx != null:
		_sleep_fx.stop()
	hide_npc()


func go_to_room(id: String, enter_x: float = -1.0) -> void:
	# Живая ширина ДО расчёта доли/ширины комнаты — иначе самый первый вход в
	# дом после запуска на реальном устройстве (до того, как хоть один кадр
	# _process/refresh успел спросить вьюпорт) выставил бы героя по доле от
	# ещё не обновлённой _room_width_px (см. VIEW_W выше).
	_refresh_view_w()
	var changed := id != _room_id
	_room_id = id
	_room_def = HouseRoomsConfig.room(id)
	if changed:
		_load_background()
		# Гость (Роберт и т.п.) принадлежит комнате, в которой сцена его
		# поставила, — переход героя в другую комнату не тащит его следом
		# (никакой сюжет сейчас так и не просит — Роберт стоит и уходит в
		# одной и той же комнате), а забытый видимый узел в комнате, куда
		# NPC никто не звал, был бы куда заметнее одного лишнего queue_free().
		hide_npc()
	var frac: float = enter_x if enter_x >= 0.0 else float(_room_def.get("spawn_x", 0.5))
	# "Разместить чуть дальше" (решение владельца, 2026-09-21): точки входа —
	# дверь, лестница, веранда — стоят у самого края комнаты (enter_at из
	# data/rooms.json, или спальный дефолт spawn_x, как у веранды в hall:
	# 0.93, почти вплотную к её же хотспоту "Выйти на улицу" на 0.95). Герой
	# появлялся вплотную к точке — сразу в радиусе СВОЕГО ЖЕ хотспота, и
	# кнопка "Зайти"/"Подняться"/"Выйти" срабатывала обратно почти
	# мгновенно. Если точка появления и так у края (а не намеренно
	# центральный spawn_x вроде кровати в спальне — её не трогаем), сдвигаем
	# на ширину героя вглубь комнаты, к центру — не жёстко вправо/влево,
	# двери бывают и слева (hall), и справа (bedroom, workshop).
	const EDGE_FRAC := 0.20
	if frac < EDGE_FRAC or frac > 1.0 - EDGE_FRAC:
		var inset_frac: float = (HERO_W * HERO_SCALE) / maxf(1.0, _room_width_px)
		frac += inset_frac if frac < 0.5 else -inset_frac
		frac = clampf(frac, 0.0, 1.0)
	_hero_x_px = clampf(frac, 0.0, 1.0) * _room_width_px
	_hold_left = false
	_hold_right = false
	_walk_dir = 0
	# БАГ (найден скриншотом при проверке новой сцены "robert", см. отчёт):
	# сигнатура пустой активной кнопки ТОЖЕ пустая строка ("|".join([]) в
	# _signature_for) — сброс в "" здесь совпадал с ней, "sig != _hotspot_
	# signature" читалось как "ничего не изменилось", и _update_hotspots()
	# пропускала _clear_hotspots(): кнопки прежней комнаты (например,
	# "Верстак" мастерской) оставались висеть на экране, стоило герою попасть
	# в комнату, где рядом с точкой входа вовсе нет хотспотов. "@"-сигил —
	# тот же приём, что уже используют "@locked"/"@sleeping" ниже: реальная
	# сигнатура (склейка action-строк точек) никогда не начинается с "@".
	_hotspot_signature = "@room_changed"
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
	_bg_declared_size = size
	_apply_room_width()
	_floor_y_px = HouseRoomsConfig.floor_y(_room_id) * STAGE_HEIGHT


## Пересчитывает _room_width_px/размер фона из уже загруженного
## _bg_declared_size и ЖИВОЙ _view_w — общая часть _load_background() (после
## реальной загрузки картинки) и _refresh_view_w() (когда картинка не
## менялась, изменился только вьюпорт): второму незачем перечитывать файл с
## диска ради пересчёта одних чисел.
func _apply_room_width() -> void:
	var h: float = maxf(1.0, _bg_declared_size.y)
	var scale_to_stage: float = STAGE_HEIGHT / h
	_room_width_px = maxf(_view_w, _bg_declared_size.x * scale_to_stage)
	_bg.size = Vector2(_room_width_px, STAGE_HEIGHT)
	_bg_fallback.size = Vector2(_room_width_px, STAGE_HEIGHT)


## Живое чтение ширины вьюпорта (см. VIEW_W выше) — тот же приём, что
## cutscene_player.gd:_relayout_if_resized()/_last_vp, под именами этого
## файла. Вызывается и из go_to_room() (до первого кадра), и из refresh()
## (каждый кадр, пока дом открыт) — оба места дешёвы при отсутствии ресайза:
## сравнение с уже известной шириной и выход, без пересчёта размеров фона.
func _refresh_view_w() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null:
		return
	var w: float = vp.get_visible_rect().size.x
	if w <= 0.0 or is_equal_approx(w, _view_w):
		return
	_view_w = w
	if not _room_id.is_empty():
		_apply_room_width()


# ---------------------------------------------------------------------------
# Кадр: ходьба, камера, хотспоты, заголовок
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible:
		return
	if _is_locked():
		_walk_dir = 0
		_hold_left = false
		_hold_right = false
	else:
		_hold_left = _walk_left_btn != null and _walk_left_btn.is_pressed()
		_hold_right = _walk_right_btn != null and _walk_right_btn.is_pressed()
		_update_walk(delta)

	_update_npc(delta)
	if _knock_t >= 0.0:
		_knock_t += delta
		if _knock_t > KNOCK_TOTAL:
			_knock_t = -1.0
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
	_refresh_view_w()
	_refresh_header()
	_apply_night_dim()
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

	# Единственный источник правды о часе — DayCycle (см. scripts/core/
	# day_cycle.gd): он же красит небо/светила/звёзды, и часы на стене дома
	# обязаны показывать то же самое время, а не пересчитывать его заново
	# без стартового сдвига на 6 утра (задание владельца: "картинки фона и
	# дома по умолчанию — 6 утра").
	var day_cycle := get_node_or_null("/root/DayCycle")
	var day: int = day_cycle.day if day_cycle != null else 1
	var hour_f: float = day_cycle.hour if day_cycle != null else 6.0
	var hour := int(hour_f)
	var minute := int((hour_f - floor(hour_f)) * 60.0)
	_day.text = str(day)
	_clock.text = "%02d:%02d" % [hour, minute]
	if _room_icon != null and String(_room_icon.get_meta("_room", "")) != _room_id:
		_room_icon.set_meta("_room", _room_id)
		Tip.bind(_room_icon, String(ROOM_NAMES.get(_room_id, "Дом")))

	if _notice != null and Time.get_ticks_msec() > _notice_until_msec:
		_notice.text = ""
		_notice.visible = false


## Ночь дома читается мягче, чем на улице (задание владельца: "мягче:
## exposure 0.5" против уличных 0.2 из DayCycle.grade()) — интерьер и так
## искусственно освещён лампой, полностью гасить его как забор с горой не
## нужно. Трогает только фон комнаты (_bg/_bg_fallback): герой и окна-панели
## (магазин, форс-экран обучения, кнопки) остаются как есть — задание прямо
## просит не трогать окна.
func _apply_night_dim() -> void:
	var day_cycle := get_node_or_null("/root/DayCycle")
	var exposure := 1.0
	if day_cycle != null:
		# sky_dark() и grade() растут из одной и той же рампы DayCycle._phase()
		# (0 днём..1 ночью); sky_dark() всегда 0..0.9, поэтому деление на 0.9
		# восстанавливает саму фазу без нового публичного метода в DayCycle.
		var phase: float = day_cycle.sky_dark() / 0.9
		exposure = lerpf(1.0, 0.5, phase)
	var tint := Color(exposure, exposure, exposure, 1.0)
	if _bg != null:
		_bg.modulate = tint
	if _bg_fallback != null:
		_bg_fallback.modulate = tint


func _set_bar(id: String, fraction: float) -> void:
	var fill: ColorRect = _bars.get(id)
	if fill != null:
		fill.size = Vector2(42.0 * clampf(fraction, 0.0, 1.0), 4)


## Горизонтальный сдвиг камеры (левый край комнаты в кадре) — общая формула
## для героя (_update_camera_and_hero) и гостя (_position_npc): оба следуют
## за одной и той же камерой, которую водит герой, а не NPC.
func _camera_x() -> float:
	return clampf(_hero_x_px - _view_w / 2.0, 0.0, maxf(0.0, _room_width_px - _view_w))


func _update_camera_and_hero() -> void:
	var cam_x: float = _camera_x()
	_bg.position.x = -cam_x
	_bg_fallback.position.x = -cam_x

	_update_hero_frame()
	var screen_x: float = _hero_x_px - cam_x
	# Масштаб растёт от левого верхнего угла, поэтому и ширина, и высота, и
	# отступ подошвы считаются уже увеличенными — иначе герой уедет вправо и
	# провалится под пол.
	# Кадр мальчика по эталону обрезан по рисунку (HeroSheets): ширина и линия
	# земли — из геометрии листа, ось по-прежнему середина кадра.
	var hw: float = _hero_frame_u.x
	var feet: float = _hero_frame_u.y
	_hero.position = Vector2(screen_x - hw * HERO_SCALE / 2.0,
		_floor_y_px - feet * HERO_SCALE)
	_hero.flip_h = _facing < 0
	_position_npc()
	_update_door_props(cam_x)


func _update_hero_frame() -> void:
	var moving := _walk_dir != 0 and not _is_locked()
	var sheet: Texture2D = _walk_sheet if (moving and _walk_sheet != null) else _idle_sheet
	if sheet == null:
		_hero.texture = null
		return
	# Листы мальчика по эталону (раунд 4) — 8 текселей на точку и несколько
	# рядов (HeroSheets); кадр тот же 48×48 точек с линией земли 46.
	var inf: Dictionary = HeroSheets.info_for(sheet)
	var sc: float = HeroSheets.scale_of(inf)
	var frame_w := int(inf["fw"]) if not inf.is_empty() else int(HERO_W * sc)
	var frame_count: int = HeroSheets.frames_of(inf) if not inf.is_empty() \
			else maxi(1, int(sheet.get_width()) / frame_w)
	var idx := 0
	if moving:
		idx = int(_walk_frame_t * WALK_FPS) % frame_count
	if sheet == _cur_frame_sheet and idx == _cur_frame_idx:
		return
	_cur_frame_sheet = sheet
	_cur_frame_idx = idx
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = HeroSheets.region(inf, idx) if not inf.is_empty() \
			else Rect2(idx * frame_w, 0, frame_w, int(HERO_H * sc))
	_hero.texture = atlas
	var fw: float = float(inf["fw"]) if not inf.is_empty() else HERO_W * sc
	var fh: float = float(inf["fh"]) if not inf.is_empty() else HERO_H * sc
	_hero.size = Vector2(fw, fh)
	_hero.scale = Vector2(HERO_SCALE / sc, HERO_SCALE / sc)
	_hero_frame_u = Vector2(fw / sc, float(inf["ground"]) / sc if not inf.is_empty() else HERO_H - FOOT_PAD)
	HeroSheets.crisp(_hero, inf)


# ---------------------------------------------------------------------------
# NPC-гость (не герой) — Роберт и подобные сюжетные визиты, см. поля выше.
# Зовётся снаружи катсценой (scripts/story/cutscene_player.gd, через
# scripts/house/house_system.gd), сам дом NPC не заводит.
# ---------------------------------------------------------------------------

## Показывает гостя в открытой комнате. idle_tex обязателен (без базовой позы
## NPC не показываем — это решает сама катсцена, см. её _house_npc_show);
## walk_tex может быть null (актёр без листа ходьбы, как Роберт сейчас —
## art/character/robert/ есть idle.png и talk.png, walk.png нет): гость тогда
## просто едет статичной позой, вместо ног перебирающих кадры, — тот же
## деградационный приём, что и у классического "show"/"hide" с enter/exit_to,
## когда лист ходьбы актёра отсутствует (см. cutscene_player.gd:_show_actor).
func show_npc(idle_tex: Texture2D, walk_tex: Texture2D, x_fraction: float, flip: bool = false) -> void:
	if idle_tex == null:
		return
	if _npc == null:
		_npc = TextureRect.new()
		_npc.name = "Npc"
		_npc.stretch_mode = TextureRect.STRETCH_KEEP
		_npc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_npc.size = Vector2(HERO_W * ART_SCALE, HERO_H * ART_SCALE)
		_npc.scale = Vector2(HERO_SCALE / ART_SCALE, HERO_SCALE / ART_SCALE)
		_stage.add_child(_npc)
		# НИЖЕ героя в дереве: если оба окажутся в одной точке, герой игрока
		# не должен прятаться под гостем.
		_stage.move_child(_npc, _hero.get_index())
	_npc_idle_tex = idle_tex
	_npc_walk_tex = walk_tex
	_npc_facing = -1 if flip else 1
	_npc_x_px = clampf(x_fraction, 0.0, 1.0) * _room_width_px
	_npc_from_px = _npc_x_px
	_npc_target_px = -1.0
	_npc_walk_left = 0.0
	_npc_frame_t = 0.0
	_npc.visible = true
	_update_npc(0.0)


## Ведёт гостя к x_fraction (доля 0..1 ширины комнаты) за seconds секунд —
## тем же приёмом, что world_walk у WorldActor: секунды задаёт кадр сцены, а
## не константа скорости, дому спорить с постановщиком незачем.
func npc_walk_to(x_fraction: float, seconds: float) -> void:
	if _npc == null:
		return
	_npc_from_px = _npc_x_px
	_npc_target_px = clampf(x_fraction, 0.0, 1.0) * _room_width_px
	_npc_walk_total = maxf(0.05, seconds)
	_npc_walk_left = _npc_walk_total
	_npc_facing = 1 if _npc_target_px >= _npc_from_px else -1


func hide_npc() -> void:
	if _npc != null:
		_npc.visible = false
	_npc_target_px = -1.0
	_npc_walk_left = 0.0


func _update_npc(delta: float) -> void:
	if _npc == null or not _npc.visible:
		return
	var moving := false
	if _npc_walk_left > 0.0:
		_npc_walk_left = maxf(0.0, _npc_walk_left - delta)
		var t: float = 1.0 - clampf(_npc_walk_left / _npc_walk_total, 0.0, 1.0)
		_npc_x_px = lerpf(_npc_from_px, _npc_target_px, t)
		moving = true
		if _npc_walk_left <= 0.0:
			_npc_x_px = _npc_target_px
	if moving:
		_npc_frame_t += delta
	else:
		_npc_frame_t = 0.0
	var sheet: Texture2D = _npc_walk_tex if (moving and _npc_walk_tex != null) else _npc_idle_tex
	if sheet == null:
		_npc.texture = null
	else:
		var frame_w := int(HERO_W * ART_SCALE)
		var frame_count: int = maxi(1, int(sheet.get_width()) / frame_w)
		var idx := 0
		if moving:
			idx = int(_npc_frame_t * WALK_FPS) % frame_count
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(idx * frame_w, 0, frame_w, int(HERO_H * ART_SCALE))
		_npc.texture = atlas
	_npc.flip_h = _npc_facing < 0
	_position_npc()


## Экранная позиция гостя — та же камера (_camera_x), тот же пол
## (_floor_y_px), что у героя (_update_camera_and_hero); зовётся и из
## _update_npc, и из _update_camera_and_hero (когда меняется только камера, а
## гость сам стоит на месте — иначе он отставал бы от панорамы на кадр).
func _position_npc() -> void:
	if _npc == null:
		return
	var cam_x: float = _camera_x()
	var screen_x: float = _npc_x_px - cam_x
	_npc.position = Vector2(screen_x - HERO_W * HERO_SCALE / 2.0,
		_floor_y_px - (HERO_H - FOOT_PAD) * HERO_SCALE)


func is_npc_visible() -> bool:
	return _npc != null and _npc.visible


func is_npc_walking() -> bool:
	return _npc_walk_left > 0.0


func npc_x_fraction() -> float:
	return _npc_x_px / maxf(1.0, _room_width_px)


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
	var btn := HouseBubble.create(def, float(_hotspot_buttons.size()) * 0.25)
	# Долгое нажатие показывает подсказку, а отпускание всё равно «нажимает»:
	# без этой проверки Tip заодно увёл бы героя через дверь.
	btn.pressed.connect(func():
		if not Tip.swallowed():
			_fire(def))
	_hotspot_layer.add_child(btn)
	return btn


## Кнопки всегда всплывают НАД ГЕРОЕМ (решение владельца), не над самой
## точкой на фоне: несколько пузырей ложатся в ряд вокруг его макушки.
func _position_hotspot_buttons() -> void:
	var n := _hotspot_buttons.size()
	if n == 0:
		return
	var hero_center_x: float = _hero.position.x + _hero_frame_u.x * HERO_SCALE / 2.0
	# Над макушкой, а не над рамкой кадра: в кадре 48×48 у героя сверху шесть
	# пустых пикселей, и после увеличения это уже тридцать — пузырь висел бы
	# заметно выше головы. Кончик хвостика — в паре точек над макушкой.
	# (Рост героя 40 точек: макушка — на 40 выше линии земли кадра.)
	var top_y: float = _hero.position.y + (_hero_frame_u.y - 40.0) * HERO_SCALE - HouseBubble.H - 2.0
	var gap := 6.0
	var total := float(n) * HouseBubble.W + gap * float(n - 1)
	var hi: float = maxf(4.0, _view_w - total - 4.0)
	var start_x: float = clampf(hero_center_x - total / 2.0, 4.0, hi)
	for i in range(n):
		var b: Button = _hotspot_buttons[i]
		b.position = Vector2(start_x + float(i) * (HouseBubble.W + gap), maxf(top_y, 2.0))
	_update_bubble_dynamic()


## Живые числа на пузырях: сколько порций ждёт у двери, что даст сон.
## Подсказку и цифру трогаем, только когда они поменялись — Tip перерисовывается
## при каждом bind, а кадров в секунду много.
func _update_bubble_dynamic() -> void:
	for b in _hotspot_buttons:
		var bubble := b as HouseBubble
		if bubble == null or not is_instance_valid(bubble):
			continue
		var action := String(bubble.get_meta("action", ""))
		var extra := ""
		var dim := false
		if action == "take_delivery":
			var n := HouseFood.food_at_door_count()
			extra = "Порций у двери: %d" % n
			bubble.set_count(n)
		elif action == "sleep":
			var plan := HouseSleep.plan(GameState.stamina, GameState.hunger)
			if bool(plan["ok"]):
				extra = "%d ч · бодрость +%d%% · сытость −%d%%" % [
					int(round(float(plan["hours"]))), int(round(float(plan["stamina_gain"]))),
					int(round(float(plan["hunger_cost"])))]
				# сон лечит (раунд 4): сытым — в полную силу, голодным — слабее
				if float(plan.get("hp_gain", 0.0)) >= 1.0:
					extra += " · здоровье +%d%%" % int(round(float(plan["hp_gain"])))
			else:
				extra = String(plan["reason"])
				dim = true
		else:
			continue
		var sig := "%s|%s" % [extra, dim]
		if String(bubble.get_meta("_dyn", "")) == sig:
			continue
		bubble.set_meta("_dyn", sig)
		bubble.set_tip_extra(extra)
		bubble.set_state("dim" if dim else "normal")


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
		Sfx.play("door")
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
## визуальная часть. hours — длина сна в игровых часах (для бегущих часов),
## skippable — показать кнопку «пропустить за ролик» (из сюжета её нет).
func play_sleep_animation(seconds: float, hours: float = 0.0, skippable: bool = false) -> void:
	_sleeping = true
	if _sleep_fx != null:
		_sleep_fx.play(seconds, hours, skippable)
	_hotspot_signature = "@sleeping"
	_clear_hotspots()


func stop_sleep_animation() -> void:
	_sleeping = false
	if _sleep_fx != null:
		_sleep_fx.stop()


## Курьер стучит у входной двери салона. Возвращает true, если ролик пошёл
## (мы в салоне и движения не урезаны): тогда звук ударов дом играет сам, по
## ходу ролика; иначе вызывающему остаётся один глухой стук.
func play_knock() -> bool:
	if not visible or _room_id != "hall" or Settings.reduce_motion:
		return false
	_knock_t = 0.0
	_knock_beats = 0
	return true


func is_knocking() -> bool:
	return _knock_t >= 0.0


func door_package_visible() -> bool:
	return _door_pack != null and _door_pack.visible


## Реквизит у двери: пакет с едой (пока она лежит) и курьер на время стука.
func _update_door_props(cam_x: float) -> void:
	if _door_pack == null:
		return
	var in_hall := _room_id == "hall"
	var door_px := float(HouseRoomsConfig.points("hall").get("front_door", {}).get("x", 0.09)) * _room_width_px
	var base_x := door_px - cam_x
	var waiting := HouseFood.food_at_door_count() > 0
	# Пока курьер не ушёл, пакета «ещё нет»: он появляется, когда курьер отходит.
	var show_pack := in_hall and waiting and (_knock_t < 0.0 or _knock_t >= KNOCK_BEATS[2] + 0.2)
	if show_pack and not _pack_shown:
		UiAnim.appear(_door_pack, 0.5, 0.2)
	_pack_shown = show_pack
	_door_pack.visible = show_pack
	_door_pack.position = Vector2(base_x + 24.0, _floor_y_px - 40.0)

	var knocking := in_hall and _knock_t >= 0.0
	_courier.visible = knocking
	_knock_icon.visible = knocking
	if not knocking:
		return
	var t := _knock_t
	# Курьер стоит прямо у двери (дверь бывает у самого края экрана — левее он
	# уехал бы за кадр) и приезжает/уезжает слева.
	var dx := -18.0
	var alpha := 1.0
	var leave_at: float = KNOCK_BEATS[2] + 0.25
	if t < 0.4:
		dx = lerpf(-110.0, -18.0, 1.0 - pow(1.0 - t / 0.4, 2.0))
	elif t > leave_at:
		var k := clampf((t - leave_at) / (KNOCK_TOTAL - leave_at), 0.0, 1.0)
		dx = lerpf(-18.0, -110.0, k * k)
		alpha = 1.0 - k
	_courier.position = Vector2(base_x + dx, _floor_y_px - 62.0)
	_courier.modulate.a = alpha
	# Удары: значок вспыхивает и звучит на каждый.
	var pop := 0.0
	for i in KNOCK_BEATS.size():
		var b: float = KNOCK_BEATS[i]
		if t >= b and t < b + 0.18:
			pop = 1.0 - (t - b) / 0.18
		if t >= b and _knock_beats == i:
			_knock_beats = i + 1
			Sfx.play("door")
			Haptics.thud()
	_knock_icon.position = Vector2(base_x + 8.0, _floor_y_px - 112.0)
	_knock_icon.scale = Vector2.ONE * (1.0 + 0.4 * pop)
	_knock_icon.modulate.a = alpha if t > 0.3 else 0.0


## Всплывающее число над макушкой героя («+2» после «Забрать»).
func float_at_hero(text: String, color: Color) -> void:
	if _hero == null:
		return
	var head := _hero.position + Vector2(_hero_frame_u.x * HERO_SCALE * 0.5 - 10.0,
			(_hero_frame_u.y - 40.0) * HERO_SCALE - 56.0)
	HouseArt.float_number(_stage, head, text, color)


func refresh_skip_counter() -> void:
	if _sleep_fx != null:
		_sleep_fx.refresh_skip()


## Для снимков экрана: поставить ролик сна на долю p.
func debug_sleep_progress(p: float) -> void:
	if _sleep_fx != null:
		_sleep_fx.debug_progress(p)


## Вспышки на полосках шапки после сна или еды: значок подпрыгивает, число
## всплывает. deltas — {"stamina": +62, "hunger": -30, "hp": +10} в процентах.
func flash_bars(deltas: Dictionary) -> void:
	var any_gain := false
	for id in deltas.keys():
		var icon := _bar_icons.get(id) as Control
		var amount := int(round(float(deltas[id])))
		if icon == null or amount == 0:
			continue
		var gain := amount > 0
		any_gain = any_gain or gain
		UiAnim.pulse(icon, 0.9, 0.5)
		var at := icon.get_global_rect().position + Vector2(-2, 12)
		HouseArt.float_number(_root, at - _root.get_global_rect().position,
			("+%d" if gain else "%d") % amount,
			ShopArt.COL_GOOD if gain else ShopArt.COL_BAD)
		if gain:
			ShopFx.sparkles(_root, icon.get_global_rect().get_center() - _root.get_global_rect().position,
				Color(1, 0.88, 0.4), 8, 16.0)
	if any_gain:
		Sfx.play("heal")


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
func set_forced(mode: String, text: String = "", button_text: String = "",
		title: String = "", icon_name: String = "") -> void:
	_forced_mode = mode
	if _forced != null:
		if mode != "":
			_forced.setup(HouseArt.tex(icon_name), 48.0, title if title != "" else button_text, text, button_text)
			_forced.open()
		else:
			_forced.close()
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

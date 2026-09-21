class_name CutscenePlayer
extends CanvasLayer
## Проигрыватель катсцен: читает список кадров из StoryData и показывает их
## поверх игры.
##
## Своя сцена, а не зум игровой камеры. Игровой мир нарисован тайлами 32×32 и
## показывает ровно семь клеток в ширину — деда, бабку и дом в него не
## поставить, а сцены интро происходят за три года до начала игры, когда
## никакого игрового мира ещё нет. Поэтому катсцена рисует собственный
## задник, землю и актёров, и ей не нужно, чтобы мир был загружен вообще.
##
## Тап работает в две ступени: первый дописывает реплику целиком, второй
## переводит на следующий кадр. Это стандарт жанра и он же спасает от
## случайного пролистывания текста двойным нажатием.
##
## Пропуск обязателен (см. задание): кнопка "Пропустить" мгновенно доигрывает
## сцену до конца. Побочные эффекты сцены (выдать кирку, поставить флаг) в
## кадрах НЕ живут — они лежат в scene.effects и применяются директором один
## раз по окончании, одинаково и при честном просмотре, и при пропуске.

signal finished(scene_id: String)

const LAYER := 100
const STAGE_TOP := 0.06        # доля высоты, где начинается "небо" сцены
const GROUND_LINE := 0.56      # доля высоты, на которой проходит линия земли
const BOX_H := 108.0           # высота реплики: шесть строк, длинные фразы не режутся
## Лист персонажа режется в ART_SCALE раз крупнее логических координат (см.
## tools/import_art.py:ART_SCALE и scripts/player/character_view.gd:CHAR_W) —
## реальный кадр 48×48 ЛОГИЧЕСКИХ пикселей занимает на диске 144×144.
## CHAR_FRAME раньше был "48" без поправки на ART_SCALE: это не будило бы
## ошибку явно (лист резался на 48-пиксельные ломти, arithmetически честно),
## но резало кадр НЕ по границам настоящих поз, а поперёк них — на 12 узких
## горизонтальных полосок вместо 4-6 нарисованных кадров. Актёр на сцене
## оставался неподвижным огрызком тела вместо дыхания/шага/замаха, и ровно
## это владелец увидел как "анимации сценариев отсутствуют".
const ART_SCALE := 3.0
const TILE := 32.0     # клетка мира в логических px — см. player.gd/world_actor.gd
const CHAR_FRAME := int(48 * ART_SCALE)
const TYPE_CHARS_PER_SEC := 42.0
const ANIM_FPS := 7.0

var scene_id: String = ""
var is_playing: bool = false

## Режим "мир" (см. play(id, opts)): сцена НЕ рисует свои небо/землю/актёров
## (_sky/_ground спрятаны, _stage не используется) — вместо этого поверх
## ЖИВОЙ игровой карты работают world_actor/world_walk/world_dig/world_fall
## (актёры — scripts/story/world_actor.gd) и настоящая копка через
## world.dig_cell. Единственные 11 сцен обучения на классическом режиме не
## трогает: у них opts.world нет, is_world_scene(id) для них false.
var world_mode: bool = false
## Ссылки, которые режиссёр выставляет перед play() (см. story_director.gd:
## cutscene.world = world; cutscene.player = player) — без них world_*
## кадры молча ничего не делают (see _run_beat), сцена не падает.
var world: WorldGen = null
var player: Node = null

## "house_enter"/"house_sleep" (см. _run_beat) — сцена показывает НАСТОЯЩИЙ
## интерьер дома (scripts/house/house_view.gd) вместо иллюстрации "mood
## room": та же комната, что видит игрок, физически зайдя внутрь. В отличие
## от world_mode, симметричного выхода на "clear" нет — сцена, вошедшая в
## дом, обычно в нём и заканчивается (см. эффект "enter_house" у сцены
## death в data/story.json), поэтому house_mode нарочно не гасится
## автоматически.
var house_mode: bool = false
var _house_sleep_left: float = 0.0

var _beats: Array = []
var _index: int = 0
var _beat_timer: float = 0.0     # сколько ещё держать кадр с автопереходом
var _waiting_tap: bool = false
var _typing: bool = false
var _anim_time: float = 0.0

# --- узлы ---
var _root: Control
var _sky: ColorRect
var _ground: TextureRect
var _backdrop_fence: TextureRect = null  # см. set_backdrop_era() — создаётся лениво
var _stage: Control
var _card: Label
var _box: Panel
var _speaker: Label
var _line: Label
var _next_hint: Label
var _skip_btn: Button
var _fade: ColorRect
var _item_card: Control
var _item_icon: TextureRect
var _item_name: Label
var _item_text: Label
var _tap_target: Control

var _actors: Dictionary = {}     # actor_id -> {node: TextureRect, frames:int, pose:String}
var _props: Dictionary = {}      # prop_id  -> TextureRect
var _moves: Array = []           # активные сдвиги актёров: {node, left, per_sec}
var _shake_left: float = 0.0
var _daynight_left: float = 0.0
var _daynight_step: float = 0.0
var _daynight_idx: int = 0
var _mood_id: String = "dark"
var _last_vp: Vector2 = Vector2.ZERO

# --- небо DayCycle (задание владельца: катсцены тоже могут жить по общим
# игровым часам — например, интро деда гонит 6:00 -> 22:00 за время показа
# через DayCycle.set_hour()/set_time_scale()). Выключено по умолчанию: без
# явного use_day_cycle(true) катсцена красит небо moods-таблицей, как раньше
# — ни одна существующая сцена не переписывается этим агентом.
var _use_day_cycle: bool = false
var _sky_view: SkyView = null

# "Рост": пролистывание поз актёра (развёртка пацана 8-15 лет в intro_boy) —
# та же механика, что и daynight (автоматический таймер держит кадр), но
# вместо смены цвета неба меняет pose актёра через _show_actor.
var _grow_left: float = 0.0
var _grow_step: float = 0.0
var _grow_idx: int = -1
var _grow_actor: String = ""
var _grow_poses: Array = []
var _grow_at: String = "center"
var _grow_scale: float = 2.0
var _grow_flip: bool = false

# Вход/выход актёра со сцены пешком: "show" с полем "enter" и "hide" с полем
# "exit_to" задают КРАЙ сцены (far_left/left/center/right/far_right), откуда
# актёр появляется или куда уходит. Сдвиг накапливается в actors[id].dx —
# отдельно от вертикального actors[id].dy (падение в шахту) — и гасится этим
# тикером с кубическим ease-out (человек тормозит перед остановкой, а не
# бьётся о стену).
var _slides: Array = []   # {"actor":id, "left":sec, "total":sec, "from_dx":float, "to_dx":float, "then_free":bool}

# ---------------------------------------------------------------------------
# Режим "мир" (world_mode) — актёры и копка на живой карте, см. заголовок.
# ---------------------------------------------------------------------------
var _world_actors: Dictionary = {}   # actor_id -> WorldActor
## Статичные предметы на живой карте (могила и подобное) — тот же приём, что
## world_actor, но проще: один спрайт без поз/кадров/разворота (владелец,
## 2026-09-21: "она хоронит его на реальной карте слева от лачуги" — могиле
## не нужна анимация, только положение в клетках).
var _world_props: Dictionary = {}    # prop_id -> Sprite2D
var _world_dug_cells: Array = []     # [Vector2i, ...] — что реально выкопали за сцену
var _camera_actor_id: String = ""    # чей x/y зеркалится в player.x/y (камера/туман идут за героем)
var _world_walk: Dictionary = {}     # {"actor","from","to","left","total","arrive_pose"} или {}
var _world_dig: Dictionary = {}      # {"actor","cell":Vector2i,"left","total"} или {}
## "world_dig_row" — быстрая промотка целого ряда (решение владельца
## 2026-09-21: "копает y1 от x15 и до конца... все тайлы, что он копает,
## должны пропадать"), не одна клетка за раз, а сплошной проезд по ряду с
## копкой каждой клетки на ходу — {"actor","y","from_x","to_x","left",
## "total","dug_up_to"} или {}. dug_up_to — крайний уже выкопанный x
## (эксклюзивно по направлению), чтобы не копать одну клетку дважды, если
## физтик перепрыгнул сразу через несколько клеток экрана.
var _world_dig_row: Dictionary = {}
var _world_fall: Dictionary = {}     # {"actor","from","to","left","total"} или {}
## Последний час, выставленный кадром "clock" — публично, чтобы тесты могли
## проверить ход времени сцены даже там, где автозагрузки /root/DayCycle ещё
## нет (см. GDD-контракт DayCycle в задании, узел параллельного агента).
var current_clock_hour: float = -1.0


func _init() -> void:
	layer = LAYER
	# Катсцена показывается и когда всё остальное поставлено на паузу
	# (сцена смерти останавливает игровой цикл), иначе текст замирает.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build()
	_root.visible = false


# ---------------------------------------------------------------------------
# Построение интерфейса сцены
# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Cutscene"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_sky = ColorRect.new()
	_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky.color = Color8(0x0B, 0x08, 0x06)
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_sky)

	# Землю мостим настоящим тайлом земли: катсцена должна выглядеть из той же
	# игры, а не как отдельная презентация со сплошной заливкой.
	_ground = TextureRect.new()
	_ground.stretch_mode = TextureRect.STRETCH_TILE
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://art/tiles/dirt_1.png"):
		_ground.texture = load("res://art/tiles/dirt_1.png")
	_root.add_child(_ground)

	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stage)
	# Земля рисуется ПОВЕРХ актёров: так проваливающийся в яму дед уходит под
	# грунт, а не съезжает по нему. Стоящих это не задевает — ступни лежат
	# ровно на линии земли, ниже в кадре только прозрачный запас.
	_root.move_child(_ground, _stage.get_index() + 1)

	_card = Label.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.autowrap_mode = TextServer.AUTOWRAP_WORD
	_card.add_theme_font_size_override("font_size", 15)
	_card.add_theme_color_override("font_color", Color8(0xE8, 0xDC, 0xC0))
	_card.visible = false
	_root.add_child(_card)

	_build_item_card()
	_build_box()
	_build_tap_target()

	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)

	_skip_btn = Button.new()
	_skip_btn.text = StoryText.get_text("ui.skip")
	_skip_btn.add_theme_font_size_override("font_size", 9)
	_skip_btn.pressed.connect(skip)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.border_color = Color8(0x9D, 0x8B, 0x73)
	sb.set_border_width_all(1)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	for state in ["normal", "hover", "pressed", "focus"]:
		_skip_btn.add_theme_stylebox_override(state, sb)
	_skip_btn.add_theme_color_override("font_color", Color8(0xC8, 0xB8, 0x9A))
	_root.add_child(_skip_btn)


func _build_box() -> void:
	_box = Panel.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.035, 0.027, 0.94)
	sb.border_color = Color8(0xE0, 0xA9, 0x3B)
	sb.border_width_left = 3
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_right = 1
	_box.add_theme_stylebox_override("panel", sb)
	_root.add_child(_box)

	_speaker = Label.new()
	_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speaker.position = Vector2(9, 4)
	_speaker.add_theme_font_size_override("font_size", 10)
	_speaker.add_theme_color_override("font_color", Color8(0xE0, 0xA9, 0x3B))
	_box.add_child(_speaker)

	_line = Label.new()
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	_line.add_theme_font_size_override("font_size", 11)
	_line.add_theme_color_override("font_color", Color8(0xE8, 0xDC, 0xC0))
	_box.add_child(_line)

	_next_hint = Label.new()
	_next_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_hint.text = StoryText.get_text("ui.tap_to_continue")
	_next_hint.add_theme_font_size_override("font_size", 8)
	_next_hint.add_theme_color_override("font_color", Color8(0x9D, 0x8B, 0x73))
	_next_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_box.add_child(_next_hint)


func _build_item_card() -> void:
	_item_card = Control.new()
	_item_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_card.visible = false
	_root.add_child(_item_card)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.05, 0.96)
	sb.border_color = Color8(0xE0, 0xA9, 0x3B)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_card.add_child(panel)

	_item_icon = TextureRect.new()
	_item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_card.add_child(_item_icon)

	_item_name = Label.new()
	_item_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	_item_name.add_theme_font_size_override("font_size", 13)
	_item_name.add_theme_color_override("font_color", Color8(0xE0, 0xA9, 0x3B))
	_item_card.add_child(_item_name)

	_item_text = Label.new()
	_item_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_item_text.add_theme_font_size_override("font_size", 10)
	_item_text.add_theme_color_override("font_color", Color8(0xC8, 0xB8, 0x9A))
	_item_card.add_child(_item_text)


## Подсветка цели обязательного тапа (кровать, батончик). Обучение действием:
## игрок должен сам нажать, а не прочитать "нажми кровать" и пойти дальше.
func _build_tap_target() -> void:
	_tap_target = Control.new()
	_tap_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tap_target.visible = false
	_tap_target.draw.connect(func():
		var r := Rect2(Vector2.ZERO, _tap_target.size)
		var pulse: float = 0.45 + 0.35 * sin(float(Time.get_ticks_msec()) / 180.0)
		_tap_target.draw_rect(r, Color(0.88, 0.66, 0.23, 0.12 * pulse), true)
		_tap_target.draw_rect(r, Color(0.88, 0.66, 0.23, pulse), false, 2.0)
	)
	_root.add_child(_tap_target)


# ---------------------------------------------------------------------------
# Раскладка (портрет 224×480, но размер вьюпорта в вебе плавает)
# ---------------------------------------------------------------------------

## Включает/выключает освещение по DayCycle вместо статичных moods (см.
## поле _use_day_cycle выше). Звёзды/солнце/месяц — тот же SkyView, что и в
## мире (scripts/world/sky_view.gd): один код рисования, не два. Узел
## создаётся лениво при первом включении и просто прячется при выключении
## (сцена может переключаться туда-обратно, если сценарий это попросит).
func use_day_cycle(enabled: bool) -> void:
	_use_day_cycle = enabled
	if enabled and _sky_view == null:
		_sky_view = preload("res://scripts/world/sky_view.gd").new()
		_sky_view.name = "SkyView"
		_root.add_child(_sky_view)
		# Сразу после _sky (плоский фон-подложка) и перед _ground/_stage —
		# светила и звёзды поверх цвета неба, но под землёй и актёрами.
		_root.move_child(_sky_view, _sky.get_index() + 1)
		if _last_vp != Vector2.ZERO:
			_layout()
	if _sky_view != null:
		_sky_view.visible = enabled


func _relayout_if_resized() -> void:
	if get_viewport().get_visible_rect().size != _last_vp:
		_layout()


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_last_vp = vp
	_root.size = vp
	_root.position = Vector2.ZERO

	var ground_y: float = vp.y * GROUND_LINE
	_ground.position = Vector2(0, ground_y)
	_ground.size = Vector2(vp.x, vp.y - ground_y)
	if _sky_view != null:
		_sky_view.position = Vector2.ZERO
		_sky_view.set_scene_rect(vp.x, ground_y, 0.0)

	_stage.position = Vector2(0, vp.y * STAGE_TOP)
	_stage.size = Vector2(vp.x, ground_y - vp.y * STAGE_TOP)

	if _backdrop_fence != null:
		# Полоса у самой линии земли — забор стоит на горизонте позади актёров,
		# а не занимает всю сцену (небо над ним остаётся плоской заливкой _sky,
		# катсцена не пытается нарисовать весь мир целиком).
		var band_h: float = (ground_y - vp.y * STAGE_TOP) * 0.5
		_backdrop_fence.position = Vector2(0, ground_y - band_h)
		_backdrop_fence.size = Vector2(vp.x, band_h)

	var box_h: float = BOX_H
	_box.position = Vector2(6, vp.y - box_h - 6)
	_box.size = Vector2(vp.x - 12, box_h)
	_line.position = Vector2(9, 21)
	_line.size = Vector2(_box.size.x - 18, box_h - 34)
	_next_hint.position = Vector2(_box.size.x - 52, box_h - 15)
	_next_hint.size = Vector2(44, 12)

	_card.position = Vector2(18, vp.y * 0.28)
	_card.size = Vector2(vp.x - 36, vp.y * 0.34)

	_item_card.position = Vector2(16, vp.y * 0.20)
	_item_card.size = Vector2(vp.x - 32, vp.y * 0.48)
	_item_icon.position = Vector2(_item_card.size.x / 2.0 - 24, 14)
	_item_icon.size = Vector2(48, 48)
	_item_name.position = Vector2(8, 68)
	_item_name.size = Vector2(_item_card.size.x - 16, 34)
	_item_text.position = Vector2(8, 104)
	_item_text.size = Vector2(_item_card.size.x - 16, _item_card.size.y - 112)

	_skip_btn.position = Vector2(vp.x - 72, 8)
	_skip_btn.size = Vector2(64, 20)

	_place_all()


## Левый край объекта шириной w, поставленного центром в center_x, но так,
## чтобы он целиком остался на экране.
func _fit_x(center_x: float, w: float) -> float:
	if w >= _stage.size.x:
		return (_stage.size.x - w) / 2.0
	return clampf(center_x - w / 2.0, 0.0, _stage.size.x - w)


func _stage_x(at: String) -> float:
	var w := _stage.size.x
	match at:
		"far_left": return w * 0.10
		"left": return w * 0.26
		"center": return w * 0.50
		"right": return w * 0.74
		"far_right": return w * 0.90
	return w * 0.5


# ---------------------------------------------------------------------------
# Публичное API
# ---------------------------------------------------------------------------

## opts.world == true — режим "мир" (см. заголовок файла и заголовок блока
## world_mode выше): сцена играет поверх живой карты, а не в своей
## декорации. Классические сцены вызывают play(id) без второго аргумента —
## поведение для них не меняется ни на бит.
func play(id: String, opts: Dictionary = {}) -> void:
	scene_id = id
	_beats = StoryData.beats(id)
	_index = 0
	_beat_timer = 0.0
	_waiting_tap = false
	_typing = false
	_shake_left = 0.0
	_daynight_left = 0.0
	_moves.clear()
	current_clock_hour = -1.0
	_clear_stage()
	_fade.color = Color(0, 0, 0, 0)
	_skip_btn.text = StoryText.get_text("ui.skip")
	is_playing = true
	_root.visible = true

	# Опциональное поле сцены "era" (data/story.json) — те же подложки забора,
	# что и в живом мире (scripts/world/backdrop.gd), позади актёров вместо
	# сплошной заливки _sky. Явно НЕ трогаем сцены без этого поля — 11 из 12
	# сцен его не задают и продолжают выглядеть ровно как раньше (задание:
	# "не переписывай сцены"). Сейчас поле стоит только у intro_grandpa.
	# В режиме мира (opts.world) свой забор НЕ создаём: он лежал бы в этом же
	# CanvasLayer поверх живой карты и закрывал бы актёров (дед пропадал за
	# полосой забора) — эпоху живого задника там переключает
	# _enter_world_mode через Backdrop.set_era.
	var scene_data := StoryData.scene(id)
	var world_mode := bool(opts.get("world", false))
	if scene_data.has("era") and not world_mode:
		set_backdrop_era(String(scene_data.get("era")))
	else:
		set_backdrop_era("")

	_layout()
	if bool(opts.get("world", false)):
		_enter_world_mode(String(scene_data.get("era", "now")))
	_advance()


## Показывает фон scripts/world/backdrop.gd (текстуры art/env/backdrop_fence_*)
## позади актёров вместо сплошной заливки _sky. era: "now" — белый забор
## (сейчас), "grandpa" — старый деревянный (интро деда), "" — снова прячет
## подложку и возвращает обычную сплошную заливку. Публичный метод — вызывать
## можно и из самой сцены (например, если катсцена меняет эпоху кадром), не
## только из play().
func set_backdrop_era(era: String) -> void:
	if era.is_empty():
		if _backdrop_fence != null:
			_backdrop_fence.visible = false
		return
	_ensure_backdrop_fence()
	var path := "res://art/env/backdrop_fence_old.png" if era == "grandpa" \
			else "res://art/env/backdrop_fence_white.png"
	if not ResourceLoader.exists(path):
		_backdrop_fence.visible = false
		return
	_backdrop_fence.texture = load(path)
	_backdrop_fence.visible = true


## Создаётся один раз при первом обращении — 11 из 12 сцен ни разу не вызовут
## set_backdrop_era(), и для них в дереве сцены вообще не появится лишнего
## узла. Вставляется сразу за _sky (перед _stage/_ground), так что стоит
## позади актёров и не мешает "земля рисуется поверх актёров" ниже.
func _ensure_backdrop_fence() -> void:
	if _backdrop_fence != null:
		return
	_backdrop_fence = TextureRect.new()
	_backdrop_fence.name = "BackdropFence"
	_backdrop_fence.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# Без EXPAND_IGNORE_SIZE TextureRect подгоняет свой Control.size под
	# натуральный размер текстуры (960×192 текстурных px, ART_SCALE=3) в тот
	# момент, когда set_backdrop_era() назначает texture, — и затирает размер
	# полосы, выставленный в _layout() ниже.
	_backdrop_fence.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop_fence.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop_fence.visible = false
	_root.add_child(_backdrop_fence)
	_root.move_child(_backdrop_fence, _sky.get_index() + 1)
	_layout()


## Мгновенно доигрывает сцену: все оставшиеся кадры пропускаются, сигнал
## finished приходит как при обычном конце. Директор применит эффекты сцены
## сам — они не в кадрах, поэтому пропустить их нельзя даже случайно.
func skip() -> void:
	if not is_playing:
		return
	_finish()


## Прерывание без сигнала finished: сцена не считается показанной и её
## эффекты не применяются. Нужно кнопке "Сброс", которая обнуляет весь сюжет.
func abort() -> void:
	is_playing = false
	_root.visible = false
	_clear_stage()


func _finish() -> void:
	is_playing = false
	_root.visible = false
	_clear_stage()
	finished.emit(scene_id)


# ---------------------------------------------------------------------------
# Ход сцены
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	if not is_playing:
		return
	_relayout_if_resized()
	_anim_time += dt
	_tick_actor_frames()
	_tick_moves(dt)
	_tick_shake(dt)
	_tick_daynight(dt)
	_tick_grow(dt)
	_tick_slides(dt)
	_tick_world(dt)
	_tick_house_sleep(dt)
	# В самом конце — иначе mood/daynight, отработавшие чуть выше, перезапишут
	# цвет неба обратно и часы DayCycle не будет видно.
	_apply_day_cycle_sky()
	_next_hint.visible = _waiting_tap and not _typing and int(_anim_time * 2.0) % 2 == 0

	if _typing:
		_line.visible_ratio = min(1.0, _line.visible_ratio + (TYPE_CHARS_PER_SEC * dt) / maxf(1.0, float(_line.text.length())))
		if _line.visible_ratio >= 1.0:
			_typing = false
		return

	if _waiting_tap:
		return

	if _beat_timer > 0.0:
		_beat_timer -= dt
		if _beat_timer <= 0.0:
			_advance()


## Тап: первый — дописать реплику, второй — следующий кадр. Карточки с
## автопереходом тап тоже листает: ждать три секунды титра, который уже
## прочитан, скучно.
func _input(event: InputEvent) -> void:
	if not is_playing:
		return
	var pressed := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		pressed = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		pressed = st.pressed
		pos = st.position
	if not pressed:
		return

	if _skip_btn.get_global_rect().has_point(pos):
		return  # кнопку обрабатывает сама кнопка
	get_viewport().set_input_as_handled()

	if _typing:
		_line.visible_ratio = 1.0
		_typing = false
		return
	if _tap_target.visible:
		# Обязательный тап засчитывается только по подсвеченной цели.
		if _tap_target.get_global_rect().has_point(pos):
			_tap_target.visible = false
			_waiting_tap = false
			_advance()
		return
	_waiting_tap = false
	_beat_timer = 0.0
	_advance()


func _advance() -> void:
	while _index < _beats.size():
		var beat: Dictionary = _beats[_index]
		_index += 1
		if _run_beat(beat):
			return  # кадр взял управление (ждёт тапа/таймера)
	_finish()


## Возвращает true, если кадр удерживает сцену (ждёт тапа или времени).
func _run_beat(beat: Dictionary) -> bool:
	match String(beat.get("t", "")):
		"card":
			_show_card(StoryText.get_text(String(beat.get("text", ""))))
			_beat_timer = float(beat.get("sec", 3.0))
			return true
		"narr":
			_show_line("", StoryText.get_text(String(beat.get("text", ""))))
			return true
		"say":
			var who := String(beat.get("who", ""))
			_show_line(StoryText.get_text(StoryData.actor_speaker_key(who)),
				StoryText.get_text(String(beat.get("text", ""))))
			return true
		"show":
			_show_actor(beat)
			return false
		"hide":
			_hide_actor(beat)
			return false
		"prop":
			_show_prop(beat)
			return false
		"clear":
			_clear_stage()
			return false
		"mood":
			_set_mood(String(beat.get("id", "dark")))
			return false
		"wait":
			_hide_text()
			_beat_timer = float(beat.get("sec", 0.5))
			return true
		"fade":
			_start_fade(String(beat.get("dir", "out")), float(beat.get("sec", 0.8)))
			return true
		"item":
			_show_item(beat)
			return true
		"tap":
			_show_tap_target(beat)
			return true
		"move":
			_start_move(beat)
			return false
		"shake":
			_shake_left = float(beat.get("sec", 0.4))
			return false
		"daynight":
			_daynight_step = float(beat.get("sec", 0.7))
			_daynight_left = _daynight_step * float(beat.get("cycles", 3)) * 2.0
			_beat_timer = _daynight_left
			return true
		"grow":
			_start_grow(beat)
			return true
		"world_enter":
			# Вход в режим "мир" ПОСЕРЕДИНЕ сцены, а не только в её самом начале
			# (см. play(): там это делает opts.world до первого кадра) — сцены,
			# у которых часть моментов иллюстрированная (спальня, символический
			# реквизит), а часть — на настоящей карте (владелец, 2026-09-21:
			# "пусть все сюжетные моменты будут делаться на реальном фоне").
			# Симметричный выход — обычный "clear" (см. _clear_stage): он и так
			# гасит world_mode, если тот включён, независимо от того, как
			# именно сцена в него вошла.
			_enter_world_mode(String(beat.get("era", "now")))
			return false
		"world_actor":
			_world_place_actor(beat)
			return false
		"world_prop":
			_world_place_prop(beat)
			return false
		"world_walk":
			return _world_start_walk(beat)
		"world_dig":
			return _world_start_dig(beat)
		"world_dig_row":
			return _world_start_dig_row(beat)
		"world_fall":
			return _world_start_fall(beat)
		"clock":
			_do_clock(beat)
			return false
		"house_enter":
			_house_enter(beat)
			return false
		"house_sleep":
			return _house_start_sleep(beat)
	return false


# ---------------------------------------------------------------------------
# Кадры
# ---------------------------------------------------------------------------

func _show_card(text: String) -> void:
	_card.text = text
	_card.visible = true
	_box.visible = false
	_item_card.visible = false


func _show_line(speaker: String, text: String) -> void:
	_card.visible = false
	_item_card.visible = false
	_box.visible = true
	_speaker.text = speaker
	_speaker.visible = not speaker.is_empty()
	_line.position.y = 21.0 if not speaker.is_empty() else 10.0
	_line.text = text
	_line.visible_ratio = 0.0
	_typing = true
	_waiting_tap = true


func _hide_text() -> void:
	_card.visible = false
	_box.visible = false
	_item_card.visible = false


func _show_item(beat: Dictionary) -> void:
	_card.visible = false
	var icon_path := String(beat.get("icon", ""))
	_item_icon.texture = load(icon_path) if ResourceLoader.exists(icon_path) else null
	_item_name.text = StoryText.get_text(String(beat.get("name", "")))
	_item_text.text = StoryText.get_text(String(beat.get("text", "")))
	_item_card.visible = true
	_box.visible = false
	_waiting_tap = true


func _show_tap_target(beat: Dictionary) -> void:
	var prop_id := String(beat.get("prop", ""))
	var rect := Rect2(_root.size.x / 2.0 - 40, _root.size.y * 0.30, 80, 80)
	if _props.has(prop_id):
		var node: TextureRect = _props[prop_id]
		rect = Rect2(node.position + _stage.position - Vector2(6, 6), node.size + Vector2(12, 12))
	elif _item_card.visible:
		rect = Rect2(_item_card.position, _item_card.size)
	_tap_target.position = rect.position
	_tap_target.size = rect.size
	_tap_target.visible = true
	_show_line("", StoryText.get_text(String(beat.get("text", ""))))
	_typing = false
	_line.visible_ratio = 1.0
	_waiting_tap = true


func _start_fade(dir: String, sec: float) -> void:
	_hide_text()
	var to_black := dir == "out"
	var tween := create_tween()
	_fade.color = Color(0, 0, 0, 0.0 if to_black else 1.0)
	tween.tween_property(_fade, "color", Color(0, 0, 0, 1.0 if to_black else 0.0), sec)
	_beat_timer = sec


func _start_move(beat: Dictionary) -> void:
	var id := String(beat.get("actor", ""))
	if not _actors.has(id):
		return
	var sec: float = maxf(0.05, float(beat.get("sec", 0.8)))
	_moves.append({
		"actor": id,
		"left": sec,
		"per_sec": float(beat.get("dy", 0)) / sec,
	})


# ---------------------------------------------------------------------------
# Актёры и реквизит
# ---------------------------------------------------------------------------

## Загружает лист кадров позы pose в уже существующий узел актёра, не трогая
## его позицию/dx/dy. Общая часть "show" и переключения на позу ходьбы во
## время шага (см. _show_actor:enter, _hide_actor:exit_to, _tick_slides) —
## актёр не должен скользить по сцене статичной фигурой, пока идёт пешком.
func _load_pose(id: String, pose: String, flip: bool) -> bool:
	var path := StoryData.actor_sheet_path(id, pose)
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	var tex: Texture2D = load(path)
	# Кадры считаем только для листов с обычной квадратной сеткой 144×144
	# (idle/walk/fall/fly/fly_jet/dig_pick/dig_shovel/dig_drill_*). Бур
	# (dig_rig_*, кадр 240×168) и одиночная поза с компасом (48×89) сетке не
	# соответствуют — для них весь файл считается ОДНИМ кадром: неверный
	# делитель резал бы их на кривые ломти хуже, чем показ целиком.
	var frames: int = 1
	if int(round(tex.get_height())) == CHAR_FRAME and int(round(tex.get_width())) % CHAR_FRAME == 0:
		frames = maxi(1, int(round(tex.get_width() / float(CHAR_FRAME))))
	var node: TextureRect = _actors[id].node
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	var frame_w: float = tex.get_width() / float(frames)
	atlas.region = Rect2(0, 0, frame_w, tex.get_height())
	node.texture = atlas
	node.flip_h = flip
	_actors[id].frames = frames
	_actors[id].frame_w = frame_w
	_actors[id].tex_h = tex.get_height()
	_actors[id].pose = pose
	_actors[id].flip = flip
	return true


func _show_actor(beat: Dictionary) -> void:
	var id := String(beat.get("actor", ""))
	var pose := String(beat.get("pose", "idle"))
	var path := StoryData.actor_sheet_path(id, pose)
	if path.is_empty() or not ResourceLoader.exists(path):
		# Спрайта нет (Роберт, родители) — реплика идёт голосом за кадром.
		return
	var is_new := not _actors.has(id)
	var node: TextureRect
	if not is_new:
		node = _actors[id].node
	else:
		node = TextureRect.new()
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_stage.add_child(node)

	# dx/dy накапливают сдвиги от "move" (падение) и от входа/выхода пешком —
	# сохраняются при смене позы у УЖЕ стоящего актёра (иначе смена idle->dig
	# посреди сцены обнулила бы, например, ещё не долетевший вход).
	var prev_dx: float = float(_actors[id].get("dx", 0.0)) if _actors.has(id) else 0.0
	var prev_dy: float = float(_actors[id].get("dy", 0.0)) if _actors.has(id) else 0.0
	_actors[id] = {
		"node": node,
		"frames": 1, "frame_w": 1.0, "tex_h": 1.0,
		"at": String(beat.get("at", "center")),
		"scale": float(beat.get("scale", 2.0)),
		"dy": prev_dy,
		"dx": prev_dx,
	}
	var flip := bool(beat.get("flip", false))
	_load_pose(id, pose, flip)
	_place_actor(id)

	# Вход пешком: только для только что созданного узла — повторный "show"
	# с тем же id (смена позы) входа не переигрывает.
	var enter_from := String(beat.get("enter", ""))
	if is_new and not enter_from.is_empty():
		var a: Dictionary = _actors[id]
		var w: float = a.frame_w * a.scale / ART_SCALE
		var start_off: float = _fit_x(_stage_x(enter_from), w) - _fit_x(_stage_x(String(a.at)), w)
		_actors[id].dx = start_off
		_place_actor(id)
		var sec: float = maxf(0.05, float(beat.get("enter_sec", 0.7)))
		# Пока идёт вход, проигрываем позу ходьбы, если она у актёра есть —
		# без неё вход выглядел статичной фигурой, скользящей по сцене
		# боком, и это и было "скачет" в глазах владельца. По прибытии
		# _tick_slides возвращает позу, заказанную кадром "show".
		var walking := _load_pose(id, "walk", flip)
		if not walking:
			_load_pose(id, pose, flip)
		_place_actor(id)
		_slides.append({"actor": id, "left": sec, "total": sec,
			"from_dx": start_off, "to_dx": 0.0, "then_free": false,
			"arrive_pose": pose, "arrive_flip": flip, "walking": walking})


## exit_to (край сцены) в beat — актёр уходит пешком, узел освобождается
## после того, как доедет; без exit_to — прежнее поведение, убрать сразу.
func _hide_actor(beat: Dictionary) -> void:
	var id := String(beat.get("actor", ""))
	# Актёр режима "мир" (world_actor) живёт в отдельной таблице — см. блок
	# world_mode выше. "hide" одинаково убирает и классического актёра со
	# сцены, и мирового с живой карты: имена кадров не путаются, две таблицы
	# просто никогда не пересекаются по одному и тому же вызову.
	if _world_actors.has(id):
		_world_actors[id].queue_free()
		_world_actors.erase(id)
		if _camera_actor_id == id:
			_camera_actor_id = ""
		return
	if not _actors.has(id):
		return
	var exit_to := String(beat.get("exit_to", ""))
	if exit_to.is_empty():
		_actors[id].node.queue_free()
		_actors.erase(id)
		return
	var a: Dictionary = _actors[id]
	var w: float = a.frame_w * a.scale / ART_SCALE
	var to_off: float = _fit_x(_stage_x(exit_to), w) - _fit_x(_stage_x(String(a.at)), w)
	var sec: float = maxf(0.05, float(beat.get("exit_sec", 0.6)))
	# Пока уходит, тоже проигрываем позу ходьбы, если она есть (см. _show_actor:
	# enter) — узел освобождается по прибытии, поэтому позу назад возвращать
	# не нужно.
	_load_pose(id, "walk", bool(a.get("flip", false)))
	_place_actor(id)
	_slides.append({"actor": id, "left": sec, "total": sec,
		"from_dx": float(a.get("dx", 0.0)), "to_dx": to_off, "then_free": true})


func _show_prop(beat: Dictionary) -> void:
	var id := String(beat.get("id", ""))
	var def := StoryData.prop(id)
	var path := String(def.get("tex", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var node: TextureRect
	if _props.has(id):
		node = _props[id]
	else:
		node = TextureRect.new()
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_stage.add_child(node)
		# Реквизит уходит под актёров: дом и забор — задник, герой перед ними.
		_stage.move_child(node, 0)
	var tex: Texture2D = load(path)
	node.texture = tex
	node.set_meta("at", String(beat.get("at", "center")))
	node.set_meta("scale", float(beat.get("scale", def.get("scale", 1.0))))
	# overflow: реквизит шире сцены не сжимается до неё (see _fit_x), а
	# уходит за край экрана — дом обязан читаться домом (крупнее актёра),
	# а не сплющиваться в рамку портрета 224 px (решение по конкретному
	# кейсу: лачуга деда шире стойки, см. props.shack в data/story.json).
	node.set_meta("overflow", bool(beat.get("overflow", def.get("overflow", false))))
	_props[id] = node
	_place_prop(id)


## "clear" — общий кадр "убрать со сцены всё" (было и раньше), а для сцены в
## режиме мира — ЕЩЁ И выход из него (_exit_world_mode): мир возвращается к
## внуку СРАЗУ, как только сюжету больше не нужна живая карта (дальше в
## intro_grandpa идёт эпилог у могилы — своя декорация, ей era/копка деда не
## нужны). Тот же вызов срабатывает и на honest-finish, и на skip()/abort()
## (оба зовут _clear_stage напрямую или через _finish/abort) — одна точка
## гарантирует откат независимо от того, досмотрели сцену или пропустили.
func _clear_stage() -> void:
	for id in _actors.keys():
		_actors[id].node.queue_free()
	_actors.clear()
	for id in _props.keys():
		_props[id].queue_free()
	_props.clear()
	_moves.clear()
	_slides.clear()
	_tap_target.visible = false
	_house_sleep_left = 0.0
	if world_mode:
		_exit_world_mode()


func _place_all() -> void:
	for id in _actors.keys():
		_place_actor(id)
	for id in _props.keys():
		_place_prop(id)


func _place_actor(id: String) -> void:
	var a: Dictionary = _actors[id]
	var node: TextureRect = a.node
	var s: float = a.scale
	# Лист на диске в ART_SCALE раз крупнее логики (см. CHAR_FRAME выше) —
	# делим перед тем, как накладывать "scale" сцены, иначе актёр выходит
	# втрое крупнее замысла постановщика и не помещается на сцене портрета.
	var w: float = a.frame_w * s / ART_SCALE
	var h: float = a.tex_h * s / ART_SCALE
	node.size = Vector2(w, h)
	# Актёр стоит НА земле: низ кадра совпадает с линией земли сцены, иначе
	# фигура висит в воздухе, и сцена перестаёт читаться как место. dx —
	# горизонтальный сдвиг входа/выхода пешком (см. _tick_slides), поверх
	# именованной позиции "at".
	node.position = Vector2(_fit_x(_stage_x(a.at), w) + float(a.get("dx", 0.0)),
		_stage.size.y - h + float(a.dy))


## Тикает вход/выход актёра пешком (см. _show_actor:enter / _hide_actor:exit_to).
## Кубический ease-out: быстрый шаг, плавное торможение у цели — то же самое,
## что step-функции в CSS/твинах, но без зависимости от готовых Tween на
## значениях внутри Dictionary (Tween не умеет анимировать поле словаря).
func _tick_slides(dt: float) -> void:
	if _slides.is_empty():
		return
	var still: Array = []
	for sl in _slides:
		var id: String = sl.actor
		sl.left -= dt
		var has_actor := _actors.has(id)
		if has_actor:
			var t: float = 1.0 - clampf(sl.left / sl.total, 0.0, 1.0)
			var eased: float = 1.0 - pow(1.0 - t, 3.0)
			_actors[id].dx = lerpf(sl.from_dx, sl.to_dx, eased)
			_place_actor(id)
		if sl.left > 0.0:
			still.append(sl)
		elif has_actor:
			if bool(sl.then_free):
				_actors[id].node.queue_free()
				_actors.erase(id)
			elif bool(sl.get("walking", false)):
				# Дошёл: возвращаем позу, заказанную кадром "show" (обычно
				# idle) — иначе актёр так и стоял бы в позе ходьбы навсегда.
				_load_pose(id, String(sl.get("arrive_pose", "idle")), bool(sl.get("arrive_flip", false)))
				_place_actor(id)
	_slides = still


func _place_prop(id: String) -> void:
	var node: TextureRect = _props[id]
	var s: float = float(node.get_meta("scale", 1.0))
	var tex: Texture2D = node.texture
	if tex == null:
		return
	var w: float = tex.get_width() * s
	var h: float = tex.get_height() * s
	node.size = Vector2(w, h)
	var center_x := _stage_x(String(node.get_meta("at", "center")))
	# overflow пропускает клампинг _fit_x в границы сцены: реквизит крупнее
	# стойки (например, лачуга — она обязана читаться крупнее актёра, ГДД)
	# уходит за край экрана вместо того, чтобы центроваться или сжиматься.
	var x: float = center_x - w / 2.0 if bool(node.get_meta("overflow", false)) \
		else _fit_x(center_x, w)
	node.position = Vector2(x, _stage.size.y - h)


func _tick_actor_frames() -> void:
	var frame_idx := int(_anim_time * ANIM_FPS)
	for id in _actors.keys():
		var a: Dictionary = _actors[id]
		if a.frames <= 1:
			continue
		var atlas: AtlasTexture = a.node.texture
		if atlas == null:
			continue
		atlas.region = Rect2((frame_idx % a.frames) * a.frame_w, 0, a.frame_w, a.tex_h)


func _tick_moves(dt: float) -> void:
	if _moves.is_empty():
		return
	var still: Array = []
	for m in _moves:
		var id: String = m.actor
		if _actors.has(id):
			_actors[id].dy += m.per_sec * minf(dt, m.left)
			_place_actor(id)
		m.left -= dt
		if m.left > 0.0:
			still.append(m)
	_moves = still


func _tick_shake(dt: float) -> void:
	if _shake_left <= 0.0:
		if _stage.position.x != 0.0:
			_stage.position.x = 0.0
		return
	_shake_left -= dt
	_stage.position.x = randf_range(-2.5, 2.5) if _shake_left > 0.0 else 0.0


## Ускоренные сутки в сцене смерти: небо гонит день-ночь втрое быстрее
## обычного, и по одному этому видно, что прошло не пять минут.
func _tick_daynight(dt: float) -> void:
	if _daynight_left <= 0.0:
		return
	_daynight_left -= dt
	var phase := int(_daynight_left / maxf(0.05, _daynight_step)) % 2
	if phase != _daynight_idx:
		_daynight_idx = phase
		_apply_mood_colors("night" if phase == 0 else "day")
	if _daynight_left <= 0.0:
		_apply_mood_colors(_mood_id)


## "Рост": пролистывает pose-список актёра, показывая каждую beat.sec секунд
## (развёртка пацана 8-15 лет — art/character/boy/age_8.png … age_15.png).
## Держит сцену, как card/daynight — конец считает общий _beat_timer.
func _start_grow(beat: Dictionary) -> void:
	var poses: Array = beat.get("poses", [])
	if poses.is_empty():
		return
	# Титр предыдущего кадра ("card") сам не гаснет — молча провисел бы поверх
	# растущей фигуры (ноги съезжали под строку текста).
	_hide_text()
	_grow_actor = String(beat.get("actor", "boy"))
	_grow_poses = poses
	_grow_step = maxf(0.05, float(beat.get("sec", 0.45)))
	_grow_at = String(beat.get("at", "center"))
	_grow_scale = float(beat.get("scale", 2.0))
	_grow_flip = bool(beat.get("flip", false))
	_grow_idx = -1
	_grow_left = _grow_step * poses.size()
	_beat_timer = _grow_left
	_tick_grow(0.0)


func _tick_grow(dt: float) -> void:
	if _grow_poses.is_empty() or _grow_left <= 0.0 and _grow_idx == _grow_poses.size() - 1:
		return
	_grow_left -= dt
	var elapsed: float = _grow_step * float(_grow_poses.size()) - maxf(_grow_left, 0.0)
	var idx: int = clampi(int(elapsed / _grow_step), 0, _grow_poses.size() - 1)
	if idx == _grow_idx:
		return
	_grow_idx = idx
	_show_actor({
		"actor": _grow_actor, "pose": _grow_poses[idx],
		"at": _grow_at, "scale": _grow_scale, "flip": _grow_flip,
	})


func _set_mood(id: String) -> void:
	_mood_id = id
	_apply_mood_colors(id)
	# Смена обстановки — это новая сцена, а затемнение от предыдущей на ней
	# уже не нужно: иначе титр после "fade out" рисовался бы под чёрным.
	_fade.color = Color(0, 0, 0, 0)


## Цвет неба из общих игровых часов вместо moods-таблицы (см.
## use_day_cycle()). Дневной ориентир берём из mood "day" — так небо
## катсцены остаётся тем же голубым небом, что и остальная игра, просто
## умноженным на DayCycle.sky_dark(), а не отдельной палитрой на глаз.
func _apply_day_cycle_sky() -> void:
	if not _use_day_cycle:
		return
	var dc := get_node_or_null("/root/DayCycle")
	if dc == null:
		return
	# Та же палитра, что у живого неба (world_view.gd): день 81D3F4, самая
	# тёмная ночь 11053B; sky_dark() 0..0.9 нормируем к 0..1.
	var wv := preload("res://scripts/world/world_view.gd")
	var k: float = clampf(dc.sky_dark() / 0.9, 0.0, 1.0)
	_sky.color = wv.COLOR_SKY.lerp(wv.COLOR_SKY_NIGHT, k)


func _apply_mood_colors(id: String) -> void:
	var m := StoryData.mood(id)
	_sky.color = Color(String(m.get("sky", "#0b0806")))
	var ground := Color(String(m.get("ground", "#241c14")))
	# Тайл земли тонируется, а не заменяется: один и тот же грунт должен
	# выглядеть ночным, подвальным и дневным.
	_ground.modulate = ground * 2.0
	_ground.modulate.a = 1.0


# ---------------------------------------------------------------------------
# Режим "мир": сцена на живой карте (см. заголовок файла, play(id, opts) и
# заголовок блока полей world_mode выше).
# ---------------------------------------------------------------------------

## Скорость ходьбы актёра по умолчанию (клеток/сек) — как у героя игрока
## (см. player.gd), если кадр не задал свой "sec".
const WORLD_WALK_SPEED := 3.0
const WORLD_DIG_SEC := 1.4
## Целый ряд ("быстрая промотка" — решение владельца) заметно быстрее
## одной клетки: секунды на весь проезд по ряду, а не на клетку.
const WORLD_DIG_ROW_SEC := 2.4


## era — по умолчанию "now": большинство сцен режима "мир" (владелец,
## 2026-09-21: "пусть все сюжетные моменты будут делаться на реальном
## фоне") играют во времени ВНУКА, на карте как она есть прямо сейчас —
## с уже построенным Робертом тоннелем, современным домом и т.д. "grandpa"
## передаёт только флешбэк деда (intro_grandpa, данные scene.era в
## data/story.json) — там своя эпоха с лачугой вместо дома и без тоннеля
## (см. world_gen.gd:era). Раньше era была захардкожена в "grandpa" —
## единственная на тот момент сцена режима "мир" её и требовала; с
## появлением вторых сцен режима "мир" ("intro_boy", "death") хардкод стал
## неверен для них.
func _enter_world_mode(era: String = "now") -> void:
	world_mode = true
	# Небо/земля катсцены прячутся — живая карта показывается КАК ЕСТЬ, её
	# рисует main.gd/world_view.gd под этим CanvasLayer, а не мы.
	_sky.visible = false
	_ground.visible = false
	if world != null:
		world.era = era
	GameState.era = era
	_set_backdrop_era(era)
	# Герой игрока молчит и стоит замороженным во время ЛЮБОЙ катсцены (см.
	# story_director._take_control), но его СПРАЙТ обычно скрыт под
	# непрозрачными небом/землёй классической сцены. В режиме "мир" декорации
	# нет — прячем сам узел отрисовки героя, иначе на поверхности рядом с
	# дедом молча стоял бы ещё и мальчик из будущего.
	var cv := get_tree().root.find_child("CharacterView", true, false)
	if cv != null:
		cv.visible = false


## Симметрично _enter_world_mode — зовётся из _clear_stage() (кадр "clear"
## ИЛИ конец сцены через _finish()/abort(), которые тоже проходят через
## _clear_stage). Идемпотентна (world_mode-гейт внутри), так что повторный
## вызов (у _finish() после уже отработавшего "clear") безопасен.
func _exit_world_mode() -> void:
	world_mode = false
	if world != null:
		# Откатываем РОВНО то, что выкопала сама сцена, — включая клетки,
		# которые были зафиксированы (фундамент), restore_garden() их не
		# трогает нарочно (см. world_gen.gd:forget_dug_cells).
		world.forget_dug_cells(_world_dug_cells)
		world.era = "now"
	GameState.era = "now"
	_set_backdrop_era("now")
	var dc := get_node_or_null("/root/DayCycle")
	if dc != null and dc.has_method("set_time_scale"):
		dc.set_time_scale(1.0)
	for id in _world_actors.keys():
		_world_actors[id].queue_free()
	_world_actors.clear()
	for id in _world_props.keys():
		_world_props[id].queue_free()
	_world_props.clear()
	_world_dug_cells.clear()
	_world_walk = {}
	_world_dig = {}
	_world_dig_row = {}
	_world_fall = {}
	_camera_actor_id = ""
	var cv := get_tree().root.find_child("CharacterView", true, false)
	if cv != null:
		cv.visible = true
	_sky.visible = true
	_ground.visible = true
	# Пока сцена шла, камера/туман следовали за дедом через player.x/y (см.
	# _tick_world) — герой игрока настоящий x/y НИКОГДА не получал (он всё
	# время заморожен и спрятан), но само поле осталось там, где кончил дед
	# (например, на дне пятиклеточной ямы). Следующая сцена (intro_boy) или
	# обычная игра унаследовали бы эту точку как стартовую — второй раз то
	# же самое падение, только уже для внука, и без единой клетки под ним
	# (яму мы только что забыли). Возвращаем на ту же точку, что и
	# main.gd:_position_from_save_or_start() — единственную позицию, с
	# которой начинается игра.
	if player != null:
		player.x = 20.5
		player.y = 0.5
		player.vx = 0.0
		player.vy = 0.0


## Задник (забор/гора) — параллельная задача, контракт: узел с именем
## "Backdrop" и методом set_era(era). Пока узла нет — no-op, сцена не падает.
func _set_backdrop_era(era: String) -> void:
	var bd := get_tree().root.find_child("Backdrop", true, false)
	if bd != null and bd.has_method("set_era"):
		bd.call("set_era", era)


## HouseSystem регистрирует себя в группе "house_system" (см.
## scripts/house/house_system.gd:_ready) — тем же приёмом, что WorldGen/
## player передаются извне (см. поля world/player выше), только без ручного
## провода: дом всегда один на игру, и находить его через группу проще, чем
## тянуть ещё одну ссылку через story_director.gd для двух кадров.
func _find_house_system() -> Node:
	return get_tree().get_first_node_in_group("house_system")


## "house_enter" — сцена показывает НАСТОЯЩИЙ интерьер (см. house_mode выше).
## beat: room ("hall"/"bedroom"/"workshop"), x — доля 0..1 ширины комнаты,
## где встанет герой (см. data/rooms.json:points), по умолчанию spawn_x
## комнаты. Своё небо/землю/героя катсцена прячет тем же приёмом, что и
## world_mode (_enter_world_mode) — дом рисуется НИЖНИМ CanvasLayer
## (layer=9), а катсцена — верхним (layer=100), и без этого закрывала бы
## его собой.
func _house_enter(beat: Dictionary) -> void:
	var hs := _find_house_system()
	if hs == null or not hs.has_method("enter_house"):
		return
	_sky.visible = false
	_ground.visible = false
	var cv := get_tree().root.find_child("CharacterView", true, false)
	if cv != null:
		cv.visible = false
	hs.call("enter_house", String(beat.get("room", "hall")), float(beat.get("x", -1.0)))
	house_mode = true


## "house_sleep" — короткая анимация сна у настоящей кровати, тот же ролик,
## что игрок видит по кнопке "Спать" (house_system._start_sleep_sequence),
## но без самого эффекта сна — часы/голод/бодрость сцена "death" считает
## сама через effects (data/story.json), не через реальный HouseSleep.
func _house_start_sleep(beat: Dictionary) -> bool:
	var hs := _find_house_system()
	var sec: float = maxf(0.1, float(beat.get("sec", 1.8)))
	if hs != null and hs.has_method("play_sleep_animation"):
		hs.call("play_sleep_animation", sec)
	_house_sleep_left = sec
	_beat_timer = sec
	return true


func _tick_house_sleep(dt: float) -> void:
	if _house_sleep_left <= 0.0:
		return
	_house_sleep_left -= dt
	if _house_sleep_left <= 0.0:
		_house_sleep_left = 0.0
		var hs := _find_house_system()
		if hs != null and hs.has_method("stop_sleep_animation"):
			hs.call("stop_sleep_animation")


## "world_actor" — поставить (или переставить/переодеть) актёра в клетку
## живой карты. beat: actor, x, y (логические координаты, как player.x/y —
## например y=0.5 значит "стоит на поверхности"), pose, flip, camera=true
## (сделать этого актёра целью камеры/тумана — см. _tick_world).
func _world_place_actor(beat: Dictionary) -> void:
	var id := String(beat.get("actor", ""))
	if id.is_empty():
		return
	var a: WorldActor = _world_actors.get(id)
	if a == null:
		a = WorldActor.new()
		a.setup(id)
		# Без явных x/y в кадре — новый актёр встаёт там, где ПО-НАСТОЯЩЕМУ
		# стоит игрок (тот же x/y, что вело обучение до заморозки — см.
		# story_director._take_control): нужно для сцен вроде "death", где
		# заранее неизвестно, в какой клетке огорода игрок пробьёт фундамент.
		if not beat.has("x") and not beat.has("y") and player != null:
			a.x = player.x
			a.y = player.y
		# Актёр обязан ехать вместе с камерой мира (тем же смещением
		# view_root, что и WorldView/Player), а не поверх интерфейса —
		# добавляем его в ViewRoot, а не в себя (CanvasLayer катсцены).
		var view_root := get_tree().root.find_child("ViewRoot", true, false)
		if view_root != null:
			view_root.add_child(a)
		else:
			add_child(a)   # тест без main.gd (см. test_story_flow.gd) — держим хоть так
		_world_actors[id] = a
	if beat.has("x"):
		a.x = float(beat.get("x"))
	if beat.has("y"):
		a.y = float(beat.get("y"))
	a.set_pose(String(beat.get("pose", "idle")), bool(beat.get("flip", a.flip)))
	if bool(beat.get("camera", false)):
		_camera_actor_id = id


## "world_prop" — поставить статичный предмет (могила и т.п.) в клетку живой
## карты. beat: id, tex (res://...), x, y (низ картинки садится на клетку,
## как у декора огорода), scale (множитель поверх ART_SCALE, по умолчанию 1).
## Без поз/кадров/разворота — see _world_place_actor для актёров с анимацией.
func _world_place_prop(beat: Dictionary) -> void:
	var id := String(beat.get("id", ""))
	if id.is_empty():
		return
	var spr: Sprite2D = _world_props.get(id)
	if spr == null:
		spr = Sprite2D.new()
		spr.centered = false
		var view_root := get_tree().root.find_child("ViewRoot", true, false)
		if view_root != null:
			view_root.add_child(spr)
		else:
			add_child(spr)
		_world_props[id] = spr
	var tex_path := String(beat.get("tex", ""))
	if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
		spr.texture = load(tex_path)
	var scale_mult: float = float(beat.get("scale", 1.0))
	spr.scale = Vector2(scale_mult / ART_SCALE, scale_mult / ART_SCALE)
	var x: float = float(beat.get("x", 0.0))
	var y: float = float(beat.get("y", 0.0))
	var w: float = spr.texture.get_width() if spr.texture != null else 0.0
	var h: float = spr.texture.get_height() if spr.texture != null else 0.0
	# Низ картинки — на клетку (x, y), по центру ширины: та же привязка, что
	# у декора огорода (world_view.gd:_draw_garden_decor) и у припаркованного
	# бурмобиля, — предмет "стоит" на клетке, а не растёт из её середины.
	spr.position = Vector2(
		x * TILE - w * scale_mult / ART_SCALE / 2.0,
		y * TILE - h * scale_mult / ART_SCALE)


## "world_walk" — дойти до x за sec секунд (по умолчанию — по WORLD_WALK_SPEED
## клеток/сек). Держит сцену (как "move"/"fade"), пока актёр не дойдёт.
func _world_start_walk(beat: Dictionary) -> bool:
	var id := String(beat.get("actor", ""))
	var a: WorldActor = _world_actors.get(id)
	if a == null:
		return false
	var target_x: float = float(beat.get("x", a.x))
	var sec: float = float(beat.get("sec", maxf(0.2, absf(target_x - a.x) / WORLD_WALK_SPEED)))
	a.set_pose("walk", target_x < a.x)
	if bool(beat.get("camera", false)):
		_camera_actor_id = id
	_world_walk = {"actor": id, "from": a.x, "to": target_x, "left": sec, "total": sec,
		"arrive_pose": String(beat.get("arrive_pose", "idle"))}
	_beat_timer = sec
	return true


## "world_dig" — выкопать клетку (x, y) НАСТОЯЩЕЙ картой (world.dig_cell):
## актёр встаёт над клеткой, sec секунд играет pose (по умолчанию
## "dig_shovel"), затем клетка выкапывается и актёр шагает в неё (y+0.5).
func _world_start_dig(beat: Dictionary) -> bool:
	var id := String(beat.get("actor", ""))
	var a: WorldActor = _world_actors.get(id)
	if a == null or world == null:
		return false
	# Без явных x/y — копает клетку ПРЯМО ПОД собой (та же клетка-под-ногами,
	# что "world_dig" всегда оставляет актёра стоять на дне: a.y=cell.y+0.5),
	# чтобы можно было копать вниз серией кадров без знания стартовых
	# координат заранее — см. "death" в data/story.json.
	var default_x := int(round(a.x - 0.5))
	var default_y := int(round(a.y - 0.5)) + 1
	var cell := Vector2i(int(beat.get("x", default_x)), int(beat.get("y", default_y)))
	var sec: float = maxf(0.1, float(beat.get("sec", WORLD_DIG_SEC)))
	a.x = float(cell.x) + 0.5
	a.y = float(cell.y) - 0.5
	a.set_pose(String(beat.get("pose", "dig_shovel")), a.flip)
	if bool(beat.get("camera", false)):
		_camera_actor_id = id
	_world_dig = {"actor": id, "cell": cell, "left": sec, "total": sec}
	_beat_timer = sec
	return true


## "world_dig_row" — весь ряд y от from_x до to_x за sec секунд одним
## проездом: актёр плавно едет по X (как world_walk), а клетки, которые он
## проезжает, копаются НАСТОЯЩЕЙ картой на лету — тем же приёмом, что и
## "быстрая промотка" у обучения внука (см. scripts/story/auto_dig.gd), но
## управляемая сюжетом, а не игроком. from_x по умолчанию — GARDEN_X_MIN
## (сразу у дома), to_x — WorldGen.WIDTH-1 ("до конца", т.е. до самого края
## карты). y_stand (по умолчанию y-0.5) — на какой высоте стоит актёр, пока
## копает ряд под собой: слой НАД тем, что копается, как и в одиночной
## "world_dig".
func _world_start_dig_row(beat: Dictionary) -> bool:
	var id := String(beat.get("actor", ""))
	var a: WorldActor = _world_actors.get(id)
	if a == null or world == null:
		return false
	var y: int = int(beat.get("y", 1))
	var from_x: int = int(beat.get("from_x", WorldGen.GARDEN_X_MIN))
	var to_x: int = int(beat.get("to_x", WorldGen.WIDTH - 1))
	var sec: float = maxf(0.2, float(beat.get("sec", WORLD_DIG_ROW_SEC)))
	a.y = float(beat.get("y_stand", float(y) - 0.5))
	a.x = float(from_x) + 0.5
	a.set_pose(String(beat.get("pose", "dig_shovel")), to_x < from_x)
	if bool(beat.get("camera", false)):
		_camera_actor_id = id
	_world_dig_row = {"actor": id, "y": y, "from_x": from_x, "to_x": to_x,
		"left": sec, "total": sec, "dug_up_to": from_x - 1 if to_x >= from_x else from_x + 1}
	_beat_timer = sec
	return true


## "world_fall" — визуальный сдвиг актёра вниз/вверх на dy КЛЕТОК (не
## пикселей, в отличие от классического "move") за sec секунд. Копки не
## делает — нужен для "пробовал выбраться, не смог": актёр дёргается в яме,
## сама яма (world_dig) уже выкопана раньше.
func _world_start_fall(beat: Dictionary) -> bool:
	var id := String(beat.get("actor", ""))
	var a: WorldActor = _world_actors.get(id)
	if a == null:
		return false
	var sec: float = maxf(0.05, float(beat.get("sec", 0.5)))
	_world_fall = {"actor": id, "from": a.y, "to": a.y + float(beat.get("dy", 0.0)),
		"left": sec, "total": sec}
	a.set_pose(String(beat.get("pose", "fall")), a.flip)
	_beat_timer = sec
	return true


## "clock" — контракт DayCycle (автозагрузка параллельного агента,
## /root/DayCycle): hour — сразу выставить час, scale — множитель скорости
## часов. Не блокирует сцену (как "mood"). Пока узла нет — только
## current_clock_hour обновляется (тесты проверяют ход времени сцены и без
## DayCycle, см. tests/test_story.gd).
func _do_clock(beat: Dictionary) -> void:
	var dc := get_node_or_null("/root/DayCycle")
	if beat.has("hour"):
		current_clock_hour = float(beat.get("hour"))
		if dc != null and dc.has_method("set_hour"):
			dc.set_hour(current_clock_hour)
	if beat.has("scale") and dc != null and dc.has_method("set_time_scale"):
		dc.set_time_scale(float(beat.get("scale")))


func _tick_world(dt: float) -> void:
	if _world_actors.is_empty():
		return
	for id in _world_actors.keys():
		_world_actors[id].anim += 60.0 * dt
	_tick_world_walk(dt)
	_tick_world_dig(dt)
	_tick_world_dig_row(dt)
	_tick_world_fall(dt)
	# Камера и туман войны идут за героем (main.gd:_camera/_reveal_around_player
	# читают ровно player.x/player.y) — во время сцены герой заморожен и
	# спрятан (см. _enter_world_mode), а его координаты ведёт актёр, за
	# которым сейчас следит камера (см. поле "camera" у world_actor/
	# world_walk/world_dig).
	if not _camera_actor_id.is_empty() and player != null and _world_actors.has(_camera_actor_id):
		var cam_a: WorldActor = _world_actors[_camera_actor_id]
		player.x = cam_a.x
		player.y = cam_a.y


func _tick_world_walk(dt: float) -> void:
	if _world_walk.is_empty():
		return
	var id: String = _world_walk.actor
	var a: WorldActor = _world_actors.get(id)
	if a == null:
		_world_walk = {}
		return
	_world_walk.left -= dt
	var t: float = 1.0 - clampf(_world_walk.left / _world_walk.total, 0.0, 1.0)
	a.x = lerpf(_world_walk.from, _world_walk.to, t)
	if _world_walk.left <= 0.0:
		a.set_pose(String(_world_walk.arrive_pose), a.flip)
		_world_walk = {}


func _tick_world_dig(dt: float) -> void:
	if _world_dig.is_empty():
		return
	var id: String = _world_dig.actor
	var a: WorldActor = _world_actors.get(id)
	if a == null:
		_world_dig = {}
		return
	_world_dig.left -= dt
	if _world_dig.left <= 0.0:
		var cell: Vector2i = _world_dig.cell
		if world != null and world.dig_cell(cell.x, cell.y):
			_world_dug_cells.append(cell)
		# Шагнул вниз, в свежую яму — так же, как игрок проваливается в
		# только что выкопанную под собой клетку.
		a.y = float(cell.y) + 0.5
		_world_dig = {}



## Копает каждую клетку ряда РОВНО РАЗ, в тот момент, когда проезжающий
## актёр пересекает её центр — а не всю пачку разом в конце (иначе "все
## тайлы должны пропадать" не читалось бы как промотка, а выглядело бы
## одним щелчком в конце проезда).
func _tick_world_dig_row(dt: float) -> void:
	if _world_dig_row.is_empty():
		return
	var id: String = _world_dig_row.actor
	var a: WorldActor = _world_actors.get(id)
	if a == null:
		_world_dig_row = {}
		return
	_world_dig_row.left -= dt
	var t: float = 1.0 - clampf(_world_dig_row.left / _world_dig_row.total, 0.0, 1.0)
	var from_x: int = _world_dig_row.from_x
	var to_x: int = _world_dig_row.to_x
	a.x = lerpf(float(from_x) + 0.5, float(to_x) + 0.5, t)
	var forward: bool = to_x >= from_x
	var reached: int = int(round(a.x - 0.5))
	if forward:
		while _world_dig_row.dug_up_to < reached and _world_dig_row.dug_up_to < to_x:
			_world_dig_row.dug_up_to += 1
			world.dig_cell(_world_dig_row.dug_up_to, _world_dig_row.y)
			_world_dug_cells.append(Vector2i(_world_dig_row.dug_up_to, _world_dig_row.y))
	else:
		while _world_dig_row.dug_up_to > reached and _world_dig_row.dug_up_to > to_x:
			_world_dig_row.dug_up_to -= 1
			world.dig_cell(_world_dig_row.dug_up_to, _world_dig_row.y)
			_world_dug_cells.append(Vector2i(_world_dig_row.dug_up_to, _world_dig_row.y))
	if _world_dig_row.left <= 0.0:
		# Последняя клетка (to_x) обязана быть выкопана даже если округление
		# a.x чуть не дотянуло до неё за отведённое время.
		if _world_dig_row.dug_up_to != to_x:
			_world_dig_row.dug_up_to = to_x
			world.dig_cell(to_x, _world_dig_row.y)
			_world_dug_cells.append(Vector2i(to_x, _world_dig_row.y))
		a.x = float(to_x) + 0.5
		_world_dig_row = {}


func _tick_world_fall(dt: float) -> void:
	if _world_fall.is_empty():
		return
	var id: String = _world_fall.actor
	var a: WorldActor = _world_actors.get(id)
	if a == null:
		_world_fall = {}
		return
	_world_fall.left -= dt
	var t: float = 1.0 - clampf(_world_fall.left / _world_fall.total, 0.0, 1.0)
	a.y = lerpf(_world_fall.from, _world_fall.to, t)
	if _world_fall.left <= 0.0:
		_world_fall = {}

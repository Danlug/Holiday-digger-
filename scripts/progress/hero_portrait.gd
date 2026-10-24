class_name HeroPortrait
extends Control
## Портрет героя на карточке экрана: кадры стойки из art/character/idle.png
## (спрайты как есть — тот же лист, что рисует CharacterView в мире), мягкий
## «софит» за спиной и тень под ногами. Герой чуть дышит: кадры стойки
## сменяются медленно.
##
## ПОЧЕМУ лист читается напрямую, а не через CharacterView: CharacterView
## привязан к живому Player (позиция, копка, состояние) и крутит десятки
## листов; портрету нужна одна статичная стойка, и ему незачем знать о мире.

const SHEET := "res://art/character/idle.png"
## Кадр 48×48 логических точек, линия земли 46 (как в шахте); на карточке
## он ×3·0,82 — тот же размер, что был при листах ×3.
const FRAME_U := 48.0
const FEET_U := 46.0
const UNIT := 3.0 * 0.82
const BREATH_SECONDS := 0.5

var _tex: Texture2D = null
var _inf: Dictionary = {}
var _frames: int = 1
var _frame: int = 0
var _t: float = 0.0
## Герой — отдельный узел с шейдером чёткости (лист ×8 на карточке
## уменьшается/растягивается в нецелое число раз).
var _hero: TextureRect = null


func _init() -> void:
	custom_minimum_size = Vector2(84, 118)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if ResourceLoader.exists(SHEET):
		_tex = load(SHEET)
		_inf = HeroSheets.info_for(_tex)
		_frames = HeroSheets.frames_of(_inf) if not _inf.is_empty() \
				else maxi(int(_tex.get_width() / (FRAME_U * HeroSheets.LEGACY_SCALE)), 1)
		_hero = TextureRect.new()
		_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_hero.stretch_mode = TextureRect.STRETCH_SCALE
		HeroSheets.crisp(_hero, _inf)
		add_child(_hero)
		_set_frame(0)
		resized.connect(_place_hero)
		_place_hero()
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	# Движок включает _process при READY, даже если скрыт с самого начала: сигнал видимости до первого показа молчит.
	set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	_t += delta
	var f := int(_t / BREATH_SECONDS) % _frames
	if f != _frame:
		_set_frame(f)


func _set_frame(f: int) -> void:
	_frame = f
	if _hero == null:
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = _tex
	var sc: float = HeroSheets.scale_of(_inf)
	atlas.region = HeroSheets.region(_inf, f) if not _inf.is_empty() \
			else Rect2(f * FRAME_U * sc, 0.0, FRAME_U * sc, FRAME_U * sc)
	_hero.texture = atlas


func _place_hero() -> void:
	if _hero == null:
		return
	var w := FRAME_U * UNIT
	var feet_y := size.y - 8.0
	_hero.position = Vector2((size.x - w) * 0.5, feet_y - FEET_U * UNIT)
	_hero.size = Vector2(w, w)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(HeroUi.box(Color(0.07, 0.06, 0.09), ProgressUiKit.GOLD.darkened(0.35), 5, 1), rect)

	# софит: несколько прозрачных эллипсов вместо градиента — без шейдеров
	var center := Vector2(size.x * 0.5, size.y * 0.52)
	for i in range(9):
		var k := float(i) / 8.0
		draw_set_transform(center, 0.0, Vector2(1.0, 1.25))
		draw_circle(Vector2.ZERO, lerpf(42.0, 10.0, k), Color(0.95, 0.72, 0.3, 0.028))
	var feet_y := size.y - 8.0
	draw_set_transform(Vector2(size.x * 0.5, feet_y), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, 22.0, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

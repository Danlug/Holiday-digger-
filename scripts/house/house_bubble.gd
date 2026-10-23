class_name HouseBubble
extends Button
## HouseBubble — плавающий пузырь-значок действия над героем (дверь, кровать,
## склад…). Текста на нём нет: что это и что произойдёт — в подсказке Tip
## (наведение мыши / долгое нажатие). Лёгкое покачивание отличает его от
## декора; цель нажатия 32×38 (не меньше ~24 проектных единиц).
##
## Тело и рамка — те же девятизонники, что у плиток магазина; рамка красится
## в золото (обычный), белый (принудительный, пульсирует) или серый (нельзя).
##
##   var b := HouseBubble.create({"icon": "act_bed", "label": "Спать", "tip": "..."})
##   b.set_state("dim")          # «пока нельзя»: приглушён, причина — в Tip
##   b.set_count(3)              # красная цифра в углу

const W := 32.0
const H := 38.0
const TAIL_W := 11.0
const BOB := 2.0

var _vis: Control
var _body: NinePatchRect
var _rim: NinePatchRect
var _glow: TextureRect
var _glyph: TextureRect
var _tail: TextureRect
var _lock: TextureRect
var _bob: Tween
var _pulse: Tween
var _state := "normal"
var _phase := 0.0


static func create(def: Dictionary, phase: float = 0.0) -> HouseBubble:
	var b := HouseBubble.new()
	b._phase = phase
	b.setup(def)
	return b


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	flat = true
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())

	_vis = Control.new()
	_vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vis.size = Vector2(W, H)
	add_child(_vis)

	_glow = ShopArt.rect(ShopArt.tex("glow"), Vector2(-8, -8), Vector2(W + 16, W + 16))
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.modulate = Color(1, 0.9, 0.5, 0.0)
	_vis.add_child(_glow)

	_tail = ShopArt.rect(HouseArt.tex("bubble_tail"), Vector2((W - TAIL_W) * 0.5, W - 1.0), Vector2(TAIL_W, 6))
	_tail.modulate = HouseArt.GOLD
	_body = HouseArt.nine("tile_body", 5, Color.WHITE, Vector2(W, W))
	_rim = HouseArt.nine("tile_rim", 5, HouseArt.GOLD, Vector2(W, W))
	_vis.add_child(_tail)
	_vis.add_child(_body)
	_vis.add_child(_rim)
	_glyph = ShopArt.rect(null, Vector2(4, 4), Vector2(24, 24))
	_vis.add_child(_glyph)
	_lock = ShopArt.rect(ShopArt.tex("glyph_lock"), Vector2(W - 12, W - 12), Vector2(12, 12))
	_lock.visible = false
	_vis.add_child(_lock)

	UiBtn.wire_feedback(self)


func setup(def: Dictionary) -> void:
	_glyph.texture = HouseArt.tex(String(def.get("icon", "")))
	set_meta("action", String(def.get("action", "")))
	set_meta("label", String(def.get("label", "")))
	Tip.bind(self, String(def.get("label", "")), String(def.get("tip", "")), String(def.get("extra", "")))
	set_state(String(def.get("state", "normal")))


## "normal" | "dim" (пока нельзя, причина в Tip) | "forced" (обучение: пульсирует).
func set_state(state: String) -> void:
	var changed := state != _state
	_state = state
	var col := HouseArt.GOLD
	var body_col := Color.WHITE
	var glyph_col := Color.WHITE
	match state:
		"dim":
			col = Color8(0x6A, 0x62, 0x78)
			body_col = Color(0.7, 0.7, 0.76)
			glyph_col = Color(0.6, 0.6, 0.66)
		"forced":
			col = Color.WHITE
	_rim.modulate = col
	_tail.modulate = col
	_body.modulate = body_col
	_glyph.modulate = glyph_col
	_lock.visible = state == "dim" and bool(get_meta("lock_dim", false))
	if changed and state == "forced":
		_start_motion()


func set_tip_extra(extra: String) -> void:
	var title := String(get_meta("label", ""))
	var d: Dictionary = get_meta(Tip.META, {"body": ""})
	Tip.bind(self, title, String(d.get("body", "")), extra)


## Красная цифра в углу (0 — нет). «Забрать»: сколько порций лежит у двери.
func set_count(n: int) -> void:
	UiBtn.set_badge(self, n)


func is_dim() -> bool:
	return _state == "dim"


func _enter_tree() -> void:
	_start_motion()


## Покачивание и появление. Твин нельзя создать вне дерева, поэтому и из
## _init, и из set_state идём сюда — а здесь ждём дерева.
func _start_motion() -> void:
	if not is_inside_tree():
		return
	if _bob != null:
		_bob.kill()
	if _pulse != null:
		_pulse.kill()
	_vis.position = Vector2.ZERO
	_glow.modulate.a = 0.0
	if Settings.reduce_motion:
		if _state == "forced":
			_glow.modulate.a = 0.5
		return
	_bob = create_tween().set_loops()
	_bob.tween_interval(_phase)
	_bob.tween_property(_vis, "position:y", -BOB, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob.tween_property(_vis, "position:y", 0.0, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _state == "forced":
		_pulse = create_tween().set_loops()
		_pulse.tween_property(_glow, "modulate:a", 0.75, 0.5).set_trans(Tween.TRANS_SINE)
		_pulse.parallel().tween_property(_rim, "modulate", HouseArt.GOLD_BRIGHT, 0.5)
		_pulse.tween_property(_glow, "modulate:a", 0.15, 0.5).set_trans(Tween.TRANS_SINE)
		_pulse.parallel().tween_property(_rim, "modulate", Color.WHITE, 0.5)
	# Появление: пузырь «выскакивает» из точки над макушкой.
	pivot_offset = Vector2(W * 0.5, H)
	scale = Vector2(0.4, 0.4)
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.1)

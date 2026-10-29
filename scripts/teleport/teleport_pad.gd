class_name TeleportPad
extends Node2D
## Мини-платформа часов-телепорта на траве справа от тоннеля и зелёный неоновый огонёк
## над ней (слова владельца 27.10). Только вид: клетки мира не меняются, копать вокруг
## можно как раньше; герой стоит на траве, крышка плиты — на линии его ног.
##
## Огонёк горит, пока возврат под землю доступен (TeleportWatch.has_return()). «Перетекание
## энергии на месте»: ядро мягко дышит и чуть покачивается, три искры бегут по кругу,
## по тонкому лучу вниз стекают капли, и паз в крышке платформы разгорается в противофазе
## с ядром — свет будто переливается из огонька в платформу и обратно. Всё на синусах
## без резких скачков; «Меньше движения» оставляет одно медленное дыхание.
## Появляется за 0,5 с, гаснет за 0,9 с.

const TILE := 32
## Линия ног героя на траве (мировые px): верх первой земляной клетки (как SURFACE_Y у LightLayer).
const FEET_Y := 32.0
const PAD_TEX := "res://art/teleport/pad.png"
const RUNE_TEX := "res://art/teleport/pad_rune.png"
const ORB_TEX := "res://art/teleport/orb.png"
const MOTE_TEX := "res://art/teleport/mote.png"
const GLOW_TEX := "res://art/fx/glow_soft.png"
## Строка картинки на линии ног — середина крышки-эллипса: герой стоит посреди диска,
## ближняя половина крышки и обод уходят ниже его ног, на землю.
const PAD_TOP_ROW := 5.0
const ORB_RISE := 58.0       # центр огонька над линией ног: над головой героя
const GREEN := Color(0.30, 1.0, 0.58)
const FADE_IN := 0.5
const FADE_OUT := 0.9

var level: float = 0.0       # 0..1 — насколько горит огонёк (тесту и снимкам)
var _t: float = 0.0
var _pad: Texture2D
var _rune: Texture2D
var _orb: Texture2D
var _mote: Texture2D
var _glow_tex: Texture2D
var _glow: Node2D
var _core: Node2D


func _ready() -> void:
	_pad = _load(PAD_TEX)
	_rune = _load(RUNE_TEX)
	_orb = _load(ORB_TEX)
	_mote = _load(MOTE_TEX)
	_glow_tex = _load(GLOW_TEX)
	_glow = Node2D.new()
	_glow.name = "Glow"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_core = Node2D.new()
	_core.name = "Core"
	_core.draw.connect(_draw_core)
	add_child(_core)
	level = 1.0 if TeleportWatch.has_return() else 0.0


static func _load(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func is_lit() -> bool:
	return level > 0.01


## Мировые координаты центра площадки (по линии ног) — тесту и снимкам.
static func pad_center() -> Vector2:
	return Vector2(TeleportWatch.pad_x() * TILE, FEET_Y)


static func orb_center() -> Vector2:
	return pad_center() + Vector2(0.0, -ORB_RISE)


func _process(dt: float) -> void:
	var show_pad := TeleportWatch.pad_ready()
	if visible != show_pad:
		visible = show_pad
	var want := 1.0 if show_pad and TeleportWatch.has_return() else 0.0
	var was := level
	if want > level:
		level = minf(want, level + dt / FADE_IN)
	elif want < level:
		level = maxf(want, level - dt / FADE_OUT)
	if not visible:
		return
	_t += dt
	if level > 0.0 or was != level:
		_glow.queue_redraw()
		_core.queue_redraw()


func _draw() -> void:
	if _pad == null:
		return
	var s := _pad.get_size()
	draw_texture(_pad, (pad_center() - Vector2(s.x * 0.5, PAD_TOP_ROW)).round())


## Ease сглаживает края появления/угасания: свет не «щёлкает», а разгорается.
func _k() -> float:
	return level * level * (3.0 - 2.0 * level)


func _calm() -> bool:
	return Settings.reduce_motion


## Дыхание ядра 0..1 (период ~4 с). Паз платформы горит в противофазе.
func _breath() -> float:
	return 0.5 + 0.5 * sin(_t * TAU / 4.2)


func _draw_glow() -> void:
	var k := _k()
	if k <= 0.0 or _glow_tex == null:
		return
	var b := _breath()
	var oc := orb_center() + Vector2(0.0, _bob())
	var pc := pad_center()
	# Ореол огонька: размер и яркость дышат вместе.
	var r := 16.0 + 4.0 * b
	_glow.draw_texture_rect(_glow_tex, Rect2(oc - Vector2(r, r), Vector2(r, r) * 2.0), false,
		Color(GREEN.r, GREEN.g, GREEN.b, (0.38 + 0.18 * b) * k))
	# Луч от огонька к платформе — тонкий и тусклый, по нему стекает энергия.
	var top := oc.y + 5.0
	var bottom := pc.y - 2.0
	var steps := 12
	for i in steps:
		var a := float(i) / float(steps)
		var y0 := lerpf(top, bottom, a)
		var y1 := lerpf(top, bottom, a + 1.0 / float(steps))
		var fade := 0.10 * (1.0 - 0.6 * a) * k
		_glow.draw_rect(Rect2(round(oc.x), y0, 1.0, y1 - y0 + 0.5), Color(GREEN.r, GREEN.g, GREEN.b, fade))
	# Свечение на крышке платформы и паз — в противофазе с ядром.
	var pb := 1.0 - b
	_glow.draw_texture_rect(_glow_tex, Rect2(pc + Vector2(-24.0, -6.0), Vector2(48.0, 10.0)), false,
		Color(GREEN.r * 0.6, GREEN.g, GREEN.b * 0.5, (0.10 + 0.16 * pb) * k))
	if _rune != null:
		var s := _rune.get_size()
		_glow.draw_texture(_rune, (pc - Vector2(s.x * 0.5, PAD_TOP_ROW)).round(),
			Color(1, 1, 1, (0.45 + 0.55 * pb) * k))
	if _calm():
		return
	# Капли, стекающие по лучу: появляются под огоньком, тают у платформы.
	for i in 3:
		var f := fposmod(_t * 0.38 + float(i) / 3.0, 1.0)
		var y := lerpf(top, bottom, f * f)
		var a2 := sin(PI * f) * 0.85 * k
		_glow.draw_rect(Rect2(round(oc.x) - 0.5, round(y), 2.0, 2.0), Color(GREEN.r, GREEN.g, GREEN.b, a2))


func _bob() -> float:
	if _calm():
		return 0.0
	return round(sin(_t * TAU / 2.8) * 1.0)


func _draw_core() -> void:
	var k := _k()
	if k <= 0.0:
		return
	var b := _breath()
	var oc := (orb_center() + Vector2(0.0, _bob())).round()
	if _orb != null:
		var s := _orb.get_size()
		_core.draw_texture(_orb, oc - (s * 0.5).floor(), Color(1, 1, 1, k * (0.82 + 0.18 * b)))
	if _calm() or _mote == null:
		return
	# Три искры по наклонённому кругу вокруг ядра: позади ядра — тусклее и мельче по яркости.
	var ms := _mote.get_size()
	for i in 3:
		var ang := _t * 1.7 + TAU * float(i) / 3.0
		var p := oc + Vector2(cos(ang) * 9.0, sin(ang) * 3.0 - cos(ang) * 1.0)
		var front := sin(ang) > 0.0
		var a := (0.95 if front else 0.4) * k
		_core.draw_texture(_mote, (p - (ms * 0.5).floor()).round(), Color(1, 1, 1, a))

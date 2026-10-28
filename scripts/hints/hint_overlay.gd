class_name HintOverlay
extends CanvasLayer
## Визуальный язык подсказки — тонкий слой поверх HUD, ничего не перехватывает:
##  * кольцо: золотая рамка вокруг цели и расходящееся «эхо» (твин, Settings.reduce_motion
##    — без движения, рамка просто стоит);
##  * палец-указатель у кнопок и стрелка у объектов мира — «тапает» к цели (твин);
##  * тост-иконка: значок и 1–3 слова; описание — в Tip на самом тосте (тап или долгое
##    нажатие по нему показывает подсказку).
## Слой знает только как нарисовать; когда показать и когда снять — решает HintDirector.

const LAYER := UiLayers.HINTS
const GOLD := UiTheme.GOLD
const GOLD_LIGHT := UiTheme.TEXT_HI
const FINGER_TIP := Vector2(7.5, 1.5)   # где в рисунке кончик пальца (в единицах экрана)
const ARROW_TIP := Vector2(6.0, 11.0)
const CHIP_GAP := 3.0
const EDGE := 4.0

var _root: Control
var _ring: HintRing
var _finger: TextureRect
var _arrow: TextureRect
var _chip: PanelContainer
var _chip_icon: TextureRect
var _chip_label: Label
var _tween: Tween
var _tap_tween: Tween
var _shown: bool = false
var _rect: Rect2 = Rect2()
var _world: bool = false
## Соседи цели (плитки меню, полоски у кнопки героя): палец и тост на них не заходят.
var _blockers: Array[Rect2] = []


func _init() -> void:
	layer = LAYER
	name = "HintOverlay"


func _ready() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.visible = false
	add_child(_root)

	_ring = HintRing.new()
	_ring.name = "Ring"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_ring)

	_finger = _make_sprite("finger")
	_arrow = _make_sprite("arrow")
	_root.add_child(_finger)
	_root.add_child(_arrow)

	_chip = PanelContainer.new()
	_chip.name = "Chip"
	_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := ProgressUiKit.popup_box(GOLD, Color(0.071, 0.055, 0.043, 0.94))
	sb.content_margin_left = 6
	sb.content_margin_right = 7
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	_chip.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	_chip.add_child(row)
	_chip_icon = TextureRect.new()
	_chip_icon.custom_minimum_size = Vector2(16, 16)
	_chip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_chip_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_chip_icon)
	_chip_label = Label.new()
	_chip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_label.add_theme_font_size_override("font_size", 12)
	_chip_label.add_theme_color_override("font_color", GOLD_LIGHT)
	_chip_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_chip_label.add_theme_constant_override("outline_size", 2)
	_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_chip_label)
	_chip.gui_input.connect(_on_chip_input)
	_root.add_child(_chip)

	get_viewport().size_changed.connect(_fit)
	_fit()


func _make_sprite(art_name: String) -> TextureRect:
	var r := TextureRect.new()
	r.name = art_name.capitalize()
	var t := HintArt.tex(art_name)
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.custom_minimum_size = HintArt.size_of(t)
	r.size = HintArt.size_of(t)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = false
	return r


func _fit() -> void:
	if _root == null:
		return
	_root.position = Vector2.ZERO
	_root.size = get_viewport().get_visible_rect().size


func is_showing() -> bool:
	return _shown


## Прямоугольники соседей цели. Зовут до show_hint/track; пустой список — как раньше.
func set_blockers(rects: Array) -> void:
	_blockers.clear()
	for r in rects:
		_blockers.append(r as Rect2)


func chip() -> Control:
	return _chip


## Показать подсказку. style: "" (по цели: кнопкам — палец, миру — стрелка), "finger",
## "arrow" или "ring" (только кольцо). tip: [заголовок, текст] для Tip на тосте.
func show_hint(rect: Rect2, world: bool, icon: Texture2D, text: String, tip: Array, style: String = "") -> void:
	_shown = true
	_world = world
	_rect = rect
	_root.visible = true
	_chip_icon.texture = icon
	_chip_icon.visible = icon != null
	# Правило владельца: слова — только в подсказке. Есть значок — тост рисуется им
	# одним (крупнее), слово остаётся в ярлыке для Tip; нет значка — слово как есть.
	_chip_label.text = text
	_chip_label.visible = not text.is_empty() and icon == null
	_chip_icon.custom_minimum_size = Vector2(22, 22) if icon != null and not text.is_empty() else Vector2(16, 16)
	if tip.size() >= 1:
		Tip.bind(_chip, String(tip[0]), String(tip[1]) if tip.size() > 1 else "")
	elif not text.is_empty():
		Tip.bind(_chip, text)
	var use_finger := style == "finger" or (style == "" and not world)
	var use_arrow := style == "arrow" or (style == "" and world)
	_finger.visible = use_finger
	_arrow.visible = use_arrow
	_ring.visible = true
	_kill_tweens()
	_layout()
	_start_animation(use_finger, use_arrow)


## Цель сдвинулась (мир едет, меню открыли) — переложить без перезапуска твинов.
func track(rect: Rect2) -> void:
	if not _shown:
		return
	if rect.position.distance_to(_rect.position) < 0.4 and rect.size.distance_to(_rect.size) < 0.4:
		return
	_rect = rect
	var before := _toward
	_layout()
	# Мир едет каждый кадр — твин «тапа» не трогаем, он гонит смещение bob поверх позиции;
	# перезапускаем, только когда палец перепрыгнул на другую сторону цели.
	if before != _toward:
		_restart_tap()


func set_paused(on: bool) -> void:
	if _root != null and _shown:
		_root.visible = not on


func hide_hint(animated: bool = true) -> void:
	if not _shown:
		return
	_shown = false
	_kill_tweens()
	if not animated or Settings.reduce_motion or not is_inside_tree():
		_root.visible = false
		_root.modulate.a = 1.0
		return
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 0.0, 0.18)
	_tween.tween_callback(_finish_hide)


func _finish_hide() -> void:
	if _shown:
		return
	_root.visible = false
	_root.modulate.a = 1.0


func _kill_tweens() -> void:
	for tw: Tween in [_tween, _tap_tween]:
		if tw != null and tw.is_valid():
			tw.kill()
	_tween = null
	_tap_tween = null
	bob = Vector2.ZERO
	_root.modulate.a = 1.0
	_ring.stop()


# ---------------------------------------------------------------------------
# Раскладка
# ---------------------------------------------------------------------------

## Смещение «тапа» к цели: его гонит твин, а позиции указателей считаются от места покоя.
var bob: Vector2 = Vector2.ZERO:
	set(v):
		bob = v
		if _finger != null:
			_finger.position = _finger_rest + v
			_arrow.position = _arrow_rest + v
var _finger_rest: Vector2 = Vector2.ZERO
var _finger_bbox: Rect2 = Rect2()
var _toward: Vector2 = Vector2.UP   # от указателя к цели
var _arrow_rest: Vector2 = Vector2.ZERO


func _layout() -> void:
	var view := Rect2(Vector2.ZERO, _root.size)
	var rect := _rect
	_ring.setup(rect)
	var occupied: Array[Rect2] = [rect]
	if _finger.visible:
		_place_finger(view)
		occupied.append(_finger_box())
	if _arrow.visible:
		_place_arrow(view)
		occupied.append(Rect2(_arrow_rest, _arrow.size))
	_place_chip(view, occupied)


## Палец касается цели с той стороны, где нет соседей: снизу, сверху, слева, справа
## (по порядку). Раньше он всегда шёл снизу и в открытом меню ложился на плитку под
## целью. Нигде не свободно — как прежде: снизу, а если там нет места — сверху.
func _finger_candidate(side: String, view: Rect2) -> Dictionary:
	var fs := _finger.size
	var ft := FINGER_TIP
	var tip := Vector2.ZERO
	var box := Rect2()
	var toward := Vector2.UP
	var rot := 0.0
	var flip := false
	var rest := Vector2.ZERO
	match side:
		"below":
			tip = Vector2(clampf(_rect.get_center().x, EDGE + ft.x, view.end.x - EDGE - fs.x + ft.x), _rect.end.y - 4.0)
			box = Rect2(tip - ft, fs)
			rest = tip - ft
		"above":
			tip = Vector2(clampf(_rect.get_center().x, EDGE + ft.x, view.end.x - EDGE - fs.x + ft.x), _rect.position.y + 4.0)
			box = Rect2(tip - Vector2(ft.x, fs.y - ft.y), fs)
			rest = box.position
			toward = Vector2.DOWN
			flip = true
		"left":
			tip = Vector2(_rect.position.x + 4.0, clampf(_rect.get_center().y, EDGE + ft.x, view.end.y - EDGE - fs.x + ft.x))
			box = Rect2(tip + Vector2(-(fs.y - ft.y), -ft.x), Vector2(fs.y, fs.x))
			toward = Vector2.RIGHT
			rot = PI * 0.5
			rest = tip - ft
		_:
			tip = Vector2(_rect.end.x - 4.0, clampf(_rect.get_center().y, EDGE + fs.x - ft.x, view.end.y - EDGE - ft.x))
			box = Rect2(tip + Vector2(-ft.y, -(fs.x - ft.x)), Vector2(fs.y, fs.x))
			toward = Vector2.LEFT
			rot = -PI * 0.5
			rest = tip - ft
	var free := view.grow(-EDGE + 1.0).encloses(box)
	if free:
		for o in _blockers:
			if box.intersects(o):
				free = false
				break
	return {"rest": rest, "box": box, "toward": toward, "rot": rot, "flip": flip, "free": free}


func _place_finger(view: Rect2) -> void:
	var fs := _finger.size
	var pick := {}
	for side: String in ["below", "above", "left", "right"]:
		var c := _finger_candidate(side, view)
		if bool(c["free"]):
			pick = c
			break
	if pick.is_empty():
		var below := _rect.end.y + fs.y - 6.0 <= view.end.y - EDGE
		pick = _finger_candidate("below" if below else "above", view)
	_finger.flip_v = bool(pick["flip"])
	_finger.pivot_offset = FINGER_TIP
	_finger.rotation = float(pick["rot"])
	_toward = pick["toward"]
	_finger_rest = pick["rest"]
	_finger_bbox = pick["box"]
	_finger.position = _finger_rest + bob


## Занятое пальцем место на экране с учётом поворота.
func _finger_box() -> Rect2:
	return _finger_bbox


## Стрелка над объектом мира (сверху нет места — под ним).
func _place_arrow(view: Rect2) -> void:
	var asz := _arrow.size
	var above := _rect.position.y - asz.y - 4.0 >= view.position.y + EDGE
	var cx := clampf(_rect.get_center().x, EDGE + asz.x * 0.5, view.end.x - EDGE - asz.x * 0.5)
	_arrow.flip_v = not above
	if above:
		_arrow_rest = Vector2(cx - asz.x * 0.5, _rect.position.y - asz.y - 4.0)
		_toward = Vector2.DOWN
	else:
		_arrow_rest = Vector2(cx - asz.x * 0.5, _rect.end.y + 4.0)
		_toward = Vector2.UP
	_arrow.position = _arrow_rest + bob


static func rect_union(rects: Array[Rect2]) -> Rect2:
	var u: Rect2 = rects[0]
	for r in rects:
		u = u.merge(r)
	return u


func _place_chip(view: Rect2, occupied: Array[Rect2]) -> void:
	var sz := _chip.get_combined_minimum_size()
	_chip.size = sz
	var c := _rect.get_center()
	var candidates: Array[Vector2] = [
		Vector2(c.x - sz.x * 0.5, _rect.position.y - sz.y - CHIP_GAP),   # над целью
		Vector2(c.x - sz.x * 0.5, _rect.end.y + CHIP_GAP),                # под целью
		Vector2(_rect.end.x + CHIP_GAP, c.y - sz.y * 0.5),                # справа
		Vector2(_rect.position.x - sz.x - CHIP_GAP, c.y - sz.y * 0.5),    # слева
	]
	# Ещё два места: над всем занятым и под ним (палец сверху — тост выше пальца).
	var union := rect_union(occupied)
	candidates.append(Vector2(c.x - sz.x * 0.5, union.position.y - sz.y - CHIP_GAP))
	candidates.append(Vector2(c.x - sz.x * 0.5, union.end.y + CHIP_GAP))
	# Сползаем вниз вдоль цели: справа и слева от неё, но уже под соседями
	# (у кнопки героя справа стоят полоски, слева край экрана).
	var y := _rect.end.y
	while y < _rect.end.y + 72.0:
		candidates.append(Vector2(_rect.end.x + CHIP_GAP, y))
		candidates.append(Vector2(_rect.position.x - sz.x - CHIP_GAP, y))
		y += 4.0
	var best := Vector2.ZERO
	var found := false
	for cand in candidates:
		var pos := Vector2(clampf(cand.x, EDGE, view.end.x - EDGE - sz.x), cand.y)
		var r := Rect2(pos, sz)
		if not view.grow(-EDGE + 1.0).encloses(r):
			continue
		var clash := false
		for o in occupied:
			if r.intersects(o.grow(1.0)):
				clash = true
				break
		for o in _blockers:
			if r.intersects(o):
				clash = true
				break
		if clash:
			continue
		best = pos
		found = true
		break
	if not found:
		# Негде — прижимаем к верху экрана по центру цели: тост важнее аккуратности.
		best = Vector2(clampf(c.x - sz.x * 0.5, EDGE, view.end.x - EDGE - sz.x), view.position.y + 52.0)
	_chip.position = best
	_chip.pivot_offset = sz * 0.5


# ---------------------------------------------------------------------------
# Движение
# ---------------------------------------------------------------------------

func _start_animation(use_finger: bool, use_arrow: bool) -> void:
	if Settings.reduce_motion or not is_inside_tree():
		_ring.pulse = 0.35
		_ring.queue_redraw()
		return
	_root.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_root, "modulate:a", 1.0, 0.2)
	UiAnim.appear(_chip, UiAnim.POP_FROM, UiAnim.D_IN)
	_ring.start()
	if use_finger or use_arrow:
		_restart_tap()


func _restart_tap() -> void:
	if _tap_tween != null and _tap_tween.is_valid():
		_tap_tween.kill()
	_tap_tween = null
	bob = Vector2.ZERO
	if Settings.reduce_motion or not is_inside_tree() or not _shown:
		return
	if not _finger.visible and not _arrow.visible:
		return
	# Палец «давит» в цель, стрелка покачивается к ней: оба двигаются к цели.
	var push := _toward * 4.0
	_tap_tween = create_tween().set_loops()
	_tap_tween.tween_property(self, "bob", push, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tap_tween.tween_interval(0.08)
	_tap_tween.tween_property(self, "bob", Vector2.ZERO, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tap_tween.tween_interval(0.45)


func _on_chip_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		Tip.show_now(_chip)
	elif ev is InputEventScreenTouch and ev.pressed:
		Tip.show_now(_chip)

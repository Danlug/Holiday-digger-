class_name GuideSpotlight
extends CanvasLayer
## GuideSpotlight — «затемнение + стрелка + разрешённая цель» для обучающих сцен
## (раунд 6: премиум-выгрузка на 150; тот же приём у обучения часам-телепорту на 200 —
## модуль общий, урок только говорит, куда показать и что делать по нажатию).
##
## Всё, кроме цели, затемнено и не нажимается; вокруг цели — золотая рамка
## (HintRing, как у подсказок), к цели качается стрелка, рядом может висеть значок
## «что будет». Нажатие по цели — сигнал target_pressed. По умолчанию сама цель
## нажатие не получает (урок решает, что сделать: в витрине бесплатный первый раз не
## должен стать покупкой); pass_through = true — нажатие уходит и в цель.
## ⏭ — тот же SkipButton, что у катсцен (долгое нажатие или двойной тап) → skipped.
##
## Цель — Callable, который каждый кадр отдаёт прямоугольник на экране (проектные
## единицы): HUD и плитки витрины двигаются (прокрутка, твины), и рамка едет следом.
## Пустой прямоугольник — цели пока нет: затемнено всё, стрелки нет.
## Узел в группе hint_block: подсказки-знакомство молчат, пока идёт урок.
##
## Карточка-объяснение (обучение часам на 200, ветка teleport-watch): show_card({icon, title,
## text, button_icon, button_text}) — затемнено всё, по центру окно в стиле витрины с одной
## зелёной кнопкой → card_pressed. any_active() — идёт ли где-то урок со спотлайтом (сюжет
## ждёт, не начинает сцену поверх).

signal target_pressed
signal skipped
signal card_pressed

const LAYER := UiLayers.SPOTLIGHT   # над витриной (20) и подсказками (40), под окнами мета (92+) и катсценой (100)
const DIM := Color(0.02, 0.015, 0.03, 0.76)
const GROW := 3.0   # рамка и «окно» в затемнении чуть шире цели
const ARROW := Vector2(24, 24)
const BADGE := 22.0
const GAP := 4.0
const EDGE := 4.0

var pass_through: bool = false

var _target: Callable = Callable()
var _rect: Rect2 = Rect2()
var _root: Control
var _dims: Array[ColorRect] = []
var _catcher: Control
var _ring: HintRing
var _arrow: TextureRect
var _badge: TextureRect
var _skip: SkipButton
var _t: float = 0.0
var _toward: Vector2 = Vector2.DOWN
var _card: Control = null
var _last_press_frame: int = -1


func _init() -> void:
	layer = LAYER
	name = "GuideSpotlight"
	add_to_group(&"hint_block")
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	for i in 4:
		var d := ColorRect.new()
		d.color = DIM
		d.mouse_filter = Control.MOUSE_FILTER_STOP   # мимо цели не нажимается ничего
		_root.add_child(d)
		_dims.append(d)
	_catcher = Control.new()
	_catcher.name = "Target"
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.gui_input.connect(_on_catcher_input)
	_root.add_child(_catcher)
	_ring = HintRing.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_ring)
	_arrow = TextureRect.new()
	_arrow.texture = HintArt.tex("arrow")
	_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_arrow.size = ARROW
	_arrow.pivot_offset = ARROW * 0.5
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.modulate = Color(1.0, 0.86, 0.36)
	_root.add_child(_arrow)
	_badge = TextureRect.new()
	_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge.size = Vector2(BADGE, BADGE)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_badge)
	_skip = SkipButton.new()
	_skip.name = "Skip"
	_skip.hint_below = true
	_skip.confirmed.connect(func() -> void: skipped.emit())
	_root.add_child(_skip)
	visible = false
	set_process(false)


## Показать на цель. target: Callable -> Rect2 (экранные единицы). badge — значок «что
## будет» у стрелки (может быть null).
func point_at(target: Callable, badge: Texture2D = null) -> void:
	_close_card()
	_target = target
	_badge.texture = badge
	_badge.visible = badge != null
	visible = true
	_skip.reset_state()
	set_process(true)
	_ring.start()
	update(0.0)


func clear() -> void:
	_close_card()
	_target = Callable()
	_rect = Rect2()
	visible = false
	_ring.stop()
	set_process(false)


func is_active() -> bool:
	return visible


## Идёт ли где-нибудь урок со спотлайтом (сюжет не начинает сцену поверх).
static func any_active() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(&"hint_block"):
		if n is GuideSpotlight and is_instance_valid(n) and (n as GuideSpotlight).visible:
			return true
	return false


## Текущее «окно» в затемнении (пусто — цели нет).
func hole() -> Rect2:
	return _rect


## Пропустит ли затемнение нажатие в точке: только внутри цели (и ⏭).
func lets_through(pos: Vector2) -> bool:
	if not visible:
		return true
	if _rect.has_area() and _rect.has_point(pos):
		return true
	var cb := card_button()
	if cb != null and cb.get_global_rect().has_point(pos):
		return true
	return _skip.visible and _skip.get_global_rect().has_point(pos)


## Нажатие в точке экрана (тест и бот зовут напрямую, без событий ввода): по цели —
## сигнал, мимо — ничего. true — попали в цель.
func tap(pos: Vector2) -> bool:
	if not visible or not _rect.has_area() or not _rect.has_point(pos):
		return false
	_emit_target()
	return true


## Одно касание — один сигнал: палец приходит в цель дважды (само касание и мышь, которую
## движок из него делает), и без этого шаг урока проскакивал бы следующий.
func _emit_target() -> void:
	var f := Engine.get_process_frames()
	if f == _last_press_frame:
		return
	_last_press_frame = f
	target_pressed.emit()


func _process(dt: float) -> void:
	update(dt)


## Один шаг раскладки (тест зовёт с нужным dt сам).
func update(dt: float) -> void:
	_t += dt
	var r: Rect2 = _target.call() if _target.is_valid() else Rect2()
	_rect = r.grow(GROW) if r.has_area() else Rect2()
	var view := _root.get_viewport_rect().size if _root.is_inside_tree() else Vector2(224, 480)
	_layout_dims(view)
	var on := _rect.has_area()
	_catcher.visible = on
	_ring.visible = on
	_arrow.visible = on
	_badge.visible = on and _badge.texture != null
	_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE if pass_through else Control.MOUSE_FILTER_STOP
	if on:
		_catcher.position = _rect.position
		_catcher.size = _rect.size
		_ring.setup(r)
		_place_arrow(view)
	_place_skip(view)


## Четыре полосы вокруг окна: сверху, снизу, слева, справа. Без цели — одна на весь экран.
func _layout_dims(view: Vector2) -> void:
	if not _rect.has_area():
		_set_dim(0, Rect2(Vector2.ZERO, view))
		for i in range(1, 4):
			_dims[i].visible = false
		return
	var r := _rect
	_set_dim(0, Rect2(0, 0, view.x, r.position.y))
	_set_dim(1, Rect2(0, r.end.y, view.x, view.y - r.end.y))
	_set_dim(2, Rect2(0, r.position.y, r.position.x, r.size.y))
	_set_dim(3, Rect2(r.end.x, r.position.y, view.x - r.end.x, r.size.y))


func _set_dim(i: int, r: Rect2) -> void:
	var d := _dims[i]
	d.visible = r.size.x > 0.0 and r.size.y > 0.0
	d.position = r.position
	d.size = Vector2(maxf(r.size.x, 0.0), maxf(r.size.y, 0.0))


## Стрелка над целью, остриём вниз; у верхнего края места нет — под целью, остриём вверх.
## Значок «что будет» — сбоку от стрелки, ближе к середине экрана.
func _place_arrow(view: Vector2) -> void:
	var above := _rect.position.y - ARROW.y - GAP - 8.0 >= EDGE + 24.0
	_toward = Vector2.DOWN if above else Vector2.UP
	_arrow.rotation = 0.0 if above else PI
	var cx := clampf(_rect.get_center().x, EDGE + ARROW.x * 0.5, view.x - EDGE - ARROW.x * 0.5)
	var rest := Vector2(cx - ARROW.x * 0.5,
		_rect.position.y - ARROW.y - GAP if above else _rect.end.y + GAP)
	var bob := 0.0 if Settings.reduce_motion else absf(sin(_t * 5.0)) * 5.0
	_arrow.position = rest - _toward * bob
	var left := cx > view.x * 0.5
	_badge.position = Vector2(rest.x - BADGE - 2.0 if left else rest.x + ARROW.x + 2.0, rest.y + (ARROW.y - BADGE) * 0.5)
	_badge.position.x = clampf(_badge.position.x, EDGE, view.x - EDGE - BADGE)


## ⏭ в правом верхнем углу, как у катсцен; занят целью или стрелкой — в левом.
func _place_skip(view: Vector2) -> void:
	var sz := SkipButton.SIZE_PX
	var right := Rect2(Vector2(view.x - sz.x - 8.0, 6.0), sz)
	var busy := _rect.grow(4.0).intersects(right) or Rect2(_arrow.position, ARROW).intersects(right)
	_skip.position = Vector2(8.0, 6.0) if (_rect.has_area() and busy) else right.position


func _on_catcher_input(ev: InputEvent) -> void:
	var press := (ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (ev as InputEventMouseButton).pressed) \
			or (ev is InputEventScreenTouch and not (ev as InputEventScreenTouch).pressed)
	if press:
		_catcher.accept_event()
		_emit_target()


## Режим pass_through: окно ничего не ловит, нажатие уходит в саму цель, а сигнал —
## отсюда (событие не съедаем).
func _input(ev: InputEvent) -> void:
	if not visible or not pass_through or not _rect.has_area():
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (ev as InputEventMouseButton).pressed and _rect.has_point((ev as InputEventMouseButton).position):
		_emit_target()


# ---------------------------------------------------------------------------
# Карточка-объяснение (часы-телепорт на 200)
# ---------------------------------------------------------------------------

## Окно по центру поверх сплошного затемнения: значок в рамке, заголовок, текст, одна
## зелёная кнопка (значок + короткое слово) → card_pressed. ⏭ остаётся.
func show_card(def: Dictionary) -> void:
	_close_card()
	_target = Callable()
	_rect = Rect2()
	_ring.stop()
	visible = true
	_skip.reset_state()
	set_process(true)
	var view := _root.get_viewport_rect().size if _root.is_inside_tree() else Vector2(224, 480)
	var w := minf(view.x - 24.0, 210.0)
	_card = Control.new()
	_card.name = "Card"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_card)
	_root.move_child(_skip, -1)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxTexture.new()
	sb.texture = ShopArt.tex("panel")
	for m in ["left", "right", "top", "bottom"]:
		sb.set("texture_margin_" + m, 6)
		sb.set("content_margin_" + m, 10)
	panel.add_theme_stylebox_override("panel", sb)
	_card.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var icon_tex = def.get("icon", null)
	if icon_tex != null:
		var frame := PanelContainer.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override("panel", ProgressUiKit.box(Color(0.06, 0.05, 0.08), ProgressUiKit.GOLD, ProgressUiKit.R_TILE, 2))
		var ic := TextureRect.new()
		ic.texture = icon_tex
		ic.custom_minimum_size = Vector2(32, 32)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(ic)
		head.add_child(frame)
	var title := ShopArt.label(String(def.get("title", "")), 13, ProgressUiKit.TEXT_HI)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.clip_text = true
	head.add_child(title)
	var body := ShopArt.label(String(def.get("text", "")), 11, ProgressUiKit.TEXT, Color(0.05, 0.04, 0.08), 2)
	body.name = "Text"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Ширина переноса явно: без неё метка с переносом считает себя узкой и высокой,
	# и окно вытягивается на весь экран.
	body.custom_minimum_size = Vector2(w - 20.0, 0)
	col.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var btn := _green_button(def.get("button_icon", null), String(def.get("button_text", "")))
	btn.name = "CardButton"
	btn.pressed.connect(_on_card_button)
	row.add_child(btn)
	panel.custom_minimum_size = Vector2(w, 0)
	panel.reset_size()
	var ps := panel.get_combined_minimum_size()
	panel.position = Vector2(round((view.x - w) * 0.5), round(view.y * 0.42 - ps.y * 0.5))
	update(0.0)
	Sfx.play("ui_open")
	if not Settings.reduce_motion:
		panel.pivot_offset = Vector2(w * 0.5, ps.y * 0.5)
		panel.scale = Vector2(0.9, 0.9)
		panel.modulate.a = 0.0
		var tw := panel.create_tween().set_parallel(true)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "modulate:a", 1.0, 0.14)


func card_button() -> Button:
	if _card == null or not is_instance_valid(_card):
		return null
	return _card.find_child("CardButton", true, false) as Button


func card_text() -> String:
	if _card == null or not is_instance_valid(_card):
		return ""
	var l := _card.find_child("Text", true, false) as Label
	return l.text if l != null else ""


func _close_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null


func _on_card_button() -> void:
	if Tip.swallowed():
		return
	var f := Engine.get_process_frames()
	if f == _last_press_frame:
		return
	_last_press_frame = f
	Sfx.play("ui_buy")
	Haptics.tap()
	card_pressed.emit()


func _green_button(icon, text: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(110, 32)
	var tex := ShopArt.tex("btn_green")
	for stn in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		for m in ["left", "right", "top", "bottom"]:
			sb.set("texture_margin_" + m, 5)
		sb.content_margin_left = 8
		sb.content_margin_right = 10
		if stn == "pressed" or stn == "hover_pressed":
			sb.modulate_color = Color(0.78, 0.78, 0.78)
		b.add_theme_stylebox_override(stn, sb)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(row)
	if icon != null:
		var ic := TextureRect.new()
		ic.texture = icon
		ic.custom_minimum_size = Vector2(18, 18)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
	if text != "":
		var l := ShopArt.label(text, 12, Color.WHITE)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
	UiBtn.wire_sink(b)
	return b

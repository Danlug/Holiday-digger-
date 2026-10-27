class_name FocusTour
extends CanvasLayer
## FocusTour — обучение «всё темнеет, кроме одной цели, стрелка показывает, куда нажать».
## Общий модуль: им ведут обучение часам-телепорту (scripts/teleport/teleport_lesson.gd)
## и выгрузке на склад; любое новое обучение «затемнение + стрелка» — сюда же.
##
##   var tour := FocusTour.begin(host, [
##       {"id": "open", "target": "node:PremiumShopBtn", "label": "Лавка",
##        "until": func() -> bool: return ShopUI.instance.is_open()},
##       {"id": "tile", "target": "shop:good:dollars:teleport_watch", "tap": "catch",
##        "back": func() -> bool: return not ShopUI.instance.is_open()},
##       {"id": "why", "card": {"icon": tex, "title": "…", "text": "…",
##        "button_icon": tex, "button_text": "…"}, "on_tap": func() -> void: ...},
##   ], {"skippable": true})
##   tour.finished.connect(func(skipped: bool) -> void: ...)
##   tour.skip() / tour.stop() — снять (finished(true)); tour.complete() — пройдено (finished(false))
##
## Шаг — словарь:
##   id       имя шага (для теста и сигнала step_changed);
##   target   цель: Control; Callable() -> Control; строка
##              "node:<Имя>"      — видимый узел с таким именем где угодно в дереве,
##              "shop:<ключ>"     — плитка открытой витрины по ключу предложения (ShopItems: "good:dollars:<id>"),
##              иначе спецификация HintTargets: "hud:menu", "attached:<id>", "group:<имя>", "menu:<id>";
##            цели нет или она скрыта — экран тёмный целиком, шаг ждёт;
##   tap      "pass" (по умолчанию) — касание цели доходит до неё самой (кнопка срабатывает как обычно);
##            "catch" — касание забирает модуль: зовёт on_tap и переходит дальше (цель не нажимается);
##   until    Callable() -> bool — «шаг сделан», опрашивается каждый кадр. Без него шаг «pass»
##            кончается сигналом pressed цели;
##   back     Callable() -> bool — откатиться на шаг назад (окно, в котором цель, закрыли);
##   on_tap   Callable() — для «catch» и для карточки;
##   label    короткая подпись у стрелки (1–3 слова), icon — значок к ней (Texture2D);
##   card     {icon, title, text, button_icon, button_text} — шаг-объяснение: окно по центру
##            поверх затемнения, без цели; кнопка зовёт on_tap и кончает шаг.
## Опции begin: skippable (true) — кнопка ⏭ (долгое нажатие или двойной тап, как в сценах);
##              freeze (true) — герой стоит, ввод мира в HUD выключен; dim — плотность тени (0.72).
##
## Касание мимо цели не проходит никуда (тень его съедает). После конца — skip(), stop() или
## последний шаг — тень сразу перестаёт ловить касания и тает; узел удаляется сам.
## is_any_running() — идёт ли сейчас какое-нибудь обучение (сюжет ждёт, не начинает сцену поверх).

signal step_changed(index: int, id: String)
signal finished(skipped: bool)

const GROUP := &"focus_tour"
const LAYER := 45   # над витриной (20), дневником (30) и подсказками (40); под окнами меты (92+) и катсценой (100)
const GOLD := Color8(0xE0, 0xA9, 0x3B)
const GOLD_LIGHT := Color8(0xF2, 0xD9, 0x9B)
const ARROW_PX := 24.0       # стрелка подсказок (art/hints/arrow.png) вдвое крупнее: это обязательный шаг
const HOLE_PAD := 3.0        # насколько дырка в тени шире цели
const EDGE := 6.0
const FADE := 0.18

var steps: Array = []
var index: int = -1
var skippable: bool = true
var freeze: bool = true
var dim_alpha: float = 0.72

var _shield: _Shield
var _ring: HintRing
var _arrow: TextureRect
var _chip: PanelContainer
var _chip_icon: TextureRect
var _chip_label: Label
var _skip: SkipButton
var _card: Control = null
var _hole: Rect2 = Rect2()
var _target: Control = null
var _target_pressed: bool = false
var _pressed_src: Control = null
var _t: float = 0.0
var _done: bool = false
var _player: Node = null
var _hud: Node = null
var _prev_frozen: bool = false
var _prev_hud_input: bool = true


## Создать слой, повесить на host и запустить.
static func begin(host: Node, p_steps: Array, opts: Dictionary = {}) -> FocusTour:
	var t := FocusTour.new()
	t.steps = p_steps
	t.skippable = bool(opts.get("skippable", true))
	t.freeze = bool(opts.get("freeze", true))
	t.dim_alpha = float(opts.get("dim", 0.72))
	host.add_child(t)
	t.call_deferred("_start")
	return t


static func is_any_running() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(GROUP):
		if is_instance_valid(n) and not bool(n.get("_done")):
			return true
	return false


func _init() -> void:
	layer = LAYER
	name = "FocusTour"
	add_to_group(GROUP)


func _ready() -> void:
	_shield = _Shield.new()
	_shield.name = "Shield"
	_shield.tour = self
	add_child(_shield)

	_ring = HintRing.new()
	_ring.name = "Ring"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield.add_child(_ring)

	_arrow = TextureRect.new()
	_arrow.name = "Arrow"
	_arrow.texture = HintArt.tex("arrow")
	_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_arrow.stretch_mode = TextureRect.STRETCH_SCALE
	_arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_arrow.size = Vector2(ARROW_PX, ARROW_PX)
	_arrow.pivot_offset = _arrow.size * 0.5
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.visible = false
	_shield.add_child(_arrow)

	_chip = PanelContainer.new()
	_chip.name = "Chip"
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := ProgressUiKit.popup_box(GOLD, Color(0.071, 0.055, 0.043, 0.94))
	sb.content_margin_left = 6
	sb.content_margin_right = 7
	sb.content_margin_top = 2
	sb.content_margin_bottom = 3
	_chip.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	_chip.add_child(row)
	_chip_icon = TextureRect.new()
	_chip_icon.custom_minimum_size = Vector2(14, 14)
	_chip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_chip_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_chip_icon)
	_chip_label = ShopArt.label("", 11, GOLD_LIGHT)
	_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_chip_label)
	_chip.visible = false
	_shield.add_child(_chip)

	_skip = SkipButton.new()
	_skip.name = "SkipButton"
	_skip.visible = false
	_skip.confirmed.connect(skip)
	_shield.add_child(_skip)


func _exit_tree() -> void:
	# Узел ушёл из дерева посреди обучения (смена сцены, сброс) — управление не должно застрять.
	if not _done:
		_done = true
		_restore_control()


func is_running() -> bool:
	return index >= 0 and not _done


func current_id() -> String:
	if index < 0 or index >= steps.size():
		return ""
	return String(steps[index].get("id", ""))


## Прямоугольник дырки в тени (экранные единицы); пусто — цели нет, тёмно всё.
func hole() -> Rect2:
	return _hole


## Пропустить обучение (кнопка ⏭ зовёт это же).
func skip() -> void:
	_finish(true)


## Снять обучение извне (смерть, сброс): как пропуск — finished(true).
func stop() -> void:
	_finish(true)


## Закончить обучение досрочно как пройденное (кнопка карточки сама ведёт дальше) — finished(false).
func complete() -> void:
	_finish(false)


func _start() -> void:
	if _done:
		return
	_resolve_refs()
	if freeze:
		if _player != null:
			_prev_frozen = bool(_player.get("frozen"))
		if _hud != null:
			_prev_hud_input = _hud.is_processing_input()
		_apply_freeze()
	_skip.visible = skippable
	if not UiAnim.reduced():
		_shield.modulate.a = 0.0
		create_tween().tween_property(_shield, "modulate:a", 1.0, FADE)
	_go(0)


func _go(i: int) -> void:
	_close_card()
	_disconnect_target()
	if i >= steps.size():
		_finish(false)
		return
	index = maxi(0, i)
	_target_pressed = false
	var st: Dictionary = steps[index]
	if st.has("card"):
		_open_card(st["card"])
	_ring.stop()
	_hole = Rect2()
	_layout()
	step_changed.emit(index, current_id())


func _process(dt: float) -> void:
	if _done or index < 0:
		return
	_t += dt
	if freeze:
		_apply_freeze()
	var st: Dictionary = steps[index]
	var back: Callable = st.get("back", Callable())
	if back.is_valid() and index > 0 and bool(back.call()):
		_go(index - 1)
		return
	if _step_done(st):
		_go(index + 1)
		return
	_layout()


func _step_done(st: Dictionary) -> bool:
	if st.has("card"):
		return false
	var until: Callable = st.get("until", Callable())
	if until.is_valid():
		return bool(until.call())
	return String(st.get("tap", "pass")) == "pass" and _target_pressed


# ---------------------------------------------------------------------------
# Цель, тень, стрелка
# ---------------------------------------------------------------------------

func _resolve_target(spec) -> Control:
	var c: Control = null
	if spec is Control:
		c = spec
	elif spec is Callable:
		var v = (spec as Callable).call()
		c = v as Control if v is Control else null
	elif spec is String:
		var s := String(spec)
		if s.begins_with("node:"):
			c = _find_named(s.substr(5))
		elif s.begins_with("shop:"):
			c = _shop_tile(s.substr(5))
		else:
			var r := HintTargets.resolve(s)
			c = r.get("node", null) as Control
	if c == null or not is_instance_valid(c) or not c.is_inside_tree() or not c.is_visible_in_tree():
		return null
	var rect := c.get_global_rect()
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		return null
	return c


func _find_named(node_name: String) -> Control:
	var root := get_tree().root if is_inside_tree() else null
	if root == null:
		return null
	for n in root.find_children(node_name, "Control", true, false):
		var c := n as Control
		if c != null and c.is_visible_in_tree():
			return c
	return null


static func _shop_tile(key: String) -> Control:
	var shop := ShopUI.instance
	if shop == null or not shop.is_open():
		return null
	var tiles = shop.get("_tiles")
	if typeof(tiles) != TYPE_DICTIONARY:
		return null
	var t = (tiles as Dictionary).get(key, null)
	return t as Control if t != null and is_instance_valid(t) else null


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_shield.position = Vector2.ZERO
	_shield.size = vp
	var st: Dictionary = steps[index] if index >= 0 and index < steps.size() else {}
	var c: Control = null
	if not st.is_empty() and not st.has("card") and st.has("target"):
		c = _resolve_target(st["target"])
	if c != _target:
		_disconnect_target()
		_target = c
		if c is BaseButton:
			(c as BaseButton).pressed.connect(_on_target_pressed)
			_pressed_src = c
		if c != null:
			_ring.start()
		else:
			_ring.stop()
	if c == null:
		_hole = Rect2()
		_ring.visible = false
		_arrow.visible = false
		_chip.visible = false
	else:
		_hole = c.get_global_rect().grow(HOLE_PAD)
		_ring.visible = true
		_ring.position = Vector2.ZERO
		_ring.size = vp
		_ring.setup(_hole.grow(-HOLE_PAD))
		_place_arrow(vp, String(st.get("label", "")), st.get("icon", null))
	_place_skip(vp)
	_shield.queue_redraw()


## Стрелка — со стороны, где больше места к центру экрана: цель вверху — стрелка под ней
## остриём вверх, внизу — над ней остриём вниз. Подпись — за стрелкой.
func _place_arrow(vp: Vector2, text: String, icon) -> void:
	_arrow.visible = true
	var below := _hole.get_center().y < vp.y * 0.45
	var bob := 0.0 if UiAnim.reduced() else (sin(_t * TAU * 1.1) * 0.5 + 0.5) * 4.0
	var ax := clampf(_hole.get_center().x - ARROW_PX * 0.5, EDGE, vp.x - ARROW_PX - EDGE)
	var ay: float
	if below:
		ay = _hole.end.y + 3.0 + bob
		_arrow.rotation = PI
	else:
		ay = _hole.position.y - ARROW_PX - 3.0 - bob
		_arrow.rotation = 0.0
	_arrow.position = Vector2(round(ax), round(ay))
	_chip.visible = text != ""
	if not _chip.visible:
		return
	_chip_label.text = text
	_chip_icon.texture = icon as Texture2D
	_chip_icon.visible = icon != null
	_chip.reset_size()
	var cs := _chip.get_combined_minimum_size()
	var cx := clampf(_hole.get_center().x - cs.x * 0.5, EDGE, vp.x - cs.x - EDGE)
	var cy := (_arrow.position.y + ARROW_PX + 2.0) if below else (_arrow.position.y - cs.y - 2.0)
	_chip.position = Vector2(round(cx), round(cy))


func _place_skip(vp: Vector2) -> void:
	if not _skip.visible:
		return
	var s := SkipButton.SIZE_PX
	var top := Rect2(Vector2(vp.x - s.x - 8.0, 8.0), s)
	if _hole.size != Vector2.ZERO and top.grow(4.0).intersects(_hole):
		# Цель в правом верхнем углу — кнопка уходит вниз, чтобы не закрывать её.
		top.position.y = vp.y - s.y - 60.0
	_skip.position = top.position
	_skip.hint_below = top.position.y < vp.y * 0.5


func _on_target_pressed() -> void:
	_target_pressed = true


func _disconnect_target() -> void:
	if _pressed_src != null and is_instance_valid(_pressed_src) \
			and (_pressed_src as BaseButton).pressed.is_connected(_on_target_pressed):
		(_pressed_src as BaseButton).pressed.disconnect(_on_target_pressed)
	_pressed_src = null
	_target = null


## Касание по тени. «catch»: попадание в цель — действие шага; мимо — ничего.
func _on_shield_tap(pos: Vector2) -> void:
	if _done or index < 0:
		return
	var st: Dictionary = steps[index]
	if st.has("card"):
		return
	if String(st.get("tap", "pass")) == "catch" and _hole.size != Vector2.ZERO and _hole.has_point(pos):
		Sfx.play("ui_tap")
		Haptics.tap()
		var cb: Callable = st.get("on_tap", Callable())
		var at := index
		if cb.is_valid():
			cb.call()
		if not _done and index == at:
			_go(index + 1)
		return
	# Мимо цели: лёгкий отказ, чтобы было понятно, что нажимать надо туда, куда стрелка.
	if _hole.size != Vector2.ZERO:
		Sfx.play("ui_deny")
		_ring.start()


## Пропускать ли касание сквозь тень (только в дырку шага «pass»).
func passes_through(pos: Vector2) -> bool:
	if _done or index < 0:
		return true
	var st: Dictionary = steps[index]
	if st.has("card"):
		return false
	return String(st.get("tap", "pass")) == "pass" and _hole.size != Vector2.ZERO and _hole.has_point(pos)


# ---------------------------------------------------------------------------
# Карточка-объяснение
# ---------------------------------------------------------------------------

func _open_card(def: Dictionary) -> void:
	_card = Control.new()
	_card.name = "Card"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shield.add_child(_card)
	_shield.move_child(_skip, -1)

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
		frame.add_theme_stylebox_override("panel", ProgressUiKit.box(Color(0.06, 0.05, 0.08), GOLD, ProgressUiKit.R_TILE, 2))
		var ic := TextureRect.new()
		ic.texture = icon_tex
		ic.custom_minimum_size = Vector2(40, 40)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(ic)
		head.add_child(frame)
	var title := ShopArt.label(String(def.get("title", "")), 13, GOLD_LIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(title)

	var body := ShopArt.label(String(def.get("text", "")), 11, ProgressUiKit.TEXT, Color(0.05, 0.04, 0.08), 2)
	body.name = "Text"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(150, 0)
	col.add_child(body)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btn_row)
	var btn := _make_green_button(def.get("button_icon", null), String(def.get("button_text", "")))
	btn.name = "CardButton"
	btn.pressed.connect(_on_card_button)
	btn_row.add_child(btn)

	var vp := get_viewport().get_visible_rect().size
	var w := minf(vp.x - 24.0, 210.0)
	panel.custom_minimum_size = Vector2(w, 0)
	panel.reset_size()
	var ps := panel.get_combined_minimum_size()
	panel.position = Vector2(round((vp.x - w) * 0.5), round(vp.y * 0.42 - ps.y * 0.5))
	if not UiAnim.reduced():
		panel.pivot_offset = Vector2(w * 0.5, ps.y * 0.5)
		panel.scale = Vector2(0.9, 0.9)
		panel.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "modulate:a", 1.0, 0.14)
	Sfx.play("ui_open")


func _make_green_button(icon, text: String) -> Button:
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


func _on_card_button() -> void:
	if Tip.swallowed() or _done or index < 0:
		return
	Sfx.play("ui_buy")
	Haptics.tap()
	var st: Dictionary = steps[index]
	var cb: Callable = st.get("on_tap", Callable())
	var at := index
	if cb.is_valid():
		cb.call()
	if not _done and index == at:
		_go(index + 1)


func _close_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null


## Кнопка карточки (тестам и снимкам).
func card_button() -> Button:
	if _card == null or not is_instance_valid(_card):
		return null
	return _card.find_child("CardButton", true, false) as Button


func card_text() -> String:
	if _card == null or not is_instance_valid(_card):
		return ""
	var l := _card.find_child("Text", true, false) as Label
	return l.text if l != null else ""


# ---------------------------------------------------------------------------
# Управление героем и HUD на время обучения
# ---------------------------------------------------------------------------

func _resolve_refs() -> void:
	if not is_inside_tree():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().root.find_child("Player", true, false)
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().root.find_child("HUD", true, false)


## Каждый кадр, а не один раз: витрина, открытая по ходу шага, на закрытии возвращает
## «как было при её открытии», и без повтора герой ожил бы посреди обучения.
func _apply_freeze() -> void:
	if _player != null and is_instance_valid(_player):
		if not bool(_player.get("frozen")):
			_player.set("frozen", true)
			if _player.has_method("release_control"):
				_player.release_control()
		_player.set("digging", null)
	if _hud != null and is_instance_valid(_hud) and _hud.is_processing_input():
		_hud.set_process_input(false)


## Вернуть управление как было до обучения. Витрина, открытая по ходу, запомнила
## «заморожено» от нас — правим её память, иначе после её закрытия герой так и стоял бы.
func _restore_control() -> void:
	if not freeze:
		return
	var shop := ShopUI.instance
	if shop != null and is_instance_valid(shop) and shop.is_open():
		shop.set("_was_frozen", _prev_frozen)
		shop.set("_hud_input_was_on", _prev_hud_input)
		return
	if _player != null and is_instance_valid(_player):
		_player.set("frozen", _prev_frozen or GameState.house_is_indoors)
	if _hud != null and is_instance_valid(_hud):
		_hud.set_process_input(_prev_hud_input)


func _finish(skipped: bool) -> void:
	if _done:
		return
	_done = true
	_disconnect_target()
	_ring.stop()
	_restore_control()
	_shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _card != null and is_instance_valid(_card):
		for p in _card.find_children("*", "Control", true, false):
			(p as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip.visible = false
	finished.emit(skipped)
	if UiAnim.reduced() or not is_inside_tree():
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(_shield, "modulate:a", 0.0, FADE)
	tw.tween_callback(queue_free)


# ---------------------------------------------------------------------------
# Тень с дыркой: рисует затемнение и решает, кому достаётся касание
# ---------------------------------------------------------------------------

class _Shield extends Control:
	var tour: FocusTour

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_preset(Control.PRESET_TOP_LEFT)

	## Дырка шага «pass» — «не моя точка»: касание уходит к цели под тенью (Viewport ищет
	## следующий Control по слоям вниз). Остальное тень забирает себе.
	func _has_point(point: Vector2) -> bool:
		if tour == null or mouse_filter == Control.MOUSE_FILTER_IGNORE:
			return false
		return not tour.passes_through(point + global_position)

	func _gui_input(event: InputEvent) -> void:
		var press := false
		var pos := Vector2.ZERO
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			press = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
			pos = mb.global_position
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			press = st.pressed
			pos = st.position
		accept_event()
		if press and tour != null:
			tour._on_shield_tap(pos)

	func _draw() -> void:
		if tour == null:
			return
		var col := Color(0.02, 0.015, 0.03, tour.dim_alpha)
		var full := Rect2(Vector2.ZERO, size)
		var h := tour.hole()
		if h.size == Vector2.ZERO:
			draw_rect(full, col)
			return
		h = h.intersection(full)
		draw_rect(Rect2(0, 0, size.x, h.position.y), col)
		draw_rect(Rect2(0, h.end.y, size.x, size.y - h.end.y), col)
		draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), col)
		draw_rect(Rect2(h.end.x, h.position.y, size.x - h.end.x, h.size.y), col)

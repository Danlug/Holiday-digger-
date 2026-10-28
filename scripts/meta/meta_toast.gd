class_name MetaToast
extends CanvasLayer
## Плашка-тост сверху: значок + название (достижение получено, задание готово).
## Рубрика («Достижение», «Задание готово») — не словом, а цветом рамки и малым
## значком: слова на экране только по наведению. Пока открыто окно, тост идёт
## снизу, над полосой вкладок: сверху он закрывал бы шапку и крестик окна. Пока
## открыто окно смерти, тост ждёт его закрытия.
## Очередь по одному: пачка достижений при включении мета-слоя не закрывает
## экран, а показывается по очереди — и не больше MAX_QUEUE.

const MAX_QUEUE := 4
const HOLD := 2.2

var _queue: Array = []
var _busy: bool = false
var _panel: PanelContainer = null
var _from_bottom: bool = false


func _ready() -> void:
	layer = UiLayers.TOAST  # выше экрана героя (95), ниже катсцен (100)


func _process(_delta: float) -> void:
	if _panel != null:
		_panel.visible = not DeathWindow.is_open_any()   # уже летящий тост прячется под окном смерти


func show_achievement(a: Dictionary) -> void:
	var tier := clampi(int(a["tier"]), 1, 3)
	_enqueue({
		"glyph": String(a["glyph"]), "head": "medal", "name": String(a["name_ru"]),
		"reward": a.get("reward", {}), "frame": MetaUiKit.TIER_COL[tier - 1], "sfx": "reward",
	})


func show_quest(q: Dictionary) -> void:
	_enqueue({
		"glyph": String(q["glyph"]), "head": "check", "name": QuestGen.title(q),
		"reward": q.get("reward", {}), "frame": MetaUiKit.GREEN, "sfx": "quest_done",
	})


func show_road(count: int) -> void:
	_enqueue({
		"glyph": "trophy", "head": "trophy", "name": "×%d" % count,
		"reward": {}, "frame": MetaUiKit.GOLD, "sfx": "reward",
	})


func pending() -> int:
	return _queue.size() + (1 if _busy else 0)


func _enqueue(item: Dictionary) -> void:
	if _queue.size() >= MAX_QUEUE:
		return
	_queue.append(item)
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	if DeathWindow.is_open_any():   # окно смерти владеет экраном: тост ждёт
		get_tree().create_timer(0.3).timeout.connect(_next)
		return
	var item: Dictionary = _queue.pop_front()
	_build(item)
	Sfx.play(String(item["sfx"]))
	Haptics.tap()
	_from_bottom = _window_open()
	_panel.reset_size()
	_panel.position = Vector2(_panel_x(), _off_y())
	if UiAnim.reduced() or not is_inside_tree():
		_panel.position.y = _rest_y()
		get_tree().create_timer(HOLD).timeout.connect(_leave)
		return
	var tw := create_tween()
	tw.tween_property(_panel, "position:y", _rest_y(), UiAnim.D_IN + 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(HOLD)
	tw.tween_callback(_leave)


func _leave() -> void:
	if _panel == null:
		return
	if UiAnim.reduced():
		_panel.queue_free()
		_panel = null
		_next()
		return
	var tw := create_tween()
	tw.tween_property(_panel, "position:y", _off_y(), UiAnim.D_OUT + 0.04).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if _panel != null:
			_panel.queue_free()
			_panel = null
		_next())


func _window_open() -> bool:
	for n in get_tree().get_nodes_in_group("meta_hub"):
		if n.has_method("is_open") and n.is_open():
			return true
	for n in get_tree().get_nodes_in_group(HintBusy.BLOCK_GROUP):   # журнал, проекты, урок
		if (n is CanvasItem and n.is_visible_in_tree()) or (n is CanvasLayer and n.visible):
			return true
	return HintBusy._modal_open(get_tree())


func _view_h() -> float:
	return get_viewport().get_visible_rect().size.y


func _rest_y() -> float:
	return _view_h() - _panel.size.y - ProgressUiKit.TAB_BAR_H - 10.0 if _from_bottom else 6.0


func _off_y() -> float:
	return _view_h() + 10.0 if _from_bottom else -_panel.size.y - 10.0


func _panel_x() -> float:
	return maxf(4.0, (get_viewport().get_visible_rect().size.x - 208.0) * 0.5)


func _build(item: Dictionary) -> void:
	if _panel != null:
		_panel.queue_free()
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(208, 0)
	var frame: Color = item["frame"]
	_panel.add_theme_stylebox_override("panel", _style(frame))
	add_child(_panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(h)

	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_theme_stylebox_override("panel", MetaUiKit.box(MetaUiKit.SLOT, frame, 2, 3))
	tile.add_child(MetaUiKit.icon_rect(MetaUiKit.tex(String(item["glyph"])), 32))
	h.add_child(tile)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 3)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	title.add_child(MetaUiKit.icon_rect(MetaUiKit.tex(String(item["head"])), 12))
	var name_l := MetaUiKit.label(String(item["name"]), 10, Color.WHITE)
	name_l.clip_text = true
	name_l.custom_minimum_size.x = 100
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(name_l)
	var rr := MetaUiKit.reward_row(item["reward"], 11, 9)
	if rr.get_child_count() > 0:
		v.add_child(rr)
	else:
		rr.free()


func _style(frame: Color) -> StyleBoxFlat:
	var sb := ProgressUiKit.popup_box(frame, Color8(0x1A, 0x14, 0x0F, 0xF5), 4)
	return sb

class_name MetaToast
extends CanvasLayer
## Плашка-тост сверху: значок + короткое слово (достижение получено, задание
## готово). Очередь по одному: пачка достижений при включении мета-слоя не
## закрывает экран, а показывается по очереди — и не больше MAX_QUEUE.

const MAX_QUEUE := 4
const HOLD := 2.2

var _queue: Array = []
var _busy: bool = false
var _panel: PanelContainer = null


func _ready() -> void:
	layer = 97  # выше экрана героя (95), ниже катсцен (100)


func show_achievement(a: Dictionary) -> void:
	var tier := clampi(int(a["tier"]), 1, 3)
	_enqueue({
		"glyph": String(a["glyph"]), "head": "Достижение", "name": String(a["name_ru"]),
		"reward": a.get("reward", {}), "frame": MetaUiKit.TIER_COL[tier - 1], "sfx": "reward",
	})


func show_quest(q: Dictionary) -> void:
	_enqueue({
		"glyph": String(q["glyph"]), "head": "Задание готово", "name": QuestGen.title(q),
		"reward": q.get("reward", {}), "frame": MetaUiKit.GREEN, "sfx": "quest_done",
	})


func show_road(count: int) -> void:
	_enqueue({
		"glyph": "trophy", "head": "Дорога трофеев", "name": "Новая награда: %d" % count,
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
	var item: Dictionary = _queue.pop_front()
	_build(item)
	Sfx.play(String(item["sfx"]))
	Haptics.tap()
	_panel.position = Vector2(_panel_x(), -50.0)
	if UiAnim.reduced() or not is_inside_tree():
		_panel.position.y = 6.0
		get_tree().create_timer(HOLD).timeout.connect(_leave)
		return
	var tw := create_tween()
	tw.tween_property(_panel, "position:y", 6.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	tw.tween_property(_panel, "position:y", -50.0, 0.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if _panel != null:
			_panel.queue_free()
			_panel = null
		_next())


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
	v.add_child(MetaUiKit.label(String(item["head"]), 8, frame))
	var name_l := MetaUiKit.label(String(item["name"]), 10, Color.WHITE)
	name_l.clip_text = true
	name_l.custom_minimum_size.x = 100
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(name_l)
	var rr := MetaUiKit.reward_row(item["reward"], 11, 9)
	if rr.get_child_count() > 0:
		v.add_child(rr)
	else:
		rr.free()


func _style(frame: Color) -> StyleBoxFlat:
	var sb := MetaUiKit.box(Color8(0x1A, 0x14, 0x0F, 0xF5), frame, 1, 6)
	sb.set_content_margin_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 3
	return sb

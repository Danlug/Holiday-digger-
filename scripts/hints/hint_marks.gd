class_name HintMarks
extends Node
## Постоянные метки «новое», не очередь подсказок: красный «!» на кнопке «•••», пока в меню
## есть пункт, который игрок ещё ни разу не открывал, и ярлык «NEW» на самом пункте.
## Какие пункты помечать — data/hints.json -> menu_new.entries; «открыт» помнит
## GameState.ext["hints"].opened (нажатие по плитке в меню).
##
## Метки живут на своём слое (выше кольца подсказки, чтобы рамка не пересекала их) и
## каждый кадр следуют за своей кнопкой: правок в hud.gd и реестре меню не нужно, а меню
## пересобирается при каждом открытии — метки навешиваются заново. Пункт на плитке
## опознаём по заголовку подсказки (Tip), тем же способом, что HintTargets.
## Красный бейдж-число (MenuRegistry badge) — другое: он считает готовые награды, а
## здесь — «ты тут ещё не был».

const LAYER := UiLayers.HINT_MARKS
const POLL := 0.2
const BANG_OFFSET := Vector2(-4, -5)
const NEW_OFFSET := Vector2(-6, -5)

var _t: float = 0.0
var _layer: CanvasLayer
var _root: Control
## Метки: {mark: TextureRect, target: Control, offset: Vector2, kind: "bang"|"new", entry: String}
var _marks: Array = []
var _bang_tw: Tween = null


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	_layer.name = "HintMarksLayer"
	add_child(_layer)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_layer.add_child(_root)


func _process(dt: float) -> void:
	_t += dt
	if _t >= POLL:
		_t = 0.0
		refresh()
	_follow()


func refresh() -> void:
	var hud := HintConditions.hud()
	if hud == null or _root == null:
		return
	var on := HintState.enabled() and HintBusy.onboarding_done()
	var menu_open: bool = hud.has_method("is_more_menu_open") and hud.is_more_menu_open()
	var pending := new_entries()
	_sync_bang(hud, on and not menu_open and not pending.is_empty())
	_sync_tiles(hud, on and menu_open, pending)


## Пункты меню, у которых сейчас должна быть метка (видимы и ни разу не открыты).
func new_entries() -> Array:
	var out: Array = []
	for entry in HintData.menu_new_entries():
		var id := String(entry)
		if HintConditions.menu_entry_visible(id) and not HintState.entry_opened(id):
			out.append(id)
	return out


## Сколько меток сейчас показано (для тестов).
func visible_marks(kind: String = "") -> Array:
	var out: Array = []
	for m: Dictionary in _marks:
		var mark: TextureRect = m["mark"]
		if is_instance_valid(mark) and mark.visible and (kind.is_empty() or String(m["kind"]) == kind):
			out.append(m)
	return out


func _find(kind: String, target: Control) -> Dictionary:
	for m: Dictionary in _marks:
		if String(m["kind"]) == kind and m["target"] == target:
			return m
	return {}


func _sync_bang(hud: Control, show_it: bool) -> void:
	var btn := hud.get("_more_button") as Control
	if btn == null:
		return
	var m := _find("bang", btn)
	if m.is_empty():
		if not show_it:
			return
		m = _add("bang", btn, BANG_OFFSET, "")
	var mark: TextureRect = m["mark"]
	var was := mark.visible
	mark.visible = show_it
	if show_it and not was and not Settings.reduce_motion and mark.is_inside_tree():
		if _bang_tw != null and _bang_tw.is_valid():
			_bang_tw.kill()
		mark.pivot_offset = mark.size * 0.5
		_bang_tw = mark.create_tween().set_loops()
		_bang_tw.tween_property(mark, "scale", Vector2.ONE * 1.2, 0.4).set_trans(Tween.TRANS_SINE)
		_bang_tw.tween_property(mark, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE)


func _sync_tiles(hud: Control, show_it: bool, pending: Array) -> void:
	var grid = hud.get("_more_grid")
	if grid == null or not show_it:
		_drop("new")
		return
	var by_title := {}
	for e: Dictionary in MenuRegistry.entries():
		var id := String(e["id"])
		if pending.has(id):
			by_title[MenuRegistry.text_of(e, "title")] = id
	_drop("new", grid)
	for b: Node in (grid as Control).get_children():
		var meta = b.get_meta(Tip.META, {})
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		var title := String(meta.get("title", ""))
		if not by_title.has(title) or not _find("new", b as Control).is_empty():
			continue
		var entry := String(by_title[title])
		_add("new", b as Control, NEW_OFFSET, entry)
		if b is BaseButton:
			(b as BaseButton).pressed.connect(_on_tile_pressed.bind(entry))


## Убирает метки данного вида; с grid — только те, чьи плитки уже пересобраны или закрыты.
func _drop(kind: String, grid = null) -> void:
	for i in range(_marks.size() - 1, -1, -1):
		var m: Dictionary = _marks[i]
		if String(m["kind"]) != kind:
			continue
		var target = m["target"]
		var stale: bool = not is_instance_valid(target) or grid == null or (target as Node).get_parent() != grid
		if stale:
			if is_instance_valid(m["mark"]):
				(m["mark"] as Node).queue_free()
			_marks.remove_at(i)


func _on_tile_pressed(entry: String) -> void:
	if Tip.swallowed():
		return
	HintState.mark_entry_opened(entry)
	for i in range(_marks.size() - 1, -1, -1):
		var m: Dictionary = _marks[i]
		if String(m["entry"]) == entry:
			if is_instance_valid(m["mark"]):
				(m["mark"] as Node).queue_free()
			_marks.remove_at(i)


func _add(kind: String, target: Control, offset: Vector2, entry: String) -> Dictionary:
	var r := TextureRect.new()
	r.name = "Mark_" + kind
	var t := HintArt.tex("bang" if kind == "bang" else "new")
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = HintArt.size_of(t)
	r.custom_minimum_size = r.size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	var m := {"mark": r, "target": target, "offset": offset, "kind": kind, "entry": entry}
	_marks.append(m)
	if not Settings.reduce_motion and r.is_inside_tree():
		UiAnim.pulse(r, 0.3, 0.3)
	_follow()
	return m


## Метка стоит в углу своей кнопки; кнопка пропала или скрыта — метка скрыта (или убрана).
func _follow() -> void:
	if _root == null:
		return
	var hud := HintConditions.hud()
	if hud != null:
		_root.size = hud.get_viewport_rect().size
	for i in range(_marks.size() - 1, -1, -1):
		var m: Dictionary = _marks[i]
		var target = m["target"]
		var mark: TextureRect = m["mark"]
		if not is_instance_valid(target) or not is_instance_valid(mark):
			if is_instance_valid(mark):
				mark.queue_free()
			_marks.remove_at(i)
			continue
		var c := target as Control
		if String(m["kind"]) == "new":
			mark.visible = c.is_visible_in_tree()
		if mark.visible:
			mark.position = c.get_global_rect().position + (m["offset"] as Vector2)

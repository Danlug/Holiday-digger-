class_name HintMarks
extends Node
## Постоянные метки «новое», не очередь подсказок: красный «!» на кнопке «•••», пока в меню
## есть пункт, который игрок ещё ни разу не открывал, и ярлык «NEW» на самом пункте.
## Какие пункты помечать — data/hints.json -> menu_new.entries; «открыт» помнит
## GameState.ext["hints"].opened (нажатие по плитке в меню).
##
## Метки — дочерние узлы чужих кнопок, правок в hud.gd и реестре меню не нужно: меню
## пересобирается при каждом открытии, и метки навешиваются заново. Пункт на плитке
## опознаём по заголовку подсказки (Tip), тем же способом, что HintTargets.
## Красный бейдж-число (MenuRegistry badge) — другое: он считает готовые награды, а
## здесь — «ты тут ещё не был».

const BANG_NAME := "HintBang"
const NEW_NAME := "HintNew"
const POLL := 0.2

var _t: float = 0.0
var _bang: TextureRect = null
var _bang_tw: Tween = null


func _process(dt: float) -> void:
	_t += dt
	if _t < POLL:
		return
	_t = 0.0
	refresh()


func refresh() -> void:
	var hud := HintConditions.hud()
	if hud == null:
		return
	var on := HintState.enabled() and HintBusy.onboarding_done()
	var menu_open: bool = hud.has_method("is_more_menu_open") and hud.is_more_menu_open()
	_sync_bang(hud, on and not menu_open and not new_entries().is_empty())
	if on and menu_open:
		_sync_tiles(hud)


## Пункты меню, у которых сейчас должна быть метка (видимы и ни разу не открыты).
func new_entries() -> Array:
	var out: Array = []
	for entry in HintData.menu_new_entries():
		var id := String(entry)
		if HintConditions.menu_entry_visible(id) and not HintState.entry_opened(id):
			out.append(id)
	return out


func _sync_bang(hud: Control, show_it: bool) -> void:
	var btn = hud.get("_more_button")
	if btn == null:
		return
	if _bang == null or not is_instance_valid(_bang) or _bang.get_parent() != btn:
		_bang = (btn as Control).get_node_or_null(BANG_NAME) as TextureRect
		if _bang == null:
			if not show_it:
				return
			_bang = _make_mark("bang", BANG_NAME)
			_bang.position = Vector2(-4, -5)
			btn.add_child(_bang)
	var was := _bang.visible
	_bang.visible = show_it
	if show_it and not was and not Settings.reduce_motion and _bang.is_inside_tree():
		if _bang_tw != null and _bang_tw.is_valid():
			_bang_tw.kill()
		_bang_tw = _bang.create_tween().set_loops()
		_bang_tw.tween_property(_bang, "position:y", -7.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_bang_tw.tween_property(_bang, "position:y", -5.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _sync_tiles(hud: Control) -> void:
	var grid = hud.get("_more_grid")
	if grid == null:
		return
	var by_title := {}
	for e: Dictionary in MenuRegistry.entries():
		var id := String(e["id"])
		if new_entries().has(id):
			by_title[MenuRegistry.text_of(e, "title")] = id
	for b: Node in (grid as Control).get_children():
		if b.get_node_or_null(NEW_NAME) != null:
			continue
		var meta = b.get_meta(Tip.META, {})
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		var title := String(meta.get("title", ""))
		if not by_title.has(title):
			continue
		var mark := _make_mark("new", NEW_NAME)
		mark.position = Vector2(-6, -5)
		b.add_child(mark)
		if b is BaseButton:
			(b as BaseButton).pressed.connect(_on_tile_pressed.bind(String(by_title[title]), mark))
		if not Settings.reduce_motion and mark.is_inside_tree():
			UiAnim.pulse(mark, 0.3, 0.3)


func _on_tile_pressed(entry: String, mark: Node) -> void:
	if Tip.swallowed():
		return
	HintState.mark_entry_opened(entry)
	if mark != null and is_instance_valid(mark):
		mark.queue_free()


func _make_mark(art_name: String, node_name: String) -> TextureRect:
	var r := TextureRect.new()
	r.name = node_name
	var t := HintArt.tex(art_name)
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = HintArt.size_of(t)
	r.custom_minimum_size = r.size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_index = 2
	return r

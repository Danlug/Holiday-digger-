class_name ShopDoorGuide
extends CanvasLayer
## ShopDoorGuide — «к двери»: стрелка над миром ведёт с огорода к входной двери
## (раунд 5, ветка garden-shop). Не телепорт: герой идёт сам, стрелка только
## показывает куда.
##
## Дверь на экране — прыгающая стрелка вниз прямо над ней. Дверь за краем
## экрана (огород шире кадра в четыре раза) — стрелка у края, по высоте двери,
## с маленькой дверью рядом. Дошёл до двери (там всплывает пузырь «Зайти» дома) —
## стрелка гаснет; зашёл в дом в ближайшие REOPEN_SECONDS — витрина сама
## открывается в прихожей на той вкладке, с которой его отправили.
## Гаснет и сама: через SECONDS, под землёй, в доме, при смерти.
##
## Узел живёт в ShopUI (одна строка там), координаты двери берёт у HouseSystem:
## это ребёнок ViewRoot, и его канвас-преобразование и есть камера мира.

const SECONDS := 20.0
const REOPEN_SECONDS := 30.0
const TILE := 32.0
const EDGE := 6.0

var tab: String = ""
var _left: float = 0.0
var _reopen_left: float = 0.0
var _reopen_wait: float = 0.0
var _t: float = 0.0

var _root: Control
var _down: Control      # стрелка над дверью
var _edge: Control      # стрелка у края экрана
var _edge_arrow: TextureRect


func _ready() -> void:
	name = "DoorGuide"
	layer = 8   # как пузыри дома: под HUD-шторками, над миром
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_down = Control.new()
	_down.name = "Down"
	_down.size = Vector2(24, 24)
	_down.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := ShopArt.rect(ShopArt.tex("glyph_arrow"), Vector2.ZERO, Vector2(24, 24))
	a.pivot_offset = Vector2(12, 12)
	a.rotation = PI * 0.5
	_down.add_child(a)
	_root.add_child(_down)

	_edge = Control.new()
	_edge.name = "Edge"
	_edge.size = Vector2(40, 24)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_arrow = ShopArt.rect(ShopArt.tex("glyph_arrow"), Vector2.ZERO, Vector2(24, 24))
	_edge.add_child(_edge_arrow)
	_edge.add_child(ShopArt.rect(ShopArt.tex("glyph_door"), Vector2(0, 4), Vector2(16, 16)))
	_root.add_child(_edge)
	_hide_marks()
	set_process(false)


func is_active() -> bool:
	return _left > 0.0


func is_reopen_pending() -> bool:
	return _reopen_left > 0.0


## Повести к двери; tab — вкладка витрины, которую открыть, когда герой зайдёт.
func start(tab_id: String) -> void:
	tab = tab_id
	_left = SECONDS
	_reopen_left = 0.0
	_t = 0.0
	set_process(true)


func stop() -> void:
	_left = 0.0
	_reopen_left = 0.0
	_hide_marks()
	set_process(false)


func _hide_marks() -> void:
	if _down != null:
		_down.visible = false
		_edge.visible = false


func _process(dt: float) -> void:
	_update(dt)


## Один шаг: dt — секунды (тест зовёт с нужным dt сам, без таймеров сцены).
func _update(dt: float) -> void:
	_t += dt
	if _reopen_left > 0.0:
		_tick_reopen(dt)
		return
	if _left <= 0.0:
		return
	_left -= dt
	var hs := HouseSystem.instance
	if _left <= 0.0 or hs == null or not is_instance_valid(hs) or not GameState.is_alive \
			or GameState.player_depth >= 1 or GameState.era == "grandpa":
		stop()
		return
	if GameState.house_is_indoors or hs.near_door():
		# Дошёл: дальше ведёт пузырь «Зайти» дома; ждём, зайдёт ли.
		_left = 0.0
		_hide_marks()
		_reopen_left = REOPEN_SECONDS
		_reopen_wait = 0.4
		_tick_reopen(0.0)
		return
	_place_marks(door_screen_pos(), get_viewport().get_visible_rect().size)


## Дверь в координатах экрана (вьюпорта): низ проёма, по центру клетки.
static func door_screen_pos() -> Vector2:
	var hs := HouseSystem.instance
	if hs == null or not is_instance_valid(hs) or not hs.is_inside_tree():
		return Vector2(-1, -1)
	var door := HouseConfig.door_cell()
	return hs.get_global_transform_with_canvas() * Vector2((float(door.x) + 0.5) * TILE, float(door.y) * TILE)


## Где рисовать: дверь в кадре — стрелка вниз над ней; за краем — стрелка у
## края в её сторону. Возвращает "down" / "left" / "right" (для теста).
func _place_marks(door: Vector2, view: Vector2) -> String:
	var bob := 0.0 if Settings.reduce_motion else absf(sin(_t * 6.0)) * 5.0
	if door.x >= EDGE + 8.0 and door.x <= view.x - EDGE - 8.0:
		_edge.visible = false
		_down.visible = true
		# Над проёмом двери, с запасом на козырёк: сам проём — клетка над порогом.
		_down.position = Vector2(door.x - 12.0, door.y - TILE * 1.5 - 26.0 - bob)
		return "down"
	_down.visible = false
	_edge.visible = true
	var left := door.x < EDGE + 8.0
	var y := clampf(door.y - TILE * 0.5 - 12.0, 120.0, view.y - 120.0)
	_edge_arrow.flip_h = left
	if left:
		_edge_arrow.position = Vector2(-bob * 0.6, 0)
		_edge.get_child(1).position = Vector2(24, 4)
		_edge.position = Vector2(EDGE, y)
	else:
		_edge_arrow.position = Vector2(16 + bob * 0.6, 0)
		_edge.get_child(1).position = Vector2(0, 4)
		_edge.position = Vector2(view.x - EDGE - 40.0, y)
	return "left" if left else "right"


## Ждём, пока герой зайдёт в прихожую, и открываем витрину там. Не открываем,
## если игрок занят другим (сюжет, обучение дома, шторка) или ушёл не туда.
func _tick_reopen(dt: float) -> void:
	_reopen_left -= dt
	if _reopen_left <= 0.0 or not GameState.is_alive or GameState.player_depth >= 1:
		stop()
		return
	if not GameState.house_is_indoors:
		return
	if GameState.house_room != "hall":
		stop()
		return
	_reopen_wait -= dt
	if _reopen_wait > 0.0:
		return
	var ui := ShopUI.instance
	_reopen_left = 0.0
	set_process(false)
	if ui == null or ui.is_open() or _busy_elsewhere():
		return
	ui.open(tab if tab != "" else ShopUI.TAB_FOOD)


func _busy_elsewhere() -> bool:
	var hs := HouseSystem.instance
	var view = hs.get("_view") if hs != null and is_instance_valid(hs) else null
	if view != null and view.has_method("forced_mode") and String(view.forced_mode()) != "":
		return true
	var tree := get_tree()
	return tree == null or tree.paused or HintBusy._cutscene_or_autodig(tree)

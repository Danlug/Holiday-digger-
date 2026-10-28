class_name GraveSite
extends Node2D
## Могила деда во дворе — интерактивный объект мира (ГДД раздел 2, «Сюжет
## после старта»). Рисует плиту, банку с дневником и парящий значок «есть что
## прочесть»; когда герой подошёл, над ним всплывает кнопка, как у «Зайти» у
## двери. Что именно случится по нажатию — решает режиссёр (сигнал pressed):
## первая встреча с тетрадью — сцена, дальше — экран дневника.
##
## Стоит в клетке 14 у забора огорода, на пути от двери к тоннелю: за каждой
## страницей не ходят через всю карту. Кнопка гаснет за пределами ±NEAR, так
## что не наезжает на кнопку «Зайти» у двери (клетка 11, радиус 1.2).

signal pressed

const TILE := 32
const GRAVE_X := 14.0
const NEAR := 0.9
## Графика — tools/gen_grave.py: текстуры 2 px на игровой пиксель (гравировке
## портрета нужна сетка мельче тайла), отсюда масштаб 0.5. Две картинки одного
## размера: плита на месте (до сцены diary_first) и сдвинутая, с ямой справа.
const STONE_TEX := "res://art/env/grave.png"
const STONE_OPEN_TEX := "res://art/env/grave_open.png"
const STONE_SCALE := 0.5
## Банка с тетрадью стоит в яме под сдвинутой плитой (правый край grave_open);
## сцена diary_first рисует её в той же точке (data/story_arc.json), пока флаг
## diary_found не поставлен. Низ банки — дно ямы, на 7 px выше линии земли.
const JAR_X := 14.6
const JAR_TEX := "res://art/env/grave_jar.png"
const JAR_SCALE := 0.5
const JAR_BOTTOM_Y := 25.0
## Самородок из концовки (ending.n6: «положил на могильную плиту») остаётся
## лежать на плите; сцена кладёт его туда же (story_arc.json), а когда плита
## сдвинута, самородок едет вместе с ней.
const NUGGET_TEX := "res://art/story/prop_nugget.png"
const NUGGET_X := 14.15
const NUGGET_SCALE := 0.5
const NUGGET_BOTTOM_Y := 22.0
const NUGGET_OPEN_DX := -6.0
const MARKER_TEX := "res://art/story/grave_marker.png"
const ICON_DIARY := "res://art/story/icon_diary.png"
const ICON_FLOWER := "res://art/story/icon_flower.png"

var player: Node = null
var hud: Node = null

var _stone: Sprite2D
var _stone_closed: Texture2D
var _stone_open: Texture2D
var _jar: Sprite2D
var _nugget: Sprite2D
var _marker: Sprite2D
var _marker_base_y: float = 0.0
var _layer: CanvasLayer
var _button: Button
var _badge: Label
var _t: float = 0.0
var _mode: String = ""   # "flower" | "diary" — что сейчас нарисовано на кнопке


func _ready() -> void:
	name = "GraveSite"
	_build_world()
	_build_button()


func _build_world() -> void:
	_stone = Sprite2D.new()
	_stone.centered = false
	_stone_closed = load(STONE_TEX)
	_stone_open = load(STONE_OPEN_TEX) if ResourceLoader.exists(STONE_OPEN_TEX) else _stone_closed
	_stone.texture = _stone_closed
	_stone.scale = Vector2(STONE_SCALE, STONE_SCALE)
	var size := _stone_closed.get_size() * STONE_SCALE
	_stone.position = Vector2(GRAVE_X * TILE - size.x / 2.0, TILE - size.y)
	add_child(_stone)

	_jar = Sprite2D.new()
	_jar.centered = false
	_jar.texture = load(JAR_TEX)
	_jar.scale = Vector2(JAR_SCALE, JAR_SCALE)
	var jar_size := _jar.texture.get_size() * JAR_SCALE
	_jar.position = Vector2(JAR_X * TILE - jar_size.x / 2.0, JAR_BOTTOM_Y - jar_size.y)
	add_child(_jar)

	_nugget = Sprite2D.new()
	_nugget.centered = false
	if ResourceLoader.exists(NUGGET_TEX):
		_nugget.texture = load(NUGGET_TEX)
	_nugget.scale = Vector2(NUGGET_SCALE, NUGGET_SCALE)
	_nugget.visible = false
	add_child(_nugget)

	_marker = Sprite2D.new()
	_marker.centered = false
	_marker.texture = load(MARKER_TEX)
	_marker_base_y = TILE - size.y - 20.0
	_marker.position = Vector2(GRAVE_X * TILE - 7.0, _marker_base_y)
	add_child(_marker)


func _build_button() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "GraveHotspot"
	_layer.layer = UiLayers.WORLD_BUBBLES
	add_child(_layer)

	_button = Button.new()
	_button.name = "GraveBtn"
	_button.custom_minimum_size = Vector2(38, 32)
	_button.focus_mode = Control.FOCUS_NONE
	_button.expand_icon = false
	_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.05, 0.04, 0.92)
		sb.border_color = UiTheme.GOLD if state == "pressed" or state == "hover" else UiTheme.BORDER
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		_button.add_theme_stylebox_override(state, sb)
	_button.visible = false
	_button.pressed.connect(_on_pressed)
	_layer.add_child(_button)

	_badge = Label.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_font_size_override("font_size", 9)
	_badge.add_theme_color_override("font_color", Color.WHITE)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.custom_minimum_size = Vector2(14, 14)
	_badge.size = Vector2(14, 14)
	_badge.position = Vector2(26, -5)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = UiTheme.DANGER   # тот же красный, что у бейджа UiBtn
	bsb.set_corner_radius_all(7)
	_badge.add_theme_stylebox_override("normal", bsb)
	_badge.visible = false
	_button.add_child(_badge)


# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

func is_near() -> bool:
	return player != null and player.y < 1.5 and absf(player.x - GRAVE_X) <= NEAR


func diary_found() -> bool:
	return StoryState.has_flag("diary_found")


## Есть ли что показать значком: звонок бабки был, а тетрадь ещё не взята, или
## в тетради есть непрочитанные страницы.
func has_news() -> bool:
	if diary_found():
		return not StoryDiary.unread_ids().is_empty()
	return StoryState.is_seen("grave_call")


func _on_pressed() -> void:
	if Tip.swallowed():
		return
	Sfx.play("ui_tap")
	Haptics.tap()
	pressed.emit()


func _process(dt: float) -> void:
	_t += dt
	var visible_world: bool = GameState.era != "grandpa"
	var opened := diary_found()
	_stone.visible = visible_world
	var want: Texture2D = _stone_open if opened else _stone_closed
	if _stone.texture != want:
		_stone.texture = want
	_jar.visible = visible_world and opened
	_nugget.visible = visible_world and _nugget.texture != null and StoryState.is_seen("ending")
	if _nugget.visible:
		var ns := _nugget.texture.get_size() * NUGGET_SCALE
		var dx := NUGGET_OPEN_DX if opened else 0.0
		_nugget.position = Vector2(NUGGET_X * TILE - ns.x / 2.0 + dx, NUGGET_BOTTOM_Y - ns.y)
	_marker.visible = visible_world and has_news()
	if _marker.visible:
		_marker.position.y = _marker_base_y + sin(_t * 3.0) * 2.0
	_update_button()


func _update_button() -> void:
	var show_it: bool = is_near() and GameState.era != "grandpa" and GameState.is_alive \
		and not GameState.house_is_indoors and not bool(player.get("frozen"))
	_button.visible = show_it
	if not show_it:
		return
	var mode := "diary" if (diary_found() or StoryState.is_seen("grave_call")) else "flower"
	if mode != _mode:
		_mode = mode
		_button.icon = load(ICON_DIARY if mode == "diary" else ICON_FLOWER)
		if mode == "diary":
			Tip.bind(_button, StoryText.get_text("grave.tip_diary_title"), StoryText.get_text("grave.tip_diary_body"))
		else:
			Tip.bind(_button, StoryText.get_text("grave.tip_title"), StoryText.get_text("grave.tip_body"))
	var unread := StoryDiary.unread_ids().size() if diary_found() else 0
	_badge.visible = unread > 0
	_badge.text = str(unread)
	if hud == null:
		return
	var cam := _camera()
	var head := Vector2(player.x - cam.x, player.y - cam.y - 1.0) * TILE
	_button.position = head - Vector2(_button.custom_minimum_size.x / 2.0, _button.custom_minimum_size.y + 4.0)


## Та же формула камеры, что в main.gd:_camera() и house_system.gd:
## _outdoor_camera() — кнопка стоит ровно над головой героя на экране.
func _camera() -> Vector2:
	var cells: Vector2i = hud.get_view_cells()
	var vw := float(cells.x)
	var vh := float(cells.y)
	var sky: int = preload("res://scripts/world/world_view.gd").SKY_HEIGHT
	return CameraRig.for_overlay(player.x, player.y, vw, vh, sky)

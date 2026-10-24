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
## Банка с тетрадью стоит у правого края плиты; сцена diary_first рисует её
## в той же клетке (data/story_arc.json), пока флаг diary_found не поставлен.
const JAR_X := 14.95
const NEAR := 0.9
const STONE_TEX := "res://art/env/grave.png"
const STONE_SCALE := 1.5
const JAR_TEX := "res://art/story/grave_jar.png"
const MARKER_TEX := "res://art/story/grave_marker.png"
const ICON_DIARY := "res://art/story/icon_diary.png"
const ICON_FLOWER := "res://art/story/icon_flower.png"

var player: Node = null
var hud: Node = null

var _stone: Sprite2D
var _jar: Sprite2D
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
	var tex: Texture2D = load(STONE_TEX)
	_stone.texture = tex
	_stone.scale = Vector2(STONE_SCALE, STONE_SCALE)
	var size := tex.get_size() * STONE_SCALE
	_stone.position = Vector2(GRAVE_X * TILE - size.x / 2.0, TILE - size.y)
	add_child(_stone)

	_jar = Sprite2D.new()
	_jar.centered = false
	_jar.texture = load(JAR_TEX)
	_jar.position = Vector2(JAR_X * TILE - 8.0, TILE - 16.0)
	add_child(_jar)

	_marker = Sprite2D.new()
	_marker.centered = false
	_marker.texture = load(MARKER_TEX)
	_marker_base_y = TILE - size.y - 20.0
	_marker.position = Vector2(GRAVE_X * TILE - 7.0, _marker_base_y)
	add_child(_marker)


func _build_button() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "GraveHotspot"
	_layer.layer = 8
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
		sb.border_color = Color8(0xE0, 0xA9, 0x3B) if state == "pressed" or state == "hover" else Color8(0x3E, 0x31, 0x25)
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
	bsb.bg_color = Color8(0xC2, 0x1E, 0x3A)
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
	_stone.visible = visible_world
	_jar.visible = visible_world and diary_found()
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

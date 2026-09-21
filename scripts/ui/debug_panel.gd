class_name DebugPanel
extends Control
## DebugPanel — тестовая отладочная панель («Раскопки на каникулах», задача
## владельца от 2026-09-21). НЕ для релиза игрокам — четыре тумблера
## вкл/выкл, каждый напрямую ставит/снимает флаг в GameState:
##
##   «Копка»       -> GameState.debug_instant_dig — время копки клетки = 0
##                     (см. player.gd:_start_dig).
##   «Бессмертие»  -> GameState.debug_invincible — урон (GameState.take_damage,
##                     единая точка: падение/голод/будущие источники) не
##                     применяется; HP не восстанавливается принудительно.
##   «Полёт 300»   -> GameState.debug_fly_300 — подъём/падение всегда ровно
##                     300 клеток/с (см. player.gd:_move_y, одно место, общее
##                     для ходьбы, ранца/джетпака и бурмобиля).
##   «Бесплатно»   -> GameState.debug_free_shop — GameState.spend_coins и
##                     spend_dollars (единая точка списания в обоих магазинах:
##                     крафт, кирки/ранцы, лавка, еда, премиум-лавка) ничего
##                     не списывают.
##
## Флаги живут в GameState, не сохраняются в сейв и не трогаются
## reset_progress() — обычный перезапуск игры возвращает все четыре в false
## (см. блок «отладочная тестовая панель» в game_state.gd).
##
## Место на экране (решение агента — задание разрешало любой из двух
## вариантов): свернуть/развернуть маленькой кнопкой «Тест», тем же приёмом,
## что меню «•••» в hud.gd (кнопка-триггер + всплывающая панель, которая не
## резервирует место на экране, пока закрыта, — см. hud.gd:_build_more_menu).
## Триггер стоит НАД основной нижней полосой (там уже инструмент/«•••»/
## топливо, и рядом другой агент двигает стрелки по бокам — см. задание) в
## углу СЛЕВА, зеркально меню «•••» справа, — поэтому раскрытые панели друг
## другу не мешают. Разворачиваясь, панель растёт ВВЕРХ от триггера, как и
## «•••». DebugPanel не завязан на видимость полосок GameState/сюжетные
## состояния и добавляется в HUD последним, поэтому виден и кликабелен поверх
## всего остального — и дома, и на поверхности, и под землёй.

## Высота основной нижней полосы hud.gd (STRIP_H там же) — значение
## продублировано здесь намеренно: DebugPanel не должен тянуть к себе
## зависимость от hud.gd, чтобы его можно было переиспользовать/тестировать
## отдельно (см. tests/test_debug_panel.gd).
const STRIP_H := 40.0
const GAP := 2.0
const TRIGGER_SIZE := Vector2(30.0, 18.0)

const TOGGLES := [
	{"field": "debug_instant_dig", "label": "Копка"},
	{"field": "debug_invincible", "label": "Бессмертие"},
	{"field": "debug_fly_300", "label": "Полёт 300"},
	{"field": "debug_free_shop", "label": "Бесплатно"},
]

var _trigger: Button
var _panel: PanelContainer
var _buttons: Dictionary = {}   # field:String -> Button


func _ready() -> void:
	# Сам контейнер прозрачен для мимо-кликов на всей площади HUD — реально
	# кликабельны только триггер и (пока раскрыта) сама панель тумблеров.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	_trigger = Button.new()
	_trigger.name = "DebugPanelTrigger"
	_trigger.text = "Тест"
	_trigger.focus_mode = Control.FOCUS_NONE
	_trigger.add_theme_font_size_override("font_size", 9)
	_trigger.tooltip_text = "Тестовая панель отладки (не для релиза)"
	# Один угол-якорь (см. комментарий у _panel ниже): якорь и рост задаём
	# ДО custom_minimum_size — иначе верхний край считается один раз от
	# нулевого размера и застывает, а нижний (offset_bottom) едет отдельно,
	# и получается перевёрнутый прямоугольник нулевой видимой высоты (баг
	# отчёта агента: кнопка «Тест» не рисовалась вовсе). custom_minimum_size,
	# заданный ПОСЛЕ, сам досчитывает верхний край от зафиксированного нижнего.
	_trigger.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_trigger.grow_horizontal = Control.GROW_DIRECTION_END
	_trigger.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_trigger.offset_left = 3.0
	_trigger.offset_bottom = -STRIP_H - GAP
	_trigger.custom_minimum_size = TRIGGER_SIZE
	_trigger.pressed.connect(_toggle_panel)
	add_child(_trigger)

	_panel = PanelContainer.new()
	_panel.name = "DebugPanelToggles"
	_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0x1A, 0x14, 0x0F)
	sb.border_color = Color8(0x3E, 0x31, 0x25)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	# Один угол-якорь (не растяжение): панель сама сжимается по содержимому
	# (HBoxContainer внутри) и растёт вверх-вправо от зафиксированной точки —
	# тот же приём, что и у hud.gd:_more_panel (там растёт вверх-влево).
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = 3.0
	_panel.offset_bottom = -STRIP_H - GAP - TRIGGER_SIZE.y - GAP
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_panel.add_child(row)

	for t in TOGGLES:
		var field := String(t["field"])
		var b := Button.new()
		b.text = String(t["label"])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 9)
		b.custom_minimum_size = Vector2(48.0, 28.0)
		b.pressed.connect(_on_toggle_pressed.bind(field))
		row.add_child(b)
		_buttons[field] = b

	_refresh()


func _toggle_panel() -> void:
	set_open(not is_open())


## Раскрыта ли панель тумблеров прямо сейчас.
func is_open() -> bool:
	return _panel != null and _panel.visible


func set_open(open: bool) -> void:
	if _panel == null:
		return
	_panel.visible = open
	if open:
		_refresh()


## Переключить один тумблер по имени поля GameState (используется и кнопками,
## и напрямую тестами — tests/test_debug_panel.gd).
func toggle(field: String) -> void:
	GameState.set(field, not bool(GameState.get(field)))
	_refresh()


func _on_toggle_pressed(field: String) -> void:
	toggle(field)


## Перечитать состояние GameState и перекрасить все четыре кнопки — зелёная
## обводка/заливка, когда флаг true, серая, когда false (задание владельца).
func _refresh() -> void:
	for t in TOGGLES:
		var field := String(t["field"])
		var b: Button = _buttons[field]
		var on := bool(GameState.get(field))
		b.button_pressed = on
		var style := _style_for(on)
		b.add_theme_stylebox_override("normal", style)
		b.add_theme_stylebox_override("hover", style)
		b.add_theme_stylebox_override("pressed", style)
		b.add_theme_stylebox_override("hover_pressed", style)
		b.add_theme_color_override("font_color",
			Color8(0xE8, 0xE0, 0xD4) if on else Color8(0x9D, 0x8B, 0x73))


func _style_for(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_border_width_all(2)
	sb.set_content_margin_all(3)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	if on:
		sb.bg_color = Color8(0x1E, 0x3A, 0x1E)
		sb.border_color = Color8(0x4C, 0xAF, 0x50)
	else:
		sb.bg_color = Color8(0x24, 0x20, 0x1A)
		sb.border_color = Color8(0x55, 0x55, 0x55)
	return sb

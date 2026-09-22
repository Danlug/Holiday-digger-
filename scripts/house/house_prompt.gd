extends CanvasLayer
## HousePrompt — модальное окно на весь экран (сцена scenes/house_prompt.tscn).
##
## Нужно там, где игру надо ОСТАНОВИТЬ и заставить сделать одно действие:
## второе истощение в шахте (ГДД п.9) выдаёт батончик в портфель и не
## отпускает, пока герой не поест. Поэтому слой выше всех остальных экранов —
## обучение не должно оказаться под шторкой магазина или инвентаря.
##
## Окно ничего не решает само: нажатие уходит сигналом confirmed наружу.

signal confirmed

var _panel: PanelContainer
var _text: Label
var _button: Button


func _ready() -> void:
	layer = 30
	_build()
	visible = false


func _build() -> void:
	var root := _need(self, "Root", Control) as Control
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := _need(root, "Shade", ColorRect) as ColorRect
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.02, 0.02, 0.86)

	_panel = _need(root, "Panel", PanelContainer) as PanelContainer
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.anchor_right = 1.0
	_panel.offset_left = 14
	_panel.offset_right = -14
	_panel.offset_top = -72
	_panel.offset_bottom = 72
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(0x1E, 0x18, 0x11)
	sb.border_color = Color8(0xE0, 0xA9, 0x3B)
	sb.set_border_width_all(1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", sb)

	var box := _need(_panel, "Box", VBoxContainer) as VBoxContainer
	box.add_theme_constant_override("separation", 8)

	_text = _need(box, "Text", Label) as Label
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_text.add_theme_font_size_override("font_size", 10)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_button = _need(box, "Button", Button) as Button
	_button.add_theme_font_size_override("font_size", 10)
	_button.custom_minimum_size = Vector2(0, 26)
	_button.pressed.connect(func(): confirmed.emit())


func show_prompt(text: String, button_text: String) -> void:
	_text.text = text
	_button.text = button_text
	visible = true


func hide_prompt() -> void:
	visible = false


func _need(parent: Node, name: String, type) -> Node:
	var existing := parent.get_node_or_null(NodePath(name))
	if existing != null:
		return existing
	var node = type.new()
	node.name = name
	parent.add_child(node)
	return node

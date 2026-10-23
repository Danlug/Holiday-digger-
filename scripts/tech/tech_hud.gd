class_name TechHud
extends Control
## Два значка у левого края под кнопкой героя, поверх HUD: топливо (вертикальная полоска и число
## блоков; виден, пока в руках бур или бурмобиль) и температура (термометр с
## градусами; виден, когда становится тепло). HUD они не меняют: свой слой,
## своё состояние. Нажатие на топливо — залить блоки из рюкзака прямо в шахте;
## на термометр — открыть экран костюма.

const FUEL_H := 30.0
const WIDTH := 28.0
const Y_TOP := 104.0   # справа по высоте героя ездит метка глубины — слева свободно

var _fuel_btn: Button
var _fuel_fill: ColorRect
var _fuel_num: Label
var _heat_btn: Button
var _heat_icon: TextureRect
var _heat_num: Label
var _blink: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_fit)
	_fit()
	_build_fuel()
	_build_heat()
	GameState.game_event.connect(func(id: StringName, _d: Dictionary) -> void:
		if id == &"fuel_used" or id == &"refueled":
			refresh())
	GameState.tool_changed.connect(func(_t: String) -> void: refresh())
	GameState.inventory_changed.connect(refresh)
	refresh()


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if _fuel_btn != null:
		_layout()


func _layout() -> void:
	var x := 3.0
	_fuel_btn.position = Vector2(x, Y_TOP)
	_heat_btn.position = Vector2(x, Y_TOP + (_fuel_btn.size.y + 5.0 if _fuel_btn.visible else 0.0))


func _build_fuel() -> void:
	_fuel_btn = UiBtn.icon_button(null, Vector2(WIDTH, 66), UiBtn.Kind.NORMAL)
	var flame := TechUi.icon_rect(TechUi.tex("icon_flame"), 18)
	flame.position = Vector2(5, 3)
	_fuel_btn.add_child(flame)
	var track := Panel.new()
	track.position = Vector2(9, 23)
	track.size = Vector2(10, FUEL_H)
	track.add_theme_stylebox_override("panel", TechUi.box(TechUi.PANEL_DARK, TechUi.BORDER, 2, 0))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuel_btn.add_child(track)
	_fuel_fill = ColorRect.new()
	_fuel_fill.color = TechUi.FIRE
	_fuel_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_fuel_fill)
	_fuel_num = TechUi.label("0", 8, Color.WHITE)
	_fuel_num.position = Vector2(0, 54)
	_fuel_num.size = Vector2(WIDTH, 10)
	_fuel_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fuel_btn.add_child(_fuel_num)
	_fuel_btn.pressed.connect(_on_fuel_pressed)
	add_child(_fuel_btn)


func _build_heat() -> void:
	_heat_btn = UiBtn.icon_button(null, Vector2(WIDTH, 38), UiBtn.Kind.NORMAL)
	_heat_icon = TechUi.icon_rect(TechUi.tex("icon_thermo_0"), 20)
	_heat_icon.position = Vector2(4, 3)
	_heat_btn.add_child(_heat_icon)
	_heat_num = TechUi.label("", 8, TechUi.MUTED)
	_heat_num.position = Vector2(0, 25)
	_heat_num.size = Vector2(WIDTH, 10)
	_heat_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heat_btn.add_child(_heat_num)
	_heat_btn.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		TechScreen.open(TechScreen.TAB_SUIT))
	add_child(_heat_btn)


func _tool() -> String:
	return GameState.current_tool if FuelTank.uses_fuel(GameState.current_tool) else ""


func _depth() -> float:
	return float(maxi(GameState.player_depth, 0))


func refresh() -> void:
	if _fuel_btn == null:
		return
	var hidden := TechSystem.is_modal_open() or GameState.house_is_indoors
	var tool := _tool()
	_fuel_btn.visible = not hidden and not tool.is_empty()
	if _fuel_btn.visible:
		var frac := FuelTank.fraction(tool)
		var h := (FUEL_H - 2.0) * frac
		_fuel_fill.position = Vector2(1, 1 + (FUEL_H - 2.0) - h)
		_fuel_fill.size = Vector2(8, h)
		var low := FuelTank.is_low(tool)
		_fuel_fill.color = TechUi.RED if low else TechUi.FIRE
		_fuel_num.text = "%d" % int(ceil(FuelTank.fuel(tool)))
		_fuel_num.add_theme_color_override("font_color", TechUi.RED if low else Color.WHITE)
		Tip.bind(_fuel_btn, FuelTank.tool_name(tool),
			"Нажми — залить блоки из рюкзака", "%.1f / %d, блоков в рюкзаке: %d" % [
				FuelTank.fuel(tool), int(FuelTank.capacity(tool)), FuelTank.in_pack()])
	# Термометр: виден с глубины, где жара вообще заметна, и когда стало неуютно.
	var depth := _depth()
	var lvl := Heat.felt_level(depth)
	_heat_btn.visible = not hidden and (lvl > 0 or depth >= 700.0)
	if _heat_btn.visible:
		_heat_icon.texture = TechUi.tex("icon_thermo_%d" % lvl)
		_heat_num.text = "%d°" % int(Heat.temperature(depth))
		_heat_num.add_theme_color_override("font_color", [TechUi.MUTED, TechUi.FIRE, TechUi.RED][lvl])
		var z := Heat.zone(depth)
		Tip.bind(_heat_btn, String(z.get("name_ru", "")),
			"Жара тратит бодрость, лава жжёт. Нажми — экран костюма",
			"×%.1f расход бодрости" % Heat.stamina_multiplier(depth))
	_layout()


func _process(dt: float) -> void:
	_blink += dt
	var tool := _tool()
	if _fuel_btn.visible and not tool.is_empty() and FuelTank.is_low(tool):
		# Мигаем красным: пустеющий бак нельзя не заметить, но и мешать копке не должен.
		_fuel_btn.modulate = Color(1, 1, 1, 0.65 + 0.35 * sin(_blink * 6.0))
	else:
		_fuel_btn.modulate = Color.WHITE
	# Глубина меняется плавно, а значок обновляем редко: не каждый кадр.
	if int(_blink * 2.0) != int((_blink - dt) * 2.0):
		refresh()


func _on_fuel_pressed() -> void:
	if Tip.swallowed():
		return
	var tool := _tool()
	if tool.is_empty():
		return
	var n := FuelTank.refuel(tool, "pack")
	if n > 0:
		Sfx.play("ui_buy")
		Haptics.tap()
		var from := TechUi.anchor("backpack")
		var to := _fuel_btn.get_global_rect().get_center()
		for i in range(mini(n, 5)):
			TechUi.fly(self, TechUi.tex("fuel_block"), from, to, 0.06 * i, Callable(), 16.0)
		UiAnim.pulse(_fuel_btn, 0.25, 0.3)
		return
	UiAnim.shake(_fuel_btn)
	Sfx.play("ui_deny")
	Haptics.buzz(30)
	var why := "Бак полон" if FuelTank.room_blocks(tool) <= 0 else "В рюкзаке нет топливных блоков"
	Tip.set_text(_fuel_btn, FuelTank.tool_name(tool), why, "станция заправки — в огороде")
	Tip.show_now(_fuel_btn)

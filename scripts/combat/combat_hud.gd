extends CanvasLayer
## CombatHud — боевой интерфейс отдельным слоем (hud.gd не правится): крупная
## кнопка «удар» слева внизу (правый большой палец держит джойстик, левый —
## удар), полоска босса и тап по врагу как второй способ ударить.
## Ввод ловится в _input раньше HUD (этот узел в дереве позже), иначе в режиме
## «нажатия» HUD забирал бы каждое касание сцены под кнопкой.
## Текста нет: кнопка — иконка меча с кольцом перезарядки, полоска босса —
## иконка и три метки фаз. Названия и описания — только в подсказке Tip.

const BTN := 46.0
const MARGIN := 8.0
const STRIP_H := 40.0
const BOTTOM_PAD := 28.0          # над отладочной кнопкой слева внизу
const BAR_W := 58.0
const BAR_H := 9.0

const GOLD := UiTheme.GOLD
const GOLD_DIM := UiTheme.GOLD_DIM
const RED := UiTheme.RED
const BG := Color(0.11, 0.09, 0.07, 0.82)
const BORDER := UiTheme.EDGE

var director: CombatDirector = null

var _attack: Control
var _bar: Control
var _icon: Texture2D
var _boss_icon: Texture2D
var _pressed_until: float = 0.0
var _hp_shown: float = 1.0
var _hit_flash: float = 0.0
var _last_boss_hp: float = -1.0


func _ready() -> void:
	layer = UiLayers.COMBAT_HUD
	_icon = CombatData.ui_icon("attack")
	_boss_icon = CombatData.ui_icon("boss")

	_attack = Control.new()
	_attack.name = "AttackButton"
	_attack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attack.custom_minimum_size = Vector2(BTN, BTN)
	_attack.size = Vector2(BTN, BTN)
	_attack.draw.connect(_draw_attack)
	add_child(_attack)
	Tip.bind(_attack, "Удар", "Бьёт ближайшего врага. Тап по врагу — тоже удар")

	_bar = Control.new()
	_bar.name = "BossBar"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.size = Vector2(BAR_W + 26.0, 22.0)   # влезает между кнопкой удара и джойстиком
	_bar.draw.connect(_draw_bar)
	_bar.visible = false
	add_child(_bar)

	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_attack.position = Vector2(MARGIN, vp.y - STRIP_H - BOTTOM_PAD - BTN)
	# внизу между кнопкой удара и джойстиком: сверху теснятся кошелёк, жара и кнопки
	_bar.position = Vector2(_attack.position.x + BTN + 4.0, vp.y - STRIP_H - 40.0)


func _process(dt: float) -> void:
	if director == null:
		return
	var show_ui := director.combat_ui_visible() and not _modal_open()
	_attack.visible = show_ui
	_bar.visible = show_ui and director.boss != null
	if _attack.visible:
		_attack.queue_redraw()
	if _bar.visible:
		_bar.queue_redraw()
	_hit_flash = maxf(0.0, _hit_flash - dt)


## Открыты ли шторки/экраны, поверх которых боевые кнопки не нужны.
func _modal_open() -> bool:
	if director.equip_screen != null and director.equip_screen.has_method("is_open") and director.equip_screen.is_open():
		return true
	if ProgressScreen.is_open():
		return true
	var hud: Node = director.hud
	if hud != null:
		if "_inv_sheet" in hud and hud._inv_sheet != null and hud._inv_sheet.visible:
			return true
		if hud.has_method("is_more_menu_open") and hud.is_more_menu_open():
			return true
		if hud.has_method("is_settings_open") and hud.is_settings_open():
			return true
	return false


func _draw_attack() -> void:
	var c := Vector2(BTN, BTN) * 0.5
	var r := BTN * 0.5 - 1.0
	var now := Time.get_ticks_msec() / 1000.0
	var press := now < _pressed_until
	var cd_frac := 0.0
	if director.swing_total > 0.0:
		cd_frac = clampf(director.swing_cd / director.swing_total, 0.0, 1.0)
	var ready := cd_frac <= 0.0
	var target: Variant = director._nearest_target(false) if director.can_fight() else null
	var scale := 0.9 if press else 1.0
	_attack.draw_circle(c + Vector2(0, 2), r * scale, Color(0, 0, 0, 0.55))
	_attack.draw_circle(c, r * scale, Color(0.15, 0.11, 0.08, 0.92) if not press else Color(0.1, 0.08, 0.06, 0.96))
	var ring := GOLD if (target != null and ready) else GOLD_DIM
	_attack.draw_arc(c, r * scale - 1.0, 0.0, TAU, 40, ring, 2.0 if target != null else 1.5)
	if _icon != null:
		var s := 32.0 * scale
		_attack.draw_texture_rect(_icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false,
			Color(1, 1, 1, 1.0 if ready else 0.55))
	if not ready:
		# перезарядка: тёмный сектор, убывающий по часовой от верха
		var pts := PackedVector2Array([c])
		var steps := 24
		var a0 := -PI / 2.0
		var a1 := a0 + TAU * cd_frac
		for i in range(steps + 1):
			var a := a0 + (a1 - a0) * float(i) / float(steps)
			pts.append(c + Vector2(cos(a), sin(a)) * (r * scale - 2.0))
		if pts.size() >= 3:
			_attack.draw_colored_polygon(pts, Color(0, 0, 0, 0.45))


func _draw_bar() -> void:
	var b: BossLogic = director.boss
	if b == null:
		return
	var w := _bar.size.x
	_bar.draw_style_box(ProgressUiKit.box(BG, BORDER, ProgressUiKit.R_TILE), Rect2(0, 0, w, 22))   # плашка на общих ступенях радиуса
	if _boss_icon != null:
		_bar.draw_texture_rect(_boss_icon, Rect2(2, 3, 16, 16), false)
	var x0 := 22.0
	var frac := clampf(b.hp / b.max_hp, 0.0, 1.0)
	if _last_boss_hp >= 0.0 and b.hp < _last_boss_hp:
		_hit_flash = 0.12
	_last_boss_hp = b.hp
	_hp_shown = lerpf(_hp_shown, frac, 0.2)
	var vul := b.vulnerable()
	_bar.draw_rect(Rect2(x0, 6, BAR_W, BAR_H), Color(0.06, 0.04, 0.03, 0.95))
	_bar.draw_rect(Rect2(x0, 6, BAR_W * _hp_shown, BAR_H), Color(0.85, 0.85, 0.85, 0.5))
	var fill := UiTheme.GOLD if vul else RED
	if _hit_flash > 0.0:
		fill = Color(1, 1, 1)
	_bar.draw_rect(Rect2(x0, 6, BAR_W * frac, BAR_H), fill)
	# метки фаз на 66% и 33%
	for t in [0.66, 0.33]:
		var mx: float = x0 + BAR_W * float(t)
		_bar.draw_rect(Rect2(mx, 5, 1, BAR_H + 2), Color(0, 0, 0, 0.9))
	_bar.draw_rect(Rect2(x0, 6, BAR_W, BAR_H), GOLD if vul else BORDER, false, 1.0)
	# три фишки фаз под полоской
	for i in range(3):
		var on: bool = i < director.boss_phase_shown
		_bar.draw_rect(Rect2(x0 + float(i) * 9.0, 17, 7, 3), GOLD if on else Color(0.18, 0.15, 0.12))


# ---------------------------------------------------------------------------
# Ввод
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if director == null or not _attack.visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_SPACE or k.keycode == KEY_J):
			if director.try_swing():
				_pressed_until = Time.get_ticks_msec() / 1000.0 + 0.1
				get_viewport().set_input_as_handled()
		return
	var pos := Vector2.ZERO
	var is_press := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		pos = mb.position
		is_press = true
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if not st.pressed:
			return
		pos = st.position
		is_press = true
	if not is_press:
		return
	if Rect2(_attack.position, _attack.size).grow(4.0).has_point(pos):
		_pressed_until = Time.get_ticks_msec() / 1000.0 + 0.12
		director.try_swing()
		get_viewport().set_input_as_handled()
		return
	# тап по врагу: не отнимаем у джойстика его зону
	var hud: Node = director.hud
	if hud != null and "_stick_center" in hud:
		var sc: Vector2 = hud._stick_center
		if pos.distance_to(sc) <= float(hud.stick_r) * 1.6 and String(hud.mode) == "stick":
			return
	var vr: Node = director.view_root
	if vr != null:
		var world_px: Vector2 = pos - (vr as Node2D).position
		if director.tap_enemy_at(world_px):
			get_viewport().set_input_as_handled()

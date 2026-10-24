class_name StreakMeter
extends Control
## Шкала азарта под полосками HP/голода/бодрости (четвёртая «полоска», видна только
## во время серии): пламя с самородком и шкала до лихорадки. В лихорадке — бело-
## золотое пламя, шесть делений гаснут по одному на клетку, по краям экрана
## дышит золотая кайма. Слов нет: название и правило — в Tip.
##
## Место берётся от якоря HUD «stamina» (HudAnchors): если HUD передвинет
## полоски, шкала поедет за ними.

const W := 74.0
const H := 12.0
const GAP_BELOW := 9.0
const SHOW_FROM := 3          # серия короче — шкалу не показываем: это не событие
const COL_BG := Color(0.07, 0.055, 0.045, 0.82)
const COL_EDGE := Color8(0x52, 0x40, 0x2D)
const COL_FILL := Color8(0xF0, 0x7A, 0x1E)
const COL_FILL_HI := Color8(0xFF, 0xC8, 0x3A)
const COL_FEVER := Color8(0xFF, 0xE5, 0x7A)
const COL_FEVER_OFF := Color(1, 1, 1, 0.12)

var streak: StreakLogic = null

var _alpha: float = 0.0
var _shown_fill: float = 0.0
var _pop: float = 0.0
var _time: float = 0.0
var _icon: Texture2D
var _icon_fever: Texture2D
var _edge: Control
var _sb := StyleBoxFlat.new()
var _place_left: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, H)
	_icon = Mechanics.tex("streak")
	_icon_fever = Mechanics.tex("fever")
	_edge = Control.new()
	_edge.name = "FeverEdge"
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge.draw.connect(_draw_edge)
	get_parent().add_child.call_deferred(_edge)
	Tip.bind(self, "Азарт", "Копай без пауз — шкала растёт. Полная — лихорадка: следующие клетки дают двойную добычу. Пауза дольше пары секунд или подъём наверх — серия сгорает.")
	modulate.a = 0.0
	visible = false


## Клетка выкопана: шкала подпрыгивает.
func on_dug(fever_cell: bool) -> void:
	_pop = 1.0 if fever_cell else 0.6


func on_break() -> void:
	_pop = 0.0


func wanted() -> bool:
	return streak != null and (streak.in_fever() or streak.count >= SHOW_FROM)


func _process(delta: float) -> void:
	_time += delta
	var target := 1.0 if wanted() else 0.0
	if target <= 0.0 and _alpha <= 0.0:
		if visible:
			visible = false
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			if _edge != null and is_instance_valid(_edge):
				_edge.visible = false
		return   # шкала спит: ни перерисовки, ни поиска якоря
	_place_left -= delta
	if _place_left <= 0.0:
		_place_left = 0.5   # якорь HUD двигается только при повороте экрана — раз в полсекунды хватает
		_place()
	if Settings.reduce_motion:
		_alpha = target
	else:
		_alpha = move_toward(_alpha, target, delta * (6.0 if target > 0.0 else 2.0))
	if _alpha <= 0.01:
		_alpha = 0.0
	visible = _alpha > 0.0
	# Tip держит палец, только пока шкала видна: невидимая не должна ловить касание мира
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	modulate.a = _alpha
	var fill := streak.meter() if streak != null else 0.0
	_shown_fill = fill if Settings.reduce_motion else lerpf(_shown_fill, fill, minf(1.0, delta * 14.0))
	_pop = maxf(0.0, _pop - delta * 4.0)
	queue_redraw()
	if _edge != null and is_instance_valid(_edge):
		_edge.visible = visible and streak != null and streak.in_fever()
		if _edge.visible:
			_edge.queue_redraw()


func _place() -> void:
	var st := HudAnchors.get_anchor("stamina")
	if st == HudAnchors.FALLBACK:
		position = Vector2(52, 62)
	else:
		position = Vector2(round(st.x - 80.0 * 0.5 + 6.0), round(st.y + GAP_BELOW))


func _draw() -> void:
	var fever := streak != null and streak.in_fever()
	var r := Rect2(Vector2(10, 1), Vector2(W - 10, H - 2))
	_sb.bg_color = COL_BG
	_sb.border_color = COL_FEVER if fever else COL_EDGE
	_sb.set_border_width_all(1)
	_sb.set_corner_radius_all(ProgressUiKit.R_BAR)
	draw_style_box(_sb, r)
	var inner := Rect2(r.position + Vector2(3, 3), r.size - Vector2(5, 6))
	if fever:
		var cells := maxi(1, streak.fever_cells)
		var gap := 2.0
		var cw := (inner.size.x - gap * float(cells - 1)) / float(cells)
		for i in cells:
			var on := i < streak.fever_left
			var x := inner.position.x + float(i) * (cw + gap)
			var col := COL_FEVER if on else COL_FEVER_OFF
			if on and not Settings.reduce_motion:
				col = col.lerp(Color.WHITE, 0.25 + 0.25 * sin(_time * 9.0 + float(i)))
			draw_rect(Rect2(Vector2(x, inner.position.y), Vector2(cw, inner.size.y)), col)
	else:
		var w := floorf(inner.size.x * clampf(_shown_fill, 0.0, 1.0))
		if w > 0.0:
			draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), COL_FILL)
			draw_rect(Rect2(inner.position, Vector2(w, 1)), COL_FILL_HI)
		# риски каждые 10 клеток: видно, сколько осталось до лихорадки
		var marks := maxi(1, streak.fever_at / 10) if streak != null else 5
		for i in range(1, marks):
			var x := inner.position.x + floorf(inner.size.x * float(i) / float(marks))
			draw_rect(Rect2(Vector2(x, inner.position.y), Vector2(1, inner.size.y)), Color(0, 0, 0, 0.35))
	var icon := _icon_fever if fever else _icon
	if icon != null:
		var s := 16.0 + 4.0 * _pop
		draw_texture_rect(icon, Rect2(Vector2(6.0 - s * 0.5 + 2.0, H * 0.5 - s * 0.5), Vector2(s, s)), false)


## Золотая кайма по краям экрана в лихорадке: тонкая, дышит; «меньше движения» — ровная.
func _draw_edge() -> void:
	var sz := _edge.size
	var k := 0.5 if Settings.reduce_motion else 0.5 + 0.5 * sin(_time * 5.0)
	for i in 4:
		var a: float = float([0.34, 0.2, 0.11, 0.05][i]) * (0.65 + 0.35 * k) * _alpha
		var col := Color(1.0, 0.84, 0.32, a)
		var d := float(i) * 2.0
		_edge.draw_rect(Rect2(Vector2(d, d), Vector2(sz.x - d * 2.0, 2)), col)
		_edge.draw_rect(Rect2(Vector2(d, sz.y - d - 2.0), Vector2(sz.x - d * 2.0, 2)), col)
		_edge.draw_rect(Rect2(Vector2(d, d + 2.0), Vector2(2, sz.y - d * 2.0 - 4.0)), col)
		_edge.draw_rect(Rect2(Vector2(sz.x - d - 2.0, d + 2.0), Vector2(2, sz.y - d * 2.0 - 4.0)), col)

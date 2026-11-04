class_name StreakMeter
extends Control
## Шкала азарта — четвёртая «полоска» под HP/голодом/бодростью (видна, пока
## копится): значок пламени с самородком и шкала до жадности. Растёт, пока кирка
## в деле; герой стоит — шкала тускнеет и тает; почти полная — пламя дышит. Полная —
## вспышка по шкале, и в жадности бело-золотое пламя, шкала превращается в таймер
## и тает, по краям экрана дышит золотая кайма. Слов нет: правило — в Tip.
##
## Геометрия — как у HudBar (значок 16 слева, зазор 3, дорожка 8 по высоте) и
## берётся от настоящей полоски бодрости (HudAnchors.get_rect("stamina")):
## значок стоит ровно под молнией, дорожка — под дорожкой, шаг строки тот же.

const ROW_H := 16.0
const SHOW_FROM_S := 0.5      # с полсекунды работы: шкала видна с первого удара, но не мигает от толчка в камень
const NEAR_FULL := 0.8        # отсюда пламя дышит: жадность близко
const COL_DRAIN := Color8(0x9A, 0x5A, 0x2A)
const COL_FILL := Color8(0xF0, 0x7A, 0x1E)
const COL_FILL_HI := Color8(0xFF, 0xC8, 0x3A)
const COL_FEVER := Color8(0xFF, 0xE5, 0x7A)
const COL_FEVER_DEEP := Color8(0xF0, 0x9A, 0x1E)
const COL_GREED := Color8(0xFF, 0xC8, 0x3A)
const ROW_GAP := 3.0          # = separation столбика полосок в hud.gd

var streak: StreakLogic = null

var _alpha: float = 0.0
var _shown_fill: float = 0.0
var _pop: float = 0.0
var _time: float = 0.0
var _icon: Texture2D
var _icon_fever: Texture2D
var _edge: Control
var _track := StyleBoxFlat.new()
var _fill := StyleBoxFlat.new()
var _place_left: float = 0.0
var _burst: float = 0.0       # вспышка шкалы в миг начала жадности (1 → 0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(HudBar.ICON_PX + HudBar.GAP + 62.0, ROW_H)
	_icon = Mechanics.tex("streak")
	_icon_fever = Mechanics.tex("fever")
	_track.bg_color = Color(0.04, 0.03, 0.025, 0.82)
	_track.set_border_width_all(1)
	_track.set_corner_radius_all(3)
	_fill.set_corner_radius_all(2)
	_edge = Control.new()
	_edge.name = "FeverEdge"
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge.draw.connect(_draw_edge)
	get_parent().add_child.call_deferred(_edge)
	Tip.bind(self, "Азарт и жадность", "Копай — шкала растёт, пока кирка в деле. Стоишь — тает. Полная — жадность: несколько секунд всё копается с первого удара, ход и падение ×7, руда вдвое. Подъём наверх или дом — шкала сгорает. Качается в ветке «Жадность».")
	modulate.a = 0.0
	visible = false


## Клетка выкопана: шкала подпрыгивает.
func on_dug(fever_cell: bool) -> void:
	_pop = 1.0 if fever_cell else 0.6


func on_break() -> void:
	_pop = 0.0


## Шкала заполнилась — жадность: шкала вспыхивает и подпрыгивает.
func on_greed_start() -> void:
	_burst = 1.0
	_pop = 1.6
	_alpha = 1.0


func wanted() -> bool:
	return streak != null and (streak.in_greed() or streak.work >= SHOW_FROM_S)


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
	# таймер жадности тает ровно, без догоняния; копилка — мягко
	_shown_fill = fill if Settings.reduce_motion or (streak != null and streak.in_greed()) \
		else lerpf(_shown_fill, fill, minf(1.0, delta * 14.0))
	_pop = maxf(0.0, _pop - delta * 4.0)
	_burst = maxf(0.0, _burst - delta * 1.6)
	queue_redraw()
	if _edge != null and is_instance_valid(_edge):
		_edge.visible = visible and streak != null and streak.in_greed()
		if _edge.visible:
			_edge.queue_redraw()


## Строка сразу под полоской бодрости: тот же левый край и ширина, шаг строки —
## как между HP, голодом и бодростью.
func _place() -> void:
	var st := HudAnchors.get_rect("stamina")
	if st.size.x <= 0.0:
		position = Vector2(49, 64)
		return
	position = Vector2(roundf(st.position.x), roundf(st.end.y + ROW_GAP + (st.size.y - ROW_H) * 0.5))
	size = Vector2(st.size.x, ROW_H)


func _draw() -> void:
	var greed := streak != null and streak.in_greed()
	var drain := streak != null and streak.draining()
	var near := not greed and not drain and _shown_fill >= NEAR_FULL and not Settings.reduce_motion
	var h := size.y
	var x0 := HudBar.ICON_PX + HudBar.GAP
	var bar := Rect2(x0, (h - HudBar.BAR_H) * 0.5, maxf(size.x - x0, 8.0), HudBar.BAR_H)
	_track.border_color = COL_FEVER if greed else Color(0, 0, 0, 0.7)
	draw_style_box(_track, bar)
	var inner := Rect2(bar.position + Vector2.ONE, bar.size - Vector2(2, 2))
	var f := clampf(_shown_fill, 0.0, 1.0)
	var fw := floorf(inner.size.x * f)
	if fw >= 1.0:
		var col := COL_FILL
		if greed:
			var low := streak.greed_left < 1.0
			col = COL_GREED
			if not Settings.reduce_motion:
				col = col.lerp(COL_FEVER, 0.5 + 0.5 * sin(_time * 9.0)) if not low \
					else (COL_GREED if sin(_time * 18.0) > 0.0 else COL_FEVER_DEEP)
		elif drain:
			col = COL_DRAIN   # стоишь — шкала тускнеет и тает
		elif near:
			col = COL_FILL.lerp(COL_FILL_HI, 0.5 + 0.5 * sin(_time * 10.0))
		_fill.bg_color = col
		draw_style_box(_fill, Rect2(inner.position, Vector2(fw, inner.size.y)))
		draw_rect(Rect2(inner.position.x + 1, inner.position.y, maxf(fw - 2, 0.0), 2),
			Color(1, 1, 1, 0.28) if greed else (Color(1, 1, 1, 0.12) if drain \
				else Color(COL_FILL_HI.r, COL_FILL_HI.g, COL_FILL_HI.b, 0.85)))
		draw_rect(Rect2(inner.position.x + 1, inner.end.y - 1, maxf(fw - 2, 0.0), 1), Color(0, 0, 0, 0.22))
	if not greed:
		# риски каждые 10 секунд работы: видно, сколько осталось до жадности
		var marks := maxi(1, roundi(streak.fever_s / 10.0)) if streak != null else 6
		for i in range(1, marks):
			var tx := inner.position.x + floorf(inner.size.x * float(i) / float(marks))
			draw_rect(Rect2(tx, inner.position.y, 1, inner.size.y), Color(0, 0, 0, 0.28))
	if _burst > 0.0:
		# миг начала жадности: шкала вспыхивает белым, от неё расходится золотой ореол
		var k := _burst * _burst
		draw_rect(bar, Color(1, 1, 1, 0.85 * k))
		var grow := (1.0 - _burst) * 6.0
		draw_rect(Rect2(bar.position - Vector2(grow, grow), bar.size + Vector2(grow, grow) * 2.0),
			Color(1.0, 0.86, 0.35, 0.9 * k), false, 2.0)
	var icon := _icon_fever if greed else _icon
	if icon != null:
		var breathe := 0.12 * (0.5 + 0.5 * sin(_time * 10.0)) if near else 0.0
		var s := HudBar.ICON_PX * (1.0 + 0.25 * _pop + breathe)
		var tint := Color(1, 1, 1, 0.55 + 0.45 * absf(sin(_time * 6.0))) if drain and not Settings.reduce_motion \
			else Color.WHITE
		draw_texture_rect(icon, Rect2(Vector2((HudBar.ICON_PX - s) * 0.5, (h - s) * 0.5), Vector2(s, s)), false, tint)


## Золотая кайма по краям экрана в жадности: тонкая, дышит; «меньше движения» — ровная.
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

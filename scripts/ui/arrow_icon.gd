class_name ArrowIcon
extends Control
## Треугольник-стрелка произвольного направления и цвета, рисуемый в _draw().
##
## Шрифт темы проекта не содержит символов ◀ ▶ ← → ↑ ↓ ✕ ↺ — известная
## ловушка проекта (см. scripts/ui/hud.gd): кнопка с таким текстом
## показывает пустоту или квадрат с шестнадцатеричным кодом внутри вместо
## стрелки. Вместо текста стрелка рисуется треугольником — работает при
## любом шрифте темы. Раньше так рисовались только стрелки режима
## "стрелки" в hud.gd (см. _draw_arrow, теперь заменённый на этот класс);
## здесь тот же приём вынесен в общий хелпер, чтобы кнопки хода в доме
## (house_view.gd) и любые будущие стрелочные кнопки не изобретали его
## заново и не наступали на ту же ловушку текстом.
##
## Добавляется ребёнком кнопки (или любого Control) во всю её площадь,
## mouse_filter = IGNORE — сама стрелка клики не перехватывает, это дело
## родителя.

## Направление остриём. Не обязан быть единичным — нормализуется в _draw().
var dir: Vector2 = Vector2.RIGHT

## Цвет заливки — по умолчанию тот же янтарный акцент, что у стрелок в hud.gd.
var color: Color = Color8(0xE0, 0xA9, 0x3B)

# Пропорции треугольника — те же числа, что были у hud.gd:_draw_arrow.
# Важно, что он заметно ВЫТЯНУТ вдоль dir: первый заход дал почти
# равносторонний треугольник, и куда он смотрит, было не понять ни у
# вертикали/горизонтали, ни тем более у диагоналей.
const REACH := 1.30
const BACK := 0.45
const SIDE := 0.58
const RADIUS_FRAC := 0.30


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(queue_redraw)


## Сменить направление и перерисоваться — вызывающему не нужно самому
## помнить про queue_redraw().
func set_dir(v: Vector2) -> void:
	dir = v
	queue_redraw()


func set_color(c: Color) -> void:
	color = c
	queue_redraw()


func _draw() -> void:
	if dir.length() < 0.001:
		return
	var v := dir.normalized()
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * RADIUS_FRAC
	var tip: Vector2 = c + v * r * REACH
	var back: Vector2 = c - v * r * BACK
	var side: Vector2 = Vector2(-v.y, v.x) * r * SIDE
	draw_colored_polygon(
		PackedVector2Array([tip, back + side, back - side]), color)

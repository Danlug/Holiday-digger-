class_name MetaStarTrack
extends Control
## Шкала звёзд дня (владелец, 27.10: «за каждую миссию даётся звёздочка,
## 10 звёздочек — сундук»): по клетке на миссию набора, после клетки сундука —
## золотая засечка. Звезда золотая — миссия забрана, полупрозрачная — выполнена
## и ждёт «Забрать», тёмная — ещё в работе. Клетки после засечки чуть меньше:
## сундук они уже не открывают, это звёзды «сверху».

const STAR_TEX := "star"
const GAP_AT_MARK := 4.0

var total: int = 13:
	set(v):
		total = maxi(1, v)
		queue_redraw()
var needed: int = 10:
	set(v):
		needed = v
		queue_redraw()
var stars: int = 0:
	set(v):
		stars = v
		queue_redraw()
## Выполнено, но награда ещё не забрана.
var done: int = 0:
	set(v):
		done = v
		queue_redraw()

var _tex: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex = MetaUiKit.tex(STAR_TEX)
	resized.connect(queue_redraw)


## Центр клетки i (0-based) — туда прилетает звезда забранной миссии.
func cell_center(i: int) -> Vector2:
	var c := _cell()
	var x := float(i) * c + c * 0.5
	if needed > 0 and needed < total and i >= needed:
		x += GAP_AT_MARK
	return Vector2(x, size.y * 0.5)


func _cell() -> float:
	var extra := GAP_AT_MARK if needed > 0 and needed < total else 0.0
	return (size.x - extra) / float(total)


func _draw() -> void:
	var c := _cell()
	var h := size.y
	# Канавка под звёздами.
	draw_rect(Rect2(0, h * 0.5 - 2.0, size.x, 4.0), Color(0.10, 0.08, 0.06))
	var lit := minf(float(stars), float(total))
	if lit > 0.0:
		var end := cell_center(int(lit) - 1).x + c * 0.5
		draw_rect(Rect2(0, h * 0.5 - 2.0, end, 4.0), MetaUiKit.GOLD.darkened(0.25))
	for i in range(total):
		var ctr := cell_center(i)
		var big := needed <= 0 or i < needed
		var px := minf(c, h) * (1.0 if big else 0.82)
		var r := Rect2(ctr - Vector2(px, px) * 0.5, Vector2(px, px))
		var col: Color
		if i < stars:
			col = Color.WHITE
		elif i < stars + done:
			col = Color(1.0, 1.0, 1.0, 0.42)
		else:
			col = Color(0.22, 0.19, 0.16)
		if _tex != null:
			draw_texture_rect(_tex, r, false, col)
	if needed > 0 and needed < total:
		var mx := float(needed) * c + GAP_AT_MARK * 0.5
		draw_rect(Rect2(mx - 1.0, 0.0, 2.0, h), MetaUiKit.GOLD)

class_name NeedBadge
extends Control
## Угловой значок «нужно для…» на плитке (продажа, склад): тёмный кружок с
## золотым ободком и значком проекта внутри. warn — плитка отмечена к продаже:
## ободок янтарный и значок мерно «дышит» (мягкое предупреждение, без запрета).
## Сам ввод не ловит — подсказку Tip держит плитка.

const SIZE := 18.0
const COL_BG := Color(0.07, 0.055, 0.045, 0.94)
const COL_RIM := Color8(0xE0, 0xA9, 0x3B)
const COL_WARN := Color8(0xFF, 0x9A, 0x2E)

var texture: Texture2D = null:
	set(v):
		texture = v
		queue_redraw()
var warn := false:
	set(v):
		warn = v
		set_process(v)
		if not v:
			_t = 0.0
		queue_redraw()

var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	set_process(false)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := Vector2(SIZE, SIZE) * 0.5
	var k := 1.0
	if warn and not UiAnim.reduced():
		k = 1.0 + 0.12 * (0.5 + 0.5 * sin(_t * 6.0))
	var r := (SIZE * 0.5 - 0.5) * k
	draw_circle(c, r, COL_WARN if warn else COL_RIM)
	draw_circle(c, r - 1.5, COL_BG)
	if texture != null:
		var isz := Vector2(13, 13) * k
		draw_texture_rect(texture, Rect2((c - isz * 0.5).round(), isz.round()), false)

class_name FrontLawn
extends Node2D
## Травяная кромка перед домом (владелец, 26.10: «хочу чтобы перед домом
## показывали травку, а не землю»). На огороде верхний ряд поверхности — тайл
## травы, а у дома этот ряд целиком закрыт фасадом, и герой стоял прямо на
## разрезе земли. Полоса невысокой травы (tools/gen_front_lawn.py — та же трава,
## что у огорода) лежит поверх цоколя дома и лачуги деда, под героем и актёрами.
##
## Только вид: клетки мира, копка, фундамент, дверь и лестница не меняются —
## полоса целиком в ряду y=0, который не копается вовсе (см. WorldGen.get_tile).

const TEX_PATH := "res://art/env/front_lawn.png"
const TILE := 32.0
const ART_SCALE := 3.0

## Где лежит кромка, в клетках: весь двор дома, до огорода (там своя трава).
var x_from: float = 0.0
var x_to: float = float(WorldGen.GARDEN_X_MIN)

var _tex: Texture2D = null


func _ready() -> void:
	name = "FrontLawn"
	if ResourceLoader.exists(TEX_PATH):
		_tex = load(TEX_PATH)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# Текстура втрое подробнее клетки, как тайлы: рисуем в её пикселях, узел уменьшен.
	scale = Vector2(1.0 / ART_SCALE, 1.0 / ART_SCALE)
	position = Vector2(x_from * TILE, TILE)
	queue_redraw()


## Прямоугольник полосы в координатах мира (логические px) — для тестов и отладки.
func world_rect() -> Rect2:
	var h: float = _tex.get_height() / ART_SCALE if _tex != null else 0.0
	return Rect2(x_from * TILE, TILE - h, (x_to - x_from) * TILE, h)


func _draw() -> void:
	if _tex == null:
		return
	var h := float(_tex.get_height())
	draw_texture_rect(_tex, Rect2(0.0, -h, (x_to - x_from) * TILE * ART_SCALE, h), true)

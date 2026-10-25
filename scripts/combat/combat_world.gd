class_name CombatWorld
extends RefCounted
## CombatWorld — дешёвый взгляд монстров на мир: «твёрдая ли клетка» с кэшем.
## WorldGen.get_tile для нетронутой породы считает хеши всех руд, а каждому
## монстру нужны десятки проб в секунду — поэтому ответы кэшируются и сбрасываются
## при копке (invalidate) и по таймеру (обвалы и землетрясения меняют мир сами).
## Сам мир не меняется и не читается иначе как через get_tile/is_dug.

const WIDTH := 32
const TTL_SEC := 2.0

var world = null
var _cache: Dictionary = {}
var _age: float = 0.0


func _init(p_world = null) -> void:
	world = p_world


func tick(dt: float) -> void:
	_age += dt
	if _age >= TTL_SEC:
		_age = 0.0
		_cache.clear()


func invalidate() -> void:
	_cache.clear()


## Стены мира по бокам — камень; выше поверхности (y < 1) — не твёрдое: туда
## монстры не лезут, их туда не пускает поведение, а не физика.
func solid(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= WIDTH:
		return true
	if cy < 1:
		return false
	if world == null:
		return false
	var key := cy * 64 + cx
	if _cache.has(key):
		return _cache[key]
	var s: bool = int(world.get_tile(cx, cy)) != TileTypes.Type.EMPTY
	_cache[key] = s
	return s


func is_dug(cx: int, cy: int) -> bool:
	return world != null and world.is_dug(cx, cy)

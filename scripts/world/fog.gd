class_name FogOfWar
extends RefCounted
## Туман войны (раздел 12 ГДД): чёрный / серый (рельеф) / полный (ресурс).
## Хранится компактно — битовые маски по чанкам (32 × 32 клетки на чанк,
## 2 бита на клетку упакованы в два раздельных PackedByteArray), а не
## Dictionary на каждую разведанную клетку. Чанк аллоцируется лениво, только
## когда в него что-то попадает — на глубину 4000+ по всей ширине это даёт
## максимум несколько сотен чанков даже при полном исследовании, а не
## структуру на 128 000+ записей.

enum State { BLACK = 0, GRAY = 1, FULL = 2 }

const WIDTH := 32           # совпадает с шириной мира (world_gen.WIDTH), см. отчёт
const CHUNK_H := 32
const CHUNK_CELLS := WIDTH * CHUNK_H
const CHUNK_BYTES := CHUNK_CELLS / 8

const DEFAULT_TERRAIN_RADIUS := 2   # ГДД раздел 12: старт рельефа — 2 клетки
const DEFAULT_RESOURCE_RADIUS := 1  # ГДД раздел 12: старт ресурсов — 1 клетка

# chunk_index:int -> {"terrain": PackedByteArray, "resource": PackedByteArray}
var _chunks: Dictionary = {}


## Удобный вызов на каждый шаг героя: раскрывает рельеф большим радиусом,
## ресурсы — меньшим, за один проход.
func reveal_around(center_x: int, center_y: int,
		terrain_radius: int = DEFAULT_TERRAIN_RADIUS,
		resource_radius: int = DEFAULT_RESOURCE_RADIUS) -> void:
	reveal_terrain(center_x, center_y, terrain_radius)
	reveal_resources(center_x, center_y, resource_radius)


func reveal_terrain(center_x: int, center_y: int, radius: int) -> void:
	_reveal_circle(center_x, center_y, radius, true)


func reveal_resources(center_x: int, center_y: int, radius: int) -> void:
	_reveal_circle(center_x, center_y, radius, false)


## Состояние клетки. Клетки выше поверхности (y < 1) вне тумана — считаем
## их всегда полностью видимыми (дом/огород и так на виду у игрока).
func get_state(x: int, y: int) -> int:
	if y < 1:
		return State.FULL
	var chunk: Dictionary = _get_chunk(_chunk_index(y), false)
	if chunk.is_empty():
		return State.BLACK
	var idx := _local_index(x, y)
	if _get_bit(chunk.resource, idx):
		return State.FULL
	if _get_bit(chunk.terrain, idx):
		return State.GRAY
	return State.BLACK


## Полный сброс тумана (после обвала/землетрясения, раздел 8 ГДД: "После
## любого сброса весь рельеф снова закрывается туманом войны"). Отчистка
## словаря чанков — O(число разведанных чанков), не O(глубина × ширина).
func reset_all() -> void:
	_chunks.clear()


func to_save_data() -> Dictionary:
	var out := {}
	for chunk_idx in _chunks.keys():
		var c: Dictionary = _chunks[chunk_idx]
		out[str(chunk_idx)] = {
			"terrain": Marshalls.raw_to_base64(c.terrain),
			"resource": Marshalls.raw_to_base64(c.resource),
		}
	return out


func load_save_data(data: Dictionary) -> void:
	_chunks.clear()
	for key in data.keys():
		var entry: Dictionary = data[key]
		_chunks[int(key)] = {
			"terrain": Marshalls.base64_to_raw(entry.get("terrain", "")),
			"resource": Marshalls.base64_to_raw(entry.get("resource", "")),
		}


# ============================== ВНУТРЕННЕЕ ==============================

func _reveal_circle(center_x: int, center_y: int, radius: int, is_terrain: bool) -> void:
	if radius <= 0:
		return
	var r2 := radius * radius
	var y_from := maxi(center_y - radius, 1)
	var y_to := center_y + radius
	for y in range(y_from, y_to + 1):
		var dy := y - center_y
		var remaining := r2 - dy * dy
		if remaining < 0:
			continue
		var dx_max := int(floor(sqrt(float(remaining))))
		var x_from := maxi(center_x - dx_max, 0)
		var x_to := mini(center_x + dx_max, WIDTH - 1)
		if x_from > x_to:
			continue
		var chunk: Dictionary = _get_chunk(_chunk_index(y), true)
		var arr: PackedByteArray = chunk.terrain if is_terrain else chunk.resource
		for x in range(x_from, x_to + 1):
			_set_bit(arr, _local_index(x, y))


func _chunk_index(y: int) -> int:
	return (y - 1) / CHUNK_H


func _local_index(x: int, y: int) -> int:
	var local_y := (y - 1) % CHUNK_H
	return local_y * WIDTH + x


func _get_chunk(chunk_idx: int, create: bool) -> Dictionary:
	if _chunks.has(chunk_idx):
		return _chunks[chunk_idx]
	if not create:
		return {}
	var terrain := PackedByteArray()
	terrain.resize(CHUNK_BYTES)
	var resource := PackedByteArray()
	resource.resize(CHUNK_BYTES)
	var chunk := {"terrain": terrain, "resource": resource}
	_chunks[chunk_idx] = chunk
	return chunk


static func _get_bit(arr: PackedByteArray, idx: int) -> bool:
	var byte_i := idx / 8
	if byte_i >= arr.size():
		return false
	return (arr[byte_i] & (1 << (idx % 8))) != 0


static func _set_bit(arr: PackedByteArray, idx: int) -> void:
	var byte_i := idx / 8
	if byte_i >= arr.size():
		return
	arr[byte_i] = arr[byte_i] | (1 << (idx % 8))

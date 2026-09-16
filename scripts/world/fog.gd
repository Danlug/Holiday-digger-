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


## Доля клетки, которую круг обзора должен накрыть, чтобы клетка открылась
## (решение владельца). Половина — потому что это единственный порог, который
## читается на глаз: край ауры прошёл через середину клетки — клетка открылась.
const COVERAGE_TO_REVEAL := 0.5

## Радиус круга обзора в клетках по ступени прокачки. Полклетки сверху — это
## та самая аура, которую игрок видит на экране с самого начала: круг всегда
## рисовался радиусом ступень+0.5.
##
## Держать эти полклетки надо здесь, одним числом на всю игру, и вот почему.
## Правило «открывать при половине клетки» строже прежнего («центр клетки
## внутри круга») примерно на полклетки. Отними их — и при ступени 1 круг
## накрывает половину только у своей же клетки: обзор ресурсов схлопывается
## в одну клетку, и туман перестаёт работать вовсе. Радиусы ступеней в ГДД
## заданы под ту картинку, что на экране, — её и берём.
static func vision_radius(stage_radius: int) -> float:
	return float(stage_radius) + 0.5


## Удобный вызов на каждый шаг героя: раскрывает рельеф большим радиусом,
## ресурсы — меньшим, за один проход. Центр — в КЛЕТОЧНЫХ координатах с
## дробной частью (player.x, player.y), а не в номере клетки: аура рисуется от
## настоящего положения героя, и если раскрывать от номера клетки, картинка
## расходится с правилом на полклетки.
func reveal_around(center_x: float, center_y: float,
		terrain_radius: int = DEFAULT_TERRAIN_RADIUS,
		resource_radius: int = DEFAULT_RESOURCE_RADIUS) -> void:
	reveal_terrain(center_x, center_y, terrain_radius)
	reveal_resources(center_x, center_y, resource_radius)


## То же, но от СЕРЕДИНЫ клетки, а не от точки. Отдельным методом, потому что
## «клетка 15» и точка (15.0) — разные места: точка лежит на её левом краю, и
## круг, заданный номером клетки, уезжает на полклетки влево-вверх.
func reveal_around_cell(cell_x: int, cell_y: int,
		terrain_radius: int = DEFAULT_TERRAIN_RADIUS,
		resource_radius: int = DEFAULT_RESOURCE_RADIUS) -> void:
	reveal_around(float(cell_x) + 0.5, float(cell_y) + 0.5, terrain_radius, resource_radius)


func reveal_terrain(center_x: float, center_y: float, radius: int) -> void:
	_reveal_circle(center_x, center_y, radius, true)


func reveal_resources(center_x: float, center_y: float, radius: int) -> void:
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


## Полный сброс тумана. Остался за землетрясением (раздел 8 ГДД: "После
## любого сброса весь рельеф снова закрывается туманом войны") — оно и есть
## "перетряхнуло копальню целиком". Обвал чанка гасит только свою зону, см.
## reset_rect. Отчистка словаря чанков — O(число разведанных чанков), не
## O(глубина × ширина).
func reset_all() -> void:
	_chunks.clear()


## Сброс тумана по прямоугольнику клеток — ровно зона обвала и ничего больше
## (решение владельца: "не надо закрывать всю карту, только там где случился
## обвал"). Разведанная глубина стоит игроку часов, и гасить её целиком из-за
## обвала в пять клеток на другом конце шахты — обман.
##
## Чистим побитово именно клетки прямоугольника, а не выбрасываем затронутые
## чанки: чанк — это 32 строки на всю ширину, и обвал 5×5 стёр бы вместе с
## собой полосу в 1024 клетки вокруг.
func reset_rect(x0: int, y0: int, w: int, h: int) -> void:
	var x_from := maxi(x0, 0)
	var x_to := mini(x0 + w - 1, WIDTH - 1)
	# Выше первой земляной клетки тумана нет вовсе (см. get_state), поэтому
	# и гасить там нечего.
	var y_from := maxi(y0, 1)
	var y_to := y0 + h - 1
	if x_from > x_to or y_from > y_to:
		return
	for y in range(y_from, y_to + 1):
		var chunk: Dictionary = _get_chunk(_chunk_index(y), false)
		# Неразведанный чанк не аллоцирован — он и так весь чёрный, а создать
		# его ради сброса значило бы плодить пустые маски на всю глубину.
		if chunk.is_empty():
			continue
		for x in range(x_from, x_to + 1):
			var idx := _local_index(x, y)
			_clear_bit(chunk.terrain, idx)
			_clear_bit(chunk.resource, idx)


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

## Клетка открывается, когда круг накрывает её не меньше чем на половину
## площади. Раньше правило было «центр клетки внутри круга» — на глаз это
## почти то же самое, но круг брался от НОМЕРА клетки и радиусом на полклетки
## меньше нарисованного, и в игре аура заметно переезжала через клетку раньше,
## чем та открывалась.
##
## Дорогую точную площадь считаем только для кольца на границе: клетка, у
## которой дальний угол внутри круга, накрыта целиком, а та, у которой ближний
## угол снаружи, не накрыта вовсе. Таких клеток O(R), а не O(R²).
func _reveal_circle(center_x: float, center_y: float, radius: int, is_terrain: bool) -> void:
	if radius <= 0:
		return
	var r := vision_radius(radius)
	var y_from := maxi(int(floor(center_y - r)), 1)
	var y_to := int(ceil(center_y + r))
	for y in range(y_from, y_to + 1):
		var x_from := maxi(int(floor(center_x - r)), 0)
		var x_to := mini(int(ceil(center_x + r)), WIDTH - 1)
		if x_from > x_to:
			continue
		var chunk: Dictionary = _get_chunk(_chunk_index(y), true)
		var arr: PackedByteArray = chunk.terrain if is_terrain else chunk.resource
		for x in range(x_from, x_to + 1):
			if _coverage(center_x, center_y, r, float(x), float(y)) >= COVERAGE_TO_REVEAL:
				_set_bit(arr, _local_index(x, y))


## Какая доля клетки [cx, cx+1] × [cy, cy+1] накрыта кругом (0..1).
func _coverage(ox: float, oy: float, r: float, cx: float, cy: float) -> float:
	var x0 := cx - ox
	var y0 := cy - oy
	var x1 := x0 + 1.0
	var y1 := y0 + 1.0
	# Ближний и дальний углы: две проверки вместо интеграла для 90% клеток.
	var near_x: float = 0.0 if (x0 <= 0.0 and x1 >= 0.0) else minf(absf(x0), absf(x1))
	var near_y: float = 0.0 if (y0 <= 0.0 and y1 >= 0.0) else minf(absf(y0), absf(y1))
	if near_x * near_x + near_y * near_y >= r * r:
		return 0.0
	var far_x: float = maxf(absf(x0), absf(x1))
	var far_y: float = maxf(absf(y0), absf(y1))
	if far_x * far_x + far_y * far_y <= r * r:
		return 1.0
	return _quad(r, x1, y1) - _quad(r, x0, y1) - _quad(r, x1, y0) + _quad(r, x0, y0)


## Знаковая площадь пересечения круга (центр в нуле, радиус r) с
## прямоугольником [0, x] × [0, y]. Круг симметричен по обеим осям, поэтому
## отрицательные стороны сводятся к положительным со сменой знака.
func _quad(r: float, x: float, y: float) -> float:
	var sx: float = signf(x)
	var sy: float = signf(y)
	if sx == 0.0 or sy == 0.0:
		return 0.0
	var ax: float = minf(absf(x), r)
	var ay: float = minf(absf(y), r)
	var area: float
	if ax * ax + ay * ay <= r * r:
		area = ax * ay
	else:
		# Дуга режет прямоугольник: до a по горизонтали высота полная,
		# дальше — под дугой (интеграл sqrt(r² - u²)).
		var a: float = minf(sqrt(maxf(r * r - ay * ay, 0.0)), ax)
		area = a * ay + (_arc_integral(r, ax) - _arc_integral(r, a))
	return sx * sy * area


## ∫ sqrt(r² − u²) du = ½ (u·sqrt(r² − u²) + r²·asin(u/r))
func _arc_integral(r: float, u: float) -> float:
	var t: float = clampf(u / r, -1.0, 1.0)
	return 0.5 * (u * sqrt(maxf(r * r - u * u, 0.0)) + r * r * asin(t))


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


static func _clear_bit(arr: PackedByteArray, idx: int) -> void:
	var byte_i := idx / 8
	if byte_i >= arr.size():
		return
	arr[byte_i] = arr[byte_i] & ~(1 << (idx % 8))

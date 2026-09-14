class_name CollapseEvents
extends RefCounted
## События сброса (раздел 8 ГДД): обвал чанка и землетрясение всей копальни.
## Модуль не хранит состояние — это набор статических операций над
## world_gen.gd (WorldGen) и fog.gd (FogOfWar), которые ему передают извне.
## Частота срабатывания ("средняя"/"очень редко") в ГДД числом не задана —
## планировщик триггеров (таймер, глубина игрока и т.п.) не наша зона,
## это должен вызывать вызывающий код (core/сцены) с нужным интервалом.

## Формы обвала чанка: {h: глубина, w: ширина}. 5×32 и 10×32 — полосы на
## всю ширину мира (совпадает с шириной мира — WorldGen.WIDTH).
static var CHUNK_SHAPES: Array[Dictionary] = [
	{"h": 5, "w": 5},
	{"h": 10, "w": 10},
	{"h": 5, "w": WorldGen.WIDTH},
	{"h": 10, "w": WorldGen.WIDTH},
]


## Обвал чанка случайного размера/позиции. Зафиксированные клетки (фундамент,
## торфяной пласт 450-455, лестница, сценарный алмаз) не трогает — это
## обеспечивает сам world_gen.apply_chunk_event. Возвращает затронутый
## прямоугольник (для UI/уведомления игрока), либо {} если world пуст.
static func trigger_chunk_collapse(world: WorldGen, fog: FogOfWar, rng: RandomNumberGenerator = null) -> Dictionary:
	var r := _rng(rng)
	var shape: Dictionary = CHUNK_SHAPES[r.randi_range(0, CHUNK_SHAPES.size() - 1)]
	var w: int = shape.w
	var h: int = shape.h

	var x0 := 0
	if w < WorldGen.WIDTH:
		x0 = r.randi_range(0, WorldGen.WIDTH - w)

	var y_min := 1
	var y_max := maxi(world.max_depth - h, y_min)
	var y0 := r.randi_range(y_min, y_max)

	var salt := r.randi()
	world.apply_chunk_event(x0, y0, w, h, salt)
	# "После любого сброса весь рельеф снова закрывается туманом войны" —
	# сбрасывается ВЕСЬ туман, а не только зона обвала (раздел 8 ГДД).
	fog.reset_all()
	return {"x0": x0, "y0": y0, "w": w, "h": h}


## Землетрясение: перегенерирует все незафиксированные клетки всей копальни
## одним O(1) вызовом (см. комментарий к WorldGen.apply_global_event) и
## полностью сбрасывает туман войны.
static func trigger_earthquake(world: WorldGen, fog: FogOfWar, rng: RandomNumberGenerator = null) -> void:
	var r := _rng(rng)
	world.apply_global_event(r.randi())
	fog.reset_all()


static func _rng(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	if rng != null:
		return rng
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r

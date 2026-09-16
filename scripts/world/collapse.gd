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


## Клетка, до которой герой считается "наверху, у входа в шахту" — тот самый
## стартовый пятачок 3×3 из формулировки владельца. Ниже неё полный ресет
## застаёт его в земле, и потому откладывается (см. is_safe_for_full_reset).
const SAFE_SURFACE_CELL_Y := 1


## Обвал чанка случайного размера/позиции. Зафиксированные клетки (фундамент,
## торфяной пласт 450-455, лестница, сценарный алмаз) не трогает — это
## обеспечивает сам world_gen.apply_chunk_event. Возвращает затронутый
## прямоугольник (для UI/уведомления игрока), либо {}, если обвалу негде
## случиться.
##
## player_cell_y — клетка, в которой стоит герой; -1 значит "ограничения нет"
## (тесты, вызов без героя). Решение владельца: "обвал не может произойти выше
## или прямо на уровне героя" — весь прямоугольник кладём строго НИЖЕ его
## клетки. Иначе порода смыкается прямо на нём, и ход теряется не по его вине.
static func trigger_chunk_collapse(world: WorldGen, fog: FogOfWar,
		rng: RandomNumberGenerator = null, player_cell_y: int = -1) -> Dictionary:
	var r := _rng(rng)
	var shape: Dictionary = CHUNK_SHAPES[r.randi_range(0, CHUNK_SHAPES.size() - 1)]
	var w: int = shape.w
	var h: int = shape.h

	var x0 := 0
	if w < WorldGen.WIDTH:
		x0 = r.randi_range(0, WorldGen.WIDTH - w)

	var y_min := 1
	if player_cell_y >= 0:
		y_min = maxi(y_min, player_cell_y + 1)
	# Нижний край прямоугольника не должен вылезать за дно копальни, поэтому
	# y0 ограничен сверху. Если герой докопался почти до дна, места под обвал
	# не остаётся — события просто не происходит, и вызывающий код о нём
	# молчит (тост о том, чего не было, пугает зря).
	var y_max := world.max_depth - h
	if y_max < y_min:
		return {}
	var y0 := r.randi_range(y_min, y_max)

	var salt := r.randi()
	world.apply_chunk_event(x0, y0, w, h, salt)
	# Туман гасится ТОЛЬКО в зоне обвала (решение владельца: "не надо
	# закрывать всю карту, только там где случился обвал"). Раздел 8 ГДД
	# требует закрывать туманом изменившийся рельеф — изменился он ровно
	# здесь, в этом прямоугольнике.
	fog.reset_rect(x0, y0, w, h)
	return {"x0": x0, "y0": y0, "w": w, "h": h}


## Землетрясение: перегенерирует все незафиксированные клетки всей копальни
## одним O(1) вызовом (см. комментарий к WorldGen.apply_global_event) и
## полностью сбрасывает туман войны — это и есть "перетряхнуло копальню
## целиком", гасить весь мир здесь правильно.
##
## Безусловный вариант: зовите его, только когда герой заведомо в безопасности
## (дома, наверху) или когда его в мире нет вовсе — иначе try_trigger_earthquake.
static func trigger_earthquake(world: WorldGen, fog: FogOfWar, rng: RandomNumberGenerator = null) -> void:
	var r := _rng(rng)
	world.apply_global_event(r.randi())
	fog.reset_all()


## Можно ли прямо сейчас перетряхнуть копальню целиком. Решение владельца:
## "не может произойти полный ресет, пока он в земле... пока он не вылезет
## наверх или в 3 на 3 клетки". Безопасно — дома или на поверхности у входа
## в шахту; под землёй порода сомкнётся прямо на герое.
static func is_safe_for_full_reset(cell_y: int, is_indoors: bool) -> bool:
	return is_indoors or cell_y <= SAFE_SURFACE_CELL_Y


## Землетрясение с оглядкой на героя. Возвращает false, если герой под землёй
## и трясти нельзя — тогда вызывающий код обязан запомнить событие как
## ОТЛОЖЕННОЕ (GameState.pending_earthquake) и повторить попытку, когда герой
## выберется. Событие не отменяется, а ждёт: иначе достаточно сидеть в шахте,
## чтобы полный ресет не случался никогда.
static func try_trigger_earthquake(world: WorldGen, fog: FogOfWar,
		cell_y: int, is_indoors: bool, rng: RandomNumberGenerator = null) -> bool:
	if not is_safe_for_full_reset(cell_y, is_indoors):
		return false
	trigger_earthquake(world, fog, rng)
	return true


static func _rng(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	if rng != null:
		return rng
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r

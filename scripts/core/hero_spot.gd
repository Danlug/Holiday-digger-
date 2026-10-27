class_name HeroSpot
extends RefCounted
## Где стоял герой под землёй, когда игру закрыли (владелец, 27.10: «Когда закрываешь игру под землёй,
## при открытии игры он должен быть на той же позиции»).
##
## Хранится КЛЕТКА, а не пиксель: {x, y, facing} в GameState.ext["hero_spot"] (формат SaveSystem не менялся).
## Пишется только под землёй — на поверхности, в доме, мёртвым и в посадке/выходе из бурмобиля место
## стирается, и запуск идёт как раньше: герой у дома (main.gd → teleport_home).
##
## Значение держится свежим двумя путями: каждый кадр (SaveHooks), пока героя ведёт сам игрок, и прямо
## перед записью сейва (sync_now из SaveSystem._serialize). Пока героя держит сцена, окно или ролик
## (frozen), место не переписывается: в катсцене player.x/y — это камера на актёре, а не герой.

const EXT_KEY := "hero_spot"
## Насколько далеко искать свободную клетку, если сохранённая стала породой (обвал, другая сборка мира).
const SEARCH_RADIUS := 12
const HERO_HH := 1.0 / 3.0   # полувысота героя — как player.gd (HH); ровно на полу, без падения на 0.17 клетки

## Что сделал restore().
enum { NONE, STANDING, HOVER }

static var _player: WeakRef = null


## SaveHooks представляет героя: sync_now() из SaveSystem берёт место прямо в момент записи.
static func bind(player: Node) -> void:
	_player = weakref(player) if player != null else null


static func _bound() -> Node:
	if _player == null:
		return null
	var p = _player.get_ref()
	return p if p != null and is_instance_valid(p) else null


## Место героя сейчас: {} — стереть (не под землёй / не в счёт), null — оставить прежнее (героя держит сцена).
static func capture(player) -> Variant:
	if player == null:
		return null
	if not GameState.is_alive or GameState.house_is_indoors or String(player.get("rig_transition")) != "":
		return {}
	if bool(player.get("frozen")):
		return null
	var cy: int = player.cell_y()
	if cy < 1:
		return {}
	return {"x": player.cell_x(), "y": cy, "facing": int(player.get("facing"))}


## Записать место в ext (если изменилось). Дёшево: словарь создаётся только при смене клетки.
static func track(player) -> void:
	var spot = capture(player)
	if spot == null:
		return
	if (spot as Dictionary).is_empty():
		if GameState.ext.has(EXT_KEY):
			GameState.ext.erase(EXT_KEY)
		return
	var old = GameState.ext.get(EXT_KEY)
	if typeof(old) == TYPE_DICTIONARY and int(old.get("x", -1)) == int(spot.x) \
			and int(old.get("y", -1)) == int(spot.y) and int(old.get("facing", 0)) == int(spot.facing):
		return
	GameState.ext[EXT_KEY] = spot


## Зовёт SaveSystem._serialize: в сейв уходит место на момент записи, а не на прошлый кадр
## (смерть и телепорт меняют его посреди кадра). Без героя (тесты без main.tscn) — ничего.
static func sync_now() -> void:
	var p := _bound()
	if p != null:
		track(p)
	elif not GameState.is_alive:
		GameState.ext.erase(EXT_KEY)


static func saved_cell() -> Vector2i:
	var spot = GameState.ext.get(EXT_KEY)
	if typeof(spot) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)
	var x = spot.get("x")
	var y = spot.get("y")
	if not (x is int or x is float) or not (y is int or y is float):
		return Vector2i(-1, -1)
	return Vector2i(int(x), int(y))


## Можно ли возвращать героя на место из сейва. Нельзя, если умер (воскреснет дома), если ждёт
## землетрясение (копальню перетряхнёт — main.gd будит его дома) и пока не пройден онбординг: до сцены
## смерти обучение ведёт героя само (ручная копка, автокопка, фундамент — ГДД §9), и чужая точка
## старта его сломала бы.
static func can_restore(loaded_dead: bool) -> bool:
	if loaded_dead or GameState.pending_earthquake or GameState.house_is_indoors:
		return false
	if saved_cell().y < 1:
		return false
	if GameState.story_seen.is_empty() and GameState.story_flags.is_empty():
		StoryState.load_from_disk()   # режиссёр читает сюжет отложенно, а решать надо сейчас
	if GameState.story_queue.has("death"):
		return false
	return StoryState.is_seen("death") or StoryState.has_flag("death_seen") or StoryState.has_flag("bars_introduced")


static func _is_free(world, x: int, y: int) -> bool:
	return y >= 1 and x >= 0 and x < WorldGen.WIDTH and world.get_tile(x, y) == TileTypes.Type.EMPTY


static func _has_floor(world, x: int, y: int) -> bool:
	return world.get_tile(x, y + 1) != TileTypes.Type.EMPTY


## Ближайшая к c пустая клетка (сама c, если пуста). Порода, лава и любые тайлы не годятся — герой
## никогда не встаёт внутрь клетки. Из равных по расстоянию — с полом под ногами. (-1,-1) — рядом нет.
static func find_safe_cell(world, c: Vector2i) -> Vector2i:
	if _is_free(world, c.x, c.y):
		return c
	var best := Vector2i(-1, -1)
	var best_cost := INF
	for dy in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
		for dx in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			var x := c.x + dx
			var y := c.y + dy
			if not _is_free(world, x, y):
				continue
			var cost := float(dx * dx + dy * dy) + (0.0 if _has_floor(world, x, y) else 0.5)
			if cost < best_cost:
				best_cost = cost
				best = Vector2i(x, y)
	return best


## Поставить героя на место из сейва. NONE — места нет или нельзя (main.gd ведёт героя домой, как раньше);
## STANDING — стоит на полу клетки; HOVER — клетка в воздухе: герой висит, пока игрок не тронет
## управление (SaveHooks), — сама загрузка его не роняет и урона от падения не даёт.
## Инструмент и бурмобиль не трогаются: current_tool уже накатил сейв — сидел в машине, в ней и остался
## (выйти из бурмобиля под землёй нельзя, высадка — только на поверхности, ГДД §5).
static func restore(player, world, loaded_dead: bool) -> int:
	if player == null or world == null or not can_restore(loaded_dead):
		return NONE
	var cell := find_safe_cell(world, saved_cell())
	if cell.y < 1:
		return NONE
	var standing := _has_floor(world, cell.x, cell.y)
	player.x = float(cell.x) + 0.5
	player.y = float(cell.y) + (1.0 - HERO_HH - 0.001 if standing else 0.5)
	player.vx = 0.0
	player.vy = 0.0
	player.on_ground = standing
	player.digging = null
	player.thrust = ""
	var facing := int(GameState.ext.get(EXT_KEY, {}).get("facing", 1))
	player.facing = -1 if facing < 0 else 1
	player.set("_air_top_y", player.y)   # высота падения для окна смерти — от этой точки, а не от дома
	GameState.player_depth = cell.y
	return STANDING if standing else HOVER

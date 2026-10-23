class_name BossArena
extends RefCounted
## BossArena — арена рейдбосса на дне мира (глубина 10 000, ГДД п.3).
##
## Арена — не выкопанная порода, а «оверлей» поверх WorldGen.get_tile: от
## строки floor_y и ниже — несокрушимое дно мира (железобетон), над ним
## камера 13×8 клеток в железобетонной оболочке с воротами в потолке шириной
## 3 клетки. Мир не хранит арену в диффах, поэтому землетрясения и обвалы её не
## портят, а герой не может ни прокопаться мимо, ни уйти копкой вниз.
## Ворота закрываются (sealed) на время боя — отступления нет, как у любого
## рейдбосса: из боя выводит победа или смерть (респавн дома, ГДД п.7).

const EMPTY := 0
const REINFORCED := TileTypes.Type.REINFORCED

## Ворота закрыты, пока идёт бой. Ставит CombatDirector.
static var sealed: bool = false


static func cfg() -> Dictionary:
	return CombatData.section("boss").get("arena", {})


static func floor_y() -> int:
	return int(cfg().get("floor_y", 10000))


static func height() -> int:
	return int(cfg().get("height", 8))


static func x0() -> int:
	return int(cfg().get("x0", 10))


static func x1() -> int:
	return int(cfg().get("x1", 22))


## Строка потолка арены (железобетон, кроме ворот).
static func top_y() -> int:
	return floor_y() - height() - 1


static func gate_x0() -> int:
	return int((cfg().get("gate", [15, 17]) as Array)[0])


static func gate_x1() -> int:
	return int((cfg().get("gate", [15, 17]) as Array)[1])


## Центр арены по x в клетках (координата границы, как у player.x).
static func center_x() -> float:
	return float(x0() + x1() + 1) / 2.0


## Внутренность арены в клетках: левый верхний угол и размер.
static func interior() -> Rect2:
	return Rect2(float(x0()), float(floor_y() - height()), float(x1() - x0() + 1), float(height()))


static func contains_cell(cx: int, cy: int) -> bool:
	return cx >= x0() and cx <= x1() and cy >= floor_y() - height() and cy < floor_y()


## Герой внутри арены (а не над воротами).
static func contains_point(px: float, py: float) -> bool:
	return interior().has_point(Vector2(px, py))


## Тип клетки оверлея или -1, если клетка обычная (решает мир). Подключается
## как WorldGen.overlay с порогом overlay_y_min = top_y().
static func tile_at(x: int, y: int) -> int:
	var fy := floor_y()
	if y >= fy:
		return REINFORCED
	var ty := fy - height() - 1
	if y < ty or x < x0() - 1 or x > x1() + 1:
		return -1
	if y == ty:
		if x >= gate_x0() and x <= gate_x1() and not sealed:
			return EMPTY
		return REINFORCED
	if x == x0() - 1 or x == x1() + 1:
		return REINFORCED
	return EMPTY


static func install(world) -> void:
	world.overlay_y_min = top_y()
	world.overlay = Callable(BossArena, "tile_at")

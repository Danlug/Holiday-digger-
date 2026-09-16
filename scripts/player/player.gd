extends Node2D
## Player — физика, копка и полёт героя. Один в один портировано из
## web/index.html (эталон ощущений, см. задание) — константы и формулы
## совпадают буквально, поведение проверялось плейтестами до этого агента.
##
## Координаты x, y — В КЛЕТКАХ (не пикселях), как в web-демо: (x, y) — центр
## хитбокса персонажа. position (Node2D, в пикселях) выставляется из них
## каждый кадр в _process, чтобы дочерний спрайт и мир рисовались в одном
## пространстве координат (см. scripts/main.gd — ViewRoot сдвигается на
## -camera*TILE, а не двигается сама камера).

signal fell(damage: float, impact_speed: float)
signal dig_started(x: int, y: int, tile_type: int)
signal dig_cancelled
signal dig_finished(x: int, y: int, tile_type: int, mineral_id: String, was_loot: bool, coins: int)
signal dig_blocked(tile_type: int)  # инструмент не берёт эту породу — стан
## Копать нельзя не из-за инструмента, а потому что так решил сюжет
## (обучение: сперва золото, потом фундамент). Текст даёт сюжет, не игрок.
signal dig_refused_by_story(reason: String)
signal tool_auto_switched(tool_id: String)
signal gear_unlocked(gear_id: String)
signal jumped
signal died_in_place

const TILE := 32

# --- физика (см. web/index.html, раздел "физика") ---
const G := 16.0                # клеток/с²
const JUMP_V := 8.1            # даёт ровно 2.2 клетки подъёма с учётом зависания
const APEX_V := 2.0            # |vy| ниже этого порога — зона зависания
const APEX_G := 0.45           # во сколько раз слабее тяготение в этой зоне
const WALK := 4.2              # клеток/с по земле
const AIR_CTRL := 0.82         # насколько слушается руля в воздухе
const V_TERM := 32.0           # предел скорости падения, клеток/с
const HW := 0.38
const HH := 0.46
const CORNER := 5.0 / 32.0     # скругление углов коллизии

# --- потолок неба ---
# Высоту неба знает рендер мира (world_view.gd:SKY_HEIGHT) — второго числа
# здесь не заводим: физика и картинка обязаны кончаться в одной клетке,
# иначе герой либо упирается в пустое место, либо улетает за нарисованную
# кромку в ничто.
const SKY_HEIGHT: int = preload("res://scripts/world/world_view.gd").SKY_HEIGHT
# Герой встаёт на клетку НИЖЕ самой кромки: камера выше -SKY_HEIGHT не идёт,
# а кадр героя выше его ног на полторы клетки — без этого запаса верхний край
# экрана срезал бы ранец с головой.
const SKY_MARGIN := 1.0
# Последние клетки подъёма тяга гаснет пропорционально остатку: потолок должен
# ощущаться упором, в который герой всплывает, а не невидимой стеной с рывком.
const SKY_BRAKE := 3.0

# --- снаряжение открывается по глубине (ГДД раздел 5/6) ---
const PROP_DEPTH := 10
const JET_DEPTH := 100
# Буровая машина — следующая ступень после ручного бура. Глубина взята той
# же логикой, что и остальные ступени: на порядок глубже предыдущей.
const RIG_DEPTH := 1000

# --- ранец с пропеллерами ---
const PROP_SPEED := 2.5
const PROP_RAMP := 3.0
const JUMP_TO_FLY_MS := 300.0  # пауза между толчком прыжка и включением тяги

# --- джетпак ---
const JET_SPEED := 20.0
const JET_RAMP := 5.0

# Пока герой падает, тяга работает тормозом с ускорением намного резче, чем
# потом разгоняет вверх — иначе подъёмная сила ранца не перебивает тяготение.
const THRUST_BRAKE := 26.0
# Отпустил тягу на подъёме — инерция гасится резче, чем тянет тяготение.
const COAST_DECEL := G * 6.0

# --- магнетизм направления (см. resolveDir в web-демо) ---
const ANG_ON := 45.0
const ANG_OFF := 33.0
# Граница между «вверх по диагонали» и «строго вверх». 67.5° — середина между
# идеальной диагональю (45°) и идеальной вертикалью (90°): вектор достаётся
# тому из шести направлений, к которому он ближе. Было 72° — диагональ
# забирала лишние четыре с половиной градуса у вертикали без причины.
const ANG_PURE := 67.5

# Косинус и синус 45° — ручка джойстика на диагонали должна стоять ровно на
# диагонали, а не «примерно там».
const DIAG := 0.70710678
const STICK_DEAD := 0.26

# --- состояние ---
var world: WorldGen = null

var x: float = 20.5
var y: float = 0.5
var vx: float = 0.0
var vy: float = 0.0
var on_ground: bool = false
var facing: int = 1
var anim: float = 0.0

var hold_dx: int = 0
var hold_up: bool = false
var hold_down: bool = false
var _dir_zone: String = ""     # "" | "side" | "up" | "down"

var digging = null             # null | {x:int, y:int, t:float, total:float, type:int}
var stun_until_msec: float = 0.0

var thrust: String = ""        # "" | "prop" | "jet"
var coasting: bool = false
var _fly_arm_at_msec: float = 0.0

var rusty_pickaxe_cracked: bool = false
var _seen_foundation: bool = false
var _announced_backpack: bool = false
var _announced_jetpack: bool = false
var _announced_rig: bool = false

var frozen: bool = false       # true во время сцены смерти/катсцен — герой не управляется


func _ready() -> void:
	_announced_backpack = has_backpack()
	_announced_jetpack = has_jetpack()
	_announced_rig = has_drill_rig()


# ---------------------------------------------------------------------------
# Публичное намерение движения (пишут joystick/hold-контроллер из hud.gd)
# ---------------------------------------------------------------------------

## Магнетизм по углу вектора, не по осям — см. ГДД п.6 и комментарий в
## web/index.html.
##
## Направлений ровно ШЕСТЬ (решение владельца): ← → ↑ ↖ ↗ ↓. Вниз по
## диагонали нет вовсе — копка всегда строго под собой. Вектор достаётся
## тому направлению, к которому он ближе, с одной поправкой: вверх и вниз
## включаются только за 45° от горизонтали. Эта поправка старше и важнее
## близости — без неё шаг вбок от неточного пальца превращался в яму под
## ногами. Гистерезис 45°/33° держит режим на самой границе.
##
## Возвращает единичный вектор направления — ручку джойстика ставим ровно на
## него, а не куда указывает палец: так видно, что игра поняла.
## null — вектор внутри мёртвой зоны.
func resolve_dir(vx_in: float, vy_in: float, dead: float) -> Variant:
	var length := Vector2(vx_in, vy_in).length()
	if length < dead:
		_dir_zone = ""
		hold_dx = 0; hold_up = false; hold_down = false
		return null

	var ang := rad_to_deg(atan2(-vy_in, absf(vx_in)))  # -90..90
	var zone: String
	# Границы включающие: ровно 45° — это идеальная диагональ ↗, и отдавать её
	# шагу вбок нельзя. «До 45° — шаг, от 45° — вверх».
	if _dir_zone == "up":
		zone = "up" if ang >= ANG_OFF else ("down" if ang <= -ANG_ON else "side")
	elif _dir_zone == "down":
		zone = "down" if ang <= -ANG_OFF else ("up" if ang >= ANG_ON else "side")
	else:
		zone = "up" if ang >= ANG_ON else ("down" if ang <= -ANG_ON else "side")
	_dir_zone = zone

	var side: int = 0 if vx_in == 0.0 else (1 if vx_in > 0.0 else -1)
	if zone == "side":
		hold_dx = side; hold_up = false; hold_down = false
		return Vector2(side, 0)
	if zone == "up":
		# ↗ и ↖ — бежать и прыгать одновременно; круче 67.5° — чистое ↑
		hold_dx = side if ang < ANG_PURE else 0
		hold_up = true; hold_down = false
		if hold_dx == 0:
			return Vector2(0, -1)
		return Vector2(hold_dx * DIAG, -DIAG)
	# вниз — строго под собой, это всегда осознанное действие
	hold_dx = 0; hold_up = false; hold_down = true
	return Vector2(0, 1)


## Прямое намерение — для клавиатуры. Магнетизм углов ей не нужен: он
## существует ради неточного пальца на стекле, а клавиша уже дискретна, и
## «чуть-чуть вниз» на ней набрать нельзя. Зону направления выставляем тоже:
## иначе следующий кадр с джойстика унаследует гистерезис от клавиатуры.
func set_intent(dx: int, up: bool, down: bool) -> void:
	if down:
		_dir_zone = "down"
	elif up:
		_dir_zone = "up"
	elif dx != 0:
		_dir_zone = "side"
	else:
		_dir_zone = ""
	hold_dx = dx
	hold_up = up
	hold_down = down


func release_control() -> void:
	_dir_zone = ""
	hold_dx = 0; hold_up = false; hold_down = false


# ---------------------------------------------------------------------------
# Снаряжение — вычисляется от максимальной достигнутой глубины (ГДД раздел 6),
# отдельного персистентного поля не нужно: max_depth_reached уже сохраняется.
# ---------------------------------------------------------------------------

func has_backpack() -> bool:
	# Ранец вручает сцена «Ранец» (data/story.json, эффект backpack_owned) —
	# её флаг главнее глубины: иначе пропеллер появляется у героя за миг до
	# того, как ролик про него показан. Глубина остаётся запасным признаком
	# для сейвов, где сюжет уже пройден, отключён или сброшен.
	if StoryState.has_flag("backpack_owned"):
		return true
	return GameState.max_depth_reached >= PROP_DEPTH


## Джетпак СОБИРАЕТСЯ на верстаке (решение владельца), а не выдаётся сам на
## глубине 100. Глубина осталась условием появления рецепта в мастерской, но
## сам предмет — только через крафт: снаряжение, которое падает в руки за то,
## что ты просто копал вниз, не ощущается покупкой.
func has_jetpack() -> bool:
	return GameState.has_gear("jetpack")


func has_hand_drill() -> bool:
	return GameState.max_depth_reached >= JET_DEPTH


## Буровая машина. Полной механики транспорта из ГДД раздела 5 (посадка в
## кабину и высадка, топливо, перегрев, своя физика движения) здесь нет —
## машина заведена как СТУПЕНЬ ИНСТРУМЕНТА: свой вид и своя скорость копки.
func has_drill_rig() -> bool:
	return GameState.max_depth_reached >= RIG_DEPTH


func _check_gear_unlocks() -> void:
	if has_backpack() and not _announced_backpack:
		_announced_backpack = true
		gear_unlocked.emit("backpack")
	if has_jetpack() and not _announced_jetpack:
		_announced_jetpack = true
		gear_unlocked.emit("jetpack")
		if GameState.current_tool != "hand_drill":
			GameState.set_current_tool("hand_drill")
			tool_auto_switched.emit("hand_drill")
	if has_drill_rig() and not _announced_rig:
		_announced_rig = true
		gear_unlocked.emit("drill_rig")
		if GameState.current_tool != "drill_rig":
			GameState.set_current_tool("drill_rig")
			tool_auto_switched.emit("drill_rig")


# ---------------------------------------------------------------------------
# Основной тик физики (вызывается из main.gd раз в кадр с dt из _process)
# ---------------------------------------------------------------------------

func physics_tick(dt: float) -> void:
	if frozen or not GameState.is_alive:
		vx = 0.0
		return

	var now := Time.get_ticks_msec()
	if now < stun_until_msec:
		vx = 0.0
	else:
		_apply_intent(dt)

	_move_x(dt)
	_move_y(dt)

	# Счётчик кадров идёт ВСЕГДА. Пока он тикал только при копке и ходьбе,
	# покой, падение и полёт стояли на первом кадре и выглядели статикой.
	anim += 2.0
	if digging != null:
		digging.t += dt
		if digging.t >= digging.total:
			_finish_dig()

	GameState.is_digging = digging != null
	_award_depth_milestones(GameState.max_depth_reached, cell_y())
	GameState.update_max_depth(cell_y())
	_check_gear_unlocks()


## Первое достижение каждой 10-й клетки глубины — бонус 50 * (глубина/10)
## опыта (см. GDD раздел 11). Цикл на случай, если за один кадр перескочило
## сразу через несколько отметок (падение на большой скорости).
func _award_depth_milestones(old_depth: int, new_depth: int) -> void:
	if new_depth <= old_depth:
		return
	var d: int = (old_depth / 10 + 1) * 10
	while d <= new_depth:
		GameState.add_xp(50 * (d / 10))
		d += 10


func cell_x() -> int:
	return int(floor(x))


func cell_y() -> int:
	return int(floor(y))


func _solid_at(wx: float, wy: float) -> bool:
	if world == null:
		return false
	return world.get_tile(int(floor(wx)), int(floor(wy))) != TileTypes.Type.EMPTY


# ---------------------------------------------------------------------------
# Столкновения (портировано из moveX/moveY web/index.html буквально)
# ---------------------------------------------------------------------------

func _move_x(dt: float) -> void:
	if vx == 0.0:
		return
	x += vx * dt
	var top := y - HH + 0.02
	var bot := y + HH - 0.02
	var probe := x + HW if vx > 0.0 else x - HW
	var hit_t := _solid_at(probe, top)
	var hit_b := _solid_at(probe, bot)
	var slipped := false

	if hit_t and not hit_b:
		var over: float = (floor(top) + 1.0) - top
		if over <= CORNER:
			y += over + 0.002
			slipped = true
	elif hit_b and not hit_t:
		var over2: float = bot - floor(bot)
		if over2 <= CORNER:
			y -= over2 + 0.002
			slipped = true

	if not slipped and (hit_t or hit_b):
		x = floor(probe) - HW - 0.001 if vx > 0.0 else floor(probe) + 1.0 + HW + 0.001
		vx = 0.0

	if world != null:
		x = clampf(x, HW, float(WorldGen.WIDTH) - HW)


func _gravity_now() -> float:
	return G * APEX_G if absf(vy) < APEX_V else G


## Самое верхнее положение центра героя: верх неба плюс запас под кадр.
func _sky_ceiling() -> float:
	return -float(SKY_HEIGHT) + SKY_MARGIN


func _prop_ramp() -> float:
	return PROP_RAMP / pow(0.85, GameState.get_total_weight() / 20.0)


func _move_y(dt: float) -> void:
	if thrust != "":
		var jet := thrust == "jet"
		var max_up: float = (JET_SPEED if jet else PROP_SPEED) * GameState.get_speed_multiplier()
		var ramp: float = JET_RAMP if jet else _prop_ramp()
		var accel: float = THRUST_BRAKE if vy > 0.0 else max_up / ramp
		vy = maxf(vy - accel * dt, -max_up)
	else:
		var g: float = COAST_DECEL if (coasting and vy < 0.0) else _gravity_now()
		vy = minf(vy + g * dt, V_TERM)

	# Небо не бесконечное: на подлёте к его верху гасим подъём пропорционально
	# остатку высоты. Падение это не трогает (только vy < 0), так что урон от
	# падения считается по прежним правилам.
	var ceiling: float = _sky_ceiling()
	if vy < 0.0 and y - ceiling < SKY_BRAKE:
		vy *= clampf((y - ceiling) / SKY_BRAKE, 0.0, 1.0)

	y += vy * dt
	# Страховка на случай большого dt: за нарисованную кромку не выпускаем.
	if y < ceiling:
		y = ceiling
		vy = maxf(vy, 0.0)
	var left := x - HW + 0.02
	var right := x + HW - 0.02
	on_ground = false

	if vy > 0.0:
		var b := y + HH
		if _solid_at(left, b) or _solid_at(right, b):
			y = floor(b) - HH - 0.001
			_land()
			vy = 0.0
			on_ground = true
	elif vy < 0.0:
		var tp := y - HH
		var hit_l := _solid_at(left, tp)
		var hit_r := _solid_at(right, tp)
		var slipped := false
		if hit_l and not hit_r:
			var over: float = (floor(left) + 1.0) - left
			if over <= CORNER:
				x += over + 0.002
				slipped = true
		elif hit_r and not hit_l:
			var over2: float = right - floor(right)
			if over2 <= CORNER:
				x -= over2 + 0.002
				slipped = true
		if not slipped and (hit_l or hit_r):
			y = floor(tp) + 1.0 + HH + 0.001
			vy = 0.0

	if not on_ground:
		var b2 := y + HH + 0.02
		on_ground = vy == 0.0 and (_solid_at(left, b2) or _solid_at(right, b2))


## Урон от падения — от СКОРОСТИ удара, а не от пройденной высоты (ГДД п.6).
## Формула — в Balance.get_fall_damage_from_speed (единый источник с тестами
## tests/test_fall_damage_speed.gd); G передаётся аргументом, потому что это
## константа ощущений движения игрока, а не баланса.
func _land() -> void:
	var v := vy
	var dmg := roundf(Balance.get_fall_damage_from_speed(v, G))
	if dmg < 1.0:
		return
	GameState.take_damage(dmg, "fall")
	fell.emit(dmg, v)


# ---------------------------------------------------------------------------
# Прыжок и полёт — раздельны (ГДД п.6): тяга не раньше JUMP_TO_FLY_MS после
# толчка И только когда прыжок перешёл в падение (vy >= 0).
# ---------------------------------------------------------------------------

func _jump() -> void:
	if not on_ground or digging != null:
		return
	if Time.get_ticks_msec() < stun_until_msec:
		return
	if _solid_at(x, y - HH - 0.1):
		return
	vy = -JUMP_V
	on_ground = false
	_fly_arm_at_msec = Time.get_ticks_msec() + JUMP_TO_FLY_MS
	jumped.emit()


func _update_flight() -> void:
	var was := thrust
	var want := ""
	if hold_up and not on_ground and digging == null:
		if has_jetpack():
			want = "jet"
		elif has_backpack():
			want = "prop"

	if want != "" and was == "" and (Time.get_ticks_msec() < _fly_arm_at_msec or vy < 0.0):
		want = ""
	thrust = want

	if was != "" and thrust == "" and vy < 0.0:
		coasting = true
	if thrust != "" or vy >= 0.0 or on_ground:
		coasting = false


# ---------------------------------------------------------------------------
# Намерение игрока: ходьба, прыжок, копка вплотную (applyIntent в web-демо)
# ---------------------------------------------------------------------------

func _apply_intent(dt: float) -> void:
	if digging != null:
		vx = 0.0
		return

	# Обессиленный герой медленнее во всём (ГДД раздел 7). Множитель берётся
	# из GameState, а не считается здесь, чтобы штраф нельзя было забыть
	# применить в одном из трёх мест — ходьбе, копке или полёте.
	var speed: float = WALK * (1.0 if on_ground else AIR_CTRL) * GameState.get_speed_multiplier()
	vx = float(hold_dx) * speed
	if hold_dx != 0:
		facing = hold_dx

	if hold_up and on_ground:
		_jump()
	_update_flight()

	if not on_ground:
		return

	var cx := cell_x()
	var cy := cell_y()
	if hold_dx != 0:
		var ahead: int = world.get_tile(cx + hold_dx, cy) if world != null else TileTypes.Type.EMPTY
		var edge: float = (float(cx + 1) - (x + HW)) if hold_dx > 0 else ((x - HW) - float(cx))
		if ahead != TileTypes.Type.EMPTY and edge < 0.06:
			_start_dig(cx + hold_dx, cy)
	elif hold_down:
		var below: int = world.get_tile(cx, cy + 1) if world != null else TileTypes.Type.EMPTY
		if below != TileTypes.Type.EMPTY:
			_start_dig(cx, cy + 1)


## Отменяет копку, если игрок увёл управление с копаемой клетки (см.
## cancelWrongDig в web-демо) — вызывается контроллером ввода на каждое
## изменение стика/удержания.
func cancel_wrong_dig() -> void:
	if digging == null:
		return
	var wrong_side: bool = hold_dx != 0 and digging.x != cell_x() + hold_dx
	var left_down: bool = not hold_down and digging.y == cell_y() + 1
	if wrong_side or (left_down and hold_dx != 0):
		digging = null
		dig_cancelled.emit()


# ---------------------------------------------------------------------------
# Копка (startDig/finishDig в web-демо)
# ---------------------------------------------------------------------------

func _can_dig(type: int) -> bool:
	if type == TileTypes.Type.STAIRCASE:
		return false
	if GameState.current_tool == "shovel":
		return TileTypes.can_dig_with_shovel(type)
	return TileTypes.can_dig_with_pickaxe(type) or TileTypes.can_dig_with_shovel(type)


## Множитель скорости копки текущего инструмента. Источник чисел —
## data/balance.json -> tools (единый источник, а не отдельная демо-константа
## DRILL_MULT из web/index.html — та дублировала бы tools.hand_drill.speed_multiplier
## другим числом; см. итоговый отчёт).
func _tool_speed_multiplier() -> float:
	var mult := Balance.get_tool_speed_multiplier(GameState.current_tool)
	if GameState.current_tool == "rusty_pickaxe" and rusty_pickaxe_cracked:
		var broken := float(Balance.unwrap(Balance.get_tool("rusty_pickaxe").get("broken_speed_multiplier", 0.75)))
		mult *= broken
	return maxf(mult, 0.01)


func _start_dig(tx: int, ty: int) -> void:
	if world == null:
		return
	var type := world.get_tile(tx, ty)
	if type == TileTypes.Type.EMPTY:
		return
	if digging != null and digging.x == tx and digging.y == ty:
		return

	if type == TileTypes.Type.STAIRCASE:
		return

	# Обучение не пускает к фундаменту, пока не выбраны пять самородков
	# золота на четвёртом уровне (ГДД п.9, порядок владельца: сперва золото
	# киркой, потом фундамент). Проверка здесь, а не в сюжете: остановить
	# удар можно только там, где он начинается.
	if type == TileTypes.Type.FOUNDATION \
			and StoryState.is_seen("workshop") and not StoryState.has_flag("gold_taken"):
		digging = null
		dig_refused_by_story.emit("gold_first")
		return

	if GameState.current_tool == "shovel":
		var shovel_max_depth := Balance.get_tool_max_depth("shovel")
		if type == TileTypes.Type.FOUNDATION:
			if not _seen_foundation:
				_seen_foundation = true
				# Упрощение квеста "мастерская" (см. итоговый отчёт): полноценной
				# сцены деда/кирки нет, но игра не оставляет игрока запертым
				# под фундаментом лопатой — выдаёт ржавую кирку сразу.
				GameState.set_current_tool("rusty_pickaxe")
				tool_auto_switched.emit("rusty_pickaxe")
			return
		if shovel_max_depth >= 0 and ty > shovel_max_depth:
			return

	if not _can_dig(type):
		# Обучающее золото — исключение из стана. Автокопка оставляет пять
		# самородков на четвёртом уровне торчать посреди расчищенной земли, и
		# первое, что делает игрок, — бьёт по ним лопатой. Стан приходит
		# РАНЬШЕ, чем игра успела сказать, что такое золото и зачем нужна
		# кирка: тряска без объяснения. Пока сцена мастерской не сыграла,
		# вместо стана объясняем словами.
		if type == TileTypes.Type.GOLD_ORE and not StoryState.is_seen("workshop"):
			digging = null
			dig_refused_by_story.emit("gold_needs_pickaxe")
			return
		stun_until_msec = Time.get_ticks_msec() + float(Balance.unwrap(
			Balance.balance.get("digging", {}).get("shovel_stun_on_stone_or_gold_seconds", 60))) * 1000.0
		digging = null
		dig_blocked.emit(type)
		return

	var mineral_id := MineralMap.mineral_id_for(type)
	var base_secs := Balance.get_mineral_drill_seconds(mineral_id) if not mineral_id.is_empty() \
		else float(Balance.unwrap(Balance.balance.get("digging", {}).get("base_seconds_per_cell", 3.0)))
	var stage := GameState.get_skill_stage("dig_speed")
	var total: float = base_secs * pow(0.96, float(stage)) / _tool_speed_multiplier() \
		/ Balance.get_global_dig_speed_multiplier()
	# Штраф за пустую бодрость — делением, потому что здесь время, а не скорость.
	total /= GameState.get_speed_multiplier()

	digging = {"x": tx, "y": ty, "t": 0.0, "total": maxf(total, 0.05), "type": type}
	dig_started.emit(tx, ty, type)


func _finish_dig() -> void:
	var d = digging
	digging = null
	if world == null:
		return
	world.dig_cell(d.x, d.y)

	var mineral_id := MineralMap.mineral_id_for(d.type)
	var price := Balance.get_mineral_price(mineral_id) if not mineral_id.is_empty() else 0
	var luck := GameState.get_skill_stage("luck_multiplier")
	var luck_mult := Balance.get_luck_multiplier(luck)
	price = int(round(float(price) * luck_mult)) if price > 0 else price

	# Опыт (ГДД раздел 11): земля 1 · камень 2 · руда = цена/5.
	if d.type == TileTypes.Type.DIRT:
		GameState.add_xp(1)
	elif d.type == TileTypes.Type.STONE:
		GameState.add_xp(2)
	elif price > 0:
		GameState.add_xp(int(round(float(price) / 5.0)))

	# Монеты за копку НЕ начисляются: сырьё превращается в деньги только при
	# продаже (ГДД раздел 15). Иначе шахта сама себя оплачивает, и подъём на
	# поверхность с грузом перестаёт быть решением игрока.
	var was_loot := MineralMap.is_loot(d.type)
	if not was_loot:
		# Земля, камень и фундамент — не добыча: в рюкзак не ложатся, вес не
		# занимают и не стоят ничего (ГДД раздел 4).
		pass
	else:
		var weight := Balance.get_mineral_weight(mineral_id)
		var free_kg: float = GameState.get_max_carry_kg() - GameState.get_total_weight()
		if weight > free_kg:
			dig_finished.emit(d.x, d.y, d.type, mineral_id, true, 0)
		else:
			GameState.add_item(mineral_id, 1)
			dig_finished.emit(d.x, d.y, d.type, mineral_id, true, price)

	if not was_loot:
		dig_finished.emit(d.x, d.y, d.type, mineral_id, false, price)

	# Дедова кирка трескается на сценарном алмазе глубины 80 (ГДД раздел 4).
	if d.y == 80 and d.type == TileTypes.Type.DIAMOND and GameState.current_tool == "rusty_pickaxe":
		rusty_pickaxe_cracked = true

	GameState.update_max_depth(d.y)


# ---------------------------------------------------------------------------
# Смерть — верхний слой земли зарастает (см. main.gd:restore_topsoil), герой
# телепортируется домой. Сама рестарт-логика тут не решается: это зона main.gd
# (нужен доступ к WorldGen).
# ---------------------------------------------------------------------------

func teleport_home() -> void:
	x = 20.5
	y = 0.5
	vx = 0.0
	vy = 0.0
	digging = null
	thrust = ""
	coasting = false


func camera() -> Vector2:
	return Vector2(x, y)

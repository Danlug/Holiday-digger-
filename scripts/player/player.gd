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
## Герой сел в бурмобиль — посадка закончилась (решение владельца от
## 2026-09-21: посадка НЕ автоматическая, а кнопкой "В бурмобиль" у
## припаркованной машины, см. start_rig_boarding()). Не путать с
## tool_auto_switched — тот сигнал говорит только "инструмент сменился",
## этот — конкретно "ты за рулём, анимация посадки доиграла".
signal entered_rig
## Бурмобиль без топлива глохнет прямо под землёй (копать нечем) — или
## посадка кнопкой "В бурмобиль" отказывает без брикетов. Текст сообщения —
## сюда, а не отдельными сигналами на каждый случай: оба говорят игроку одно
## и то же — "нужны брикеты" — разными словами момента.
signal rig_fuel_warning(message: String)
## Начался/закончился выход из бурмобиля на поверхности (проехал из-под
## земли) или посадка в него (кнопка у припаркованной машины) — см. блок
## "Выход и посадка в бурмобиль на поверхности" ниже. character_view.gd
## слушает эти сигналы, чтобы не гадать о состоянии по кадрам.
signal rig_transition_started(entering: bool)
signal rig_transition_finished(entering: bool)

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
# Высота хитбокса — треть клетки в каждую сторону от центра (2/3 клетки
# целиком), а не 0.46*2≈0.92 как было (владелец, 2026-09-21: «после
# скругления пикселей тайлов он начал застревать, либо падать застряв на
# некоторое время на высоте 1 тайла... отрегулируй его физическую высоту —
# треть тайла, на две трети тайла в высоту, пусть визуально выглядит так
# же»). Причина: при старой высоте 0.92 в проёме ровно в 1 клетку оставалось
# только 0.08 клетки (~2.5 px) зазора. Скругление углов (CORNER ниже) при
# падении/ходьбе через такой проём подталкивает героя на доли пикселя то в
# одну, то в другую сторону — и хитбокс, которому не хватало миллиметров,
# то ловил соседнюю стену, то нет, отсюда дрожь/зависание ровно на высоте
# 1 тайла. 2/3 клетки высоты оставляют 0.33 клетки (~10.7 px) запаса — с
# запасом хватает пережить скругление без сцепления. На картинку не
# влияет: спрайт героя (character_view.gd) хитбокс не читает вовсе, он
# заякорен по голове отдельной логикой.
const HH := 1.0 / 3.0
const CORNER := 7.0 / 32.0     # скругление углов коллизии (решение владельца:
# герой сильно застревал на углах тайлов при прежних 5 px — см. отчёт агента,
# tests/test_player_harness.gd:_test_corner_rounding_* — форгив до 7 px
# проскальзывает, 8+ px по-прежнему честно блокирует)

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

# --- пороги глубины (ГДД раздел 5/6) ---
# Ранцы по глубине больше НЕ выдаются — вся линейка покупается за монеты.
# PROP_DEPTH остался тем рубежом, на котором ранец впервые нужен (сюжетная
# сцена «Ранец» играет примерно там же), и по нему же миграция старого сейва
# понимает, что ранец у игрока уже был; сама выдача из этого числа ушла.
const PROP_DEPTH := 10
const JET_DEPTH := 100
# Буровая машина — следующая ступень после ручного бура. Глубина взята той
# же логикой, что и остальные ступени: на порядок глубже предыдущей.
const RIG_DEPTH := 1000

# --- линейка ранцев ---
# Потолок скорости подъёма БАЗОВОГО ранца сюда не пишется: он лежит в
# data/balance.json (gear.base_max_speed_cells_per_sec = 2.5, прежняя
# PROP_SPEED из web-демо), потому что его умножает вся линейка ступеней.
# Держать базу в коде, а множители ступеней в данных — верный способ развести
# их при первой правке цены.
const PROP_RAMP := 3.0          # время разгона пропеллеров до потолка, сек
const JET_RAMP := 5.0           # то же у реактивной тяги (грузом не портится)
const JUMP_TO_FLY_MS := 300.0   # пауза между толчком прыжка и включением тяги

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

## Стартовая клетка героя: сразу справа от дома и слева от тоннеля Роберта
## (решение владельца 2026-09-21). Припаркованный бурмобиль ждёт по другую
## сторону устья — справа от тоннеля (см. _start_rig_exit).
const HOME_X := float(WorldGen.HOUSE_X_MAX + 1) + 0.5   # 15.5

var x: float = HOME_X
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

# --- бурмобиль как транспорт (ГДД раздел 5, решение владельца) ---
## Была ли клетка под героем подземной в ПРЕДЫДУЩЕМ кадре — по перепаду
## отсюда узнаём момент выезда на поверхность (см. _check_rig_surface_exit),
## а не пересчитываем его из типа тайла каждый раз.
var _was_underground: bool = false
## Дробный остаток расхода топлива (blocks_per_cell меньше единицы — блок
## тратится не на каждой клетке). Не сохраняется между сессиями: точность в
## доли блока никто не заметит, а хранить её ради этого не стоит.
var _rig_fuel_progress: float = 0.0
## Тост «кончилось топливо» при попытке копать без брикетов уже показан для
## текущего удержания копки — _start_dig вызывается каждый кадр физики, пока
## держится направление копки, и без этого флага тост эмитился бы 60 раз в
## секунду вместо одного раза за попытку. Сбрасывается на «отпустил ввод» —
## новая попытка снова получает своё сообщение. (Стены у устья без топлива
## больше нет — спуск пешком разрешён всегда, посадка только кнопкой.)
var _rig_dig_stall_warned: bool = false

# --- выход/посадка в бурмобиль на поверхности (свои переменные и функции —
# см. блок ниже — держатся отдельно от фаз копки (DIG_PHASES в
# character_view.gd), которые параллельно правит другой агент: слияние
# должно остаться простым) ---
## "" — герой не в переходе; "exit" — выезжает из-под земли (запускается
## сам, см. _check_rig_surface_exit); "enter" — садится в припаркованную
## машину (по кнопке "В бурмобиль", см. start_rig_boarding()).
var rig_transition: String = ""
## Индекс текущей фазы внутри _rig_transition_keys/_rig_transition_durations.
var rig_transition_phase: int = 0
var _rig_transition_t: float = 0.0
var _rig_transition_keys: Array = []       # порядок ключей 1..7 текущего перехода
var _rig_transition_durations: Array = []  # их длительности в секундах, тот же порядок

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
# Снаряжение — надетая ступень линейки ранцев (решение владельца: четыре
# ступени за монеты, одна активная). Глубина снаряжение больше НЕ выдаёт:
# воротами прогресса стали деньги, и ранец, падающий в руки за то, что ты
# просто копал вниз, не ощущается покупкой.
# ---------------------------------------------------------------------------

## Умеет ли герой летать вообще: на спине что-то надето.
func has_backpack() -> bool:
	return not GameState.current_gear.is_empty()


## Надета реактивная ступень (джетпак или топовый джетпак). Отличается от
## пропеллеров временем разгона, анимацией полёта и ударом головой о потолок —
## отдельной ветки линейки тут нет, просто верхние две ступени реактивные.
func has_jetpack() -> bool:
	return Balance.get_gear_kind(GameState.current_gear) == "jet" and has_backpack()


## Ступень надетого снаряжения (0 — ничего, 1..4 — ранец… топовый джетпак).
## По ней CharacterView выбирает ленту полёта fly_1..fly_4 — своя у каждой
## ступени, потому что нарисованы они вместе с героем, а не накладкой.
func flight_tier() -> int:
	if GameState.current_gear.is_empty():
		return 0
	return int(Balance.unwrap(Balance.get_gear(GameState.current_gear).get("tier", 0)))


func has_hand_drill() -> bool:
	return GameState.max_depth_reached >= JET_DEPTH


## Открыт ли рецепт бурмобиля по глубине (RIG_DEPTH). Открытие рецепта и
## владение — разные вещи: has_drill_rig() говорит "можно собрать", а
## GameState.owned_tools.has("drill_rig") — "уже стоит в гараже". Само
## владение решает, ходит ли герой пешком или ездит (см. блок ниже:
## "бурмобиль как транспорт", start_rig_boarding и _check_rig_surface_exit).
## Перегрев машины из
## ГДД раздела 5 по-прежнему не реализован — числа не заданы владельцем
## (см. balance.json -> survival.hazards.drill_overheat).
func has_drill_rig() -> bool:
	return GameState.max_depth_reached >= RIG_DEPTH


# ---------------------------------------------------------------------------
# Бурмобиль как транспорт (ГДД раздел 5). Уточнение владельца от 2026-09-21
# (поверх более раннего «спускаясь под землю он должен быть только в нём»):
# посадка НЕ автоматическая. Герой пешком подходит к припаркованной у устья
# машине — контекстная кнопка «В бурмобиль» (HouseSystem, как «Зайти» у
# веранды) запускает посадку. Не нажал и пошёл в тоннель вниз — спускается
# пешком со своей экипировкой, машина остаётся на парковке. Под землёй
# пешком теперь МОЖНО (старая невидимая стена на входе снята вместе с
# автопосадкой): единственное, что по-прежнему нельзя без брикетов, — сама
# посадка (см. start_rig_boarding) и копка в машине без топлива (см.
# _start_dig).
#
# Единственная истина, надета ли машина, — GameState.current_tool ==
# "drill_rig" (is_in_rig()). Где машина, когда НЕ надета, — GameState.
# rig_parked_at (см. game_state.gd): либо нигде (ещё не куплена или впервые
# едет вниз при разблокировке рецепта — та ветка не в зоне этой задачи), либо
# на поверхности у устья тоннеля, куда её поставил _start_rig_exit.
# ---------------------------------------------------------------------------

## Герой прямо сейчас "за рулём": машина в собственности и надета. Отдельно
## от того, под землёй он или нет, — character_view.gd решает по этому же
## условию ПЛЮС cell_y() >= 1: на поверхности, пока не доиграла посадка,
## машина просто стоит на парковке (рисуется миром, не героем).
func is_in_rig() -> bool:
	return GameState.current_tool == "drill_rig"


## Хватает ли топлива на бурмобиль прямо сейчас. Топливо — брикеты угля
## (fuel_block), а не сам уголь: уголь ещё нужно спрессовать на верстаке
## (см. ShopCatalog._recipe_fuel_block_coal).
func _has_rig_fuel() -> bool:
	return GameState.get_item_count("fuel_block") > 0


## Публичная обёртка — HouseSystem (владелец кнопки «В бурмобиль») спрашивает
## топливо ровно тем же способом, что и сам player.gd, чтобы кнопка и
## реальная посадка не разошлись в том, что считается «есть топливо».
func has_rig_fuel() -> bool:
	return _has_rig_fuel()


## Лучший инструмент для копки в собственности игрока (не считая саму
## машину) — на него переключается герой, выйдя из бурмобиля пешком
## (решение владельца: «current_tool переключается на лучшую кирку в
## собственности»). "Лучший" — по множителю скорости копки из balance.json,
## а не по фиксированному списку: список кирок и так живёт в данных, и
## дублировать его порядок здесь — плодить второй источник правды.
func _best_owned_dig_tool() -> String:
	var best := "shovel"
	var best_mult := -1.0
	for t in GameState.owned_tools:
		var tool_id := String(t)
		if tool_id == "drill_rig":
			continue
		var mult := Balance.get_tool_speed_multiplier(tool_id)
		if mult > best_mult:
			best_mult = mult
			best = tool_id
	return best


## Ловит момент, когда герой ВЫЕХАЛ из-под земли на поверхность в бурмобиле
## (пересёк границу y=1 снизу вверх) — начинает анимацию выхода (см.
## _start_rig_exit). Обратное направление (спуск) больше не трогает: под
## землю пешком теперь можно всегда, посадка в машину — отдельное явное
## действие (start_rig_boarding), а не пересечение границы.
func _check_rig_surface_exit() -> void:
	var underground := cell_y() >= 1
	if not underground and _was_underground and is_in_rig() and rig_transition == "":
		_start_rig_exit()
	_was_underground = underground


# ---------------------------------------------------------------------------
# Анимация выхода/посадки (art/character/rig_exit.png + rig_exit.json, см.
# tools/import_rig_exit.py). Семь КЛЮЧЕВЫХ поз без интерполяции между ними —
# пиксель-арт, "плавности" тут не бывает, только держим каждый ключ
# положенное число кадров и режем на следующий.
# ---------------------------------------------------------------------------

const RIG_EXIT_META_PATH := "res://art/character/rig_exit.json"
## Резервные числа на случай отсутствия JSON (тесты без art/, урезанная
## сборка) — те же, что напечатал tools/import_rig_exit.py по факту листа.
const RIG_EXIT_PHASES_FALLBACK := [8, 8, 8, 4, 6, 7, 8]
const RIG_EXIT_FPS_FALLBACK := 7.0
const RIG_EXIT_STAND_DX_FALLBACK := 15.0  # логические px, см. JSON stand_dx

static var _rig_exit_meta: Dictionary = {}
static var _rig_exit_meta_loaded: bool = false


## Метаданные листа выхода — читаются один раз на весь процесс (общий файл
## для всех героев, разбирать JSON каждый переход незачем).
static func _rig_exit_meta_dict() -> Dictionary:
	if not _rig_exit_meta_loaded:
		_rig_exit_meta_loaded = true
		if ResourceLoader.exists(RIG_EXIT_META_PATH):
			var f := FileAccess.open(RIG_EXIT_META_PATH, FileAccess.READ)
			if f != null:
				var parsed = JSON.parse_string(f.get_as_text())
				if parsed is Dictionary:
					_rig_exit_meta = parsed
	return _rig_exit_meta


func _rig_phase_frames() -> Array:
	var arr = _rig_exit_meta_dict().get("phase_frames", RIG_EXIT_PHASES_FALLBACK)
	return arr if arr is Array and arr.size() == 7 else RIG_EXIT_PHASES_FALLBACK


func _rig_exit_fps() -> float:
	return float(_rig_exit_meta_dict().get("fps", RIG_EXIT_FPS_FALLBACK))


## Смещение героя от центра припаркованной машины в ключе 7 (стоит рядом) —
## переводится из логических px листа в клетки (x, y здесь — клетки).
func _rig_stand_dx_cells() -> float:
	return float(_rig_exit_meta_dict().get("stand_dx", RIG_EXIT_STAND_DX_FALLBACK)) / TILE


## Ключ (1..7) листа rig_exit.png, который сейчас должен быть на экране —
## character_view.gd спрашивает это, а не считает кадр сам: порядок ключей
## при посадке обратный (7→1), и дублировать эту логику в двух файлах —
## плодить рассинхрон.
func rig_transition_key() -> int:
	if _rig_transition_keys.is_empty():
		return 1
	return int(_rig_transition_keys[clampi(rig_transition_phase, 0, _rig_transition_keys.size() - 1)])


func _rig_setup_transition(entering: bool) -> void:
	var frames := _rig_phase_frames()
	var fps := maxf(0.1, _rig_exit_fps())
	var keys: Array = []
	var secs: Array = []
	if entering:
		# Посадка — та же последовательность ключей в обратном порядке
		# (решение владельца), с той же длительностью на каждый ключ.
		for i in range(frames.size() - 1, -1, -1):
			keys.append(i + 1)
			secs.append(float(frames[i]) / fps)
	else:
		for i in range(frames.size()):
			keys.append(i + 1)
			secs.append(float(frames[i]) / fps)
	_rig_transition_keys = keys
	_rig_transition_durations = secs
	rig_transition_phase = 0
	_rig_transition_t = 0.0


## Выезд из-под земли на поверхность (см. _check_rig_surface_exit) — играет
## сам, без участия игрока. Машина паркуется ровно в клетке, где герой
## пересёк границу (единственная вертикальная шахта — устье тоннеля, других
## колонок сюда не приводит), он сам замирает рядом на время анимации.
func _start_rig_exit() -> void:
	rig_transition = "exit"
	_rig_setup_transition(false)
	# Машина паркуется справа от устья (решение владельца: герой стартует
	# слева от тоннеля, бурмобиль ждёт справа), а не в самой колонке устья.
	var park_x := WorldGen.TUNNEL_X + 1
	GameState.rig_parked_at = Vector2i(park_x, 0)
	x = float(park_x) + 0.5
	y = 0.5
	vx = 0.0; vy = 0.0
	digging = null
	thrust = ""
	frozen = true
	rig_transition_started.emit(false)


## Посадка в припаркованную машину — по кнопке "В бурмобиль" (HouseSystem),
## НЕ автоматически (решение владельца от 2026-09-21). Без брикетов кнопка
## есть, но посадка отказывает тостом — топливо проверяется здесь же, одной
## точкой с _has_rig_fuel(), чтобы кнопка и реальная посадка не разошлись.
## Возвращает false, если посадка не началась (не запаркована, уже едет,
## переход уже идёт, нет топлива) — вызывающий сам решает, что сказать
## игроку по ложному false по топливу (см. HouseSystem._on_rig_button).
func start_rig_boarding() -> bool:
	if rig_transition != "" or not GameState.is_rig_parked() or is_in_rig():
		return false
	if not _has_rig_fuel():
		rig_fuel_warning.emit("Нет брикетов — сделай на верстаке из угля")
		return false
	rig_transition = "enter"
	_rig_setup_transition(true)
	x = float(GameState.rig_parked_at.x) + 0.5
	y = 0.5
	vx = 0.0; vy = 0.0
	digging = null
	thrust = ""
	frozen = true
	rig_transition_started.emit(true)
	return true


func _tick_rig_transition(dt: float) -> void:
	_rig_transition_t += dt
	var dur: float = 0.2
	if rig_transition_phase < _rig_transition_durations.size():
		dur = float(_rig_transition_durations[rig_transition_phase])
	if _rig_transition_t < dur:
		return
	_rig_transition_t = 0.0
	rig_transition_phase += 1
	if rig_transition_phase >= _rig_transition_keys.size():
		_finish_rig_transition()


func _finish_rig_transition() -> void:
	var entering := rig_transition == "enter"
	rig_transition = ""
	rig_transition_phase = 0
	_rig_transition_keys = []
	_rig_transition_durations = []
	frozen = false
	if entering:
		# Машина уходит с парковки — она "надета": is_in_rig()/GameState.
		# current_tool теперь единственная истина, второй записи об этой же
		# машине существовать не должно (см. шапку блока "Бурмобиль как
		# транспорт" выше).
		GameState.rig_parked_at = Vector2i(-1, -1)
		GameState.set_current_tool("drill_rig")
		# Сел — и машина уже стоит над устьем: парковка справа от тоннеля,
		# а спуск — только через колонку TUNNEL_X, поэтому подкатываем сюда
		# сами; дальше вниз ведёт обычная физика/ввод игрока.
		x = float(WorldGen.TUNNEL_X) + 0.5
		y = 0.5
		_was_underground = cell_y() >= 1
		entered_rig.emit()
	else:
		# Приехал, вылез — берётся за лучшее, что есть в руках, а не остаётся
		# голыми руками (решение владельца: "current_tool переключается на
		# лучшую кирку в собственности").
		GameState.set_current_tool(_best_owned_dig_tool())
		var park: Vector2i = GameState.rig_parked_at
		x = float(park.x) + 0.5 + _rig_stand_dx_cells()
		y = 0.5
		_was_underground = false
	rig_transition_finished.emit(entering)


## Тратит топливо бурмобиля за одну прокопанную клетку (расход —
## balance.json -> fuel_consumption.blocks_per_cell.drill_rig, дробный:
## блок уходит не на каждый удар). Вызывается из _finish_dig ТОЛЬКО когда
## клетка реально прокопана — попытка по несокрушимому топливо не тратит.
func _consume_rig_fuel() -> void:
	var rate := Balance.get_drill_rig_fuel_per_cell()
	if rate <= 0.0:
		return
	_rig_fuel_progress += rate
	# Эпсилон против дрейфа плавающей точки: 0.1 десять раз подряд даёт
	# 0.999999999999999..., а не ровно 1.0, и без запаса блок списывался бы
	# на одиннадцатой клетке вместо десятой.
	while _rig_fuel_progress >= 1.0 - 0.0001 and GameState.get_item_count("fuel_block") > 0:
		_rig_fuel_progress -= 1.0
		GameState.remove_item("fuel_block", 1)


func _check_gear_unlocks() -> void:
	# Сцена «Ранец» (data/story.json, эффект backpack_owned) вручает базовую
	# ступень флагом сюжета. Переводим флаг в собственность один раз, и дальше
	# всё решает один список owned_gear: два параллельных признака «есть ранец»
	# разъезжаются ровно в тот момент, когда игрок купит вторую ступень.
	if StoryState.has_flag("backpack_owned") and not GameState.has_gear("backpack"):
		GameState.grant_gear("backpack")
	if has_backpack() and not _announced_backpack:
		_announced_backpack = true
		gear_unlocked.emit("backpack")
	if has_jetpack() and not _announced_jetpack:
		_announced_jetpack = true
		gear_unlocked.emit("jetpack")
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
	# Переход (выход/посадка) тикает ДО общей заморозки: он сам держит
	# frozen=true на время анимации (управление и правда заблокировано), но
	# кадры переключать обязан — иначе ранний return ниже никогда не даст
	# анимации сдвинуться с первого ключа.
	if rig_transition != "":
		_tick_rig_transition(dt)
		vx = 0.0
		return

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
	GameState.player_depth = cell_y()
	_award_depth_milestones(GameState.max_depth_reached, cell_y())
	GameState.update_max_depth(cell_y())
	_check_gear_unlocks()
	_check_rig_surface_exit()


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


## Отладочный тумблер «Полёт 300» (debug_panel.gd). Скорость подъёма/падения,
## клеток/с — перекрывает и тягу, и обычную гравитацию мгновенно, константой,
## без разгона.
const DEBUG_FLY_SPEED := 300.0


func _move_y(dt: float) -> void:
	if GameState.debug_fly_300 and (thrust != "" or not on_ground):
		# Единственное место, где vy окончательно применяется к позиции (см.
		# y += vy * dt ниже) — override стоит здесь же, ДО этой строки, а не
		# внутри if/else тяги, поэтому работает одинаково пешком (свободное
		# падение), с ранцем/джетпаком (тяга) и в бурмобиле: снаряжение сюда
		# не заглядывает вовсе. `not on_ground` в условии — иначе герой,
		# просто стоящий на месте без тяги, каждый кадр получал бы vy=+300 и
		# на 60 fps улетал бы на 5 клеток вниз ЗА ОДИН физтик, пробивая тонкий
		# пол мимо коллизии (она проверяет только конечную позицию, не путь
		# до неё): тумблер разгоняет реальное падение/полёт, а не превращает
		# стояние на земле в свободное падение.
		vy = -DEBUG_FLY_SPEED if thrust != "" else DEBUG_FLY_SPEED
	elif thrust != "":
		var jet := thrust == "jet"
		# Множитель ступени ранца умножает ПОТОЛОК скорости подъёма (клеток в
		# секунду) базового ранца — и только его. «×2 скорости полёта» в
		# заказе владельца — это вдвое быстрее лететь, а не вдвое быстрее
		# разогнаться.
		#
		# Время разгона при этом остаётся временем ступени (3 с у пропеллеров
		# с поправкой на груз, 5 с у реактивной тяги), поэтому ускорение
		# max_up/ramp растёт вместе с потолком. Иначе на топовом джетпаке
		# герой десять секунд набирал бы обещанную скорость, и «×10» на
		# практике ощущалось бы как «×10 разгона».
		var max_up: float = Balance.get_gear_base_speed() \
			* GameState.get_gear_fly_multiplier() * GameState.get_speed_multiplier()
		# Бурмобиль: "полёт на 30% быстрее" (решение владельца) — множитель
		# поверх потолка скорости подъёма, пока машина надета (см.
		# Balance.get_drill_rig_flight_speed_mult). Пешего/ранец/джетпак без
		# машины не трогает — множитель 1.0, когда is_in_rig() ложь.
		if is_in_rig():
			max_up *= Balance.get_drill_rig_flight_speed_mult()
		var ramp: float = JET_RAMP if jet else _prop_ramp()
		var accel: float = THRUST_BRAKE if vy > 0.0 else max_up / ramp
		vy = maxf(vy - accel * dt, -max_up)
	else:
		var g: float = COAST_DECEL if (coasting and vy < 0.0) else _gravity_now()
		# Бурмобиль: "скорость падения в бурмобиле на 30% быстрее" (решение
		# владельца) — множитель поверх предела скорости падения, пока машина
		# надета (см. Balance.get_drill_rig_fall_speed_mult).
		var v_term: float = V_TERM * (Balance.get_drill_rig_fall_speed_mult() if is_in_rig() else 1.0)
		vy = minf(vy + g * dt, v_term)

	# Небо не бесконечное: на подлёте к его верху гасим подъём пропорционально
	# остатку высоты. Падение это не трогает (только vy < 0), так что урон от
	# падения считается по прежним правилам.
	var ceiling: float = _sky_ceiling()
	if vy < 0.0 and y - ceiling < SKY_BRAKE:
		vy *= clampf((y - ceiling) / SKY_BRAKE, 0.0, 1.0)

	on_ground = false

	# Шаг по Y дробим на куски не больше MOVE_STEP_MAX клетки: коллизия ниже
	# проверяет только итоговую позицию после шага, а не путь до неё, и при
	# большой скорости (тумблер отладки «Полёт 300» — 300 клеток/с) герой
	# перепрыгивал однотайловый пол/потолок целиком за один физтик, ни разу
	# не попав в него собственной проверкой. Обычная скорость (V_TERM, тяга
	# ранца/джетпака) всегда меньше клетки за тик, так что цикл почти всегда
	# проходит ровно одну итерацию — лишней работы это не добавляет.
	const MOVE_STEP_MAX := 0.9
	var remaining: float = vy * dt
	var stopped := false
	while absf(remaining) > 0.0001 and not stopped:
		var step: float = clampf(remaining, -MOVE_STEP_MAX, MOVE_STEP_MAX)
		y += step
		remaining -= step

		# Страховка на случай большого шага: за нарисованную кромку неба не
		# выпускаем.
		if y < ceiling:
			y = ceiling
			vy = maxf(vy, 0.0)
			stopped = true
			break

		var left := x - HW + 0.02
		var right := x + HW - 0.02

		if vy > 0.0:
			var b := y + HH
			var hit_lb := _solid_at(left, b)
			var hit_rb := _solid_at(right, b)
			var slipped_b := false
			# Тот же угловой допуск, что и при взлёте ниже (раздельная коллизия
			# по осям иначе сажала героя на карниз шахты шириной в клетку,
			# стоило ему при падении/копке вниз оказаться смещённым от центра
			# на пиксели — решение владельца, см. отчёт агента): падение в
			# шахту соскальзывает к центру, а не садится на угол, который
			# герой всё равно бы прошёл.
			if hit_lb and not hit_rb:
				var over_b: float = (floor(left) + 1.0) - left
				if over_b <= CORNER:
					x += over_b + 0.002
					slipped_b = true
			elif hit_rb and not hit_lb:
				var over2_b: float = right - floor(right)
				if over2_b <= CORNER:
					x -= over2_b + 0.002
					slipped_b = true
			if (hit_lb or hit_rb) and not slipped_b:
				y = floor(b) - HH - 0.001
				_land()
				vy = 0.0
				on_ground = true
				stopped = true
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
				stopped = true
		else:
			stopped = true

	var left := x - HW + 0.02
	var right := x + HW - 0.02
	if not on_ground:
		var b2 := y + HH + 0.02
		on_ground = vy == 0.0 and (_solid_at(left, b2) or _solid_at(right, b2))


## Урон от падения — от СКОРОСТИ удара, а не от пройденной высоты (ГДД п.6).
## Формула — в Balance.get_fall_damage_from_speed (единый источник с тестами
## tests/test_fall_damage_speed.gd); G передаётся аргументом, потому что это
## константа ощущений движения игрока, а не баланса.
##
## Бурмобиль: "урон от падения на 50% меньше, а высота, с которой он получает
## урон, в 3 раза выше" (решение владельца) — множители поверх формулы, пока
## машина надета (см. Balance.get_drill_rig_fall_damage_mult/
## get_drill_rig_fall_damage_height_mult); пешего/ранец/джетпак не трогает —
## оба множителя 1.0, когда is_in_rig() ложь.
func _land() -> void:
	var v := vy
	var dmg_mult := 1.0
	var height_mult := 1.0
	if is_in_rig():
		dmg_mult = Balance.get_drill_rig_fall_damage_mult()
		height_mult = Balance.get_drill_rig_fall_damage_height_mult()
	var dmg := roundf(Balance.get_fall_damage_from_speed(v, G, dmg_mult, height_mult))
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
		else:
			_rig_dig_stall_warned = false
	elif hold_down:
		var below: int = world.get_tile(cx, cy + 1) if world != null else TileTypes.Type.EMPTY
		if below != TileTypes.Type.EMPTY:
			_start_dig(cx, cy + 1)
		else:
			_rig_dig_stall_warned = false
	else:
		# Не держит ни направление, ни "вниз" — новая попытка копать без
		# топлива (после этого простоя) снова получит своё сообщение.
		_rig_dig_stall_warned = false


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
## Balance.get_tool_speed_multiplier() (data/balance.json -> tools; бур и
## бурмобиль считаются ОТ лучшей кирки, см. комментарий там) — единый
## источник, а не отдельная демо-константа DRILL_MULT из web/index.html
## (устаревший статический прототип до Godot-версии, не собирается и не
## тестируется вместе с игрой: та дублировала бы это число своим, другим).
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
		# Раньше здесь просто выходили молча: удар о лестницу не давал вообще
		# никакой обратной связи — ни стана (её и не должно быть, это не
		# порода), ни подсказки. После того как лестница развернулась широким
		# концом к поверхности (см. отчёт агента у world_gen.gd:
		# _pre_autodig_min_x — баг владельца "не копается даже справа от
		# лестницы"), герой на старте почти наверняка сначала упрётся именно
		# в неё, а не в гейт — тот же самый совет ("начни справа от
		# лестницы") здесь так же уместен, и даёт его та же самая строка
		# перевода, что и раньше у гейта, а не отдельная.
		dig_refused_by_story.emit("garden_left_of_stairs")
		return

	# Под домом (x 0..14) верхние пять уровней не копают никогда — решение
	# владельца, никаким инструментом; глубже дом копается как вся шахта.
	# world.dig_cell() и так откажет в конце анимации (единая точка правды —
	# см. world_gen.gd), но отказывать нужно ДО удара, тем же приёмом, что и
	# запечатанный огород ниже: иначе стан/опыт/топливо успели бы примениться
	# за удар, который ничего не выкопал.
	if world.is_house_locked_cell(tx, ty):
		digging = null
		return

	# Пока не запущен сценарий со скоростной копкой (ГДД п.9, решение
	# владельца: "в начале игры ему можно копать только справа от дома и
	# лестницы"), огород левее правого края лестницы не копается никаким
	# инструментом — единая точка правды та же, что и у дома выше:
	# world.dig_cell() своё держит, но отказывать надо ДО удара.
	if world.has_method("is_pre_autodig_locked_cell") and world.is_pre_autodig_locked_cell(tx, ty):
		digging = null
		dig_refused_by_story.emit("garden_left_of_stairs")
		return

	# Бурмобиль без топлива глохнет под землёй: копать нечем, но идти по уже
	# прорытому можно (решение владельца) — поэтому запрет только здесь, в
	# начале копки, а не в физике движения.
	if is_in_rig() and not _has_rig_fuel():
		digging = null
		# _start_dig зовётся каждый кадр, пока герой держит направление копки
		# (см. _apply_intent) — без флага тост сыпался бы каждый кадр вместо
		# одного раза за попытку (сбрасывается там же, когда ввод отпущен).
		if not _rig_dig_stall_warned:
			_rig_dig_stall_warned = true
			rig_fuel_warning.emit("Кончилось топливо")
		return

	# Запечатанный Робертом огород (уровни 1..4 вне ствола тоннеля) не
	# копается вообще. Отказывать надо ДО удара, а не после: world.dig_cell()
	# своё держит и клетку не отдаёт, но удар уже прошёл бы — а опыт в
	# _finish_dig начисляется за сам удар. Получалась бесконечная ферма опыта
	# на грядке.
	if world.has_method("is_garden_sealed_cell") and world.is_garden_sealed_cell(tx, ty):
		digging = null
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
			# Кирка больше не появляется в руках сама от удара о фундамент:
			# за ней идут в мастерскую и снимают со стены среди швабр и удочек
			# (решение владельца; HouseSystem.take_starting_pickaxe). Лопата
			# о фундамент — только слова, без стана: игрок ещё не знает, что
			# такое фундамент, и тряска без объяснения ничему не учит.
			digging = null
			dig_refused_by_story.emit("foundation_needs_pickaxe")
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
	var total: float
	if GameState.debug_instant_dig:
		# Отладочный тумблер «Копка» (debug_panel.gd): время копки — 0, клетка
		# выкапывается на первом же физтике удержания (digging.t += dt сразу
		# перевалит за total=0.0, см. physics_tick). Обычная формула ниже
		# нарочно не считается вовсе — она пропускается, а не обнуляется
		# постфактум, иначе maxf(total, 0.05) в конце вернул бы минимум 0.05с.
		total = 0.0
	else:
		var base_secs := Balance.get_mineral_drill_seconds(mineral_id) if not mineral_id.is_empty() \
			else float(Balance.unwrap(Balance.balance.get("digging", {}).get("base_seconds_per_cell", 3.0)))
		var stage := GameState.get_skill_stage("dig_speed")
		total = base_secs * pow(0.96, float(stage)) / _tool_speed_multiplier() \
			/ Balance.get_global_dig_speed_multiplier()
		# Штраф за пустую бодрость — делением, потому что здесь время, а не скорость.
		total /= GameState.get_speed_multiplier()
		total = maxf(total, 0.05)

	digging = {"x": tx, "y": ty, "t": 0.0, "total": total, "type": type}
	dig_started.emit(tx, ty, type)


func _finish_dig() -> void:
	var d = digging
	digging = null
	if world == null:
		return
	# Мир — последнее слово: если клетку он не отдал (зафиксированная порода,
	# запечатанный огород), то и награды за удар нет. Раньше результат
	# игнорировался, и опыт капал за удары по несокрушимому.
	if not world.dig_cell(d.x, d.y):
		return

	# Топливо тратится на реально прокопанную клетку, не на попытку удара —
	# тем же правилом, что и опыт ниже.
	if is_in_rig():
		_consume_rig_fuel()

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
	x = HOME_X
	y = 0.5
	vx = 0.0
	vy = 0.0
	digging = null
	thrust = ""
	coasting = false
	# Герой оказался дома не своим ходом: следующий спуск обязан снова
	# считаться входом в тоннель, а не "он и так был внизу".
	_was_underground = false
	# Смерть/телепорт не должны оставлять недоигранный переход висящим —
	# frozen из него снимается здесь же, иначе герой дома навсегда замер бы
	# в позе анимации выхода.
	if rig_transition != "":
		rig_transition = ""
		rig_transition_phase = 0
		_rig_transition_keys = []
		_rig_transition_durations = []
		frozen = false


func camera() -> Vector2:
	return Vector2(x, y)

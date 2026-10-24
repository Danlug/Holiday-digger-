extends Node2D
## CharacterView — отрисовка спрайта героя (портировано из блока анимации в
## draw() web/index.html): выбор листа по состоянию (копает/летит/падает/
## идёт/стоит), покадровая анимация горизонтальной полосой кадров, разворот
## по facing.
##
## Кадр шире клетки: при 32 px замах киркой и винты ранца не помещались, и
## спрайт приходилось ужимать — герой заметно худел, стоило ему начать
## копать. Тело по-прежнему ~20 px, просто вокруг него есть поле.

const TILE := 32

## Во сколько раз текстуры подробнее игровых координат (см. пояснение в
## tools/import_art.py). Кадр героя на диске — 144×144, а на экране он занимает
## те же 48 логических точек: спрайт рисуется уменьшенным втрое, и телефону
## достаётся втрое больше настоящих пикселей вместо растянутых квадратов.
const ART_SCALE := 3.0

const CHAR_W := int(48 * ART_SCALE)
const CHAR_H := int(48 * ART_SCALE)
const HH := 0.46

## Линия земли внутри кадра: подошва героя стоит на CHAR_H - FOOT_PAD.
## На этом держится вся вертикальная привязка спрайта — см. SHEET_FRAME.
const GROUND_Y := int(46 * ART_SCALE)

## Листы, у которых кадр не 48×48: имя листа -> [ширина, высота, линия земли].
##
## Бурмобиль по ГДД п.5 занимает две клетки в ширину — это 64 px, и в кадр 48
## он не влезает. Ужимать машину нельзя: вместе с ней ужимается герой в
## кабине, и он становится мельче героя пешком. Лишняя высота кадра уходит
## ВНИЗ, под линию земли, — бур, копающий вниз, входит в клетку под машиной,
## и отвал породы должен лечь именно туда.
##
## Ленты полёта fly_1..fly_4 — та же история, только лишнее место уходит
## ВВЕРХ, под винты, и немного вниз, под выхлоп. Тело героя в них того же
## размера, что в idle.png: масштаб на весь лист один, и посчитан он по росту
## героя (см. tools/import_packs.py). Влезть в 48×48 винты не могут — у
## большого винта один диск 66 px в поперечнике, у топового джетпака пламя
## уносит на 43 px назад, — а ужимать под них героя нельзя: он станет мельче
## себя же пешком. Числа берутся из печати импортёра, менять их руками не надо.
##
## Ряды копки инструментом (dig_pick, dig_pick_rusty, dig_shovel) — тоже
## шире 48 px: удар о землю рисует дугу замаха и разлетающуюся породу шире
## клетки, а ужимать замах нельзя — герой на этом кадре худеет (см.
## tools/import_dig.py, DIG_FRAME_W). Высота и линия земли те же, что у
## idle — лишней высоты этим наборам не нужно.
## rig_jump/rig_fly — прыжок и полёт бурмобиля (см. tools/import_rig_jump_fly.py
## и блок "Прыжок и полёт бурмобиля" ниже). GROUND_Y=150 у обоих — та же линия
## земли, что у dig_rig_down/side: машина не должна прыгать по вертикали при
## переходе копка <-> прыжок <-> полёт.
const SHEET_FRAME := {
	"dig_pick": [192, 144, 138],
	"dig_pick_rusty": [192, 144, 138],
	"dig_shovel": [192, 144, 138],
	"dig_rig_down": [240, 168, 150],
	"dig_rig_side": [240, 168, 150],
	"rig_jump": [240, 168, 150],
	"rig_fly": [220, 220, 150],
	"fly_1": [154, 162, 156],
	"fly_2": [204, 165, 163],
	"fly_3": [152, 141, 129],
	"fly_4": [260, 136, 123],
}

## Лента полёта по уровню снаряжения: 1 — ранец, 2 — улучшенный ранец,
## 3 — джетпак, 4 — топовый джетпак. 0 — снаряжения нет.
const FLY_SHEETS := ["fly_1", "fly_2", "fly_3", "fly_4"]

## Сколько единиц счётчика anim держится один кадр. Меньше — быстрее.
const ANIM_DIV := 7.0

## Свой темп у листов, где кадров не четыре.
##
## Ходьба нарисована на шестнадцать кадров, и это ЧЕТЫРЕ шага, а не один
## цикл: узкие позы (ноги вместе) приходятся на кадры 1, 5, 9 и 13. При общем
## темпе 7.0 шаг растянулся бы вчетверо, и герой поехал бы по земле как на
## коньках. Первоначально темп был считан от скорости буквально (4.2
## клетки/с = 134 px/с, шаг в рисунке ~17 px -> 3.8 единицы на кадр), но
## визуально ноги семенили слишком быстро (владелец, 2026-09-22:
## «анимация ходьбы слишком быстрая, замедли, скорость ходьбы нормальная» —
## САМА скорость передвижения не трогается, WALK ниже как была). 6.0 —
## почти вдвое ленивее буквального расчёта, ближе к общему темпу 7.0 у
## остальных листов. Захочется бодрее или ленивее — крутится здесь, одним
## числом.
const SHEET_ANIM_DIV := {
	"walk": 6.0,
}

## Листы копки, нарисованные отдельно для копки вниз и для копки вбок.
## Ключ — общее имя набора, к нему приписывается "_down" или "_side".
const DIG_SHEETS := ["idle", "walk", "fall", "fly", "fly_jet",
		"fly_1", "fly_2", "fly_3", "fly_4",
		"dig_shovel", "dig_pick", "dig_pick_rusty",
		"dig_drill_down", "dig_drill_side", "dig_rig_down", "dig_rig_side",
		"rig_jump", "rig_fly", "jump", "hurt", "idle_x"]

## Фазы анимации копки: не все листы копки играются простым циклом по всем
## кадрам. Бурмобиль нарисован тремя фазами — старт бурения, зацикленное
## бурение, финиш, — и играть его по кругу с первого кадра до последнего
## неверно: получится, что машина то и дело заново «выезжает» и «уезжает».
## Ключ — общее имя набора БЕЗ суффикса направления (см. _dig_tool_base),
## значение — три списка 0-based индексов кадров листа:
##   start — играются один раз при начале копки;
##   loop  — крутятся по кругу, пока копка идёт;
##   end   — играются один раз после того, как копка закончилась.
## Точка расширения: для листов без записи здесь (кирка, лопата, ручной бур)
## сохраняется старое поведение — цикл по всем кадрам листа, см. _process.
const DIG_PHASES := {
	"dig_rig": {"start": [0, 1, 2], "loop": [3, 4, 5, 6], "end": [7, 2, 1, 0]},
}

## Копка следующей клетки, начавшаяся не позже чем через это время после
## конца предыдущей, — продолжение той же непрерывной работы (бур уже
## раскручен), и старт не играется повторно: сразу в цикл. Дольше — новый
## заход, играется полный старт (см. _dig_frame).
const DIG_PHASE_RESTART_GAP_MS := 300.0

var player: Node = null

# Тряска стана: 3 пикселя вправо-влево (решение владельца) на 14 Гц.
const SHAKE_PIXELS := 3.0
const SHAKE_HZ := 14.0

var _sprite: Sprite2D
var _stun_flash: ColorRect
var _sheets: Dictionary = {}

# ---------------------------------------------------------------------------
# Выход/посадка в бурмобиль на поверхности (art/character/rig_exit.png +
# .json, см. tools/import_rig_exit.py). Свой, отдельный от DIG_SHEETS/
# SHEET_FRAME выше — те листы и фазы копки правит параллельно другой агент,
# и общий кусок кода между двумя задачами усложнил бы слияние. Всё моё живёт
# в этом блоке и в _draw_rig_transition().
# ---------------------------------------------------------------------------
const RIG_EXIT_SHEET_PATH := "res://art/character/rig_exit.png"
const RIG_EXIT_META_PATH := "res://art/character/rig_exit.json"
const RIG_EXIT_FRAMES := 7
## Резерв на случай отсутствия JSON (тесты без art/) — тот же кадр, что
## печатает tools/import_rig_exit.py по факту листа сейчас.
const RIG_EXIT_GROUND_Y_FALLBACK := 150

var _rig_exit_sheet: Texture2D = null
var _rig_exit_ground_y: int = RIG_EXIT_GROUND_Y_FALLBACK

## Уровень снаряжения, выставленный снаружи. -1 значит «не выставляли» — тогда
## уровень спрашивается у самого героя, см. _flight_tier().
var _tier_override: int = -1

## Состояние машины фаз копки (см. DIG_PHASES и _dig_frame).
var _dig_phase: String = "none"        # "none" | "start" | "loop" | "end"
var _dig_phase_t0: float = 0.0         # player.anim в момент начала текущей фазы
var _dig_was_active: bool = false      # player.digging != null на прошлом кадре
var _dig_last_end_msec: float = -1e9   # когда копка в прошлый раз закончилась
var _dig_last_base: String = ""        # набор, который доигрывает фазу "end"
var _dig_last_sheet_name: String = ""  # лист (с суффиксом направления) для "end"

# ---------------------------------------------------------------------------
# Прыжок и полёт бурмобиля (art/character/rig_jump.png + rig_fly.png, см.
# tools/import_rig_jump_fly.py) — вертикальное перемещение машины: отдельная
# система от DIG_PHASES (копка вбок/вниз — там же владелец задачи «Раскопки»
# держит другой агент, эту таблицу не трогаем) и от rig_transition
# (выход/посадка на поверхности — тоже чужая зона, см. блок выше). Приоритет
# в _process: копка > rig_transition > это > статичный кадр — оба «чужих»
# состояния перехватывают отрисовку РАНЬШЕ (см. ранний return для
# rig_transition и dig.has("sheet_name") в _process), эта система работает
# только когда игрок в машине, не копает и не садится/высаживается.
#
# rig_jump.png (кадры 1-8 листа, индексы 0-7): бур втягивается — играется
# ВПЕРЁД (0..7) при толчке от земли вверх (баллистический прыжок, без тяги)
# и НАЗАД (7..0) при приземлении — то же самое движение в обратном порядке,
# ровно как попросил владелец.
# rig_fly.png (кадры 9-16 листа, индексы 0-7): розжиг и полный ход турбины —
# START (0..5) один раз при начале тяги, затем LOOP (6,7) по кругу, пока тяга
# держится, затем STOP (5..0) один раз, когда тяга кончилась.
const RIG_JUMP_SHEET := "rig_jump"
const RIG_FLY_SHEET := "rig_fly"
const RIG_JUMP_UP := [0, 1, 2, 3, 4, 5, 6, 7]
const RIG_JUMP_DOWN := [7, 6, 5, 4, 3, 2, 1, 0]
const RIG_FLY_START := [0, 1, 2, 3, 4, 5]
const RIG_FLY_LOOP := [6, 7]
const RIG_FLY_STOP := [5, 4, 3, 2, 1, 0]
## Статичный кадр бурмобиля на поверхности вне копки/прыжка/полёта — последний
## кадр rig_jump.png, бур полностью втянут, обтекаемый закрытый корпус.
## Показывается вместо dig_rig_side (тот кадр 0 — бур торчит, поза "готов
## бурить", уместна только под землёй, см. _process) — решение владельца:
## после приземления/остановки полёта машина должна быть закрытой, пока не
## началась копка.
const RIG_CLOSED_FRAME := 7

var _rig_move_phase: String = "none"   # "none"|"jump_up"|"jump_down"|"fly_start"|"fly_loop"|"fly_stop"
var _rig_move_t0: float = 0.0          # player.anim в момент начала текущей фазы
var _rig_was_on_ground: bool = true    # player.on_ground на прошлом кадре — для edge-детекции
var _rig_was_thrust: bool = false      # (player.thrust != "") на прошлом кадре

# ---------------------------------------------------------------------------
# Апгрейд бура (задача «Апгрейд бура»): титан/платина/алмаз/обсидиан — тот же
# бур, перекрашенный tools/rig_drill_recolor.py в цвет соответствующей кирки
# (см. его докстринг). Индекс — GameState.drill_rig_tier (0 = обычный серый
# бур, апгрейда нет). Листы РАЗНЫЕ ФАЙЛЫ (dig_rig_down_titanium.png и т.п.),
# не перекраска на лету: так дешевле по кадру и не плывёт при повторной
# перекраске на разных платформах.
#
# rig_fly.png СЮДА НЕ ВХОДИТ: бур не виден ни в одном её кадре (см. докстринг
# rig_drill_recolor.py) — перекрашенных вариантов для него нет и подставлять
# нечего, RIG_FLY_SHEET всегда берёт базовый лист.
# ---------------------------------------------------------------------------
const RIG_TIER_SUFFIX := ["", "_titanium", "_platinum", "_diamond", "_obsidian"]
const RIG_RECOLOR_SHEETS := ["dig_rig_down", "dig_rig_side", "rig_jump"]


func _ready() -> void:
	_setup_nodes()
	for sheet: String in DIG_SHEETS:
		var path: String = "res://art/character/" + sheet + ".png"
		if ResourceLoader.exists(path):
			_sheets[sheet] = load(path)
		if RIG_RECOLOR_SHEETS.has(sheet):
			for suffix: String in RIG_TIER_SUFFIX:
				if suffix.is_empty():
					continue
				var tiered_path: String = "res://art/character/" + sheet + suffix + ".png"
				if ResourceLoader.exists(tiered_path):
					_sheets[sheet + suffix] = load(tiered_path)
	_load_rig_exit_sheet()
	_hp_prev = GameState.hp
	_connect_signals()


## Суффикс перекрашенного варианта бура по текущей ступени апгрейда — одна
## точка, которую читают все места ниже, где имя листа начинается с
## "dig_rig_"/"rig_jump" (см. _tex_for_sheet). "" — обычный серый бур.
func _rig_tier_suffix() -> String:
	var tier: int = clampi(int(GameState.drill_rig_tier), 0, RIG_TIER_SUFFIX.size() - 1)
	return RIG_TIER_SUFFIX[tier]


## Текстура листа по имени, с подстановкой перекрашенного варианта бура, если
## это один из RIG_RECOLOR_SHEETS и нужный тир вообще нарезан (см. _ready).
## Единственная точка, где имя листа превращается в реальную Texture2D —
## поэтому геометрия (SHEET_FRAME) и фазы (DIG_PHASES) по-прежнему считаются
## по БАЗОВОМУ имени листа (dig_rig_side, а не dig_rig_side_titanium): у
## перекрашенных вариантов та же ширина/высота кадра и те же фазы, отдельной
## записи под суффиксом им заводить незачем.
func _tex_for_sheet(name: String) -> Texture2D:
	if RIG_RECOLOR_SHEETS.has(name):
		var suffix := _rig_tier_suffix()
		if not suffix.is_empty() and _sheets.has(name + suffix):
			return _sheets[name + suffix]
	return _sheets.get(name)


## Общее имя набора копки по текущему инструменту, БЕЗ суффикса направления
## («вниз»/«вбок») — см. _dig_sheet_name и DIG_PHASES, где по этому имени
## ищется таблица фаз анимации.
func _dig_tool_base() -> String:
	match GameState.current_tool:
		"shovel": return "dig_shovel"
		"rusty_pickaxe": return "dig_pick_rusty"
		"hand_drill": return "dig_drill"
		"drill_rig": return "dig_rig"
		_: return "dig_pick"


## Имя листа копки по инструменту и направлению. Направление берём из самой
## копаемой клетки: она либо прямо под героем, либо сбоку. У кирки и лопаты
## нарисован один набор на оба направления — тогда суффикса просто нет.
func _dig_sheet_name() -> String:
	var base: String = _dig_tool_base()
	var dir: String = "_down" if int(player.digging.y) == player.cell_y() + 1 else "_side"
	return base + dir if _sheets.has(base + dir) else base


## Задать уровень летающего снаряжения извне: 0 — снаряжения нет, 1..4 —
## уровни из магазина. Нужно и для теста, и для витрины: там герой показан в
## полёте на снаряжении, которого у него ещё нет.
func set_flight_tier(tier: int) -> void:
	_tier_override = clampi(tier, 0, FLY_SHEETS.size())


## Уровень снаряжения героя.
##
## Снаряжение переписывается в линейку из четырёх уровней, и новый метод
## flight_tier() у героя может появиться уже после этого файла. Пока его нет,
## уровень собирается из старых has_jetpack()/has_backpack(): джетпак это
## третий уровень линейки, ранец — первый. Ни того, ни другого — ноль.
func _flight_tier() -> int:
	if _tier_override >= 0:
		return _tier_override
	if player == null:
		return 0
	if player.has_method("flight_tier"):
		return clampi(int(player.flight_tier()), 0, FLY_SHEETS.size())
	if player.has_method("has_jetpack") and player.has_jetpack():
		return 3
	if player.has_method("has_backpack") and player.has_backpack():
		return 1
	return 0


## Имя ленты полёта. Новые ленты по уровням, а если их в сборке нет — старые
## fly/fly_jet, а если и тех нет — падение: герой всё равно в воздухе. Кадр из
## листа, которого нет, рисовать нечем, и лучше показать не тот полёт, чем
## уронить отрисовку.
func _fly_sheet_name() -> String:
	var tier: int = _flight_tier()
	var names: Array = []
	if tier > 0:
		names.append(FLY_SHEETS[tier - 1])
	names.append("fly_jet" if tier >= 3 else "fly")
	names.append("fall")
	for name: String in names:
		if _sheets.has(name):
			return name
	return String(names[0])


## Фаза и кадр анимации копки — см. DIG_PHASES. Вызывается КАЖДЫЙ кадр, даже
## когда копки нет: так отслеживается, не доигрывает ли лист копки фазу
## "end" (герой ещё доигрывает финиш удара, хотя сама копка уже кончилась).
##
## Возвращает {} — копки не видно, обычная стойка/ходьба/полёт. Иначе —
## {"sheet_name": ..., "frame": ...}, где frame < 0 значит «для этого набора
## фаз нет (см. DIG_PHASES) — считай кадр как раньше, циклом по всем кадрам
## листа» (точка расширения для остальных инструментов).
func _dig_frame(digging_active: bool) -> Dictionary:
	var now := float(Time.get_ticks_msec())

	if digging_active and not _dig_was_active:
		# Старт копки. Если предыдущая копка закончилась только что (та же
		# машина сразу бурит следующую клетку) — без повторного старта, сразу
		# в цикл; иначе — полный заход со старта (см. DIG_PHASE_RESTART_GAP_MS).
		_dig_phase = "loop" if (now - _dig_last_end_msec) <= DIG_PHASE_RESTART_GAP_MS \
				else "start"
		_dig_phase_t0 = player.anim
	elif not digging_active and _dig_was_active:
		# Конец копки: доигрываем "end", если он есть для этого набора.
		_dig_last_end_msec = now
		_dig_phase = "end" if DIG_PHASES.has(_dig_last_base) else "none"
		_dig_phase_t0 = player.anim
	_dig_was_active = digging_active

	if digging_active:
		_dig_last_base = _dig_tool_base()
		_dig_last_sheet_name = _dig_sheet_name()
	elif _dig_phase != "end":
		return {}   # копки не видно — ни самой копки, ни доигрывания финиша

	var base: String = _dig_last_base
	var sheet_name: String = _dig_last_sheet_name
	var phases: Dictionary = DIG_PHASES.get(base, {})
	if phases.is_empty():
		if not digging_active:
			return {}   # доигрывать нечего — фаз для этого набора вовсе нет
		return {"sheet_name": sheet_name, "frame": -1}

	var anim_div: float = SHEET_ANIM_DIV.get(sheet_name, ANIM_DIV)
	var frames: Array = phases.get(_dig_phase, [])
	var idx: int = int(floor((player.anim - _dig_phase_t0) / anim_div)) if anim_div > 0.0 else 0

	if _dig_phase == "start" and idx >= frames.size():
		# Старт доигран — без паузы дальше в цикл.
		_dig_phase = "loop"
		_dig_phase_t0 = player.anim
		idx = 0
		frames = phases.get(_dig_phase, [])
	elif _dig_phase == "end" and idx >= frames.size():
		# Финиш доигран — дальше обычная стойка/ходьба.
		_dig_phase = "none"
		return {}

	if frames.is_empty():
		return {"sheet_name": sheet_name, "frame": -1}

	var frame_i: int
	if _dig_phase == "loop":
		frame_i = int(frames[idx % frames.size()])
	else:
		frame_i = int(frames[clampi(idx, 0, frames.size() - 1)])
	return {"sheet_name": sheet_name, "frame": frame_i}


## Фаза и кадр прыжка/полёта бурмобиля — см. блок объявлений выше. Вызывается
## КАЖДЫЙ кадр (как и _dig_frame), даже когда игрок не в машине: так
## _rig_was_on_ground/_rig_was_thrust остаются свежими, и edge-детекция
## (оттолкнулся/приземлился/включил-выключил тягу) не путает старое
## состояние с новым, когда игрок садится в машину или вылезает из неё.
##
## Возвращает {} — играть нечего, обычный статичный кадр (см. _process).
## Иначе — {"sheet_name": ..., "frame": ...}, 0-based индекс внутри листа.
func _rig_move_frame() -> Dictionary:
	if not (player.has_method("is_in_rig") and player.is_in_rig()):
		_rig_move_phase = "none"
		_rig_was_on_ground = true
		_rig_was_thrust = false
		return {}

	var on_ground: bool = player.on_ground
	var thrusting: bool = player.thrust != ""
	# Приземление — сильнее всего остального: даже если фаза сейчас
	# fly_stop/jump_up, касание земли обязано показать посадку заново (см.
	# решение владельца: "приземление... после прыжка ИЛИ полёта" — общий
	# случай для обоих путей в воздух).
	var landed_now: bool = (not _rig_was_on_ground) and on_ground
	# Прыжок — именно толчок вверх (vy < 0), а не "сошёл с края платформы"
	# (там vy стартует от нуля и только потом растёт под тяготением) — и
	# только без тяги: тяга сразу после толчка физикой запрещена
	# (JUMP_TO_FLY_MS/vy>=0 в player.gd), так что thrusting здесь всегда
	# false в момент самого толчка.
	var jumped_now: bool = _rig_was_on_ground and not on_ground and not thrusting and player.vy < 0.0
	var thrust_started: bool = thrusting and not _rig_was_thrust
	var thrust_stopped: bool = (not thrusting) and _rig_was_thrust and not on_ground

	if landed_now:
		_rig_move_phase = "jump_down"
		_rig_move_t0 = player.anim
	elif jumped_now:
		_rig_move_phase = "jump_up"
		_rig_move_t0 = player.anim
	elif thrust_started:
		_rig_move_phase = "fly_start"
		_rig_move_t0 = player.anim
	elif thrust_stopped:
		_rig_move_phase = "fly_stop"
		_rig_move_t0 = player.anim

	_rig_was_on_ground = on_ground
	_rig_was_thrust = thrusting

	if _rig_move_phase == "none":
		return {}

	# "closed" — доигранные jump_up/jump_down/fly_stop оседают сюда: машина
	# закрыта (кадр 8 rig_jump.png), пока не начнётся новый прыжок/полёт,
	# копка (выше по приоритету, см. _process) или спуск под землю. Отдаём
	# кадр ТОЛЬКО на поверхности (player.cell_y() < 1) — под землёй эта фаза
	# не должна перебивать статичный dig_rig_side/копку (см. _process, у
	# in_rig_underground приоритет ниже rig_move, поэтому здесь отступаем
	# сами, а не полагаемся на порядок веток).
	var closed_frame: Dictionary = {} if player.cell_y() >= 1 \
			else {"sheet_name": RIG_JUMP_SHEET, "frame": RIG_CLOSED_FRAME}
	if _rig_move_phase == "closed":
		return closed_frame

	var anim_div: float = SHEET_ANIM_DIV.get(RIG_JUMP_SHEET, ANIM_DIV)
	var idx: int = int(floor((player.anim - _rig_move_t0) / anim_div)) if anim_div > 0.0 else 0

	match _rig_move_phase:
		"jump_up":
			if idx >= RIG_JUMP_UP.size():
				# Апекс доигран раньше, чем машина легла на пик прыжка, или
				# сам прыжок короче анимации — держим закрытый кадр (тот же,
				# чем кончается сама анимация втягивания) до приземления.
				_rig_move_phase = "closed"
				return closed_frame
			return {"sheet_name": RIG_JUMP_SHEET, "frame": RIG_JUMP_UP[idx]}
		"jump_down":
			if idx >= RIG_JUMP_DOWN.size():
				_rig_move_phase = "closed"
				return closed_frame
			return {"sheet_name": RIG_JUMP_SHEET, "frame": RIG_JUMP_DOWN[idx]}
		"fly_start":
			if idx >= RIG_FLY_START.size():
				# Старт доигран — без паузы дальше в цикл (тот же приём, что
				# у DIG_PHASES: "start" -> "loop" без задержки).
				_rig_move_phase = "fly_loop"
				_rig_move_t0 = player.anim
				return {"sheet_name": RIG_FLY_SHEET, "frame": RIG_FLY_LOOP[0]}
			return {"sheet_name": RIG_FLY_SHEET, "frame": RIG_FLY_START[idx]}
		"fly_loop":
			return {"sheet_name": RIG_FLY_SHEET, "frame": RIG_FLY_LOOP[idx % RIG_FLY_LOOP.size()]}
		"fly_stop":
			if idx >= RIG_FLY_STOP.size():
				_rig_move_phase = "closed"
				return closed_frame
			return {"sheet_name": RIG_FLY_SHEET, "frame": RIG_FLY_STOP[idx]}
	return {}


# ---------------------------------------------------------------------------
# Слой движения (ветка «hero-anim»). Рисунки героя — авторские, и менять их
# мы не можем; зато можем менять ВРЕМЯ и ПОЛОЖЕНИЕ рисунка: шаг считается по
# пройденному пути (ноги не скользят и не семенят на месте), корпус
# наклоняется, приседает и вытягивается на пружине (HeroAnim.Spring), замах
# при копке привязан к ударам из JuiceDirector, смена листа смешивается, а не
# щёлкает. Всё применяется к узлу _body с осью в подошве: так голова остаётся
# над ногами, а не «плывёт» (ГДД §15.1).
# ---------------------------------------------------------------------------

## Листы поз и их кадры (tools/gen_hero_anim.py). Нет листа — кадры fall.png.
const JUMP_FRAMES := {"crouch": 0, "launch": 1, "rise": 2, "apex": 3,
		"fall": 4, "fall_fast": 5, "recover": 6, "apex_b": 7, "rise_lo": 8}
const FALL_FALLBACK := {"crouch": 0, "launch": 1, "rise": 1, "apex": 2,
		"fall": 2, "fall_fast": 2, "recover": 3, "apex_b": 1, "rise_lo": 1}
const IDLE_X := {"blink": 0, "look_a": 1, "look_b": 2, "tap_a": 3, "tap_b": 4}
const HURT_FRAMES := {"flinch": 0, "ko": 1}

## Ленты полёта: спутники у fly_1/fly_2 — розжиг винта один раз, потом цикл.
const FLY_START := {"fly_1": [0, 1, 2], "fly_2": [0, 1, 2]}
const FLY_LOOP := {"fly_1": [3, 4, 5], "fly_2": [3, 4, 5],
		"fly_3": [0, 1, 2, 3, 4, 5], "fly_4": [0, 1, 2, 3, 4, 5]}
## Сопло джетпака относительно подошвы (логические точки, герой смотрит вправо).
const JET_NOZZLE := {"fly_3": Vector2(-14.0, -3.0), "fly_4": Vector2(-24.0, -9.0)}

## Скорость ходьбы из player.gd — нужна как масштаб наклона.
const WALK_REF := 4.2

## Линейный фильтр вместо ближайшего: спрайт теперь наклоняется и сжимается, а на
## ближайшем соседе косой край рвётся в лесенку.
const SMOOTH_FILTER := true
const FOOT_Y := -HH * TILE - 16.0 + float(GROUND_Y) / ART_SCALE

signal footstep(world_pos: Vector2)

var _body: Node2D
var _ghost: Sprite2D
var _ghost_left: float = 0.0
var _last_shake: float = 0.0
var _cur_key: String = ""
var _t: float = 0.0

var _have_prev: bool = false
var _prev_x: float = 0.0
var _prev_y: float = 0.0
var _vx_s: float = 0.0            # сглаженная скорость по оси X, клеток/с
var _ax_s: float = 0.0            # её производная — разгон и торможение
var _prev_vy: float = 0.0
var _air_t: float = 0.0
var _was_air: bool = false
var _land_t: float = 0.0
var _land_hard: bool = false

var _sq := HeroAnim.Spring.new(5.2, 0.32)       # >0 — сжатие, <0 — растяжение
var _lean := HeroAnim.Spring.new(3.0, 0.7)      # наклон корпуса, рад (вперёд — плюс)
var _drag := HeroAnim.Spring.new(4.0, 0.45)     # перекос: верх отстаёт при разгоне
var _kick := HeroAnim.Spring.new(7.0, 0.5)      # толчок корпуса вперёд, точки

var _stride: float = 0.0
var _walk_active: bool = false
var _last_idx: int = 0

var _idle_t: float = 0.0
var _idle_act: String = ""
var _idle_act_t: float = 0.0
var _next_blink: float = 3.0
var _next_extra: float = 0.0
var _rng := RandomNumberGenerator.new()

var _face_target: int = 1
var _face_drawn: int = 1
var _turn_t: float = -1.0

var _dig_state: String = ""          # "" | "active" | "follow"
var _dig_dp: float = 0.0
var _dig_cached_sheet: String = ""
var _dig_cached_base: String = ""
var _drill_t: float = 0.0

var _fly_t: float = 0.0
var _fly_on: bool = false
var _fly_sheet_last: String = ""
var _spin_down_t: float = 0.0
var _jet: CPUParticles2D = null

var _hurt_t: float = 0.0
var _hurt_pose_t: float = 0.0
var _hp_prev: float = -1.0
var _death_t: float = -1.0
var _death_bounced: bool = false
var _getup_t: float = -1.0
var _flash: Color = Color(1, 1, 1, 1)


func _connect_signals() -> void:
	if player != null and player.has_signal("jumped") and not player.jumped.is_connected(_on_jumped):
		player.jumped.connect(_on_jumped)
	if not GameState.hp_changed.is_connected(_on_hp_changed):
		GameState.hp_changed.connect(_on_hp_changed)
	if not GameState.died.is_connected(on_died):
		GameState.died.connect(on_died)
	if not GameState.respawned.is_connected(on_respawned):
		GameState.respawned.connect(on_respawned)


func _setup_nodes() -> void:
	_body = Node2D.new()
	_body.name = "Body"
	_body.position = Vector2(0.0, FOOT_Y)
	add_child(_body)
	_ghost = Sprite2D.new()
	_ghost.centered = false
	_ghost.region_enabled = true
	_ghost.scale = Vector2(1.0 / ART_SCALE, 1.0 / ART_SCALE)
	_ghost.visible = false
	_body.add_child(_ghost)
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.scale = Vector2(1.0 / ART_SCALE, 1.0 / ART_SCALE)
	_body.add_child(_sprite)
	if SMOOTH_FILTER:
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_rng.randomize()
	_next_blink = _rng.randf_range(HeroAnim.num("idle.blink_min_s", 2.4), HeroAnim.num("idle.blink_max_s", 5.2))


## Сброс накопленного движения: телепорт, смена сцены, начало сценария в тесте.
func _reset_motion() -> void:
	_have_prev = false
	_vx_s = 0.0
	_ax_s = 0.0
	_air_t = 0.0
	_was_air = false
	_land_t = 0.0
	_walk_active = false
	_idle_t = 0.0
	_idle_act = ""
	_dig_state = ""
	_fly_on = false
	_spin_down_t = 0.0
	_hurt_t = 0.0
	_hurt_pose_t = 0.0
	_death_t = -1.0
	_getup_t = -1.0
	_turn_t = -1.0
	_sq.reset()
	_lean.reset()
	_drag.reset()
	_kick.reset()
	if _body != null:
		_pose_rest()


func _feet_world() -> Vector2:
	return Vector2(player.x, player.y + 0.33) * float(TILE)


# ---------------------------------------------------------------------------
# Измерение движения
# ---------------------------------------------------------------------------

func _sample_motion(dt: float) -> void:
	var dx: float = player.x - _prev_x
	var dy: float = player.y - _prev_y
	_prev_x = player.x
	_prev_y = player.y
	if not _have_prev or absf(dx) > 3.0 or absf(dy) > 3.0:
		# Первый кадр или телепорт — скорости неоткуда взяться.
		_have_prev = true
		_vx_s = 0.0
		_ax_s = 0.0
		_face_target = player.facing if player.facing != 0 else 1
		_face_drawn = _face_target
		_turn_t = -1.0
		return
	if dt <= 0.0:
		_vx_s = float(player.vx)
		return
	var new_v: float = HeroAnim.damp(_vx_s, dx / dt, 18.0, dt)
	_ax_s = HeroAnim.damp(_ax_s, (new_v - _vx_s) / dt, 14.0, dt)
	_vx_s = new_v


## Воздух с «койот-временем»: шаг с кромки на один кадр не меняет лист.
func _update_air(dt: float) -> bool:
	var grounded: bool = bool(player.on_ground)
	var thrusting: bool = String(player.thrust) != ""
	if grounded:
		_air_t = 0.0
	else:
		_air_t += dt
	var coyote: float = HeroAnim.num("air.coyote_s", 0.07)
	var air: bool = (not grounded) and (_air_t > coyote or float(player.vy) < -0.5 or thrusting)
	if _was_air and not air and grounded:
		_on_landed(absf(_prev_vy))
	_was_air = air
	_prev_vy = float(player.vy)
	return air


func _on_landed(impact: float) -> void:
	var lo: float = HeroAnim.num("air.land_squash_min", 0.07)
	var hi: float = HeroAnim.num("air.land_squash_max", 0.26)
	var k: float = clampf((impact - 2.0) / 20.0, 0.0, 1.0)
	var amp: float = HeroAnim.motion_scale(Settings.reduce_motion)
	_sq.zeta = 0.32
	_sq.x = lerpf(lo, hi, k) * amp
	_sq.v = 0.0
	_sq.target = 0.0
	_land_hard = impact > 11.0
	_land_t = HeroAnim.num("air.land_pose_s", 0.16) * (1.0 if _land_hard else 0.75)
	if impact > 5.0:
		Fx.burst("poof", _feet_world(), 0.25 + 0.5 * k)


func _on_jumped() -> void:
	var amp: float = HeroAnim.motion_scale(Settings.reduce_motion)
	_sq.zeta = 0.55
	_sq.x = -HeroAnim.num("air.takeoff_stretch", 0.16) * amp
	_sq.v = 0.0
	_land_t = 0.0
	if String(player.thrust) == "":
		Fx.burst("poof", _feet_world(), 0.35)


# ---------------------------------------------------------------------------
# Копка кирки, лопаты и ручного бура (листы без фаз в DIG_PHASES)
# ---------------------------------------------------------------------------

func _frames_in(sheet_name: String) -> int:
	var geom: Array = SHEET_FRAME.get(sheet_name, [CHAR_W, CHAR_H, GROUND_Y])
	var tex: Texture2D = _tex_for_sheet(sheet_name)
	if tex == null:
		return 1
	return maxi(1, int(round(tex.get_width() / float(geom[0]))))


## Замах — удар — упор — отдача. Фаза цикла привязана к времени копки клетки
## (digging.t), а кадр удара приходится на те же моменты, в которые
## JuiceDirector играет звук и пыль удара. После конца копки замах не обрывается,
## а доигрывается до «готов» (последний кадр) — иначе рука дёргается в стойку.
func _hero_dig(sheet_name: String, active: bool, dt: float) -> Dictionary:
	if active:
		_dig_cached_sheet = sheet_name
		_dig_cached_base = _dig_tool_base()
	elif _dig_state != "follow" and _dig_state != "active":
		return {}
	var base: String = _dig_cached_base
	var sheet: String = _dig_cached_sheet
	var frames: int = _frames_in(sheet)

	if base == "dig_drill":
		if not active:
			_dig_state = ""
			return {}
		_dig_state = "active"
		_drill_t += dt
		return {"sheet_name": sheet, "frame": int(_drill_t * HeroAnim.num("dig.drill_fps", 24.0)) % frames}

	var key: String = "dig.shovel" if base == "dig_shovel" else "dig.pick"
	var weights: Array = HeroAnim.nums(key + ".weights", [1, 1, 1, 1, 1, 1, 1, 1])
	var impact_i: int = int(HeroAnim.num(key + ".impact", 3.0))
	var imp_phase: float = HeroAnim.phase_mid(weights, impact_i)
	var period: float = Juice.num("dig.hit_period_s", 0.38)

	if active:
		var tt: float = float(player.digging.get("t", 0.0))
		var target: float = HeroAnim.dig_target_phase(tt, period, imp_phase)
		var prev_dp: float = _dig_dp
		if _dig_state == "":
			_dig_dp = target
		else:
			_dig_dp = HeroAnim.chase_phase(_dig_dp, target, dt, period,
					HeroAnim.num("dig.pll_gain", 6.0))
		_dig_state = "active"
		_check_impact(prev_dp, imp_phase)
	else:
		_dig_state = "follow"
		var ready: float = HeroAnim.phase_start(weights, weights.size() - 1)
		if _dig_dp >= ready:
			_dig_state = ""
			return {}
		var prev_dp2: float = _dig_dp
		_dig_dp = minf(_dig_dp + dt / period * HeroAnim.num("dig.follow_speedup", 2.2), ready)
		_check_impact(prev_dp2, imp_phase)
		if _dig_dp >= ready:
			_dig_state = ""
			return {}
	return {"sheet_name": sheet, "frame": mini(HeroAnim.phase_frame(weights, _dig_dp), frames - 1)}


func _check_impact(prev_dp: float, imp_phase: float) -> void:
	var moved: float = fposmod(_dig_dp - prev_dp, 1.0)
	if moved <= 0.0 or moved > 0.5:
		return
	var d: float = fposmod(imp_phase - prev_dp, 1.0)
	if d <= 0.0 or d > moved:
		return
	var amp: float = HeroAnim.motion_scale(Settings.reduce_motion)
	_kick.x = HeroAnim.num("dig.kick_px", 1.0) * amp
	_kick.v = 0.0
	_sq.zeta = 0.32
	_sq.x = maxf(_sq.x, HeroAnim.num("dig.kick_squash", 0.045) * amp)


# ---------------------------------------------------------------------------
# Воздух: прыжок, падение, полёт
# ---------------------------------------------------------------------------

func _jump_frame(pose: String) -> Dictionary:
	if _sheets.has("jump"):
		return {"sheet_name": "jump", "frame": int(JUMP_FRAMES[pose])}
	return {"sheet_name": "fall", "frame": int(FALL_FALLBACK[pose])}


func _air_pose() -> Dictionary:
	var vy: float = float(player.vy)
	var pose: String
	if vy < -5.5:
		pose = "launch"
	elif vy < -3.2:
		pose = "rise_lo"
	elif vy < -1.4:
		pose = "rise"
	elif vy <= 1.6:
		# Зависание: два такта поз чередуются, герой не стоит истуканом.
		pose = "apex" if int(_t * 5.5) % 2 == 0 else "apex_b"
	elif vy <= 5.0:
		pose = "fall"
	else:
		pose = "fall_fast"
	return _jump_frame(pose)


func _fly_frame(sheet_name: String, dt: float) -> int:
	if not _fly_on:
		_fly_on = true
		_fly_t = 0.0
	_fly_t += dt
	_spin_down_t = 0.0
	_fly_sheet_last = sheet_name
	var frames: int = _frames_in(sheet_name)
	var is_prop: bool = String(player.thrust) == "prop"
	var start: Array = FLY_START.get(sheet_name, [])
	var loop: Array = FLY_LOOP.get(sheet_name, [])
	if loop.is_empty():
		return int(_fly_t * 16.0) % frames
	var step: float = HeroAnim.num("fly.prop_start_frame_s", 0.055)
	if _fly_t < step * float(start.size()):
		return mini(int(start[int(_fly_t / step)]), frames - 1)
	var fps: float = HeroAnim.num("fly.prop_loop_fps" if is_prop else "fly.jet_loop_fps", 18.0)
	var li: int = int((_fly_t - step * float(start.size())) * fps)
	return mini(int(loop[li % loop.size()]), frames - 1)


## Винт доворачивается после выключения тяги, а не пропадает в кадре.
func _spin_down_frame(dt: float) -> Dictionary:
	_spin_down_t -= dt
	var start: Array = FLY_START.get(_fly_sheet_last, [])
	if start.is_empty() or _spin_down_t <= 0.0:
		return {}
	var i: int = clampi(int((1.0 - _spin_down_t / 0.18) * float(start.size())), 0, start.size() - 1)
	return {"sheet_name": _fly_sheet_last, "frame": int(start[start.size() - 1 - i])}


func _tick_jet(dt: float, sheet_name: String, f: int) -> void:
	var on: bool = _fly_on and String(player.thrust) == "jet" and JET_NOZZLE.has(sheet_name)
	if _jet == null:
		if not on:
			return
		_jet = CPUParticles2D.new()
		_jet.name = "JetSparks"
		_jet.local_coords = false
		_jet.amount = 14
		_jet.lifetime = 0.36
		_jet.explosiveness = 0.0
		_jet.direction = Vector2(0, 1)
		_jet.spread = 22.0
		_jet.gravity = Vector2(0, 40)
		_jet.initial_velocity_min = 38.0
		_jet.initial_velocity_max = 78.0
		_jet.scale_amount_min = 1.2
		_jet.scale_amount_max = 2.4
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 0.92, 0.55, 0.95))
		ramp.add_point(0.45, Color(1.0, 0.55, 0.18, 0.8))
		ramp.set_color(1, Color(0.6, 0.15, 0.05, 0.0))
		_jet.color_ramp = ramp
		_jet.z_index = -1
		add_child(_jet)
	_jet.emitting = on
	if on:
		var n: Vector2 = JET_NOZZLE[sheet_name]
		_jet.position = Vector2(n.x * float(f), FOOT_Y + n.y)
		_jet.direction = Vector2(-0.35 * float(f), 1.0).normalized()


# ---------------------------------------------------------------------------
# Реакции: урон, смерть, возрождение
# ---------------------------------------------------------------------------

func _on_hp_changed(hp: float, _max_hp: float) -> void:
	var prev: float = _hp_prev
	_hp_prev = hp
	if prev < 0.0 or hp <= 0.0 or _death_t >= 0.0:
		return
	if prev - hp >= 1.5 and _hurt_t <= 0.05:
		on_hurt(prev - hp, -_face_drawn)


## Удар: корпус отбрасывает от источника (dir — куда), кадр «ой», красная вспышка.
func on_hurt(dmg: float, _dir: int = 0) -> void:
	var amp: float = HeroAnim.motion_scale(Settings.reduce_motion)
	var share: float = clampf(dmg / 25.0, 0.3, 1.0)
	_hurt_t = HeroAnim.num("hurt.duration_s", 0.42)
	_hurt_pose_t = HeroAnim.num("hurt.pose_s", 0.2)
	_lean.v = -deg_to_rad(HeroAnim.num("hurt.recoil_deg", 14.0)) * 18.0 * share * amp
	_sq.zeta = 0.3
	_sq.x = 0.1 * share * amp
	_kick.x = -1.6 * share * amp
	_kick.v = 0.0
	_turn_t = -1.0


func on_died() -> void:
	_death_t = 0.0
	_death_bounced = false
	_hurt_pose_t = 0.0
	_sq.zeta = 0.3
	_sq.x = 0.12


func on_respawned() -> void:
	if _death_t >= 0.0:
		_death_t = -1.0
		_getup_t = 0.0
		Fx.burst("heal", _feet_world() + Vector2(0, -20), 0.8)


## Идёт ли сейчас показ смерти. main.gd откладывает возрождение, пока он идёт.
## Без окна (headless) и в скрытом состоянии смотреть некому — не ждём.
func death_playing() -> bool:
	if _death_t < 0.0 or not is_visible_in_tree():
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return _death_t < HeroAnim.num("death.total_s", 1.2)


func _tick_reactions(dt: float) -> void:
	_hurt_t = maxf(0.0, _hurt_t - dt)
	_hurt_pose_t = maxf(0.0, _hurt_pose_t - dt)
	if _death_t >= 0.0:
		_death_t += dt
	if _getup_t >= 0.0:
		_getup_t += dt
		if _getup_t > 0.5:
			_getup_t = -1.0
	_land_t = maxf(0.0, _land_t - dt)
	# Красная вспышка гаснет вместе с «ой».
	var duration: float = maxf(HeroAnim.num("hurt.duration_s", 0.42), 0.01)
	var k: float = clampf(_hurt_t / duration, 0.0, 1.0)
	if k > 0.82:
		# Первые кадры удара — белая вспышка, потом красноватый налив.
		_flash = Color(1.9, 1.9, 1.9, 1.0)
	else:
		_flash = Color(1.0, 1.0 - 0.32 * k, 1.0 - 0.32 * k, 1.0)
	if _death_t >= 0.0:
		_flash = Color(1.0, 0.88, 0.88, 1.0)


# ---------------------------------------------------------------------------
# Простой: дыхание, моргание, оглядывание, нетерпение
# ---------------------------------------------------------------------------

func _idle_pose(dt: float) -> Dictionary:
	_idle_t += dt
	var seq := [0, 1, 2, 3, 2, 1]
	var step: float = maxf(HeroAnim.num("idle.breath_frame_s", 0.5), 0.05)
	var frame: int = int(seq[int(_idle_t / step) % seq.size()])
	if not _sheets.has("idle_x"):
		return {"sheet_name": "idle", "frame": frame}

	_next_blink -= dt
	if _idle_act == "":
		var look_after: float = HeroAnim.num("idle.look_after_s", 6.0)
		var tap_after: float = HeroAnim.num("idle.impatient_after_s", 13.0)
		if _idle_t > tap_after and _idle_t >= _next_extra:
			_idle_act = "tap"
			_idle_act_t = 0.0
		elif _idle_t > look_after and _idle_t < tap_after and _idle_t >= _next_extra:
			_idle_act = "look"
			_idle_act_t = 0.0
		elif _next_blink <= 0.0:
			_idle_act = "blink"
			_idle_act_t = 0.0
	if _idle_act != "":
		_idle_act_t += dt
		match _idle_act:
			"blink":
				if _idle_act_t > 0.13:
					_idle_act = ""
					_next_blink = _rng.randf_range(HeroAnim.num("idle.blink_min_s", 2.4),
							HeroAnim.num("idle.blink_max_s", 5.2))
				else:
					return {"sheet_name": "idle_x", "frame": int(IDLE_X["blink"])}
			"look":
				var dur := 2.2
				if _idle_act_t > dur:
					_idle_act = ""
					_next_extra = _idle_t + _rng.randf_range(5.0, 9.0)
				else:
					var ph: float = _idle_act_t / dur
					var look: String = "look_a" if ph < 0.45 else ("look_b" if ph < 0.8 else "")
					if look != "":
						return {"sheet_name": "idle_x", "frame": int(IDLE_X[look])}
			"tap":
				var dur2 := 1.9
				if _idle_act_t > dur2:
					_idle_act = ""
					_next_extra = _idle_t + _rng.randf_range(2.5, 4.5)
				else:
					var tap: String = "tap_a" if int(_idle_act_t * 3.6) % 2 == 0 else "tap_b"
					return {"sheet_name": "idle_x", "frame": int(IDLE_X[tap])}
	return {"sheet_name": "idle", "frame": frame}


# ---------------------------------------------------------------------------
# Главный цикл отрисовки
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return
	var dt: float = clampf(delta, 0.0, 0.05)
	_t += dt
	position = Vector2(player.x * TILE, player.y * TILE)
	_sample_motion(dt)
	_tick_reactions(dt)

	# Выход из бурмобиля на поверхности / посадка в него — свой рисунок поверх
	# всего остального (player.rig_transition != ""), пока анимация не
	# доиграла управление и так заблокировано, см. player.gd). Держит экран,
	# пока не закончится, — обычные ветки ниже (копка/полёт/ходьба) в это
	# время не имеют смысла: герой либо в кабине, либо ещё не встал.
	if String(player.get("rig_transition")) != "":
		_draw_rig_transition()
		_pose_rest()
		return

	# Бурмобиль под землёй — герой ВСЕГДА в кабине (решение владельца, задача
	# «Бурмобиль — транспорт»): никаких листов ходьбы/полёта/падения пешком,
	# пока едет машина. Отдельных кадров простоя у машины под землёй нет —
	# статичный боковой кадр (бур торчит, "готов бурить") как замена. На
	# поверхности статику вне прыжка/полёта отдаёт сам rig_move (фаза
	# "closed", см. _rig_move_frame) — здесь отдельной ветки для этого нет,
	# иначе она перебивала бы обычную стойку/ходьбу ДО того, как герой хоть
	# раз прыгнул или взлетел (см. test_dig_phases.gd: "в машине, стоит на
	# поверхности, никогда не прыгал" — обязана остаться idle-стойкой).
	var in_rig: bool = player.has_method("is_in_rig") and player.is_in_rig()
	var in_rig_underground: bool = in_rig and player.cell_y() >= 1

	var dig: Dictionary = _dig_frame(player.digging != null)
	# Набор без фаз (кирка, лопата, ручной бур): кадр по времени копки клетки.
	if dig.has("sheet_name") and int(dig["frame"]) < 0:
		dig = _hero_dig(String(dig["sheet_name"]), true, dt)
	elif not dig.has("sheet_name"):
		dig = _hero_dig("", false, dt)
	else:
		_dig_state = ""
	# Вызывается КАЖДЫЙ кадр (см. её собственный докстринг) — даже когда
	# сейчас копка/переход выигрывают отрисовку: иначе edge-детекция
	# прыжка/посадки/тяги внутри неё видела бы устаревшее on_ground/thrust.
	var rig_move: Dictionary = _rig_move_frame()
	var air: bool = _update_air(dt)
	var thrusting: bool = String(player.thrust) != ""
	if not (air and thrusting) and _fly_on:
		_fly_on = false
		if not in_rig and _fly_sheet_last != "" and FLY_START.has(_fly_sheet_last):
			_spin_down_t = 0.18

	var sheet_name: String
	var phase_frame: int = -1
	var force_static_frame := false
	var mode := "idle"
	if dig.has("sheet_name"):
		# Для каждого инструмента нарисована своя анимация, а для бура и
		# бурмобиля — ещё и своя на каждое направление копки; фаза (старт /
		# цикл / финиш) — см. _dig_frame и DIG_PHASES.
		sheet_name = dig["sheet_name"]
		phase_frame = dig["frame"]
		mode = "rigdig" if in_rig else "dig"
	elif rig_move.has("sheet_name"):
		# Прыжок/приземление/начало-конец полёта бурмобиля — см. _rig_move_frame.
		# Приоритет НИЖЕ копки (бур не прыгает во время бурения — физически
		# невозможно, но порядок на всякий случай тот же, что просил
		# владелец) и выше статичных кадров ниже.
		sheet_name = rig_move["sheet_name"]
		phase_frame = rig_move["frame"]
		mode = "rigfly"
	elif in_rig_underground:
		sheet_name = "dig_rig_side" if _sheets.has("dig_rig_side") else "dig_pick"
		force_static_frame = true
		mode = "rigdig"
	elif (_hurt_pose_t > 0.0 or _death_t >= 0.0) and _sheets.has("hurt"):
		sheet_name = "hurt"
		phase_frame = int(HURT_FRAMES["ko"]) if (_death_t >= HeroAnim.num("death.topple_s", 0.55) * 0.4) \
				else int(HURT_FRAMES["flinch"])
		mode = "hurt"
	elif air:
		if thrusting:
			# Все четыре уровня снаряжения выглядят по-разному, и по кадру должно
			# быть видно, на чём герой висит: пропеллер, большой винт, джетпак с
			# выхлопом или две ракеты. Тяга при этом своя — она из player.thrust.
			sheet_name = _fly_sheet_name()
			phase_frame = _fly_frame(sheet_name, dt) if FLY_LOOP.has(sheet_name) \
					else -1
			if phase_frame < 0:
				_fly_on = true
			mode = "fly"
		else:
			var spin: Dictionary = _spin_down_frame(dt) if _spin_down_t > 0.0 else {}
			if spin.has("sheet_name"):
				sheet_name = spin["sheet_name"]
				phase_frame = spin["frame"]
				mode = "fly"
			else:
				var pose: Dictionary = _air_pose()
				sheet_name = pose["sheet_name"]
				phase_frame = pose["frame"]
				mode = "air"
	else:
		var pose2: Dictionary = _ground_pose(dt)
		sheet_name = pose2["sheet_name"]
		phase_frame = pose2["frame"]
		mode = pose2["mode"]

	var geom: Array = SHEET_FRAME.get(sheet_name, [CHAR_W, CHAR_H, GROUND_Y])
	var anim_div: float = SHEET_ANIM_DIV.get(sheet_name, ANIM_DIV)
	var fw: int = geom[0]
	var fh: int = geom[1]
	var tex: Texture2D = _tex_for_sheet(sheet_name)

	# Позы прыжка и «ой» меняются скачком кадров, поэтому смешиваем и их.
	var key: String = sheet_name
	if mode == "air" or mode == "hurt":
		key = "%s#%d" % [sheet_name, phase_frame]
	if key != _cur_key:
		if _cur_key != "" and _sprite.texture != null and mode != "rigdig" and mode != "rigfly":
			_start_ghost()
		_cur_key = key

	if tex != null:
		_sprite.texture = tex
		var frames: int = maxi(1, int(round(tex.get_width() / float(fw))))
		var frame: int = phase_frame
		if frame < 0:
			frame = 0 if force_static_frame else \
					(int(floor(player.anim / anim_div)) % frames if frames > 1 else 0)
		_sprite.region_rect = Rect2(frame * fw, 0, fw, fh)

	# Разворот: при смене направления спрайт на миг сужается, на середине
	# переворачивается и разжимается обратно — вместо мгновенного «щёлк».
	var want_face: int = player.facing if player.facing != 0 else 1
	if want_face != _face_target:
		_face_target = want_face
		if _turn_t < 0.0 and mode != "rigdig" and mode != "rigfly" and not in_rig:
			_turn_t = 0.0
			if player.on_ground and absf(_vx_s) > HeroAnim.num("turn.skid_speed", 0.6) * WALK_REF:
				Fx.burst("poof", _feet_world() + Vector2(float(_face_drawn) * 6.0, 0.0), 0.5)
		else:
			_face_drawn = want_face
	var turn_x := 1.0
	if _turn_t >= 0.0:
		var dur: float = maxf(HeroAnim.num("turn.duration_s", 0.11), 0.02)
		_turn_t += dt
		if _turn_t >= dur * 0.5:
			_face_drawn = _face_target
		if _turn_t >= dur:
			_turn_t = -1.0
		else:
			var sq: float = HeroAnim.num("turn.squeeze", 0.42) * HeroAnim.motion_scale(Settings.reduce_motion)
			turn_x = 1.0 - sq * sin(PI * _turn_t / dur)
	elif not (mode == "rigdig" or mode == "rigfly"):
		_face_drawn = _face_target
	else:
		_face_drawn = want_face
	var f: int = _face_drawn
	_sprite.flip_h = f < 0

	_apply_pose(dt, mode, f, turn_x, sheet_name, fw, geom)
	_tick_jet(dt, sheet_name, f)


## Ставит спрайт относительно оси в подошве и накладывает все движения корпуса.
func _apply_pose(dt: float, mode: String, f: int, turn_x: float, sheet_name: String,
		fw: int, geom: Array) -> void:
	var amp: float = HeroAnim.motion_scale(Settings.reduce_motion)
	var vr: float = clampf(_vx_s * float(f) / WALK_REF, -1.0, 1.0)
	var lean_t := 0.0
	var skew_t := 0.0
	var bob := 0.0
	var breath := 0.0
	var sway := 0.0
	var shake := Vector2.ZERO
	match mode:
		"walk":
			lean_t = deg_to_rad(HeroAnim.num("walk.lean_deg", 3.2)) * vr \
					+ deg_to_rad(HeroAnim.num("walk.accel_lean_deg", 2.6)) \
					* clampf(_ax_s * float(f) / 60.0, -1.0, 1.0)
			skew_t = clampf(_ax_s * float(f) * 0.0008, -0.07, 0.07)
			bob = -HeroAnim.num("walk.bob_px", 1.1) * HeroAnim.step_lift(_stride) * minf(1.0, absf(vr) * 1.3)
		"idle":
			var breathe: float = sin(_t * TAU / 2.7)
			breath = HeroAnim.num("idle.breath_scale", 0.018) * (0.5 + 0.5 * breathe)
			sway = deg_to_rad(HeroAnim.num("idle.sway_deg", 0.7)) * sin(_t * TAU / 7.3)
		"air":
			var tilt: float = deg_to_rad(HeroAnim.num("air.air_tilt_deg", 5.0))
			lean_t = tilt * clampf(_vx_s * float(f) / 3.5, -1.0, 1.0)
			var vy: float = float(player.vy)
			_sq.zeta = 0.55
			_sq.target = -HeroAnim.num("air.fall_stretch", 0.10) * clampf((vy - 5.0) / 24.0, 0.0, 1.0)
		"fly":
			var is_jet: bool = String(player.thrust) == "jet" or sheet_name == "fly_3" or sheet_name == "fly_4"
			var tilt_f: float = deg_to_rad(HeroAnim.num("fly.tilt_deg", 9.0)) * (0.6 if sheet_name == "fly_4" else 1.0)
			lean_t = tilt_f * clampf(_vx_s * float(f) / 3.5, -1.0, 1.0) \
					+ deg_to_rad(HeroAnim.num("fly.tilt_vy_deg", 3.0)) * clampf(float(player.vy) / 6.0, -1.0, 1.0)
			bob = sin(_t * TAU * (2.4 if is_jet else 1.6)) * HeroAnim.num("fly.bob_px", 1.2)
			sway = deg_to_rad(1.1) * sin(_t * TAU * 0.9)
			if is_jet:
				shake = Vector2(sin(_t * 91.0), cos(_t * 77.0)) * 0.35
		"rigdig":
			if player.digging != null:
				var s: float = HeroAnim.num("rig.dig_shake_px", 0.55)
				shake = Vector2(sin(_t * TAU * 37.0) * s, cos(_t * TAU * 29.0) * s * 0.7)
		"rigfly":
			if String(player.thrust) != "":
				var s2: float = HeroAnim.num("rig.fly_shake_px", 0.4)
				shake = Vector2(sin(_t * TAU * 41.0) * s2, cos(_t * TAU * 31.0) * s2)
				lean_t = deg_to_rad(5.0) * clampf(_vx_s * float(f) / 3.5, -1.0, 1.0)
	if mode != "air":
		_sq.target = 0.0
		if mode != "dig":
			_sq.zeta = 0.4

	_lean.target = lean_t * amp
	_lean.step(dt)
	_drag.target = skew_t * amp
	_drag.step(dt)
	_sq.step(dt)
	_kick.step(dt)

	# Смерть и возрождение поверх обычной позы.
	var death_rot := 0.0
	var death_y := 0.0
	var death_x := 0.0
	var alpha := 1.0
	var pop := Vector2.ONE
	if _death_t >= 0.0:
		var topple: float = HeroAnim.num("death.topple_s", 0.55)
		var pre := 0.12
		if _death_t < pre:
			death_rot = -deg_to_rad(10.0) * (_death_t / pre)
		else:
			var u: float = (_death_t - pre) / topple
			var b: float = HeroAnim.ease_out_bounce(u)
			death_rot = -deg_to_rad(10.0) - deg_to_rad(76.0) * b
			death_y = -6.5 * b
			death_x = -3.5 * b
			if u >= 0.36 and not _death_bounced:
				_death_bounced = true
				Fx.burst("poof", _feet_world() + Vector2(float(-f) * 14.0, 0.0), 1.1)
		var total: float = HeroAnim.num("death.total_s", 1.2)
		alpha = clampf((total - _death_t) / 0.28, 0.0, 1.0)
	elif _getup_t >= 0.0:
		var g: float = clampf(_getup_t / 0.45, 0.0, 1.0)
		var e: float = HeroAnim.ease_out_back(g, 2.2)
		pop = Vector2(lerpf(0.35, 1.0, e), lerpf(1.45, 1.0, e))
		alpha = clampf(g * 3.0, 0.0, 1.0)

	var squash: float = _sq.x
	var sx: float = (1.0 + 0.55 * squash + breath * -0.5) * turn_x * pop.x
	var sy: float = (1.0 - squash + breath) * pop.y
	var rot: float = (_lean.x + sway) * float(f) + death_rot * float(f)
	_body.rotation = rot
	_body.skew = _drag.x * float(f)
	_body.scale = Vector2(sx, sy)
	_body.position = Vector2(FOOT_Y * 0.0 + _kick.x * float(f) + shake.x + death_x * float(f),
			FOOT_Y + bob + shake.y + death_y)
	_sprite.self_modulate = _flash
	_sprite.modulate.a = alpha
	_last_shake = _stun_shake()
	_sprite.position = Vector2(-fw / (2.0 * ART_SCALE) + _last_shake,
			-46.0 + float(GROUND_Y - int(geom[2])) / ART_SCALE)

	# Затухание следа смены листа.
	if _ghost_left > 0.0:
		_ghost_left -= dt
		var fade: float = maxf(HeroAnim.num("blend.cross_fade_s", 0.09), 0.01)
		_ghost.modulate.a = clampf(_ghost_left / fade, 0.0, 1.0) * 0.7 * alpha
		if _ghost_left <= 0.0:
			_ghost.visible = false


func _pose_rest() -> void:
	_body.rotation = 0.0
	_body.skew = 0.0
	_body.scale = Vector2.ONE
	_body.position = Vector2(0.0, FOOT_Y)
	_sprite.self_modulate = Color.WHITE
	_sprite.modulate.a = 1.0
	if _sprite.texture != null:
		var fw: int = int(_sprite.region_rect.size.x)
		_sprite.position = Vector2(-fw / (2.0 * ART_SCALE) + 0.0, _sprite.position.y)
	_ghost.visible = false
	_ghost_left = 0.0
	_cur_key = ""


## Прежний кадр остаётся на экране и тает: смена листа не щёлкает.
func _start_ghost() -> void:
	var fade: float = HeroAnim.num("blend.cross_fade_s", 0.09)
	if fade <= 0.0 or _t <= 0.0:
		return
	_ghost.texture = _sprite.texture
	_ghost.region_rect = _sprite.region_rect
	_ghost.flip_h = _sprite.flip_h
	_ghost.position = _sprite.position - Vector2(_last_shake, 0.0)
	_ghost.modulate.a = 0.7
	_ghost.visible = true
	_ghost_left = fade


## Ходьба и стойка: шаг по пути, остановка в проходной позе, приседание после
## приземления.
func _ground_pose(dt: float) -> Dictionary:
	var spd: float = absf(_vx_s)
	var moving: bool = spd > 0.3
	var fpc: float = 4.0 / maxf(Juice.num("steps.distance_cells", 0.85), 0.2)
	if moving and _land_t > 0.0:
		_land_t = 0.0
	if moving:
		if not _walk_active:
			_walk_active = true
			_idle_t = 0.0
			_idle_act = ""
		_stride = HeroAnim.stride_advance(_stride, spd * dt, fpc)
	elif _walk_active:
		# Остановка: ставим ногу в проходную позу, а не замираем на размахе.
		var need: float = HeroAnim.frames_to_passing(_stride)
		if need < 0.2 or need > 3.3:
			_walk_active = false
			_stride = fposmod(floorf(_stride / 4.0 + 0.5) * 4.0, 16.0)
		else:
			_stride = fposmod(_stride + minf(need, 22.0 * dt), 16.0)
	if _walk_active:
		var idx: int = int(floor(_stride)) % 16
		if idx != _last_idx and idx % 4 == 1 and spd >= HeroAnim.num("walk.dust_min_speed", 0.7) * WALK_REF \
				and player.digging == null:
			footstep.emit(_feet_world())
			Fx.burst("poof", _feet_world() + Vector2(-float(_face_drawn) * 5.0, 0.0), 0.3)
		_last_idx = idx
		return {"sheet_name": "walk", "frame": idx, "mode": "walk"}
	if _land_t > 0.0:
		var half: float = HeroAnim.num("air.land_pose_s", 0.16) * (1.0 if _land_hard else 0.75) * 0.5
		var jf: Dictionary = _jump_frame("crouch" if _land_t > half else "recover")
		return {"sheet_name": jf["sheet_name"], "frame": jf["frame"], "mode": "idle"}
	var ip: Dictionary = _idle_pose(dt)
	return {"sheet_name": ip["sheet_name"], "frame": ip["frame"], "mode": "idle"}


## Стан показывается тряской, а не простоем: секунда без движения выглядит как
## зависшая игра, и игрок начинает давить на экран. Три пикселя вправо-влево
## на 14 Гц читаются как «отдало в руки», занимают ровно столько, сколько
## длится стан, и не двигают саму клетку — только рисунок героя. К концу стана
## размах плавно спадает: тряска не обрывается на полном размахе.
func _stun_shake() -> float:
	if player.stun_until_msec <= 0.0:
		return 0.0
	var left: float = player.stun_until_msec - float(Time.get_ticks_msec())
	if left <= 0.0:
		return 0.0
	var ease_out: float = clampf(left / 220.0, 0.0, 1.0)
	return signf(sin(left / 1000.0 * TAU * SHAKE_HZ)) * SHAKE_PIXELS \
			* ease_out * HeroAnim.motion_scale(Settings.reduce_motion)


# ---------------------------------------------------------------------------
# Выход/посадка в бурмобиль — см. блок объявлений в начале файла.
# ---------------------------------------------------------------------------

func _load_rig_exit_sheet() -> void:
	if ResourceLoader.exists(RIG_EXIT_SHEET_PATH):
		_rig_exit_sheet = load(RIG_EXIT_SHEET_PATH)
	if ResourceLoader.exists(RIG_EXIT_META_PATH):
		var f := FileAccess.open(RIG_EXIT_META_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary and parsed.has("ground_y"):
				_rig_exit_ground_y = int(parsed["ground_y"])


## Кадр листа rig_exit.png по ключу (1..7), который держит player.gd
## (rig_transition_key()) — семь поз без интерполяции между ними, ключ
## переключается целиком, никакого anim-счётчика тут нет: это не цикл, а
## одноразовая постановочная сценка.
func _draw_rig_transition() -> void:
	if _rig_exit_sheet == null or player == null:
		return
	var key: int = int(player.call("rig_transition_key")) if player.has_method("rig_transition_key") else 1
	var fw: int = int(_rig_exit_sheet.get_width() / RIG_EXIT_FRAMES)
	var fh: int = int(_rig_exit_sheet.get_height())
	_sprite.texture = _rig_exit_sheet
	_sprite.region_rect = Rect2(clampi(key - 1, 0, RIG_EXIT_FRAMES - 1) * fw, 0, fw, fh)
	# Сцена выхода всегда смотрит в одну сторону (та, куда исходно смотрел
	# художник — герой выходит из машины лицом от тоннеля): разворот по
	# facing её не касается, машина не разворачивается вместе с героем.
	_sprite.flip_h = false
	_sprite.position = Vector2(-fw / (2.0 * ART_SCALE),
			-46.0 + float(GROUND_Y - _rig_exit_ground_y) / ART_SCALE)

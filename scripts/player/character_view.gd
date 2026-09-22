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
		"rig_jump", "rig_fly"]

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
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.scale = Vector2(1.0 / ART_SCALE, 1.0 / ART_SCALE)
	add_child(_sprite)
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


func _process(_dt: float) -> void:
	if player == null:
		return
	position = Vector2(player.x * TILE, player.y * TILE)

	# Выход из бурмобиля на поверхности / посадка в него — свой рисунок поверх
	# всего остального (player.rig_transition != ""), пока анимация не
	# доиграла управление и так заблокировано, см. player.gd). Держит экран,
	# пока не закончится, — обычные ветки ниже (копка/полёт/ходьба) в это
	# время не имеют смысла: герой либо в кабине, либо ещё не встал.
	if String(player.get("rig_transition")) != "":
		_draw_rig_transition()
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
	var in_rig_underground: bool = player.has_method("is_in_rig") and player.is_in_rig() and player.cell_y() >= 1

	var dig: Dictionary = _dig_frame(player.digging != null)
	# Вызывается КАЖДЫЙ кадр (см. её собственный докстринг) — даже когда
	# сейчас копка/переход выигрывают отрисовку: иначе edge-детекция
	# прыжка/посадки/тяги внутри неё видела бы устаревшее on_ground/thrust.
	var rig_move: Dictionary = _rig_move_frame()

	var sheet_name: String
	var phase_frame: int = -1
	var force_static_frame := false
	if dig.has("sheet_name"):
		# Для каждого инструмента нарисована своя анимация, а для бура и
		# бурмобиля — ещё и своя на каждое направление копки; фаза (старт /
		# цикл / финиш) — см. _dig_frame и DIG_PHASES.
		sheet_name = dig["sheet_name"]
		phase_frame = dig["frame"]
	elif rig_move.has("sheet_name"):
		# Прыжок/приземление/начало-конец полёта бурмобиля — см. _rig_move_frame.
		# Приоритет НИЖЕ копки (бур не прыгает во время бурения — физически
		# невозможно, но порядок на всякий случай тот же, что просил
		# владелец) и выше статичных кадров ниже.
		sheet_name = rig_move["sheet_name"]
		phase_frame = rig_move["frame"]
	elif in_rig_underground:
		sheet_name = "dig_rig_side" if _sheets.has("dig_rig_side") else "dig_pick"
		force_static_frame = true
	elif not player.on_ground:
		# Все четыре уровня снаряжения выглядят по-разному, и по кадру должно
		# быть видно, на чём герой висит: пропеллер, большой винт, джетпак с
		# выхлопом или две ракеты. Тяга при этом своя — она из player.thrust.
		if player.thrust != "":
			sheet_name = _fly_sheet_name()
		else:
			sheet_name = "fall"
	else:
		sheet_name = "walk" if player.vx != 0.0 else "idle"

	var geom: Array = SHEET_FRAME.get(sheet_name, [CHAR_W, CHAR_H, GROUND_Y])
	var anim_div: float = SHEET_ANIM_DIV.get(sheet_name, ANIM_DIV)
	var fw: int = geom[0]
	var fh: int = geom[1]
	var tex: Texture2D = _tex_for_sheet(sheet_name)
	if tex != null:
		_sprite.texture = tex
		var frames: int = maxi(1, int(round(tex.get_width() / float(fw))))
		var frame: int = phase_frame
		if frame < 0:
			frame = 0 if force_static_frame else \
					(int(floor(player.anim / anim_div)) % frames if frames > 1 else 0)
		_sprite.region_rect = Rect2(frame * fw, 0, fw, fh)
	_sprite.flip_h = player.facing < 0
	# Линия земли листа должна лечь туда же, куда ложится подошва у кадра
	# 48×48, иначе высокий кадр повиснет над землёй.
	# Позиция — в логических точках, а текстура в ART_SCALE раз крупнее,
	# поэтому её размеры сюда попадают делёными.
	_sprite.position = Vector2(-fw / (2.0 * ART_SCALE) + _stun_shake(),
			-HH * TILE - 16.0 + float(GROUND_Y - int(geom[2])) / ART_SCALE)


## Стан показывается тряской, а не простоем: секунда без движения выглядит как
## зависшая игра, и игрок начинает давить на экран. Три пикселя вправо-влево
## на 14 Гц читаются как «отдало в руки», занимают ровно столько, сколько
## длится стан, и не двигают саму клетку — только рисунок героя.
func _stun_shake() -> float:
	if player.stun_until_msec <= 0.0:
		return 0.0
	var left: float = player.stun_until_msec - float(Time.get_ticks_msec())
	if left <= 0.0:
		return 0.0
	return signf(sin(left / 1000.0 * TAU * SHAKE_HZ)) * SHAKE_PIXELS


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
			-HH * TILE - 16.0 + float(GROUND_Y - _rig_exit_ground_y) / ART_SCALE)

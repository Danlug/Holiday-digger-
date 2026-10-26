class_name StreakLogic
extends RefCounted
## Азарт: шкала, которая копится секундами работы (кирка в деле), и жадность
## (бывшая «лихорадка») — когда шкала полна, N секунд любая клетка копается с
## первого удара, ход и падение в 7 раз быстрее, руда этих клеток идёт вдвое.
## Числа — GreedRules и data/mechanics.json → streak. Чистая логика без узлов и
## часов: время приходит аргументом (tick), поэтому тест крутит её детерминированно.
##
## ПОЧЕМУ секунды работы, а не клетки (26.10, «у меня вообще не сработала
## жадность»): клетка киркой — 1.8–8 с, бурмобилем — доли секунды, и 60 клеток
## подряд были для живого игрока 2.5–4 минутами без единой паузы. Секунды дают
## одну и ту же частоту на любом инструменте.
##
## ПОЧЕМУ пауза не обнуляет, а сначала ждёт, потом тает: огляделся, вернулся по
## штреку к шахте, перелетел к руде — это игра, а не безделье. Обнуляют только
## поверхность, дом и смерть (их решает вызывающий: allowed = false).

var work: float = 0.0          # секунд работы в серии — это и есть шкала
var count: int = 0             # клеток в серии (журнал, отладка)
var greed_left: float = 0.0    # секунд жадности осталось
var greed_total: float = 0.0   # на сколько секунд она началась (шкала-таймер)
var idle: float = 0.0          # секунд без копки подряд
var fevers: int = 0            # сколько раз жадность начиналась (имя прежнее: журнал и сейв зовут их «лихорадками»)
var stage: int = -1            # ступень ветки «Жадность», под которую посчитаны порог и длительность

var fever_s: float = 60.0      # секунд работы до жадности (уже с поправкой ступени)
var greed_s: float = 3.0       # длительность жадности (уже со ступенью)
var gap_s: float = 0.6
var hold_s: float = 2.5
var drain_per_s: float = 5.0
var min_depth: int = 6


func _init(stage_n: int = 0) -> void:
	gap_s = MechData.num("streak", "gap_s", 0.6)
	hold_s = MechData.num("streak", "hold_s", 2.5)
	drain_per_s = MechData.num("streak", "drain_per_s", 5.0)
	min_depth = int(MechData.num("streak", "min_depth", 6))
	set_stage(stage_n)


## Ступень ветки «Жадность»: порог и длительность пересчитываются, идущая серия и
## жадность не трогаются (купил ступень посреди серии — до жадности ближе).
func set_stage(stage_n: int) -> void:
	if stage_n == stage:
		return
	stage = stage_n
	fever_s = GreedRules.threshold(stage_n)
	greed_s = GreedRules.seconds(stage_n)


func in_greed() -> bool:
	return greed_left > 0.0


## Прежнее имя (журнал, тесты раунда 3).
func in_fever() -> bool:
	return in_greed()


## Доля шкалы 0..1: копится к жадности, в жадности — сколько её осталось.
func meter() -> float:
	if greed_left > 0.0:
		return clampf(greed_left / maxf(greed_total, 0.001), 0.0, 1.0)
	return clampf(work / maxf(fever_s, 0.001), 0.0, 1.0)


func active() -> bool:
	return work > 0.0 or count > 0 or greed_left > 0.0


## Шкала тает прямо сейчас (простой дольше hold_s) — шкале HUD есть что показать.
func draining() -> bool:
	return greed_left <= 0.0 and work > 0.0 and idle > hold_s


## Кадр: digging — герой сейчас копает; allowed — серия вообще может жить (герой
## под землёй, жив, не дома, механики включены); hold — открыто окно или идёт сцена:
## шкала замирает как есть (жадность — нет, она по часам). Возвращает true, если
## серия сгорела именно сейчас (растаяла или allowed = false). Конец жадности по
## времени — не «сгорела»: смотри in_greed().
func tick(dt: float, digging: bool, allowed: bool, hold: bool = false) -> bool:
	if not allowed:
		return reset()
	if greed_left > 0.0:
		idle = 0.0
		greed_left = maxf(0.0, greed_left - dt)
		return false
	if hold:
		return false
	if digging:
		idle = 0.0
		work += dt
		return false
	idle += dt
	if idle <= gap_s:
		if count > 0:
			work += dt   # шаг в выкопанную клетку, падение в неё — та же работа
		return false
	if idle <= hold_s or work <= 0.0:
		return false
	work -= drain_per_s * dt
	if work <= 0.0:
		return reset()
	return false


func reset() -> bool:
	var had := active()
	work = 0.0
	count = 0
	greed_left = 0.0
	idle = 0.0
	return had


## Клетка выкопана на глубине depth. Ответ:
##   fever_cell — клетка выкопана в жадности (её руда удваивается);
##   started    — шкала была полна: жадность началась (со следующей клетки).
## Клетки жадности шкалу не копят: иначе жадность продлевала бы сама себя.
func on_dug(depth: int) -> Dictionary:
	var out := {"fever_cell": false, "started": false}
	if depth < min_depth:
		return out
	idle = 0.0
	if greed_left > 0.0:
		out["fever_cell"] = true
		return out
	count += 1
	if work >= fever_s - 0.0001:
		work = 0.0
		count = 0
		greed_left = greed_s
		greed_total = greed_s
		fevers += 1
		out["started"] = true
	return out

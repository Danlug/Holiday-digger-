class_name StreakLogic
extends RefCounted
## Азарт: серия клеток, выкопанных без пауз, и жадность (бывшая «лихорадка») —
## когда шкала полна, N секунд любая клетка копается с первого удара, ход и
## падение в 7 раз быстрее, руда этих клеток идёт вдвое. Числа — GreedRules.
## Чистая логика без узлов и часов: время приходит аргументом (tick), поэтому
## тест крутит её детерминированно.
##
## ПОЧЕМУ жадность считается секундами (в раунде 3 лихорадка шла клетками):
## так задал владелец, и неравенства инструментов больше нет — в жадности любой
## инструмент бьёт клетку одним ударом, темп упирается в ход героя.
##
## ПОЧЕМУ пауза считается без копки, а не между ударами: камень лопатой копается
## 10 секунд — серия не должна рваться посреди удара по камню.

var count: int = 0             # клеток в серии (до жадности)
var greed_left: float = 0.0    # секунд жадности осталось
var greed_total: float = 0.0   # на сколько секунд она началась (шкала-таймер)
var idle: float = 0.0          # секунд без копки подряд
var fevers: int = 0            # сколько раз жадность начиналась (имя прежнее: журнал и сейв зовут их «лихорадками»)
var stage: int = -1            # ступень ветки «Жадность», под которую посчитаны порог и длительность

var fever_at: int = 60         # клеток подряд до жадности (уже с поправкой ступени)
var greed_s: float = 3.0       # длительность жадности (уже со ступенью)
var idle_break_s: float = 2.5
var min_depth: int = 6


func _init(stage_n: int = 0) -> void:
	idle_break_s = MechData.num("streak", "idle_break_s", 2.5)
	min_depth = int(MechData.num("streak", "min_depth", 6))
	set_stage(stage_n)


## Ступень ветки «Жадность»: порог и длительность пересчитываются, идущая серия и
## жадность не трогаются (купил ступень посреди серии — до жадности ближе).
func set_stage(stage_n: int) -> void:
	if stage_n == stage:
		return
	stage = stage_n
	fever_at = GreedRules.threshold(stage_n)
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
	return clampf(float(count) / float(fever_at), 0.0, 1.0)


func active() -> bool:
	return count > 0 or greed_left > 0.0


## Кадр: digging — герой сейчас копает; allowed — серия вообще может жить (герой
## под землёй, жив, не дома, механики включены). Возвращает true, если серия
## порвалась именно сейчас (пауза, поверхность, дом). Жадность идёт по часам и
## паузой не рвётся; её конец по времени — не «порвалась»: смотри in_greed().
func tick(dt: float, digging: bool, allowed: bool) -> bool:
	if not allowed:
		return reset()
	if greed_left > 0.0:
		idle = 0.0
		greed_left = maxf(0.0, greed_left - dt)
		return false
	if digging:
		idle = 0.0
		return false
	idle += dt
	if idle > idle_break_s:
		return reset()
	return false


func reset() -> bool:
	var had := active()
	count = 0
	greed_left = 0.0
	idle = 0.0
	return had


## Клетка выкопана на глубине depth. Ответ:
##   fever_cell — клетка выкопана в жадности (её руда удваивается);
##   started    — жадность началась (со следующей клетки).
## Клетки жадности серию не копят: иначе жадность продлевала бы сама себя.
func on_dug(depth: int) -> Dictionary:
	var out := {"fever_cell": false, "started": false}
	if depth < min_depth:
		return out
	idle = 0.0
	if greed_left > 0.0:
		out["fever_cell"] = true
		return out
	count += 1
	if count >= fever_at:
		count = 0
		greed_left = greed_s
		greed_total = greed_s
		fevers += 1
		out["started"] = true
	return out

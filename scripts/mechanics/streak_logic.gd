class_name StreakLogic
extends RefCounted
## Азарт: серия клеток, выкопанных без пауз, и лихорадка — следующие несколько
## клеток с двойной добычей. Чистая логика без узлов и часов: время приходит
## аргументом (tick), поэтому тест крутит её детерминированно.
##
## ПОЧЕМУ лихорадка считается клетками, а не секундами: лопата копает клетку
## секунды, бурмобиль — доли секунды. Секундная лихорадка дала бы бурмобилю в
## десять раз больше двойной добычи; клеточная даёт любому инструменту одну и ту
## же долю (fever_cells из fever_at + fever_cells клеток подряд).
##
## ПОЧЕМУ пауза считается без копки, а не между ударами: камень лопатой копается
## 10 секунд — серия не должна рваться посреди удара по камню.

var count: int = 0          # клеток в серии (до лихорадки)
var fever_left: int = 0     # сколько клеток лихорадки осталось
var idle: float = 0.0       # секунд без копки подряд
var fevers: int = 0         # сколько раз лихорадка начиналась (статистика журнала и тестов)

var fever_at: int = 50
var fever_cells: int = 6
var idle_break_s: float = 2.5
var min_depth: int = 6


func _init() -> void:
	fever_at = maxi(1, int(MechData.num("streak", "fever_at", 50)))
	fever_cells = maxi(1, int(MechData.num("streak", "fever_cells", 6)))
	idle_break_s = MechData.num("streak", "idle_break_s", 2.5)
	min_depth = int(MechData.num("streak", "min_depth", 6))


func in_fever() -> bool:
	return fever_left > 0


## Доля шкалы 0..1: копится к лихорадке, в лихорадке — сколько её осталось.
func meter() -> float:
	if fever_left > 0:
		return float(fever_left) / float(fever_cells)
	return clampf(float(count) / float(fever_at), 0.0, 1.0)


func active() -> bool:
	return count > 0 or fever_left > 0


## Кадр: digging — герой сейчас копает; allowed — серия вообще может жить (герой
## под землёй, жив, не дома, механики включены). Возвращает true, если серия
## порвалась именно сейчас.
func tick(dt: float, digging: bool, allowed: bool) -> bool:
	if not allowed:
		return reset()
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
	fever_left = 0
	idle = 0.0
	return had


## Клетка выкопана на глубине depth. Ответ:
##   fever_cell — эта клетка копалась в лихорадке (её добыча удваивается);
##   started    — лихорадка началась (со следующей клетки);
##   ended      — эта клетка была последней в лихорадке.
func on_dug(depth: int) -> Dictionary:
	var out := {"fever_cell": false, "started": false, "ended": false}
	if depth < min_depth:
		return out
	idle = 0.0
	if fever_left > 0:
		fever_left -= 1
		out["fever_cell"] = true
		if fever_left == 0:
			out["ended"] = true
			count = 0
		return out
	count += 1
	if count >= fever_at:
		count = 0
		fever_left = fever_cells
		fevers += 1
		out["started"] = true
	return out

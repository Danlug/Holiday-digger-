extends RefCounted
## Телеметрия бота-игрока (tests/bot_play.gd): вехи, кривые, поездки, покупки, смерти,
## застревания, всплески кадра, «скучные» отрезки — и запись всего в JSON.
##
## Чистые данные без узлов: бот зовёт note_*() по ходу игры и finish() в конце.
## Время везде — ИГРОВЫЕ секунды от старта прогона (sim), кроме времени кадра (мс настенных).

const DEPTH_MARKS := [10, 25, 50, 100, 150, 200, 300, 400, 500, 750, 1000, 1500, 2000, 3000, 4000, 5000]
## Отрезок без единого «события» дольше этого — скучно (игровые секунды).
const BORING_SEC := 480.0
## Кадр дольше этого (мс процессора, без досыпания бота) — всплеск.
const SPIKE_MS := 50.0

var meta: Dictionary = {}
var milestones: Dictionary = {}          # имя -> sim
var curve: Array = []                    # [t, coins, xp, level, depth, max_depth, hp, hunger, stamina, weight, max_w]
var goal_curve: Array = []               # [t, метрика стратегии]
var trips: Array = []
var purchases: Array = []
var sales: Array = []
var meals: Array = []
var sleeps: Array = []
var deaths: Array = []
var scenes: Array = []
var stuck: Array = []
var modals: Array = []
var findings: Array = []                 # {sev, kind, text, t, data}
var events: Array = []                   # [t, kind, text] — для хронологии
var activity: Dictionary = {}            # занятие -> игровых секунд
var event_counts: Dictionary = {}        # id шины GameState -> сколько раз
var minerals_first: Dictionary = {}      # минерал -> sim первого подбора
var lines: Dictionary = {}               # сцена -> [реплики]
var shots: Array = []
var frame_ms: PackedFloat32Array = PackedFloat32Array()
var spikes: Array = []
var burned_ms := 0.0
var bot_ms := 0.0                        # время самого бота (план, детекторы, досыпание) — вычтено из кадров
var _interesting: Array = []             # моменты «что-то произошло» для детектора скуки
var _trip: Dictionary = {}
var _finding_keys: Dictionary = {}


func mark(name: String, t: float) -> bool:
	if milestones.has(name):
		return false
	milestones[name] = snappedf(t, 0.1)
	event(t, "milestone", name)
	return true


func event(t: float, kind: String, text: String, interesting: bool = true) -> void:
	events.append([snappedf(t, 0.1), kind, text])
	if interesting:
		_interesting.append(t)


## Находка: sev P0 (падение/тупик), P1 (баг), P2 (баланс/темп), P3 (удобство/вид).
## Одинаковые (kind + key) не дублируются: считаются в поле count.
func finding(sev: String, kind: String, text: String, t: float, data: Dictionary = {}, key: String = "") -> void:
	var k := kind + "|" + (key if key != "" else text)
	if _finding_keys.has(k):
		var f: Dictionary = findings[int(_finding_keys[k])]
		f["count"] = int(f.get("count", 1)) + 1
		f["last_t"] = snappedf(t, 0.1)
		return
	_finding_keys[k] = findings.size()
	findings.append({"sev": sev, "kind": kind, "text": text, "t": snappedf(t, 0.1), "count": 1, "data": data})
	event(t, "finding", "%s %s: %s" % [sev, kind, text], false)


func add_activity(name: String, dt: float) -> void:
	activity[name] = float(activity.get(name, 0.0)) + dt


func sample(t: float, coins: int, xp: int, level: int, depth: int, max_depth: int, hp: float,
		hunger: float, stamina: float, weight: float, max_w: float) -> void:
	curve.append([snappedf(t, 0.1), coins, xp, level, depth, max_depth, snappedf(hp, 0.1),
		snappedf(hunger, 0.1), snappedf(stamina, 0.1), snappedf(weight, 0.1), snappedf(max_w, 0.1)])


func frame(ms: float, t: float, context: String) -> void:
	frame_ms.append(ms)
	if ms >= SPIKE_MS and spikes.size() < 200:
		spikes.append({"t": snappedf(t, 0.1), "ms": snappedf(ms, 0.1), "ctx": context})


func trip_start(t: float, depth: int) -> void:
	_trip = {"start": snappedf(t, 0.1), "from_depth": depth, "max_depth": depth, "digs": 0, "loot": 0}


func trip_dig(depth: int, loot: bool) -> void:
	if _trip.is_empty():
		return
	_trip["digs"] = int(_trip["digs"]) + 1
	_trip["max_depth"] = maxi(int(_trip["max_depth"]), depth)
	if loot:
		_trip["loot"] = int(_trip["loot"]) + 1


func trip_end(t: float, reason: String, pack_value: int, weight: float) -> void:
	if _trip.is_empty():
		return
	_trip["end"] = snappedf(t, 0.1)
	_trip["reason"] = reason
	_trip["pack_value"] = pack_value
	_trip["weight"] = snappedf(weight, 0.1)
	trips.append(_trip)
	_trip = {}


func in_trip() -> bool:
	return not _trip.is_empty()


func add_line(scene: String, text: String) -> void:
	if not lines.has(scene):
		lines[scene] = []
	var arr: Array = lines[scene]
	if not arr.has(text) and arr.size() < 80:
		arr.append(text)


## Скучные отрезки: промежутки между «интересными» моментами длиннее BORING_SEC.
func boring_spans(end_t: float) -> Array:
	var pts: Array = _interesting.duplicate()
	pts.append(end_t)
	pts.sort()
	var out: Array = []
	var prev := 0.0
	for p in pts:
		if float(p) - prev >= BORING_SEC:
			out.append({"from": snappedf(prev, 0.1), "to": snappedf(float(p), 0.1),
				"minutes": snappedf((float(p) - prev) / 60.0, 0.1), "context": _context_between(prev, float(p))})
		prev = maxf(prev, float(p))
	return out


## Что было между двумя моментами: глубины и монеты по кривой.
func _context_between(a: float, b: float) -> Dictionary:
	var d0 := -1
	var d1 := -1
	var c0 := -1
	var c1 := -1
	for row in curve:
		var t := float(row[0])
		if t < a or t > b:
			continue
		if d0 < 0:
			d0 = int(row[5])
			c0 = int(row[1])
		d1 = int(row[5])
		c1 = int(row[1])
	return {"max_depth_from": d0, "max_depth_to": d1, "coins_from": c0, "coins_to": c1}


func frame_stats() -> Dictionary:
	if frame_ms.is_empty():
		return {}
	var arr := Array(frame_ms)
	arr.sort()
	var n := arr.size()
	var sum := 0.0
	for v in arr:
		sum += float(v)
	return {"frames": n, "avg_ms": snappedf(sum / n, 0.01), "p50_ms": snappedf(float(arr[n / 2]), 0.01),
		"p95_ms": snappedf(float(arr[int(n * 0.95)]), 0.01), "p99_ms": snappedf(float(arr[int(n * 0.99)]), 0.01),
		"max_ms": snappedf(float(arr[n - 1]), 0.01), "spikes_over_%d_ms" % int(SPIKE_MS): spikes.size(),
		"bot_burned_real_ms": snappedf(burned_ms, 1.0), "bot_logic_ms": snappedf(bot_ms, 1.0)}


func to_dict(end_t: float) -> Dictionary:
	return {
		"meta": meta,
		"milestones": milestones,
		"findings": findings,
		"deaths": deaths,
		"stuck": stuck,
		"trips": trips,
		"purchases": purchases,
		"sales": sales,
		"meals": meals,
		"sleeps": sleeps,
		"scenes": scenes,
		"modals": modals,
		"boring": boring_spans(end_t),
		"activity_seconds": activity,
		"event_counts": event_counts,
		"minerals_first": minerals_first,
		"frame": frame_stats(),
		"frame_spikes": spikes,
		"curve_columns": ["t", "coins", "xp", "level", "depth", "max_depth", "hp", "hunger", "stamina", "weight", "max_weight"],
		"curve": curve,
		"goal_curve": goal_curve,
		"events": events,
		"lines": lines,
		"shots": shots,
	}


func write_json(path: String, end_t: float) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("bot: не записать телеметрию в " + path)
		return false
	f.store_string(JSON.stringify(to_dict(end_t), "\t"))
	f.close()
	return true

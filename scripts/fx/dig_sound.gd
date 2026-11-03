class_name DigSound
extends RefCounted
## Звук копки (зона dig-sound, раунд 6). Живёт внутри JuiceDirector и не трогает
## героя: читает `player.digging` ({x, y, t, total, type}) и `GameState.current_tool`.
##
## Ритм. Удары ложатся в длительность клетки: n = round(total / период инструмента),
## удары на k·(total/n), k = 1…n−1, а n-й удар — сама клетка (событие `dug`):
## порода ломается ровно на замахе, а не между ударами. Короткая клетка (быстрая
## кирка по земле) — только финальный удар.
##
## Слои. Удар = `dig_<материал>_<инструмент>` (tools/audio_dig.py), финал — тот же
## удар громче плюс осыпание `break_<материал>`; ржавая кирка добавляет `rattle`.
## Ручной бур держит петлю `drill_loop`, пока копает (и 0,35 с после — следующая
## клетка не перезапускает мотор); бурмобиль — `rig_loop`, пока герой в машине:
## на холостых тихо и низко, под нагрузкой громче и выше, после каждого удара
## обороты проседают. Долгая непрерывная копка плавно теряет до 4 дБ на ударах
## (усталость): бурмобиль не оглушает, моторная петля остаётся фоном.

const NO_CELL := Vector2i(-99999, -99999)
const CHAIN_GAP_S := 0.35          # пауза между клетками, в которую мотор не глушится
const FATIGUE_DB := 4.0            # сколько теряют удары за FATIGUE_S непрерывной копки
const FATIGUE_S := 8.0
const RATTLE_CHANCE := 0.75
const RECENT_MAX := 40

const HARD_TILES := [
	TileTypes.Type.FOUNDATION, TileTypes.Type.REINFORCED, TileTypes.Type.OBSIDIAN,
	TileTypes.Type.HELLSTONE, TileTypes.Type.DARK_MATTER, TileTypes.Type.UNIVERSALIUM,
	TileTypes.Type.ANGEL_STONE, TileTypes.Type.DIVINE_HEART,
]
const GEM_TILES := [TileTypes.Type.DIAMOND, TileTypes.Type.RUBY, TileTypes.Type.EMERALD, TileTypes.Type.GEOCRYSTAL]
const GOLD_TILES := [TileTypes.Type.GOLD_ORE, TileTypes.Type.PLATINUM_ORE]
const PEAT_TILES := [TileTypes.Type.PEAT, TileTypes.Type.COAL]
const STONE_TILES := [TileTypes.Type.STONE, TileTypes.Type.RUIN_BRICK]

var stats := {"strikes": 0, "breaks": 0, "plans": 0}
## Последние сыгранные id (для тестов и отладки), новые в конце.
var recent: Array[String] = []

var _cell := NO_CELL
var _total := -1.0
var _n := 1
var _period := 1.0
var _next_k := 1
var _busy := 0.0        # секунд непрерывной копки
var _idle := 1e6        # секунд с конца последней копки
var _drill_on := false
var _rig_on := false
var _rig_db := -14.0
var _rig_pitch := 0.85
var _dip := 0.0         # просадка оборотов после удара (1 → 0)


# ---------------------------------------------------------------------------
# Сопоставления
# ---------------------------------------------------------------------------

static func material_for(tile: int) -> String:
	if tile == TileTypes.Type.DIRT:
		return "dirt"
	if PEAT_TILES.has(tile):
		return "peat"
	if STONE_TILES.has(tile):
		return "stone"
	if HARD_TILES.has(tile):
		return "hard"
	if GEM_TILES.has(tile):
		return "gem"
	if GOLD_TILES.has(tile):
		return "gold"
	if tile == TileTypes.Type.LAVA:
		return "lava"
	return "ore"


## Чем звучит инструмент: shovel | pick | drill. Техника без топлива копает киркой (Player).
static func tool_kind(tool_id: String) -> String:
	if tool_id == "shovel":
		return "shovel"
	if tool_id == "hand_drill" or tool_id == "drill_rig":
		if FuelTank.uses_fuel(tool_id) and not FuelTank.has_fuel(tool_id):
			return "pick"
		return "drill"
	return "pick"


static func strike_id(mat: String, kind: String) -> String:
	if mat == "lava":
		return "dig_lava"
	if kind == "shovel" and not (mat == "dirt" or mat == "peat" or mat == "ore"):
		kind = "pick"
	return "dig_%s_%s" % [mat, kind]


static func break_id(mat: String) -> String:
	return "break_" + mat


## Сколько ударов уложится в клетку длительностью total (с финальным).
static func hits_for(total: float, tool_id: String) -> int:
	return maxi(1, roundi(total / Feel.hit_period(tool_id)))


# ---------------------------------------------------------------------------
# Покадровое
# ---------------------------------------------------------------------------

## Возвращает true, если в этом кадре был удар (режиссёр добавляет к нему частицы).
func tick(player: Node, delta: float) -> bool:
	var d = player.get("digging")
	var tool := GameState.current_tool
	var struck := false
	if d != null:
		var cell := Vector2i(int(d["x"]), int(d["y"]))
		var total := float(d["total"])
		if cell != _cell or not is_equal_approx(total, _total):
			_plan(cell, total, tool)
		var t := float(d["t"])
		if _next_k < _n and t >= float(_next_k) * _period:
			_strike(int(d["type"]), tool, float(_next_k) / float(_n))
			# если кадр был долгим (свёрнутая вкладка), пропущенные удары не досыпаем очередью
			_next_k = maxi(_next_k + 1, int(floor(t / _period)) + 1)
			struck = true
		_busy += delta
		_idle = 0.0
	else:
		_cell = NO_CELL
		_total = -1.0
		_idle += delta
		_busy = maxf(0.0, _busy - delta * 2.0)
	_tick_motors(player, tool, d != null, delta)
	return struck


func _plan(cell: Vector2i, total: float, tool: String) -> void:
	_cell = cell
	_total = total
	_n = hits_for(total, tool)
	_period = total / float(_n)
	_next_k = 1
	stats["plans"] += 1
	# Веб: копка начинается только с нажатия — это и есть жест, звук можно включать.
	Sfx.gesture()
	# новый заход (не продолжение серии) — лёгкий замах
	var kind := tool_kind(tool)
	if _idle > CHAIN_GAP_S and kind != "drill":
		_play("swing", 1.1, -12.0)


func _strike(tile: int, tool: String, progress: float) -> void:
	var prof := Feel.tool_profile(tool)
	var kind := tool_kind(tool)
	var mat := material_for(tile)
	# к концу клетки удары чуть крепче (+2 дБ), долгая серия устаёт (до −4 дБ)
	var db := float(prof["db"]) + 2.0 * progress - _fatigue_db()
	_play(strike_id(mat, kind), randf_range(0.94, 1.0) * float(prof["pitch"]), db)
	if tool == "rusty_pickaxe" and randf() < RATTLE_CHANCE:
		_play("rattle", randf_range(0.95, 1.05), db + 1.0)
	_dip = 1.0
	stats["strikes"] += 1


## Клетка разрушена: финальный удар громче рядовых плюс осыпание породы.
func on_dug(tile: int, tool: String) -> void:
	var prof := Feel.tool_profile(tool)
	var kind := tool_kind(tool)
	var mat := material_for(tile)
	_play(strike_id(mat, kind), randf_range(0.9, 0.97) * float(prof["pitch"]), float(prof["db"]) + 5.0 - _fatigue_db() * 0.5)
	_play(break_id(mat), 1.0, -_fatigue_db() * 0.5)
	if tool == "rusty_pickaxe":
		_play("rattle", 0.95, float(prof["db"]) + 4.0)
	_dip = 1.0
	_cell = NO_CELL
	stats["breaks"] += 1


func _fatigue_db() -> float:
	return FATIGUE_DB * clampf(_busy / FATIGUE_S, 0.0, 1.0)


func _play(id: String, pitch: float, db: float) -> void:
	Sfx.play(id, pitch, db)
	recent.append(id)
	if recent.size() > RECENT_MAX:
		recent.pop_front()


# ---------------------------------------------------------------------------
# Моторы
# ---------------------------------------------------------------------------

func _tick_motors(player: Node, tool: String, digging: bool, delta: float) -> void:
	_dip = maxf(0.0, _dip - delta * 5.0)
	var frozen: bool = bool(player.get("frozen")) if "frozen" in player else false

	var want_drill := tool == "hand_drill" and tool_kind(tool) == "drill" and (digging or _idle < CHAIN_GAP_S)
	if want_drill != _drill_on:
		_drill_on = want_drill
		if want_drill:
			Sfx.loop_start("drill_loop", 0.0, 1.0)
		else:
			Sfx.loop_stop("drill_loop", 0.12)
	elif _drill_on:
		Sfx.loop_set("drill_loop", 0.0, 1.0 - 0.1 * _dip)

	var in_rig: bool = tool == "drill_rig" and player.has_method("is_in_rig") and player.call("is_in_rig")
	if in_rig != _rig_on:
		_rig_on = in_rig
		if in_rig:
			_rig_db = -14.0
			_rig_pitch = 0.85
			Sfx.loop_start("rig_loop", _rig_db, _rig_pitch)
		else:
			Sfx.loop_stop("rig_loop", 0.3)
	if _rig_on:
		var load := digging and not frozen and tool_kind(tool) == "drill"
		var want_db := -4.0 if load else -14.0
		var want_pitch := 1.15 if load else 0.85
		_rig_db = move_toward(_rig_db, want_db, delta * (40.0 if load else 14.0))
		_rig_pitch = move_toward(_rig_pitch, want_pitch, delta * (1.2 if load else 0.5))
		Sfx.loop_set("rig_loop", _rig_db, _rig_pitch * (1.0 - 0.08 * _dip))


## Гасит моторы (режиссёр уходит из дерева).
func stop() -> void:
	if _drill_on:
		Sfx.loop_stop("drill_loop", 0.05)
	if _rig_on:
		Sfx.loop_stop("rig_loop", 0.05)
	_drill_on = false
	_rig_on = false

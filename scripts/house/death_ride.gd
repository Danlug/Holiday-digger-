class_name DeathRide
extends RefCounted
## «Скорая везёт долго» — смерть не лифт наверх (раунд 5, ветка death-cost; ГДД §7
## «Цена смерти»). Владелец: «Смерть не должна быть удобным способом копать вниз и
## просто потом, чтобы не лететь [наверх], — умирать».
##
## Раньше герой просыпался дома в тот же кадр и с полными полосками: с пустым
## рюкзаком смерть была лифтом наверх, обедом и лечением разом. Теперь:
##  * скорая поднимает героя по стволу: поездка = коэффициент × прямой полёт с
##    глубины смерти на ТЕКУЩЕМ ранце (1 у поверхности → 2 с 300 клеток), но не
##    дольше max_seconds. Всё это время GameState.is_alive ложь — управление и
##    выживание стоят, карточка смерти ведёт отсчёт;
##  * по приезде HP — половина полоски, сытость и бодрость — как были в момент
##    смерти, но не ниже bars_min_percent.
## До конца онбординга (флаг gold_sold) смерть мягкая, как раньше: без поездки и
## с полными полосками. Числа — data/healing.json → death.ride / death.respawn.
## Поездку ведёт main.gd (_handle_death: старт, тик, приезд). Остаток лежит в
## GameState.ext — выход из игры посреди поездки её не отменяет.

const EXT_KEY := "death_ride"
## Разгон до потолка скорости (как в player.gd: PROP_RAMP у пропеллеров, JET_RAMP
## у реактивной тяги). Не preload: скрипт героя тянет автозагрузки, а эта
## арифметика нужна и тестам без них.
const PROP_RAMP_S := 3.0
const JET_RAMP_S := 5.0
const SAVE_EVERY_S := 1.0

static var _active := false
static var _left := 0.0
static var _total := 0.0
static var _depth := 0
static var _hunger := 100.0
static var _stamina := 100.0
static var _soft := true
static var _announced := true
static var _save_acc := 0.0


static func _sec(section: String) -> Dictionary:
	var d = Healing.data().get("death", {}).get(section, {})
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func _num(section: String, key: String, fallback: float) -> float:
	var v = Balance.unwrap(_sec(section).get(key, fallback))
	return float(v) if v != null else fallback


# ---------------------------------------------------------------------------
# Арифметика поездки (чистые функции — их проверяет тест)
# ---------------------------------------------------------------------------

## Потолок скорости подъёма, клеток/с: ступень ранца, без ранца — базовая, в
## бурмобиле — с его надбавкой к полёту. Усталость не учитывается: это лучший
## собственный полёт, с которым сравнивается скорая.
static func climb_speed(gear: String, in_rig: bool) -> float:
	var v := Balance.get_gear_max_speed(gear) if gear != "" else 0.0
	if v <= 0.0:
		v = Balance.get_gear_base_speed()
	if in_rig:
		v *= Balance.get_drill_rig_flight_speed_mult()
	return maxf(v, 0.1)


## Прямой полёт с глубины depth до поверхности: путь на потолке скорости плюс
## половина разгона (пока набираешь скорость, летишь в среднем вдвое медленнее).
static func flight_seconds(depth: int, gear: String, in_rig: bool) -> float:
	if depth <= 0:
		return 0.0
	var ramp := JET_RAMP_S if gear != "" and Balance.get_gear_kind(gear) == "jet" else PROP_RAMP_S
	return float(depth) / climb_speed(gear, in_rig) + ramp * 0.5


## Во сколько раз скорая медленнее прямого полёта: у поверхности как сам герой,
## к factor_deep_from_cells — factor_deep, между ними по прямой.
static func factor(depth: int) -> float:
	var lo := _num("ride", "factor_shallow", 1.0)
	var hi := _num("ride", "factor_deep", 2.0)
	var from := maxf(1.0, _num("ride", "factor_deep_from_cells", 300.0))
	return lerpf(lo, hi, clampf(float(depth) / from, 0.0, 1.0))


static func max_seconds() -> float:
	return _num("ride", "max_seconds", 150.0)


## Сколько секунд везёт скорая с глубины depth (0 — у поверхности не везёт).
static func ride_seconds(depth: int, gear: String, in_rig: bool) -> float:
	if depth < int(_num("ride", "min_depth_cells", 3.0)):
		return 0.0
	return minf(max_seconds(), factor(depth) * flight_seconds(depth, gear, in_rig))


## То же для героя как он есть сейчас (ранец и бурмобиль из GameState).
static func ride_seconds_now(depth: int) -> float:
	return ride_seconds(depth, GameState.current_gear, GameState.current_tool == "drill_rig")


static func respawn_hp_percent() -> float:
	return _num("respawn", "hp_percent", 50.0)


static func bars_min_percent() -> float:
	return _num("respawn", "bars_min_percent", 25.0)


## Смерть мягкая, пока не пройден онбординг: без поездки и с полными полосками.
static func is_soft() -> bool:
	return not StoryState.has_flag("gold_sold")


# ---------------------------------------------------------------------------
# Поездка (состояние; ведёт main.gd)
# ---------------------------------------------------------------------------

## GameState.die(): каждая смерть — новая поездка. Если прошлую оборвал чужой
## respawn() (тест, отладка), её остаток не должен подхватиться.
static func on_died() -> void:
	_active = false
	_left = 0.0


## Первый кадр смерти: запомнить полоски и, если надо, начать поездку. Зовётся ДО
## телепорта домой — бурмобиль ещё надет, глубина ещё настоящая. Возвращает
## длительность поездки (0 — респавн сразу).
static func start(depth: int) -> float:
	_soft = is_soft()
	_hunger = GameState.hunger
	_stamina = GameState.stamina
	_depth = maxi(depth, 0)
	_total = 0.0 if _soft else ride_seconds_now(_depth)
	_left = _total
	_active = _total > 0.0
	_save_acc = 0.0
	if _active:
		_save()
		_announced = true
		GameState.emit_event(&"ambulance_ride", {"seconds": _total, "depth": _depth})
	return _total


## Едет ли скорая. Чужой GameState.respawn() (тест, отладка) поездку обрывает.
static func riding() -> bool:
	return _active and not GameState.is_alive


## Кадр поездки. true — приехали, пора респавнить.
static func tick(dt: float) -> bool:
	if not _active:
		return true
	if not _announced:   # поездка, продолженная после перезапуска игры: карточке надо узнать
		_announced = true
		GameState.emit_event(&"ambulance_ride", {"seconds": _total, "depth": _depth, "resumed": true})
	_left = maxf(0.0, _left - maxf(dt, 0.0))
	_save_acc += dt
	if _save_acc >= SAVE_EVERY_S:
		_save_acc = 0.0
		_save()
	return _left <= 0.0


## Приезд (или смерть без поездки): респавн и полоски после скорой.
static func respawn() -> void:
	var rode := _total
	var soft := _soft
	_active = false
	_left = 0.0
	GameState.ext.erase(EXT_KEY)
	GameState.respawn()
	if rode > 0.0:
		# часы мира стояли, пока герой был «в машине» (GameState не тикает мёртвым)
		GameState.game_clock_hours += rode / 3600.0 * Balance.get_game_hours_per_real_hour()
	if soft:
		return
	var min_bar := bars_min_percent()
	GameState.hp = GameState.get_max_hp() * clampf(respawn_hp_percent(), 1.0, 100.0) / 100.0
	GameState.hp_changed.emit(GameState.hp, GameState.get_max_hp())
	GameState.set_hunger(maxf(_hunger, min_bar))
	GameState.set_stamina(maxf(_stamina, min_bar))
	GameState.emit_event(&"ambulance_arrived", {"seconds": rode, "depth": _depth, "hp": GameState.hp})


## Тесты и отладка: доехать сейчас (следующий тик main.gd — респавн).
static func skip() -> void:
	_left = 0.0


static func seconds_left() -> float:
	return _left if _active else 0.0


static func total_seconds() -> float:
	return _total


static func depth() -> int:
	return _depth


## 0 — только выехали, 1 — приехали.
static func progress() -> float:
	if _total <= 0.0:
		return 1.0
	return clampf(1.0 - _left / _total, 0.0, 1.0)


## Загрузка сейва: герой мёртв и в GameState.ext лежит недоезженная поездка —
## продолжить её (true) вместо мгновенного респавна.
static func resume() -> bool:
	var d = GameState.ext_get(EXT_KEY, {})
	if typeof(d) != TYPE_DICTIONARY or float(d.get("left", 0.0)) <= 0.0:
		return false
	_active = true
	_left = float(d.get("left", 0.0))
	_total = maxf(_left, float(d.get("total", _left)))
	_depth = int(d.get("depth", 0))
	_hunger = float(d.get("hunger", GameState.hunger))
	_stamina = float(d.get("stamina", GameState.stamina))
	_soft = false
	_announced = false
	_save_acc = 0.0
	return true


static func _save() -> void:
	GameState.ext_set(EXT_KEY, {"left": snappedf(_left, 0.1), "total": snappedf(_total, 0.1), "depth": _depth,
		"hunger": snappedf(_hunger, 0.1), "stamina": snappedf(_stamina, 0.1)})


## Статика переживает перезагрузку сцены — main.gd сбрасывает её в _exit_tree.
static func reset() -> void:
	_active = false
	_left = 0.0
	_total = 0.0
	_depth = 0
	_soft = true
	_announced = true
	_save_acc = 0.0

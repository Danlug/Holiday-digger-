class_name RecordsStore
extends Node
## Локальные рекорды игрока (ГДД раздел 17 — но без бэкенда).
##
## ГДД прямо говорит, что лидерборды требуют сервера и не входят в первую
## версию. Поэтому здесь считается ровно то, что можно честно посчитать на
## устройстве: максимальная глубина, богатство, доля открытых минералов и
## артефактов, развитие. Когда появится сервер, эти же четыре числа уедут в
## запрос — формат специально совпадает с четырьмя топами из ГДД.
##
## ПОЧЕМУ свой файл user://records.json, а не общий сейв: save_system.gd —
## общий для всех систем, и дописывание туда полей означает миграцию схемы и
## конфликт с другими агентами. Рекорды же ни на что в игре не влияют: их
## потеря не ломает прохождение, а отдельный файл не трогает чужие данные.

const PATH := "user://records.json"
const SCHEMA_VERSION := 1

signal records_changed

var lifetime_coins_earned: int = 0   # сколько монет заработано за всё время
var lifetime_hauled_value: int = 0   # стоимость всего вынесенного на поверхность
var best_haul_value: int = 0         # самая дорогая единичная ходка
var best_level: int = 1
var discovered_minerals: Array = []  # id минералов, которые игрок хоть раз выкопал

var _player: Node = null
var _prev_coins: int = 0
var _was_underground: bool = false
# Стоимость рюкзака, уже засчитанная в вынесенное. Без этого каждый выход на
# поверхность с тем же рюкзаком засчитывался бы заново, и "богатство" росло
# от одного хождения вверх-вниз.
var _credited_haul: int = 0


func _ready() -> void:
	load_records()
	_prev_coins = GameState.coins
	best_level = maxi(best_level, GameState.level)
	GameState.coins_changed.connect(_on_coins_changed)
	GameState.xp_changed.connect(_on_xp_changed)
	# Кнопка «Сброс» обнуляет прогресс и присылает max_depth_changed(0).
	# Отдельного сигнала сброса в GameState нет, а глубина сама по себе
	# только растёт — значит ноль приходит ровно один раз и ровно на сбросе.
	GameState.max_depth_changed.connect(_on_max_depth_changed)


func setup(player: Node) -> void:
	_player = player
	if player != null and not player.dig_finished.is_connected(_on_dig_finished):
		player.dig_finished.connect(_on_dig_finished)


func _process(_dt: float) -> void:
	if _player == null:
		return
	var underground: bool = _player.cell_y() > 0
	if _was_underground and not underground:
		_credit_haul()
	_was_underground = underground


# ---------------------------------------------------------------------------
# Сбор чисел
# ---------------------------------------------------------------------------

func _on_coins_changed(coins: int) -> void:
	if coins > _prev_coins:
		lifetime_coins_earned += coins - _prev_coins
		records_changed.emit()
	_prev_coins = coins


func _on_xp_changed(_xp: int, level: int) -> void:
	if level > best_level:
		best_level = level
		records_changed.emit()


func _on_dig_finished(_x: int, _y: int, _tile_type: int, mineral_id: String, _was_loot: bool, _coins: int) -> void:
	if mineral_id.is_empty() or discovered_minerals.has(mineral_id):
		return
	discovered_minerals.append(mineral_id)
	records_changed.emit()


## Засчитывает поднятое на поверхность. Считается прирост относительно уже
## засчитанного: рюкзак не опустошается сам (магазин делает другая система),
## поэтому в зачёт идёт только то, что появилось после прошлого подъёма.
func _credit_haul() -> void:
	var value := current_inventory_value()
	if value > _credited_haul:
		lifetime_hauled_value += value - _credited_haul
		records_changed.emit()
	best_haul_value = maxi(best_haul_value, value)
	_credited_haul = value
	save_records()


func current_inventory_value() -> int:
	var total := 0
	for id in GameState.inventory.keys():
		total += Balance.get_mineral_price(id) * int(GameState.inventory[id])
	return total


# ---------------------------------------------------------------------------
# Итоговые показатели — те же четыре топа, что в ГДД разделе 17
# ---------------------------------------------------------------------------

func get_max_depth() -> int:
	return GameState.max_depth_reached


## Богатство: заработанные монеты плюс стоимость всего, что реально вынесено
## наверх. Доход буровой скважины (ГДД п.17) прибавится сюда же, когда idle
## появится, — отдельной строкой в сумме.
func get_wealth() -> int:
	return lifetime_coins_earned + lifetime_hauled_value


## Сколько всего минералов вообще можно встретить в мире: у не добываемых
## (бронза плавится из металлолома) плотности нет, и в знаменатель они не идут
## — иначе 100% недостижимы в принципе.
func get_total_minerals() -> int:
	var count := 0
	for m in Balance.minerals.get("minerals", []):
		if m.get("density", null) != null:
			count += 1
	return maxi(count, 1)


func get_discovered_minerals_count() -> int:
	return discovered_minerals.size()


func get_minerals_percent() -> float:
	return 100.0 * float(get_discovered_minerals_count()) / float(get_total_minerals())


func get_total_artifacts() -> int:
	return maxi(Balance.artifacts.get("artifacts", []).size(), 1)


func get_artifacts_percent() -> float:
	return 100.0 * float(GameState.collected_artifacts.size()) / float(get_total_artifacts())


## «Топ по развитию» из ГДД: уровень плюс вложенные очки прокачки — одно
## число, по которому можно сравнивать игроков, когда появится сервер.
func get_development_score() -> int:
	var spent := 0
	for branch_id in GameState.skill_stages.keys():
		spent += Balance.get_upgrade_total_cost(String(branch_id), int(GameState.skill_stages[branch_id]))
	return GameState.level * 10 + spent


func get_spent_points() -> int:
	var spent := 0
	for branch_id in GameState.skill_stages.keys():
		spent += Balance.get_upgrade_total_cost(String(branch_id), int(GameState.skill_stages[branch_id]))
	return spent


# ---------------------------------------------------------------------------
# Хранение
# ---------------------------------------------------------------------------

func reset() -> void:
	lifetime_coins_earned = 0
	lifetime_hauled_value = 0
	best_haul_value = 0
	best_level = 1
	discovered_minerals.clear()
	_credited_haul = 0
	_prev_coins = GameState.coins
	save_records()
	records_changed.emit()


func _on_max_depth_changed(depth: int) -> void:
	if depth == 0:
		reset()


func save_records() -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("RecordsStore: не открыть %s на запись (код %d)" % [PATH, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify({
		"version": SCHEMA_VERSION,
		"lifetime_coins_earned": lifetime_coins_earned,
		"lifetime_hauled_value": lifetime_hauled_value,
		"best_haul_value": best_haul_value,
		"best_level": best_level,
		"discovered_minerals": discovered_minerals,
		"credited_haul": _credited_haul,
	}, "\t"))
	f.close()
	return true


func load_records() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_warning("RecordsStore: %s повреждён — рекорды начаты заново" % PATH)
		return false
	var data: Dictionary = parsed
	lifetime_coins_earned = int(data.get("lifetime_coins_earned", 0))
	lifetime_hauled_value = int(data.get("lifetime_hauled_value", 0))
	best_haul_value = int(data.get("best_haul_value", 0))
	best_level = int(data.get("best_level", 1))
	discovered_minerals = data.get("discovered_minerals", [])
	_credited_haul = int(data.get("credited_haul", 0))
	return true

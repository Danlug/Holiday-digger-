extends Node
## GameState — автолоад состояния игрока.
##
## Хранит HP/голод/бодрость, опыт и прокачку, валюты, инвентарь с весом и
## стаками, чёрный ящик, текущий инструмент, максимальную глубину, собранные
## артефакты и дневные лимиты рекламы. Формулы берёт из автолоада Balance.
##
## КРИТИЧНО (см. GDD п.7, 15): дневной сброс лимитов рекламы считается по
## РЕАЛЬНОМУ времени (UTC-полночь), а не по игровому дню/часам — иначе игрок
## спамит мгновенный сон (который прыгает игровые часы вперёд бесплатно) и
## бесконечно фармит рекламные награды. last_reset_utc_date хранит именно
## календарную UTC-дату реального мира.

signal hp_changed(hp: float, max_hp: float)
signal stamina_changed(stamina: float)
signal hunger_changed(hunger: float)
signal died
signal respawned
signal xp_changed(xp: int, level: int)
signal leveled_up(new_level: int, points_awarded: int)
signal skill_points_changed(available: int)
signal coins_changed(coins: int)
signal dollars_changed(dollars: int)
signal inventory_changed
signal black_box_changed
signal artifact_collected(artifact_id: String)
signal branch_completed(branch_num: int)
signal tool_changed(tool_id: String)
signal max_depth_changed(depth: int)
signal daily_reset

const AUTOSAVE_INTERVAL_SEC := 60.0

# --- Выживание ---
var hp: float = 100.0
var stamina: float = 100.0  # проценты 0..100
var hunger: float = 100.0   # проценты 0..100
var is_digging: bool = false  # ставится извне (player-контроллером) каждый кадр
var is_alive: bool = true

# --- Прокачка ---
var xp: int = 0
var level: int = 1
var skill_points_available: int = 0
var skill_stages: Dictionary = {}  # branch_id:String -> stage:int

# --- Валюты ---
var coins: int = 0
var dollars: int = 0  # премиум-валюта

# --- Инвентарь ---
var inventory: Dictionary = {}  # mineral_id:String -> count:int
var black_box_tier: String = "base"  # base | premium | premium_plus
var black_box: Dictionary = {}  # mineral_id:String -> count:int

# --- Инструмент и прогресс ---
var current_tool: String = "shovel"
var max_depth_reached: int = 0
var collected_artifacts: Array = []  # артефакт id
var completed_branches: Array = []   # номера веток

# --- Время ---
var game_clock_hours: float = 0.0  # накопленное игровое время с начала игры

# --- Дневные лимиты рекламы (сброс по реальному UTC-дню, см. шапку файла) ---
var ad_daily_counts: Dictionary = {}  # ad_id:String -> использовано раз сегодня
var last_reset_utc_date: String = ""

var _autosave_timer: Timer


func _ready() -> void:
	_check_daily_reset()
	SaveSystem.load_game()
	_start_autosave_timer()


func _process(delta: float) -> void:
	if not is_alive:
		return
	_tick_survival(delta)
	_tick_game_clock(delta)
	_check_daily_reset()


func _start_autosave_timer() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_SEC
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(func(): SaveSystem.save_game())
	add_child(_autosave_timer)


# ---------------------------------------------------------------------------
# Выживание: расход полосок, утечка HP, смерть (см. GDD раздел 7)
# ---------------------------------------------------------------------------

func _tick_survival(delta: float) -> void:
	var stamina_rate := Balance.get_bar_depletion_rate_per_second("stamina", is_digging)
	var hunger_rate := Balance.get_bar_depletion_rate_per_second("hunger", is_digging)
	set_stamina(stamina - stamina_rate * 100.0 * delta)
	set_hunger(hunger - hunger_rate * 100.0 * delta)

	var empty_bars := 0
	if stamina <= 0.0:
		empty_bars += 1
	if hunger <= 0.0:
		empty_bars += 1
	if empty_bars > 0:
		var drain_per_sec := Balance.get_hp_drain_per_second_when_depleted() * empty_bars
		take_damage(drain_per_sec * delta, "starvation")


func set_stamina(value: float) -> void:
	stamina = clamp(value, 0.0, 100.0)
	stamina_changed.emit(stamina)


func set_hunger(value: float) -> void:
	hunger = clamp(value, 0.0, 100.0)
	hunger_changed.emit(hunger)


func take_damage(amount: float, _source: String = "") -> void:
	if not is_alive or amount <= 0.0:
		return
	hp = clamp(hp - amount, 0.0, get_max_hp())
	hp_changed.emit(hp, get_max_hp())
	if hp <= 0.0:
		die()


func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	hp = clamp(hp + amount, 0.0, get_max_hp())
	hp_changed.emit(hp, get_max_hp())


func apply_fall_damage(height_cells: float) -> void:
	take_damage(Balance.get_fall_damage(height_cells), "fall")


func get_max_hp() -> float:
	return float(Balance.get_max_hp(get_skill_stage("hp")))


## Смерть: теряются все минералы, кроме чёрного ящика (см. GDD раздел 7).
func die() -> void:
	if not is_alive:
		return
	is_alive = false
	inventory.clear()
	inventory_changed.emit()
	died.emit()


## Респавн дома: восстанавливает полоски выживания. Позицию героя и анимацию
## ставит сцена/игрок-контроллер (не входит в зону ответственности GameState).
func respawn() -> void:
	is_alive = true
	hp = get_max_hp()
	stamina = 100.0
	hunger = 100.0
	hp_changed.emit(hp, get_max_hp())
	stamina_changed.emit(stamina)
	hunger_changed.emit(hunger)
	respawned.emit()


# ---------------------------------------------------------------------------
# Игровое время и сон (см. GDD раздел 7)
# ---------------------------------------------------------------------------

func _tick_game_clock(delta_real_sec: float) -> void:
	var game_hours_per_real_hour := Balance.get_game_hours_per_real_hour()
	game_clock_hours += (delta_real_sec / 3600.0) * game_hours_per_real_hour


## Сон: анимация пропускается (см. GDD раздел 7), время сразу "прыгает".
## hours меньше минимума поднимается до минимума (2 игровых часа = 25%).
func sleep(hours: float) -> void:
	var min_hours := Balance.get_min_sleep_game_hours()
	var actual_hours: float = max(hours, min_hours)
	var restore_percent := Balance.get_sleep_restore_percent_per_game_hour() * actual_hours
	set_stamina(stamina + restore_percent)
	game_clock_hours += actual_hours


# ---------------------------------------------------------------------------
# Опыт и прокачка (см. GDD раздел 11)
# ---------------------------------------------------------------------------

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	xp_changed.emit(xp, level)
	_check_level_up()


func _check_level_up() -> void:
	var level_cap := int(Balance.upgrades.get("xp_formula", {}).get("level_cap", 100))
	while level < level_cap and xp >= _xp_needed_for_next_level():
		xp -= _xp_needed_for_next_level()
		level += 1
		var points_awarded := int(Balance.upgrades.get("skill_points", {}).get("per_level", 1))
		if level % 5 == 0:
			points_awarded += int(Balance.upgrades.get("skill_points", {}).get("bonus_every_5th_level", 2))
		skill_points_available += points_awarded
		leveled_up.emit(level, points_awarded)
		skill_points_changed.emit(skill_points_available)
		xp_changed.emit(xp, level)


func _xp_needed_for_next_level() -> int:
	return Balance.xp_required_for_level(level)


func get_skill_stage(branch_id: String) -> int:
	return int(skill_stages.get(branch_id, 0))


## Тратит одно очко прокачки на следующую ступень ветки branch_id.
## Возвращает false, если очков не хватает или ветка уже на максимуме.
func spend_skill_point(branch_id: String) -> bool:
	var branch := Balance.get_upgrade_branch(branch_id)
	if branch.is_empty():
		return false
	var max_stages := int(branch.get("stages", 0))
	var current_stage := get_skill_stage(branch_id)
	if current_stage >= max_stages:
		return false
	var cost := Balance.get_upgrade_stage_cost(branch_id, current_stage + 1)
	if cost < 0 or skill_points_available < cost:
		return false
	skill_points_available -= cost
	skill_stages[branch_id] = current_stage + 1
	skill_points_changed.emit(skill_points_available)
	return true


# ---------------------------------------------------------------------------
# Валюты
# ---------------------------------------------------------------------------

func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	coins_changed.emit(coins)


func spend_coins(amount: int) -> bool:
	if amount <= 0 or coins < amount:
		return false
	coins -= amount
	coins_changed.emit(coins)
	return true


func add_dollars(amount: int) -> void:
	if amount <= 0:
		return
	dollars += amount
	dollars_changed.emit(dollars)


func spend_dollars(amount: int) -> bool:
	if amount <= 0 or dollars < amount:
		return false
	dollars -= amount
	dollars_changed.emit(dollars)
	return true


# ---------------------------------------------------------------------------
# Инвентарь: вес и стаки (см. GDD раздел 14)
# ---------------------------------------------------------------------------

func get_total_weight() -> float:
	var total := 0.0
	for id in inventory.keys():
		total += Balance.get_mineral_weight(id) * int(inventory[id])
	return total


func get_max_carry_kg() -> float:
	return Balance.get_max_carry_kg(get_skill_stage("strength"))


## Пытается положить count единиц mineral_id в инвентарь, учитывая макс. стак
## (99 по умолчанию) и грузоподъёмность. Возвращает реально добавленное
## количество (может быть меньше count, если не хватило места/веса).
func add_item(id: String, count: int) -> int:
	if count <= 0:
		return 0
	var max_stack := Balance.get_mineral_max_stack(id)
	var weight_each := Balance.get_mineral_weight(id)
	var current_count := int(inventory.get(id, 0))
	var room_by_stack: int = max(0, max_stack - current_count)

	var room_by_weight := count
	if weight_each > 0.0:
		var free_weight: float = get_max_carry_kg() - get_total_weight()
		room_by_weight = int(floor(free_weight / weight_each)) if free_weight > 0.0 else 0

	var to_add: int = min(count, min(room_by_stack, room_by_weight))
	if to_add <= 0:
		return 0
	inventory[id] = current_count + to_add
	inventory_changed.emit()
	return to_add


func remove_item(id: String, count: int) -> bool:
	var current_count := int(inventory.get(id, 0))
	if count <= 0 or current_count < count:
		return false
	var remaining := current_count - count
	if remaining <= 0:
		inventory.erase(id)
	else:
		inventory[id] = remaining
	inventory_changed.emit()
	return true


func get_item_count(id: String) -> int:
	return int(inventory.get(id, 0))


# --- Чёрный ящик: содержимое гарантированно возвращается при смерти ---

func set_black_box_tier(tier: String) -> void:
	black_box_tier = tier
	black_box_changed.emit()


func get_black_box_capacity() -> int:
	return Balance.get_black_box_capacity(black_box_tier)


## Кладёт count единиц mineral_id в чёрный ящик. Каждый вид минерала занимает
## одну ячейку (клетку) ящика; клетки ящика в грузоподъёмность не входят
## (см. GDD раздел 14). Возвращает реально добавленное количество.
func add_to_black_box(id: String, count: int) -> int:
	if count <= 0:
		return 0
	var capacity := get_black_box_capacity()
	var current_count := int(black_box.get(id, 0))
	if current_count == 0 and black_box.size() >= capacity:
		return 0
	var max_stack := Balance.get_mineral_max_stack(id)
	var to_add: int = min(count, max(0, max_stack - current_count))
	if to_add <= 0:
		return 0
	black_box[id] = current_count + to_add
	black_box_changed.emit()
	return to_add


func remove_from_black_box(id: String, count: int) -> bool:
	var current_count := int(black_box.get(id, 0))
	if count <= 0 or current_count < count:
		return false
	var remaining := current_count - count
	if remaining <= 0:
		black_box.erase(id)
	else:
		black_box[id] = remaining
	black_box_changed.emit()
	return true


# ---------------------------------------------------------------------------
# Инструмент, глубина, артефакты
# ---------------------------------------------------------------------------

func set_current_tool(tool_id: String) -> void:
	current_tool = tool_id
	tool_changed.emit(tool_id)


func update_max_depth(depth: int) -> void:
	if depth > max_depth_reached:
		max_depth_reached = depth
		max_depth_changed.emit(max_depth_reached)


func collect_artifact(artifact_id: String) -> void:
	if collected_artifacts.has(artifact_id):
		return
	collected_artifacts.append(artifact_id)
	add_xp(Balance.get_artifact_find_xp(artifact_id))
	add_coins(Balance.get_artifact_find_coins(artifact_id))
	artifact_collected.emit(artifact_id)

	var artifact := Balance.get_artifact(artifact_id)
	var branch_num := int(artifact.get("branch", -1))
	if branch_num > 0 and not completed_branches.has(branch_num):
		if Balance.is_branch_complete(branch_num, collected_artifacts):
			completed_branches.append(branch_num)
			var reward := _find_branch_completion_reward(branch_num)
			add_coins(int(Balance.unwrap(reward.get("coins", 0))))
			add_dollars(int(Balance.unwrap(reward.get("premium_currency", 0))))
			branch_completed.emit(branch_num)


func _find_branch_completion_reward(branch_num: int) -> Dictionary:
	for b in Balance.artifacts.get("branches", []):
		if int(b.get("branch", -1)) == branch_num:
			return b.get("completion_reward", {})
	return {}


# ---------------------------------------------------------------------------
# Дневные лимиты рекламы — сброс по РЕАЛЬНОМУ UTC-дню (см. шапку файла)
# ---------------------------------------------------------------------------

static func _current_utc_date_string() -> String:
	var d := Time.get_datetime_dict_from_system(true)  # true = UTC
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func _check_daily_reset() -> void:
	var today := _current_utc_date_string()
	if last_reset_utc_date != today:
		last_reset_utc_date = today
		ad_daily_counts.clear()
		daily_reset.emit()


func get_ad_uses_today(ad_id: String) -> int:
	return int(ad_daily_counts.get(ad_id, 0))


## Пытается засчитать использование рекламной награды ad_id. Возвращает false,
## если дневной лимит (Balance.get_ad_daily_limit) уже исчерпан.
func try_use_ad_reward(ad_id: String) -> bool:
	_check_daily_reset()
	var limit := Balance.get_ad_daily_limit(ad_id)
	var used := get_ad_uses_today(ad_id)
	if used >= limit:
		return false
	ad_daily_counts[ad_id] = used + 1
	return true


# ---------------------------------------------------------------------------
# Интерфейс для мира (owner: scripts/world/, не входит в мою зону)
# ---------------------------------------------------------------------------

## Диффы выкопанных клеток мира. Мир детерминирован от сида и генерируется
## отдельным модулем (scripts/world/) — GameState лишь хранит и сохраняет
## список изменений (что выкопано), не саму карту (см. GDD, save_system.gd).
var world_dug_cells: Dictionary = {}  # "x,y":String -> Dictionary (что было на клетке)


func mark_cell_dug(x: int, y: int, cell_data: Dictionary = {}) -> void:
	world_dug_cells["%d,%d" % [x, y]] = cell_data


func is_cell_dug(x: int, y: int) -> bool:
	return world_dug_cells.has("%d,%d" % [x, y])


func get_dug_cells() -> Dictionary:
	return world_dug_cells


func load_dug_cells(cells: Dictionary) -> void:
	world_dug_cells = cells

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


## Полный сброс прогресса игрока (кнопка ↺ в нижней полосе — отладочный "новый
## огород", как в web-демо). Мир/туман main.gd сбрасывает отдельно (это его
## зона ответственности), здесь — только то, что принадлежит GameState.
func reset_progress() -> void:
	hp = get_max_hp()
	stamina = 100.0
	hunger = 100.0
	is_alive = true
	xp = 0
	level = 1
	skill_points_available = 0
	skill_stages.clear()
	coins = 0
	dollars = 0
	inventory.clear()
	black_box.clear()
	current_tool = "shovel"
	max_depth_reached = 0
	collected_artifacts.clear()
	completed_branches.clear()
	game_clock_hours = 0.0
	world_dug_cells.clear()
	reset_economy()
	hp_changed.emit(hp, get_max_hp())
	stamina_changed.emit(stamina)
	hunger_changed.emit(hunger)
	xp_changed.emit(xp, level)
	skill_points_changed.emit(skill_points_available)
	coins_changed.emit(coins)
	dollars_changed.emit(dollars)
	inventory_changed.emit()
	black_box_changed.emit()
	tool_changed.emit(current_tool)
	max_depth_changed.emit(max_depth_reached)


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


## Радиусы аур тумана войны (ГДД раздел 12): большая — рельеф, маленькая —
## ресурсы. Растут прокачкой веток terrain_vision/resource_vision.
func get_vision_terrain_radius() -> int:
	return Balance.get_vision_radius("terrain_vision", get_skill_stage("terrain_vision"))


func get_vision_resource_radius() -> int:
	return Balance.get_vision_radius("resource_vision", get_skill_stage("resource_vision"))


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
	# Ступени инструментов покупаются и крафтятся (ГДД п.5), а не выдаются по
	# глубине: иначе кирка и бур приходят сами, и весь смысл копить сырьё
	# исчезает. Владение проверяется здесь, в единственной точке смены
	# инструмента, — см. блок "экономика" в конце файла.
	if not owns_tool(tool_id):
		tool_purchase_required.emit(tool_id)
		return
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

## Ссылки на живые экземпляры мира/тумана, которые создаёт и владеет main.gd.
## GameState сам карту не хранит (мир детерминирован от сида, см. world_gen.gd)
## — но SaveSystem должен где-то достать их диффы для записи в user://save.json,
## а автолоад — единственное место, доступное отовсюду без явной прокидки.
## Пока main.gd не назначил эти поля (например, в headless-тестах баланса),
## SaveSystem просто пропускает сохранение/загрузку мира — это ожидаемо.
var world_ref: WorldGen = null
var fog_ref: FogOfWar = null

## Сид генерации мира (см. world_gen.gd) — должен быть стабилен между
## запусками, иначе сохранённые диффы "выкопано" разъедутся с новой
## генерацией. 0 значит "ещё не назначен"; main.gd просит один при первом
## запуске через ensure_world_seed() ДО создания WorldGen.
var world_seed: int = 0


func ensure_world_seed() -> int:
	if world_seed == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		world_seed = rng.randi() | 1  # нечётный: 0 зарезервирован под "не назначен"
	return world_seed

## Диффы выкопанных клеток мира — запасной путь, если world_ref не назначен
## (например, старый сейв или тест). В обычной игре не используется: реальный
## источник правды — world_ref.diffs/events (см. save_system.gd).
var world_dug_cells: Dictionary = {}  # "x,y":String -> Dictionary (что было на клетке)


func mark_cell_dug(x: int, y: int, cell_data: Dictionary = {}) -> void:
	world_dug_cells["%d,%d" % [x, y]] = cell_data


func is_cell_dug(x: int, y: int) -> bool:
	return world_dug_cells.has("%d,%d" % [x, y])


func get_dug_cells() -> Dictionary:
	return world_dug_cells


func load_dug_cells(cells: Dictionary) -> void:
	world_dug_cells = cells


# ---------------------------------------------------------------------------
# --- дом и выживание ---
# Блок системы дома (scripts/house/): интерьер, сон, еда, переходы дом↔огород.
# Поля добавлены отдельным блоком в конец файла; существующие поля выше не
# переименованы и не переставлены. Здесь лежит только СОСТОЯНИЕ — вся логика
# в scripts/house/, потому что GameState обязан оставаться загружаемым в
# headless-тестах без сцены дома.
# ---------------------------------------------------------------------------

## Герой внутри дома: мир и HUD скрыты, физика героя заморожена.
## Флаг нужен не только интерфейсу — по нему другие системы поймут, что
## герой недосягаем для событий шахты (обвал под домом его не касается).
var house_is_indoors: bool = false

## Комната, в которой стоит герой: bedroom | hall | workshop | museum |
## peat_still | basement. Хранится в состоянии, а не в UI: после смерти и
## обучения система сама ставит героя в нужную комнату.
var house_room: String = "hall"

## Заказанная еда, которая уже доставлена и ждёт у входной двери
## (food_id -> порций). Лежит именно здесь, а не в инвентаре: по ГДД п.7
## доставка приходит К ДВЕРИ, забрать её нужно отдельным действием — иначе
## заказ из шахты телепортировал бы еду в рюкзак.
var house_food_at_door: Dictionary = {}

## Сколько бесплатных доставок («деньги, оставленные бабкой») израсходовано
## за сегодня. Обнуляется по сигналу daily_reset, то есть по РЕАЛЬНЫМ суткам:
## мгновенный сон прокручивает игровые часы, и привязка к игровому дню
## позволила бы кормиться бесплатно сколько угодно.
var house_free_orders_used_today: int = 0

## Люк из подвала на клетку (15, 6) построен (его строит Роберт, ГДД п.9).
## Пока false — из подвала в шахту хода нет, и выход из дома только через дверь.
var house_hatch_built: bool = false

## Огород закрыт бабкой после квеста с Робертом (ГДД п.3): копать с поверхности
## больше нельзя, вход в копальню — только через люк. Сцену с Робертом делает
## другая система, здесь только флаг, на который она переключит мир.
var house_garden_closed: bool = false

## Стадия обучения сну и еде (ГДД п.9): 0 — ещё не было истощения,
## 1 — первое истощение отработано (принудительный сон в кровати),
## 2 — второе истощение отработано (принудительный батончик в шахте).
var house_tutorial_stage: int = 0

## Отдел допингов в магазине открыт (ГДД п.9: открывается после второго
## истощения). Флаг для системы магазина, которую делает другая система.
var house_dopings_shop_unlocked: bool = false


# ---------------------------------------------------------------------------
# --- экономика ---
# Блок системы магазина/мастерской (scripts/shop/): владение инструментами,
# первый визит в мастерскую, одноразовое удвоение продажи с рекламы и счётчик
# заработанного. Поля добавлены отдельным блоком в конец файла; существующие
# поля выше не переименованы и не переставлены. Здесь только СОСТОЯНИЕ — вся
# логика продажи и крафта живёт в scripts/shop/shop_service.gd, чтобы
# GameState оставался загружаемым в headless-тестах без сцены магазина.
# ---------------------------------------------------------------------------

## Инструмент, за который надо платить, попросили надеть, не купив его.
## Сигнал нужен магазину: он объясняет игроку, что ступень инструмента теперь
## собирается на верстаке, а не выдаётся по глубине.
signal tool_purchase_required(tool_id: String)

## Инструменты, которые игрок реально получил. Лопата есть с самого начала
## (ГДД п.5: "acquired: старт игры"), дедова кирка приходит квестом мастерской,
## остальное — покупка и крафт.
var owned_tools: Array = ["shovel"]

## Игрок уже спускался в мастерскую. Первый спуск — сюжетная сцена с дедовой
## киркой среди швабр и грабель (ГДД п.2), поэтому её нельзя выдать дважды.
var workshop_visited: bool = false

## Реклама "удвоить доход при продаже" (ГДД п.15) заряжена на ОДНУ сделку.
## Хранится в состоянии, а не в UI: игрок смотрит ролик в магазине долларов,
## а продаёт потом, уже в другой вкладке.
var next_sale_doubled: bool = false

## Сколько монет всего принесла продажа сырья. Нужно не для баланса, а для
## лидерборда "топ по богатству" (ГДД п.17) и для проверки экономики на
## живых цифрах: монеты тратятся, и по текущему кошельку не видно, сколько
## шахта принесла на самом деле.
var lifetime_coins_from_sales: int = 0


## Есть ли инструмент на руках. Бесплатные ступени (лопата, дедова кирка)
## владением не гейтятся: они приходят по сюжету, а не из магазина, — иначе
## герой остался бы под фундаментом с одной лопатой, пока не найдёт монеты.
func owns_tool(tool_id: String) -> bool:
	if owned_tools.has(tool_id):
		return true
	return is_tool_free(tool_id)


## Инструмент ничего не стоит (нет статьи cost или в ней одни нули).
func is_tool_free(tool_id: String) -> bool:
	var cost = Balance.unwrap(Balance.get_tool(tool_id).get("cost", {}))
	if typeof(cost) != TYPE_DICTIONARY:
		return true
	for key in cost.keys():
		if int(Balance.unwrap(cost[key])) > 0:
			return false
	return true


## Выдать инструмент (крафт на верстаке, покупка, сюжетная находка).
func grant_tool(tool_id: String) -> void:
	if owned_tools.has(tool_id):
		return
	owned_tools.append(tool_id)


## Материалы, вложенные в конкретный рецепт верстака:
## recipe_id -> {item_id: количество}.
##
## Нужны потому, что железная кирка по ГДД п.5 стоит 25 железа, 10 бронзы и
## 30 свинца — это 160 кг при грузоподъёмности 60 кг, и принести их за одну
## ходку невозможно физически. Общего склада в игре нет и быть не должно
## (ГДД п.14: сундук на поверхности отменён), поэтому материал кладётся не
## "на склад", а В САМ ПРОЕКТ: вложенное назад не достаётся и продать его
## нельзя, так что хранилищем это не работает.
var craft_invested: Dictionary = {}


## Сколько материала id уже вложено в рецепт recipe_id.
func get_invested(recipe_id: String, item_id: String) -> int:
	return int(Dictionary(craft_invested.get(recipe_id, {})).get(item_id, 0))


func add_invested(recipe_id: String, item_id: String, count: int) -> void:
	if count <= 0:
		return
	var project: Dictionary = craft_invested.get(recipe_id, {})
	project[item_id] = int(project.get(item_id, 0)) + count
	craft_invested[recipe_id] = project


## Проект собран — вложенное израсходовано.
func clear_invested(recipe_id: String) -> void:
	craft_invested.erase(recipe_id)


## Сброс экономической части прогресса. Вызывается из reset_progress(), чтобы
## кнопка "Сброс" не оставляла игроку купленные кирки в новом огороде.
func reset_economy() -> void:
	owned_tools = ["shovel"]
	workshop_visited = false
	next_sale_doubled = false
	lifetime_coins_from_sales = 0
	craft_invested.clear()


# ---------------------------------------------------------------------------
# --- сюжет ---
# Память катсцен и обучения (см. scripts/story/). Живёт здесь, а не в самом
# сюжетном модуле, чтобы дом, магазин и игрок читали её одной строкой —
# GameState.story_flags.get("hatch_built") и подобное — не подключая к себе
# режиссёра. Пишет и читает эти поля StoryState, он же дублирует их на диск
# в user://story.json (в общий сейв они не идут: катсцену надо запоминать в
# момент показа, а не на ближайшем автосейве через минуту).
# ---------------------------------------------------------------------------

var story_flags: Dictionary = {}   # id флага -> true
var story_seen: Array = []         # id уже показанных катсцен
var story_queue: Array = []        # id сцен, которые ждут показа

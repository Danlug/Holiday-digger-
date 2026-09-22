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
signal gear_changed(gear_id: String)
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
## Бурмобиль, припаркованный на поверхности у устья тоннеля, как объект мира
## (решение владельца: посадка не автоматическая — герой пешком подходит к
## припаркованной машине и садится кнопкой "В бурмобиль", см. HouseSystem и
## player.gd "Бурмобиль как транспорт"). (-1, -1) — машина не запаркована:
## либо ещё не куплена, либо герой в ней прямо сейчас (current_tool ==
## "drill_rig") — тогда парковки не существует, машина "надета".
var rig_parked_at: Vector2i = Vector2i(-1, -1)
## Надетая ступень ранца ("" — летать нечем). Ровно одна активная: владелец
## переписал ранцы в линейку из четырёх ступеней, где надетую выбирают на
## верстаке. Хранится рядом с current_tool, потому что это ровно такой же
## выбор — только не для рук, а для спины.
var current_gear: String = ""
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

signal exhausted_changed(exhausted: bool)
signal survival_warning(bar: String, severe: bool)

var is_exhausted: bool = false
# Что уже показали, чтобы не мигать красным каждый кадр. Сбрасывается, когда
# полоска поднимется выше порога — предупреждение должно прийти снова, если
# игрок снова довёл себя до того же.
var _warned: Dictionary = {}


func _tick_survival(delta: float) -> void:
	var stamina_rate := Balance.get_bar_depletion_rate_per_second("stamina", is_digging)
	var hunger_rate := Balance.get_bar_depletion_rate_per_second("hunger", is_digging)

	# Обессиленный ест больше: усталость не убивает сама, но ускоряет голод,
	# который убивает. Штраф считается по состоянию НА НАЧАЛО кадра, иначе
	# полоска, упавшая в ноль этим же кадром, штрафует задним числом.
	var was_exhausted := stamina <= 0.0
	if was_exhausted and is_digging:
		hunger_rate *= Balance.get_exhausted_hunger_multiplier()

	set_stamina(stamina - stamina_rate * 100.0 * delta)
	set_hunger(hunger - hunger_rate * 100.0 * delta)

	_update_exhausted()
	_check_survival_warnings()

	# Голод и бодрость наказывают по-разному (ГДД раздел 7): голод убивает,
	# усталость мешает. Пустая бодрость сама по себе HP не трогает.
	var drain := Balance.get_hp_drain_per_second(hunger <= 0.0, stamina <= 0.0)
	if drain > 0.0:
		take_damage(drain * delta, "starvation")


func _update_exhausted() -> void:
	var now := stamina <= 0.0
	if now == is_exhausted:
		return
	is_exhausted = now
	exhausted_changed.emit(now)


## Множитель ко всем скоростям героя. Копка, ходьба и полёт спрашивают его
## сами — так штраф нельзя забыть применить в одном из трёх мест.
func get_speed_multiplier() -> float:
	return Balance.get_exhausted_speed_multiplier() if is_exhausted else 1.0


func _check_survival_warnings() -> void:
	for bar in ["hunger", "stamina"]:
		var value: float = hunger if bar == "hunger" else stamina
		for severe in [true, false]:
			var key: String = bar + ("_severe" if severe else "_notice")
			var threshold := Balance.get_warning_percent(severe)
			if value <= threshold and not _warned.get(key, false):
				_warned[key] = true
				survival_warning.emit(bar, severe)
			# Порог отпускается с запасом, иначе дрожание вокруг него
			# устроит мигание на каждом кадре.
			elif value > threshold + 5.0 and _warned.get(key, false):
				_warned[key] = false


func set_stamina(value: float) -> void:
	stamina = clamp(value, 0.0, 100.0)
	stamina_changed.emit(stamina)


func set_hunger(value: float) -> void:
	hunger = clamp(value, 0.0, 100.0)
	hunger_changed.emit(hunger)


func take_damage(amount: float, _source: String = "") -> void:
	if not is_alive or amount <= 0.0:
		return
	# Отладочный тумблер «Бессмертие» (debug_panel.gd): урон игнорируется
	# целиком, HP не восстанавливается принудительно — единственная точка,
	# где HP вообще снижается (падение, голод и всё будущее туда же), так что
	# гейт здесь перекрывает все источники разом.
	if debug_invincible:
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
	current_gear = ""
	rig_parked_at = Vector2i(-1, -1)
	max_depth_reached = 0
	player_depth = 0
	collected_artifacts.clear()
	completed_branches.clear()
	game_clock_hours = 0.0
	world_dug_cells.clear()
	pending_earthquake = false
	reset_economy()
	reset_house()
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
	gear_changed.emit(current_gear)
	max_depth_changed.emit(max_depth_reached)


# ---------------------------------------------------------------------------
# Игровое время и сон (см. GDD раздел 7)
# ---------------------------------------------------------------------------

func _tick_game_clock(delta_real_sec: float) -> void:
	var game_hours_per_real_hour := Balance.get_game_hours_per_real_hour()
	# DayCycle.time_scale — сценарии (интро деда и т.п.), которые гонят часы
	# быстрее обычного, чтобы прогнать день за секунды показа. Часы двигает
	# ТОЛЬКО эта строка — DayCycle сам собственного счётчика не ведёт (см.
	# шапку day_cycle.gd), иначе game_clock_hours сдвигался бы дважды за
	# кадр и рассинхронил бы сон/еду/рекламные лимиты со светом на экране.
	var time_scale := 1.0
	var day_cycle := get_node_or_null("/root/DayCycle")
	if day_cycle != null:
		time_scale = day_cycle.time_scale
	game_clock_hours += (delta_real_sec / 3600.0) * game_hours_per_real_hour * time_scale


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
	# Отладочный тумблер «Бесплатно» (debug_panel.gd): единственная точка
	# списания монет во всей игре (крафт, кирки/ранцы, лавка, еда — см.
	# scripts/shop/shop_service.gd и scripts/house/house_food.gd), поэтому
	# гейт здесь разом обнуляет цену в обоих магазинах.
	if debug_free_shop:
		return true
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
	# См. комментарий в spend_coins() — тот же тумблер, та же единственная
	# точка списания, только для премиум-лавки за доллары.
	if debug_free_shop:
		return true
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


## Лимит переноски: база от ступени "сила" плюс бонус бурмобиля, пока он
## надет (решение владельца: «когда он обретает бурмобиль, его носимый вес
## увеличивается на 200 кг, вдобавок к собственному» — см.
## Balance.get_drill_rig_capacity_bonus_kg). Это прибавка к ЛИМИТУ, а не вес
## самой машины в инвентаре — машина в инвентарь не кладётся.
func get_max_carry_kg() -> float:
	var base := Balance.get_max_carry_kg(get_skill_stage("strength"))
	if current_tool == "drill_rig":
		base += Balance.get_drill_rig_capacity_bonus_kg()
	return base


## Радиусы аур тумана войны (ГДД раздел 12): большая — рельеф, маленькая —
## ресурсы. Качается ОДНА ветка «Обзор» (решение владельца): порознь эти два
## радиуса игроку ничего не говорили, а рельеф всегда видно на клетку дальше
## ресурсов. Ступень поднимает оба разом.
func get_vision_terrain_radius() -> int:
	return get_vision_resource_radius() + Balance.get_vision_terrain_bonus()


func get_vision_resource_radius() -> int:
	return Balance.get_vision_radius("vision", get_skill_stage("vision"))


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

## Стоит ли бурмобиль сейчас на парковке у устья тоннеля.
func is_rig_parked() -> bool:
	return rig_parked_at.x >= 0


func set_current_tool(tool_id: String) -> void:
	# Ступени инструментов покупаются и крафтятся (ГДД п.5), а не выдаются по
	# глубине: иначе кирка и бур приходят сами, и весь смысл копить сырьё
	# исчезает. Владение проверяется здесь, в единственной точке смены
	# инструмента, — см. блок "экономика" в конце файла.
	if not owns_tool(tool_id):
		tool_purchase_required.emit(tool_id)
		return
	# Бурмобиль — транспорт, не кирка (решение владельца): пока герой в нём и
	# под землёй, высадиться нельзя — только на поверхности (player_depth<=0)
	# или дома (house_is_indoors). Переход В машину эта проверка не трогает:
	# она смотрит только на current_tool == "drill_rig" СЕЙЧАС.
	if current_tool == "drill_rig" and tool_id != "drill_rig" \
			and player_depth >= 1 and not house_is_indoors:
		rig_dismount_blocked.emit(tool_id)
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

## Землетрясение (полный ресет копальни) сработало, пока герой был под землёй,
## и ждёт своего часа. Решение владельца: "не может произойти полный ресет,
## пока он в земле... пока он не вылезет наверх или в 3 на 3 клетки".
##
## Флаг лежит в состоянии и сохраняется (см. save_system.gd) намеренно: иначе
## достаточно свернуть игру под землёй, чтобы отменить землетрясение, — а по
## слову владельца оно должно застать героя уже дома при следующем заходе.
## Применяет его main.gd, как только герой оказывается в безопасности
## (CollapseEvents.is_safe_for_full_reset).
var pending_earthquake: bool = false

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

## Склад в мастерской (ГДД п.14, «Склад в мастерской»): item_id -> количество.
## Живёт отдельно от инвентаря и от чёрного ящика: при смерти теряется только
## рюкзак, склад остаётся целиком — он и нужен затем, чтобы копить материалы
## на ступень инструмента, которую за одну ходку не принести (железная кирка
## — 160 кг при рюкзаке 60). Грузоподъёмность на склад не действует: он стоит
## дома, а не на спине.
var house_storage: Dictionary = {}


## Сброс домашней части прогресса. Вызывается из reset_progress(), чтобы
## кнопка «Сброс» не оставляла в новом огороде построенный Робертом люк,
## пройденное обучение и оплаченную, но не забранную доставку.
## house_is_indoors здесь намеренно не трогается: закрыть интерьер и вернуть
## HUD — дело самой системы дома, GameState узлов сцены не знает.
func reset_house() -> void:
	house_room = "hall"
	house_food_at_door.clear()
	house_free_orders_used_today = 0
	house_hatch_built = false
	house_garden_closed = false
	house_tutorial_stage = 0
	house_dopings_shop_unlocked = false
	house_storage.clear()


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

## Попытались снять бурмобиль (сменить current_tool на что-то ещё), пока
## герой физически под землёй и не дома. Решение владельца (задача
## «Бурмобиль — транспорт»): «спускаясь под землю он должен быть только в
## нём» — значит и бросить его посреди шахты нельзя, высадка только на
## поверхности или дома. UI слушает сигнал, чтобы объяснить отказ тостом.
signal rig_dismount_blocked(tool_id: String)

## Инструменты, которые игрок реально получил. Лопата есть с самого начала
## (ГДД п.5: "acquired: старт игры"), дедова кирка приходит квестом мастерской,
## остальное — покупка и крафт.
var owned_tools: Array = ["shovel"]

## Купленные ступени ранца. Отдельно от инструментов: инструмент берут в руки,
## ранец надевают на спину, и одно другому не мешает — герой копает алмазной
## киркой с джетпаком за плечами.
##
## Хранится, а не вычисляется от глубины: вся линейка покупается за монеты
## (решение владельца), и глубина про неё больше ничего не знает.
var owned_gear: Array = []

## Ступень апгрейда бура бурмобиля (задача «Апгрейд бура»): 0 — апгрейда ещё
## нет (обычный серый бур), 1..N — купленная ступень (1=титан, 2=платина,
## 3=алмаз, 4=обсидиан — порядок и число ступеней читаются из balance.json ->
## tools.drill_rig.upgrade_tiers, см. Balance.get_drill_rig_tier_row).
## Отдельное поле, а не "тир записан внутри owned_tools": апгрейд — не
## отдельный инструмент, который берут в руки вместо бурмобиля, а ступень
## УЖЕ ВЗЯТОГО бурмобиля, как ступень ранца у owned_gear/current_gear выше.
## Покупки строго последовательны (см. ShopService.buy_drill_upgrade): нельзя
## купить платину, не купив титан, — простое +1 к этому числу за раз.
var drill_rig_tier: int = 0

## Ступень апгрейда бура сменилась (покупка в магазине) — HUD слушает, чтобы
## перерисовать иконку инструмента внизу экрана (см. hud.gd:_sync_tool):
## смена тира не меняет current_tool (герой как сидел в бурмобиле, так и
## сидит), поэтому GameState.tool_changed на неё не сработает сам.
signal drill_rig_tier_changed(tier: int)


## Выдать ступень апгрейда бура (см. ShopService.buy_drill_upgrade) — тем же
## приёмом, что grant_tool/grant_gear выше: пишет поле и оповещает, а не
## присваивается напрямую по всему коду.
func grant_drill_rig_tier(tier: int) -> void:
	if tier <= drill_rig_tier:
		return
	drill_rig_tier = tier
	drill_rig_tier_changed.emit(tier)

## Клетка глубины героя ПРЯМО СЕЙЧАС (0 — поверхность, растёт вниз). Пишется
## каждый кадр из player.gd (как is_digging чуть выше по файлу) — GameState
## сам позицию не считает, но она нужна ровно одной проверке ниже
## (set_current_tool: бурмобиль нельзя бросить под землёй), а протаскивать
## ссылку на героя через автолоад ради одного числа не стоит.
var player_depth: int = 0

## Сколько раз уже показывали тост о редкой находке. Решение владельца: такое
## уведомление перестаёт быть событием, если повторять его бесконечно, —
## показываем считанные разы за игру и больше не трогаем игрока.
var rare_find_toasts_shown: int = 0

## Буровая скважина (ГДД п.1) — единственная idle-механика. 0 — не построена.
var well_level: int = 0
## Когда с неё забирали в последний раз (реальное время). По нему считается
## офлайн-доход при заходе в игру.
var well_last_collect_unix: int = 0

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


func has_gear(gear_id: String) -> bool:
	return owned_gear.has(gear_id)


## Выдать ступень ранца (покупка в магазине, сюжетная находка).
##
## Свежая ступень сразу надевается, если она быстрее надетой: покупать ранец
## и отдельно идти его надевать — лишний шаг ради ничего. Выбор вручную
## никуда не девается, он живёт на верстаке (верстак = экипировка).
func grant_gear(gear_id: String) -> void:
	if not owned_gear.has(gear_id):
		owned_gear.append(gear_id)
	if Balance.get_gear_fly_multiplier(gear_id) > Balance.get_gear_fly_multiplier(current_gear):
		set_current_gear(gear_id)


## Надеть ступень ранца. "" — снять всё. Возвращает false, если такой ступени
## у игрока нет: владение проверяется здесь, в единственной точке смены, —
## так же, как у инструментов в set_current_tool.
func set_current_gear(gear_id: String) -> bool:
	if not gear_id.is_empty() and not has_gear(gear_id):
		return false
	if current_gear == gear_id:
		return true
	current_gear = gear_id
	gear_changed.emit(gear_id)
	return true


## Множитель скорости полёта надетой ступени. 0.0 — ранца нет вовсе; физика
## полёта до этого места не доходит, потому что тяга включается только когда
## ранец надет (см. player.gd:_update_flight).
func get_gear_fly_multiplier() -> float:
	return Balance.get_gear_fly_multiplier(current_gear)


## Материалы, вложенные в конкретный рецепт верстака:
## recipe_id -> {item_id: количество}.
##
## УСТАРЕЛО. Механику вложений придумали в отсутствие склада: железная кирка
## стоит 160 кг материалов при рюкзаке 60 кг, и принести их за одну ходку
## невозможно. ГДД п.14 («Склад в мастерской») ввёл склад и прямо отменил
## вложения — верстак теперь берёт материалы со склада (house_storage), а
## это поле больше не пишется. Оставлено только затем, чтобы не ломать уже
## записанные сейвы; удалять его вместе с полем в save_system — отдельной
## уборкой, когда сейвы неважны.
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
	owned_gear = []
	current_gear = ""
	drill_rig_tier = 0
	rare_find_toasts_shown = 0
	well_level = 0
	well_last_collect_unix = 0
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

# ---------------------------------------------------------------------------
# --- отладочная тестовая панель (scripts/ui/debug_panel.gd) ---
# Четыре тумблера тестировщика — НЕ для релиза игрокам. Нарочно НЕ сохраняются
# в user://save.json (см. save_system.gd — этот блок там не упомянут) и
# нарочно НЕ трогаются в reset_progress(): это не игровой прогресс, а
# переключатели отладки, и они обязаны сбрасываться в false при каждом
# перезапуске процесса, а не при нажатии кнопки «Сброс» в игре. Обычная игра
# не отличается от текущей, пока эти поля не тронуты руками (default false).
# ---------------------------------------------------------------------------

## Время копки любой клетки — 0 (см. player.gd:_start_dig).
var debug_instant_dig: bool = false
## Урон (GameState.take_damage) не применяется; HP не подскакивает сам.
var debug_invincible: bool = false
## Подъём/падение всегда ровно 300 клеток/с (см. player.gd:_move_y) — пешком,
## с ранцем/джетпаком и в бурмобиле одинаково.
var debug_fly_300: bool = false
## Покупки в обоих магазинах (за монеты и за доллары) ничего не списывают
## (см. spend_coins/spend_dollars ниже).
var debug_free_shop: bool = false

## Кнопки-действия панели (не тумблеры — «Дом», «Динамит»): DebugPanel не
## держит ссылку на игрока/мир (см. debug_panel.gd), поэтому просто шлёт
## имя действия сюда, а слушает и исполняет main.gd, у которого оба узла
## есть под рукой.
signal debug_action_triggered(name: String)


func trigger_debug_action(name: String) -> void:
	debug_action_triggered.emit(name)

## Эпоха живого мира: "now" (внук, обычная игра) или "grandpa" (интро деда
## играет НА ЖИВОЙ КАРТЕ, см. scripts/story/cutscene_player.gd, режим
## play(id, {"world": true})). Выставляет и снимает сама катсцена
## (_enter_world_mode/_exit_world_mode) — здесь просто общее место, которое
## читают системы, которым не по пути тащить к себе WorldGen (см.
## scripts/house/house_system.gd — лачуга вместо богатого дома). WorldGen
## держит своё зеркало этого же факта (world.era) тем же приёмом, что и
## house_garden_closed/_garden_locked: он чистый RefCounted без автозагрузок.
##
## Не сохраняется в user://save.json нарочно: единственный, кто временно
## переводит игру в эпоху деда, — сама интро-сцена, и она же гарантированно
## возвращает "now" по завершении (доигранном или пропущенном) — см.
## _exit_world_mode(). Если игра закрылась посреди сцены, при следующем
## запуске era снова "now" по умолчанию, а сцена (она осталась в очереди,
## см. StoryState) переиграется с начала и сама выставит её заново.
var era: String = "now"

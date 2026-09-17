class_name SaveSystem
extends RefCounted
## SaveSystem — сохранение/загрузка в user://save.json.
##
## Не автолоад: регистрируется как глобальный класс через class_name, поэтому
## доступен как `SaveSystem.save_game()` откуда угодно (в первую очередь — из
## GameState, который его и вызывает при старте/автосейве/значимых событиях).
##
## Сохраняет только ДИФФ мира (выкопанные клетки), а не всю карту: мир
## детерминирован от сида и генерируется модулем scripts/world/ заново при
## каждой загрузке, поверх него накатывается world_dug_cells (см. GDD).
##
## Версионирование: поле "version" в корне сейва. При изменении схемы в
## будущем — прибавить SCHEMA_VERSION и дописать шаг в _migrate().

const SAVE_PATH := "user://save.json"
const SCHEMA_VERSION := 2


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func delete_save() -> void:
	if not has_save():
		return
	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(SAVE_PATH.get_file())


## Собирает состояние GameState в plain-Dictionary, готовый к JSON.stringify.
static func _serialize() -> Dictionary:
	var gs := GameState
	return {
		"version": SCHEMA_VERSION,
		"saved_at_utc": Time.get_datetime_string_from_system(true),

		"survival": {
			"hp": gs.hp,
			"stamina": gs.stamina,
			"hunger": gs.hunger,
			"is_alive": gs.is_alive,
		},
		"progression": {
			"xp": gs.xp,
			"level": gs.level,
			"skill_points_available": gs.skill_points_available,
			"skill_stages": gs.skill_stages,
		},
		"currency": {
			"coins": gs.coins,
			"dollars": gs.dollars,
		},
		"inventory": gs.inventory,
		"black_box": {
			"tier": gs.black_box_tier,
			"contents": gs.black_box,
		},
		"tool": {
			"current_tool": gs.current_tool,
		},
		"depth": {
			"max_depth_reached": gs.max_depth_reached,
		},
		"artifacts": {
			"collected": gs.collected_artifacts,
			"completed_branches": gs.completed_branches,
		},
		"time": {
			"game_clock_hours": gs.game_clock_hours,
		},
		"ads": {
			"daily_counts": gs.ad_daily_counts,
			"last_reset_utc_date": gs.last_reset_utc_date,
		},
		"world_seed": gs.world_seed,
		"world": _serialize_world(gs),

		# Отложенное землетрясение обязано пережить выход из игры: без записи
		# в сейв игроку достаточно свернуть игру под землёй, чтобы полный
		# ресет не случился никогда (см. game_state.pending_earthquake).
		"events": {
			"pending_earthquake": gs.pending_earthquake,
		},

		# --- дом и выживание (scripts/house/) ---
		# Сохраняется всё, что игрок уже "потратил" или получил: построенный
		# Робертом люк, стадия обучения, оплаченная и ещё не забранная
		# доставка. Без этого перезапуск игры возвращает люк в непостроенное
		# состояние и съедает оплаченный заказ.
		# house_is_indoors намеренно НЕ сохраняется: позиция героя между
		# сессиями и так не сохраняется (см. main.gd:_position_from_save_or_start),
		# и запуск игры внутри дома разошёлся бы с координатами в огороде.
		"house": {
			"room": gs.house_room,
			"food_at_door": gs.house_food_at_door,
			"free_orders_used_today": gs.house_free_orders_used_today,
			"hatch_built": gs.house_hatch_built,
			"garden_closed": gs.house_garden_closed,
			"tutorial_stage": gs.house_tutorial_stage,
			"dopings_shop_unlocked": gs.house_dopings_shop_unlocked,
			"storage": gs.house_storage,
		},

		# --- экономика (scripts/shop/) ---
		# Купленные и скрафченные инструменты обязаны переживать перезапуск:
		# без этого железная кирка, стоившая 25 железа, 10 бронзы, 30 свинца и
		# 200 монет, пропадает, а current_tool указывает на инструмент, которым
		# игрок больше не владеет. Заряженное рекламой удвоение продажи тоже
		# сохраняется — ролик уже просмотрен, и терять его при выходе нечестно.
		"economy": {
			"owned_tools": gs.owned_tools,
			"owned_gear": gs.owned_gear,
			"current_gear": gs.current_gear,
			"rare_find_toasts_shown": gs.rare_find_toasts_shown,
			"well_level": gs.well_level,
			"well_last_collect_unix": gs.well_last_collect_unix,
			"workshop_visited": gs.workshop_visited,
			"next_sale_doubled": gs.next_sale_doubled,
			"lifetime_coins_from_sales": gs.lifetime_coins_from_sales,
			"craft_invested": gs.craft_invested,
		},
	}


## Реальный мир хранится в GameState.world_ref (WorldGen), назначаемом
## main.gd: только он знает и диффы, и события обвалов/землетрясений
## (см. world_gen.gd:get_save_data). Запасной путь — устаревший
## GameState.world_dug_cells, на случай если world_ref ещё не назначен.
static func _serialize_world(gs) -> Dictionary:
	if gs.world_ref != null:
		var out := {"gen": gs.world_ref.get_save_data()}
		if gs.fog_ref != null:
			out["fog"] = gs.fog_ref.to_save_data()
		return out
	return {"dug_cells": gs.world_dug_cells}


## Накатывает загруженные данные на GameState. Ожидает уже мигрированный
## словарь текущей SCHEMA_VERSION (см. _migrate).
static func _apply(data: Dictionary) -> void:
	var gs := GameState

	var survival: Dictionary = data.get("survival", {})
	gs.hp = float(survival.get("hp", gs.hp))
	gs.stamina = float(survival.get("stamina", gs.stamina))
	gs.hunger = float(survival.get("hunger", gs.hunger))
	gs.is_alive = bool(survival.get("is_alive", true))

	var progression: Dictionary = data.get("progression", {})
	gs.xp = int(progression.get("xp", gs.xp))
	gs.level = int(progression.get("level", gs.level))
	gs.skill_points_available = int(progression.get("skill_points_available", gs.skill_points_available))
	gs.skill_stages = progression.get("skill_stages", {})

	var currency: Dictionary = data.get("currency", {})
	gs.coins = int(currency.get("coins", gs.coins))
	gs.dollars = int(currency.get("dollars", gs.dollars))

	gs.inventory = data.get("inventory", {})

	var black_box: Dictionary = data.get("black_box", {})
	gs.black_box_tier = String(black_box.get("tier", gs.black_box_tier))
	gs.black_box = black_box.get("contents", {})

	var tool: Dictionary = data.get("tool", {})
	gs.current_tool = String(tool.get("current_tool", gs.current_tool))

	var depth: Dictionary = data.get("depth", {})
	gs.max_depth_reached = int(depth.get("max_depth_reached", gs.max_depth_reached))

	var artifacts_data: Dictionary = data.get("artifacts", {})
	gs.collected_artifacts = artifacts_data.get("collected", [])
	gs.completed_branches = artifacts_data.get("completed_branches", [])

	var time_data: Dictionary = data.get("time", {})
	gs.game_clock_hours = float(time_data.get("game_clock_hours", gs.game_clock_hours))

	var ads_data: Dictionary = data.get("ads", {})
	gs.ad_daily_counts = ads_data.get("daily_counts", {})
	gs.last_reset_utc_date = String(ads_data.get("last_reset_utc_date", gs.last_reset_utc_date))

	gs.world_seed = int(data.get("world_seed", gs.world_seed))

	# Сейвы до правила об отложенном ресете блока "events" не содержат —
	# для них отложенного землетрясения просто нет.
	var events_data: Dictionary = data.get("events", {})
	gs.pending_earthquake = bool(events_data.get("pending_earthquake", false))

	# --- дом и выживание (scripts/house/) ---
	var house_data: Dictionary = data.get("house", {})
	gs.house_room = String(house_data.get("room", gs.house_room))
	gs.house_food_at_door = house_data.get("food_at_door", {})
	gs.house_free_orders_used_today = int(house_data.get("free_orders_used_today", 0))
	gs.house_hatch_built = bool(house_data.get("hatch_built", false))
	gs.house_garden_closed = bool(house_data.get("garden_closed", false))
	gs.house_tutorial_stage = int(house_data.get("tutorial_stage", 0))
	gs.house_dopings_shop_unlocked = bool(house_data.get("dopings_shop_unlocked", false))
	# Склад обязан пережить перезапуск: в нём лежат материалы, которые игрок
	# носил домой несколько ходок (ГДД п.14).
	gs.house_storage = _as_int_counts(house_data.get("storage", {}))

	var economy: Dictionary = data.get("economy", {})
	# Старый сейв (до магазина) экономического блока не содержит: инструменты
	# там не записаны, и восстановить их можно только по текущему инструменту —
	# иначе игрок, уже собравший бур, теряет его при первой же загрузке.
	gs.owned_tools = economy.get("owned_tools", ["shovel", gs.current_tool])
	gs.rare_find_toasts_shown = int(economy.get("rare_find_toasts_shown", 0))
	gs.well_level = int(economy.get("well_level", 0))
	gs.well_last_collect_unix = int(economy.get("well_last_collect_unix", 0))
	# Старые правила («ранец с глубины 10, джетпак с глубины 100») разбирает
	# миграция v1 -> v2: к этому месту ключ уже есть даже у сейва, где его не
	# было вовсе. Здесь остаётся простое чтение.
	gs.owned_gear = economy.get("owned_gear", [])
	# Надетая ступень ранца. Сейвы до линейки ранцев её не знают — миграция
	# v1 -> v2 дописывает её сама (см. _migrate_v1_to_v2), здесь остаётся
	# только страховка: надетым не может быть то, чего нет в собственности.
	gs.current_gear = String(economy.get("current_gear", ""))
	if not gs.current_gear.is_empty() and not gs.owned_gear.has(gs.current_gear):
		gs.current_gear = ""
	gs.workshop_visited = bool(economy.get("workshop_visited", gs.workshop_visited))
	gs.next_sale_doubled = bool(economy.get("next_sale_doubled", false))
	gs.lifetime_coins_from_sales = int(economy.get("lifetime_coins_from_sales", 0))
	gs.craft_invested = economy.get("craft_invested", {})

	var world_data: Dictionary = data.get("world", {})
	if world_data.has("gen") and gs.world_ref != null:
		gs.world_ref.load_save_data(world_data["gen"])
		if gs.fog_ref != null and world_data.has("fog"):
			gs.fog_ref.load_save_data(world_data["fog"])
	else:
		gs.world_dug_cells = world_data.get("dug_cells", {})


## JSON не различает int и float: количества, прочитанные из сейва, приходят
## числами с плавающей точкой, а инвентарь и склад считают штуки целыми.
static func _as_int_counts(raw) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key in (raw as Dictionary).keys():
		var n := int((raw as Dictionary)[key])
		if n > 0:
			out[String(key)] = n
	return out


## Приводит сохранение произвольной старой версии к текущей SCHEMA_VERSION.
## Шаги идут ступенями: каждая функция поднимает сейв ровно на одну версию.
static func _migrate(data: Dictionary) -> Dictionary:
	var from_version := int(data.get("version", 1))
	if from_version > SCHEMA_VERSION:
		push_warning("SaveSystem: сейв версии %d новее текущей схемы %d — грузим как есть" % [from_version, SCHEMA_VERSION])
		return data
	if from_version <= 1:
		data = _migrate_v1_to_v2(data)
		from_version = 2
	data["version"] = from_version
	return data


## v1 -> v2: владелец переписал прогресс — кирки и ранцы стали линейками за
## монеты, а рецепты остались только у техники.
##
## Ничего не отбираем. По старым правилам у игрока могли быть:
##   * железная кирка — собиралась из 25 железа, 10 бронзы, 30 свинца и 200
##     монет. Теперь она стоит 500 монет, но заслужена она уже была: id не
##     менялся, поэтому она просто остаётся в owned_tools как есть, и
##     трогать её здесь не нужно;
##   * джетпак — собирался на верстаке и лежал в owned_gear отдельной строкой,
##     без понятия «надет». Теперь это третья ступень линейки: собственность
##     сохраняется, и он становится надетым;
##   * ранец с пропеллерами — его в сейве НЕ БЫЛО вовсе: старый код выдавал
##     его по флагу сюжета backpack_owned или по достигнутой глубине 10.
##     После обновления ранец стоит 100 монет, и игрок, пролетавший на нём
##     полигры, обнаружил бы, что летать больше нечем. Поэтому глубина 10 в
##     старом сейве читается как «ранец был» и записывается в собственность.
##     Это одноразовое чтение старого признака, а не новое правило: начиная с
##     v2 глубина ранцев не выдаёт.
static func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var economy: Dictionary = data.get("economy", {})
	var depth := int(Dictionary(data.get("depth", {})).get("max_depth_reached", 0))

	var gear: Array = economy.get("owned_gear", [])
	# Сейв мог вообще не иметь блока economy (до магазина): тогда джетпак у
	# игрока был, если он дошёл до глубины 100 — снаряжение считалось от неё.
	if not economy.has("owned_gear") and depth >= 100:
		gear = ["jetpack"]
	if depth >= 10 and not gear.has("backpack"):
		gear.append("backpack")

	# Надевается лучшая из имеющихся ступеней: предлагать игроку выбор между
	# джетпаком и ранцем на экране, которого он ещё не видел, — значит
	# посадить его после обновления на пропеллеры.
	var best := ""
	for id in gear:
		if Balance.get_gear_fly_multiplier(String(id)) > Balance.get_gear_fly_multiplier(best):
			best = String(id)

	economy["owned_gear"] = gear
	economy["current_gear"] = best
	data["economy"] = economy

	# Видимость рельефа и ресурсов слиты в одну ветку «Обзор» (решение
	# владельца). Берём БОЛЬШУЮ из двух старых ступеней, а не сумму: ступени
	# шли параллельно, и сумма выдала бы игроку вдвое больший обзор, чем он
	# купил. Очки за вторую ветку не возвращаются — они и раньше были
	# потрачены на то, что человек получил.
	var progression: Dictionary = data.get("progression", {})
	var stages: Dictionary = progression.get("skill_stages", {})
	if stages.has("terrain_vision") or stages.has("resource_vision"):
		var merged := maxi(int(stages.get("terrain_vision", 0)), int(stages.get("resource_vision", 0)))
		stages["vision"] = maxi(int(stages.get("vision", 0)), merged)
		stages.erase("terrain_vision")
		stages.erase("resource_vision")
		progression["skill_stages"] = stages
		data["progression"] = progression
	return data


static func save_game() -> bool:
	var data := _serialize()
	var json_text := JSON.stringify(data, "\t")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: не удалось открыть %s для записи (код %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return false
	f.store_string(json_text)
	f.close()
	return true


static func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_error("SaveSystem: не удалось открыть %s для чтения (код %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return false
	var text := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveSystem: сейв повреждён или не является объектом JSON")
		return false

	var migrated := _migrate(parsed)
	_apply(migrated)
	return true

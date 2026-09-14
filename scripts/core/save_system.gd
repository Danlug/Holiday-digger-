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
const SCHEMA_VERSION := 1


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


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
		"world": {
			"dug_cells": gs.world_dug_cells,
		},
	}


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

	var world_data: Dictionary = data.get("world", {})
	gs.world_dug_cells = world_data.get("dug_cells", {})


## Приводит сохранение произвольной старой версии к текущей SCHEMA_VERSION.
## Сейчас существует только версия 1, поэтому шагов миграции нет — но
## структура заложена, чтобы будущие апдейты могли писать сюда шаги вида
## "if from_version == 1: ...".
static func _migrate(data: Dictionary) -> Dictionary:
	var from_version := int(data.get("version", 1))
	if from_version > SCHEMA_VERSION:
		push_warning("SaveSystem: сейв версии %d новее текущей схемы %d — грузим как есть" % [from_version, SCHEMA_VERSION])
		return data
	# Будущие миграции добавлять здесь ступенями, например:
	# if from_version == 1:
	#     data = _migrate_v1_to_v2(data)
	#     from_version = 2
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

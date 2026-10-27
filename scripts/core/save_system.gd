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
## Предыдущая удачная запись и временный файл текущей: запись идёт «во временный, потом
## переименовать», и оборванная запись (выход посреди записи, полный диск) не съедает прогресс.
const BACKUP_PATH := "user://save.json.bak"
const TMP_PATH := "user://save.json.tmp"
const SCHEMA_VERSION := 2


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func delete_save() -> void:
	# Копия тоже: после «Сброса» из неё поднялась бы стёртая игра.
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for path in [SAVE_PATH, BACKUP_PATH, TMP_PATH]:
		if FileAccess.file_exists(path):
			dir.remove(String(path).get_file())


## Собирает состояние GameState в plain-Dictionary, готовый к JSON.stringify.
static func _serialize() -> Dictionary:
	var gs := GameState
	HeroSpot.sync_now()   # место героя под землёй — в ext на момент записи (scripts/core/hero_spot.gd)
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
		"tool": {
			"current_tool": gs.current_tool,
			# Припаркованная машина — объект мира, переживает перезапуск:
			# без записи герой у себя дома нашёл бы бурмобиль пропавшим
			# (см. GameState.rig_parked_at, player.gd "Бурмобиль как
			# транспорт"). -1,-1 — не запаркована.
			"rig_parked_x": gs.rig_parked_at.x,
			"rig_parked_y": gs.rig_parked_at.y,
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
		# house_is_indoors намеренно НЕ сохраняется: место героя пишется только
		# под землёй (HeroSpot, ext["hero_spot"]), из дома запуск идёт у дома
		# (main.gd:_position_from_save_or_start) — внутри дома он разошёлся бы с огородом.
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
			"drill_rig_tier": gs.drill_rig_tier,
			"rare_find_toasts_shown": gs.rare_find_toasts_shown,
			"well_level": gs.well_level,
			"well_last_collect_unix": gs.well_last_collect_unix,
			"workshop_visited": gs.workshop_visited,
			"next_sale_doubled": gs.next_sale_doubled,
			"lifetime_coins_from_sales": gs.lifetime_coins_from_sales,
			"craft_invested": gs.craft_invested,
		},

		"ext": gs.ext,
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
	# Блок ящика-страховки из старых сейвов не читаем: механика убрана (решение владельца,
	# раунд 5), положить в ящик было нельзя — он всегда пуст; следующее сохранение блок не пишет.

	var tool: Dictionary = data.get("tool", {})
	gs.current_tool = String(tool.get("current_tool", gs.current_tool))
	# Сейв до бурмобиля-транспорта паркинга не знает — (-1,-1) по умолчанию
	# уже значит "не запаркована" (см. GameState.rig_parked_at).
	gs.rig_parked_at = Vector2i(int(tool.get("rig_parked_x", -1)), int(tool.get("rig_parked_y", -1)))

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
	# Ступень апгрейда бура (см. GameState.drill_rig_tier) — сейвы до этой
	# задачи её не знают, 0 ("апгрейда нет") — верное значение по умолчанию.
	gs.drill_rig_tier = int(economy.get("drill_rig_tier", 0))
	gs.workshop_visited = bool(economy.get("workshop_visited", gs.workshop_visited))
	gs.next_sale_doubled = bool(economy.get("next_sale_doubled", false))
	gs.lifetime_coins_from_sales = int(economy.get("lifetime_coins_from_sales", 0))
	gs.craft_invested = economy.get("craft_invested", {})

	var ext_data = data.get("ext", {})
	gs.ext = ext_data if typeof(ext_data) == TYPE_DICTIONARY else {}

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
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: не удалось открыть %s для записи (код %d)" % [TMP_PATH, FileAccess.get_open_error()])
		return false
	f.store_string(json_text)
	f.close()
	# Записано всё? Полный диск оставляет обрубок: сверяем размер, не разбирая JSON заново
	# (на сейве с десятками тысяч клеток разбор — десятки миллисекунд, а пишем часто).
	if FileAccess.open(TMP_PATH, FileAccess.READ).get_length() != json_text.to_utf8_buffer().size():
		push_error("SaveSystem: запись во временный файл неполная — старый сейв оставлен как есть")
		DirAccess.remove_absolute(TMP_PATH)
		return false
	# Прежний сейв уходит в копию, если он выглядит целым: битый не должен затереть хорошую копию.
	if has_save() and _looks_complete(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH)
	if DirAccess.rename_absolute(TMP_PATH, SAVE_PATH) != OK:
		push_error("SaveSystem: не удалось подменить %s" % SAVE_PATH)
		return false
	return true


static var _now_frame := -1


## Сохранить и синхронизировать сейчас: закрытие страницы, пауза, сворачивание (SaveHooks), смерть.
## reason — для журнала. Повтор в том же кадре не пишет второй раз (скрытие и уход страницы приходят
## подряд, у скрытой вкладки кадров нет). В вебе файл сразу уходит в IndexedDB (_persist_web).
static func save_now(reason: String = "") -> bool:
	var frame := Engine.get_process_frames()
	if frame == _now_frame:
		return true
	_now_frame = frame
	var ok := save_game()
	if ok and OS.has_feature("web"):
		_persist_web()
	if not ok:
		push_warning("SaveSystem: запись «%s» не удалась" % reason)
	return ok


## Движок переносит user:// в IndexedDB сам, но в начале СЛЕДУЮЩЕГО кадра после записи, а у скрытой
## вкладки кадров нет: сейв, записанный при уходе со страницы, жил бы только в памяти, и телефон,
## выгрузивший вкладку, унёс бы его с собой. Поэтому отдаём текст оболочке (web/shell.src.html,
## RaskopkiShell.persistFile): она кладёт его в ту же базу тем же форматом, что и движок.
static func _persist_web() -> void:
	var shell = JavaScriptBridge.get_interface("RaskopkiShell")
	if shell == null or shell.persistFile == null:
		return
	for path in [SAVE_PATH, "user://story.json"]:
		if FileAccess.file_exists(path):
			shell.persistFile(ProjectSettings.globalize_path(path), FileAccess.get_file_as_string(path))


## Дёшево: файл начинается с «{» и кончается «}» (обрыв записи так не выглядит).
static func _looks_complete(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 2:
		return false
	var head := f.get_buffer(1)
	var tail_len: int = mini(16, int(f.get_length()))
	f.seek(f.get_length() - tail_len)
	var tail := f.get_buffer(tail_len).get_string_from_utf8().strip_edges()
	f.close()
	return head.size() == 1 and head[0] == 0x7B and tail.ends_with("}")


## Читает файл как JSON-объект. null — нет файла, мусор, обрыв или не объект.
static func _read_dict(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else null


static func load_game() -> bool:
	if not has_save():
		return false
	var parsed = _read_dict(SAVE_PATH)
	if parsed == null:
		# Главный файл испорчен — пробуем предыдущую удачную запись.
		parsed = _read_dict(BACKUP_PATH)
		if parsed == null:
			push_error("SaveSystem: сейв повреждён или не является объектом JSON")
			return false
		push_warning("SaveSystem: основной сейв повреждён — поднята резервная копия")

	var migrated := _migrate(_sanitize(parsed))
	_apply(migrated)
	GameState.top_up_skill_points()  # очки за уровни растут с раунда 4 — доплата старому сейву
	PremiumUnload.migrate_legacy()  # таблетка снята с продажи (раунд 6): лежавшая в сейве — долларами назад
	return true


# ---------------------------------------------------------------------------
# Санитайзер: сейв с «правильным JSON, но неправильными типами» (ручная правка, чужая версия,
# битая синхронизация). Тип не тот — ошибка скрипта посреди _apply, и остальной сейв не
# накатывается. Всё, чего не ждёт _apply, выбрасывается ДО него: значение берётся по умолчанию.
# ---------------------------------------------------------------------------

## Блоки-словари корня сейва. ext и world свободной формы — их содержимое не трогаем.
const _SAN_BLOCKS: Array[String] = ["survival", "progression", "currency", "tool", "depth",
	"artifacts", "time", "ads", "world", "events", "house", "economy", "ext"]
const _SAN_FREE_BLOCKS: Array[String] = ["ext", "world"]
## Листья-строки; любая другая строка там, где ждут число или bool, ломает int()/bool().
const _SAN_STRING_KEYS: Array[String] = ["current_tool", "last_reset_utc_date", "room", "current_gear"]
## Листья, где контейнер — норма; в любом другом месте словарь или массив вместо числа ломает float()/int().
const _SAN_CONTAINER_KEYS: Array[String] = ["skill_stages", "daily_counts", "food_at_door", "storage",
	"collected", "completed_branches", "owned_tools", "owned_gear", "craft_invested"]
## Словари «ключ → число» (inventory — в корне; остальные — [блок, ключ]).
const _SAN_COUNT_DICTS: Array = [["", "inventory"], ["progression", "skill_stages"],
	["ads", "daily_counts"], ["house", "food_at_door"], ["house", "storage"]]
## Массивы строк / чисел.
const _SAN_ARRAYS: Array = [["artifacts", "collected", TYPE_STRING], ["artifacts", "completed_branches", TYPE_FLOAT],
	["economy", "owned_tools", TYPE_STRING], ["economy", "owned_gear", TYPE_STRING]]


static func _san_warn(what: String) -> void:
	push_warning("SaveSystem: в сейве испорчено «%s» — беру значение по умолчанию" % what)


static func _is_num(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _sanitize(data: Dictionary) -> Dictionary:
	# Корень: версия и сид — числа.
	for key in ["version", "world_seed"]:
		if data.has(key) and not _is_num(data[key]):
			_san_warn(String(key))
			data.erase(key)

	for block in _SAN_BLOCKS:
		if not data.has(block):
			continue
		if typeof(data[block]) != TYPE_DICTIONARY:
			_san_warn(block)
			data.erase(block)
			continue
		if _SAN_FREE_BLOCKS.has(block):
			continue
		var b: Dictionary = data[block]
		for key in b.keys():
			var v = b[key]
			var t := typeof(v)
			if t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_BOOL:
				continue
			if (t == TYPE_DICTIONARY or t == TYPE_ARRAY) and _SAN_CONTAINER_KEYS.has(String(key)):
				continue  # содержимое проверяют таблицы ниже
			if t == TYPE_STRING and _SAN_STRING_KEYS.has(String(key)):
				continue
			_san_warn("%s.%s" % [block, key])
			b.erase(key)

	for pair in _SAN_COUNT_DICTS:
		var holder: Dictionary = data if String(pair[0]).is_empty() else data.get(pair[0], {})
		if not holder.has(pair[1]):
			continue
		if typeof(holder[pair[1]]) != TYPE_DICTIONARY:
			_san_warn("%s.%s" % [pair[0], pair[1]])
			holder.erase(pair[1])
			continue
		var counts: Dictionary = holder[pair[1]]
		for id in counts.keys():
			if not _is_num(counts[id]):
				counts.erase(id)

	for row in _SAN_ARRAYS:
		var holder2: Dictionary = data.get(row[0], {})
		if not holder2.has(row[1]):
			continue
		if typeof(holder2[row[1]]) != TYPE_ARRAY:
			_san_warn("%s.%s" % [row[0], row[1]])
			holder2.erase(row[1])
			continue
		var kept: Array = []
		for item in holder2[row[1]]:
			var ok: bool = typeof(item) == TYPE_STRING if int(row[2]) == TYPE_STRING else _is_num(item)
			if ok:
				kept.append(item)
		holder2[row[1]] = kept

	# craft_invested: словарь словарей — нужен только словарь.
	var economy: Dictionary = data.get("economy", {})
	if economy.has("craft_invested") and typeof(economy["craft_invested"]) != TYPE_DICTIONARY:
		economy.erase("craft_invested")
	return data

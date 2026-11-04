extends Node
## test_save_robustness — сейв переживает старые версии, мусор и обрыв записи,
## а reset_progress() не оставляет «хвостов» состояния.
##
## Запуск: godot --headless --path . res://tests/test_save_robustness.tscn
##
## Тест трогает user://save.json и story.json, поэтому на старте прячет чужие
## файлы и в конце возвращает; run_tests.sh к тому же даёт каждому тесту свой
## XDG_DATA_HOME. Строки «ERROR: SaveSystem: ...» в логе — ожидаемы: так игра
## сообщает о мусоре в сейве.

var failures := 0
var total := 0
var _stash: Dictionary = {}


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _ready() -> void:
	print("=== test_save_robustness ===")
	_stash_files()
	_test_old_save_without_ext()
	_test_v1_save_migrates()
	_test_old_save_with_removed_box()
	_test_garbage_and_truncated()
	_test_wrong_types()
	_test_backup_recovery()
	_test_round_trip()
	_test_reset_leaks()
	_restore_files()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# Файлы
# ---------------------------------------------------------------------------

const FILES := ["user://save.json", "user://save.json.bak", "user://save.json.tmp", "user://story.json"]


func _stash_files() -> void:
	for p: String in FILES:
		if FileAccess.file_exists(p):
			_stash[p] = FileAccess.get_file_as_string(p)
			DirAccess.remove_absolute(p)


func _restore_files() -> void:
	for p: String in FILES:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	for p: String in _stash.keys():
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(_stash[p])
		f.close()


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _wipe() -> void:
	for p: String in FILES:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _fresh() -> void:
	_wipe()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	GameState.reset_progress()


## Состояние пригодно к игре: типы на месте, ничего не осталось «на полпути».
func _state_sane() -> bool:
	return typeof(GameState.inventory) == TYPE_DICTIONARY and typeof(GameState.skill_stages) == TYPE_DICTIONARY \
		and typeof(GameState.ext) == TYPE_DICTIONARY and typeof(GameState.owned_tools) == TYPE_ARRAY \
		and typeof(GameState.owned_gear) == TYPE_ARRAY and typeof(GameState.collected_artifacts) == TYPE_ARRAY \
		and typeof(GameState.house_food_at_door) == TYPE_DICTIONARY and typeof(GameState.craft_invested) == TYPE_DICTIONARY \
		and typeof(GameState.ad_daily_counts) == TYPE_DICTIONARY \
		and typeof(GameState.completed_branches) == TYPE_ARRAY


# ---------------------------------------------------------------------------
# Старые и странные сейвы
# ---------------------------------------------------------------------------

func _test_old_save_without_ext() -> void:
	_fresh()
	GameState.ext_set("probe", 5)
	GameState.coins = 123
	SaveSystem.save_game()
	# Сейв «до ext»: тот же файл, но без ключа — как писали версии до хранилища.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://save.json"))
	data.erase("ext")
	_write("user://save.json", JSON.stringify(data))
	GameState.reset_progress()
	GameState.ext_set("leftover", 1)
	check("старый сейв без ext загружается", SaveSystem.load_game())
	check("монеты из старого сейва на месте", GameState.coins == 123)
	# Единственное, что загрузка сама кладёт в ext, — отметка о разовых подарках (OwnerGifts, data/gifts.json).
	var ext_rest: Array = GameState.ext.keys().filter(func(k): return String(k) != OwnerGifts.CLAIMED_KEY) \
		if typeof(GameState.ext) == TYPE_DICTIONARY else ["не словарь"]
	check("ext после загрузки — словарь без хвоста прошлой сессии (кроме отметки подарков), а не None",
		typeof(GameState.ext) == TYPE_DICTIONARY and ext_rest.is_empty(), str(GameState.ext))
	check("ext_get на пустом хранилище отдаёт значение по умолчанию", GameState.ext_get("probe", 7) == 7)
	check("состояние пригодно к игре", _state_sane())


func _test_v1_save_migrates() -> void:
	_fresh()
	# Сейв первой схемы: без блока economy и без ext, глубина 120 — ранец и джетпак были «по глубине».
	var v1 := {
		"version": 1,
		"survival": {"hp": 80.0, "stamina": 50.0, "hunger": 60.0, "is_alive": true},
		"progression": {"xp": 500, "level": 4, "skill_points_available": 2,
			"skill_stages": {"terrain_vision": 3, "resource_vision": 5, "strength": 1}},
		"currency": {"coins": 900, "dollars": 3},
		"inventory": {"iron_ore": 4},
		"tool": {"current_tool": "iron_pickaxe"},
		"depth": {"max_depth_reached": 120},
	}
	_write("user://save.json", JSON.stringify(v1))
	check("сейв v1 загружается", SaveSystem.load_game())
	check("v1: ранец и джетпак по старому правилу глубины выданы",
		GameState.owned_gear.has("backpack") and GameState.owned_gear.has("jetpack"), str(GameState.owned_gear))
	check("v1: надет лучший из имеющихся", GameState.current_gear == "jetpack", GameState.current_gear)
	check("v1: ветки обзора слиты по большей ступени", GameState.get_skill_stage("vision") == 5)
	check("v1: железная кирка не потеряна", GameState.owns_tool("iron_pickaxe"))
	check("v1: инвентарь и монеты на месте", GameState.get_item_count("iron_ore") == 4 and GameState.coins == 900)
	check("v1: состояние пригодно к игре", _state_sane())



## Ящик-страховка убран (решение владельца, раунд 5). Сейвы до этого несут его блок —
## грузятся без ошибок, блок молча пропускается, содержимое не «высыпается» в рюкзак,
## а следующее сохранение блок уже не пишет.
const OLD_BOX := "black_box"   # ключ блока (и префикс полей GameState) в старых сейвах


func _test_old_save_with_removed_box() -> void:
	_fresh()
	GameState.coins = 321
	GameState.add_item("iron_ore", 3)
	SaveSystem.save_game()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://save.json"))
	check("новый сейв блока ящика не пишет", not data.has(OLD_BOX))
	data[OLD_BOX] = {"tier": "premium_plus", "contents": {"gold": 7, "diamond": 2}}
	_write("user://save.json", JSON.stringify(data))
	GameState.reset_progress()
	check("сейв со старым блоком ящика загружается", SaveSystem.load_game())
	check("ящик: монеты и рюкзак из сейва на месте", GameState.coins == 321 and GameState.get_item_count("iron_ore") == 3)
	check("ящик: содержимое не попало в рюкзак", GameState.get_item_count("gold") == 0 and GameState.get_item_count("diamond") == 0,
		str(GameState.inventory))
	check("ящик: у GameState такого поля больше нет", GameState.get(OLD_BOX) == null and GameState.get(OLD_BOX + "_tier") == null)
	check("ящик: состояние пригодно к игре", _state_sane())
	SaveSystem.save_game()
	var again: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://save.json"))
	check("ящик: пересохранённый сейв от блока очищен", not again.has(OLD_BOX))
	# Испорченный старый блок (не словарь, не те типы внутри) тоже ничего не ломает.
	for junk in ["мусор", {"tier": 5, "contents": [1, 2]}, {"contents": {"gold": "много"}}]:
		data[OLD_BOX] = junk
		_write("user://save.json", JSON.stringify(data))
		GameState.reset_progress()
		check("ящик: испорченный блок %s не мешает загрузке" % str(junk).left(24),
			SaveSystem.load_game() and GameState.coins == 321 and _state_sane())


func _test_garbage_and_truncated() -> void:
	_fresh()
	GameState.coins = 777
	GameState.max_depth_reached = 33
	var before_coins := GameState.coins

	_write("user://save.json", "это не json {{{")
	check("мусор в сейве: загрузка не падает и сообщает об отказе", not SaveSystem.load_game())
	check("мусор: состояние в памяти не тронуто", GameState.coins == before_coins and _state_sane())

	_write("user://save.json", "")
	check("пустой файл: отказ без падения", not SaveSystem.load_game())

	_write("user://save.json", "[1, 2, 3]")
	check("JSON не-объект: отказ без падения", not SaveSystem.load_game())

	# Обрезанный файл: пишем настоящий сейв и отрезаем хвост на середине.
	GameState.coins = 999
	SaveSystem.save_game()
	var full := FileAccess.get_file_as_string("user://save.json")
	_write("user://save.json", full.substr(0, full.length() / 2))
	GameState.coins = 5
	check("обрезанный файл: отказ без падения", not SaveSystem.load_game())
	check("обрезанный файл: состояние в памяти не тронуто и пригодно", GameState.coins == 5 and _state_sane())


func _test_wrong_types() -> void:
	# Валидный JSON с неверными типами внутри: ручная правка, битая синхронизация, чужая версия.
	# Ошибка скрипта посреди _apply не роняет игру, но бросает остальной сейв «на полпути», поэтому
	# после каждой загрузки проверяем маркеры: глубина 60 лежит в другом блоке и обязана доехать,
	# монеты 1500 — тоже, если мусор не в их блоке.
	var cases := {
		"инвентарь — число": [{"inventory": 5}, true],
		"инвентарь с null и массивом": [{"inventory": {"gold": null, "iron_ore": [1], "lead": 2}}, true],
		"ветки прокачки — строка": [{"progression": {"skill_stages": "x", "xp": 10}}, true],
		"блок валюты — массив": [{"currency": [1, 2]}, false],
		"ext — массив": [{"ext": [1, 2]}, true],
		"собранные артефакты — словарь": [{"artifacts": {"collected": {"a": 1}}}, true],
		"монеты — строка": [{"currency": {"coins": "много"}}, false],
		"монеты — null": [{"currency": {"coins": null, "dollars": 4}}, false],
		"hp — массив": [{"survival": {"hp": [1], "is_alive": "да"}}, true],
		"владение инструментами — число": [{"economy": {"owned_tools": 3, "owned_gear": "x"}}, true],
		"дом — число": [{"house": 7}, true],
		"еда у двери — строка": [{"house": {"food_at_door": "x", "hatch_built": "да"}}, true],
		"версия — строка": [{"version": "два"}, true],
		"версия — словарь": [{"version": {"a": 1}}, true],
	}
	for name: String in cases.keys():
		_fresh()
		GameState.coins = 42
		var save: Dictionary = {"version": 2, "currency": {"coins": 1500}, "depth": {"max_depth_reached": 60}}
		save.merge(cases[name][0], true)
		_write("user://save.json", JSON.stringify(save))
		var loaded := SaveSystem.load_game()
		check("мусорные типы (%s): загрузка прошла, состояние пригодно" % name, loaded and _state_sane())
		check("мусорные типы (%s): остальной сейв доехал (глубина 60)" % name, GameState.max_depth_reached == 60,
			"глубина %d" % GameState.max_depth_reached)
		if bool(cases[name][1]):
			check("мусорные типы (%s): монеты 1500 доехали" % name, GameState.coins == 1500, "монеты %d" % GameState.coins)


# ---------------------------------------------------------------------------
# Резервная копия: оборванная запись не стоит игроку прогресса
# ---------------------------------------------------------------------------

func _test_backup_recovery() -> void:
	_fresh()
	GameState.coins = 4000
	SaveSystem.save_game()
	GameState.coins = 4100
	SaveSystem.save_game()
	check("после второй записи рядом лежит резервная копия", FileAccess.file_exists("user://save.json.bak"))

	# Главный файл испорчен (обрыв записи, диск) — игра поднимает копию.
	_write("user://save.json", "{\"version\": 2, \"currency\": {\"coi")
	GameState.coins = 1
	var ok := SaveSystem.load_game()
	check("испорченный сейв: подхвачена резервная копия", ok and GameState.coins == 4000,
		"монеты %d, загрузка %s" % [GameState.coins, ok])

	# Запись не оставляет временный файл.
	SaveSystem.save_game()
	check("временный файл записи убран", not FileAccess.file_exists("user://save.json.tmp"))


# ---------------------------------------------------------------------------
# Круг «сохранить — сбросить — загрузить» сохраняет всё, что пишется
# ---------------------------------------------------------------------------

func _test_round_trip() -> void:
	_fresh()
	GameState.coins = 12345
	GameState.dollars = 7
	GameState.add_item("iron_ore", 3)
	GameState.owned_tools = ["shovel", "rusty_pickaxe", "iron_pickaxe"]
	GameState.current_tool = "iron_pickaxe"
	GameState.owned_gear = ["backpack"]
	GameState.current_gear = "backpack"
	GameState.skill_stages = {"dig_speed": 3, "strength": 2}
	GameState.max_depth_reached = 88
	GameState.house_food_at_door = {"food_soup": 2}
	GameState.house_storage = {"gold": 4}
	GameState.craft_invested = {"hand_drill": {"scrap": 10}}
	GameState.ext_set("probe_area", {"level": 3, "list": [1, 2, 3]})
	var before := _snapshot()
	check("сейв записан", SaveSystem.save_game())
	GameState.reset_progress()
	check("сейв загружен", SaveSystem.load_game())
	var after := _snapshot()
	var diff := _diff(before, after)
	check("после круга сохранить → сбросить → загрузить всё записанное на месте", diff.is_empty(), diff)
	check("числа ext вернулись как есть (JSON даёт float — потребитель приводит int)",
		int(GameState.ext_get("probe_area", {}).get("level", 0)) == 3)


## Всё, что сохраняется, в сравнимом виде (числа приведены к float: JSON их не различает).
func _snapshot() -> Dictionary:
	var data: Dictionary = SaveSystem._serialize()
	data.erase("saved_at_utc")
	data.erase("world")
	return JSON.parse_string(JSON.stringify(data))


func _diff(a: Dictionary, b: Dictionary) -> String:
	var out: Array[String] = []
	for k in a.keys():
		if str(a[k]) != str(b.get(k)):
			out.append("%s: %s != %s" % [k, str(a[k]).left(80), str(b.get(k)).left(80)])
	return "; ".join(out)


# ---------------------------------------------------------------------------
# reset_progress(): хвосты состояния
# ---------------------------------------------------------------------------

## Намеренно переживают сброс: не прогресс героя, а настройки отладки, дневные лимиты рекламы,
## покупки за деньги, служебные ссылки и состояние сюжета (его обнуляет StoryDirector по
## сигналу max_depth_changed(0), см. story_director._on_max_depth_changed).
const SURVIVES_RESET := {
	"debug_instant_dig": "тумблер тестировщика", "debug_invincible": "тумблер тестировщика",
	"debug_fly_300": "тумблер тестировщика", "debug_free_shop": "тумблер тестировщика",
	"ad_daily_counts": "лимиты рекламы привязаны к реальным суткам", "last_reset_utc_date": "реальные сутки",
	"world_ref": "ссылка", "fog_ref": "ссылка",
	"world_seed": "мир сбрасывает main.gd", "world_dug_cells": "сбрасывается (запасной путь)",
	"story_flags": "StoryDirector", "story_seen": "StoryDirector", "story_queue": "StoryDirector",
	"era": "эпоху держит катсцена", "house_is_indoors": "вид дома закрывает HouseSystem",
	"_autosave_timer": "узел", "is_digging": "ставит игрок каждый кадр",
}


## Автоматический обход: каждую переменную GameState «портим» по типу, сбрасываем прогресс и
## ищем те, что не вернулись к исходному. Новое поле соседней ветки, про которое забыли в
## reset_progress(), попадёт сюда само.
func _test_reset_leaks() -> void:
	_fresh()
	var base := _vars_snapshot()
	var touched: Array[String] = []
	for prop in GameState.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n: String = prop["name"]
		if SURVIVES_RESET.has(n):
			continue
		var v = GameState.get(n)
		match typeof(v):
			TYPE_INT:
				GameState.set(n, int(v) + 7)
			TYPE_FLOAT:
				GameState.set(n, float(v) + 1.5)
			TYPE_BOOL:
				GameState.set(n, not bool(v))
			TYPE_STRING:
				GameState.set(n, String(v) + "x")
			TYPE_ARRAY:
				(v as Array).append("утечка")
			TYPE_DICTIONARY:
				(v as Dictionary)["утечка"] = 1
			TYPE_VECTOR2I:
				GameState.set(n, Vector2i(v) + Vector2i(3, 3))
			_:
				continue
		touched.append(n)
	check("обход нашёл поля состояния GameState (%d)" % touched.size(), touched.size() > 40)

	GameState.reset_progress()
	var after := _vars_snapshot()
	var leaks: Array[String] = []
	for n: String in touched:
		if str(base[n]) != str(after[n]):
			leaks.append("%s (было %s, стало %s)" % [n, str(base[n]).left(40), str(after[n]).left(40)])
	check("reset_progress() не оставляет хвостов: каждое поле вернулось к исходному", leaks.is_empty(), "\n    ".join(leaks))
	_fresh()


func _vars_snapshot() -> Dictionary:
	var out := {}
	for prop in GameState.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var v = GameState.get(prop["name"])
		out[prop["name"]] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return out

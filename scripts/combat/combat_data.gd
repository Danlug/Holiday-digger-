class_name CombatData
extends RefCounted
## CombatData — данные боя из data/combat.json (монстры, снаряжение, босс).
## Грузится лениво и кэшируется в статике; тесты сбрасывают кэш через reload().
## Числа в файле придуманы агентом и помечены proposed (раздел «Бой и монстры»
## ГДД), поэтому всё берётся через v(): значение может быть и простым числом,
## и {value, proposed, note}, как принято в проекте (Balance.unwrap).

const PATH := "res://data/combat.json"
const ART_GEAR := "res://art/gear/"
const ART_MONSTERS := "res://art/monsters/"

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _tex_cache: Dictionary = {}


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = _load_json(PATH)
	return _data


static func reload() -> void:
	_loaded = false
	_data = {}
	_tex_cache.clear()


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("CombatData: нет файла %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CombatData: не разобрался %s" % path)
		return {}
	return parsed


static func v(node, default = null):
	var x = Balance.unwrap(node)
	return default if x == null else x


static func section(name: String) -> Dictionary:
	return data().get(name, {})


static func start_depth() -> int:
	return int(v(data().get("start_depth"), 4000))


static func player_cfg(key: String, default = 0.0):
	return v(section("player").get(key), default)


static func formula(key: String, default = 0.0):
	return v(section("formula").get(key), default)


static func spawn_cfg(key: String, default = 0.0):
	return v(section("spawn").get(key), default)


# --- монстры ---

static func monster_ids() -> Array:
	return section("monsters").keys()


## Вид по id: тоннельные монстры (monsters) и стражи полостей (cave_monsters, раунд 5).
static func monster(id: String) -> Dictionary:
	var m: Dictionary = section("monsters").get(id, {})
	if m.is_empty():
		m = section("cave_monsters").get(id, {})
	return m


## Стражи полостей-фигур 1500–4000: только по своим полостям (CaveGuards), тоннельный
## спавн их не перебирает.
static func cave_monster_ids() -> Array:
	var out: Array = []
	for id in section("cave_monsters").keys():
		if typeof(section("cave_monsters")[id]) == TYPE_DICTIONARY and not String(id).begins_with("_"):
			out.append(String(id))
	return out


static func is_cave_monster(id: String) -> bool:
	return section("cave_monsters").has(id)


## Множитель характеристик монстра на глубине (HP и урон растут от нижней
## границы его пояса, чтобы глубже тот же вид был опаснее). У вида может быть
## свой темп (hp_per_1000/dmg_per_1000 в записи) — у стражей полостей он выше:
## герой между 1500 и 4000 растёт только ступенями HP.
static func hp_mult(id: String, depth: int) -> float:
	var m := monster(id)
	var d0 := int((m.get("depth", [4000, 10000]) as Array)[0])
	var k := float(m.get("hp_per_1000", v(section("scaling").get("hp_per_1000"), 0.1)))
	return 1.0 + k * maxf(0.0, float(depth - d0)) / 1000.0


static func dmg_mult(id: String, depth: int) -> float:
	var m := monster(id)
	var d0 := int((m.get("depth", [4000, 10000]) as Array)[0])
	var k := float(m.get("dmg_per_1000", v(section("scaling").get("dmg_per_1000"), 0.06)))
	return 1.0 + k * maxf(0.0, float(depth - d0)) / 1000.0


# --- снаряжение ---

static func slots() -> Array:
	return data().get("slots", [])


static func gear_ids() -> Array:
	return section("gear").keys()


static func gear(id: String) -> Dictionary:
	return section("gear").get(id, {})


static func has_gear(id: String) -> bool:
	return section("gear").has(id)


## Какие ключи слотов подходят предмету: аксессуар — любой из acc1/acc2.
static func slot_keys_for(id: String) -> Array:
	match String(gear(id).get("slot", "")):
		"accessory":
			return ["acc1", "acc2"]
		"": return []
		var s: return [s]


static func recipe(id: String) -> Dictionary:
	return gear(id).get("recipe", {})


static func craftable_ids() -> Array:
	var out: Array = []
	for id in gear_ids():
		if not recipe(String(id)).is_empty():
			out.append(String(id))
	out.sort_custom(func(a, b):
		var ta := int(gear(a).get("tier", 0))
		var tb := int(gear(b).get("tier", 0))
		return ta < tb if ta != tb else String(a) < String(b))
	return out


static func material_name(id: String) -> String:
	var m := Balance.get_mineral(id)
	if not m.is_empty():
		return String(m.get("name_ru", id))
	return String(section("materials").get(id, {}).get("name", id))


static func item_name(id: String) -> String:
	if has_gear(id):
		return String(gear(id).get("name", id))
	return material_name(id)


# --- картинки ---

static func _load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex_cache[path] = tex
	return tex


## Иконка снаряжения или материала боя (art/gear/<icon>.png, 96×96 при
## ART_SCALE 3 — на экране 32). Без файла вернёт null.
static func icon(id: String) -> Texture2D:
	var file := id
	if has_gear(id):
		file = String(gear(id).get("icon", id))
	var tex := _load_tex(ART_GEAR + file + ".png")
	if tex == null:
		tex = _load_tex(ART_GEAR + "mat_" + id + ".png")
	return tex


static func ui_icon(name: String) -> Texture2D:
	return _load_tex(ART_GEAR + "ui_" + name + ".png")

class_name WorldGen
extends RefCounted
## Детерминированная генерация мира по сиду + хранение диффов (раскопано /
## перегенерировано событием). Вся раскладка слоёв и вероятностей — в
## data/world_layers.json, здесь только алгоритм.
##
## Архитектура:
##   get_tile(x, y) — чистая функция от (world_seed, x, y, diffs, events).
##   Полный массив клеток нигде не хранится: 32 × 6000+ клеток пересчитываются
##   на лету за O(1) на клетку (несколько строковых хешей). Сохраняется только
##   то, что отличается от "чистой" генерации:
##     - diffs   — Dictionary[int key -> true], клетка выкопана игроком
##     - events  — Array[{x0,y0,w,h,salt}], зоны обвалов/землетрясений:
##                  в пределах такой зоны клетка при отсутствии диффа
##                  генерируется по тем же правилам, но с другой "солью" —
##                  получается новый, но всё ещё детерминированный слой.
##   Благодаря этому землетрясение ("перегенерировать всю копальню") не
##   трогает 190 000+ клеток эагерно — оно просто очищает diffs/events и
##   добавляет одну запись на весь мир. Это O(1) плюс O(число диффов) на
##   их отчистку, а не O(глубина × ширина).

const WIDTH := 32               # ГДД: "ширина ровно 32", это структурное правило, не баланс
const HOUSE_X_MAX := 14         # дом: 0..14
const GARDEN_X_MIN := 15        # огород: 15..31

const LAYERS_PATH := "res://data/world_layers.json"

# Нечётные константы-множители для лавинного перемешивания в _roll. Записаны
# знаковыми: int в GDScript — 64-битный со знаком, и 0x9E37... / 0xC2B2...
# в шестнадцатеричном виде движок обрезает как "слишком большие".
const MIX_A := -7046029254386353131   # 0x9E3779B97F4A7C15
const MIX_B := -4417276706812531889   # 0xC2B2AE3D27D4EB4F

var world_seed: int = 0
var layers: Dictionary = {}
var max_depth: int = 6500

var diffs: Dictionary = {}      # int key -> true (клетка выкопана)
var events: Array = []          # [{x0:int, y0:int, w:int, h:int, salt:int}, ...]

# ---- кэш разобранного world_layers.json, чтобы не парсить JSON на каждый tile ----
var _shallow_layers: Array = []
var _deep: Dictionary = {}
var _ores: Array = []
var _label_ids: Dictionary = {}
var _staircase_x_start: int = GARDEN_X_MIN
var _staircase_y_max: int = 4
var _foundation_y: int = 5
var _peat_seam_y_min: int = 450
var _peat_seam_y_max: int = 455
var _diamond_x: int = -1
var _diamond_y: int = -1
var _diamond_guards: Array = []  # [Vector2i, ...] относительно клетки алмаза
# Сценарная добыча первых уровней (обучающий круг, ГДД п.9). Словарь, а не
# массив: _permanent_feature_type зовут на каждую клетку экрана, и линейный
# перебор списка там обошёлся бы дороже самой генерации.
var _scripted_loot: Dictionary = {}  # "x,y" -> TileTypes.Type


func _init(p_world_seed: int) -> void:
	world_seed = p_world_seed
	_load_layers()


func _load_layers() -> void:
	var text := ""
	var f := FileAccess.open(LAYERS_PATH, FileAccess.READ)
	if f != null:
		text = f.get_as_text()
	if text.is_empty():
		push_error("WorldGen: не найден %s, используется минимальный запасной набор слоёв" % LAYERS_PATH)
		layers = _fallback_layers()
	else:
		var parsed = JSON.parse_string(text)
		if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
			push_error("WorldGen: %s повреждён, используется запасной набор слоёв" % LAYERS_PATH)
			layers = _fallback_layers()
		else:
			layers = parsed
	_apply_layers()


## Минимальный набор на случай отсутствия/порчи JSON — игра не должна падать.
func _fallback_layers() -> Dictionary:
	return {
		"max_depth": 6500,
		"foundation_y": 5,
		"staircase": {"x_start": GARDEN_X_MIN, "y_max": 4},
		"peat_seam": {"y_min": 450, "y_max": 455},
		"scripted_diamond": {"x": 20, "y": 80, "guard_offsets": [[-1, 0], [1, 0], [0, 1]]},
		"shallow_layers": [
			{"y_min": 1, "y_max": 1, "stone_chance": 0.03},
			{"y_min": 2, "y_max": 2, "stone_chance": 0.07},
			{"y_min": 3, "y_max": 4, "stone_chance": 0.10},
		],
		"deep": {"y_min": 6, "void_chance": 0.10, "stone_chance": 0.075},
		"ores": [
			{"id": "iron_ore", "tile": "IRON_ORE", "y_min": 5, "y_max": 200, "density": 0.075},
		],
	}


func _apply_layers() -> void:
	max_depth = int(layers.get("max_depth", 6000))
	_foundation_y = int(layers.get("foundation_y", 5))

	var st: Dictionary = layers.get("staircase", {})
	_staircase_x_start = int(st.get("x_start", GARDEN_X_MIN))
	_staircase_y_max = int(st.get("y_max", 4))

	var seam: Dictionary = layers.get("peat_seam", {})
	_peat_seam_y_min = int(seam.get("y_min", 450))
	_peat_seam_y_max = int(seam.get("y_max", 455))

	var dia: Dictionary = layers.get("scripted_diamond", {})
	_diamond_x = int(dia.get("x", -1))
	_diamond_y = int(dia.get("y", -1))
	_diamond_guards.clear()
	for off in dia.get("guard_offsets", []):
		_diamond_guards.append(Vector2i(int(off[0]), int(off[1])))

	_scripted_loot.clear()
	var loot: Dictionary = layers.get("scripted_loot", {})
	for cell in loot.get("cells", []):
		# Запасное значение — EMPTY, а не камень по умолчанию: опечатка в
		# имени тайла должна пропасть из мира, а не заложить камень поперёк
		# обучающего ряда.
		var t := TileTypes.from_name(String(cell.get("tile", "")), TileTypes.Type.EMPTY)
		if t == TileTypes.Type.EMPTY:
			continue
		_scripted_loot[_key(int(cell.get("x", -1)), int(cell.get("y", -1)))] = t

	_shallow_layers = layers.get("shallow_layers", [])
	_deep = layers.get("deep", {})
	_ores = layers.get("ores", [])


# ============================== ПУБЛИЧНОЕ API ==============================

## Главная точка входа: тип клетки (x, y) с учётом раскопок/событий.
func get_tile(x: int, y: int) -> int:
	if x < 0 or x >= WIDTH or y < 1:
		return TileTypes.Type.EMPTY

	var fixed_type := _permanent_feature_type(x, y)
	if fixed_type != -1:
		# зафиксированные структуры (фундамент/лестница/торфяной пласт/
		# сценарный алмаз) исключены из событий сброса целиком: пока не
		# выкопаны игроком — вечно те же; выкопанные — вечно пустые.
		# Это сознательное упрощение раздела 8 ГДД: рухнувшая порода
		# никогда не "досыпается" обратно поверх игрока. См. отчёт агента.
		if diffs.has(_key(x, y)):
			return TileTypes.Type.EMPTY
		return fixed_type

	if diffs.has(_key(x, y)):
		return TileTypes.Type.EMPTY

	var salt := _active_event_salt(x, y)
	return _generate_layered(x, y, salt)


## Игрок выкапывает клетку. Возвращает false, если копать нечего/нельзя
## (пусто или неразрушимый тип вроде лестницы). Проверка "тем ли инструментом"
## — вне зоны ответственности world_gen (инвентарь/инструменты — core/player).
func dig_cell(x: int, y: int) -> bool:
	if x < 0 or x >= WIDTH or y < 1:
		return false
	var current := get_tile(x, y)
	if current == TileTypes.Type.EMPTY:
		return false
	if not TileTypes.is_diggable(current):
		return false
	diffs[_key(x, y)] = true
	return true


## Сценарные клетки огорода (сейчас — пять самородков золота на 4 уровне).
## Нужны сюжету: он подсвечивает их и не пускает игрока к фундаменту, пока
## они не выбраны. Порядок списка — из data/world_layers.json.
func scripted_loot_cells() -> Array:
	var out: Array = []
	for cell in layers.get("scripted_loot", {}).get("cells", []):
		out.append(Vector2i(int(cell.get("x", -1)), int(cell.get("y", -1))))
	return out


## Глубина фундамента. Сюжету она нужна, чтобы отличить «пробил фундамент» от
## любой другой копки, а миру — чтобы не спрашивать число дважды.
func foundation_y() -> int:
	return _foundation_y


func is_dug(x: int, y: int) -> bool:
	return diffs.has(_key(x, y))


## Клетка не участвует в событиях сброса, пока не выкопана (фундамент,
## торфяной пласт, лестница, сценарный алмаз со стражами-камнями).
func is_permanent_feature(x: int, y: int) -> bool:
	return _permanent_feature_type(x, y) != -1


## Помечает прямоугольник [x0, x0+w) × [y0, y0+h) как обрушенный/
## перегенерированный новой "солью" (обвал чанка). Зафиксированные клетки
## (см. is_permanent_feature) исключаются автоматически.
func apply_chunk_event(x0: int, y0: int, w: int, h: int, salt: int) -> void:
	var cx0 := clampi(x0, 0, WIDTH)
	var cx1 := clampi(x0 + w, 0, WIDTH)
	var cy0 := clampi(y0, 1, max_depth)
	var cy1 := clampi(y0 + h, 1, max_depth)
	if cx1 <= cx0 or cy1 <= cy0:
		return
	_clear_diffs_in_rect(cx0, cy0, cx1 - cx0, cy1 - cy0)
	events.append({"x0": cx0, "y0": cy0, "w": cx1 - cx0, "h": cy1 - cy0, "salt": salt})


## Землетрясение: перегенерирует всю незафиксированную копальню. Старые
## локальные события больше не нужны — их накрывает эта одна запись,
## поэтому список событий не растёт бесконечно за игру.
func apply_global_event(salt: int) -> void:
	events.clear()
	_clear_diffs_in_rect(0, 1, WIDTH, max_depth)
	events.append({"x0": 0, "y0": 1, "w": WIDTH, "h": max_depth, "salt": salt})


func get_save_data() -> Dictionary:
	return {"dug": diffs.keys(), "events": events.duplicate(true)}


func load_save_data(data: Dictionary) -> void:
	diffs.clear()
	for k in data.get("dug", []):
		diffs[int(k)] = true
	events = (data.get("events", []) as Array).duplicate(true)


# ============================== ВНУТРЕННЕЕ ==============================

func _key(x: int, y: int) -> int:
	return y * WIDTH + x


func _clear_diffs_in_rect(x0: int, y0: int, w: int, h: int) -> void:
	var x1 := x0 + w
	var y1 := y0 + h
	for key in diffs.keys():
		var packed: int = key
		var x: int = packed % WIDTH
		var y: int = packed / WIDTH
		if x >= x0 and x < x1 and y >= y0 and y < y1 and not is_permanent_feature(x, y):
			diffs.erase(key)


## Возвращает тип зафиксированной структуры в (x, y) или -1, если клетка
## обычная (генерируется послойно).
func _permanent_feature_type(x: int, y: int) -> int:
	if y == _foundation_y:
		return TileTypes.Type.FOUNDATION
	if y >= 1 and y <= _staircase_y_max:
		if x >= _staircase_x_start and x < _staircase_x_start + y:
			return TileTypes.Type.STAIRCASE
	if y >= _peat_seam_y_min and y <= _peat_seam_y_max:
		return TileTypes.Type.PEAT
	if not _scripted_loot.is_empty():
		var loot_key := _key(x, y)
		if _scripted_loot.has(loot_key):
			return int(_scripted_loot[loot_key])
	if _diamond_x >= 0:
		if x == _diamond_x and y == _diamond_y:
			return TileTypes.Type.DIAMOND
		for off: Vector2i in _diamond_guards:
			if x == _diamond_x + off.x and y == _diamond_y + off.y:
				return TileTypes.Type.STONE
	return -1


## Соль последнего (самого свежего) события, чей прямоугольник покрывает
## (x, y); 0, если клетка не задета ни одним событием (обычная генерация).
func _active_event_salt(x: int, y: int) -> int:
	for i in range(events.size() - 1, -1, -1):
		var e: Dictionary = events[i]
		if x >= e.x0 and x < e.x0 + e.w and y >= e.y0 and y < e.y0 + e.h:
			return e.salt
	return 0


func _generate_layered(x: int, y: int, salt: int) -> int:
	for band: Dictionary in _shallow_layers:
		if y >= int(band.get("y_min", 0)) and y <= int(band.get("y_max", 0)):
			var stone_chance: float = band.get("stone_chance", 0.0)
			if _roll(x, y, "stone", salt) < stone_chance:
				return TileTypes.Type.STONE
			return TileTypes.Type.DIRT

	# глубокие слои (5+)
	var void_chance: float = _deep.get("void_chance", 0.0)
	if _roll(x, y, "void", salt) < void_chance:
		return TileTypes.Type.EMPTY

	for ore: Dictionary in _ores:
		if y < int(ore.get("y_min", 0)):
			continue
		# отсутствие y_max означает, что руда не заканчивается с глубиной
		if ore.has("y_max") and y > int(ore.get("y_max")):
			continue
		var density := _ore_density(ore, y)
		var ore_id: String = ore.get("id", "")
		if _roll(x, y, ore_id, salt) < density:
			var tile_name: String = ore.get("tile", "")
			return TileTypes.from_name(tile_name)

	var stone_chance: float = _deep.get("stone_chance", 0.0)
	if _roll(x, y, "stone", salt) < stone_chance:
		return TileTypes.Type.STONE

	return TileTypes.Type.DIRT


## Плотность руды на глубине y. Три профиля:
##   parabola — руда появляется не раньше y_min, растёт по параболе к пику на
##              peak_y, за пиком спадает, но не ниже tail: выработанных
##              насовсем горизонтов нет, редкие вкрапления есть на любой
##              глубине. Из-за этого к нижним слоям руды занимают уже больше
##              половины породы, и игроку приходится выбирать, что уносить.
##   ramp     — линейный рост density_start -> density_end к ramp_end_y (торф).
##   flat     — постоянная density.
func _ore_density(ore: Dictionary, y: int) -> float:
	var curve: String = ore.get("curve", "")

	if curve == "parabola":
		var y_min := int(ore.get("y_min", 0))
		if y < y_min:
			return 0.0
		var peak_y := int(ore.get("peak_y", y_min))
		var peak: float = ore.get("peak", 0.0)
		var tail: float = ore.get("tail", 0.0)
		var width := float(peak_y - y_min) if y <= peak_y else float(ore.get("fall_width", 1.0))
		if width <= 0.0:
			return maxf(peak, tail)
		var t := float(y - peak_y) / width
		return maxf(peak * (1.0 - t * t), tail)

	if curve == "ramp" or ore.has("ramp_end_y"):
		var y_min := int(ore.get("y_min", 0))
		var ramp_end := int(ore.get("ramp_end_y", y_min))
		var d_start: float = ore.get("density_start", 0.0)
		var d_end: float = ore.get("density_end", 0.0)
		var t := 0.0
		if ramp_end > y_min:
			t = clampf(float(y - y_min) / float(ramp_end - y_min), 0.0, 1.0)
		return lerpf(d_start, d_end, t)

	return ore.get("density", 0.0)


## Детерминированный псевдослучайный [0, 1) для клетки.
##
## Броски разных руд в одной клетке обязаны быть независимыми: руды
## проверяются по списку, и клетка достаётся первой совпавшей. Если броски
## коррелируют, то клетки, пережившие верхние руды, систематически получают
## смещённый бросок для нижних, и последняя руда в списке недобирает в разы.
## Строковый хеш такую независимость не давал — метка руды стоит в середине
## строки, а djb2 слабо размазывает различия в середине.
func _roll(x: int, y: int, label: String, salt: int) -> float:
	var h := (_label_id(label) * MIX_A) ^ (world_seed * MIX_B)
	h = (h ^ (x * 0x27D4EB2F)) * MIX_A
	h = (h ^ (y * 0x165667B1)) * MIX_B
	h = (h ^ (salt * 0x85EBCA6B)) * MIX_A
	h ^= h >> 29
	h *= MIX_B
	h ^= h >> 32
	return float((h & 0x3FFFFFFFFFFFFFFF) % 1000003) / 1000003.0


func _label_id(label: String) -> int:
	var cached: int = _label_ids.get(label, -1)
	if cached != -1:
		return cached
	var id := absi(label.hash()) | 1
	_label_ids[label] = id
	return id

class_name ArtifactSpawn
extends RefCounted
## Где в мире лежат артефакты (ГДД раздел 10).
##
## Каждый артефакт — настоящий предмет в ОДНОЙ конкретной клетке (решение
## владельца 27.10: «они должны реально быть в земле, а не просто код и шанс»).
## Клетку видно в породе, как только её открыл туман (ArtifactLayer), и предмет
## достаётся тому, кто её выкопал (ArtifactFinder). Раньше здесь была лотерея:
## 4–24 невидимых клетки-кандидата на артефакт, находка — первая выкопанная.
##
## ПОЧЕМУ меткой поверх породы, а не типом клетки в world_gen: генератор пород
## детерминирован и проверен статистически, новый «минерал» сдвинул бы все броски
## руд. Клетка остаётся той породой, что сгенерировал мир; артефакт лежит в ней.
##
## ПОЧЕМУ ничего не хранится в сейве: клетка выводится из сида мира чистой
## функцией, один и тот же сид всегда кладёт артефакт в ту же клетку. Достаточно
## списка уже собранных (GameState.collected_artifacts): собранный больше не
## рисуется и не выдаётся — старый сейв с находками дублей не получит.
##
## ПОЧЕМУ место проверяется по исходной породе (соль 0, без образований): обвал и
## землетрясение перетряхивают руду, и проверка по нынешней переносила бы предмет.
## Образования и полости клетку артефакта не вырывают (main.gd → protect_cell).
##
## Темп — как у прежней лотереи. Там на артефакт приходилось K ≈ клеток_полосы / E
## кандидатов (E — data/artifacts.json → spawn.expected_cells_dug_per_find_by_branch),
## и игрок, прочёсывающий ряды, встречал самый верхний из K — в среднем через
## ряды_полосы/(K+1) ≈ E/32 рядов от верха полосы. Одна клетка, равномерно лежащая
## в окне из 2·E/32 верхних рядов полосы, встречается в среднем там же: окна
## ~8 / 13 / 22 / 38 / 63 ряда для веток 1–5. Замер на 100 сидах, рядов от верха
## полосы до встречи по веткам: было 2–3 / 5–6 / 8–10 / 16–17 / 27–35, стало
## 2 / 4 / 8–9 / 15–17 / 27–31. Шанс заметить предмет из одной шахты у тоннеля
## (обзор рельефа 2 → 5 столбцов из 32) — 10–20%; у прежних 4–24 кандидатов было
## 11–58%: глубокие ветки из голой шахты попадаются реже, зато видны издалека и
## никуда не исчезают.

const WORLD_WIDTH := 32  # ГДД раздел 3: ширина мира ровно 32 клетки
const TRIES := 48        # попыток найти годную клетку в окне (пустоты и лава отбрасываются)

# Никчёмный клад (ряд 15) — у тоннеля Роберта (x=17), мимо его стен 16 и 18:
# спускаясь, игрок видит его в обзоре. Сам клад выдаёт сцена автокопки (ГДД п.9),
# клетка — запасной путь, если сцену пропустили.
const SCRIPTED_XS := [15, 19, 14, 20]

# Запасные значения на случай, если data/artifacts.json -> spawn отсутствует.
const FALLBACK_EXPECTED_CELLS := {1: 120, 2: 200, 3: 350, 4: 600, 5: 1000}

# Где предмета быть не может: в пустоте его не выкопать, в лаве не достать,
# несокрушимое не копается.
const BAD_TILES := [TileTypes.Type.EMPTY, TileTypes.Type.LAVA, TileTypes.Type.REINFORCED]

# Нечётные множители лавинного перемешивания. Записаны знаковыми: int в
# GDScript 64-битный со знаком, шестнадцатеричные литералы такой величины
# движок считает переполнением.
const MIX_A := -7046029254386353131   # 0x9E3779B97F4A7C15
const MIX_B := -4417276706812531889   # 0xC2B2AE3D27D4EB4F

# id:сид:мир → клетка. Слой рисования спрашивает 10 раз в секунду, а проверка
# годности — до TRIES генераций породы.
static var _cache: Dictionary = {}


# ---------------------------------------------------------------------------
# Публичное API
# ---------------------------------------------------------------------------

## Полоса глубин артефакта как Vector2i(min, max). Понимает и голое число, и
## обёртку {"value":X,"proposed":true} из data/artifacts.json.
static func depth_range(artifact: Dictionary) -> Vector2i:
	var lo := int(Balance.unwrap(artifact.get("depth_min", 0)))
	var hi := int(Balance.unwrap(artifact.get("depth_max", lo)))
	if hi < lo:
		hi = lo
	return Vector2i(lo, hi)


## true, если артефакт лежит в одном ряду и найти его обязан каждый игрок
## (Никчёмный клад на глубине 15 — скриптовая находка онбординга, ГДД п.9).
static func is_scripted_row(artifact: Dictionary) -> bool:
	var range_cells := depth_range(artifact)
	return range_cells.x == range_cells.y and _single_row_is_guaranteed()


## Сколько верхних рядов полосы занимает окно, в котором лежит предмет (см. шапку).
static func window_rows(artifact: Dictionary) -> int:
	var range_cells := depth_range(artifact)
	var rows: int = range_cells.y - range_cells.x + 1
	if is_scripted_row(artifact):
		return 1
	var expected := _expected_cells_per_find(int(artifact.get("branch", 1)))
	if expected <= 0:
		expected = 120
	return clampi(ceili(2.0 * float(expected) / WORLD_WIDTH), 1, rows)


## Клетка, в которой лежит артефакт при данном сиде. world — для проверки породы
## (в игре всегда передаётся); без него клетка берётся без проверки — только для
## чистых тестов раскладки.
static func cell_of(artifact: Dictionary, world_seed: int, world: WorldGen = null) -> Vector2i:
	var key := "%s:%d:%d" % [String(artifact.get("id", "")), world_seed,
		world.get_instance_id() if world != null else 0]
	if _cache.has(key):
		return _cache[key]
	var cell := _pick_cell(artifact, world_seed, world)
	_cache[key] = cell
	return cell


## Годится ли клетка под артефакт: внутри мира, не на дне (арена рейдбосса),
## не в зафиксированной структуре и не в доме, исходная порода копается.
static func is_valid_cell(world: WorldGen, c: Vector2i) -> bool:
	if c.x < 0 or c.x >= WORLD_WIDTH or c.y < 1:
		return false
	if world == null:
		return true
	if c.y > world.max_depth - 40:
		return false
	if world.is_permanent_feature(c.x, c.y) or world.is_house_locked_cell(c.x, c.y):
		return false
	# База без образований: образования сами спрашивают protect_cell, а тот — нас.
	return not BAD_TILES.has(world._generate_base(c.x, c.y, 0))


## id артефакта, лежащего в клетке (x, y), или "" — если клетка пустая.
## artifacts — массив из data/artifacts.json (Balance.artifacts["artifacts"]);
## передаётся аргументом, чтобы функция оставалась чистой и тестируемой.
## collected — уже собранные id: их клетки больше ничего не выдают.
static func artifact_id_at(x: int, y: int, world_seed: int, artifacts: Array,
		collected: Array = [], world: WorldGen = null) -> String:
	if x < 0 or x >= WORLD_WIDTH:
		return ""
	for a: Dictionary in artifacts:
		var id := String(a.get("id", ""))
		if collected.has(id):
			continue
		var range_cells := depth_range(a)
		if y < range_cells.x or y > range_cells.y:
			continue
		if cell_of(a, world_seed, world) == Vector2i(x, y):
			return id
	return ""


## Все артефакты, чья полоса глубин накрывает y. Нужна витрине, чтобы
## подсказать игроку, на какой глубине что искать.
static func artifacts_at_depth(y: int, artifacts: Array) -> Array:
	var out: Array = []
	for a: Dictionary in artifacts:
		var range_cells := depth_range(a)
		if y >= range_cells.x and y <= range_cells.y:
			out.append(a)
	return out


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

static func _pick_cell(artifact: Dictionary, world_seed: int, world: WorldGen) -> Vector2i:
	var range_cells := depth_range(artifact)
	var key := _artifact_key(String(artifact.get("id", "")))
	if is_scripted_row(artifact):
		var start := _mix(key, world_seed, 0)
		for i in range(SCRIPTED_XS.size()):
			var c := Vector2i(int(SCRIPTED_XS[(start + i) % SCRIPTED_XS.size()]), range_cells.x)
			if is_valid_cell(world, c):
				return c
		return Vector2i(int(SCRIPTED_XS[0]), range_cells.x)

	var rows := window_rows(artifact)
	var first := Vector2i(-1, -1)
	for i in range(TRIES):
		var hy := _mix(key, world_seed, i * 2 + 1)
		var hx := _mix(key, world_seed, i * 2 + 2)
		var c := Vector2i(int(hx % WORLD_WIDTH), range_cells.x + int(hy % rows))
		if i == 0:
			first = c
		if is_valid_cell(world, c):
			return c
	# shortcut: окно целиком из пустот/лавы не встречалось ни на одном сиде; тогда
	# предмет лежит в первой клетке — пустая подбирается касанием (ArtifactFinder).
	return first


static func _spawn_config() -> Dictionary:
	return Balance.artifacts.get("spawn", {})


static func _expected_cells_per_find(branch: int) -> int:
	var table: Dictionary = _spawn_config().get("expected_cells_dug_per_find_by_branch", {})
	if table.has(str(branch)):
		return int(Balance.unwrap(table[str(branch)]))
	return int(FALLBACK_EXPECTED_CELLS.get(branch, 120))


static func _single_row_is_guaranteed() -> bool:
	return bool(Balance.unwrap(_spawn_config().get("single_row_is_guaranteed", true)))


## Стабильный числовой ключ из строкового id. String.hash() в Godot стабилен
## между запусками — иначе позиции артефактов разъезжались бы после
## перезапуска при том же сиде.
static func _artifact_key(id: String) -> int:
	return absi(id.hash()) | 1


## Детерминированный неотрицательный хеш от трёх чисел.
static func _mix(a: int, b: int, c: int) -> int:
	var h := (a * MIX_A) ^ (b * MIX_B)
	h = (h ^ (c * 0x27D4EB2F)) * MIX_A
	h ^= h >> 29
	h *= MIX_B
	h ^= h >> 32
	return h & 0x3FFFFFFFFFFFFFFF

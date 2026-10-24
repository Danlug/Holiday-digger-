class_name ArtifactSpawn
extends RefCounted
## Слой артефактов поверх генерации пород (ГДД раздел 10).
##
## ПОЧЕМУ отдельным слоем, а не типом клетки в world_gen: генератор пород
## детерминирован и проверен статистически, его кривые плотности нельзя
## трогать — добавление 26-го "минерала" сдвинуло бы все броски ниже по
## списку руд. Здесь артефакт — не порода, а метка на координате: клетка
## остаётся ровно тем, что сгенерировал world_gen, а находка выдаётся в тот
## момент, когда эту клетку выкопали.
##
## ПОЧЕМУ ничего не хранится в сейве: позиции выводятся из сида мира чистой
## функцией, один и тот же сид всегда кладёт артефакт в те же клетки.
## Достаточно списка уже собранных (GameState.collected_artifacts) — иначе
## пришлось бы тащить в сейв 25 координат и мигрировать их при каждом
## изменении полос глубин.
##
## ПОЧЕМУ кандидатов несколько, а не один: одна клетка на полосу в сотни
## рядов — это лотерея, в которую игрок не выиграет за всю игру. Число
## кандидатов считается от того, сколько клеток внутри полосы игрок в среднем
## успевает выкопать до находки (data/artifacts.json -> spawn, предложено).

const WORLD_WIDTH := 32  # ГДД раздел 3: ширина мира ровно 32 клетки

# Запасные значения на случай, если data/artifacts.json -> spawn отсутствует
# (старый файл данных): модуль обязан продолжать работать, а не делить на ноль.
const FALLBACK_EXPECTED_CELLS := {1: 120, 2: 200, 3: 350, 4: 600, 5: 1000}
const FALLBACK_MIN_CANDIDATES := 4
const FALLBACK_MAX_CANDIDATES := 24

# Нечётные множители лавинного перемешивания. Записаны знаковыми: int в
# GDScript 64-битный со знаком, шестнадцатеричные литералы такой величины
# движок считает переполнением.
const MIX_A := -7046029254386353131   # 0x9E3779B97F4A7C15
const MIX_B := -4417276706812531889   # 0xC2B2AE3D27D4EB4F


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


## Сколько клеток-кандидатов приходится на этот артефакт.
static func candidate_count(artifact: Dictionary) -> int:
	if is_scripted_row(artifact):
		return WORLD_WIDTH  # весь ряд — находку нельзя пропустить
	var range_cells := depth_range(artifact)
	var rows: int = range_cells.y - range_cells.x + 1
	var band_cells: int = rows * WORLD_WIDTH
	var expected := _expected_cells_per_find(int(artifact.get("branch", 1)))
	if expected <= 0:
		expected = 120
	var k := int(round(float(band_cells) / float(expected)))
	return clampi(k, _min_candidates(), _max_candidates())


## Клетки, в которых лежит этот артефакт при данном сиде мира.
## Кандидаты могут совпасть между собой — это не ошибка, просто чуть меньше
## шансов, и на детерминированность не влияет.
static func candidate_cells(artifact: Dictionary, world_seed: int) -> Array:
	var out: Array = []
	var range_cells := depth_range(artifact)
	var rows: int = range_cells.y - range_cells.x + 1
	var key := _artifact_key(String(artifact.get("id", "")))

	if is_scripted_row(artifact):
		for x in range(WORLD_WIDTH):
			out.append(Vector2i(x, range_cells.x))
		return out

	var count := candidate_count(artifact)
	for i in range(count):
		var hy := _mix(key, world_seed, i * 2 + 1)
		var hx := _mix(key, world_seed, i * 2 + 2)
		out.append(Vector2i(int(hx % WORLD_WIDTH), range_cells.x + int(hy % rows)))
	return out


## id артефакта, лежащего в клетке (x, y), или "" — если клетка пустая.
## artifacts — массив из data/artifacts.json (Balance.artifacts["artifacts"]);
## передаётся аргументом, чтобы функция оставалась чистой и тестируемой.
## collected — уже собранные id: их клетки больше ничего не выдают.
static func artifact_id_at(x: int, y: int, world_seed: int, artifacts: Array, collected: Array = []) -> String:
	if x < 0 or x >= WORLD_WIDTH:
		return ""
	for a: Dictionary in artifacts:
		var id := String(a.get("id", ""))
		if collected.has(id):
			continue
		var range_cells := depth_range(a)
		if y < range_cells.x or y > range_cells.y:
			continue
		for cell: Vector2i in candidate_cells(a, world_seed):
			if cell.x == x and cell.y == y:
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

static func _spawn_config() -> Dictionary:
	return Balance.artifacts.get("spawn", {})


static func _expected_cells_per_find(branch: int) -> int:
	var table: Dictionary = _spawn_config().get("expected_cells_dug_per_find_by_branch", {})
	if table.has(str(branch)):
		return int(Balance.unwrap(table[str(branch)]))
	return int(FALLBACK_EXPECTED_CELLS.get(branch, 120))


static func _min_candidates() -> int:
	return int(Balance.unwrap(_spawn_config().get("min_candidate_cells", FALLBACK_MIN_CANDIDATES)))


static func _max_candidates() -> int:
	return int(Balance.unwrap(_spawn_config().get("max_candidate_cells", FALLBACK_MAX_CANDIDATES)))


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

extends SceneTree
## test_balance.gd — headless-проверка формул Balance на опорных точках из GDD.
##
## Запуск (если Godot установлен):
##   godot --headless --script res://tests/test_balance.gd
##
## Скрипт не полагается на автолоады (SceneTree с --script не гарантирует их
## инициализацию до выполнения кастомного скрипта), а создаёт экземпляр
## balance.gd вручную и вызывает _ready() напрямую, чтобы JSON точно был
## загружен к моменту проверок.

var failures := 0
var total := 0


func _init() -> void:
	print("=== test_balance.gd ===")

	var bal = load("res://scripts/core/balance.gd").new()
	bal._ready()

	_test_fall_damage(bal)
	_test_overload(bal)
	_test_backpack_accel(bal)
	_test_jetpack(bal)
	_test_xp(bal)
	_test_mineral_data(bal)
	_test_dig_speed(bal)
	_test_luck(bal)

	_print_summary()
	quit(0 if failures == 0 else 1)


func _check(name: String, actual: float, expected: float, tolerance: float = 0.01) -> void:
	total += 1
	var ok: bool = abs(actual - expected) <= tolerance
	if not ok:
		failures += 1
	print("[%s] %s: получено=%s ожидалось=%s (допуск %s)" % [
		"OK" if ok else "FAIL", name, actual, expected, tolerance
	])


func _check_int(name: String, actual: int, expected: int) -> void:
	_check(name, float(actual), float(expected), 0.0)


# ---------------------------------------------------------------------------
# Урон от падения: 0.154 * h^2.16, h < 5 -> 0 (см. GDD раздел 6)
# ---------------------------------------------------------------------------

func _test_fall_damage(bal) -> void:
	print("--- Урон от падения ---")
	# Опорные точки, явно заданные в GDD (раздел 6): 5 клеток = 5 HP, 20 клеток = 100 HP.
	# Коэффициент 0.154 и степень 2.16 в самом GDD округлены до 3 значащих цифр,
	# поэтому формула даёт 4.98 и 99.48 — не ровно 5/100; допуск учитывает это округление.
	_check("падение 4 клетки (ниже порога)", bal.get_fall_damage(4.0), 0.0, 0.001)
	_check("падение 5 клеток ~ 5 HP", bal.get_fall_damage(5.0), 5.0, 0.6)
	_check("падение 20 клеток ~ 100 HP", bal.get_fall_damage(20.0), 100.0, 0.6)
	# Остальные строки таблицы GDD — регрессионная проверка самой формулы
	# (точный пересчёт 0.154*h^2.16), а не независимая сверка с округлённой
	# таблицей GDD (её значения 14/22/54/160/233 расходятся с формулой на
	# заметную величину именно из-за округления коэффициентов в тексте GDD).
	_check("падение 8 клеток (формула)", bal.get_fall_damage(8.0), 0.154 * pow(8.0, 2.16), 0.01)
	_check("падение 10 клеток (формула)", bal.get_fall_damage(10.0), 0.154 * pow(10.0, 2.16), 0.01)
	_check("падение 15 клеток (формула)", bal.get_fall_damage(15.0), 0.154 * pow(15.0, 2.16), 0.01)
	_check("падение 25 клеток (формула)", bal.get_fall_damage(25.0), 0.154 * pow(25.0, 2.16), 0.01)
	_check("падение 30 клеток (формула)", bal.get_fall_damage(30.0), 0.154 * pow(30.0, 2.16), 0.01)


# ---------------------------------------------------------------------------
# Перегруз: t = clamp((load/max - 0.85)/0.15, 0, 1); mult = 0.35^t (см. GDD раздел 6)
# ---------------------------------------------------------------------------

func _test_overload(bal) -> void:
	print("--- Перегруз ---")
	_check("50% груза — без замедления", bal.get_overload_speed_multiplier(30.0, 60.0), 1.0, 0.001)
	_check("85% груза — порог, ещё без замедления", bal.get_overload_speed_multiplier(51.0, 60.0), 1.0, 0.001)
	_check("100% груза — множитель 0.35", bal.get_overload_speed_multiplier(60.0, 60.0), 0.35, 0.001)
	# половина полосы перегруза (92.5%) должна давать sqrt(0.35) ~ 0.5916
	_check("92.5% груза — середина полосы", bal.get_overload_speed_multiplier(55.5, 60.0), sqrt(0.35), 0.005)


# ---------------------------------------------------------------------------
# Разгон ранца: 3 / 0.85^(load/20), потолок 3 кл/сек (см. GDD раздел 6)
# ---------------------------------------------------------------------------

func _test_backpack_accel(bal) -> void:
	print("--- Разгон ранца ---")
	_check("разгон с 60 кг ~4.9 сек", bal.get_backpack_accel_time(60.0), 4.9, 0.05)
	_check("разгон с 0 кг = 3 сек (базовое время)", bal.get_backpack_accel_time(0.0), 3.0, 0.001)
	_check("потолок скорости ранца 3 кл/сек", bal.get_backpack_max_speed(), 3.0, 0.001)


# ---------------------------------------------------------------------------
# Джетпак: удар головой 20*(ratio-0.8)/0.2, до 80% безопасно (см. GDD раздел 6)
# ---------------------------------------------------------------------------

func _test_jetpack(bal) -> void:
	print("--- Джетпак ---")
	_check("80% скорости — без урона", bal.get_jetpack_head_bump_damage(16.0, 20.0), 0.0, 0.001)
	_check("100% скорости — полный удар 20", bal.get_jetpack_head_bump_damage(20.0, 20.0), 20.0, 0.001)
	_check("90% скорости — половина удара (10)", bal.get_jetpack_head_bump_damage(18.0, 20.0), 10.0, 0.001)


# ---------------------------------------------------------------------------
# Опыт: XP(n) = 100 * n^1.5 (см. GDD раздел 11)
# ---------------------------------------------------------------------------

func _test_xp(bal) -> void:
	print("--- Опыт ---")
	_check_int("1 -> 2", bal.xp_required_for_level(1), 100)
	_check_int("5 -> 6", bal.xp_required_for_level(5), 1118)
	_check_int("10 -> 11", bal.xp_required_for_level(10), 3162)
	_check_int("25 -> 26", bal.xp_required_for_level(25), 12500)
	_check_int("50 -> 51", bal.xp_required_for_level(50), 35355)


# ---------------------------------------------------------------------------
# Данные минералов: цены и плотность из GDD (раздел 4)
# ---------------------------------------------------------------------------

func _test_mineral_data(bal) -> void:
	print("--- Минералы (опорные цены и плотность) ---")
	_check_int("земля = 1 монета", bal.get_mineral_price("earth"), 1)
	_check_int("металлолом = 5 монет", bal.get_mineral_price("scrap"), 5)
	_check_int("железо = 5 монет", bal.get_mineral_price("iron_ore"), 5)
	_check_int("серебро = 20 монет", bal.get_mineral_price("silver"), 20)
	_check_int("золото = 100 монет", bal.get_mineral_price("gold"), 100)
	_check_int("алмаз = 500 монет", bal.get_mineral_price("diamond"), 500)

	# золото — парабола: нет выше 100, пик 10% на 500, вечный хвост 2.5%
	_check("золота нет выше глубины 100", bal.get_mineral_density_percent("gold", 50), 0.0, 0.01)
	_check("плотность золота на глубине 100 = хвост 2.5%", bal.get_mineral_density_percent("gold", 100), 2.5, 0.01)
	_check("плотность золота на пике (500) = 10%", bal.get_mineral_density_percent("gold", 500), 10.0, 0.01)
	_check("плотность золота на глубине 300 = 7.5%", bal.get_mineral_density_percent("gold", 300), 7.5, 0.01)
	_check("золото не исчезает на глубине 3000 (хвост 2.5%)", bal.get_mineral_density_percent("gold", 3000), 2.5, 0.01)

	# торф: 5% на глубине 60 -> 20% на глубине 450 (линейный рост)
	_check("плотность торфа на глубине 60 = 5%", bal.get_mineral_density_percent("peat", 60), 5.0, 0.01)
	_check("плотность торфа на глубине 450 = 20%", bal.get_mineral_density_percent("peat", 450), 20.0, 0.01)


# ---------------------------------------------------------------------------
# Скорость копки: время(ступень) = 3.0 * 0.96^ступень (см. GDD раздел 6, upgrades.json)
# ---------------------------------------------------------------------------

func _test_dig_speed(bal) -> void:
	print("--- Скорость копки ---")
	_check("база копки (0 ступеней) = 3 сек/клетка", bal.get_dig_time_seconds(0), 3.0, 0.001)
	_check("копка быстрее с прокачкой (ступень 5 < база)", bal.get_dig_time_seconds(5), 3.0 * pow(0.96, 5.0), 0.001)


# ---------------------------------------------------------------------------
# Удача: множитель x2/x3/x4, шанс земля 2..10%, ресурс 1..5% (см. GDD раздел 11)
# ---------------------------------------------------------------------------

func _test_luck(bal) -> void:
	print("--- Удача ---")
	_check("множитель удачи без прокачки = 1.0", bal.get_luck_multiplier(0), 1.0, 0.001)
	_check("множитель удачи ступень 1 = x2", bal.get_luck_multiplier(1), 2.0, 0.001)
	_check("множитель удачи ступень 3 = x4", bal.get_luck_multiplier(3), 4.0, 0.001)

	var chance1: Dictionary = bal.get_luck_chance_percent(1)
	_check("шанс земли ступень 1 = 2%", chance1["earth"], 2.0, 0.001)
	_check("шанс ресурса ступень 1 = 1%", chance1["resource"], 1.0, 0.001)

	var chance5: Dictionary = bal.get_luck_chance_percent(5)
	_check("шанс земли ступень 5 = 10%", chance5["earth"], 10.0, 0.001)
	_check("шанс ресурса ступень 5 = 5%", chance5["resource"], 5.0, 0.001)


func _print_summary() -> void:
	print("=== Итог: %d/%d пройдено, %d упало ===" % [total - failures, total, failures])

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
	_test_tool_line(bal)
	_test_gear_line(bal)
	_test_drill_speed_computed(bal)
	_test_drill_rig_upgrade_tiers(bal)
	_test_no_old_rig_name()

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


func _check_true(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", name])


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

## Со старта копается в 1.3 раза быстрее (решение владельца). Множитель общий
## и лежит одним числом в balance.json: секунды у минералов заданы по
## твёрдости и переписывать их под темп нельзя — они перестанут читаться.
func _test_dig_speed(bal) -> void:
	print("--- Скорость копки ---")
	var mult: float = bal.get_global_dig_speed_multiplier()
	_check("общий множитель темпа копки = 1.3", mult, 1.3, 0.001)
	_check("база копки (0 ступеней) = 3 сек / 1.3", bal.get_dig_time_seconds(0), 3.0 / mult, 0.001)
	_check("копка быстрее с прокачкой (ступень 5 < база)",
		bal.get_dig_time_seconds(5), 3.0 * pow(0.96, 5.0) / mult, 0.001)
	_check_true("множитель ускоряет, а не замедляет", bal.get_dig_time_seconds(0) < 3.0)


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


# ---------------------------------------------------------------------------
# Линейка кирок и линейка ранцев (владелец переписал развитие игры)
#
# Проверка на уровне ДАННЫХ, без автолоадов и без магазина: цены и множители
# названы владельцем словами, и если balance.json разойдётся с этими словами,
# упасть должно здесь — раньше, чем игрок увидит не ту цену на кнопке.
# ---------------------------------------------------------------------------

func _test_tool_line(bal) -> void:
	print("--- Кирки ---")
	var want := [
		["rusty_pickaxe", 0, 1.0],
		["iron_pickaxe", 500, 1.3],
		["titanium_pickaxe", 1500, 1.6],
		["platinum_pickaxe", 10000, 2.5],
		["diamond_pickaxe", 20000, 3.5],
		["obsidian_pickaxe", 50000, 5.0],
	]
	var line: Array = bal.get_tools_in_line("pickaxe")
	_check_int("кирок ровно шесть", line.size(), 6)
	for i in range(want.size()):
		var id := String(want[i][0])
		_check_true("ступень %d — %s" % [i, id], i < line.size() and String(line[i]) == id)
		_check_int("%s: цена" % id, bal.get_tool_cost_coins(id), int(want[i][1]))
		_check("%s: копка" % id, bal.get_tool_speed_multiplier(id), float(want[i][2]), 0.0001)
		# Ворота прогресса — деньги, а не глубина (решение агента, см. отчёт).
		_check_true("%s: по глубине не ограничена" % id, bal.get_tool_max_depth(id) < 0)
	_check_int("у лопаты ограничение по глубине осталось", bal.get_tool_max_depth("shovel"), 4)
	# Кирки — только за монеты, материалов в цене нет ни у одной.
	for id in line:
		_check_true("%s покупается за одни монеты" % id, not bal.tool_needs_materials(String(id)))
	# Техника — наоборот: без материалов не собирается.
	for id in ["hand_drill", "drill_rig"]:
		_check_true("технику %s одними монетами не взять" % id, bal.tool_needs_materials(id))


func _test_gear_line(bal) -> void:
	print("--- Ранцы ---")
	var base: float = bal.get_gear_base_speed()
	_check("база линейки = прежняя PROP_SPEED (2.5 кл/с)", base, 2.5, 0.0001)
	var want := [
		["backpack", 100, 1.0],
		["backpack_plus", 1000, 2.0],
		["jetpack", 5000, 3.0],
		["jetpack_top", 20000, 10.0],
	]
	var line: Array = bal.get_gear_ids()
	_check_int("ранцев ровно четыре", line.size(), 4)
	for i in range(want.size()):
		var id := String(want[i][0])
		var mult := float(want[i][2])
		_check_true("ступень %d — %s" % [i, id], i < line.size() and String(line[i]) == id)
		_check_int("%s: цена" % id, bal.get_gear_cost_coins(id), int(want[i][1]))
		_check("%s: полёт" % id, bal.get_gear_fly_multiplier(id), mult, 0.0001)
		# Множитель — на СКОРОСТЬ полёта: потолок подъёма в клетках/сек.
		_check("%s: потолок подъёма" % id, bal.get_gear_max_speed(id), base * mult, 0.0001)
	_check_true("верхние две ступени реактивные",
		bal.get_gear_kind("jetpack") == "jet" and bal.get_gear_kind("jetpack_top") == "jet")
	_check_true("нижние две — пропеллеры",
		bal.get_gear_kind("backpack") == "prop" and bal.get_gear_kind("backpack_plus") == "prop")
	# Пустой id — не «летать со скоростью ноль», а «ранца нет»: на этом
	# держится сравнение ступеней в GameState.grant_gear.
	_check("без ранца множителя нет", bal.get_gear_fly_multiplier(""), 0.0, 0.0001)
	# Топовый джетпак быстрее всех, но всё ещё медленнее свободного падения
	# (player.gd:V_TERM = 32): падать по-прежнему опаснее, чем лететь.
	_check_true("потолок топового джетпака ниже предела падения",
		bal.get_gear_max_speed("jetpack_top") < 32.0)


## Владелец: «ручной бур копает в 2 раза быстрее, чем лучшая кирка. Бурмобиль
## копает в 2 раза лучше, чем ручной бур» — и это должно быть ВЫЧИСЛЕНО от
## текущей лучшей кирки (Balance.get_best_pickaxe_speed_multiplier), а не
## храниться отдельным числом в balance.json: иначе линейки разъедутся при
## следующей правке кирок.
func _test_drill_speed_computed(bal) -> void:
	print("--- Бур и бурмобиль: скорость от лучшей кирки ---")
	var best: float = bal.get_best_pickaxe_speed_multiplier()
	_check("лучшая кирка сейчас — обсидиановая (×5)", best, 5.0, 0.0001)
	var drill: float = bal.get_tool_speed_multiplier("hand_drill")
	var rig: float = bal.get_tool_speed_multiplier("drill_rig")
	_check("бур = 2 × лучшая кирка", drill, 2.0 * best, 0.0001)
	_check("бурмобиль = 2 × бур", rig, 2.0 * drill, 0.0001)
	_check("бурмобиль = 4 × лучшая кирка", rig, 4.0 * best, 0.0001)
	# У бура и бурмобиля в JSON больше НЕТ поля speed_multiplier — есть
	# только коэффициент относительно другого инструмента (см. balance.json).
	_check_true("hand_drill.speed_multiplier убран из JSON (считается кодом)",
		not bal.get_tool("hand_drill").has("speed_multiplier"))
	_check_true("drill_rig.speed_multiplier убран из JSON (считается кодом)",
		not bal.get_tool("drill_rig").has("speed_multiplier"))


## Задача «Апгрейд бура»: «титановый/платиновый/алмазный/обсидиановый бур,
## каждый на 20% быстрее предыдущего» — проверяется на уровне ДАННЫХ
## (get_drill_rig_speed_at_tier принимает тир параметром, в обход
## GameState.drill_rig_tier — этот bare-скрипт его не видит, см. докстринг
## файла и Balance._current_drill_rig_tier): растёт РОВНО ×1.2 от тира к
## тиру (сравнение соседних тиров, не абсолютные числа — они завтра
## пересчитаются вслед за линейкой кирок), последовательность id строго
## титан -> платина -> алмаз -> обсидиан, и у каждой ступени цена больше
## предыдущей (порядок покупки в магазине).
func _test_drill_rig_upgrade_tiers(bal) -> void:
	print("--- Апгрейд бура: тиры ×1.2 за ступень ---")
	_check_int("четыре ступени апгрейда бура", bal.get_drill_rig_tier_count(), 4)
	var want_ids := ["titanium", "platinum", "diamond", "obsidian"]
	for i in range(want_ids.size()):
		var tier := i + 1
		_check_true("тир %d — %s" % [tier, want_ids[i]],
			bal.get_drill_rig_tier_id(tier) == want_ids[i])
		_check("тир %d: собственный бонус ×1.2" % tier,
			bal.get_drill_rig_tier_speed_bonus(tier), 1.2, 0.0001)

	# Компаунд, не сумма: тир N = тир (N-1) × 1.2, начиная от тира 0 (без
	# апгрейда) — «каждый на 20% быстрее ПРЕДЫДУЩЕГО», не от базы каждый раз.
	var prev: float = bal.get_drill_rig_speed_at_tier(0)
	for tier in range(1, 5):
		var cur: float = bal.get_drill_rig_speed_at_tier(tier)
		_check("тир %d ровно ×1.2 от тира %d" % [tier, tier - 1], cur, prev * 1.2, 0.0001)
		prev = cur
	_check("тир 4 (обсидиан) = база × 1.2⁴",
		bal.get_drill_rig_speed_at_tier(4),
		bal.get_drill_rig_speed_at_tier(0) * pow(1.2, 4.0), 0.0001)

	# Последовательные цены — растут от ступени к ступени (порядок покупки),
	# без проверки конкретных сумм: они помечены proposed в balance.json и
	# может поменять владелец, не тест.
	var prev_price := 0
	for tier in range(1, 5):
		var price: int = bal.get_drill_rig_tier_cost_coins(tier)
		_check_true("тир %d: цена задана и больше предыдущей ступени" % tier,
			price > prev_price)
		prev_price = price

	# Тир 0 (апгрейда нет) не должен молчаливо тянуть бонус — множитель на
	# нём ровно 1.0, вся разница входит только со ступени 1.
	_check("тир 0: множитель апгрейда = 1.0 (апгрейда ещё нет)",
		bal.get_drill_rig_tier_multiplier(0), 1.0, 0.0001)


## Владелец: «бурмобиль называется в игре везде „бурмобиль“». Старое название
## «буровая машина» не должно встречаться ни в одной пользовательской строке
## (и ни в одном комментарии/note данных) в игровых JSON-файлах.
func _test_no_old_rig_name() -> void:
	print("--- Название «бурмобиль» везде ---")
	# Известные падежные формы старого названия — без \w-регэкспа: Godot/PCRE
	# \w по умолчанию не берёт кириллицу, а точный список форм проще и надёжнее.
	var old_forms := [
		"буровая машина", "буровой машины", "буровую машину",
		"буровой машине", "буровой машиной", "буровые машины",
	]
	for path in [
		"res://data/story_ru.json",
		"res://data/balance.json",
		"res://data/shop.json",
		"res://data/upgrades.json",
	]:
		var f := FileAccess.open(path, FileAccess.READ)
		var ok := f != null
		_check_true("%s читается" % path, ok)
		if not ok:
			continue
		var text: String = f.get_as_text().to_lower()
		f.close()
		var found := false
		for form in old_forms:
			if text.contains(form):
				found = true
				break
		_check_true("%s: нет старого названия «буровая машина»" % path, not found)


func _print_summary() -> void:
	print("=== Итог: %d/%d пройдено, %d упало ===" % [total - failures, total, failures])

extends Node
## test_player_harness — интеграционная проверка player.gd вместе с
## GameState/Balance (автозагрузки доступны только при обычной загрузке
## движка, не в headless --script, см. отчёт агента) — поэтому запускается
## как обычная сцена:
##   godot --headless --path . res://tests/test_player_harness.tscn
## и завершает процесс с кодом 0 (всё ок) или 1 (есть провалы).

var failures := 0
var total := 0
var world: WorldGen
var fog: FogOfWar
var player


func _ready() -> void:
	print("=== test_player_harness ===")
	world = WorldGen.new(4242)
	fog = FogOfWar.new()
	GameState.world_ref = world
	GameState.fog_ref = fog
	GameState.reset_progress()

	player = load("res://scripts/player/player.gd").new()
	player.world = world
	add_child(player)

	_test_gravity_and_landing()
	_test_resolve_dir_zones()
	_test_keyboard_intent()
	_test_dig_earth_gives_xp_not_coins()
	_test_shovel_cannot_dig_stone()
	_test_tutorial_gold_does_not_stun()
	_test_gear_unlock_by_depth()
	_test_exhaustion_penalty()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _tick(n: int, dt: float = 1.0 / 30.0) -> void:
	for i in range(n):
		player.physics_tick(dt)


func _find_tile(type: int, x_max: int = 15, y_min: int = 1, y_max: int = 4) -> Vector2i:
	for y in range(y_min, y_max + 1):
		for x in range(0, x_max):
			if world.get_tile(x, y) == type:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _test_gravity_and_landing() -> void:
	# Короткое падение (< 5 клеток, порог безопасности ГДД раздел 6) — без урона.
	player.x = 5.5
	player.y = -2.5   # до земли (y≈1) чуть больше 3 клеток — безопасно
	player.vx = 0.0
	player.vy = 0.0
	player.hold_dx = 0; player.hold_up = false; player.hold_down = false
	var hp_before: float = GameState.hp
	_tick(180)
	check("герой приземлился после свободного падения", player.on_ground)
	check("короткое падение (<5 клеток) — без урона", GameState.hp == hp_before)

	# Заметное падение (~10 клеток, ГДД: 17.9 кл/с ~ 22 HP) — урон обязателен,
	# но не смертелен, чтобы не оборвать физику для следующих проверок.
	player.y = -9.0
	player.vy = 0.0
	player.on_ground = false
	var hp_before2: float = GameState.hp
	_tick(240)
	check("герой приземлился после заметного падения", player.on_ground)
	check("падение (~10 клеток) — есть урон от удара", GameState.hp < hp_before2)
	check("падение с ~10 клеток не убивает (для следующих проверок)", GameState.is_alive)
	GameState.respawn()  # снимаем урон/восстанавливаем hp перед следующими блоками


func _test_resolve_dir_zones() -> void:
	var snap_side = player.resolve_dir(1.0, 0.0, 0.26)
	check("чисто горизонтальный вектор -> зона 'side'", snap_side != null and player.hold_dx == 1 and not player.hold_up)

	var snap_dead = player.resolve_dir(0.05, 0.0, 0.26)
	check("вектор внутри мёртвой зоны -> нет намерения", snap_dead == null and player.hold_dx == 0)

	player.resolve_dir(0.0, 0.0, 0.26)  # сброс зоны залипания перед следующим тестом
	var snap_down = player.resolve_dir(0.0, 1.0, 0.26)
	check("вектор строго вниз -> копать под собой", player.hold_down and player.hold_dx == 0)

	player.resolve_dir(0.0, 0.0, 0.26)
	var snap_up = player.resolve_dir(0.1, -1.0, 0.26)
	check("вектор почти строго вверх (>72° от горизонтали) -> чистый взлёт без шага", player.hold_up and player.hold_dx == 0)


## Клавиатура (WASD и стрелки): набор намерения без углового магнетизма.
## Магнетизм придуман против неточного пальца на стекле, клавиша дискретна —
## и правила у неё те же, что палец получает ПОСЛЕ магнетизма: вниз строго под
## собой без шага, вверх можно вместе с шагом.
func _test_keyboard_intent() -> void:
	player.set_intent(1, false, false)
	check("клавиша вправо — шаг вправо, без верха и низа",
		player.hold_dx == 1 and not player.hold_up and not player.hold_down)

	player.set_intent(-1, true, false)
	check("влево+вверх — бежит и прыгает одновременно",
		player.hold_dx == -1 and player.hold_up and not player.hold_down)

	player.set_intent(0, false, true)
	check("вниз — строго под собой, без шага",
		player.hold_dx == 0 and not player.hold_up and player.hold_down)

	# Зона направления сбрасывается вместе с намерением: иначе следующий кадр
	# с джойстика унаследует гистерезис от клавиатуры и «залипнет» в копке.
	player.set_intent(0, false, false)
	check("отпущенные клавиши снимают намерение",
		player.hold_dx == 0 and not player.hold_up and not player.hold_down)
	var snap = player.resolve_dir(1.0, 0.0, 0.26)
	check("после клавиатуры джойстик читается заново", snap != null and snap.x == 1)
	player.release_control()


func _test_dig_earth_gives_xp_not_coins() -> void:
	var cell := _find_tile(TileTypes.Type.DIRT)
	check("нашлась клетка земли для теста копки", cell.x >= 0)
	if cell.x < 0:
		return

	GameState.current_tool = "shovel"
	var coins_before := GameState.coins
	var xp_before := GameState.xp
	player.x = float(cell.x) - 1.0 + player.HW + 0.5
	player.y = float(cell.y) + 0.5
	player.vx = 0.0; player.vy = 0.0
	player.on_ground = true
	player.hold_dx = 1; player.hold_up = false; player.hold_down = false
	player.digging = null

	var dug := false
	for i in range(600):  # с запасом на самое долгое время копки
		player.physics_tick(1.0 / 30.0)
		if world.get_tile(cell.x, cell.y) == TileTypes.Type.EMPTY:
			dug = true
			break
	check("клетка земли выкопана", dug)
	# Копка даёт опыт, но НЕ деньги: сырьё продаётся, а не превращается в
	# монеты в момент удара (ГДД раздел 4).
	check("опыт за землю начислен", GameState.xp > xp_before)
	check("монеты за копку НЕ начислены", GameState.coins == coins_before)
	check("земля НЕ попала в инвентарь (см. ГДД раздел 4)", not GameState.inventory.has("earth"))


func _test_shovel_cannot_dig_stone() -> void:
	var cell := _find_tile(TileTypes.Type.STONE)
	if cell.x < 0:
		check("клетка камня для теста стана — пропущено (не нашлась в диапазоне)", true)
		return
	GameState.current_tool = "shovel"
	player.x = float(cell.x) - 1.0 + player.HW + 0.5
	player.y = float(cell.y) + 0.5
	player.vx = 0.0; player.vy = 0.0
	player.on_ground = true
	player.hold_dx = 1; player.hold_up = false; player.hold_down = false
	player.digging = null
	player.stun_until_msec = 0.0

	_tick(3)
	check("лопата не берёт камень — копка не началась", player.digging == null)
	check("лопата о камень — герой оглушён (стан)", player.stun_until_msec > Time.get_ticks_msec())


## Обучающее золото не оглушает. Автокопка оставляет пять самородков торчать
## посреди расчищенной земли, и первое, что делает игрок, — бьёт по ним
## лопатой. Минута стана за это приходит раньше, чем игра объяснила, что такое
## золото и зачем кирка. После сцены мастерской стан возвращается: там игрок
## уже знает, чем копают золото, и бьёт лопатой по своей воле.
func _test_tutorial_gold_does_not_stun() -> void:
	var cells: Array = world.scripted_loot_cells()
	check("сценарное золото для теста нашлось", not cells.is_empty())
	if cells.is_empty():
		return
	var cell: Vector2i = cells[0]
	GameState.current_tool = "shovel"
	GameState.story_seen.erase("workshop")
	# Автокопка к этому моменту расчистила колонку над самородком — без этого
	# герою просто негде стоять, и коллизия выталкивает его наверх.
	for y in range(1, cell.y):
		world.dig_cell(cell.x, y)
	# Ровно та поза, в которой игрок оказывается после автокопки: стоит НА
	# самородке и жмёт «вниз».
	player.x = float(cell.x) + 0.5
	player.y = float(cell.y) - 0.5
	player.vx = 0.0; player.vy = 0.0
	player.on_ground = true
	player.hold_dx = 0; player.hold_up = false; player.hold_down = true
	player.digging = null
	player.stun_until_msec = 0.0

	_tick(3)
	check("лопата не берёт сценарное золото", player.digging == null)
	check("до мастерской золото не оглушает", player.stun_until_msec <= Time.get_ticks_msec())

	# После мастерской правило общее: лопата о золото — стан.
	GameState.story_seen.append("workshop")
	player.stun_until_msec = 0.0
	player.digging = null
	_tick(3)
	check("после мастерской лопата о золото оглушает", player.stun_until_msec > Time.get_ticks_msec())
	GameState.story_seen.erase("workshop")
	player.hold_down = false
	player.stun_until_msec = 0.0


func _test_gear_unlock_by_depth() -> void:
	GameState.max_depth_reached = 0
	check("на глубине 0 ранца ещё нет", not player.has_backpack())
	GameState.max_depth_reached = player.PROP_DEPTH
	check("на глубине 10 открывается ранец с пропеллерами", player.has_backpack())
	check("джетпака на глубине 10 ещё нет", not player.has_jetpack())
	# Джетпак глубиной больше НЕ открывается (решение владельца): его
	# собирают на верстаке. Глубина осталась условием появления рецепта.
	GameState.max_depth_reached = player.JET_DEPTH
	check("глубина 100 сама джетпак не даёт", not player.has_jetpack())
	GameState.grant_gear("jetpack")
	check("собранный на верстаке джетпак работает", player.has_jetpack())
	GameState.owned_gear.erase("jetpack")
	check("на глубине 100 открывается ручной бур", player.has_hand_drill())
	check("буровой машины на глубине 100 ещё нет", not player.has_drill_rig())
	GameState.max_depth_reached = player.RIG_DEPTH - 1
	check("на клетку выше порога буровой машины ещё нет", not player.has_drill_rig())
	GameState.max_depth_reached = player.RIG_DEPTH
	check("на глубине 1000 открывается буровая машина", player.has_drill_rig())

	# Ступень должна не только открыться, но и включиться: сама машина в руках
	# героя — это другой инструмент с другой скоростью копки. Владение выдаём
	# руками: смена инструмента проходит через GameState.set_current_tool, а
	# он требует, чтобы машина была куплена или скрафчена (ГДД п.5).
	GameState.grant_tool("drill_rig")
	player._announced_rig = false
	player._check_gear_unlocks()
	check("буровая машина становится текущим инструментом",
			GameState.current_tool == "drill_rig")
	check("буровая машина копает втрое быстрее кирки",
			is_equal_approx(Balance.get_tool_speed_multiplier("drill_rig"), 3.0))


# ---------------------------------------------------------------------------
# Пустая бодрость не убивает, а мешает (ГДД раздел 7, решение владельца)
# ---------------------------------------------------------------------------

func _test_exhaustion_penalty() -> void:
	GameState.reset_progress()
	GameState.set_hunger(80.0)

	GameState.set_stamina(50.0)
	GameState._update_exhausted()
	check("с бодростью герой не обессилен", not GameState.is_exhausted)
	check("множитель скорости без штрафа = 1", is_equal_approx(GameState.get_speed_multiplier(), 1.0))

	GameState.set_stamina(0.0)
	GameState._update_exhausted()
	check("пустая бодрость -> обессилен", GameState.is_exhausted)
	check("множитель скорости со штрафом = 0.5", is_equal_approx(GameState.get_speed_multiplier(), 0.5))

	# Голод полон, бодрость пуста — HP трогать НЕЛЬЗЯ.
	var hp_before: float = GameState.hp
	GameState._tick_survival(1.0)
	check("пустая бодрость сама по себе HP не отнимает", GameState.hp >= hp_before - 0.001)

	# Пустой голод убивает по 1 HP/сек, обе пустые — по 2.
	check("голод пуст -> 1 HP/сек", is_equal_approx(Balance.get_hp_drain_per_second(true, false), 1.0))
	check("бодрость пуста -> 0 HP/сек", is_equal_approx(Balance.get_hp_drain_per_second(false, true), 0.0))
	check("обе пусты -> 2 HP/сек", is_equal_approx(Balance.get_hp_drain_per_second(true, true), 2.0))

	# Предупреждения приходят до того, как станет поздно.
	var seen: Array = []
	var cb := func(bar: String, severe: bool): seen.append([bar, severe])
	GameState.survival_warning.connect(cb)
	GameState.reset_progress()
	GameState._warned.clear()
	GameState.set_hunger(24.0)
	GameState._check_survival_warnings()
	check("на 25% голода приходит предупреждение", seen.any(func(e): return e[0] == "hunger" and not e[1]))
	GameState.set_hunger(9.0)
	GameState._check_survival_warnings()
	check("на 10% голода приходит серьёзное предупреждение", seen.any(func(e): return e[0] == "hunger" and e[1]))
	GameState.survival_warning.disconnect(cb)
	GameState.reset_progress()

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
	_test_dig_earth_gives_xp_not_coins()
	_test_shovel_cannot_dig_stone()
	_test_gear_unlock_by_depth()

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


func _test_gear_unlock_by_depth() -> void:
	GameState.max_depth_reached = 0
	check("на глубине 0 ранца ещё нет", not player.has_backpack())
	GameState.max_depth_reached = player.PROP_DEPTH
	check("на глубине 10 открывается ранец с пропеллерами", player.has_backpack())
	check("джетпака на глубине 10 ещё нет", not player.has_jetpack())
	GameState.max_depth_reached = player.JET_DEPTH
	check("на глубине 100 открывается джетпак", player.has_jetpack())
	check("на глубине 100 открывается ручной бур", player.has_hand_drill())

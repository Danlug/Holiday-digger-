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
	_test_six_direction_snap()
	_test_arrow_pad_combinations()
	_test_keyboard_intent()
	_test_dig_earth_gives_xp_not_coins()
	_test_shovel_cannot_dig_stone()
	_test_tutorial_gold_does_not_stun()
	_test_gear_unlock_by_depth()
	_test_exhaustion_penalty()
	_test_sky_ceiling()
	_test_sky_colors()
	_test_sealed_garden_gives_no_xp()

	# --- бурмобиль как транспорт ---
	_test_walks_underground_without_boarding()
	_test_rig_boarding_blocked_without_fuel()
	_test_rig_boarding_with_fuel()
	_test_rig_exit_plays_all_phases_in_order()
	_test_rig_parked_survives_save_load()
	_test_rig_fuel_consumption_accumulator()
	_test_rig_stalls_digging_without_fuel()

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
## Шесть направлений джойстика (решение владельца): ← → ↑ ↖ ↗ ↓. Вниз по
## диагонали нет — копка всегда строго под собой. Ручка встаёт ровно на
## направление, а не туда, куда указывает палец.
func _test_six_direction_snap() -> void:
	player.release_control()
	var s1 = player.resolve_dir(1.0, -0.2, 0.26)      # ~11° вверх — всё ещё шаг
	check("до 45° — чистый шаг вбок, ручка на горизонтали",
		s1 != null and is_equal_approx(s1.x, 1.0) and is_zero_approx(s1.y)
		and player.hold_dx == 1 and not player.hold_up)

	player.release_control()
	var s2 = player.resolve_dir(1.0, -1.0, 0.26)      # ровно 45° — диагональ
	check("45° — диагональ ↗: бежит и прыгает",
		s2 != null and player.hold_dx == 1 and player.hold_up)
	check("ручка на диагонали стоит ровно на 45°",
		s2 != null and is_equal_approx(s2.x, player.DIAG) and is_equal_approx(s2.y, -player.DIAG))

	player.release_control()
	var s3 = player.resolve_dir(-1.0, -1.0, 0.26)
	check("зеркальная диагональ ↖", s3 != null and player.hold_dx == -1 and player.hold_up
		and is_equal_approx(s3.x, -player.DIAG))

	player.release_control()
	var s4 = player.resolve_dir(0.2, -1.0, 0.26)      # ~79° — чистый верх
	check("круче 67.5° — чистое ↑ без шага",
		s4 != null and player.hold_dx == 0 and player.hold_up
		and is_zero_approx(s4.x) and is_equal_approx(s4.y, -1.0))

	player.release_control()
	var s5 = player.resolve_dir(0.7, 1.0, 0.26)       # вниз по диагонали
	check("вниз по диагонали не существует — это ↓ строго под собой",
		s5 != null and player.hold_dx == 0 and player.hold_down
		and is_zero_approx(s5.x) and is_equal_approx(s5.y, 1.0))
	player.release_control()


## Экранные стрелки: четыре кнопки, диагонали — двумя пальцами (↑ вместе с
## ← или →). Логика набора намерения та же, что у клавиатуры и джойстика
## после магнетизма: ↓ перебивает всё, ↑ можно вместе с шагом.
func _test_arrow_pad_combinations() -> void:
	var hud = preload("res://scripts/ui/hud.gd").new()
	hud.player = player

	check("кнопок на крестовине ровно четыре", hud.ARROW_CELLS.size() == 4)
	var dirs: Array = []
	for cell in hud.ARROW_CELLS:
		dirs.append(String(cell["dir"]))
	check("диагональных кнопок нет",
		not dirs.has("upleft") and not dirs.has("upright"))
	check("есть все четыре стороны",
		dirs.has("up") and dirs.has("down") and dirs.has("left") and dirs.has("right"))

	hud._arrows_held = {"right": true}
	hud._apply_arrows()
	check("→ — шаг вправо", player.hold_dx == 1 and not player.hold_up and not player.hold_down)

	hud._arrows_held = {"up": true, "right": true}
	hud._apply_arrows()
	check("↑ и → вместе — диагональ: бежит и прыгает",
		player.hold_dx == 1 and player.hold_up and not player.hold_down)

	hud._arrows_held = {"up": true, "left": true}
	hud._apply_arrows()
	check("↑ и ← вместе — зеркальная диагональ",
		player.hold_dx == -1 and player.hold_up)

	# ↓ перебивает всё: копка — осознанное действие, и «вниз-вбок» не бывает.
	hud._arrows_held = {"down": true, "right": true}
	hud._apply_arrows()
	check("↓ вместе с → — всё равно строго под собой",
		player.hold_dx == 0 and player.hold_down and not player.hold_up)

	# Обе горизонтальные разом гасят друг друга, а не дёргают героя.
	hud._arrows_held = {"left": true, "right": true}
	hud._apply_arrows()
	check("← и → вместе гасят друг друга", player.hold_dx == 0)

	hud.free()
	player.release_control()


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


## Запечатанный Робертом огород не должен кормить опытом. Мир клетку не
## отдаёт, но раньше результат dig_cell игнорировался, и опыт капал за сам
## удар — на грядке получалась бесконечная ферма.
func _test_sealed_garden_gives_no_xp() -> void:
	var sealed := WorldGen.new(4242)
	sealed.build_robert_tunnel()
	var prev_world = player.world
	player.world = sealed
	GameState.world_ref = sealed

	# Клетка земли в огороде вне ствола тоннеля: x=25 заведомо не 16..18.
	var cx := 25
	var cy := 2
	check("огород после Роберта запечатан", sealed.is_garden_sealed_cell(cx, cy))
	check("в запечатанном огороде клетка не пустая", sealed.get_tile(cx, cy) != TileTypes.Type.EMPTY)

	GameState.current_tool = "shovel"
	var xp_before := GameState.xp
	player.x = float(cx) - 1.0 + player.HW + 0.5
	player.y = float(cy) + 0.5
	player.vx = 0.0; player.vy = 0.0
	player.on_ground = true
	player.hold_dx = 1; player.hold_up = false; player.hold_down = false
	player.digging = null
	for i in range(600):
		player.physics_tick(1.0 / 30.0)
	check("запечатанная клетка не выкопана", sealed.get_tile(cx, cy) != TileTypes.Type.EMPTY)
	check("опыт за удары по запечатанному огороду не начислен", GameState.xp == xp_before)
	check("удар по запечатанному даже не начинается", player.digging == null)

	player.hold_dx = 0
	player.world = prev_world
	GameState.world_ref = prev_world


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


## Ранцы по глубине больше НЕ открываются: владелец переписал их в линейку из
## четырёх ступеней за монеты, и летает герой тем, что надето.
func _test_gear_unlock_by_depth() -> void:
	GameState.owned_gear.clear()
	GameState.current_gear = ""
	GameState.max_depth_reached = 0
	check("на глубине 0 летать нечем", not player.has_backpack())
	GameState.max_depth_reached = player.PROP_DEPTH
	check("глубина 10 ранца больше не выдаёт", not player.has_backpack())
	GameState.max_depth_reached = player.JET_DEPTH
	check("глубина 100 джетпака больше не выдаёт", not player.has_jetpack())

	GameState.grant_gear("backpack")
	check("купленный ранец даёт полёт", player.has_backpack())
	check("ранец — пропеллеры, а не реактивная тяга", not player.has_jetpack())
	GameState.grant_gear("jetpack")
	check("купленный джетпак надет и считается реактивным", player.has_jetpack())
	GameState.set_current_gear("backpack")
	check("надет ранец — тяга снова пропеллерная", not player.has_jetpack())
	GameState.owned_gear.clear()
	GameState.current_gear = ""
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


# ---------------------------------------------------------------------------
# Небо над поверхностью: высота, потолок полёта и цвет кромки
# ---------------------------------------------------------------------------

## Воздух над землёй конечен (world_view.gd:SKY_HEIGHT). Проверяем ровно то,
## ради чего потолок и заводился: герой на джетпаке долетает почти до верха,
## не уходит за него ни на клетку и упирается мягко — без рывка о стену.
func _test_sky_ceiling() -> void:
	GameState.reset_progress()
	# Верхняя ступень линейки: самый быстрый полёт в игре (×10 к базовому
	# ранцу). Потолок неба проверяется именно ею — на медленной ступени герой
	# просто не успевает долететь за отведённые 20 секунд, и проверка
	# говорила бы не о потолке, а о скорости ранца.
	GameState.grant_gear("jetpack_top")
	GameState.max_depth_reached = player.JET_DEPTH
	check("небо высотой 20–30 клеток (просьба владельца)",
		player.SKY_HEIGHT >= 20 and player.SKY_HEIGHT <= 30)

	player.release_control()
	player.x = 20.5
	player.y = 0.5
	player.vx = 0.0; player.vy = 0.0
	player.digging = null
	player.on_ground = true

	var ceiling: float = player._sky_ceiling()
	var top: float = player.y      # самая высокая достигнутая точка
	var v_at_top: float = 0.0
	for i in range(600):           # 20 игровых секунд непрерывного подъёма
		player.set_intent(0, true, false)
		# Пауза между толчком прыжка и включением тяги отмеряется НАСТОЯЩИМИ
		# миллисекундами (JUMP_TO_FLY_MS), а 600 кадров симуляции пролетают
		# быстрее неё — снимаем задержку руками, иначе тяга не включится
		# никогда и проверять будет нечего.
		player._fly_arm_at_msec = 0.0
		player.physics_tick(1.0 / 30.0)
		if player.y < top:
			top = player.y
			v_at_top = player.vy
	player.release_control()

	check("герой не улетает выше верха неба", top >= ceiling - 0.001)
	check("на джетпаке герой добирается до верха неба", top <= ceiling + 1.0)
	check("в потолок герой всплывает, а не влетает рывком", absf(v_at_top) < 1.0)
	GameState.reset_progress()


## Кромка неба не должна зиять дырой: render() красит на клетку выше камеры,
## а камера стоит ровно на -SKY_HEIGHT.
func _test_sky_colors() -> void:
	var view = load("res://scripts/world/world_view.gd").new()
	add_child(view)  # _ready собирает таблицу цветов
	var near_ground: Color = view._sky_color(-1)
	var at_top: Color = view._sky_color(-view.SKY_HEIGHT)
	check("небо у земли и у верхней кромки — разные тона", near_ground != at_top)
	check("строка выше верха неба тоже покрашена",
		view._sky_color(-view.SKY_HEIGHT - 1) == at_top)
	view.queue_free()


# ---------------------------------------------------------------------------
# Бурмобиль как транспорт. Уточнение владельца от 2026-09-21 поверх более
# раннего «спускаясь под землю он должен быть только в нём»: посадка НЕ
# автоматическая — кнопка «В бурмобиль» у припаркованной машины
# (player.start_rig_boarding, см. house_system.gd), а спуск пешком больше
# ничем не гейтится. Единственная истина, надета ли машина, —
# GameState.current_tool == "drill_rig" (player.is_in_rig()); где она, когда
# не надета, — GameState.rig_parked_at.
# ---------------------------------------------------------------------------

## Общая подготовка: настоящий тоннель Роберта (build_robert_tunnel) вместо
## произвольной дырки — граница поверхность/под землёй проверяется в player.gd
## по y, а не по конкретному тоннелю, но тест должен ходить тем же путём, что
## и игрок.
func _setup_rig_world() -> WorldGen:
	var w := WorldGen.new(4242)
	w.build_robert_tunnel()
	player.world = w
	GameState.world_ref = w
	GameState.reset_progress()
	GameState.owned_tools = ["shovel", "drill_rig"]
	GameState.current_tool = "shovel"
	GameState.max_depth_reached = player.RIG_DEPTH
	GameState.house_is_indoors = false
	player._was_underground = false
	player.frozen = false
	var mouth := w.tunnel_mouth()
	player.x = float(mouth.x) + 0.5
	player.y = 0.5
	player.vx = 0.0; player.vy = 0.0
	player.on_ground = false
	player.hold_dx = 0; player.hold_up = false; player.hold_down = false
	player.digging = null
	return w


func _teardown_rig_world(prev_world: WorldGen) -> void:
	player.world = prev_world
	GameState.world_ref = prev_world
	GameState.reset_progress()


## Под землю пешком теперь можно всегда — стены на входе больше нет, ни с
## бурмобилем в собственности без топлива, ни вовсе без машины. Инструмент
## при этом не трогается: спустился пешком — пешком и остался.
func _test_walks_underground_without_boarding() -> void:
	var w := _setup_rig_world()
	GameState.inventory.clear()  # брикетов нет

	var warnings: Array = []
	var cb := func(m): warnings.append(m)
	player.rig_fuel_warning.connect(cb)
	_tick(120)
	player.rig_fuel_warning.disconnect(cb)

	check("без топлива и без посадки герой всё равно уходит под тоннель", player.cell_y() >= 1)
	check("инструмент не переключился сам", GameState.current_tool == "shovel")
	check("не в бурмобиле", not player.is_in_rig())
	check("тост о топливе на спуске пешком не приходит", warnings.is_empty())
	check("машина не запаркована — её и не было", not GameState.is_rig_parked())

	_teardown_rig_world(w)


## Посадка кнопкой «В бурмобиль» (start_rig_boarding) требует, чтобы машина
## была припаркована, и без топлива отказывает тостом, не трогая инструмент
## и не убирая машину с парковки.
func _test_rig_boarding_blocked_without_fuel() -> void:
	var w := _setup_rig_world()
	GameState.inventory.clear()  # брикетов нет
	GameState.rig_parked_at = Vector2i(w.tunnel_mouth().x, 0)
	player.x = float(GameState.rig_parked_at.x) + 0.5
	player.y = 0.5

	var warnings: Array = []
	var cb := func(m): warnings.append(m)
	player.rig_fuel_warning.connect(cb)
	var started: bool = player.start_rig_boarding()
	player.rig_fuel_warning.disconnect(cb)

	check("посадка без топлива не началась", not started)
	check("player.rig_transition пуст", player.rig_transition == "")
	check("инструмент не переключился", GameState.current_tool == "shovel")
	check("машина осталась на парковке", GameState.is_rig_parked())
	check("тост «нет брикетов» пришёл", warnings.has("Нет брикетов — сделай на верстаке из угля"))

	_teardown_rig_world(w)


## С брикетами посадка играет фазами (7 ключей, суммарная длительность —
## сумма phase_frames/fps) и заканчивается тем, что герой за рулём, машина
## снята с парковки, управление разморожено.
func _test_rig_boarding_with_fuel() -> void:
	var w := _setup_rig_world()
	GameState.add_item("fuel_block", 5)
	GameState.rig_parked_at = Vector2i(w.tunnel_mouth().x, 0)
	player.x = float(GameState.rig_parked_at.x) + 0.5
	player.y = 0.5

	var entered_events: Array = []
	var cb := func(): entered_events.append(true)
	player.entered_rig.connect(cb)

	var started: bool = player.start_rig_boarding()
	check("посадка началась", started)
	check("управление заблокировано на время посадки", player.frozen)
	check("посадка идёт в обратном порядке, начиная с ключа 7", player.rig_transition_key() == 7)

	# 10 секунд с запасом хватает на любую разумную сумму фаз (7×8 кадров при
	# 7 fps — это 8 секунд).
	_tick(int(10.0 / (1.0 / 30.0)))
	player.entered_rig.disconnect(cb)

	check("посадка закончилась", player.rig_transition == "")
	check("управление разморожено", not player.frozen)
	check("герой за рулём", player.is_in_rig())
	check("машина снята с парковки", not GameState.is_rig_parked())
	check("сигнал \"сел в бурмобиль\" пришёл ровно один раз", entered_events.size() == 1)

	_teardown_rig_world(w)


## Выезд из-под земли на поверхность запускается сам (без кнопки), играет
## все семь ключей ПО ПОРЯДКУ и суммарная длительность равна сумме
## phase_frames/fps (см. art/character/rig_exit.json).
func _test_rig_exit_plays_all_phases_in_order() -> void:
	var w := _setup_rig_world()
	GameState.add_item("fuel_block", 99)
	# Железная кирка в собственности рядом с лопатой — чтобы проверить, что
	# после выезда встаёт именно ЛУЧШИЙ инструмент (по множителю скорости), а
	# не первый попавшийся или всегда лопата.
	GameState.owned_tools = ["shovel", "drill_rig", "iron_pickaxe"]
	GameState.current_tool = "drill_rig"
	player.x = float(w.tunnel_mouth().x) + 0.5
	player.y = 1.2                     # чуть ниже границы, ещё под землёй
	player.vy = -40.0                   # с запасом пересечёт y=1 за один тик
	player._was_underground = true

	_tick(1)
	check("выезд запустился сам, без кнопки", player.rig_transition == "exit")

	var seen_keys: Array = []
	var last_key := 0
	var frames := 0
	var max_frames := int(15.0 / (1.0 / 30.0))
	while player.rig_transition != "" and frames < max_frames:
		var k: int = player.rig_transition_key()
		if k != last_key:
			seen_keys.append(k)
			last_key = k
		_tick(1)
		frames += 1

	check("выезд закончился в разумное время", player.rig_transition == "")
	check("ключи шли по порядку 1..7", seen_keys == [1, 2, 3, 4, 5, 6, 7])
	check("герой больше не в бурмобиле", not player.is_in_rig())
	check("после выезда — лучший инструмент в собственности (кирка, не лопата)",
		GameState.current_tool == "iron_pickaxe")
	check("машина запаркована у устья", GameState.is_rig_parked())
	check("машина запаркована на поверхности (y=0)", GameState.rig_parked_at.y == 0)

	_teardown_rig_world(w)


## GameState.rig_parked_at — обычное поле сейва: переживает save/load, как
## house_hatch_built и остальной "дом" (см. save_system.gd).
func _test_rig_parked_survives_save_load() -> void:
	GameState.rig_parked_at = Vector2i(17, 0)
	SaveSystem.save_game()
	GameState.rig_parked_at = Vector2i(-1, -1)
	SaveSystem.load_game()
	check("парковка пережила save/load", GameState.rig_parked_at == Vector2i(17, 0))
	SaveSystem.delete_save()
	GameState.reset_progress()


## Расход топлива копится дробно (blocks_per_cell < 1) и списывает ровно один
## блок, когда накопится полная единица — не раньше и не позже.
func _test_rig_fuel_consumption_accumulator() -> void:
	GameState.reset_progress()
	GameState.inventory.clear()
	GameState.add_item("fuel_block", 3)
	player._rig_fuel_progress = 0.0

	var rate := Balance.get_drill_rig_fuel_per_cell()
	check("расход топлива на клетку задан (> 0, ПРЕДЛОЖЕНО)", rate > 0.0)
	var cells_per_block: int = int(round(1.0 / rate)) if rate > 0.0 else 1

	for i in range(maxi(cells_per_block - 1, 0)):
		player._consume_rig_fuel()
	check("до полной клеточной нормы блок цел",
		GameState.get_item_count("fuel_block") == 3)

	player._consume_rig_fuel()
	check("на %d-й клетке блок расходуется" % cells_per_block,
		GameState.get_item_count("fuel_block") == 2)

	GameState.reset_progress()


## Под землёй без топлива бурмобиль глохнет: копка не запускается вовсе
## (движение по уже прорытому при этом не трогается — эта проверка про
## копку, не про ходьбу).
func _test_rig_stalls_digging_without_fuel() -> void:
	var cell := _find_tile(TileTypes.Type.DIRT)
	check("нашлась клетка земли для теста бурмобиля без топлива", cell.x >= 0)
	if cell.x < 0:
		return

	GameState.owned_tools = ["shovel", "drill_rig"]
	GameState.current_tool = "drill_rig"
	GameState.inventory.clear()  # брикетов нет
	player.x = float(cell.x) - 1.0 + player.HW + 0.5
	player.y = float(cell.y) + 0.5
	player.vx = 0.0; player.vy = 0.0
	player.on_ground = true
	player.hold_dx = 1; player.hold_up = false; player.hold_down = false
	player.digging = null

	var warnings: Array = []
	var cb := func(m): warnings.append(m)
	player.rig_fuel_warning.connect(cb)
	_tick(30)
	player.rig_fuel_warning.disconnect(cb)
	player.hold_dx = 0

	check("без топлива бурмобиль клетку не берёт", world.get_tile(cell.x, cell.y) != TileTypes.Type.EMPTY)
	check("копка даже не начинается", player.digging == null)
	check("тост «кончилось топливо» пришёл", warnings.has("Кончилось топливо"))

	GameState.reset_progress()

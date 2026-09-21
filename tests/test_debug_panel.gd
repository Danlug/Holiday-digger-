extends Node
## test_debug_panel — проверка тестовой отладочной панели (scripts/ui/
## debug_panel.gd) и четырёх флагов GameState, которые она переключает:
## debug_instant_dig, debug_invincible, debug_fly_300, debug_free_shop.
##
## Для каждого флага проверяется ОБА направления: включение меняет поведение,
## выключение возвращает как было, — а не только "включено работает" (задание
## явно требует именно так).
##
## Запуск:  godot --headless --path . res://tests/test_debug_panel.tscn
## Код возврата — 0 (всё ок) или 1 (есть провалы), как у остальных тестов.

var failures := 0
var total := 0
var world: WorldGen
var fog: FogOfWar
var player


func _ready() -> void:
	print("=== test_debug_panel ===")
	world = WorldGen.new(4242)
	fog = FogOfWar.new()
	GameState.world_ref = world
	GameState.fog_ref = fog
	GameState.reset_progress()

	player = load("res://scripts/player/player.gd").new()
	player.world = world
	add_child(player)

	_test_flags_default_off()
	_test_instant_dig_toggle()
	_test_invincible_toggle()
	_test_fly_300_toggle()
	_test_free_shop_coins_toggle()
	_test_free_shop_dollars_toggle()
	_test_panel_ui_toggles_flags_and_paints()

	# Флаги — тестовые, не часть прогресса: возвращаем игру в обычное
	# состояние, чтобы этот тест не портил порядок запуска остальных (если
	# кто-то однажды соберёт их в один процесс).
	GameState.debug_instant_dig = false
	GameState.debug_invincible = false
	GameState.debug_fly_300 = false
	GameState.debug_free_shop = false

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _find_tile(type: int, x_min: int = WorldGen.GARDEN_X_MIN, x_max: int = WorldGen.WIDTH,
		y_min: int = 1, y_max: int = 4) -> Vector2i:
	for y in range(y_min, y_max + 1):
		for x in range(x_min, x_max):
			if world.get_tile(x, y) == type:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _test_flags_default_off() -> void:
	check("debug_instant_dig выключен по умолчанию", not GameState.debug_instant_dig)
	check("debug_invincible выключен по умолчанию", not GameState.debug_invincible)
	check("debug_fly_300 выключен по умолчанию", not GameState.debug_fly_300)
	check("debug_free_shop выключен по умолчанию", not GameState.debug_free_shop)


## «Мгновенная копка»: включённый флаг выкапывает клетку на первом же физтике
## удержания; выключенный — снова тратит обычное время (несколько тиков).
func _test_instant_dig_toggle() -> void:
	var cell := _find_tile(TileTypes.Type.DIRT)
	check("нашлась клетка земли для теста мгновенной копки", cell.x >= 0)
	if cell.x < 0:
		return

	GameState.current_tool = "shovel"
	player.x = float(cell.x) - 1.0 + player.HW + 0.5
	player.y = float(cell.y) + 0.5
	player.vx = 0.0; player.vy = 0.0
	player.on_ground = true
	player.hold_dx = 1; player.hold_up = false; player.hold_down = false
	player.digging = null

	GameState.debug_instant_dig = true
	player.physics_tick(1.0 / 30.0)
	check("вкл: клетка выкопана на первом физтике",
		world.get_tile(cell.x, cell.y) == TileTypes.Type.EMPTY)

	# --- выключаем: копка снова идёт обычное время ---
	var cell2 := _find_tile(TileTypes.Type.DIRT, cell.x + 1)
	check("нашлась вторая клетка земли (выкл)", cell2.x >= 0)
	if cell2.x < 0:
		return
	GameState.debug_instant_dig = false
	player.x = float(cell2.x) - 1.0 + player.HW + 0.5
	player.y = float(cell2.y) + 0.5
	player.vx = 0.0; player.vy = 0.0
	player.on_ground = true
	player.hold_dx = 1; player.hold_up = false; player.hold_down = false
	player.digging = null
	player.physics_tick(1.0 / 30.0)
	check("выкл: клетка НЕ выкопана на первом физтике (время копки вернулось)",
		world.get_tile(cell2.x, cell2.y) != TileTypes.Type.EMPTY)
	# Дальше должна докопаться обычным ходом — иначе тест выше ничего не
	# доказывает (мог бы просто вечно не копать).
	var dug := false
	for i in range(600):
		player.physics_tick(1.0 / 30.0)
		if world.get_tile(cell2.x, cell2.y) == TileTypes.Type.EMPTY:
			dug = true
			break
	check("выкл: клетка всё же докопалась обычным ходом", dug)


## «Бессмертие»: включённый флаг гасит любой урон через take_damage; HP не
## лечится принудительно, просто не падает. Выключенный — урон снова проходит.
func _test_invincible_toggle() -> void:
	GameState.respawn()
	var hp_before := GameState.hp

	GameState.debug_invincible = true
	GameState.take_damage(1000.0, "test")
	check("вкл: урон полностью проигнорирован", GameState.hp == hp_before)
	check("вкл: HP не подскочил сам", GameState.hp == hp_before)

	GameState.debug_invincible = false
	GameState.take_damage(10.0, "test")
	check("выкл: урон снова проходит", GameState.hp < hp_before)


## «Полёт 300»: включённый флаг ставит |vy| ровно 300 клеток/с и вверх (тяга),
## и вниз (свободное падение) — без разгона, за один вызов _move_y. Проверка
## делается на отдельном игроке без мира, чтобы коллизии/потолок неба не
## подмешивались к чистому значению скорости.
func _test_fly_300_toggle() -> void:
	var flyer = load("res://scripts/player/player.gd").new()
	add_child(flyer)
	flyer.x = 10.0
	flyer.y = 200.0  # подальше и от потолка неба, и от земли

	GameState.debug_fly_300 = true

	flyer.vy = 0.0
	flyer.thrust = "prop"  # тяга — подъём
	flyer._move_y(1.0 / 30.0)
	check("вкл: тяга даёт vy == -300 (вверх)", is_equal_approx(flyer.vy, -300.0))

	flyer.vy = 0.0
	flyer.thrust = ""  # без тяги — свободное падение
	flyer._move_y(1.0 / 30.0)
	check("вкл: без тяги vy == +300 (вниз)", is_equal_approx(flyer.vy, 300.0))

	# --- выключаем: обычная физика (разгон, а не мгновенные 300) ---
	GameState.debug_fly_300 = false
	flyer.vy = 0.0
	flyer.thrust = ""
	flyer._move_y(1.0 / 30.0)
	check("выкл: свободное падение снова разгоняется, а не прыгает на 300",
		flyer.vy > 0.0 and flyer.vy < 300.0)

	flyer.queue_free()


## «Бесплатно» (монеты): включённый флаг не списывает монеты при покупке
## любой ценой, даже если их не хватает; выключенный — обычная проверка
## достатка снова работает.
func _test_free_shop_coins_toggle() -> void:
	GameState.coins = 5
	GameState.debug_free_shop = true
	var ok := GameState.spend_coins(999999)
	check("вкл: покупка за монеты 'проходит' без учёта цены/остатка", ok)
	check("вкл: монеты не списались", GameState.coins == 5)

	GameState.debug_free_shop = false
	GameState.coins = 5
	var ok2 := GameState.spend_coins(999999)
	check("выкл: не хватает монет — списание снова отказывает", not ok2)
	check("выкл: монеты не тронуты неудавшейся покупкой", GameState.coins == 5)

	GameState.coins = 100
	var ok3 := GameState.spend_coins(40)
	check("выкл: обычная покупка по-прежнему списывает ровно цену", ok3 and GameState.coins == 60)


## «Бесплатно» (доллары) — тот же тумблер, премиум-лавка.
func _test_free_shop_dollars_toggle() -> void:
	GameState.dollars = 0
	GameState.debug_free_shop = true
	var ok := GameState.spend_dollars(500)
	check("вкл: покупка за доллары 'проходит' без остатка", ok)
	check("вкл: доллары не списались", GameState.dollars == 0)

	GameState.debug_free_shop = false
	var ok2 := GameState.spend_dollars(500)
	check("выкл: не хватает долларов — списание снова отказывает", not ok2)

	GameState.dollars = 20
	var ok3 := GameState.spend_dollars(5)
	check("выкл: обычная покупка долларами по-прежнему списывает ровно цену",
		ok3 and GameState.dollars == 15)


## Сама панель UI: кнопки-тумблеры реально переключают поля GameState (не
## только напрямую руками, как в тестах выше) и красятся в соответствии с
## состоянием — зелёная обводка включённой, серая выключенной.
func _test_panel_ui_toggles_flags_and_paints() -> void:
	GameState.debug_instant_dig = false
	GameState.debug_invincible = false
	GameState.debug_fly_300 = false
	GameState.debug_free_shop = false

	var panel := DebugPanel.new()
	add_child(panel)

	check("панель закрыта по умолчанию", not panel.is_open())
	panel.set_open(true)
	check("панель открывается", panel.is_open())

	panel.toggle("debug_instant_dig")
	check("тумблер «Копка» включил флаг в GameState", GameState.debug_instant_dig)
	var btn: Button = panel._buttons["debug_instant_dig"]
	check("кнопка «Копка» отражает включённое состояние (button_pressed)", btn.button_pressed)

	panel.toggle("debug_instant_dig")
	check("повторное нажатие тумблера «Копка» выключает флаг", not GameState.debug_instant_dig)
	check("кнопка «Копка» отражает выключенное состояние (button_pressed)", not btn.button_pressed)

	# Нажатие настоящей кнопки (сигнал pressed), а не прямой вызов toggle() —
	# проверяем, что кнопка и правда подключена к переключателю.
	var invincible_btn: Button = panel._buttons["debug_invincible"]
	invincible_btn.pressed.emit()
	check("клик по кнопке «Бессмертие» включает GameState.debug_invincible",
		GameState.debug_invincible)
	invincible_btn.pressed.emit()
	check("повторный клик выключает GameState.debug_invincible",
		not GameState.debug_invincible)

	panel.set_open(false)
	check("панель закрывается", not panel.is_open())

	panel.queue_free()

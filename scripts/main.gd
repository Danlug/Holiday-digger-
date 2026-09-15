extends Node2D
## Main — корневой оркестратор игровой сцены: создаёт мир/туман, героя,
## рендерер и HUD, ведёт игровой цикл (порядок как в web/index.html:loop —
## намерение → столкновения → туман → снаряжение → копка → отрисовка).

const TILE := 32

var world: WorldGen
var fog: FogOfWar
var player: Node2D
var world_view: Node2D
var hud: Control
var view_root: Node2D

var _collapse_timer: Timer


func _ready() -> void:
	randomize()

	var seed_value := GameState.ensure_world_seed()
	world = WorldGen.new(seed_value)
	fog = FogOfWar.new()
	GameState.world_ref = world
	GameState.fog_ref = fog
	# Первая загрузка (в GameState._ready, ещё до этого момента) не смогла
	# накатить диффы мира — world_ref тогда был null. Догружаем сейчас, когда
	# и мир, и туман уже созданы (см. save_system.gd:_serialize_world).
	SaveSystem.load_game()

	view_root = Node2D.new()
	view_root.name = "ViewRoot"
	add_child(view_root)

	world_view = preload("res://scripts/world/world_view.gd").new()
	world_view.name = "WorldView"
	world_view.world = world
	world_view.fog = fog
	view_root.add_child(world_view)

	player = preload("res://scripts/player/player.gd").new()
	player.name = "Player"
	player.world = world
	view_root.add_child(player)
	world_view.player = player

	var char_holder := preload("res://scripts/player/character_view.gd").new()
	char_holder.name = "CharacterView"
	char_holder.player = player
	view_root.add_child(char_holder)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	canvas.add_child(hud)
	hud.set_player(player)

	if not GameState.is_alive:
		GameState.respawn()

	_restore_top_soil_if_needed()
	_position_from_save_or_start()

	world_view.set_view_size(_view_w(), _view_h())

	_reveal_around_player()

	_collapse_timer = Timer.new()
	_collapse_timer.wait_time = 90.0  # ПРЕДЛОЖЕНО: частота обвалов не задана в GDD числом ("средняя")
	_collapse_timer.autostart = true
	_collapse_timer.timeout.connect(_on_collapse_tick)
	add_child(_collapse_timer)

	# --- подключение модулей (одна строка на модуль) ---
	add_child(preload("res://scenes/shop.tscn").instantiate())  # мастерская: продажа, верстак, лавка
	# --- конец блока подключения ---

	# --- сюжет --- подключение одной строкой: режиссёр сам находит игрока,
	# мир и HUD у родителя и дальше ведёт интро, катсцены и онбординг.
	add_child(StoryDirector.new())
	# --- конец блока сюжета ---

	hud.toast("Бабка улетела в Таиланд. Огород твой — копай.", 3.6)


func _view_w() -> int:
	return hud.get_view_cells().x


func _view_h() -> int:
	return hud.get_view_cells().y


func _position_from_save_or_start() -> void:
	# Стартовая позиция героя — центр огорода на поверхности (20.5, 0.5),
	# как в web-демо; между сессиями не сохраняется намеренно (см. GDD раздел
	# 9 про респаун дома) — сохраняется только прогресс/мир, не координаты.
	player.x = 20.5
	player.y = 0.5


func _restore_top_soil_if_needed() -> void:
	# см. GDD раздел 7: верхний слой земли при смерти зарастает, иначе игрок
	# возрождается над своей же дырой и падает в неё снова. GameState.is_alive
	# уже true к моменту сохранения (die() восстанавливает respawn отдельно
	# через UI сцены смерти — сама сцена смерти не реализована, см. отчёт),
	# поэтому здесь просто гарантируем, что стартовая зона огорода не дырявая
	# при каждом запуске под управлением live-инстанса.
	pass


func _reveal_around_player() -> void:
	fog.reveal_around(player.cell_x(), player.cell_y(),
		GameState.get_vision_terrain_radius(), GameState.get_vision_resource_radius())


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.033)

	hud.update_hold_intent()
	player.physics_tick(dt)
	_reveal_around_player()

	var cam: Vector2 = _camera()
	view_root.position = Vector2(-cam.x * TILE, -cam.y * TILE)
	hud.set_camera(cam)

	world_view.render(cam)

	if not GameState.is_alive:
		_handle_death()


func _camera() -> Vector2:
	var vw := float(_view_w())
	var vh := float(_view_h())
	var cam_x: float = clampf(player.x - vw / 2.0, 0.0, maxf(0.0, float(WorldGen.WIDTH) - vw))
	var cam_y: float = maxf(player.y - vh / 2.0, -2.0)
	return Vector2(cam_x, cam_y)


## Смерть (см. GDD раздел 7 и 9): инвентарь теряется (GameState.die() уже
## это сделал), верхний слой земли зарастает, герой возрождается дома.
## Полноценная сцена смерти (замедленная киносцена, см. GDD раздел 9) не
## реализована — см. итоговый отчёт; здесь мгновенный респаун.
func _handle_death() -> void:
	var x0 := 0
	var x1 := WorldGen.WIDTH
	var y0 := 1
	var y1 := 5  # первые уровни, куда чаще всего проваливается герой
	for x in range(x0, x1):
		for y in range(y0, y1):
			if world.is_dug(x, y):
				world.diffs.erase(y * WorldGen.WIDTH + x)
	fog.reset_all()
	player.teleport_home()
	GameState.respawn()
	hud.toast("Ты погиб. Минералы потеряны. В игре уцелел бы только чёрный ящик.", 4.2)


func _on_collapse_tick() -> void:
	# Частота ("средняя"/"очень редко", ГДД раздел 8) числом не задана —
	# ПРЕДЛОЖЕНО: обвал чанка раз в ~90 сек с вероятностью 35%, землетрясение
	# на порядок реже. Реальный игрок не должен стоять и смотреть, как мир
	# рушится каждую минуту — обвалы должны быть редким сюрпризом.
	if randf() < 0.35:
		CollapseEvents.trigger_chunk_collapse(world, fog)
		hud.toast("Где-то в шахте прогремел обвал.", 3.0)
	elif randf() < 0.03:
		CollapseEvents.trigger_earthquake(world, fog)
		hud.toast("Земля вздрогнула — копальню тряхнуло целиком.", 3.6)

extends Node2D
## Main — корневой оркестратор игровой сцены: создаёт мир/туман, героя,
## рендерер и HUD, ведёт игровой цикл (порядок как в web/index.html:loop —
## намерение → столкновения → туман → снаряжение → копка → отрисовка).

const TILE := 32

var world: WorldGen
var fog: FogOfWar
var player: Node2D
var world_view: Node2D
var sky_view: SkyView
var backdrop: Backdrop
var clouds_view: CloudsView
var hud: Control
var view_root: Node2D

var _collapse_timer: Timer


func _ready() -> void:
	randomize()

	# Настройки (звук/музыка/управление/радиус обзора/язык) — до всего
	# остального: звуковые шины должны существовать раньше первого чтения
	# регулятора панели настроек, а режим управления (Settings.control_mode)
	# читает hud.gd при сборке своей нижней полосы чуть ниже.
	Settings.load_from_disk()
	Settings.ensure_buses()
	Settings.apply_audio()

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

	# Порядок слоёв ViewRoot (рисуется от первого к последнему):
	#   SkyView    — градиент неба, солнце, месяц, звёзды (за всем);
	#   Backdrop   — гора вдали (параллакс) и забор со средним планом;
	#   CloudsView — облака (параллакс БЛИЖЕ горы — рисуются поверх неё, но
	#                не закреплены по высоте, см. clouds_view.gd);
	#   WorldView  — тайлы, трава, декор, дом (небо тайлами не красит).
	# Все четыре — дети одного ViewRoot: движение камеры (view_root.position)
	# достаётся им без второй копии кода.
	sky_view = preload("res://scripts/world/sky_view.gd").new()
	sky_view.name = "SkyView"
	view_root.add_child(sky_view)

	backdrop = preload("res://scripts/world/backdrop.gd").new()
	backdrop.name = "Backdrop"
	view_root.add_child(backdrop)

	clouds_view = preload("res://scripts/world/clouds_view.gd").new()
	clouds_view.name = "CloudsView"
	view_root.add_child(clouds_view)

	world_view = preload("res://scripts/world/world_view.gd").new()
	world_view.name = "WorldView"
	world_view.world = world
	world_view.fog = fog
	view_root.add_child(world_view)
	sky_view.sky_color_source = world_view

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
	ProgressScreen.attach(self)  # прокачка, музей, артефакты, рекорды
	view_root.add_child(HouseSystem.new())  # дом: сон, еда, переходы дом↔огород↔шахта
	# --- конец блока подключения ---

	# --- сюжет --- подключение одной строкой: режиссёр сам находит игрока,
	# мир и HUD у родителя и дальше ведёт интро, катсцены и онбординг.
	var story := StoryDirector.new()
	# Имя обязательно: дом ищет режиссёра через find_child("StoryDirector"),
	# а узел, созданный через .new(), получает служебное имя вроде
	# @StoryDirector@12 — по шаблону оно не находится, и дом молча оставался
	# без сюжета. Молча — потому что обе стороны написаны терпимо к
	# отсутствию друг друга, и ни одна не ругается. Ловит tests/test_wiring.
	story.name = "StoryDirector"
	add_child(story)
	# --- конец блока сюжета ---

	# Скважина работала, пока игрока не было (решение владельца): показываем
	# отчёт сразу при заходе, до всякого приветствия.
	var well_report := IdleWell.collect()
	if not well_report.is_empty():
		hud.show_well_report(well_report)
	else:
		hud.toast("Бабка улетела в Таиланд. Огород твой — копай.", 3.6)

	_apply_saved_earthquake_on_start()

	GameState.debug_action_triggered.connect(_on_debug_action)


func _view_w() -> int:
	return hud.get_view_cells().x


func _view_h() -> int:
	return hud.get_view_cells().y


func _position_from_save_or_start() -> void:
	# Стартовая позиция героя — на поверхности сразу справа от дома, слева от
	# тоннеля (player.HOME_X); между сессиями не сохраняется намеренно (см.
	# GDD раздел 9 про респаун дома) — сохраняется только прогресс/мир.
	player.x = player.HOME_X
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
	# Центр — настоящее положение героя, а не номер клетки: аура рисуется
	# оттуда же, и правило «половина клетки» должно совпадать с картинкой.
	fog.reveal_around(player.x, player.y,
		GameState.get_vision_terrain_radius(), GameState.get_vision_resource_radius())


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.033)

	hud.update_input_intent()
	player.physics_tick(dt)
	_reveal_around_player()

	var cam: Vector2 = _camera()
	view_root.position = Vector2(-cam.x * TILE, -cam.y * TILE)
	backdrop.update(cam)
	clouds_view.update(cam)
	hud.set_camera(cam)

	world_view.render(cam)
	# Солнце/месяц — экранно-относительные (DayCycle.sun_t()/moon_t() отдают
	# долю ШИРИНЫ ЭКРАНА, не всей карты, см. sky_view.gd) — без этого вызова
	# они почти всегда стояли бы за пределами узкого 7-клеточного окна камеры.
	sky_view.set_camera(cam, _view_w())

	if not GameState.is_alive:
		_handle_death()
	# Отложенное землетрясение ждёт не следующего тика таймера обвалов, а
	# самого героя: "как только вылез" — это про его шаг, а не про минуту.
	_apply_pending_earthquake_if_safe()


## Высоту неба держит рендер мира — берём число оттуда, а не заводим второе:
## камера обязана останавливаться ровно на той строке, выше которой небо уже
## не нарисовано (см. world_view.gd:SKY_HEIGHT).
const SKY_HEIGHT: int = preload("res://scripts/world/world_view.gd").SKY_HEIGHT


func _camera() -> Vector2:
	var vw := float(_view_w())
	var vh := float(_view_h())
	var cam_x: float = clampf(player.x - vw / 2.0, 0.0, maxf(0.0, float(WorldGen.WIDTH) - vw))
	# Верх неба — жёсткий предел: выше кромки смотреть не на что. Раньше здесь
	# стояло -2, и небо над огородом было толщиной в две клетки — подниматься
	# на ранце было некуда, экран упирался в землю.
	var cam_y: float = maxf(player.y - vh / 2.0, -float(SKY_HEIGHT))
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
	# Гасим туман только над заросшим слоем, а не весь мир: изменился ровно
	# он. Разведанная глубина — часы работы игрока, и смерть по ГДД отбирает
	# инвентарь, а не карту (то же правило, что у обвала: закрываем туманом
	# только то, что переписали).
	fog.reset_rect(x0, y0, x1 - x0, y1 - y0)
	player.teleport_home()
	GameState.respawn()
	hud.toast("Ты погиб. Минералы потеряны. В игре уцелел бы только чёрный ящик.", 4.2)


func _on_collapse_tick() -> void:
	# Частота ("средняя"/"очень редко", ГДД раздел 8) числом не задана —
	# ПРЕДЛОЖЕНО: обвал чанка раз в ~90 сек с вероятностью 35%, землетрясение
	# на порядок реже. Реальный игрок не должен стоять и смотреть, как мир
	# рушится каждую минуту — обвалы должны быть редким сюрпризом.
	if randf() < 0.35:
		# Обвал случается только НИЖЕ героя (решение владельца), поэтому тик
		# отдаёт его клетку. Если под ним места не нашлось, обвала не было —
		# и тоста тоже: пугать сообщением о том, чего не произошло, нечестно.
		var rect := CollapseEvents.trigger_chunk_collapse(world, fog, null, player.cell_y())
		if not rect.is_empty():
			hud.toast("Где-то в шахте прогремел обвал.", 3.0)
	elif randf() < 0.03:
		# Полный ресет не может застать героя в земле (решение владельца):
		# запоминаем событие и применяем, когда он выберется. Тост — в момент
		# РЕАЛЬНОГО применения, иначе игрок услышит грохот, которого не было.
		GameState.pending_earthquake = true
		_apply_pending_earthquake_if_safe()


## Отложенное землетрясение: полный ресет копальни не может случиться, пока
## герой в земле, — порода сомкнулась бы прямо на нём. Ждём, пока он не
## окажется дома или наверху у входа в шахту, и только тогда трясём.
func _apply_pending_earthquake_if_safe() -> bool:
	if not GameState.pending_earthquake:
		return false
	if not CollapseEvents.try_trigger_earthquake(world, fog,
			player.cell_y(), GameState.house_is_indoors):
		return false
	GameState.pending_earthquake = false
	hud.toast("Земля вздрогнула — копальню тряхнуло целиком.", 3.6)
	return true


## Землетрясение, дождавшееся своего часа в сейве. Герой закрыл игру под
## землёй — "вылезти наверх" ему уже негде, поэтому трясём копальню сейчас и
## будим его дома, а не в перетряхнутой породе (решение владельца).
func _apply_saved_earthquake_on_start() -> void:
	if not GameState.pending_earthquake:
		return
	GameState.pending_earthquake = false
	CollapseEvents.trigger_earthquake(world, fog)
	var house := HouseSystem.instance
	if house != null:
		# Дом разбирает ссылки на героя и HUD только в своём _process, а
		# спрятать HUD и заморозить героя надо уже сейчас — представляем их
		# сами, как это делает house_system._resolve_refs.
		if house.player == null:
			house.player = player
		if house.hud == null:
			house.hud = hud
		house.enter_house("bedroom")
	hud.toast("Пока тебя не было, копальню тряхнуло целиком. Ты отсиделся дома.", 4.4)


## Кнопки-действия тестовой панели (scripts/ui/debug_panel.gd) — панель сама
## не трогает ни player, ни world (решение: не тянуть к ней зависимость от
## игровых узлов), поэтому просто шлёт имя действия через
## GameState.trigger_debug_action, а исполняет его здесь, где оба узла есть.
func _on_debug_action(name: String) -> void:
	match name:
		"home":
			player.teleport_home()
		"dynamite":
			_debug_dynamite()


## «Динамит»: мгновенно копает 3×3 клетки вокруг героя (задание владельца) —
## та же единственная точка входа world.dig_cell, что у обычной лопаты, так
## что дом/запечатанный Робертом огород остаются защищены теми же правилами.
func _debug_dynamite() -> void:
	var cx: int = player.cell_x()
	var cy: int = player.cell_y()
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			world.dig_cell(cx + dx, cy + dy)
	_reveal_around_player()

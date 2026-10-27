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
var deep_backdrop: DeepBackdrop   # подземная стена пояса, видна сквозь пустоту (ветка «world»)
var ambient_fx: AmbientFx         # капли, пыль, светлячки, блики по поясам (ветка «world»)
var surface_life: SurfaceLife     # трава, бабочки, птицы, светлячки на поверхности (ветка «world»)
var collapse_fx: CollapseFx       # предупреждение и пыль обвала/землетрясения (ветка «world»)
var hud: Control
var view_root: Node2D

var _collapse_timer: Timer
var _quake_timer: Timer
var _cam_rig := CameraRig.new()     # плавная камера с упреждением и наездом (scripts/feel/)


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

	deep_backdrop = DeepBackdrop.new()
	deep_backdrop.name = "DeepBackdrop"
	view_root.add_child(deep_backdrop)

	world_view = preload("res://scripts/world/world_view.gd").new()
	world_view.name = "WorldView"
	world_view.deep_backdrop_active = true
	world_view.world = world
	world_view.fog = fog
	view_root.add_child(world_view)
	sky_view.sky_color_source = world_view

	surface_life = SurfaceLife.new()
	surface_life.name = "SurfaceLife"
	view_root.add_child(surface_life)

	player = preload("res://scripts/player/player.gd").new()
	player.name = "Player"
	player.world = world
	view_root.add_child(player)
	world_view.player = player

	ambient_fx = AmbientFx.new()
	ambient_fx.name = "AmbientFx"
	ambient_fx.world = world
	ambient_fx.fog = fog
	ambient_fx.player = player
	view_root.add_child(ambient_fx)
	# Образования не вырывают воздух из клеток артефактов: артефакт лежит в
	# породе и выдаётся при раскопке клетки, а в каверне копать нечего.
	world.set_protect_cell(_is_artifact_cell)
	collapse_fx = CollapseFx.new()
	collapse_fx.name = "CollapseFx"
	view_root.add_child(collapse_fx)

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

	var loaded_dead := not GameState.is_alive   # до респавна: умерший встаёт дома, а не там, где упал
	# Сейв мёртвым (вкладку закрыли в кадр смерти, до записи респавна) — тот же респавн, что
	# в игре: дома, верхний слой зарос. Плату и рюкзак die() уже записал в этот сейв.
	if loaded_dead:
		_handle_death()

	_restore_top_soil_if_needed()
	var spot := _position_from_save_or_start(loaded_dead)
	SaveHooks.attach(self, spot == HeroSpot.HOVER)  # место героя между сессиями и запись при закрытии (scripts/core/save_hooks.gd)

	world_view.set_view_size(_view_w(), _view_h())

	_reveal_around_player()

	# Частота обвала и землетрясения — решение владельца (ГДД §8, data/balance.json → reset_events):
	# обвал проверяется раз в 5 минут с шансом 7%, землетрясение раз в 10 минут с шансом 3%. Раньше
	# здесь стояло «раз в 90 с, 35%» (числа ещё не были заданы) — обвалы шли в 16 раз чаще, чем решено.
	var reset_events: Dictionary = Balance.balance.get("reset_events", {})
	_collapse_timer = Timer.new()
	_collapse_timer.wait_time = float(reset_events.get("chunk_collapse", {}).get("check_every_seconds", 300))
	_collapse_timer.autostart = true
	_collapse_timer.timeout.connect(_on_collapse_tick)
	add_child(_collapse_timer)
	_quake_timer = Timer.new()
	_quake_timer.wait_time = float(reset_events.get("mine_earthquake", {}).get("check_every_seconds", 600))
	_quake_timer.autostart = true
	_quake_timer.timeout.connect(_on_quake_tick)
	add_child(_quake_timer)

	# --- подключение модулей (одна строка на модуль) ---
	add_child(preload("res://scenes/shop.tscn").instantiate())  # мастерская: продажа, верстак, лавка
	ProgressScreen.attach(self)  # прокачка, музей, артефакты, рекорды
	TechSystem.attach(self)  # техника: бак и заправка, жара и лава, скважина и окно отчёта
	view_root.add_child(HouseSystem.new())  # дом: сон, еда, переходы дом↔огород↔шахта
	Juice.attach(self)  # «сок»: звук, музыка, частицы, тряска, вибро (scripts/fx/)
	Feel.attach(self)  # «ощущение»: слияние «+N», момент крупной находки, карточка потерь, вехи глубины (scripts/feel/)
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
	MetaService.attach(self)  # мета-слой: ежедневная награда, задания, достижения, дорога трофеев
	NewbieStreakService.attach(self)  # стрик новичка: 30 дней отметки за вход, пропуск за доллары, подарок за все 30 (scripts/meta/newbie_streak*.gd)
	HintDirector.attach(self)  # подсказки «знакомство с системами»: кольцо, палец, метки «new» (scripts/hints/)

	# --- бой глубже 4000: монстры, удар, снаряжение, рейдбосс на дне (ветка combat) ---
	CombatService.attach(self)
	# --- конец блока боя ---
	Mechanics.attach(self)  # механики из больших игр: тайники, азарт и лихорадка, мастерство и журнал (scripts/mechanics/)
	Guidance.attach(self)  # «Проекты»: цепочки материалов бура/скважины/бурмобиля, трекер на HUD, «нужно для…» (scripts/guidance/)
	PremiumUnloadLesson.attach(self)  # сцена «выгрузка на склад» на 150: затемнение, стрелка, объяснение (scripts/guidance/)
	TeleportWatch.attach(self)  # часы-телепорт: площадка у тоннеля, возврат вниз, обучение лавке на 200 (scripts/teleport/)

	# Скважина работала, пока игрока не было (решение владельца): показываем
	# отчёт сразу при заходе, до всякого приветствия.
	var well_report := IdleWell.collect()
	if not well_report.is_empty():
		hud.show_well_report(well_report)
	else:
		hud.toast("Бабка улетела в Таиланд. Огород твой — копай.", 3.6)

	_apply_saved_earthquake_on_start()

	GameState.debug_action_triggered.connect(_on_debug_action)


var _artifact_cells: Dictionary = {}


## В клетке лежит артефакт (ArtifactSpawn) при текущем сиде. Множество строится
## один раз, из той же функции, что и сама раскладка артефактов.
func _is_artifact_cell(x: int, y: int) -> bool:
	if _artifact_cells.is_empty():
		for a in Balance.artifacts.get("artifacts", []):
			var c := ArtifactSpawn.cell_of(a, GameState.world_seed, world)
			_artifact_cells[c.y * WorldGen.WIDTH + c.x] = true
		_artifact_cells[-1] = false
	return _artifact_cells.has(y * WorldGen.WIDTH + x)


func _view_w() -> int:
	return hud.get_view_cells().x


func _view_h() -> int:
	return hud.get_view_cells().y


func _position_from_save_or_start(loaded_dead: bool = false) -> int:
	# Закрыл игру под землёй — открыл там же (владелец, 27.10): клетка из сейва, а если она
	# стала породой — ближайшая свободная (HeroSpot). Иначе — как раньше, у дома.
	var spot := HeroSpot.restore(player, world, loaded_dead)
	if spot != HeroSpot.NONE:
		return spot
	# Стартовая позиция героя — на поверхности сразу справа от дома, слева от
	# тоннеля (player.HOME_X). Сюда же — мёртвый в сейве (GDD раздел 9 про
	# респаун дома), до конца онбординга и с отложенным землетрясением.
	#
	# player.teleport_home() делает то же самое (x=HOME_X, y=0.5) и ДОПОЛНИТЕЛЬНО
	# паркует бурмобиль/переключает инструмент, если сейв закрыли, пока герой
	# был за рулём под землёй (баг агента: current_tool == "drill_rig" и
	# GameState.rig_parked_at переживают сейв как есть — простое присваивание
	# x/y здесь оставляло машину ни на парковке, ни надетой по-настоящему,
	# приводя ровно к тому же навсегда потерянному бурмобилю, что и телепорт
	# без этого фикса, см. player.gd:teleport_home). SaveSystem.load_game()
	# выше по _ready() уже накатил current_tool/rig_parked_at до этого вызова.
	player.teleport_home()
	return HeroSpot.NONE


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

	# Камера: упреждение и плавное следование (CameraRig); наезд идёт вокруг героя,
	# поэтому его экранное положение не меняется.
	var cam: Vector2 = _cam_rig.step(player, float(_view_w()), float(_view_h()), SKY_HEIGHT, dt)
	var vt := CameraRig.view_transform(cam, _cam_rig.zoom, (Vector2(player.x, player.y) - cam) * TILE, TILE)
	view_root.position = vt.position
	view_root.scale = vt.scale
	backdrop.update(cam)
	clouds_view.update(cam)
	hud.set_camera(cam)

	world_view.render(cam)
	deep_backdrop.update(cam, _view_w(), _view_h())
	ambient_fx.update(cam, _view_w(), _view_h(), dt)
	surface_life.update(cam, _view_w(), _view_h(), dt)
	collapse_fx.update(cam, _view_w(), _view_h(), dt)
	_tick_planned_collapse(dt)
	# Солнце/месяц — экранно-относительные (DayCycle.sun_t()/moon_t() отдают
	# долю ШИРИНЫ ЭКРАНА, не всей карты, см. sky_view.gd) — без этого вызова
	# они почти всегда стояли бы за пределами узкого 7-клеточного окна камеры.
	sky_view.set_camera(cam, _view_w())

	if not GameState.is_alive:
		_handle_death()
	# Отложенное землетрясение ждёт не следующего тика таймера обвалов, а
	# самого героя: "как только вылез" — это про его шаг, а не про минуту.
	_apply_pending_earthquake_if_safe()


func _exit_tree() -> void:
	CameraRig.reset_static()   # статика переживает перезагрузку сцены


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


## Смерть (см. GDD раздел 7 и 9): рюкзак и плату больнице GameState.die() уже
## забрал, верхний слой земли зарастает, герой возрождается дома с полным HP
## (Healing.respawn_after_death), окно смерти открывает FeelDirector.
## Сюжетная смерть онбординга (§9) — своя сцена, сюда не приходит.
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
	Healing.respawn_after_death()
	# Респавн — в ту же запись, что смерть (один сейв на кадр): файл помнит героя дома, а не мёртвым там, где он упал.
	SaveSystem.save_at_frame_end("respawn")


func _on_collapse_tick() -> void:
	# Шанс — из data/balance.json (reset_events.chunk_collapse.chance_percent, 7%).
	var chance := float(Balance.balance.get("reset_events", {}).get("chunk_collapse", {}).get("chance_percent", 7))
	if randf() * 100.0 < chance:
		# Обвал случается только НИЖЕ героя (решение владельца), поэтому тик
		# отдаёт его клетку. Если под ним места не нашлось, обвала не было —
		# и тоста тоже: пугать сообщением о том, чего не произошло, нечестно.
		# Зону выбираем сразу, а бьём через COLLAPSE_WARN_SECONDS: дрожь, звук и
		# пыль в зоне — предупреждение (правила и частота те же).
		if _planned_collapse.is_empty():
			var plan := CollapseEvents.plan_chunk_collapse(world, null, player.cell_y())
			if not plan.is_empty():
				_planned_collapse = plan
				_planned_left = COLLAPSE_WARN_SECONDS
				collapse_fx.warn(plan, COLLAPSE_WARN_SECONDS)
				Fx.shake(1.6, COLLAPSE_WARN_SECONDS)
				Sfx.play("quake", 1.25, -9.0)   # глухой гул до удара; сам удар озвучивает JuiceDirector по событию


## Землетрясение: проверка раз в 10 минут, шанс 3% (reset_events.mine_earthquake).
func _on_quake_tick() -> void:
	var chance := float(Balance.balance.get("reset_events", {}).get("mine_earthquake", {}).get("chance_percent", 3))
	if randf() * 100.0 < chance:
		# Полный ресет не может застать героя в земле (решение владельца):
		# запоминаем событие и применяем, когда он выберется. Тост — в момент
		# РЕАЛЬНОГО применения, иначе игрок услышит грохот, которого не было.
		GameState.pending_earthquake = true
		_apply_pending_earthquake_if_safe()


const COLLAPSE_WARN_SECONDS := 1.6   # ПРЕДЛОЖЕНО: сколько дрожит земля до удара
var _planned_collapse: Dictionary = {}
var _planned_left := 0.0


## Предупреждение отыграло — бьём по зоне, если герой не оказался в ней или ниже
## её верха (правило «обвал не бывает выше или на уровне героя» держится и тут).
func _tick_planned_collapse(dt: float) -> void:
	if _planned_collapse.is_empty():
		return
	_planned_left -= dt
	if _planned_left > 0.0:
		return
	var plan := _planned_collapse
	_planned_collapse = {}
	if player.cell_y() >= int(plan.y0):
		collapse_fx.cancel_warning()
		return
	var rect := CollapseEvents.apply_planned(world, fog, plan)
	collapse_fx.impact(rect)
	# дрожь, звук и вибро удара — у JuiceDirector по событию «collapse»; пыль в зоне — наша
	Fx.burst("poof", Vector2((rect.x0 + rect.w * 0.5) * TILE, (rect.y0 + rect.h * 0.5) * TILE), 2.0)
	GameState.emit_event(&"collapse", {"rect": rect})
	hud.toast("Где-то в шахте прогремел обвал.", 3.0)


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
	var cam := _camera()
	collapse_fx.impact({"x0": int(floor(cam.x)), "y0": 1, "w": _view_w() + 1, "h": _view_h()})
	hud.toast("Земля вздрогнула — копальню тряхнуло целиком.", 3.6)
	GameState.emit_event(&"quake", {})  # дрожь и звук — JuiceDirector («сок»)
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

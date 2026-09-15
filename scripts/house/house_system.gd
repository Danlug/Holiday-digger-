class_name HouseSystem
extends Node2D
## HouseSystem — дом как место в мире и как сцена (ГДД п.3, 7, 9).
##
## Зачем система вообще: полоски голода и бодрости тикали вниз и убивали
## героя, а восполнить их было нечем — выживание работало в одну сторону.
## Здесь закрывается обратная сторона: кровать (сон), доставка еды и сами
## переходы «огород ↔ дом ↔ шахта».
##
## Подключается одной строкой из scripts/main.gd. Узел кладётся в ViewRoot,
## потому что экстерьер дома и люк — часть мира и обязаны ездить вместе с
## камерой; интерьер и модалка живут на своих CanvasLayer и от камеры не
## зависят.
##
## Роберту (ГДД п.9) достаточно вызвать robert_finished_garden(): дом сам
## покажет люк в мире, откроет спуск из подвала и закроет огород.

const TILE := 32
const HOUSE_SPRITE := "res://art/env/house_exterior.png"
const HATCH_SPRITE := "res://art/env/hatch.png"
const VIEW_SCENE := "res://scenes/house.tscn"
const PROMPT_SCENE := "res://scenes/house_prompt.tscn"
const STORAGE_SCENE := "res://scenes/house_storage.tscn"

## Батончик, которым система учит есть при втором истощении (ГДД п.9).
const TUTORIAL_FOOD := "energy_bar"

static var instance: HouseSystem = null

var player: Node = null
var hud: Node = null
var world: WorldGen = null

var _view: CanvasLayer = null
var _prompt: CanvasLayer = null
var _storage_view: CanvasLayer = null
var _exterior: Sprite2D = null
var _hatch: Sprite2D = null
var _button: Button = null
var _button_action: String = ""
var _storage_button: Button = null
var _prompt_action: String = ""
var _story: Node = null


func _ready() -> void:
	instance = self
	add_to_group("house_system")
	name = "HouseSystem"

	# Экстерьер рисуется ПОСЛЕ тайлов, но ДО героя: иначе дом закрывает
	# героя, стоящего у двери, а если уйти под тайлы — дом закрывает небо.
	var parent := get_parent()
	if parent != null and parent.get_child_count() > 1:
		parent.move_child(self, 1)

	_build_world_props()
	_build_scenes()

	GameState.daily_reset.connect(_on_daily_reset)

	_resolve_refs()
	_sync_world_props()


func _resolve_refs() -> void:
	if world == null:
		world = GameState.world_ref
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			player = get_tree().root.find_child("Player", true, false)
	if hud == null:
		hud = get_tree().root.find_child("HUD", true, false)
	if _story == null:
		_story = get_tree().root.find_child("StoryDirector", true, false)
		# Сюжетная система зовёт дом через свои хуки (build_hatch у Роберта,
		# ГДД п.9), но сама искать его не умеет — представляемся сами: дом
		# знает про сюжет, сюжету про дом знать не обязательно.
		if _story != null and _story.get("house") == null:
			_story.set("house", self)
	if _button == null:
		_button = get_tree().get_first_node_in_group("house_button") as Button
		if _button != null and not _button.pressed.is_connected(on_hud_button):
			# Кнопку создаёт HUD (одна строка в его блоке), а связывает и
			# ведёт дом: тексты и условия — знание дома, а не интерфейса.
			_button.pressed.connect(on_hud_button)
	if _storage_button == null:
		_storage_button = get_tree().get_first_node_in_group("house_storage_button") as Button
		if _storage_button != null and not _storage_button.pressed.is_connected(open_storage):
			_storage_button.pressed.connect(open_storage)


# ---------------------------------------------------------------------------
# Мир: дом на поверхности и люк под фундаментом
# ---------------------------------------------------------------------------

func _build_world_props() -> void:
	var door := HouseConfig.door_cell()
	if ResourceLoader.exists(HOUSE_SPRITE):
		_exterior = Sprite2D.new()
		_exterior.name = "HouseExterior"
		_exterior.centered = false
		_exterior.texture = load(HOUSE_SPRITE)
		var size := _exterior.texture.get_size()
		# Дверь на рисунке в середине фасада, поэтому фасад центрируется по
		# клетке двери. Низ ставится на ВЕРХ первой земляной клетки (y = 1), а
		# не на y = 0: земля начинается с первого слоя, и герой стоит ступнями
		# именно там — по y = 0 дом висел бы на клетку выше уровня земли.
		_exterior.position = Vector2((door.x + 0.5) * TILE - size.x * 0.5, TILE - size.y)
		add_child(_exterior)

	if ResourceLoader.exists(HATCH_SPRITE):
		_hatch = Sprite2D.new()
		_hatch.name = "Hatch"
		_hatch.centered = false
		_hatch.texture = load(HATCH_SPRITE)
		var hatch_cell := HouseConfig.hatch_cell()
		_hatch.position = Vector2(hatch_cell.x * TILE, hatch_cell.y * TILE)
		_hatch.visible = false
		add_child(_hatch)


func _sync_world_props() -> void:
	if _hatch != null:
		_hatch.visible = GameState.house_hatch_built


func _build_scenes() -> void:
	if ResourceLoader.exists(VIEW_SCENE):
		_view = (load(VIEW_SCENE) as PackedScene).instantiate()
	else:
		# Сцена — снимок того же кода (см. house_view.gd): если файл потеряли,
		# дом всё равно должен открываться, иначе игрок остаётся без еды и сна.
		_view = load("res://scripts/house/house_view.gd").new()
	add_child(_view)
	_view.action_requested.connect(_on_view_action)

	if ResourceLoader.exists(PROMPT_SCENE):
		_prompt = (load(PROMPT_SCENE) as PackedScene).instantiate()
	else:
		_prompt = load("res://scripts/house/house_prompt.gd").new()
	add_child(_prompt)
	_prompt.confirmed.connect(_on_prompt_confirmed)

	if ResourceLoader.exists(STORAGE_SCENE):
		_storage_view = (load(STORAGE_SCENE) as PackedScene).instantiate()
	else:
		_storage_view = load("res://scripts/house/house_storage_view.gd").new()
	add_child(_storage_view)
	_storage_view.closed.connect(_on_storage_closed)


# ---------------------------------------------------------------------------
# Кадр
# ---------------------------------------------------------------------------

func _process(_dt: float) -> void:
	_resolve_refs()
	_sync_world_props()
	_tick_tutorial()
	_update_hud_button()
	if _view != null and _view.visible:
		_view.refresh()
	if _storage_view != null and _storage_view.visible:
		_storage_view.refresh()


# ---------------------------------------------------------------------------
# Переходы
# ---------------------------------------------------------------------------

func is_indoors() -> bool:
	return GameState.house_is_indoors


## Стоит ли герой у входной двери (на поверхности, в радиусе взаимодействия).
func near_door() -> bool:
	if player == null:
		return false
	var door := HouseConfig.door_cell()
	return player.y < 1.5 and absf(player.x - (door.x + 0.5)) <= HouseConfig.interact_radius()


func near_hatch() -> bool:
	if player == null or not GameState.house_hatch_built:
		return false
	var hatch := HouseConfig.hatch_cell()
	return absf(player.x - (hatch.x + 0.5)) <= HouseConfig.interact_radius() \
		and absf(player.y - (hatch.y + 0.5)) <= HouseConfig.interact_radius()


func enter_house(room: String = "hall") -> void:
	GameState.house_is_indoors = true
	GameState.house_room = room
	_freeze_player(true)
	if hud != null:
		# HUD скрывается целиком: его джойстик и нижняя полоса иначе торчат
		# поверх интерьера и ловят нажатия, адресованные комнатам. Полоски
		# выживания продублированы в шапке дома.
		hud.visible = false
	if _view != null:
		_view.open(room)


## Выход через входную дверь на поверхность (ГДД п.3: дом занимает клетки
## 0–14, дверь — house.door_cell в balance.json).
func exit_to_door() -> void:
	var door := HouseConfig.door_cell()
	_leave_house(Vector2(door.x + 0.5, 0.5))


## Выход через люк в шахту (ГДД п.9). Возвращает false, если люка ещё нет.
func exit_through_hatch() -> bool:
	if not GameState.house_hatch_built:
		return false
	var hatch := HouseConfig.hatch_cell()
	_carve_hatch_cell()
	_leave_house(Vector2(hatch.x + 0.5, hatch.y + 0.5))
	return true


func _leave_house(world_pos: Vector2) -> void:
	GameState.house_is_indoors = false
	if _view != null:
		_view.close()
	if hud != null:
		hud.visible = true
	if player != null:
		player.x = world_pos.x
		player.y = world_pos.y
		player.vx = 0.0
		player.vy = 0.0
		player.digging = null
		player.thrust = ""
		player.release_control()
	_freeze_player(false)


## Клетка люка обязана быть пустой каждый раз, когда через неё выходят:
## землетрясение (ГДД п.8) стирает диффы и «зарастает» её обратно, и герой
## оказался бы замурован в породе на глубине 6.
func _carve_hatch_cell() -> void:
	if world == null:
		world = GameState.world_ref
	if world == null:
		return
	var hatch := HouseConfig.hatch_cell()
	if world.get_tile(hatch.x, hatch.y) != TileTypes.Type.EMPTY:
		world.dig_cell(hatch.x, hatch.y)
	if GameState.fog_ref != null:
		GameState.fog_ref.reveal_around(hatch.x, hatch.y,
			GameState.get_vision_terrain_radius(), GameState.get_vision_resource_radius())


func _freeze_player(value: bool) -> void:
	if player == null:
		return
	player.frozen = value
	if value:
		player.vx = 0.0
		player.vy = 0.0
		player.digging = null
		player.release_control()


## Хук сюжетной сцены Роберта (data/story.json: {"do":"hook","target":"house",
## "method":"build_hatch"}). Имя менять нельзя — на него ссылается сценарий.
func build_hatch() -> void:
	robert_finished_garden()


## Роберт закончил работу (ГДД п.9): огород приведён в порядок и закрыт,
## из подвала построен люк. Одна точка входа для сюжетной системы.
func robert_finished_garden() -> void:
	GameState.house_hatch_built = true
	GameState.house_garden_closed = true
	_sync_world_props()
	_toast("Роберт закончил: огород закрыт, из подвала есть люк в шахту.", 4.0)


# ---------------------------------------------------------------------------
# Контекстная кнопка HUD
# ---------------------------------------------------------------------------

func _update_hud_button() -> void:
	if _button == null:
		return
	if GameState.house_is_indoors or not GameState.is_alive:
		_button_action = ""
		_button.visible = false
		return
	if near_door():
		_button_action = "enter_door"
		_button.text = "Дом"
	elif near_hatch():
		_button_action = "enter_hatch"
		_button.text = "Люк"
	else:
		var food := HouseFood.best_food_for_now()
		if food.is_empty():
			_button_action = ""
			_button.visible = false
			return
		_button_action = "eat:" + food
		# Коротко: в ряду нижней полосы каждая буква — место, которого там
		# уже не хватает (см. комментарий к кнопке в hud.gd).
		_button.text = "Еда"
	_button.visible = true


func on_hud_button() -> void:
	if _button_action.is_empty():
		return
	var parts := _button_action.split(":", true, 1)
	match parts[0]:
		"enter_door":
			enter_house("hall")
		"enter_hatch":
			enter_house("basement")
		"eat":
			_eat(parts[1])


# ---------------------------------------------------------------------------
# Действия интерьера
# ---------------------------------------------------------------------------

func _on_view_action(action: String, arg: String) -> void:
	match action:
		"goto":
			GameState.house_room = arg
			_view.go_to_room(arg)
		"sleep":
			_sleep()
		"order":
			_order(arg)
		"take_delivery":
			_take_delivery()
		"eat":
			_eat(arg)
		"exit_door":
			exit_to_door()
		"exit_hatch":
			if not exit_through_hatch():
				_toast("Люка ещё нет — его построит Роберт.")
		"storage":
			# Тап пришёл из карточки мастерской, то есть герой уже подошёл к
			# складу: фиксируем комнату, иначе панель откроется в режиме
			# «только смотреть», хотя игрок стоит в двух шагах от полки.
			GameState.house_room = HouseStorage.ROOM
			_view.go_to_room(HouseStorage.ROOM)
			open_storage()
		"open_panel":
			if not _view.open_external_panel(arg):
				_toast("Комната пока пустая.")
		"forced_confirm":
			_finish_forced_sleep()


func _sleep() -> void:
	var before := GameState.stamina
	var result := HouseSleep.sleep_now()
	if not bool(result["ok"]):
		_toast(String(result["reason"]), 3.4)
		return
	_view.go_to_room("bedroom")
	GameState.house_room = "bedroom"
	_toast("Проспал %d игровых часов. Бодрость +%d%%." % [
		int(round(float(result["hours"]))), int(round(GameState.stamina - before))], 3.0)


func _order(food_id: String) -> void:
	var check := HouseFood.can_order(food_id)
	if not bool(check["ok"]):
		_toast(String(check["reason"]), 3.0)
		return
	if not HouseFood.pay_for_order(food_id):
		return
	var seconds := HouseConfig.delivery_seconds()
	# Доставка идёт РЕАЛЬНЫЕ 5 секунд (ГДД п.7), а не игровые: игрок ждёт её
	# сидя дома, и пересчёт в игровые часы превратил бы ожидание в полминуты.
	var timer := get_tree().create_timer(seconds)
	timer.timeout.connect(func(): _on_delivered(food_id))
	_toast("Заказ принят. Курьер будет у двери через %d секунд." % int(seconds), 3.0)


func _on_delivered(food_id: String) -> void:
	HouseFood.deliver(food_id)
	_toast("%s у входной двери." % HouseConfig.food_name(food_id), 3.0)


func _take_delivery() -> void:
	var taken := HouseFood.take_from_door()
	if taken <= 0:
		_toast("Забрать нечего — либо у двери пусто, либо рюкзак переполнен.", 3.2)
		return
	_toast("Забрал порций: %d." % taken)


func _eat(food_id: String) -> void:
	var result := HouseFood.eat(food_id)
	if not bool(result["ok"]):
		_toast(String(result["reason"]))
		return
	var parts: Array = []
	if float(result["hunger"]) > 0.0:
		parts.append("сытость +%d%%" % int(round(float(result["hunger"]))))
	if float(result["stamina"]) > 0.0:
		parts.append("бодрость +%d%%" % int(round(float(result["stamina"]))))
	if parts.is_empty():
		parts.append("и так полный")
	_toast("%s: %s." % [HouseConfig.food_name(food_id), ", ".join(parts)], 3.0)


# ---------------------------------------------------------------------------
# Обучение сну и еде (ГДД п.9), две стадии
# ---------------------------------------------------------------------------

## Двухстадийное обучение сну и еде (ГДД п.9). Если в сцене есть сюжетная
## система, обучение ведёт она — у неё те же две стадии сняты катсценами
## (sleep_lesson_1 и sleep_lesson_2 в data/story.json), и два учителя разом
## показали бы игроку два экрана про одно и то же. Дом в этом случае держит
## наготове сами действия: open_bedroom(), give_energy_bar(), build_hatch().
func _tick_tutorial() -> void:
	if not GameState.is_alive or player == null or _story != null:
		return
	if GameState.house_tutorial_stage == 0:
		# Первое истощение: телепорт домой в спальню и принудительный тап по
		# кровати. Ловим именно бодрость — она и есть та полоска, которой
		# учат пользоваться кроватью.
		if GameState.stamina <= 0.0:
			_start_forced_sleep()
	elif GameState.house_tutorial_stage == 1:
		# Второе истощение — в шахте (ГДД п.9): домой уже не ведут, вместо
		# этого в портфель падает батончик и его заставляют съесть.
		if not GameState.house_is_indoors and player.cell_y() >= 1 \
				and (GameState.stamina <= 0.0 or GameState.hunger <= 0.0) \
				and _prompt_action.is_empty():
			_start_forced_bar()


func _start_forced_sleep() -> void:
	if GameState.house_is_indoors and _view != null and _view.forced_mode() == "sleep":
		return
	enter_house("bedroom")
	_view.set_forced("sleep",
		"Ты вымотался. Пустая полоска бодрости жжёт HP, пока не выспишься.\n\n"
		+ "Спать можно только дома, в кровати: 8 игровых часов проходят за один реальный, "
		+ "а кровать отматывает их сразу — 12.5% бодрости за каждый игровой час.",
		"Лечь спать")


func _finish_forced_sleep() -> void:
	HouseSleep.sleep_now(true)
	GameState.house_tutorial_stage = 1
	_view.set_forced("")
	_toast("Выспался. Дальше кровать работает так же, но за сон тратится сытость.", 4.2)


func _start_forced_bar() -> void:
	_prompt_action = "eat_bar"
	give_energy_bar()
	_freeze_player(true)
	_prompt.show_prompt(
		"Полоска кончилась прямо в шахте. Домой отсюда не добежать.\n\n"
		+ "В портфеле нашёлся энергетический батончик: 100% бодрости и 50% сытости. "
		+ "Такие продаются в магазине — отдел допингов теперь открыт.",
		"Съесть батончик")


func _on_prompt_confirmed() -> void:
	if _prompt_action == "eat_bar":
		HouseFood.eat(TUTORIAL_FOOD)
		GameState.house_tutorial_stage = 2
		GameState.house_dopings_shop_unlocked = true
	_prompt_action = ""
	_prompt.hide_prompt()
	if not GameState.house_is_indoors:
		_freeze_player(false)


## Открыть панель склада. Снаружи она работает как витрина «что у меня дома»
## (ГДД п.14: смотреть можно откуда угодно), у самого склада — как склад.
func open_storage() -> void:
	if _storage_view == null:
		return
	# Пока панель открыта, герой стоит: она может открыться прямо в шахте, а
	# палец, нажимающий «Взять», под панелью попадает в джойстик и уводит
	# героя копать вслепую.
	_freeze_player(true)
	_storage_view.open()


func _on_storage_closed() -> void:
	if not GameState.house_is_indoors:
		_freeze_player(false)


## Показать интерьер в нужной комнате — для сюжетных сцен («телепорт домой в
## спальню», ГДД п.9) и для любой системы, которой нужен дом открытым.
func open_bedroom() -> void:
	enter_house("bedroom")


## Положить герою батончик в портфель (второе истощение, ГДД п.9). Вес не
## проверяется: подарок обучения не должен зависеть от того, полон ли рюкзак.
func give_energy_bar() -> void:
	if GameState.add_item(TUTORIAL_FOOD, 1) <= 0:
		GameState.inventory[TUTORIAL_FOOD] = GameState.get_item_count(TUTORIAL_FOOD) + 1
		GameState.inventory_changed.emit()


func _on_daily_reset() -> void:
	# Бесплатные доставки обнуляются вместе с рекламными лимитами — по
	# РЕАЛЬНЫМ суткам: мгновенный сон прокручивает игровые часы как угодно
	# быстро, и привязка к игровому дню кормила бы героя бесконечно.
	GameState.house_free_orders_used_today = 0


## Сообщение игроку. В доме HUD скрыт, поэтому текст идёт в шапку интерьера,
## снаружи — обычным тостом HUD. Одна точка, чтобы ни одно сообщение системы
## не пропало из-за того, что игрок оказался не на том экране.
func _toast(text: String, seconds: float = 2.6) -> void:
	if GameState.house_is_indoors and _view != null and _view.has_method("notify"):
		_view.notify(text, seconds)
		return
	if hud != null and hud.has_method("toast"):
		hud.toast(text, seconds)

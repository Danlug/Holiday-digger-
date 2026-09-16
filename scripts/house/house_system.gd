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
## потому что экстерьер дома — часть мира и обязан ездить вместе с камерой;
## интерьер и модалка живут на своих CanvasLayer и от камеры не зависят.
##
## Роберту (ГДД п.9) достаточно вызвать robert_finished_garden(): дом сам
## попросит мир пробить тоннель, откроет спуск из подвала и закроет огород.
## Люка (старое решение) больше нет — владелец его отменил: единственный
## вход в копальню теперь бетонный тоннель Роберта в клетке WorldGen.TUNNEL_X.
##
## «Дом» как контекстное меню карточек комнат ОТМЕНЕНО владельцем
## (2026-09-16): интерьер (scripts/house/house_view.gd) — настоящее
## пространство, герой в нём физически ходит, а кнопки действий (двери,
## кровать, верстак, сундук...) всплывают над ним, когда он подошёл. Этот
## файл по-прежнему решает, ЧТО происходит по нажатию (сон, магазин, склад,
## переходы), вид отвечает только за то, КАК это показано.

const TILE := 32
## Дом бабки после смерти деда (решение владельца, картинка от него же):
## двухэтажный, с навесом, машиной и забором — тот самый достаток, который
## она тщательно скрывает (ГДД п.2). Старый house_exterior.png остаётся для
## катсцен, где показывают время деда.
const HOUSE_SPRITE := "res://art/env/house_rich.png"
const HOUSE_META := "res://art/env/house_rich.json"
const VIEW_SCENE := "res://scenes/house.tscn"
const PROMPT_SCENE := "res://scenes/house_prompt.tscn"
const STORAGE_SCENE := "res://scenes/house_storage.tscn"

## Мастерская — чужая система (scripts/shop/), дом только просит её открыться
## (ГДД: верстак и «Заказать» открывают одну и ту же витрину). Путь, а не
## глобальное имя класса — по тем же причинам, что EXTERNAL_STATIC раньше:
## если соседнюю систему выкинут или она не соберётся, дом не имеет права
## упасть вместе с ней.
const SHOP_SCRIPT := "res://scripts/shop/shop_ui.gd"

## Высоту неба знает рендер мира — то же число, которым main.gd ограничивает
## камеру сверху. Плавающая кнопка «Зайти» использует его для тех же расчётов
## позиции на экране, что и main.gd:_camera(), не трогая сам main.gd.
const SKY_HEIGHT: int = preload("res://scripts/world/world_view.gd").SKY_HEIGHT

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
var _button: Button = null
var _button_action: String = ""
var _storage_button: Button = null
var _prompt_action: String = ""

## Кнопка «Зайти», плавающая НАД ГЕРОЕМ у окна веранды (решение владельца:
## «Дом» как контекстная кнопка внизу экрана отменяется). Живёт в собственном
## CanvasLayer, а не в строке HUD — HUD дому не принадлежит.
var _outdoor_layer: CanvasLayer = null
var _outdoor_button: Button = null

## Идёт ли сейчас ~10-секундная анимация сна у кровати (ГДД: «спит быстро,
## буквально 10 секунд, показывая анимацию»). Гейт от повторного нажатия,
## пока таймер не истёк.
var _sleeping: bool = false

## Устье тоннеля втягивает в дом при касании (решение владельца), но только
## после того, как от него отошли. Без этой защёлки спуск превращается в
## петлю: герой выходит в устье, стоит в нём, и устье тут же забирает его
## обратно. Раньше тем же латчем был защищён люк.
var _tunnel_armed: bool = false
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
	_build_outdoor_hotspot()

	GameState.daily_reset.connect(_on_daily_reset)

	_resolve_refs()


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
		# Сюжетная система зовёт дом через свои хуки (build_tunnel у Роберта,
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
# Мир: дом на поверхности. Тоннель Роберта дом не рисует — это тайлы, а их
# геометрию держит scripts/world/world_gen.gd (build_robert_tunnel).
# ---------------------------------------------------------------------------

func _build_world_props() -> void:
	var door := HouseConfig.door_cell()
	if ResourceLoader.exists(HOUSE_SPRITE):
		_exterior = Sprite2D.new()
		_exterior.name = "HouseExterior"
		_exterior.centered = false
		_exterior.texture = load(HOUSE_SPRITE)
		var size := _exterior.texture.get_size()
		# Дом прижимается ПРАВЫМ краем к границе огорода, а не центрируется по
		# двери: он шире своей половины карты не бывает, но и залезать на
		# грядки не должен — там копают. Дверь на рисунке одна и не в центре
		# (левее — навес с машиной), поэтому клетка двери в balance.json
		# подобрана под рисунок, а не наоборот.
		#
		# Низ ставится на ВЕРХ первой земляной клетки (y = 1), а не на y = 0:
		# земля начинается с первого слоя, и герой стоит ступнями именно там —
		# по y = 0 дом висел бы на клетку выше уровня земли.
		_exterior.position = Vector2(WorldGen.GARDEN_X_MIN * TILE - size.x, TILE - size.y)
		add_child(_exterior)


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


## Плавающая кнопка «Зайти» у окна веранды (решение владельца, 2026-09-16:
## «Дом» отменён как контекстная кнопка внизу экрана — вместо этого над
## героем загорается кнопка, когда он подошёл к окну). Свой CanvasLayer,
## а не строка HUD: HUD — чужой файл, дом только читает его для расчёта
## позиции на экране (_outdoor_camera), но не правит.
func _build_outdoor_hotspot() -> void:
	_outdoor_layer = CanvasLayer.new()
	_outdoor_layer.name = "OutdoorHotspot"
	_outdoor_layer.layer = 8
	add_child(_outdoor_layer)

	_outdoor_button = Button.new()
	_outdoor_button.name = "EnterHouseBtn"
	_outdoor_button.text = "Зайти"
	_outdoor_button.custom_minimum_size = Vector2(64, 22)
	_style_outdoor_button(_outdoor_button)
	_outdoor_button.visible = false
	_outdoor_button.pressed.connect(func(): enter_house("hall"))
	_outdoor_layer.add_child(_outdoor_button)


func _style_outdoor_button(b: Button) -> void:
	b.add_theme_font_size_override("font_size", 10)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.05, 0.04, 0.9)
		sb.border_color = Color8(0xE0, 0xA9, 0x3B) if state == "pressed" else Color8(0x3E, 0x31, 0x25)
		sb.set_border_width_all(1)
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color8(0x9D, 0x8B, 0x73))
	b.add_theme_color_override("font_hover_color", Color8(0xE0, 0xA9, 0x3B))
	b.add_theme_color_override("font_pressed_color", Color8(0xE0, 0xA9, 0x3B))


# ---------------------------------------------------------------------------
# Кадр
# ---------------------------------------------------------------------------

func _process(_dt: float) -> void:
	_resolve_refs()
	_tick_tutorial()
	_auto_enter_tunnel_if_touched()
	_update_hud_button()
	_update_outdoor_hotspot()
	if _view != null and _view.visible:
		_view.refresh()
	if _storage_view != null and _storage_view.visible:
		_storage_view.refresh()


## Камера мира, посчитанная теми же числами, что main.gd:_camera() — не
## вызываем main.gd напрямую (он не наш файл), а держим свою копию формулы:
## клетка вида и потолок неба публичны (hud.get_view_cells(), SKY_HEIGHT),
## разъехаться с оригиналом им попросту нечем.
func _outdoor_camera() -> Vector2:
	if hud == null or player == null:
		return Vector2.ZERO
	var view_cells: Vector2i = hud.get_view_cells()
	var vw := float(view_cells.x)
	var vh := float(view_cells.y)
	var cam_x: float = clampf(player.x - vw / 2.0, 0.0, maxf(0.0, float(WorldGen.WIDTH) - vw))
	var cam_y: float = maxf(player.y - vh / 2.0, -float(SKY_HEIGHT))
	return Vector2(cam_x, cam_y)


## Кнопка «Зайти» у окна веранды — над героем, не внизу экрана (решение
## владельца). Видимость решает near_door() (та же клетка и радиус, что
## раньше открывали дом); позицию на экране (без hud её взять не у кого)
## можно не знать — тогда кнопка просто не подсвечивается там, где нужно, но
## не падает.
func _update_outdoor_hotspot() -> void:
	if _outdoor_button == null:
		return
	if GameState.house_is_indoors or not GameState.is_alive or player == null or not near_door():
		_outdoor_button.visible = false
		return
	_outdoor_button.visible = true
	if hud == null:
		return
	var cam := _outdoor_camera()
	var head := Vector2(player.x - cam.x, player.y - cam.y - 1.0) * TILE
	_outdoor_button.position = head - Vector2(
		_outdoor_button.custom_minimum_size.x / 2.0, _outdoor_button.custom_minimum_size.y + 4.0)


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


## Устье тоннеля Роберта — верхняя клетка бетонного колодца (ГДД п.9,
## решение владельца: единственный вход в копальню). Геометрию держит мир,
## дом только спрашивает; HouseConfig отвечает запасным значением, пока мира
## ещё нет (загрузка сейва до генерации, тесты дома в одиночку).
func tunnel_mouth() -> Vector2i:
	if world == null:
		world = GameState.world_ref
	if world != null:
		return world.tunnel_mouth()
	return HouseConfig.tunnel_mouth_cell()


## Стоит ли герой в устье тоннеля (в радиусе взаимодействия).
func near_tunnel_mouth() -> bool:
	if player == null or not GameState.house_hatch_built:
		return false
	var mouth := tunnel_mouth()
	return absf(player.x - (mouth.x + 0.5)) <= HouseConfig.interact_radius() \
		and absf(player.y - (mouth.y + 0.5)) <= HouseConfig.interact_radius()


## Старое имя времён люка. Оставлено обёрткой: на него мог ссылаться чужой
## код, написанный до отмены люка.
func near_hatch() -> bool:
	return near_tunnel_mouth()


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


## Спуск из подвала в шахту (ГДД п.9). Возвращает false, пока Роберт не
## пробил тоннель.
func exit_through_tunnel() -> bool:
	if not GameState.house_hatch_built:
		return false
	if world == null:
		world = GameState.world_ref
	if world == null:
		return false
	# Тоннель пробивается заново на каждом спуске: землетрясение (ГДД п.8)
	# стирает диффы, и колодец зарастает обратно. Вызов идемпотентный —
	# мир сам разбирается, что уже пробито.
	world.build_robert_tunnel()
	var mouth := world.tunnel_mouth()
	# Герой встаёт РОВНО в устье (решение владельца): вниз ведёт только
	# колодец, шага в сторону из него нет — стенки 16 и 18 железобетонные.
	# Латч гасится ДО выхода, иначе устье тут же утащит героя обратно в дом
	# (см. _auto_enter_tunnel_if_touched).
	_tunnel_armed = false
	_reveal_around(mouth)
	_leave_house(Vector2(mouth.x + 0.5, mouth.y + 0.5))
	return true


## Старое имя спуска (люк). Оставлено обёрткой ради старых сейвов и старых
## записей очереди сюжета: люка больше нет, но падать на них нельзя.
func exit_through_hatch() -> bool:
	return exit_through_tunnel()


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


## Туман вокруг клетки, куда герой только что попал не своим ходом: без
## этого он вываливается в устье тоннеля посреди чёрного экрана.
func _reveal_around(cell: Vector2i) -> void:
	if GameState.fog_ref == null:
		return
	GameState.fog_ref.reveal_around_cell(cell.x, cell.y,
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
## "method":"build_tunnel"}). Имя менять нельзя — на него ссылается сценарий.
func build_tunnel() -> void:
	robert_finished_garden()


## Старое имя того же хука (люк отменён владельцем). Тонкая обёртка, а не
## удалённый метод: в сейве лежит очередь сюжетных сцен, и у игрока со старым
## сохранением в ней может остаться method="build_hatch" — без обёртки сцена
## Роберта молча не построила бы ничего, и игрок остался бы без входа в шахту.
func build_hatch() -> void:
	build_tunnel()


## Роберт закончил работу (ГДД п.9, решение владельца): огород засыпан и
## закрыт навсегда, вместо лестницы вниз уходит бетонный тоннель. Одна точка
## входа для сюжетной системы.
func robert_finished_garden() -> void:
	# Поле в GameState осталось со времён люка (house_hatch_built), смысл у
	# него теперь один: Роберт построил тоннель. Переименование поля — за
	# scripts/core, дому важно только значение.
	GameState.house_hatch_built = true
	GameState.house_garden_closed = true
	if world == null:
		world = GameState.world_ref
	if world != null:
		# Вся геометрия — знание мира: он пробивает колодец в клетке
		# WorldGen.TUNNEL_X, ставит железобетонные стенки 16 и 18, засыпает
		# остальной огород (копать там больше нельзя) и расчищает площадку
		# под фундаментом. Выкопанное сценарное золото не отрастает — оно
		# зафиксировано и уже унесено игроком.
		world.build_robert_tunnel()
	_toast("Роберт закончил: огород засыпан и закрыт, вниз ведёт бетонный тоннель.", 4.0)


# ---------------------------------------------------------------------------
# Контекстная кнопка HUD
# ---------------------------------------------------------------------------

## Устье тоннеля втягивает героя в дом само, как только он в него налетел
## (решение владельца, раньше так же работал люк): подтверждение у дыры, из
## которой только что поднялся, — лишний тап на каждом возвращении.
##
## Дверь так НЕ работает намеренно: мимо неё ходят по огороду постоянно, и
## дом хватал бы игрока при каждом проходе.
func _auto_enter_tunnel_if_touched() -> void:
	if GameState.house_is_indoors or not GameState.is_alive:
		return
	if not GameState.house_hatch_built or player == null or player.frozen:
		return
	if not near_tunnel_mouth():
		_tunnel_armed = true
		return
	if not _tunnel_armed:
		return
	_tunnel_armed = false
	# «Подвал» слит с мастерской (решение владельца, 2026-09-16): устье
	# тоннеля поднимает героя туда же, где стена с удочками, верстак и склад.
	enter_house("workshop")


## «Дом» как контекстная кнопка внизу экрана ОТМЕНЕНА владельцем (2026-09-16):
## вход теперь через плавающую кнопку «Зайти» над героем у окна веранды (см.
## _update_outdoor_hotspot). Метод и поле _button оставлены пустой обёрткой —
## на группу "house_button" всё ещё может ссылаться HUD (чужой файл) и старый
## тест; кнопка просто никогда не становится видимой.
func _update_hud_button() -> void:
	if _button == null:
		return
	_button_action = ""
	_button.visible = false


func on_hud_button() -> void:
	pass


# ---------------------------------------------------------------------------
# Действия интерьера
# ---------------------------------------------------------------------------

func _on_view_action(action: String, arg: String) -> void:
	match action:
		"goto":
			# Сам переезд герой уже сделал (это вид — go_to_room вызван внутри
			# house_view.gd._fire до этого сигнала); здесь только бухгалтерия,
			# которую обязан вести дом: где герой, знает сейв.
			GameState.house_room = arg
		"sleep":
			_start_sleep_sequence()
		"take_delivery":
			_take_delivery()
		"exit_door":
			exit_to_door()
		# exit_hatch — то же действие под старым именем: интерьер мог быть
		# собран из сохранённой сцены, снятой до отмены люка.
		"exit_tunnel", "exit_hatch":
			if not exit_through_tunnel():
				_toast("Тоннеля ещё нет — его пробьёт Роберт.")
		"storage":
			# Хотспот сундука виден только в мастерской — герой уже там, но
			# фиксируем комнату на всякий случай (тот же вызов, что раньше).
			GameState.house_room = HouseStorage.ROOM
			open_storage()
		"open_shop":
			_open_shop("open_shop")
		"open_equipment":
			_open_shop("open_workshop")
		"take_pickaxe":
			take_starting_pickaxe()
		"forced_confirm":
			_finish_forced_sleep()


## Ровно эффект сна (не меняется — см. HouseSleep.sleep_now): числа считает
## HouseSleep, здесь только сообщение. Вызывается ОДИН раз — либо сразу
## (обучающий форс-сон, _finish_forced_sleep), либо по концу анимации у
## кровати (_finish_sleep_sequence).
func _sleep() -> void:
	var before := GameState.stamina
	var result := HouseSleep.sleep_now()
	if not bool(result["ok"]):
		_toast(String(result["reason"]), 3.4)
		return
	_toast("Проспал %d игровых часов. Бодрость +%d%%." % [
		int(round(float(result["hours"]))), int(round(GameState.stamina - before))], 3.0)


## Кнопка «Спать» у кровати (ГДД, решение владельца: «спит быстро, буквально
## 10 секунд, показывая анимацию»). Правила самого сна не меняются — меняется
## только то, что эффект применяется не мгновенно по тапу, а по концу
## короткого ролика: комната на это время «на паузе» (house_view.set_locked),
## чтобы нельзя было утащить героя за дверь посреди сна.
func _start_sleep_sequence() -> void:
	if _sleeping or _view == null:
		return
	var plan := HouseSleep.plan(GameState.stamina, GameState.hunger)
	if not bool(plan["ok"]):
		_toast(String(plan["reason"]), 3.4)
		return
	_sleeping = true
	_view.set_locked(true)
	_view.play_sleep_animation(HouseConfig.sleep_animation_seconds())
	var timer := get_tree().create_timer(HouseConfig.sleep_animation_seconds())
	timer.timeout.connect(_finish_sleep_sequence)


func _finish_sleep_sequence() -> void:
	_sleeping = false
	if _view != null:
		_view.stop_sleep_animation()
		_view.set_locked(false)
	_sleep()


## Мастерская (верстак и «Заказать» в салоне открывают одну и ту же витрину —
## решение владельца). Сам магазин переписывает другой агент: дому важен
## только вызов ShopUI.open_workshop().
## Две точки входа в одну шторку: «Заказать» у входной двери — магазин
## (open_shop), «Верстак» в мастерской — экипировка (open_workshop): что
## куплено, то и надеть. Раньше оба вели в один экран, и верстак продавал.
func _open_shop(entry: String = "open_shop") -> void:
	if not ResourceLoader.exists(SHOP_SCRIPT):
		_toast("Мастерская пока недоступна.")
		return
	load(SHOP_SCRIPT).call(entry)


## Точка выдачи ржавой кирки (ГДД, решение владельца: «кирку он берёт на
## анимации отсюда, среди удочек и швабр» — стена мастерской). Кирка попадает
## в руки через ту же сюжетную сцену "workshop", которую раньше запускал
## первый удар лопатой о фундамент (см. story_director.gd:_on_tool_auto_switched
## и данные её эффектов в data/story.json) — enqueue идемпотентен, повторный
## вызов ничего не ломает. Без сюжетной системы (тесты, урезанная сборка) —
## запасной прямой выдачей, чтобы дом не запирал игрока без кирки.
##
## Гейт — StoryState.is_seen("workshop"), а НЕ GameState.owns_tool():
## ржавая кирка бесплатна (сюжетная ступень, is_tool_free в game_state.gd),
## и owns_tool() отвечает true на неё всегда, даже до того, как её вообще
## взяли — по нему нельзя понять, брал ли игрок кирку здесь.
func take_starting_pickaxe() -> void:
	if StoryState.is_seen("workshop"):
		return
	if _story != null:
		StoryState.enqueue("workshop")
		return
	GameState.grant_tool("rusty_pickaxe")
	GameState.set_current_tool("rusty_pickaxe")
	StoryState.mark_seen("workshop")
	_toast("Ржавая кирка деда — теперь твоя.", 3.0)


## Заказ и доставка еды (HouseFood.pay_for_order/deliver) больше не ведутся
## отсюда: «Заказать» в салоне и «Верстак» в мастерской открывают магазин
## (_open_shop), и заказ теперь его забота — см. отчёт агента дома. Здесь
## остаётся только «Забрать»: у входной двери он всплывает, пока там лежит
## уже оплаченная доставка (data/rooms.json: hall.front_door, condition
## food_at_door), и это чисто «дом» дело — до чего донесли, то и забираем.
func _take_delivery() -> void:
	var taken := HouseFood.take_from_door()
	if taken <= 0:
		_toast("Забрать нечего — либо у двери пусто, либо рюкзак переполнен.", 3.2)
		return
	_toast("Забрал порций: %d." % taken)


# ---------------------------------------------------------------------------
# Обучение сну и еде (ГДД п.9), две стадии
# ---------------------------------------------------------------------------

## Двухстадийное обучение сну и еде (ГДД п.9). Если в сцене есть сюжетная
## система, обучение ведёт она — у неё те же две стадии сняты катсценами
## (sleep_lesson_1 и sleep_lesson_2 в data/story.json), и два учителя разом
## показали бы игроку два экрана про одно и то же. Дом в этом случае держит
## наготове сами действия: open_bedroom(), give_energy_bar(), build_tunnel().
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

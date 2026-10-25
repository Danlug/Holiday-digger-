class_name FeelDirector
extends Node
## Режиссёр «ощущения игры» (ветка aaa-feel). Только слушает игру и включает
## отклик — правил не меняет:
##  * добыча: значок летит в рюкзак, «момент» крупной находки (вспышка, наезд
##    камеры, короткая пауза героя, вибро);
##  * инструмент: бур и бурмобиль дробят экран лёгкой дрожью, пока идёт копка;
##  * камера: наезд на тяжёлом ударе и на жёстком приземлении;
##  * глубина: вехи каждые 10 / 100 / 1000 клеток (опыт за них давали молча);
##  * смерть: карточка «что потеряно, что уцелело» — с поездкой скорой сразу (отсчёт до
##    приезда), без неё — после респавна.
## Пары к JuiceDirector («Звук и сок»): тот отвечает за звук и частицы, этот — за
## вес событий. Подписки на сигналы, чужой код не правится.

const EPIC_CATEGORIES := ["gem", "exotic", "warzone", "radioactive"]
const COL_GOLD := Color("FFE066")
const COL_RARE := Color("6FE0D8")

var player: Node = null
var card: DeathCard = null

var _pick_item: String = ""
var _pick_frame: int = -1
var _prev_depth: int = 0
var _was_digging: bool = false
var _next_micro: float = 0.0
var _prev_on_ground: bool = false
var _prev_vy: float = 0.0
var _inv_prev: Dictionary = {}
var _inv_cur: Dictionary = {}
var _pending: Dictionary = {}
var _last_fall_msec: int = -100000
var _fee: int = 0   # «скорая забрала» при этой смерти (событие ambulance, раунд 4)
var _connected: bool = false

## Для тестов: что режиссёр сделал (счётчики), не завязываясь на сервисы Fx/Sfx.
var stats: Dictionary = {"fly": 0, "epic": 0, "milestones": 0, "cards": 0, "punches": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var host := get_parent()
	if player == null and host != null:
		if "player" in host and host.player != null:
			player = host.player
		else:
			player = host.find_child("Player", true, false)
	card = DeathCard.new()
	card.name = "DeathCard"
	add_child(card)
	_prev_depth = GameState.max_depth_reached
	_inv_cur = GameState.inventory.duplicate()
	_inv_prev = _inv_cur.duplicate()
	_connect()


func _connect() -> void:
	if _connected:
		return
	_connected = true
	GameState.game_event.connect(_on_event)
	GameState.max_depth_changed.connect(_on_max_depth)
	GameState.inventory_changed.connect(_on_inventory)
	GameState.died.connect(_on_died)
	GameState.respawned.connect(_on_respawned)
	if player != null and player.has_signal("fell"):
		player.fell.connect(_on_fell)


func _exit_tree() -> void:
	Feel.card_pending = false
	if not _connected:
		return
	_connected = false
	for pair in [[GameState.game_event, _on_event], [GameState.max_depth_changed, _on_max_depth],
			[GameState.inventory_changed, _on_inventory], [GameState.died, _on_died],
			[GameState.respawned, _on_respawned]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	if player != null and is_instance_valid(player) and player.has_signal("fell") \
			and player.fell.is_connected(_on_fell):
		player.fell.disconnect(_on_fell)


# ---------------------------------------------------------------------------
# Покадровое: дрожь бура и жёсткое приземление
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var d = player.digging
	if d != null:
		var prof := Feel.tool_profile(GameState.current_tool)
		var amp := float(prof["micro_shake"])
		if amp > 0.0:
			if not _was_digging:
				_next_micro = 0.0
			_next_micro -= delta
			if _next_micro <= 0.0:
				_next_micro = float(prof["hit_period_s"])
				Fx.shake(amp, 0.1)
	_was_digging = d != null

	# жёсткое приземление: короткий наезд камеры (звук и пыль — у JuiceDirector)
	var on_ground: bool = player.on_ground
	if on_ground and not _prev_on_ground and _prev_vy > 14.0:
		_punch(clampf((_prev_vy - 14.0) / 600.0 + 0.01, 0.01, 0.03))
	_prev_on_ground = on_ground
	_prev_vy = float(player.vy)


func _punch(amount: float) -> void:
	stats["punches"] += 1
	Feel.punch(amount)


# ---------------------------------------------------------------------------
# События игры
# ---------------------------------------------------------------------------

func _on_event(id: StringName, data: Dictionary) -> void:
	match id:
		&"picked":
			_pick_item = String(data.get("item", ""))
			_pick_frame = Engine.get_process_frames()
		&"dug":
			var tile := int(data.get("tile", 0))
			if bool(data.get("loot", false)):
				var item := String(data.get("mineral", ""))
				# подбор и копка приходят в одном кадре: если рюкзак был полон, «picked» не было
				if item != "" and item == _pick_item and _pick_frame == Engine.get_process_frames():
					_on_loot(item, data.get("pos", Vector2.ZERO))
			elif Feel.WEIGHTY_TILES.has(tile):
				_punch(0.008 if tile == TileTypes.Type.STONE else 0.014)
		&"boss_defeated":
			_punch(0.05)
		&"collapse":
			_punch(0.02)
		&"ambulance":
			_fee = int(data.get("coins", 0))
		&"ambulance_ride":
			_on_ride(data)


## Находка, добытая киркой: значок летит в рюкзак; дорогая — «момент».
func _on_loot(item: String, cell_pos: Vector2) -> void:
	var price := Balance.get_mineral_price(item)
	var epic := is_epic_item(item)
	var fly_min := int(Feel.num("loot.fly_min_price", 20.0))
	if epic or price >= fly_min:
		stats["fly"] += 1
		var fxn := get_tree().get_first_node_in_group(Fx.GROUP)
		if fxn != null and fxn.has_method("world_to_screen") and not Settings.reduce_motion:
			Fx.fly_to(UiIcons.item(item), fxn.world_to_screen(cell_pos), HudAnchors.get_anchor("backpack"), 1)
	if epic:
		stats["epic"] += 1
		Fx.flash(Color(1.0, 0.93, 0.62, 0.26), 0.35)
		Fx.burst("spark", cell_pos, 2.2)
		_punch(0.03)
		Sfx.play("reward", 1.0, -4.0)
		Haptics.buzz(45)
		if player != null and player.has_method("hitstop") and not Settings.reduce_motion:
			player.hitstop(Feel.num("loot.epic_hitstop_s", 0.07))


## Дорогая добыча: самоцветы, экзотика, радиоактивное или дороже порога цены.
static func is_epic_item(item: String) -> bool:
	var m := Balance.get_mineral(item)
	if m.is_empty():
		return false
	if EPIC_CATEGORIES.has(String(m.get("category", ""))):
		return true
	return Feel.is_epic_price(Balance.get_mineral_price(item))


func _on_fell(_damage: float, _speed: float) -> void:
	_last_fall_msec = Time.get_ticks_msec()


# ---------------------------------------------------------------------------
# Вехи глубины
# ---------------------------------------------------------------------------

## Опыт, начисленный Player за отметки (prev, depth]: 50 × (глубина / 10) на каждой
## десятой клетке — та же формула, что в Player._award_depth_milestones.
static func milestone_xp(prev: int, depth: int) -> int:
	var xp := 0
	var d := (prev / 10 + 1) * 10
	while d <= depth:
		xp += 50 * (d / 10)
		d += 10
	return xp


## 1 — каждые 10 клеток, 2 — каждые 100, 3 — каждые 1000.
static func milestone_tier(top: int) -> int:
	if top % 1000 == 0:
		return 3
	if top % 100 == 0:
		return 2
	return 1


## Опыт за каждую 10-ю клетку нового рекорда начисляется молча (ГДД §11). Видимая
## веха даёт ритм в «пустых» участках спуска: тик каждые 10, всплеск каждые 100,
## удар каждые 1000. Падение через несколько отметок за раз сливается в одну.
func _on_max_depth(depth: int) -> void:
	var prev := _prev_depth
	_prev_depth = depth
	if depth <= prev or depth < 10 or GameState.house_is_indoors:
		return
	var top := (depth / 10) * 10
	if top <= (prev / 10) * 10:
		return
	var xp := milestone_xp(prev, depth)
	stats["milestones"] += 1
	var head := Vector2.ZERO
	if player != null:
		head = Vector2(float(player.x), float(player.y) - 0.9) * 32.0
	var tier := milestone_tier(top)
	# выше, чем «+N» добычи, чтобы не налезать на них
	Fx.float_icon(head + Vector2(0, -18), UiIcons.tex("star"), "+%s" % MetaUiKit.compact(xp), COL_GOLD if tier > 1 else COL_RARE)
	match tier:
		1:
			Sfx.play("pickup", 1.45, -11.0)
		2:
			Sfx.play("reward", 1.0, -5.0)
			Fx.burst("spark", head, 1.4)
			Fx.flash(Color(1.0, 0.9, 0.45, 0.14), 0.3)
			Haptics.tap()
			_punch(0.02)
		3:
			Sfx.play("levelup")
			Fx.burst("levelup", head, 1.6)
			Fx.flash(Color(1.0, 0.9, 0.45, 0.3), 0.5)
			Haptics.buzz(70)
			_punch(0.04)


# ---------------------------------------------------------------------------
# Смерть
# ---------------------------------------------------------------------------

func _on_inventory() -> void:
	_inv_prev = _inv_cur
	_inv_cur = GameState.inventory.duplicate()


## К моменту «died» рюкзак уже очищен (GameState.die): потерянное берём из
## снимка перед последним изменением.
func _on_died() -> void:
	var cause := "fall" if Time.get_ticks_msec() - _last_fall_msec < 1500 else ""
	if GameState.hunger <= 0.0:
		cause = "hunger"
	elif cause == "" and _near_lava():
		cause = "lava"
	_pending = DeathCard.build_report(_inv_prev if _inv_cur.is_empty() else _inv_cur, GameState.player_depth, cause, _fee)
	_fee = 0


func _near_lava() -> bool:
	if player == null or player.world == null:
		return false
	var cx: int = player.cell_x()
	var cy: int = player.cell_y()
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if player.world.get_tile(cx + dx, cy + dy) == TileTypes.Type.LAVA:
				return true
	return false


## «Скорая везёт» (раунд 5, death-cost): карточка открывается сразу и ведёт
## отсчёт поездки, респавн — по приезде. Поездка, продолженная после перезапуска
## игры, приходит без отчёта: потерь уже не перечесть, показываем саму поездку.
func _on_ride(data: Dictionary) -> void:
	var rep := _pending
	_pending = {}
	if rep.is_empty():
		rep = DeathCard.build_report({}, int(data.get("depth", 0)), "", 0)
	rep["ride_s"] = float(data.get("seconds", 0.0))
	stats["cards"] += 1
	Feel.card_pending = true
	var t := get_tree().create_timer(0.7 if not bool(data.get("resumed", false)) else 0.05)
	t.timeout.connect(func() -> void:
		Feel.card_pending = false
		if is_instance_valid(card) and card.is_inside_tree():
			card.open(rep))


func _on_respawned() -> void:
	if card != null and card.is_open():
		card.ride_arrived()   # приехали: карточка уже открыта поездкой
	if _pending.is_empty():
		return
	var rep := _pending
	_pending = {}
	if not DeathCard.worth_showing(rep):
		return
	stats["cards"] += 1
	Feel.card_pending = true
	# герой уже дома; пауза в 0.7 с даёт отыграть красной вспышке смерти
	var t := get_tree().create_timer(0.7)
	t.timeout.connect(func() -> void:
		Feel.card_pending = false
		if is_instance_valid(card) and card.is_inside_tree():
			card.open(rep))

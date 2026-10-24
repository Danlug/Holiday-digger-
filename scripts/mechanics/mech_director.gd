class_name MechDirector
extends Node
## Режиссёр механик раунда 3. Слушает шину (`dug`), считает серию, мастерство и
## тайники, выдаёт награду через GameState (вес рюкзака проверяет add_item) и
## включает отклик через фасады Sfx / Fx / Haptics. Правил копки не меняет:
## копку, опыт и добычу клетки делает Player, здесь — только надбавки сверху.
##
## Узлы: ChestLayer (сундуки в мире, в ViewRoot сразу над тайлами), StreakMeter
## (шкала азарта под полосками HUD), JournalScreen (журнал, пункт меню «•••»).

signal chest_opened(cell: Vector2i, tier: String, items: Dictionary)
signal fever_started
signal fever_ended
signal star_gained(item: String, star: int)

const COL_GOLD := Color("FFE066")

var player: Node = null
var world: WorldGen = null
var fog: FogOfWar = null
var view_root: Node = null

var streak := StreakLogic.new()
var chest_layer: ChestLayer = null
var meter: StreakMeter = null
var journal: JournalScreen = null

## Броски двойной добычи (мастерство) — свой генератор от сида мира: тест крутит
## копку и получает один и тот же результат.
var rng := RandomNumberGenerator.new()

## Для тестов и журнала: что сделано за сессию.
var stats := {"chests": 0, "fevers": 0, "fever_items": 0, "mastery_items": 0, "stars": 0}

var _band_cache: Dictionary = {}
var _loot_tick: float = 0.0
var _full_warned: Dictionary = {}
var _connected := false


func _ready() -> void:
	var host := get_parent()
	if host != null:
		if player == null and "player" in host:
			player = host.player
		if world == null and "world" in host:
			world = host.world
		if fog == null and "fog" in host:
			fog = host.fog
		if view_root == null and "view_root" in host:
			view_root = host.view_root
	rng.seed = ChestLogic.mix(GameState.world_seed, 0x51, 0x7A)
	_build()
	_register_menu()
	_connect()


func _build() -> void:
	if view_root != null and world != null:
		chest_layer = ChestLayer.new()
		chest_layer.name = "ChestLayer"
		chest_layer.director = self
		view_root.add_child(chest_layer)
		# над тайлами мира, под героем, светом и тенями: сундук лежит в породе
		var wv := view_root.get_node_or_null("WorldView")
		if wv != null:
			view_root.move_child(chest_layer, wv.get_index() + 1)
	var meter_layer := CanvasLayer.new()
	meter_layer.name = "StreakLayer"
	meter_layer.layer = 2   # рядом с HUD и значками техники, ниже шторок и экранов
	add_child(meter_layer)
	meter = StreakMeter.new()
	meter.name = "StreakMeter"
	meter.streak = streak
	meter_layer.add_child(meter)
	journal = JournalScreen.new()
	journal.name = "JournalScreen"
	journal.director = self
	add_child(journal)


func _register_menu() -> void:
	MenuRegistry.add("journal", {
		"icon": Mechanics.tex("journal"),
		"title": "Журнал добытчика",
		"body": "Мастерство руд: звёзды за добычу дают опыт и шанс двойной добычи. Найденные тайники и лихорадки.",
		"order": 40,
		"visible": func() -> bool: return MechData.gate_open(),
		"badge": func() -> int: return MechState.unseen_count() if MechData.gate_open() else 0,
		"on_press": func() -> void: open_journal(),
	})


func open_journal() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var d: MechDirector = tree.root.find_child("MechDirector", true, false) if tree != null else null
	if d != null and d.journal != null:
		d.journal.open()


func _connect() -> void:
	if _connected:
		return
	_connected = true
	GameState.game_event.connect(_on_event)
	GameState.died.connect(_on_died)


func _exit_tree() -> void:
	if _connected:
		_connected = false
		if GameState.game_event.is_connected(_on_event):
			GameState.game_event.disconnect(_on_event)
		if GameState.died.is_connected(_on_died):
			GameState.died.disconnect(_on_died)


# ---------------------------------------------------------------------------
# Кадр: серия рвётся на паузе, добыча из открытого сундука подбирается рядом
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	step(delta)


## Шаг логики (тесты зовут его сами с фиксированным dt).
func step(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var digging: bool = player.get("digging") != null
	if streak.tick(dt, digging, _streak_allowed()):
		if meter != null:
			meter.on_break()
	_loot_tick -= dt
	if _loot_tick <= 0.0:
		_loot_tick = 0.25
		_pick_leftovers()


func _streak_allowed() -> bool:
	if not MechData.gate_open() or not GameState.is_alive or GameState.house_is_indoors:
		return false
	if bool(player.get("frozen")):
		return false
	return int(player.call("cell_y")) >= streak.min_depth


func _on_died() -> void:
	streak.reset()
	if meter != null:
		meter.on_break()


# ---------------------------------------------------------------------------
# Копка
# ---------------------------------------------------------------------------

func _on_event(id: StringName, data: Dictionary) -> void:
	if id == &"dug":
		on_dug(data)


func on_dug(data: Dictionary) -> void:
	var cell: Vector2i = data.get("cell", Vector2i(-1, -1))
	var mineral := String(data.get("mineral", ""))
	var loot := bool(data.get("loot", false))
	var pos: Vector2 = data.get("pos", Vector2(cell.x * 32.0 + 16.0, cell.y * 32.0 + 16.0))
	var open := MechData.gate_open()
	if loot and MasteryLogic.is_kind(mineral):
		_mastery(mineral, pos, open)
	if not open:
		return
	var r := streak.on_dug(cell.y)
	if bool(r["fever_cell"]) and loot and mineral != "":
		var extra := int(MechData.num("streak", "fever_extra", 1))
		var got := GameState.add_item(mineral, extra)
		if got > 0:
			stats["fever_items"] += got
			MechState.bump_stat("bonus_items", got)
			Fx.burst("spark", pos, 0.9, COL_GOLD)
	if bool(r["started"]):
		_on_fever_started()
	if bool(r["ended"]):
		_on_fever_ended()
	if meter != null:
		meter.on_dug(bool(r["fever_cell"]))
	var ch := chest_at(cell)
	if not ch.is_empty() and not MechState.chest_opened(cell):
		open_chest(cell, String(ch["tier"]))


# --- мастерство --------------------------------------------------------------

func _mastery(item: String, pos: Vector2, open: bool) -> void:
	var before := MechState.mastery_count(item)
	var n := MechState.add_mastery(item, 1)
	if not open:
		return   # до конца онбординга счётчик копится молча, награды и звуки — потом
	if before == 0:
		_fly_to_menu(UiIcons.item_small(item, 16), pos)
	var stars := MasteryLogic.stars_for(item, n)
	var granted := MechState.stars_granted(item)
	while granted < stars:
		granted += 1
		MechState.set_stars_granted(item, granted)
		var xp := MasteryLogic.star_xp(item, granted)
		GameState.add_xp(xp)
		stats["stars"] += 1
		Sfx.play("quest_done")
		Haptics.tap()
		Fx.float_icon(pos + Vector2(0, -18), Mechanics.tex("star_on"), "%d" % granted, COL_GOLD)
		_fly_to_menu(Mechanics.tex("star_on"), pos)
		GameState.emit_event(&"mastery_star", {"item": item, "star": granted, "xp": xp})
		star_gained.emit(item, granted)
	# двойная добыча мастера: копка уже положила одну штуку — бросок на вторую
	var chance := MasteryLogic.double_chance(MechState.stars_granted(item))
	if chance > 0.0 and rng.randf() < chance:
		if GameState.add_item(item, 1) > 0:
			stats["mastery_items"] += 1
			MechState.bump_stat("bonus_items", 1)
			Fx.burst("pickup_glint", pos, 0.8)


func _fly_to_menu(icon: Texture2D, world_pos: Vector2) -> void:
	if icon == null or Settings.reduce_motion:
		return
	var from := _to_screen(world_pos)
	Fx.fly_to(icon, from, HudAnchors.get_anchor("menu"), 1)


func _to_screen(world_pos: Vector2) -> Vector2:
	if view_root != null and view_root is Node2D:
		return (view_root as Node2D).get_global_transform_with_canvas() * world_pos
	return HudAnchors.FALLBACK


# --- лихорадка ---------------------------------------------------------------

func _on_fever_started() -> void:
	stats["fevers"] += 1
	MechState.bump_stat("fevers", 1)
	Sfx.play("reward")
	Haptics.buzz(70)
	Fx.flash(Color(1.0, 0.85, 0.3, 0.22), 0.25)
	if player != null:
		var head := Vector2(float(player.x) * 32.0, float(player.y) * 32.0 - 12.0)
		Fx.burst("levelup", head, 1.0)
		Fx.float_icon(head + Vector2(0, -14), Mechanics.tex("fever"), "×2", COL_GOLD)
	Feel.punch(0.02)
	GameState.emit_event(&"fever_started", {"cells": streak.fever_cells})
	fever_started.emit()


func _on_fever_ended() -> void:
	Sfx.play("pickup", 0.8, -4.0)
	GameState.emit_event(&"fever_ended", {})
	fever_ended.emit()


# --- тайники -----------------------------------------------------------------

## Сундук полосы (кэш на сессию: место — чистая функция от сида и исходной породы).
func chest_for_band(band: int) -> Dictionary:
	if band < 0:
		return {}
	if not _band_cache.has(band):
		_band_cache[band] = ChestLogic.chest_in_band(world, GameState.world_seed, band)
	return _band_cache[band]


## Сундук в клетке cell ({cell, tier}) или {}.
func chest_at(cell: Vector2i) -> Dictionary:
	var ch := chest_for_band(ChestLogic.band_of(cell.y))
	if ch.is_empty() or ch["cell"] != cell:
		return {}
	return ch


func open_chest(cell: Vector2i, tier: String) -> Dictionary:
	MechState.mark_chest_opened(cell, tier)
	var loot := ChestLogic.roll_loot(world, GameState.world_seed, cell, tier)
	var items: Dictionary = loot["items"]
	GameState.add_xp(int(loot["xp"]))
	var left := {}
	for id in items.keys():
		var n := int(items[id])
		var got := GameState.add_item(String(id), n)
		if got < n:
			left[id] = n - got
	MechState.set_chest_left(cell, left)
	stats["chests"] += 1
	var pos := Vector2(cell.x * 32.0 + 16.0, cell.y * 32.0 + 16.0)
	Sfx.play("pickup_rare" if tier == "wood" else "reward")
	Sfx.play("door", 1.6, -8.0)   # скрип крышки
	Haptics.buzz(50 if tier == "wood" else 90)
	Fx.burst("coins", pos, 0.8 if tier == "wood" else 1.4)
	Fx.burst("spark", pos + Vector2(0, -6), 1.0, COL_GOLD)
	if tier == "gold":
		Fx.flash(Color(1.0, 0.9, 0.5, 0.25), 0.2)
	Feel.punch(0.015 if tier == "wood" else 0.03)
	# добыча «вылетает» из сундука в рюкзак: по значку на вид, до трёх штук веером
	if not Settings.reduce_motion:
		var from := _to_screen(pos)
		var shown := 0
		for id in items.keys():
			var got_n := int(items[id]) - int(left.get(id, 0))
			if got_n <= 0 or shown >= 5:
				continue
			shown += 1
			Fx.fly_to(UiIcons.item_small(String(id), 16), from, HudAnchors.get_anchor("backpack"), mini(got_n, 3))
	if not left.is_empty():
		_full_warned[MechState.cell_key(cell)] = true
		Fx.float_icon(pos + Vector2(0, -20), UiIcons.tex("weight"), "Полно", Color("FF8A6A"))
	if chest_layer != null:
		chest_layer.play_open(cell)
	GameState.emit_event(&"chest_opened", {"cell": cell, "tier": tier, "items": items, "xp": int(loot["xp"])})
	chest_opened.emit(cell, tier, items)
	return loot


## Остаток в открытом сундуке забирается, когда герой рядом и в рюкзаке есть место.
func _pick_leftovers() -> void:
	if not GameState.is_alive or GameState.house_is_indoors:
		return
	var hx := int(player.call("cell_x"))
	var hy := int(player.call("cell_y"))
	for c: Vector2i in MechState.chests_with_loot():
		if absi(c.x - hx) > 1 or absi(c.y - hy) > 1:
			_full_warned.erase(MechState.cell_key(c))
			continue
		var left := MechState.chest_left(c)
		var took := false
		for id in left.keys():
			var got := GameState.add_item(String(id), int(left[id]))
			if got > 0:
				left[id] = int(left[id]) - got
				took = true
		MechState.set_chest_left(c, left)
		var pos := Vector2(c.x * 32.0 + 16.0, c.y * 32.0 + 16.0)
		if took:
			Sfx.play("pickup")
			Fx.burst("pickup_glint", pos, 1.0)
			if chest_layer != null:
				chest_layer.queue_redraw()
		elif not _full_warned.has(MechState.cell_key(c)):
			_full_warned[MechState.cell_key(c)] = true
			Fx.float_icon(pos + Vector2(0, -20), UiIcons.tex("weight"), "Полно", Color("FF8A6A"))

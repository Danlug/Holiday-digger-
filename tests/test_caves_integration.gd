extends Node
## test_caves_integration — полости-фигуры в живой main-сцене (без окна):
## слой кромки в ViewRoot, стражи появляются у полости с домом и поводком,
## сундук заперт, пока они живы, после зачистки открывается касанием через
## MechDirector (добыча в рюкзак, событие chest_opened), убитые не возвращаются,
## живые при возвращении появляются снова; снаряд стрелка летит, виден и бьёт.
##
## Запуск: godot --headless --path . res://tests/test_caves_integration.tscn

const SEED := 4242

var failures := 0
var total := 0
var main: Node2D
var director: CombatDirector
var events: Array = []


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _on_event(id: StringName, data: Dictionary) -> void:
	events.append([String(id), data])


func _count(id: String) -> int:
	var n := 0
	for e in events:
		if e[0] == id:
			n += 1
	return n


func _last(id: String) -> Dictionary:
	for i in range(events.size() - 1, -1, -1):
		if events[i][0] == id:
			return events[i][1]
	return {}


func _step(n: int, dt: float = 1.0 / 30.0, keep_alive: bool = true) -> void:
	for i in range(n):
		if keep_alive:
			GameState.hp = GameState.get_max_hp()
		director._process(dt)


## Герой в центре полости: стоит на алтаре (клетка под сундуком — камень).
func _place(p, c: Dictionary, dx: float = 0.0) -> void:
	var cell := Caves.chest_cell(c)
	p.x = float(cell.x) + 0.5 + dx
	p.y = float(cell.y) + 1.0 - CombatDirector.HERO_HH - 0.01
	p.vx = 0.0
	p.vy = 0.0
	p.on_ground = true
	p.digging = null
	p.stun_until_msec = 0.0
	director.iframes = 0.0
	director._kb_left = 0.0
	director._cave_tick = 0.0
	main.fog.reveal_around(p.x, p.y, 9, 9)


func _guards_of(id: String) -> Array:
	var out: Array = []
	for m: Monster in director.monsters:
		if m.cave_id == id:
			out.append(m)
	return out


func _ready() -> void:
	print("=== test_caves_integration ===")
	seed(20260101)
	GameState.world_seed = SEED
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	StoryState.set_flag("food_ordered", true)
	GameState.ext.clear()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in range(4):
		await get_tree().process_frame
	GameState.game_event.connect(_on_event)
	GameState.ext.clear()
	GameState.inventory.clear()
	director = CombatService.director as CombatDirector
	director._stats_dirty = true
	check("директор боя знает о полостях", director.caves != null)
	var layer: Node = main.view_root.get_node_or_null("CaveLayer")
	var wv: Node = main.view_root.get_node_or_null("WorldView")
	check("слой полостей в ViewRoot сразу над миром", layer != null and wv != null and layer.get_index() == wv.get_index() + 1)
	main.set_process(false)
	director.set_process(false)
	director.spawner.reset()
	var p = main.player
	var w: WorldGen = main.world
	p.frozen = false
	GameState.house_is_indoors = false
	GameState.respawn()
	GameState.max_depth_reached = 3000
	GameState.inventory.clear()

	var caves := Caves.caves_between(w, 1500, 2600)
	check("на сиде %d есть полости до 2600 (%d)" % [SEED, caves.size()], caves.size() >= 2)
	var c: Dictionary = caves[0]
	var id := Caves.id_of(c)
	var n := Caves.guards(c).size()
	print("     полость %s «%s» r=%d, стражей %d" % [id, String(c.kind), int(c.r), n])

	# --- далеко от полости стражей нет ---
	_place(p, c)
	p.y -= 40.0
	main.fog.reveal_around(p.x, p.y, 9, 9)
	_step(30)
	check("в 40 клетках от полости стражи не появляются", _guards_of(id).is_empty())

	# --- у полости появляются все стражи с домом и поводком ---
	_place(p, c)
	_step(30)
	var gs := _guards_of(id)
	check("у полости появились все стражи (%d из %d)" % [gs.size(), n], gs.size() == n)
	var ok := true
	for m: Monster in gs:
		if m.home != Caves.center(c) or m.leash <= 0.0 or m.aggro < m.leash or m.guard_index < 0:
			ok = false
		if director.cw.solid(int(floor(m.x)), int(floor(m.y))):
			ok = false
	check("стражи стоят в воздухе полости, знают дом и поводок", ok)
	check("кнопка удара видна во время боя со стражами на %d" % int(c.cy), director.combat_ui_visible())
	check("сундук заперт", CaveGuards.chest_state(c) == "locked")
	var chest := Caves.chest_cell(c)
	_step(30)
	check("касание запертого сундука не открывает его", not MechState.chest_opened(chest) and _count("chest_opened") == 0)
	check("слой рисует полость и запертый сундук", _layer_has_chest(layer, chest, "locked"))

	# --- стражи ранят героя (хотя бы один удар за 20 секунд рядом) ---
	var hp0 := GameState.get_max_hp()
	GameState.hp = hp0
	var hurt := [0]
	director.hero_hurt.connect(func(_d, _s) -> void: hurt[0] += 1)
	for i in range(30 * 20):
		if GameState.hp < hp0 * 0.5:
			GameState.hp = hp0
		director._process(1.0 / 30.0)
		if hurt[0] > 0:
			break
	check("стражи бьют героя", hurt[0] > 0)
	check("герой жив (тест не про выживание)", GameState.is_alive)

	# --- убили одного, ушли, вернулись: он не вернулся, остальные стоят ---
	GameState.hp = hp0
	var first: Monster = gs[0]
	first.take_hit(1e9, 1)
	_step(40)
	check("убитый страж запомнен", CaveGuards.killed(id).size() == 1 and _count("monster_killed") >= 1)
	check("полость не зачищена одним убийством", not CaveGuards.is_cleared(c) and _count("cave_cleared") == 0)
	_place(p, c)
	p.y -= 45.0
	_step(30)
	check("ушёл далеко — стражи исчезли", _guards_of(id).is_empty())
	_place(p, c)
	_step(30)
	check("вернулся — стоят только живые (%d)" % _guards_of(id).size(), _guards_of(id).size() == n - 1)

	# --- зачистка: событие, замок снят, сундук открывается касанием ---
	for m: Monster in _guards_of(id):
		m.take_hit(1e9, 1)
	_step(40)
	check("полость зачищена: событие cave_cleared", CaveGuards.is_cleared(c) and _count("cave_cleared") == 1
			and String(_last("cave_cleared").get("id", "")) == id)
	check("стражей не осталось и новых нет", _guards_of(id).is_empty())
	var inv0 := GameState.inventory.size()
	_place(p, c)
	_step(20)
	check("сундук открыт касанием через MechDirector", MechState.chest_opened(chest) and _count("chest_opened") == 1
			and String(_last("chest_opened").get("tier", "")) == "cave")
	check("событие cave_chest_opened", _count("cave_chest_opened") == 1)
	var items: Dictionary = _last("chest_opened").get("items", {})
	check("добыча легла в рюкзак или осталась в сундуке", not items.is_empty() and (GameState.inventory.size() > inv0 or not MechState.chest_left(chest).is_empty()))
	check("состояние сундука: с остатком или пуст", CaveGuards.chest_state(c) in ["loot", "empty"])
	check("повторного открытия нет", _count("chest_opened") == 1)
	_step(5)
	check("слой рисует открытый сундук", _layer_has_chest(layer, chest, "loot") or _layer_has_chest(layer, chest, "empty"))
	check("память в ext: убитых %d, открытых 1" % n, CaveGuards.killed(id).size() == n and int((GameState.ext_get("caves", {}) as Dictionary).get("opened", 0)) == 1)

	# --- стрелок в живой сцене: снаряд существует, рисуется, долетает ---
	var c2: Dictionary = caves[1]
	for m: Monster in director.monsters:
		m.take_hit(1e9, 1)
	_step(40)
	director.monsters.clear()
	director.spawning_enabled = false
	_place(p, c2)
	GameState.hp = hp0
	var cell2 := Caves.chest_cell(c2)
	var floors := Caves.floor_cells(c2)
	var fcell: Vector2i = floors[0]
	for f: Vector2i in floors:
		if absi(f.x - cell2.x) > absi(fcell.x - cell2.x):
			fcell = f
	var sp := director.spawn({"id": "acid_spitter", "x": float(fcell.x) + 0.5, "y": float(fcell.y), "group": 1, "emerge": Vector2.ZERO})
	sp.cd = 0.0
	var shot := false
	var hp_before := GameState.hp
	var broke_or_hit := false
	director.iframes = 0.0
	for i in range(30 * 12):
		director._process(1.0 / 30.0)
		if not director.projectiles.is_empty():
			shot = true
			var view: Node = main.view_root.get_node_or_null("CombatView")
			if view != null and not view._proj_sprites.is_empty():
				broke_or_hit = true   # спрайт снаряда создан
		if shot and director.projectiles.is_empty():
			break
	check("стрелок выпустил снаряд, снаряд рисуется", shot and broke_or_hit)
	check("снаряд долетел: либо ранил героя, либо разбился", GameState.hp < hp_before or director.projectiles.is_empty())
	director.monsters.clear()
	director.projectiles.clear()

	# --- смерть героя чистит стражей и снаряды ---
	director.spawning_enabled = true
	_place(p, c2)
	_step(30)
	check("у второй полости стражи стоят", not _guards_of(Caves.id_of(c2)).is_empty())
	GameState.take_damage(1e6, "test")
	check("смерть героя убирает монстров и снаряды", director.monsters.is_empty() and director.projectiles.is_empty())
	GameState.respawn()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _layer_has_chest(layer: Node, cell: Vector2i, state: String) -> bool:
	if layer == null:
		return false
	layer._collect()
	for e in layer.entries():
		var ch: Dictionary = e["chest"]
		if not ch.is_empty() and ch["cell"] == cell and String(ch["state"]) == state:
			return true
	return false

class_name CaveGuards
extends RefCounted
## CaveGuards — стражи и сундуки полостей-фигур (раунд 5): кто ещё жив, кого
## пора поставить, когда сундук отперт. Логика без узлов: директор боя зовёт
## spawn_requests() и tick_chest(), сам создаёт монстров и ранит героя.
##
## Убитые стражи запоминаются по индексу в GameState.ext["caves"] (сейв не
## правился): вернулся в полость — остальные стоят как стояли, с полным HP
## (HP живых не хранится: хит-энд-ран ничего не даёт и ничего не ломает).
## Сундук в центре заперт, пока жив хоть один страж; отперли — открывается
## касанием (MechDirector.open_chest, ступень "cave" из data/mechanics.json),
## дальше это обычный открытый сундук: остаток подбирается, как у тайников.

const KEY := "caves"

var world: WorldGen
var cw: CombatWorld
var _warned: Dictionary = {}


func _init(p_world: WorldGen = null, p_cw: CombatWorld = null) -> void:
	world = p_world
	cw = p_cw


# ---------------------------------------------------------------------------
# Сохраняемое: убитые стражи
# ---------------------------------------------------------------------------

static func root() -> Dictionary:
	var r = GameState.ext.get(KEY, null)
	if typeof(r) != TYPE_DICTIONARY:
		r = {}
		GameState.ext[KEY] = r
	if typeof(r.get("kills")) != TYPE_DICTIONARY:
		r["kills"] = {}
	return r


## Индексы убитых стражей полости.
static func killed(cave_id: String) -> Array:
	var raw = root()["kills"].get(cave_id, null)
	var out: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for v in raw:
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				out.append(int(v))
	return out


static func note_kill(cave_id: String, index: int) -> void:
	var k := killed(cave_id)
	if not k.has(index):
		k.append(index)
	root()["kills"][cave_id] = k
	root()["kills_total"] = int(root().get("kills_total", 0)) + 1
	GameState.ext_set(KEY, root())


static func is_cleared(c: Dictionary) -> bool:
	return killed(Caves.id_of(c)).size() >= Caves.guards(c).size()


static func cleared_count() -> int:
	return int(root().get("cleared", 0))


static func note_cleared() -> void:
	root()["cleared"] = cleared_count() + 1
	GameState.ext_set(KEY, root())


static func tier() -> String:
	return String(Caves.section("chest").get("tier", "cave"))


static func touch_radius() -> float:
	return float(Caves.unwrap(Caves.section("chest").get("touch_radius"), 1.15))


# ---------------------------------------------------------------------------
# Полости рядом с героем
# ---------------------------------------------------------------------------

func near(hero: Vector2, dist: float) -> Array:
	var out: Array = []
	if world == null:
		return out
	var span := int(ceil(dist)) + Caves.slot_h()
	for c in Caves.caves_between(world, int(hero.y) - span, int(hero.y) + span):
		if Caves.center(c).distance_to(hero) <= dist:
			out.append(c)
	return out


## Заявки на появление недостающих стражей полостей в радиусе spawn_dist:
## [{id, x, y, group, emerge, cave_id, index, home, leash, aggro}].
## monsters — живые монстры директора (кто уже стоит, второй раз не ставится).
func spawn_requests(hero: Vector2, monsters: Array) -> Array:
	var out: Array = []
	var spawn_dist := float(Caves.unwrap(Caves.section("guards").get("spawn_dist"), 16.0))
	for c in near(hero, spawn_dist):
		if is_cleared(c):
			continue
		var id := Caves.id_of(c)
		var present := {}
		for m in monsters:
			if m is Monster and (m as Monster).cave_id == id:
				present[(m as Monster).guard_index] = true
		var dead := killed(id)
		for g in Caves.guards(c):
			if present.has(int(g.index)) or dead.has(int(g.index)):
				continue
			var req := _place(c, g)
			if not req.is_empty():
				out.append(req)
	return out


## Место стражу: своя клетка, иначе первая подходящая того же рода (воздух / пол).
func _place(c: Dictionary, g: Dictionary) -> Dictionary:
	var mid := String(g.id)
	var air := bool(g.air)
	var depth := int(c.cy)
	var candidates: Array = [g.cell]
	candidates.append_array(Caves.air_cells(c) if air else Caves.floor_cells(c))
	for cell: Vector2i in candidates:
		var y := float(cell.y) + (0.5 if air else 0.0)
		var probe := Monster.create(mid, float(cell.x) + 0.5, y, depth)
		if cw != null and not probe.fits(cw.solid):
			continue
		return {"id": mid, "x": float(cell.x) + 0.5, "y": y, "group": 0, "emerge": Vector2.ZERO,
			"cave_id": Caves.id_of(c), "index": int(g.index), "home": Caves.center(c),
			"leash": Caves.leash(c), "aggro": Caves.aggro(c)}
	return {}


# ---------------------------------------------------------------------------
# Сундук
# ---------------------------------------------------------------------------

## Состояние сундука полости: locked / closed / loot / empty.
static func chest_state(c: Dictionary) -> String:
	var cell := Caves.chest_cell(c)
	if MechState.chest_opened(cell):
		return "empty" if MechState.chest_left(cell).is_empty() else "loot"
	return "closed" if is_cleared(c) else "locked"


## Герой коснулся сундука: отперт — открывается (mech — MechDirector), заперт —
## один раз за подход звякает замок. Возвращает открытую полость или {}.
func tick_chest(hero: Vector2, mech: Node) -> Dictionary:
	for c in near(hero, 14.0):
		var cell := Caves.chest_cell(c)
		if MechState.chest_opened(cell):
			continue
		var id := Caves.id_of(c)
		var pos := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
		if hero.distance_to(pos) > touch_radius():
			_warned.erase(id)
			continue
		if is_cleared(c):
			if mech != null and mech.has_method("open_chest"):
				mech.call("open_chest", cell, tier())
				root()["opened"] = int(root().get("opened", 0)) + 1
				GameState.ext_set(KEY, root())
				GameState.emit_event(&"cave_chest_opened", {"id": id, "kind": String(c.kind), "cell": cell, "pos": pos * 32.0})
				return c
		elif not _warned.has(id):
			_warned[id] = true
			Sfx.play("ui_deny")
			Haptics.tap()
			Fx.float_icon(pos * 32.0 + Vector2(0, -20), Mechanics.tex("cave_lock"), "", Color("FF7A6A"))
	return {}

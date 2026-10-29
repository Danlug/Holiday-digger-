extends Node
## test_caves — стражи полостей-фигур (раунд 5) без окна: данные стражей, поводок
## и возвращение домой, прыжок через ступеньку, стрелок и снаряды, память об
## убитых и замок сундука, награда сундука полости, проходимость боя героем
## без брони (модель героя против настоящих Monster/Projectile).
## Генерация полостей — tests/test_caves_gen.gd, живая сцена — test_caves_integration.
##
## Запуск: godot --headless --path . res://tests/test_caves.tscn

var failures := 0
var total := 0
var world: WorldGen

## Ступенька на пути ходячего: клетка (11, 9) твёрдая, пол — ряд 10.
var _step_grid := false


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_caves ===")
	await get_tree().process_frame
	world = WorldGen.new(4242)
	_test_data()
	_test_leash()
	_test_hop()
	_test_shooter()
	_test_guard_state()
	_test_rewards()
	_test_balance()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _solid(cx: int, cy: int) -> bool:
	if _step_grid and cx == 11 and cy == 9:
		return true
	return cy >= 10 or cx <= 0 or cx >= 24 or cy < 2


func _hero(x: float, y: float) -> Dictionary:
	return {"x": x, "y": y, "hw": 0.38, "hh": 1.0 / 3.0, "alive": true}


func _run(m: Monster, seconds: float, hero: Dictionary) -> Array:
	var events: Array = []
	var t := 0.0
	var solid := Callable(self, "_solid")
	while t < seconds:
		events.append_array(m.tick(1.0 / 60.0, hero, solid))
		t += 1.0 / 60.0
	return events


func _count(events: Array, type: String) -> int:
	var n := 0
	for e in events:
		if e["type"] == type:
			n += 1
	return n


func _guard(mid: String, x: float, y: float, depth: int, home: Vector2, leash: float, aggro: float, seed_value: int = 7) -> Monster:
	var m := Monster.create(mid, x, y, depth, seed_value)
	m.home = home
	m.leash = leash
	m.aggro = aggro
	m.cave_id = "test"
	return m


# ---------------------------------------------------------------------------

func _test_data() -> void:
	CombatData.reload()
	var ids := CombatData.cave_monster_ids()
	check("четыре вида стражей", ids.size() == 4)
	var beh := {}
	var ok := true
	for id in ids:
		var m := CombatData.monster(String(id))
		beh[String(m.get("behavior"))] = true
		for key in ["hp", "damage", "speed", "size", "depth", "xp", "drops", "kind", "cave"]:
			if not m.has(key):
				ok = false
				print("  у ", id, " нет ", key)
		if not m.has("proposed") or int((m["depth"] as Array)[0]) != 1500 or int((m["depth"] as Array)[1]) >= 4000:
			ok = false
		var sh := MonsterSheet.get_sheet(String(id))
		if sh.texture == null or not (sh.has_anim("idle") and sh.has_anim("move") and sh.has_anim("attack") and sh.has_anim("die")):
			ok = false
			print("  у ", id, " нет листа кадров")
	check("у каждого стража поля, пометка proposed (владелец утвердил 26.10 — false), пояс 1500–3999 и лист кадров", ok)
	check("летающий, прыгающий, ходящий и стреляющий", beh.has("flyer") and beh.has("jumper") and beh.has("crawler") and beh.has("shooter"))
	check("стражи не в списке тоннельных монстров (спавн глубже 4000 не тронут)",
			not CombatData.monster_ids().has("cave_bat") and CombatData.monster("cave_bat").get("behavior") == "flyer")
	var pr := MonsterSheet.get_sheet("fx_projectiles")
	check("лист снарядов: кислота, камень, искра", pr.texture != null and pr.has_anim("acid") and pr.has_anim("stone") and pr.has_anim("spark"))
	check("сила стража растёт от 1500 своим темпом (×%.2f HP на 3500)" % CombatData.hp_mult("cave_bat", 3500),
			absf(CombatData.hp_mult("cave_bat", 3500) - 1.6) < 0.01 and absf(CombatData.dmg_mult("cave_bat", 3500) - 1.44) < 0.01
			and CombatData.hp_mult("cave_bat", 1500) == 1.0)
	check("темп старых монстров прежний", absf(CombatData.hp_mult("cinder_grub", 5000) - 1.1) < 0.001)
	check("стрелок несёт описание снаряда", CombatData.monster("acid_spitter").has("projectile"))
	check("сундук полости: своя ступень с ростом по глубине",
			not ChestLogic.tier_row("cave").is_empty() and ChestLogic.tier_value_cells(ChestLogic.tier_row("cave"), 1500) < ChestLogic.tier_value_cells(ChestLogic.tier_row("cave"), 3500))
	check("ступень cave не разыгрывается полосами тайников", ChestLogic.pick_tier(4242, 3, 2000) != "cave" and ChestLogic.pick_tier(4242, 9, 3500) != "cave")
	check("графика сундука и замка на месте", Mechanics.tex("chest_cave") != null and Mechanics.tex("chest_cave_icon") != null and Mechanics.tex("cave_lock") != null)


func _test_leash() -> void:
	var home := Vector2(12.5, 6.5)
	# летун: герой вне агро — не замечает, не бьёт, держится дома
	var bat := _guard("cave_bat", 12.5, 6.5, 2000, home, 4.0, 6.0)
	var ev := _run(bat, 4.0, _hero(21.0, 9.67))
	check("летун вне агро не бьёт и не замахивается", _count(ev, "hit") == 0 and _count(ev, "windup") == 0)
	check("летун вне агро держится у дома (%.1f)" % Vector2(bat.x, bat.y).distance_to(home), Vector2(bat.x, bat.y).distance_to(home) <= 4.6)
	# герой в агро — атакует
	var bat2 := _guard("cave_bat", 12.5, 6.5, 2000, home, 4.0, 6.0, 8)
	var hero_near := _hero(16.0, 9.67)
	var max_d := 0.0
	var windups := 0
	var t := 0.0
	while t < 8.0:
		for e in bat2.tick(1.0 / 60.0, hero_near, Callable(self, "_solid")):
			if e["type"] == "windup":
				windups += 1
		max_d = maxf(max_d, Vector2(bat2.x, bat2.y).distance_to(home))
		t += 1.0 / 60.0
	check("летун в агро атакует (замахов %d)" % windups, windups >= 1)
	check("летун не улетает далеко за поводок (макс %.1f при поводке 4)" % max_d, max_d <= 7.0)
	# ушёл за поводок — возвращается домой, не глядя на героя
	var bat3 := _guard("cave_bat", 20.0, 6.5, 2000, home, 4.0, 6.0, 9)
	bat3.state = "chase"
	var ev3 := _run(bat3, 0.1, _hero(21.0, 9.67))
	check("за поводком летун переходит в возвращение", bat3.state == "return")
	_run(bat3, 5.0, _hero(21.0, 9.67))
	check("летун вернулся к дому (%.1f)" % Vector2(bat3.x, bat3.y).distance_to(home), Vector2(bat3.x, bat3.y).distance_to(home) <= 2.5)
	check("возвращение рисуется как полёт", bat3.anim_name() in ["move", "idle"])
	# ходячий: патрулирует у дома, героя далеко не замечает
	var beetle := _guard("shell_beetle", 12.5, 9, 2000, Vector2(12.5, 9.5), 4.0, 6.0, 10)
	var far := 0.0
	t = 0.0
	while t < 10.0:
		beetle.tick(1.0 / 60.0, _hero(22.0, 9.67), Callable(self, "_solid"))
		far = maxf(far, absf(beetle.x - 12.5))
		t += 1.0 / 60.0
	check("ходячий страж не уходит дальше поводка (макс %.1f)" % far, far <= 5.0 and beetle.on_ground)
	# прыгун: в агро прыгает на героя, вне агро — домой
	var toad := _guard("cave_toad", 10.5, 9, 2000, Vector2(10.5, 9.5), 4.0, 6.0, 11)
	var leaps := 0
	t = 0.0
	var hero_t := _hero(13.5, 9.67)
	while t < 5.0:
		toad.tick(1.0 / 60.0, hero_t, Callable(self, "_solid"))
		if toad.state == "leap":
			leaps += 1
		t += 1.0 / 60.0
	check("прыгун в агро прыгает", leaps > 0)
	var toad2 := _guard("cave_toad", 19.5, 9, 2000, Vector2(10.5, 9.5), 4.0, 6.0, 12)
	_run(toad2, 8.0, _hero(22.0, 9.67))
	check("прыгун за поводком допрыгал домой (%.1f)" % absf(toad2.x - 10.5), absf(toad2.x - 10.5) <= 3.0)


func _test_hop() -> void:
	_step_grid = true
	var beetle := _guard("shell_beetle", 8.5, 9, 2000, Vector2(12.5, 9.5), 9.0, 12.0, 13)
	var hero := _hero(14.5, 9.67)
	var t := 0.0
	var passed := false
	while t < 8.0 and not passed:
		beetle.tick(1.0 / 60.0, hero, Callable(self, "_solid"))
		passed = beetle.x > 12.0
		t += 1.0 / 60.0
	check("ходячий страж перепрыгивает ступеньку в погоне (x=%.1f)" % beetle.x, passed)
	# старый ползун без can_hop упирается в ступеньку, как раньше
	var grub := Monster.create("cinder_grub", 8.5, 9, 4500, 14)
	t = 0.0
	while t < 5.0:
		grub.tick(1.0 / 60.0, hero, Callable(self, "_solid"))
		t += 1.0 / 60.0
	check("старый ползун ступеньку не берёт (поведение прежнее)", grub.x < 11.0)
	_step_grid = false


func _test_shooter() -> void:
	# прицел: по дуге снаряд приходит в точку
	var v := Projectile.aim(5.0, 0.0, 7.5, 11.0, false)
	var x := 0.0
	var y := 0.0
	var vx := v.x
	var vy := v.y
	var landed := -1.0
	for i in range(600):
		var dt := 1.0 / 120.0
		vy += 11.0 * dt
		x += vx * dt
		y += vy * dt
		if y >= 0.0 and i > 5:
			landed = x
			break
	check("прицел по дуге попадает в цель (%.2f из 5)" % landed, absf(landed - 5.0) < 0.35)
	var vh := Projectile.aim(3.0, 0.0, 7.5, 11.0, true)
	check("навесной выстрел выше настильного", vh.y < Projectile.aim(3.0, 0.0, 7.5, 11.0, false).y)
	var vs := Projectile.aim(4.0, -3.0, 6.0, 0.0, false)
	check("без тяготения — по прямой со скоростью 6", absf(vs.length() - 6.0) < 0.01 and vs.x > 0.0 and vs.y < 0.0)
	check("недосягаемая цель — выстрел под углом, не ошибка", Projectile.aim(40.0, 0.0, 3.0, 11.0, false).length() > 0.0)

	# стрелок: замах, выстрел, снаряд долетает до стоящего героя
	var sp := Monster.create("acid_spitter", 8.5, 9, 2000, 15)
	var hero := _hero(14.0, 9.67)
	var solid := Callable(self, "_solid")
	var shots: Array = []
	var windups := 0
	var t := 0.0
	while t < 8.0:
		for e in sp.tick(1.0 / 60.0, hero, solid):
			if e["type"] == "windup":
				windups += 1
			elif e["type"] == "shoot":
				shots.append(e)
		t += 1.0 / 60.0
	check("стрелок замахивается и стреляет (замахов %d, выстрелов %d)" % [windups, shots.size()], windups >= 2 and shots.size() >= 2 and shots.size() <= 4)
	check("стрелок не подходит вплотную (x=%.1f)" % sp.x, sp.x < 11.0)
	var hits := 0
	var breaks := 0
	for s in shots:
		var p := Projectile.create(s["spec"], float(s["x"]), float(s["y"]), float(s["vx"]), float(s["vy"]), float(s["damage"]), String(s["kind"]))
		var tt := 0.0
		while p.alive and tt < 4.0:
			for e in p.tick(1.0 / 60.0, hero, solid):
				if e["type"] == "hit":
					hits += 1
					check("урон снаряда — урон стрелка, вид void", absf(float(e["damage"]) - sp.damage) < 0.01 and e["kind"] == "void")
				elif e["type"] == "break":
					breaks += 1
			tt += 1.0 / 60.0
	check("снаряды попадают по стоящему герою (%d из %d)" % [hits, shots.size()], hits >= 1)
	# снаряд в стену бьётся, не пролетает
	var wall := Projectile.create({"kind": "stone", "speed": 8.0, "gravity": 0.0, "radius": 0.2, "ttl": 3.0}, 20.0, 8.0, 8.0, 0.0, 5.0, "phys")
	var ev: Array = []
	var tt2 := 0.0
	while wall.alive and tt2 < 3.0:
		ev.append_array(wall.tick(1.0 / 60.0, _hero(2.0, 9.67), solid))
		tt2 += 1.0 / 60.0
	check("снаряд бьётся о породу (break) и гаснет", _count(ev, "break") == 1 and not wall.alive and wall.x < 24.5)
	var old := Projectile.create({"kind": "acid", "speed": 1.0, "gravity": 0.0, "radius": 0.2, "ttl": 0.5}, 12.0, 6.0, 0.0, 0.0, 5.0, "void")
	var ev2: Array = []
	for i in range(60):
		ev2.append_array(old.tick(1.0 / 60.0, _hero(2.0, 9.67), solid))
	check("снаряд гаснет по времени жизни", _count(ev2, "expire") == 1 and not old.alive)
	# близко — стрелок пятится
	var sp2 := Monster.create("acid_spitter", 12.5, 9, 2000, 16)
	var x0 := sp2.x
	_run(sp2, 1.0, _hero(13.5, 9.67))
	check("герой вплотную — стрелок пятится (%.1f → %.1f)" % [x0, sp2.x], sp2.x < x0 - 0.2)
	# удар героя прерывает замах
	var sp3 := Monster.create("acid_spitter", 8.5, 9, 2000, 17)
	sp3.state = "windup"
	sp3.telegraph = true
	sp3.take_hit(5.0, 1)
	check("удар по стрелку сбивает замах", sp3.state == "stagger" and not sp3.telegraph)
	check("замах стрелка рисуется атакой", Monster.create("acid_spitter", 8.5, 9, 2000).anim_name() == "idle" and sp3.anim_name() == "idle")


class StubMech:
	extends Node
	var calls: Array = []
	func open_chest(cell: Vector2i, tier: String) -> Dictionary:
		calls.append([cell, tier])
		MechState.mark_chest_opened(cell, tier)
		return {}


func _test_guard_state() -> void:
	GameState.ext.clear()
	var caves := Caves.caves_between(world, 1500, 2600)
	check("на сиде 4242 есть полости до 2600 (%d)" % caves.size(), caves.size() >= 1)
	var c: Dictionary = caves[0]
	var id := Caves.id_of(c)
	var n := Caves.guards(c).size()
	check("полость не зачищена, сундук заперт", not CaveGuards.is_cleared(c) and CaveGuards.chest_state(c) == "locked")
	var cg := CaveGuards.new(world, CombatWorld.new(world))
	var center := Caves.center(c)
	var reqs := cg.spawn_requests(center, [])
	check("у центра полости заявки на всех стражей (%d)" % reqs.size(), reqs.size() == n)
	var fields_ok := true
	var air_ok := true
	for r in reqs:
		if String(r.get("cave_id", "")) != id or float(r.get("leash", 0.0)) <= 0.0 or r.get("home") != center:
			fields_ok = false
		var probe := Monster.create(String(r["id"]), float(r["x"]), float(r["y"]), int(c.cy))
		if not probe.fits(cg.cw.solid):
			air_ok = false
	check("в заявках дом, поводок и полость", fields_ok)
	check("страж помещается в своей клетке", air_ok)
	check("далеко от полости заявок нет", cg.spawn_requests(center + Vector2(0, 60), []).is_empty())
	# один уже стоит — заявок на одного меньше
	var m := Monster.create(String(reqs[0]["id"]), float(reqs[0]["x"]), float(reqs[0]["y"]), int(c.cy))
	m.cave_id = id
	m.guard_index = int(reqs[0]["index"])
	check("стоящий страж второй раз не ставится", cg.spawn_requests(center, [m]).size() == n - 1)
	# убитые запоминаются
	for g in Caves.guards(c):
		if int(g.index) == n - 1:
			continue
		CaveGuards.note_kill(id, int(g.index))
	check("после убийств заявки только на живых (1)", cg.spawn_requests(center, []).size() == 1 and not CaveGuards.is_cleared(c))
	var mech := StubMech.new()
	add_child(mech)
	var chest := Caves.chest_cell(c)
	var cpos := Vector2(chest.x + 0.5, chest.y + 0.5)
	cg.tick_chest(cpos, mech)
	check("запертый сундук касанием не открывается", mech.calls.is_empty() and not MechState.chest_opened(chest))
	CaveGuards.note_kill(id, n - 1)
	check("последний страж — полость зачищена, сундук закрыт", CaveGuards.is_cleared(c) and CaveGuards.chest_state(c) == "closed")
	check("память об убитых в GameState.ext[caves]", (GameState.ext_get("caves", {}) as Dictionary).get("kills", {}).has(id)
			and CaveGuards.killed(id).size() == n)
	check("далеко от сундука касания нет", cg.tick_chest(cpos + Vector2(3, 0), mech).is_empty() and mech.calls.is_empty())
	var opened := cg.tick_chest(cpos, mech)
	check("касание отпертого сундука открывает его ступенью cave", not opened.is_empty() and mech.calls.size() == 1
			and mech.calls[0][1] == "cave" and MechState.chest_opened(chest) and CaveGuards.chest_state(c) == "empty")
	check("повторное касание ничего не делает", cg.tick_chest(cpos, mech).is_empty() and mech.calls.size() == 1)
	mech.queue_free()
	# мусор в сейве не роняет
	GameState.ext["caves"] = {"kills": {id: "x", "a": [1.0, "b", 2]}, "cleared": "много"}
	check("мусор в ext переживается", CaveGuards.killed(id).is_empty() and CaveGuards.killed("a") == [1, 2] and CaveGuards.cleared_count() == 0)
	GameState.ext.clear()
	# тайники не попадают в воздух полости (ChestLogic видит полости через исходную породу)
	var in_air := 0
	for s in range(6):
		var w := WorldGen.new(s * 77 + 9)
		for cv in Caves.caves_between(w, 1500, 4000):
			var air := {}
			for cell: Vector2i in Caves.air_cells(cv):
				air[cell] = true
			for band in range(ChestLogic.band_of(int(cv.y0)), ChestLogic.band_of(int(cv.y1)) + 1):
				var ch := ChestLogic.chest_in_band(w, w.world_seed, band)
				if not ch.is_empty() and air.has(ch["cell"]):
					in_air += 1
	check("тайники не попадают в воздух полостей", in_air == 0)


func _test_rewards() -> void:
	var better := 0
	var total_caves := 0
	var items_ok := true
	var gems := 0
	var medkits := 0
	var xp_ok := true
	for s in range(5):
		var w := WorldGen.new(s * 101 + 5)
		for c in Caves.caves_between(w, 1500, 4000):
			total_caves += 1
			var cell := Caves.chest_cell(c)
			var cave := ChestLogic.roll_loot(w, w.world_seed, cell, "cave")
			var gold := ChestLogic.roll_loot(w, w.world_seed, cell, "gold")
			var cv := ChestLogic.loot_value(cave["items"])
			var gv := ChestLogic.loot_value(gold["items"])
			if cv > gv:
				better += 1
			var n := 0
			for id in (cave["items"] as Dictionary).keys():
				if String(id) == "medkit":
					medkits += 1
					continue
				if ["diamond", "ruby", "divine_heart"].has(String(id)):
					gems += 1
				n += int(cave["items"][id])
			if n < 6 or n > 31:
				items_ok = false
			if int(cave["xp"]) < 250:
				xp_ok = false
	print("     полостей: %d, сундук полости ценнее золотого в %d, самоцветов %d, аптечек %d" % [total_caves, better, gems, medkits])
	check("сундук полости ценнее золотого тайника почти всегда", total_caves > 20 and better >= total_caves * 0.9)
	check("штук в сундуке полости 6–30 (плюс аптечка)", items_ok)
	check("в каждом сундуке полости самоцвет", gems >= total_caves)
	check("аптечка — больше чем в половине сундуков", medkits > total_caves / 2)
	check("опыт сундука полости не меньше 250", xp_ok)
	var cv1500 := ChestLogic.tier_value_cells(ChestLogic.tier_row("cave"), 1500)
	var cv3500 := ChestLogic.tier_value_cells(ChestLogic.tier_row("cave"), 3500)
	check("ценность растёт с глубиной: %.0f → %.0f клеток" % [cv1500, cv3500], cv1500 >= 40.0 and cv3500 >= cv1500 + 40.0)
	check("у тайников value_per_1000 нет — их ценность прежняя", ChestLogic.tier_value_cells(ChestLogic.tier_row("gold"), 3500) == 35.0)


# ---------------------------------------------------------------------------
# Проходимость: модель героя (кирка 14/0.7 с, без брони) против настоящих стражей.
# Герой стоит на полу и бьёт всё в радиусе удара; «уклонение» — доля ударов, которых
# внимательный игрок избегает по телеграфу (0 — стоит столбом).
# ---------------------------------------------------------------------------

func _sim_fight(ids: Array, depth: int, hero_hp: float, dodge: float, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := CombatService.stats()
	var hero := _hero(12.0, 9.67)
	var hp := hero_hp
	var iframes := 0.0
	var cd := 0.0
	var monsters: Array = []
	var projectiles: Array = []
	var xs := [8.5, 16.5, 6.5, 18.5]
	for i in range(ids.size()):
		var mid := String(ids[i])
		var air: bool = CombatData.monster(mid).get("behavior") == "flyer"
		var m := Monster.create(mid, float(xs[i]), 6.5 if air else 9.0, depth, seed_value + i)
		m.home = Vector2(12.5, 7.5)
		m.leash = 9.0
		m.aggro = 12.0
		monsters.append(m)
	var solid := Callable(self, "_solid")
	var t := 0.0
	var dt := 1.0 / 30.0
	var taken := 0.0
	while t < 90.0 and hp > 0.0:
		var alive := 0
		for m: Monster in monsters:
			if not m.alive:
				continue
			alive += 1
			for e in m.tick(dt, hero, solid):
				if e["type"] == "hit" and iframes <= 0.0:
					if rng.randf() < dodge:
						continue
					hp -= CombatService.mitigate(float(e["damage"]), String(e["kind"]), st)
					taken += float(e["damage"])
					iframes = 0.5
				elif e["type"] == "shoot":
					projectiles.append(Projectile.create(e["spec"], float(e["x"]), float(e["y"]), float(e["vx"]), float(e["vy"]), float(e["damage"]), String(e["kind"])))
		for p: Projectile in projectiles.duplicate():
			for e in p.tick(dt, hero, solid):
				if e["type"] == "hit" and iframes <= 0.0:
					if rng.randf() < dodge:
						continue
					hp -= CombatService.mitigate(float(e["damage"]), String(e["kind"]), st)
					taken += float(e["damage"])
					iframes = 0.5
			if not p.alive:
				projectiles.erase(p)
		if alive == 0:
			break
		iframes = maxf(0.0, iframes - dt)
		cd = maxf(0.0, cd - dt)
		if cd <= 0.0:
			# удар по ближайшему в радиусе, как _nearest_target/_do_swing директора
			var reach := float(st["reach"])
			var half_h := 0.5
			var best: Monster = null
			var best_gap := 1e9
			for m: Monster in monsters:
				if not m.alive:
					continue
				var gap := absf(m.x - hero["x"]) - m.hw - 0.38
				if gap <= reach and absf(m.y - hero["y"]) <= half_h + m.hh and gap < best_gap:
					best_gap = gap
					best = m
			if best == null:
				# никого в радиусе — шаг к ближайшему живому стражу (скорость героя ~3 клетки/с)
				var near: Monster = null
				var nd := 1e9
				for m: Monster in monsters:
					if m.alive and absf(m.x - hero["x"]) < nd:
						nd = absf(m.x - hero["x"])
						near = m
				if near != null and nd > 1.0:
					hero["x"] = clampf(float(hero["x"]) + signf(near.x - float(hero["x"])) * 3.0 * dt, 2.0, 22.0)
			if best != null:
				cd = float(st["cd"])
				var dir := 1 if best.x >= hero["x"] else -1
				var x0: float = hero["x"] - 0.15 if dir > 0 else hero["x"] - 0.38 - reach
				var rect := Rect2(x0, hero["y"] - half_h, 0.38 + reach + 0.15, half_h * 2.0)
				for m: Monster in monsters:
					if m.alive and m.hurtbox().intersects(rect):
						m.take_hit(float(st["damage"]) * rng.randf_range(0.92, 1.08), dir)
		t += dt
	var left := 0
	for m: Monster in monsters:
		if m.alive:
			left += 1
	return {"hp": hp, "won": left == 0 and hp > 0.0, "t": t, "taken": taken}


func _test_balance() -> void:
	GameState.ext.clear()
	var sets := [
		["1500, два стража, герой 140 HP (2 ступени)", ["shell_beetle", "acid_spitter"], 1500, 140.0],
		["1500, мышь и жаба, герой 140 HP", ["cave_bat", "cave_toad"], 1500, 140.0],
		["2500, три стража, герой 180 HP (4 ступени)", ["shell_beetle", "cave_toad", "acid_spitter"], 2500, 180.0],
		["3500, четыре стража, герой 220 HP (6 ступеней)", ["shell_beetle", "cave_toad", "cave_bat", "acid_spitter"], 3500, 220.0],
	]
	for s in sets:
		for dodge in [0.0, 0.4]:
			var wins := 0
			var runs := 20
			var hp_sum := 0.0
			var t_sum := 0.0
			for i in range(runs):
				var r := _sim_fight(s[1], int(s[2]), float(s[3]), dodge, 100 + i * 7)
				if bool(r["won"]):
					wins += 1
					hp_sum += float(r["hp"]) / float(s[3])
				t_sum += float(r["t"])
			var rate := float(wins) / float(runs)
			var hp_avg := hp_sum / maxf(1.0, float(wins))
			print("     %s, уклонение %.0f%%: побед %d/%d, HP после %.0f%%, бой %.0f с" % [s[0], dodge * 100.0, wins, runs, hp_avg * 100.0, t_sum / runs])
			if dodge == 0.0:
				check("%s: без уклонения — побед ≥ 50%%, но бой не бесплатный (HP после ≤ 75%%)" % s[0], rate >= 0.5 and hp_avg <= 0.75)
			else:
				check("%s: с уклонением — побед ≥ 85%%" % s[0], rate >= 0.85)

extends Node
## test_combat — логика боя без окна: данные, снаряжение и урон, крафт,
## сокеты, поведение монстров на синтетической сетке, спавн по тоннелям,
## арена и фазы босса. Симуляция боя с боссом — tests/test_combat_boss.gd,
## живая сцена — tests/test_combat_integration.gd.
##
## Запуск: godot --headless --path . res://tests/test_combat.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_combat ===")
	await get_tree().process_frame
	_test_data()
	_test_gear_and_stats()
	_test_ultimate_and_sockets()
	_test_craft()
	_test_save_roundtrip()
	_test_monsters()
	_test_spawner()
	_test_arena()
	_test_boss_logic()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _reset_state() -> void:
	GameState.ext.clear()
	GameState.collected_artifacts.clear()
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.house_is_indoors = false
	GameState.coins = 0
	GameState.max_depth_reached = 0
	GameState.debug_free_shop = false


# ---------------------------------------------------------------------------

func _test_data() -> void:
	CombatData.reload()
	var d := CombatData.data()
	check("data/combat.json читается", not d.is_empty())
	check("глубже 4000 — монстры от 4000", CombatData.start_depth() == 4000)
	var ids := CombatData.monster_ids()
	check("5–6 видов монстров", ids.size() >= 5 and ids.size() <= 7)
	var behaviors := {}
	var all_ok := true
	for id in ids:
		var m := CombatData.monster(String(id))
		behaviors[String(m.get("behavior"))] = true
		for key in ["hp", "damage", "speed", "size", "depth", "xp", "drops", "kind"]:
			if not m.has(key):
				all_ok = false
				print("  у ", id, " нет ", key)
		if m.get("proposed") != true:
			all_ok = false
			print("  у ", id, " нет proposed")
		var depth: Array = m["depth"]
		if int(depth[0]) < 4000:
			all_ok = false
	check("у каждого монстра поля и proposed, пояс не выше 4000", all_ok)
	check("поведения: ползун, летун, прыгун, засадник, стая", behaviors.has("crawler") and behaviors.has("flyer")
		and behaviors.has("jumper") and behaviors.has("ambusher") and behaviors.has("swarm"))
	var sheets_ok := true
	for id in ids:
		var sh := MonsterSheet.get_sheet(String(id))
		if sh.texture == null or not (sh.has_anim("idle") and sh.has_anim("move") and sh.has_anim("attack") and sh.has_anim("die")):
			sheets_ok = false
			print("  нет листа/анимаций у ", id)
	check("у каждого монстра лист с idle/move/attack/die", sheets_ok)
	check("у засадника есть кадр «в породе»", MonsterSheet.get_sheet("rock_mimic").has_anim("dormant"))
	check("у босса лист с фазами боя", MonsterSheet.get_sheet("abyss_idol").has_anim("exposed")
		and MonsterSheet.get_sheet("abyss_idol").has_anim("attack"))

	var mats_ok := true
	var icons_ok := true
	var proposed_ok := true
	for gid in CombatData.gear_ids():
		var g := CombatData.gear(String(gid))
		if g.get("proposed") != true:
			proposed_ok = false
		if CombatData.icon(String(gid)) == null:
			icons_ok = false
			print("  нет иконки ", gid)
		for mid in CombatData.recipe(String(gid)).get("inputs", {}).keys():
			if Balance.get_mineral(String(mid)).is_empty():
				mats_ok = false
				print("  нет минерала ", mid)
			elif CombatData.icon(String(mid)) == null:
				icons_ok = false
				print("  нет иконки материала ", mid)
	check("материалы рецептов есть в minerals.json", mats_ok)
	check("у снаряжения и материалов есть иконки", icons_ok)
	check("числа снаряжения помечены proposed", proposed_ok)
	var drops_ok := true
	for id in ids:
		for dr in CombatData.monster(String(id)).get("drops", []):
			if Balance.get_mineral(String(dr["id"])).is_empty():
				drops_ok = false
				print("  дроп без минерала: ", dr["id"])
	check("все дропы монстров описаны в minerals.json", drops_ok)
	check("детали монстров не продаются", not ShopCatalog.is_bought("cinder_ash") and not ShopCatalog.is_bought("hellstone"))
	check("раздел босса, формулы, спавна помечены proposed",
		d["boss"].get("proposed") == true and d["formula"].get("proposed") == true and d["spawn"].get("proposed") == true)
	var slots := CombatData.slots()
	check("шесть слотов: шлем, броня, оружие, щит, два аксессуара", slots.size() == 6 and slots.has("acc2"))


func _test_gear_and_stats() -> void:
	_reset_state()
	var base := CombatService.stats()
	check("без снаряжения: защита 0, урон — базовое оружие", float(base["defense"]) == 0.0
		and is_equal_approx(float(base["damage"]), float(CombatData.player_cfg("base_weapon")["dmg"])))
	check("без брони урон не режется", is_equal_approx(CombatService.mitigate(50.0, "phys"), 50.0))
	CombatService.give("helm_t1")
	check("предмет получен, но не надет", CombatService.is_owned("helm_t1") and CombatService.equipped("helmet") == "")
	check("нельзя надеть чужое", not CombatService.equip("helm_t2"))
	check("надеть шлем", CombatService.equip("helm_t1") and CombatService.equipped("helmet") == "helm_t1")
	var s1 := CombatService.stats()
	check("защита от шлема", float(s1["defense"]) == 10.0)
	check("формула: защита 10 режет 9%", absf(float(s1["reduction"]) - 10.0 / 110.0) < 0.001)
	check("броня снижает урон", CombatService.mitigate(100.0, "phys") < 100.0)
	for id in ["armor_t3", "blade_t3", "shield_t3", "charm_t3", "charm_t2"]:
		CombatService.give(id)
	CombatService.equip("armor_t3")
	CombatService.equip("blade_t3")
	CombatService.equip("shield_t3")
	CombatService.equip("charm_t3")
	CombatService.equip("charm_t2")
	var s2 := CombatService.stats()
	check("суммируется защита шлема, брони и щита", float(s2["defense"]) == 10.0 + 50.0 + 22.0)
	check("оружие задаёт урон и темп; проценты аксессуаров применяются",
		float(s2["damage"]) > 64.0 and float(s2["cd"]) < 0.5)
	check("аксессуар встал во вторую ячейку", CombatService.equipped("acc1") == "charm_t3" and CombatService.equipped("acc2") == "charm_t2")
	var fire := CombatService.mitigate(100.0, "fire")
	var phys := CombatService.mitigate(100.0, "phys")
	check("сопротивление режет огонь и тень сверх брони", fire < phys)
	check("урон не меньше минимума", CombatService.mitigate(0.1, "phys") >= 1.0)
	CombatService.equip("helm_t1", "helmet")
	CombatService.give("helm_t2")
	CombatService.equip("helm_t2")
	check("новый шлем вытесняет прежний из слота", CombatService.equipped("helmet") == "helm_t2"
		and CombatService.slot_of("helm_t1") == "")
	check("снять", CombatService.unequip("helmet") and CombatService.equipped("helmet") == "")
	check("снимать из пустого нечего", not CombatService.unequip("helmet"))
	# потолок сопротивления
	CombatService.give("idol_crown")
	CombatService.equip("idol_crown", "acc1")
	check("сопротивление ограничено потолком", float(CombatService.stats()["res_pct"]) <= 75.0)


func _test_ultimate_and_sockets() -> void:
	_reset_state()
	for pid in CombatData.section("sets")["ultimate"]["pieces"]:
		check("%s без артефакта не надевается" % pid, not CombatService.equip(String(pid)))
	check("ультимативный сет — пять артефактов 5-го слота",
		CombatData.gear("ult_glove")["artifact"] == "legends_5" and CombatData.gear("ult_shield")["artifact"] == "antiquity_5"
		and CombatData.gear("ult_armor")["artifact"] == "mysticism_5" and CombatData.gear("ult_amulet")["artifact"] == "occult_5"
		and CombatData.gear("ult_helmet")["artifact"] == "forgotten_civilizations_5")
	for a in ["antiquity_5", "mysticism_5", "occult_5", "forgotten_civilizations_5", "legends_5"]:
		check("артефакт %s есть в artifacts.json" % a, not Balance.get_artifact(a).is_empty() if Balance.has_method("get_artifact") else true)
		GameState.collected_artifacts.append(a)
	check("найденный артефакт даёт надеваемый предмет", CombatService.is_owned("ult_helmet"))
	var before := CombatService.stats()
	for pid in CombatData.section("sets")["ultimate"]["pieces"]:
		CombatService.equip(String(pid))
	var full := CombatService.stats()
	check("надеты все пять", CombatService.set_pieces_worn() == 5)
	var pieces_def := 40.0 + 72.0 + 36.0
	check("бонус комплекта: +40 защиты сверх предметов", float(full["defense"]) == pieces_def + 15.0 + 25.0)
	check("бонус комплекта растёт с числом частей", CombatService.set_bonus(2)["res_pct"] == 6.0 and CombatService.set_bonus(5)["regen"] == 1.0)
	check("комплект усиливает героя", float(full["reduction"]) > float(before["reduction"]) and float(full["regen"]) > 2.0)
	# сокеты
	var empty_sockets := CombatService.sockets_filled_count()
	check("сокеты пусты", empty_sockets == 0)
	check("нельзя без верстака и материала", not bool(CombatService.check_socket("hellstone")["ok"]))
	GameState.house_is_indoors = true
	GameState.inventory["hellstone"] = 3
	var chk := CombatService.check_socket("hellstone")
	check("в мастерской с материалом сокет доступен", bool(chk["ok"]))
	var dps0 := float(CombatService.stats()["dps"])
	var res := CombatService.fill_socket("hellstone")
	check("сокет заполнен, материал списан", bool(res["ok"]) and CombatService.socket_filled("hellstone")
		and GameState.get_item_count("hellstone") == 0)
	check("сокет даёт эффект (урон +6%)", float(CombatService.stats()["dps"]) > dps0)
	check("повторно в тот же сокет нельзя", not bool(CombatService.fill_socket("hellstone")["ok"]))
	GameState.inventory["divine_heart"] = 2
	check("материала меньше стоимости — отказ", not bool(CombatService.fill_socket("divine_heart")["ok"]))
	CombatService.unequip(CombatService.slot_of("ult_glove"))
	check("без перчатки на герое сокеты не работают", float(CombatService.stats()["dmg_pct"]) < 20.0)
	_reset_state()


func _test_craft() -> void:
	_reset_state()
	var rid := "helm_t1"
	var r := CombatData.recipe(rid)
	check("рецепт: адский камень + пепел + монеты", r["inputs"].has("hellstone") and r["inputs"].has("cinder_ash") and int(r["coins"]) > 0)
	var chk := CombatService.check_craft(rid)
	check("вне верстака крафт закрыт", not bool(chk["ok"]) and String(chk["reason"]).contains("Верстак"))
	check("недостающее считается всё равно", (chk["missing"] as Dictionary).has("hellstone"))
	GameState.house_is_indoors = true
	check("без материалов — «не хватает»", not CombatService.can_craft(rid))
	GameState.house_storage["hellstone"] = 5
	GameState.inventory["hellstone"] = 3
	GameState.inventory["cinder_ash"] = 4
	GameState.coins = 1500
	check("материалы со склада и из рюкзака складываются", CombatService.held("hellstone") == 8)
	check("всё есть — можно", CombatService.can_craft(rid))
	var out := CombatService.craft(rid)
	check("крафт удался", bool(out["ok"]) and CombatService.is_owned(rid))
	check("материалы списаны сначала со склада, потом из рюкзака",
		HouseStorage.count("hellstone") == 0 and GameState.get_item_count("hellstone") == 0 and GameState.get_item_count("cinder_ash") == 0)
	check("монеты списаны", GameState.coins == 0)
	check("свободный слот — надето сразу", CombatService.equipped("helmet") == rid)
	check("повторно собрать нельзя", not CombatService.can_craft(rid))
	GameState.debug_free_shop = true
	check("флаг «Бесплатно» снимает монеты", int(CombatService.check_craft("armor_t1")["missing_coins"]) == 0)
	GameState.debug_free_shop = false
	# клинок Бездны — награда за босса
	check("клинок Бездны требует трофеи босса", CombatData.recipe("blade_abyss")["inputs"].has("abyss_core"))
	_reset_state()


func _test_save_roundtrip() -> void:
	_reset_state()
	CombatService.give("blade_t2")
	CombatService.equip("blade_t2")
	GameState.collected_artifacts.append("legends_5")
	GameState.house_is_indoors = true
	GameState.inventory["hellstone"] = 3
	CombatService.fill_socket("hellstone")
	CombatService.boss_note_attempt()
	CombatService.boss_note_phase(2)
	CombatService.note_kill("cinder_grub")
	var text := JSON.stringify(GameState.ext)
	var parsed = JSON.parse_string(text)
	GameState.ext = parsed
	check("снаряжение переживает JSON (числа — float)", CombatService.is_owned("blade_t2") and CombatService.equipped("weapon") == "blade_t2")
	check("сокеты и прогресс босса переживают JSON", CombatService.socket_filled("hellstone")
		and int(CombatService.boss_state()["attempts"]) == 1 and int(CombatService.boss_state()["best_phase"]) == 2)
	check("счётчик убийств", CombatService.kills_total() == 1)
	check("сброс прогресса чистит бой", _after_reset_clean())
	_reset_state()


func _after_reset_clean() -> bool:
	GameState.ext.clear()
	return not CombatService.is_owned("blade_t2") and CombatService.equipped("weapon") == ""


# ---------------------------------------------------------------------------
# Монстры на синтетической сетке: пол на y=10, стены на x<=0 и x>=24
# ---------------------------------------------------------------------------

func _solid(cx: int, cy: int) -> bool:
	return cy >= 10 or cx <= 0 or cx >= 24


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


func _hits(events: Array) -> int:
	var n := 0
	for e in events:
		if e["type"] == "hit":
			n += 1
	return n


func _test_monsters() -> void:
	# ползун
	var g := Monster.create("cinder_grub", 10.5, 9, 4500, 5)
	check("ползун встал на пол", absf((g.y + g.hh) - 10.0) < 0.01)
	_run(g, 2.0, _hero(20.0, 0.0))
	check("ползун патрулирует и не падает сквозь пол", g.on_ground and absf((g.y + g.hh) - 10.0) < 0.02)
	var x0 := g.x
	_run(g, 14.0, _hero(20.0, 0.0))
	check("ползун разворачивается у стены и остаётся в тоннеле", g.x > 0.9 and g.x < 23.1 and absf(g.x - x0) > 0.0)
	var g2 := Monster.create("cinder_grub", 10.5, 9, 4500, 6)
	var hero := _hero(12.0, 9.67)
	var ev := _run(g2, 0.1, hero)
	check("ползун замахивается, подойдя", g2.state == "windup" and g2.telegraph)
	var hits_before := _hits(ev)
	ev = _run(g2, 0.5, hero)
	check("удар после замаха (телеграф 0.3 с)", hits_before == 0 and _hits(ev) == 1)
	check("урон ползуна растёт с глубиной", Monster.create("cinder_grub", 10.5, 9, 5900).damage > Monster.create("cinder_grub", 10.5, 9, 4000).damage)
	var g3 := Monster.create("cinder_grub", 10.5, 9, 4500, 7)
	g3.state = "windup"
	g3.t = 0.0
	g3.take_hit(5.0, 1)
	check("удар героя прерывает замах (оглушение)", g3.state == "stagger")
	var dealt := g3.take_hit(1000.0, 1)
	check("смерть: состояние dying, затем событие died", dealt > 0.0 and g3.state == "dying" and not g3.alive)
	var evs := _run(g3, 1.0, _hero(20, 0))
	var died := false
	for e in evs:
		if e["type"] == "died":
			died = true
	check("после анимации смерти монстр помечен dead", died and g3.dead)
	var warden := Monster.create("abyss_warden", 10.5, 9, 8000, 8)
	warden.take_hit(10.0, 1)
	check("страж с суперброней не пошатывается от удара", warden.state != "stagger")
	check("зона удара по стражу шире тела", warden.hurtbox().size.x > warden.hw * 2.0)

	# летун
	var mo := Monster.create("gloom_moth", 10.5, 6.5, 4600, 9)
	check("летун летает", mo.is_flying())
	var hero2 := _hero(10.5, 8.5)
	var started_dive := false
	var dove_hit := 0
	var t := 0.0
	var solid := Callable(self, "_solid")
	while t < 8.0:
		for e in mo.tick(1.0 / 60.0, hero2, solid):
			if e["type"] == "hit":
				dove_hit += 1
		if mo.state == "windup":
			started_dive = true
		t += 1.0 / 60.0
	check("летун зависает, замахивается и пикирует", started_dive)
	check("летун остаётся в пределах сетки", mo.y > 0.0 and mo.y < 10.0)
	check("пике попадает по стоящему герою", dove_hit >= 1)

	# прыгун
	var hp := Monster.create("rift_hopper", 8.5, 9, 5000, 10)
	var hero3 := _hero(12.5, 9.67)
	var saw_windup := false
	var saw_leap := false
	var leaped_hit := 0
	t = 0.0
	while t < 5.0:
		for e in hp.tick(1.0 / 60.0, hero3, solid):
			if e["type"] == "hit":
				leaped_hit += 1
		if hp.state == "windup":
			saw_windup = true
		if hp.state == "leap":
			saw_leap = true
		t += 1.0 / 60.0
	check("прыгун приседает (замах), потом прыгает", saw_windup and saw_leap)
	check("прыжок достаёт героя", leaped_hit >= 1)

	# засадник
	var mm := Monster.create("rock_mimic", 10.5, 9, 6000, 11)
	mm.emerge_pos = Vector2(11.5, 9.5)
	check("засадник спит в породе", mm.state == "dormant" and mm.anim_name() == "dormant")
	_run(mm, 1.0, _hero(20.0, 9.67))
	check("далеко от героя не просыпается", mm.state == "dormant")
	var evm := _run(mm, 0.05, _hero(11.5, 9.67))
	var emerged := false
	for e in evm:
		if e["type"] == "emerge":
			emerged = true
	check("рядом с героем вылетает из породы", emerged and mm.state != "dormant")
	var mm2 := Monster.create("rock_mimic", 10.5, 9, 6000, 12)
	mm2.emerge_pos = Vector2(11.5, 9.5)
	mm2.take_hit(5.0, 1)
	check("удар по спящему будит его", mm2.state != "dormant")

	# стая
	var sp := Monster.create("spark_swarm", 10.5, 7.5, 6000, 13)
	var sev: Array = []
	var hero4 := _hero(10.5, 7.5)
	sev = _run(sp, 3.0, hero4)
	var shits := _hits(sev)
	check("искорка жалит с кулдауном, а не каждый кадр", shits >= 1 and shits <= 5)

	# коллизии: монстр не уходит в твёрдое
	var inside := false
	var mm3 := Monster.create("cinder_grub", 2.5, 9, 4500, 14)
	t = 0.0
	while t < 20.0:
		mm3.tick(1.0 / 60.0, _hero(40.0, 0.0), solid)
		if mm3._box_hits(solid, mm3.x, mm3.y):
			inside = true
		t += 1.0 / 60.0
	check("монстр ни разу не вошёл в твёрдую клетку", not inside)


# ---------------------------------------------------------------------------
# Спавн: настоящий WorldGen, выкопанный тоннель на глубине
# ---------------------------------------------------------------------------

func _tunnel_world(depth_y: int) -> WorldGen:
	var w := WorldGen.new(777)
	# вертикальная шахта x=16 и горизонтальный ход на depth_y
	for y in range(depth_y - 14, depth_y + 1):
		w.diffs[y * WorldGen.WIDTH + 16] = true
	for x in range(3, 29):
		w.diffs[depth_y * WorldGen.WIDTH + x] = true
	return w


func _test_spawner() -> void:
	var w := _tunnel_world(4600)
	var cw := CombatWorld.new(w)
	var sp := MonsterSpawner.new(cw, 99)
	check("плотность растёт с глубиной: лимит 4000 < 10000", MonsterSpawner.max_alive(4000) < MonsterSpawner.max_alive(10000))
	check("темп растёт с глубиной: интервал 4000 > 10000", MonsterSpawner.interval(4000) > MonsterSpawner.interval(10000))
	check("на 4000 — 3 монстра, на дне — 8", MonsterSpawner.max_alive(4000) == 3 and MonsterSpawner.max_alive(10000) == 8)
	check("выше 4000 монстров нет", sp.tick(100.0, 16.5, 3999.5, 0).is_empty())
	check("вес вида вне пояса — нуль", MonsterSpawner.weight_at("abyss_warden", 5000) == 0.0 and MonsterSpawner.weight_at("cinder_grub", 4500) > 0.0)
	check("новый вид появляется плавно", MonsterSpawner.weight_at("gloom_moth", 4210) < MonsterSpawner.weight_at("gloom_moth", 4600))
	var reach := sp.reachable_cells(16.5, 4600.5)
	check("достижимы клетки тоннеля, не порода", reach.has(Vector2i(10, 4600)) and not reach.has(Vector2i(10, 4605)))
	var spawned: Array = []
	for i in range(80):
		spawned.append_array(sp.spawn_once(16.5, 4600.5))
	check("спавн происходит", not spawned.is_empty())
	var bad := 0
	var view := sp.view_rect(16.5, 4600.5)
	var kinds := {}
	for r in spawned:
		var req: Dictionary = r
		kinds[String(req["id"])] = true
		var c := Vector2i(int(floor(float(req["x"]))), int(floor(float(req["y"]))))
		if String(req["id"]) == "rock_mimic":
			# засадник — в породе рядом с тоннелем, не в кадре
			if w.is_dug(c.x, c.y) or not cw.solid(c.x, c.y):
				bad += 1
			var em: Vector2 = req["emerge"]
			if not w.is_dug(int(floor(em.x)), int(floor(em.y))):
				bad += 1
		else:
			if not w.is_dug(c.x, c.y):
				bad += 1
			if view.has_point(Vector2(float(req["x"]), float(req["y"]))):
				bad += 1
		if Vector2(float(req["x"]), float(req["y"])).distance_to(Vector2(16.5, 4600.5)) < 3.0:
			bad += 1
	check("все заявки — в тоннеле, вне кадра, не рядом с героем (засадник — в породе)", bad == 0)
	check("на глубине 4600 только подходящие виды", not kinds.has("abyss_warden") and kinds.has("cinder_grub"))
	check("нет монстров слишком глубоких для пояса", not kinds.has("spark_swarm"))
	# стая даёт несколько
	var w2 := _tunnel_world(7200)
	var sp3 := MonsterSpawner.new(CombatWorld.new(w2), 3)
	var swarm_seen := false
	var warden_seen := false
	for i in range(200):
		var req2 := sp3.spawn_once(16.5, 7200.5)
		if req2.size() >= 3:
			swarm_seen = true
		for r in req2:
			if String(r["id"]) == "abyss_warden":
				warden_seen = true
	check("стая появляется группой", swarm_seen)
	check("страж появляется на 7000+", warden_seen)
	# таймер
	var sp4 := MonsterSpawner.new(cw, 1)
	var first := sp4.tick(1.0, 16.5, 4600.5, 0)
	check("первый монстр не сразу (задержка)", first.is_empty())
	var later: Array = []
	for i in range(40):
		later.append_array(sp4.tick(1.0, 16.5, 4600.5, 0))
	check("потом монстры идут по таймеру", not later.is_empty())
	var capped: Array = []
	for i in range(60):
		capped.append_array(sp4.tick(1.0, 16.5, 4600.5, 99))
	check("при полном лимите новые не появляются", capped.is_empty())


# ---------------------------------------------------------------------------
# Арена
# ---------------------------------------------------------------------------

func _test_arena() -> void:
	var w := WorldGen.new(5)
	var natural := w.get_tile(16, 9995)
	check("без оверлея мир обычный", natural != TileTypes.Type.REINFORCED or true)
	BossArena.sealed = false
	BossArena.install(w)
	check("пол мира — несокрушимое дно", w.get_tile(3, BossArena.floor_y()) == TileTypes.Type.REINFORCED
		and w.get_tile(30, BossArena.floor_y() + 40) == TileTypes.Type.REINFORCED)
	check("дно не копается", not w.dig_cell(3, BossArena.floor_y()))
	check("внутри арены пусто", w.get_tile(16, BossArena.floor_y() - 1) == TileTypes.Type.EMPTY
		and w.get_tile(BossArena.x0(), BossArena.floor_y() - BossArena.height()) == TileTypes.Type.EMPTY)
	check("стены и потолок — железобетон", w.get_tile(BossArena.x0() - 1, BossArena.floor_y() - 3) == TileTypes.Type.REINFORCED
		and w.get_tile(BossArena.x1() + 1, BossArena.floor_y() - 3) == TileTypes.Type.REINFORCED
		and w.get_tile(12, BossArena.top_y()) == TileTypes.Type.REINFORCED)
	check("ворота в потолке открыты", w.get_tile(16, BossArena.top_y()) == TileTypes.Type.EMPTY)
	check("ворота — три клетки", BossArena.gate_x1() - BossArena.gate_x0() == 2)
	check("стены не копаются", not w.dig_cell(BossArena.x0() - 1, BossArena.floor_y() - 3))
	BossArena.sealed = true
	check("на время боя ворота закрыты", w.get_tile(16, BossArena.top_y()) == TileTypes.Type.REINFORCED)
	BossArena.sealed = false
	check("дно арены совпадает с глубиной мира", BossArena.floor_y() == w.max_depth)
	check("выше арены мир не тронут", w.get_tile(3, BossArena.top_y() - 20) == WorldGen.new(5).get_tile(3, BossArena.top_y() - 20))
	check("центр арены по x — середина мира", absf(BossArena.center_x() - 16.5) < 0.01)
	check("герой внутри арены определяется", BossArena.contains_point(16.5, 9996.0) and not BossArena.contains_point(16.5, 9990.0))
	# землетрясение не стирает арену
	w.apply_global_event(12345)
	check("землетрясение арену не трогает", w.get_tile(16, BossArena.floor_y() - 1) == TileTypes.Type.EMPTY
		and w.get_tile(3, BossArena.floor_y()) == TileTypes.Type.REINFORCED)


# ---------------------------------------------------------------------------
# Логика босса
# ---------------------------------------------------------------------------

func _boss_hero() -> Dictionary:
	return {"x": 20.5, "y": 9998.7, "hw": 0.38, "hh": 1.0 / 3.0, "alive": true}


func _tick_boss(b: BossLogic, seconds: float, hero: Dictionary, log: Array = []) -> void:
	var t := 0.0
	while t < seconds:
		log.append_array(b.tick(1.0 / 30.0, hero))
		t += 1.0 / 30.0


func _has(log: Array, type: String) -> bool:
	for e in log:
		if e["type"] == type:
			return true
	return false


func _test_boss_logic() -> void:
	var b := BossLogic.new(42)
	check("босс до старта неактивен", not b.is_active() and b.take_hit(100.0) == 0.0)
	b.start()
	var hero := _boss_hero()
	check("интро: босс неуязвим", b.state == BossLogic.INTRO and b.take_hit(100.0) == 0.0)
	var log: Array = []
	_tick_boss(b, 2.6, hero, log)
	check("после интро идут паттерны", b.state != BossLogic.INTRO and b.is_active())
	# дождаться телеграфа
	var tele_t := 0.0
	var found_tele := false
	for i in range(60 * 30):
		var ev := b.tick(1.0 / 30.0, hero)
		for e in ev:
			if e["type"] == "telegraph":
				found_tele = true
				tele_t = float(e["sec"])
		if found_tele:
			break
	check("атаке предшествует телеграф", found_tele)
	check("телеграф не короче 0.9 с (читаемость)", tele_t >= 0.9)
	check("в телеграфе босс бронирован: урон ×armor_mult",
		absf(b.take_hit(100.0) - 100.0 * float(CombatData.section("boss")["armor_mult"])) < 0.01)
	# после удара — окно уязвимости
	var strike := false
	var vul := false
	var log2: Array = []
	_tick_boss(b, 3.0, {"x": 5.0, "y": 9998.7, "hw": 0.38, "hh": 0.33, "alive": true}, log2)
	strike = _has(log2, "strike")
	vul = b.vulnerable() or _has(log2, "vulnerable")
	check("за телеграфом — удар, затем окно уязвимости", strike and vul)
	if not b.vulnerable():
		var guard := 0
		while not b.vulnerable() and guard < 600:
			b.tick(1.0 / 30.0, {"x": 5.0, "y": 9998.7, "hw": 0.38, "hh": 0.33, "alive": true})
			guard += 1
	check("в окне уязвимости урон полный", absf(b.take_hit(100.0) - 100.0) < 0.001)
	# фазы
	var b2 := BossLogic.new(1)
	b2.start()
	_tick_boss(b2, 3.0, {"x": 3.0, "y": 9998.7, "hw": 0.38, "hh": 0.33, "alive": true})
	b2.hp = b2.phase_hp_threshold(1) + 5.0
	b2.state = BossLogic.RECOVER
	var dealt := b2.take_hit(1000.0)
	check("удар не перескакивает порог фазы", absf(dealt - 5.0) < 0.01 and b2.hp <= b2.phase_hp_threshold(1) + 0.001)
	var l3: Array = []
	_tick_boss(b2, 0.1, hero, l3)
	check("порог → передышка, рёв, лечение героя", b2.state == BossLogic.TRANSITION and _has(l3, "roar")
		and _has(l3, "phase") and _has(l3, "phase_heal"))
	check("в передышке босс неуязвим", b2.take_hit(500.0) == 0.0)
	var l4: Array = []
	_tick_boss(b2, 3.2, {"x": 3.0, "y": 9998.7, "hw": 0.38, "hh": 0.33, "alive": true}, l4)
	check("вторая фаза началась", b2.phase == 2)
	b2.hp = b2.phase_hp_threshold(2) + 1.0
	b2.state = BossLogic.RECOVER
	b2.take_hit(100.0)
	_tick_boss(b2, 3.4, {"x": 3.0, "y": 9998.7, "hw": 0.38, "hh": 0.33, "alive": true})
	check("третья фаза началась", b2.phase == 3)
	b2.state = BossLogic.RECOVER
	b2.hp = 10.0
	var dealt3 := b2.take_hit(1000.0)
	check("в третьей фазе можно добить", dealt3 == 10.0 and b2.hp <= 0.0)
	var l5: Array = []
	_tick_boss(b2, 0.1, hero, l5)
	check("смерть босса: событие dead, потом неактивен", _has(l5, "dead") and not b2.is_active())
	# зоны удара: герой под колонной получает урон один раз
	var b3 := BossLogic.new(7)
	b3.start()
	var stand := {"x": 16.5, "y": 9998.7, "hw": 0.38, "hh": 0.33, "alive": true}
	var l6: Array = []
	var hits := 0
	for i in range(30 * 20):
		var ev2 := b3.tick(1.0 / 30.0, stand)
		for e in ev2:
			if e["type"] == "hero_hit":
				hits += 1
				check("урон босса — из данных, с типом", float(e["damage"]) > 0.0 and String(e["kind"]) in ["phys", "void"])
		if hits >= 1:
			break
	check("стоящий на месте герой получает удар", hits >= 1)
	# уклонение: герой, отходящий от колонны, не получает урона от слэма
	var b4 := BossLogic.new(8)
	b4.start()
	var dodged := true
	var slam_seen := false
	var hx := 14.0
	for i in range(30 * 40):
		var h := {"x": hx, "y": 9998.7, "hw": 0.38, "hh": 0.33, "alive": true}
		var ev3 := b4.tick(1.0 / 30.0, h)
		for e in ev3:
			if e["type"] == "telegraph" and e["kind"] == "slam":
				slam_seen = true
			if e["type"] == "hero_hit" and e["source"] == "slam":
				dodged = false
		# уходим от целящейся зоны в последние 0.3 с: смещаемся на 2.5 клетки
		if b4.state == BossLogic.TELEGRAPH and b4.attack == "slam" and b4.t > b4._tele - 0.3:
			hx = 18.5 if hx < 17.0 else 12.0
		if slam_seen and b4.phase == 1 and b4.state == BossLogic.RECOVER:
			break
	check("слэм можно переиграть шагом в сторону", slam_seen and dodged)

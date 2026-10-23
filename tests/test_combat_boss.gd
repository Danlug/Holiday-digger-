extends Node
## test_combat_boss — расчёт боя с рейдбоссом: настоящий BossLogic против
## модели героя (data/combat.json → boss.hero_model: доля уклонений от каждого
## телеграфа, доля времени у тела босса, HP). Проверяет, что босс проходим при
## разумной экипировке и непроходим «голышом»: числа в данных подбираются
## по этой таблице. Печатает таблицу побед — её копируем в ГДД.
##
## Модель честная в одном: удар босса попадает ровно с вероятностью промаха
## игрока (1 − dodge), урон героя идёт через CombatService.mitigate. Не
## моделируются искорки второй и третьей фазы (их добивает автоатака за пару
## секунд) и ошибки позиционирования сверх uptime.
##
## Запуск: godot --headless --path . res://tests/test_combat_boss.tscn

const DT := 1.0 / 20.0
const SEEDS := 120
const TIME_CAP := 600.0

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
	print("=== test_combat_boss ===")
	await get_tree().process_frame
	CombatData.reload()
	var scenarios := [
		["без снаряжения", {}],
		["T1 полный (Пепел)", _tier_set(1)],
		["T2 полный (Тень)", _tier_set(2)],
		["T3 полный (Звёзды)", _tier_set(3)],
		["T4 полный (Свет)", _tier_set(4)],
		["T5 полный (Сердце)", _tier_set(5)],
		["ультимативный сет + клинок T3", _ultimate("blade_t3", false)],
		["ультимативный сет + клинок T5 + сокеты", _ultimate("blade_t5", true)],
		["только оружие T4, без брони", {"weapon": "blade_t4"}],
		["только броня T4, оружие — кирка", {"helmet": "helm_t4", "armor": "armor_t4", "shield": "shield_t4"}],
	]
	var results := {}
	print("%-44s %6s %8s %8s %8s %8s" % ["экипировка", "защита", "dps", "победы", "время,с", "HP ушло"])
	for sc in scenarios:
		var r := _run_scenario(String(sc[0]), sc[1])
		results[String(sc[0])] = r
		print("%-44s %6d %8.0f %7d%% %8.0f %8.0f" % [sc[0], int(r["defense"]), r["dps"], int(round(r["win"] * 100.0)), r["avg_time"], r["avg_hp_lost"]])

	check("«голышом» босса не победить (нет шансов)", results["без снаряжения"]["win"] < 0.02)
	check("T1 (первая броня 4000) — босс ещё не по зубам", results["T1 полный (Пепел)"]["win"] < 0.15)
	check("T2 — тоже рано", results["T2 полный (Тень)"]["win"] < 0.35)
	check("T3 — уже проходимо, но не гарантия", results["T3 полный (Звёзды)"]["win"] >= 0.5 and results["T3 полный (Звёзды)"]["win"] < 0.97)
	check("T4 — разумная экипировка проходит босса уверенно", results["T4 полный (Свет)"]["win"] >= 0.8)
	check("T5 — босс падает почти всегда", results["T5 полный (Сердце)"]["win"] >= 0.93)
	check("ультимативный сет с клинком T3 проходим", results["ультимативный сет + клинок T3"]["win"] >= 0.7)
	check("полный набор с сокетами — легко", results["ультимативный сет + клинок T5 + сокеты"]["win"] >= 0.95)
	check("броня без оружия не тянет (нужны оба)", results["только броня T4, оружие — кирка"]["win"] < 0.2)
	check("оружие без брони не тянет", results["только оружие T4, без брони"]["win"] < 0.6)
	check("бой с T4 длится не дольше 4 минут", results["T4 полный (Свет)"]["avg_time"] <= 240.0)
	check("бой с T5 короче, чем с T3", results["T5 полный (Сердце)"]["avg_time"] < results["T3 полный (Звёзды)"]["avg_time"])
	check("урон героя от босса осмыслен: удар слэма режется бронёй", _slam_with(0) > _slam_with_set(4) * 1.5)
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _tier_set(t: int) -> Dictionary:
	return {"helmet": "helm_t%d" % t, "armor": "armor_t%d" % t, "weapon": "blade_t%d" % t,
		"shield": "shield_t%d" % t, "acc1": "charm_t%d" % t}


func _ultimate(weapon: String, sockets: bool) -> Dictionary:
	return {"helmet": "ult_helmet", "armor": "ult_armor", "shield": "ult_shield", "acc1": "ult_amulet",
		"acc2": "ult_glove", "weapon": weapon, "_artifacts": true, "_sockets": sockets}


func _apply(equipped: Dictionary) -> void:
	GameState.ext.clear()
	GameState.collected_artifacts.clear()
	if equipped.get("_artifacts", false):
		for a in ["antiquity_5", "mysticism_5", "occult_5", "forgotten_civilizations_5", "legends_5"]:
			GameState.collected_artifacts.append(a)
	for k in equipped.keys():
		if String(k).begins_with("_"):
			continue
		var id := String(equipped[k])
		CombatService.give(id)
		CombatService.equip(id, String(k))
	if equipped.get("_sockets", false):
		for s in CombatService.socket_defs():
			CombatService.state()["sockets"][String(s["id"])] = true


func _slam_with(_x: int) -> float:
	_apply({})
	return CombatService.mitigate(float(CombatData.section("boss")["attacks"]["slam"]["damage"]), "phys")


func _slam_with_set(t: int) -> float:
	_apply(_tier_set(t))
	return CombatService.mitigate(float(CombatData.section("boss")["attacks"]["slam"]["damage"]), "phys")


func _run_scenario(_name: String, equipped: Dictionary) -> Dictionary:
	_apply(equipped)
	var st := CombatService.stats()
	var wins := 0
	var total_time := 0.0
	var total_lost := 0.0
	for seed_i in range(SEEDS):
		var r := _fight(st, 1000 + seed_i)
		if r["win"]:
			wins += 1
			total_time += float(r["time"])
		total_lost += float(r["hp_lost"])
	return {
		"win": float(wins) / float(SEEDS),
		"avg_time": total_time / maxf(1.0, float(wins)) if wins > 0 else TIME_CAP,
		"avg_hp_lost": total_lost / float(SEEDS),
		"defense": st["defense"],
		"dps": st["dps"],
	}


func _fight(st: Dictionary, seed_value: int) -> Dictionary:
	var model: Dictionary = CombatData.section("boss")["hero_model"]
	var dodge: Dictionary = model["dodge"]
	var uptime := float(model["uptime"])
	var max_hp := float(model["hp"])
	var hp := max_hp
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var boss := BossLogic.new(seed_value)
	boss.start()
	var spot_x := boss.center_x + 2.3
	var floor_y := boss.floor_y
	var hero := {"x": spot_x, "y": floor_y - 0.34, "hw": 0.38, "hh": 1.0 / 3.0, "alive": true}
	var dodged := false
	var dodge_until := -1.0
	var dodge_kind := ""
	var iframes := 0.0
	var since_hit := 99.0
	var t := 0.0
	var lost := 0.0
	var dps: float = float(st["dps"])
	var regen: float = float(CombatService.regen_per_sec())
	while t < TIME_CAP and boss.is_active():
		t += DT
		iframes = maxf(0.0, iframes - DT)
		since_hit += DT
		# герой возвращается на позицию, когда уклонение кончилось
		if t > dodge_until:
			hero["x"] = spot_x
			hero["y"] = floor_y - 0.34
		for e in boss.tick(DT, hero):
			match String(e["type"]):
				"telegraph":
					var k := String(e["kind"])
					if dodge.has(k):
						dodged = rng.randf() < float(dodge[k])
						dodge_kind = k
				"strike":
					var kind := String(e["kind"])
					if dodged and dodge.has(kind):
						dodge_until = t + 1.3
						match kind:
							"slam":
								var rect := (boss.hazards[0]["rect"]) as Rect2
								hero["x"] = rect.get_center().x + (rect.size.x / 2.0 + 1.2) * (1.0 if rect.get_center().x < boss.right - 3.0 else -1.0)
							"rain":
								hero["x"] = _safe_x(boss, rng)
							"wave":
								hero["y"] = floor_y - 1.9
				"hero_hit":
					if iframes <= 0.0:
						var dmg := CombatService.mitigate(float(e["damage"]), String(e["kind"]), st)
						hp -= dmg
						lost += dmg
						iframes = 0.5
						since_hit = 0.0
				"phase_heal":
					hp = minf(max_hp, hp + max_hp * float(e["pct"]))
		if hp <= 0.0:
			return {"win": false, "time": t, "hp_lost": lost}
		# герой бьёт, когда рядом с телом (uptime — доля времени у тела)
		if boss.state != BossLogic.INTRO and boss.state != BossLogic.TRANSITION:
			boss.take_hit(dps * uptime * DT)
		if since_hit > float(CombatData.player_cfg("regen_delay_sec", 6.0)):
			hp = minf(max_hp, hp + regen * DT)
	return {"win": not boss.is_active() and boss.hp <= 0.0, "time": t, "hp_lost": lost}


func _safe_x(boss: BossLogic, rng: RandomNumberGenerator) -> float:
	for i in range(40):
		var x := boss.left + 0.5 + float(rng.randi() % int(boss.right - boss.left))
		var ok := true
		for hz in boss.hazards:
			var r: Rect2 = hz["rect"]
			if absf(x - r.get_center().x) < r.size.x / 2.0 + 0.55:
				ok = false
		if ok:
			return x
	return boss.left + 0.5

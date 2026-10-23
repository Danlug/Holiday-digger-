class_name BossLogic
extends RefCounted
## BossLogic — рейдбосс «Идол Бездны»: фазы, паттерны, телеграфы и окна
## уязвимости без узлов и без окна (рисует CombatDirector, число HP и
## тайминги — data/combat.json → boss). Так же боссом управляет симуляция боя в
## tests/test_combat_boss.gd.
##
## Ритм боя — «приманка, уклонение, наказание»:
##   gap → telegraph (1 с: красная зона на полу) → strike (удар) → recover
##   (окно уязвимости: ядро открыто, урон ×1, иначе ×armor_mult).
## Три фазы по порогам HP; между фазами — передышка: босс неуязвим, героя
## подлечивает (phase_heal_pct). Паттерн каждой фазы — циклический список.
##
## Координаты — клетки (как у героя). Зона удара — Rect2 в клетках; герой
## задевается, если его хитбокс пересёк активную зону (раз за зону).

const GAP := "gap"
const TELEGRAPH := "telegraph"
const STRIKE := "strike"
const RECOVER := "recover"
const TRANSITION := "transition"
const INTRO := "intro"
const IDLE := "idle"
const DEAD := "dead"

var cfg: Dictionary = {}
var max_hp: float = 1.0
var hp: float = 1.0
var phase: int = 1
var state: String = IDLE
var t: float = 0.0
var attack: String = ""
var hazards: Array = []
var rng := RandomNumberGenerator.new()
var center_x: float = 16.5
var floor_y: float = 10000.0
var ceiling_y: float = 9992.0
var left: float = 10.0
var right: float = 23.0

var _turn: Array = []
var _turn_i: int = 0
var _pattern_i: int = 0
var _tele: float = 1.0
var _phase_cycle: int = 0


func _init(seed_value: int = 0) -> void:
	cfg = CombatData.section("boss")
	max_hp = float(CombatData.v(cfg.get("hp"), 9000))
	hp = max_hp
	var a := BossArena.interior()
	left = a.position.x
	right = a.position.x + a.size.x
	floor_y = a.position.y + a.size.y
	ceiling_y = a.position.y
	center_x = BossArena.center_x()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func start() -> void:
	state = INTRO
	t = 0.0
	hp = max_hp
	phase = 1
	hazards.clear()
	_pattern_i = 0


func is_active() -> bool:
	return state != IDLE and state != DEAD


func vulnerable() -> bool:
	return state == RECOVER


## Кто бьёт и что видно игроку: размер тела из данных.
func hurtbox() -> Rect2:
	var s: Array = cfg.get("size", [3.4, 3.3])
	return Rect2(center_x - float(s[0]) / 2.0, floor_y - float(s[1]), float(s[0]), float(s[1]))


func in_reach(box: Rect2) -> bool:
	var pad := float(cfg.get("reach_pad", 0.3))
	return hurtbox().grow(pad).intersects(box)


func phase_hp_threshold(p: int) -> float:
	var arr: Array = cfg.get("phase_hp", [0.66, 0.33])
	return float(arr[p - 1]) * max_hp if p >= 1 and p <= arr.size() else 0.0


func _tele_sec() -> float:
	return float((cfg.get("telegraph_sec", [1.0]) as Array)[mini(phase - 1, 2)])


func _recover_sec() -> float:
	return float((cfg.get("recover_sec", [2.0]) as Array)[mini(phase - 1, 2)])


func _atk(kind: String) -> Dictionary:
	return (cfg.get("attacks", {}) as Dictionary).get(kind, {})


# ---------------------------------------------------------------------------
# Урон по боссу
# ---------------------------------------------------------------------------

## Возвращает реально снятые HP. Неуязвим в интро, передышке и после смерти.
func take_hit(amount: float) -> float:
	if state == IDLE or state == INTRO or state == TRANSITION or state == DEAD or amount <= 0.0:
		return 0.0
	var dealt := amount if vulnerable() else amount * float(cfg.get("armor_mult", 0.2))
	var floor_hp := 0.0
	if phase < 3:
		floor_hp = phase_hp_threshold(phase)
	dealt = minf(dealt, hp - floor_hp) if hp - floor_hp > 0.0 else 0.0
	if hp <= floor_hp and phase < 3:
		return 0.0
	hp -= dealt
	return dealt


# ---------------------------------------------------------------------------
# Тик
# ---------------------------------------------------------------------------

## hero: {x, y, hw, hh, alive}. Возвращает события:
##   intro, roar, phase{phase}, phase_heal{pct}, telegraph{kind, rects},
##   strike{kind}, hero_hit{damage, kind, source}, summon{id, count, x, y},
##   vulnerable{on}, dead.
func tick(dt: float, hero: Dictionary) -> Array:
	var ev: Array = []
	if state == IDLE or state == DEAD:
		return ev
	t += dt

	# пороги фаз и смерть (после удара героя)
	if hp <= 0.0 and state != DEAD:
		state = DEAD
		hazards.clear()
		ev.append({"type": "vulnerable", "on": false})
		ev.append({"type": "dead"})
		return ev
	if state != TRANSITION and phase < 3 and hp <= phase_hp_threshold(phase) + 0.001:
		_enter_transition(ev)

	match state:
		INTRO:
			if t >= float(cfg.get("intro_sec", 2.5)):
				_next_turn(ev)
		TRANSITION:
			if t >= float(cfg.get("transition_sec", 3.0)):
				phase += 1
				_pattern_i = 0
				_next_turn(ev)
		GAP:
			if t >= float(cfg.get("gap_sec", 0.5)):
				_begin_attack(ev, hero)
		TELEGRAPH:
			_tick_hazards(dt, hero, ev)
			if t >= _tele:
				_fire_attack(ev)
		STRIKE:
			_tick_hazards(dt, hero, ev)
			if _all_done():
				_after_strike(ev, hero)
		RECOVER:
			if t >= _recover_sec():
				ev.append({"type": "vulnerable", "on": false})
				_next_turn(ev)
	return ev


func _enter_transition(ev: Array) -> void:
	state = TRANSITION
	t = 0.0
	hazards.clear()
	attack = ""
	ev.append({"type": "vulnerable", "on": false})
	ev.append({"type": "roar"})
	ev.append({"type": "phase", "phase": phase + 1})
	ev.append({"type": "phase_heal", "pct": float(cfg.get("phase_heal_pct", 0.25))})


## Строит очередь атак очередного хода и переходит в gap.
func _next_turn(_ev: Array) -> void:
	var pats: Array = cfg.get("pattern", [])
	var cycle: Array = pats[mini(phase - 1, pats.size() - 1)]
	var name := String(cycle[_pattern_i % cycle.size()])
	_pattern_i += 1
	_turn = Array(name.split("_")) if name.contains("_") else [name]
	_turn_i = 0
	state = GAP
	t = 0.0


func _begin_attack(ev: Array, hero: Dictionary) -> void:
	attack = String(_turn[_turn_i])
	state = TELEGRAPH
	t = 0.0
	# сразу за первой атакой комбо телеграф короче — иначе «комбо» не комбо
	_tele = _tele_sec() * (0.8 if _turn_i > 0 else 1.0)
	hazards.clear()
	var a := _atk(attack)
	var hx := float(hero.get("x", center_x))
	var rects: Array = []
	match attack:
		"slam":
			var w := float(a.get("width", 1.7))
			hazards.append({"kind": "slam", "rect": _column(hx, w), "warn": _tele, "active": float(a.get("strike_sec", 0.3)),
				"damage": float(a.get("damage", 90)), "dmg_kind": String(a.get("kind", "phys")),
				"aim": true, "lock": float(a.get("lock_before", 0.35)), "done": false, "fired": false, "hit": false})
		"rain":
			var n := int((a.get("count", [4, 6, 8]) as Array)[mini(phase - 1, 2)])
			var cols := _random_columns(n - 1, hx, float(a.get("width", 1.0)))
			for cx in cols:
				hazards.append({"kind": "rain", "rect": _column(cx, float(a.get("width", 1.0))), "warn": _tele,
					"active": float(a.get("strike_sec", 0.25)), "damage": float(a.get("damage", 48)),
					"dmg_kind": String(a.get("kind", "phys")), "aim": false, "lock": 0.0,
					"done": false, "fired": false, "hit": false})
			# одна капля целится в героя: стоять на месте нельзя
			hazards.append({"kind": "rain", "rect": _column(hx, float(a.get("width", 1.0))), "warn": _tele,
				"active": float(a.get("strike_sec", 0.25)), "damage": float(a.get("damage", 48)),
				"dmg_kind": String(a.get("kind", "phys")), "aim": true, "lock": 0.4,
				"done": false, "fired": false, "hit": false})
		"wave":
			var h := float(a.get("height", 0.9))
			for dir in [-1, 1]:
				var x0 := center_x + float(dir) * (float(cfg.get("size", [3.4, 3.3])[0]) / 2.0)
				hazards.append({"kind": "wave", "dir": dir, "x": x0, "h": h, "speed": float(a.get("speed", 7.0)),
					"rect": Rect2(x0 - 0.45, floor_y - h, 0.9, h), "warn": _tele, "active": 99.0,
					"damage": float(a.get("damage", 66)), "dmg_kind": String(a.get("kind", "void")),
					"aim": false, "lock": 0.0, "done": false, "fired": false, "hit": false})
		"summon":
			pass
	for hz in hazards:
		rects.append(hz["rect"])
	ev.append({"type": "telegraph", "kind": attack, "rects": rects, "sec": _tele})
	if attack == "wave" or attack == "slam":
		ev.append({"type": "roar_soft"})


func _fire_attack(ev: Array) -> void:
	state = STRIKE
	t = 0.0
	ev.append({"type": "strike", "kind": attack})
	if attack == "summon":
		var a := _atk("summon")
		var n := int((a.get("count", [0, 2, 3]) as Array)[mini(phase - 1, 2)])
		ev.append({"type": "summon", "id": String(a.get("monster", "spark_swarm")), "count": n,
			"x": center_x, "y": floor_y - float(cfg.get("size", [3.4, 3.3])[1]) * 0.8})


func _after_strike(ev: Array, _hero: Dictionary) -> void:
	_turn_i += 1
	if _turn_i < _turn.size():
		_begin_attack(ev, _hero)
		return
	state = RECOVER
	t = 0.0
	attack = ""
	hazards.clear()
	ev.append({"type": "vulnerable", "on": true})


func _all_done() -> bool:
	if attack == "summon":
		return t >= 0.4
	for hz in hazards:
		if not bool(hz["done"]):
			return false
	return true


func _column(cx: float, w: float) -> Rect2:
	var x := clampf(cx - w / 2.0, left, right - w)
	return Rect2(x, ceiling_y, w, floor_y - ceiling_y)


func _random_columns(n: int, avoid_x: float, w: float) -> Array:
	var out: Array = []
	var tries := 0
	while out.size() < n and tries < 80:
		tries += 1
		var cx := left + 0.5 + float(rng.randi() % int(right - left))
		var ok := true
		for o in out:
			if absf(float(o) - cx) < w + 0.2:
				ok = false
		if absf(cx - avoid_x) < 0.8:
			ok = false
		if ok:
			out.append(cx)
	return out


func _tick_hazards(dt: float, hero: Dictionary, ev: Array) -> void:
	var hb := Rect2(float(hero["x"]) - float(hero.get("hw", 0.38)), float(hero["y"]) - float(hero.get("hh", 0.33)),
		float(hero.get("hw", 0.38)) * 2.0, float(hero.get("hh", 0.33)) * 2.0)
	var alive := bool(hero.get("alive", true))
	for hz in hazards:
		if bool(hz["done"]):
			continue
		if not bool(hz["fired"]):
			hz["warn"] = float(hz["warn"]) - dt
			# целящиеся зоны ведут героя до последних lock секунд, потом замирают
			if bool(hz["aim"]) and float(hz["warn"]) > float(hz["lock"]) and hz["kind"] != "wave":
				hz["rect"] = _column(float(hero["x"]), (hz["rect"] as Rect2).size.x)
			if state == STRIKE:
				hz["fired"] = true
				hz["warn"] = 0.0
			else:
				continue
		# активная фаза
		hz["active"] = float(hz["active"]) - dt
		if hz["kind"] == "wave":
			var nx: float = float(hz["x"]) + float(hz["dir"]) * float(hz["speed"]) * dt
			hz["x"] = nx
			hz["rect"] = Rect2(nx - 0.45, floor_y - float(hz["h"]), 0.9, float(hz["h"]))
			if nx < left - 1.0 or nx > right + 1.0:
				hz["done"] = true
		elif float(hz["active"]) <= 0.0:
			hz["done"] = true
		if alive and not bool(hz["hit"]) and (hz["rect"] as Rect2).intersects(hb):
			hz["hit"] = true
			ev.append({"type": "hero_hit", "damage": float(hz["damage"]), "kind": String(hz["dmg_kind"]), "source": String(hz["kind"])})

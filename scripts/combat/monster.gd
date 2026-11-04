class_name Monster
extends RefCounted
## Monster — один монстр: данные и поведение без узлов (рисует CombatDirector).
## Координаты в клетках, как у героя: (x, y) — центр хитбокса, y вниз.
##
## Поведения (data/combat.json → behavior):
##   crawler  — ползун/страж: патруль по полу, погоня, замах и удар в упор;
##   flyer    — летун: висит рядом, замах, пике по прямой, отход;
##   jumper   — прыгун: приседает (замах) и прыгает, в полёте не отменить;
##   ambusher — засадник: замурован в породе, просыпается рядом, дальше ползун;
##   swarm    — стая: мелкие летуны кружат и жалят по таймеру;
##   shooter  — стрелок (раунд 5): держит дистанцию, раздувается (замах) и
##              плюёт снарядом по дуге — событие "shoot", снаряд ведёт Projectile.
## Удар всегда предваряется замахом (windup) — это и телеграф, и окно для
## уклонения. tick() возвращает события, а не трогает героя сам: так поведение
## проверяется в тестах без окна и без GameState.
##
## Поводок (раунд 5, стражи полостей): у монстра с home/leash есть дом — он не
## замечает героя дальше aggro от дома и, уйдя дальше leash, возвращается
## (состояние "return"), не глядя на героя. Без поводка поведение прежнее.

const GRAVITY := 16.0
const V_TERM := 20.0
const EPS := 0.001

var id: String = ""
var def: Dictionary = {}
var x: float = 0.0
var y: float = 0.0
var hw: float = 0.45
var hh: float = 0.3
var vx: float = 0.0
var vy: float = 0.0
var facing: int = 1
var hp: float = 1.0
var max_hp: float = 1.0
var damage: float = 1.0
var kind: String = "phys"
var behavior: String = "crawler"
var state: String = "patrol"
var t: float = 0.0
var on_ground: bool = false
var alive: bool = true
var dead: bool = false
var flash: float = 0.0
var stun: float = 0.0
var kvx: float = 0.0
var cd: float = 0.0
var telegraph: bool = false
var group: int = 0
var depth: int = 0
var emerge_pos: Vector2 = Vector2.ZERO
var anim_t: float = 0.0
var rng := RandomNumberGenerator.new()
## Поводок стража полости: дом, радиус поводка и агро (0 — поводка нет).
var home: Vector2 = Vector2.INF
var leash: float = 0.0
var aggro: float = 0.0
var cave_id: String = ""
var guard_index: int = -1

var _hit_done: bool = false
var _phase: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _dir: int = 1


## Создаёт монстра вида id в точке (cx, cy) — центр клетки с поправкой на
## хитбокс: ноги ставятся на нижнюю грань клетки.
static func create(mid: String, cx: float, cy: float, at_depth: int, seed_value: int = 0) -> Monster:
	var m := Monster.new()
	m.id = mid
	m.def = CombatData.monster(mid)
	var size: Array = m.def.get("size", [0.8, 0.6])
	m.hw = float(size[0]) / 2.0
	m.hh = float(size[1]) / 2.0
	m.behavior = String(m.def.get("behavior", "crawler"))
	m.kind = String(m.def.get("kind", "phys"))
	m.depth = at_depth
	m.max_hp = float(m.def.get("hp", 30)) * CombatData.hp_mult(mid, at_depth)
	m.hp = m.max_hp
	m.damage = float(m.def.get("damage", 5)) * CombatData.dmg_mult(mid, at_depth)
	m.rng.seed = seed_value if seed_value != 0 else randi()
	m.x = cx
	m.y = floorf(cy) + 1.0 - m.hh - EPS if m.behavior != "flyer" and m.behavior != "swarm" else cy
	m._dir = 1 if m.rng.randf() < 0.5 else -1
	m.facing = m._dir
	m._phase = m.rng.randf() * TAU
	m.state = "dormant" if m.behavior == "ambusher" else "patrol"
	return m


func attack_cfg(key: String, default: float = 0.0) -> float:
	return float((def.get("attack", {}) as Dictionary).get(key, default))


func speed_cfg(key: String) -> float:
	return float(def.get(key, 1.0))


## Имя анимации для рисования: idle / move / attack / die / dormant.
func anim_name() -> String:
	match state:
		"dying", "dead":
			return "die"
		"dormant":
			return "dormant"
		"windup", "strike", "shoot":
			return "attack"
		"dash", "leap":
			return "attack"
		"patrol", "chase", "return":
			return "move" if absf(vx) > 0.05 or behavior == "flyer" or behavior == "swarm" else "idle"
		_:
			return "idle"


## Зона, по которой бьёт герой. У крупных монстров шире хитбокса: картинка
## стража больше клетки тоннеля, и удар по видимому телу обязан засчитываться.
func hurtbox() -> Rect2:
	var pad := float(def.get("hit_pad", 0.0))
	return Rect2(x - hw - pad, y - hh - pad, (hw + pad) * 2.0, (hh + pad) * 2.0)


## Помещается ли хитбокс в текущей точке (не в породе). Спавнер проверяет это
## до появления: монстр шире прохода (1.1 клетки в шахте шириной 1) застрял бы
## намертво.
func fits(solid: Callable) -> bool:
	return not _box_hits(solid, x, y)


func is_flying() -> bool:
	return behavior == "flyer" or behavior == "swarm"


# ---------------------------------------------------------------------------
# Урон по монстру
# ---------------------------------------------------------------------------

## Удар героя. Возвращает реально нанесённый урон. dir — куда отбросить.
func take_hit(amount: float, dir: int, knock: float = 3.0) -> float:
	if not alive or amount <= 0.0:
		return 0.0
	if state == "dormant":
		_wake()
	hp -= amount
	flash = 0.12
	var resist: float = float(def.get("knock_resist", 0.0))
	kvx = float(dir) * knock * (1.0 - resist)
	if hp <= 0.0:
		alive = false
		state = "dying"
		t = 0.0
		telegraph = false
		vx = 0.0
		return amount
	var armored := bool(def.get("super_armor", false)) or state == "leap" or state == "dash"
	# stagger_chance (стражи полостей): панцирный жук от удара шатается не всегда —
	# иначе кирка 0.7 с сбивала бы каждый его замах, и бой был бы без риска
	if not armored and rng.randf() >= float(def.get("stagger_chance", 1.0)):
		armored = true
	if not armored:
		stun = 0.25
		state = "stagger"
		t = 0.0
		telegraph = false
	return amount


func _wake() -> void:
	state = "chase"
	t = 0.0
	x = emerge_pos.x if emerge_pos != Vector2.ZERO else x
	y = emerge_pos.y if emerge_pos != Vector2.ZERO else y


# ---------------------------------------------------------------------------
# Тик
# ---------------------------------------------------------------------------

## hero: {x, y, hw, hh, alive}; solid: Callable(int, int) -> bool.
## События: {"type": "hit", "damage", "kind", "dir"}, {"type": "windup"},
## {"type": "emerge"}, {"type": "died"}.
func tick(dt: float, hero: Dictionary, solid: Callable) -> Array:
	var ev: Array = []
	anim_t += dt
	flash = maxf(0.0, flash - dt)
	cd = maxf(0.0, cd - dt)
	t += dt

	if state == "dying":
		_apply_gravity(dt)
		_move(dt, solid)
		if t >= 0.7:
			state = "dead"
			dead = true
			ev.append({"type": "died"})
		return ev
	if dead:
		return ev

	if state == "stagger":
		_apply_gravity(dt)
		if is_flying():
			vy = 0.0
		vx = kvx
		kvx = move_toward(kvx, 0.0, 14.0 * dt)
		_move(dt, solid)
		stun -= dt
		if stun <= 0.0:
			state = "chase"
			t = 0.0
		return ev

	var hero_ok := bool(hero.get("alive", true))
	if leashed():
		# вне агро героя будто нет; ушёл за поводок — домой, не глядя на героя
		if hero_ok and not hero_in_aggro(hero):
			hero_ok = false
		var far := Vector2(x, y).distance_to(home)
		if state == "return":
			if far <= leash * 0.5:
				state = "patrol"
				t = 0.0
			else:
				_ai_return(dt, solid)
				return ev
		elif far > leash and (state == "patrol" or state == "chase"):
			state = "return"
			t = 0.0
			telegraph = false
			_ai_return(dt, solid)
			return ev
	match behavior:
		"crawler":
			_ai_crawler(dt, hero, hero_ok, solid, ev)
		"ambusher":
			if state == "dormant":
				_ai_dormant(hero, hero_ok, ev)
			else:
				_ai_crawler(dt, hero, hero_ok, solid, ev)
		"flyer":
			_ai_flyer(dt, hero, hero_ok, solid, ev)
		"jumper":
			_ai_jumper(dt, hero, hero_ok, solid, ev)
		"swarm":
			_ai_swarm(dt, hero, hero_ok, solid, ev)
		"shooter":
			_ai_shooter(dt, hero, hero_ok, solid, ev)
	return ev


func leashed() -> bool:
	return leash > 0.0 and home != Vector2.INF


func hero_in_aggro(hero: Dictionary) -> bool:
	if not leashed():
		return true
	return Vector2(float(hero["x"]), float(hero["y"])).distance_to(home) <= aggro


## Домой: летун — по прямой, ходячие и прыгуны — по полу (через ступеньку прыжком).
func _ai_return(dt: float, solid: Callable) -> void:
	var to := home - Vector2(x, y)
	if is_flying():
		var v := to.limit_length(speed_cfg("chase_speed"))
		vx = v.x
		vy = v.y
		facing = 1 if vx >= 0.0 else -1
		_move(dt, solid)
		return
	_apply_gravity(dt)
	_dir = 1 if to.x >= 0.0 else -1
	facing = _dir
	if behavior == "jumper":
		if on_ground:
			if t > 0.5:
				t = 0.0
				vx = float(_dir) * 2.5
				vy = -4.5
				on_ground = false
			else:
				vx = 0.0
	else:
		vx = float(_dir) * speed_cfg("chase_speed") * 0.8
	_move(dt, solid)
	_hop_if_blocked()


## Есть ли пол перед монстром. Страж полости (can_hop) считает полом и ступеньку
## на клетку ниже: пол круга или звезды — лесенка, с которой он сходит, а не стоит.
func _floor_ahead(solid: Callable, dir: int) -> bool:
	var fx := x + float(dir) * (hw + 0.12)
	if _solid_at(solid, fx, y + hh + 0.1):
		return true
	return bool(def.get("can_hop", false)) and _solid_at(solid, fx, y + hh + 1.1)


## Ступенька на пути (пол полости не ровный): ходячий страж перепрыгивает одну клетку.
func _hop_if_blocked() -> void:
	if _blocked_x and on_ground and bool(def.get("can_hop", false)):
		vy = -6.4
		on_ground = false
		vx = float(facing) * speed_cfg("chase_speed") * 0.8


# ---------------------------------------------------------------------------
# Поведения
# ---------------------------------------------------------------------------

func _dist_to(hero: Dictionary) -> Vector2:
	return Vector2(float(hero["x"]) - x, float(hero["y"]) - y)


func _hero_overlaps(hero: Dictionary, pad_x: float = 0.0, pad_y: float = 0.0, front: float = 0.0) -> bool:
	var hb := Rect2(float(hero["x"]) - float(hero.get("hw", 0.38)), float(hero["y"]) - float(hero.get("hh", 0.33)),
		float(hero.get("hw", 0.38)) * 2.0, float(hero.get("hh", 0.33)) * 2.0)
	var mb := Rect2(x - hw - pad_x, y - hh - pad_y, (hw + pad_x) * 2.0, (hh + pad_y) * 2.0)
	if front > 0.0:
		# выпад вперёд: боксы тела и вытянутой «пасти» в сторону взгляда
		var fx := x + float(facing) * (hw + front * 0.5)
		mb = mb.merge(Rect2(fx - front * 0.5, y - hh - pad_y, front, (hh + pad_y) * 2.0))
	return mb.intersects(hb)


func _emit_hit(ev: Array, hero: Dictionary) -> void:
	ev.append({"type": "hit", "damage": damage, "kind": kind,
		"dir": 1 if float(hero["x"]) >= x else -1})


func _ai_dormant(hero: Dictionary, hero_ok: bool, ev: Array) -> void:
	if not hero_ok:
		return
	var d := _dist_to(hero)
	if d.length() <= float(def.get("wake_radius", 1.9)):
		_wake()
		state = "windup"
		t = 0.0
		telegraph = true
		ev.append({"type": "emerge"})


func _ai_crawler(dt: float, hero: Dictionary, hero_ok: bool, solid: Callable, ev: Array) -> void:
	_apply_gravity(dt)
	var d := _dist_to(hero)
	var sight := float(def.get("sight", 6.0))
	var reach := attack_cfg("reach", 0.5)
	var seen := hero_ok and absf(d.x) <= sight and absf(d.y) <= sight * 0.55
	match state:
		"windup":
			vx = 0.0
			telegraph = true
			if t >= attack_cfg("windup", 0.3):
				telegraph = false
				if _hero_overlaps(hero, 0.0, 0.25, reach + 0.25):
					_emit_hit(ev, hero)
				state = "recover"
				t = 0.0
		"recover":
			vx = 0.0
			if t >= attack_cfg("recover", 0.5):
				state = "chase"
				t = 0.0
		_:
			if seen:
				state = "chase"
				facing = 1 if d.x >= 0.0 else -1
				_dir = facing
				vx = float(facing) * speed_cfg("chase_speed")
				# хватит ли дотянуться: замах
				if absf(d.x) <= hw + float(hero.get("hw", 0.38)) + reach and absf(d.y) <= hh + 0.7:
					state = "windup"
					t = 0.0
					vx = 0.0
					telegraph = true
					ev.append({"type": "windup"})
			else:
				state = "patrol"
				vx = float(_dir) * speed_cfg("speed")
				facing = _dir
			if on_ground and state != "windup":
				var wall_ahead := _solid_at(solid, x + float(_dir) * (hw + 0.1), y)
				var floor_ahead := _floor_ahead(solid, _dir)
				var hero_below := d.y > 1.2 and absf(d.x) < 2.0
				if wall_ahead or (not floor_ahead and not (state == "chase" and hero_below)):
					if state == "patrol":
						_dir = -_dir
						facing = _dir
						vx = float(_dir) * speed_cfg("speed")
					elif wall_ahead and bool(def.get("can_hop", false)):
						pass   # ступенька: упрёмся и перепрыгнем (см. _hop_if_blocked)
					else:
						vx = 0.0
	_move(dt, solid)
	if state == "chase":
		_hop_if_blocked()


## Стрелок: держит дистанцию (отходит, если герой ближе keep_dist), по кулдауну
## замахивается и выпускает снаряд в текущее место героя — навесом вблизи,
## настильно издали. Пока не видит героя — медленно бродит, как ползун.
func _ai_shooter(dt: float, hero: Dictionary, hero_ok: bool, solid: Callable, ev: Array) -> void:
	_apply_gravity(dt)
	var d := _dist_to(hero)
	var sight := float(def.get("sight", 7.0))
	var seen := hero_ok and d.length() <= sight
	match state:
		"windup":
			vx = 0.0
			telegraph = true
			facing = 1 if d.x >= 0.0 else -1
			if t >= attack_cfg("windup", 0.6):
				telegraph = false
				var spec: Dictionary = def.get("projectile", {})
				var mx := x + float(facing) * hw * 0.6
				var my := y - hh * 0.3
				var aim := Projectile.aim(float(hero["x"]) - mx, float(hero["y"]) - my,
					float(spec.get("speed", 7.0)), float(spec.get("gravity", 0.0)), d.length() < 4.5)
				ev.append({"type": "shoot", "x": mx, "y": my, "vx": aim.x, "vy": aim.y, "spec": spec,
					"damage": damage, "kind": kind})
				cd = attack_cfg("cooldown", 2.4)
				state = "recover"
				t = 0.0
		"recover":
			vx = 0.0
			if t >= attack_cfg("recover", 0.5):
				state = "chase"
				t = 0.0
		_:
			if seen:
				state = "chase"
				facing = 1 if d.x >= 0.0 else -1
				var keep := attack_cfg("keep_dist", 2.5)
				if absf(d.x) < keep and on_ground:
					# слишком близко: пятится, пока есть куда
					var back := -facing
					var wall := _solid_at(solid, x + float(back) * (hw + 0.1), y)
					var floor_ok := _solid_at(solid, x + float(back) * (hw + 0.12), y + hh + 0.1)
					vx = float(back) * speed_cfg("chase_speed") if not wall and floor_ok else 0.0
				else:
					vx = 0.0
				if cd <= 0.0 and t > 0.3 and d.length() >= attack_cfg("min_range", 1.5):
					state = "windup"
					t = 0.0
					vx = 0.0
					telegraph = true
					ev.append({"type": "windup"})
			else:
				state = "patrol"
				vx = float(_dir) * speed_cfg("speed")
				facing = _dir
				if on_ground:
					var wall_ahead := _solid_at(solid, x + float(_dir) * (hw + 0.1), y)
					if wall_ahead or not _floor_ahead(solid, _dir):
						_dir = -_dir
						facing = _dir
						vx = float(_dir) * speed_cfg("speed")
	_move(dt, solid)


func _ai_flyer(dt: float, hero: Dictionary, hero_ok: bool, solid: Callable, ev: Array) -> void:
	var d := _dist_to(hero)
	var sight := float(def.get("sight", 7.0))
	_phase += dt * 4.0
	match state:
		"windup":
			vx = 0.0
			vy = 0.0
			telegraph = true
			facing = 1 if d.x >= 0.0 else -1
			if t >= attack_cfg("windup", 0.45):
				telegraph = false
				_dash_dir = d.normalized() if d.length() > 0.01 else Vector2(float(facing), 0.0)
				state = "dash"
				t = 0.0
				_hit_done = false
		"dash":
			var sp := attack_cfg("dash_speed", 6.0)
			vx = _dash_dir.x * sp
			vy = _dash_dir.y * sp
			facing = 1 if vx >= 0.0 else -1
			if not _hit_done and hero_ok and _hero_overlaps(hero, 0.05, 0.05):
				_hit_done = true
				_emit_hit(ev, hero)
			if t >= attack_cfg("dash_time", 0.45):
				state = "recover"
				t = 0.0
		"recover":
			# отход вверх-назад: летун не липнет к герою после пике
			vx = -_dash_dir.x * 1.2
			vy = -1.4
			if t >= attack_cfg("recover", 1.1):
				state = "chase"
				t = 0.0
		_:
			if hero_ok and d.length() <= sight:
				state = "chase"
				# завис над героем и чуть сбоку, покачиваясь
				var want := Vector2(float(hero["x"]) + sin(_phase * 0.5) * 2.4, float(hero["y"]) - 1.6 + sin(_phase) * 0.35)
				var to := want - Vector2(x, y)
				var sp2 := speed_cfg("chase_speed")
				var v := to.limit_length(sp2) if to.length() > 0.15 else Vector2.ZERO
				vx = v.x
				vy = v.y
				facing = 1 if d.x >= 0.0 else -1
				if t > 0.9 and d.length() <= 4.2 and cd <= 0.0:
					state = "windup"
					t = 0.0
					telegraph = true
					ev.append({"type": "windup"})
			else:
				state = "patrol"
				vx = sin(_phase * 0.5) * speed_cfg("speed") * 0.6
				vy = cos(_phase * 0.7) * 0.5
	_move(dt, solid)
	if _blocked_x and state == "dash":
		state = "recover"
		t = 0.0


func _ai_jumper(dt: float, hero: Dictionary, hero_ok: bool, solid: Callable, ev: Array) -> void:
	_apply_gravity(dt)
	var d := _dist_to(hero)
	var sight := float(def.get("sight", 7.0))
	match state:
		"windup":
			vx = 0.0
			telegraph = true
			facing = 1 if d.x >= 0.0 else -1
			if t >= attack_cfg("windup", 0.5):
				telegraph = false
				state = "leap"
				t = 0.0
				_hit_done = false
				on_ground = false
				vx = float(facing) * attack_cfg("leap_vx", 5.5)
				vy = -attack_cfg("leap_vy", 9.0)
		"leap":
			if not _hit_done and hero_ok and _hero_overlaps(hero, 0.05, 0.05):
				_hit_done = true
				_emit_hit(ev, hero)
			if on_ground and t > 0.1:
				state = "recover"
				t = 0.0
				vx = 0.0
		"recover":
			vx = 0.0
			if t >= attack_cfg("recover", 0.9):
				state = "chase"
				t = 0.0
		_:
			if hero_ok and absf(d.x) <= sight and absf(d.y) <= sight * 0.6:
				state = "chase"
				facing = 1 if d.x >= 0.0 else -1
				vx = 0.0
				# прыжок на расстоянии: дальше ~5 клеток не долетит
				if on_ground and t > 0.4 and absf(d.x) <= 4.6:
					state = "windup"
					t = 0.0
					telegraph = true
					ev.append({"type": "windup"})
				elif on_ground and absf(d.x) > 4.6:
					vx = float(facing) * speed_cfg("speed")
			else:
				state = "patrol"
				# редкие пружинистые шаги вместо ходьбы
				if on_ground and t > 1.2:
					t = 0.0
					_dir = 1 if rng.randf() < 0.5 else -1
					facing = _dir
					vx = float(_dir) * 2.0
					vy = -4.0
					on_ground = false
				elif on_ground:
					vx = 0.0
	_move(dt, solid)


func _ai_swarm(dt: float, hero: Dictionary, hero_ok: bool, solid: Callable, ev: Array) -> void:
	var d := _dist_to(hero)
	var sight := float(def.get("sight", 8.0))
	_phase += dt * 3.2
	if state == "recover":
		# отлёт после укуса
		vx = -float(facing) * 2.2
		vy = -1.0
		if t >= 0.4:
			state = "chase"
			t = 0.0
	elif hero_ok and d.length() <= sight:
		state = "chase"
		var r := 1.1 + 0.4 * sin(_phase * 0.7)
		var want := Vector2(float(hero["x"]) + cos(_phase + float(group)) * r, float(hero["y"]) + sin(_phase + float(group)) * r * 0.7 - 0.2)
		var to := want - Vector2(x, y)
		var v := to.limit_length(speed_cfg("chase_speed")) if to.length() > 0.1 else Vector2.ZERO
		# к герою подтягиваются агрессивнее, когда кулдаун кончился
		if cd <= 0.0:
			v = d.limit_length(speed_cfg("chase_speed"))
		vx = v.x
		vy = v.y
		facing = 1 if vx >= 0.0 else -1
		if cd <= 0.0 and _hero_overlaps(hero, 0.0, 0.0):
			_emit_hit(ev, hero)
			cd = attack_cfg("cooldown", 0.8)
			state = "recover"
			t = 0.0
	else:
		state = "patrol"
		vx = cos(_phase) * speed_cfg("speed") * 0.5
		vy = sin(_phase * 1.3) * speed_cfg("speed") * 0.4
	_move(dt, solid)


# ---------------------------------------------------------------------------
# Физика: коробка против клеток
# ---------------------------------------------------------------------------

var _blocked_x: bool = false


func _apply_gravity(dt: float) -> void:
	if is_flying():
		return
	vy = minf(vy + GRAVITY * dt, V_TERM)


func _solid_at(solid: Callable, wx: float, wy: float) -> bool:
	return bool(solid.call(int(floor(wx)), int(floor(wy))))


func _box_hits(solid: Callable, cx: float, cy: float) -> bool:
	var x0 := int(floor(cx - hw + EPS))
	var x1 := int(floor(cx + hw - EPS))
	var y0 := int(floor(cy - hh + EPS))
	var y1 := int(floor(cy + hh - EPS))
	for ix in range(x0, x1 + 1):
		for iy in range(y0, y1 + 1):
			if bool(solid.call(ix, iy)):
				return true
	return false


func _move(dt: float, solid: Callable) -> void:
	_blocked_x = false
	if vx != 0.0:
		var nx := x + vx * dt
		if _box_hits(solid, nx, y):
			if vx > 0.0:
				x = floorf(nx + hw - EPS) - hw - EPS
			else:
				x = floorf(nx - hw + EPS) + 1.0 + hw + EPS
			# не «втолкнуть» назад дальше, чем стояли: упёрлись — стоим
			vx = 0.0
			_blocked_x = true
		else:
			x = nx
	var ny := y + vy * dt
	if vy != 0.0:
		if _box_hits(solid, x, ny):
			if vy > 0.0:
				y = floorf(ny + hh - EPS) - hh - EPS
				on_ground = true
			else:
				y = floorf(ny - hh + EPS) + 1.0 + hh + EPS
				on_ground = false
			vy = 0.0
		else:
			y = ny
			on_ground = false
	elif not is_flying():
		on_ground = _box_hits(solid, x, y + 0.05)
	if not is_flying() and vy >= 0.0 and not on_ground:
		on_ground = _box_hits(solid, x, y + 0.02)

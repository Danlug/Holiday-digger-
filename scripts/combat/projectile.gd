class_name Projectile
extends RefCounted
## Projectile — снаряд стреляющего монстра (раунд 5: плевок кислоты, камень,
## искра). Летит по прямой (gravity 0) или по дуге, бьётся о породу, задевает
## героя. Как и Monster, ничего не трогает сам: tick() возвращает события
## {"type": "hit", damage, kind, dir} / {"type": "break"} / {"type": "expire"},
## а CombatDirector уже ранит героя и зовёт Sfx/Fx. Координаты — клетки.

const STEP := 0.2   # шаг подвыборки по пути: быстрый снаряд не проскакивает стенку

var x: float = 0.0
var y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
var gravity: float = 0.0
var radius: float = 0.2
var damage: float = 1.0
var kind: String = "acid"
var dmg_kind: String = "void"
var ttl: float = 3.0
var t: float = 0.0
var alive: bool = true
var owner_id: String = ""
var prev: Vector2 = Vector2.ZERO
var anim_t: float = 0.0


## Снаряд из записи projectile монстра (data/combat.json), выпущенный из (px, py).
static func create(spec: Dictionary, px: float, py: float, p_vx: float, p_vy: float, p_damage: float, p_dmg_kind: String) -> Projectile:
	var p := Projectile.new()
	p.kind = String(spec.get("kind", "acid"))
	p.gravity = float(spec.get("gravity", 0.0))
	p.radius = float(spec.get("radius", 0.2))
	p.ttl = float(spec.get("ttl", 3.0))
	p.x = px
	p.y = py
	p.prev = Vector2(px, py)
	p.vx = p_vx
	p.vy = p_vy
	p.damage = p_damage
	p.dmg_kind = p_dmg_kind
	return p


## Скорость броска по дуге, чтобы попасть из (0,0) в (dx, dy) (y вниз) при
## модуле скорости speed и тяготении g. high — верхняя дуга (навесом), иначе
## настильная. Если цель недосягаема — выстрел под 45° в сторону цели.
static func aim(dx: float, dy: float, speed: float, g: float, high: bool) -> Vector2:
	if g <= 0.0:
		var d := Vector2(dx, dy)
		return d.normalized() * speed if d.length() > 0.001 else Vector2(speed, 0.0)
	var sx := 1.0 if dx >= 0.0 else -1.0
	var X := absf(dx)
	var h := -dy   # высота цели над дулом, вверх положительно
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * X * X + 2.0 * h * v2)
	var ang: float
	if disc < 0.0 or X < 0.001:
		ang = PI / 4.0 if h <= 0.0 else PI / 3.0
	else:
		var root := sqrt(disc)
		var tan_a := (v2 + root) / (g * X) if high else (v2 - root) / (g * X)
		ang = atan(tan_a)
	return Vector2(sx * cos(ang) * speed, -sin(ang) * speed)


## hero: {x, y, hw, hh, alive}; solid: Callable(int, int) -> bool.
func tick(dt: float, hero: Dictionary, solid: Callable) -> Array:
	var ev: Array = []
	if not alive:
		return ev
	anim_t += dt
	t += dt
	prev = Vector2(x, y)
	if t >= ttl:
		alive = false
		ev.append({"type": "expire"})
		return ev
	vy += gravity * dt
	var move := Vector2(vx, vy) * dt
	var n := maxi(1, int(ceil(move.length() / STEP)))
	var hb := Rect2(float(hero["x"]) - float(hero.get("hw", 0.38)), float(hero["y"]) - float(hero.get("hh", 0.33)),
		float(hero.get("hw", 0.38)) * 2.0, float(hero.get("hh", 0.33)) * 2.0).grow(radius)
	var hero_ok := bool(hero.get("alive", true))
	for i in range(n):
		x += move.x / float(n)
		y += move.y / float(n)
		if x < 0.0 or x >= float(CombatWorld.WIDTH) or y < 0.0 or bool(solid.call(int(floor(x)), int(floor(y)))):
			alive = false
			ev.append({"type": "break"})
			return ev
		if hero_ok and hb.has_point(Vector2(x, y)):
			alive = false
			ev.append({"type": "hit", "damage": damage, "kind": dmg_kind, "dir": 1 if vx >= 0.0 else -1})
			return ev
	return ev

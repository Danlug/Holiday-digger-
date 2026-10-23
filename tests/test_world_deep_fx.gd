extends Node
## Эффекты мира (ветка «world»): AmbientFx, DeepBackdrop, SurfaceLife, CollapseFx и
## разрезанный обвал (plan/apply). Без рендера: проверяем логику и устойчивость.

var checks := 0
var failures := 0


class FakePlayer extends Node:
	var y: float = 2000.0
	var x: float = 20.0


func _ready() -> void:
	print("=== test_world_deep_fx: старт ===")
	test_plan_equals_trigger()
	test_ambient_particles_live_only_in_visible_air()
	test_ambient_sleeps_on_surface()
	test_collapse_fx_and_surface_life()
	print("=== Итог: %d проверок, %d провалов ===" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("  OK    ", label)
	else:
		failures += 1
		print("  FAIL  ", label)


func test_plan_equals_trigger() -> void:
	print("-- Обвал: выбор зоны и удар — те же правила --")
	var a := WorldGen.new(11)
	var b := WorldGen.new(11)
	var fa := FogOfWar.new()
	var fb := FogOfWar.new()
	var ra := RandomNumberGenerator.new()
	var rb := RandomNumberGenerator.new()
	ra.seed = 77
	rb.seed = 77
	var same := true
	var below := true
	for i in range(40):
		var rect_a := CollapseEvents.trigger_chunk_collapse(a, fa, ra, 100)
		var plan := CollapseEvents.plan_chunk_collapse(b, rb, 100)
		var rect_b := CollapseEvents.apply_planned(b, fb, plan)
		if rect_a != rect_b:
			same = false
		if int(plan.y0) <= 100 or int(plan.x0) < WorldGen.GARDEN_X_MIN:
			below = false
	check("plan+apply даёт ровно тот же прямоугольник, что trigger_chunk_collapse (40 бросков)", same)
	check("зона строго ниже героя и правее дома", below)
	check("мир после plan+apply совпадает с миром после trigger", a.events == b.events)
	var w := WorldGen.new(3)
	var plan0 := CollapseEvents.plan_chunk_collapse(w, ra, 100)
	check("plan ничего не меняет в мире", w.events.is_empty() and not plan0.is_empty())


func _make_ambient(depth: int) -> Array:
	var world := WorldGen.new(5)
	var fog := FogOfWar.new()
	var pl := FakePlayer.new()
	pl.y = float(depth)
	add_child(pl)
	# каверна вокруг героя: пустая видимая полость 9x7
	for x in range(18, 27):
		for y in range(depth - 3, depth + 4):
			world.diffs[world._key(x, y)] = true
	fog.reveal_around(22.0, float(depth), 8, 8)
	var fx := AmbientFx.new()
	fx.world = world
	fx.fog = fog
	fx.player = pl
	add_child(fx)
	return [fx, world, pl]


func test_ambient_particles_live_only_in_visible_air() -> void:
	print("-- AmbientFx: частицы только в видимой пустоте --")
	for depth in [1500, 2500, 3500, 4500, 6000, 7500, 9000]:
		var pack := _make_ambient(depth)
		var fx: AmbientFx = pack[0]
		var world: WorldGen = pack[1]
		var cam := Vector2(18.0, float(depth) - 5.0)
		var maxp := 0
		var in_rock := 0
		for i in range(200):
			fx.update(cam, 7, 14, 0.033)
			maxp = maxi(maxp, fx.particle_count())
			for d in fx._p:
				if d.k != "splash" and world.get_tile(int(floor(d.x / 32.0)), int(floor(d.y / 32.0))) != TileTypes.Type.EMPTY:
					in_rock += 1
		check("глубина %d (%s): частицы появились и не больше 28 (макс %d)" % [depth, Biomes.name_at(depth), maxp],
				maxp > 0 and maxp <= AmbientFx.MAX_PARTICLES)
		check("глубина %d: ни одной частицы внутри породы" % depth, in_rock == 0)
		fx.get_parent().remove_child(fx)
		fx.queue_free()
		pack[2].queue_free()


func test_ambient_sleeps_on_surface() -> void:
	print("-- AmbientFx: на поверхности спит --")
	var pack := _make_ambient(1500)
	var fx: AmbientFx = pack[0]
	for i in range(30):
		fx.update(Vector2(18.0, 1495.0), 7, 14, 0.033)
	check("под землёй частицы есть", fx.particle_count() > 0)
	pack[2].y = 0.5
	fx.update(Vector2(18.0, -6.0), 7, 14, 0.033)
	check("герой на поверхности — частиц нет", fx.particle_count() == 0)
	fx.queue_free()
	pack[2].queue_free()


func test_collapse_fx_and_surface_life() -> void:
	print("-- CollapseFx, SurfaceLife, DeepBackdrop --")
	var cfx := CollapseFx.new()
	add_child(cfx)
	var cam := Vector2(17.0, 295.0)
	cfx.warn({"x0": 18, "y0": 300, "w": 8, "h": 5}, 1.0)
	check("после warn — предупреждение идёт", cfx.is_warning())
	for i in range(40):
		cfx.update(cam, 7, 14, 0.033)
	check("пыль предупреждения не разрастается безгранично (<= 60 зёрен)", cfx._grains.size() <= CollapseFx.MAX_GRAINS)
	cfx.impact({"x0": 18, "y0": 300, "w": 8, "h": 5})
	check("удар гасит предупреждение", not cfx.is_warning())
	for i in range(60):
		cfx.update(cam, 7, 14, 0.033)
	check("через ~2 секунды после удара пыль улеглась", cfx._grains.is_empty() and cfx._impact.is_empty())
	cfx.warn({"x0": 18, "y0": 800, "w": 8, "h": 5}, 1.0)
	for i in range(10):
		cfx.update(cam, 7, 14, 0.033)
	check("зона вне камеры не плодит зёрен", cfx._grains.is_empty())
	cfx.cancel_warning()
	check("cancel_warning снимает предупреждение", not cfx.is_warning())
	cfx.queue_free()

	var sl := SurfaceLife.new()
	add_child(sl)
	var t0: float = sl._birds[0].x
	for i in range(30):
		sl.update(Vector2(15.0, -6.5), 7, 14, 0.033)
	check("птицы летят (x меняется)", sl._birds[0].x != t0)
	sl.update(Vector2(15.0, 300.0), 7, 14, 0.033)
	check("под землёй поверхность спит (узел скрыт)", not sl.visible)
	sl.queue_free()

	var db := DeepBackdrop.new()
	add_child(db)
	db.update(Vector2(10.0, 3000.0), 7, 14)
	check("стена видна под землёй", db.visible)
	db.update(Vector2(10.0, -20.0), 7, 14)
	check("над землёй стена скрыта", not db.visible)
	db.queue_free()

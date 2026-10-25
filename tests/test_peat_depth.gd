extends Node
## Торф после пласта (решение владельца, раунд 5): «Торф должен быть так же, как до 450, в такой же
## концентрации и после 455 до 1000». Замер на настоящем WorldGen (сцена — с автозагрузками, иначе
## LavaField не знает своей глубины и заливает лавой весь мир, см. шапку run_tests.sh).
##
## Эталон «как до 450» — доля торфа в рядах 400–449: там рост 5% → 20% (data/world_layers.json → ores
## → peat, curve=ramp) уже дошёл до своей концентрации, и с неё же порода продолжается за пластом.
## Средняя по всей толще 6–449 ниже (у поверхности торфа нет, с 60 он только набирает долю) — её
## печатаем для сравнения: за пластом торфа не меньше, чем в среднем выше.

const SEEDS := [1, 7, 42, 20260915, 99991, 424242]
const TOL := 0.15                 # «≈ эталону ±15%»
const WINDOW := 50                # окно проверки «без провалов» на 456–999

var checks := 0
var failures := 0


func _ready() -> void:
	print("=== test_peat_depth: старт ===")
	_test_concentration()
	_test_formula()
	print("=== Итог: %d проверок, %d провалов ===" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("  OK    ", label)
	else:
		failures += 1
		print("  FAIL  ", label)


## Доля торфа по рядам [y0; y1] и число клеток.
func _rows(w: WorldGen, y0: int, y1: int) -> Vector2i:
	var hit := 0
	for y in range(y0, y1 + 1):
		for x in range(WorldGen.WIDTH):
			if w.get_tile(x, y) == TileTypes.Type.PEAT:
				hit += 1
	return Vector2i(hit, (y1 - y0 + 1) * WorldGen.WIDTH)


func _test_concentration() -> void:
	print("-- Концентрация торфа по глубине (%d сидов) --" % SEEDS.size())
	var sum := {"surface": Vector2i.ZERO, "ref": Vector2i.ZERO, "deep": Vector2i.ZERO, "after": Vector2i.ZERO}
	var seam_ok := true
	var worst_window := 1.0
	var worst_seed_ratio := 1.0
	for s in SEEDS:
		var w := WorldGen.new(s)
		var surface := _rows(w, 6, 449)
		var ref := _rows(w, 400, 449)
		var seam := _rows(w, 450, 455)
		var deep := _rows(w, 456, 999)
		var after := _rows(w, 1001, 1400)
		seam_ok = seam_ok and seam.x == seam.y
		sum["surface"] += surface
		sum["ref"] += ref
		sum["deep"] += deep
		sum["after"] += after
		var r_ref := float(ref.x) / ref.y
		var r_deep := float(deep.x) / deep.y
		worst_seed_ratio = minf(worst_seed_ratio, 1.0 - absf(r_deep / r_ref - 1.0))
		for y0 in range(456, 1000 - WINDOW + 1, WINDOW):
			var win := _rows(w, y0, y0 + WINDOW - 1)
			worst_window = minf(worst_window, (float(win.x) / win.y) / r_ref)
		print("     сид %-9d 6–449 %.3f (%.2f/ряд) | 400–449 %.3f (%.2f/ряд) | 456–999 %.3f (%.2f/ряд) | 1001–1400 %.4f" % [
			s, float(surface.x) / surface.y, float(surface.x) / 444.0, r_ref, float(ref.x) / 50.0,
			r_deep, float(deep.x) / 544.0, float(after.x) / after.y])
	var f := func(k: String) -> float: return float(sum[k].x) / float(sum[k].y)
	var ref_all: float = f.call("ref")
	var deep_all: float = f.call("deep")
	print("     ИТОГО: 6–449 %.3f, эталон 400–449 %.3f (%.2f клетки на ряд), 456–999 %.3f (%.2f на ряд), отношение %.3f" % [
		f.call("surface"), ref_all, ref_all * WorldGen.WIDTH, deep_all, deep_all * WorldGen.WIDTH, deep_all / ref_all])
	check("пласт 450–455 сплошь торф на всех сидах", seam_ok)
	check("456–999: доля торфа = эталону 400–449 ±15%% по всем сидам (%.3f против %.3f)" % [deep_all, ref_all],
		absf(deep_all / ref_all - 1.0) <= TOL)
	check("и на каждом сиде отдельно ±15%% (худший — %.0f%% совпадения)" % (worst_seed_ratio * 100.0),
		worst_seed_ratio >= 1.0 - TOL)
	check("на 456–999 нет окна в %d рядов беднее 60%% эталона (худшее %.0f%%)" % [WINDOW, worst_window * 100.0],
		worst_window >= 0.6)
	check("за пластом торфа не меньше, чем в среднем выше него (6–449)", deep_all >= f.call("surface"))
	check("глубже 1000 торфа нет — там уголь (доля %.4f)" % f.call("after"), f.call("after") < 0.005)


## Формула (её же читает скважина — WorldGen.ore_densities_at) держит долю торфа ровной от 450 до 1000.
func _test_formula() -> void:
	print("-- Формула доли торфа --")
	var w := WorldGen.new(1)
	var at := func(y: int) -> float:
		for d in w.ore_densities_at(y):
			if String(d["id"]) == "peat":
				return float(d["density"])
		return 0.0
	var d449: float = at.call(449)
	var worst := 1.0
	for y in range(460, 1000, 20):
		worst = minf(worst, 1.0 - absf(float(at.call(y)) / d449 - 1.0))
	print("     доля по формуле: y=300 %.3f, y=449 %.3f, y=600 %.3f, y=999 %.3f, y=1000 %.3f" % [
		at.call(300), d449, at.call(600), at.call(999), at.call(1000)])
	check("по формуле 460–999 держит долю y=449 ±15%% (худшее %.0f%%)" % (worst * 100.0), worst >= 1.0 - TOL)
	check("по формуле торф кончается на 1000", at.call(1001) == 0.0)

extends Node
## test_hero_art — мальчик по эталону владельца (раунд 4, «boy-art»;
## tools/gen_hero_ref.py, геометрия — art/character/hero_sheets.json).
##
## Для каждого листа из hero_sheets.json: лист есть и вмещает ровно свои кадры;
## сторона ≤ 4096 (лимит текстуры мобильного WebGL); плотность ≥ ×6 текселей на
## логическую точку (было ×3 — на телефоне ×5,2 кадр растягивался и мутнел);
## рисунок на сетке cell×cell (увеличение только ближайшим соседом); альфа только
## 0/255; по краю силуэта нет светлых и зелёных пикселей (кайма подложки,
## ореол хромакея); подошва стоит на линии земли (кадры на земле — ровно,
## остальные — не ниже неё); герой в каждом кадре не пустой. Плюс контракт
## CharacterView: размер героя на экране прежний (40 точек ростом), шейдер
## чёткости берёт cell из геометрии.
##
## Запуск:  godot --headless --path . res://tests/test_hero_art.tscn

const OUT := "res://art/character/"

## Листы, где подошва обязана стоять ровно на линии земли в каждом кадре.
const ON_GROUND := ["idle", "idle_x", "walk", "walk_turn", "boy/idle", "boy/walk",
		"boy_gear/idle", "boy_gear/walk"]
## Сюжетный «мальчик» — копии листов героя (один рисунок на всю игру).
const COPIES := {
	"boy/idle": "idle", "boy/walk": "walk",
}

var failures := 0
var total := 0


func _ready() -> void:
	print("=== test_hero_art ===")
	var f := FileAccess.open(HeroSheets.META_PATH, FileAccess.READ)
	check("есть art/character/hero_sheets.json", f != null)
	var sheets: Dictionary = {}
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			sheets = parsed.get("sheets", {})
	check("в нём есть стойка и ходьба", sheets.has("idle") and sheets.has("walk"))
	for rel: String in sheets:
		_test_sheet(rel, sheets[rel])
	_test_copies(sheets)
	_test_view_contract()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _img(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _test_sheet(rel: String, inf: Dictionary) -> void:
	var img := _img(OUT + rel + ".png")
	check("%s: лист есть" % rel, img != null)
	if img == null:
		return
	var fw := int(inf["fw"])
	var fh := int(inf["fh"])
	var cols := int(inf["cols"])
	var n := int(inf["frames"])
	var cell := int(inf.get("cell", 1))
	var sc := float(inf["scale"])
	var rows := int(ceil(float(n) / float(cols)))
	var w := img.get_width()
	var h := img.get_height()
	check("%s: лист %d×%d вмещает %d кадров %d×%d" % [rel, w, h, n, fw, fh],
			w == cols * fw and h == rows * fh)
	check("%s: сторона ≤ 4096 (мобильный WebGL)" % rel, w <= 4096 and h <= 4096)
	check("%s: плотность ×%d ≥ ×6 текселей на точку" % [rel, int(sc)], sc >= 6.0)
	check("%s: кадр в целых логических точках" % rel,
			is_equal_approx(fmod(float(fw), sc), 0.0) and is_equal_approx(fmod(float(fh), sc), 0.0))
	check("%s: альфа только 0/255" % rel, img.detect_alpha() != Image.ALPHA_BLEND)

	# Сетка cell×cell: уменьшение и обратное увеличение ближайшим соседом даёт тот же лист.
	var native := img.duplicate() as Image
	native.resize(w / cell, h / cell, Image.INTERPOLATE_NEAREST)
	var back := native.duplicate() as Image
	back.resize(w, h, Image.INTERPOLATE_NEAREST)
	check("%s: рисунок на сетке %d×%d текселя (только ближайший сосед)" % [rel, cell, cell],
			back.get_data() == img.get_data())

	# Край силуэта и опорные точки — по родной сетке.
	var nw := native.get_width()
	var nh := native.get_height()
	var d := native.get_data()
	var light := 0
	var green := 0
	var edge := 0
	for y in nh:
		var row := y * nw * 4
		for x in nw:
			var i := row + x * 4
			if d[i + 3] == 0:
				continue
			if not (x == 0 or y == 0 or x == nw - 1 or y == nh - 1 or d[i - 1] == 0 or d[i + 7] == 0 \
					or d[i - nw * 4 + 3] == 0 or d[i + nw * 4 + 3] == 0):
				continue
			edge += 1
			var r := d[i]
			var g := d[i + 1]
			var b := d[i + 2]
			if 0.299 * r + 0.587 * g + 0.114 * b > 170.0 and maxi(r, maxi(g, b)) - mini(r, mini(g, b)) < 40:
				light += 1
			if g > r + 12 and g > b + 12:
				green += 1
	var allow_light := int(edge * 0.03)
	check("%s: светлой каймы нет (%d из %d пикселей края, допуск %d — белое само по себе)" % [rel, light, edge, allow_light],
			light <= allow_light)
	check("%s: зелёного ореола нет (%d)" % [rel, green], green == 0)

	var nfw := fw / cell
	var nfh := fh / cell
	var ground := int(inf["ground"]) / cell
	var empty := 0
	var off_ground := 0
	var below := 0
	for k in n:
		var x0 := (k % cols) * nfw
		var y0 := (k / cols) * nfh
		var bottom := -1
		for y in range(nfh - 1, -1, -1):
			var row := (y0 + y) * nw * 4
			for x in nfw:
				if d[row + (x0 + x) * 4 + 3] != 0:
					bottom = y
					break
			if bottom >= 0:
				break
		if bottom < 0:
			empty += 1
			continue
		if bottom != ground - 1:
			off_ground += 1
		if bottom > ground + 2 and not rel.contains("drill") and not rel.contains("dig_"):
			below += 1
	check("%s: пустых кадров нет" % rel, empty == 0)
	if ON_GROUND.has(rel):
		check("%s: подошва на линии земли во всех кадрах (мимо: %d)" % [rel, off_ground], off_ground == 0)
	else:
		check("%s: ниже линии земли рисунок не уходит (кадров: %d)" % [rel, below], below == 0)


func _test_copies(sheets: Dictionary) -> void:
	for dst: String in COPIES:
		if not sheets.has(dst):
			continue
		var a := _img(OUT + dst + ".png")
		var b := _img(OUT + String(COPIES[dst]) + ".png")
		check("%s совпадает с %s (сюжетный мальчик = герой)" % [dst, COPIES[dst]],
				a != null and b != null and a.get_data() == b.get_data())


## Контракт CharacterView: размер героя прежний, cell шейдера — из геометрии.
func _test_view_contract() -> void:
	var inf: Dictionary = HeroSheets.info("idle")
	check("стойка — лист высокого разрешения", not inf.is_empty())
	if inf.is_empty():
		return
	var sc: float = HeroSheets.scale_of(inf)
	check("кадр стойки — 48×48 логических точек, как раньше",
			is_equal_approx(float(inf["fw"]) / sc, 48.0) and is_equal_approx(float(inf["fh"]) / sc, 48.0))
	check("линия земли — 46 точек, как раньше", is_equal_approx(float(inf["ground"]) / sc, 46.0))
	var img := _img(OUT + "idle.png")
	var top := -1
	var bottom := -1
	for y in int(inf["fh"]):
		for x in int(inf["fw"]):
			if img.get_pixel(x, y).a > 0.5:
				if top < 0:
					top = y
				bottom = y
				break
	var tall: float = float(bottom - top + 1) / sc
	check("рост героя 40 точек (%.2f)" % tall, absf(tall - 40.0) <= 0.5)
	var view_script: GDScript = load("res://scripts/player/character_view.gd")
	var consts: Dictionary = view_script.get_script_constant_map()
	check("CharacterView не держит своих списков cell (берёт из hero_sheets.json)",
			not consts.has("PIXEL_CELL_2") and not consts.has("PIXEL_CELL_1_FRAMES"))
	check("шейдер чёткости существует", ResourceLoader.exists("res://shaders/pixel_art.gdshader"))
	check("у листов героя cell = 2", int(inf.get("cell", 0)) == 2)

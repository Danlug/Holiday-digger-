extends Node
## test_hero_art — перерисованный мальчик (tools/gen_hero_art.py, ветка «hero-art»):
## те же имена файлов и размеры холстов, что у авторской нарезки
## (art/_source/hero_cut/), те же опорные точки (подошва на линии земли, рука с
## инструментом не ближе и не дальше), альфа только 0/255 (ни одного
## полупрозрачного пикселя), светлой каймы по краю нет, перерисованные листы —
## на сетке 2×2 текселя, и шейдер чёткости героя знает именно их.
##
## Запуск:  godot --headless --path . res://tests/test_hero_art.tscn

const CUT := "res://art/_source/hero_cut/"
const OUT := "res://art/character/"

## [лист, ширина кадра, перерисован ли (иначе авторский кадр без каймы)].
## Тот же список, что SHEETS в tools/gen_hero_art.py.
const SHEETS := [
	["idle", 144, true], ["idle_x", 144, true], ["walk", 144, true],
	["fall", 144, true], ["jump", 144, true], ["hurt", 144, true],
	["fly", 144, true], ["fly_jet", 144, true],
	["fly_1", 154, true], ["fly_2", 204, true], ["fly_3", 152, true], ["fly_4", 260, true],
	["dig_pick", 192, true], ["dig_pick_rusty", 192, true], ["dig_shovel", 192, true],
	["dig_drill_down", 144, true], ["dig_drill_side", 144, true], ["sleep", 144, true],
	["boy/walk", 144, true],
	["boy/age_8", 47, true], ["boy/age_9", 47, true], ["boy/age_10", 47, true],
	["boy/age_11", 47, true], ["boy/age_12", 47, true], ["boy/age_15", 47, true],
	["boy_gear/idle", 144, false], ["boy_gear/walk", 144, false], ["boy_gear/fall", 144, false],
	["boy_gear/fly", 144, false], ["boy_gear/fly_jet", 144, false],
	["boy_gear/dig_pick", 144, false], ["boy_gear/dig_shovel", 144, false],
	["boy_gear/sleep", 144, false],
]
## Кадры перерисованных листов, оставленные авторскими (без каймы): замах с
## руками над головой. Тот же список — PIXEL_CELL_1_FRAMES в character_view.gd.
const KEPT_FRAMES := {"dig_pick": [0, 1, 2], "dig_pick_rusty": [0, 1, 2]}
## Листы сюжетного «мальчика» — копии листов героя.
const COPIES := {
	"boy/idle": "idle", "boy/fall": "fall", "boy/sleep": "sleep",
	"boy/dig_pick": "dig_pick", "boy/dig_pick_rusty": "dig_pick_rusty",
	"boy/dig_shovel": "dig_shovel", "boy/dig_drill_down": "dig_drill_down",
	"boy/dig_drill_side": "dig_drill_side", "boy/fly": "fly", "boy/fly_jet": "fly_jet",
}

var failures := 0
var total := 0


func _ready() -> void:
	print("=== test_hero_art ===")
	for row in SHEETS:
		_test_sheet(String(row[0]), int(row[1]), bool(row[2]))
	_test_copies()
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


func _test_sheet(rel: String, fw: int, redrawn: bool) -> void:
	var cut := _img(CUT + rel + ".png")
	var img := _img(OUT + rel + ".png")
	check("%s: есть и снимок нарезки, и лист" % rel, cut != null and img != null)
	if cut == null or img == null:
		return
	var w := img.get_width()
	var h := img.get_height()
	check("%s: холст тот же (%d×%d)" % [rel, w, h], w == cut.get_width() and h == cut.get_height())
	check("%s: ширина кратна кадру %d" % [rel, fw], w % fw == 0)
	var d := img.get_data()
	var c := cut.get_data()

	# Альфа только 0/255.
	var partial := 0
	for i in range(3, d.size(), 4):
		if d[i] != 0 and d[i] != 255:
			partial += 1
	check("%s: полупрозрачных пикселей нет (%d)" % [rel, partial], partial == 0)

	# Сетка 2×2: каждый квадрат 2×2 от верхнего левого угла — один цвет.
	if redrawn:
		var kept: Array = KEPT_FRAMES.get(rel, [])
		var broken := 0
		for y in range(0, h - 1, 2):
			for x in range(0, w - 1, 2):
				if kept.has(x / fw):
					continue
				var i := (y * w + x) * 4
				for o in [4, w * 4, w * 4 + 4]:
					for k in 4:
						if d[i + k] != d[i + o + k]:
							broken += 1
							break
		check("%s: рисунок на сетке 2×2 текселя (нарушений %d)" % [rel, broken], broken == 0)

	# Светлый край: доля светлых серо-белых пикселей на краю силуэта. У авторских
	# кадров это кайма от подложки (в idle — половина края). Остаётся только
	# светлое само по себе: дуга замаха, искры, белые баллоны джетпака.
	var e_new := _light_edge(d, w, h)
	var e_old := _light_edge(c, w, h)
	var limit := 0.04 if redrawn else 0.12
	var share: float = float(e_new.x) / maxf(1.0, float(e_new.y))
	check("%s: светлый край %.1f%% (было %.1f%%), не больше %d%%" % [rel, share * 100.0,
			float(e_old.x) * 100.0 / maxf(1.0, float(e_old.y)), int(limit * 100.0)],
			share <= limit and e_new.x <= e_old.x)

	# Опорные точки: рамка рисунка в каждом кадре там же (подошва на линии
	# земли, рука с инструментом и винт там же).
	var worst_bottom := 0
	var worst_side := 0
	var worst_top := 0
	var empty := 0
	for f in range(w / fw):
		var bn := _bbox(d, w, f * fw, fw, h)
		var bc := _bbox(c, w, f * fw, fw, h)
		if bn.size() == 0 or bc.size() == 0:
			empty += 1
			continue
		worst_top = maxi(worst_top, absi(bn[0] - bc[0]))
		worst_bottom = maxi(worst_bottom, absi(bn[1] - bc[1]))
		worst_side = maxi(worst_side, maxi(absi(bn[2] - bc[2]), absi(bn[3] - bc[3])))
	check("%s: пустых кадров нет" % rel, empty == 0)
	check("%s: подошва там же (сдвиг %d ≤ 1)" % [rel, worst_bottom], worst_bottom <= 1)
	check("%s: верх рисунка там же (сдвиг %d ≤ 2)" % [rel, worst_top], worst_top <= 2)
	check("%s: края (рука, инструмент, винт) там же (сдвиг %d ≤ 3)" % [rel, worst_side], worst_side <= 3)


## Vector2i(светлых пикселей края, всего пикселей края).
func _light_edge(d: PackedByteArray, w: int, h: int) -> Vector2i:
	var light := 0
	var edge := 0
	for y in h:
		for x in w:
			var i := (y * w + x) * 4
			if d[i + 3] < 128:
				continue
			var is_edge := x == 0 or y == 0 or x == w - 1 or y == h - 1 \
					or d[i - 4 + 3] < 128 or d[i + 4 + 3] < 128 \
					or d[i - w * 4 + 3] < 128 or d[i + w * 4 + 3] < 128
			if not is_edge:
				continue
			edge += 1
			var r := d[i]
			var g := d[i + 1]
			var b := d[i + 2]
			var lum := 0.299 * r + 0.587 * g + 0.114 * b
			if lum > 170.0 and maxi(r, maxi(g, b)) - mini(r, mini(g, b)) < 40:
				light += 1
	return Vector2i(light, edge)


## [верх, низ, лево, право] непрозрачного в кадре или [] — кадр пуст.
func _bbox(d: PackedByteArray, w: int, x0: int, fw: int, h: int) -> Array:
	var top := h
	var bottom := -1
	var left := fw
	var right := -1
	for y in h:
		for x in fw:
			if d[(y * w + x0 + x) * 4 + 3] >= 128:
				top = mini(top, y)
				bottom = maxi(bottom, y)
				left = mini(left, x)
				right = maxi(right, x)
	if bottom < 0:
		return []
	return [top, bottom, left, right]


func _test_copies() -> void:
	for dst: String in COPIES:
		var a := _img(OUT + dst + ".png")
		var b := _img(OUT + String(COPIES[dst]) + ".png")
		check("%s совпадает с %s (сюжетный мальчик = герой)" % [dst, COPIES[dst]],
				a != null and b != null and a.get_data() == b.get_data())


## Шейдер чёткости: cell=2 ровно у перерисованных листов героя, и у всех них
## ширина кадра в CharacterView та же, что у генератора.
func _test_view_contract() -> void:
	var view_script: GDScript = load("res://scripts/player/character_view.gd")
	var consts: Dictionary = view_script.get_script_constant_map()
	var cell2: Array = consts.get("PIXEL_CELL_2", [])
	var frames: Dictionary = consts.get("SHEET_FRAME", {})
	var redrawn := {}
	for row in SHEETS:
		if bool(row[2]) and not String(row[0]).contains("/"):
			redrawn[String(row[0])] = int(row[1])
	check("шейдер чёткости знает все перерисованные листы героя", cell2.size() == redrawn.size())
	for name: String in cell2:
		check("%s: перерисован (cell=2 у шейдера верно)" % name, redrawn.has(name))
		if redrawn.has(name):
			var fw: int = int(frames[name][0]) if frames.has(name) else 144
			check("%s: ширина кадра у героя и генератора одна (%d)" % [name, fw], fw == int(redrawn[name]))
	check("шейдер чёткости существует", ResourceLoader.exists("res://shaders/pixel_art.gdshader"))
	check("шейдер знает авторские кадры среди перерисованных",
			consts.get("PIXEL_CELL_1_FRAMES", {}) == KEPT_FRAMES)

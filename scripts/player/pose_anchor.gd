class_name PoseAnchor
extends RefCounted
## PoseAnchor — единые метаданные привязки кадров героя и актёров сцен
## (art/character/poses.json): размер кадра, линия земли и ось тела на позу
## и одна формула, куда класть Sprite2D, чтобы подошва легла на низ клетки,
## а ось тела — на x персонажа.
##
## Зачем одно место: геометрия жила тремя таблицами — SHEET_FRAME в
## character_view.gd, «144 или 192» в world_actor.gd и «144 или весь файл» в
## cutscene_player.gd — и расходились молча: в классической сцене широкий лист
## копки мальчика (кадр 192) показывался целой полосой из восьми кадров, а бур
## вбок рисовался на 6 логических px левее героя. Теперь числа — в JSON (их
## меряет tools/audit_boy_frames.py, проверяет tests/test_boy_scale.gd), а
## рисовальщики только спрашивают geom() и sprite_position().
##
## Пиксели — текстуры (ART_SCALE=3 к логическим). ground_y — первая строка
## ПОД подошвой; axis_x — ось тела, при развороте зеркально (frame_w − axis_x).

const PATH := "res://art/character/poses.json"
const ART_SCALE := 3.0
const TILE := 32.0
## Полувысота хитбокса героя — та же, что в физике (player.gd:HH): стоя на
## земле, низ хитбокса лежит ровно на низу клетки.
const HERO_HH: float = preload("res://scripts/player/player.gd").HH
## Линия ступней ГЕРОЯ относительно его точки (player.x, player.y): низ
## хитбокса. Раньше рисовка считалась от старой полувысоты 0,46
## (−0,46·TILE − 16 + 138/3 = 15,28), а физика давно стоит на 1/3 (10,67) —
## подошвы уходили в землю на 4,6 px в любой позе (ГДД, house-look: «герой
## стоит на ≈4 px ниже линии земли»).
const FEET_Y_HERO := HERO_HH * TILE
## Линия ступней АКТЁРА сцен (WorldActor): его точка — центр клетки
## (y = ряд + 0,5, см. cutscene_player.gd:_world_land), ступни — на низу клетки.
const FEET_Y_ACTOR := TILE / 2.0

## Резерв на случай отсутствия JSON: квадрат 144, земля 138, ось посередине.
const FALLBACK_DEFAULT := {"frame_w": 144, "frame_h": 144, "ground_y": 138, "axis_x": 72}

static var _doc: Dictionary = {}
static var _loaded := false
static var _cache: Dictionary = {}


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_doc = parsed


## Весь документ (тестам и аудиту).
static func doc() -> Dictionary:
	_ensure()
	return _doc


## Геометрия кадра позы: frame_w, frame_h, ground_y, axis_x, ref_frame (int)
## плюс остальные поля записи (sole_tol, note …). dir — папка актёра сцен
## (art/character/<dir>/); "" и "boy" — листы героя.
static func geom(pose: String, dir: String = "") -> Dictionary:
	_ensure()
	var key := dir + "/" + pose
	if _cache.has(key):
		return _cache[key]
	var out: Dictionary = FALLBACK_DEFAULT.duplicate()
	_merge(out, _doc.get("default", {}))
	# Перекрашенные варианты бура (dig_rig_side_titanium …) — та же геометрия,
	# что у базового листа: суффиксы перечислены в JSON (suffix_variants).
	var base := pose
	for suffix in _doc.get("suffix_variants", []):
		if pose.ends_with(String(suffix)):
			base = pose.trim_suffix(String(suffix))
			break
	if dir.is_empty() or dir == "boy":
		_merge(out, _doc.get("poses", {}).get(base, {}))
	if not dir.is_empty():
		_merge(out, _doc.get("actors_common", {}).get(base, {}))
	_merge(out, _doc.get("actors", {}).get(dir, {}).get(base, {}))
	for k in ["frame_w", "frame_h", "ground_y", "axis_x", "ref_frame"]:
		if out.has(k):
			out[k] = int(out[k])
	_cache[key] = out
	return out


static func _merge(dst: Dictionary, src) -> void:
	if src is Dictionary:
		for k in src.keys():
			dst[k] = src[k]


## Сколько кадров в листе tex по ширине кадра позы. Ширина, не кратная кадру,
## — один кадр на весь лист (одиночные позы), чтобы неверный делитель не
## резал картинку на ломти.
static func frames(tex: Texture2D, pose: String, dir: String = "") -> int:
	if tex == null:
		return 1
	var fw: int = geom(pose, dir)["frame_w"]
	var w: int = int(round(tex.get_width()))
	if fw <= 0 or w % fw != 0:
		return 1
	return maxi(1, w / fw)


## Левый верхний угол Sprite2D (centered=false, scale = k/ART_SCALE)
## относительно точки персонажа: линия земли кадра ложится на feet_y
## (FEET_Y_HERO у героя, FEET_Y_ACTOR у актёров сцен), ось тела — на x = 0.
## k — рост относительно героя (бабушки 0.92), flip — разворот влево.
static func sprite_position(pose: String, dir: String = "", flip: bool = false, k: float = 1.0,
		feet_y: float = FEET_Y_HERO) -> Vector2:
	var g := geom(pose, dir)
	var axis: float = float(g["axis_x"]) if not flip else float(g["frame_w"] - g["axis_x"])
	return Vector2(-axis * k / ART_SCALE, feet_y - float(g["ground_y"]) * k / ART_SCALE)

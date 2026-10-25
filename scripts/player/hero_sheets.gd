class_name HeroSheets
extends RefCounted
## Геометрия листов мальчика высокого разрешения (раунд 4, «boy-art»).
##
## Листы мальчика нарисованы по эталону владельца в 8 текселях на логическую
## точку (4 пикселя рисунка × 2 текселя), а не в 3, как прочие персонажи, и
## длинные ленты разложены в несколько рядов (лимит 4096 мобильного WebGL).
## Геометрию пишет tools/gen_hero_ref.py в art/character/hero_sheets.json:
## fw/fh — кадр в текселях, ground — линия земли (подошва на строке над ней),
## scale — текселей на точку, cell — текселей на пиксель рисунка, cols —
## кадров в ряду, frames — сколько кадров. Лист, которого в файле нет, —
## прежний: один ряд, ART_SCALE 3 (дед, бабушки, Роберт, бурмобиль).

const META_PATH := "res://art/character/hero_sheets.json"
const ROOT := "res://art/character/"
const LEGACY_SCALE := 3.0
const SHADER := preload("res://shaders/pixel_art.gdshader")

static var _sheets: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(META_PATH):
		return
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and parsed.get("sheets") is Dictionary:
		_sheets = parsed["sheets"]


## Геометрия листа по имени относительно art/character/ без .png
## («idle», «boy/walk»); {} — лист прежний (ART_SCALE 3, один ряд).
static func info(rel: String) -> Dictionary:
	_load()
	return _sheets.get(rel, {})


## То же по текстуре (по её пути).
static func info_for(tex: Texture2D) -> Dictionary:
	if tex == null:
		return {}
	var path := tex.resource_path
	if not path.begins_with(ROOT):
		return {}
	return info(path.substr(ROOT.length()).get_basename())


static func scale_of(inf: Dictionary) -> float:
	return float(inf.get("scale", LEGACY_SCALE))


static func frames_of(inf: Dictionary) -> int:
	return int(inf.get("frames", 1))


## Прямоугольник кадра в текстуре (кадры идут слева направо, сверху вниз).
static func region(inf: Dictionary, frame: int) -> Rect2:
	var fw := float(inf["fw"])
	var fh := float(inf["fh"])
	var cols := maxi(1, int(inf.get("cols", 1)))
	var n := maxi(1, frames_of(inf))
	var i := posmod(frame, n)
	return Rect2(float(i % cols) * fw, float(i / cols) * fh, fw, fh)


## Чёткий пиксель-арт на нецелом масштабе: шейдер shaders/pixel_art.gdshader
## (середина пикселя рисунка из его центра, смешение — только на границе в
## экранный пиксель) и линейный фильтр под ним. Прежним листам — как было.
static func crisp(item: CanvasItem, inf: Dictionary) -> void:
	if inf.is_empty():
		if item.material != null and (item.material as ShaderMaterial) != null \
				and (item.material as ShaderMaterial).shader == SHADER:
			item.material = null
			item.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
		return
	var mat := item.material as ShaderMaterial
	if mat == null or mat.shader != SHADER:
		mat = ShaderMaterial.new()
		mat.shader = SHADER
		item.material = mat
	item.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mat.set_shader_parameter("cell", float(inf.get("cell", 1.0)))


## Кадр по прямоугольнику (обратное region) — для тестов и отладки.
static func frame_at(inf: Dictionary, rect: Rect2) -> int:
	var cols := maxi(1, int(inf.get("cols", 1)))
	return int(round(rect.position.y / float(inf["fh"]))) * cols + int(round(rect.position.x / float(inf["fw"])))

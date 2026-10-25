class_name DialogueCast
extends RefCounted
## Труппа диалогов: кто из говорящих какой портрет носит, с какой стороны стоит,
## каким «голосом» бипает и какое у него сейчас лицо.
##
## Портреты — листы art/dialogue/portrait_<id>.png (tools/gen_portraits.py):
## столбцы — кадры FRAMES, строки — выражения FACES, ячейка CELL×CELL. Данные
## (сторона, высота блипа, цвет ленточки, замены лиц по ключу реплики) лежат в
## data/dialogue.json: это оформление, а не сюжет — трогать сценарий не нужно.

const PATH := "res://data/dialogue.json"
const SHEET := "res://art/dialogue/portrait_%s.png"
const CELL := 64
const FACES := ["neutral", "surprise", "happy", "angry", "sad"]
const FRAMES := ["idle", "talk", "blink"]
const DEFAULT_ACCENT := Color8(0x8A, 0x7A, 0x5A)

static var _doc: Dictionary = {}
static var _sheets: Dictionary = {}


static func _ensure() -> void:
	if not _doc.is_empty():
		return
	_doc = {"speakers": {}, "typing": {}, "faces": {}}
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) == TYPE_DICTIONARY:
		_doc = raw


static func speaker(who: String) -> Dictionary:
	_ensure()
	return _doc.get("speakers", {}).get(who, {})


static func has_speaker(who: String) -> bool:
	return not speaker(who).is_empty()


## Параметры печати из data/dialogue.json с запасными значениями.
static func typing_param(key: String, fallback: float) -> float:
	_ensure()
	return float(_doc.get("typing", {}).get(key, fallback))


## Какой лист показывать: если на сцене стоит «экипированный» двойник говорящего
## (boy_gear при говорящем boy), берём его портрет.
static func portrait_id(who: String, stage_actors: Array = []) -> String:
	var sp := speaker(who)
	if sp.is_empty():
		return ""
	var variants: Dictionary = sp.get("variants", {})
	if not stage_actors.has(who):
		for actor_id in variants.keys():
			if stage_actors.has(actor_id):
				return String(variants[actor_id])
	return String(sp.get("portrait", who))


static func sheet(portrait: String) -> Texture2D:
	if portrait.is_empty():
		return null
	if _sheets.has(portrait):
		return _sheets[portrait]
	var path := SHEET % portrait
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_sheets[portrait] = t
	return t


static func face_index(face: String) -> int:
	var i := FACES.find(face)
	return maxi(i, 0)


## Прямоугольник кадра в листе: строка — выражение, столбец — idle/talk/blink.
## cell — сторона кадра в текселях листа (64; у мальчика по эталону — 128,
## пиксель рисунка 2×2, см. tools/gen_hero_ref.py).
static func region(face: String, frame: int, cell: int = CELL) -> Rect2:
	return Rect2(frame * cell, face_index(face) * cell, cell, cell)


## Сторона кадра листа по его ширине (кадров в ряду — FRAMES).
static func cell_of(tex: Texture2D) -> int:
	return CELL if tex == null else maxi(1, int(tex.get_width()) / FRAMES.size())


static func side(who: String) -> String:
	return String(speaker(who).get("side", "right"))


static func pitch(who: String) -> float:
	return float(speaker(who).get("pitch", 1.0))


static func blip_db(who: String) -> float:
	return float(speaker(who).get("blip_db", typing_param("blip_db", -10.0)))


static func accent(who: String) -> Color:
	var sp := speaker(who)
	if sp.has("accent"):
		return Color.html(String(sp["accent"]))
	return DEFAULT_ACCENT


## Цвет текста реплики: у большинства общий, у «Голоса» — свой, чтобы читался чужим.
static func text_color(who: String) -> Color:
	var sp := speaker(who)
	if sp.has("text"):
		return Color.html(String(sp["text"]))
	return DialogueStyle.TEXT


## Выражение лица по реплике. Сначала явная замена по ключу текста
## (data/dialogue.json: faces), иначе по знакам препинания — они одинаковы в
## любом языке, так что подбор не привязан к русскому тексту.
static func guess_face(who: String, text: String, key: String = "") -> String:
	_ensure()
	var forced := String(_doc.get("faces", {}).get(key, ""))
	if FACES.has(forced):
		return forced
	if who == "voice":
		return "neutral"
	var t := text.strip_edges()
	if t.contains("?!") or t.contains("!?"):
		return "surprise"
	var trailing_dots := t.ends_with("...") or t.ends_with("…")
	var leading_dots := t.begins_with("...") or t.begins_with("…")
	if (leading_dots or trailing_dots) and t.contains("?"):
		return "surprise"
	if leading_dots or trailing_dots:
		return "sad"
	if t.ends_with("!"):
		return "angry"
	return "neutral"


## Все, кто хоть раз говорит в сценах сюжета (для проверки, что у каждого есть портрет).
static func speakers_in_story() -> Array:
	StoryData.ensure_loaded()
	var seen := {}
	for sid in StoryData.scene_ids():
		for beat in StoryData.beats(String(sid)):
			if String(beat.get("t", "")) == "say":
				seen[String(beat.get("who", ""))] = true
	return seen.keys()


## Только для тестов: следующий вызов перечитает файлы.
static func _reset_for_tests() -> void:
	_doc = {}
	_sheets.clear()

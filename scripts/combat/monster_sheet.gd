class_name MonsterSheet
extends RefCounted
## MonsterSheet — лист кадров монстра (art/monsters/<id>.png + <id>.json, их
## делает tools/gen_monsters.py). Строка листа — анимация (idle, move, attack,
## die, у засадника ещё dormant), столбцы — кадры. Графика в ART_SCALE раз
## подробнее клетки, как у героя: рисуем уменьшенной, а подробности достаются
## экрану телефона.

const ART_SCALE := 3.0
const DIR := "res://art/monsters/"

static var _cache: Dictionary = {}

var texture: Texture2D = null
var meta: Dictionary = {}
var frame_w: float = 32.0      # логические px
var frame_h: float = 32.0
var foot: float = 0.0          # от низа кадра до линии земли, логические px
var anchor_feet: bool = true


static func get_sheet(id: String) -> MonsterSheet:
	if _cache.has(id):
		return _cache[id]
	var s := MonsterSheet.new()
	var png := DIR + id + ".png"
	if ResourceLoader.exists(png):
		s.texture = load(png)
	var jf := FileAccess.open(DIR + id + ".json", FileAccess.READ)
	if jf != null:
		var parsed = JSON.parse_string(jf.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			s.meta = parsed
		jf.close()
	var fr: Array = s.meta.get("frame", [32, 32])
	s.frame_w = float(fr[0])
	s.frame_h = float(fr[1])
	s.foot = float(s.meta.get("foot", 0))
	s.anchor_feet = String(s.meta.get("anchor", "feet")) == "feet"
	_cache[id] = s
	return s


func has_anim(anim: String) -> bool:
	return (meta.get("anims", {}) as Dictionary).has(anim)


## Область листа для анимации anim в момент t секунд от её начала.
func region(anim: String, t: float) -> Rect2:
	var anims: Dictionary = meta.get("anims", {})
	var a: Dictionary = anims.get(anim, anims.get("idle", {"row": 0, "frames": 1, "fps": 1, "loop": true}))
	var n := maxi(1, int(a.get("frames", 1)))
	var fps := float(a.get("fps", 6))
	var i := int(floor(t * fps))
	if bool(a.get("loop", true)):
		i = i % n
	else:
		i = mini(i, n - 1)
	var s := ART_SCALE
	return Rect2(float(i) * frame_w * s, float(int(a.get("row", 0))) * frame_h * s, frame_w * s, frame_h * s)


## Кадр по доле прогресса 0..1 (замах босса, смерть) вместо времени.
func region_progress(anim: String, p: float) -> Rect2:
	var anims: Dictionary = meta.get("anims", {})
	var a: Dictionary = anims.get(anim, anims.get("idle", {"row": 0, "frames": 1}))
	var n := maxi(1, int(a.get("frames", 1)))
	var i := clampi(int(floor(p * float(n))), 0, n - 1)
	var s := ART_SCALE
	return Rect2(float(i) * frame_w * s, float(int(a.get("row", 0))) * frame_h * s, frame_w * s, frame_h * s)

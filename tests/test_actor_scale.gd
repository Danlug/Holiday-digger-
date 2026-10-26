extends Node
## test_actor_scale.gd — рост сюжетных актёров рядом с героем и вид двора у дома
## (ветка «house-look», 26.10: «Бабка маленькая, и я хочу чтобы перед домом
## показывали травку, а не землю»).
##
##   - на живой карте актёры в одном масштабе с героем: внук, дед, Роберт — его
##     роста, бабушки чуть ниже (90–95 %), никто не вдвое; ступни — на земле;
##   - развёртка "grow" (мальчик ×2.2) не переживает тап и "clear": это она
##     висела великаном поверх живой карты на скриншоте владельца;
##   - в интро внука ни внук, ни бабушка не стоят на могиле деда;
##   - перед домом лежит травяная кромка — только вид, целиком в ряду y=0.
##
## Запуск:
##   godot --headless --path . res://tests/test_actor_scale.tscn

const ALPHA_MIN := 40
## Рост на экране относительно героя: свои — «как герой», бабушки — чуть ниже.
const SAME_MIN := 0.97
const SAME_MAX := 1.05
const ELDER_MIN := 0.88
const ELDER_MAX := 0.96
const ELDERS := ["grandma_poor", "grandma_rich"]

var failures := 0
var total := 0


func _ready() -> void:
	_run()


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name,
		("  " + detail) if not ok and not detail.is_empty() else ""])


func _run() -> void:
	print("=== test_actor_scale.gd ===")
	_test_heights_and_feet()
	_test_grow_does_not_outlive_its_beat()
	_test_intro_boy_clear_of_grave()
	await _test_front_lawn()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


## Непрозрачная рамка первого кадра листа (x0, y0, x1, y1) в пикселях текстуры.
func _bbox(path: String, frame_w: int) -> Rect2i:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return Rect2i()
	var x0 := frame_w
	var y0 := img.get_height()
	var x1 := -1
	var y1 := -1
	for y in img.get_height():
		for x in mini(frame_w, img.get_width()):
			if img.get_pixel(x, y).a8 > ALPHA_MIN:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _test_heights_and_feet() -> void:
	# Герой: тот же узел, что рисует его в игре (scripts/player/character_view.gd).
	var cv: Node2D = preload("res://scripts/player/character_view.gd").new()
	add_child(cv)
	var hero_sprite: Sprite2D = cv.get_child(0)
	var hero_box := _bbox("res://art/character/idle.png", 144)
	var hero_h: float = hero_box.size.y * hero_sprite.scale.y
	# Подошва героя относительно его точки (x, y) — та же формула, что в _process.
	var hero_feet: float = -cv.HH * cv.TILE - 16.0 + float(hero_box.end.y) / cv.ART_SCALE
	check("рост героя на экране — около 40 логических px (121 px листа / 3)",
		hero_h > 36.0 and hero_h < 44.0, "%.1f" % hero_h)
	cv.queue_free()

	var ids: Array = []
	for id in ["boy", "boy_gear", "grandpa", "grandpa_gear", "grandma_poor", "grandma_rich", "robert"]:
		ids.append(id)
	for id: String in ids:
		var path := StoryData.actor_sheet_path(id, "idle")
		check("%s: есть лист стойки" % id, ResourceLoader.exists(path), path)
		if not ResourceLoader.exists(path):
			continue
		var a := WorldActor.new()
		a.setup(id)
		a.x = 10.5
		a.y = 0.5
		add_child(a)
		a._process(0.0)
		var spr: Sprite2D = a.get_child(0)
		var box := _bbox(path, 144)
		var h: float = box.size.y * spr.scale.y
		var ratio: float = h / hero_h
		var lo := ELDER_MIN if ELDERS.has(id) else SAME_MIN
		var hi := ELDER_MAX if ELDERS.has(id) else SAME_MAX
		check("%s: рост на экране %.0f%% героя (нужно %d–%d%%)" % [id, ratio * 100.0, int(lo * 100), int(hi * 100)],
			ratio >= lo and ratio <= hi, "%.1f px против %.1f" % [h, hero_h])
		# Ступни: низ рисунка — там же, где у героя, при любом росте.
		var feet: float = spr.position.y + float(box.end.y) * spr.scale.y
		check("%s: ступни на линии земли героя (±0.6 px)" % id, absf(feet - hero_feet) <= 0.6,
			"%.2f против %.2f" % [feet, hero_feet])
		var world_feet: float = a.y * a.TILE + feet
		check("%s: стоя на поверхности (y=0.5), ступни у кромки земли y=32" % id,
			world_feet > 29.0 and world_feet < 34.0, "%.1f" % world_feet)
		# Классическая иллюстрация (катсцена без живой карты) держит то же соотношение.
		check("%s: рост в иллюстрации тот же, что на карте" % id,
			is_equal_approx(StoryData.actor_height(id), a.height_k))
		a.queue_free()


## Тап по развёртке "grow" в интро внука — дальше "hide", "mood", "fade": мальчик
## ×2.2 не должен вернуться ни через полсекунды, ни после "clear".
func _test_grow_does_not_outlive_its_beat() -> void:
	var cs := CutscenePlayer.new()
	add_child(cs)
	cs.play("intro_boy")
	var guard := 0
	while cs.is_playing and cs._index < cs._beats.size() and guard < 10:
		guard += 1
		var prev: Dictionary = cs._beats[cs._index - 1] if cs._index > 0 else {}
		if String(prev.get("t", "")) == "grow":
			break
		cs._beat_timer = 0.0
		cs._advance()
	check("интро внука дошло до развёртки «рост»", not cs._grow_poses.is_empty())
	check("развёртка показала мальчика крупным планом", cs._actors.has("boy")
		and is_equal_approx(float(cs._actors["boy"].scale), 2.2))
	# Тап: как _input() — таймер в ноль, следующий кадр.
	cs._process(0.05)
	cs._waiting_tap = false
	cs._beat_timer = 0.0
	cs._advance()
	check("после тапа «hide» убрал мальчика", not cs._actors.has("boy"))
	for _i in 4:
		cs._process(0.15)   # 0.6 с — меньше затемнения 0.7 с: свой "show" ещё не наступил
	check("через 0.6 с после тапа развёртка не вернула мальчика ×2.2", not cs._actors.has("boy"),
		"актёры: %s" % str(cs._actors.keys()))
	# Дальше до живой карты: на ней классических актёров быть не должно вовсе.
	guard = 0
	while cs.is_playing and not cs.world_mode and guard < 40:
		guard += 1
		cs._process(0.2)
		if cs._typing:
			cs._dlg.finish_typing()
		cs._waiting_tap = false
		cs._beat_timer = 0.0
		cs._advance()
	for _i in 10:
		cs._process(0.3)
	check("интро внука вошло на живую карту", cs.world_mode)
	check("на живой карте нет иллюстрированного мальчика поверх неё", cs._actors.is_empty(),
		"актёры: %s" % str(cs._actors.keys()))
	cs.skip()
	cs.queue_free()


## Ширина рисунка актёра по X в логических px мира: [левый, правый] край.
func _actor_span(id: String, x: float, flip: bool) -> Vector2:
	var box := _bbox(StoryData.actor_sheet_path(id, "idle"), 144)
	var k := StoryData.actor_height(id) / 3.0
	var l := float(box.position.x) - 72.0
	var r := float(box.end.x) - 72.0
	if flip:
		var t := l
		l = -r
		r = -t
	return Vector2(x * 32.0 + l * k, x * 32.0 + r * k)


func _test_intro_boy_clear_of_grave() -> void:
	var stone := _bbox(GraveSite.STONE_TEX, 128)
	var gw := 128.0 * GraveSite.STONE_SCALE
	var g0 := GraveSite.GRAVE_X * 32.0 - gw / 2.0 + stone.position.x * GraveSite.STONE_SCALE
	var g1 := GraveSite.GRAVE_X * 32.0 - gw / 2.0 + stone.end.x * GraveSite.STONE_SCALE
	var pos: Dictionary = {}
	var flips: Dictionary = {}
	var spoke := 0
	for beat: Dictionary in StoryData.beats("intro_boy"):
		var t := String(beat.get("t", ""))
		var id := String(beat.get("actor", ""))
		if t == "world_actor":
			if beat.has("x"):
				pos[id] = float(beat.x)
			flips[id] = bool(beat.get("flip", flips.get(id, false)))
		elif t == "world_walk":
			pos[id] = float(beat.x)
		elif t == "hide":
			pos.erase(id)
		elif t == "say" or t == "narr":
			spoke += 1
			for who: String in pos.keys():
				var span := _actor_span(who, float(pos[who]), bool(flips.get(who, false)))
				check("интро внука, реплика %d: %s (x=%.2f) не стоит на могиле деда" % [spoke, who, float(pos[who])],
					span.y < g0 or span.x > g1, "актёр %.0f..%.0f, могила %.0f..%.0f" % [span.x, span.y, g0, g1])
	check("в интро внука на могилу проверены реплики", spoke > 5)


func _test_front_lawn() -> void:
	var lawn := FrontLawn.new()
	add_child(lawn)
	await get_tree().process_frame
	var r := lawn.world_rect()
	check("травяная кромка: текстура на месте", lawn._tex != null)
	check("кромка — весь двор дома, от края карты до огорода",
		is_equal_approx(r.position.x, 0.0) and is_equal_approx(r.end.x, WorldGen.GARDEN_X_MIN * 32.0), str(r))
	check("кромка стоит низом на кромке земли (y=32) и целиком в ряду y=0 — копку и землю не трогает",
		is_equal_approx(r.end.y, 32.0) and r.position.y >= 0.0, str(r))
	check("кромка невысокая — фасад и дверь видны (не выше трети клетки и выше 6 px)",
		r.size.y >= 6.0 and r.size.y <= 16.0, str(r.size.y))
	lawn.queue_free()
	# Дом сам кладёт кромку поверх фасада и под пакет у двери.
	var hs := HouseSystem.new()
	add_child(hs)
	await get_tree().process_frame
	var ext := hs.get_node_or_null("HouseExterior")
	var fl := hs.get_node_or_null("FrontLawn")
	check("дом положил травяную кромку", fl != null)
	if ext != null and fl != null:
		check("кромка рисуется сразу после фасада (поверх цоколя, под пакетом у двери)",
			fl.get_index() == ext.get_index() + 1, "%d / %d" % [fl.get_index(), ext.get_index()])
	hs.queue_free()
	await get_tree().process_frame

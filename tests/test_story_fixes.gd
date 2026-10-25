extends Node
## test_story_fixes — правки сюжета раунда 5 (владелец), на настоящей main.tscn.
##
## Запуск: godot --headless --path . res://tests/test_story_fixes.tscn
##
##  1. Интро деда: «Пропустить» в любой момент (до копки, посреди ряда, посреди
##     фундамента, после ямы, у могилы) и пролистывание тапами дают то же итоговое
##     состояние, что и досмотренная сцена: мир, эпоха, туман, герой, камера, часы,
##     ни одного актёра на карте. Пока сцену листают, дед ни разу не стоит в целой
##     породе и копает свою шахту, а не соседнюю клетку («будто под фундаментом»).
##  2. Сцена смерти: внук выкапывает вглубь шесть клеток, как дед, — откуда бы
##     ни начал (над пробитым фундаментом или уже в нём); после сцены он в
##     мастерской, сюжет идёт к ранцу; пропуск даёт то же, что просмотр.

const SEED := 4242
const FRAME_GUARD := 20000

var failures := 0
var total := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== test_story_fixes ===")
	await _test_intro_grandpa()
	await _test_death_six_cells()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _clean(seen: Array, flags: Array) -> void:
	for f in ["user://save.json", "user://save.json.bak", "user://records.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	GameState.reset_progress()
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	for id in seen:
		StoryState.mark_seen(id)
	for f in flags:
		StoryState.set_flag(f)
	GameState.world_seed = SEED


func _spawn_main() -> Node2D:
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	await _frames(4)
	return m


func _close_daily_popup() -> void:
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms) and ms.popup.is_open():
		ms.popup.close()


## Терпеливый зритель: реплику дочитывает, по тапу листает только то, что ждёт тапа.
func _watch_step(cs: CutscenePlayer) -> void:
	if cs._typing:
		cs._dlg.finish_typing()
	elif cs._waiting_tap:
		_tap(cs)


## Настоящий тап по сцене (тот же _input, что у пальца/мыши), без защиты от дребезга.
func _tap(cs: CutscenePlayer) -> void:
	cs._last_tap_ms = -100000
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = Vector2(100, 300)
	cs._input(ev)


func _current_beat(cs: CutscenePlayer) -> Dictionary:
	if cs._index <= 0 or cs._index > cs._beats.size():
		return {}
	return cs._beats[cs._index - 1]


func _live_world_actors(m: Node) -> int:
	var n := 0
	for c in m.view_root.get_children():
		if c is WorldActor and not c.is_queued_for_deletion():
			n += 1
	return n


func _snapshot(m: Node2D, d: StoryDirector) -> Dictionary:
	var dug: Array = d.world.diffs.keys()
	dug.sort()
	var cv: Node = m.find_child("CharacterView", true, false)
	return {
		"dug": dug,
		"era": "%s/%s" % [d.world.era, GameState.era],
		"fog": JSON.stringify(GameState.fog_ref.to_save_data(), "", true),
		"pos": Vector2(d.player.x, d.player.y),
		"actors": _live_world_actors(m) + d.cutscene._world_props.size(),
		"cv": cv != null and cv.visible,
		"scale": DayCycle.time_scale,
		"clock": GameState.game_clock_hours,
	}


## Камера успокаивается на герое (упреждение и сглаживание CameraRig).
func _settled_camera() -> Vector2:
	var last := Vector2.INF
	for _i in 600:
		await _frames(1)
		if CameraRig.current.distance_to(last) < 0.0005:
			break
		last = CameraRig.current
	return CameraRig.current


# ---------------------------------------------------------------------------
# 1. Интро деда
# ---------------------------------------------------------------------------

## Прогон интро деда. mode: "watch" — досмотреть; "tap" — листать тапами каждые
## два кадра; "skip" — досмотреть до кадра, на котором skip_at(beat) == true,
## подождать skip_delay кадров (посреди копки) и нажать «Пропустить».
func _run_intro(mode: String, skip_at: Callable = Callable(), skip_delay: int = 0) -> Dictionary:
	_clean([], [])
	var m := await _spawn_main()
	var d: StoryDirector = m.find_child("StoryDirector", true, false)
	var cs := d.cutscene
	var res := {"snap": {}, "in_rock": 0, "rock_at": "", "pit_ok": false, "pit_detail": "", "skipped_at": ""}
	var on_finished := func(id: String) -> void:
		if id == "intro_grandpa":
			res.snap = _snapshot(m, d)
	cs.finished.connect(on_finished)
	var guard := 0
	var skip_wait := -1
	var pit_checked := false
	while guard < FRAME_GUARD and not StoryState.is_seen("intro_grandpa"):
		guard += 1
		await _frames(1)
		_close_daily_popup()
		if not cs.is_playing or cs.scene_id != "intro_grandpa":
			continue
		var a: WorldActor = cs._world_actors.get("grandpa")
		if a != null and is_instance_valid(a):
			var body := Vector2i(int(floor(a.x)), int(floor(a.y - 0.01)))
			if body.y >= 1 and d.world.get_tile(body.x, body.y) != TileTypes.Type.EMPTY:
				res.in_rock += 1
				if res.rock_at.is_empty():
					res.rock_at = "(%d;%d) на кадре %d" % [body.x, body.y, cs._index - 1]
		var beat := _current_beat(cs)
		# Дно ямы: дед в «ловушке» стоит в своей шахте x=15 на глубине 6, вся шахта открыта.
		if not pit_checked and String(beat.get("text", "")) == "intro_grandpa.s_trapped" and a != null:
			pit_checked = true
			var shaft_open := true
			for y in range(1, 7):
				if d.world.get_tile(15, y) != TileTypes.Type.EMPTY:
					shaft_open = false
			res.pit_ok = shaft_open and is_equal_approx(a.x, 15.5) and is_equal_approx(a.y, 6.5)
			res.pit_detail = "шахта открыта: %s, дед в (%.2f; %.2f)" % [shaft_open, a.x, a.y]
		match mode:
			"watch":
				_watch_step(cs)
			"tap":
				if guard % 2 == 0:
					_tap(cs)
			"skip":
				if skip_wait < 0 and skip_at.call(beat):
					skip_wait = skip_delay
					res.skipped_at = "%d:%s" % [cs._index - 1, beat.get("t", "")]
				if skip_wait == 0:
					cs._skip_btn.confirmed.emit()   # та же связь, что у кнопки «Пропустить»
					skip_wait = -2
				elif skip_wait > 0:
					skip_wait -= 1
				else:
					_watch_step(cs)
	res["frames"] = guard
	res["camera"] = await _settled_camera()
	m.free()
	await _frames(2)
	return res


func _same(a: Dictionary, b: Dictionary) -> Array:
	var diff: Array = []
	for k in ["dug", "era", "fog", "actors", "cv", "scale"]:
		if a.get(k) != b.get(k):
			diff.append(k)
	if Vector2(a.get("pos", Vector2.INF)).distance_to(b.get("pos", Vector2.ZERO)) > 0.001:
		diff.append("pos")
	if absf(float(a.get("clock", -1.0)) - float(b.get("clock", 1.0e9))) > 0.05:
		diff.append("clock %.3f/%.3f" % [float(a.get("clock", -1.0)), float(b.get("clock", -1.0))])
	return diff


func _test_intro_grandpa() -> void:
	var ref := await _run_intro("watch")
	var snap: Dictionary = ref.snap
	check("интро деда досмотрено", not snap.is_empty(), "кадров %d" % ref.frames)
	if snap.is_empty():
		return
	check("досмотрено: яма деда засыпана, эпоха — внук, актёров на карте нет",
		snap.dug.is_empty() and snap.era == "now/now" and snap.actors == 0, str([snap.dug.size(), snap.era, snap.actors]))
	check("досмотрено: герой на старте обучения (20.5; 0.5), его спрайт виден",
		snap.pos == Vector2(20.5, 0.5) and snap.cv)
	check("досмотрено: часы деда не уходят в игру внука (утро первого дня)",
		snap.clock < 1.0 and is_equal_approx(snap.scale, 1.0), "часы %.2f, темп %.2f" % [snap.clock, snap.scale])
	check("досмотрено: дед ни разу не стоял в целой породе", ref.in_rock == 0, ref.rock_at)
	check("досмотрено: дно ямы — шахта x=15 до глубины 6, дед в ней", ref.pit_ok, ref.pit_detail)

	var tap := await _run_intro("tap")
	check("пролистано тапами: дед ни разу не стоял в целой породе", tap.in_rock == 0,
		"%d кадров, первый %s" % [tap.in_rock, tap.rock_at])
	check("пролистано тапами: дно ямы то же, что при просмотре", tap.pit_ok, tap.pit_detail)
	var tdiff := _same(tap.snap, snap)
	check("пролистано тапами: итог = досмотренной сцене", tdiff.is_empty(), str(tdiff))
	check("пролистано тапами: камера там же", Vector2(tap.camera).distance_to(ref.camera) < 0.01,
		"%s / %s" % [tap.camera, ref.camera])

	var points := {
		"до копки (первая реплика)": [func(b: Dictionary) -> bool: return String(b.get("text", "")) == "intro_grandpa.n1", 3],
		"посреди первого ряда": [func(b: Dictionary) -> bool: return b.get("t") == "world_dig_row" and int(b.get("y", 0)) == 1, 20],
		"посреди третьего ряда": [func(b: Dictionary) -> bool: return b.get("t") == "world_dig_row" and int(b.get("y", 0)) == 3, 20],
		"посреди копки фундамента": [func(b: Dictionary) -> bool: return b.get("t") == "world_dig" and int(b.get("y", 0)) == 5, 10],
		"после ямы («сейчас вылезу»)": [func(b: Dictionary) -> bool: return String(b.get("text", "")) == "intro_grandpa.s_trapped", 3],
		"посреди рывка из ямы": [func(b: Dictionary) -> bool: return b.get("t") == "world_fall", 4],
		"у могилы": [func(b: Dictionary) -> bool: return String(b.get("text", "")) == "intro_grandpa.g3", 3],
	}
	for label: String in points:
		var p: Array = points[label]
		var r := await _run_intro("skip", p[0], int(p[1]))
		var diff := _same(r.snap, snap)
		check("«Пропустить» %s: итог = досмотренной сцене" % label, not r.snap.is_empty() and diff.is_empty(),
			"кадр %s, отличается: %s" % [r.skipped_at, diff])
		check("«Пропустить» %s: камера там же" % label, Vector2(r.camera).distance_to(ref.camera) < 0.01,
			"%s / %s" % [r.camera, ref.camera])


# ---------------------------------------------------------------------------
# 2. Сцена смерти — шесть клеток
# ---------------------------------------------------------------------------

const DEATH_X := 22


## Сцена смерти от пробитого фундамента. start_y — где герой в миг пробития:
## 4.5 — ещё стоит над пробитой клеткой, 5.5 — уже упал в неё.
func _run_death(start_y: float, skip_on_dig: int = -1) -> Dictionary:
	_clean(["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure", "workshop"],
		["intro_seen", "workshop_seen", "gold_taken"])
	var m := await _spawn_main()
	var d: StoryDirector = m.find_child("StoryDirector", true, false)
	var cs := d.cutscene
	var w := d.world
	for y in range(1, 6):
		w.dig_cell(DEATH_X, y)
	d.player.x = float(DEATH_X) + 0.5
	d.player.y = start_y
	StoryState.set_flag("foundation_broken")
	StoryState.enqueue("death")
	var res := {"digs": 0, "deepest": 0.0, "open_at_s1": [], "snap": {}, "skipped": false}
	var on_finished := func(id: String) -> void:
		if id == "death":
			res.snap = _snapshot(m, d)
			res.snap["indoors"] = GameState.house_is_indoors
			res.snap["bars"] = StoryState.has_flag("bars_introduced")
			res.snap["stamina"] = GameState.stamina
	cs.finished.connect(on_finished)
	var guard := 0
	var last_dig_index := -1
	while guard < FRAME_GUARD and not StoryState.is_seen("death"):
		guard += 1
		await _frames(1)
		_close_daily_popup()
		if not cs.is_playing or cs.scene_id != "death":
			continue
		var a: WorldActor = cs._world_actors.get("boy")
		if a != null and is_instance_valid(a):
			res.deepest = maxf(res.deepest, a.y)
		var beat := _current_beat(cs)
		if beat.get("t") == "world_dig" and cs._index - 1 != last_dig_index:
			last_dig_index = cs._index - 1
			res.digs += 1
			if res.digs == skip_on_dig:
				await _frames(5)
				cs._skip_btn.confirmed.emit()
				res.skipped = true
				continue
		if String(beat.get("text", "")) == "death.s1" and res.open_at_s1.is_empty():
			for y in range(1, 16):
				if w.get_tile(DEATH_X, y) == TileTypes.Type.EMPTY:
					res.open_at_s1.append(y)
		_watch_step(cs)
	res["after_seen"] = StoryState.is_seen("death")
	# Ранец режиссёр ставит в очередь сам, на следующем своём кадре.
	for _i in 30:
		await _frames(1)
		if GameState.story_queue.has("backpack") or (cs.is_playing and cs.scene_id == "backpack"):
			break
	res["next"] = GameState.story_queue.duplicate()
	if cs.is_playing:
		res.next.append(cs.scene_id)
	m.free()
	await _frames(2)
	return res


func _test_death_six_cells() -> void:
	StoryData.ensure_loaded()
	var digs := 0
	for b in StoryData.beats("death"):
		if b.get("t") == "world_dig" and b.get("actor") == "boy":
			digs += 1
	check("сцена смерти: шесть кадров копки внука, как у деда", digs == 6, "кадров: %d" % digs)
	for loc in ["ru", "en"]:
		StoryText.load_locale(loc)
		var six := "шест" if loc == "ru" else "six"
		check("сцена смерти (%s): счёт клеток доходит до шести" % loc,
			StoryText.get_text("death.n1b").to_lower().contains(six))
	StoryText.load_locale("ru")

	var ref: Dictionary = {}
	for start_y in [4.5, 5.5]:
		var r := await _run_death(start_y)
		var label := "над пробитым фундаментом" if start_y < 5.0 else "в пробитом фундаменте"
		check("смерть (%s): сцена доиграна" % label, r.after_seen and not r.snap.is_empty())
		check("смерть (%s): внук ушёл на шесть клеток под фундамент" % label,
			is_equal_approx(r.deepest, 5.0 + 6.0 + 0.5), "дно %.2f" % r.deepest)
		check("смерть (%s): в «вылезаю» его яма открыта до 11-го ряда" % label,
			r.open_at_s1 == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], str(r.open_at_s1))
		if r.snap.is_empty():
			continue
		check("смерть (%s): после сцены — в мастерской, полоски введены, бодрость полная" % label,
			r.snap.indoors and r.snap.bars and is_equal_approx(r.snap.stamina, 100.0),
			str([r.snap.indoors, r.snap.bars, r.snap.stamina]))
		check("смерть (%s): дальше по сюжету — ранец" % label, r.next.has("backpack"), str(r.next))
		check("смерть (%s): яма сцены засыпана, пробитый игроком фундамент остался" % label,
			r.snap.dug.has(DEATH_X + 5 * WorldGen.WIDTH) and not r.snap.dug.has(DEATH_X + 6 * WorldGen.WIDTH))
		if ref.is_empty():
			ref = r.snap
	if ref.is_empty():
		return
	var s := await _run_death(4.5, 4)
	check("смерть: «Пропустить» посреди копки — сцена засчитана", s.skipped and s.after_seen)
	var diff := _same(s.snap, ref)
	if s.snap.get("indoors") != ref.get("indoors"):
		diff.append("indoors")
	check("смерть: «Пропустить» посреди копки = досмотренной сцене", diff.is_empty(), str(diff))

class_name SfxService
extends Node
## Сервис звука: пул AudioStreamPlayer на шине «SFX», два проигрывателя музыки
## на шине «Music» (кроссфейд) и отдельные голоса для зацикленных звуков.
## Узел состоит в группе Sfx.GROUP — фасад Sfx находит его там.
##
## Каталог звуков — audio/catalog.json (его пишет tools/gen_audio.py): для
## каждого id — файлы-варианты, громкость, разброс высоты, приоритет, потолок
## одновременных голосов и «остывание» между повторами. Неизвестные id молча
## игнорируются. Громкость/mute шин ведёт Settings — сервис их не трогает.
##
## В вебе звук стартует только после жеста пользователя: до первого нажатия
## ничего не играет, а запрошенная музыка ждёт и включается сама.

signal unlocked_changed

const CATALOG_PATH := "res://audio/catalog.json"
const AUDIO_DIR := "res://audio/"
const POOL_SIZE := 14
const SILENT_DB := -60.0

var enabled: bool = true
## true — звук ждёт первого ввода (веб). Для тестов можно выставить вручную.
var require_gesture: bool = OS.has_feature("web")
var unlocked: bool = not OS.has_feature("web")
var stats := {"played": 0, "dropped": 0, "stolen": 0, "cooldown": 0}

var _defs: Dictionary = {}          # id -> {streams, db, pv, prio, voices, cd, duck, loop}
var _music_defs: Dictionary = {}    # id -> {file, db} | {alias}
var _pool: Array[AudioStreamPlayer] = []
var _meta: Array[Dictionary] = []   # по одному на голос: {id, prio, t}
var _last_ms: Dictionary = {}
var _last_variant: Dictionary = {}
var _loops: Dictionary = {}         # id -> AudioStreamPlayer
var _loop_streams: Dictionary = {}

var _music: Array[AudioStreamPlayer] = []
var _music_db: Array[float] = [0.0, 0.0]     # громкость трека из каталога
var _music_fade: Array[float] = [SILENT_DB, SILENT_DB]
var _music_active: int = 0
var _music_id: String = ""                    # что должно играть сейчас
var _music_file: String = ""
var _music_tween: Tween
var _pending_music: Dictionary = {}
var _music_streams: Dictionary = {}

var _duck_db: float = 0.0
var _duck_target: float = 0.0
var _duck_until_ms: int = 0


func _ready() -> void:
	add_to_group(Sfx.GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.ensure_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = Settings.BUS_SFX
		add_child(p)
		_pool.append(p)
		_meta.append({"id": "", "prio": -1, "t": 0})
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = Settings.BUS_MUSIC
		m.volume_db = SILENT_DB
		add_child(m)
		_music.append(m)
	_load_catalog()


func _load_catalog() -> void:
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		return
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for id in raw.get("sfx", {}):
		var e: Dictionary = raw["sfx"][id]
		var streams: Array = []
		for file in e.get("files", []):
			var s := _load_stream(String(file))
			if s != null:
				streams.append(s)
		if streams.is_empty():
			continue
		_defs[String(id)] = {
			"streams": streams, "db": float(e.get("db", 0.0)), "pv": float(e.get("pv", 0.05)),
			"prio": int(e.get("prio", 1)), "voices": maxi(1, int(e.get("voices", 3))),
			"cd": int(e.get("cd", 0)), "duck": float(e.get("duck", 0.0)), "loop": bool(e.get("loop", false)),
		}
	_music_defs = raw.get("music", {})


func _load_stream(rel: String) -> AudioStream:
	var path := AUDIO_DIR + rel
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


func has_sfx(id: String) -> bool:
	return _defs.has(id)


func has_music(id: String) -> bool:
	return not _resolve_music(id).is_empty()


func sfx_ids() -> Array:
	return _defs.keys()


func pool_size() -> int:
	return _pool.size()


func active_voices() -> int:
	var n := 0
	for p in _pool:
		if p.playing:
			n += 1
	return n


# ---------------------------------------------------------------------------
# Разовые звуки
# ---------------------------------------------------------------------------

func play(id: String, pitch: float = 1.0, volume_db: float = 0.0) -> bool:
	if not enabled or (require_gesture and not unlocked) or Settings.sound_muted:
		return false
	var d: Dictionary = _defs.get(id, {})
	if d.is_empty() or d["loop"]:
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(id, -1000000)) < int(d["cd"]):
		stats["cooldown"] += 1
		return false
	var idx := _pick_voice(id, int(d["prio"]), int(d["voices"]))
	if idx < 0:
		stats["dropped"] += 1
		return false
	var p := _pool[idx]
	if p.playing:
		stats["stolen"] += 1
	var stream := _pick_stream(id, d)
	p.stream = stream
	var pv: float = d["pv"]
	p.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-pv, pv)))
	p.volume_db = float(d["db"]) + volume_db
	p.play()
	_meta[idx] = {"id": id, "prio": int(d["prio"]), "t": now}
	_last_ms[id] = now
	stats["played"] += 1
	if float(d["duck"]) > 0.0:
		_duck_target = -float(d["duck"])
		_duck_until_ms = now + int(stream.get_length() * 800.0)
	return true


func _pick_stream(id: String, d: Dictionary) -> AudioStream:
	var streams: Array = d["streams"]
	if streams.size() == 1:
		return streams[0]
	var last := int(_last_variant.get(id, -1))
	var k := randi() % streams.size()
	if k == last:
		k = (k + 1) % streams.size()
	_last_variant[id] = k
	return streams[k]


## Свободный голос; иначе — вытеснение: сначала самый старый голос того же id
## (если он упёрся в потолок), затем самый тихий по приоритету и старший по
## возрасту, но не важнее нового звука. -1 — звук теряется.
func _pick_voice(id: String, prio: int, cap: int) -> int:
	var same := 0
	var oldest_same := -1
	var free := -1
	var victim := -1
	for i in _pool.size():
		var p := _pool[i]
		if not p.playing:
			if free < 0:
				free = i
			continue
		var m := _meta[i]
		if m["id"] == id:
			same += 1
			if oldest_same < 0 or int(m["t"]) < int(_meta[oldest_same]["t"]):
				oldest_same = i
		if int(m["prio"]) <= prio:
			if victim < 0 or int(m["prio"]) < int(_meta[victim]["prio"]) \
					or (int(m["prio"]) == int(_meta[victim]["prio"]) and int(m["t"]) < int(_meta[victim]["t"])):
				victim = i
	if same >= cap and oldest_same >= 0:
		return oldest_same
	if free >= 0:
		return free
	return victim


# ---------------------------------------------------------------------------
# Зацикленные звуки (гул ранца)
# ---------------------------------------------------------------------------

func loop_start(id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled or (require_gesture and not unlocked):
		return
	var d: Dictionary = _defs.get(id, {})
	if d.is_empty() or not d["loop"]:
		return
	var p: AudioStreamPlayer = _loops.get(id)
	if p == null:
		p = AudioStreamPlayer.new()
		p.bus = Settings.BUS_SFX
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_loops[id] = p
		p.stream = _looped(id, d["streams"][0])
	p.set_meta("fade_gen", int(p.get_meta("fade_gen", 0)) + 1)
	p.pitch_scale = pitch
	var target_db: float = float(d["db"]) + volume_db
	if not p.playing:
		p.volume_db = SILENT_DB
		p.play()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", target_db, 0.12)


func loop_stop(id: String, fade: float = 0.15) -> void:
	var p: AudioStreamPlayer = _loops.get(id)
	if p == null or not p.playing:
		return
	var gen := int(p.get_meta("fade_gen", 0)) + 1
	p.set_meta("fade_gen", gen)
	var tw := create_tween()
	tw.tween_property(p, "volume_db", SILENT_DB, maxf(fade, 0.01))
	tw.tween_callback(func() -> void:
		# Если за время затухания звук включили снова, не глушим его.
		if is_instance_valid(p) and int(p.get_meta("fade_gen", 0)) == gen:
			p.stop())


func is_looping(id: String) -> bool:
	var p: AudioStreamPlayer = _loops.get(id)
	return p != null and p.playing


func _looped(id: String, src: AudioStream) -> AudioStream:
	if _loop_streams.has(id):
		return _loop_streams[id]
	var s := src
	# fly_loop зациклен прямо в .import; для остальных петлю включаем здесь.
	if s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var w := src.duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * float(w.mix_rate))
		s = w
	_loop_streams[id] = s
	return s


# ---------------------------------------------------------------------------
# Музыка
# ---------------------------------------------------------------------------

func _resolve_music(id: String) -> Dictionary:
	var e: Dictionary = _music_defs.get(id, {})
	var guard := 0
	while e.has("alias") and guard < 4:
		e = _music_defs.get(String(e["alias"]), {})
		guard += 1
	return e if e.has("file") else {}


func current_music() -> String:
	return _music_id


func music(id: String, fade: float = 1.0) -> void:
	var def := _resolve_music(id)
	if def.is_empty():
		return
	if id == _music_id:
		return
	_music_id = id
	# Псевдоним (mus_menu → mus_shop) на тот же файл: перезапускать трек незачем.
	if def["file"] == _music_file:
		return
	_music_file = String(def["file"])
	if not enabled or (require_gesture and not unlocked):
		_pending_music = {"id": id, "fade": fade}
		return
	_start_music(def, fade)


func stop_music(fade: float = 1.0) -> void:
	_music_id = ""
	_music_file = ""
	_pending_music.clear()
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	for i in 2:
		if _music[i].playing:
			_music_tween.tween_method(_set_fade.bind(i), _music_fade[i], SILENT_DB, maxf(fade, 0.01))
	_music_tween.chain().tween_callback(_stop_silent)


func _stop_silent() -> void:
	for i in 2:
		if _music_fade[i] <= SILENT_DB + 0.5:
			_music[i].stop()


func _start_music(def: Dictionary, fade: float) -> void:
	var stream: AudioStream = _music_streams.get(def["file"])
	if stream == null:
		stream = _load_stream(String(def["file"]))
		if stream == null:
			return
		if "loop" in stream:
			stream.loop = true
		_music_streams[def["file"]] = stream
	var old := _music_active
	var nw := 1 - old
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music[nw].stream = stream
	_music_db[nw] = float(def.get("db", -4.0))
	_set_fade(SILENT_DB, nw)
	_music[nw].play()
	_music_active = nw
	var f := maxf(fade, 0.01)
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_method(_set_fade.bind(nw), SILENT_DB, 0.0, f)
	if _music[old].playing:
		_music_tween.tween_method(_set_fade.bind(old), _music_fade[old], SILENT_DB, f)
	_music_tween.chain().tween_callback(_stop_silent)


func _set_fade(v: float, i: int) -> void:
	_music_fade[i] = v
	_apply_music_volume(i)


func _apply_music_volume(i: int) -> void:
	_music[i].volume_db = maxf(SILENT_DB, _music_db[i] + _music_fade[i] + _duck_db)


func _process(delta: float) -> void:
	var target := _duck_target
	if Time.get_ticks_msec() > _duck_until_ms:
		target = 0.0
		_duck_target = 0.0
	# Вниз — быстро (фанфара не должна тонуть в музыке), вверх — медленно.
	var speed := 90.0 if target < _duck_db else 10.0
	var nd := move_toward(_duck_db, target, speed * delta)
	if not is_equal_approx(nd, _duck_db):
		_duck_db = nd
		for i in 2:
			if _music[i].playing:
				_apply_music_volume(i)


func _input(event: InputEvent) -> void:
	if unlocked:
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventKey and event.pressed) or (event is InputEventJoypadButton and event.pressed):
		unlock()


## Первый жест пользователя: веб разрешает звук. Запрошенная раньше музыка
## включается здесь.
func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	unlocked_changed.emit()
	if not _pending_music.is_empty():
		var p := _pending_music
		_pending_music = {}
		var def := _resolve_music(String(p["id"]))
		if not def.is_empty() and String(p["id"]) == _music_id:
			_start_music(def, float(p["fade"]))

class_name Analytics
extends Node
## Аналитика игры по согласию игрока (ГДД §16.1). Событие уходит только при
## Settings.analytics_consent == "granted": без согласия track() молчит, очередь пуста.
##
##   Analytics.attach(self)                       # main.gd, одной строкой
##   Analytics.track("bought", {"id": "drill_1"}) # остальное — подписки ниже
##
## Куда: PostHog (data/analytics.json → host, api_key), POST {host}/batch/. Пустой api_key —
## события копятся в очереди (не больше QUEUE_CAP), наружу не уходит ничего.
## Что: игровые числа и сведения об устройстве. Не шлём: имя, сейв, текст игрока, IP
## ($geoip_disable; ключа $ip нет — IP ещё и отбрасывает проект PostHog, docs/BUILD.md).
## Кто: случайный UUID в user://analytics_id.txt — не из сейва, «Сброс» его не трогает.
## Отказ (в окне или в настройках) сразу стирает очередь и её файл.
## Тесты, боты и headless: окно согласия не показывается, без явного "granted" не пишется
## ничего, а настоящей сети нет вовсе (отправитель в тестах подменяется — sender).

const CONFIG_PATH := "res://data/analytics.json"
const ID_PATH := "user://analytics_id.txt"
const QUEUE_PATH := "user://analytics_queue.json"
const QUEUE_CAP := 500
const FLUSH_EVERY_S := 30.0
const FLUSH_AT := 20
const BATCH_MAX := 100
const LEAVE_MAX := 40        # уход со страницы: keepalive-запрос до 64 КБ
const BACKOFF_MAX_S := 600.0
const DEPTH_STEP := 100
## Ключи, которых в событии быть не может, даже если их передал вызывающий.
const FORBIDDEN := ["name", "email", "ip", "$ip", "save", "text", "nickname"]

## Какие события шины GameState.game_event уходят в аналитику. Частые (dug, picked,
## monster_hit, fuel_used, spent) не шлём — их итог виден по редким.
const BUS_EVENTS := [
	"sold", "bought", "crafted", "gear_crafted", "smelt_started", "fuel_refined", "premium_unload",
	"monster_killed", "boss_started", "boss_defeated", "boss_failed", "cave_cleared",
	"cave_chest_opened", "chest_opened", "quest_done", "story_beat", "diary_page",
	"hint_shown", "hint_done", "slept", "ate", "healed", "food_ordered", "hospital",
	"ad_watched", "fever_started", "mastery_star", "well_collected", "teleport_used",
	"collapse", "quake", "screen_opened",
]

static var _cfg: Dictionary = {}
static var _q: Array = []
static var _gen := 0                 # растёт при стирании очереди: ответ на старую отправку не трогает новую
static var _id := ""
static var _session := ""
static var _start_ms := 0
static var _static_props: Dictionary = {}
static var _session_sent := false
static var _loaded := false
## Отправитель: func(url: String, body: String, done: Callable) — done.call(ok: bool).
## Пустой — HTTPRequest этого узла. Тесты подменяют, сети нет.
static var sender := Callable()
static var _inst: Analytics = null

var _flush_in := FLUSH_EVERY_S
var _backoff := 0.0
var _busy := false
var _fps_t := 0.0
var _fps_sum := 0.0
var _fps_n := 0
var _fps_min := 1000.0
var _depth_mark := 0
var _http: HTTPRequest = null
var _http_done := Callable()
var _js_leave = null   # JavaScriptObject колбэка: без ссылки его соберёт сборщик


static func attach(host: Node) -> Analytics:
	var a := Analytics.new()
	a.name = "Analytics"
	host.add_child(a)
	return a


## Конфиг сборки; в тестах можно подменить целиком.
static func config() -> Dictionary:
	if _cfg.is_empty():
		var raw = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else null
		_cfg = raw if typeof(raw) == TYPE_DICTIONARY else {"enabled_build": false}
	return _cfg


static func set_config(c: Dictionary) -> void:
	_cfg = c


static func build_enabled() -> bool:
	return bool(config().get("enabled_build", false))


static func allowed() -> bool:
	return build_enabled() and Settings.analytics_consent == "granted"


## Запуск под тестом, ботом или без окна: окна согласия нет, сеть не трогаем.
static func automated() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	var tree := Engine.get_main_loop() as SceneTree
	var cs := tree.current_scene if tree != null else null
	return cs != null and cs.scene_file_path.begins_with("res://tests/")


## Спросить ли согласие сейчас (первый запуск обычной игры).
static func should_ask() -> bool:
	return build_enabled() and Settings.analytics_consent == "unset" and not automated()


static func queue() -> Array:
	return _q


static func track(event: String, props: Dictionary = {}) -> void:
	if not allowed():
		return
	var p := super_props()
	for k in props:
		if FORBIDDEN.has(String(k)):
			continue
		var v = props[k]
		match typeof(v):
			TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
				p[String(k)] = v
			TYPE_STRING, TYPE_STRING_NAME:
				p[String(k)] = String(v).left(64)   # только id из кода: текст игрока сюда не попадает
	_q.append({"event": event, "uuid": _uuid(), "distinct_id": distinct_id(), "timestamp": _iso_now(), "properties": p})
	while _q.size() > QUEUE_CAP:
		_q.pop_front()
	if _inst != null and _q.size() >= FLUSH_AT and _inst._backoff == 0.0:
		_inst._flush_in = 0.0


## Свойства на каждом событии: сборка, устройство, настройки, время сессии.
static func super_props() -> Dictionary:
	if _static_props.is_empty():
		_static_props = _device_props()
	var p := _static_props.duplicate()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var vp := tree.root.get_visible_rect().size
		p["viewport"] = "%dx%d" % [int(vp.x), int(vp.y)]
	p["window"] = "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	p["control_mode"] = Settings.control_mode
	p["reduce_motion"] = Settings.reduce_motion
	p["session_id"] = session_id()
	p["session_s"] = int((Time.get_ticks_msec() - _start_ms) / 1000.0)
	p["$geoip_disable"] = true
	p["$lib"] = "godot"
	return p


static func _device_props() -> Dictionary:
	var build := {}
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/build_info.json"))
	if typeof(raw) == TYPE_DICTIONARY:
		build = raw
	var scr := DisplayServer.screen_get_size()
	var p := {
		"build": String(build.get("build", "")),
		"commit": String(build.get("commit", "")),
		"godot": Engine.get_version_info().get("string", ""),
		"$os": OS.get_name(),
		"$os_version": OS.get_version(),
		"$device_model": OS.get_model_name(),
		"locale": OS.get_locale(),
		"screen": "%dx%d" % [scr.x, scr.y],
		"dpi_scale": DisplayServer.screen_get_scale(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
	}
	if OS.has_feature("web"):
		p["user_agent"] = String(JavaScriptBridge.eval("navigator.userAgent"))
		p["dpi_scale"] = float(JavaScriptBridge.eval("window.devicePixelRatio || 1"))
	return p


static func distinct_id() -> String:
	if _id.is_empty():
		_id = FileAccess.get_file_as_string(ID_PATH).strip_edges() if FileAccess.file_exists(ID_PATH) else ""
		if _id.length() != 36:
			_id = _uuid()
			var f := FileAccess.open(ID_PATH, FileAccess.WRITE)
			if f != null:
				f.store_string(_id)
	return _id


static func session_id() -> String:
	if _session.is_empty():
		_session = _uuid()
	return _session


static func _uuid() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


static func _iso_now() -> String:
	return Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()), false) + "Z"


## Тело запроса /batch/ из первых n событий очереди.
static func batch_body(n: int = BATCH_MAX) -> String:
	return JSON.stringify({"api_key": String(config().get("api_key", "")), "batch": _q.slice(0, n)})


static func batch_url() -> String:
	return String(config().get("host", "")).trim_suffix("/") + "/batch/"


## Зовёт Settings.set_analytics_consent: отказ стирает всё, согласие начинает сессию.
static func consent_changed() -> void:
	if allowed():
		_session_sent = false
		if _inst != null:
			_inst._start_session()
	else:
		clear_queue()


static func clear_queue() -> void:
	_q.clear()
	_gen += 1
	if FileAccess.file_exists(QUEUE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(QUEUE_PATH))


static func save_queue() -> void:
	if not allowed():
		return
	if _q.is_empty():
		if FileAccess.file_exists(QUEUE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(QUEUE_PATH))
		return
	var f := FileAccess.open(QUEUE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_q))


## Один раз за процесс: очередь статична и переживает перезапуск сцены, повторное чтение задвоило бы её.
static func load_queue() -> void:
	if _loaded or not allowed() or not FileAccess.file_exists(QUEUE_PATH):
		return
	_loaded = true
	var raw = JSON.parse_string(FileAccess.get_file_as_string(QUEUE_PATH))
	if typeof(raw) == TYPE_ARRAY:
		_q = raw + _q
		while _q.size() > QUEUE_CAP:
			_q.pop_front()


# ---------------------------------------------------------------------------
# Узел: подписки, таймер отправки, FPS, уход в фон
# ---------------------------------------------------------------------------

func _ready() -> void:
	_inst = self
	if _start_ms == 0:
		_start_ms = Time.get_ticks_msec()
	if not build_enabled():
		set_process(false)
		return
	load_queue()
	_depth_mark = floori(GameState.max_depth_reached / float(DEPTH_STEP))
	# методы, не лямбды: подписка метода снимается сама, когда узел уходит (перезапуск сцены)
	GameState.game_event.connect(_on_game_event)
	GameState.died.connect(_on_died)
	GameState.leveled_up.connect(_on_leveled_up)
	GameState.max_depth_changed.connect(_on_max_depth)
	GameState.tool_changed.connect(_on_one.bind("tool_changed", "tool"))
	GameState.gear_changed.connect(_on_one.bind("gear_changed", "gear"))
	GameState.artifact_collected.connect(_on_one.bind("artifact_collected", "artifact"))
	GameState.branch_completed.connect(_on_one.bind("branch_completed", "branch"))
	GameState.daily_reset.connect(_on_one.bind(0, "daily_reset", ""))
	IAPManager.purchase_started.connect(_on_one.bind("iap_started", "product"))
	IAPManager.purchase_completed.connect(_on_one.bind("iap_completed", "product"))
	IAPManager.purchase_failed.connect(_on_iap_failed)
	_hook_web_page()
	_start_session()


func _exit_tree() -> void:
	save_queue()
	if _inst == self:
		_inst = null   # статика переживает перезагрузку сцены


func _start_session() -> void:
	if _session_sent or not allowed():
		return
	_session_sent = true
	track("session_start", {"level": GameState.level, "max_depth": GameState.max_depth_reached})


func _on_game_event(id: StringName, data: Dictionary) -> void:
	if BUS_EVENTS.has(String(id)):
		track(String(id), data)


## Сигнал с одним значением → событие {key: значение}; key "" — без свойств.
func _on_one(value, event: String, key: String) -> void:
	track(event, {key: value} if key != "" else {})


func _on_died() -> void:
	track("died", {"depth": GameState.player_depth, "cause": String(GameState.death_cause.get("source", ""))})


func _on_leveled_up(lvl: int, _pts: int) -> void:
	track("level_up", {"level": lvl})


func _on_iap_failed(id: String, why: String) -> void:
	track("iap_failed", {"product": id, "reason": why})


func _on_max_depth(depth: int) -> void:
	var mark := floori(depth / float(DEPTH_STEP))
	if mark > _depth_mark:
		track("depth_milestone", {"depth": mark * DEPTH_STEP})
	_depth_mark = mark   # «Сброс» откатывает к нулю — вехи начинаются заново


func _process(dt: float) -> void:
	_fps_t += dt
	if _fps_t >= 1.0:
		_fps_t = 0.0
		var fps := Engine.get_frames_per_second()
		_fps_sum += fps
		_fps_n += 1
		_fps_min = minf(_fps_min, fps)
	_flush_in -= dt
	if _flush_in <= 0.0:
		_flush_in = FLUSH_EVERY_S + _backoff
		flush()


func fps_props() -> Dictionary:
	return {"duration_s": int((Time.get_ticks_msec() - _start_ms) / 1000.0),
		"fps_avg": snappedf(_fps_sum / _fps_n, 0.1) if _fps_n > 0 else 0.0,
		"fps_min": _fps_min if _fps_n > 0 else 0.0}


## Отправляет начало очереди. Без согласия, ключа или под тестом без подменённого
## отправителя — ничего; события ждут в очереди.
func flush() -> void:
	if _busy or _q.is_empty() or not allowed() or String(config().get("api_key", "")).is_empty():
		return
	if not sender.is_valid() and automated():
		return
	var n := mini(_q.size(), BATCH_MAX)
	var gen := _gen
	_busy = true
	var done := func(ok: bool) -> void:
		_busy = false
		if gen != _gen:
			return
		if ok:
			_q = _q.slice(n)
			_backoff = 0.0
			save_queue()
		else:
			_backoff = clampf(_backoff * 2.0, FLUSH_EVERY_S, BACKOFF_MAX_S)
			_flush_in = _backoff
			save_queue()
	if sender.is_valid():
		sender.call(batch_url(), batch_body(n), done)
	else:
		_http_send(batch_url(), batch_body(n), done)


func _http_send(url: String, body: String, done: Callable) -> void:
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 15.0
		_http.request_completed.connect(_on_http_done)
		add_child(_http)
	_http_done = done
	if _http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
		_http_done = Callable()
		done.call(false)


func _on_http_done(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	var done := _http_done
	_http_done = Callable()
	if done.is_valid():
		done.call(result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300)


## Ушли в фон или закрываемся: событие, очередь на диск, попытка отправить.
func _leave(event: String) -> void:
	if not allowed():
		return
	track(event, fps_props())
	save_queue()
	flush()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_leave("app_backgrounded")
		NOTIFICATION_WM_CLOSE_REQUEST:
			_leave("session_end")   # HTTP до выхода не успеет — уйдёт со следующим запуском


## Браузер: у скрытой вкладки нет кадров, HTTPRequest не дойдёт. Шлём fetch с keepalive прямо
## из обработчика страницы и очищаем отправленное (повтор не нужен: потеря редкая, дубль — хуже).
func _hook_web_page() -> void:
	if not OS.has_feature("web"):
		return
	var shell = JavaScriptBridge.get_interface("RaskopkiShell")
	if shell == null or shell.onLeave == null:
		return
	_js_leave = JavaScriptBridge.create_callback(_on_page_leave)
	shell.onLeave(_js_leave)


func _on_page_leave(args: Array) -> void:
	if not allowed():
		return
	track("session_end" if not args.is_empty() and String(args[0]) == "pagehide" else "app_backgrounded", fps_props())
	if String(config().get("api_key", "")).is_empty() or _busy:
		save_queue()
		return
	var n := mini(_q.size(), LEAVE_MAX)
	JavaScriptBridge.eval("fetch(%s,{method:'POST',keepalive:true,headers:{'Content-Type':'application/json'},body:%s}).catch(function(){})"
		% [JSON.stringify(batch_url()), JSON.stringify(batch_body(n))])
	_q = _q.slice(n)
	save_queue()

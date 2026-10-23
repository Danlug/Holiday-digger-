class_name HintDirector
extends Node
## Движок контекстных подсказок: правило (data/hints.json) -> условие -> цель -> сигнал.
## Подключается одной строкой из main.gd (HintDirector.attach(self)) и сам находит HUD,
## меню и объекты мира по группам и именам.
##
## Порядок жизни подсказки:
##  1. правило ещё не показывалось (HintState), онбординг пройден, игрок не занят
##     (HintBusy), прошли first_delay после «тишины» и gap после прошлой подсказки;
##  2. условие when держится не меньше hold секунд, цель нашлась и видна;
##  3. из подходящих берётся с наибольшим prio — показываем (ровно одна за раз), пишем
##     «показана» в GameState.ext["hints"], играем мягкий звук и вибро;
##  4. снимается, как только игрок нажал на цель, сработало done, условие when
##     перестало держаться (сделал или передумал) или прошло ttl секунд;
##     пока открыта шторка или играет сцена, подсказка прячется и время не идёт.
##
## Условия опрашиваются по таймеру (poll), а сигналы GameState (очки навыков, артефакт,
## глубина, смена снаряжения, шина game_event) только «будят» опрос — состояние игры
## и так читается, отдельной очереди событий не нужно. Событие шины запоминается в
## HintConditions.latched — для условий вида {"fn": "event", "id": "..."}.

signal hint_shown(id: String)
signal hint_ended(id: String, reason: String)

## Причины снятия, после которых подсказка считается «сделано» (игрок понял и сделал).
const DONE_REASONS := ["done", "cond"]

static var _instance: HintDirector = null

var overlay: HintOverlay = null
var marks: HintMarks = null
var rules: Array = []

var _active: Dictionary = {}
var _hold: Dictionary = {}
var _eval_t: float = 0.0
var _calm_t: float = 0.0
var _gap_left: float = 0.0
var _poll: float = 0.25
var _first_delay: float = 4.0
var _gap: float = 8.0
var _default_hold: float = 1.2
var _default_ttl: float = 16.0
var _lost_after: float = 2.0


static func attach(host: Node) -> HintDirector:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var d := HintDirector.new()
	d.name = "HintDirector"
	host.add_child(d)
	return d


static func instance() -> HintDirector:
	return _instance if _instance != null and is_instance_valid(_instance) else null


func _ready() -> void:
	_instance = self
	overlay = HintOverlay.new()
	add_child(overlay)
	marks = HintMarks.new()
	marks.name = "HintMarks"
	add_child(marks)
	reload()
	GameState.game_event.connect(_on_game_event)
	GameState.skill_points_changed.connect(_on_signal_1)
	GameState.artifact_collected.connect(_on_signal_1)
	GameState.max_depth_changed.connect(_on_signal_1)
	GameState.tool_changed.connect(_on_signal_1)
	GameState.gear_changed.connect(_on_signal_1)
	GameState.leveled_up.connect(_on_signal_2)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	_disconnect(GameState.game_event, _on_game_event)
	_disconnect(GameState.skill_points_changed, _on_signal_1)
	_disconnect(GameState.artifact_collected, _on_signal_1)
	_disconnect(GameState.max_depth_changed, _on_signal_1)
	_disconnect(GameState.tool_changed, _on_signal_1)
	_disconnect(GameState.gear_changed, _on_signal_1)
	_disconnect(GameState.leveled_up, _on_signal_2)


func _disconnect(sig: Signal, method: Callable) -> void:
	if sig.is_connected(method):
		sig.disconnect(method)


## Перечитать правила и тайминги (старт и тесты).
func reload() -> void:
	HintData.reload()
	set_rules(HintData.rules())
	_poll = maxf(HintData.timing("poll", 0.25), 0.05)
	_first_delay = HintData.timing("first_delay", 4.0)
	_gap = HintData.timing("gap", 8.0)
	_default_hold = HintData.timing("hold", 1.2)
	_default_ttl = HintData.timing("ttl", 16.0)
	_lost_after = HintData.timing("lost_after", 2.0)
	_gap_left = 0.0
	_calm_t = 0.0


## Порядок проверки: по убыванию prio, при равенстве — как в файле.
func set_rules(list: Array) -> void:
	rules = list.duplicate()
	var order := {}
	for i in range(rules.size()):
		order[String((rules[i] as Dictionary).get("id", ""))] = i
	rules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a.get("prio", 0))
		var pb := int(b.get("prio", 0))
		if pa != pb:
			return pa > pb
		return int(order.get(String(a.get("id", "")), 0)) < int(order.get(String(b.get("id", "")), 0)))
	_hold.clear()


func active_id() -> String:
	return String((_active.get("rule", {}) as Dictionary).get("id", ""))


func is_active() -> bool:
	return not _active.is_empty()


func _on_game_event(id: StringName, _data: Dictionary) -> void:
	HintConditions.latched[String(id)] = true
	_kick()


func _on_signal_1(_a) -> void:
	_kick()


func _on_signal_2(_a, _b) -> void:
	_kick()


## Сигнал игры — повод проверить условия на ближайшем кадре, а не ждать таймера.
func _kick() -> void:
	_eval_t = _poll


func _process(dt: float) -> void:
	tick(dt)


## Один шаг движка. Выделен из _process, чтобы тест «прокручивал время» без кадров.
func tick(dt: float) -> void:
	if not HintState.enabled() or not HintBusy.onboarding_done():
		if is_active():
			_end("disabled")
		_calm_t = 0.0
		return
	var busy := HintBusy.is_busy()
	if is_active():
		_tick_active(dt, busy)
		return
	if busy:
		_calm_t = 0.0
		return
	_calm_t += dt
	_gap_left = maxf(0.0, _gap_left - dt)
	_eval_t += dt
	if _eval_t < _poll:
		return
	var step := _eval_t
	_eval_t = 0.0
	var ready: Array = []
	for r: Dictionary in rules:
		var id := String(r.get("id", ""))
		if id.is_empty() or HintState.is_seen(id):
			continue
		if HintConditions.test(r.get("when", {})):
			_hold[id] = float(_hold.get(id, 0.0)) + step
			if float(_hold[id]) >= float(HintData.v(r.get("hold", null), _default_hold)):
				ready.append(r)
		else:
			_hold[id] = 0.0
	if ready.is_empty() or _calm_t < _first_delay or _gap_left > 0.0:
		return
	for r: Dictionary in ready:
		var res := HintTargets.resolve(r.get("target", []))
		if not res.is_empty():
			_start(r, res)
			return


func _tick_active(dt: float, busy: bool) -> void:
	var r: Dictionary = _active["rule"]
	if bool(_active.get("tapped", false)):
		_end("done")
		return
	var done = r.get("done", null)
	if done is Dictionary and HintConditions.test(done):
		_end("done")
		return
	if busy:
		overlay.set_paused(true)
		_calm_t = 0.0
		return
	overlay.set_paused(false)
	_active["elapsed"] = float(_active["elapsed"]) + dt
	var res := HintTargets.resolve(r.get("target", []))
	if res.is_empty():
		_active["lost"] = float(_active.get("lost", 0.0)) + dt
		_active["final"] = false
		if float(_active["lost"]) >= _lost_after:
			_end("lost")
		return
	_active["lost"] = 0.0
	_active["rect"] = res["rect"]
	_active["final"] = bool(res["final"])
	overlay.track(res["rect"])
	if not bool(r.get("sticky", false)) and not HintConditions.test(r.get("when", {})):
		_end("cond")
		return
	if float(_active["elapsed"]) >= float(HintData.v(r.get("ttl", null), _default_ttl)):
		_end("ttl")


func _start(r: Dictionary, res: Dictionary) -> void:
	var id := String(r["id"])
	_active = {"rule": r, "elapsed": 0.0, "lost": 0.0, "tapped": false,
		"rect": res["rect"], "final": bool(res["final"])}
	HintState.mark_seen(id)
	var toast: Dictionary = r.get("toast", {})
	overlay.show_hint(res["rect"], bool(res["world"]), HintArt.icon(String(toast.get("icon", ""))),
		String(toast.get("text", "")), r.get("tip", []), String(r.get("style", "")))
	Sfx.play(String(r.get("sfx", "ui_open")))
	Haptics.tap()
	GameState.emit_event(&"hint_shown", {"id": id})
	hint_shown.emit(id)


func _end(reason: String) -> void:
	if _active.is_empty():
		return
	var id := active_id()
	_active = {}
	overlay.hide_hint(true)
	if DONE_REASONS.has(reason):
		HintState.mark_done(id)
	_gap_left = _gap
	GameState.emit_event(&"hint_done", {"id": id, "why": reason})
	hint_ended.emit(id, reason)


## Принудительно снять текущую подсказку (тест, переключение «подсказки» в настройках).
func dismiss(reason: String = "dismissed") -> void:
	_end(reason)


## Нажатие по цели — действие «сделал». Событие не гасим: нажатие идёт дальше самой кнопке.
func _input(event: InputEvent) -> void:
	if _active.is_empty() or not bool(_active.get("final", false)):
		return
	var pos := Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	else:
		return
	if (_active["rect"] as Rect2).grow(2.0).has_point(pos):
		_active["tapped"] = true

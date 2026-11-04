class_name HurtJuice
extends CanvasLayer
## Отклик на урон по герою (владелец, 27.10): «сотрясение камеры 10 процентов, на
## мгновение зум 10, задержка 0.3 и плавный отход назад в течение 3 секунд, каждый
## новый урон ещё зум 10; экран краснеет, как сейчас, но отходит в нормальный цвет
## за 3 секунды после задержки 0.3; каждый новый урон краснеет ещё сильнее».
##
##  * удар (монстр, снаряд, босс, падение): тряска 10% клетки, наезд камеры +10% к
##    текущему (CameraKick, канал "hurt", потолок), краснота — шаг сильнее текущей
##    (потолок — полупрозрачная, не сплошь красная); обе держатся 0.3 с и за 3 с
##    уходят (ease-out). Новый удар прерывает возврат.
##  * капли урона (лава — каждый кадр): первая капля после затишья — удар, следующие
##    подряд только держат наезд и красноту, а не накачивают их до потолка.
##  * голод и изнеможение (1 HP/с каплями): ни тряски, ни наезда — ровный слабый
##    красный фон, пока HP тает; после — те же 0.3 с и 3 с. Пульсации нет.
## Звук, вибро и «−N» над головой — по-прежнему JuiceDirector. Подключает FeelDirector.

const QUIET_SOURCES := ["starvation", "exhaustion", "heat"]   # жара жжёт каждый кадр — тихо, как голод
const COL := Color(0.85, 0.08, 0.1)   # тот же красный, что у прежней вспышки урона

var clock: float = 0.0
var red_peak: float = 0.0
var red_hold: float = 0.0
var red_prog: float = 1.0      # 0..1 — доля возврата; 1 — красноты нет
var quiet: float = 0.0         # альфа слабого фона «тихого» урона
var _quiet_last: float = -1.0e9
var _drip_last: float = -1.0e9
var _rect: ColorRect = null
var _connected: bool = false

## Для тестов: что отклик сделал.
var stats: Dictionary = {"hits": 0, "held": 0, "quiet": 0}


static func num(key: String, default: float) -> float:
	return Feel.num("hurt." + key, default)


func _ready() -> void:
	layer = UiLayers.HURT   # над HUD и окнами, под общей вспышкой Fx (58) и окном смерти (93)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.name = "HurtTint"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(COL, 0.0)
	_rect.visible = false
	add_child(_rect)
	if not _connected:
		_connected = true
		GameState.damaged.connect(on_damage)
		GameState.died.connect(reset)
		GameState.respawned.connect(reset)


func _exit_tree() -> void:
	if not _connected:
		return
	_connected = false
	for pair in [[GameState.damaged, on_damage], [GameState.died, reset], [GameState.respawned, reset]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


func _process(delta: float) -> void:
	tick(minf(delta, 0.1))


func on_damage(amount: float, source: String, _info: Dictionary = {}) -> void:
	if amount <= 0.0 or not GameState.is_alive or GameState.hp <= 0.0:
		return   # добивающий удар — у смерти своя вспышка и окно
	if source in QUIET_SOURCES:
		_quiet_last = clock
		stats["quiet"] += 1
		return
	var hold := num("hold_s", 0.3)
	if amount < num("hit_min_hp", 1.5):
		var going := clock - _drip_last <= hold
		_drip_last = clock
		if going:
			_hold(hold)
			return
	_hit(amount)


func _hit(amount: float) -> void:
	stats["hits"] += 1
	var hold := num("hold_s", 0.3)
	CameraKick.shake(num("shake_cells", 0.10), num("shake_s", 0.2))
	CameraKick.zoom_punch(num("zoom_step", 0.10), hold, num("return_s", 3.0), "hurt", num("zoom_max", 0.40))
	# «как сейчас»: прежняя вспышка урона 0.18 + доля HP × 1.2; каждый следующий
	# удар — шаг сильнее того, что ещё не ушло
	var share := clampf(amount / maxf(GameState.get_max_hp(), 1.0), 0.0, 1.0)
	var base := clampf(num("red_base", 0.18) + share * num("red_share_gain", 1.2),
			num("red_base", 0.18), num("red_base_max", 0.36))
	red_peak = minf(maxf(red_value() + num("red_step", 0.15), base), num("red_max", 0.5))
	red_hold = hold
	red_prog = 0.0
	_apply()


## Непрерывный урон держит отклик на месте: начатый возврат замирает, не скачет.
func _hold(hold: float) -> void:
	stats["held"] += 1
	CameraKick.zoom_hold("hurt", hold)
	if red_prog >= 1.0:
		return
	if red_prog > 0.0:
		red_peak = red_value()
		red_prog = 0.0
	red_hold = maxf(red_hold, hold)


func red_value() -> float:
	if red_prog >= 1.0:
		return 0.0
	return red_peak * (1.0 - sin(clampf(red_prog, 0.0, 1.0) * PI * 0.5))


## Итоговая альфа красноты (с учётом «меньше движения»).
func alpha() -> float:
	var a := maxf(red_value(), quiet)
	if Settings.reduce_motion:
		a *= num("reduce_motion_k", 0.3)
	return a


func tick(dt: float) -> void:
	clock += dt
	if red_prog < 1.0:
		var t := dt
		if red_hold > 0.0:
			var used := minf(red_hold, t)
			red_hold -= used
			t -= used
		if t > 0.0:
			red_prog = minf(red_prog + t / maxf(num("return_s", 3.0), 0.01), 1.0)
	var q := num("quiet_alpha", 0.07)
	var want := q if clock - _quiet_last <= num("hold_s", 0.3) else 0.0
	if quiet < want:
		quiet = minf(want, quiet + dt * q / maxf(num("quiet_rise_s", 0.5), 0.01))
	elif quiet > want:
		quiet = maxf(want, quiet - dt * q / maxf(num("return_s", 3.0), 0.01))
	_apply()


func _apply() -> void:
	if _rect == null:
		return
	var a := alpha()
	_rect.color = Color(COL, a)
	_rect.visible = a > 0.002


## Смерть и возрождение: краснота и наезд урона снимаются сразу (у смерти своя
## вспышка, окно смерти камеру не дёргает).
func reset() -> void:
	red_peak = 0.0
	red_hold = 0.0
	red_prog = 1.0
	quiet = 0.0
	_quiet_last = -1.0e9
	_drip_last = -1.0e9
	CameraKick.clear("hurt")
	_apply()

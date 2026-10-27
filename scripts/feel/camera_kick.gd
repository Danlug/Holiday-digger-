class_name CameraKick
extends RefCounted
## Общий «толчок» камеры: наезд (zoom) с задержкой и плавным возвратом и короткая
## тряска. Им пользуются отклики урона (HurtJuice, канал "hurt") и удачи (канал
## "luck"); вклады СКЛАДЫВАЮТСЯ, а не перетирают друг друга.
##
## Наезд: у каждого канала своя огибающая «мгновенно +amount → держится hold_s →
## ease-out к норме за return_s». Повтор в тот же канал прибавляет к ТЕКУЩЕМУ
## значению канала (не выше потолка канала) и заново запускает задержку; итог —
## сумма каналов, не выше общего потолка. Масштаб применяет CameraRig
## (1 + старый Feel.punch + zoom_extra()), он же тикает огибающие каждый кадр.
##
## Где толчка нет: «меньше движения» — ни наезда, ни тряски; полёт на ранце,
## бурмобиль и переход в него — новый наезд не принимается, начатый быстро и
## плавно уходит; сцена сюжета или меню (герой заморожен) — ещё и без тряски;
## окно смерти — всё сброшено.
##
## Статика — только числа и словарь чисел (гигиена статик, ГДД §19); сброс —
## reset() из CameraRig.reset_static().

const TILE_PX := 32.0

static var _ch: Dictionary = {}          # канал → {peak, hold, ret, prog}
static var block_zoom: bool = false      # по последнему кадру камеры
static var block_shake: bool = false
## Для тестов: последняя принятая тряска (пиксели) и сколько их было.
static var last_shake_px: float = 0.0
static var shakes: int = 0


## Общий потолок суммы наездов всех каналов (доля масштаба: 0.45 = +45%).
static func max_total() -> float:
	return Feel.num("camera_kick.max_total", 0.45)


## Наезд +amount (0.10 = +10%), держится hold_s, затем ease-out к норме за return_s.
## cap — потолок канала (0 — общий). false — отказ (см. шапку).
static func zoom_punch(amount: float, hold_s: float = 0.0, return_s: float = 0.35,
		channel: String = "", cap: float = 0.0) -> bool:
	if amount <= 0.0 or Settings.reduce_motion or block_zoom:
		return false
	var top := max_total() if cap <= 0.0 else minf(cap, max_total())
	_ch[channel] = {
		"peak": minf(channel_value(channel) + amount, top),
		"hold": maxf(hold_s, 0.0),
		"ret": maxf(return_s, 0.01),
		"prog": 0.0,
	}
	return true


## Продлить задержку канала, не добавляя наезда: непрерывный урон (лава) держит
## наезд, а не накачивает его каждый кадр. Если возврат уже начался, канал замирает
## на текущем значении — без скачка обратно к пику.
static func zoom_hold(channel: String, hold_s: float) -> void:
	if not _ch.has(channel) or block_zoom:
		return
	var e: Dictionary = _ch[channel]
	if float(e["prog"]) > 0.0:
		e["peak"] = channel_value(channel)
		e["prog"] = 0.0
	e["hold"] = maxf(float(e["hold"]), hold_s)


## Тряска, амплитуда в долях клетки (0.1 = 10% клетки = 3.2 px): складывается с
## остатком текущей тряски (FxService.shake_add), не выше потолка.
static func shake(cells: float, duration: float = 0.2) -> void:
	if cells <= 0.0 or Settings.reduce_motion or block_shake:
		return
	var px := cells * TILE_PX
	last_shake_px = px
	shakes += 1
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var n := tree.get_first_node_in_group(Fx.GROUP)
	if n == null:
		return
	if n.has_method("shake_add"):
		n.call("shake_add", px, duration, Feel.num("camera_kick.shake_max_cells", 0.25) * TILE_PX)
	else:
		n.call("shake", px, duration)


## Текущая добавка канала к масштабу (0 — канала нет).
static func channel_value(channel: String) -> float:
	if not _ch.has(channel):
		return 0.0
	var e: Dictionary = _ch[channel]
	# ease-out (синус): быстро трогается, мягко садится на 1.0
	return float(e["peak"]) * (1.0 - sin(clampf(float(e["prog"]), 0.0, 1.0) * PI * 0.5))


## Сумма всех каналов, не выше общего потолка.
static func zoom_extra() -> float:
	var s := 0.0
	for k in _ch.keys():
		s += channel_value(k)
	return minf(s, max_total())


static func has_channel(channel: String) -> bool:
	return _ch.has(channel)


## Один кадр. p — герой (frozen, thrust, rig_transition, is_in_rig()); null —
## блокировки не меняются (тесты шагают вручную).
static func tick(dt: float, p: Object = null) -> void:
	if p != null:
		_update_blocks(p)
	if Settings.reduce_motion or DeathWindow.is_open_any():
		_ch.clear()
		return
	var fast := maxf(Feel.num("camera_kick.blocked_return_s", 0.4), 0.01)
	for k in _ch.keys():
		var e: Dictionary = _ch[k]
		var t := dt
		if block_zoom:
			e["hold"] = 0.0
			e["ret"] = minf(float(e["ret"]), fast)
		else:
			var h := float(e["hold"])
			if h > 0.0:
				var used := minf(h, t)
				e["hold"] = h - used
				t -= used
		if t > 0.0:
			e["prog"] = float(e["prog"]) + t / float(e["ret"])
		if float(e["prog"]) >= 1.0:
			_ch.erase(k)


static func _update_blocks(p: Object) -> void:
	var frozen := "frozen" in p and bool(p.get("frozen"))
	var flying := "thrust" in p and String(p.get("thrust")) != ""
	var rig := (p.has_method("is_in_rig") and bool(p.call("is_in_rig"))) \
			or ("rig_transition" in p and String(p.get("rig_transition")) != "")
	block_shake = frozen or DeathWindow.is_open_any()
	block_zoom = block_shake or flying or rig


## Убрать наезд канала (или всех, channel == "").
static func clear(channel: String = "") -> void:
	if channel == "":
		_ch.clear()
	else:
		_ch.erase(channel)


static func reset() -> void:
	_ch.clear()
	block_zoom = false
	block_shake = false
	last_shake_px = 0.0
	shakes = 0

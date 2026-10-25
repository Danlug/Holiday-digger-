class_name HouseDeliveryBadge
extends CanvasLayer
## HouseDeliveryBadge — значок доставки еды: курьер в кольце, которое
## заполняется за delivery_seconds (ГДД п.7: «к входной двери за 5 секунд»), и
## число секунд под ним. Видно везде (в шахте, на огороде, дома): заказ можно
## сделать и уйти, а вернуться к двери — решение игрока.
##
## Когда курьер доехал — в кольце кулак у двери (стук, звук door), потом пакет
## с галочкой, и значок гаснет. Текста нет: что это — в подсказке Tip.
##
## Слой ниже магазина и выше интерьера дома: виден поверх комнаты и мира, но не
## поверх витрины. Свои секунды значок считает сам; приезд объявляет дом
## (arrive) — таймер доставки остаётся одним, в HouseSystem.

const LAYER_ORDER := 10
const POS := Vector2(6.0, 108.0)
const SIZE := Vector2(52.0, 66.0)
const KNOCK_SECONDS := 1.3
const DONE_SECONDS := 1.4

var _holder: Control
var _ring: Ring
var _icon: TextureRect
var _label: Label
var _orders: Array = []   # [{id, left, total}] в порядке заказа
var _state := "idle"      # idle | transit | knock | done
var _state_t := 0.0
var _shake: Tween


## Кольцо из «пикселей»: N квадратиков по кругу, заполненные — золотые.
class Ring extends Control:
	const TICKS := 24
	const RADIUS := 22.0
	var progress := 0.0
	var tint := Color(1.0, 0.85, 0.35)

	func _draw() -> void:
		var c := size * 0.5
		var filled := int(round(progress * float(TICKS)))
		for i in TICKS:
			var a := -PI * 0.5 + TAU * float(i) / float(TICKS)
			var p := (c + Vector2.from_angle(a) * RADIUS).round() - Vector2(1.5, 1.5)
			var col := tint if i < filled else Color(1, 1, 1, 0.16)
			draw_rect(Rect2(p, Vector2(3, 3)), Color(0.05, 0.04, 0.08, 0.9))
			draw_rect(Rect2(p + Vector2(0.5, 0.5), Vector2(2, 2)), col)


func _ready() -> void:
	layer = LAYER_ORDER
	_holder = Control.new()
	_holder.position = POS
	_holder.size = SIZE
	_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_holder.visible = false
	add_child(_holder)

	var body := HouseArt.nine("tile_body", 5, Color(1, 1, 1, 0.92), Vector2(48, 48))
	body.position = Vector2(2, 0)
	_holder.add_child(body)
	_ring = Ring.new()
	_ring.size = Vector2(52, 52)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_ring)
	_icon = ShopArt.rect(HouseArt.tex("courier"), Vector2(10, 8), Vector2(32, 32))
	_icon.pivot_offset = Vector2(16, 16)
	_holder.add_child(_icon)
	_label = ShopArt.label("", 11, Color.WHITE, HouseArt.INK, 4)
	_label.position = Vector2(0, 50)
	_label.size = Vector2(52, 14)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_holder.add_child(_label)
	Tip.bind(_holder, "Курьер едет", "Заказ приедет к входной двери. Заберёшь его дома.")


## Заказ ушёл: курьер выехал, кольцо побежало.
func track(id: String, seconds: float) -> void:
	_orders.append({"id": id, "left": seconds, "total": maxf(0.1, seconds)})
	if _state != "transit":
		_enter_transit()
	_update_tip()
	UiAnim.pulse(_holder, 0.15, 0.3)


## Курьер доехал до двери (зовёт дом по концу таймера доставки).
func arrive(id: String) -> void:
	for i in _orders.size():
		if String(_orders[i]["id"]) == id:
			_orders.remove_at(i)
			break
	_enter_knock()


## Сбросить значок (смена сейва, тесты): заказы в пути забыты.
func reset() -> void:
	_orders.clear()
	_state = "idle"
	if _shake != null:
		_shake.kill()
	if _holder != null:
		_holder.visible = false


func is_visible_now() -> bool:
	return _holder != null and _holder.visible


func state() -> String:
	return _state


func orders_in_flight() -> int:
	return _orders.size()


func _enter_transit() -> void:
	_state = "transit"
	_state_t = 0.0
	_icon.texture = HouseArt.tex("courier")
	_icon.size = Vector2(32, 32)
	_icon.position = Vector2(10, 8)
	_ring.tint = Color(1.0, 0.85, 0.35)
	_holder.modulate.a = 1.0
	_holder.visible = true
	if _shake != null:
		_shake.kill()
	_icon.rotation = 0.0


func _enter_knock() -> void:
	_state = "knock"
	_state_t = 0.0
	_ring.progress = 1.0
	_ring.tint = Color(0.45, 1.0, 0.65)
	_ring.queue_redraw()
	_icon.texture = HouseArt.tex("knock")
	_icon.size = Vector2(28, 28)
	_icon.position = Vector2(12, 10)
	_icon.pivot_offset = Vector2(14, 14)
	_label.text = ""
	_holder.visible = true
	_holder.modulate.a = 1.0
	if Settings.reduce_motion or not is_inside_tree():
		return
	# Звук стука дом играет сам (его удары синхронны с роликом у двери).
	# Три удара: значок «стучит» вперёд-назад.
	if _shake != null:
		_shake.kill()
	_shake = create_tween()
	for i in 3:
		_shake.tween_property(_icon, "position:x", 17.0, 0.07)
		_shake.tween_property(_icon, "position:x", 12.0, 0.1)
		_shake.tween_interval(0.12)


func _enter_done() -> void:
	_state = "done"
	_state_t = 0.0
	_icon.texture = HouseArt.tex("act_package")
	_icon.size = Vector2(28, 28)
	_icon.position = Vector2(12, 10)
	_label.text = ""
	UiAnim.pulse(_icon, 0.35, 0.35)
	ShopFx.sparkles(_holder, Vector2(26, 24), Color(0.5, 1.0, 0.7), 10, 26.0)
	Sfx.play("ui_buy")


func _process(delta: float) -> void:
	if _holder == null or _state == "idle":
		return
	_state_t += delta
	match _state:
		"transit":
			var shown: Dictionary = _orders[0] if not _orders.is_empty() else {}
			if shown.is_empty():
				_finish()
				return
			for o in _orders:
				o["left"] = maxf(0.0, float(o["left"]) - delta)
			# Кольцо — у ближайшего заказа; число — сколько секунд ему осталось.
			var soon: Dictionary = _orders[0]
			for o in _orders:
				if float(o["left"]) < float(soon["left"]):
					soon = o
			_ring.progress = 1.0 - float(soon["left"]) / float(soon["total"])
			_ring.queue_redraw()
			_label.text = str(int(ceil(float(soon["left"]))))
		"knock":
			if _state_t >= KNOCK_SECONDS:
				_enter_done()
		"done":
			if _state_t >= DONE_SECONDS:
				if _orders.is_empty():
					_finish()
				else:
					_enter_transit()


func _finish() -> void:
	_state = "idle"
	if _holder == null:
		return
	if Settings.reduce_motion or not is_inside_tree():
		_holder.visible = false
		return
	var tw := create_tween()
	tw.tween_property(_holder, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		if _state == "idle":
			_holder.visible = false
		_holder.modulate.a = 1.0)


func _update_tip() -> void:
	var n := _orders.size()
	Tip.bind(_holder, "Курьер едет", "Заказ приедет к входной двери. Заберёшь его дома.",
		"Заказов в пути: %d" % n if n > 1 else "")
	UiBtn.set_badge(_holder, n if n > 1 else 0)

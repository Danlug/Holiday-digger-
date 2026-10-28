class_name UiAnim
extends RefCounted
## UiAnim — движение интерфейса с уважением к «меньше движения»
## (Settings.reduce_motion): окна идут пружиной, при включённом флаге — только
## короткое проявление.
##
## Все функции безопасны для узла вне дерева: без дерева твин не создать, и
## тогда состояние просто выставляется сразу.


## Единые длительности и размах движения интерфейса: окна и шторки берут их
## отсюда, а не подбирают числа каждое сами (раньше было 0.12…0.22 и 0.85…0.97).
const D_IN := 0.18       # появление окна, шторки, меню
const D_OUT := 0.12      # закрытие: короче открытия — это ответ на нажатие
const D_TAB := 0.14      # смена вкладки
const SHEET_DY := 28.0   # на сколько выезжает шторка снизу
const POP_FROM := 0.92   # с какого масштаба всплывает окно по центру
const TAP_SCALE := 0.92  # во сколько «проседает» кнопка под пальцем
const RESPONSE := 0.3       # отклик пружины окна и шторки, с
const RESPONSE_TAP := 0.1   # отклик кнопки под пальцем
const RESPONSE_FADE := 0.1  # «меньше движения»: короткое проявление
const WIN_META := &"_ui_anim_win"
const PRESS_META := &"_ui_anim_press"

## Как показывать и убирать окно: SHEET — выезд снизу, POP — всплытие по центру,
## FADE — просто проявление (вкладки, подложки).
enum Kind { SHEET, POP, FADE }


static func reduced() -> bool:
	return Settings.reduce_motion


## Без окна (headless-тесты) и без «меньше движения» переходы мгновенные: так
## состояние `visible` в тестах меняется сразу, как и раньше.
static func instant(c: Control) -> bool:
	return reduced() or _still(c)


## Совсем без движения: узла нет, он вне дерева, нет окна или идёт сцена тестов
## (снимки экранов ждут окно уже открытым).
static func _still(c: Control) -> bool:
	if c == null or not c.is_inside_tree() or DisplayServer.get_name() == "headless":
		return true
	var cs := c.get_tree().current_scene
	return cs != null and cs.scene_file_path.begins_with("res://tests/")


## Критически задемпфированная пружина (затухание 1.0): к target без перелёта.
## Смена target идёт от текущих x и скорости v — разворот без скачка.
class Spring extends RefCounted:
	var x := 0.0
	var v := 0.0
	var target := 0.0
	var response := 0.3
	var node: Node
	var apply := Callable()   # func(x) — выставить значение на узле
	var done := Callable()    # один раз, когда пришли в target
	var rest := Vector2.ZERO  # место карточки, когда окно открыто
	var fade: Control         # что проявляется

	## Точное решение за шаг dt: устойчиво при любом кадре.
	func step(dt: float) -> void:
		var w := TAU / response
		var d := x - target
		var c := v + w * d
		var e := exp(-w * dt)
		x = target + (d + c * dt) * e
		v = (v - w * c * dt) * e

	func settled() -> bool:
		return absf(x - target) < 0.002 and absf(v) < 0.02

	var _tree: SceneTree

	func running() -> bool:
		return _tree != null and _tree.process_frame.is_connected(_tick)

	func run() -> void:
		if not running():
			_tree = node.get_tree()
			_tree.process_frame.connect(_tick)

	func stop() -> void:
		if running():
			_tree.process_frame.disconnect(_tick)
		_tree = null

	func _tick() -> void:
		if not is_instance_valid(node):
			stop()
			return
		step(node.get_process_delta_time())
		if not node.is_inside_tree() or settled():
			x = target
			v = 0.0
			stop()
		if apply.is_valid():
			apply.call(x)
		if not running() and done.is_valid():
			var d := done
			done = Callable()
			d.call()


static func _spring(c: Control, key: StringName) -> Spring:
	if not c.has_meta(key):
		var s := Spring.new()
		s.node = c
		c.set_meta(key, s)
	return c.get_meta(key)


## Поза окна на доле p (0 — убрано, 1 — открыто). calm — только прозрачность.
static func _pose(p: float, card: Control, fade: Control, kind: int, calm: bool, rest: Vector2) -> void:
	if not is_instance_valid(card):
		return
	if is_instance_valid(fade):
		fade.modulate.a = clampf(p, 0.0, 1.0)
	if calm:
		return
	match kind:
		Kind.SHEET:
			card.position.y = rest.y + SHEET_DY * (1.0 - p)
		Kind.POP:
			# точка масштаба — центр, пока вызывающий не задал свою (кнопка-источник)
			if card.pivot_offset == Vector2.ZERO:
				card.pivot_offset = card.size * 0.5
			card.scale = Vector2.ONE * lerpf(POP_FROM, 1.0, p)


static func _rest(card: Control) -> Vector2:
	return (card.get_meta(WIN_META) as Spring).rest if card.has_meta(WIN_META) else card.position


## Мгновенный путь: остановить окно, если оно в пути, и вернуть карточку на место.
static func _halt(card: Control) -> void:
	if not card.has_meta(WIN_META):
		return
	var s: Spring = card.get_meta(WIN_META)
	if s.running():
		s.stop()
		s.done = Callable()
		card.position = s.rest
		card.scale = Vector2.ONE
		if is_instance_valid(s.fade):
			s.fade.modulate.a = 1.0


## Ведёт окно пружиной к target (1 — открыть, 0 — убрать). Если окно уже в пути,
## разворачивается от текущей позы и скорости: тем же путём, без скачка.
static func _drive(card: Control, kind: int, fade: Control, target: float, done: Callable) -> void:
	var s := _spring(card, WIN_META)
	if not s.running():
		s.rest = card.position
		s.x = 1.0 - target
		s.v = 0.0
	if is_instance_valid(s.fade) and s.fade != fade:
		s.fade.modulate.a = 1.0
	s.fade = fade
	var calm := reduced()
	var rest := s.rest
	s.response = RESPONSE_FADE if calm else RESPONSE
	s.target = target
	s.apply = func(p: float) -> void: _pose(p, card, fade, kind, calm, rest)
	s.done = done
	s.apply.call(s.x)
	s.run()


## Единый показ. root — то, что включают/выключают (узел с подложкой), card — то,
## что движется. Если root == card, движется и проявляется один узел.
static func open(card: Control, kind: int = Kind.POP, root: Control = null) -> void:
	if card == null:
		return
	if _still(card):
		_halt(card)
		card.modulate.a = 1.0
		card.scale = Vector2.ONE
		if root != null:
			root.modulate.a = 1.0
		return
	var fade: Control = root if root != null else card
	if fade != card:
		card.modulate.a = 1.0
	_drive(card, kind, fade, 1.0, Callable())


## Единое закрытие: карточка уходит тем же путём, каким пришла, и только потом
## root прячется. Вызывающий сам сделал свою часть логики до вызова (флаги,
## сигналы), так что во время ухода окно уже «закрыто» по смыслу — просто ещё видно.
## Откроют снова посреди ухода — окно развернётся, а done не вызовется.
static func close(card: Control, kind: int = Kind.POP, root: Control = null, done: Callable = Callable()) -> void:
	var target: Control = root if root != null else card
	if card == null or target == null:
		return
	if _still(card) or not target.visible:
		_halt(card)
		target.visible = false
		if done.is_valid():
			done.call()
		return
	_drive(card, kind, target, 0.0, func() -> void:
		if not is_instance_valid(target) or not is_instance_valid(card):
			return
		target.visible = false
		target.modulate.a = 1.0
		card.position = _rest(card)
		card.scale = Vector2.ONE
		if done.is_valid():
			done.call())


## Отклик кнопки под пальцем: пружина ~0.1 с от текущего масштаба (нажал и сразу
## отпустил — без рывка). Звать на button_down (down) и button_up.
static func press(c: Control, down: bool, to: float = TAP_SCALE) -> void:
	if c == null or not c.is_inside_tree() or reduced():
		return
	var s := _spring(c, PRESS_META)
	if not s.running():
		s.x = c.scale.x
		s.v = 0.0
	s.response = RESPONSE_TAP
	s.target = to if down else 1.0
	s.apply = func(k: float) -> void:
		if is_instance_valid(c):
			c.scale = Vector2(k, k)
	s.run()


## «Меньше движения»: вместо сдвига и масштаба — короткое проявление.
static func _calm_in(c: Control) -> void:
	if _still(c):
		return
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, D_TAB)


static func _center_pivot(c: Control) -> void:
	c.pivot_offset = c.size * 0.5


## Всплытие: из чуть меньшего масштаба и прозрачности — в норму.
static func appear(c: Control, from_scale: float = 0.9, duration: float = 0.14) -> void:
	if c == null:
		return
	c.modulate.a = 1.0
	c.scale = Vector2.ONE
	if not c.is_inside_tree():
		return
	if reduced():
		_calm_in(c)
		return
	_center_pivot(c)
	c.scale = Vector2.ONE * from_scale
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, duration * 0.8)


## Плитки сетки или карточки списка всплывают по очереди (шаг step секунд, не дольше
## max_total всего). Размер для точки вращения берётся в момент показа: сразу после
## добавления в контейнер он ещё нулевой.
static func stagger(nodes: Array, step: float = 0.03, from_scale: float = 0.85, max_total: float = 0.4) -> void:
	if nodes.is_empty() or instant(nodes[0] as Control):
		return
	var n := nodes.size()
	var dt := minf(step, max_total / float(n))
	for i in n:
		var c := nodes[i] as Control
		if c == null or not c.is_inside_tree():
			continue
		c.modulate.a = 0.0
		var tw := c.create_tween()
		tw.tween_interval(dt * float(i))
		tw.tween_callback(func() -> void:
			c.pivot_offset = c.size * 0.5
			c.scale = Vector2.ONE * from_scale)
		tw.tween_property(c, "scale", Vector2.ONE, D_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(c, "modulate:a", 1.0, D_IN * 0.7)


## Шторка выезжает снизу: сдвиг вверх на dy и появление.
static func slide_up(c: Control, dy: float = 24.0, duration: float = 0.2) -> void:
	if c == null:
		return
	c.modulate.a = 1.0
	var target_y := c.position.y
	if not c.is_inside_tree():
		return
	if reduced():
		_calm_in(c)
		return
	c.position.y = target_y + dy
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "position:y", target_y, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, duration * 0.8)


## «Пульс» — быстро вырасти и вернуться (пришли деньги, подняли находку).
static func pulse(c: Control, amount: float = 0.18, duration: float = 0.22) -> void:
	if c == null or reduced() or not c.is_inside_tree():
		return
	_center_pivot(c)
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), duration * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, duration * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Короткая встряска по горизонтали (отказ, не хватает места).
static func shake(c: Control, strength: float = 3.0, duration: float = 0.24) -> void:
	if c == null or reduced() or not c.is_inside_tree():
		return
	var x0 := c.position.x
	var tw := c.create_tween()
	var steps := 4
	for i in steps:
		var k := 1.0 - float(i) / float(steps)
		tw.tween_property(c, "position:x", x0 + strength * k * (1.0 if i % 2 == 0 else -1.0), duration / float(steps + 1))
	tw.tween_property(c, "position:x", x0, duration / float(steps + 1))

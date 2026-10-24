class_name UiAnim
extends RefCounted
## UiAnim — маленькие твины интерфейса с уважением к «меньше движения»
## (Settings.reduce_motion): при включённом флаге переходы мгновенные.
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
const TW_META := &"_ui_anim_tween"
const REST_META := &"_ui_anim_rest"

## Как показывать и убирать окно: SHEET — выезд снизу, POP — всплытие по центру,
## FADE — просто проявление (вкладки, подложки).
enum Kind { SHEET, POP, FADE }


static func reduced() -> bool:
	return Settings.reduce_motion


## Без окна (headless-тесты) и без «меньше движения» переходы мгновенные: так
## состояние `visible` в тестах меняется сразу, как и раньше.
static func instant(c: Control) -> bool:
	return reduced() or c == null or not c.is_inside_tree() or DisplayServer.get_name() == "headless"


static func _kill(c: Control) -> void:
	if c.has_meta(TW_META):
		var old = c.get_meta(TW_META)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		c.remove_meta(TW_META)
	if c.has_meta(REST_META):
		c.position = c.get_meta(REST_META)
		c.remove_meta(REST_META)


## Единый показ. root — то, что включают/выключают (узел с подложкой), card — то,
## что движется. Если root == card, движется и проявляется один узел.
static func open(card: Control, kind: int = Kind.POP, root: Control = null) -> void:
	if card == null:
		return
	_kill(card)
	card.modulate.a = 1.0
	card.scale = Vector2.ONE
	if root != null and root != card:
		root.modulate.a = 1.0
	if instant(card):
		return
	match kind:
		Kind.SHEET:
			slide_up(card, SHEET_DY, D_IN)
		Kind.POP:
			appear(card, POP_FROM, D_IN)
		_:
			card.modulate.a = 0.0
			card.create_tween().tween_property(card, "modulate:a", 1.0, D_TAB)
	if root != null and root != card:
		root.modulate.a = 0.0
		var tw := root.create_tween()
		card.set_meta(TW_META, tw)
		tw.tween_property(root, "modulate:a", 1.0, D_IN * 0.8)


## Единое закрытие: карточка уходит за D_OUT и только потом root прячется.
## Вызывающий сам сделал свою часть логики до вызова (флаги, сигналы), так что
## во время ухода окно уже «закрыто» по смыслу — просто ещё видно.
static func close(card: Control, kind: int = Kind.POP, root: Control = null, done: Callable = Callable()) -> void:
	var target: Control = root if root != null else card
	if card == null or target == null:
		return
	_kill(card)
	if instant(card) or not target.visible:
		target.visible = false
		if done.is_valid():
			done.call()
		return
	var rest_pos := card.position
	card.set_meta(REST_META, rest_pos)
	if card.pivot_offset == Vector2.ZERO:
		card.pivot_offset = card.size * 0.5
	var tw := card.create_tween().set_parallel(true)
	card.set_meta(TW_META, tw)
	match kind:
		Kind.SHEET:
			tw.tween_property(card, "position:y", rest_pos.y + SHEET_DY, D_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		Kind.POP:
			tw.tween_property(card, "scale", Vector2.ONE * 0.96, D_OUT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(target, "modulate:a", 0.0, D_OUT)
	tw.chain().tween_callback(func() -> void:
		if not is_instance_valid(target) or not is_instance_valid(card):
			return
		target.visible = false
		target.modulate.a = 1.0
		card.position = rest_pos
		card.scale = Vector2.ONE
		card.remove_meta(REST_META)
		card.remove_meta(TW_META)
		if done.is_valid():
			done.call())


static func _center_pivot(c: Control) -> void:
	c.pivot_offset = c.size * 0.5


## Всплытие: из чуть меньшего масштаба и прозрачности — в норму.
static func appear(c: Control, from_scale: float = 0.9, duration: float = 0.14) -> void:
	if c == null:
		return
	c.modulate.a = 1.0
	c.scale = Vector2.ONE
	if reduced() or not c.is_inside_tree():
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
	if reduced() or not c.is_inside_tree():
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

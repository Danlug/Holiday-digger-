class_name UiAnim
extends RefCounted
## UiAnim — маленькие твины интерфейса с уважением к «меньше движения»
## (Settings.reduce_motion): при включённом флаге переходы мгновенные.
##
## Все функции безопасны для узла вне дерева: без дерева твин не создать, и
## тогда состояние просто выставляется сразу.


static func reduced() -> bool:
	return Settings.reduce_motion


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

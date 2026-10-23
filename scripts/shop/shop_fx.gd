class_name ShopFx
extends RefCounted
## ShopFx — «сок» самой витрины: всё рисуется ВНУТРИ шторки магазина.
##
## Общий фасад Fx (scripts/core/fx.gd) живёт в мире и на своих слоях; шторка
## магазина — непрозрачный слой выше HUD, и эффекты мира под ним не видны.
## Поэтому монеты, искры и вспышки покупки делаются здесь, на узлах шторки,
## твинами: работают и без сервиса Fx, и в скриншотных тестах.


## «Меньше движения» из настроек: эффекты не рисуем, но обратные вызовы
## (кошелёк «капает») всё равно срабатывают.
static func reduced() -> bool:
	return Settings.reduce_motion


## Упругий «щелчок»: узел чуть вырастает и садится на место.
static func pop(c: Control, amount: float = 0.2, t: float = 0.28) -> void:
	if c == null or not is_instance_valid(c) or not c.is_inside_tree() or reduced():
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * (1.0 + amount)
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, t).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Покачивание «нельзя»: поворот, а не сдвиг — контейнер сетки сдвиг затёр бы.
static func wiggle(c: Control) -> void:
	if c == null or not is_instance_valid(c) or not c.is_inside_tree() or reduced():
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	for a in [0.09, -0.09, 0.06, -0.04, 0.0]:
		tw.tween_property(c, "rotation", a, 0.045)


## Короткая вспышка поверх прямоугольника (в координатах host).
static func flash(host: Control, rect: Rect2, color: Color = Color(1, 1, 1, 0.7), t: float = 0.25) -> void:
	if host == null or not host.is_inside_tree() or reduced():
		return
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = rect.position
	r.size = rect.size
	r.z_index = 90
	host.add_child(r)
	var tw := host.create_tween()
	tw.tween_property(r, "modulate:a", 0.0, t)
	tw.tween_callback(r.queue_free)


## Искры веером из точки: крошечные квадраты, дуга вверх и падение.
static func sparkles(host: Control, center: Vector2, color: Color = Color(1, 0.88, 0.4),
		n: int = 12, reach: float = 30.0) -> void:
	if host == null or not host.is_inside_tree() or reduced():
		return
	for i in n:
		var s := ColorRect.new()
		var px := 2.0 if i % 3 else 3.0
		s.size = Vector2(px, px)
		s.color = color if i % 4 else Color.WHITE
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.position = center - s.size * 0.5
		s.z_index = 95
		host.add_child(s)
		var ang := (float(i) / float(n)) * TAU + randf_range(-0.3, 0.3)
		var dist := reach * randf_range(0.55, 1.0)
		var peak := center + Vector2.from_angle(ang) * dist - s.size * 0.5
		var tw := host.create_tween()
		tw.tween_property(s, "position", peak, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "position", peak + Vector2(randf_range(-4, 4), 14.0), 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(s, "modulate:a", 0.0, 0.3).set_delay(0.0)
		tw.tween_callback(s.queue_free)


## Монеты разлетаются от точки и по дуге летят к цели (кошельку). on_arrive
## зовётся на каждое долетевшее значение с индексом — шапка так «капает».
static func coins(host: Control, icon: Texture2D, from: Vector2, to: Vector2, n: int,
		on_arrive: Callable = Callable(), size: float = 12.0) -> void:
	if host == null or not host.is_inside_tree() or icon == null or reduced():
		if on_arrive.is_valid():
			for i in n:
				on_arrive.call(i)
		return
	var sz := Vector2(size, size)
	for i in n:
		var s := TextureRect.new()
		s.texture = icon
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.size = sz
		s.pivot_offset = sz * 0.5
		s.position = from - sz * 0.5
		s.scale = Vector2.ONE * 0.5
		s.z_index = 100
		host.add_child(s)
		var burst := from + Vector2.from_angle(randf() * TAU) * randf_range(8.0, 24.0) - sz * 0.5
		var tw := host.create_tween()
		tw.tween_interval(float(i) * 0.04)
		tw.tween_property(s, "position", burst, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(s, "scale", Vector2.ONE, 0.16)
		tw.tween_interval(0.05)
		tw.tween_property(s, "position", to - sz * 0.5, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(s, "scale", Vector2.ONE * 0.6, 0.4)
		tw.tween_callback(func() -> void:
			if on_arrive.is_valid():
				on_arrive.call(i)
			s.queue_free())


## Число в метке «накручивается» от from до to.
static func count_up(host: Node, label: Label, from: int, to: int, seconds: float = 0.5,
		delay: float = 0.0, fmt: Callable = Callable()) -> Tween:
	if label == null or host == null or not host.is_inside_tree() or from == to:
		if label != null:
			label.text = fmt.call(to) if fmt.is_valid() else str(to)
		return null
	var tw := host.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(v: float) -> void:
		label.text = fmt.call(int(round(v))) if fmt.is_valid() else str(int(round(v))),
		float(from), float(to), seconds)
	return tw

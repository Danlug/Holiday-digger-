class_name TechUi
extends RefCounted
## Общие мелочи экранов техники: иконки (art/tech, art/ui/icons, тайлы руд),
## плитки «иконка + число», полоски. Текста на плитках нет — названия и описания
## в подсказках Tip (решение владельца).

const ART := "res://art/tech/%s.png"

const GOLD := ProgressUiKit.GOLD
const MUTED := ProgressUiKit.MUTED
const DIM := ProgressUiKit.DIM
const GREEN := ProgressUiKit.GREEN
const RED := Color8(0xD0, 0x5A, 0x4E)
const PANEL := ProgressUiKit.CARD_BG
const PANEL_DARK := Color8(0x12, 0x0D, 0x0A)
const BORDER := ProgressUiKit.EDGE
const FIRE := Color8(0xF0, 0x70, 0x1E)

static var _cache: Dictionary = {}


## Картинка из art/tech (null, если файла нет — экран тогда просто без значка).
static func tex(icon_name: String) -> Texture2D:
	if _cache.has(icon_name):
		return _cache[icon_name]
	var path := ART % icon_name
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[icon_name] = t
	return t


## Иконка предмета 32×32: блок — свой значок, руда — тайл мира, сглаженный до
## иконки (тайл на диске 96 px: нарезка «ближайшим» на 28 px рябит), экзотика
## глубже 3000 — значки из art/tech.
static func item_icon(id: String) -> Texture2D:
	var key := "item:" + id
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = ShopArt.tex("item_" + id)   # нарисованный значок ресурса (art/ui/shop/item_<id>.png)
	if t != null:
		pass
	elif id == FuelTank.block_item():
		t = tex("fuel_block")
	else:
		var tile_type := MineralMap.tile_type_for(id)
		var src: Texture2D = TileArt.texture_for(tile_type, 0, 0) if tile_type >= 0 else null
		if src != null:
			var img := src.get_image()
			img.resize(32, 32, Image.INTERPOLATE_LANCZOS)
			t = ImageTexture.create_from_image(img)
		else:
			t = tex("mat_" + id)
	if t == null:
		t = UiIcons.tex("star")
	_cache[key] = t
	return t


## То же для мелких мест (ряд цены 14 px): с ободком, без «нарезки» ближайшим.
static func item_icon_small(id: String, px: int = 16) -> Texture2D:
	var key := "item_small:%s@%d" % [id, px]
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = null
	if id == FuelTank.block_item():
		t = tex("fuel_block")
	else:
		t = UiIcons.item_small(id, px)
	if t == null:
		t = item_icon(id)
	_cache[key] = t
	return t


static func item_name(id: String) -> String:
	if id == FuelTank.block_item():
		return "Топливный блок"
	return ShopCatalog.item_name(id)


static func icon_rect(texture: Texture2D, px: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r


static func label(text: String, size: int = 9, color: Color = MUTED, outline: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Рамка-плитка. selected — золотая; ok — зелёная; bad — красная.
static func box(bg: Color = PANEL, border: Color = BORDER, radius: int = 5, margin: int = 3) -> StyleBoxFlat:
	var sb := ProgressUiKit.box(bg, border, ProgressUiKit.snap_radius(radius), 1)
	sb.set_content_margin_all(margin)
	return sb


## Ряд «иконка + число» (цена, количество). Число красное, если не хватает.
static func chip(texture: Texture2D, number: String, color: Color = MUTED, icon_px: float = 16) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(icon_rect(texture, icon_px))
	row.add_child(label(number, 10, color))
	return row


## Длительность «5ч 12м» / «43м» — числа без слов-абзацев.
static func hm(seconds: float) -> String:
	var total := int(seconds)
	var h := total / 3600
	var m := (total % 3600) / 60
	if h > 0:
		return "%dч %02dм" % [h, m]
	return "%dм" % maxi(m, 0)


## Полоска заполнения: фон + заливка. Двигать заливку — set_fill().
static func make_bar(width: float, height: float, color: Color) -> Control:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(width, height)
	track.add_theme_stylebox_override("panel", box(PANEL_DARK, BORDER, 3, 0))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = color
	fill.position = Vector2(1, 1)
	fill.size = Vector2(width - 2, height - 2)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	var shine := ColorRect.new()
	shine.name = "Shine"
	shine.color = Color(1, 1, 1, 0.18)
	shine.position = Vector2(1, 1)
	shine.size = Vector2(width - 2, 2)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.add_child(shine)
	return track


static func set_fill(bar: Control, fraction: float, color: Color = Color(0, 0, 0, 0), animate: bool = false) -> void:
	var fill := bar.get_node("Fill") as ColorRect
	var w := (bar.custom_minimum_size.x - 2.0) * clampf(fraction, 0.0, 1.0)
	if color.a > 0.0:
		fill.color = color
	if animate and bar.is_inside_tree() and not UiAnim.reduced():
		var tw := bar.create_tween()
		tw.tween_property(fill, "size:x", w, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		fill.size.x = w


## Экранная точка якоря HUD (куда лететь иконкам); без HUD — центр экрана.
static func anchor(id: String) -> Vector2:
	return HudAnchors.get_anchor(id)


## Иконка летит от одной точки экрана к другой и гаснет: на слое host.
## Свой твин вместо Fx.fly_to, потому что нужен колбэк прилёта (счётчик, пульс).
static func fly(host: Node, texture: Texture2D, from: Vector2, to: Vector2, delay: float = 0.0,
		on_arrive: Callable = Callable(), px: float = 18.0) -> void:
	if host == null or not host.is_inside_tree():
		if on_arrive.is_valid():
			on_arrive.call()
		return
	if UiAnim.reduced():
		if on_arrive.is_valid():
			on_arrive.call()
		return
	var r := icon_rect(texture, px)
	r.size = Vector2(px, px)
	r.pivot_offset = r.size * 0.5
	r.position = from - r.size * 0.5
	r.modulate.a = 0.0
	host.add_child(r)
	var mid := (from + to) * 0.5 + Vector2(randf_range(-26.0, 26.0), -24.0)
	var step := func(t: float) -> void:
		# квадратичная кривая Безье: дуга, а не прямая
		var p := from.lerp(mid, t).lerp(mid.lerp(to, t), t)
		r.position = p - r.size * 0.5
		r.scale = Vector2.ONE * lerpf(1.0, 0.55, t)
	var done := func() -> void:
		if on_arrive.is_valid():
			on_arrive.call()
		r.queue_free()
	var tw := r.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(r, "modulate:a", 1.0, 0.05)
	tw.tween_method(step, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(done)

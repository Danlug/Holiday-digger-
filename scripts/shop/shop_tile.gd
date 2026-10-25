class_name ShopTile
extends Button
## ShopTile — плитка витрины 64×64: рамка по ступени, значок товара, бейдж внизу
## (цена, сумма, число материалов) и угловые знаки (галочка, замок, «новинка»).
## Текста на плитке нет вовсе: название, описание и цена — в подсказке Tip.
##
## Плитка рисуется из словаря-«предложения» (см. ShopItems и GDD §16):
##   icon: Texture2D, tier: int 0..5, state: String, title/body/extra: String (Tip),
##   pill: {icon, text, color, pips}, corner: "check"|"lock"|"cross"|"home"|"gift",
##   count_text: String (число в углу значка), selected: bool, new: bool,
##   sub_icon: Texture2D (мелкая «награда» на значке ролика),
##   need_icon: Texture2D — значок проекта «нужно для…» в левом верхнем углу
##   (ProjectChain.decorate_offer); отмеченная к продаже такая плитка горит
##   янтарной рамкой — мягкое предупреждение, продаже не мешает.
## Состояния state: available, poor (не хватает денег), owned, locked, away,
## ready (рецепт можно собрать), active (надето), nosale, off (отключено).

const W := 64.0
const H := 64.0
const COL_GREEN := Color8(0x4D, 0xE0, 0x94)
const COL_NEED := Color8(0xFF, 0x9A, 0x2E)

var offer: Dictionary = {}

var _body: NinePatchRect
var _rim: NinePatchRect
var _glow: TextureRect
var _icon: TextureRect
var _sub: TextureRect
var _count: Label
var _pill: NinePatchRect
var _pill_box: Control
var _corner_tr: TextureRect
var _corner_tl: TextureRect
var _lock: TextureRect
var _pulse: Tween
var _need: NeedBadge


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	flat = true
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())

	_body = _nine("tile_body", 5)
	_rim = _nine("tile_rim", 5)
	_glow = ShopArt.rect(ShopArt.tex("glow"), Vector2(-9, -9), Vector2(W + 18, H + 18))
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.visible = false
	add_child(_glow)
	move_child(_glow, 0)

	_icon = ShopArt.rect(null, Vector2(16, 6), Vector2(32, 32))
	add_child(_icon)
	_sub = ShopArt.rect(null, Vector2(34, 24), Vector2(14, 14))
	_sub.visible = false
	add_child(_sub)
	_lock = ShopArt.rect(ShopArt.tex("glyph_lock"), Vector2(24, 14), Vector2(16, 16))
	_lock.visible = false
	add_child(_lock)

	_count = ShopArt.label("", 9, Color.WHITE, Color(0.05, 0.04, 0.08), 3)
	_count.position = Vector2(2, 27)
	_count.size = Vector2(W - 5, 12)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.visible = false
	add_child(_count)

	_pill = _nine("pill", 4)
	_pill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_pill.position = Vector2(4, 43)
	_pill.size = Vector2(W - 8, 15)
	_pill_box = Control.new()
	_pill_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(_pill_box)

	_corner_tr = _corner(Vector2(W - 15, 1))
	_corner_tl = _corner(Vector2(1, 1))
	button_down.connect(_on_down)
	button_up.connect(_on_up)


func _nine(tex_name: String, margin: int) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = ShopArt.tex(tex_name)
	n.patch_margin_left = margin
	n.patch_margin_right = margin
	n.patch_margin_top = margin
	n.patch_margin_bottom = margin
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(n)
	return n


func _corner(pos: Vector2) -> TextureRect:
	var t := ShopArt.rect(null, pos, Vector2(14, 14))
	t.visible = false
	add_child(t)
	return t


func _on_down() -> void:
	if disabled:
		return
	pivot_offset = size * 0.5
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.93, 0.93), 0.06)


func _on_up() -> void:
	pivot_offset = size * 0.5
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Заполняет плитку из предложения (формат — в шапке файла).
func setup(o: Dictionary) -> void:
	offer = o
	var state := String(o.get("state", "available"))
	var tier := int(o.get("tier", 0))
	var dim := state in ["poor", "locked", "away", "nosale", "off"]
	var rim_col := ShopArt.tier_color(tier)
	var body_col := Color.WHITE
	var icon_col := Color.WHITE

	match state:
		"poor":
			rim_col = rim_col.darkened(0.45)
			body_col = Color(0.72, 0.72, 0.78)
			icon_col = Color(0.55, 0.55, 0.62)
		"locked":
			rim_col = Color8(0x6A, 0x62, 0x78)
			body_col = Color(0.62, 0.62, 0.7)
			icon_col = Color(0.07, 0.06, 0.11)
		"away", "nosale", "off":
			rim_col = rim_col.darkened(0.5)
			body_col = Color(0.7, 0.7, 0.76)
			icon_col = Color(0.55, 0.55, 0.62)
		"active":
			rim_col = ShopArt.COL_GOLD
		"ready":
			rim_col = ShopArt.COL_GOOD
	if o.has("selected"):
		if bool(o["selected"]):
			rim_col = ShopArt.COL_GOLD
		else:
			rim_col = Color8(0x5C, 0x56, 0x68)
			body_col = Color(0.6, 0.6, 0.66)
			icon_col = Color(0.45, 0.45, 0.52)

	_rim.modulate = rim_col
	_body.modulate = body_col
	_icon.texture = o.get("icon", null)
	_icon.modulate = icon_col
	_lock.visible = state == "locked" and not bool(o.get("hide_lock", false))

	var sub: Texture2D = o.get("sub_icon", null)
	_sub.visible = sub != null
	_sub.texture = sub

	var ct := String(o.get("count_text", ""))
	_count.visible = ct != ""
	_count.text = ct
	_count.modulate = Color(1, 1, 1, 0.55) if dim else Color.WHITE

	_set_pill(o.get("pill", {}))
	_set_corner(_corner_tr, String(o.get("corner", "")))
	var tl := ""
	if bool(o.get("new", false)):
		tl = "new"
	elif String(o.get("corner_tl", "")) != "":
		tl = String(o.get("corner_tl"))
	_set_corner(_corner_tl, tl)
	_set_need(o)

	_glow.visible = state in ["ready", "active"] or bool(o.get("new", false))
	if _glow.visible:
		_glow.modulate = Color(0.45, 1.0, 0.65, 0.6) if state == "ready" else Color(1, 0.9, 0.5, 0.6)
		_start_pulse()

	Tip.bind(self, String(o.get("title", "")), String(o.get("body", "")), String(o.get("extra", "")))


## Значок «нужно для…» (ветка guidance): у материала открытого проекта. Если
## такая плитка отмечена к продаже — янтарная рамка и пульс значка.
func _set_need(o: Dictionary) -> void:
	var tex: Texture2D = o.get("need_icon", null)
	if tex == null:
		if _need != null:
			_need.visible = false
		return
	if _need == null:
		_need = NeedBadge.new()
		add_child(_need)
	_need.texture = tex
	_need.position = Vector2(0, 17) if _corner_tl.visible else Vector2(0, 0)
	_need.visible = true
	# Продажа «за ролик» из-под земли сдаёт всё разом — там отметок нет, и плитка
	# предупреждает сразу.
	_need.warn = bool(o.get("selected", String(o.get("kind", "")) == "sell"))
	if _need.warn:
		_rim.modulate = COL_NEED


## Твин нельзя создать, пока узел вне дерева, поэтому плитку, собранную до
## add_child, запускаем при входе в дерево.
func _enter_tree() -> void:
	_start_pulse()


func _start_pulse() -> void:
	if _glow == null or not _glow.visible or not is_inside_tree():
		return
	if _pulse != null:
		_pulse.kill()
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_glow, "modulate:a", 0.25, 0.9).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(_glow, "modulate:a", 0.7, 0.9).set_trans(Tween.TRANS_SINE)


func _set_corner(t: TextureRect, kind: String) -> void:
	if kind == "":
		t.visible = false
		return
	var name := "glyph_" + kind
	t.texture = ShopArt.tex(name)
	t.visible = t.texture != null


func _set_pill(p: Dictionary) -> void:
	for c in _pill_box.get_children():
		_pill_box.remove_child(c)
		c.queue_free()
	var text := String(p.get("text", ""))
	var icon: Texture2D = p.get("icon", null)
	var pips: Array = p.get("pips", [])
	if text == "" and icon == null and pips.is_empty():
		_pill.visible = false
		return
	_pill.visible = true
	var col: Color = p.get("color", Color.WHITE)
	# Части бейджа: [узел, ширина].
	var parts: Array = []
	if icon != null:
		parts.append([ShopArt.rect(icon, Vector2.ZERO, Vector2(11, 11)), 11.0])
	for ok in pips:
		var d := ColorRect.new()
		d.size = Vector2(5, 5)
		d.color = ShopArt.COL_GOOD if bool(ok) else ShopArt.COL_BAD
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parts.append([d, 5.0])
	if text != "":
		var l := ShopArt.label(text, 9, col, Color(0.05, 0.04, 0.08), 2)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var tw := l.get_minimum_size().x
		l.size = Vector2(tw, 15.0)
		parts.append([l, tw])
	var total := -2.0
	for pt in parts:
		total += float(pt[1]) + 2.0
	var pill_w := clampf(total + 10.0, 22.0, W - 8.0)
	_pill.size.x = pill_w
	_pill.position.x = (W - pill_w) * 0.5
	var x := (pill_w - total) * 0.5
	for pt in parts:
		var c: Control = pt[0]
		c.position = Vector2(x, (15.0 - c.size.y) * 0.5)
		_pill_box.add_child(c)
		x += float(pt[1]) + 2.0


## Плитка «не получилось»: качнуться и мигнуть красным бейджем.
func deny() -> void:
	ShopFx.wiggle(self)
	if _pill != null and _pill.visible:
		var tw := create_tween()
		_pill.modulate = Color(1, 0.35, 0.35)
		tw.tween_property(_pill, "modulate", Color.WHITE, 0.4)


func pill_center() -> Vector2:
	return get_global_rect().get_center()

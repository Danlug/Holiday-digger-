class_name PremiumUnloadFx
extends CanvasLayer
## PremiumUnloadFx — отклик выгрузки на склад (раунд 6): «улетело домой».
##
## Вверху экрана всплывает домик, значки добычи (самые крупные стопки) по дуге
## летят к нему из точки нажатия, домик подпрыгивает на каждый, под ним — «×N»
## (сколько штук ушло), потом домик уезжает вверх и гаснет. Звук — свист взлёта,
## «тук» прилёта с повышением тона, дверь в конце. Это не тост и не счётчик «•••»
## (их владелец просил не трогать): короткая анимация поверх витрины, сама себя
## удаляет. «Меньше движения» — домик с «×N» просто стоит и гаснет.

const LAYER := UiLayers.PREMIUM_FX          # над витриной (20), подсказками (40) и летящими монетами Fx (59)
const HOUSE := 28.0
const PLATE := Vector2(52, 52)
## Плашка — в середине экрана, ниже двух рядов плиток витрины за доллары: сверху
## её закрывали бы тосты достижений и баннеры вех (они выше по слоям).
const PLATE_Y := 0.52
const ICON := 16.0
const MAX_ICONS := 7
const FLY := 0.46
const STAGGER := 0.07
const HOLD := 0.45
## Сколько длится всё целиком при MAX_ICONS (уроку — сколько ждать до объяснения).
const DURATION := 0.2 + STAGGER * (MAX_ICONS - 1) + FLY + HOLD + 0.35
const GOLD := UiTheme.GOLD

var count: int = 0
var _root: Control
var _plate: Panel
var _house: TextureRect
var _label: Label
var _landed: int = 0
var _icons: int = 0


## Запустить на дереве host: from — откуда летит (экранные единицы), moved — {id: штук}.
static func play(host: Node, from: Vector2, moved: Dictionary) -> PremiumUnloadFx:
	var fx := PremiumUnloadFx.new()
	host.get_tree().root.add_child(fx)
	fx.run(from, moved)
	return fx


func _init() -> void:
	layer = LAYER
	name = "PremiumUnloadFx"
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	# Домик и «×N» на своей тёмной плашке: поверх плиток витрины и поверх шахты читаются одинаково.
	_plate = Panel.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.size = PLATE
	_plate.pivot_offset = PLATE * 0.5
	_plate.add_theme_stylebox_override("panel", ProgressUiKit.popup_box(GOLD, Color(0.071, 0.055, 0.043, 0.94), 0))
	_root.add_child(_plate)
	_house = ShopArt.rect(ShopArt.tex("glyph_house"), Vector2((PLATE.x - HOUSE) * 0.5, 5.0), Vector2(HOUSE, HOUSE))
	_house.pivot_offset = Vector2(HOUSE * 0.5, HOUSE)
	_plate.add_child(_house)
	_label = ShopArt.label("", 13, GOLD)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(0, HOUSE + 4.0)
	_label.size = Vector2(PLATE.x, 16)
	_label.visible = false
	_plate.add_child(_label)


## Куда летят значки: середина домика на плашке.
func house_center() -> Vector2:
	return _plate_pos() + Vector2(PLATE.x * 0.5, 5.0 + HOUSE * 0.5)


func _plate_pos() -> Vector2:
	var vp := _root.get_viewport_rect().size if _root.is_inside_tree() else Vector2(224, 480)
	return Vector2((vp.x - PLATE.x) * 0.5, roundf(vp.y * PLATE_Y))


func run(from: Vector2, moved: Dictionary) -> void:
	count = 0
	for n in moved.values():
		count += int(n)
	var ids := moved.keys()
	ids.sort_custom(func(a, b): return int(moved[a]) > int(moved[b]))
	_icons = mini(ids.size(), MAX_ICONS)
	var hc := house_center()
	_plate.position = _plate_pos()
	_label.text = "×%d" % count
	Sfx.play("fly_start")
	if Settings.reduce_motion or not is_inside_tree():
		_label.visible = true
		_finish(0.9)
		return
	_plate.scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(_plate, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in _icons:
		_fly(UiIcons.item(String(ids[i])), from, hc, 0.2 + STAGGER * i)
	if _icons == 0:
		_on_land(0)


func _fly(icon: Texture2D, from: Vector2, to: Vector2, delay: float) -> void:
	var r := ShopArt.rect(icon, Vector2.ZERO, Vector2(ICON, ICON))
	r.visible = false
	_root.add_child(r)
	var start := from + Vector2(randf_range(-8.0, 8.0), randf_range(-6.0, 6.0))
	var ctrl := (start + to) * 0.5 + Vector2(randf_range(-50.0, 50.0), -randf_range(40.0, 90.0))
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void: r.visible = true)
	tw.tween_method(_fly_step.bind(r, start, ctrl, to), 0.0, 1.0, FLY) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_fly_land.bind(r))


func _fly_step(t: float, r: Control, a: Vector2, c: Vector2, b: Vector2) -> void:
	var u := 1.0 - t
	r.position = a * (u * u) + c * (2.0 * u * t) + b * (t * t) - r.size * 0.5
	r.scale = Vector2.ONE * (1.0 - 0.45 * t)
	r.modulate.a = 1.0 if t < 0.85 else (1.0 - t) / 0.15


func _fly_land(r: Control) -> void:
	r.queue_free()
	_on_land(_landed)


func _on_land(i: int) -> void:
	_landed += 1
	Sfx.play("pickup", 1.0 + 0.06 * float(i))
	if _house.is_inside_tree() and not Settings.reduce_motion:
		_house.scale = Vector2(1.18, 0.86)
		create_tween().tween_property(_house, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _landed < maxi(1, _icons):
		return
	_label.visible = true
	_label.pivot_offset = _label.size * 0.5
	_label.scale = Vector2.ONE * 1.4
	create_tween().tween_property(_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("door")
	Haptics.tap()
	_finish(HOLD)


func _finish(hold: float) -> void:
	if not is_inside_tree():
		queue_free()
		return
	var tw := create_tween()
	tw.tween_interval(hold)
	if not Settings.reduce_motion:
		tw.tween_property(_root, "position:y", -24.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_root, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)

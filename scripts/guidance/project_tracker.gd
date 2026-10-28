class_name ProjectTracker
extends Control
## Трекер отслеживаемого проекта на HUD: плашка 46×24 слева от кнопки «Магазин»
## под кошельком (там пусто: полоски слева, кнопки заданий и техники — левый
## столбик, метка глубины ездит ниже 116, джойстик внизу). Значок проекта и
## столбик тонких полосок — по одной на материал (и монеты): золото — копится,
## зелень — набрано. Всё есть — рамка зеленеет и плашка покачивается. Тап —
## экран «Проекты» на этом проекте; название и числа — в Tip.
##
## Место берётся от кнопки «Магазин» HUD (читаем её через get, hud.gd не правим);
## нет кнопки — запасная точка того же места.

signal tapped

const W := 46.0
const H := 26.0   # цель нажатия ≥ 25
const POLL := 0.4
const COL_BG := Color(0.07, 0.055, 0.045, 0.86)
const COL_EDGE := Color8(0x52, 0x40, 0x2D)
const COL_READY := Color8(0x7F, 0xD0, 0x6B)
const COL_FILL := Color8(0xE0, 0xA9, 0x3B)
const COL_TRACK := Color(0, 0, 0, 0.55)

var _id := ""
var _icon: Texture2D = null
var _fracs: Array = []      # [{frac, done}]
var _is_ready := false
var _key := ""
var _acc := POLL
var _pop := 0.0
var _t := 0.0
var _sb := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(W, H)
	custom_minimum_size = Vector2(W, H)
	pivot_offset = size * 0.5
	_sb.set_corner_radius_all(ProgressUiKit.R_TILE)
	_sb.set_border_width_all(1)
	visible = false
	HintPulse.attach(self, "project_tracker")
	sync()


func _gui_input(event: InputEvent) -> void:
	var up: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and not event.pressed) or (event is InputEventScreenTouch and not event.pressed)
	if up and not Tip.swallowed():
		accept_event()
		Sfx.play("ui_tap")
		Haptics.tap()
		ShopFx.pop(self, 0.15, 0.2)
		tapped.emit()
		ProjectsScreen.open_for(_id)


func _process(delta: float) -> void:
	_t += delta
	_pop = maxf(0.0, _pop - delta * 3.0)
	_acc += delta
	if _acc >= POLL:
		_acc = 0.0
		sync()
	if visible and (_is_ready or _pop > 0.0):
		queue_redraw()


func tracked_id() -> String:
	return _id


func is_ready_state() -> bool:
	return _is_ready


func bar_count() -> int:
	return _fracs.size()


## Перечитать состояние (тест зовёт сам). Изменился прогресс — плашка подпрыгивает.
func sync() -> void:
	var id := ProjectChain.tracked()
	var show := id != "" and ProjectChain.ids().has(id) and not ProjectChain.is_built(id) \
		and HintBusy.onboarding_done()
	if not show:
		visible = false
		_id = id
		_key = ""
		return
	var fr: Array = []
	for m: Dictionary in ProjectChain.materials(id):
		fr.append({"frac": clampf(float(m["effective"]) / maxf(1.0, float(m["need"])), 0.0, 1.0),
			"done": bool(m["done"])})
	var c := ProjectChain.coins_need(id)
	if c > 0:
		fr.append({"frac": clampf(float(GameState.coins) / float(c), 0.0, 1.0), "done": GameState.coins >= c})
	var now_ready := ProjectChain.ready(id)
	var key := "%s|%s|%s" % [id, str(fr), str(now_ready)]
	if key != _key:
		var was_ready := _is_ready
		var same := id == _id and _key != ""
		_key = key
		_id = id
		_icon = ProjectChain.icon(id)
		_fracs = fr
		_is_ready = now_ready
		if same:
			_pop = 1.0
			if now_ready and not was_ready:
				Sfx.play("quest_done")
				Haptics.thud()
				ShopFx.sparkles(self, size * 0.5, COL_READY, 12, 24.0)
		_bind_tip()
	visible = true
	_place()
	queue_redraw()


func _bind_tip() -> void:
	var lines: Array = []
	for m: Dictionary in ProjectChain.materials(_id):
		lines.append("%s: %d/%d" % [ShopCatalog.item_name(String(m["id"])), int(m["have"]), int(m["need"])])
	var c := ProjectChain.coins_need(_id)
	if c > 0:
		lines.append("Монеты: %s/%s" % [UiFmt.short(mini(GameState.coins, c)), UiFmt.short(c)])
	Tip.bind(self, ProjectChain.title(_id), "\n".join(lines),
		"Всё есть — собирай!" if _is_ready else "Тап — цепочка материалов")


func _place() -> void:
	var hud := get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	var btn = hud.get("_shop_btn") if hud != null else null
	if btn is Control and (btn as Control).is_visible_in_tree():
		var r := (btn as Control).get_global_rect()
		position = Vector2(round(r.position.x - 4.0 - W), round(r.get_center().y - H * 0.5))
	else:
		var vw := get_viewport_rect().size.x
		position = Vector2(vw - 8.0 - 30.0 - 4.0 - W, 89.0)


func _draw() -> void:
	var k := 1.0 + 0.12 * _pop
	if _is_ready and not UiAnim.reduced():
		k += 0.04 * sin(_t * 5.0)
	draw_set_transform(size * 0.5 * (1.0 - k), 0.0, Vector2(k, k))
	_sb.bg_color = COL_BG
	_sb.border_color = COL_READY if _is_ready else COL_EDGE
	_sb.set_border_width_all(2 if _is_ready else 1)
	draw_style_box(_sb, Rect2(Vector2.ZERO, size))
	if _icon != null:
		draw_texture_rect(_icon, Rect2(Vector2(3, 3), Vector2(18, 18)), false)
	var n := _fracs.size()
	if n > 0:
		var x := 24.0
		var bw := W - x - 4.0
		var gap := 1.0 if n > 4 else 2.0
		var bh := floorf((H - 6.0 - gap * float(n - 1)) / float(n))
		bh = clampf(bh, 2.0, 4.0)
		var total := bh * float(n) + gap * float(n - 1)
		var y := floorf((H - total) * 0.5)
		for f: Dictionary in _fracs:
			draw_rect(Rect2(Vector2(x, y), Vector2(bw, bh)), COL_TRACK)
			var fw := floorf(bw * float(f["frac"]))
			if fw > 0.0:
				draw_rect(Rect2(Vector2(x, y), Vector2(fw, bh)), COL_READY if bool(f["done"]) else COL_FILL)
			y += bh + gap
	if _is_ready:
		var ok := ShopArt.tex("glyph_check")
		if ok != null:
			draw_texture_rect(ok, Rect2(Vector2(W - 13, -5), Vector2(14, 14)), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

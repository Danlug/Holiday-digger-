class_name DialogueUI
extends Control
## Плашка реплики в стиле современных мобильных игр: скруглённая рамка с тенью,
## портреты говорящих над плашкой (слева/справа, говорящий подсвечен), имя на
## ленточке, печать текста по буквам с блипом голоса, мигающий треугольник «дальше».
##
## Это только слой представления: какой кадр показать и когда перейти дальше
## решает CutscenePlayer. Тап «дописать → дальше» остаётся его делом, сюда он
## зовёт finish_typing(). «Меньше движения» (Settings.reduce_motion) отключает
## печать, моргание, покачивание и въезд: весь текст сразу, кадры статичны.

const MARGIN_X := 6.0
const PAD_X := 12.0
const PAD_TOP_SPEAKER := 14.0
const PAD_TOP_NARR := 12.0
const PAD_BOTTOM := 14.0
const MIN_H := 62.0
const MAX_H := 190.0
const TEXT_SIZE := UiTheme.FS_LABEL
const RIBBON_H := 16.0
const PORTRAIT_OVERLAP := 6.0     # на сколько портрет заходит на плашку
const PORTRAIT_INSET := 4.0
const HEIGHT_EASE := 22.0         # скорость подгонки высоты плашки под текст

var box: Panel
var line: Label
var arrow: Control
var ribbon: PanelContainer
var name_label: Label

var typing: bool = false
var narration: bool = false
var bottom_inset: float = 30.0

var _slots: Dictionary = {"left": null, "right": null}
var _active_side: String = ""
var _who: String = ""
var _vp: Vector2 = Vector2(224, 480)
var _cur_h: float = MIN_H
var _target_h: float = MIN_H
var _text_h: float = 14.0
var _shown_chars: int = 0
var _pos_f: float = 0.0
var _pause: float = 0.0
var _letters: int = 0
var _cps: float = 42.0
var _waiting: bool = false
var _t: float = 0.0
var _enter: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func _build() -> void:
	box = Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", DialogueStyle.panel_box())
	box.draw.connect(_draw_box_ornament)
	add_child(box)

	line = Label.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.autowrap_mode = TextServer.AUTOWRAP_WORD
	line.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	line.add_theme_constant_override("line_spacing", 1)
	DialogueStyle.shadowed(line, TEXT_SIZE, DialogueStyle.TEXT)
	box.add_child(line)

	arrow = Control.new()
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.size = Vector2(9, 7)
	arrow.visible = false
	arrow.draw.connect(_draw_arrow)
	box.add_child(arrow)

	ribbon = PanelContainer.new()
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.add_theme_stylebox_override("panel", DialogueStyle.ribbon_box(DialogueCast.DEFAULT_ACCENT))
	ribbon.visible = false
	add_child(ribbon)
	name_label = Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	DialogueStyle.shadowed(name_label, UiTheme.FS_BODY, Color8(0xFF, 0xEB, 0xB8))
	ribbon.add_child(name_label)

	for side in ["left", "right"]:
		var p := DialoguePortrait.new()
		p.visible = false
		add_child(p)
		_slots[side] = p


# ---------------------------------------------------------------------------
# Публичное API
# ---------------------------------------------------------------------------

## Показать реплику. who — id говорящего («boy», «grandma_rich»…), пустой — закадровый
## текст. opts: stage — id актёров на сцене (чтобы выбрать портрет экипированного
## двойника), key — ключ текста (замена выражения из data/dialogue.json), face —
## выражение явно.
func show_line(who: String, speaker_name: String, text: String, opts: Dictionary = {}) -> void:
	var was_hidden := not visible
	visible = true
	narration = speaker_name.is_empty() and who.is_empty()
	_who = who
	line.text = text
	line.modulate.a = 1.0
	_apply_text_style()
	_set_speaker(who, speaker_name, text, opts)
	_measure()
	if was_hidden:
		_cur_h = _target_h
		_play_enter()
	_begin_typing(text, who)
	_apply_geometry()
	box.queue_redraw()


## Скрыть плашку и портреты; следующая реплика появится «с нуля».
func hide_all() -> void:
	visible = false
	typing = false
	_waiting = false
	_who = ""
	_active_side = ""
	arrow.visible = false
	ribbon.visible = false
	for side in _slots.keys():
		var p: DialoguePortrait = _slots[side]
		p.visible = false
		p.who = ""
		p.talking = false
		p.modulate.a = 1.0
	if _enter != null and _enter.is_valid():
		_enter.kill()
	position = Vector2.ZERO
	modulate.a = 1.0


## Дописать реплику целиком (тап во время печати).
func finish_typing() -> void:
	typing = false
	_pause = 0.0
	_shown_chars = line.text.length()
	line.visible_ratio = 1.0
	_set_talking(false)


func set_waiting(w: bool) -> void:
	_waiting = w


## Размер вьюпорта поменялся или сменился нижний отступ (под кинополосу).
func relayout(vp: Vector2, inset: float) -> void:
	_vp = vp
	bottom_inset = inset
	size = vp
	if visible:
		_measure()
		_cur_h = _target_h
		_apply_geometry()


func box_rect() -> Rect2:
	return Rect2(box.position, box.size)


func portrait(side: String) -> DialoguePortrait:
	return _slots.get(side)


func active_side() -> String:
	return _active_side


func slot_who(side: String) -> String:
	var p: DialoguePortrait = _slots.get(side)
	return "" if p == null or not p.visible else p.who


func _process(dt: float) -> void:
	tick(dt)


## Шаг анимации: подгонка высоты, печать, портреты, «дальше». Зовётся из _process;
## тест может звать сам, подставляя своё dt.
func tick(dt: float) -> void:
	if not visible:
		return
	_t += dt
	if absf(_cur_h - _target_h) > 0.5 and not DialogueStyle.reduced():
		_cur_h = lerpf(_cur_h, _target_h, minf(1.0, dt * HEIGHT_EASE))
		_apply_geometry()
	elif _cur_h != _target_h:
		_cur_h = _target_h
		_apply_geometry()
	if typing:
		_tick_typing(dt)
	for side in _slots.keys():
		var p: DialoguePortrait = _slots[side]
		if not p.visible:
			continue
		p.tick(dt)
		var bob := 0.0
		if p.active and p.talking and p.current_frame() == 1 and not DialogueStyle.reduced():
			bob = -1.0
		p.position = p.position.lerp(p.target_pos + Vector2(0, bob) + p.react_off, minf(1.0, dt * 30.0)) \
			if not DialogueStyle.reduced() else p.target_pos
	arrow.visible = _waiting and not typing
	if arrow.visible:
		arrow.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * 6.0))
		arrow.position = Vector2(box.size.x - 22.0, box.size.y - 15.0 + (0.0 if DialogueStyle.reduced() else sin(_t * 6.0) * 1.2))


# ---------------------------------------------------------------------------
# Говорящий: портреты и ленточка
# ---------------------------------------------------------------------------

func _set_speaker(who: String, speaker_name: String, text: String, opts: Dictionary) -> void:
	if who.is_empty() or not DialogueCast.has_speaker(who):
		# Закадровый текст — голос автора: портретов нет, ленточка только у подписанного.
		for side in _slots.keys():
			var p: DialoguePortrait = _slots[side]
			p.vanish()
		_active_side = ""
		ribbon.visible = not speaker_name.is_empty()
		if ribbon.visible:
			_fill_ribbon(speaker_name, DialogueCast.DEFAULT_ACCENT)
		return
	var stage: Array = opts.get("stage", [])
	var portrait_id := DialogueCast.portrait_id(who, stage)
	var side := _pick_side(who, portrait_id)
	var face := String(opts.get("face", ""))
	if face.is_empty():
		face = DialogueCast.guess_face(who, text, String(opts.get("key", "")))
	var target: DialoguePortrait = _slots[side]
	var fresh := not target.visible or target.who.is_empty() or target.portrait_id != portrait_id or target.who != who
	if fresh:
		target.assign(who, portrait_id)
		target.set_face(face, false)
	for s in _slots.keys():
		var p: DialoguePortrait = _slots[s]
		if p.visible and not p.who.is_empty():
			p.set_active(s == side, true)
	_active_side = side
	var changed := target.face != face
	target.set_face(face, false)
	if fresh or changed:
		target.react(face)
	_place_portraits()
	if fresh:
		target.appear(Vector2(-14.0 if side == "left" else 14.0, 10.0))
	_fill_ribbon(speaker_name, DialogueCast.accent(who))


## Сторона по данным; если занята другим — вторая сторона, если и она занята —
## вытесняем того, кто молчал последним.
func _pick_side(who: String, portrait_id: String) -> String:
	var pref := DialogueCast.side(who)
	var other := "left" if pref == "right" else "right"
	var a: DialoguePortrait = _slots[pref]
	var b: DialoguePortrait = _slots[other]
	if a.who.is_empty() or a.who == who or a.portrait_id == portrait_id:
		return pref
	if b.who.is_empty() or b.who == who or b.portrait_id == portrait_id:
		return other
	return other if _active_side == pref else pref


func _fill_ribbon(speaker_name: String, accent: Color) -> void:
	ribbon.add_theme_stylebox_override("panel", DialogueStyle.ribbon_box(accent))
	name_label.text = speaker_name
	ribbon.reset_size()
	ribbon.visible = true
	_place_ribbon()
	if not DialogueStyle.reduced() and is_inside_tree():
		ribbon.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(ribbon, "modulate:a", 1.0, 0.14)
	else:
		ribbon.modulate.a = 1.0


func _set_talking(v: bool) -> void:
	for side in _slots.keys():
		var p: DialoguePortrait = _slots[side]
		p.talking = v and side == _active_side


# ---------------------------------------------------------------------------
# Печать
# ---------------------------------------------------------------------------

func _begin_typing(text: String, who: String) -> void:
	_shown_chars = 0
	_pos_f = 0.0
	_pause = 0.0
	_letters = 0
	var n := text.length()
	var cps := DialogueCast.typing_param("cps", 42.0)
	var cps_long := DialogueCast.typing_param("cps_long", 70.0)
	_cps = clampf(cps + (float(n) - 60.0) * 0.3, cps, maxf(cps, cps_long))
	typing = n > 0 and not DialogueStyle.reduced()
	if typing:
		line.visible_characters = 0
	else:
		line.visible_ratio = 1.0
	_set_talking(typing and not who.is_empty())


func _tick_typing(dt: float) -> void:
	if line.visible_ratio >= 1.0:
		# Кто-то дописал строку снаружи (тест, скриншот): печать окончена.
		finish_typing()
		return
	var text := line.text
	var count := text.length()
	if _pause > 0.0:
		_pause -= dt
		_set_talking(false)
		return
	_set_talking(not _who.is_empty())
	_pos_f += _cps * dt
	var want := mini(count, int(_pos_f))
	while _shown_chars < want:
		var ch := text[_shown_chars]
		_shown_chars += 1
		_on_char(ch, text)
		if _pause > 0.0:
			_pos_f = float(_shown_chars)
			break
	line.visible_characters = _shown_chars
	if _shown_chars >= count:
		finish_typing()


func _on_char(ch: String, text: String) -> void:
	var is_letter := ch.to_upper() != ch.to_lower() or ch.is_valid_int()
	if is_letter and not _who.is_empty():
		_letters += 1
		var every := maxi(1, int(DialogueCast.typing_param("blip_every", 3.0)))
		if _letters % every == 0:
			var wobble: float = [1.0, 1.07, 0.95, 1.04][(_letters / every) % 4]
			Sfx.play("ui_tap", DialogueCast.pitch(_who) * wobble, DialogueCast.blip_db(_who))
		return
	var next := text[_shown_chars] if _shown_chars < text.length() else ""
	if ch == "," or ch == ";" or ch == ":":
		_pause = DialogueCast.typing_param("pause_comma", 0.09)
	elif ch == "." or ch == "…":
		var in_ellipsis := next == "." or ch == "…" or (_shown_chars >= 2 and text[_shown_chars - 2] == ".")
		_pause = DialogueCast.typing_param("pause_ellipsis", 0.07) if in_ellipsis \
				else DialogueCast.typing_param("pause_stop", 0.2)
	elif ch == "!" or ch == "?":
		_pause = DialogueCast.typing_param("pause_stop", 0.2) if next != "!" and next != "?" else 0.0


# ---------------------------------------------------------------------------
# Раскладка
# ---------------------------------------------------------------------------

func _apply_text_style() -> void:
	if narration:
		line.add_theme_color_override("font_color", DialogueStyle.TEXT_NARR)
	else:
		line.add_theme_color_override("font_color", DialogueCast.text_color(_who))


func _measure() -> void:
	var text_w := maxf(40.0, _vp.x - 2.0 * MARGIN_X - 2.0 * PAD_X)
	line.size = Vector2(text_w, 200.0)
	var lines := maxi(1, line.get_line_count())
	var lh := float(line.get_line_height()) + float(line.get_theme_constant("line_spacing"))
	_text_h = float(lines) * lh
	var top := PAD_TOP_NARR if narration else PAD_TOP_SPEAKER
	_target_h = clampf(_text_h + top + PAD_BOTTOM, MIN_H, maxf(MAX_H, _vp.y * 0.55))


func _apply_geometry() -> void:
	var box_w := _vp.x - 2.0 * MARGIN_X
	box.size = Vector2(box_w, _cur_h)
	box.position = Vector2(MARGIN_X, _vp.y - bottom_inset - _cur_h)
	var top := PAD_TOP_NARR if narration else PAD_TOP_SPEAKER
	line.position = Vector2(PAD_X, top)
	line.size = Vector2(box_w - 2.0 * PAD_X, _text_h + 4.0)
	_place_portraits()
	_place_ribbon()


func _place_portraits() -> void:
	var top_y := box.position.y - DialoguePortrait.SIZE_PX + PORTRAIT_OVERLAP
	for side in _slots.keys():
		var p: DialoguePortrait = _slots[side]
		var x := MARGIN_X + PORTRAIT_INSET if side == "left" \
				else _vp.x - MARGIN_X - PORTRAIT_INSET - DialoguePortrait.SIZE_PX
		p.target_pos = Vector2(x, top_y + (0.0 if p.active else 2.0))
		if not p.visible or DialogueStyle.reduced():
			p.position = p.target_pos


func _place_ribbon() -> void:
	if not ribbon.visible:
		return
	var y := box.position.y - RIBBON_H * 0.5 - 1.0
	var p: DialoguePortrait = _slots.get(_active_side)
	if _active_side.is_empty() or p == null:
		ribbon.position = Vector2(MARGIN_X + 10.0, y)
		return
	if _active_side == "left":
		ribbon.position = Vector2(p.target_pos.x + DialoguePortrait.SIZE_PX + 4.0, y)
	else:
		ribbon.position = Vector2(p.target_pos.x - 4.0 - ribbon.size.x, y)


func _play_enter() -> void:
	if _enter != null and _enter.is_valid():
		_enter.kill()
	position = Vector2.ZERO
	modulate.a = 1.0
	if DialogueStyle.reduced() or not is_inside_tree():
		return
	position = Vector2(0, 8)
	modulate.a = 0.0
	_enter = create_tween().set_parallel(true)
	_enter.tween_property(self, "position", Vector2.ZERO, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_enter.tween_property(self, "modulate:a", 1.0, 0.14)


# ---------------------------------------------------------------------------
# Рисование
# ---------------------------------------------------------------------------

func _draw_box_ornament() -> void:
	if not narration:
		return
	# Закадровый текст: ромбик с линиями на верхней кромке — «автор», а не персонаж.
	var cx := box.size.x * 0.5
	var c := DialogueStyle.GOLD
	var d := PackedVector2Array([Vector2(cx, -3), Vector2(cx + 4, 1), Vector2(cx, 5), Vector2(cx - 4, 1)])
	box.draw_colored_polygon(d, DialogueStyle.PANEL_BG)
	box.draw_polyline(PackedVector2Array([d[0], d[1], d[2], d[3], d[0]]), c, 1.0)


func _draw_arrow() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(9, 0), Vector2(4.5, 6)])
	arrow.draw_colored_polygon(pts, DialogueStyle.GOLD)
	arrow.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.5), 1.0)

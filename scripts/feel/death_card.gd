class_name DeathCard
extends CanvasLayer
## Карточка после смерти: что потеряно и что уцелело. Только значки и числа —
## названия и пояснения лежат в `Tip` (долгое нажатие или наведение). Раньше
## игрок получал тост «Ты погиб. Минералы потеряны…» на три секунды и не мог
## ни пересчитать потерю, ни понять, что осталось при нём.
##
## Правила смерти ГДД §7: теряется весь рюкзак и плата «скорой» — 5% монет,
## от 50 до 5000 (раунд 5, не в минус, scripts/house/healing.gd); уровень,
## прокачка, карта, артефакты и рекорды целы. С раунда 5 скорая ещё и везёт
## героя наверх (DeathRide): карточка открывается сразу, ведёт отсчёт поездки
## (полоска с фургоном) и до приезда не закрывается. Карточка эти правила только
## показывает.

signal closed

const MAX_TILES := 8
const PER_ROW := 4

var _root: Control = null
var _card: PanelContainer = null
var _report: Dictionary = {}
var _auto_close: Tween = null
var _riding := false
var _track: Control = null
var _ride_label: Label = null
var _ok: Button = null


## Отчёт о смерти — чистые данные, их проверяет тест, а не картинка.
## lost: словарь «предмет → штук», потерянный из рюкзака; fee — сколько монет
## забрала скорая (событие ambulance перед died); ride_s — сколько везёт скорая
## (событие ambulance_ride, 0 — без поездки).
static func build_report(lost: Dictionary, death_depth: int, cause: String, fee: int = 0, ride_s: float = 0.0) -> Dictionary:
	var rows: Array = []
	var total := 0
	for id in lost.keys():
		var n := int(lost[id])
		if n <= 0:
			continue
		var price := Balance.get_mineral_price(String(id))
		rows.append({"id": String(id), "count": n, "value": price * n, "price": price})
		total += price * n
	rows.sort_custom(func(a, b): return a["value"] > b["value"] or (a["value"] == b["value"] and String(a["id"]) < String(b["id"])))
	return {
		"lost": rows,
		"lost_value": total,
		"coins": GameState.coins,
		"level": GameState.level,
		"depth": death_depth,
		"max_depth": GameState.max_depth_reached,
		"cause": cause,
		"fee": maxi(fee, 0),
		"ride_s": maxf(ride_s, 0.0),
	}


## Нужна ли карточка вообще: только после онбординга (сцена смерти из §9 играет
## своя) и только если было что показать — потерю, плату скорой или глубину.
static func worth_showing(report: Dictionary) -> bool:
	if not StoryState.has_flag("gold_sold"):
		return false
	return not (report["lost"] as Array).is_empty() or int(report["depth"]) > 0 \
			or int(report.get("fee", 0)) > 0 or float(report.get("ride_s", 0.0)) > 0.0


func _ready() -> void:
	layer = 93   # выше HUD и шторок, ниже окна дня (94) и катсцен (100)
	visible = false
	set_process(false)
	add_to_group("hint_block")


func is_open() -> bool:
	return visible


func report() -> Dictionary:
	return _report


## Едет ли ещё скорая (карточка тогда не закрывается).
func is_riding() -> bool:
	return _riding


func open(report_data: Dictionary) -> void:
	_report = report_data
	_riding = float(_report.get("ride_s", 0.0)) > 0.0 and DeathRide.riding()
	_build()
	visible = true
	set_process(_riding)
	Sfx.play("ui_open", 0.9)
	if _card != null:
		UiAnim.appear(_card, 0.88, 0.24)
	_update_ride()
	if not _riding:
		_start_auto_close()
	else:
		# музыка после смерти молчит до респавна (JuiceDirector): поездка в минуту-две
		# в тишине выглядела бы зависанием — тихая тема огорода, когда отзвучит «die»
		var t := get_tree().create_timer(2.6)
		t.timeout.connect(func() -> void:
			if _riding and visible and Sfx.current_music() == "":
				Sfx.music("mus_surface"))


func _start_auto_close() -> void:
	if UiAnim.reduced():
		return
	if _auto_close != null and _auto_close.is_valid():
		_auto_close.kill()
	_auto_close = create_tween()
	_auto_close.tween_interval(Feel.num("death.auto_hide_s", 7.0))
	_auto_close.tween_callback(close)


## Скорая приехала (респавн): кнопка оживает, дальше — как обычная карточка.
func ride_arrived() -> void:
	if not _riding:
		return
	_riding = false
	set_process(false)
	_update_ride()
	if _ok != null:
		_ok.disabled = false
		_ok.modulate = Color.WHITE
		UiAnim.pulse(_ok)
	_start_auto_close()


func _process(_delta: float) -> void:
	if not visible or not _riding:
		return
	_update_ride()
	# респавн мимо FeelDirector (тест, отладка) — тоже приезд
	if not DeathRide.riding():
		ride_arrived()


func _update_ride() -> void:
	if _track != null:
		_track.queue_redraw()
	if _ride_label != null:
		_ride_label.text = fmt_seconds(DeathRide.seconds_left()) if _riding else fmt_seconds(float(_report.get("ride_s", 0.0)))


static func _pct_text() -> String:
	var p := Healing.death_fee_percent()
	return str(int(p)) if is_equal_approx(p, roundf(p)) else str(snappedf(p, 0.1))


## «1:05», «0:42»: число без букв, как на таймерах мобильных игр.
static func fmt_seconds(sec: float) -> String:
	var s := int(ceil(maxf(sec, 0.0)))
	return "%d:%02d" % [s / 60, s % 60]


func close() -> void:
	if not visible or _riding:
		return
	visible = false
	if _auto_close != null and _auto_close.is_valid():
		_auto_close.kill()
	if _root != null:
		_root.queue_free()
		_root = null
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Пока карточка открыта, нажатия не должны вести героя под ней: HUD читает
## указатель в `_input`, а мы стоим в дереве позже и получаем событие раньше.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()


func _build() -> void:
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "DeathRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.0, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			close())
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_card = PanelContainer.new()
	var sb := MetaUiKit.box(MetaUiKit.CARD, MetaUiKit.RED, 2, 6)
	sb.set_content_margin_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 4
	_card.add_theme_stylebox_override("panel", sb)
	_card.custom_minimum_size = Vector2(204, 0)
	center.add_child(_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	_card.add_child(box)
	box.add_child(_build_header())
	box.add_child(_build_ride())
	box.add_child(_build_lost())
	box.add_child(_build_kept())
	box.add_child(_build_button())


func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var skull := MetaUiKit.icon_rect(MetaUiKit.tex("skull"), 28)
	h.add_child(skull)
	Tip.bind(skull, "Смерть", ("Рюкзак потерян, скорая берёт %s%% монет (от %d до %d) и везёт наверх дольше, чем летел бы сам. "
			% [_pct_text(), Healing.death_fee_min(), Healing.death_fee_max()]) + "Уровень и прокачка остались.")
	var depth := MetaUiKit.chip(UiIcons.tex("depth"), str(int(_report["depth"])), MetaUiKit.BLUE, 14, 12)
	Tip.bind(depth, "Глубина смерти", "На какой глубине ты погиб.", str(int(_report["depth"])))
	h.add_child(depth)
	var cause := String(_report.get("cause", ""))
	if cause != "":
		var ic := _cause_icon(cause)
		if ic != null:
			var c := MetaUiKit.icon_rect(ic, 16)
			c.flip_v = cause == "fall"   # стрелка вверх, перевёрнутая: «упал»
			c.mouse_filter = Control.MOUSE_FILTER_PASS
			Tip.bind(c, _cause_title(cause), _cause_hint(cause))
			h.add_child(c)
	return h


static func _cause_icon(cause: String) -> Texture2D:
	match cause:
		"hunger":
			return UiIcons.tex("eat")
		"fall":
			return UiIcons.tex("arrow_up")
		"lava":
			return MetaUiKit.tex("flame")
	return null


static func _cause_title(cause: String) -> String:
	match cause:
		"hunger":
			return "Голод"
		"fall":
			return "Падение"
		"lava":
			return "Лава"
	return "Причина"


static func _cause_hint(cause: String) -> String:
	match cause:
		"hunger":
			return "Сытость кончилась. Заказывай еду заранее и бери порцию с собой."
		"fall":
			return "Удар о землю на большой скорости. Гаси падение ранцем или ступай на уступы."
		"lava":
			return "Лава жжёт, пока копаешь. Нужен костюм или запас HP."
	return ""


func _build_lost() -> Control:
	var lost: Array = _report["lost"]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	var bag := MetaUiKit.icon_rect(UiIcons.tex("backpack"), 16)
	bag.mouse_filter = Control.MOUSE_FILTER_PASS
	Tip.bind(bag, "Потеряно", "Всё, что лежало в рюкзаке. По прайсу мастерской это стоило столько.")
	head.add_child(bag)
	var value_chip := MetaUiKit.chip(MetaUiKit.tex("coin"), "−" + MetaUiKit.compact(int(_report["lost_value"])),
			MetaUiKit.RED.lightened(0.45), 13, 11)
	head.add_child(value_chip)
	head.add_child(_build_fee())
	v.add_child(head)
	if lost.is_empty():
		var ok := MetaUiKit.icon_rect(MetaUiKit.tex("check"), 20)
		ok.mouse_filter = Control.MOUSE_FILTER_PASS
		Tip.bind(ok, "Рюкзак был пуст", "Терять было нечего.")
		v.add_child(ok)
		return v
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	v.add_child(rows)
	var shown := mini(lost.size(), MAX_TILES)
	var row: HBoxContainer = null
	for i in shown:
		if i % PER_ROW == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 3)
			rows.add_child(row)
		var e: Dictionary = lost[i]
		row.add_child(_item_tile(String(e["id"]), int(e["count"]), int(e["price"]), true))
	if lost.size() > shown:
		var more := PanelContainer.new()
		more.custom_minimum_size = Vector2(40, 40)
		more.add_theme_stylebox_override("panel", MetaUiKit.box(MetaUiKit.SLOT, MetaUiKit.BORDER, 1, 3))
		more.add_child(_centered(MetaUiKit.label("+%d" % (lost.size() - shown), 11, MetaUiKit.MUTED)))
		Tip.bind(more, "Ещё потеряно", "Остальные стопки не поместились в строку.", "+%d" % (lost.size() - shown))
		row.add_child(more)
	return v


## «Скорая забрала»: значок фургона и −200 монет (раунд 4, healing). Пусто,
## если монет не было вовсе — минуса не бывает.
func _build_fee() -> Control:
	var fee := int(_report.get("fee", 0))
	var h := HBoxContainer.new()
	h.name = "Fee"
	h.add_theme_constant_override("separation", 3)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL | Control.SIZE_SHRINK_END
	h.alignment = BoxContainer.ALIGNMENT_END
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	h.visible = fee > 0
	if fee <= 0:
		return h
	h.add_child(MetaUiKit.icon_rect(ShopArt.tex("glyph_ambulance"), 18))
	h.add_child(MetaUiKit.chip(MetaUiKit.tex("coin"), "−" + MetaUiKit.compact(fee), MetaUiKit.RED.lightened(0.45), 13, 11))
	var lo := Healing.death_fee_min()
	Tip.bind(h, "Скорая забрала", ("За вызов — %s%% монет при себе, не меньше %d и не больше %d." % [
			_pct_text(), lo, Healing.death_fee_max()]) if fee >= lo \
			else "Вызов стоит не меньше %d — забрали сколько было." % lo, "−%d" % fee)
	return h


## «Скорая везёт»: полоска пути от глубины смерти к поверхности, фургон едет по
## ней, справа — сколько осталось. Пусто, если поездки не было.
func _build_ride() -> Control:
	var ride_s := float(_report.get("ride_s", 0.0))
	var h := HBoxContainer.new()
	h.name = "Ride"
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	h.visible = ride_s > 0.0
	_track = null
	_ride_label = null
	if ride_s <= 0.0:
		return h
	_track = Control.new()
	_track.name = "Track"
	_track.custom_minimum_size = Vector2(0, 24)
	_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.draw.connect(_draw_track)
	h.add_child(_track)
	var clock := MetaUiKit.icon_rect(MetaUiKit.tex("clock"), 14)
	h.add_child(clock)
	_ride_label = MetaUiKit.label(fmt_seconds(ride_s), 12, Color.WHITE)
	_ride_label.name = "RideLeft"
	_ride_label.custom_minimum_size = Vector2(30, 0)
	_ride_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(_ride_label)
	var depth := int(_report.get("depth", 0))
	Tip.bind(h, "Скорая везёт наверх", ("Поднимает по стволу с глубины %d — дольше, чем летел бы ты сам: " % depth)
			+ "умереть, чтобы не лететь, не выйдет. Приедешь домой с половиной здоровья, голод и усталость — как были.",
			fmt_seconds(ride_s))
	return h


func _draw_track() -> void:
	if _track == null:
		return
	var w := _track.size.x
	var hgt := _track.size.y
	var end_w := 12.0
	var bar := Rect2(2.0, hgt - 8.0, maxf(8.0, w - end_w - 4.0), 5.0)
	_track.draw_rect(bar.grow(1.0), MetaUiKit.BORDER)
	_track.draw_rect(bar, MetaUiKit.SLOT)
	var p := DeathRide.progress() if _riding else 1.0
	if p > 0.0:
		_track.draw_rect(Rect2(bar.position, Vector2(bar.size.x * p, bar.size.y)), MetaUiKit.RED.lightened(0.25))
	# метки «ствола» каждые 25% пути — видно, что это дорога снизу вверх
	for i in range(1, 4):
		var x := bar.position.x + bar.size.x * float(i) / 4.0
		_track.draw_rect(Rect2(x, bar.position.y + 1.0, 1.0, bar.size.y - 2.0), Color(1, 1, 1, 0.25))
	var up := UiIcons.tex("arrow_up")
	if up != null:
		_track.draw_texture_rect(up, Rect2(w - end_w, hgt - 13.0, end_w, end_w), false, MetaUiKit.GREEN.lightened(0.3))
	var van := ShopArt.tex("glyph_ambulance")
	if van != null:
		var vw := 18.0
		var vx := bar.position.x + (bar.size.x - vw) * p
		_track.draw_texture_rect(van, Rect2(roundf(vx), 0.0, vw, vw), false)


func _build_kept() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	var coins := MetaUiKit.chip(MetaUiKit.tex("coin"), MetaUiKit.compact(int(_report["coins"])), MetaUiKit.GOLD_LIGHT, 13, 11)
	Tip.bind(coins, "Монеты при тебе", "Всё, что не забрала скорая, осталось.", MetaUiKit.compact(int(_report["coins"])))
	head.add_child(coins)
	var lvl := MetaUiKit.chip(MetaUiKit.tex("star"), str(int(_report["level"])), MetaUiKit.BLUE, 13, 11)
	Tip.bind(lvl, "Уровень и прокачка сохранены", "Опыт, очки навыков и разведанная карта при смерти не теряются.", str(int(_report["level"])))
	head.add_child(lvl)
	var rec := MetaUiKit.chip(UiIcons.tex("depth"), str(int(_report["max_depth"])), MetaUiKit.MUTED, 13, 11)
	Tip.bind(rec, "Рекорд глубины", "Лучшая глубина за всю игру.", str(int(_report["max_depth"])))
	head.add_child(rec)
	v.add_child(head)
	return v


func _build_button() -> Control:
	var b := Button.new()
	b.icon = MetaUiKit.tex("check")
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.custom_minimum_size = Vector2(0, 30)
	UiBtn.style(b, UiBtn.Kind.ACCENT)
	b.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		close())
	Tip.bind(b, "Понятно", "Закрыть. Ты дома, всё остальное при тебе. Пока едет скорая — подожди.")
	_ok = b
	if _riding:
		b.disabled = true
		b.modulate = Color(1, 1, 1, 0.45)
	return b


func _item_tile(id: String, count: int, price: int, lost: bool) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(40, 40)
	var border := MetaUiKit.RED.darkened(0.15) if lost else MetaUiKit.GREEN.darkened(0.2)
	tile.add_theme_stylebox_override("panel", MetaUiKit.box(MetaUiKit.SLOT, border, 1, 3))
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(holder)
	var ic := MetaUiKit.icon_rect(UiIcons.item(id), 24)
	ic.position = Vector2(6, 3)
	ic.size = Vector2(24, 24)
	if lost:
		ic.modulate = Color(1, 1, 1, 0.78)
	holder.add_child(ic)
	var n := MetaUiKit.label("×%d" % count, 10, Color.WHITE)
	n.position = Vector2(3, 24)
	n.size = Vector2(32, 12)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(n)
	var nm := String(Balance.get_mineral(id).get("name_ru", id))
	Tip.bind(tile, nm, "×%d" % count, MetaUiKit.compact(price * count))
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	return tile


static func _centered(c: Control) -> Control:
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(c)
	return cc

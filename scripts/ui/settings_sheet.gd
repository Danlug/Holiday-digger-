class_name SettingsSheet
extends Control
## SettingsSheet — шторка настроек (Settings: scripts/core/settings.gd), только
## иконки: ползунки громкости звука и музыки с кнопкой-«мьют» (динамик/нота),
## переключатели «вибрация», «радиус обзора», «меньше движения», три режима
## управления (джойстик/нажатия/стрелки), язык и восстановление покупок. Слова —
## в подсказках Tip; исключение — названия языков на самих кнопках.
##
## Шторка ничего не знает про HUD: выбор режима и «восстановить покупки» —
## сигналы, остальное пишет прямо в Settings.

signal closed
signal mode_chosen(mode: String)
signal restore_pressed

const CARD_BG := Color8(0x1A, 0x14, 0x0F)
const ROW_BG := Color8(0x23, 0x1B, 0x14)
const EDGE := Color8(0x52, 0x40, 0x2D)
const GOLD := Color8(0xE0, 0xA9, 0x3B)
const MUTED := Color8(0x9D, 0x8B, 0x73)

const MODES: Array[String] = ["stick", "hold", "arrows"]
const MODE_ICONS := {"stick": "joystick", "hold": "ctl_hold", "arrows": "ctl_arrows"}
const MODE_TIPS := {
	"stick": ["Джойстик", "Ручка справа внизу"],
	"hold": ["Нажатия", "Зажми экран — герой идёт туда"],
	"arrows": ["Стрелки", "Четыре кнопки по краям"],
}

var _card: PanelContainer
var _sound_btn: Button
var _sound_slider: HSlider
var _music_btn: Button
var _music_slider: HSlider
var _haptics_btn: Button
var _vision_btn: Button
var _motion_btn: Button
var _mode_btns: Dictionary = {}
var _lang_btns: Dictionary = {}
var _last_tick_ms: int = 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func is_open() -> bool:
	return visible


func open() -> void:
	refresh()
	visible = true
	Sfx.play("ui_open")
	if _card != null and is_inside_tree():
		UiAnim.slide_up(_card, 28.0, 0.2)


func close() -> void:
	var was := visible
	visible = false
	if was:
		Sfx.play("ui_close")
	closed.emit()


## Перечитывает Settings и красит все контролы — вызывается при открытии и
## после любого изменения, чтобы кнопки сразу отражали новое состояние.
func refresh() -> void:
	if _sound_slider == null:
		return
	_sound_slider.set_value_no_signal(Settings.sound_volume * 100.0)
	_music_slider.set_value_no_signal(Settings.music_volume * 100.0)
	_sound_btn.icon = UiIcons.tex("sound_off" if Settings.sound_muted else "sound_on")
	_music_btn.icon = UiIcons.tex("music_off" if Settings.music_muted else "music_on")
	_sound_slider.modulate.a = 0.45 if Settings.sound_muted else 1.0
	_music_slider.modulate.a = 0.45 if Settings.music_muted else 1.0
	Tip.bind(_sound_btn, "Звук", "Выключен — нажми, чтобы включить" if Settings.sound_muted else "Нажми, чтобы выключить")
	Tip.bind(_music_btn, "Музыка", "Выключена — нажми, чтобы включить" if Settings.music_muted else "Нажми, чтобы выключить")

	_set_toggle(_haptics_btn, Settings.haptics_enabled, "Вибрация")
	_set_toggle(_vision_btn, Settings.show_vision_radius, "Радиус обзора")
	_vision_btn.icon = UiIcons.tex("eye" if Settings.show_vision_radius else "eye_off")
	_set_toggle(_motion_btn, not Settings.reduce_motion, "Движение интерфейса")
	_motion_btn.icon = UiIcons.tex("motion" if not Settings.reduce_motion else "motion_off")
	Tip.bind(_motion_btn, "Движение интерфейса", "Включено" if not Settings.reduce_motion else "Меньше движения: выключено")

	for m in _mode_btns.keys():
		_mark(_mode_btns[m], m == Settings.control_mode)
	for code in _lang_btns.keys():
		var b: Button = _lang_btns[code]
		if not b.disabled:
			_mark(b, code == Settings.language)


# ---------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_card = PanelContainer.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.offset_top = 22.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = EDGE
	sb.border_width_top = 2
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 6
	_card.add_theme_stylebox_override("panel", sb)
	add_child(_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_card.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var gear := TextureRect.new()
	gear.texture = UiIcons.tex("gear")
	gear.custom_minimum_size = Vector2(20, 20)
	gear.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gear.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear.mouse_filter = Control.MOUSE_FILTER_PASS
	Tip.bind(gear, "Настройки")
	head.add_child(gear)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var close_btn := UiBtn.icon_button(UiIcons.tex("close"), Vector2(28, 26), UiBtn.Kind.GHOST)
	Tip.bind(close_btn, "Закрыть")
	close_btn.pressed.connect(func():
		if Tip.swallowed():
			return
		close())
	head.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Без этого ScrollContainer по умолчанию разрешает содержимому расти и
	# ВПРАВО, а не только вниз — строка из трёх кнопок вместо равного деления
	# ширины считала себя свободной шириться, и третья уезжала за край экрана.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	DragScroll.attach(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)

	_build_volume_rows(body)
	_build_toggle_row(body)
	_build_mode_row(body)
	_build_language_row(body)
	_build_restore_row(body)


func _row(parent: Control) -> HBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ROW_BG
	sb.border_color = Color8(0x3A, 0x2E, 0x22)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	return h


func _build_volume_rows(body: Control) -> void:
	var row := _row(body)
	_sound_btn = UiBtn.icon_button(UiIcons.tex("sound_on"), Vector2(34, 30))
	_sound_btn.pressed.connect(func():
		if Tip.swallowed():
			return
		Settings.set_sound_muted(not Settings.sound_muted)
		refresh())
	row.add_child(_sound_btn)
	_sound_slider = _make_slider(row)
	_sound_slider.value_changed.connect(func(v: float):
		Settings.set_sound_volume(v / 100.0)
		_tick())

	var row2 := _row(body)
	_music_btn = UiBtn.icon_button(UiIcons.tex("music_on"), Vector2(34, 30))
	_music_btn.pressed.connect(func():
		if Tip.swallowed():
			return
		Settings.set_music_muted(not Settings.music_muted)
		refresh())
	row2.add_child(_music_btn)
	_music_slider = _make_slider(row2)
	_music_slider.value_changed.connect(func(v: float):
		Settings.set_music_volume(v / 100.0))


func _make_slider(row: Control) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.step = 1.0
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiBtn.style_slider(s)
	row.add_child(s)
	return s


## Короткий «тик» при движении ползунка звука — слышно, какая получилась громкость.
func _tick() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_tick_ms > 90:
		_last_tick_ms = now
		Sfx.play("ui_slider")


func _build_toggle_row(body: Control) -> void:
	var row := _row(body)
	_haptics_btn = _toggle(row, "haptics", func():
		Settings.set_haptics_enabled(not Settings.haptics_enabled)
		Haptics.tap())
	_vision_btn = _toggle(row, "eye", func():
		Settings.set_show_vision_radius(not Settings.show_vision_radius))
	_motion_btn = _toggle(row, "motion", func():
		Settings.set_reduce_motion(not Settings.reduce_motion))


func _toggle(row: Control, icon_name: String, action: Callable) -> Button:
	var b := UiBtn.icon_button(UiIcons.tex(icon_name), Vector2(0, 32))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.toggle_mode = false
	b.pressed.connect(func():
		if Tip.swallowed():
			return
		action.call()
		refresh())
	row.add_child(b)
	return b


func _set_toggle(b: Button, on: bool, title: String) -> void:
	_mark(b, on)
	b.modulate = Color(1, 1, 1, 1.0 if on else 0.55)
	if title != "":
		Tip.bind(b, title, "Включено" if on else "Выключено")


## Подсвечивает выбранную кнопку золотом (общий стиль, вид ACCENT).
func _mark(b: Button, on: bool) -> void:
	UiBtn.set_kind(b, UiBtn.Kind.ACCENT if on else UiBtn.Kind.NORMAL)


func _build_mode_row(body: Control) -> void:
	var row := _row(body)
	for m in MODES:
		var b := UiBtn.icon_button(UiIcons.tex(MODE_ICONS[m]), Vector2(0, 36))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Tip.bind(b, MODE_TIPS[m][0], MODE_TIPS[m][1])
		var mode_id: String = m
		b.pressed.connect(func():
			if Tip.swallowed():
				return
			mode_chosen.emit(mode_id))
		row.add_child(b)
		_mode_btns[m] = b


## Язык: чипы с названиями на самом языке. HFlowContainer, не HBoxContainer:
## шесть чипов в один ряд не помещаются на портретных 224px — этот контейнер сам
## переносит лишние на следующую строку, а не сжимает всех до нечитаемой ширины.
func _build_language_row(body: Control) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ROW_BG
	sb.border_color = Color8(0x3A, 0x2E, 0x22)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", sb)
	body.add_child(p)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	p.add_child(flow)
	for entry in Settings.LANGUAGES:
		var code := String(entry.get("code", ""))
		var available := bool(entry.get("available", false))
		var b := UiBtn.icon_button(null, Vector2(0, 26))
		b.text = String(entry.get("name", code))
		b.add_theme_font_size_override("font_size", 10)
		b.disabled = not available
		if not available:
			# Языки ждут перевода (задание владельца: "дальше, после моего
			# разрешения, будет...") — видны сразу, но серые и некликабельные.
			Tip.bind(b, String(entry.get("name", code)), "Скоро")
		else:
			b.pressed.connect(func():
				if Tip.swallowed():
					return
				Settings.set_language(code)
				refresh())
		flow.add_child(b)
		_lang_btns[code] = b


## Единственная точка входа в покупки, подключённая к IAPManager (см.
## scripts/core/iap_manager.gd): кнопка «Восстановить покупки» обязана быть
## где-то в игре для публикации в App Store (Apple отклоняет сборки с
## покупками без неё). Пока платежей нет, об этом скажет тост HUD.
func _build_restore_row(body: Control) -> void:
	var row := _row(body)
	var b := UiBtn.icon_button(UiIcons.tex("restore"), Vector2(0, 30))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Tip.bind(b, "Восстановить покупки", "Платежи не подключены в этой сборке")
	b.pressed.connect(func():
		if Tip.swallowed():
			return
		IAPManager.restore_purchases()
		restore_pressed.emit())
	row.add_child(b)

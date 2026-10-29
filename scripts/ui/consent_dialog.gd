class_name ConsentDialog
extends CanvasLayer
## Окно согласия на аналитику (ГДД §16.1): один раз, при первом запуске, до интро.
## Исключение владельца из правила «текст только в Tip» (ГДД §16): здесь игрок должен
## прочитать, на что соглашается. «Разрешить» / «Нет, спасибо» пишут Settings.analytics_consent;
## «Подробнее» — точный список собираемого и ссылка на web/privacy.html.
## Пока окно открыто, сюжет не начинает сцену, а HUD не ведёт героя (is_open_any).
##
##   if Analytics.should_ask(): ConsentDialog.open_on(self)   # main.gd

signal closed

const WIDTH := 208.0
const BTN_H := 30.0

const TITLE := "Помочь улучшить игру?"
const BODY := "Можно присылать нам обезличенную статистику: как идёт игра, где трудно, что покупают и как игра работает на твоём устройстве.\n\nВместо имени — случайный номер. Экран не записываем.\n\nИграть и сохраняться можно в любом случае. Передумаешь — в Настройках."
const DETAILS := "Собираем:\n• случайный номер игрока и номер запуска;\n• версию игры, систему, модель устройства, видеокарту, язык системы, размер экрана, браузер;\n• настройки: управление, «меньше движения»;\n• игру: начало и конец запуска, время, частоту кадров, уровень, рекорд глубины, смерти и их причину, покупки, крафт, продажу, инструменты, снаряжение, артефакты, сюжетные сцены, подсказки, открытые экраны.\n\nНе собираем: имя, почту, IP и место, сохранение, то, что ты вводишь, запись экрана.\n\nДанные хранит PostHog (сервер в ЕС). Выключить — в Настройках, значок графика."

static var _open_any := false

var _root: Control = null
var _card: PanelContainer = null
var _main_box: VBoxContainer = null
var _details_box: VBoxContainer = null
var _closing := false


static func is_open_any() -> bool:
	return _open_any


static func open_on(host: Node) -> ConsentDialog:
	var d := ConsentDialog.new()
	d.name = "ConsentDialog"
	host.add_child(d)
	d.open()
	return d


func _ready() -> void:
	layer = UiLayers.CONSENT
	add_to_group("hint_block")   # подсказки ждут (scripts/hints/hint_busy.gd)


func _exit_tree() -> void:
	_open_any = false   # статика переживает перезагрузку сцены


func is_open() -> bool:
	return visible and not _closing


func open() -> void:
	Tip.hide_all()
	_build()
	_closing = false
	visible = true
	_open_any = true
	UiAnim.open(_card, UiAnim.Kind.POP, _root)


func choose(granted: bool) -> void:
	if not is_open():
		return
	Settings.set_analytics_consent("granted" if granted else "denied")
	_open_any = false
	_closing = true
	UiAnim.close(_card, UiAnim.Kind.POP, _root, queue_free)
	closed.emit()


func show_details(on: bool) -> void:
	_main_box.visible = not on
	_details_box.visible = on


## Политика: в вебе — web/privacy.html рядом со страницей игры, иначе адрес из data/analytics.json.
static func privacy_url() -> String:
	if OS.has_feature("web"):
		return String(JavaScriptBridge.eval("new URL('privacy.html', location.href).href"))
	return String(Analytics.config().get("privacy_url", ""))


# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "ConsentRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	UiTheme.scrim(_root)   # тап мимо окна ничего не решает: выбор — только кнопкой

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_card = PanelContainer.new()
	_card.name = "Card"
	var sb := ProgressUiKit.box(UiTheme.SHEET, UiTheme.GOLD_DIM, ProgressUiKit.R_CARD)
	sb.set_content_margin_all(8)
	sb.shadow_color = UiTheme.SHADOW
	sb.shadow_size = 4
	_card.add_theme_stylebox_override("panel", sb)
	_card.custom_minimum_size = Vector2(WIDTH, 0)
	center.add_child(_card)

	var stack := VBoxContainer.new()
	_card.add_child(stack)
	_main_box = _build_main()
	stack.add_child(_main_box)
	_details_box = _build_details()
	stack.add_child(_details_box)
	show_details(false)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 16, 0)
	return l


func _row(left: Button, right: Button) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for b in [left, right]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	return h


func _build_main() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = "Main"
	v.add_theme_constant_override("separation", 8)
	var t := _label(TITLE, UiTheme.FS_TITLE_L, UiTheme.TEXT_HI)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(_label(BODY, UiTheme.FS_BODY, UiTheme.TEXT))
	var more := UiBtn.text_button("Подробнее", UiBtn.Kind.GHOST, Vector2(0, 26), UiTheme.FS_BODY)
	more.name = "More"
	more.add_theme_color_override("font_color", UiTheme.GOLD)
	more.pressed.connect(show_details.bind(true))
	v.add_child(more)
	var no := UiBtn.text_button("Нет, спасибо", UiBtn.Kind.NORMAL, Vector2(0, BTN_H), UiTheme.FS_BODY)
	no.name = "Deny"
	no.pressed.connect(choose.bind(false))
	var yes := UiBtn.fill_button(null, Vector2(0, BTN_H), UiTheme.OK_BTN, "Разрешить")
	yes.name = "Allow"
	yes.pressed.connect(choose.bind(true))
	v.add_child(_row(no, yes))
	return v


func _build_details() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = "Details"
	v.add_theme_constant_override("separation", 8)
	var t := _label("Что собираем", UiTheme.FS_TITLE_L, UiTheme.TEXT_HI)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH - 16, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(_label(DETAILS, UiTheme.FS_SMALL, UiTheme.TEXT))
	v.add_child(scroll)
	DragScroll.attach(scroll)
	var back := UiBtn.text_button("Назад", UiBtn.Kind.NORMAL, Vector2(0, BTN_H), UiTheme.FS_BODY)
	back.name = "Back"
	back.pressed.connect(show_details.bind(false))
	var policy := UiBtn.text_button("Политика", UiBtn.Kind.ACCENT, Vector2(0, BTN_H), UiTheme.FS_BODY)
	policy.name = "Privacy"
	policy.pressed.connect(func() -> void: OS.shell_open(privacy_url()))
	v.add_child(_row(back, policy))
	return v

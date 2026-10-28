class_name ProgressScreen
extends Control
## Общий экран героя: три вкладки с иконками — герой (портрет, характеристики,
## рекорды), навыки (дерево прокачки) и музей. Нижняя панель вкладок лежит в зоне
## большого пальца; названия вкладок — в подсказках.
##
## ПОЧЕМУ три экрана под одной кнопкой: нижняя полоса HUD шириной 224 точки
## уже занята инвентарём, инструментом, снаряжением, режимом и сбросом —
## трём отдельным кнопкам там места нет, и по правилам интерфейса (ГДД
## раздел 16) новых панелей вокруг экрана заводить нельзя. Вкладки дают тот
## же доступ одной кнопкой.
##
## Точка входа для остальных систем — статические методы:
##     ProgressScreen.open("museum")    — открыть витрину (например, из
##                                        комнаты музея, которую строит дом)
##     ProgressScreen.open("progress")  — экран прокачки
##     ProgressScreen.open("hero")      — портрет, характеристики, рекорды
##     ProgressScreen.open("records")   — то же, список прокручен к рекордам
##     ProgressScreen.new_museum_panel() — витрина отдельным узлом, если
##                                        комнату надо обставить своей сценой
##
## Пока экран открыт, герой стоит: ввод HUD выключается, копка отменяется —
## иначе палец, нажимающий кнопку апгрейда в левом нижнем углу, попадает в
## джойстик под ней.

const TAB_HERO := "hero"
const TAB_PROGRESS := "progress"
const TAB_MUSEUM := "museum"
# Рекорды переехали внутрь вкладки героя; старое имя оставлено для вызовов извне.
const TAB_RECORDS := "records"

const TAB_BAR_H := ProgressUiKit.TAB_BAR_H

static var _instance: ProgressScreen = null

var finder: ArtifactFinder = null
var records: RecordsStore = null

var _hud: Node = null
var _player: Node = null
var _tab_buttons: Dictionary = {}   # вкладка -> HeroTabButton
var _panels: Dictionary = {}
var _current_tab: String = TAB_PROGRESS
var _hud_button: Button = null
var _closing: bool = false   # экран гаснет (анимация): по смыслу уже закрыт


# ---------------------------------------------------------------------------
# Статическая точка входа
# ---------------------------------------------------------------------------

## Создаёт экран и служебные узлы внутри host (обычно — Main) и запоминает
## его как текущий. Вызывается одной строкой из main.gd.
static func attach(host: Node) -> ProgressScreen:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var layer := CanvasLayer.new()
	layer.name = "ProgressLayer"
	# Слой 95 — выше HUD (1), интерьера дома (9), шторки мастерской (20),
	# модалки дома (30) и баннера автокопки (90), но ниже катсцен (100):
	# сюжетный ролик обязан перекрывать всё. Экран модальный, на весь
	# вьюпорт — если он окажется ниже чужого прозрачного оверлея, тот съест
	# нажатия по вкладкам, хотя на экране ничего не видно.
	layer.layer = UiLayers.HERO
	host.add_child(layer)

	var screen := ProgressScreen.new()
	screen.name = "ProgressScreen"
	layer.add_child(screen)
	screen.setup(host.get("player"), host.get("hud"))

	# Карточка-вспышка находки живёт выше самого экрана (слой 96): артефакт
	# находят под землёй, экран при этом закрыт, а при открытом — тоже виден.
	var card_layer := CanvasLayer.new()
	card_layer.name = "ArtifactCardLayer"
	card_layer.layer = UiLayers.HERO_CARD
	host.add_child(card_layer)
	var card := ArtifactCard.new()
	card.name = "ArtifactCard"
	card_layer.add_child(card)
	return screen


static func instance() -> ProgressScreen:
	return _instance if _instance != null and is_instance_valid(_instance) else null


static func open(tab: String = TAB_PROGRESS) -> void:
	var screen := instance()
	if screen == null:
		return
	screen.open_tab(tab)


static func close_screen() -> void:
	var screen := instance()
	if screen != null:
		screen.close()


static func is_open() -> bool:
	var screen := instance()
	return screen != null and screen.visible and not screen._closing


## Витрина музея отдельным узлом — для комнаты музея в доме.
static func new_museum_panel() -> MuseumPanel:
	return MuseumPanel.new()


## Кнопка нижней полосы HUD. Принимает уже оформленную «фишку» (hud._make_chip),
## чтобы кнопка выглядела ровно как соседние, и возвращает её же.
##
## Кнопка намеренно сделана как можно уже: в ряду шириной 224 точки уже стоят
## инвентарь, инструмент, снаряжение, мастерская, дом, режим и сброс. Если
## художник нарисует res://art/ui/icon_progress.png, подпись сменится иконкой
## сама — ряду это сэкономит ещё десяток точек.
static func make_hud_button(chip: Button) -> Button:
	const ICON_PATH := "res://art/ui/icon_progress.png"
	if ResourceLoader.exists(ICON_PATH):
		chip.icon = load(ICON_PATH)
		chip.expand_icon = true
		chip.custom_minimum_size = Vector2(22, chip.custom_minimum_size.y)
	else:
		chip.text = "Герой"
		chip.add_theme_font_size_override("font_size", UiTheme.FS_TINY)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var sb: StyleBox = chip.get_theme_stylebox(state)
			if sb != null:
				sb.content_margin_left = 3
				sb.content_margin_right = 3
	chip.tooltip_text = "Прокачка, музей, рекорды"
	chip.pressed.connect(func(): ProgressScreen.open())
	var screen := instance()
	if screen != null:
		screen._bind_hud_button(chip)
	else:
		# Кнопка строится раньше экрана (HUD создаётся в main.gd до
		# подключения этой системы) — досвяжемся при attach().
		_pending_hud_button = chip
	return chip


static var _pending_hud_button: Button = null


# ---------------------------------------------------------------------------
# Жизненный цикл
# ---------------------------------------------------------------------------

func _ready() -> void:
	_instance = self
	# Control, лежащий прямо в CanvasLayer, не наследует размер вьюпорта:
	# якоря считаются от нулевого прямоугольника, и весь экран схлопывается
	# в точку (та же грабля описана в hud.gd:_update_layout). Размер задаём
	# руками и пересчитываем на каждую смену размера окна.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()
	_build()
	visible = false
	if _pending_hud_button != null and is_instance_valid(_pending_hud_button):
		_bind_hud_button(_pending_hud_button)
		_pending_hud_button = null
	GameState.skill_points_changed.connect(_on_points_changed)
	GameState.artifact_collected.connect(_on_artifact_collected)
	_sync_hud_button()
	_sync_tabs()


func _on_points_changed(_points: int) -> void:
	_sync_hud_button()
	_sync_tabs()


func _on_artifact_collected(_id: String) -> void:
	_sync_hud_button()


func setup(player, hud) -> void:
	_player = player
	_hud = hud

	finder = ArtifactFinder.new()
	finder.name = "ArtifactFinder"
	add_child(finder)
	finder.setup(player, hud)

	records = RecordsStore.new()
	records.name = "RecordsStore"
	add_child(records)
	records.setup(player)

	var effects := UpgradeEffects.new()
	effects.name = "UpgradeEffects"
	add_child(effects)

	var museum: MuseumPanel = _panels.get(TAB_MUSEUM, null)
	if museum != null:
		museum.store = records
	var hero_panel: HeroPanel = _panels.get(TAB_HERO, null)
	if hero_panel != null and hero_panel.records_panel != null:
		hero_panel.records_panel.setup(records)


func _build() -> void:
	var bg := ColorRect.new()
	# Непрозрачный: сквозь прежние 0.97 просвечивали тосты и мир под экраном.
	bg.color = ProgressUiKit.BG_SOLID
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Именно контейнер, а не голый Control: вкладки создаются скрытыми, а
	# невидимому Control родитель размер по якорям не проталкивает — панели
	# оставались нулевого размера, и открытая вкладка выглядела пустой.
	# Container раскладывает детей при каждом показе.
	var content := MarginContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", 4)
	content.add_theme_constant_override("margin_right", 4)
	var sb := HudSafeArea.bottom(get_viewport())
	content.add_theme_constant_override("margin_top", int(UiBtn.CLOSE_ROW))
	content.add_theme_constant_override("margin_bottom", int(TAB_BAR_H + 6 + sb))
	# Контейнер занимает весь вьюпорт, включая нижнюю панель вкладок по дереву:
	# мышь выбирает самого позднего ребёнка, и без IGNORE он перехватывал
	# нажатия по вкладкам, оставаясь при этом невидимым.
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	_panels[TAB_HERO] = HeroPanel.new()
	_panels[TAB_PROGRESS] = ProgressPanel.new()
	_panels[TAB_MUSEUM] = MuseumPanel.new()
	for key in _panels.keys():
		var panel: Control = _panels[key]
		panel.visible = false
		content.add_child(panel)
	(_panels[TAB_HERO] as HeroPanel).skills_requested.connect(open_tab.bind(TAB_PROGRESS))

	# Нижняя панель вкладок — в зоне большого пальца; крестик — сверху справа, как везде.
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 4
	bar.offset_right = -4
	bar.offset_top = -(TAB_BAR_H + 4 + sb)
	bar.offset_bottom = -4 - sb
	bar.add_theme_constant_override("separation", 3)
	add_child(bar)
	_add_tab_button(bar, TAB_HERO, "tab_hero", "Герой", "Портрет, характеристики и рекорды")
	_add_tab_button(bar, TAB_PROGRESS, "tab_skills", "Навыки", "Дерево прокачки")
	_add_tab_button(bar, TAB_MUSEUM, "tab_museum", "Музей", "Коллекция артефактов")
	UiBtn.close_button(close, self)


func _add_tab_button(parent: Control, tab: String, icon_name: String, title: String, body: String) -> void:
	var b := HeroTabButton.new()
	b.setup(icon_name, title, body)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, TAB_BAR_H)
	b.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		open_tab(tab)
		Sfx.play("ui_tab")
		Haptics.tap())
	parent.add_child(b)
	_tab_buttons[tab] = b


## Значок-число на вкладке «Навыки»: свободные очки.
func _sync_tabs() -> void:
	var skills: HeroTabButton = _tab_buttons.get(TAB_PROGRESS, null)
	if skills != null:
		skills.set_badge(GameState.skill_points_available)


# ---------------------------------------------------------------------------
# Открытие/закрытие
# ---------------------------------------------------------------------------

func open_tab(tab: String) -> void:
	var to_records := tab == TAB_RECORDS
	if to_records:
		tab = TAB_HERO
	_current_tab = tab if _panels.has(tab) else TAB_PROGRESS
	var entering := not visible or _closing
	var switching := not entering
	for key in _panels.keys():
		var panel: Control = _panels[key]
		var was_shown := panel.visible
		panel.visible = key == _current_tab
		if panel.visible and panel.has_method("refresh"):
			panel.refresh()
		# Смена вкладки проявляется мягко, а не щёлкает; первое открытие проявляет весь экран.
		if panel.visible and (not was_shown or entering):
			if switching:
				UiAnim.open(panel, UiAnim.Kind.FADE)
			if panel.has_method("play_intro"):
				panel.play_intro()
	for key in _tab_buttons.keys():
		(_tab_buttons[key] as HeroTabButton).set_selected(key == _current_tab)
	_sync_tabs()
	Tip.hide_all()
	if not visible or _closing:
		_enter()
	if to_records:
		(_panels[TAB_HERO] as HeroPanel).scroll_to_records()


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	UiAnim.close(self, UiAnim.Kind.FADE, null, func() -> void: _closing = false)
	Tip.hide_all()
	Sfx.play("ui_close")
	Haptics.tap()
	SaveSystem.save_game()
	if records != null:
		records.save_records()


func _enter() -> void:
	_closing = false
	visible = true
	UiAnim.open(self, UiAnim.Kind.FADE)
	Sfx.play("ui_open")
	Haptics.tap()
	# Экран во весь вьюпорт, а герой в это время не должен ни копать, ни идти.
	if _player != null:
		_player.digging = null
		_player.release_control()
	# HUD получает ввод через _input, то есть раньше кнопок экрана, и сам
	# проверяет ProgressScreen.is_open() — иначе нажатие в нижней трети
	# уходило бы в джойстик под ней. Шторку инвентаря просто закрываем.
	if _hud != null and _hud.has_method("close_inventory"):
		_hud.close_inventory()


func _fit_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Кнопка в нижней полосе
# ---------------------------------------------------------------------------

func _bind_hud_button(chip: Button) -> void:
	_hud_button = chip
	_sync_hud_button()


## Свободные очки прокачки — главная причина открыть экран, поэтому кнопка
## подсвечивается золотом ровно тогда, когда есть что потратить. Само число
## в подпись не выносится: каждая лишняя буква в ряду шириной 224 точки
## выдавливает соседнюю кнопку за край экрана.
func _sync_hud_button() -> void:
	if _hud_button == null or not is_instance_valid(_hud_button):
		return
	var points: int = GameState.skill_points_available
	var color := ProgressUiKit.GOLD if points > 0 else ProgressUiKit.MUTED
	_hud_button.add_theme_color_override("font_color", color)
	_hud_button.modulate = Color(1, 1, 1, 1) if points > 0 else Color(1, 1, 1, 0.8)
	_hud_button.tooltip_text = "Прокачка, музей, рекорды" if points <= 0 \
		else "Свободных очков: %d" % points

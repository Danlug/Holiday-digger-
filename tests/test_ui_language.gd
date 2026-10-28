extends Node
## test_ui_language — единый язык оформления интерфейса: ступени радиусов, общие
## плашки, движение окон (UiAnim.open/close), нижняя полоса вкладок, значки
## предметов для мелких мест. Визуал проверяется скриншотами (test_screenshot_*).
##
## Запуск: godot --headless --path . res://tests/test_ui_language.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_ui_language ===")
	_check_radius_steps()
	_check_boxes()
	_check_kits_share_palette()
	_check_anim_instant()
	_check_open_close_reopen()
	_check_spring()
	_check_tab_bar()
	_check_small_item_icon()
	_check_tap_scale()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check_radius_steps() -> void:
	var steps := [ProgressUiKit.R_BAR, ProgressUiKit.R_TILE, ProgressUiKit.R_CARD, ProgressUiKit.R_SHEET]
	var ok := true
	for r in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 20]:
		if not steps.has(ProgressUiKit.snap_radius(r)):
			ok = false
	check("любой радиус притягивается к одной из четырёх ступеней", ok)
	check("0 остаётся прямым углом", ProgressUiKit.snap_radius(0) == 0)
	check("ступени растут", ProgressUiKit.R_BAR < ProgressUiKit.R_TILE and ProgressUiKit.R_TILE < ProgressUiKit.R_CARD \
		and ProgressUiKit.R_CARD < ProgressUiKit.R_SHEET)


func _check_boxes() -> void:
	var sheet := ProgressUiKit.sheet_box()
	check("шторка: скруглены верхние углы, нижние прямые", sheet.corner_radius_top_left == ProgressUiKit.R_SHEET \
		and sheet.corner_radius_bottom_left == 0)
	check("шторка: верхняя кромка 2, боковые 1", sheet.border_width_top == 2 and sheet.border_width_left == 1)
	var pop := ProgressUiKit.popup_box()
	check("окно: радиус карточки, рамка 1, есть тень", pop.corner_radius_top_left == ProgressUiKit.R_CARD \
		and pop.border_width_left == 1 and pop.shadow_size > 0)
	var panel := ProgressUiKit.panel_box()
	check("панель экранов героя/музея скруглена (раньше была прямой)", panel.corner_radius_top_left == ProgressUiKit.R_TILE)
	# экранные наборы сами притягивают радиус
	check("MetaUiKit.box(радиус 4) -> ступень плитки", MetaUiKit.box(Color.BLACK, Color.WHITE, 1, 4).corner_radius_top_left == ProgressUiKit.R_TILE)
	check("TechUi.box(радиус 8) -> ступень карточки", TechUi.box(Color.BLACK, Color.WHITE, 8, 3).corner_radius_top_left == ProgressUiKit.R_CARD)
	check("HeroUi.box по умолчанию — плитка", HeroUi.box(Color.BLACK, Color.WHITE).corner_radius_top_left == ProgressUiKit.R_TILE)


func _check_kits_share_palette() -> void:
	check("палитра меты и техники — та же, что у экранов героя",
		MetaUiKit.GOLD == ProgressUiKit.GOLD and TechUi.GOLD == ProgressUiKit.GOLD \
		and MetaUiKit.BORDER == ProgressUiKit.BORDER and TechUi.BORDER == ProgressUiKit.EDGE)
	check("фон полноэкранных экранов непрозрачный", is_equal_approx(ProgressUiKit.BG_SOLID.a, 1.0))


func _check_anim_instant() -> void:
	var c := Control.new()
	check("вне дерева переходы мгновенные", UiAnim.instant(c))
	c.free()
	check("D_OUT короче D_IN: закрытие — ответ на нажатие", UiAnim.D_OUT < UiAnim.D_IN)


func _check_open_close_reopen() -> void:
	var root := Control.new()
	var card := PanelContainer.new()
	root.add_child(card)
	add_child(root)
	card.position = Vector2(0, 30)
	root.visible = true
	var done := [false]
	UiAnim.close(card, UiAnim.Kind.SHEET, root, func() -> void: done[0] = true)
	check("закрытие без окна: root скрыт сразу, done вызван", not root.visible and done[0])
	check("после закрытия карточка на месте и непрозрачна", card.position == Vector2(0, 30) and is_equal_approx(root.modulate.a, 1.0))
	root.visible = true
	UiAnim.open(card, UiAnim.Kind.SHEET, root)
	check("открытие без окна: полная непрозрачность и масштаб 1", is_equal_approx(card.modulate.a, 1.0) \
		and card.scale == Vector2.ONE and card.position == Vector2(0, 30))
	# закрытие без done не падает
	UiAnim.close(card, UiAnim.Kind.POP, root)
	check("закрытие без done не падает", not root.visible)
	root.queue_free()


func _check_spring() -> void:
	var s := UiAnim.Spring.new()
	s.target = 1.0
	var peak := 0.0
	for i in 60:
		s.step(1.0 / 60.0)
		peak = maxf(peak, s.x)
	check("пружина приходит в цель за секунду и не перелетает", s.settled() and peak <= 1.0 + 1e-4)
	s.x = 0.0
	s.v = 0.0
	for i in 5:
		s.step(1.0 / 60.0)
	var x0 := s.x
	var v0 := s.v
	s.target = 0.0
	check("смена цели не двигает значение", s.x == x0 and s.v == v0)
	s.step(1.0 / 60.0)
	check("разворот без скачка: сдвиг за кадр не больше скорости", absf(s.x - x0) <= absf(v0) / 60.0 + 1e-4)
	for i in 60:
		s.step(1.0 / 60.0)
	check("после разворота пружина приходит в новую цель", s.settled())


func _check_tab_bar() -> void:
	var picked := [""]
	var closed := [false]
	var specs := [["a", UiIcons.tex("gear"), "А", "первая"], ["b", UiIcons.tex("eye"), "Б", ""]]
	var bar := HeroTabButton.make_bar(specs, "b", func(k: String) -> void: picked[0] = k, func() -> void: closed[0] = true)
	add_child(bar)
	var buttons: Dictionary = bar.get_meta("buttons")
	check("полоса вкладок: кнопки по ключам", buttons.size() == 2 and buttons.has("a") and buttons.has("b"))
	check("выбранная вкладка помечена", (buttons["b"] as HeroTabButton).selected and not (buttons["a"] as HeroTabButton).selected)
	var big_enough := true
	for b in buttons.values():
		if (b as Control).custom_minimum_size.y < 22.0:
			big_enough = false
	check("цель нажатия вкладки не меньше 22", big_enough and ProgressUiKit.TAB_BAR_H >= 22)
	(buttons["a"] as HeroTabButton).pressed.emit()
	check("нажатие вкладки отдаёт ключ", picked[0] == "a")
	bar.queue_free()
	check("значок вкладки задаётся картинкой", (HeroTabButton.new() as HeroTabButton).icon_tex == null)


func _check_small_item_icon() -> void:
	var t := UiIcons.item_small("diamond", 16)
	check("мелкий значок предмета 16×16", t != null and t.get_width() == 16 and t.get_height() == 16)
	var img := t.get_image()
	var dark_edge := false
	for y in 16:
		for x in 16:
			var p := img.get_pixel(x, y)
			if p.a > 0.9 and p.get_luminance() < 0.12:
				dark_edge = true
	check("у мелкого значка есть тёмный ободок", dark_edge)
	check("значок кэшируется", UiIcons.item_small("diamond", 16) == t)


func _check_tap_scale() -> void:
	check("кнопка под пальцем проседает, но не сильно", UiAnim.TAP_SCALE < 1.0 and UiAnim.TAP_SCALE > 0.85)
	var b := UiBtn.icon_button(UiIcons.tex("gear"), Vector2(30, 30))
	check("кнопка с откликом помечена", b.has_meta(UiBtn.FEEDBACK_META))
	var tab := HeroTabButton.new()
	check("вкладка героя получает то же «проседание»", tab.has_meta(UiBtn.FEEDBACK_META))
	b.free()
	tab.free()

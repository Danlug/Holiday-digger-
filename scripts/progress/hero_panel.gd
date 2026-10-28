class_name HeroPanel
extends Control
## Вкладка «Герой»: портрет, уровень с полосой опыта, очки навыков, шесть
## характеристик и рекорды — всё плитками «иконка + число». Названия и пояснения
## лежат в подсказках Tip (наведение мыши / долгое нажатие), абзацев на экране нет.
##
## Цифры характеристик берутся у тех же функций Balance и GameState, которыми
## пользуется игра на ходу (радиус тумана, время копки, грузоподъёмность), —
## экран ничего не считает сам и не может разойтись с игрой.

signal skills_requested

var records_panel: RecordsPanel

var _scroll: ScrollContainer
var _column: VBoxContainer
var _level_label: Label
var _xp_track: Control
var _xp_fill: ColorRect
var _xp_label: Label
var _points_chip: PanelContainer
var _points_icon: TextureRect
var _points_label: Label
var _coins_tile: PanelContainer
var _dollars_tile: PanelContainer
var _stats: Dictionary = {}     # id -> плитка
var _time: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	# Подписки — методами, а не лямбдами: метод отцепляется сам, когда узел удалён.
	GameState.xp_changed.connect(_on_xp_changed)
	GameState.skill_points_changed.connect(_on_int_changed)
	GameState.coins_changed.connect(_on_int_changed)
	GameState.dollars_changed.connect(_on_int_changed)
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	# Движок включает _process при READY, даже если скрыт с самого начала: сигнал видимости до первого показа молчит.
	set_process(is_visible_in_tree())
	refresh()


func _build() -> void:
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	# Прокрутка перетаскиванием списка, а не только ползунком (решение владельца).
	DragScroll.attach(_scroll)

	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 8)
	_scroll.add_child(_column)

	_build_card()
	_build_stats()
	records_panel = RecordsPanel.new()
	_column.add_child(records_panel)


func _build_card() -> void:
	var card := HBoxContainer.new()
	card.add_theme_constant_override("separation", 6)
	_column.add_child(card)
	card.add_child(HeroPortrait.new())

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 5)
	card.add_child(right)

	# уровень: большое число рядом с «искрой опыта»
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 5)
	level_row.mouse_filter = Control.MOUSE_FILTER_STOP
	right.add_child(level_row)
	level_row.add_child(HeroIcons.make("ui_xp", 20.0))
	_level_label = ProgressUiKit.make_label("1", UiTheme.FS_HUGE, ProgressUiKit.GOLD)
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_row.add_child(_level_label)
	Tip.bind(level_row, "Уровень героя", "Опыт даёт всё: копка, находки, новая глубина. Каждый уровень — очко навыков.")

	# полоса опыта с числами внутри
	_xp_track = Panel.new()
	_xp_track.custom_minimum_size = Vector2(0, 13)
	_xp_track.add_theme_stylebox_override("panel", HeroUi.box(Color(0.043, 0.035, 0.027, 0.95), ProgressUiKit.BORDER, 3))
	_xp_track.mouse_filter = Control.MOUSE_FILTER_STOP
	right.add_child(_xp_track)
	_xp_fill = ColorRect.new()
	_xp_fill.color = ProgressUiKit.BLUE
	_xp_fill.position = Vector2(1, 1)
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_track.add_child(_xp_fill)
	_xp_label = ProgressUiKit.make_label("", UiTheme.FS_TINY, Color(0.95, 0.93, 0.88))
	_xp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_track.add_child(_xp_label)
	_xp_track.resized.connect(_sync)
	Tip.bind(_xp_track, "Опыт", "Сколько набрано и сколько нужно до следующего уровня.")

	# очки навыков: тап открывает дерево
	_points_chip = PanelContainer.new()
	_points_chip.custom_minimum_size = Vector2(0, 28)
	_points_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	_points_chip.gui_input.connect(_on_points_input)
	right.add_child(_points_chip)
	var chip_row := HBoxContainer.new()
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip_row.add_theme_constant_override("separation", 5)
	chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_points_chip.add_child(chip_row)
	_points_icon = HeroIcons.make("ui_star", 18.0)
	chip_row.add_child(_points_icon)
	_points_label = ProgressUiKit.make_label("0", UiTheme.FS_HERO, ProgressUiKit.GOLD)
	_points_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_row.add_child(_points_label)
	Tip.bind(_points_chip, "Очки навыков", "Нажми — откроется дерево прокачки.")

	# кошелёк: монеты и доллары
	var wallet := HBoxContainer.new()
	wallet.add_theme_constant_override("separation", 4)
	right.add_child(wallet)
	_coins_tile = HeroUi.make_tile("ui_coin", "0", ProgressUiKit.GOLD, Vector2(0, 24))
	_dollars_tile = HeroUi.make_tile("ui_dollar", "0", HeroUi.OK, Vector2(0, 24))
	wallet.add_child(_coins_tile)
	wallet.add_child(_dollars_tile)
	Tip.bind(_coins_tile, "Монеты", "Платят за добычу и находки.")
	Tip.bind(_dollars_tile, "Доллары", "Редкая валюта: награды за собранные ветки музея.")


func _build_stats() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_child(grid)
	for id: String in ["hp", "stamina", "hunger", "strength", "vision", "dig_speed"]:
		var tile := HeroUi.make_tile("sk_" + id, "0", HeroUi.branch_color(id))
		grid.add_child(tile)
		_stats[id] = tile


func _on_xp_changed(_xp: int, _lvl: int) -> void:
	_sync()


func _on_int_changed(_value: int) -> void:
	_sync()


func _on_points_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if pressed:
		# Касание завершает долгое нажатие подсказки — действие не нужно.
		await get_tree().process_frame
		if Tip.swallowed():
			return
		HeroUi.tap()
		HeroUi.bounce(_points_chip, 1.05)
		skills_requested.emit()


func _process(delta: float) -> void:
	_time += delta
	var glow: bool = GameState.skill_points_available > 0 and not HeroUi.calm()
	var s := 1.0 + (0.14 * (0.5 + 0.5 * sin(_time * 5.0)) if glow else 0.0)
	_points_icon.pivot_offset = _points_icon.size * 0.5
	_points_icon.scale = Vector2(s, s)


func refresh() -> void:
	_sync()
	if records_panel != null:
		records_panel.refresh()


## Плитки характеристик и рекордов всплывают по очереди при открытии вкладки.
func play_intro() -> void:
	var tiles: Array = _stats.values()
	if records_panel != null:
		tiles.append_array(records_panel.tiles())
	UiAnim.stagger(tiles, 0.035)


## Подкрутить список к рекордам (ProgressScreen.open("records")).
func scroll_to_records() -> void:
	await get_tree().process_frame
	if records_panel != null and _scroll != null:
		_scroll.scroll_vertical = int(records_panel.position.y)


func _sync() -> void:
	if _level_label == null:
		return
	_level_label.text = str(GameState.level)
	var need := Balance.xp_required_for_level(GameState.level)
	var have: int = GameState.xp
	_xp_label.text = "%d / %d" % [have, need]
	_xp_fill.size = Vector2(maxf(_xp_track.size.x - 2.0, 0.0) * clampf(float(have) / float(maxi(need, 1)), 0.0, 1.0),
		maxf(_xp_track.size.y - 2.0, 0.0))

	var points: int = GameState.skill_points_available
	_points_label.text = str(points)
	_points_label.add_theme_color_override("font_color", ProgressUiKit.GOLD if points > 0 else ProgressUiKit.DIM)
	_points_chip.add_theme_stylebox_override("panel", HeroUi.box(
		HeroUi.TILE_BG_HI if points > 0 else HeroUi.TILE_BG,
		ProgressUiKit.GOLD if points > 0 else ProgressUiKit.BORDER, 4, 2 if points > 0 else 1))

	HeroUi.tile_value(_coins_tile).text = UiFmt.short(GameState.coins)
	HeroUi.tile_value(_dollars_tile).text = UiFmt.short(GameState.dollars)
	_sync_stats()


func _sync_stats() -> void:
	var hp_stage := GameState.get_skill_stage("hp")
	_set_stat("hp", str(int(GameState.get_max_hp())), "Здоровье",
		"Сколько выдержит герой: падения, лава, голод.",
		"Ступень %d из %d, +%d HP за ступень" % [hp_stage, _stages("hp"), _per_stage("hp", 20)])

	var st := GameState.get_skill_stage("stamina")
	var st_pct := _per_stage("stamina", 15) * st
	_set_stat("stamina", "+%d%%" % st_pct, "Бодрость",
		"Дольше копаешь, прежде чем выдохнешься.",
		"Ступень %d из %d" % [st, _stages("stamina")])

	var hg := GameState.get_skill_stage("hunger")
	var hg_pct := _per_stage("hunger", 8) * hg
	_set_stat("hunger", "-%d%%" % hg_pct, "Голод",
		"Сытость тает медленнее.",
		"Ступень %d из %d, расход меньше на %d%%" % [hg, _stages("hunger"), hg_pct])

	var carry_now := GameState.get_total_weight()
	var carry_max := GameState.get_max_carry_kg()
	_set_stat("strength", "%d/%d" % [int(round(carry_now)), int(round(carry_max))], "Носимый вес",
		"Сколько килограммов добычи герой тащит без перегруза.",
		"Сейчас %.1f из %.0f кг" % [carry_now, carry_max])

	var vis := GameState.get_skill_stage("vision")
	var res_r := Balance.get_vision_radius("vision", vis)
	_set_stat("vision", str(res_r), "Обзор",
		"Как далеко видно под землёй: ресурсы и рельеф.",
		"Ресурсы %d кл., рельеф %d кл." % [res_r, res_r + Balance.get_vision_terrain_bonus()])

	var ds := GameState.get_skill_stage("dig_speed")
	var secs := Balance.get_dig_time_seconds(ds)
	_set_stat("dig_speed", "%.1fс" % secs, "Скорость копки",
		"Сколько секунд уходит на одну клетку земли.",
		"Ступень %d из %d" % [ds, _stages("dig_speed")])


func _set_stat(id: String, value: String, title: String, body: String, extra: String) -> void:
	var tile: Control = _stats.get(id, null)
	if tile == null:
		return
	HeroUi.tile_value(tile).text = value
	Tip.set_text(tile, title, body, extra)


func _stages(branch_id: String) -> int:
	return int(Balance.get_upgrade_branch(branch_id).get("stages", 0))


func _per_stage(branch_id: String, fallback: int) -> int:
	var effect: Dictionary = Balance.get_upgrade_branch(branch_id).get("effect", {})
	if effect.has("percent_per_stage"):
		return int(Balance.unwrap(effect.get("percent_per_stage", fallback)))
	return int(Balance.unwrap(effect.get("per_stage", fallback)))

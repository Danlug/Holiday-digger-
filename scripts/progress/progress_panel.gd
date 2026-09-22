class_name ProgressPanel
extends Control
## Экран прокачки (ГДД раздел 11): уровень, опыт до следующего, свободные
## очки и девять веток апгрейдов, которые можно поднимать.
##
## ПОЧЕМУ здесь нет ни одной формулы: уровни, стоимости ступеней и эффекты
## уже посчитаны в balance.gd и game_state.gd и используются игрой на ходу
## (радиус тумана читается каждый кадр, скорость копки — в момент удара,
## грузоподъёмность — при каждой находке). Экран только показывает их и
## вызывает GameState.spend_skill_point — иначе числа на экране и числа в
## игре начали бы расходиться.

const BAR_W := 190.0

var _level_label: Label
var _xp_label: Label
var _xp_fill: ColorRect
var _points_label: Label
var _branch_rows: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	GameState.xp_changed.connect(func(_xp, _lvl): _sync_header())
	GameState.skill_points_changed.connect(func(_p): refresh())
	refresh()


func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	# Прокрутка перетаскиванием списка, а не только ползунком (решение владельца).
	DragScroll.attach(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	scroll.add_child(column)

	var head := ProgressUiKit.make_panel()
	column.add_child(head)
	var head_box := VBoxContainer.new()
	head_box.add_theme_constant_override("separation", 2)
	head.add_child(head_box)

	var top_row := HBoxContainer.new()
	head_box.add_child(top_row)
	_level_label = ProgressUiKit.make_label("Уровень 1", 13, ProgressUiKit.GOLD)
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_level_label)
	_points_label = ProgressUiKit.make_label("", 11, ProgressUiKit.GREEN)
	top_row.add_child(_points_label)

	_xp_fill = ProgressUiKit.make_bar(head_box, BAR_W, 6, ProgressUiKit.BLUE)
	_xp_label = ProgressUiKit.make_label("", 9, ProgressUiKit.DIM)
	head_box.add_child(_xp_label)

	_branch_rows = VBoxContainer.new()
	_branch_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_branch_rows.add_theme_constant_override("separation", 3)
	column.add_child(_branch_rows)

	var footer := ProgressUiKit.make_wrapped_label(
		"На полную прокачку всех веток нужно около 540 очков, а к сотому уровню их набирается около 140. "
		+ "Выбирай, кем быть.", 9, ProgressUiKit.DIM)
	column.add_child(footer)


func refresh() -> void:
	_sync_header()
	for c in _branch_rows.get_children():
		c.queue_free()
	for branch in Balance.upgrades.get("branches", []):
		_branch_rows.add_child(_make_branch_row(branch))


func _sync_header() -> void:
	_level_label.text = "Уровень %d" % GameState.level
	var need := Balance.xp_required_for_level(GameState.level)
	var have: int = GameState.xp
	_xp_label.text = "Опыт %d / %d — до %d уровня" % [have, need, GameState.level + 1]
	_xp_fill.size.x = (BAR_W - 2.0) * clampf(float(have) / float(maxi(need, 1)), 0.0, 1.0)
	var points: int = GameState.skill_points_available
	_points_label.text = "очков: %d" % points
	_points_label.add_theme_color_override("font_color",
		ProgressUiKit.GREEN if points > 0 else ProgressUiKit.DIM)


func _make_branch_row(branch: Dictionary) -> Control:
	var branch_id := String(branch.get("id", ""))
	var stages := int(branch.get("stages", 0))
	var stage := GameState.get_skill_stage(branch_id)
	var cost := Balance.get_upgrade_stage_cost(branch_id, stage + 1)
	var is_max := stage >= stages
	var can_afford := not is_max and cost >= 0 and GameState.skill_points_available >= cost

	var panel := ProgressUiKit.make_panel(
		ProgressUiKit.PANEL_BG,
		ProgressUiKit.GOLD if can_afford else ProgressUiKit.BORDER)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var title_row := HBoxContainer.new()
	box.add_child(title_row)
	var title := ProgressUiKit.make_label(String(branch.get("name_ru", branch_id)), 11,
		ProgressUiKit.MUTED if not is_max else ProgressUiKit.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(ProgressUiKit.make_label("%d/%d" % [stage, stages], 9, ProgressUiKit.DIM))

	var mid_row := HBoxContainer.new()
	mid_row.add_theme_constant_override("separation", 6)
	box.add_child(mid_row)
	var pips_holder := HBoxContainer.new()
	pips_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pips_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid_row.add_child(pips_holder)
	# 15 ступеней скорости копки в 224 точки ширины влезают только узкими
	# фишками — поэтому ширина фишки зависит от числа ступеней.
	ProgressUiKit.make_pips(pips_holder, stages, stage, 9.0 if stages <= 10 else 6.0)

	var buy := ProgressUiKit.make_button("макс" if is_max else "+%d" % cost)
	buy.custom_minimum_size = Vector2(38, 18)
	buy.disabled = is_max or not can_afford
	buy.pressed.connect(_on_buy_pressed.bind(branch_id))
	mid_row.add_child(buy)

	var effect_text := _effect_text(branch, stage)
	if not is_max:
		# Стрелка «→» (U+2192) в шрифте темы по умолчанию отсутствует и
		# рисуется пустым квадратом — та же история, что с ↺ в нижней полосе.
		effect_text += "  ->  " + _effect_text(branch, stage + 1)
	box.add_child(ProgressUiKit.make_wrapped_label(effect_text, 9,
		ProgressUiKit.MUTED if can_afford else ProgressUiKit.DIM))
	return panel


func _on_buy_pressed(branch_id: String) -> void:
	var before := GameState.get_skill_stage(branch_id)
	if not GameState.spend_skill_point(branch_id):
		return
	# Поднятый потолок HP бесполезен, пока полоска не подросла: игрок отдал
	# очко и не увидел ничего. Доливаем ровно прибавку ступени.
	if branch_id == "hp":
		var per_stage := float(Balance.unwrap(
			Balance.get_upgrade_branch("hp").get("effect", {}).get("per_stage", 20)))
		GameState.heal(per_stage * float(GameState.get_skill_stage(branch_id) - before))
	SaveSystem.save_game()
	refresh()


## Человеческое описание эффекта ветки на заданной ступени. Разбор идёт по
## полю effect.type из data/upgrades.json, а не по id ветки: новая ветка с
## уже известным типом эффекта опишется сама, без правки этого файла.
func _effect_text(branch: Dictionary, stage: int) -> String:
	var effect: Dictionary = branch.get("effect", {})
	var type := String(effect.get("type", ""))
	match type:
		"radius_add_cells":
			var base := int(Balance.unwrap(effect.get("base", 0)))
			var per := int(Balance.unwrap(effect.get("per_stage", 1)))
			return "обзор %d кл." % (base + per * stage)
		"multiplicative_time_reduction":
			return "%.2f сек/клетка" % Balance.get_dig_time_seconds(stage)
		"flat_add":
			return "%d HP" % Balance.get_max_hp(stage)
		"flat_add_kg":
			return "%.0f кг" % Balance.get_max_carry_kg(stage)
		"percent_of_base_duration":
			var per_stamina := int(Balance.unwrap(effect.get("percent_per_stage", 15)))
			return "+%d%% времени до истощения" % (per_stamina * stage)
		"percent_consumption_reduction":
			var per_hunger := int(Balance.unwrap(effect.get("percent_per_stage", 8)))
			return "−%d%% расхода голода" % (per_hunger * stage)
		"table":
			return "множитель ×%d" % int(Balance.get_luck_multiplier(stage)) if stage > 0 else "множитель ×1"
		"table_dual":
			var chance := Balance.get_luck_chance_percent(stage)
			return "земля %.0f%%, ресурс %.0f%%" % [chance["earth"], chance["resource"]]
		_:
			return String(branch.get("notes", ""))

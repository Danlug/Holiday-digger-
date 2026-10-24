class_name ProgressPanel
extends Control
## Вкладка «Навыки» (ГДД раздел 11): сверху очки навыков крупным числом и
## полоса опыта, ниже — дерево прокачки (SkillTree), которое прокручивается
## перетаскиванием. Здесь нет ни абзацев, ни формул: объяснения живут в
## подсказках, числа — на плитках.

const BAR_W := 150.0

var tree: SkillTree
var _points_chip: PanelContainer
var _points_icon: TextureRect
var _points_label: Label
var _level_label: Label
var _xp_fill: ColorRect
var _xp_label: Label
var _time: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	GameState.xp_changed.connect(_on_xp_changed)
	GameState.skill_points_changed.connect(_on_points_changed)
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	# Движок включает _process при READY, даже если скрыт с самого начала: сигнал видимости до первого показа молчит.
	set_process(is_visible_in_tree())
	refresh()


func _on_xp_changed(_xp: int, _lvl: int) -> void:
	_sync_header()


func _on_points_changed(_points: int) -> void:
	_sync_header()


func _build() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 4)
	add_child(column)

	# --- шапка: очки навыков и уровень ---
	var head := ProgressUiKit.make_panel()
	column.add_child(head)
	var head_box := VBoxContainer.new()
	head_box.add_theme_constant_override("separation", 3)
	head.add_child(head_box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	head_box.add_child(top)

	_points_chip = PanelContainer.new()
	_points_chip.add_theme_stylebox_override("panel", HeroUi.box(HeroUi.TILE_BG_HI, ProgressUiKit.GOLD, 4))
	_points_chip.custom_minimum_size = Vector2(64, 26)
	_points_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	top.add_child(_points_chip)
	var chip_row := HBoxContainer.new()
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip_row.add_theme_constant_override("separation", 4)
	chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_points_chip.add_child(chip_row)
	_points_icon = HeroIcons.make("ui_star", 16.0)
	chip_row.add_child(_points_icon)
	_points_label = ProgressUiKit.make_label("0", 15, ProgressUiKit.GOLD)
	_points_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_row.add_child(_points_label)
	Tip.bind(_points_chip, "Очки навыков", points_rule_text(),
		"К сотому уровню — %d очков, всё дерево стоит %d" % [Balance.skill_points_total(100),
			Balance.get_upgrade_tree_total_cost()])

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	var level_chip := HBoxContainer.new()
	level_chip.add_theme_constant_override("separation", 3)
	level_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	top.add_child(level_chip)
	level_chip.add_child(HeroIcons.make("ui_xp", 16.0))
	_level_label = ProgressUiKit.make_label("1", 14, ProgressUiKit.BLUE)
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_chip.add_child(_level_label)
	Tip.bind(level_chip, "Уровень героя", "Опыт даёт всё: копка, находки, глубина.")

	var bar_holder := Control.new()
	bar_holder.custom_minimum_size = Vector2(0, 9)
	head_box.add_child(bar_holder)
	var bar_row := HBoxContainer.new()
	bar_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_holder.add_child(bar_row)
	_xp_fill = ProgressUiKit.make_bar(bar_row, BAR_W, 9, ProgressUiKit.BLUE)
	var track := _xp_fill.get_parent() as Control
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.resized.connect(_sync_header)
	_xp_label = ProgressUiKit.make_label("", 8, ProgressUiKit.DIM)
	bar_row.add_child(_xp_label)
	Tip.bind(track, "Опыт", "До следующего уровня")

	# --- дерево с прокруткой перетаскиванием ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Полоса прокрутки съедала 8 из 216 точек ширины — девятой ветке не хватало места.
	# Прокрутка остаётся: перетаскивание (DragScroll) и колесо.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	column.add_child(scroll)
	DragScroll.attach(scroll)

	tree = SkillTree.new()
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tree)


## Правило очков словами — из тех же чисел, что считает Balance (ГДД §11).
static func points_rule_text() -> String:
	var parts: PackedStringArray = []
	var from := 2
	var sp: Dictionary = Balance.upgrades.get("skill_points", {})
	for tier in Balance.unwrap(sp.get("per_level_tiers", [])):
		var to := int(tier.get("up_to_level", 100))
		parts.append("%d–%d ур. — по %d" % [from, to, int(tier.get("points", 1))])
		from = to + 1
	var bonus := int(Balance.unwrap(sp.get("bonus_every_5th_level", 2)))
	return "Даются за уровень, и чем выше уровень, тем больше: %s; каждый пятый — ещё +%d. На все ветки не хватит — выбирай, кем быть." % [
		"; ".join(parts), bonus]


func _process(delta: float) -> void:
	_time += delta
	var ready: bool = GameState.skill_points_available > 0 and not HeroUi.calm()
	var s := 1.0 + (0.12 * (0.5 + 0.5 * sin(_time * 5.0)) if ready else 0.0)
	_points_icon.pivot_offset = _points_icon.size * 0.5
	_points_icon.scale = Vector2(s, s)


func refresh() -> void:
	_sync_header()
	if tree != null:
		tree.refresh()


func _sync_header() -> void:
	if _level_label == null:
		return
	_level_label.text = str(GameState.level)
	var need := Balance.xp_required_for_level(GameState.level)
	var have: int = GameState.xp
	_xp_label.text = "%d/%d" % [have, need]
	var track := _xp_fill.get_parent() as Control
	_xp_fill.size.x = maxf(track.size.x - 2.0, 0.0) * clampf(float(have) / float(maxi(need, 1)), 0.0, 1.0)
	var points: int = GameState.skill_points_available
	_points_label.text = str(points)
	_points_label.add_theme_color_override("font_color", ProgressUiKit.GOLD if points > 0 else ProgressUiKit.DIM)
	_points_chip.add_theme_stylebox_override("panel", HeroUi.box(
		HeroUi.TILE_BG_HI if points > 0 else HeroUi.TILE_BG,
		ProgressUiKit.GOLD if points > 0 else ProgressUiKit.BORDER, 4))

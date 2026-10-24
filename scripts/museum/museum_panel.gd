class_name MuseumPanel
extends Control
## Музей в доме (ГДД раздел 10): витрины-сетка 5 веток × 5 артефактов и
## центральная витрина ультимативного сета с гнёздами Перчатки Мироздания.
##
## Найденные артефакты — яркие, с мягким сиянием; ненайденные — силуэты с «?».
## Название, описание и глубина находки — только в подсказке Tip (у
## ненайденных — лишь намёк). Закрытая ветка обводится золотом, по ряду бежит
## блик, а в момент закрытия вспыхивают искры.
##
## Панель самодостаточна: её можно показать и как вкладку общего экрана, и
## вставить в комнату музея, которую строит дом (см. ProgressScreen.open).
## Картинки берутся у ArtifactArt (art/artifacts/<id>.png); нет картинки —
## ячейка рисует заглушку с инициалами.

const SLOT := ArtifactSlot.SIZE
const ICON := ArtifactSlot.ICON
const ROMAN := ["I", "II", "III", "IV", "V"]

## Хранилище рекордов — для гнёзд Перчатки (выкопанные материалы).
var store: RecordsStore = null:
	set(value):
		store = value
		if _showcase != null:
			_showcase.store = value
			_showcase.refresh()

var _column: VBoxContainer
var _showcase: SetShowcase
var _branch_panels: Dictionary = {}     # номер ветки -> PanelContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	GameState.artifact_collected.connect(_on_artifact_collected)
	GameState.branch_completed.connect(celebrate_branch)
	refresh()


func _on_artifact_collected(_id: String) -> void:
	refresh()


func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	# Прокрутка перетаскиванием списка, а не только ползунком (решение владельца).
	DragScroll.attach(scroll)

	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 4)
	scroll.add_child(_column)


func refresh() -> void:
	for c in _column.get_children():
		_column.remove_child(c)
		c.queue_free()
	_branch_panels.clear()
	_showcase = null

	_column.add_child(_make_header())
	for branch: Dictionary in Balance.artifacts.get("branches", []):
		var case_panel := _make_branch_case(branch)
		_column.add_child(case_panel)
		_branch_panels[int(branch.get("branch", 0))] = case_panel

	_showcase = SetShowcase.new()
	_showcase.store = store
	_column.add_child(_showcase)


# ---------------------------------------------------------------------------
# Шапка
# ---------------------------------------------------------------------------

func _make_header() -> Control:
	var total: int = Balance.artifacts.get("artifacts", []).size()
	var found: int = GameState.collected_artifacts.size()
	var head := ProgressUiKit.make_panel()
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(row)
	row.add_child(HeroIcons.make("tab_museum", 16.0))
	var count := ProgressUiKit.make_label("%d/%d" % [found, total], 12, ProgressUiKit.GOLD)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count)
	var bar := HeroUi.make_mini_bar(float(found) / float(maxi(total, 1)), ProgressUiKit.GOLD, 7.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	Tip.bind(head, "Музей", "Находки из шахты встают на витрины. Закрой ветку целиком — получишь награду.",
		"Собрано %d из %d" % [found, total])
	return head


# ---------------------------------------------------------------------------
# Витрина ветки
# ---------------------------------------------------------------------------

func _make_branch_case(branch: Dictionary) -> Control:
	var branch_num := int(branch.get("branch", 0))
	var items := Balance.get_artifacts_in_branch(branch_num)
	var found := 0
	for a: Dictionary in items:
		if GameState.collected_artifacts.has(String(a.get("id", ""))):
			found += 1
	var complete := GameState.completed_branches.has(branch_num)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _case_box(branch_num, complete))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	box.add_child(_make_case_header(branch, branch_num, found, items.size(), complete))

	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 4)
	box.add_child(slots)
	for a: Dictionary in items:
		var slot := ArtifactSlot.new()
		slots.add_child(slot)
		slot.setup(a)

	if complete:
		var shimmer := _Shimmer.new()
		panel.add_child(shimmer)
	return panel


func _case_box(branch_num: int, complete: bool) -> StyleBoxFlat:
	var tint: Color = ArtifactSlot.TINTS.get(branch_num, ProgressUiKit.GOLD)
	var sb := HeroUi.box(Color(0.085, 0.07, 0.06).lerp(tint.darkened(0.78), 0.35),
		ProgressUiKit.GOLD if complete else ProgressUiKit.BORDER, ProgressUiKit.R_CARD, 2 if complete else 1)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 4
	return sb


func _make_case_header(branch: Dictionary, branch_num: int, found: int, total: int, complete: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var numeral := ProgressUiKit.make_label(ROMAN[clampi(branch_num - 1, 0, ROMAN.size() - 1)], 10,
		ProgressUiKit.GOLD if complete else ProgressUiKit.MUTED)
	numeral.custom_minimum_size = Vector2(18, 0)
	numeral.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(numeral)

	for i in range(total):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(8, 6)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.color = ProgressUiKit.GOLD if i < found else Color(0.2, 0.17, 0.13)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	var reward: Dictionary = branch.get("completion_reward", {})
	var coins := int(Balance.unwrap(reward.get("coins", 0)))
	var dollars := int(Balance.unwrap(reward.get("premium_currency", 0)))
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 2)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chip)
	chip.add_child(HeroIcons.make("ui_check" if complete else "ui_chest", 14.0))
	var coin_label := ProgressUiKit.make_label(HeroUi.short_num(coins), 9,
		ProgressUiKit.DIM if complete else ProgressUiKit.GOLD)
	coin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(coin_label)

	var range_cells: Array = branch.get("depth_range", [0, 0])
	Tip.bind(row, ArtifactText.branch_name(branch),
		"Глубина %d–%d. Найдено %d из %d." % [int(Balance.unwrap(range_cells[0])),
			int(Balance.unwrap(range_cells[1])), found, total],
		("Награда получена: %d монет, %d долларов" if complete else "Награда за всю ветку: %d монет, %d долларов")
			% [coins, dollars])
	return row


## Момент славы: ветка закрыта — рамка вспыхивает, летят искры.
func celebrate_branch(branch_num: int) -> void:
	var panel: Control = _branch_panels.get(branch_num, null)
	if panel == null or not is_visible_in_tree():
		return
	HeroUi.bounce(panel, 1.04)
	HeroUi.burst_particles(panel, panel.size * 0.5, ProgressUiKit.GOLD, 32, 120.0)
	Sfx.play("quest_done")
	Haptics.buzz(80)


## Блик, пробегающий по закрытой ветке. Не ловит нажатия.
class _Shimmer extends Control:
	var _t: float = randf() * 3.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var k := fmod(_t / 3.2, 1.0)
		if k > 0.45 or HeroUi.calm():
			return
		var x := lerpf(-16.0, size.x + 16.0, k / 0.45)
		var w := 9.0
		var pts := PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w - 8.0, size.y), Vector2(x - 8.0, size.y)])
		draw_colored_polygon(pts, Color(1, 0.95, 0.7, 0.16))

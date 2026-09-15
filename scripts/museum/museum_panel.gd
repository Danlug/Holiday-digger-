class_name MuseumPanel
extends Control
## Музей в доме (ГДД раздел 10): витрина из пяти веток по пять предметов,
## пустые места под ненайденное и ультимативный сет из пятых предметов.
##
## ПОЧЕМУ слот рисуется сам, а не через готовый спрайт: спрайтов артефактов
## ещё не существует. Слот спрашивает картинку у ArtifactArt и, если её нет,
## рисует заглушку с инициалами названия. Когда художник положит файлы в
## art/artifacts/, картинки встанут на место сами — правок кода не будет.
##
## Панель самодостаточна: её можно показать и как вкладку общего экрана, и
## вставить в комнату музея, которую строит дом (см. ProgressScreen.open).

const SLOT := 38.0
const ICON := 32.0

var _found_label: Label
var _found_fill: ColorRect
var _column: VBoxContainer
# branch -> Label с описанием выбранного в этой ветке предмета
var _detail_labels: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	GameState.artifact_collected.connect(func(_id): refresh())
	refresh()


func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 4)
	scroll.add_child(_column)


func refresh() -> void:
	for c in _column.get_children():
		c.queue_free()
	_detail_labels.clear()

	var total: int = Balance.artifacts.get("artifacts", []).size()
	var found: int = GameState.collected_artifacts.size()

	var head := ProgressUiKit.make_panel()
	_column.add_child(head)
	var head_box := VBoxContainer.new()
	head_box.add_theme_constant_override("separation", 2)
	head.add_child(head_box)
	var head_row := HBoxContainer.new()
	head_box.add_child(head_row)
	var title := ProgressUiKit.make_label("Музей", 13, ProgressUiKit.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(title)
	_found_label = ProgressUiKit.make_label("%d / %d" % [found, total], 11, ProgressUiKit.MUTED)
	head_row.add_child(_found_label)
	_found_fill = ProgressUiKit.make_bar(head_box, 190, 5, ProgressUiKit.GOLD)
	_found_fill.size.x = 188.0 * (float(found) / float(maxi(total, 1)))

	for branch in Balance.artifacts.get("branches", []):
		_column.add_child(_make_branch_panel(branch))

	_column.add_child(_make_ultimate_panel())


func _make_branch_panel(branch: Dictionary) -> Control:
	var branch_num := int(branch.get("branch", 0))
	var items := Balance.get_artifacts_in_branch(branch_num)
	var found := 0
	for a in items:
		if GameState.collected_artifacts.has(String(a.get("id", ""))):
			found += 1

	var complete := GameState.completed_branches.has(branch_num)
	var panel := ProgressUiKit.make_panel(
		ProgressUiKit.PANEL_BG,
		ProgressUiKit.GOLD if complete else ProgressUiKit.BORDER)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	var title_row := HBoxContainer.new()
	box.add_child(title_row)
	var name_label := ProgressUiKit.make_label(
		"%d — %s" % [branch_num, String(branch.get("name_ru", ""))], 11,
		ProgressUiKit.GOLD if complete else ProgressUiKit.MUTED)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(name_label)
	title_row.add_child(ProgressUiKit.make_label("%d/5" % found, 9, ProgressUiKit.DIM))

	var depth_range: Array = branch.get("depth_range", [0, 0])
	box.add_child(ProgressUiKit.make_label(
		"глубина %d–%d" % [int(Balance.unwrap(depth_range[0])), int(Balance.unwrap(depth_range[1]))],
		9, ProgressUiKit.DIM))

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 2)
	box.add_child(slots)
	for a in items:
		slots.add_child(_make_slot(a, branch_num))

	var detail := ProgressUiKit.make_wrapped_label(_default_hint(items), 9, ProgressUiKit.DIM)
	box.add_child(detail)
	_detail_labels[branch_num] = detail
	return panel


## Подсказка по умолчанию: первый ненайденный предмет ветки и его глубина —
## игроку нужно знать, куда копать, а не просто видеть пустой слот.
func _default_hint(items: Array) -> String:
	for a in items:
		if not GameState.collected_artifacts.has(String(a.get("id", ""))):
			var range_cells := ArtifactSpawn.depth_range(a)
			return "Следующий: пусто. Ищи на глубине %d–%d." % [range_cells.x, range_cells.y]
	return "Ветка собрана целиком."


func _make_slot(artifact: Dictionary, branch_num: int) -> Control:
	var id := String(artifact.get("id", ""))
	var name_ru := String(artifact.get("name_ru", id))
	var is_found: bool = GameState.collected_artifacts.has(id)

	var slot := Button.new()
	slot.custom_minimum_size = Vector2(SLOT, SLOT)
	slot.tooltip_text = name_ru
	slot.pressed.connect(_on_slot_pressed.bind(artifact, branch_num))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.075, 0.06, 1.0) if is_found else Color(0.05, 0.043, 0.035, 1.0)
	sb.border_color = ProgressUiKit.GOLD if is_found else ProgressUiKit.BORDER
	sb.set_border_width_all(1)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		slot.add_theme_stylebox_override(state, sb)
	slot.add_child(_make_slot_content(artifact, is_found))
	return slot


func _make_slot_content(artifact: Dictionary, is_found: bool) -> Control:
	var id := String(artifact.get("id", ""))
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not is_found:
		# Пустое место: силуэт есть, содержимого нет. Номер слота показывает,
		# какой по счёту предмет ветки тут не хватает.
		var q := ProgressUiKit.make_label("?", 14, ProgressUiKit.DIM)
		holder.add_child(q)
		return holder

	var tex := ArtifactArt.texture_for(id)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.custom_minimum_size = Vector2(ICON, ICON)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(icon)
		return holder

	var initials := ProgressUiKit.make_label(
		ArtifactArt.placeholder_initials(String(artifact.get("name_ru", id))), 12, ProgressUiKit.GOLD)
	holder.add_child(initials)
	return holder


func _on_slot_pressed(artifact: Dictionary, branch_num: int) -> void:
	var label: Label = _detail_labels.get(branch_num, null)
	if label == null:
		return
	var id := String(artifact.get("id", ""))
	var name_ru := String(artifact.get("name_ru", id))
	var range_cells := ArtifactSpawn.depth_range(artifact)
	if GameState.collected_artifacts.has(id):
		var text := "%s — найден на глубине %d–%d. +%d опыта, +%d монет." % [
			name_ru, range_cells.x, range_cells.y,
			Balance.get_artifact_find_xp(id), Balance.get_artifact_find_coins(id)]
		if bool(artifact.get("is_ultimate_set_piece", false)):
			text += " Часть ультимативного сета: %s." % \
				ArtifactArt.set_piece_name_ru(String(artifact.get("equip_slot", "")))
		label.text = text
	else:
		label.text = "Пусто. Здесь будет: %s. Глубина %d–%d." % [name_ru, range_cells.x, range_cells.y]


func _make_ultimate_panel() -> Control:
	var set_data: Dictionary = Balance.artifacts.get("ultimate_set", {})
	var pieces: Array = set_data.get("pieces", [])
	var have := 0

	var panel := ProgressUiKit.make_panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	box.add_child(ProgressUiKit.make_label("Ультимативный сет", 11, ProgressUiKit.GOLD))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	box.add_child(row)
	for piece in pieces:
		var artifact := _artifact_for_piece(String(piece))
		var id := String(artifact.get("id", ""))
		var is_found: bool = GameState.collected_artifacts.has(id)
		if is_found:
			have += 1
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(SLOT, 0)
		cell.add_theme_constant_override("separation", 1)
		row.add_child(cell)
		cell.add_child(_make_slot(artifact, int(artifact.get("branch", 0))))
		var caption := ProgressUiKit.make_label(
			ArtifactArt.set_piece_name_ru(String(piece)), 7,
			ProgressUiKit.GOLD if is_found else ProgressUiKit.DIM)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.custom_minimum_size = Vector2(SLOT, 0)
		cell.add_child(caption)

	box.add_child(ProgressUiKit.make_wrapped_label(
		"Собрано %d из 5. Без полного комплекта глубже 4000 против монстров не выстоять." % have,
		9, ProgressUiKit.MUTED if have > 0 else ProgressUiKit.DIM))

	var sockets: Array = set_data.get("glove_sockets", [])
	if not sockets.is_empty():
		var socket_names: Array = []
		for s in sockets:
			socket_names.append(String(Balance.get_mineral(String(s)).get("name_ru", s)).to_lower())
		box.add_child(ProgressUiKit.make_wrapped_label(
			"Перчатка Мироздания: пять сокетов под %s." % ", ".join(socket_names), 9, ProgressUiKit.DIM))
	return panel


func _artifact_for_piece(piece: String) -> Dictionary:
	for a in Balance.artifacts.get("artifacts", []):
		if String(a.get("equip_slot", "")) == piece:
			return a
	return {}

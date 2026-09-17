class_name RecordsPanel
extends Control
## Локальные рекорды (ГДД раздел 17 без бэкенда).
##
## ГДД перечисляет четыре топа — глубина, богатство, процент открытых
## минералов и артефактов, развитие — и тут же говорит, что лидерборды
## требуют сервера и в первую версию не входят. Поэтому здесь ровно те же
## четыре показателя, но только свои: считаются на устройстве и показываются
## как личные рекорды. Оговорка про друзей стоит прямо на экране, чтобы
## игрок не ждал чужих результатов от экрана, который их не покажет.

var _store: RecordsStore = null
var _column: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()


func setup(store: RecordsStore) -> void:
	_store = store
	if store != null and not store.records_changed.is_connected(refresh):
		store.records_changed.connect(refresh)
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
	if _column == null:
		return
	for c in _column.get_children():
		c.queue_free()

	_column.add_child(ProgressUiKit.make_label("Рекорды", 13, ProgressUiKit.GOLD))

	if _store == null:
		_column.add_child(ProgressUiKit.make_wrapped_label("Рекорды ещё не собраны.", 9))
		return

	_add_record("Максимальная глубина", "%d кл." % _store.get_max_depth(),
		"Самая глубокая точка, до которой ты добрался.")
	_add_record("Богатство", "%d монет" % _store.get_wealth(),
		"Заработано %d, вынесено наверх на %d. Доход буровой скважины добавится сюда же, когда она заработает."
			% [_store.lifetime_coins_earned, _store.lifetime_hauled_value])
	_add_record("Лучшая ходка", "%d монет" % _store.best_haul_value,
		"Самый дорогой рюкзак, поднятый на поверхность за один раз.")

	var minerals_found := _store.get_discovered_minerals_count()
	var minerals_total := _store.get_total_minerals()
	_add_record_with_bar("Открыто минералов",
		"%d / %d" % [minerals_found, minerals_total],
		float(minerals_found) / float(minerals_total), ProgressUiKit.BLUE)

	var artifacts_found: int = GameState.collected_artifacts.size()
	var artifacts_total := _store.get_total_artifacts()
	_add_record_with_bar("Открыто артефактов",
		"%d / %d" % [artifacts_found, artifacts_total],
		float(artifacts_found) / float(artifacts_total), ProgressUiKit.GOLD)

	_add_record("Развитие", str(_store.get_development_score()),
		"Уровень %d, вложено %d очков прокачки." % [GameState.level, _store.get_spent_points()])

	ProgressUiKit.make_separator(_column, 4)
	_column.add_child(ProgressUiKit.make_wrapped_label(
		"Пока это только твои рекорды — они лежат на этом устройстве. "
		+ "Общий топ и прогресс друзей появятся, когда у игры будет сервер.",
		9, ProgressUiKit.DIM))


func _add_record(title: String, value: String, note: String) -> void:
	var panel := ProgressUiKit.make_panel()
	_column.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)

	var row := HBoxContainer.new()
	box.add_child(row)
	var title_label := ProgressUiKit.make_label(title, 10, ProgressUiKit.MUTED)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	row.add_child(ProgressUiKit.make_label(value, 11, ProgressUiKit.GOLD))

	if not note.is_empty():
		box.add_child(ProgressUiKit.make_wrapped_label(note, 8, ProgressUiKit.DIM))


func _add_record_with_bar(title: String, value: String, fraction: float, color: Color) -> void:
	var panel := ProgressUiKit.make_panel()
	_column.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var row := HBoxContainer.new()
	box.add_child(row)
	var title_label := ProgressUiKit.make_label(title, 10, ProgressUiKit.MUTED)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	row.add_child(ProgressUiKit.make_label("%s  (%.0f%%)" % [value, fraction * 100.0], 10, color))

	var fill := ProgressUiKit.make_bar(box, 190, 5, color)
	fill.size.x = 188.0 * clampf(fraction, 0.0, 1.0)

class_name RecordsPanel
extends VBoxContainer
## Локальные рекорды (ГДД раздел 17 без бэкенда) — плитки «иконка + число».
##
## ГДД перечисляет четыре топа — глубина, богатство, процент открытых
## минералов и артефактов, развитие — и тут же говорит, что лидерборды
## требуют сервера и в первую версию не входят. Поэтому здесь те же показатели,
## но только свои: считаются на устройстве. Оговорка про друзей живёт в
## подсказке значка-кубка, а не абзацем на экране.
##
## Вставляется внутрь вкладки героя (HeroPanel); сама не прокручивается.

var _store: RecordsStore = null
var _grid: GridContainer


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_build()
	refresh()


func setup(store: RecordsStore) -> void:
	_store = store
	if store != null and not store.records_changed.is_connected(refresh):
		store.records_changed.connect(refresh)
	refresh()


func _build() -> void:
	# разделитель-«кубок»: линия, значок, линия
	var divider := HBoxContainer.new()
	divider.add_theme_constant_override("separation", 4)
	divider.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(divider)
	divider.add_child(_line())
	var trophy := HeroIcons.make("ui_trophy", 16.0)
	trophy.mouse_filter = Control.MOUSE_FILTER_STOP
	divider.add_child(trophy)
	divider.add_child(_line())
	Tip.bind(trophy, "Рекорды",
		"Пока это только твои рекорды — они лежат на этом устройстве. Общий топ и прогресс друзей появятся, когда у игры будет сервер.")

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_grid)


func _line() -> Control:
	var c := ColorRect.new()
	c.color = ProgressUiKit.BORDER
	c.custom_minimum_size = Vector2(0, 1)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func refresh() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
		_grid.remove_child(c)

	var depth: int = GameState.max_depth_reached
	var wealth := 0
	var earned := 0
	var hauled := 0
	var best_haul := 0
	var minerals_found := 0
	var minerals_total := 1
	var dev := 0
	var spent := 0
	if _store != null:
		depth = _store.get_max_depth()
		wealth = _store.get_wealth()
		earned = _store.lifetime_coins_earned
		hauled = _store.lifetime_hauled_value
		best_haul = _store.best_haul_value
		minerals_found = _store.get_discovered_minerals_count()
		minerals_total = _store.get_total_minerals()
		dev = _store.get_development_score()
		spent = _store.get_spent_points()
	var artifacts_found: int = GameState.collected_artifacts.size()
	var artifacts_total: int = maxi(Balance.artifacts.get("artifacts", []).size(), 1)

	_add("ui_depth", str(depth), ProgressUiKit.BLUE, -1.0,
		"Максимальная глубина", "Самая глубокая точка, до которой ты добрался.", "%d клеток" % depth)
	_add("ui_coin", HeroUi.short_num(wealth), ProgressUiKit.GOLD, -1.0,
		"Богатство", "Заработано %d монет, вынесено наверх на %d. Доход буровой скважины добавится сюда же." % [earned, hauled],
		"Всего %d" % wealth)
	_add("ui_bag", HeroUi.short_num(best_haul), ProgressUiKit.MUTED, -1.0,
		"Лучшая ходка", "Самый дорогой рюкзак, поднятый на поверхность за один раз.", "%d монет" % best_haul)
	var mf := float(minerals_found) / float(maxi(minerals_total, 1))
	_add("ui_gem", "%d%%" % int(round(mf * 100.0)), Color8(0x4F, 0xD8, 0xD0), mf,
		"Открыто минералов", "Сколько видов руды ты уже выкапывал.", "%d из %d" % [minerals_found, minerals_total])
	var af := float(artifacts_found) / float(artifacts_total)
	_add("tab_museum", "%d%%" % int(round(af * 100.0)), Color8(0xC0, 0x62, 0x3A), af,
		"Открыто артефактов", "Витрины музея, заполненные находками.", "%d из %d" % [artifacts_found, artifacts_total])
	_add("ui_trophy", str(dev), ProgressUiKit.GOLD, -1.0,
		"Развитие", "Уровень героя и вложенные в навыки очки — одним числом.",
		"Уровень %d, вложено %d очков" % [GameState.level, spent])


func _add(icon: String, value: String, color: Color, fraction: float,
		title: String, body: String, extra: String) -> void:
	var tile := HeroUi.make_tile(icon, value, color, Vector2(0, 28), fraction)
	_grid.add_child(tile)
	Tip.bind(tile, title, body, extra)

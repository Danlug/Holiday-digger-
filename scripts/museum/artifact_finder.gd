class_name ArtifactFinder
extends Node
## Связывает раскопку с артефактами: слушает dig_finished у игрока и, если
## выкопанная клетка оказалась клеткой артефакта, отдаёт находку в GameState.
##
## ПОЧЕМУ через сигнал, а не внутри player.gd: игрок уже умеет всё, что нужно
## (копает, знает координату и момент завершения), а артефакты — чужая для
## него система. Подписка снаружи оставляет player.gd нетронутым и позволяет
## выключить артефакты целиком, просто не создав этот узел.
##
## Начисление опыта, монет и награды за закрытие ветки делает
## GameState.collect_artifact — здесь только определение факта находки и
## реакция интерфейса.

signal artifact_found(artifact_id: String)

## Как близко герой должен подойти к артефакту, лежащему в пустой клетке (её
## вырвал обвал или землетрясение — копать там нечего), чтобы подобрать его.
## Тот же радиус касания, что у сундука полости (data/caves.json → chest.touch_radius).
const TOUCH_RADIUS := 1.15

var layer: ArtifactLayer = null

var _hud: Node = null
var _player: Node = null
var _touch_left := 0.0


func setup(player: Node, hud: Node) -> void:
	_player = player
	_hud = hud
	if player != null and not player.dig_finished.is_connected(_on_dig_finished):
		player.dig_finished.connect(_on_dig_finished)
	if not GameState.branch_completed.is_connected(_on_branch_completed):
		GameState.branch_completed.connect(_on_branch_completed)
	_attach_layer(player)


## Артефакты в породе рисует ArtifactLayer в ViewRoot (родитель героя) сразу над
## тайлами мира — как сундуки: свет глубины и тени ложатся на него как на породу.
func _attach_layer(player: Node) -> void:
	if layer != null or player == null or player.get_parent() == null:
		return
	var view_root := player.get_parent()
	layer = ArtifactLayer.new()
	layer.name = "ArtifactLayer"
	layer.player = player
	layer.world = player.get("world")
	var host := view_root.get_parent()
	layer.fog = host.get("fog") if host != null else null
	view_root.add_child(layer)
	var wv := view_root.get_node_or_null("WorldView")
	if wv != null:
		view_root.move_child(layer, wv.get_index() + 1)


## Проверка клетки без раскопки — нужна витрине и тестам.
func artifact_at(x: int, y: int) -> String:
	return ArtifactSpawn.artifact_id_at(
		x, y, GameState.world_seed,
		Balance.artifacts.get("artifacts", []),
		GameState.collected_artifacts, GameState.world_ref)


## Артефакт в пустой клетке подбирается касанием: проверка 5 раз в секунду.
func _process(delta: float) -> void:
	_touch_left -= delta
	if _touch_left > 0.0:
		return
	_touch_left = 0.2
	var world := GameState.world_ref
	if _player == null or world == null or not ("x" in _player) or world.era == "grandpa":
		return   # во флешбэке деда копает дед — находки внука не трогаем
	var hero := Vector2(float(_player.x), float(_player.y))
	for a: Dictionary in Balance.artifacts.get("artifacts", []):
		if GameState.collected_artifacts.has(String(a.get("id", ""))):
			continue
		var c := ArtifactSpawn.cell_of(a, GameState.world_seed, world)
		if absf(float(c.y) - hero.y) > 3.0 or world.get_tile(c.x, c.y) != TileTypes.Type.EMPTY:
			continue
		if hero.distance_to(Vector2(c.x + 0.5, c.y + 0.5)) <= TOUCH_RADIUS:
			claim_at(c.x, c.y)


## Выдать находку из клетки (x, y), если она там есть. Возвращает id найденного
## артефакта или "". Вынесено отдельно от обработчика сигнала, чтобы тест мог
## вызвать то же самое без физики и таймеров копки.
func claim_at(x: int, y: int) -> String:
	var id := artifact_at(x, y)
	if id.is_empty():
		return ""
	var was_first := GameState.collected_artifacts.is_empty()
	# Глубину пишем до выдачи: подписчики artifact_collected (музей) уже должны её видеть.
	HeroData.record_find(id, y)
	GameState.collect_artifact(id)
	_announce(id, was_first)
	artifact_found.emit(id)
	return id


func _on_dig_finished(x: int, y: int, _tile_type: int, _mineral_id: String, _was_loot: bool, _coins: int) -> void:
	claim_at(x, y)


## «Сочный» момент находки: карточка-вспышка с иконкой, звук, вибро и искры
## на герое. Длинного текста нет — название и описание смотрят в музее.
func _announce(artifact_id: String, was_first: bool) -> void:
	Fx.burst("levelup", _hero_pos())
	# ГДД п.9: на первой же находке игроку показывают коллекцию — иначе он не
	# понимает, что именно только что открыл. Музей откроется, когда карточка уйдёт.
	ArtifactCard.show_find(artifact_id, was_first)


func _on_branch_completed(branch_num: int) -> void:
	Fx.burst("levelup", _hero_pos(), 1.6)
	# GameState.collect_artifact шлёт branch_completed ещё до возврата в claim_at:
	# откладываем, чтобы карточка ветки встала в очередь ПОСЛЕ карточки предмета.
	ArtifactCard.show_branch.call_deferred(branch_num)


func _hero_pos() -> Vector2:
	if _player is Node2D:
		return (_player as Node2D).global_position
	return Vector2.ZERO

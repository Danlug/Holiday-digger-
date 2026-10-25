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

var _hud: Node = null
var _player: Node = null


func setup(player: Node, hud: Node) -> void:
	_player = player
	_hud = hud
	if player != null and not player.dig_finished.is_connected(_on_dig_finished):
		player.dig_finished.connect(_on_dig_finished)
	if not GameState.branch_completed.is_connected(_on_branch_completed):
		GameState.branch_completed.connect(_on_branch_completed)


## Проверка клетки без раскопки — нужна витрине и тестам.
func artifact_at(x: int, y: int) -> String:
	return ArtifactSpawn.artifact_id_at(
		x, y, GameState.world_seed,
		Balance.artifacts.get("artifacts", []),
		GameState.collected_artifacts)


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

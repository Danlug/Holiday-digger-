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
	GameState.collect_artifact(id)
	_announce(id, was_first)
	artifact_found.emit(id)
	return id


func _on_dig_finished(x: int, y: int, _tile_type: int, _mineral_id: String, _was_loot: bool, _coins: int) -> void:
	claim_at(x, y)


func _announce(artifact_id: String, was_first: bool) -> void:
	var a := Balance.get_artifact(artifact_id)
	var name_ru := String(a.get("name_ru", artifact_id))
	var xp := Balance.get_artifact_find_xp(artifact_id)
	var coins := Balance.get_artifact_find_coins(artifact_id)
	if _hud != null and _hud.has_method("toast"):
		_hud.toast("Артефакт: %s. +%d опыта, +%d монет. Встал в музей." % [name_ru, xp, coins], 4.5)
	# ГДД п.9: на первой же находке игроку показывают коллекцию из пяти
	# веток — иначе он не понимает, что именно только что открыл.
	if was_first:
		ProgressScreen.open("museum")


func _on_branch_completed(branch_num: int) -> void:
	if _hud == null or not _hud.has_method("toast"):
		return
	var branch_name := "ветка %d" % branch_num
	for b in Balance.artifacts.get("branches", []):
		if int(b.get("branch", -1)) == branch_num:
			branch_name = String(b.get("name_ru", branch_name))
			break
	_hud.toast("Ветка «%s» собрана целиком. Награда в кошельке." % branch_name, 4.5)

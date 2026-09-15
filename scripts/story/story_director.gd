class_name StoryDirector
extends Node
## Режиссёр: единственное место, которое решает, какая катсцена и когда
## играет. Подключается к main.gd одной строкой и дальше находит игрока, мир и
## HUD сам.
##
## Почему всё в одном узле: сюжетные триггеры по природе своей сквозные —
## "после смерти", "при первом истощении", "когда лопата упёрлась в
## фундамент". Разложи их по местам срабатывания, и порядок сцен окажется
## размазан по игроку, миру и интерфейсу, а собрать его обратно глазами будет
## нельзя. Здесь порядок читается сверху вниз одним экраном (_check_triggers).
##
## Подключение чужих систем (дом и магазин делают другие агенты) — тоже по
## одной строке, см. поля house/shop ниже. Пока их нет, сцены играют целиком:
## люк и отдел допингов остаются сюжетным фактом и сюжетным флагом, который
## эти системы прочитают, когда появятся.

const SLEEP_LESSON_STAMINA := 8.0   # порог "первого истощения" в процентах
const MANUAL_DIGS_BEFORE_AUTODIG := 3

## Чужие системы. Подключаются одной строкой из main.gd, когда появятся:
##   $StoryDirector.house = $House
##   $StoryDirector.shop = $Shop
var house: Node = null
var shop: Node = null

var player: Node = null
var world: WorldGen = null
var hud: Control = null

var cutscene: CutscenePlayer
var auto_dig: AutoDigTutorial

var _playing: bool = false
var _manual_digs: int = 0
var _gauges: Control = null
var _booted: bool = false
var _resetting: bool = false


func _ready() -> void:
	# Отложенный старт: main.gd создаёт игрока, HUD и мир в своём _ready, и на
	# момент add_child части из них может ещё не быть.
	call_deferred("boot")


func boot() -> void:
	if _booted:
		return
	_booted = true

	StoryText.load_locale(_pick_locale())
	StoryData.ensure_loaded()
	StoryState.load_from_disk()

	_find_game_nodes()

	cutscene = CutscenePlayer.new()
	cutscene.name = "CutscenePlayer"
	cutscene.finished.connect(_on_cutscene_finished)
	add_child(cutscene)

	auto_dig = AutoDigTutorial.new()
	auto_dig.name = "AutoDig"
	auto_dig.midpoint_reached.connect(_on_autodig_midpoint)
	auto_dig.finished.connect(_on_autodig_finished)
	add_child(auto_dig)

	_connect_signals()
	_find_gauges()
	_queue_intro_if_new_game()
	_play_next_if_idle()


## Локаль берём системную, но файла перевода может ещё не быть — StoryText
## сам откатится на русский, поэтому проверять здесь нечего.
func _pick_locale() -> String:
	var loc := OS.get_locale_language()
	return loc if not loc.is_empty() else StoryText.DEFAULT_LOCALE


func _find_game_nodes() -> void:
	var parent := get_parent()
	if parent == null:
		return
	if player == null and "player" in parent:
		player = parent.player
	if world == null and "world" in parent:
		world = parent.world
	if hud == null and "hud" in parent:
		hud = parent.hud


## Для тестов и для случая, когда сцену запускают отдельно от main.gd.
func setup(p_player: Node, p_world: WorldGen, p_hud: Control) -> void:
	player = p_player
	world = p_world
	hud = p_hud


func _connect_signals() -> void:
	if player != null:
		if player.has_signal("dig_finished"):
			player.dig_finished.connect(_on_dig_finished)
		if player.has_signal("dig_started"):
			player.dig_started.connect(_on_dig_started)
		if player.has_signal("tool_auto_switched"):
			player.tool_auto_switched.connect(_on_tool_auto_switched)
	# Полный сброс прогресса (кнопка "Сброс" в нижней полосе) виден отсюда
	# только по одному признаку: максимальная глубина откатилась к нулю — в
	# обычной игре она умеет только расти. Свои сигналы GameState не отдаёт, а
	# трогать чужой код ради этого нельзя, см. границы задачи.
	GameState.max_depth_changed.connect(_on_max_depth_changed)


## Три полоски выживания до сцены смерти не показываются вовсе: понятие
## усталости вводится только после неё (ГДД раздел 9). Ищем их у HUD через
## заливку HP — это временная связка, пока в HUD нет своего set_bars_visible.
func _find_gauges() -> void:
	if hud == null or not ("_hp_fill" in hud):
		return
	var fill = hud._hp_fill
	if fill == null:
		return
	var box = fill.get_parent()
	for _i in range(3):
		if box == null:
			return
		box = box.get_parent()
	_gauges = box as Control


func _queue_intro_if_new_game() -> void:
	# Интро — два ролика подряд, дед и внук; порядок задан ГДД разделом 2.
	StoryState.enqueue("intro_grandpa")
	StoryState.enqueue("intro_boy")


# ---------------------------------------------------------------------------
# Основной цикл: триггеры и очередь
# ---------------------------------------------------------------------------

func _process(_dt: float) -> void:
	if not _booted:
		return
	_apply_no_fatigue_period()
	if _playing:
		return
	# Пока крутится автокопка, новые триггеры не собираем: ролик и так держит
	# управление. Но если он на паузе ради находки — очередь двигать нужно.
	if auto_dig != null and auto_dig.running and not auto_dig.paused:
		return
	_check_triggers()
	_play_next_if_idle()


## До сцены смерти голод и усталость не тратятся (ГДД раздел 9: "первые 4
## уровня копаются вообще без усталости"), и полосок на экране нет. Проще
## всего это сделать здесь: GameState тикает расход всегда, а править чужой
## файл ради обучающего периода нельзя.
func _apply_no_fatigue_period() -> void:
	var introduced := StoryState.has_flag("bars_introduced")
	if _gauges != null and _gauges.visible != introduced:
		_gauges.visible = introduced
	if introduced:
		return
	if GameState.stamina < 100.0:
		GameState.set_stamina(100.0)
	if GameState.hunger < 100.0:
		GameState.set_hunger(100.0)


func _check_triggers() -> void:
	# Порядок важен: сверху вниз он совпадает с порядком онбординга из ГДД.
	if not StoryState.has_flag("intro_seen"):
		return

	if not StoryState.is_seen("autodig_start") and _manual_digs >= MANUAL_DIGS_BEFORE_AUTODIG:
		StoryState.enqueue("autodig_start")
		return

	if StoryState.is_seen("death"):
		if not StoryState.is_seen("backpack"):
			StoryState.enqueue("backpack")
			return
		if not StoryState.is_seen("robert"):
			StoryState.enqueue("robert")
			return

	if StoryState.has_flag("bars_introduced"):
		if not StoryState.is_seen("sleep_lesson_1") and GameState.stamina <= SLEEP_LESSON_STAMINA:
			StoryState.enqueue("sleep_lesson_1")
			return
		if StoryState.is_seen("sleep_lesson_1") and not StoryState.is_seen("sleep_lesson_2") \
				and GameState.stamina <= SLEEP_LESSON_STAMINA and _player_underground():
			StoryState.enqueue("sleep_lesson_2")
			return


func _player_underground() -> bool:
	return player != null and player.cell_y() > 0


func _play_next_if_idle() -> void:
	if _playing or _resetting or cutscene == null:
		return
	if auto_dig != null and auto_dig.running and not auto_dig.paused:
		return
	var next := StoryState.next_queued()
	if next.is_empty():
		return
	play(next)


## Запускает катсцену принудительно (из очереди, из теста или из чужой
## системы). Очередь и флаги гарантируют, что просмотренная сцена сама не
## запустится второй раз.
func play(id: String) -> void:
	if not StoryData.has_scene(id):
		push_warning("StoryDirector: нет сцены %s" % id)
		StoryState.mark_seen(id)
		return
	_playing = true
	_take_control()
	cutscene.play(id)


func _on_cutscene_finished(id: String) -> void:
	# Эффекты применяются здесь, а не в кадрах, ровно по одной причине: сцену
	# можно пропустить кнопкой и можно закрыть игру посередине. Что бы игрок
	# ни сделал, кирка выдаётся ровно один раз и ровно тогда, когда сцена
	# признана показанной.
	_apply_effects(StoryData.effects(id))
	StoryState.mark_seen(id)
	_playing = false
	_after_scene(id)
	_play_next_if_idle()


## Сюжетные последствия, которые нельзя выразить данными: запуск следующего
## этапа обучения и передача управления другим системам.
func _after_scene(id: String) -> void:
	match id:
		"autodig_start":
			if world != null and player != null:
				# HUD во время автокопки остаётся на экране (прячется он только
				# в сцене смерти, ГДД раздел 9) — но ввод отключён, иначе
				# джойстик перетягивал бы героя у скрипта.
				_take_control(false)
				auto_dig.begin(player, world)
			else:
				_release_control()
		"dud_treasure":
			if auto_dig != null and auto_dig.running:
				_take_control(false)
				auto_dig.resume()
			else:
				_release_control()
		_:
			_release_control()


func _on_autodig_midpoint() -> void:
	# Никчёмный клад находится по ходу автокопки (ГДД раздел 9, пункт 4),
	# поэтому ролик встаёт на паузу ровно посередине.
	auto_dig.pause()
	_playing = false
	StoryState.enqueue("dud_treasure")
	_play_next_if_idle()


func _on_autodig_finished() -> void:
	_release_control()
	StoryState.enqueue("autodig_done")
	_play_next_if_idle()


# ---------------------------------------------------------------------------
# Перехват управления на время сцены
# ---------------------------------------------------------------------------

func _take_control(hide_hud: bool = true) -> void:
	if player != null:
		player.release_control()
		player.digging = null
		player.frozen = true
	if hud != null:
		# В сцене смерти интерфейс исчезает полностью (ГДД раздел 9), в
		# автокопке остаётся — но ввод глушим всегда: джойстик и удержание
		# слушают _input мимо Control-фильтров, и тап по катсцене иначе
		# одновременно вёл бы героя под ней.
		hud.visible = not hide_hud
		hud.set_process_input(false)


func _release_control() -> void:
	if player != null:
		player.frozen = false
		player.release_control()
	if hud != null:
		hud.visible = true
		hud.set_process_input(true)


# ---------------------------------------------------------------------------
# Эффекты сцены
# ---------------------------------------------------------------------------

func _apply_effects(effects: Array) -> void:
	for e in effects:
		match String(e.get("do", "")):
			"flag":
				StoryState.set_flag(String(e.get("id", "")))
			"tool":
				# Именно найденный, а не купленный: владение инструментом
				# проверяется в GameState.set_current_tool, и без grant_tool
				# кирка из мастерской упёрлась бы в кассу магазина.
				var tool_id := String(e.get("id", ""))
				GameState.grant_tool(tool_id)
				GameState.set_current_tool(tool_id)
			"coins":
				GameState.add_coins(int(e.get("n", 0)))
			"dollars":
				GameState.add_dollars(int(e.get("n", 0)))
			"xp":
				GameState.add_xp(int(e.get("n", 0)))
			"artifact":
				_collect_scripted_artifact(String(e.get("id", "")))
			"sleep":
				GameState.sleep(float(e.get("hours", 8)))
			"stamina":
				GameState.set_stamina(float(e.get("n", 100)))
			"hunger":
				GameState.set_hunger(GameState.hunger + float(e.get("n", 0)))
			"teleport_home":
				if player != null:
					player.teleport_home()
			"toast":
				if hud != null:
					hud.toast(StoryText.get_text(String(e.get("text", ""))), float(e.get("sec", 3.0)))
			"hook":
				_call_hook(String(e.get("target", "")), String(e.get("method", "")))


## Никчёмный клад даёт ровно то, что записано в ГДД разделе 9: 50 монет и 5
## премиум-валюты. В data/artifacts.json у него стоит общая для всех находок
## награда (750 монет) — для предмета, вся суть которого в разочаровании, это
## мимо. Значение в чужом файле не трогаем, а награду берём из ГДД; расхождение
## вынесено в отчёт.
func _collect_scripted_artifact(artifact_id: String) -> void:
	if artifact_id.is_empty() or GameState.collected_artifacts.has(artifact_id):
		return
	GameState.collected_artifacts.append(artifact_id)
	GameState.add_xp(Balance.get_artifact_find_xp(artifact_id))
	GameState.artifact_collected.emit(artifact_id)


func _call_hook(target: String, method: String) -> void:
	var node: Node = house if target == "house" else (shop if target == "shop" else null)
	if node != null and node.has_method(method):
		node.call(method)


# ---------------------------------------------------------------------------
# Сигналы игрока
# ---------------------------------------------------------------------------

func _on_dig_finished(_x: int, _y: int, _type: int, _mineral_id: String, _was_loot: bool, _coins: int) -> void:
	_manual_digs += 1


## Сцена смерти (ГДД раздел 9, пункт 7): "копнуть один раз под себя". Ловим
## именно копку строго под ногами и только после мастерской — до кирки герою
## ещё нечем повторить путь деда.
func _on_dig_started(x: int, y: int, _type: int) -> void:
	if not StoryState.is_seen("workshop") or StoryState.is_seen("death"):
		return
	if player == null:
		return
	if x == player.cell_x() and y == player.cell_y() + 1:
		StoryState.enqueue("death")


## Кирка сейчас выдаётся игроком автоматически при первом ударе лопатой о
## фундамент — это заглушка, оставшаяся от времён без сюжета. Перехватываем:
## инструмент возвращаем, сцену мастерской играем, и кирку выдаёт уже она
## (эффект tool). Так момент выдачи один и тот же и при просмотре, и при
## пропуске, и после выхода из игры посреди ролика.
func _on_tool_auto_switched(tool_id: String) -> void:
	if tool_id != "rusty_pickaxe" or StoryState.is_seen("workshop"):
		return
	GameState.set_current_tool("shovel")
	StoryState.enqueue("workshop")
	_play_next_if_idle()


func _on_max_depth_changed(depth: int) -> void:
	if depth != 0:
		return
	# Игрок нажал "Сброс": сюжет тоже начинается заново, иначе новый огород
	# достаётся ему без интро и с уже выданной киркой.
	# Прерываем, а не пропускаем: пропуск доиграл бы сцену и выдал её награды
	# ровно в тот момент, когда игрок попросил начать всё с нуля.
	_resetting = true
	if cutscene != null:
		cutscene.abort()
	if auto_dig != null:
		auto_dig.abort()
	StoryState.clear_all()
	_manual_digs = 0
	_playing = false
	_release_control()
	_resetting = false
	_queue_intro_if_new_game()
	_play_next_if_idle()

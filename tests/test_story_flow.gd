extends Node
## test_story_flow.gd — проверка поведения сюжета вживую, со сценой и кадрами.
##
## Запуск:
##   godot --headless --path . res://tests/test_story_flow.tscn
##
## Проверяется ровно то, что обещано в задании:
##   - катсцена проигрывается и завершается;
##   - флаг "просмотрено" сохраняется, второй раз сцена не показывается;
##   - выход из игры посреди ролика ничего не ломает: сцена вернётся в
##     очередь и доиграется, а её награда выдастся ровно один раз;
##   - обучение не зацикливается, автокопка всегда доходит до конца.

var failures := 0
var total := 0

var world: WorldGen
var player: Node2D
var director: StoryDirector


func _ready() -> void:
	_run()


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name,
		("  " + detail) if not ok and not detail.is_empty() else ""])


func _frame() -> void:
	await get_tree().process_frame


func _run() -> void:
	print("=== test_story_flow.gd ===")

	# Чистый лист: тест не должен зависеть от сейва предыдущего прогона.
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	GameState.reset_progress()

	world = WorldGen.new(20240915)
	player = preload("res://scripts/player/player.gd").new()
	player.world = world
	add_child(player)

	director = _spawn_director()
	await _frame()

	await _test_intro_plays_and_finishes()
	await _test_not_shown_twice()
	await _test_survives_quit_midscene()
	await _test_autodig_terminates()
	await _test_tutorial_does_not_loop()
	await _test_death_trigger_and_bars()
	_test_tutorial_quests()

	_print_total()


func _print_total() -> void:
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _spawn_director() -> StoryDirector:
	var d := StoryDirector.new()
	d.setup(player, world, null)
	add_child(d)
	return d


## Прокручивает все накопившиеся сцены пропуском. Ограничение по кругам —
## страховка от зацикливания: если очередь сама себя пополняет, тест должен
## упасть, а не висеть.
func _drain(d: StoryDirector, limit: int = 40) -> int:
	var rounds := 0
	while rounds < limit:
		if d.cutscene != null and d.cutscene.is_playing:
			d.cutscene.skip()
		elif GameState.story_queue.is_empty():
			break
		rounds += 1
		await _frame()
	return rounds


# ---------------------------------------------------------------------------

func _test_intro_plays_and_finishes() -> void:
	check("интро деда встало в очередь на новой игре", GameState.story_queue.has("intro_grandpa"))
	check("катсцена запустилась сама", director.cutscene.is_playing)
	check("на время катсцены герой заморожен", player.frozen)

	director.cutscene.skip()
	await _frame()
	check("сцена деда помечена просмотренной", StoryState.is_seen("intro_grandpa"))
	check("следом пошло интро внука", director.cutscene.is_playing and director.cutscene.scene_id == "intro_boy")

	director.cutscene.skip()
	await _frame()
	check("интро дошло до конца", StoryState.is_seen("intro_boy"))
	check("эффект сцены применился и при пропуске", StoryState.has_flag("intro_seen"))
	check("очередь опустела", GameState.story_queue.is_empty())
	check("управление вернулось игроку", not player.frozen)


func _test_not_shown_twice() -> void:
	director._queue_intro_if_new_game()
	check("просмотренное интро в очередь не возвращается", GameState.story_queue.is_empty())

	check("состояние сюжета записано на диск", FileAccess.file_exists(StoryState.PATH))
	GameState.story_flags = {}
	GameState.story_seen = []
	StoryState.load_from_disk()
	check("после перезагрузки сцена всё ещё просмотрена", StoryState.is_seen("intro_grandpa"))
	check("после перезагрузки флаг на месте", StoryState.has_flag("intro_seen"))
	await _frame()


## Выход из игры посреди катсцены: узел сюжета умирает вместе со сценой, но
## сцена осталась в очереди и её награда ещё не выдана.
func _test_survives_quit_midscene() -> void:
	StoryState.enqueue("workshop")
	await _frame()
	check("мастерская запустилась", director.cutscene.is_playing and director.cutscene.scene_id == "workshop")

	director.cutscene.abort()
	director.queue_free()
	await _frame()
	check("прерванная сцена не считается просмотренной", not StoryState.is_seen("workshop"))
	check("прерванная сцена осталась в очереди", GameState.story_queue.has("workshop"))
	check("кирку прерванная сцена не выдала", GameState.current_tool == "shovel")

	director = _spawn_director()
	await _frame()
	await _frame()
	check("после перезапуска сцена играет снова",
		director.cutscene.is_playing and director.cutscene.scene_id == "workshop")

	director.cutscene.skip()
	await _frame()
	check("кирка выдана после показа сцены", GameState.current_tool == "rusty_pickaxe")
	check("кирка есть в собственности", GameState.owns_tool("rusty_pickaxe"))
	check("сцена ушла из очереди", not GameState.story_queue.has("workshop"))
	await _drain(director)


func _test_autodig_terminates() -> void:
	var coins_before := GameState.coins
	director.auto_dig.begin(player, world)
	check("автокопке нашлось что копать", director.auto_dig.running)

	var guard := 0
	while director.auto_dig.running and guard < 400:
		if director.cutscene != null and director.cutscene.is_playing:
			director.cutscene.skip()
			await _frame()
		elif director.auto_dig.paused:
			director.auto_dig.resume()
		else:
			# Шаг крупнее клетки: тест не должен идти столько же, сколько ролик.
			director.auto_dig._process(0.35)
		guard += 1

	check("автокопка завершилась и не зациклилась", not director.auto_dig.running, "кругов: %d" % guard)

	var left := 0
	for y in range(1, AutoDigTutorial.ROWS + 1):
		for x in range(WorldGen.GARDEN_X_MIN, WorldGen.WIDTH):
			if TileTypes.can_dig_with_shovel(world.get_tile(x, y)):
				left += 1
	check("огород выбран на три уровня", left == 0, "осталось клеток: %d" % left)

	await _drain(director)
	check("управление после автокопки и итогового ролика отдано игроку", not player.frozen)
	check("никчёмный клад нашёлся по ходу", GameState.collected_artifacts.has("antiquity_1"))
	check("клад дал ровно 50 монет (ГДД раздел 9)", GameState.coins - coins_before == 50,
		"получено: %d" % (GameState.coins - coins_before))
	check("клад дал 5 премиум-валюты", GameState.dollars >= 5)
	check("итог автокопки показан", StoryState.is_seen("autodig_done"))


func _test_tutorial_does_not_loop() -> void:
	StoryState.mark_seen("autodig_start")
	director._manual_digs = 99
	GameState.story_queue.clear()
	director._check_triggers()
	check("показанная автокопка второй раз в очередь не встаёт",
		not GameState.story_queue.has("autodig_start"))

	# И наоборот: сцены, которые по ГДД идут после смерти, до неё не лезут.
	check("до смерти ранец не предлагается", not GameState.story_queue.has("backpack"))


func _test_death_trigger_and_bars() -> void:
	GameState.add_item("iron_ore", 3)
	GameState.set_stamina(50.0)
	director._apply_no_fatigue_period()
	check("до сцены смерти усталость не тратится", is_equal_approx(GameState.stamina, 100.0))

	# Сцену смерти зовёт ПРОБИТИЕ ФУНДАМЕНТА (решение владельца), а не копка
	# под собой: фундамент пробивают ровно один раз и только киркой, а мимо
	# копки под собой игрок мог пройти боком и не увидеть сцену вовсе.
	GameState.story_queue.clear()
	StoryState.set_flag("gold_taken")
	director._on_dig_finished(20, 5, TileTypes.Type.FOUNDATION, "", false, 0)
	check("пробитие фундамента зовёт сцену смерти", GameState.story_queue.has("death"))
	check("флаг пробитого фундамента выставлен", StoryState.has_flag("foundation_broken"))
	director._on_dig_finished(21, 5, TileTypes.Type.FOUNDATION, "", false, 0)
	check("второй раз та же сцена в очередь не встаёт", GameState.story_queue.count("death") == 1)
	# Обычная копка сцену смерти не зовёт — иначе она играла бы на первой земле.
	GameState.story_queue.clear()
	StoryState.mark_seen("death")
	director._on_dig_finished(22, 6, TileTypes.Type.DIRT, "", false, 0)
	check("обычная клетка сцену смерти не зовёт", not GameState.story_queue.has("death"))
	GameState.story_seen.erase("death")
	GameState.story_queue.append("death")

	var rounds := await _drain(director)
	check("очередь после смерти доигралась до конца", rounds < 40, "кругов: %d" % rounds)
	check("сцена смерти показана", StoryState.is_seen("death"))
	check("инвентарь после сцены смерти уцелел (единственный раз, ГДД раздел 9)",
		GameState.get_item_count("iron_ore") == 3)
	check("полоски выживания введены", StoryState.has_flag("bars_introduced"))
	check("ранец выдан следом за смертью", StoryState.is_seen("backpack"))
	check("Роберт построил люк", StoryState.has_flag("hatch_built"))

	GameState.set_stamina(50.0)
	director._apply_no_fatigue_period()
	check("после смерти усталость снова тратится", is_equal_approx(GameState.stamina, 50.0))

	_test_bars_for_old_saves()


## Сохранения, снятые до появления флага bars_introduced, о нём не знают: у
## игрока обучение давно позади, а после обновления полоски просто исчезли бы
## посреди игры. Признак «обучение пройдено» — пробитый фундамент или глубина
## ниже его уровня.
func _test_bars_for_old_saves() -> void:
	var saved_depth := GameState.max_depth_reached
	GameState.story_flags.erase("bars_introduced")
	GameState.story_flags.erase("death_seen")
	GameState.story_flags.erase("foundation_broken")
	GameState.story_seen.erase("death")
	GameState.max_depth_reached = 0
	check("на самом обучении полосок всё ещё нет", not director._bars_introduced())

	GameState.max_depth_reached = 40
	check("старый сейв с глубиной 40 полоски возвращает", director._bars_introduced())
	check("найденное «уже пройдено» записано флагом", StoryState.has_flag("bars_introduced"))

	GameState.story_flags.erase("bars_introduced")
	GameState.max_depth_reached = 0
	StoryState.set_flag("foundation_broken")
	check("пробитый фундамент полоски возвращает", director._bars_introduced())

	GameState.max_depth_reached = saved_depth
	StoryState.set_flag("bars_introduced")


## Обучающие задания (ГДД п.9, порядок владельца): золото — фундамент —
## продать — заказать еду. Проверяем состояние, а не события: игрок может
## выйти посреди задания, и после загрузки оно обязано найтись само.
func _test_tutorial_quests() -> void:
	StoryState.clear_all()
	GameState.inventory.clear()
	GameState.coins = 0
	GameState.house_food_at_door.clear()

	director._update_quests()
	check("до мастерской заданий нет", director._objective.is_empty())

	StoryState.mark_seen("workshop")
	director._update_quests()
	var gold_cells: Array = world.scripted_loot_cells()
	check("сценарного золота ровно пять", gold_cells.size() == 5)
	check("после мастерской задание — золото", director._objective.contains("золото"))
	check("подсвечены все пять клеток", director._quest_cells.size() == 5)
	check("задание считает оставшиеся самородки", director._objective.contains("5"))

	world.dig_cell(gold_cells[0].x, gold_cells[0].y)
	director._update_quests()
	check("выкопанный самородок из подсветки уходит", director._quest_cells.size() == 4)
	check("задание не закрыто, пока золото не выбрано", not StoryState.has_flag("gold_taken"))

	for i in range(1, gold_cells.size()):
		world.dig_cell(gold_cells[i].x, gold_cells[i].y)
	director._update_quests()
	check("всё золото выбрано — задание закрыто", StoryState.has_flag("gold_taken"))
	check("подсветка снята", director._quest_cells.is_empty())
	check("следующее задание — фундамент", director._objective.contains("фундамент"))

	StoryState.set_flag("foundation_broken")
	StoryState.mark_seen("death")
	GameState.add_item("gold", 5)
	director._update_quests()
	check("после смерти задание — продать золото", director._objective.contains("продай"))
	check("с золотом в рюкзаке продажа не засчитана", not StoryState.has_flag("gold_sold"))

	# Выбросить — не значит продать: пустой рюкзак без денег задание не закрывает.
	GameState.inventory.clear()
	director._update_quests()
	check("выброшенное золото за продажу не считается", not StoryState.has_flag("gold_sold"))

	GameState.coins = 250
	director._update_quests()
	check("проданное золото закрывает задание", StoryState.has_flag("gold_sold"))
	check("следующее задание — еда", director._objective.contains("еду"))

	GameState.house_food_at_door["food_soup"] = 1
	director._update_quests()
	check("заказанная еда закрывает обучение", StoryState.has_flag("food_ordered"))
	check("заданий больше нет", director._objective.is_empty())

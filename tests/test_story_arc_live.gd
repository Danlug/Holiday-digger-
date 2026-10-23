extends Node
## test_story_arc_live.gd — сюжет после старта в НАСТОЯЩЕЙ игре (main.tscn): звонок
## бабки играет сам, когда герой вышел на поверхность; могила в мире зовёт
## дневник; HUD прячется на сцене и возвращается; герой не застревает и остаётся
## там, где был.
##
## Запуск: godot --headless --path . res://tests/test_story_arc_live.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name,
		("  " + detail) if not ok and not detail.is_empty() else ""])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== test_story_arc_live.gd ===")
	# Чужой сейв (user:// общий на запуск) подсунул бы глубину и артефакты: main
	# читает его при старте. Начинаем с пустого.
	for f in ["user://save.json", "user://records.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	GameState.reset_progress()
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure",
			"workshop", "death", "backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2"]:
		StoryState.mark_seen(id)
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "gold_sold", "food_ordered"]:
		StoryState.set_flag(f)

	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(8)
	var director: StoryDirector = main.find_child("StoryDirector", true, false)
	var player: Node2D = main.player
	var hud: Control = main.hud
	director.arc_calm_wait_ms = 3000

	check("режиссёр создал могилу в мире", director.grave != null and director.grave.get_parent() == main.view_root)
	check("могила стоит перед героем по глубине отрисовки (позади него)",
		director.grave.get_index() < player.get_index())

	# Первая вылазка: герой вышел наверх, глубина набрана.
	player.x = 17.5
	player.y = 0.5
	GameState.max_depth_reached = 15
	var guard := 0
	while not director.cutscene.is_playing and guard < 240:
		await _frames(1)
		guard += 1
	check("звонок бабки сыграл сам, когда герой стоит на земле",
		director.cutscene.is_playing and director.cutscene.scene_id == "grave_call", "кадров ждали: %d" % guard)
	check("на сцене HUD спрятан, герой заморожен", not hud.visible and player.frozen)
	check("настоящий герой спрятан под актёра сцены", not main.find_child("CharacterView", true, false).visible)
	director.cutscene.skip()
	await _frames(3)
	check("после сцены HUD вернулся", hud.visible)
	check("после сцены герой разморожен", not player.frozen)
	check("после сцены герой на месте (не отброшен на старт обучения)", absf(player.x - 17.5) < 0.6 and player.y < 1.0,
		"(%.1f; %.1f)" % [player.x, player.y])
	check("после сцены спрайт героя снова виден", main.find_child("CharacterView", true, false).visible)

	# Могила: подошёл — кнопка, нажал — сцена тетради, потом дневник.
	player.x = 14.0
	player.y = 0.5
	await _frames(4)
	var btn: Button = director.grave.get_node("GraveHotspot/GraveBtn")
	check("у могилы всплыла кнопка", btn.visible)
	player.x = 17.5
	await _frames(3)
	check("отошёл — кнопка гаснет", not btn.visible)
	player.x = 14.0
	await _frames(3)
	btn.pressed.emit()
	guard = 0
	while not director.cutscene.is_playing and guard < 240:
		await _frames(1)
		guard += 1
	check("нажатие на могилу запускает сцену тетради",
		director.cutscene.is_playing and director.cutscene.scene_id == "diary_first")
	director.cutscene.skip()
	await _frames(4)
	check("после тетради открыт экран дневника", director.diary_ui.is_open)
	check("на дневнике кнопка могилы не торчит поверх", not btn.visible)
	# Листаем дневник кнопками: вперёд до упора и назад, ничего не падает.
	var start_page := director.diary_ui.current
	director.diary_ui._next.pressed.emit()
	director.diary_ui._next.pressed.emit()
	await _frames(2)
	check("дневник листается вперёд", director.diary_ui.current == mini(start_page + 2, StoryDiary.page_count() - 1))
	for i in 20:
		director.diary_ui._next.pressed.emit()
	check("вперёд дальше последней страницы не пускает", director.diary_ui.current == StoryDiary.page_count() - 1)
	for i in 20:
		director.diary_ui._prev.pressed.emit()
	check("назад дальше первой не пускает", director.diary_ui.current == 0)
	director.diary_ui._goto(StoryDiary.page_count() - 1, true)
	check("закрытая страница не засчитывается прочитанной", not StoryDiary.is_read("last"))
	director.diary_ui.close_diary()
	await _frames(3)
	check("дневник закрыт, управление вернулось", not director.diary_ui.is_open and not player.frozen and hud.visible)

	# Сцена глубины: герой глубоко под землёй, остаётся там же.
	player.x = 20.5
	player.y = 120.5
	main.world.dig_cell(20, 120)
	GameState.max_depth_reached = 130
	director.arc_calm_wait_ms = 0
	guard = 0
	while not director.cutscene.is_playing and guard < 120:
		await _frames(1)
		guard += 1
	check("сцена сотни играет на глубине", director.cutscene.is_playing and director.cutscene.scene_id == "depth_100")
	var y_in: float = player.y
	director.cutscene.skip()
	await _frames(3)
	check("после сцены глубины герой остался под землёй, а не на старте",
		player.y > 100.0 and absf(player.y - y_in) < 1.0, "y=%.1f" % player.y)
	check("страница дневника про золото теперь открыта", StoryDiary.unlocked_ids().has("gold"))

	# Концовка по событию боя.
	GameState.max_depth_reached = 10000
	for e in StoryData.depth_scenes():
		StoryState.mark_seen(String(e.id))
	GameState.emit_event(&"boss_defeated", {"id": "x"})
	guard = 0
	while not director.cutscene.is_playing and guard < 240:
		await _frames(1)
		guard += 1
	check("boss_defeated со дна запускает концовку в настоящей игре",
		director.cutscene.is_playing and director.cutscene.scene_id == "ending")
	director.cutscene.skip()
	await _frames(4)
	check("после концовки идут титры", director.cutscene.is_playing and director.cutscene.scene_id == "credits")
	director.cutscene.skip()
	await _frames(4)
	check("титры доиграны, игра продолжается", not director.cutscene.is_playing and not player.frozen and hud.visible)
	check("концовка запомнена", StoryState.is_seen("ending") and StoryState.has_flag("ending_seen"))
	check("после концовки герой дома у старта", absf(player.x - 15.5) < 0.1 and player.y < 1.0)

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)

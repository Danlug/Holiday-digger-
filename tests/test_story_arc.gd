extends Node
## test_story_arc.gd — сюжет после старта (ГДД раздел 2): каждая веха играет
## один раз, запоминается, переживает сейв, не повторяется и не оставляет игрока
## в заморозке; дневник и могила; концовка по событию боя и по запасным путям.
##
## Запуск:
##   godot --headless --path . res://tests/test_story_arc.tscn
##
## Герой здесь — настоящий player.gd без цикла физики: он «спокоен» не бывает
## (on_ground ложно), поэтому режиссёру ставится arc_calm_wait_ms = 0 — сам
## тайм-аут ожидания проверяется отдельно.

var failures := 0
var total := 0

var world: WorldGen
var player: Node2D
var director: StoryDirector
var beats_seen: Array = []     # id из событий story_beat по порядку

const TUTORIAL_SCENES := ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done",
	"dud_treasure", "workshop", "death", "backpack", "robert", "fuel_station",
	"sleep_lesson_1", "sleep_lesson_2"]


func _ready() -> void:
	_run()


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name,
		("  " + detail) if not ok and not detail.is_empty() else ""])


func _frames(n: int = 3) -> void:
	for _i in n:
		await get_tree().process_frame


## Состояние героя и сюжета с нуля — БЕЗ GameState.reset_progress(): тот шлёт
## max_depth_changed(0), а режиссёр по этому сигналу считает, что игрок нажал
## «Сброс», и начинает сюжет заново (интро в очереди). Сам сброс проверяет
## отдельный тест в конце.
func _reset_state() -> void:
	StoryState.delete_from_disk()
	GameState.max_depth_reached = 0
	GameState.collected_artifacts.clear()
	GameState.owned_tools = ["shovel"]
	GameState.ext.clear()
	GameState.set_stamina(100.0)
	GameState.set_hunger(100.0)
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	for id in TUTORIAL_SCENES:
		StoryState.mark_seen(id)
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "gold_sold",
			"food_ordered", "hatch_built", "robert_seen", "death_seen"]:
		StoryState.set_flag(f)
	beats_seen.clear()
	GameState.house_is_indoors = false
	player.x = 15.5
	player.y = 0.5
	player.frozen = false


func _on_event(id: StringName, data: Dictionary) -> void:
	if id == &"story_beat":
		beats_seen.append(String(data.get("id", "")))


func _run() -> void:
	print("=== test_story_arc.gd ===")
	GameState.game_event.connect(_on_event)

	world = WorldGen.new(20240915)
	player = preload("res://scripts/player/player.gd").new()
	player.world = world
	add_child(player)
	_reset_state()

	director = StoryDirector.new()
	director.setup(player, world, null)
	director.arc_calm_wait_ms = 0
	add_child(director)
	await _frames(4)

	_test_scene_data()
	await _test_grave_call_and_diary_first()
	await _test_first_artifact()
	await _test_depth_beats()
	await _test_catch_up()
	await _test_grandma_returns()
	await _test_gates()
	await _test_ending()
	_test_diary()
	_test_grave_site()
	await _test_playthrough_never_soft_locks()
	await _test_reset_clears_arc()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


## Дождаться, пока режиссёр сыграет сцену id (он сам берёт её из очереди), и
## пропустить её. Возвращает true, если сцена действительно начала играть.
func _play_and_skip(id: String) -> bool:
	var guard := 0
	while not (director.cutscene.is_playing and director.cutscene.scene_id == id) and guard < 30:
		await _frames(1)
		guard += 1
	var started: bool = director.cutscene.is_playing and director.cutscene.scene_id == id
	if started:
		director.cutscene.skip()
		await _frames(2)
	return started


## Один и тот же набор проверок для любой вехи: встала в очередь → сыграла →
## просмотрена → событие ушло ровно один раз → не повторяется → переживает сейв.
func _check_beat_once(id: String) -> void:
	var started := await _play_and_skip(id)
	check("%s: сцена сыграла сама" % id, started)
	check("%s: помечена просмотренной" % id, StoryState.is_seen(id))
	check("%s: ушла из очереди" % id, not GameState.story_queue.has(id))
	check("%s: story_beat эмитнут ровно один раз" % id, beats_seen.count(id) == 1,
		"раз: %d" % beats_seen.count(id))
	check("%s: управление возвращено" % id, not player.frozen)

	await _frames(6)
	check("%s: второй раз не встаёт в очередь" % id, not GameState.story_queue.has(id))
	check("%s: второй раз не играет" % id,
		not (director.cutscene.is_playing and director.cutscene.scene_id == id))
	check("%s: story_beat не повторился" % id, beats_seen.count(id) == 1)

	var queue_before: Array = GameState.story_queue.duplicate()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	StoryState.load_from_disk()
	check("%s: просмотренность пережила сейв и перезапуск" % id, StoryState.is_seen(id))
	GameState.story_queue = queue_before


# ---------------------------------------------------------------------------

func _test_scene_data() -> void:
	for id in ["grave_call", "diary_first", "first_artifact", "depth_100", "fever_500",
			"grandma_returns", "whisper_1200", "abyss_warning", "bottom_near", "ending", "credits"]:
		check("%s: сцена арки помечена arc" % id, bool(StoryData.scene(id).get("arc", false)))
	var depths: Array = StoryData.depth_scenes()
	var expected := ["depth_100", "fever_500", "whisper_1200", "abyss_warning", "bottom_near"]
	var got: Array = []
	for e in depths:
		got.append(String(e.id))
	check("сцены глубины отсортированы по порогу", got == expected, str(got))
	check("пороги глубины из ГДД: 100/500/1200/3900/9700",
		[int(depths[0].depth), int(depths[1].depth), int(depths[2].depth), int(depths[3].depth), int(depths[4].depth)] == [100, 500, 1200, 3900, 9700])


func _test_grave_call_and_diary_first() -> void:
	# Роберт ушёл, но герой ещё не спускался: звонка нет.
	await _frames(4)
	check("до первой вылазки бабка про могилу не звонит", not GameState.story_queue.has("grave_call"))

	GameState.max_depth_reached = 12
	player.y = 12.5       # герой в шахте
	await _frames(4)
	check("после первой вылазки звонок в очереди", GameState.story_queue.has("grave_call"))
	check("но под землёй не играет: сцена требует поверхность",
		not director.cutscene.is_playing)

	player.y = 0.5        # вылез
	await _frames(1)
	await _check_beat_once("grave_call")
	check("задание «загляни к могиле» висит над полосой",
		director._objective.contains("могил"))

	# Нажатие на могилу до звонка — только тост, после — тетрадь.
	check("тетради ещё нет", not StoryState.has_flag("diary_found"))
	director._on_grave_pressed()
	await _frames(2)
	check("нажатие на могилу после звонка запускает сцену тетради",
		director.cutscene.is_playing and director.cutscene.scene_id == "diary_first")
	director.cutscene.skip()
	await _frames(3)
	check("diary_first: тетрадь найдена (флаг)", StoryState.has_flag("diary_found"))
	check("diary_first: story_beat эмитнут", beats_seen.count("diary_first") == 1)
	check("после сцены тетради открылся экран дневника", director.diary_ui.is_open)
	check("пока дневник открыт, герой заморожен", player.frozen)
	check("дневник открылся на первой странице", director.diary_ui.current == 0)
	check("первая страница открыта и прочитана", StoryDiary.is_read("first"))
	director.diary_ui.close_diary()
	await _frames(2)
	check("закрыли дневник — герой свободен", not player.frozen)
	check("задание про могилу снято", not director._objective.contains("могил"))
	var again_queue := GameState.story_queue.has("diary_first")
	check("тетрадь второй раз не предлагается", not again_queue)

	director._on_grave_pressed()
	await _frames(2)
	check("повторное нажатие открывает дневник, а не сцену",
		director.diary_ui.is_open and not director.cutscene.is_playing)
	director.diary_ui.close_diary()
	await _frames(2)


func _test_first_artifact() -> void:
	GameState.collected_artifacts.append("antiquity_1")
	await _frames(4)
	check("никчёмный клад первой находкой не считается", not GameState.story_queue.has("first_artifact"))
	GameState.collected_artifacts.append("antiquity_2")
	await _frames(1)
	await _check_beat_once("first_artifact")


func _test_depth_beats() -> void:
	GameState.max_depth_reached = 99
	await _frames(4)
	check("на глубине 99 сотня не играет", not GameState.story_queue.has("depth_100"))
	GameState.max_depth_reached = 100
	await _check_beat_once("depth_100")

	GameState.max_depth_reached = 500
	await _check_beat_once("fever_500")
	check("лихорадка: герой поел и выспался (бодрость почти 100)", GameState.stamina >= 99.0)
	check("лихорадка: флаг «пережил»", StoryState.has_flag("fever_survived"))

	GameState.max_depth_reached = 1200
	await _check_beat_once("whisper_1200")
	check("шёпот: флаг слышал голос", StoryState.has_flag("whisper_heard"))

	GameState.max_depth_reached = 3899
	await _frames(4)
	check("на 3899 предупреждение не играет", not GameState.story_queue.has("abyss_warning"))
	GameState.max_depth_reached = 3900
	await _check_beat_once("abyss_warning")

	GameState.max_depth_reached = 9700
	await _check_beat_once("bottom_near")


## Сейв глубже порога, а сцены не играли: играет только самая глубокая.
func _test_catch_up() -> void:
	_reset_state()
	StoryState.mark_seen("grave_call")
	StoryState.set_flag("diary_found")
	GameState.max_depth_reached = 3000
	await _frames(3)
	check("catch-up: в очереди только самая глубокая из пропущенных", GameState.story_queue == ["whisper_1200"],
		str(GameState.story_queue))
	check("catch-up: сотня помечена просмотренной тихо", StoryState.is_seen("depth_100"))
	check("catch-up: лихорадка помечена просмотренной тихо", StoryState.is_seen("fever_500"))
	check("catch-up: тихие сцены story_beat не шлют", not beats_seen.has("depth_100") and not beats_seen.has("fever_500"))
	check("catch-up: до 3900 предупреждение не звали", not StoryState.is_seen("abyss_warning"))
	await _play_and_skip("whisper_1200")
	await _frames(2)
	GameState.max_depth_reached = 10000
	await _frames(3)
	check("catch-up: на 10000 пропущенное закрывается одной сценой", GameState.story_queue == ["bottom_near"],
		str(GameState.story_queue))
	check("catch-up: предупреждение 3900 помечено тихо", StoryState.is_seen("abyss_warning"))
	await _play_and_skip("bottom_near")


func _test_grandma_returns() -> void:
	_reset_state()
	StoryState.mark_seen("grave_call")
	GameState.max_depth_reached = 50
	await _frames(3)
	check("без бурмобиля бабка не возвращается", not GameState.story_queue.has("grandma_returns"))
	GameState.grant_tool("drill_rig")
	await _frames(1)
	await _check_beat_once("grandma_returns")
	check("бабка дома: флаг", StoryState.has_flag("grandma_home"))


## Жёсткие условия: внутри дома и под землёй для сцен «на поверхности» сцена
## не стартует вовсе, а мягкое — «герой спокоен» — отпускается по тайм-ауту.
func _test_gates() -> void:
	_reset_state()
	director.arc_calm_wait_ms = 0
	GameState.max_depth_reached = 12
	GameState.house_is_indoors = true
	await _frames(4)
	check("в доме сцены арки не стартуют", not director.cutscene.is_playing and GameState.story_queue.has("grave_call"))
	GameState.house_is_indoors = false
	player.y = 0.5
	await _frames(2)
	check("вышел из дома — звонок играет", director.cutscene.is_playing and director.cutscene.scene_id == "grave_call")
	director.cutscene.skip()
	await _frames(2)

	# Тайм-аут спокойствия: пока ждём — сцена в очереди, потом играет.
	StoryState.enqueue("first_artifact")
	director.arc_calm_wait_ms = 400
	director._arc_wait_since.clear()
	await _frames(3)
	check("герой не спокоен: сцена ждёт", not director.cutscene.is_playing and GameState.story_queue.has("first_artifact"))
	await get_tree().create_timer(0.5).timeout
	await _frames(2)
	check("по тайм-ауту сцена играет и без покоя",
		director.cutscene.is_playing and director.cutscene.scene_id == "first_artifact")
	director.cutscene.skip()
	await _frames(2)
	director.arc_calm_wait_ms = 0

	# Спокойный герой — сцена без ожидания.
	player.on_ground = true
	check("герой на земле без копки спокоен", director._hero_calm())
	player.on_ground = false


func _test_ending() -> void:
	_reset_state()
	StoryState.mark_seen("grave_call")
	GameState.max_depth_reached = 10000
	# Мимо катсцен глубины: считаем их просмотренными, чтобы очередь была чистой.
	for e in StoryData.depth_scenes():
		StoryState.mark_seen(String(e.id))

	# Чужой босс на малой глубине концовку не зовёт.
	GameState.max_depth_reached = 4500
	GameState.emit_event(&"boss_defeated", {"id": "mini_boss"})
	await _frames(3)
	check("босс не со дна концовку не зовёт", not GameState.story_queue.has("ending") and not StoryState.is_seen("ending"))

	GameState.max_depth_reached = 10000
	GameState.emit_event(&"boss_defeated", {"id": "abyss_lord"})
	var started := await _play_and_skip("ending")
	check("boss_defeated на дне запускает концовку", started)
	check("концовка: помечена просмотренной", StoryState.is_seen("ending"))
	check("концовка: флаг", StoryState.has_flag("ending_seen"))
	check("концовка: story_beat ровно один раз", beats_seen.count("ending") == 1)
	check("концовка: герой дома (teleport_home)", is_equal_approx(player.x, 15.5) and player.y < 1.0)
	check("концовка: за ней в очереди титры или они уже идут",
		GameState.story_queue.has("credits") or (director.cutscene.is_playing and director.cutscene.scene_id == "credits"))
	await _play_and_skip("credits")
	check("титры сыграли", StoryState.is_seen("credits"))
	check("титры: story_beat", beats_seen.count("credits") == 1)
	check("после титров игра свободна", not player.frozen and GameState.story_queue.is_empty())

	GameState.emit_event(&"boss_defeated", {"id": "final_boss"})
	await _frames(3)
	check("повторная победа концовку не переигрывает", not GameState.story_queue.has("ending"))

	# Запасные пути: каждый воспроизводит концовку заново.
	GameState.emit_event(&"story_ending_debug")
	check("событие story_ending_debug запускает концовку", await _play_and_skip("ending"))
	await _play_and_skip("credits")

	StoryState.set_flag("story_ending_debug")
	await _frames(3)
	check("флаг story_ending_debug запускает концовку", await _play_and_skip("ending"))
	check("флаг после запуска погашен", not StoryState.has_flag("story_ending_debug"))
	await _play_and_skip("credits")

	GameState.trigger_debug_action("story_ending")
	check("отладочное действие story_ending запускает концовку", await _play_and_skip("ending"))
	await _play_and_skip("credits")

	check("trigger_ending без force виденную не повторяет", not director.trigger_ending())
	check("trigger_ending(true) повторяет", director.trigger_ending(true))
	director.cutscene.skip()
	await _frames(2)
	await _play_and_skip("credits")


func _test_diary() -> void:
	_reset_state()
	var pages: Array = StoryDiary.pages()
	check("в дневнике 13 страниц (10–15 по заказу)", pages.size() == 13, str(pages.size()))
	check("до тетради ни одна страница не открыта", StoryDiary.unlocked_ids().is_empty())

	StoryState.set_flag("diary_found")
	check("первая страница открывается флагом тетради", StoryDiary.unlocked_ids() == ["first"])
	GameState.max_depth_reached = 49
	check("на 49 торф закрыт", not StoryDiary.unlocked_ids().has("peat"))
	GameState.max_depth_reached = 50
	check("на 50 торф открыт", StoryDiary.unlocked_ids().has("peat"))
	GameState.max_depth_reached = 3000
	for id in ["diamond", "gold", "heavy", "gems", "lava"]:
		check("на 3000 открыта страница %s" % id, StoryDiary.unlocked_ids().has(id))
	check("страницы-события на глубине сами не открываются", not StoryDiary.unlocked_ids().has("relic")
		and not StoryDiary.unlocked_ids().has("whisper") and not StoryDiary.unlocked_ids().has("last"))
	for pair in [["relic", "first_artifact"], ["whisper", "whisper_1200"], ["rig", "grandma_returns"],
			["monsters", "abyss_warning"], ["bottom", "bottom_near"], ["last", "ending"]]:
		StoryState.mark_seen(String(pair[1]))
		check("страницу %s открывает сцена %s" % pair, StoryDiary.unlocked_ids().has(String(pair[0])))
	check("в конце открыты все 13", StoryDiary.unlocked_ids().size() == 13)

	# Закрытые страницы честно называют печать, но чисел в ней нет.
	for k in ["diary.sealed_depth", "diary.sealed_event"]:
		check("текст печати %s без цифр" % k, not _has_digit(StoryText.get_text(k)))
	for p in pages:
		var id := String(p.get("id", ""))
		check("страница %s: у иконки есть файл" % id, ResourceLoader.exists(String(p.get("icon", ""))))
		check("страница %s: текст страницы не длиннее 160 знаков" % id,
			StoryText.get_text(StoryDiary.text_key(id, "text")).length() <= 160)
		check("страница %s: пометка на полях не длиннее 110 знаков" % id,
			StoryText.get_text(StoryDiary.text_key(id, "note")).length() <= 110)
		check("страница %s: пометка без чисел-спойлеров" % id,
			not _has_digit(StoryText.get_text(StoryDiary.text_key(id, "note"))))

	# Прочитанное: хранится в ext, переживает сохранение (JSON) и сброс чистит.
	GameState.ext.clear()
	check("после чистого ext все открытые страницы — непрочитанные", StoryDiary.unread_ids().size() == 13)
	StoryDiary.mark_read("first")
	StoryDiary.mark_read("first")
	check("пометка «прочитано» не дублируется", StoryDiary.unread_ids().size() == 12)
	var round_trip = JSON.parse_string(JSON.stringify(GameState.ext))
	GameState.ext = round_trip
	check("прочитанное пережило сохранение", StoryDiary.is_read("first") and not StoryDiary.is_read("peat"))
	check("уведомления: первый раз отдаются, второй пусты",
		StoryDiary.take_unannounced().size() == 13 and StoryDiary.take_unannounced().is_empty())
	GameState.ext.clear()
	check("пустой ext забывает прочитанное", not StoryDiary.is_read("first"))
	_reset_state()


func _has_digit(s: String) -> bool:
	for ch in s:
		if ch >= "0" and ch <= "9":
			return true
	return false


func _test_grave_site() -> void:
	var gs := GraveSite.new()
	gs.player = player
	add_child(gs)
	player.y = 0.5
	player.x = GraveSite.GRAVE_X
	check("у плиты герой рядом", gs.is_near())
	player.x = GraveSite.GRAVE_X + GraveSite.NEAR + 0.2
	check("в шаге от радиуса уже не рядом", not gs.is_near())
	player.x = 11.5
	check("у двери (клетка 11) могила не мешает кнопке «Зайти»", not gs.is_near())
	player.x = 15.5
	check("на старте героя (15.5) кнопка могилы не выскакивает", not gs.is_near())
	player.x = GraveSite.GRAVE_X
	player.y = 6.5
	check("из шахты могила не достаётся", not gs.is_near())
	player.y = 0.5
	check("до звонка бабки значка новостей нет", not gs.has_news())
	StoryState.mark_seen("grave_call")
	check("после звонка есть значок «иди сюда»", gs.has_news())
	StoryState.set_flag("diary_found")
	GameState.max_depth_reached = 60
	check("в тетради есть непрочитанное — значок", gs.has_news())
	for id in StoryDiary.unlocked_ids():
		StoryDiary.mark_read(id)
	check("всё прочитано — значок гаснет", not gs.has_news())
	var pressed := [0]
	gs.pressed.connect(func() -> void: pressed[0] += 1)
	gs._on_pressed()
	check("нажатие кнопки шлёт сигнал режиссёру", pressed[0] == 1)
	gs.queue_free()
	GameState.ext.clear()


## Каждая сцена арки доигрывается кадр за кадром (без кнопки «Пропустить») —
## ни один кадр не держит сцену навсегда, и после конца герой свободен и стоит
## там же, где стоял (world_exit = actor).
func _test_playthrough_never_soft_locks() -> void:
	_reset_state()
	var cs := director.cutscene
	for id in ["grave_call", "diary_first", "first_artifact", "depth_100", "fever_500",
			"grandma_returns", "whisper_1200", "abyss_warning", "bottom_near", "ending", "credits"]:
		director.cutscene.abort()
		GameState.story_queue.clear()
		player.x = 14.0
		player.y = 0.5
		var world_scene := StoryData.is_world_scene(id)
		cs.world = world
		cs.player = player
		var finished := [false]
		var on_done := func(_sid: String) -> void: finished[0] = true
		cs.finished.connect(on_done)
		cs.play(id, {"world": world_scene})
		var steps := 0
		while cs.is_playing and steps < 400:
			cs._typing = false
			cs._waiting_tap = false
			cs._beat_timer = 0.0
			cs._tap_target.visible = false
			cs._tick_world(0.2)
			# Таймеры ходьбы держат кадр — докручиваем, как делает _process.
			var guard := 0
			while (not cs._world_walk.is_empty() or not cs._world_fall.is_empty()) and guard < 400:
				cs._tick_world(0.2)
				guard += 1
			cs._advance()
			steps += 1
		check("%s: сцена доиграна покадрово за %d шагов" % [id, steps], finished[0] and steps < 400)
		check("%s: после конца режим «мир» снят" % id, not cs.world_mode)
		check("%s: после конца era = now" % id, GameState.era == "now")
		cs.finished.disconnect(on_done)
	player.x = 15.5
	player.y = 0.5


func _test_reset_clears_arc() -> void:
	_reset_state()
	StoryState.mark_seen("grave_call")
	StoryState.set_flag("diary_found")
	StoryDiary.mark_read("first")
	GameState.max_depth_reached = 800
	director.open_diary()
	check("перед сбросом дневник открыт", director.diary_ui.is_open)
	GameState.reset_progress()
	await _frames(2)
	check("сброс прогресса: сюжет арки забыт", not StoryState.is_seen("grave_call") and not StoryState.has_flag("diary_found"))
	check("сброс прогресса: прочитанное в ext забыто", not StoryDiary.is_read("first"))
	check("сброс прогресса: дневник закрыт", not director.diary_ui.is_open)
	check("сброс прогресса: сюжет пошёл заново (интро в очереди или играет)",
		GameState.story_queue.has("intro_grandpa") or (director.cutscene.is_playing and director.cutscene.scene_id == "intro_grandpa"))

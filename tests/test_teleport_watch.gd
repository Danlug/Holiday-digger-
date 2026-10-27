extends Node
## test_teleport_watch — часы-телепорт (владелец 27.10, ГДД §15.3, scripts/teleport/):
##  1. площадка справа от тоннеля, на траве; декора на ней нет; клетки мира не тронуты;
##  2. часы с глубины ставят героя на площадку, он стоит ровно; точка запомнена;
##  3. огонёк горит только пока возврат доступен, гаснет плавно;
##  4. «Вниз» — ровно один раз, на сохранённую точку; завалило — ближайшая безопасная клетка;
##  5. смерть гасит возврат; новое применение под землёй — новая точка, на поверхности — старая;
##  6. сюжет на 200 срабатывает один раз; обучение на общем GuideSpotlight: затемнение пропускает
##     касание только в цель (кнопка лавки → плитка часов → карточка), касание пальцем — один шаг,
##     лавку закрыли — шаг назад; «Наверх» переносит бесплатно (доллары целы); после конца
##     затемнение снято;
##  7. пропуск — подарок остаётся: плитка «0 $», покупка не тратит доллары, второй раз — платно;
##  8. сейв/загрузка состояния; слои (затемнение над лавкой, под Tip и катсценой).
##
## Запуск: godot --headless --path . res://tests/test_teleport_watch.tscn

const SEED := 4242
const DEPTH := 200

var failures := 0
var total := 0
var main: Node2D
var story: StoryDirector
var tw: TeleportWatch
var p


func check(label: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", label, ("  — " + detail) if not ok and not detail.is_empty() else ""])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== test_teleport_watch ===")
	await _boot()
	_test_pad_geometry()
	await _test_use_and_stand()
	await _test_glow_and_return_once()
	await _test_buried_point()
	await _test_death_and_overwrite()
	await _test_story_and_lesson()
	await _test_skip_keeps_gift()
	_test_save_load()
	_test_layers()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# Подготовка: игра после онбординга, тоннель Роберта построен
# ---------------------------------------------------------------------------

func _boot() -> void:
	for f in ["user://save.json", "user://save.json.bak", "user://records.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	GameState.reset_progress()
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	GameState.world_seed = SEED
	Settings.hints_enabled = false
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure", "workshop", "death",
			"backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2", "grave_call",
			"first_artifact", "grandma_returns"]:
		StoryState.mark_seen(id)
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "gold_sold", "food_ordered"]:
		StoryState.set_flag(f)
	StoryData.ensure_loaded()
	for e in StoryData.depth_scenes():
		if String(e.id) != TeleportLesson.SCENE_ID:
			StoryState.mark_seen(String(e.id))
	GameState.house_hatch_built = true
	GameState.house_garden_closed = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(6)
	main.world.build_robert_tunnel()
	story = main.find_child("StoryDirector", true, false)
	story.arc_calm_wait_ms = 0
	tw = TeleportWatch.find(get_tree())
	p = main.player
	var ms := MetaService.instance
	if ms != null:
		ms.set_process(false)
		if ms.popup != null and ms.popup.is_open():
			ms.popup.close()
	p.frozen = false
	check("модуль часов подключён к игре (TeleportWatch, площадка, урок)",
		tw != null and tw.pad != null and tw.lesson != null)


## Пустая клетка с твёрдым полом на глубине y: герою есть где стоять.
func _make_spot(x: int, y: int) -> void:
	var w: WorldGen = main.world
	w.dig_cell(x, y)
	w.dig_cell(x, y - 1)


func _place(x: float, y: float) -> void:
	p.x = x
	p.y = y
	p.vx = 0.0
	p.vy = 0.0
	p.digging = null


## Кадры без окна бегут быстрее реального времени: падение на полклетки ждём по часам.
func _settle(n: int = 30) -> void:
	await _frames(n)
	var until := Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


# ---------------------------------------------------------------------------
# 1. Площадка
# ---------------------------------------------------------------------------

func _test_pad_geometry() -> void:
	var px := WorldGen.TELEPORT_PAD_X
	check("площадка справа от тоннеля (за его правой стеной)", px > WorldGen.TUNNEL_WALL_RIGHT)
	check("площадка не залезает на станцию и её запас под декор", px < WorldGen.FUEL_STATION_X - 1)
	check("на площадке нет декора огорода", main.world.garden_decor_at(px) == "")
	check("под площадкой земля (y=1) — клетки мира не тронуты", main.world.get_tile(px, 1) != TileTypes.Type.EMPTY)
	check("центр площадки в клетках = клетка + 0.5", is_equal_approx(TeleportWatch.pad_x(), px + 0.5))
	var vr: Node = main.find_child("ViewRoot", true, false)
	var cv: Node = vr.get_node_or_null("CharacterView")
	check("площадка рисуется под героем (раньше CharacterView в ViewRoot)",
		cv != null and tw.pad.get_parent() == vr and tw.pad.get_index() < cv.get_index())
	check("площадка видна после тоннеля Роберта", TeleportWatch.pad_ready())
	# Парковка бурмобиля (18) и станция (от 21.3) не делят пузырь с площадкой.
	var r := TeleportWatch.num("near_cells", 0.75)
	check("зона «Вниз» не пересекает «В бурмобиль» у парковки 18 (радиус 1.2)",
		TeleportWatch.pad_x() - r > 18.5 + HouseConfig.interact_radius())
	check("зона «Вниз» не пересекает кнопку станции (от 21.3)", TeleportWatch.pad_x() + r <= WorldGen.FUEL_STATION_X + 1.0 - 1.7)


# ---------------------------------------------------------------------------
# 2. Часы с глубины: на площадку, стоит ровно, точка запомнена
# ---------------------------------------------------------------------------

func _test_use_and_stand() -> void:
	_make_spot(24, 150)
	_place(24.5, 150.5)
	await _settle(10)
	var from := Vector2(p.x, p.y)
	var dollars := GameState.dollars
	var r := TeleportWatch.use(p)
	check("часы сработали", bool(r.get("ok", false)) and bool(r.get("saved", false)))
	check("герой справа от тоннеля, на площадке", is_equal_approx(p.x, TeleportWatch.pad_x()) and p.y < 1.0,
		"x=%.2f y=%.2f" % [p.x, p.y])
	await _settle(30)
	# Стоит: ноги на траве (центр хитбокса на 1 - HH), не падает и не съехал вбок. on_ground без окна
	# мигает (кадры короче шага физики), поэтому меряем само положение.
	check("герой стоит на траве ровно (ноги на земле, x не уехал)", absf(p.y - (1.0 - p.HH)) < 0.01
		and absf(p.vy) < 0.5 and absf(p.x - TeleportWatch.pad_x()) < 0.01,
		"y=%.3f vy=%.2f x=%.2f" % [p.y, p.vy, p.x])
	check("точка возврата — откуда перенесли", TeleportWatch.has_return()
		and TeleportWatch.return_point().distance_to(from) < 0.01, str(TeleportWatch.return_point()))
	check("сама функция часов денег не трогает (оплата — в лавке)", GameState.dollars == dollars)
	check("применение посчитано", int(TeleportWatch.state()["uses"]) == 1)


# ---------------------------------------------------------------------------
# 3–4. Огонёк и возврат один раз
# ---------------------------------------------------------------------------

func _test_glow_and_return_once() -> void:
	var pad: TeleportPad = tw.pad
	for _i in 12:
		pad._process(0.1)
	check("огонёк горит, пока возврат доступен", pad.is_lit() and pad.level > 0.99, "level=%.2f" % pad.level)
	await _frames(2)
	var btn := tw.button()
	check("над героем на площадке — пузырь «Вниз»", btn.visible and btn.is_visible_in_tree())
	check("пузырь — значок без подписи, слово в подсказке",
		String(btn.get_meta("label", "")) == TeleportWatch.text("down_title"))
	var target := TeleportWatch.return_point()
	var ok := tw.press_down()
	check("«Вниз» вернул героя на сохранённую точку", ok and absf(p.x - (floor(target.x) + 0.5)) < 0.01
		and int(floor(p.y)) == int(floor(target.y)), "x=%.2f y=%.2f" % [p.x, p.y])
	check("клетка возврата пустая, под ногами твёрдое",
		main.world.get_tile(int(floor(p.x)), int(floor(p.y))) == TileTypes.Type.EMPTY
		and main.world.get_tile(int(floor(p.x)), int(floor(p.y)) + 1) != TileTypes.Type.EMPTY)
	check("возврат израсходован", not TeleportWatch.has_return())
	pad._process(0.3)
	check("огонёк гаснет плавно, а не щелчком", pad.level > 0.2 and pad.level < 0.9, "level=%.2f" % pad.level)
	for _i in 10:
		pad._process(0.1)
	check("огонёк погас", not pad.is_lit())
	# Второй раз: на площадку пешком (переносим), возврата нет — пузыря нет, нажатие ничего не делает.
	_place(TeleportWatch.pad_x(), 0.5)
	await _settle(4)
	check("второго возврата нет: пузыря нет", not btn.visible)
	check("второго возврата нет: нажатие ничего не делает", not tw.press_down() and p.y < 1.0)


func _test_buried_point() -> void:
	var w: WorldGen = main.world
	_make_spot(26, 300)
	_place(26.5, 300.5)
	await _settle(6)
	TeleportWatch.use(p)
	# Обвал: точку засыпало заново (снимаем диффы клетки и соседей — порода вернулась).
	for dx in [-1, 0, 1]:
		for dy in [-1, 0]:
			w.diffs.erase((300 + dy) * WorldGen.WIDTH + 26 + dx)
	w._touch_all()
	check("точка завалена", w.get_tile(26, 300) != TileTypes.Type.EMPTY)
	# Рядом есть пустая клетка с полом: выкопаем такую в 3 клетках.
	_make_spot(29, 300)
	var t := TeleportWatch.safe_return_target(w, TeleportWatch.return_point())
	# Ближайшая безопасная перебором: пустая клетка с твёрдым полом не лавой.
	var best := 1e9
	for yy in range(290, 311):
		for xx in range(WorldGen.WIDTH):
			if w.get_tile(xx, yy) == TileTypes.Type.EMPTY and w.get_tile(xx, yy + 1) != TileTypes.Type.EMPTY \
					and w.get_tile(xx, yy + 1) != TileTypes.Type.LAVA:
				best = minf(best, Vector2(xx, yy).distance_to(Vector2(26, 300)))
	check("завал: выбрана ближайшая безопасная клетка", t.x >= 0.0
		and absf(Vector2(floor(t.x), floor(t.y)).distance_to(Vector2(26, 300)) - best) < 0.01, "%s, ближайшая на %.2f" % [str(t), best])
	await _settle(2)
	var ok := TeleportWatch.go_down(p, w)
	check("завал: герой в пустой клетке с полом, не в породе", ok
		and w.get_tile(int(floor(p.x)), int(floor(p.y))) == TileTypes.Type.EMPTY
		and w.get_tile(int(floor(p.x)), int(floor(p.y)) + 1) != TileTypes.Type.EMPTY)
	# Совсем без пустот рядом — точку откапывают.
	var far := TeleportWatch.safe_return_target(w, Vector2(5.5, 900.5))
	check("пустот рядом нет — клетка точки откапывается и годится", far.x >= 0.0
		and w.get_tile(int(far.x), int(far.y)) == TileTypes.Type.EMPTY)


# ---------------------------------------------------------------------------
# 5. Смерть и новое применение
# ---------------------------------------------------------------------------

func _test_death_and_overwrite() -> void:
	_make_spot(24, 150)
	_place(24.5, 150.5)
	TeleportWatch.use(p)
	check("смерть подписана на гашение возврата", GameState.died.is_connected(tw._on_died))
	tw._on_died()
	check("смерть гасит возврат", not TeleportWatch.has_return())
	_place(24.5, 150.5)
	TeleportWatch.use(p)
	_make_spot(25, 160)
	_place(25.5, 160.5)
	TeleportWatch.use(p)
	check("новое применение под землёй — новая точка (возвраты не копятся)",
		TeleportWatch.return_point().distance_to(Vector2(25.5, 160.5)) < 0.01)
	_place(TeleportWatch.pad_x() - 1.0, 0.5)
	TeleportWatch.use(p)
	check("применение на поверхности старую точку не трогает",
		TeleportWatch.return_point().distance_to(Vector2(25.5, 160.5)) < 0.01)
	TeleportWatch.clear_return()


# ---------------------------------------------------------------------------
# 6. Сюжет на 200 и обучение
# ---------------------------------------------------------------------------

func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)
		await _frames(1)


## Касание пальцем: движок шлёт и само касание, и мышь из него — в одном кадре.
func _finger(pos: Vector2) -> void:
	for pressed in [true, false]:
		var t := InputEventScreenTouch.new()
		t.pressed = pressed
		t.position = pos
		get_viewport().push_input(t, true)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)
		await _frames(1)


func _test_story_and_lesson() -> void:
	var dollars_before := 7
	GameState.dollars = dollars_before
	GameState.dollars_changed.emit(GameState.dollars)
	_make_spot(23, DEPTH)
	_place(23.5, DEPTH + 0.5)
	await _settle(10)
	var beats: Array = []
	var on_event := func(id: StringName, data: Dictionary) -> void:
		if String(id) == "story_beat":
			beats.append(String(data.get("id", "")))
	GameState.game_event.connect(on_event)
	GameState.max_depth_reached = DEPTH
	var guard := 0
	while not story.cutscene.is_playing and guard < 60:
		guard += 1
		await _frames(1)
	check("рекорд 200 запускает сюжет «часы»", story.cutscene.is_playing and story.cutscene.scene_id == TeleportLesson.SCENE_ID,
		"кадров %d" % guard)
	story.cutscene.skip()
	await _frames(3)
	check("сцена отмечена и подарок выдан", StoryState.is_seen(TeleportLesson.SCENE_ID) and TeleportWatch.free_uses() == 1)
	var lesson: TeleportLesson = tw.lesson
	var sp: GuideSpotlight = lesson.spotlight
	guard = 0
	while not lesson.is_active() and guard < 60:
		guard += 1
		await _frames(1)
	check("обучение началось в спокойный момент (общий GuideSpotlight)", lesson.is_active()
		and lesson.current_step() == "open_shop" and sp.visible and GuideSpotlight.any_active(), "кадров %d" % guard)
	check("на время обучения герой стоит, ввод мира выключен", p.frozen and not main.hud.is_processing_input())
	check("сюжет не начинает сцену поверх обучения", story._modal_open())
	await _frames(3)
	var shop_btn: Control = main.hud.get("_shop_btn")
	var inv_btn: Control = main.hud.get("_inv_button")
	check("а) затемнение пропускает касание в кнопку лавки", sp.lets_through(shop_btn.get_global_rect().get_center()))
	check("а) затемнение ловит касание мимо цели (рюкзак)", not sp.lets_through(inv_btn.get_global_rect().get_center()))
	check("а) стрелка видна, окно — кнопка лавки", sp._arrow.visible and sp.hole().encloses(shop_btn.get_global_rect()))
	await _click(inv_btn.get_global_rect().get_center())
	check("а) нажатие мимо цели ничего не открыло", not main.hud._inv_sheet.visible and not ShopUI.instance.is_open())
	# Палец: касание и мышь из него приходят в цель в одном кадре — шаг один, а не два.
	await _finger(shop_btn.get_global_rect().get_center())
	await _frames(3)
	check("а) касание пальцем в цель открыло премиум-лавку", ShopUI.instance.is_open()
		and String(ShopUI.instance.get("_tab")) == ShopUI.SCREEN_PREMIUM)
	check("б) шаг — плитка часов (одно касание — один шаг)", lesson.current_step() == "watch_tile")
	await _frames(2)
	var tile: Control = lesson._tile()
	check("б) плитка часов найдена по ключу и в окне затемнения", tile != null and sp.hole().encloses(tile.get_global_rect()))
	# Закрыли лавку (Esc) — шаг назад, затемнение не пропало.
	ShopUI.instance.close()
	await _frames(2)
	check("б) лавку закрыли — шаг назад к кнопке лавки", lesson.is_active() and lesson.current_step() == "open_shop"
		and sp.hole().encloses(shop_btn.get_global_rect()))
	await _click(shop_btn.get_global_rect().get_center())
	await _frames(3)
	tile = lesson._tile()
	check("б) снова в лавке на плитке часов", lesson.current_step() == "watch_tile" and tile != null)
	var tabs: Control = ShopUI.instance.get("_nav")
	check("б) вкладки лавки под затемнением не нажимаются",
		tabs != null and not sp.lets_through(tabs.get_global_rect().get_center()))
	await _click(tile.get_global_rect().get_center())
	await _frames(2)
	check("в) нажатие на часы — объяснение, а не окно покупки", lesson.current_step() == "explain"
		and ShopUI.instance.get("_card") == null)
	check("в) текст объяснения — слова владельца", sp.card_text() == TeleportWatch.text("card_text"))
	var btn := sp.card_button()
	check("в) у карточки одна кнопка «Наверх», мимо неё не нажимается", btn != null
		and sp.lets_through(btn.get_global_rect().get_center()) and not sp.lets_through(tile.get_global_rect().get_center()))
	var from := Vector2(p.x, p.y)
	await _click(btn.get_global_rect().get_center())
	await _frames(4)
	check("г) бесплатно: доллары не списаны", GameState.dollars == dollars_before, "$%d" % GameState.dollars)
	check("г) подарок израсходован", TeleportWatch.free_uses() == 0)
	check("г) герой на площадке, точка возврата — 200", is_equal_approx(p.x, TeleportWatch.pad_x()) and p.y < 1.0
		and TeleportWatch.return_point().distance_to(from) < 0.01)
	check("обучение закончено, лавка закрыта, герой свободен", not lesson.is_active() and not GuideSpotlight.any_active()
		and not ShopUI.instance.is_open() and not p.frozen and main.hud.is_processing_input())
	check("затемнение после конца снято и ничего не держит", not sp.visible and sp.lets_through(Vector2(10, 10))
		and sp.card_button() == null)
	await _frames(3)
	check("пузырь «Вниз» мигает после урока", tw.button().visible and String(tw.button().get("_state")) == "forced")
	check("обучение отмечено пройденным", TeleportWatch.lesson_state() == "done")
	# Один раз за игру: глубже 200 снова — ни сцены, ни подарка.
	GameState.max_depth_reached = DEPTH + 50
	await _frames(10)
	tw.lesson.begin()
	check("сюжет на 200 — один раз (не в очереди, подарок не удвоился)",
		not GameState.story_queue.has(TeleportLesson.SCENE_ID) and not story.cutscene.is_playing
		and TeleportWatch.free_uses() == 0 and beats.count(TeleportLesson.SCENE_ID) == 1)
	GameState.game_event.disconnect(on_event)
	tw.press_down()
	await _frames(3)


# ---------------------------------------------------------------------------
# 7. Пропуск: подарок остаётся на плитке
# ---------------------------------------------------------------------------

func _test_skip_keeps_gift() -> void:
	var s := TeleportWatch.state()
	s["lesson"] = ""
	GameState.ext_set(TeleportWatch.KEY, s)
	_make_spot(23, DEPTH)
	_place(23.5, DEPTH + 0.5)
	await _settle(8)
	tw.lesson.begin()
	var guard := 0
	while not tw.lesson.is_active() and guard < 600:
		guard += 1
		await _frames(1)
	check("пропуск: обучение шло", tw.lesson.is_active(), "кадров %d" % guard)
	await _click(main.hud.get("_shop_btn").get_global_rect().get_center())
	await _frames(3)
	check("пропуск: в лавке на плитке часов", ShopUI.instance.is_open() and tw.lesson.current_step() == "watch_tile")
	tw.lesson.spotlight._skip.confirmed.emit()   # ⏭: долгое нажатие или двойной тап
	await _frames(2)
	check("пропуск: подарок остался, обучение пройдено", TeleportWatch.free_uses() == 1 and TeleportWatch.lesson_state() == "done")
	check("пропуск: затемнение снято, лавка закрыта, управление вернулось", not p.frozen and main.hud.is_processing_input()
		and not GuideSpotlight.any_active() and not ShopUI.instance.is_open())
	var offer := {}
	for o in ShopItems.offers_flat("premium"):
		if String(o["ref"]) == TeleportWatch.GOOD_ID:
			offer = o
	check("плитка часов с подарком: «0 $», бант, доступна",
		not offer.is_empty() and int(offer["price"]) == 0 and bool(offer.get("free", false))
		and String(offer["corner"]) == "gift" and String(offer["state"]) == "available")
	GameState.dollars = 0
	var r := ShopService.buy(TeleportWatch.GOOD_ID, "dollars")
	check("покупка подарком при $0 — успешна, доллары не тронуты", bool(r["ok"]) and GameState.dollars == 0
		and String(r["effect"]) == "teleport_home")
	check("подарок израсходован", TeleportWatch.free_uses() == 0)
	var r2 := ShopService.buy(TeleportWatch.GOOD_ID, "dollars")
	check("второй раз — снова за доллары (при $0 — отказ)", not bool(r2["ok"]))
	GameState.dollars = 20
	var r3 := ShopService.buy(TeleportWatch.GOOD_ID, "dollars")
	check("обычная покупка списывает цену", bool(r3["ok"]) and GameState.dollars == 5, "$%d" % GameState.dollars)


# ---------------------------------------------------------------------------
# 8. Сейв и слои
# ---------------------------------------------------------------------------

func _test_save_load() -> void:
	GameState.ext_set(TeleportWatch.KEY, {"ret": {"x": 12.5, "y": 345.5}, "free": 1, "lesson": "running", "uses": 3})
	check("сейв записан", SaveSystem.save_game())
	GameState.ext = {}
	check("до загрузки состояния нет", not TeleportWatch.has_return() and TeleportWatch.free_uses() == 0)
	SaveSystem.load_game()
	check("после загрузки: точка возврата, подарок, счётчик", TeleportWatch.return_point() == Vector2(12.5, 345.5)
		and TeleportWatch.free_uses() == 1 and int(TeleportWatch.state()["uses"]) == 3)
	var l := TeleportLesson.new()
	add_child(l)
	check("прерванное обучение после загрузки не повторяется (подарок на месте)",
		TeleportWatch.lesson_state() == "done" and TeleportWatch.free_uses() == 1)
	l.queue_free()
	TeleportLesson.instance = tw.lesson
	GameState.ext_set(TeleportWatch.KEY, {"ret": "мусор", "free": "x", "lesson": 5})
	var s := TeleportWatch.state()
	check("мусор в сейве не роняет часы", not TeleportWatch.has_return() and int(s["free"]) == 0)


func _test_layers() -> void:
	check("затемнение урока над лавкой (20) и подсказками (40)", GuideSpotlight.LAYER > 40)
	check("затемнение урока под окнами меты (92+), катсценой (100) и Tip (128)", GuideSpotlight.LAYER < 92)
	var hot: CanvasLayer = tw.get_node("TeleportHotspot")
	check("пузырь «Вниз» в полосе HUD-виджетов, как «Зайти»", hot.layer >= UiLayers.HUD and hot.layer <= UiLayers.HUD_TOP)

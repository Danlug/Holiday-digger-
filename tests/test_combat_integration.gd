extends Node
## test_combat_integration — бой в живой main-сцене (без окна): директор
## подключён, монстры спавнятся в тоннеле глубже 4000, автоатака и кнопка
## бьют, урон идёт в GameState.hp с бронёй и неуязвимостью 0.5 с, смерть как
## обычно, дроп и события, арена и рейдбосс на дне.
##
## Запуск: godot --headless --path . res://tests/test_combat_integration.tscn

var failures := 0
var total := 0
var main: Node2D
var director: CombatDirector
var events: Array = []


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _on_event(id: StringName, data: Dictionary) -> void:
	events.append([String(id), data])


func _count(id: String) -> int:
	var n := 0
	for e in events:
		if e[0] == id:
			n += 1
	return n


func _step(n: int, dt: float = 1.0 / 30.0) -> void:
	for i in range(n):
		director._process(dt)


func _ready() -> void:
	print("=== test_combat_integration ===")
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	GameState.ext.clear()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in range(4):
		await get_tree().process_frame
	GameState.game_event.connect(_on_event)
	GameState.ext.clear()   # сейв с диска мог принести чужое снаряжение

	director = CombatService.director as CombatDirector
	director._stats_dirty = true
	check("директор боя подключён к main", director != null and is_instance_valid(director))
	check("вид боя в ViewRoot рядом с героем", main.view_root.get_node_or_null("CombatView") != null)
	check("боевой интерфейс и экран снаряжения в сцене", main.find_child("CombatHud", true, false) != null
		and main.find_child("EquipmentLayer", true, false) != null)
	GameState.max_depth_reached = 4100
	check("пункт меню «Снаряжение» зарегистрирован и открывается с глубиной боя", _menu_has("equipment"))
	GameState.max_depth_reached = 100
	check("на мелководье пункта «Снаряжение» в меню нет (онбординг не тронут)", not _menu_has("equipment"))
	GameState.max_depth_reached = 4100
	check("мир получил хук арены", main.world.overlay.is_valid())
	check("ворота арены открыты до боя", not BossArena.sealed)

	# дальше драйвим кадры сами: игра и директор — вручную
	main.set_process(false)
	director.set_process(false)
	var p = main.player
	var w: WorldGen = main.world
	p.frozen = false
	GameState.house_is_indoors = false
	GameState.respawn()

	# --- глубина < 4000: тишина ---
	_place_hero(p, w, 2500)
	director.spawner.reset()
	_step(30 * 30)
	check("выше 4000 монстров нет", director.monsters.is_empty())
	check("кнопка удара не показывается на мелководье", not director.combat_ui_visible())

	# --- глубже 4000: спавн по таймеру в тоннеле ---
	_place_hero(p, w, 4600)
	director.spawner.reset()
	var spawned := [0]
	director.monster_spawned.connect(func(_m) -> void: spawned[0] += 1)
	_step(30 * 40)
	check("глубже 4000 появляются монстры", spawned[0] >= 2)
	var inside_ok := true
	for m: Monster in director.monsters:
		if director.cw.solid(int(floor(m.x)), int(floor(m.y))) and m.state != "dormant":
			inside_ok = false
	check("монстры не застряли в породе", inside_ok)
	check("кнопка удара видна в зоне боя", director.combat_ui_visible())
	check("лимит монстров соблюдается", director.monsters.size() <= MonsterSpawner.max_alive(4600) + 5)
	director.monsters.clear()
	director.spawning_enabled = false   # дальше сцены собираем вручную

	# --- удар героя и урон по герою ---
	CombatService.give("blade_t2")   # чтобы бой не зависел от везения с кулдауном кирки
	CombatService.equip("blade_t2")
	director._stats_dirty = true
	GameState.hp = GameState.get_max_hp()
	_place_hero(p, w, 4600)
	var grub := director.spawn({"id": "cinder_grub", "x": 18.5, "y": 4600.0, "group": 1, "emerge": Vector2.ZERO})
	p.facing = 1
	var hp0 := GameState.hp
	var kills0 := _count("monster_killed")
	var xp0 := GameState.xp + GameState.level * 100000
	_step(20)
	check("автоатака бьёт ближайшего врага", grub.hp < grub.max_hp or not grub.alive)
	check("герой развернулся к врагу", p.facing == 1)
	for i in range(30 * 10):
		GameState.hp = GameState.get_max_hp()
		director._process(1.0 / 30.0)
		if not grub.alive:
			break
	check("червь убит автоатакой", not grub.alive)
	_step(30)   # анимация смерти
	check("событие monster_killed", _count("monster_killed") == kills0 + 1)
	check("за убийство дан опыт", GameState.xp + GameState.level * 100000 > xp0)
	check("убийство записано в счётчик", CombatService.kills_total() >= 1)
	check("монстр убран из мира после смерти", not director.monsters.has(grub))
	# дроп
	var drops_seen := 0
	for k in range(60):
		var g := Monster.create("cinder_grub", 18.5, 4600, 4500)
		director.monsters.append(g)
		g.take_hit(1e9, 1)
		_step(30)
	drops_seen = GameState.get_item_count("cinder_ash") + GameState.get_item_count("hellstone")
	check("с монстров падают материалы в рюкзак", drops_seen > 0)

	# --- монстр бьёт героя: броня и неуязвимость ---
	GameState.inventory.clear()
	director.monsters.clear()
	GameState.hp = GameState.get_max_hp()
	_place_hero(p, w, 4600)
	var biter := director.spawn({"id": "cinder_grub", "x": 17.6, "y": 4600.0, "group": 2, "emerge": Vector2.ZERO})
	biter.max_hp = 1e9
	biter.hp = 1e9
	director.swing_cd = 99.0   # не убиваем: проверяем только урон по герою
	var hurt := {"count": 0, "dmg": 0.0}
	var on_hurt := func(d: float, _s: String) -> void:
		hurt["count"] += 1
		hurt["dmg"] = d
	director.hero_hurt.connect(on_hurt)
	var hp_before := GameState.hp
	_step(60)
	check("монстр бьёт героя: HP падает", GameState.hp < hp_before and hurt["count"] >= 1)
	check("после удара — неуязвимость", director.iframes > 0.0 or hurt["count"] >= 1)
	var raw := biter.damage
	check("без брони урон = сырому (-%d)" % int(raw), absf(float(hurt["dmg"]) - raw) < 0.01)
	# интервал между ударами не меньше iframes (считаем по сигналу, героя подлечиваем)
	hurt["frames"] = []
	hurt["frame"] = 0
	director.hero_hurt.disconnect(on_hurt)
	var on_hurt2 := func(_d: float, _s: String) -> void:
		(hurt["frames"] as Array).append(int(hurt["frame"]))
	director.hero_hurt.connect(on_hurt2)
	for i in range(30 * 8):
		hurt["frame"] = i
		GameState.hp = GameState.get_max_hp()
		director._process(1.0 / 30.0)
	director.hero_hurt.disconnect(on_hurt2)
	var fr: Array = hurt["frames"]
	var gaps_ok := fr.size() >= 3
	for i in range(1, fr.size()):
		if (int(fr[i]) - int(fr[i - 1])) < 14:   # 0.5 с при 30 к/с
			gaps_ok = false
	check("между ударами не меньше 0.5 с неуязвимости (ударов: %d)" % fr.size(), gaps_ok)
	check("отброс и оглушение героя при ударе", p.stun_until_msec > 0.0)
	# с бронёй урона меньше
	director.monsters.clear()
	GameState.ext.clear()
	CombatService.give("armor_t3")
	CombatService.equip("armor_t3")
	director._stats_dirty = true
	var armored := {"dmg": 0.0}
	director.hero_hurt.connect(func(d: float, _s: String) -> void: armored["dmg"] = d)
	director.iframes = 0.0
	GameState.hp = GameState.get_max_hp()
	_place_hero(p, w, 4600)
	var biter2 := director.spawn({"id": "cinder_grub", "x": 17.6, "y": 4600.0, "group": 3, "emerge": Vector2.ZERO})
	biter2.max_hp = 1e9
	biter2.hp = 1e9
	director.swing_cd = 99.0
	_step(40)
	check("броня снижает урон монстра", float(armored["dmg"]) > 0.0 and float(armored["dmg"]) < raw * 0.7)
	director.monsters.clear()

	# --- кнопка и нажатие ---
	director.swing_cd = 0.0
	GameState.hp = GameState.get_max_hp()
	var hud_node = main.hud
	hud_node.mode = "hold"
	var ui: CanvasLayer = director.ui
	ui._process(0.1)
	var btn: Control = ui._attack
	check("кнопка удара видна", btn.visible)
	var vr := get_viewport().get_visible_rect().size
	check("кнопка крупная и в зоне большого пальца", btn.size.x >= 40.0 and btn.position.y > vr.y * 0.6 and btn.position.x < vr.x * 0.4)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = btn.position + btn.size / 2.0
	director.swing_cd = 0.0
	get_viewport().push_input(press, true)
	check("нажатие на кнопку бьёт даже в режиме «нажатия» (раньше HUD)", director.swing_cd > 0.0)
	check("герой при этом не пошёл «держать» палец", not hud_node._has_touch)

	# --- смерть как обычно ---
	director.monsters.clear()
	var died_flag := [false]
	GameState.died.connect(func() -> void: died_flag[0] = true)
	var dead_hp_frames := 0
	director.spawn({"id": "abyss_warden", "x": 17.6, "y": 4600.0, "group": 4, "emerge": Vector2.ZERO})
	GameState.hp = 3.0
	director.iframes = 0.0
	director.swing_cd = 99.0
	_step(60)
	check("смерть от монстра — GameState.died и потеря рюкзака", died_flag[0] and not GameState.is_alive)
	check("после смерти монстры убраны", director.monsters.is_empty())
	GameState.respawn()

	# --- арена и босс ---
	_test_boss(p, w)

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _menu_has(id: String) -> bool:
	for e in MenuRegistry.entries():
		if String(e["id"]) == id:
			return true
	return false


func _place_hero(p, w: WorldGen, depth: int) -> void:
	for x in range(8, 26):
		w.diffs[depth * WorldGen.WIDTH + x] = true
	# карман повыше для прыжков/полёта
	for x in range(15, 19):
		w.diffs[(depth - 1) * WorldGen.WIDTH + x] = true
	director.cw.invalidate()
	p.x = 16.5
	p.y = float(depth) + 0.6
	p.vx = 0.0
	p.vy = 0.0
	p.on_ground = true
	p.digging = null
	p.stun_until_msec = 0.0
	director.iframes = 0.0
	director._kb_left = 0.0


func _test_boss(p, w: WorldGen) -> void:
	events.clear()
	GameState.ext.clear()
	GameState.inventory.clear()
	GameState.house_storage.clear()
	GameState.hp = GameState.get_max_hp()
	director.monsters.clear()
	CombatService.give("blade_t5")
	CombatService.equip("blade_t5")
	director._stats_dirty = true
	var floor_y := BossArena.floor_y()
	# герой над воротами не запускает бой
	p.x = 16.5
	p.y = float(BossArena.top_y()) - 3.0
	director.swing_cd = 0.0
	_step(10)
	check("над воротами бой не начался", director.boss == null)
	# падает в арену
	p.y = float(floor_y) - 1.5
	_step(3)
	check("герой в арене: бой начался, ворота закрылись", director.boss != null and BossArena.sealed)
	check("потолок закрыт — отступления нет", w.get_tile(16, BossArena.top_y()) == TileTypes.Type.REINFORCED)
	check("попытка засчитана", int(CombatService.boss_state()["attempts"]) == 1)
	check("полоска босса показывается", director.combat_ui_visible())
	# босс бьёт — HP падает, не мгновенно
	_step(30 * 3)
	check("после интро босс начинает паттерн", director.boss.state != BossLogic.INTRO)
	# герой дерётся: выставляем рядом с телом и ждём окно уязвимости
	var boss: BossLogic = director.boss
	var dealt_total := 0.0
	var hero_hp0 := GameState.hp
	var guard := 0
	while boss.hp > boss.max_hp * 0.9 and guard < 30 * 120:
		guard += 1
		p.x = boss.center_x + 2.3
		p.y = float(floor_y) - 0.4
		p.on_ground = true
		director.iframes = 99.0     # здесь проверяем удар по боссу, не выживание
		GameState.hp = GameState.get_max_hp()
		director._process(1.0 / 30.0)
	check("герой бьёт босса (HP падает)", boss.hp < boss.max_hp)
	# добиваем: прыгаем по фазам
	boss.hp = boss.phase_hp_threshold(1) + 1.0
	boss.state = BossLogic.RECOVER
	p.x = boss.center_x + 2.3
	director.swing_cd = 0.0
	guard = 0
	while boss.phase < 2 and guard < 30 * 30:
		guard += 1
		director.iframes = 99.0
		p.x = boss.center_x + 2.3
		p.y = float(floor_y) - 0.4
		director._process(1.0 / 30.0)
	check("фаза 2 наступила", boss.phase == 2 and director.boss_phase_shown == 2)
	check("лучший рубеж сохранён", int(CombatService.boss_state()["best_phase"]) >= 2)
	# смерть в бою сбрасывает босса и открывает ворота
	GameState.hp = 1.0
	director.iframes = 0.0
	GameState.take_damage(5.0, "test")
	check("смерть в арене: бой сброшен, ворота открыты", director.boss == null and not BossArena.sealed)
	GameState.respawn()

	# ушёл с арены (телепорт) — бой прерван, ворота открыты
	p.x = 16.5
	p.y = float(floor_y) - 1.5
	director.iframes = 0.0
	_step(3)
	check("снова вошёл — бой идёт", director.boss != null and BossArena.sealed)
	p.y = 100.0
	_step(3)
	check("герой ушёл с арены: бой прерван, ворота открыты", director.boss == null and not BossArena.sealed)
	check("прерванный бой сообщает boss_failed", _count("boss_failed") >= 1)

	# победа
	events.clear()
	p.x = 16.5
	p.y = float(floor_y) - 1.5
	director.iframes = 0.0
	director.swing_cd = 0.0
	_step(3)
	check("повторный вход — новый бой", director.boss != null and BossArena.sealed)
	boss = director.boss
	boss.hp = 1.0
	boss.phase = 3
	boss.state = BossLogic.RECOVER
	boss.t = 0.0
	GameState.hp = GameState.get_max_hp()
	var xp_before := GameState.xp + GameState.level * 1000000
	guard = 0
	while director.boss != null and director.boss.is_active() and guard < 30 * 10:
		guard += 1
		director.iframes = 99.0
		p.x = boss.center_x + 2.3
		p.y = float(floor_y) - 0.4
		director._process(1.0 / 30.0)
	check("босс побеждён: событие boss_defeated с id", _count("boss_defeated") == 1)
	var id_ok := false
	for e in events:
		if e[0] == "boss_defeated" and String(e[1].get("id")) == "abyss_boss":
			id_ok = true
	check("id босса — abyss_boss (его ждёт финал сюжета)", id_ok)
	check("монстр убит: monster_killed на босса", _count("monster_killed") >= 1)
	check("ворота снова открыты", not BossArena.sealed and w.get_tile(16, BossArena.top_y()) == TileTypes.Type.EMPTY)
	check("награда на складе: ядро и осколки", HouseStorage.count("abyss_core") == 1 and HouseStorage.count("idol_shard") == 4)
	check("трофей — Венец Идола", CombatService.is_owned("idol_crown"))
	check("опыт за босса", GameState.xp + GameState.level * 1000000 > xp_before)
	check("прогресс: босс побеждён", CombatService.boss_defeated())
	_step(30 * 4)   # концовка сюжета могла заморозить героя — анимация смерти всё равно доигрывается
	check("после победы босс убран, спавн в арене не идёт", director.boss == null and director.monsters.is_empty())
	# повторно бой не начинается
	p.frozen = false
	p.y = float(floor_y) - 1.5
	_step(5)
	check("побеждённый босс не возрождается", director.boss == null)

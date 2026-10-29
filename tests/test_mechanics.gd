extends Node
## test_mechanics — механики раунда 3 (ГДД §20.1): тайники, азарт и лихорадка,
## мастерство руд и журнал. Всё детерминированно: фиксированный сид мира, время
## шагами (StreakLogic.tick, MechDirector.step), без часов и таймеров сцены.
## Автозагрузки нужны, поэтому запускается сценой:
##   godot --headless --path . res://tests/test_mechanics.tscn

const SEED := 4242

var failures := 0
var total := 0
var world: WorldGen
var fog: FogOfWar


class StubPlayer:
	extends Node2D
	var x: float = 20.5
	var y: float = 30.5
	var digging = null
	var frozen: bool = false
	var greed_mult: float = 1.0
	func cell_x() -> int:
		return int(floor(x))
	func cell_y() -> int:
		return int(floor(y))
	func release_control() -> void:
		pass


class StubHost:
	extends Node
	var player: Node
	var world: WorldGen
	var fog: FogOfWar
	var view_root: Node2D


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== test_mechanics ===")
	await _frames(2)
	Settings.reduce_motion = false
	GameState.world_seed = SEED
	world = WorldGen.new(SEED)
	fog = FogOfWar.new()
	GameState.world_ref = world
	GameState.fog_ref = fog
	GameState.reset_progress()
	GameState.world_seed = SEED
	StoryState.set_flag("food_ordered", false)

	_test_config()
	_test_chest_placement()
	_test_chest_tiers()
	_test_chest_loot()
	_test_streak()
	_test_mastery_logic()
	await _test_director()
	await _test_main_scene()

	StoryState.set_flag("food_ordered", false)
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------------------

func _test_config() -> void:
	# ошибка разбора скрипта не роняет процесс (код 0) — ловим её здесь, а не глазами в логе
	for f in DirAccess.get_files_at("res://scripts/mechanics"):
		if f.ends_with(".gd"):
			var sc: GDScript = load("res://scripts/mechanics/" + f)
			check("скрипт %s компилируется" % f, sc != null and sc.can_instantiate())
	check("data/mechanics.json читается", not MechData.config().is_empty())
	for sec in ["chests", "streak", "mastery"]:
		check("раздел %s есть" % sec, not MechData.section(sec).is_empty())
	# все числа, которых владелец не задавал, помечены proposed
	var unmarked: Array = []
	for sec in ["chests", "streak", "mastery"]:
		for k in MechData.section(sec).keys():
			var v = MechData.section(sec)[k]
			if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
				unmarked.append("%s.%s" % [sec, k])
	check("голых чисел без proposed нет (%s)" % str(unmarked), unmarked.is_empty())
	for id in MasteryLogic.kinds():
		check("порода журнала %s есть в minerals.json" % id, not Balance.get_mineral(String(id)).is_empty())
	check("гейт закрыт до конца онбординга", not MechData.gate_open())


func _test_chest_placement() -> void:
	var w2 := WorldGen.new(SEED)
	var same := true
	var found := 0
	var bands := 400
	var bad_tile := 0
	for b in range(bands):
		var a := ChestLogic.chest_in_band(world, SEED, b)
		var c := ChestLogic.chest_in_band(w2, SEED, b)
		if a != c:
			same = false
		if a.is_empty():
			continue
		found += 1
		var cell: Vector2i = a["cell"]
		if ChestLogic.band_of(cell.y) != b:
			bad_tile += 1
		if ChestLogic.BAD_TILES.has(world._generate_layered(cell.x, cell.y, 0)):
			bad_tile += 1
	check("место сундука — чистая функция сида (два мира, 400 полос)", same)
	var share := float(found) / float(bands)
	check("сундук в %.0f%% полос (шанс 60%%, минус пустоты и лава)" % (share * 100.0), share > 0.5 and share <= 0.62)
	check("сундук лежит в своей полосе и в цельной породе", bad_tile == 0)
	check("выше 20-го ряда сундуков нет", ChestLogic.band_of(19) == -1 and ChestLogic.chest_in_band(world, SEED, -1).is_empty())
	# другой сид — другая раскладка
	var diff := 0
	for b in range(60):
		if ChestLogic.chest_in_band(world, SEED, b) != ChestLogic.chest_in_band(world, SEED + 2, b):
			diff += 1
	check("другой сид — другие места (%d из 60 полос)" % diff, diff > 20)
	# землетрясение перетряхивает породу, но не двигает сундук
	var before := []
	for b in range(80):
		before.append(ChestLogic.chest_in_band(world, SEED, b))
	var wq := WorldGen.new(SEED)
	wq.apply_global_event(777)
	var moved := 0
	for b in range(80):
		if ChestLogic.chest_in_band(wq, SEED, b) != before[b]:
			moved += 1
	check("землетрясение не переносит сундук в другую клетку", moved == 0)
	# клетка-кандидат артефакта сундуком не занимается
	var wp := WorldGen.new(SEED)
	var first := ChestLogic.chest_in_band(wp, SEED, 3)
	if not first.is_empty():
		var pc: Vector2i = first["cell"]
		wp.set_protect_cell(func(x: int, y: int) -> bool: return x == pc.x and y == pc.y)
		var second := ChestLogic.chest_in_band(wp, SEED, 3)
		check("кандидат артефакта не занят сундуком", second.is_empty() or second["cell"] != pc)


func _test_chest_tiers() -> void:
	var low_bad := 0
	var counts := {"wood": 0, "iron": 0, "gold": 0}
	for b in range(1500):
		var y := ChestLogic.y_min() + b * ChestLogic.band_rows()
		var t := ChestLogic.pick_tier(SEED, b, y)
		if (t == "iron" and y < 120) or (t == "gold" and y < 300):
			low_bad += 1
	# доли ступеней на 300–1500: 3000 бросков (полоса как ключ броска, глубина по кругу)
	for b in range(3000):
		counts[ChestLogic.pick_tier(SEED, b, 300 + (b * 7) % 1200)] += 1
	check("железо не мельче 120, золото не мельче 300", low_bad == 0)
	var n := float(counts["wood"] + counts["iron"] + counts["gold"])
	var gold_share := float(counts["gold"]) / n
	var wood_share := float(counts["wood"]) / n
	check("на 300–1500 дерево чаще всего (%.0f%%), золото редкое (%.1f%%)" % [wood_share * 100.0, gold_share * 100.0],
		wood_share > 0.55 and wood_share < 0.8 and gold_share > 0.04 and gold_share < 0.1)


func _test_chest_loot() -> void:
	var c := Vector2i(12, 340)
	var a := ChestLogic.roll_loot(world, SEED, c, "iron")
	var b := ChestLogic.roll_loot(world, SEED, c, "iron")
	check("добыча сундука детерминирована (сейв-скам не перебрасывает)", a == b)
	check("в сундуке есть добыча и опыт", not (a["items"] as Dictionary).is_empty() and int(a["xp"]) > 0)
	var forbidden := 0
	var gems := 0
	var food := 0
	var heaviest := 0.0
	for i in range(200):
		var cell := Vector2i(i % 32, 300 + i * 13)
		for tier in ["wood", "iron", "gold"]:
			var l := ChestLogic.roll_loot(world, SEED, cell, tier)
			heaviest = maxf(heaviest, ChestLogic.ore_kg(l["items"]))
			for id in (l["items"] as Dictionary).keys():
				if ["mercury", "uranium", "peat", "coal"].has(String(id)):
					forbidden += 1
				if tier == "gold" and ["diamond", "ruby", "divine_heart"].has(String(id)):
					gems += 1
				if String(id).begins_with("food_"):
					food += 1
	check("ртуть, уран, торф и уголь из сундука не выпадают", forbidden == 0)
	check("в каждом золотом сундуке самоцвет (%d из 200)" % gems, gems >= 200)
	check("еда в сундуках бывает (%d)" % food, food > 100)
	check("руды в сундуке не больше 60 кг — владелец (самый тяжёлый %.1f кг)" % heaviest, heaviest <= 60.0 + 0.001)
	# ценность — «value_cells клеток копки» (у деревянного 3, но не меньше двух штук) на любой глубине
	for y in [60, 300, 1200, 2500]:
		var sum := 0.0
		for i in range(80):
			sum += float(ChestLogic.loot_value(ChestLogic.roll_loot(world, SEED, Vector2i(i % 32, y), "wood")["items"]))
		var cells := sum / 80.0 / ChestLogic.cell_value(world, y)
		check("деревянный сундук на %d ≈ 3 клетки копки (%.1f)" % [y, cells], cells > 1.5 and cells < 10.0)
	# сундук-тайник не превращается в кошелёк: монет он не даёт вовсе
	check("монет в добыче нет (только руда, еда, опыт)", not (a["items"] as Dictionary).has("coins"))


func _test_streak() -> void:
	var s := StreakLogic.new()
	var at := s.fever_s
	check("жадность из данных: %.0f с работы → %.0f с жадности" % [at, s.greed_s],
		is_equal_approx(at, 60.0) and is_equal_approx(s.greed_s, 3.0))
	# шкала копится секундами копки, порог срабатывает на выкопанной клетке
	s.on_dug(40)
	s.tick(at - 0.5, true, true)
	check("%.1f с копки — ещё не жадность (шкала %.0f%%)" % [at - 0.5, s.meter() * 100.0],
		not s.in_greed() and s.meter() > 0.95 and s.meter() < 1.0)
	check("клетка до порога жадность не включает", not bool(s.on_dug(40)["started"]))
	s.tick(0.5, true, true)
	check("шкала полна — %.0f%%" % (s.meter() * 100.0), is_equal_approx(s.meter(), 1.0) and not s.in_greed())
	var r := s.on_dug(40)
	check("клетка на полной шкале запускает жадность", bool(r["started"]) and s.in_greed() and is_equal_approx(s.greed_left, 3.0))
	check("сама клетка-порог не двойная", not bool(r["fever_cell"]))
	check("клетка в жадности — двойная и шкалу не копит", bool(s.on_dug(40)["fever_cell"]) and s.work == 0.0)
	s.tick(1.0, true, true)
	check("копка в жадности шкалу не копит", s.work == 0.0)
	check("пауза в жадности её не рвёт (идёт по часам)", not s.tick(1.9, false, true) and s.in_greed())
	check("окно в жадности её не держит (по часам)", not s.tick(0.05, false, true, true) and s.greed_left < 0.1)
	s.tick(0.2, true, true)
	check("через 3 с жадность кончилась, шкала с нуля", not s.in_greed() and s.work < 0.25)
	s.reset()
	# паузы: шаг между клетками — работа; стоит — ждёт; дальше — тает
	s.on_dug(40)
	s.tick(20.0, true, true)
	check("пока копает — шкала растёт, как бы долго ни шёл удар (20 с)", is_equal_approx(s.work, 20.0))
	s.tick(0.5, false, true)
	check("шаг или падение в клетку до 0.6 с — тоже работа", is_equal_approx(s.work, 20.5))
	s.tick(1.9, false, true)
	check("пауза 2.4 с — шкала стоит", is_equal_approx(s.work, 20.5) and not s.draining())
	s.tick(1.0, false, true)
	check("дольше 2.5 с — шкала тает, но не сгорает разом (%.1f с)" % s.work, s.draining() and s.work > 15.0 and s.work < 20.5)
	s.on_dug(40)
	check("новая клетка — таяние кончилось", s.idle == 0.0 and not s.draining())
	var w := s.work
	check("окно или сцена (hold) — шкала замирает", not s.tick(30.0, false, true, true) and is_equal_approx(s.work, w))
	check("долгий простой — шкала растаяла до нуля", s.tick(10.0, false, true) or s.tick(10.0, false, true))
	check("растаявшая серия — с нуля", s.work == 0.0 and s.count == 0)
	s.on_dug(40)
	s.tick(at, true, true)
	s.on_dug(40)
	check("подъём наверх или дом рвут и жадность", s.in_greed() and s.tick(0.01, false, false) and not s.in_greed())
	s.on_dug(40)
	s.tick(5.0, true, true)
	check("подъём наверх или дом (allowed=false) — сброс", s.tick(0.01, false, false) and s.work == 0.0 and s.count == 0)
	check("огород и обучение не считаются", s.on_dug(3)["started"] == false and s.count == 0)
	check("шкала 0..1", s.meter() == 0.0)


func _test_mastery_logic() -> void:
	check("железо — дешёвая порода", MasteryLogic.price_class("iron_ore") == "cheap")
	check("золото — средняя", MasteryLogic.price_class("gold") == "mid")
	check("алмаз — драгоценная", MasteryLogic.price_class("diamond") == "precious")
	check("геокристалл без цены — средняя", MasteryLogic.price_class("geocrystal") == "mid")
	check("0 клеток — 0 звёзд", MasteryLogic.stars_for("iron_ore", 0) == 0)
	check("10 железа — звезда", MasteryLogic.stars_for("iron_ore", 10) == 1)
	check("1500 железа — пять звёзд", MasteryLogic.stars_for("iron_ore", 1500) == 5)
	check("3 алмаза — звезда", MasteryLogic.stars_for("diamond", 3) == 1)
	check("порог следующей звезды железа после 12 — 40", MasteryLogic.next_threshold("iron_ore", 12) == 40)
	check("после пятой звезды порога нет", MasteryLogic.next_threshold("iron_ore", 5000) == 0)
	check("шанс двойной добычи +2% за звезду", is_equal_approx(MasteryLogic.double_chance(3), 0.06))
	check("опыт звезды не меньше 10", MasteryLogic.star_xp("iron_ore", 1) >= 10)
	check("опыт звезды алмаза = 3 × 100 × 0.25 = 75", MasteryLogic.star_xp("diamond", 1) == 75)


# ---------------------------------------------------------------------------
# Режиссёр на заглушке героя: награды, рюкзак, остатки, гейт, лихорадка, меню
# ---------------------------------------------------------------------------

func _make_director() -> Array:
	var host := StubHost.new()
	host.name = "Host"
	var p := StubPlayer.new()
	p.name = "Player"
	host.player = p
	host.world = world
	host.fog = fog
	host.view_root = Node2D.new()
	host.add_child(p)
	host.add_child(host.view_root)
	add_child(host)
	var d := Mechanics.attach(host) as MechDirector
	return [host, d, p]


func _dug(cell: Vector2i, mineral: String, loot: bool) -> void:
	var tile := MineralMap.tile_type_for(mineral) if mineral != "" else TileTypes.Type.DIRT
	GameState.emit_event(&"dug", {"cell": cell, "tile": tile, "mineral": mineral, "loot": loot,
		"pos": Vector2(cell.x * 32.0 + 16.0, cell.y * 32.0 + 16.0)})


func _test_director() -> void:
	GameState.reset_progress()
	GameState.world_seed = SEED
	var parts := _make_director()
	var host: Node = parts[0]
	var d: MechDirector = parts[1]
	var p: StubPlayer = parts[2]
	await _frames(1)
	check("режиссёр подключён одной строкой и не удваивается", Mechanics.attach(host) == d)
	check("слой сундуков в мире создан", d.chest_layer != null and d.chest_layer.get_parent() == host.view_root)

	# найти сундук
	var ch := {}
	for b in range(2, 60):
		ch = d.chest_for_band(b)
		if not ch.is_empty() and String(ch["tier"]) == "wood":
			break
	check("сундук найден для проверки", not ch.is_empty())
	var cell: Vector2i = ch["cell"]

	# до онбординга: мастерство копится молча, сундук не открывается, лихорадки нет
	_dug(Vector2i(3, 40), "iron_ore", true)
	check("до онбординга счётчик мастерства идёт", MechState.mastery_count("iron_ore") == 1)
	_dug(cell, "", false)
	check("до онбординга сундук не открывается", not MechState.chest_opened(cell))
	for i in range(60):
		_dug(Vector2i(4, 41), "", false)
		d.step(1.0)
	check("до онбординга азарт не копится", d.streak.count == 0 and d.streak.work == 0.0 and not d.streak.in_fever())
	check("до онбординга пункта «Журнал» не видно",
		MenuRegistry.entries().filter(func(e) -> bool: return e["id"] == "journal").is_empty())

	StoryState.set_flag("food_ordered", true)
	check("гейт открыт после онбординга", MechData.gate_open())

	# сундук
	var xp0 := GameState.xp + GameState.level * 1000000
	var events := []
	var cb := func(id: StringName, data: Dictionary) -> void:
		if id == &"chest_opened":
			events.append(data)
	GameState.game_event.connect(cb)
	var expect := ChestLogic.roll_loot(world, SEED, cell, String(ch["tier"]))
	_dug(cell, "", false)
	GameState.game_event.disconnect(cb)
	check("выкопал клетку сундука — открыт", MechState.chest_opened(cell))
	check("событие chest_opened ушло в шину", events.size() == 1 and events[0]["tier"] == ch["tier"])
	var all_in := true
	for id in (expect["items"] as Dictionary).keys():
		if GameState.get_item_count(String(id)) < int(expect["items"][id]):
			all_in = false
	check("добыча легла в рюкзак", all_in)
	check("опыт начислен", GameState.xp + GameState.level * 1000000 > xp0)
	check("ступень записана в сейв", MechState.opened_count(String(ch["tier"])) == 1)
	var inv_before := GameState.inventory.duplicate()
	_dug(cell, "", false)
	check("повторно сундук не открывается", GameState.inventory == inv_before)

	# рюкзак полон → остаток в сундуке, подбирается рядом
	GameState.inventory.clear()
	var ch2 := {}
	for b in range(60, 200):
		ch2 = d.chest_for_band(b)
		if not ch2.is_empty() and String(ch2["tier"]) == "iron":
			break
	var cell2: Vector2i = ch2["cell"]
	GameState.inventory["lead"] = 20   # 60 кг — рюкзак забит
	_dug(cell2, "", false)
	var left := MechState.chest_left(cell2)
	check("полный рюкзак: добыча осталась в сундуке", not left.is_empty())
	check("сундук с остатком в списке", MechState.chests_with_loot().has(cell2))
	GameState.inventory.clear()
	p.x = cell2.x + 5.5
	p.y = cell2.y + 0.5
	d.step(0.3)
	check("далеко от сундука — остаток не подбирается", not MechState.chest_left(cell2).is_empty())
	p.x = cell2.x + 1.5
	d.step(0.3)
	check("рядом и есть место — остаток в рюкзаке", MechState.chest_left(cell2).is_empty() and not GameState.inventory.is_empty())

	# жадность: fever_s секунд копки, клетка — и руда двойная, герой ×7
	GameState.inventory.clear()
	d.streak.reset()
	_dug(Vector2i(0, 60), "", false)
	p.digging = {"x": 1, "y": 60, "t": 0.0, "total": 999.0, "type": TileTypes.Type.STONE}
	for i in range(int(ceil(d.streak.fever_s / 0.5))):
		d.step(0.5)
	p.digging = null
	_dug(Vector2i(1, 60), "", false)
	check("%.0f с копки и клетка — жадность" % d.streak.fever_s, d.streak.in_greed() and int(d.stats["fevers"]) == 1)
	check("герой узнал о жадности сразу", is_equal_approx(p.greed_mult, 7.0))
	GameState.add_item("silver", 1)   # копка кладёт свою штуку сама (Player), режиссёр — сверху
	_dug(Vector2i(5, 61), "silver", true)
	check("руда в жадности — вторая штука сверху", GameState.get_item_count("silver") == 2)
	check("счётчик добычи сверху в сейве", MechState.stat("bonus_items") >= 1 and MechState.stat("fevers") == 1)
	# жадность идёт по часам: 3 с — и всё
	p.digging = null
	d.step(3.1)
	check("через 3 с жадность кончилась", not d.streak.in_greed() and is_equal_approx(p.greed_mult, 1.0))
	# дом рвёт серию
	for i in range(10):
		_dug(Vector2i(6, 62), "", false)
	GameState.house_is_indoors = true
	d.step(0.1)
	GameState.house_is_indoors = false
	check("зашёл домой — серия сброшена", d.streak.count == 0 and d.streak.work == 0.0)

	# мастерство: звезда, опыт, двойная добыча детерминирована
	MechState.root()["mastery"] = {}
	var stars := []
	var on_star := func(item: String, star: int) -> void: stars.append([item, star])
	d.star_gained.connect(on_star)
	var lvl_xp0 := GameState.xp + GameState.level * 1000000
	for i in range(10):
		_dug(Vector2i(7, 63), "copper", true)
	check("10 меди — первая звезда", stars.size() == 1 and stars[0] == ["copper", 1])
	check("за звезду — опыт", GameState.xp + GameState.level * 1000000 > lvl_xp0)
	check("звезда записана", MechState.stars_granted("copper") == 1)
	d.star_gained.disconnect(on_star)
	# 5 звёзд → 10% двойной добычи; генератор от сида — число повторяемо
	MechState.root()["mastery"]["n"]["nickel"] = 1500
	MechState.set_stars_granted("nickel", 5)
	d.rng.seed = 99
	var before_items := int(d.stats["mastery_items"])
	GameState.inventory.clear()
	for i in range(1000):
		_dug(Vector2i(8, 64), "nickel", true)
		if GameState.get_item_count("nickel") > 10:
			GameState.inventory.clear()
	var extra := int(d.stats["mastery_items"]) - before_items
	check("пять звёзд никеля: ~10%% двойной добычи (%d из 1000)" % extra, extra > 70 and extra < 130)
	d.rng.seed = 99
	var before2 := int(d.stats["mastery_items"])
	for i in range(1000):
		_dug(Vector2i(8, 64), "nickel", true)
		if GameState.get_item_count("nickel") > 10:
			GameState.inventory.clear()
	check("тот же сид — то же число двойных", int(d.stats["mastery_items"]) - before2 == extra)

	# меню и журнал
	var entry := {}
	for e in MenuRegistry.entries():
		if e["id"] == "journal":
			entry = e
	check("пункт «Журнал» в меню «•••»", not entry.is_empty() and bool((entry["visible"] as Callable).call()))
	check("бейдж — новые записи журнала", int((entry["badge"] as Callable).call()) > 0)
	d.journal.open()
	check("журнал открыт, герой стоит", d.journal.is_open() and p.frozen)
	check("открытый журнал гасит бейдж", MechState.unseen_count() == 0)
	d.journal._set_tab(JournalScreen.TAB_CHESTS)
	check("вкладка тайников строится", d.journal._body != null)
	d.journal.close()
	await _frames(1)
	check("журнал закрыт, герой снова ходит", not d.journal.is_open() and not p.frozen)

	# испорченный сейв: мусор в ext["mechanics"] не роняет ни чтение, ни копку
	for junk in ["мусор", 42, [1, 2], {"chests": 5, "mastery": {"n": [1], "stars": "x"}, "stats": null},
			{"chests": {"opened": {"1,2": 3.5, "a,b": "gold"}, "left": {"3,4": "x", "5,6": {"iron_ore": "много"}}}}]:
		GameState.ext["mechanics"] = junk
		var ok := MechState.opened_count() >= 0 and MechState.opened_count("gold") >= 0 \
			and MechState.mastery_count("iron_ore") >= 0 and MechState.unseen_count() >= 0 \
			and MechState.chests_with_loot() is Array and MechState.chest_left(Vector2i(5, 6)).is_empty()
		_dug(Vector2i(9, 65), "iron_ore", true)
		d.step(0.3)
		check("мусор в сейве (%s) не ломает механики" % str(junk).left(24), ok)

	# сброс игры стирает механики
	GameState.reset_progress()
	check("сброс прогресса стирает механики", not GameState.ext.has("mechanics") or MechState.opened_count() == 0)
	GameState.world_seed = SEED
	StoryState.set_flag("food_ordered", false)
	host.queue_free()
	await _frames(1)


# ---------------------------------------------------------------------------
# Настоящая сцена: подключение в main.tscn, слой сундуков над тайлами, вид в мире
# ---------------------------------------------------------------------------

func _test_main_scene() -> void:
	GameState.reset_progress()
	GameState.world_seed = SEED
	for id in ["intro_grandpa", "intro_boy"]:
		StoryState.mark_seen(id)
	StoryState.set_flag("food_ordered", true)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	var d: MechDirector = main.get_node_or_null("MechDirector")
	check("main.tscn поднимает режиссёра механик", d != null)
	if d == null:
		return
	var wv: Node = main.view_root.get_node("WorldView")
	check("сундуки рисуются сразу над тайлами (под героем и светом)",
		d.chest_layer.get_index() == wv.get_index() + 1 and d.chest_layer.get_index() < main.player.get_index())
	var ch := {}
	for b in range(4, 40):
		ch = d.chest_for_band(b)
		if not ch.is_empty():
			break
	var cell: Vector2i = ch["cell"]
	# серый туман сундук не выдаёт, полный — показывает
	main.player.x = cell.x + 0.5
	main.player.y = cell.y - 2.5
	main.fog.reveal_terrain(cell.x + 0.5, cell.y + 0.5, 1)
	d.chest_layer._collect()
	check("в сером тумане сундука не видно", d.chest_layer.entries().is_empty())
	main.fog.reveal_resources(cell.x + 0.5, cell.y + 0.5, 1)
	d.chest_layer._collect()
	check("в полном обзоре сундук виден", d.chest_layer.entries().size() >= 1)
	main.world.dig_cell(cell.x, cell.y)
	_dug(cell, "", false)
	d.chest_layer._collect()
	var e := {}
	for x in d.chest_layer.entries():
		if x["cell"] == cell:
			e = x
	check("открытый сундук лежит в выкопанной клетке (кадр «открыт»)", not e.is_empty() and int(e["frame"]) >= 2)
	main.queue_free()
	await _frames(30)   # звуки сцены доигрывают, иначе при выходе «утекают» их проигрыватели
	StoryState.set_flag("food_ordered", false)

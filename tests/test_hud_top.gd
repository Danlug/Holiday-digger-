extends Node
## test_hud_top — верх HUD (владелец 27.10): «сверху слева … иконка с лицом нашего героя, а не
## дурачка в каске. Часы убери с правого верхнего угла под его иконку, … а справа сверху как раз
## все полоски начнутся от верха экрана, а не после часов».
##
## Настоящая main.tscn после онбординга. Проверяем: (1) в кнопке «Герой» — лицо героя, вырезанное
## из его же листа стойки (art/character/…), а не значок «hero»; (2) часы — под портретом, в его
## столбике, а не в кошельке; (3) кошелёк справа и портрет слева начинаются от верхней границы
## безопасной зоны (HUD_MARGIN под вырезом), в т.ч. с смоделированным вырезом; (4) ни один виджет
## верха — портрет, опыт, часы, полоски, азарт, задание, задания дня, бак бура, термометр, курьер,
## монеты, доллары, вес, магазин, трекер проекта, глубина — не наезжает на другой, все на экране;
## баннер задания не заходит под бак и курьера. Узкий экран (224 единицы, как телефон 448×960) и
## широкий (окно headless), на огороде и в шахте со всеми плашками, плюс дом.
##
## Запуск:  godot --headless --path . res://tests/test_hud_top.tscn

const SEED := 4242
const NOTCH := 24.0

var failures := 0
var total := 0
var main: Node2D
var hud
var story
var tech_hud: Control
var courier: Control


func check(label: String, ok: bool, detail: String = "") -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label + ("" if detail.is_empty() else "  — " + detail))


func _ready() -> void:
	print("=== test_hud_top ===")
	HudSafeArea.debug_top = -1.0
	check("без выреза (не телефон) отступ безопасной зоны — 0", HudSafeArea.top(get_viewport()) == 0.0)
	await _boot()
	_check_portrait()
	_check_clock_place()
	for narrow in [true, false]:
		await _set_narrow(narrow)
		var tag := "узкий" if narrow else "широкий"
		await _surface()
		_check_layout("%s, огород" % tag, 0.0)
		await _mine()
		_check_layout("%s, шахта со всеми плашками" % tag, 0.0)
		await _check_objective("%s, шахта" % tag)
		HudSafeArea.debug_top = NOTCH
		hud._update_layout()
		await _settle()
		_check_layout("%s, шахта, вырез %d" % [tag, int(NOTCH)], NOTCH)
		await _check_objective("%s, шахта, вырез" % tag)
		HudSafeArea.debug_top = -1.0
		hud._update_layout()
		await _settle()
	await _set_narrow(true)
	await _check_house()
	HudSafeArea.debug_top = -1.0
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Кадры и явная перестановка тех, кто сверяется с HUD опросом раз в 0.4–0.5 с (шкала
## азарта, трекер проекта): тест не ждёт настоящих секунд.
func _settle() -> void:
	await _frames(3)
	if tech_hud != null:
		tech_hud.call("refresh")
	var meter := main.find_child("StreakMeter", true, false)
	if meter != null:
		meter.call("_place")
	var tracker := main.find_child("ProjectTracker", true, false) as ProjectTracker
	if tracker != null:
		tracker.sync()
	await _frames(2)


# ---------------------------------------------------------------------------
# Игра после онбординга
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
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(4)
	hud = main.hud
	story = main.get_node("StoryDirector")
	for f in ["intro_seen", "bars_introduced", "gold_taken", "foundation_broken", "food_ordered", "gold_sold",
			"backpack_owned", "death_seen", "robert_seen", "autodig_done", "workshop_seen"]:
		StoryState.set_flag(f)
	for sid in StoryData.scene_ids():
		StoryState.mark_seen(String(sid))
	GameState.house_tutorial_stage = 2
	for i in 6:
		if story.cutscene != null and story.cutscene.is_playing:
			story.cutscene.skip()
		await _frames(3)
	Settings.reduce_motion = true
	MetaState.sub("daily")["last"] = MetaState.today()
	var ms = MetaService.instance
	if ms != null and ms.popup.is_open():
		ms.popup.close()
	GameState.house_is_indoors = false
	hud.visible = true
	hud.set_process_input(true)
	hud.set_gauges_visible(true)
	GameState.grant_gear("backpack")
	tech_hud = main.find_child("TechHud", true, false) as Control
	var hs := main.find_child("HouseSystem", true, false)
	var badge = hs.get("_delivery_badge") if hs != null else null
	courier = badge.get("_holder") if badge != null else null
	if badge != null:
		badge.track("noodles", 900.0)   # курьер едет всё время теста
	await _frames(30)   # кнопка заданий дня опрашивает состояние раз в 0.4 с


## Узкий — как телефон 448×960 (ровно 224 единицы); широкий — окно как есть (headless шире).
func _set_narrow(narrow: bool) -> void:
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP if narrow \
		else Window.CONTENT_SCALE_ASPECT_EXPAND
	await _frames(3)
	hud._update_layout()
	await _settle()


func _surface() -> void:
	GameState.set_current_tool("shovel")
	main.player.y = 0.5
	GameState.player_depth = 0
	hud.set_objective("")
	await _settle()


## Все плашки разом: бур в руках (бак), жара на 760 (термометр), трекер проекта у витрины,
## азарт под бодростью, курьер, кнопка задания и задания дня, метка глубины.
func _mine() -> void:
	for id in ["gold", "iron_ore", "silver", "scrap", "peat", "energy_bar", "fuel_block", "noodles"]:
		GameState.inventory[id] = 2
	HintState.mark_seen("project_hand_drill")
	HintState.mark_seen("project_well")
	ProjectChain.set_tracked("drill_rig")
	GameState.grant_tool("hand_drill")
	GameState.set_current_tool("hand_drill")
	GameState.max_depth_reached = 760
	main.player.y = 760.5
	GameState.player_depth = 760
	var mech := main.get_node_or_null("MechDirector") as MechDirector
	if mech != null:
		mech.set_process(false)   # шкала азарта не тает
		mech.streak.work = 3.0
	hud.set_objective("Задание: загляни к могиле деда — у забора огорода, правее двери")
	await _frames(10)
	var tracker := main.find_child("ProjectTracker", true, false) as ProjectTracker
	if tracker != null:
		tracker.sync()
	await _settle()


# ---------------------------------------------------------------------------
# Портрет
# ---------------------------------------------------------------------------

func _check_portrait() -> void:
	var btn: Button = hud._hero_button
	var face := btn.get_node_or_null("Portrait") as HudPortrait
	check("в кнопке «Герой» — портрет (HudPortrait), а не значок «мальчик в каске»",
		face != null and btn.icon == null)
	if face == null:
		return
	check("портрет под бейджами: уровень и «+» рисуются поверх лица", face.get_index() == 0)
	var side := int(minf(face.size.x, face.size.y) - HudPortrait.INSET * 2.0)
	var tex := HudPortrait.face_texture(side)
	check("лицо вырезано из листа героя (art/character/…), того же, что ходит по миру",
		tex != null and tex.atlas != null and tex.atlas.resource_path == HudPortrait.SHEET
		and HudPortrait.SHEET.begins_with("res://art/character/"))
	check("кадр лица — квадрат %d×%d, пиксель листа = единица экрана (без дробного масштаба)" % [side, side],
		tex != null and tex.region.size == Vector2(side, side) and side >= 30)
	if tex == null:
		return
	var img: Image = tex.atlas.get_image()
	if img.is_compressed():
		img.decompress()
	var frame := mini(img.get_width(), img.get_height())
	var r := tex.region
	check("кадр — внутри первого кадра стойки", r.position.x >= 0 and r.position.y >= 0
		and r.end.x <= frame and r.end.y <= frame)
	var crown := -1
	for y in frame:
		for x in frame:
			if img.get_pixel(x, y).a > 0.5:
				crown = y
				break
		if crown >= 0:
			break
	var opaque := 0
	for y in range(int(r.position.y), int(r.end.y)):
		for x in range(int(r.position.x), int(r.end.x)):
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
	var c := r.get_center()
	check("верх кадра — у макушки героя (кадр по голове, а не по ногам или пустоте)",
		crown >= 0 and absf(r.position.y - crown) <= HudPortrait.CROWN_CUT + 0.5, "макушка %d, кадр %s" % [crown, r])
	check("в центре кадра — лицо (непрозрачно), голова занимает кадр",
		img.get_pixel(int(c.x), int(c.y)).a > 0.5 and opaque > int(r.get_area() * 0.5),
		"заполнено %d из %d" % [opaque, int(r.get_area())])
	# Середина кадра (половина стороны) — лицо: больше трети пикселей тёплого тона кожи,
	# а не волосы, футболка, ноги или пустота.
	var skin := 0
	var probe := Rect2(r.position + r.size * 0.25, r.size * 0.5)
	for y in range(int(probe.position.y), int(probe.end.y)):
		for x in range(int(probe.position.x), int(probe.end.x)):
			var p := img.get_pixel(x, y)
			if p.a > 0.5 and p.r > p.b + 0.12 and p.r > 0.55:
				skin += 1
	check("в середине кадра — лицо (кожа), а не волосы, футболка или пустота",
		skin > int(probe.get_area() / 3.0), "кожи %d из %d" % [skin, int(probe.get_area())])


func _check_clock_place() -> void:
	var clock: Control = hud._clock_box
	check("часы — не в кошельке справа", not hud._purse_box.is_ancestor_of(clock))
	check("часы — в столбике портрета (под кнопкой «Герой» и полоской опыта)",
		hud._hero_button.get_parent().is_ancestor_of(clock)
		and clock.get_index() > hud._xp_bar.get_index())
	check("часы показывают время «ЧЧ:ММ»", RegEx.create_from_string("^\\d\\d:\\d\\d$").search(
		hud._clock_label.text) != null, hud._clock_label.text)


# ---------------------------------------------------------------------------
# Раскладка верха
# ---------------------------------------------------------------------------

func _rect(c: Control) -> Rect2:
	return c.get_global_rect()


func _add(out: Dictionary, name: String, c: Control) -> void:
	if c != null and is_instance_valid(c) and c.is_visible_in_tree():
		out[name] = _rect(c)


func _widgets() -> Dictionary:
	var out := {}
	_add(out, "портрет", hud._hero_button)
	_add(out, "опыт", hud._xp_bar)
	_add(out, "часы", hud._clock_box)
	_add(out, "HP", hud._hp_bar)
	_add(out, "голод", hud._hunger_bar)
	_add(out, "бодрость", hud._stamina_bar)
	_add(out, "задание", hud._quest_button)
	_add(out, "задания дня", main.find_child("DailyTasksButton", true, false) as Control)
	_add(out, "азарт", main.find_child("StreakMeter", true, false) as Control)
	_add(out, "монеты", hud._coins_pill)
	_add(out, "доллары", hud._dollars_pill)
	_add(out, "вес", hud._load_pill)
	_add(out, "магазин", hud._shop_btn)
	_add(out, "трекер проекта", main.find_child("ProjectTracker", true, false) as Control)
	_add(out, "глубина", hud._depth_box)
	if tech_hud != null:
		_add(out, "бак бура", tech_hud.get("_fuel_btn"))
		_add(out, "термометр", tech_hud.get("_heat_btn"))
	_add(out, "курьер", courier)
	return out


func _check_layout(tag: String, safe: float) -> void:
	var vp: Vector2 = hud.get_viewport_rect().size
	var w := _widgets()
	var want := ["портрет", "опыт", "часы", "HP", "голод", "бодрость", "монеты", "доллары", "вес", "магазин",
		"задания дня", "курьер"]
	if tag.contains("шахта"):
		want += ["бак бура", "термометр", "трекер проекта", "азарт", "задание", "глубина"]
	var miss: Array = []
	for n in want:
		if not w.has(n):
			miss.append(n)
	check("[%s] на экране все виджеты верха" % tag, miss.is_empty(), "нет: " + str(miss))
	print("  [%s] экран %s: %s" % [tag, vp, ", ".join(w.keys())])

	var top: float = hud.HUD_MARGIN + safe
	var hero: Rect2 = w.get("портрет", Rect2())
	var coins: Rect2 = w.get("монеты", Rect2())
	check("[%s] портрет — от верхней границы безопасной зоны (y=%d)" % [tag, int(top)],
		absf(hero.position.y - top) < 0.5, str(hero))
	check("[%s] кошелёк справа начинается от верха (монеты на y=%d, не после часов)" % [tag, int(top)],
		absf(coins.position.y - top) < 0.5, str(coins))
	check("[%s] монеты — первая плашка справа, у правого края" % tag,
		absf(coins.end.x - (vp.x - 8.0)) < 0.5 and hud._purse_box.get_child(0) == hud._coins_pill)

	var clock: Rect2 = w.get("часы", Rect2())
	var xp: Rect2 = w.get("опыт", Rect2())
	check("[%s] часы — под портретом и полоской опыта" % tag,
		clock.position.y >= maxf(hero.end.y, xp.end.y) - 0.5 and clock.position.y - hero.end.y < 16.0,
		"%s под %s" % [clock, hero])
	check("[%s] часы — в ширину портрета, по его центру" % tag,
		clock.position.x >= hero.position.x - 0.5 and clock.end.x <= hero.end.x + 0.5
		and absf(clock.get_center().x - hero.get_center().x) < 1.0, "%s / %s" % [clock, hero])
	check("[%s] правый верхний угол свободен от часов" % tag, clock.get_center().x < vp.x * 0.5)

	var off: Array = []
	var notch: Array = []
	for n in w:
		var r: Rect2 = w[n]
		if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > vp.x + 0.5 or r.end.y > hud.stage_rect.size.y + 0.5:
			off.append("%s %s" % [n, r])
		if r.position.y < safe - 0.5:
			notch.append("%s %s" % [n, r])
	check("[%s] все виджеты верха — на экране" % tag, off.is_empty(), str(off))
	check("[%s] ничего не заходит под вырез (y ≥ %d)" % [tag, int(safe)], notch.is_empty(), str(notch))

	var hits: Array = []
	var names: Array = w.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			if (w[names[i]] as Rect2).intersects(w[names[j]]):
				hits.append("%s × %s" % [names[i], names[j]])
	check("[%s] ни один виджет не наезжает на другой" % tag, hits.is_empty(), str(hits))

	# Левый столбик сверху вниз: портрет → задания → бак → термометр → курьер.
	var order := ["портрет", "задание", "задания дня", "бак бура", "термометр", "курьер"]
	var prev := ""
	var bad: Array = []
	for n in order:
		if not w.has(n):
			continue
		if not prev.is_empty() and (w[n] as Rect2).position.y < (w[prev] as Rect2).end.y:
			bad.append("%s выше низа «%s»" % [n, prev])
		prev = n
	check("[%s] левый столбик идёт сверху вниз без нахлёста" % tag, bad.is_empty(), str(bad))
	var ragged: Array = []
	for n in ["портрет", "часы", "задание", "задания дня", "бак бура", "термометр"]:
		if w.has(n) and absf((w[n] as Rect2).position.x - hud.HUD_MARGIN) > 0.5:
			ragged.append("%s x=%d" % [n, int((w[n] as Rect2).position.x)])
	check("[%s] левый край столбика ровный (x=%d)" % [tag, int(hud.HUD_MARGIN)], ragged.is_empty(), str(ragged))


## Баннер задания (6 с) — под обоими кластерами и правее бака/курьера: их слои выше HUD.
func _check_objective(tag: String) -> void:
	hud._show_objective_banner()
	await _frames(2)
	var panel: Control = hud._objective_panel
	if not panel.is_visible_in_tree():
		check("[%s] баннер задания показан" % tag, false)
		return
	var r := _rect(panel)
	var hits: Array = []
	for n in ["бак бура", "термометр", "курьер", "портрет", "задания дня", "монеты", "магазин", "трекер проекта",
			"глубина"]:
		var w := _widgets()
		if w.has(n) and r.intersects(w[n]):
			hits.append(n)
	check("[%s] баннер задания не заходит под бак, термометр, курьера и верхние кластеры" % tag,
		hits.is_empty(), "%s: %s" % [r, hits])
	check("[%s] баннер задания не уже половины экрана" % tag,
		r.size.x >= hud.get_viewport_rect().size.x * 0.5, str(r))


## Дом: HUD спрятан, курьер — на прежнем месте под шапкой дома, не уезжает к верху экрана.
func _check_house() -> void:
	GameState.house_is_indoors = true
	hud.visible = false
	await _settle()
	check("дома HUD скрыт — столбика нет, бак и термометр спрятаны",
		not hud._gauges_box.is_visible_in_tree() and not (tech_hud.get("_fuel_btn") as Control).visible)
	check("дома курьер — на своём месте (как до переезда часов)",
		courier != null and courier.is_visible_in_tree()
		and courier.position == HouseDeliveryBadge.POS, str(courier.position if courier != null else null))
	GameState.house_is_indoors = false
	hud.visible = true
	await _settle()

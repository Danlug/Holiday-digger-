extends Node
## test_screenshot_house_look — разовый QA-инструмент (не автотест): двор у дома
## на настоящем рендере — трава перед домом и рост сюжетных актёров рядом с героем.
##
##   XDG_DATA_HOME=$PWD/.godot/xdg xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_house_look.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [вид ...]
##
## Виды (по умолчанию все):
##   yard:X        — обычная игра, герой стоит на поверхности в столбце X (дом внука);
##   shack:X       — то же в эпоху деда (лачуга, старый забор), без сцены;
##   cast:X        — у дома внука рядом с героем поставлены все актёры сюжета
##                   (бабушки, дед, Роберт) — сравнить рост на одном кадре;
##   scene:ID      — сюжетная сцена, кадр на каждой реплике (как test_screenshot_story);
##   tapgrow       — intro_boy, где «рост» мальчика пролистан тапом (так играл владелец).

const SHOTS_PER_SCENE := 40

var _out_dir := "/tmp/house_look"
var _spec: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if i == 0:
			_out_dir = args[0]
		else:
			_spec.append(args[i])
	if _spec.is_empty():
		_spec = ["yard:8", "yard:13", "yard:17", "shack:8", "shack:12", "cast:12",
			"tapgrow", "scene:intro_grandpa"]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	get_window().size = Vector2i(448, 960)

	StoryState.delete_from_disk()
	GameState.reset_progress()
	GameState.world_seed = 12345
	Settings.hints_enabled = false   # подсказки-знакомства закрывали бы ноги героя
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure",
			"workshop", "death", "backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2"]:
		StoryState.mark_seen(id)
	for e in StoryData.depth_scenes():
		StoryState.mark_seen(String(e.id))
	StoryState.set_flag("intro_seen")
	StoryState.set_flag("autodig_start_seen")
	StoryState.set_flag("bars_introduced")

	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _i in 6:
		await get_tree().process_frame
	var director: StoryDirector = main.find_child("StoryDirector", true, false)

	for item: String in _spec:
		var kind := item.get_slice(":", 0)
		var arg := item.get_slice(":", 1) if item.contains(":") else ""
		match kind:
			"yard":
				await _shoot_yard(main, "now", float(arg), "yard_%s" % arg)
			"shack":
				await _shoot_yard(main, "grandpa", float(arg), "shack_%s" % arg)
			"cast":
				await _shoot_cast(main, director, float(arg))
			"scene":
				await _shoot_scene(director, arg, -1)
			"tapgrow":
				await _shoot_scene(director, "intro_boy", 3)
	print("test_screenshot_house_look: готово -> " + _out_dir)
	get_tree().quit(0)


func _close_daily_popup() -> void:
	var ms = MetaService.instance
	if ms != null and is_instance_valid(ms) and ms.popup.is_open():
		ms.popup.close()


func _set_era(main: Node2D, era: String) -> void:
	main.world.era = era
	GameState.era = era
	var bd := main.find_child("Backdrop", true, false)
	if bd != null and bd.has_method("set_era"):
		bd.call("set_era", era)


func _shoot_yard(main: Node2D, era: String, x: float, name: String) -> void:
	_set_era(main, era)
	var p = main.player
	p.x = x + 0.5
	p.y = 0.5
	p.vx = 0.0
	p.vy = 0.0
	GameState.game_clock_hours = 10.0
	for _k in 40:
		_close_daily_popup()
		await get_tree().process_frame
	_shot(name)
	_set_era(main, "now")


## Все актёры сюжета у дома внука рядом с героем — один кадр на сравнение роста.
func _shoot_cast(main: Node2D, director: StoryDirector, x: float) -> void:
	var p = main.player
	p.x = x + 0.5
	p.y = 0.5
	GameState.game_clock_hours = 10.0
	var view_root: Node = main.find_child("ViewRoot", true, false)
	var actors: Array = []
	var dx := 1.1
	for id in ["grandma_rich", "grandma_poor", "grandpa", "robert"]:
		var a := WorldActor.new()
		a.setup(id)
		a.x = p.x + dx
		a.y = 0.5
		a.flip = true
		view_root.add_child(a)
		actors.append(a)
		dx += 0.9
	var b := WorldActor.new()
	b.setup("boy")
	b.x = p.x - 1.1
	b.y = 0.5
	view_root.add_child(b)
	actors.append(b)
	for _k in 30:
		_close_daily_popup()
		await get_tree().process_frame
	_shot("cast_%d" % int(x))
	for a in actors:
		a.queue_free()


## tap_at >= 0 — игрок-торопыга: каждый кадр пролистывается тапом сразу, а
## развёртку "grow" (кадр с этим индексом) он пролистывает на третьем кадре —
## так играл владелец. Иначе таймерные кадры (ходьба, карточки) доигрываются
## честно, чтобы актёры дошли до своих мест.
func _shoot_scene(director: StoryDirector, id: String, tap_at: int) -> void:
	director.play(id)
	var cs := director.cutscene
	var shot := 0
	var guard := 0
	var hasty := tap_at >= 0
	var prefix := id if not hasty else id + "_tapgrow"
	while cs.is_playing and guard < 6000:
		guard += 1
		await get_tree().process_frame
		if cs._typing:
			cs._line.visible_ratio = 1.0
			cs._typing = false
		if hasty and cs._index == tap_at and cs._beat_timer > 0.0:
			for _k in 3:
				await get_tree().process_frame
			cs._waiting_tap = false
			cs._beat_timer = 0.0
			cs._advance()
			continue
		if cs._waiting_tap or cs._beat_timer > 0.0:
			if not hasty and cs._beat_timer > 0.0 and not cs._waiting_tap:
				continue
			cs._beat_timer = 0.0
			for _k in 12:
				await get_tree().process_frame
			if shot < SHOTS_PER_SCENE:
				_shot("%s_%02d" % [prefix, shot])
				shot += 1
			cs._waiting_tap = false
			cs._tap_target.visible = false
			cs._advance()
	cs.skip()
	for _k in 3:
		await get_tree().process_frame


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(name + ".png"))

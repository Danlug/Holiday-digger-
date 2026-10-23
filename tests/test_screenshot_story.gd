extends Node
## test_screenshot_story — разовый QA-инструмент (не автотест): поднимает настоящую
## main-сцену и снимает кадры сюжетных сцен и экрана дневника на реальном рендере.
##
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_story.tscn --rendering-driver opengl3 -- /каталог сцена1 сцена2 ...
##
## Первый аргумент после "--" — каталог, остальные — id сцен (по умолчанию все новые).
## Спец-имена: grave (могила во дворе), diary (экран дневника).
## Снимок делается на каждой реплике/карточке сцены, но не больше SHOTS_PER_SCENE.

const SHOTS_PER_SCENE := 6

var _out_dir := "/tmp/story_shots"
var _ids: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if i == 0:
			_out_dir = args[0]
		else:
			_ids.append(args[i])
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	get_window().size = Vector2i(448, 960)

	StoryState.delete_from_disk()
	GameState.reset_progress()
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure",
			"workshop", "death", "backpack", "robert"]:
		StoryState.mark_seen(id)
	StoryState.set_flag("intro_seen")
	StoryState.set_flag("autodig_start_seen")
	StoryState.set_flag("bars_introduced")
	StoryState.set_flag("hatch_built")
	GameState.house_hatch_built = true

	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _i in 6:
		await get_tree().process_frame
	var director: StoryDirector = main.find_child("StoryDirector", true, false)

	for id: String in _ids:
		match id:
			"grave":
				await _shoot_grave(main)
			"diary":
				await _shoot_diary(main)
			_:
				await _shoot_scene(director, id)

	print("test_screenshot_story: готово -> " + _out_dir)
	get_tree().quit(0)


func _shoot_scene(director: StoryDirector, id: String) -> void:
	if not StoryData.has_scene(id):
		print("нет сцены ", id)
		return
	director.play(id)
	var cs := director.cutscene
	var shot := 0
	var guard := 0
	while cs.is_playing and guard < 400:
		guard += 1
		await get_tree().process_frame
		if cs._typing:
			cs._line.visible_ratio = 1.0
			cs._typing = false
		if cs._waiting_tap or cs._beat_timer > 0.0:
			for _k in 12:
				await get_tree().process_frame
			if shot < SHOTS_PER_SCENE:
				_shot("%s_%02d" % [id, shot])
				shot += 1
			cs._waiting_tap = false
			cs._beat_timer = 0.0
			cs._tap_target.visible = false
			cs._advance()
	cs.skip()
	for _k in 3:
		await get_tree().process_frame


func _shoot_grave(main: Node) -> void:
	var player: Node2D = main.player
	player.x = 13.2
	player.y = 0.5
	for _k in 12:
		await get_tree().process_frame
	_shot("grave_near")
	player.x = 15.5
	for _k in 6:
		await get_tree().process_frame
	_shot("grave_far")


func _shoot_diary(main: Node) -> void:
	var site: Node = main.find_child("GraveSite", true, false)
	if site == null:
		print("нет GraveSite")
		return
	site.open_diary()
	for _k in 12:
		await get_tree().process_frame
	_shot("diary")


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(name + ".png"))

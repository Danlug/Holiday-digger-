extends Node
## test_screenshot_dialogue — разовый QA-инструмент (не автотест): снимает вид диалогов,
## карточек, титров и кнопки «Пропустить» на реальном рендере.
##
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_dialogue.tscn --rendering-driver opengl3 -- /каталог [масштаб] [en] [calm]
##
## масштаб: 1 — окно 224×480, 2 — 448×960 (по умолчанию 2). en — английский текст.
## calm — «меньше движения» включено. Снимки: <имя>_x<масштаб>.png.
## Сцены играются настоящим CutscenePlayer на настоящей карте; кроме них снимаются
## синтетические случаи (самая длинная реплика, два говорящих подряд, состояния кнопки).

const SETTLE_SEC := 0.45

var _out_dir := "/tmp/dialogue_shots"
var _scale := 2
var _calm := false
var _en := false
var _suffix := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	for i in range(1, args.size()):
		match String(args[i]):
			"1", "2":
				_scale = int(args[i])
			"en":
				_en = true
			"calm":
				_calm = true
	_suffix = "_x%d%s%s" % [_scale, "_en" if _en else "", "_calm" if _calm else ""]
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	get_window().size = Vector2i(224 * _scale, 480 * _scale)
	Settings.reduce_motion = _calm
	Settings.language = "en" if _en else "ru"

	StoryState.delete_from_disk()
	GameState.reset_progress()
	for id in ["intro_grandpa", "intro_boy", "autodig_start", "autodig_done", "dud_treasure",
			"workshop", "death", "backpack", "robert", "fuel_station", "sleep_lesson_1", "sleep_lesson_2"]:
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
	if _en:
		StoryText.load_locale("en")
	for e in StoryData.depth_scenes():
		StoryState.mark_seen(String(e.id))
	StoryState.mark_seen("first_artifact")
	StoryState.mark_seen("grave_call")

	var wanted: Array = []
	for i in range(1, args.size()):
		if not (String(args[i]) in ["1", "2", "en", "calm"]):
			wanted.append(String(args[i]))
	if wanted.is_empty():
		wanted = ["synthetic", "intro_grandpa", "intro_boy", "backpack", "workshop", "diary_first", "whisper_1200",
				"grandma_returns", "fuel_station", "sleep_lesson_2", "ending", "credits", "skip"]
	for id in wanted:
		match String(id):
			"synthetic":
				await _synthetic(director)
			"skip":
				await _skip_states(director)
			_:
				await _scene(director, String(id))
	print("test_screenshot_dialogue: готово -> " + _out_dir)
	get_tree().quit(0)


func _settle(sec: float = SETTLE_SEC) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(name + _suffix + ".png"))


## Прогон сцены: на каждом кадре «ждём тапа» — снимок после того, как печать дописана.
## Первую реплику снимаем ещё и посреди печати.
func _scene(director: StoryDirector, id: String) -> void:
	if not StoryData.has_scene(id):
		print("нет сцены ", id)
		return
	director.play(id)
	var cs := director.cutscene
	var shot := 0
	var guard := 0
	var mid_done := false
	while cs.is_playing and guard < 500:
		guard += 1
		await get_tree().process_frame
		if cs._typing and not mid_done and cs._dlg.line.text.length() > 30:
			mid_done = true
			await _settle(0.25)
			_shot("%s_%02d_typing" % [id, shot])
		if cs._typing:
			cs._dlg.finish_typing()
		if cs._waiting_tap or cs._beat_timer > 0.0:
			await _settle()
			_shot("%s_%02d" % [id, shot])
			shot += 1
			cs._waiting_tap = false
			cs._beat_timer = 0.0
			cs._tap_target.visible = false
			cs._advance()
	cs.skip()
	await _settle(0.5)
	director.player.x = 15.5
	director.player.y = 0.5


## Реплики, собранные руками: самая длинная, две подряд, ненайденный говорящий.
func _synthetic(director: StoryDirector) -> void:
	var cs := director.cutscene
	cs.abort()
	cs.scene_id = "synthetic"
	cs.is_playing = true
	cs._root.visible = true
	cs._skip_btn.visible = true
	cs._layout()
	cs._bars.open(cs._last_vp, false)

	var longest := ""
	var longest_key := ""
	var longest_who := ""
	for sid in StoryData.scene_ids():
		for b in StoryData.beats(String(sid)):
			if String(b.get("t", "")) in ["say", "narr"]:
				var t := StoryText.get_text(String(b.get("text", "")))
				if t.length() > longest.length():
					longest = t
					longest_key = String(b.get("text", ""))
					longest_who = String(b.get("who", ""))
	cs._run_beat({"t": "narr", "text": longest_key})
	cs._dlg.finish_typing()
	await _settle()
	_shot("syn_longest_narr")
	cs._run_beat({"t": "say", "who": "grandma_rich", "text": longest_key})
	cs._dlg.finish_typing()
	await _settle()
	_shot("syn_longest_grandma")

	var lines := [
		["boy", "intro_boy.s3"], ["grandma_rich", "intro_boy.g1"], ["boy", "intro_boy.s4"],
		["robert", "backpack.r1"], ["voice", "whisper_1200.v1"], ["parents", "intro_boy.p1"],
		["grandpa", "intro_grandpa.s3"], ["grandma_poor", "intro_grandpa.g1"],
	]
	var i := 0
	for pair in lines:
		var key := String(pair[1])
		if not StoryText.has_key(key):
			continue
		cs._run_beat({"t": "say", "who": pair[0], "text": key})
		await _settle(0.2)
		_shot("syn_say_%02d_%s_typing" % [i, pair[0]])
		cs._dlg.finish_typing()
		await _settle()
		_shot("syn_say_%02d_%s" % [i, pair[0]])
		i += 1
	# Все лица одного говорящего в ряд: контроль выражений.
	for face in DialogueCast.FACES:
		cs._dlg.show_line("boy", StoryText.get_text("speaker.boy"), "...", {"face": face})
		cs._dlg.finish_typing()
		await _settle(0.25)
		_shot("syn_face_%s" % face)
	cs.abort()
	await _settle(0.5)


## Кнопка «Пропустить»: покой, подсказка после касания, кольцо удержания.
func _skip_states(director: StoryDirector) -> void:
	var cs := director.cutscene
	cs.abort()
	director.play("grandma_returns")
	await _settle(0.8)
	cs._dlg.finish_typing()
	await _settle()
	_shot("skip_idle")
	cs._skip_btn.press()
	cs._skip_btn.release()
	await _settle(0.3)
	_shot("skip_hint")
	cs._skip_btn.press()
	await _settle(0.35)
	_shot("skip_holding")
	cs._skip_btn.release()
	cs.abort()
	await _settle(0.5)

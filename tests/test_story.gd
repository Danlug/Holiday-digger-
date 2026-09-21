extends SceneTree
## test_story.gd — проверка данных сюжета: режиссура (data/story.json) и
## тексты (data/story_ru.json) должны сходиться между собой и с артом.
##
## Запуск:
##   godot --headless --path . --script res://tests/test_story.gd
##
## Автолоады здесь не нужны и не используются (SceneTree с --script их не
## гарантирует): StoryData и StoryText читают файлы напрямую.

const KNOWN_BEATS := ["card", "narr", "say", "show", "hide", "prop", "clear",
	"mood", "wait", "fade", "item", "tap", "move", "shake", "daynight", "grow",
	# Режим "мир" (см. scripts/story/cutscene_player.gd:world_mode) — сцена
	# играет на живой карте, эти кадры двигают/копают WorldActor'а по-настоящему.
	"world_actor", "world_walk", "world_dig", "world_fall", "clock"]
const KNOWN_EFFECTS := ["flag", "tool", "coins", "dollars", "xp", "artifact",
	"sleep", "stamina", "hunger", "teleport_home", "enter_house", "toast", "hook"]
## Сцены, без которых сюжет из ГДД разделов 2 и 9 не собирается.
const REQUIRED_SCENES := ["intro_grandpa", "intro_boy", "autodig_start",
	"autodig_done", "dud_treasure", "workshop", "death", "backpack", "robert",
	"sleep_lesson_1", "sleep_lesson_2"]

var failures := 0
var total := 0


func _init() -> void:
	print("=== test_story.gd ===")
	StoryText.load_locale("ru")
	StoryData.ensure_loaded()

	_test_required_scenes()
	_test_beats_known()
	_test_effects_known()
	_test_texts_present()
	_test_art_present()
	_test_flags_wired()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	quit(0 if failures == 0 else 1)


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _test_required_scenes() -> void:
	for id in REQUIRED_SCENES:
		check("есть сцена %s" % id, StoryData.has_scene(id))
	for id in REQUIRED_SCENES:
		check("в сцене %s есть кадры" % id, StoryData.beats(id).size() > 0)


func _test_beats_known() -> void:
	for id in StoryData.scene_ids():
		for beat in StoryData.beats(id):
			var t := String(beat.get("t", ""))
			check("%s: известный кадр '%s'" % [id, t], KNOWN_BEATS.has(t))


func _test_effects_known() -> void:
	for id in StoryData.scene_ids():
		for e in StoryData.effects(id):
			var d := String(e.get("do", ""))
			check("%s: известный эффект '%s'" % [id, d], KNOWN_EFFECTS.has(d))


## Ни одна реплика не должна доехать до экрана ключом: get_text возвращает сам
## ключ, когда перевода нет, и такая строка сразу видна в игре как "intro.n1".
func _test_texts_present() -> void:
	var missing: Array = []
	for id in StoryData.scene_ids():
		var title := String(StoryData.scene(id).get("title", ""))
		if not title.is_empty() and not StoryText.has_key(title):
			missing.append(title)
		for beat in StoryData.beats(id):
			for field in ["text", "name"]:
				var key := String(beat.get(field, ""))
				if not key.is_empty() and not StoryText.has_key(key):
					missing.append(key)
			var who := String(beat.get("who", ""))
			if not who.is_empty():
				var sp := StoryData.actor_speaker_key(who)
				check("%s: у актёра '%s' есть подпись" % [id, who], not sp.is_empty())
				if not sp.is_empty() and not StoryText.has_key(sp):
					missing.append(sp)
		for e in StoryData.effects(id):
			var key2 := String(e.get("text", ""))
			if not key2.is_empty() and not StoryText.has_key(key2):
				missing.append(key2)
	check("все ключи текстов переведены", missing.is_empty(), str(missing))

	for key in ["ui.skip", "ui.autodig_banner"]:
		check("есть служебный текст %s" % key, StoryText.has_key(key))


## Катсцена молча пропускает отсутствующий спрайт (у Роберта его и нет), но
## тихо потерянный дед — это уже баг, а не сценарное решение.
func _test_art_present() -> void:
	for id in StoryData.scene_ids():
		for beat in StoryData.beats(id):
			match String(beat.get("t", "")):
				"show":
					var actor_id := String(beat.get("actor", ""))
					var path := StoryData.actor_sheet_path(actor_id, String(beat.get("pose", "idle")))
					if path.is_empty():
						continue  # актёр без спрайта — голос за кадром, так задумано
					check("%s: есть лист %s" % [id, path], ResourceLoader.exists(path))
				"grow":
					var g_actor := String(beat.get("actor", ""))
					var poses: Array = beat.get("poses", [])
					check("%s: у 'grow' есть список поз" % id, not poses.is_empty())
					for p in poses:
						var gpath := StoryData.actor_sheet_path(g_actor, String(p))
						check("%s: есть лист роста %s" % [id, gpath], ResourceLoader.exists(gpath))
				"prop":
					var prop := StoryData.prop(String(beat.get("id", "")))
					check("%s: реквизит '%s' описан" % [id, beat.get("id", "")], not prop.is_empty())
					var tex := String(prop.get("tex", ""))
					check("%s: есть картинка %s" % [id, tex], ResourceLoader.exists(tex))
				"item":
					var icon := String(beat.get("icon", ""))
					check("%s: есть иконка %s" % [id, icon], ResourceLoader.exists(icon))
				"mood":
					check("%s: настроение '%s' описано" % [id, beat.get("id", "")],
						not StoryData.mood(String(beat.get("id", ""))).is_empty())
				"world_actor", "world_dig":
					# world_dig без явного "pose" по умолчанию копает dig_shovel
					# (см. cutscene_player.gd:_world_start_dig) — тот же лист,
					# что и "show" молча пропускает, если актёра без спрайта нет
					# (Роберт, родители): по факту в мире сейчас есть только
					# дед/бабка, спрайт у них есть, и тихо потерять его нельзя.
					var wa_id := String(beat.get("actor", ""))
					var wa_pose := String(beat.get("pose", "dig_shovel" if String(beat.get("t", "")) == "world_dig" else "idle"))
					var wa_path := StoryData.actor_sheet_path(wa_id, wa_pose)
					if not wa_path.is_empty():
						check("%s: есть лист %s" % [id, wa_path], ResourceLoader.exists(wa_path))


## Флаги, по которым другие системы (дом, магазин, игрок) узнают о сюжете,
## должны кем-то ставиться — иначе они навсегда останутся ложью.
func _test_flags_wired() -> void:
	var produced: Array = []
	for id in StoryData.scene_ids():
		for e in StoryData.effects(id):
			if String(e.get("do", "")) == "flag":
				produced.append(String(e.get("id", "")))
	for flag in ["intro_seen", "bars_introduced", "backpack_owned", "hatch_built"]:
		check("флаг %s кто-то ставит" % flag, produced.has(flag))

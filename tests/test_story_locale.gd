extends Node
## test_story_locale.gd — английский перевод сюжета полон: набор ключей
## data/story_en.json совпадает с data/story_ru.json, нет пустых строк, плейсхолдеры
## на месте, а каждый ключ, на который ссылаются сцены и дневник, есть в обоих
## языках. Рядом — проверка, что StoryText действительно переключается.
##
## Запуск: godot --headless --path . res://tests/test_story_locale.tscn
## (сценой, а не --script: дневник читает GameState, нужны автозагрузки)

var failures := 0
var total := 0


func _ready() -> void:
	print("=== test_story_locale.gd ===")
	var ru := _load("res://data/story_ru.json")
	var en := _load("res://data/story_en.json")
	check("story_ru.json читается", not ru.is_empty())
	check("story_en.json читается", not en.is_empty())

	var missing_in_en: Array = []
	var missing_in_ru: Array = []
	for k in ru.keys():
		if not en.has(k):
			missing_in_en.append(k)
	for k in en.keys():
		if not ru.has(k):
			missing_in_ru.append(k)
	check("все ключи ru есть в en", missing_in_en.is_empty(), str(missing_in_en))
	check("лишних ключей в en нет", missing_in_ru.is_empty(), str(missing_in_ru))
	check("ключей поровну", ru.size() == en.size(), "%d против %d" % [ru.size(), en.size()])

	var empty: Array = []
	var untranslated: Array = []
	var bad_placeholders: Array = []
	var cyrillic_left: Array = []
	for k in en.keys():
		if String(k).begins_with("_") or k == "version" or k == "locale":
			continue
		var v := String(en[k])
		if v.strip_edges().is_empty():
			empty.append(k)
		if _has_cyrillic(v):
			cyrillic_left.append(k)
		if ru.has(k) and v == String(ru[k]):
			untranslated.append(k)
		if ru.has(k) and _placeholders(String(ru[k])) != _placeholders(v):
			bad_placeholders.append(k)
	check("в английском нет пустых строк", empty.is_empty(), str(empty))
	check("в английском не осталось кириллицы", cyrillic_left.is_empty(), str(cyrillic_left))
	check("английская строка не копия русской", untranslated.is_empty(), str(untranslated))
	check("плейсхолдеры %d/%s совпадают с русскими", bad_placeholders.is_empty(), str(bad_placeholders))
	check("локаль en объявлена", String(en.get("locale", "")) == "en")

	# Ссылки из режиссуры и дневника.
	StoryData.ensure_loaded()
	var used := _used_keys()
	var lost_ru: Array = []
	var lost_en: Array = []
	for k in used:
		if not ru.has(k):
			lost_ru.append(k)
		if not en.has(k):
			lost_en.append(k)
	check("все ключи сцен и дневника есть в ru", lost_ru.is_empty(), str(lost_ru))
	check("все ключи сцен и дневника есть в en", lost_en.is_empty(), str(lost_en))
	check("проверено больше 250 ссылок на тексты", used.size() > 250, str(used.size()))

	# Переключение языка в самом движке текстов.
	StoryText._reset_for_tests()
	StoryText.load_locale("ru")
	var ru_line := StoryText.get_text("grave_call.g5")
	StoryText.load_locale("en")
	var en_line := StoryText.get_text("grave_call.g5")
	check("StoryText.load_locale(en) отдаёт английскую реплику", en_line != ru_line and en_line == "Wash your hands first.", en_line)
	check("StoryText.locale() отвечает en", StoryText.locale() == "en")
	check("has_locale_file видит en и не видит выдуманный", StoryText.has_locale_file("en") and not StoryText.has_locale_file("xx"))
	StoryText.load_locale("xx")
	check("неизвестный язык откатывается на русский", StoryText.locale() == "ru")

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name,
		("  " + detail) if not ok and not detail.is_empty() else ""])


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


func _has_cyrillic(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			return true
	return false


func _placeholders(s: String) -> Array:
	var out: Array = []
	var i := 0
	while i < s.length() - 1:
		if s[i] == "%" and (s[i + 1] == "d" or s[i + 1] == "s"):
			out.append(s.substr(i, 2))
			i += 2
		else:
			i += 1
	return out


## Все ключи текстов, на которые ссылаются сцены (кадры, титулы, эффекты) и
## страницы дневника. Тот же список полей, что проверяет test_story.gd.
func _used_keys() -> Array:
	var keys: Dictionary = {}
	for id in StoryData.scene_ids():
		var sc := StoryData.scene(id)
		keys[String(sc.get("title", ""))] = true
		for b in StoryData.beats(id):
			for field in ["text", "name"]:
				keys[String(b.get(field, ""))] = true
			var who := String(b.get("who", ""))
			if not who.is_empty():
				keys[StoryData.actor_speaker_key(who)] = true
		for e in StoryData.effects(id):
			keys[String(e.get("text", ""))] = true
	for p in StoryDiary.pages():
		var pid := String(p.get("id", ""))
		keys[StoryDiary.text_key(pid, "text")] = true
		keys[StoryDiary.text_key(pid, "note")] = true
	for k in ["diary.title", "diary.page_n", "diary.sealed_depth", "diary.sealed_event",
			"diary.new_pages", "diary.close", "diary.prev", "diary.next", "grave.tip_title",
			"grave.tip_body", "grave.tip_diary_title", "grave.tip_diary_body", "grave.epitaph",
			"quest.grave", "ui.skip", "ui.tap_to_continue"]:
		keys[k] = true
	keys.erase("")
	return keys.keys()

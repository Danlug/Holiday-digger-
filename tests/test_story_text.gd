extends SceneTree
## test_story_text — «линтер» текстов сюжета: ловит то, что вычитка раунда 3
## (ГДД, «Тексты сцен: вычитка») поправила руками, чтобы оно не вернулось.
##
## Запуск: godot --headless --path . --script res://tests/test_story_text.gd
##
## Только проверяемое без ложных срабатываний: типографика (пробелы, кавычки,
## тире, многоточие, десятичная запятая), латиница внутри русских слов, слова
## без «ё» из короткого списка, двусмысленное «дедов-» (владелец прочёл
## «дедовой плитой» как «деловой»), пустые и обрубленные реплики, длина под
## окно диалога, ключ реплики ↔ говорящий (у Роберта — .rN, у бабки — .gN…),
## реплики Роберта короткие и все стоят в сценах. Смысл реплик не проверить
## скриптом — это вычитка глазами.
##
## Автозагрузки не нужны: JSON читается напрямую.

const SCENE_FILES := ["res://data/story.json", "res://data/story_arc.json"]
const SAY_MAX := {"ru": 160, "en": 190}
const CARD_MAX := 130
const ITEM_MAX := 210
const ROBERT_MAX_CHARS := 70
const ROBERT_MAX_WORDS := 7   # в одном предложении: «Роберт — одно-два слова за раз» (ГДД п.2)
## Первая буква суффикса ключа реплики (после последней точки) — кто говорит.
## «s» у деда — только в его собственной эпохе (intro_grandpa), иначе это внук.
const SPEAKER_LETTERS := {
	"robert": "r", "grandma_poor": "g", "grandma_rich": "g", "voice": "v",
	"parents": "p", "grandpa": "d", "grandpa_gear": "d", "boy": "s", "boy_gear": "s",
}
## Слова, которые в тексте пишутся только через «ё» (правило вычитки: ё везде).
const NEED_YO := ["еще", "ее", "нее", "пошел", "нашел", "ушел", "пришел", "зашел", "вошел", "шел",
	"черный", "черная", "черное", "черные", "желтый", "желтая", "желтое", "тяжелый", "тяжелая",
	"тяжелое", "зеленый", "зеленая", "зеленой", "теплый", "теплая", "темный", "легкий", "идет",
	"несет", "берет", "живет", "ждет", "найдет", "придет", "поймет"]

var failures := 0
var total := 0
var ru: Dictionary = {}
var en: Dictionary = {}
var scenes: Array = []


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _init() -> void:
	print("=== test_story_text ===")
	ru = _load("res://data/story_ru.json")
	en = _load("res://data/story_en.json")
	for path in SCENE_FILES:
		scenes.append_array(_load(path).get("scenes", []))
	check("тексты и сцены читаются", not ru.is_empty() and not en.is_empty() and scenes.size() > 15)

	_test_typography("ru", ru)
	_test_typography("en", en)
	_test_russian_only()
	_test_beats("ru", ru)
	_test_beats("en", en)
	_test_speaker_keys()
	_test_robert()
	_test_faces()
	_test_linter_catches()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	quit(0 if failures == 0 else 1)


func _load(path: String) -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


## Строки таблицы, кроме служебных полей.
func _texts(table: Dictionary) -> Dictionary:
	var out := {}
	for k in table.keys():
		var key := String(k)
		if key.begins_with("_") or key == "version" or key == "locale":
			continue
		out[key] = String(table[k])
	return out


# ---------------------------------------------------------------------------
# Типографика (оба языка)
# ---------------------------------------------------------------------------

func _test_typography(loc: String, table: Dictionary) -> void:
	var bad := {"empty": [], "spaces": [], "before_punct": [], "after_open": [], "quotes": [],
		"parens": [], "mixed": [], "dots": [], "repeat": []}
	for key in _texts(table).keys():
		var s := String(table[key])
		if s.strip_edges().is_empty():
			bad.empty.append(key)
			continue
		for p in _typography_problems(s, loc):
			bad[p].append(key)
	var tag := "[%s] " % loc
	check(tag + "нет пустых строк", bad.empty.is_empty(), str(bad.empty))
	check(tag + "нет двойных пробелов и пробелов по краям строк", bad.spaces.is_empty(), str(bad.spaces))
	check(tag + "нет пробела перед знаком препинания", bad.before_punct.is_empty(), str(bad.before_punct))
	check(tag + "нет пробела после открывающей кавычки или скобки", bad.after_open.is_empty(), str(bad.after_open))
	check(tag + "кавычки парные", bad.quotes.is_empty(), str(bad.quotes))
	check(tag + "скобки парные", bad.parens.is_empty(), str(bad.parens))
	check(tag + "нет слов, где латиница смешана с кириллицей", bad.mixed.is_empty(), str(bad.mixed))
	check(tag + "многоточие — ровно три точки", bad.dots.is_empty(), str(bad.dots))
	check(tag + "нет слова, повторённого дважды подряд", bad.repeat.is_empty(), str(bad.repeat))


## Список нарушений одной строки (имена — ключи словаря bad в _test_typography).
func _typography_problems(s: String, loc: String) -> Array:
	var out: Array = []
	if s.contains("  ") or s != s.strip_edges() or s.contains(" \n") or s.contains("\n "):
		out.append("spaces")
	for p in [",", ".", "!", "?", ":", ";", "»", ")"]:
		if s.contains(" " + p):
			out.append("before_punct")
			break
	if s.contains("« ") or s.contains("( "):
		out.append("after_open")
	if loc == "ru":
		if s.contains("\"") or not _balanced(s, "«", "»"):
			out.append("quotes")
	elif s.count("\"") % 2 != 0:
		out.append("quotes")
	if not _balanced(s, "(", ")"):
		out.append("parens")
	if s.contains("…") or s.contains("...."):
		out.append("dots")
	var prev := ""
	for w in _words(s, true):
		if String(w[0]).length() == 0:
			continue
		if _is_mixed(String(w[0])):
			out.append("mixed")
		if not prev.is_empty() and String(w[0]).to_lower() == prev and String(w[1]).strip_edges().is_empty():
			out.append("repeat")
		prev = String(w[0]).to_lower()
	return out


func _balanced(s: String, open: String, close: String) -> bool:
	var depth := 0
	for i in s.length():
		if s[i] == open:
			depth += 1
		elif s[i] == close:
			depth -= 1
			if depth < 0:
				return false
	return depth == 0


func _is_cyr(c: int) -> bool:
	return c >= 0x0400 and c <= 0x04FF


func _is_lat(c: int) -> bool:
	return (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A)


func _is_mixed(word: String) -> bool:
	var cyr := false
	var lat := false
	for i in word.length():
		var c := word.unicode_at(i)
		cyr = cyr or _is_cyr(c)
		lat = lat or _is_lat(c)
	return cyr and lat


## Слова строки: непрерывные куски букв (кириллица/латиница). with_gap — вернуть
## пары [слово, разделитель перед ним], иначе — просто слова.
func _words(s: String, with_gap: bool = false) -> Array:
	var out: Array = []
	var word := ""
	var gap := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if _is_cyr(c) or _is_lat(c):
			word += s[i]
		else:
			if not word.is_empty():
				out.append([word, gap] if with_gap else word)
				word = ""
				gap = ""
			gap += s[i]
	if not word.is_empty():
		out.append([word, gap] if with_gap else word)
	return out


# ---------------------------------------------------------------------------
# Правила только для русского
# ---------------------------------------------------------------------------

func _test_russian_only() -> void:
	var bad := {"hyphen": [], "dash": [], "decimal": [], "yo": [], "dedov": []}
	for key in _texts(ru).keys():
		for p in _russian_problems(String(ru[key])):
			bad[p].append(key)
	check("[ru] тире — «—», а не дефис или «–» между пробелами", bad.hyphen.is_empty(), str(bad.hyphen))
	check("[ru] тире «—» отбито пробелами с обеих сторон", bad.dash.is_empty(), str(bad.dash))
	check("[ru] дробные числа — через запятую (12,5%)", bad.decimal.is_empty(), str(bad.decimal))
	check("[ru] «ё» на месте (ещё, её, нашёл, жёлтый…)", bad.yo.is_empty(), str(bad.yo))
	check("[ru] нет «дедов-» (читается как «делов-»): пишем «деда», «у деда»", bad.dedov.is_empty(), str(bad.dedov))


func _russian_problems(s: String) -> Array:
	var out: Array = []
	if s.contains(" - ") or s.contains("–"):
		out.append("hyphen")
	for i in s.length():
		if s[i] != "—":
			continue
		var left_ok := i == 0 or s[i - 1] == " " or s[i - 1] == "\n"
		var right_ok := i < s.length() - 1 and s[i + 1] == " "
		if not (left_ok and right_ok):
			out.append("dash")
			break
	var re := RegEx.create_from_string("\\d\\.\\d")
	if re.search(s) != null:
		out.append("decimal")
	var words := _words(s)
	for i in words.size():
		var w := String(words[i]).to_lower()
		if NEED_YO.has(w) or (w == "все" and i + 1 < words.size() and String(words[i + 1]).to_lower() == "равно"):
			out.append("yo")
		if w.begins_with("дедов"):
			out.append("dedov")
	return out


# ---------------------------------------------------------------------------
# Кадры сцен: заглавная, конец фразы, длина под окно
# ---------------------------------------------------------------------------

func _test_beats(loc: String, table: Dictionary) -> void:
	var no_cap: Array = []
	var no_end: Array = []
	var too_long: Array = []
	var twice: Array = []
	for sc in scenes:
		var last := ""
		for b in sc.get("beats", []):
			var t := String(b.get("t", ""))
			var key := String(b.get("text", ""))
			if not t in ["say", "narr", "card", "item"] or not table.has(key):
				continue
			var s := String(table[key])
			if not _starts_capital(s):
				no_cap.append(key)
			var limit: int = SAY_MAX[loc] if t in ["say", "narr"] else (CARD_MAX if t == "card" else ITEM_MAX)
			if s.length() > limit:
				too_long.append("%s (%d > %d)" % [key, s.length(), limit])
			if t != "card" and not _ends_phrase(s):
				no_end.append(key)
			if t in ["say", "narr"]:
				if s == last:
					twice.append(key)
				last = s
		for e in sc.get("effects", []):
			var tk := String(e.get("text", ""))
			if table.has(tk) and (not _starts_capital(String(table[tk])) or not _ends_phrase(String(table[tk]))):
				no_end.append(tk)
	var tag := "[%s] " % loc
	check(tag + "реплики, титры и карточки начинаются с заглавной", no_cap.is_empty(), str(no_cap))
	check(tag + "реплика, карточка и тост кончаются знаком конца фразы (не обрублены)", no_end.is_empty(), str(no_end))
	check(tag + "длина под окно диалога и карточки", too_long.is_empty(), str(too_long))
	check(tag + "одна и та же реплика не идёт дважды подряд", twice.is_empty(), str(twice))


## Первая буква — заглавная (перед ней можно «...», кавычку, скобку).
func _starts_capital(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if _is_cyr(c) or _is_lat(c):
			return s[i] == s[i].to_upper()
		if c >= 0x30 and c <= 0x39:
			return true
	return true


func _ends_phrase(s: String) -> bool:
	var t := s.strip_edges()
	return not t.is_empty() and t[t.length() - 1] in [".", "!", "?", "»", ")", "—", "\""]


# ---------------------------------------------------------------------------
# Ключ ↔ говорящий
# ---------------------------------------------------------------------------

func _suffix(key: String) -> String:
	var i := key.rfind(".")
	return key.substr(i + 1) if i >= 0 else key


func _test_speaker_keys() -> void:
	var wrong: Array = []
	var narr_wrong: Array = []
	var reused: Array = []
	var seen := {}
	for sc in scenes:
		var grandpa_era := String(sc.get("era", "")) == "grandpa"
		for b in sc.get("beats", []):
			var t := String(b.get("t", ""))
			if not t in ["say", "narr"]:
				continue
			var key := String(b.get("text", ""))
			if seen.has(key):
				reused.append(key)
			seen[key] = true
			var letter := _suffix(key).left(1)
			if t == "narr":
				if letter != "n":
					narr_wrong.append(key)
				continue
			var who := String(b.get("who", ""))
			var allowed := String(SPEAKER_LETTERS.get(who, "?"))
			if grandpa_era and who.begins_with("grandpa"):
				allowed += "s"
			if grandpa_era and who.begins_with("boy"):
				allowed = "?"
			if not allowed.contains(letter):
				wrong.append("%s ← %s" % [key, who])
	check("ключ реплики совпадает с говорящим (.r — Роберт, .g — бабка, .s — внук…)", wrong.is_empty(), str(wrong))
	check("закадровый текст — ключи .nN", narr_wrong.is_empty(), str(narr_wrong))
	check("ни одна реплика не стоит в двух местах", reused.is_empty(), str(reused))


func _test_robert() -> void:
	var said := {}
	for sc in scenes:
		for b in sc.get("beats", []):
			if String(b.get("t", "")) == "say" and String(b.get("who", "")) == "robert":
				said[String(b.get("text", ""))] = true
	var re := RegEx.create_from_string("^r\\d+$")
	var orphans: Array = []
	for key in _texts(ru).keys():
		if re.search(_suffix(String(key))) != null and not said.has(key):
			orphans.append(key)
	check("у Роберта есть реплики в сценах", said.size() >= 4, str(said.size()))
	check("каждая строка .rN стоит в сцене за Робертом (нет потерянных реплик)", orphans.is_empty(), str(orphans))
	var unpaired: Array = []
	var long_lines: Array = []
	for key in said.keys():
		if not ru.has(key) or not en.has(key) or String(en[key]) == String(ru[key]):
			unpaired.append(key)
			continue
		var s := String(ru[key])
		var words_max := 0
		for sentence in RegEx.create_from_string("[.!?]+").sub(s, "|", true).split("|", false):
			words_max = maxi(words_max, _words(sentence).size())
		if s.length() > ROBERT_MAX_CHARS or words_max > ROBERT_MAX_WORDS:
			long_lines.append("%s (%d зн., до %d слов в предложении)" % [key, s.length(), words_max])
	check("реплики Роберта есть в ru и en парой", unpaired.is_empty(), str(unpaired))
	check("Роберт говорит коротко: до %d знаков, до %d слов в предложении" % [ROBERT_MAX_CHARS, ROBERT_MAX_WORDS],
		long_lines.is_empty(), str(long_lines))


## Выражения лиц в data/dialogue.json ссылаются на ключи реплик: после правок
## текста не должно остаться ссылок на удалённые ключи.
func _test_faces() -> void:
	var faces: Dictionary = _load("res://data/dialogue.json").get("faces", {})
	var stale: Array = []
	for key in faces.keys():
		if not ru.has(key):
			stale.append(key)
	check("лица из dialogue.json ссылаются на существующие реплики", not faces.is_empty() and stale.is_empty(), str(stale))


## Сам линтер видит нарушения (иначе зелёный цвет ничего не значит).
func _test_linter_catches() -> void:
	check("линтер ловит двойной пробел", _typography_problems("Он  пошёл.", "ru").has("spaces"))
	check("линтер ловит пробел перед запятой", _typography_problems("Ну , да.", "ru").has("before_punct"))
	check("линтер ловит непарную «", _typography_problems("Он сказал: «стой.", "ru").has("quotes"))
	check("линтер ловит латинскую «а» в русском слове", _typography_problems("Ба, я тут.".replace("а", "a"), "ru").has("mixed"))
	check("линтер ловит повтор слова", _typography_problems("Он не не пошёл.", "ru").has("repeat"))
	check("линтер ловит «...» из четырёх точек и «…»", _typography_problems("Ну....", "ru").has("dots")
		and _typography_problems("Ну…", "ru").has("dots"))
	check("линтер ловит «дедовой»", _russian_problems("Под дедовой плитой.").has("dedov"))
	check("линтер ловит «еще» без ё", _russian_problems("Еще чуть-чуть.").has("yo"))
	check("линтер ловит 12.5%", _russian_problems("Сон: 12.5% в час.").has("decimal"))
	check("линтер ловит тире без пробела", _russian_problems("Он—там.").has("dash"))
	check("линтер ловит дефис вместо тире", _russian_problems("Он - там.").has("hyphen"))
	check("линтер не трогает «чуть-чуть» и «Сейчас, сейчас»", _typography_problems("Ещё чуть-чуть. Сейчас, сейчас.", "ru").is_empty()
		and _russian_problems("Ещё чуть-чуть. Сейчас, сейчас.").is_empty())
	check("обрубленная реплика видна", not _ends_phrase("Под плитой стоит") and _ends_phrase("Ещё чу...") and _ends_phrase("A little mo—"))

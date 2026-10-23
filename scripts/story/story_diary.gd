class_name StoryDiary
extends RefCounted
## Дневник деда: какие страницы открыты и какие уже прочитаны.
##
## Открытость страницы НЕ хранится — она вычисляется из состояния игры
## (макс. глубина, просмотренные сцены, флаги сюжета, см. data/story_diary.json).
## Так страница не может «потеряться» при загрузке и не расходится со сценой,
## которая её открывает. Хранится только то, что игрок УЖЕ видел: прочитанные
## страницы (значок «новое») и страницы, о которых игре пора было сказать
## тостом; живёт в GameState.ext["story"] — общий сейв и сброс прогресса.

const PATH := "res://data/story_diary.json"
const EXT_KEY := "story"

static var _pages: Array = []


static func pages() -> Array:
	if _pages.is_empty():
		_load()
	return _pages


static func _load() -> void:
	if not FileAccess.file_exists(PATH):
		push_error("StoryDiary: не найден %s" % PATH)
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("StoryDiary: %s повреждён" % PATH)
		return
	_pages = raw.get("pages", [])


static func page_count() -> int:
	return pages().size()


static func page(index: int) -> Dictionary:
	var p := pages()
	return p[index] if index >= 0 and index < p.size() else {}


static func index_of(id: String) -> int:
	var p := pages()
	for i in p.size():
		if String(p[i].get("id", "")) == id:
			return i
	return -1


static func is_unlocked(p: Dictionary) -> bool:
	var w: Dictionary = p.get("when", {})
	if w.has("depth") and GameState.max_depth_reached < int(w["depth"]):
		return false
	if w.has("seen") and not StoryState.is_seen(String(w["seen"])):
		return false
	if w.has("flag") and not StoryState.has_flag(String(w["flag"])):
		return false
	return true


## Чем запечатана страница, пока закрыта: "depth" (дойди глубже) или "event"
## (сделай дело). Текст печати у них разный, но чисел в нём нет.
static func sealed_kind(p: Dictionary) -> String:
	return "depth" if p.get("when", {}).has("depth") else "event"


static func unlocked_ids() -> Array:
	var out: Array = []
	for p in pages():
		if is_unlocked(p):
			out.append(String(p.get("id", "")))
	return out


static func text_key(id: String, part: String) -> String:
	return "diary.%s.%s" % [id, part]


# --- сохраняемое: прочитанное и «уведомлённое» ---

static func _state() -> Dictionary:
	var d = GameState.ext_get(EXT_KEY, {})
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func _list(key: String) -> Array:
	var l = _state().get(key, [])
	return l if typeof(l) == TYPE_ARRAY else []


static func _add(key: String, id: String) -> bool:
	var l := _list(key)
	if l.has(id):
		return false
	var d := _state()
	l = l.duplicate()
	l.append(id)
	d[key] = l
	GameState.ext_set(EXT_KEY, d)
	return true


static func is_read(id: String) -> bool:
	return _list("diary_read").has(id)


static func mark_read(id: String) -> void:
	_add("diary_read", id)


static func unread_ids() -> Array:
	var out: Array = []
	for id in unlocked_ids():
		if not is_read(id):
			out.append(id)
	return out


## Страницы, открытые, но ещё не объявленные тостом. Зовёт режиссёр: объявляет
## и тут же помечает, чтобы тост не повторялся.
static func take_unannounced() -> Array:
	var out: Array = []
	for id in unlocked_ids():
		if _add("diary_announced", id):
			out.append(id)
	return out


## Пока дневника нет (тетрадь ещё лежит под плитой), тосты о страницах молчат,
## но открытое к этому моменту считается объявленным — иначе на первом же
## открытии тетради игрок получил бы тост о восьми страницах сразу.
static func announce_all_quietly() -> void:
	for id in unlocked_ids():
		_add("diary_announced", id)

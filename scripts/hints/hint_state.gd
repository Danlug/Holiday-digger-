class_name HintState
extends RefCounted
## Что игрок уже видел: GameState.ext["hints"] = {"seen": {id: 1|2}, "opened": {entry: 1}}.
## 1 — подсказка показана (снята временем или условием), 2 — игрок сделал то, на что
## она указывала. «Показана» пишем в момент показа: закрыл игру посреди подсказки —
## она не повторится. Сохраняется вместе с сейвом (ext), сбрасывается вместе с
## прогрессом и кнопкой «показать подсказки заново» в настройках.
## Числа из JSON приходят float — читаем только наличие ключа.

const KEY := "hints"


static func root() -> Dictionary:
	var r = GameState.ext_get(KEY, null)
	if typeof(r) != TYPE_DICTIONARY:
		r = {}
		GameState.ext[KEY] = r
	if typeof(r.get("seen", null)) != TYPE_DICTIONARY:
		r["seen"] = {}
	if typeof(r.get("opened", null)) != TYPE_DICTIONARY:
		r["opened"] = {}
	return r


static func is_seen(id: String) -> bool:
	return root()["seen"].has(id)


static func was_done(id: String) -> bool:
	return int(root()["seen"].get(id, 0)) >= 2


static func mark_seen(id: String) -> void:
	var r := root()
	if not r["seen"].has(id):
		r["seen"][id] = 1
		GameState.ext_set(KEY, r)


static func mark_done(id: String) -> void:
	var r := root()
	r["seen"][id] = 2
	GameState.ext_set(KEY, r)


static func entry_opened(entry: String) -> bool:
	return root()["opened"].has(entry)


static func mark_entry_opened(entry: String) -> void:
	var r := root()
	if not r["opened"].has(entry):
		r["opened"][entry] = 1
		GameState.ext_set(KEY, r)


## «Показать подсказки заново».
static func reset() -> void:
	GameState.ext_set(KEY, {"seen": {}, "opened": {}})


static func enabled() -> bool:
	return Settings.hints_enabled

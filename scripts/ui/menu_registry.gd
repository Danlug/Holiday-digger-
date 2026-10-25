class_name MenuRegistry
extends RefCounted
## MenuRegistry — реестр пунктов меню «•••» (и экранов-«входов» вообще).
## Каждая подсистема регистрирует свой пункт у себя в коде, а HUD рисует меню
## из реестра: так HUD не знает о квестах, достижениях и прочем, а подсистемы
## не правят hud.gd.
##
##   MenuRegistry.add("quests", {
##       "icon": preload("res://art/ui/icons/quests.png"),   # Texture2D
##       "title": "Задания",                  # заголовок подсказки (Tip)
##       "body": "Ежедневные и недельные",    # необязательно
##       "order": 40,                          # меньше — левее/выше
##       "visible": func() -> bool: return true,   # необязательно
##       "badge": func() -> int: return 2,         # необязательно: красная цифра
##       "on_press": func() -> void: open_quests(),
##       "confirm": true,   # необязательно: опасный пункт — нужно нажать дважды
##   })
##
## icon, title и body могут быть и Callable без аргументов (иконка/текст
## меняются по состоянию, например режим управления): HUD читает их при
## каждом открытии меню через icon_of()/text_of().
##
## Регистрация идёт один раз за запуск процесса; повторный add с тем же id
## заменяет запись (так безопасно звать из _ready узла, который могут создать
## дважды).

static var _entries: Dictionary = {}
static var _exit_hooked: bool = false


static func add(id: String, entry: Dictionary) -> void:
	var e := entry.duplicate()
	e["id"] = id
	if not e.has("order"):
		e["order"] = 100
	_entries[id] = e
	_hook_exit()


## В записях лежат лямбды (on_press, badge, visible), а они держат ссылку на
## скрипт, где созданы. Статическая переменная переживает скрипты при выходе
## из движка, и Godot 4.4 на этом портит кучу («corrupted size vs. prev_size»,
## код 134 в headless-тестах). Поэтому реестр сам очищается, пока корень дерева
## ещё жив.
static func _hook_exit() -> void:
	if _exit_hooked:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_exit_hooked = true
	tree.root.tree_exiting.connect(_on_tree_exiting)


static func _on_tree_exiting() -> void:
	_entries.clear()
	_exit_hooked = false


static func remove(id: String) -> void:
	_entries.erase(id)


static func clear() -> void:
	_entries.clear()


## Видимые пункты по возрастанию order (при равенстве — по id).
static func entries() -> Array:
	var out: Array = []
	for id in _entries.keys():
		var e: Dictionary = _entries[id]
		var vis = e.get("visible", null)
		if vis is Callable and not (vis as Callable).call():
			continue
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["order"]) != int(b["order"]):
			return int(a["order"]) < int(b["order"])
		return String(a["id"]) < String(b["id"]))
	return out


static func badge_of(e: Dictionary) -> int:
	var b = e.get("badge", null)
	return int((b as Callable).call()) if b is Callable else 0


## Иконка пункта: Texture2D или Callable, который её возвращает.
static func icon_of(e: Dictionary) -> Texture2D:
	var i = e.get("icon", null)
	if i is Callable:
		i = (i as Callable).call()
	return i as Texture2D


## Текст пункта по ключу ("title"/"body"): строка или Callable со строкой.
static func text_of(e: Dictionary, key: String) -> String:
	var t = e.get(key, "")
	if t is Callable:
		t = (t as Callable).call()
	return String(t)

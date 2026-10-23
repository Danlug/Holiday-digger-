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
##   })
##
## Регистрация идёт один раз за запуск процесса; повторный add с тем же id
## заменяет запись (так безопасно звать из _ready узла, который могут создать
## дважды).

static var _entries: Dictionary = {}


static func add(id: String, entry: Dictionary) -> void:
	var e := entry.duplicate()
	e["id"] = id
	if not e.has("order"):
		e["order"] = 100
	_entries[id] = e


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

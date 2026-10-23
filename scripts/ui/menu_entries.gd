class_name HudMenuEntries
extends RefCounted
## Стандартные пункты меню «•••»: мастерская, режим управления, настройки,
## сброс. Регистрируются в MenuRegistry при сборке HUD — сам hud.gd о них
## ничего не знает, а остальные подсистемы (задания, достижения, музей…) так
## же добавляют свои пункты у себя. HUD находит эти действия по группе "hud",
## поэтому записи переживают перезагрузку сцены (сброс игры создаёт новый HUD).

const MODE_NAMES := {"stick": "Джойстик", "hold": "Нажатия", "arrows": "Стрелки"}
const MODE_ICONS := {"stick": "joystick", "hold": "ctl_hold", "arrows": "ctl_arrows"}


static func register() -> void:
	MenuRegistry.add("workshop", {
		"icon": UiIcons.tex("workshop"),
		"title": "Мастерская",
		"body": "Продажа, верстак, лавка",
		"order": 10,
		"on_press": func() -> void: ShopUI.open_shop(),
	})
	MenuRegistry.add("controls", {
		"icon": func() -> Texture2D: return UiIcons.tex(MODE_ICONS.get(Settings.control_mode, "joystick")),
		"title": "Управление",
		"body": func() -> String: return String(MODE_NAMES.get(Settings.control_mode, "")),
		"order": 80,
		"on_press": func() -> void: _call_hud("cycle_mode"),
	})
	MenuRegistry.add("settings", {
		"icon": UiIcons.tex("gear"),
		"title": "Настройки",
		"body": "Звук, вибро, управление, язык",
		"order": 90,
		"on_press": func() -> void: _call_hud("open_settings"),
	})
	MenuRegistry.add("reset", {
		"icon": UiIcons.tex("reset"),
		"title": "Сброс игры",
		"body": "Стирает весь прогресс. Нажми дважды",
		"order": 99,
		"confirm": true,
		"on_press": func() -> void: _call_hud("reset_game"),
	})


static func _call_hud(method: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var hud := tree.get_first_node_in_group("hud") if tree != null else null
	if hud != null and hud.has_method(method):
		hud.call(method)

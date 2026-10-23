class_name HintPulse
extends RefCounted
## HintPulse — реестр целей подсказок, которые экраны регистрируют сами одной строкой:
##
##   HintPulse.attach(button, "my_button")
##
## и правило в data/hints.json указывает на неё как "attached:my_button". Кнопки HUD,
## меню и мира система находит без регистрации (HintTargets); attach нужен новым
## экранам, чтобы не менять чужие файлы ради чужой подсказки.
##
## Ссылки — на узлы, не на лямбды: статический словарь с лямбдами портит кучу при
## выходе из движка. Реестр сам чистится на tree_exiting, пока корень дерева жив.

static var _attached: Dictionary = {}
static var _exit_hooked: bool = false


static func attach(control: Control, id: String) -> void:
	if control == null or id.is_empty():
		return
	_attached[id] = control
	_hook_exit()


static func detach(id: String) -> void:
	_attached.erase(id)


static func target(id: String) -> Control:
	var c = _attached.get(id, null)
	if c != null and is_instance_valid(c):
		return c as Control
	_attached.erase(id)
	return null


static func clear() -> void:
	_attached.clear()


static func _hook_exit() -> void:
	if _exit_hooked:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_exit_hooked = true
	tree.root.tree_exiting.connect(_on_tree_exiting)


static func _on_tree_exiting() -> void:
	_attached.clear()
	HintConditions.latched.clear()
	_exit_hooked = false

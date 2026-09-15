extends Node
## Генератор сцен дома: scenes/house.tscn и scenes/house_prompt.tscn.
##
## Сцены собираются ровно тем же кодом, который потом их и использует
## (house_view._ensure_structure / house_prompt._build), поэтому файл сцены и
## поведение не могут разъехаться. Открывать и править сцены в редакторе
## можно как обычно — при загрузке код только находит уже существующие узлы.
##
## Запускается СЦЕНОЙ, а не через --script: house_view.gd обращается к
## автозагрузке GameState, а в режиме --script автозагрузок нет и скрипт даже
## не компилируется (та же причина, по которой tests/test_player_harness —
## сцена, см. docs/BUILD.md).
##
## Запуск:
##   godot --headless --path . res://tools/gen_house_scenes.tscn

func _ready() -> void:
	_build("res://scripts/house/house_view.gd", "res://scenes/house.tscn", "House")
	_build("res://scripts/house/house_prompt.gd", "res://scenes/house_prompt.tscn", "HousePrompt")
	_build("res://scripts/house/house_storage_view.gd", "res://scenes/house_storage.tscn", "HouseStorageView")
	get_tree().quit(0)


func _build(script_path: String, scene_path: String, root_name: String) -> void:
	var node = load(script_path).new()
	node.name = root_name
	if node.has_method("_ensure_structure"):
		node._ensure_structure()
	else:
		node._build()
	_set_owner(node, node)
	var packed := PackedScene.new()
	var err := packed.pack(node)
	if err != OK:
		push_error("не удалось упаковать %s: %d" % [scene_path, err])
		return
	err = ResourceSaver.save(packed, scene_path)
	print("%s -> %s (код %d)" % [script_path, scene_path, err])
	node.free()


## Узлы, созданные кодом, попадают в .tscn только если у них выставлен
## владелец — иначе PackedScene.pack() сохранит один корень.
func _set_owner(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		if child != owner_node:
			child.owner = owner_node
		_set_owner(child, owner_node)

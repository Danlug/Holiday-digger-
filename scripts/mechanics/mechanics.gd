class_name Mechanics
extends RefCounted
## Механики из больших игр (раунд 3, ГДД §20.1): тайники, азарт и жадность (раунд 4),
## мастерство руд и журнал. Подключение одной строкой в main.gd
## (`Mechanics.attach(self)`); дальше режиссёр сам слушает шину событий.

static func attach(host: Node) -> Node:
	var old := host.get_node_or_null("MechDirector")
	if old != null:
		return old
	var d := MechDirector.new()
	d.name = "MechDirector"
	host.add_child(d)
	return d


static func tex(name: String) -> Texture2D:
	var path := "res://art/mechanics/%s.png" % name
	if ResourceLoader.exists(path):
		return load(path)
	return null

class_name Juice
extends RefCounted
## Juice — точка входа ветки «Звук и сок»: одна строка в main.gd
## (`Juice.attach(self)`) поднимает три узла — SfxService (звук и музыка),
## FxService (частицы, всплывающие числа, тряска, вспышка, летящие иконки) и
## JuiceDirector (подписки на сигналы игры, которые всё это включают).
## Остальной код ничего о них не знает и зовёт только фасады Sfx / Fx / Haptics.

const CONFIG_PATH := "res://data/juice.json"

static var _cfg: Dictionary = {}
static var _cfg_loaded: bool = false


## Подключает «сок» к корню игровой сцены. Берёт у хоста view_root (мировые
## эффекты живут в нём — их координаты совпадают с мировыми пикселями героя).
## Возвращает режиссёра. Повторный вызов ничего не удваивает.
static func attach(host: Node) -> Node:
	var old := host.get_node_or_null("JuiceDirector")
	if old != null:
		return old
	var sfx := SfxService.new()
	sfx.name = "SfxService"
	host.add_child(sfx)

	var world_root: Node = host
	if "view_root" in host and host.view_root != null:
		world_root = host.view_root
	var fx := FxService.new()
	fx.name = "FxService"
	world_root.add_child(fx)

	var director := JuiceDirector.new()
	director.name = "JuiceDirector"
	director.sfx = sfx
	director.fx = fx
	host.add_child(director)
	_attach_world_light(host, world_root)
	return director


## Свет и тени мира (ветка «world-fx»): тоже «сок», поэтому подключаются здесь же и не требуют строки
## в main.gd. Нужны мир, его рендер и герой; в хосте без них (тесты с заглушкой) тихо пропускаются.
static func _attach_world_light(host: Node, world_root: Node) -> void:
	if not ("world_view" in host and "player" in host and "world" in host):
		return
	if host.world_view == null or host.player == null or host.world == null:
		return
	if world_root.get_node_or_null("LightLayer") != null:
		return
	var shadows := ContactShadows.new()
	shadows.player = host.player
	shadows.world = host.world
	world_root.add_child(shadows)
	world_root.move_child(shadows, host.player.get_index())   # над тайлами и домом, под героем
	var light := LightLayer.new()
	light.world_view = host.world_view
	light.player = host.player
	world_root.add_child(light)


static func config() -> Dictionary:
	if not _cfg_loaded:
		_cfg_loaded = true
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f != null:
			var raw = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(raw) == TYPE_DICTIONARY:
				_cfg = raw
	return _cfg


## Число из data/juice.json по пути "раздел.ключ" (понимает {value, proposed}).
static func num(path: String, default: float) -> float:
	var node: Variant = config()
	for part in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(part):
			return default
		node = node[part]
	if typeof(node) == TYPE_DICTIONARY:
		node = node.get("value", default)
	if typeof(node) == TYPE_INT or typeof(node) == TYPE_FLOAT:
		return float(node)
	return default

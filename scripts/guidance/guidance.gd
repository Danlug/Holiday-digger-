class_name Guidance
extends Node
## Ветка guidance (раунд 4): объяснение цепочек материалов для бура, скважины,
## бурмобиля и костюма. Подключается одной строкой в main.gd (Guidance.attach).
## Узлы: ProjectsScreen (экран «Проекты», пункт меню «•••»), ProjectTracker
## (плашка отслеживаемого проекта на HUD). Значки «нужно для…» на плитках
## продажи и склада рисует сама плитка (ProjectChain.decorate_offer → ShopTile).
## Подсказка-знакомство — правила project_* в data/hints.json.

const ART_DIR := "res://art/guidance/%s.png"
const POLL := 0.5

var screen: ProjectsScreen = null
var tracker: ProjectTracker = null
var _acc := 0.0


static func attach(host: Node) -> Guidance:
	var g := Guidance.new()
	g.name = "Guidance"
	host.add_child(g)
	return g


static func tex(icon_name: String) -> Texture2D:
	return ShopArt.load_path(ART_DIR % icon_name)


static func ready_count() -> int:
	var n := 0
	for id in ProjectChain.open_ids():
		if ProjectChain.ready(String(id)):
			n += 1
	return n


func _ready() -> void:
	screen = ProjectsScreen.new()
	screen.name = "ProjectsScreen"
	add_child(screen)
	var layer := CanvasLayer.new()
	layer.name = "ProjectTrackerLayer"
	layer.layer = UiLayers.HUD_WIDGETS   # рядом с HUD и шкалой азарта, ниже шторок и экранов
	layer.add_to_group(UiLayers.WIDGETS_GROUP)
	add_child(layer)
	tracker = ProjectTracker.new()
	tracker.name = "ProjectTracker"
	layer.add_child(tracker)
	screen.track_changed.connect(func(_id: String) -> void: tracker.sync())
	MenuRegistry.add("projects", {
		"icon": tex("projects"),
		"title": "Проекты",
		"body": "Бур, скважина, бурмобиль, костюм: из каких материалов, сколько уже есть и где копать.",
		"order": 38,
		"visible": func() -> bool: return HintBusy.onboarding_done(),
		"badge": func() -> int: return Guidance.ready_count(),
		"on_press": func() -> void: ProjectsScreen.open_for(""),
	})
	step()


func _process(delta: float) -> void:
	_acc += delta
	if _acc >= POLL:
		_acc = 0.0
		step()


## Автослежка: открылся проект, а следить не за чем — трекер берёт его сам.
func step() -> void:
	if not HintBusy.onboarding_done():
		return
	if ProjectChain.auto_track() != "" and tracker != null:
		tracker.sync()

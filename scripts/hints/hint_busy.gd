class_name HintBusy
extends RefCounted
## «Не сейчас»: когда подсказки молчат. Два вопроса.
##
## onboarding_done() — онбординг (ГДД п.9) неприкосновенен: подсказки включаются только
## после его последнего шага «закажи еду» (флаг сюжета food_ordered) либо после второго
## урока выживания.
##
## is_busy() — игрок занят чем-то другим: катсцена и автокопка, шторка или экран
## (мастерская, герой, техника, настройки, рюкзак, меню, мета-хаб, дневник), интерьер
## дома, смерть, бой. Бой ветка боя объявляет сама — любой из способов:
## GameState.in_combat = true, узел в группе "in_combat" или ext["combat"]["active"].
## Любой другой экран может запретить подсказки, добавив свой видимый узел в группу
## "hint_block" — править этот файл ради этого не надо.

const BLOCK_GROUP := &"hint_block"


static func onboarding_done() -> bool:
	return StoryState.has_flag("food_ordered") or GameState.house_tutorial_stage >= 2


static func is_busy() -> bool:
	if not GameState.is_alive or GameState.house_is_indoors or GameState.era == "grandpa":
		return true
	var tree := HintConditions.tree()
	if tree == null:
		return true
	if tree.paused:
		return true
	if _cutscene_or_autodig(tree):
		return true
	if _modal_open(tree):
		return true
	if _in_combat(tree):
		return true
	for n: Node in tree.get_nodes_in_group(BLOCK_GROUP):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			return true
		if n is CanvasLayer and (n as CanvasLayer).visible:
			return true
	return false


static func _cutscene_or_autodig(tree: SceneTree) -> bool:
	var director := tree.root.find_child("StoryDirector", true, false)
	if director == null:
		return false
	var cs = director.get("cutscene")
	if cs != null and bool(cs.get("is_playing")):
		return true
	var ad = director.get("auto_dig")
	if ad != null and bool(ad.get("running")):
		return true
	if bool(director.get("_playing")):
		return true
	return false


static func _modal_open(tree: SceneTree) -> bool:
	if ProgressScreen.is_open() or TechSystem.is_modal_open():
		return true
	if ShopUI.instance != null and ShopUI.instance.is_open():
		return true
	var m := MetaService.instance
	if m != null and is_instance_valid(m) and (m.hub.is_open() or m.popup.is_open()):
		return true
	for name in ["settings", "backpack", "diary"]:
		if HintConditions.screen_open(name):
			return true
	var hud := HintConditions.hud()
	if hud != null and hud.get("_well_panel") != null:
		return true
	return false


static func _in_combat(tree: SceneTree) -> bool:
	var flag = GameState.get("in_combat")
	if flag != null and bool(flag):
		return true
	if not tree.get_nodes_in_group("in_combat").is_empty():
		return true
	var c = GameState.ext_get("combat", null)
	return typeof(c) == TYPE_DICTIONARY and bool(c.get("active", false))

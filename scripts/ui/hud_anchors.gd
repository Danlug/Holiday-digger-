class_name HudAnchors
extends RefCounted
## Экранные «якоря» HUD для эффектов: куда лететь монетам и предметам.
##
##   Fx.fly_to(icon, from_screen, HudAnchors.get_anchor("coins"), 5)
##
## id: coins, dollars, backpack, hp, hunger, stamina, menu, depth, tasks. Координаты —
## проектные единицы вьюпорта (224×480), центр элемента. Без HUD в дереве
## (тесты, --script) отдаёт центр экрана — летящая иконка не улетит в угол.
## Статический, а не метод HUD: HUD — Control, а у Control уже есть свой
## get_anchor(Side), и перекрыть его нельзя.

const FALLBACK := Vector2(112, 240)


static func get_anchor(id: String) -> Vector2:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return FALLBACK
	var hud := tree.get_first_node_in_group("hud")
	if hud == null or not hud.has_method("anchor_of"):
		return FALLBACK
	return hud.call("anchor_of", id)

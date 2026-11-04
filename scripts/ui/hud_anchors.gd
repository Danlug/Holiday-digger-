class_name HudAnchors
extends RefCounted
## Экранные «якоря» HUD для эффектов: куда лететь монетам и предметам.
##
##   Fx.fly_to(icon, from_screen, HudAnchors.get_anchor("coins"), 5)
##
## id: coins, dollars, backpack, hp, hunger, stamina, menu, depth, tasks, clock. Координаты —
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


## Прямоугольник элемента HUD (те же единицы, что get_anchor). Нужен тем, кто
## встаёт в линию с элементом (шкала азарта под полосками). Нет HUD — пустой Rect2.
static func get_rect(id: String) -> Rect2:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Rect2()
	var hud := tree.get_first_node_in_group("hud")
	if hud == null or not hud.has_method("anchor_rect"):
		return Rect2()
	return hud.call("anchor_rect", id)


## Левый столбик HUD — портрет с часами, задание и задания дня (ранг 0), бак бура и
## термометр (1), курьер доставки (2): у каждого свой слой и свой скрипт, а встают они
## друг под друга. Раньше бак и курьер стояли на жёстких y=104/108 и наезжали на кнопку
## заданий дня и друг на друга (владелец 27.10: часы переехали под портрет — столбик вырос).
const LEFT_COLUMN := &"hud_left_column"
const COLUMN_GAP := 5.0


static func join_left_column(c: Control, rank: int) -> void:
	c.set_meta(&"hud_column_rank", rank)
	c.add_to_group(LEFT_COLUMN)


## Нижний край видимых участников столбика рангом ниже rank; никого — fallback.
static func left_column_bottom(rank: int, fallback: float) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return fallback
	var bottom := -INF
	for n in tree.get_nodes_in_group(LEFT_COLUMN):
		var c := n as Control
		if c == null or not c.is_visible_in_tree() or int(c.get_meta(&"hud_column_rank", 0)) >= rank:
			continue
		bottom = maxf(bottom, c.get_global_rect().end.y)
	return bottom if bottom > -INF else fallback

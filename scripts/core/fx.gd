class_name Fx
extends RefCounted
## Fx — фасад визуальных эффектов («сок» игры): частицы, всплывающий текст,
## тряска, вспышка, летящие в кошелёк монеты. Как и Sfx, ничего не требует от
## вызывающего: сервис — узел из группы "svc_fx", без него вызовы молча
## пропускаются (безопасно в тестах и в --script).
##
## Координаты: world_pos — в мировых пикселях сцены (как у Player.global_position),
## screen_pos — в проектных единицах вьюпорта 224×480.
##
## Виды вспышек частиц (kind): dig_dirt dig_stone dig_ore dig_gold spark
## poof hit_enemy enemy_die levelup coins heal fire

const GROUP := &"svc_fx"


## tint — необязательный акцент (для руды: цвет её вкраплений); прозрачный
## (по умолчанию) — краски вида по умолчанию.
static func burst(kind: String, world_pos: Vector2, amount: float = 1.0, tint: Color = Color(0, 0, 0, 0)) -> void:
	# Четвёртый аргумент передаём, только если он задан: заглушки сервиса в
	# старых тестах знают ровно три.
	_call("burst", [kind, world_pos, amount] if tint.a <= 0.0 else [kind, world_pos, amount, tint])


static func float_text(world_pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	_call("float_text", [world_pos, text, color])


## Всплывающая иконка с числом/словом (+1 с картинкой предмета).
static func float_icon(world_pos: Vector2, icon: Texture2D, text: String = "", color: Color = Color.WHITE) -> void:
	_call("float_icon", [world_pos, icon, text, color])


static func shake(strength: float = 4.0, duration: float = 0.2) -> void:
	_call("shake", [strength, duration])


static func flash(color: Color = Color(1, 1, 1, 0.5), duration: float = 0.15) -> void:
	_call("flash", [color, duration])


## Иконка летит по экрану от from_screen до to_screen (монеты в кошелёк,
## предмет в рюкзак). count — сколько иконок пустить веером.
static func fly_to(icon: Texture2D, from_screen: Vector2, to_screen: Vector2, count: int = 1) -> void:
	_call("fly_to", [icon, from_screen, to_screen, count])


static func _call(method: String, args: Array) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var n := tree.get_first_node_in_group(GROUP)
	if n != null:
		n.callv(method, args)

class_name SaveHooks
extends Node
## Запись при закрытии и место героя между сессиями (зона save-position, 27.10). Подключается одной
## строкой в main.gd (`SaveHooks.attach(self, hover)`), сам ничего в чужих узлах не меняет, кроме героя.
##
##  * Место героя под землёй (HeroSpot) освежается каждый кадр — до шага физики (process_priority).
##  * Сохранить сразу (SaveSystem.save_now): свернули/ушли на паузу (APPLICATION_PAUSED, FOCUS_OUT),
##    закрыли окно (WM_CLOSE_REQUEST), а в браузере — страница скрыта или уходит (visibilitychange →
##    hidden, pagehide: оболочка web/shell.src.html зовёт сюда через RaskopkiShell.onLeave). Автосейв раз в
##    минуту этого не ловил: закрыл вкладку через 50 с после спуска — и спуска будто не было.
##  * Загрузка в воздухе: герой висит там, где был, пока игрок не тронет управление (или пока его не
##    сдвинет кто-то другой: сцена, телепорт, дом). Сама загрузка не роняет его и не бьёт падением.

var player: Node2D = null
var _hover := false
var _hover_at := Vector2.ZERO
var _js_leave = null   # JavaScriptObject колбэка: без ссылки его соберёт сборщик и страница позовёт пустоту


static func attach(host: Node, hover: bool = false) -> SaveHooks:
	var old := host.get_node_or_null("SaveHooks") as SaveHooks
	if old != null:
		return old
	var hooks := SaveHooks.new()
	hooks.name = "SaveHooks"
	hooks.player = host.get("player")
	hooks._hover = hover and hooks.player != null
	if hooks._hover:
		hooks._hover_at = Vector2(hooks.player.x, hooks.player.y)
	host.add_child(hooks)
	return hooks


func _ready() -> void:
	process_priority = -10   # раньше main.gd: место и «висение» — до шага физики этого кадра
	HeroSpot.bind(player)
	_hook_web_page()


func _exit_tree() -> void:
	HeroSpot.bind(null)   # статика переживает перезагрузку сцены


func is_hovering() -> bool:
	return _hover


func _process(_dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _hover:
		_tick_hover()
	HeroSpot.track(player)


func _tick_hover() -> void:
	var touched: bool = int(player.hold_dx) != 0 or bool(player.hold_up) or bool(player.hold_down)
	var moved := absf(player.x - _hover_at.x) > 0.25 or absf(player.y - _hover_at.y) > 0.25
	if touched or moved or bool(player.on_ground) or not GameState.is_alive or GameState.house_is_indoors:
		_hover = false
		return
	player.x = _hover_at.x
	player.y = _hover_at.y
	player.vx = 0.0
	player.vy = 0.0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			SaveSystem.save_now("paused")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			SaveSystem.save_now("focus_out")
		NOTIFICATION_WM_CLOSE_REQUEST:
			SaveSystem.save_now("close")


## Браузер: страница скрыта (свернули, переключили вкладку, телефон убрал браузер) или уходит. Кадров у
## скрытой вкладки нет, поэтому сохраняемся прямо в обработчике события страницы, а save_now сам кладёт
## файл в IndexedDB (SaveSystem._persist_web).
func _hook_web_page() -> void:
	if not OS.has_feature("web"):
		return
	var shell = JavaScriptBridge.get_interface("RaskopkiShell")
	if shell == null or shell.onLeave == null:
		return
	_js_leave = JavaScriptBridge.create_callback(_on_page_leave)
	shell.onLeave(_js_leave)


func _on_page_leave(args: Array) -> void:
	SaveSystem.save_now("page_" + (String(args[0]) if not args.is_empty() else "leave"))

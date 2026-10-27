class_name NewbieStreakService
extends Node
## Узел стрика новичка: слушает шину событий и сигналы GameState, кормит ими
## NewbieStreak (логика), держит экран и пункт меню «•••». Подключается одной
## строкой в main.gd: NewbieStreakService.attach(self).
##
## Тостов нет и бейджа в меню нет (заказ 27.10: поведение тостов и счётчика
## «•••» не меняем) — засчитанный день виден на экране стрика.

const POLL_SEC := 1.0

static var instance: NewbieStreakService = null

var panel: NewbieStreakPanel = null

var _acc: float = 0.0
var _locked: bool = false
var _was_frozen: bool = false
var _hud_input_was_on: bool = true


static func attach(host: Node) -> NewbieStreakService:
	if instance != null and is_instance_valid(instance):
		return instance
	var s := NewbieStreakService.new()
	s.name = "NewbieStreakService"
	host.add_child(s)
	return s


func _ready() -> void:
	instance = self
	panel = NewbieStreakPanel.new()
	panel.name = "NewbieStreakPanel"
	add_child(panel)
	panel.closed.connect(_on_closed)
	GameState.game_event.connect(_on_bus)
	GameState.max_depth_changed.connect(_on_max_depth)
	GameState.leveled_up.connect(_on_leveled_up)
	GameState.artifact_collected.connect(_on_artifact)
	_register_menu()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	_acc += delta
	if _acc < POLL_SEC:
		return
	_acc = 0.0
	if MetaState.is_unlocked():
		_done(NewbieStreak.refresh())


func _on_bus(id: StringName, data: Dictionary) -> void:
	_apply(id, data)


func _on_max_depth(depth: int) -> void:
	_apply(&"max_depth_changed", {"depth": depth})


func _on_leveled_up(level: int, _points: int) -> void:
	_apply(&"leveled_up", {"level": level})


func _on_artifact(id: String) -> void:
	_apply(&"artifact_collected", {"id": id})


func _apply(id: StringName, data: Dictionary) -> void:
	if MetaState.is_unlocked():
		_done(NewbieStreak.on_event(id, data))


## День засчитан (n > 0): в сейв в конце кадра — иначе закрытая до автосейва
## игра, открытая уже завтра, потеряла бы выполненный день.
func _done(n: int) -> void:
	if n <= 0:
		return
	SaveSystem.save_at_frame_end("newbie_day")
	if panel != null and panel.is_open():
		panel.refresh()


# ---------------------------------------------------------------------------
# Экран
# ---------------------------------------------------------------------------

func open() -> void:
	if panel.is_open() or not MetaState.is_unlocked():
		return
	var meta := MetaService.instance
	if meta != null:
		for w in [meta.popup, meta.hub, meta.tasks]:
			if w != null and w.is_open():
				w.close()
	NewbieStreak.ensure_started()
	_done(NewbieStreak.refresh())
	_lock(true)
	panel.open()


func _on_closed() -> void:
	_lock(false)
	var meta := MetaService.instance
	if meta != null:
		meta.after_change()


## Пока экран открыт, герой стоит, а ввод HUD выключен — как у окон мета-слоя
## (MetaService._lock): иначе джойстик под окном перехватывает нажатия.
func _lock(on: bool) -> void:
	if on == _locked:
		return
	_locked = on
	var tree := get_tree()
	var player := tree.root.find_child("Player", true, false)
	var hud := tree.get_first_node_in_group("hud")
	if player != null:
		if on:
			_was_frozen = bool(player.get("frozen"))
			player.set("frozen", true)
			player.set("digging", null)
			if player.has_method("release_control"):
				player.call("release_control")
		else:
			player.set("frozen", _was_frozen)
	if hud != null:
		if on:
			_hud_input_was_on = hud.is_processing_input()
			hud.set_process_input(false)
			if hud.has_method("close_inventory"):
				hud.call("close_inventory")
		else:
			hud.set_process_input(_hud_input_was_on)
	Tip.hide_all()


# ---------------------------------------------------------------------------
# Меню «•••» — без бейджа (счётчик меню не трогаем)
# ---------------------------------------------------------------------------

static func _open_static() -> void:
	if instance != null and is_instance_valid(instance):
		instance.open()


func _register_menu() -> void:
	MenuRegistry.add("newbie_streak", {
		"icon": MetaUiKit.tex("newbie"),
		"title": func() -> String: return NewbieStreak.text("title"),
		"body": func() -> String: return NewbieStreakService.menu_body(),
		"order": 29,
		"visible": func() -> bool: return MetaState.is_unlocked(),
		"on_press": func() -> void: NewbieStreakService._open_static(),
	})


static func menu_body() -> String:
	NewbieStreak.ensure_started()   # пункт виден только после онбординга — календарь уже идёт
	var total := NewbieStreak.days_total()
	var n := NewbieStreak.today_n()
	if n > 0:
		return NewbieStreak.text("menu_body") % [n, total, NewbieStreak.done_count()]
	return NewbieStreak.text("menu_body_over") % [NewbieStreak.done_count(), total]

class_name MetaService
extends Node
## Мета-слой удержания: ежедневная награда с серией, ежедневные и недельные
## задания, достижения, дорога трофеев. Подключается одной строкой в main.gd:
##
##   MetaService.attach(self)
##
## Узел слушает шину GameState.game_event и сигналы GameState, кормит ими
## MetaEvents (чистая логика, см. остальные файлы scripts/meta/), показывает
## тосты, регистрирует пункты меню «•••» и сам открывает окно ежедневной
## награды при первом спокойном моменте за день.
##
## Включается только после онбординга: первая продажа золота (ГДД раздел 9,
## флаг сюжета gold_sold). До этого счётчики копятся молча, а пунктов меню,
## заданий, наград и тостов нет — обучение не перебивается.

signal changed

const POLL_SEC := 0.5
## Сколько секунд подряд должно быть «спокойно», прежде чем всплывёт окно дня.
const CALM_BEFORE_POPUP := 1.5

static var instance: MetaService = null

var hub: MetaHub = null
var popup: DailyPopup = null
var toast: MetaToast = null

var _acc: float = 0.0
var _calm_for: float = 0.0
var _dismissed_day: int = -1
var _road_ready: int = 0
var _locked: bool = false
var _was_frozen: bool = false
var _hud_input_was_on: bool = true


static func attach(host: Node) -> MetaService:
	if instance != null and is_instance_valid(instance):
		return instance
	var s := MetaService.new()
	s.name = "MetaService"
	host.add_child(s)
	return s


func _ready() -> void:
	instance = self
	hub = MetaHub.new()
	hub.name = "MetaHub"
	add_child(hub)
	popup = DailyPopup.new()
	popup.name = "DailyPopup"
	add_child(popup)
	toast = MetaToast.new()
	toast.name = "MetaToast"
	add_child(toast)
	hub.closed.connect(_on_modal_closed)
	popup.closed.connect(_on_popup_closed)
	popup.claimed.connect(_on_daily_claimed)

	GameState.game_event.connect(_on_bus_event)
	GameState.max_depth_changed.connect(_on_max_depth)
	GameState.leveled_up.connect(_on_leveled_up)
	GameState.artifact_collected.connect(_on_artifact)
	GameState.branch_completed.connect(_on_branch)
	GameState.died.connect(_on_died)
	GameState.daily_reset.connect(_poll)

	_register_menu()
	_road_ready = TrophyRoad.claimable().size()
	_poll()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	_acc += delta
	if _acc < POLL_SEC:
		return
	var dt := _acc
	_acc = 0.0
	_poll()
	_watch_daily_popup(dt)


# ---------------------------------------------------------------------------
# События
# ---------------------------------------------------------------------------

func _on_bus_event(id: StringName, data: Dictionary) -> void:
	# Эхо закрытия собственного задания уже учтено в MetaEvents.apply.
	if id == &"quest_done" and String(data.get("source", "")) == "meta":
		return
	_apply(id, data)


func _on_max_depth(depth: int) -> void:
	_apply(&"max_depth_changed", {"depth": depth})


func _on_leveled_up(level: int, _points: int) -> void:
	_apply(&"leveled_up", {"level": level})


func _on_artifact(id: String) -> void:
	_apply(&"artifact_collected", {"id": id})


func _on_branch(n: int) -> void:
	_apply(&"branch_completed", {"branch": n})


func _on_died() -> void:
	_apply(&"died", {})


func _apply(id: StringName, data: Dictionary) -> void:
	_announce(MetaEvents.apply(id, data))


func _announce(res: Dictionary) -> void:
	var any := false
	for q in res.get("quests", []):
		toast.show_quest(q)
		any = true
	for a in res.get("ach", []):
		toast.show_achievement(a)
		any = true
	if any:
		_after_progress()


func _after_progress() -> void:
	_check_road()
	changed.emit()
	if hub != null and hub.is_open():
		hub.refresh()


func _check_road() -> void:
	var n := TrophyRoad.claimable().size()
	if n > _road_ready:
		toast.show_road(n)
	_road_ready = n


## Зовут экраны после того, как игрок что-то забрал: сохранить, обновить.
func after_change() -> void:
	_check_road()
	persist()
	changed.emit()
	if hub != null and hub.is_open():
		hub.refresh()


## Награда уже выдана — фиксируем сейв сразу, как ShopService после продажи:
## иначе краш до автосейва вернул бы деньги в кошелёк, а «забрано» не запомнил.
func persist() -> void:
	if GameState.world_ref != null:
		SaveSystem.save_game()


func _on_daily_claimed(_res: Dictionary) -> void:
	_announce({"quests": [], "ach": Achievements.evaluate()})
	after_change()


# ---------------------------------------------------------------------------
# Опрос: онбординг, смена суток, окно дня
# ---------------------------------------------------------------------------

func _poll() -> void:
	if not MetaState.is_unlocked():
		if StoryState.has_flag("gold_sold"):
			_unlock()
		return
	if QuestEngine.refresh():
		changed.emit()
		if hub != null and hub.is_open():
			hub.refresh()


func _unlock() -> void:
	MetaState.root()["unlocked"] = true
	QuestEngine.refresh()
	_announce({"quests": [], "ach": Achievements.evaluate()})
	_road_ready = TrophyRoad.claimable().size()
	changed.emit()


func _watch_daily_popup(dt: float) -> void:
	if not MetaState.is_unlocked() or popup.is_open() or hub.is_open():
		_calm_for = 0.0
		return
	if _dismissed_day == MetaState.today() or not DailyReward.can_claim():
		return
	_calm_for = _calm_for + dt if _calm() else 0.0
	if _calm_for >= CALM_BEFORE_POPUP:
		_calm_for = 0.0
		open_daily()


## «Спокойный момент»: ничто не играет и не открыто, герой жив и не копает.
func _calm() -> bool:
	if not GameState.is_alive or GameState.is_digging:
		return false
	var tree := get_tree()
	var player := tree.root.find_child("Player", true, false)
	if player != null:
		# Не в прыжке, не в падении и не в полёте: окно замораживает героя на месте.
		if bool(player.get("frozen")) or not bool(player.get("on_ground")) or absf(float(player.get("vy"))) > 1.0:
			return false
	var director := tree.root.find_child("StoryDirector", true, false)
	if director != null:
		var cs = director.get("cutscene")
		if cs != null and bool(cs.get("is_playing")):
			return false
	var hud := tree.get_first_node_in_group("hud")
	if hud != null:
		if hud.has_method("is_more_menu_open") and hud.is_more_menu_open():
			return false
		if hud.has_method("is_settings_open") and hud.is_settings_open():
			return false
		var inv = hud.get("_inv_sheet")
		if inv != null and inv.visible:
			return false
		if hud.get("_well_panel") != null:
			return false
	if ShopUI.instance != null and ShopUI.instance.is_open():
		return false
	return not ProgressScreen.is_open()


# ---------------------------------------------------------------------------
# Экраны
# ---------------------------------------------------------------------------

func open_hub(tab: String = "") -> void:
	if hub.is_open():
		return
	if popup.is_open():
		popup.close()
	_lock(true)
	hub.open(tab)


func open_daily() -> void:
	if popup.is_open() or not MetaState.is_unlocked():
		return
	if hub.is_open():
		hub.close()
	_lock(true)
	popup.open()


func _on_modal_closed() -> void:
	if not popup.is_open():
		_lock(false)
	_after_progress()


func _on_popup_closed() -> void:
	if DailyReward.can_claim():
		_dismissed_day = MetaState.today()
	if not hub.is_open():
		_lock(false)
	_after_progress()


## Пока экран открыт, герой стоит, а ввод HUD выключен — как у ShopUI: иначе
## джойстик под экраном перехватывает нажатия раньше кнопок.
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
# Меню «•••»
# ---------------------------------------------------------------------------

func badge_total() -> int:
	return QuestEngine.claimable_count() + Achievements.unseen_count() + TrophyRoad.claimable().size()


func _register_menu() -> void:
	MenuRegistry.add("meta_daily", {
		"icon": MetaUiKit.tex("gift"),
		"title": "Ежедневный подарок",
		"body": func() -> String: return "Серия: %d" % int(DailyReward.plan()["streak"]),
		"order": 30,
		"visible": func() -> bool: return MetaState.is_unlocked(),
		"badge": func() -> int: return 1 if DailyReward.can_claim() else 0,
		"on_press": open_daily,
	})
	MenuRegistry.add("meta_rewards", {
		"icon": MetaUiKit.tex("trophy"),
		"title": "Награды",
		"body": "Задания, достижения, дорога трофеев",
		"order": 31,
		"visible": func() -> bool: return MetaState.is_unlocked(),
		"badge": badge_total,
		"on_press": func() -> void: open_hub(),
	})

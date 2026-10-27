class_name TeleportLesson
extends Node
## Обучение премиум-лавке на глубине 200 (слова владельца 27.10): «всё остальное темнеет
## и не кликабельно, кроме валютного магазина на экране, и стрелочка показывает нажать
## туда; потом так же в магазине всё тёмное, кроме часов телепорта… после нажатия
## появляется объяснение… сюжетно даёт воспользоваться часами бесплатно 1 раз».
##
## Ход: сюжетная сцена teleport_watch (data/story_arc.json, depth 200: звонок бабушки —
## «первый раз за мой счёт») → событие story_beat → подарок (бесплатное применение
## часов) ложится сразу, обучение ждёт безопасного момента и ведёт FocusTour:
##   а) тень везде, кроме кнопки лавки на HUD, стрелка на неё;
##   б) в лавке тень везде, кроме плитки часов, стрелка на неё (лавку закрыли — назад к а);
##   в) карточка-объяснение; кнопка «Наверх» тратит подарок и переносит героя на площадку
##      (на поверхности — «Понятно», подарок остаётся на плитке часов).
## Пропуск (⏭ сцены или обучения) подарок не отнимает: плитка часов показывает «0 $» с
## подарком, пока им не воспользуются. Закрыли игру посреди обучения — после загрузки
## оно не повторяется (герой всё равно дома), подарок на месте.
##
## Безопасный момент — как у сюжетных сцен, но строже (обучение замораживает героя): жив,
## не в доме, на земле, без тяги и перехода в бурмобиль, нет окон и сцен, нет боя рядом.

const SCENE_ID := "teleport_watch"
const SHOP_TILE := "shop:good:dollars:teleport_watch"
const DIG_WAIT_MS := 4000   # копает без передышки дольше — обучение снимает копку само
const COMBAT_NEAR := 10.0   # монстр ближе стольких клеток — это бой

var watch: TeleportWatch = null
var tour: FocusTour = null
var _pending: bool = false
var _dig_since: int = -1


func _ready() -> void:
	GameState.game_event.connect(_on_game_event)
	# Прерванное обучение (игру закрыли посреди шагов) не возобновляем: после загрузки
	# герой дома, переносить некого. Подарок остался на плитке.
	if TeleportWatch.lesson_state() == "running":
		TeleportWatch.set_lesson_state("done")


func is_active() -> bool:
	return _pending or (tour != null and is_instance_valid(tour) and tour.is_running())


func _on_game_event(id: StringName, data: Dictionary) -> void:
	if String(id) == "story_beat" and String(data.get("id", "")) == SCENE_ID:
		begin()


## Выдать подарок и поставить обучение в очередь. Повторно не срабатывает.
func begin() -> void:
	if TeleportWatch.lesson_state() != "":
		return
	TeleportWatch.grant_free(int(TeleportWatch.num("lesson_free_uses", 1)))
	TeleportWatch.set_lesson_state("running")
	SaveSystem.save_game()
	_pending = true
	_dig_since = -1


func _process(_dt: float) -> void:
	if tour != null and is_instance_valid(tour) and tour.is_running() \
			and (not GameState.is_alive or GameState.max_depth_reached == 0):
		# Смерть (лава, жара) или «Сброс» посреди шагов: тень не должна пережить игру.
		tour.stop()
		return
	if not _pending:
		return
	if not GameState.is_alive:
		# Смерть до начала: обучать некого, подарок остаётся.
		_pending = false
		TeleportWatch.set_lesson_state("done")
		return
	if _safe_now():
		_pending = false
		_start_tour()


# ---------------------------------------------------------------------------
# Безопасный момент
# ---------------------------------------------------------------------------

func _safe_now() -> bool:
	var p = watch.player if watch != null else null
	if p == null or not is_instance_valid(p):
		return false
	if GameState.house_is_indoors or GameState.era == "grandpa" or bool(p.get("frozen")):
		return false
	if FocusTour.is_any_running() or _story_busy() or _window_open() or _in_combat(p):
		return false
	if not bool(p.get("on_ground")) or absf(float(p.get("vy"))) > 0.5:
		return false
	if String(p.get("thrust")) != "" or String(p.get("rig_transition")) != "":
		return false
	if p.get("digging") != null:
		var now := Time.get_ticks_msec()
		if _dig_since < 0:
			_dig_since = now
		return now - _dig_since >= DIG_WAIT_MS
	_dig_since = -1
	return true


## Сцена идёт или вот-вот начнётся. Очередь сама по себе не мешает: сцена «только на
## поверхности» (звонок про могилу) ждёт там, а обучение нужно именно на глубине.
func _story_busy() -> bool:
	var d := get_tree().root.find_child("StoryDirector", true, false)
	if d == null:
		return not GameState.story_queue.is_empty()
	if bool(d.get("_playing")):
		return true
	if d.has_method("_next_playable") and String(d.call("_next_playable")) != "":
		return true
	var ad = d.get("auto_dig")
	if ad != null and bool(ad.get("running")):
		return true
	var diary = d.get("diary_ui")
	return diary != null and bool(diary.get("is_open"))


func _window_open() -> bool:
	if ShopUI.instance != null and ShopUI.instance.is_open():
		return true
	if ProgressScreen.is_open() or DeathWindow.is_open_any() or TechSystem.is_modal_open():
		return true
	if ProjectsScreen.is_open_any():
		return true
	var ms := MetaService.instance
	if ms != null and is_instance_valid(ms):
		if (ms.hub != null and ms.hub.is_open()) or (ms.popup != null and ms.popup.is_open()):
			return true
	var hud = watch.hud if watch != null else null
	if hud != null and is_instance_valid(hud):
		if not hud.visible or not hud.is_processing_input():
			return true
		if hud.has_method("is_more_menu_open") and hud.is_more_menu_open():
			return true
		for sheet in ["_inv_sheet", "_settings_sheet"]:
			var s = hud.get(sheet)
			if s != null and is_instance_valid(s) and s.visible:
				return true
	return false


func _in_combat(p) -> bool:
	var d = CombatService.director
	if d == null or not is_instance_valid(d):
		return false
	if d.has_method("boss_fight_active") and d.boss_fight_active():
		return true
	var here := Vector2(float(p.get("x")), float(p.get("y")))
	for m in d.get("monsters"):
		if m != null and is_instance_valid(m) and Vector2(float(m.get("x")), float(m.get("y"))).distance_to(here) < COMBAT_NEAR:
			return true
	return false


# ---------------------------------------------------------------------------
# Шаги
# ---------------------------------------------------------------------------

func _start_tour() -> void:
	var host: Node = watch.get_parent() if watch != null else get_parent()
	tour = FocusTour.begin(host, steps(), {"skippable": true})
	tour.finished.connect(_on_tour_finished)


func steps() -> Array:
	return [
		{
			"id": "open_shop",
			"target": _shop_button,
			"label": TeleportWatch.text("step_shop"),
			"icon": ShopArt.ui("icon_dollar"),
			"until": func() -> bool: return _shop_on_premium(),
		},
		{
			"id": "watch_tile",
			"target": SHOP_TILE,
			"tap": "catch",
			"label": TeleportWatch.text("step_watch"),
			"back": func() -> bool: return not _shop_on_premium(),
		},
		{
			"id": "explain",
			"card": _card_def(),
			"on_tap": _on_card_pressed,
		},
	]


## Кнопка лавки на HUD — по узлу, а не по координатам: верх HUD двигают другие ветки.
## HUD хранит её в _shop_btn; переименуют поле — найдём кнопку по заголовку её подсказки.
func _shop_button() -> Control:
	var hud = watch.hud if watch != null else null
	if hud == null or not is_instance_valid(hud):
		return null
	var b = hud.get("_shop_btn")
	if b is Control and is_instance_valid(b):
		return b
	for n in (hud as Node).find_children("*", "BaseButton", true, false):
		var meta = n.get_meta(Tip.META, {})
		if typeof(meta) == TYPE_DICTIONARY and String(meta.get("title", "")) == "Магазин":
			return n as Control
	return null


func _shop_on_premium() -> bool:
	var shop := ShopUI.instance
	return shop != null and shop.is_open() and String(shop.get("_tab")) == ShopUI.SCREEN_PREMIUM


func _hero_underground() -> bool:
	var p = watch.player if watch != null else null
	return p != null and is_instance_valid(p) and int(floor(float(p.get("y")))) >= 1


func _card_def() -> Dictionary:
	var go := _hero_underground()
	return {
		"icon": ShopArt.item_icon(TeleportWatch.GOOD_ID),
		"title": TeleportWatch.text("card_title"),
		"text": TeleportWatch.text("card_text"),
		"button_icon": ShopArt.tex("glyph_gift") if go else ShopArt.tex("glyph_check"),
		"button_text": TeleportWatch.text("card_go") if go else TeleportWatch.text("card_ok"),
	}


## «Наверх»: сначала снять обучение и закрыть лавку (управление возвращается как было),
## потом перенос — герой уже свободен и стоит на площадке.
func _on_card_pressed() -> void:
	var go := _hero_underground()
	if tour != null and is_instance_valid(tour):
		tour.complete()
	if ShopUI.instance != null and ShopUI.instance.is_open():
		ShopUI.instance.close()
	if go and watch != null and TeleportWatch.use_free(watch.player):
		watch.pulse_button()


func _on_tour_finished(skipped: bool) -> void:
	TeleportWatch.set_lesson_state("done")
	SaveSystem.save_game()
	if skipped and TeleportWatch.free_uses() > 0 and watch != null and watch.hud != null \
			and watch.hud.has_method("toast"):
		watch.hud.toast(TeleportWatch.text("skipped_toast"), 3.4)

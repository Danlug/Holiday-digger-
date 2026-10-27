class_name TeleportLesson
extends Node
## Обучение премиум-лавке на глубине 200 (слова владельца 27.10): «всё остальное темнеет
## и не кликабельно, кроме валютного магазина на экране, и стрелочка показывает нажать
## туда; потом так же в магазине всё тёмное, кроме часов телепорта… после нажатия
## появляется объяснение… сюжетно даёт воспользоваться часами бесплатно 1 раз».
##
## Ход: сюжетная сцена teleport_watch (data/story_arc.json, depth 200: звонок бабушки —
## «первый раз за мой счёт») → событие story_beat → подарок (бесплатное применение
## часов) ложится сразу, обучение ждёт безопасного момента и ведёт тем же спотлайтом,
## что и выгрузка на 150 (GuideSpotlight: один механизм затемнения на игру):
##   а) затемнено всё, кроме кнопки лавки на HUD, стрелка на неё (у стрелки — значок часов);
##   б) в лавке затемнено всё, кроме плитки часов, стрелка и бант подарка
##      (лавку закрыли «назад» — снова к а);
##   в) карточка-объяснение со словами владельца; кнопка «Наверх» тратит подарок и
##      переносит героя на площадку (на поверхности — «Понятно», подарок остаётся на плитке).
## Нажатие по цели урок забирает себе (pass_through выключен): плитка часов не открывает
## окно покупки, бесплатный раз не становится покупкой.
## Пропуск (⏭ сцены или обучения) подарок не отнимает: плитка часов показывает «0 $» с
## бантом, пока им не воспользуются. Закрыли игру посреди шагов — после загрузки обучение
## не повторяется (герой всё равно дома), подарок на месте.
##
## Безопасный момент строже сюжетных сцен (урок замораживает героя): жив, не в доме, на
## земле, без тяги и перехода в бурмобиль, нет окон, сцен и урока выгрузки, нет боя рядом;
## копающему без передышки — не дольше DIG_WAIT_MS.

const SCENE_ID := "teleport_watch"
const TILE_KEY := "good:dollars:" + TeleportWatch.GOOD_ID
const DIG_WAIT_MS := 4000   # копает без передышки дольше — обучение снимает копку само
const COMBAT_NEAR := 10.0   # монстр ближе стольких клеток — это бой

enum Step { IDLE, WAIT, SHOP, TILE, CARD }
const STEP_IDS := {Step.SHOP: "open_shop", Step.TILE: "watch_tile", Step.CARD: "explain"}

static var instance: TeleportLesson = null

var watch: TeleportWatch = null
var spotlight: GuideSpotlight
var step: int = Step.IDLE
var _dig_since: int = -1
var _scrolled: bool = false
var _was_frozen: bool = false
var _hud_input_was: bool = true


func _ready() -> void:
	instance = self
	spotlight = GuideSpotlight.new()
	spotlight.name = "TeleportSpotlight"
	add_child(spotlight)
	spotlight.target_pressed.connect(_on_target)
	spotlight.card_pressed.connect(_on_card)
	spotlight.skipped.connect(skip)
	GameState.game_event.connect(_on_game_event)
	# Прерванное обучение (игру закрыли посреди шагов) не возобновляем: после загрузки
	# герой дома, переносить некого. Подарок остался на плитке.
	if TeleportWatch.lesson_state() == "running":
		TeleportWatch.set_lesson_state("done")


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Шаги а–в идут (герой стоит, тень на экране).
func is_active() -> bool:
	return step == Step.SHOP or step == Step.TILE or step == Step.CARD


func current_step() -> String:
	return String(STEP_IDS.get(step, ""))


## Куда нажать сейчас (бот и тест жмут в середину): окно цели или кнопка карточки.
func target_rect() -> Rect2:
	if step == Step.CARD:
		var b := spotlight.card_button()
		return b.get_global_rect() if b != null else Rect2()
	return spotlight.hole() if is_active() else Rect2()


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
	step = Step.WAIT
	_dig_since = -1


func _process(_dt: float) -> void:
	match step:
		Step.WAIT:
			if not GameState.is_alive:
				# Смерть до начала: обучать некого, подарок остаётся.
				_set_done()
				step = Step.IDLE
			elif _safe_now():
				_start()
		Step.SHOP, Step.TILE, Step.CARD:
			_tick_running()


# ---------------------------------------------------------------------------
# Безопасный момент
# ---------------------------------------------------------------------------

func _player():
	return watch.player if watch != null else null


func _hud():
	return watch.hud if watch != null else null


func _safe_now() -> bool:
	var p = _player()
	if p == null or not is_instance_valid(p) or _shop_button() == null:
		return false
	if GameState.house_is_indoors or GameState.era == "grandpa" or bool(p.get("frozen")):
		return false
	if GuideSpotlight.any_active() or _unload_lesson_busy() or _story_busy() or _window_open() or _in_combat(p):
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


func _unload_lesson_busy() -> bool:
	var u := PremiumUnloadLesson.instance
	return u != null and is_instance_valid(u) and int(u.step) != PremiumUnloadLesson.Step.IDLE


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
	var hud = _hud()
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
# Цели
# ---------------------------------------------------------------------------

## Кнопка лавки на HUD — по узлу, а не по координатам: верх HUD двигают другие ветки.
## HUD хранит её в _shop_btn; переименуют поле — найдём кнопку по заголовку её подсказки.
func _shop_button() -> Control:
	var hud = _hud()
	if hud == null or not is_instance_valid(hud):
		return null
	var b = hud.get("_shop_btn")
	if not (b is Control and is_instance_valid(b)):
		b = null
		for n in (hud as Node).find_children("*", "BaseButton", true, false):
			var meta = n.get_meta(Tip.META, {})
			if typeof(meta) == TYPE_DICTIONARY and String(meta.get("title", "")) == "Магазин":
				b = n
				break
	return b as Control if b != null and (b as Control).is_visible_in_tree() else null


func _shop_rect() -> Rect2:
	var b := _shop_button()
	return b.get_global_rect() if b != null else Rect2()


func _tile() -> Control:
	var ui := ShopUI.instance
	if ui == null or not ui.is_open():
		return null
	var tiles = ui.get("_tiles")
	var t = (tiles as Dictionary).get(TILE_KEY, null) if typeof(tiles) == TYPE_DICTIONARY else null
	if t == null or not is_instance_valid(t):   # витрина пересобирает плитки
		return null
	return t as Control if (t as Control).is_visible_in_tree() else null


func _tile_rect() -> Rect2:
	var t := _tile()
	if t == null:
		return Rect2()
	if not _scrolled:
		_scrolled = true
		var sc = ShopUI.instance.get("_scroll")
		if sc is ScrollContainer:
			(sc as ScrollContainer).ensure_control_visible(t)
	return t.get_global_rect()


func _hero_underground() -> bool:
	var p = _player()
	return p != null and is_instance_valid(p) and int(floor(float(p.get("y")))) >= 1


# ---------------------------------------------------------------------------
# Шаги
# ---------------------------------------------------------------------------

func _start() -> void:
	var p = _player()
	var hud = _hud()
	_was_frozen = bool(p.get("frozen"))
	p.set("frozen", true)
	p.set("digging", null)
	if p.has_method("release_control"):
		p.call("release_control")
	_hud_input_was = hud.is_processing_input()
	hud.set_process_input(false)   # джойстик слушает _input мимо фильтров Control
	if hud.has_method("close_inventory"):
		hud.close_inventory()
	Sfx.play("ui_open")
	_to_shop_step()


func _to_shop_step() -> void:
	step = Step.SHOP
	spotlight.point_at(_shop_rect, ShopArt.item_icon(TeleportWatch.GOOD_ID))


## Пока идут шаги: умер, попал в дом, «Сброс» — снять; лавку закрыли «назад» — к кнопке лавки.
func _tick_running() -> void:
	if not GameState.is_alive or GameState.house_is_indoors or GameState.max_depth_reached == 0:
		skip()
		return
	if step == Step.TILE and (ShopUI.instance == null or not ShopUI.instance.is_open()):
		_to_shop_step()


func _on_target() -> void:
	match step:
		Step.SHOP:
			Sfx.play("ui_tap")
			Haptics.tap()
			ShopUI.open_premium()
			step = Step.TILE
			_scrolled = false
			spotlight.point_at(_tile_rect, ShopArt.tex("glyph_gift"))
		Step.TILE:
			Sfx.play("ui_tap")
			Haptics.tap()
			step = Step.CARD
			spotlight.show_card(_card_def())


func _card_def() -> Dictionary:
	var go := _hero_underground()
	return {
		"icon": ShopArt.item_icon(TeleportWatch.GOOD_ID),
		"title": TeleportWatch.text("card_title"),
		"text": TeleportWatch.text("card_text"),
		"button_icon": ShopArt.tex("glyph_gift") if go else ShopArt.tex("glyph_check"),
		"button_text": TeleportWatch.text("card_go") if go else TeleportWatch.text("card_ok"),
	}


## «Наверх»: снять обучение и закрыть лавку (управление возвращается как было), потом
## перенос — герой уже свободен и встаёт на площадку.
func _on_card() -> void:
	if step != Step.CARD:
		return
	var go := _hero_underground()
	_set_done()
	_close_and_release()
	if go and watch != null and TeleportWatch.use_free(_player()):
		watch.pulse_button()


## ⏭ (или урок сорвался: смерть, дом, сброс) — обучение пройдено, подарок остаётся на плитке.
func skip() -> void:
	if not is_active():
		return
	_set_done()
	_close_and_release()
	var hud = _hud()
	if TeleportWatch.free_uses() > 0 and GameState.is_alive and hud != null and hud.has_method("toast"):
		hud.toast(TeleportWatch.text("skipped_toast"), 3.4)


func _set_done() -> void:
	TeleportWatch.set_lesson_state("done")
	SaveSystem.save_game()


## Сначала лавка: закрываясь, она возвращает «как было при открытии» (заморожено уроком),
## и только потом урок возвращает своё «как было до урока».
func _close_and_release() -> void:
	spotlight.clear()
	step = Step.IDLE
	if ShopUI.instance != null and ShopUI.instance.is_open():
		ShopUI.instance.close()
	var p = _player()
	if p != null and is_instance_valid(p):
		p.set("frozen", _was_frozen or GameState.house_is_indoors)
	var hud = _hud()
	if hud != null and is_instance_valid(hud):
		hud.set_process_input(_hud_input_was)

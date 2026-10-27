class_name PremiumUnloadLesson
extends Node
## PremiumUnloadLesson — сцена «выгрузка на склад» на глубине 150 (раунд 6, слова
## владельца: «на глубине в 150–200 сделай тоже сценарий с этим, объясни, что есть
## такая функция, чтобы не бегать туда-сюда»).
##
## Один раз за игру, при первом рекорде глубины в поясе [150, 200) (data/shop.json →
## goods_dollars.extra[premium_unload].lesson). На 200 своё обучение у часов-телепорта:
## не начатая к 200 выгрузка тихо пропускается, сцены не встают друг на друга.
## Ждёт безопасного момента: не в бою, не в падении, не поверх окна или катсцены,
## под землёй и с добычей в рюкзаке; копающему без пауз — не дольше calm_wait_s.
##
## Ход (по образцу обучения часам):
##   1. затемнено всё, кроме кнопки магазина на HUD, к ней — стрелка (GuideSpotlight);
##   2. в витрине затемнено всё, кроме плитки выгрузки, стрелка;
##   3. нажатие — первая выгрузка бесплатно (free_use, proposed): добыча летит домой;
##   4. объяснение — катсцена unload_150 (бабка по телефону, карточка выгрузки).
## ⏭ на шагах 1–2 — урок пропущен насовсем, как у катсцен.
##
## Состояние — GameState.ext["premium_unload"]["lesson"]: "" → "armed" → "done" |
## "skipped" | "missed". Посреди шагов 1–2 урок не сохраняется: после загрузки он
## снова «armed» и начнётся с начала.

const EXT_KEY := "premium_unload"
const SCENE := "unload_150"
const TILE_KEY := "good:dollars:" + PremiumUnload.ID
const FOUNDATION := 5   # выше фундамента — огород: там склад в двух шагах

enum Step { IDLE, SHOP, TILE, FX }

static var instance: PremiumUnloadLesson = null

## Сколько ждать спокойного героя, прежде чем начать всё равно (тесты ставят 0).
var calm_wait_s: float = 15.0
## Сколько показывать «улетело домой» до объяснения (тесты ставят 0).
var fx_wait_s: float = PremiumUnloadFx.DURATION
var step: int = Step.IDLE
var spotlight: GuideSpotlight

var _waited: float = 0.0
var _fx_left: float = 0.0
var _player: Node = null
var _hud: Node = null
var _was_frozen: bool = false
var _hud_input_was: bool = true
var _scrolled: bool = false


static func attach(host: Node) -> PremiumUnloadLesson:
	var l := PremiumUnloadLesson.new()
	l.name = "PremiumUnloadLesson"
	host.add_child(l)
	return l


# ---------------------------------------------------------------------------
# Данные и состояние
# ---------------------------------------------------------------------------

static func _cfg() -> Dictionary:
	return ShopCatalog.good(PremiumUnload.ID, "dollars").get("lesson", {})


## Пояс глубины [from, until).
static func band() -> Vector2i:
	var c := _cfg()
	return Vector2i(int(Balance.unwrap(c.get("depth", 150))), int(Balance.unwrap(c.get("until", 200))))


static func free_use() -> bool:
	return bool(Balance.unwrap(_cfg().get("free_use", true)))


static func state() -> String:
	var d = GameState.ext_get(EXT_KEY, {})
	return String(d.get("lesson", "")) if typeof(d) == TYPE_DICTIONARY else ""


static func _set_state(s: String) -> void:
	var d = GameState.ext_get(EXT_KEY, {})
	if typeof(d) != TYPE_DICTIONARY:
		d = {}
	d["lesson"] = s
	GameState.ext_set(EXT_KEY, d)


func _ready() -> void:
	instance = self
	calm_wait_s = float(Balance.unwrap(_cfg().get("calm_wait_seconds", calm_wait_s)))
	spotlight = GuideSpotlight.new()
	add_child(spotlight)
	spotlight.target_pressed.connect(_on_target)
	spotlight.skipped.connect(skip)
	GameState.max_depth_changed.connect(_on_record)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Рекорд глубины (сигнал GameState.max_depth_changed): первый в поясе взводит урок.
## Прямое присвоение max_depth_reached (тесты, отладка) рекордом не считается.
func _on_record(depth: int) -> void:
	var b := band()
	if state() == "" and depth >= b.x and depth < b.y:
		_set_state("armed")
		_waited = 0.0


func is_active() -> bool:
	return step == Step.SHOP or step == Step.TILE


## Прямоугольник цели на экране (бот и тест жмут в его середину).
func target_rect() -> Rect2:
	return spotlight.hole() if is_active() else Rect2()


# ---------------------------------------------------------------------------
# Кадр
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	tick(dt)


## Один шаг (тест зовёт с нужным dt сам, без таймеров сцены).
func tick(dt: float) -> void:
	match step:
		Step.IDLE:
			_tick_armed(dt)
		Step.SHOP, Step.TILE:
			_tick_running()
		Step.FX:
			_fx_left -= dt
			if _fx_left <= 0.0:
				_explain()


func _tick_armed(dt: float) -> void:
	if state() != "armed":
		return
	if GameState.max_depth_reached >= band().y:
		_set_state("missed")   # к 200 так и не нашлось спокойной минуты — там уже обучение часам
		return
	if not hard_ready():
		return
	_waited += dt
	if _calm() or _waited >= calm_wait_s:
		start()


## Жёсткие условия — их таймаут не обходит: жив, под землёй, на земле (не в падении),
## не в бою, без окон и катсцен, в рюкзаке есть что отправить, у HUD есть кнопка магазина.
func hard_ready() -> bool:
	_resolve()
	if _player == null or _hud == null or ShopUI.instance == null or _shop_button() == null:
		return false
	if not HintBusy.onboarding_done() or HintBusy.is_busy() or not GameState.story_queue.is_empty():
		return false
	if _hud.has_method("is_more_menu_open") and _hud.is_more_menu_open():
		return false
	if int(_player.call("cell_y")) <= FOUNDATION or not bool(_player.get("on_ground")):
		return false
	if String(_player.get("rig_transition")) != "" or bool(_player.get("frozen")):
		return false
	return PremiumUnload.can_unload()


func _calm() -> bool:
	return _player.get("digging") == null and String(_player.get("thrust")) == ""


func _resolve() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().root.find_child("Player", true, false) if is_inside_tree() else null
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("hud") if is_inside_tree() else null


func _shop_button() -> Control:
	var b = _hud.get("_shop_btn") if _hud != null else null
	return b as Control if b is Control and (b as Control).is_visible_in_tree() else null


func _tile() -> ShopTile:
	var ui := ShopUI.instance
	if ui == null or not ui.is_open():
		return null
	var t = ui._tiles.get(TILE_KEY)
	return t as ShopTile if t is ShopTile and is_instance_valid(t) and (t as ShopTile).is_visible_in_tree() else null


# ---------------------------------------------------------------------------
# Шаги
# ---------------------------------------------------------------------------

func start() -> void:
	_resolve()
	step = Step.SHOP
	_scrolled = false
	_was_frozen = bool(_player.get("frozen"))
	_player.set("frozen", true)
	_player.set("digging", null)
	if _player.has_method("release_control"):
		_player.call("release_control")
	_hud_input_was = _hud.is_processing_input()
	_hud.set_process_input(false)   # джойстик слушает _input мимо фильтров Control
	if _hud.has_method("close_inventory"):
		_hud.close_inventory()
	Sfx.play("ui_open")
	spotlight.point_at(_shop_rect, ShopArt.item_icon(PremiumUnload.ID))


func _shop_rect() -> Rect2:
	var b := _shop_button()
	return b.get_global_rect() if b != null else Rect2()


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


## Пока идут шаги 1–2: умер, попал в дом, витрину закрыли — откат.
func _tick_running() -> void:
	if not GameState.is_alive or GameState.house_is_indoors:
		_abort()
		return
	if step == Step.TILE and (ShopUI.instance == null or not ShopUI.instance.is_open()):
		# Витрину закрыли «назад» — снова к кнопке магазина.
		step = Step.SHOP
		spotlight.point_at(_shop_rect, ShopArt.item_icon(PremiumUnload.ID))


func _on_target() -> void:
	match step:
		Step.SHOP:
			Sfx.play("ui_tap")
			Haptics.tap()
			ShopUI.open_premium()
			step = Step.TILE
			_scrolled = false
			spotlight.point_at(_tile_rect)
		Step.TILE:
			_press_tile()


func _press_tile() -> void:
	var t := _tile()
	var from := t.get_global_rect().get_center() if t != null else Vector2(112, 240)
	spotlight.clear()
	step = Step.FX
	_fx_left = 0.25
	if free_use() and PremiumUnload.can_unload():
		var r := PremiumUnload.unload(true)
		var d = GameState.ext_get(EXT_KEY, {})
		if typeof(d) == TYPE_DICTIONARY:
			d["free_used"] = true
			GameState.ext_set(EXT_KEY, d)
		if t != null:
			ShopFx.pop(t, 0.16, 0.26)
		PremiumUnloadFx.play(self, from, r.get("moved", {}))
		_fx_left = fx_wait_s
	else:
		Sfx.play("ui_tap")


## Шаг 4: урок засчитан, витрина закрыта, герой отпущен — объяснение катсценой.
func _explain() -> void:
	_set_state("done")
	_close_and_release()
	SaveSystem.save_game()
	var director := get_tree().root.find_child("StoryDirector", true, false) if is_inside_tree() else null
	if director != null and director.has_method("play") and StoryData.has_scene(SCENE):
		director.call("play", SCENE)


## ⏭ — урок пропущен насовсем (как пропущенная катсцена).
func skip() -> void:
	if not is_active():
		return
	_set_state("skipped")
	_close_and_release()
	SaveSystem.save_game()


## Сорвался (смерть, дом): не засчитан, начнётся заново в следующий спокойный момент.
func _abort() -> void:
	_close_and_release()
	_waited = 0.0


func _close_and_release() -> void:
	spotlight.clear()
	step = Step.IDLE
	if ShopUI.instance != null and ShopUI.instance.is_open():
		ShopUI.instance.close()
	if _player != null and is_instance_valid(_player):
		_player.set("frozen", _was_frozen or GameState.house_is_indoors)
	if _hud != null and is_instance_valid(_hud):
		_hud.set_process_input(_hud_input_was)

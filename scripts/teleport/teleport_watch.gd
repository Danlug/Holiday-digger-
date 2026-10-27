class_name TeleportWatch
extends Node
## Часы-телепорт (ГДД §15.3): куда переносят, возврат под землю, площадка с огоньком.
##
## Слова владельца (27.10): часы переносят героя на мини-платформу на траве справа от
## тоннеля; после этого можно ОДИН раз вернуться на исходную точку под землёй; пока
## возврат доступен, над платформой горит зелёный неоновый огонёк.
##
## Состояние — GameState.ext["teleport_watch"] (сейв без правки SaveSystem):
##   ret     {x, y} — откуда перенесли часы (возврат ещё не использован) или {} — возврата нет;
##   free    сколько бесплатных применений часов (подарок обучения на 200);
##   lesson  "" | "running" | "done" — обучение премиум-лавке (scripts/teleport/teleport_lesson.gd);
##   uses    сколько раз часами пользовались (для статистики и теста).
## Правила возврата: один на одно применение часов; новое применение под землёй ставит
## новую точку (старая пропадает — возвраты не копятся); применение на поверхности точку
## не трогает. Смерть гасит возврат: «скорая» увозит домой, вылазка окончена — иначе
## смерть + возврат работали бы лифтом вниз (владелец, раунд 5: смерть — не удобный способ
## перемещаться). Сброс прогресса очищает ext целиком.
##
## Узел (attach из main.gd одной строкой): площадка с огоньком в мире, пузырь «Вниз»
## над героем на площадке, обучение на глубине 200.

const KEY := "teleport_watch"
const GOOD_ID := "teleport_watch"
const DATA_PATH := "res://data/teleport_watch.json"
const TILE := 32
const SURFACE_Y := 0.5      # y героя, поставленного на траву (как teleport_home)
const SKY_HEIGHT: int = preload("res://scripts/world/world_view.gd").SKY_HEIGHT

static var _cfg: Dictionary = {}

var player = null   # Player (player.gd): свойства x/y и методы героя — без статического типа
var world: WorldGen = null
var hud: Node = null
var pad: TeleportPad = null
var lesson: TeleportLesson = null
var _layer: CanvasLayer
var _button: HouseBubble
var _pulse_left: float = 0.0


# ---------------------------------------------------------------------------
# Подключение
# ---------------------------------------------------------------------------

static func attach(host: Node) -> TeleportWatch:
	var tw := TeleportWatch.new()
	tw.name = "TeleportWatch"
	tw.player = host.get("player")
	tw.world = host.get("world")
	tw.hud = host.get("hud")
	host.add_child(tw)
	var view_root: Node = host.get("view_root")
	if view_root != null:
		tw.pad = TeleportPad.new()
		tw.pad.name = "TeleportPad"
		view_root.add_child(tw.pad)
		# Сразу за жизнью поверхности (трава, бабочки) и перед героем: плита лежит на траве,
		# герой стоит на плите.
		var life := view_root.get_node_or_null("SurfaceLife")
		var anchor := life if life != null else view_root.get_node_or_null("WorldView")
		if anchor != null:
			view_root.move_child(tw.pad, anchor.get_index() + 1)
	return tw


static func find(tree: SceneTree) -> TeleportWatch:
	if tree == null:
		return null
	return tree.root.find_child("TeleportWatch", true, false) as TeleportWatch


func _ready() -> void:
	_build_button()
	lesson = TeleportLesson.new()
	lesson.name = "TeleportLesson"
	lesson.watch = self
	add_child(lesson)
	GameState.died.connect(_on_died)


# ---------------------------------------------------------------------------
# Данные и состояние
# ---------------------------------------------------------------------------

static func cfg() -> Dictionary:
	if _cfg.is_empty():
		if FileAccess.file_exists(DATA_PATH):
			var raw = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if typeof(raw) == TYPE_DICTIONARY:
				_cfg = raw
		if _cfg.is_empty():
			_cfg = {"_empty": true}
	return _cfg


static func num(key: String, fallback: float) -> float:
	return float(Balance.unwrap(cfg().get(key, fallback)))


## Строка интерфейса на языке настроек (data/teleport_watch.json → texts).
static func text(key: String) -> String:
	var texts: Dictionary = cfg().get("texts", {})
	var lang := String(Settings.language)
	var table: Dictionary = texts.get(lang, texts.get("ru", {}))
	return String(table.get(key, texts.get("ru", {}).get(key, key)))


static func state() -> Dictionary:
	var raw = GameState.ext_get(KEY, {})
	var s: Dictionary = raw.duplicate(true) if typeof(raw) == TYPE_DICTIONARY else {}
	var ret = s.get("ret", {})
	if typeof(ret) != TYPE_DICTIONARY or not (ret.has("x") and ret.has("y")):
		ret = {}
	s["ret"] = ret
	s["free"] = maxi(0, int(s.get("free", 0)))
	s["lesson"] = str(s.get("lesson", "")) if typeof(s.get("lesson", "")) == TYPE_STRING else ""
	s["uses"] = maxi(0, int(s.get("uses", 0)))
	return s


static func _store(s: Dictionary) -> void:
	GameState.ext_set(KEY, s)


## Каждый кадр (огонёк, пузырь) — без копии состояния.
static func has_return() -> bool:
	var raw = GameState.ext_get(KEY, null)
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var ret = (raw as Dictionary).get("ret", null)
	return typeof(ret) == TYPE_DICTIONARY and (ret as Dictionary).has("x") and (ret as Dictionary).has("y")


## Точка возврата в клетках (центр героя) или (-1, -1).
static func return_point() -> Vector2:
	var ret: Dictionary = state()["ret"]
	if ret.is_empty():
		return Vector2(-1, -1)
	return Vector2(float(ret["x"]), float(ret["y"]))


static func clear_return() -> void:
	var s := state()
	if (s["ret"] as Dictionary).is_empty():
		return
	s["ret"] = {}
	_store(s)


static func free_uses() -> int:
	return int(state()["free"])


static func grant_free(n: int = 1) -> void:
	var s := state()
	s["free"] = int(s["free"]) + n
	_store(s)


## Списать один бесплатный раз; false — бесплатных нет.
static func take_free() -> bool:
	var s := state()
	if int(s["free"]) <= 0:
		return false
	s["free"] = int(s["free"]) - 1
	_store(s)
	return true


static func lesson_state() -> String:
	return String(state()["lesson"])


static func set_lesson_state(v: String) -> void:
	var s := state()
	s["lesson"] = v
	_store(s)


## Площадка стоит, когда есть тоннель Роберта (до него огород ещё копается, и садиться
## было бы некуда) и не в эпоху деда.
static func pad_ready() -> bool:
	return GameState.house_hatch_built and GameState.era != "grandpa"


## Центр площадки в клетках (x героя, стоящего на ней).
static func pad_x() -> float:
	return float(WorldGen.TELEPORT_PAD_X) + 0.5


static func near_pad(px: float, py: float) -> bool:
	return py < 1.5 and absf(px - pad_x()) <= num("near_cells", 0.75)


# ---------------------------------------------------------------------------
# Часы: перенос наверх
# ---------------------------------------------------------------------------

## Применить часы: запомнить точку (если герой под землёй), перенести на площадку.
## Возвращает {ok, saved: bool, from: Vector2}.
static func use(p) -> Dictionary:
	if p == null or not is_instance_valid(p):
		return {"ok": false, "saved": false, "from": Vector2.ZERO}
	var from := Vector2(float(p.get("x")), float(p.get("y")))
	var underground := int(floor(from.y)) >= 1
	# teleport_home паркует бурмобиль, гасит переход и копку — вся «уборка» героя там.
	p.teleport_home()
	if pad_ready():
		p.set("x", pad_x())
		p.set("y", SURFACE_Y)
	var s := state()
	s["uses"] = int(s["uses"]) + 1
	if underground:
		s["ret"] = {"x": from.x, "y": from.y}
	_store(s)
	_fx_at(Vector2(float(p.get("x")), float(p.get("y"))))
	GameState.emit_event(&"teleport_used", {"from": from, "saved": underground})
	SaveSystem.save_game()
	return {"ok": true, "saved": underground, "from": from}


## Плитка часов в лавке, пока есть подарок: «0 $», бант в углу, подарок — в подсказке.
static func mark_free_offer(o: Dictionary) -> void:
	o["state"] = "available"
	o["price"] = 0
	o["free"] = true
	o["corner"] = "gift"
	o["pill"] = {"icon": ShopArt.tex("glyph_gift"), "text": "0", "color": ShopArt.COL_GOOD}
	o["extra"] = text("free_tip")


## Бесплатное применение (подарок обучения): списать подарок и перенести.
static func use_free(p) -> bool:
	if not take_free():
		return false
	use(p)
	return true


# ---------------------------------------------------------------------------
# Возврат вниз
# ---------------------------------------------------------------------------

## Безопасная клетка для возврата: пустая, под ногами твёрдое и не лава. Сама точка —
## если цела; завалило (обвал, землетрясение) — ближайшая безопасная по кольцам вокруг
## (сначала та же строка и ниже: падать на голову лучше, чем вылезать в чужую полость).
## Ничего за радиусом — клетка точки расчищается (как будто её откопали), если копается.
## Возвращает центр героя в клетках или (-1, -1).
static func safe_return_target(w: WorldGen, point: Vector2) -> Vector2:
	if w == null or point.x < 0.0:
		return Vector2(-1, -1)
	var c := Vector2i(int(floor(point.x)), int(floor(point.y)))
	if _safe_cell(w, c):
		return Vector2(c.x + 0.5, c.y + 0.5)
	var radius := int(num("search_radius_cells", 12))
	for r in range(1, radius + 1):
		var best := Vector2i(-1, -1)
		var best_score := 1 << 30
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cc := c + Vector2i(dx, dy)
				if not _safe_cell(w, cc):
					continue
				# Ровно по кольцу: ближе по прямой — лучше; при равенстве — ниже, а не выше.
				var score := (dx * dx + dy * dy) * 4 + (0 if dy >= 0 else 1)
				if score < best_score:
					best_score = score
					best = cc
		if best.x >= 0:
			return Vector2(best.x + 0.5, best.y + 0.5)
	if w.dig_cell(c.x, c.y) and _safe_cell(w, c):
		return Vector2(c.x + 0.5, c.y + 0.5)
	return Vector2(-1, -1)


static func _safe_cell(w: WorldGen, c: Vector2i) -> bool:
	if c.x < 0 or c.x >= WorldGen.WIDTH or c.y < 1:
		return false
	if w.get_tile(c.x, c.y) != TileTypes.Type.EMPTY:
		return false
	var floor_t := w.get_tile(c.x, c.y + 1)
	return floor_t != TileTypes.Type.EMPTY and floor_t != TileTypes.Type.LAVA


## Вернуть героя вниз. false — возврата нет или безопасной клетки не нашлось (возврат
## тогда остаётся — попробовать можно позже).
static func go_down(p, w: WorldGen) -> bool:
	if p == null or not has_return():
		return false
	var target := safe_return_target(w, return_point())
	if target.x < 0.0:
		return false
	_fx_at(Vector2(float(p.get("x")), float(p.get("y"))))
	p.set("x", target.x)
	p.set("y", target.y)
	p.set("vx", 0.0)
	p.set("vy", 0.0)
	p.set("digging", null)
	if p.has_method("release_control"):
		p.release_control()
	clear_return()
	var fog = GameState.fog_ref
	if fog != null and fog.has_method("reveal_around"):
		fog.reveal_around(target.x, target.y, GameState.get_vision_terrain_radius(), GameState.get_vision_resource_radius())
	_fx_at(target)
	GameState.emit_event(&"teleport_returned", {"to": target})
	SaveSystem.save_game()
	return true


static func _fx_at(cell_pos: Vector2) -> void:
	var px := cell_pos * TILE
	Fx.burst("spark", px, 1.2, Color(0.35, 1.0, 0.6))
	Fx.flash(Color(0.45, 1.0, 0.7, 0.28), 0.22)
	Sfx.play("pickup_rare")
	Haptics.tap()


func _on_died() -> void:
	clear_return()


# ---------------------------------------------------------------------------
# Пузырь «Вниз» над героем на площадке
# ---------------------------------------------------------------------------

func _build_button() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "TeleportHotspot"
	_layer.layer = 8   # как «Зайти» и «В бурмобиль»: над миром, под окнами
	add_child(_layer)
	_button = HouseBubble.create({"action": "teleport_down", "label": text("down_title"),
		"icon": "act_teleport_down", "tip": text("down_tip")})
	_button.name = "TeleportDownBtn"
	_button.visible = false
	_button.pressed.connect(func() -> void:
		if not Tip.swallowed():
			press_down())
	_layer.add_child(_button)


func button() -> HouseBubble:
	return _button


## Пузырь «Вниз» мигает белым пару секунд — сразу после переноса уроком.
func pulse_button(seconds: float = 6.0) -> void:
	_pulse_left = seconds


func press_down() -> bool:
	if not _button_allowed():
		return false
	return go_down(player, world)


func _button_allowed() -> bool:
	if player == null or not is_instance_valid(player) or not has_return() or not pad_ready():
		return false
	if not GameState.is_alive or GameState.house_is_indoors or bool(player.get("frozen")):
		return false
	if player.has_method("is_in_rig") and player.is_in_rig():
		return false
	if String(player.get("rig_transition")) != "":
		return false
	return near_pad(float(player.get("x")), float(player.get("y")))


func _process(dt: float) -> void:
	if _button == null:
		return
	var show_it := _button_allowed()
	_button.visible = show_it
	if _pulse_left > 0.0:
		_pulse_left = maxf(0.0, _pulse_left - dt)
	if not show_it:
		return
	var want := "forced" if _pulse_left > 0.0 else "normal"
	if _button.get("_state") != want:
		_button.set_state(want)
	if hud == null or not hud.has_method("get_view_cells"):
		return
	var cells: Vector2i = hud.get_view_cells()
	var cam := CameraRig.for_overlay(player.x, player.y, float(cells.x), float(cells.y), SKY_HEIGHT)
	var head := Vector2(player.x - cam.x, player.y - cam.y - 1.0) * TILE
	# Пузырь левее головы: прямо над ней горит огонёк площадки — пузырь его не закрывает.
	head.x -= HouseBubble.W * 0.5 + 6.0
	_button.position = head - Vector2(_button.custom_minimum_size.x / 2.0, _button.custom_minimum_size.y + 4.0)

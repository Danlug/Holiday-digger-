class_name TechSystem
extends Node
## Ветка «Техника»: связывает бак, жару, лаву и скважину с игрой. Подключается
## одной строкой из main.gd (TechSystem.attach(self)) и сама находит героя, мир и
## HUD у хозяина.
##
## Что делает каждый кадр:
##  * жара — сверх стойкости костюма быстрее тратит бодрость (HP не трогает);
##  * лава — пока герой копает её клетку, жжёт HP/с и подаёт звук, искры, вибро;
##  * станция заправки (перегонка + заправка) и скважина — подходишь, над героем
##    всплывает кнопка-значок;
##  * жар в воздухе — шейдер-дрожание поверх мира (только когда жарко);
##  * скважина — отметка времени для защиты от перемотки часов и окно отчёта при
##    возвращении в приложение.
## Топливо расходует player.gd (клетка прокопана) через FuelTank; здесь — только
## реакция на пустой и пустеющий бак.

const TILE := 32
const SKY_HEIGHT: int = preload("res://scripts/world/world_view.gd").SKY_HEIGHT
const HAZE_SHADER := "res://shaders/heat_haze.gdshader"
const NEAR_STATION := 1.7
const NEAR_WELL := 1.7
## Столько отсутствия в приложении (свернул и вернулся) уже стоит окна отчёта.
const MIN_RETURN_SECONDS := 600.0

static var _instance: TechSystem = null

var player: Node = null
var hud: Control = null
var world: WorldGen = null

var _tech_hud: TechHud = null
var _tech_world: TechWorld = null
var _hot_layer: CanvasLayer = null
var _hot_btn: Button = null
var _hot_target: String = ""
var _haze_layer: CanvasLayer = null
var _haze_rect: ColorRect = null
var _haze_mat: ShaderMaterial = null
var _haze_strength: float = 0.0
var _lava_fx_t: float = 0.0
var _refuse_cd: float = 0.0
var _note_t: float = 0.0
var _warned: Dictionary = {}
var _zone_seen: int = 0


# ---------------------------------------------------------------------------
# Подключение
# ---------------------------------------------------------------------------

static func attach(host: Node) -> TechSystem:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var s := TechSystem.new()
	s.name = "TechSystem"
	host.add_child(s)
	s._setup(host)
	return s


static func instance() -> TechSystem:
	return _instance if _instance != null and is_instance_valid(_instance) else null


## Открыт ли модальный экран техники: HUD в это время не ловит ввод в мир.
static func is_modal_open() -> bool:
	return TechScreen.is_open() or WellReport.is_open()


func _ready() -> void:
	_instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS


func _setup(host: Node) -> void:
	player = host.get("player")
	hud = host.get("hud")
	world = host.get("world")
	var view_root: Node = host.get("view_root")

	TechScreen.attach(host, player)
	WellReport.attach(host)

	var hud_layer := CanvasLayer.new()
	hud_layer.name = "TechHudLayer"
	hud_layer.layer = UiLayers.HUD_WIDGETS   # бак и термометр: над миром, под окнами (и рюкзаком)
	host.add_child(hud_layer)
	_tech_hud = TechHud.new()
	_tech_hud.name = "TechHud"
	hud_layer.add_child(_tech_hud)

	if view_root != null:
		_tech_world = TechWorld.new()
		_tech_world.world = world
		_tech_world.fog = host.get("fog")
		view_root.add_child(_tech_world)

	_build_hotspot(host)
	_build_haze(host)
	_register_menu()

	if player != null:
		player.dig_started.connect(_on_dig_started)
		player.dig_refused_by_lava.connect(_on_lava_refused)
		if player.has_signal("rig_fuel_warning"):
			player.rig_fuel_warning.connect(_on_rig_fuel_warning)
	GameState.game_event.connect(_on_game_event)
	GameState.respawned.connect(func() -> void: _warned.clear())


func _register_menu() -> void:
	MenuRegistry.add("tech", {
		"icon": TechUi.tex("icon_tech"),
		"title": "Техника",
		"body": "Топливо, костюм от жары, скважина",
		"order": 30,
		"visible": func() -> bool:
			return GameState.max_depth_reached >= 100 or IdleWell.is_built(),
		"badge": func() -> int:
			return 1 if IdleWell.is_built() and IdleWell.fill_fraction() >= 1.0 else 0,
		"on_press": func() -> void:
			TechScreen.open(TechScreen.TAB_WELL if IdleWell.is_built() and not FuelTank.uses_fuel(GameState.current_tool)
				else TechScreen.TAB_TANK),
	})


func _build_hotspot(host: Node) -> void:
	_hot_layer = CanvasLayer.new()
	_hot_layer.name = "TechHotspot"
	_hot_layer.layer = 8
	host.add_child(_hot_layer)
	_hot_btn = UiBtn.icon_button(TechUi.tex("icon_tank"), Vector2(36, 32), UiBtn.Kind.ACCENT, 24)
	_hot_btn.visible = false
	_hot_btn.pressed.connect(func() -> void:
		if Tip.swallowed():
			return
		if _hot_target == "station":
			TechScreen.open(TechScreen.TAB_TANK, true)
		elif _hot_target == "well":
			TechScreen.open(TechScreen.TAB_WELL))
	_hot_layer.add_child(_hot_btn)


func _build_haze(host: Node) -> void:
	_haze_layer = CanvasLayer.new()
	_haze_layer.name = "HeatHaze"
	_haze_layer.layer = 1
	host.add_child(_haze_layer)
	# Тот же слой, что у HUD, но раньше него в дереве: дрожит мир, а не интерфейс.
	if hud != null and hud.get_parent() != null:
		host.move_child(_haze_layer, hud.get_parent().get_index())
	_haze_rect = ColorRect.new()
	_haze_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_haze_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_haze_rect.visible = false
	if ResourceLoader.exists(HAZE_SHADER):
		_haze_mat = ShaderMaterial.new()
		_haze_mat.shader = load(HAZE_SHADER)
		_haze_rect.material = _haze_mat
	_haze_layer.add_child(_haze_rect)


# ---------------------------------------------------------------------------
# Кадр
# ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	if player == null or get_tree().paused:
		return
	_refuse_cd = maxf(0.0, _refuse_cd - dt)
	_heat_tick(dt)
	_lava_tick(dt)
	_hotspot_tick()
	_haze_tick(dt)
	_note_t += dt
	if _note_t >= 20.0:
		_note_t = 0.0
		IdleWell.note_time()


func _depth() -> float:
	return float(maxi(GameState.player_depth, 0))


## Жара сверх стойкости костюма: бодрость уходит быстрее (множитель считает Heat).
func _heat_tick(dt: float) -> void:
	if not GameState.is_alive or GameState.house_is_indoors or player.frozen:
		return
	var depth := _depth()
	var mult := Heat.stamina_multiplier(depth)
	if depth >= 1.0:
		_announce_zone(depth)
	if mult <= 1.001 or depth < 1.0:
		return
	var base := Balance.get_bar_depletion_rate_per_second("stamina", GameState.is_digging)
	GameState.set_stamina(GameState.stamina - base * (mult - 1.0) * 100.0 * dt)


func _announce_zone(depth: float) -> void:
	var z := Heat.zone(depth)
	var idx := int(z.get("index", 0))
	if idx <= _zone_seen or idx == 0:
		return
	_zone_seen = idx
	if Heat.stamina_multiplier(depth) <= 1.001:
		return
	Sfx.play("warn_low")
	Haptics.buzz(40)
	if hud != null:
		hud.toast("%s: %d°" % [String(z.get("name_ru", "")), int(Heat.temperature(depth))], 2.4)


## Пока герой копает клетку лавы — жжём и подаём «горячо».
func _lava_tick(dt: float) -> void:
	var d = player.digging
	if d == null or int(d.type) != TileTypes.Type.LAVA:
		_lava_fx_t = 0.0
		return
	var dmg := Heat.burn_digger(dt)
	_lava_fx_t += dt
	if _lava_fx_t >= 0.5:
		_lava_fx_t = 0.0
		var pos := Vector2(float(d.x) * TILE + TILE * 0.5, float(d.y) * TILE + TILE * 0.5)
		Sfx.play("lava_hiss")
		Fx.burst("fire", pos)
		if dmg > 0.0:
			Haptics.buzz(30)
			Fx.flash(Color(1.0, 0.3, 0.1, 0.14), 0.12)


func _on_dig_started(x: int, y: int, tile_type: int) -> void:
	if tile_type != TileTypes.Type.LAVA:
		return
	Sfx.play("lava_hiss")
	Fx.burst("fire", Vector2(float(x) * TILE + TILE * 0.5, float(y) * TILE + TILE * 0.5), 1.5)
	Fx.shake(2.0, 0.15)


## Лава убила бы на месте: объясняем коротко и цифрой, не спамим каждый кадр.
func _on_lava_refused(cost_hp: float) -> void:
	if _refuse_cd > 0.0:
		return
	_refuse_cd = 1.6
	Sfx.play("ui_deny")
	Haptics.buzz(50)
	Fx.shake(3.0, 0.2)
	if hud != null:
		hud.toast("Лава: −%d HP за клетку, а у тебя %d. Нужен костюм." % [int(round(cost_hp)), int(GameState.hp)], 3.2)


func _on_rig_fuel_warning(_message: String) -> void:
	Sfx.play("ui_deny")
	Haptics.buzz(50)


## Топливо: «на исходе» один раз, «пусто» — когда бак опустел.
func _on_game_event(id: StringName, data: Dictionary) -> void:
	if id == &"refueled":
		_warned.erase(String(data.get("tool", "")))
		return
	if id != &"fuel_used":
		return
	var tool_id := String(data.get("tool", ""))
	var left := float(data.get("left", 1.0))
	if left <= 0.0:
		Sfx.play("ui_deny")
		Haptics.buzz(60)
		Fx.shake(2.0, 0.15)
		if hud != null and tool_id == "hand_drill":
			hud.toast("Бак пуст — копаю киркой", 2.6)
		_warned[tool_id] = 2
	elif FuelTank.is_low(tool_id) and not _warned.has(tool_id):
		_warned[tool_id] = 1
		Sfx.play("warn_low")
		if hud != null:
			hud.toast("Топливо на исходе: %d клеток" % FuelTank.cells_left(tool_id), 2.4)


# ---------------------------------------------------------------------------
# Станция заправки и скважина: кнопка-значок над героем
# ---------------------------------------------------------------------------

func _hotspot_tick() -> void:
	if _hot_btn == null:
		return
	var target := ""
	if GameState.is_alive and not GameState.house_is_indoors and GameState.era != "grandpa" \
			and not player.frozen and GameState.player_depth <= 0 and not is_modal_open() \
			and String(player.get("rig_transition")) == "":
		if _tech_world != null and _tech_world.station_visible() \
				and absf(player.x - (WorldGen.FUEL_STATION_X + 1.0)) < NEAR_STATION:
			target = "station"
		elif _tech_world != null and _tech_world.well_visible() \
				and absf(player.x - (WorldGen.WELL_X + 1.0)) < NEAR_WELL:
			target = "well"
	if target != _hot_target:
		_hot_target = target
		if target == "station":
			_hot_btn.icon = TechUi.tex("icon_tank")
			Tip.bind(_hot_btn, "Станция заправки", "Перегнать торф и уголь в топливные блоки, залить бак")
		elif target == "well":
			_hot_btn.icon = TechUi.tex("icon_well")
			Tip.bind(_hot_btn, "Буровая скважина", "Забрать добычу, улучшить")
	_hot_btn.visible = target != ""
	if target == "" or hud == null:
		return
	var view_cells: Vector2i = hud.get_view_cells()
	var cam := CameraRig.for_overlay(player.x, player.y, float(view_cells.x), float(view_cells.y), SKY_HEIGHT)
	var head := Vector2(player.x - cam.x, player.y - cam.y - 1.0) * TILE
	_hot_btn.position = head - Vector2(_hot_btn.custom_minimum_size.x * 0.5, _hot_btn.custom_minimum_size.y + 4.0)


# ---------------------------------------------------------------------------
# Жар в воздухе
# ---------------------------------------------------------------------------

func _haze_tick(dt: float) -> void:
	if _haze_rect == null or _haze_mat == null:
		return
	var target := 0.0
	if GameState.is_alive and not GameState.house_is_indoors and GameState.player_depth >= 1:
		var t := Heat.temperature(_depth())
		target = clampf((t - 60.0) / 180.0, 0.0, 1.0) * (1.0 - 0.5 * Heat.lava_resist())
	_haze_strength = lerpf(_haze_strength, target, minf(1.0, dt * 1.5))
	var on := _haze_strength > 0.02 and not Settings.reduce_motion
	_haze_rect.visible = on
	if on:
		_haze_mat.set_shader_parameter("strength", _haze_strength)


# ---------------------------------------------------------------------------
# Возвращение в приложение
# ---------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		IdleWell.note_time()
		if is_inside_tree():
			SaveSystem.save_game()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		check_return()


## Вернулись в приложение: если скважина копила достаточно долго — забрать и
## показать окно отчёта (то же окно, что при запуске).
func check_return(min_seconds: float = MIN_RETURN_SECONDS) -> Dictionary:
	if not IdleWell.is_built() or WellReport.is_open() or IdleWell.pending_seconds() < min_seconds:
		return {}
	var rep := IdleWell.collect()
	var w := WellReport.instance()
	if not rep.is_empty() and w != null:
		w.show_report(rep)
	return rep

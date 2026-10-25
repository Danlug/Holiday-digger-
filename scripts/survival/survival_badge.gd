class_name SurvivalBadge
extends Control
## Значок-статус на правом конце полоски голода или бодрости (раунд 5, ГДД §7):
## улитка «медленнее», кирка со стрелкой «слабее», звёздочки «шатает», сердце
## с каплей «здоровье тает». На ≤25% полоска уже почти пуста, и правый конец
## дорожки тёмный — значок встаёт на свободное место. Что именно хуже — в Tip
## (долгое нажатие на значок или на саму полоску, см. tip_suffix).
##
## Без сил героя ещё и шатает: над головой раз в STAGGER_FX_SEC всплывают
## те же звёздочки (Fx.float_icon) — видно и в мире, а не только в шапке.

const SIZE := 12.0
const STAGGER_FX_SEC := 1.6

var bar_id := "hunger"
var hud: Node = null

var _status: Dictionary = {}
var _rank := 0          # 0 норма, 1 ≤25%, 2 ≤10%, 3 ноль: рост — «выскочить» заново
var _t := 0.0
var _pop := 0.0
var _fx_left := 0.0
var _box: StyleBoxFlat


## Вешает значок на полоску. hud — чтобы найти героя для звёздочек над головой.
static func attach(bar: Control, id: String, hud_node: Node = null) -> SurvivalBadge:
	if bar == null:
		return null
	var b := SurvivalBadge.new()
	b.name = "SurvivalBadge"
	b.bar_id = id
	b.hud = hud_node
	bar.add_child(b)
	return b


## Хвост подсказки самой полоски: «Голоден — копка −15%…». Пусто, если норма.
static func tip_suffix(bar: Control) -> String:
	if bar == null:
		return ""
	var b := bar.get_node_or_null("SurvivalBadge") as SurvivalBadge
	if b == null or b._status.is_empty():
		return ""
	return "\n%s: %s" % [b._status["title"], b._status["text"]]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(SIZE, SIZE)
	_box = StyleBoxFlat.new()
	_box.bg_color = Color(0.06, 0.045, 0.035, 0.92)
	_box.set_border_width_all(1)
	_box.set_corner_radius_all(3)
	visible = false
	if bar_id == "hunger":
		GameState.hunger_changed.connect(_on_value)
	else:
		GameState.stamina_changed.connect(_on_value)
	GameState.respawned.connect(refresh)
	refresh()


func _value() -> float:
	return GameState.hunger if bar_id == "hunger" else GameState.stamina


func _on_value(_v: float) -> void:
	refresh()


## Пересчитать статус (сигналы полосок зовут сами; тесты — напрямую).
func refresh() -> void:
	var st := SurvivalRules.status(bar_id, _value()) if GameState.is_alive else {}
	var rank := 0
	match String(st.get("tier", "")):
		SurvivalRules.LOW:
			rank = 1
		SurvivalRules.CRITICAL:
			rank = 2
		SurvivalRules.EMPTY:
			rank = 3
	if rank == _rank and st.get("icon", "") == _status.get("icon", ""):
		return
	if rank > _rank and not Settings.reduce_motion:
		_pop = 1.0
	_rank = rank
	_status = st
	visible = rank > 0
	if visible:
		Tip.bind(self, String(st["title"]), String(st["text"]))
	_place()
	set_process(visible)
	queue_redraw()


func status() -> Dictionary:
	return _status


func _place() -> void:
	var p := get_parent() as Control
	if p == null:
		return
	position = Vector2(p.size.x - SIZE - 1.0, (p.size.y - SIZE) * 0.5)


func _process(dt: float) -> void:
	_t += dt
	_pop = maxf(0.0, _pop - dt * 3.0)
	_place()
	queue_redraw()
	if _rank == 3 and bar_id == "stamina":
		_fx_left -= dt
		if _fx_left <= 0.0:
			_fx_left = STAGGER_FX_SEC
			_stagger_fx()


func _stagger_fx() -> void:
	var player: Node = hud.get("player") if hud != null else null
	if player == null or GameState.house_is_indoors or bool(player.get("frozen")):
		return
	Fx.float_icon(Vector2(float(player.get("x")) * 32.0, (float(player.get("y")) - 1.1) * 32.0),
		UiIcons.tex("st_dizzy"))


func _draw() -> void:
	if _status.is_empty():
		return
	var pulse := 0.0
	if _rank >= 2 and not Settings.reduce_motion:
		pulse = 0.5 + 0.5 * sin(_t * 7.0)
	var s := 1.0 + 0.45 * _pop * _pop + 0.08 * pulse
	var c := size * 0.5
	var half := SIZE * 0.5 * s
	var ring := Color8(0xE0, 0xA9, 0x3B) if _rank == 1 else Color8(0xE8, 0x50, 0x4A)
	_box.border_color = ring.lerp(Color.WHITE, 0.35 * pulse)
	draw_style_box(_box, Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0))
	var tex := UiIcons.tex(String(_status.get("icon", "")))
	if tex != null:
		var ih := 5.0 * s
		draw_texture_rect(tex, Rect2(c - Vector2(ih, ih), Vector2(ih, ih) * 2.0), false)

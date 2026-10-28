class_name ArtifactCard
extends Control
## Карточка-вспышка находки: артефакт выпрыгивает из тьмы силуэтом, вспыхивает
## цветом, за ним крутятся лучи, снизу — иконки и числа награды. Длинного
## текста нет вовсе: название и описание смотрят в музее, в подсказке Tip.
## То же для закрытой ветки: сундук, пять золотых «фишек» и числа награды.
##
## Звук ("artifact"/"quest_done"), вибро и искры запускает сама карточка.
## Вспышки в мире (Fx.burst) — забота того, кто знает координаты (ArtifactFinder).
##
## Нажатие по карточке закрывает её сразу; иначе она гаснет сама. Несколько
## находок подряд встают в очередь и показываются по одной.
##
## Сам узел занимает весь вьюпорт, но нажатия не ловит (иначе он перекрыл бы
## кнопки HUD под собой): ловит только невидимая кнопка размером с карточку.

signal finished

const CARD := Vector2(128, 116)
const HOLD := 1.7
const TOP_FRACTION := 0.30

static var _instance: ArtifactCard = null

var _queue: Array = []
var _busy: bool = false
var _entry: Dictionary = {}
var _pop: float = 0.0
var _reveal: float = 0.0
var _alpha: float = 0.0
var _flash: float = 0.0
var _rays: float = 0.0
var _hit: Control
var _tween: Tween = null


## Показать находку артефакта. open_museum — после карточки открыть музей
## (ГДД п.9: на первой находке игроку показывают коллекцию).
static func show_find(artifact_id: String, open_museum: bool = false) -> void:
	if _instance == null or not is_instance_valid(_instance):
		if open_museum:
			ProgressScreen.open("museum")
		return
	_instance._enqueue({"kind": "find", "id": artifact_id, "open_museum": open_museum})


static func show_branch(branch_num: int) -> void:
	if _instance == null or not is_instance_valid(_instance):
		return
	_instance._enqueue({"kind": "branch", "branch": branch_num})


static func instance() -> ArtifactCard:
	return _instance if _instance != null and is_instance_valid(_instance) else null


func _ready() -> void:
	_instance = self
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(_fit)
	_hit = Control.new()
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit.visible = false
	_hit.gui_input.connect(_on_hit_input)
	add_child(_hit)
	visible = false
	_fit()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if _hit != null:
		_hit.size = CARD
		_hit.position = _card_center() - CARD * 0.5


func _card_center() -> Vector2:
	return Vector2(size.x * 0.5, maxf(size.y * TOP_FRACTION, CARD.y * 0.5 + 8.0))


func _enqueue(entry: Dictionary) -> void:
	_queue.append(entry)
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		visible = false
		_hit.visible = false
		finished.emit()
		return
	_busy = true
	_entry = _queue.pop_front()
	_fit()
	visible = true
	_hit.visible = true
	var calm := HeroUi.calm()
	_pop = 1.0 if calm else 0.0
	_reveal = 1.0 if calm else 0.0
	_alpha = 1.0
	_flash = 0.0 if calm else 0.55
	var is_branch: bool = _entry["kind"] == "branch"
	Sfx.play("quest_done" if is_branch else "artifact")
	Haptics.buzz(120 if is_branch else 60)
	HeroUi.burst_particles(self, _card_center(), ProgressUiKit.GOLD if not is_branch else UiTheme.GOLD_LIGHT,
		36 if is_branch else 26, 130.0)

	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	if not calm:
		_tween.set_parallel(true)
		_tween.tween_property(self, "_pop", 1.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "_reveal", 1.0, 0.32).set_delay(0.12)
		_tween.tween_property(self, "_flash", 0.0, 0.3)
	_tween.chain().tween_interval(HOLD)
	_tween.chain().tween_property(self, "_alpha", 0.0, 0.22)
	_tween.chain().tween_callback(_done)
	_tween.set_parallel(false)


func _done() -> void:
	if _entry.get("open_museum", false):
		ProgressScreen.open("museum")
	_entry = {}
	_next()


func _on_hit_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if pressed and _busy:
		if _tween != null:
			_tween.kill()
		_done()


func _process(delta: float) -> void:
	if not visible:
		return
	if not HeroUi.calm():
		_rays += delta * 0.7
	queue_redraw()


func _draw() -> void:
	if _entry.is_empty():
		return
	var center := _card_center()
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.95, 0.75, _flash * _alpha))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35 * _alpha * _pop))

	var is_branch: bool = _entry["kind"] == "branch"
	var accent := ProgressUiKit.GOLD
	draw_set_transform(center, 0.0, Vector2(_pop, _pop))

	# лучи
	var ray_col := Color(accent.r, accent.g, accent.b, 0.30 * _alpha)
	for i in range(12):
		var a := _rays + TAU * float(i) / 12.0
		var a2 := a + TAU / 24.0
		var pts := PackedVector2Array([Vector2.ZERO, Vector2(cos(a), sin(a)) * 92.0, Vector2(cos(a2), sin(a2)) * 92.0])
		draw_colored_polygon(pts, ray_col)

	# карточка
	var card_rect := Rect2(-CARD * 0.5, CARD)
	var sb := HeroUi.box(Color(0.09, 0.075, 0.06, 0.96 * _alpha), Color(accent.r, accent.g, accent.b, _alpha), 8, 2)
	draw_style_box(sb, card_rect)

	var icon_size := 64.0
	var icon_rect := Rect2(Vector2(-icon_size * 0.5, -CARD.y * 0.5 + 8.0), Vector2(icon_size, icon_size))
	var mod := Color(1, 1, 1, _alpha)
	var dark := Color(0.04, 0.035, 0.05, _alpha)
	var tint := dark.lerp(mod, _reveal)
	if is_branch:
		var chest := HeroIcons.get_icon("ui_chest")
		if chest != null:
			draw_texture_rect(chest, icon_rect, false, tint)
		for i in range(5):
			draw_rect(Rect2(Vector2(-27.0 + float(i) * 11.5, icon_rect.position.y - 1.0), Vector2(8, 4)),
				Color(accent.r, accent.g, accent.b, _alpha))
	else:
		var tex := ArtifactArt.texture_for(String(_entry.get("id", "")))
		if tex != null:
			draw_texture_rect(tex, icon_rect, false, tint)

	# награда: иконка + число, без слов
	var row_y := CARD.y * 0.5 - 18.0
	var xp := 0
	var coins := 0
	var dollars := 0
	if is_branch:
		var reward := _branch_reward(int(_entry["branch"]))
		coins = int(Balance.unwrap(reward.get("coins", 0)))
		dollars = int(Balance.unwrap(reward.get("premium_currency", 0)))
	else:
		xp = Balance.get_artifact_find_xp(String(_entry.get("id", "")))
		coins = Balance.get_artifact_find_coins(String(_entry.get("id", "")))
	var items: Array = []
	if xp > 0:
		items.append(["ui_xp", UiFmt.short(xp), Color8(0x5E, 0xA8, 0xF0)])
	if coins > 0:
		items.append(["ui_coin", UiFmt.short(coins), ProgressUiKit.GOLD])
	if dollars > 0:
		items.append(["ui_dollar", str(dollars), HeroUi.OK])
	var font := ThemeDB.fallback_font
	var fs := 10
	var total_w := 0.0
	for it: Array in items:
		total_w += 16.0 + 2.0 + font.get_string_size(String(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0
	var x := -total_w * 0.5
	for it: Array in items:
		var icon := HeroIcons.get_icon(String(it[0]))
		if icon != null:
			draw_texture_rect(icon, Rect2(Vector2(x, row_y), Vector2(16, 16)), false, mod)
		x += 18.0
		var col: Color = it[2]
		col.a = _alpha
		draw_string(font, Vector2(x, row_y + 12.0), String(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += font.get_string_size(String(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _branch_reward(branch_num: int) -> Dictionary:
	for b: Dictionary in Balance.artifacts.get("branches", []):
		if int(b.get("branch", -1)) == branch_num:
			return b.get("completion_reward", {})
	return {}

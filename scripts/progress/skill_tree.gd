class_name SkillTree
extends Control
## Дерево прокачки (ГДД раздел 11): восемь веток — восемь колонок-«стволов»,
## ступени идут вниз, как шахта. Ступени ветки соединены линией; пройденные
## подсвечены цветом ветки, следующая пульсирует золотом, остальные закрыты
## замком. Покупка — два нажатия: первое «взводит» узел (в нём появляется
## галочка и сразу всплывает подсказка с ценой и эффектом), второе по галочке
## тратит очки. Купленная ступень вспыхивает: по линии от предыдущей бежит
## светящаяся точка и на узле разлетаются искры.
##
## ПОЧЕМУ здесь нет ни одной формулы эффектов: уровни, цены и эффекты считают
## balance.gd и game_state.gd (радиус тумана читается каждый кадр, скорость
## копки — в момент удара). Дерево только показывает их и вызывает
## GameState.spend_skill_point — иначе числа на экране и в игре разошлись бы.
##
## Весь текст (название, эффект, цена, требования) — только в подсказке Tip.

signal purchased(branch_id: String, stage: int)

const HEAD := 22.0
const HEAD_Y := 2.0
const FIRST_NODE_Y := 40.0
const PITCH := 27.0
const ARM_SECONDS := 4.0

## Писать сейв после покупки (тесты выключают — они не должны трогать user://).
var save_on_buy: bool = true

var _branches: Array = []
var _cols: Array = []          # {id, head, nodes, stages}
var _armed: SkillNode = null
var _arm_token: int = 0
var _time: float = 0.0
var _flash_line: Dictionary = {}   # {x, y0, y1, t, color}
var _sparks: Array = []            # {pos, vel, life, color}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_branches = Balance.upgrades.get("branches", [])
	_build()
	resized.connect(_layout)
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	# Движок включает _process при READY, даже если скрыт с самого начала: сигнал видимости до первого показа молчит.
	set_process(is_visible_in_tree())
	GameState.skill_points_changed.connect(_on_points_changed)
	refresh()


func _on_points_changed(_points: int) -> void:
	refresh()


# ---------------------------------------------------------------------------
# Построение
# ---------------------------------------------------------------------------

func _build() -> void:
	var tallest := 0
	for b: Dictionary in _branches:
		var id := String(b.get("id", ""))
		var stages := int(b.get("stages", 0))
		tallest = maxi(tallest, stages)
		var color := HeroUi.branch_color(id)

		var head := Button.new()
		head.custom_minimum_size = Vector2(HEAD, HEAD)
		head.size = Vector2(HEAD, HEAD)
		head.focus_mode = Control.FOCUS_NONE
		head.flat = true
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			head.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		head.draw.connect(_draw_head.bind(head))
		head.set_meta("branch_id", id)
		head.set_meta("color", color)
		head.pressed.connect(func() -> void:
			if Tip.swallowed():
				return
			HeroUi.tap()
			Tip.show_now(head))
		add_child(head)

		var nodes: Array = []
		for s in range(1, stages + 1):
			var node := SkillNode.new()
			node.setup(id, s, color)
			node.pressed.connect(_on_node_pressed.bind(node))
			add_child(node)
			nodes.append(node)
		_cols.append({"id": id, "head": head, "nodes": nodes, "stages": stages, "color": color})
	custom_minimum_size = Vector2(0, FIRST_NODE_Y + float(tallest) * PITCH + 6.0)
	_layout()


func _col_x(i: int) -> float:
	var n := maxi(_cols.size(), 1)
	return size.x / float(n) * (float(i) + 0.5)


func _node_center_y(k: int) -> float:
	return FIRST_NODE_Y + SkillNode.SIZE * 0.5 + float(k) * PITCH


func _layout() -> void:
	for i in range(_cols.size()):
		var col: Dictionary = _cols[i]
		var cx := _col_x(i)
		var head: Control = col["head"]
		head.position = Vector2(cx - HEAD * 0.5, HEAD_Y)
		var nodes: Array = col["nodes"]
		for k in range(nodes.size()):
			var node: Control = nodes[k]
			node.position = Vector2(cx - SkillNode.SIZE * 0.5, FIRST_NODE_Y + float(k) * PITCH)
	queue_redraw()


# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

## Пересчитывает состояния узлов и подсказки. Узлы не пересоздаются: иначе
## сбились бы анимации и привязки Tip.
func refresh() -> void:
	var points: int = GameState.skill_points_available
	for col: Dictionary in _cols:
		var id: String = col["id"]
		var stage := GameState.get_skill_stage(id)
		var nodes: Array = col["nodes"]
		for k in range(nodes.size()):
			var node: SkillNode = nodes[k]
			var number := k + 1
			var cost := Balance.get_upgrade_stage_cost(id, number)
			if number <= stage:
				node.set_state(SkillNode.State.DONE, cost)
			elif number == stage + 1:
				node.set_state(SkillNode.State.NEXT_READY if cost >= 0 and points >= cost
					else SkillNode.State.NEXT_POOR, cost)
			else:
				node.set_state(SkillNode.State.LOCKED, cost)
			if node == _armed and node.state != SkillNode.State.NEXT_READY:
				_disarm()
			_bind_node_tip(node, id, number, stage, cost, points)
		_bind_head_tip(col, stage)
		(col["head"] as Control).queue_redraw()
	queue_redraw()


func _bind_node_tip(node: SkillNode, id: String, number: int, stage: int, cost: int, points: int) -> void:
	var branch := Balance.get_upgrade_branch(id)
	var title := "%s — ступень %d" % [String(branch.get("name_ru", id)), number]
	var body := effect_text(branch, number)
	var extra := ""
	if number <= stage:
		extra = "Куплено"
	elif number == stage + 1:
		if cost < 0:
			extra = ""
		elif points >= cost:
			body = effect_text(branch, stage) + "  ->  " + body
			extra = "Цена: %d оч. Нажми ещё раз по галочке" % cost if node.armed else "Цена: %d оч." % cost
		else:
			body = effect_text(branch, stage) + "  ->  " + body
			extra = "Цена: %d оч. Не хватает %d" % [cost, cost - points]
	else:
		extra = "Сначала открой ступень %d" % (stage + 1)
	Tip.set_text(node, title, body, extra)


func _bind_head_tip(col: Dictionary, stage: int) -> void:
	var id: String = col["id"]
	var branch := Balance.get_upgrade_branch(id)
	var stages: int = col["stages"]
	var spent := Balance.get_upgrade_total_cost(id, stage)
	var extra := "Ступень %d из %d" % [stage, stages]
	if stage >= stages:
		extra += " — максимум"
	elif spent > 0:
		extra += ", вложено %d оч." % spent
	Tip.set_text(col["head"], String(branch.get("name_ru", id)), "Сейчас: " + effect_text(branch, stage), extra)


# ---------------------------------------------------------------------------
# Нажатия и покупка
# ---------------------------------------------------------------------------

func _on_node_pressed(node: SkillNode) -> void:
	if Tip.swallowed():
		return
	match node.state:
		SkillNode.State.DONE:
			HeroUi.tap()
			Tip.show_now(node)
		SkillNode.State.NEXT_READY:
			if _armed == node:
				_buy(node)
			else:
				_arm(node)
		_:
			_deny(node)


func _deny(node: SkillNode) -> void:
	Sfx.play("ui_deny")
	Haptics.tap()
	HeroUi.shake(node)
	Tip.show_now(node)


func _arm(node: SkillNode) -> void:
	Tip.hide_all()
	if _armed != null and is_instance_valid(_armed):
		_armed.set_armed(false)
		_rebind_armed_tip(_armed)
	_armed = node
	node.set_armed(true)
	Sfx.play("ui_tap", 1.2)
	Haptics.tap()
	HeroUi.bounce(node, 1.15)
	_rebind_armed_tip(node)
	Tip.show_now(node)
	# Взведённый узел сам гаснет: забытое подтверждение не должно висеть вечно.
	_arm_token += 1
	var token := _arm_token
	get_tree().create_timer(ARM_SECONDS).timeout.connect(func() -> void:
		if token == _arm_token and _armed == node:
			_disarm())


func _rebind_armed_tip(node: SkillNode) -> void:
	var stage := GameState.get_skill_stage(node.branch_id)
	_bind_node_tip(node, node.branch_id, node.stage, stage, node.cost, GameState.skill_points_available)


func _disarm() -> void:
	if _armed != null and is_instance_valid(_armed):
		_armed.set_armed(false)
		_rebind_armed_tip(_armed)
	_armed = null
	_arm_token += 1


func _buy(node: SkillNode) -> void:
	var id := node.branch_id
	if not try_buy(id, save_on_buy):
		_deny(node)
		return
	_disarm()
	Tip.hide_all()
	var new_stage := GameState.get_skill_stage(id)
	refresh()
	_start_flash(id, new_stage)
	Sfx.play("skill_buy")
	Haptics.buzz(40)
	purchased.emit(id, new_stage)


## Покупка ступени без интерфейса — её же вызывают экран и тесты. Возвращает
## false, если очков не хватает или ветка уже на максимуме.
static func try_buy(branch_id: String, save: bool = true) -> bool:
	var before := GameState.get_skill_stage(branch_id)
	if not GameState.spend_skill_point(branch_id):
		return false
	# Поднятый потолок HP бесполезен, пока полоска не подросла: игрок отдал
	# очко и не увидел ничего. Доливаем ровно прибавку ступени.
	if branch_id == "hp":
		var per_stage := float(Balance.unwrap(
			Balance.get_upgrade_branch("hp").get("effect", {}).get("per_stage", 20)))
		GameState.heal(per_stage * float(GameState.get_skill_stage(branch_id) - before))
	if save:
		SaveSystem.save_game()
	return true


## Человеческое описание эффекта ветки на заданной ступени. Разбор идёт по
## полю effect.type из data/upgrades.json, а не по id ветки: новая ветка с
## уже известным типом эффекта опишется сама, без правки этого файла.
static func effect_text(branch: Dictionary, stage: int) -> String:
	var effect: Dictionary = branch.get("effect", {})
	var type := String(effect.get("type", ""))
	match type:
		"radius_add_cells":
			var base := int(Balance.unwrap(effect.get("base", 0)))
			var per := int(Balance.unwrap(effect.get("per_stage", 1)))
			return "обзор %d кл." % (base + per * stage)
		"multiplicative_time_reduction":
			return "%.2f сек/клетка" % Balance.get_dig_time_seconds(stage)
		"flat_add":
			return "%d HP" % Balance.get_max_hp(stage)
		"flat_add_kg":
			return "%.0f кг" % Balance.get_max_carry_kg(stage)
		"percent_of_base_duration":
			var per_stamina := int(Balance.unwrap(effect.get("percent_per_stage", 15)))
			return "+%d%% времени до истощения" % (per_stamina * stage)
		"percent_consumption_reduction":
			var per_hunger := int(Balance.unwrap(effect.get("percent_per_stage", 8)))
			return "-%d%% расхода голода" % (per_hunger * stage)
		"table":
			return "находка x%d при удаче" % Balance.get_lucky_find_multiplier(stage)
		"table_dual":
			var chance := Balance.get_luck_chance_percent(stage)
			return "земля %.0f%%, ресурс %.0f%%" % [chance["earth"], chance["resource"]]
		_:
			return String(branch.get("notes", ""))


# ---------------------------------------------------------------------------
# Анимация: «вспышка по линии», пульс, искры
# ---------------------------------------------------------------------------

func _start_flash(branch_id: String, stage: int) -> void:
	if HeroUi.calm():
		return
	for i in range(_cols.size()):
		var col: Dictionary = _cols[i]
		if col["id"] != branch_id:
			continue
		var y1 := _node_center_y(stage - 1)
		var y0 := _node_center_y(stage - 2) if stage > 1 else HEAD_Y + HEAD
		_flash_line = {"x": _col_x(i), "y0": y0, "y1": y1, "t": 0.0, "color": col["color"],
			"node": (col["nodes"] as Array)[stage - 1]}
		return


func _process(delta: float) -> void:
	_time += delta
	var p := 0.5 if HeroUi.calm() else 0.5 + 0.5 * sin(_time * 4.0)
	for col: Dictionary in _cols:
		for node: SkillNode in col["nodes"]:
			if node.state == SkillNode.State.NEXT_READY:
				node.pulse = p
				node.queue_redraw()
	if not _flash_line.is_empty():
		_flash_line["t"] = float(_flash_line["t"]) + delta / 0.26
		if float(_flash_line["t"]) >= 1.0:
			var node: SkillNode = _flash_line["node"]
			_burst(node.position + node.size * 0.5, _flash_line["color"])
			node.play_flash()
			_flash_line = {}
	for s: Dictionary in _sparks:
		s["life"] = float(s["life"]) - delta
		s["vel"] = (s["vel"] as Vector2) + Vector2(0, 160.0) * delta
		s["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * delta
	_sparks = _sparks.filter(func(s: Dictionary) -> bool: return float(s["life"]) > 0.0)
	queue_redraw()


func _burst(at: Vector2, color: Color) -> void:
	for i in range(12):
		var a := TAU * float(i) / 12.0 + randf() * 0.4
		var sp := randf_range(30.0, 70.0)
		_sparks.append({"pos": at, "vel": Vector2(cos(a), sin(a) - 0.4) * sp,
			"life": randf_range(0.35, 0.6), "color": color.lightened(0.3) if i % 2 == 0 else ProgressUiKit.GOLD})


func _draw() -> void:
	for i in range(_cols.size()):
		var col: Dictionary = _cols[i]
		var cx := _col_x(i)
		var color: Color = col["color"]
		var stage := GameState.get_skill_stage(col["id"])
		var stages: int = col["stages"]
		var y_prev := FIRST_NODE_Y - 4.0
		for k in range(stages):
			var y := _node_center_y(k)
			var y_from := y_prev if k == 0 else _node_center_y(k - 1) + SkillNode.SIZE * 0.5
			var y_to := y - SkillNode.SIZE * 0.5
			var line_color := Color(0.16, 0.13, 0.1)
			var width := 3.0
			if k + 1 <= stage:
				line_color = color
			elif k == stage:
				var ready: bool = (col["nodes"][k] as SkillNode).state == SkillNode.State.NEXT_READY
				if ready:
					var p := 0.5 if HeroUi.calm() else 0.5 + 0.5 * sin(_time * 4.0)
					line_color = ProgressUiKit.GOLD.darkened(0.55 - 0.3 * p)
			draw_line(Vector2(cx, y_from), Vector2(cx, y_to), line_color, width)
			y_prev = y
		# счётчик «ступень/всего» под значком ветки — число, не текст
		var font := ThemeDB.fallback_font
		var txt := "%d/%d" % [stage, stages]
		var done := stage >= stages
		draw_string(font, Vector2(cx - 14.0, HEAD_Y + HEAD + 9.0), txt, HORIZONTAL_ALIGNMENT_CENTER, 28.0, 8,
			ProgressUiKit.GOLD if done else ProgressUiKit.MUTED)

	if not _flash_line.is_empty():
		var t := clampf(float(_flash_line["t"]), 0.0, 1.0)
		var x: float = _flash_line["x"]
		var y0: float = _flash_line["y0"]
		var y1: float = _flash_line["y1"]
		var y := lerpf(y0, y1, t)
		var c: Color = _flash_line["color"]
		draw_line(Vector2(x, y0), Vector2(x, y), c.lightened(0.5), 3.0)
		draw_circle(Vector2(x, y), 4.0, Color(1, 1, 1, 0.9))
		draw_circle(Vector2(x, y), 7.0, Color(c.r, c.g, c.b, 0.35))
	for s: Dictionary in _sparks:
		var life := clampf(float(s["life"]) / 0.5, 0.0, 1.0)
		var sc: Color = s["color"]
		sc.a = life
		draw_rect(Rect2((s["pos"] as Vector2) - Vector2(1, 1), Vector2(2, 2)), sc)


func _draw_head(head: Button) -> void:
	var id: String = head.get_meta("branch_id")
	var color: Color = head.get_meta("color")
	var stage := GameState.get_skill_stage(id)
	var stages := 0
	for col: Dictionary in _cols:
		if col["id"] == id:
			stages = col["stages"]
	var maxed := stages > 0 and stage >= stages
	var sb := HeroUi.box(color.darkened(0.65), ProgressUiKit.GOLD if maxed else color, 5, 2 if maxed else 1)
	head.draw_style_box(sb, Rect2(Vector2.ZERO, head.size))
	var icon := HeroIcons.skill_icon(id)
	if icon != null:
		head.draw_texture_rect(icon, Rect2((head.size - Vector2(16, 16)) * 0.5, Vector2(16, 16)), false)
	if maxed:
		head.draw_texture_rect(HeroIcons.get_icon("ui_star"), Rect2(Vector2(head.size.x - 9, -4), Vector2(12, 12)), false)

class_name SkillNode
extends Button
## Один узел дерева прокачки: ступень ветки. Рисует себя сам, текста нет —
## только иконка ветки, число-цена или замок; название, эффект и требования
## живут в подсказке Tip (её выставляет SkillTree).
##
## Состояния:
##   DONE        — куплена: заливка цветом ветки, иконка ветки;
##   NEXT_READY  — следующая и очков хватает: золотая пульсирующая рамка и цена;
##   NEXT_POOR   — следующая, но очков не хватает: тусклая рамка, цена красным;
##   LOCKED      — дальше следующей: замок;
##   BLOCKED     — следующая, но не открыта ветка-предок (requires): замок и
##                 в углу значок ветки, которую надо качнуть (need_branch).
## В «взведённом» состоянии (armed) вместо цены — галочка: второе нажатие по ней
## подтверждает покупку.

enum State { DONE, NEXT_READY, NEXT_POOR, LOCKED, BLOCKED }

const SIZE := 22.0

var branch_id: String = ""
var stage: int = 1          # номер ступени, 1..N
var cost: int = 0
var state: State = State.LOCKED
var armed: bool = false
var pulse: float = 0.0      # 0..1, пишет дерево
var flash: float = 0.0      # вспышка после покупки, твин спадает до нуля
var branch_color: Color = Color.WHITE
var need_branch: String = ""  # для BLOCKED: какую ветку качнуть сначала

var _sb := StyleBoxFlat.new()


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	pivot_offset = Vector2(SIZE, SIZE) * 0.5
	focus_mode = Control.FOCUS_NONE
	flat = true
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_sb.set_corner_radius_all(ProgressUiKit.R_TILE)
	_sb.set_border_width_all(1)
	button_down.connect(func() -> void: _squash(0.9))
	button_up.connect(func() -> void: _squash(1.0))


func _squash(target: float) -> void:
	UiAnim.press(self, target < 1.0, target)


## Сторона узла задаёт дерево по ширине колонки (веток может стать больше).
func set_side(side: float) -> void:
	custom_minimum_size = Vector2(side, side)
	size = Vector2(side, side)
	pivot_offset = size * 0.5
	queue_redraw()


func setup(branch_id_: String, stage_: int, color: Color) -> void:
	branch_id = branch_id_
	stage = stage_
	branch_color = color


func set_state(new_state: State, cost_: int) -> void:
	state = new_state
	cost = cost_
	queue_redraw()


func set_armed(value: bool) -> void:
	if armed == value:
		return
	armed = value
	queue_redraw()


func play_flash() -> void:
	if HeroUi.calm():
		return
	flash = 1.0
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.3, 1.3), 0.08).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tw2 := create_tween()
	tw2.tween_method(func(v: float) -> void:
		flash = v
		queue_redraw(), 1.0, 0.0, 0.5)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var icon: Texture2D = null
	var number := ""
	var number_color := ProgressUiKit.GOLD
	var icon_mod := Color.WHITE

	match state:
		State.DONE:
			_sb.bg_color = branch_color.darkened(0.62)
			_sb.border_color = branch_color
			icon = HeroIcons.skill_icon(branch_id)
		State.NEXT_READY:
			var p := pulse
			_sb.bg_color = Color(0.2, 0.15, 0.07).lerp(Color(0.3, 0.22, 0.08), p)
			_sb.border_color = ProgressUiKit.GOLD.darkened(0.35 - 0.35 * p)
			if armed:
				_sb.bg_color = Color(0.1, 0.28, 0.14)
				_sb.border_color = HeroUi.OK
				icon = HeroIcons.get_icon("ui_check")
			else:
				number = str(cost)
		State.NEXT_POOR:
			_sb.bg_color = Color(0.1, 0.08, 0.065)
			_sb.border_color = ProgressUiKit.BORDER.lightened(0.15)
			number = str(cost)
			number_color = HeroUi.POOR
		State.BLOCKED:
			_sb.bg_color = Color(0.08, 0.06, 0.05)
			_sb.border_color = HeroUi.branch_color(need_branch).darkened(0.25)
			icon = HeroIcons.get_icon("ui_lock")
			icon_mod = Color(1, 1, 1, 0.8)
		_:
			_sb.bg_color = Color(0.06, 0.05, 0.04)
			_sb.border_color = ProgressUiKit.BORDER.darkened(0.2)
			icon = HeroIcons.get_icon("ui_lock")
			icon_mod = Color(1, 1, 1, 0.42)

	if state == State.NEXT_READY and not armed:
		# мягкое свечение вокруг доступной ступени
		var glow := Color(ProgressUiKit.GOLD.r, ProgressUiKit.GOLD.g, ProgressUiKit.GOLD.b, 0.10 + 0.18 * pulse)
		draw_rect(rect.grow(2.0), glow, false, 2.0)
	draw_style_box(_sb, rect)

	if icon != null:
		var isz := Vector2(16, 16)
		draw_texture_rect(icon, Rect2((size - isz) * 0.5, isz), false, icon_mod)
	if state == State.BLOCKED:
		# значок ветки-предка в углу: «сначала вот это»
		var need := HeroIcons.skill_icon(need_branch)
		if need != null:
			var b := Rect2(size - Vector2(9, 9), Vector2(11, 11))
			draw_rect(b.grow(0.5), Color(0.06, 0.05, 0.04))
			draw_texture_rect(need, b, false)
	if number != "":
		var font := ThemeDB.fallback_font
		var fs := UiTheme.FS_BODY
		var asc := font.get_ascent(fs)
		var h := font.get_height(fs)
		draw_string(font, Vector2(0, (size.y - h) * 0.5 + asc), number,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, number_color)
	if flash > 0.0:
		draw_rect(rect, Color(1, 1, 1, 0.75 * flash))

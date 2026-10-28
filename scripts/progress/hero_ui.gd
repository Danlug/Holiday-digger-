class_name HeroUi
extends RefCounted
## Мелочи оформления экрана героя: плитка «иконка + число», отклик нажатия,
## сокращение больших чисел. Палитра — из ProgressUiKit (общая для вкладок),
## сам ui_kit.gd не правим: он принадлежит ветке HUD.

const TILE_BG := Color(0.11, 0.09, 0.07, 1.0)
const TILE_BG_HI := Color(0.17, 0.13, 0.08, 1.0)
const ACCENT := Color8(0xE0, 0xA9, 0x3B)
const OK := Color8(0x7D, 0xE0, 0x8A)
const POOR := Color8(0xB8, 0x5A, 0x52)
const TILE_H := 34.0     # высота плитки «иконка + число»: на узком экране цифры читаются крупнее
const TILE_FONT := 11

# Цвет каждой ветки прокачки: по нему читается дерево с первого взгляда.
const BRANCH_COLORS := {
	"vision": Color8(0x3F, 0xB7, 0xC8),
	"dig_speed": Color8(0xE8, 0xE0, 0xD0),
	"hp": Color8(0xD2, 0x3A, 0x4A),
	"stamina": Color8(0xFF, 0xE0, 0x66),
	"hunger": Color8(0xE0, 0x9A, 0x5A),
	"strength": Color8(0x8A, 0xA0, 0xD0),
	"luck_multiplier": Color8(0xC0, 0x8A, 0xFF),
	"luck_chance": Color8(0x58, 0xC2, 0x6A),
	"greed": Color8(0xF0, 0x7A, 0x1E),   # ветка «Жадность»: цвет шкалы азарта (scripts/mechanics/streak_meter.gd)
}


static func branch_color(branch_id: String) -> Color:
	return BRANCH_COLORS.get(branch_id, ACCENT)


static func box(bg: Color, border: Color, radius: int = ProgressUiKit.R_TILE, border_w: int = 1) -> StyleBoxFlat:
	return ProgressUiKit.box(bg, border, ProgressUiKit.snap_radius(radius), border_w)


## «Меньше движения» (Settings.reduce_motion): пульс, покачивание, искры и вспышки
## выключаются, остаётся статичная картинка.
static func calm() -> bool:
	return Settings.reduce_motion


## Звук и вибро обычного нажатия — одной строкой во всех экранах.
static func tap(sound: String = "ui_tap") -> void:
	Sfx.play(sound)
	Haptics.tap()


## Короткий «пружинистый» отклик: сжатие и возврат с перелётом.
static func bounce(c: Control, amount: float = 1.12) -> void:
	UiAnim.pulse(c, amount - 1.0, 0.23)


## Отказ: быстрое покачивание по горизонтали.
static func shake(c: Control, px: float = 2.5) -> void:
	if c == null or not c.is_inside_tree() or calm():
		return
	var x0 := c.position.x
	var tw := c.create_tween()
	for dx in [px, -px, px * 0.6, -px * 0.6, 0.0]:
		tw.tween_property(c, "position:x", x0 + dx, 0.04)


## Плитка «иконка + число». Подпись плитки — только в подсказке Tip.
## Возвращает панель; число доступно через метаданные "value_label".
static func make_tile(icon_name: String, value: String, color: Color = ProgressUiKit.GOLD,
		min_size: Vector2 = Vector2(0, TILE_H), fraction: float = -1.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", box(TILE_BG, ProgressUiKit.BORDER))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(col)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	row.add_child(HeroIcons.make(icon_name, 16.0))
	var l := ProgressUiKit.make_label(value, TILE_FONT, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	if fraction >= 0.0:
		col.add_child(make_mini_bar(fraction, color))
	p.set_meta("value_label", l)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


## Тонкая полоска прогресса под числом (процент минералов и артефактов).
static func make_mini_bar(fraction: float, color: Color, height: float = 3.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, height)
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.value = clampf(fraction, 0.0, 1.0)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("background", box(Color(0.04, 0.035, 0.03), ProgressUiKit.BORDER, 1, 0))
	b.add_theme_stylebox_override("fill", box(color, color, 1, 0))
	return b


static func tile_value(tile: Control) -> Label:
	return tile.get_meta("value_label") as Label


## Разовая вспышка искр в точке pos внутри parent (локальные координаты).
## Узел сам исчезает по окончании — вызывающему ничего чистить не надо.
static func burst_particles(parent: Node, pos: Vector2, color: Color, amount: int = 24, speed: float = 90.0) -> void:
	if parent == null or not parent.is_inside_tree() or calm():
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 140)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = color
	p.z_index = 20
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	p.emitting = true

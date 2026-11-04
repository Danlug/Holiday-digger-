class_name ArtifactSlot
extends Button
## Одна ячейка витрины музея. Найденный артефакт — яркая иконка с мягким
## сиянием, лёгким покачиванием и редкой искрой; ненайденный — чёрный силуэт
## той же иконки с «?». Пятые предметы веток (части ультимативного сета) в
## золотой рамке со звёздочкой.
##
## Текста в ячейке нет: название, описание и глубина находки — в подсказке Tip
## (для ненайденного — только намёк и полоса глубин). Тап по ячейке тоже
## показывает подсказку: в музее нечего «нажимать», поэтому экран на палец
## отвечает ровно тем, что хочет узнать игрок.

const SIZE := 38.0
const ICON := 32.0

## Цвет сияния по ветке: тот же характер, что у палитры ветки в иконках.
const TINTS := {
	1: Color8(0xE8, 0xB3, 0x2E),
	2: Color8(0xA8, 0x6C, 0xF0),
	3: Color8(0xE8, 0x55, 0x2A),
	4: Color8(0x6F, 0xF0, 0xE0),
	5: Color8(0x7A, 0xA2, 0xFF),
}

var artifact: Dictionary = {}
var artifact_id: String = ""
var branch_num: int = 1
var found: bool = false
var is_set_piece: bool = false

var _t: float = 0.0
var _acc: float = 0.0
var _seed: float = 0.0
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
	button_down.connect(func() -> void: UiAnim.press(self, true))
	button_up.connect(func() -> void: UiAnim.press(self, false))
	pressed.connect(_on_pressed)
	visibility_changed.connect(_sync_process)


func _ready() -> void:
	_sync_process()   # движок включает _process при входе в дерево, даже если плитка скрыта и ничего не нашла


func setup(a: Dictionary) -> void:
	artifact = a
	artifact_id = String(a.get("id", ""))
	branch_num = int(a.get("branch", 1))
	is_set_piece = bool(a.get("is_ultimate_set_piece", false))
	_seed = float(abs(artifact_id.hash()) % 1000) / 100.0
	_t = _seed
	refresh()


## Перечитывает состояние (найден или нет) и обновляет подсказку.
func refresh() -> void:
	found = GameState.collected_artifacts.has(artifact_id)
	_bind_tip()
	_sync_process()
	queue_redraw()


func _sync_process() -> void:
	set_process(found and is_visible_in_tree())


func _bind_tip() -> void:
	var range_cells := ArtifactSpawn.depth_range(artifact)
	var band := "%d" % range_cells.x if range_cells.x == range_cells.y \
		else "%d–%d" % [range_cells.x, range_cells.y]
	if found:
		var depth := HeroData.find_depth(artifact_id)
		var where := "Найден на глубине %d" % depth if depth >= 0 else "Лежал на глубине %s" % band
		var extra := "%s\n+%d опыта, +%d монет" % [where,
			Balance.get_artifact_find_xp(artifact_id), Balance.get_artifact_find_coins(artifact_id)]
		if is_set_piece:
			extra += "\nЧасть сета: %s" % ArtifactText.set_piece_name(String(artifact.get("equip_slot", "")))
		Tip.set_text(self, ArtifactText.name_of(artifact), ArtifactText.desc_of(artifact), extra)
	else:
		Tip.set_text(self, "???", ArtifactText.hint_of(artifact), "Искать на глубине %s" % band)


func _on_pressed() -> void:
	if Tip.swallowed():
		return
	HeroUi.tap()
	HeroUi.bounce(self, 1.1)
	Tip.show_now(self)


func _process(delta: float) -> void:
	_t += delta
	_acc += delta
	if _acc >= 1.0 / 30.0:
		_acc = 0.0
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var tint: Color = TINTS.get(branch_num, ProgressUiKit.GOLD)
	if found:
		_sb.bg_color = Color(0.10, 0.08, 0.065).lerp(tint.darkened(0.7), 0.5)
		_sb.border_color = ProgressUiKit.GOLD if is_set_piece else tint.darkened(0.2)
		_sb.set_border_width_all(2 if is_set_piece else 1)
	else:
		_sb.bg_color = Color(0.15, 0.13, 0.115)
		_sb.border_color = ProgressUiKit.GOLD.darkened(0.5) if is_set_piece else ProgressUiKit.BORDER
		_sb.set_border_width_all(1)
	draw_style_box(_sb, rect)

	var tex := ArtifactArt.texture_for(artifact_id)
	var origin := ((size - Vector2(ICON, ICON)) * 0.5).floor()
	var c := size * 0.5

	if found:
		# сияние: два мягких круга, дышат вразнобой по ячейкам (seed)
		var calm := HeroUi.calm()
		var pulse := 0.5 if calm else 0.5 + 0.5 * sin(_t * 2.2)
		draw_circle(c, 17.0, Color(tint.r, tint.g, tint.b, 0.07 + 0.07 * pulse))
		draw_circle(c, 12.0, Color(tint.r, tint.g, tint.b, 0.10 + 0.10 * pulse))
		var bob := Vector2(0.0, 0.0 if calm else round(sin(_t * 2.0) * 1.2))
		if tex != null:
			draw_texture_rect(tex, Rect2(origin + bob, Vector2(ICON, ICON)), false)
		else:
			_draw_initials()
		# редкая искра: раз в ~3 секунды на 0.35 с в «своём» углу
		var phase := fmod(_t * 0.33 + _seed, 1.0)
		if phase < 0.11 and not calm:
			var k := phase / 0.11
			var corner := Vector2(8.0 + 22.0 * float(int(_seed * 7.0) % 2), 8.0 + 14.0 * float(int(_seed * 3.0) % 2))
			var a := sin(k * PI)
			var s := 1.0 + 2.0 * a
			var col := Color(1, 1, 0.85, a)
			draw_rect(Rect2(corner - Vector2(0.5, s), Vector2(1, s * 2.0)), col)
			draw_rect(Rect2(corner - Vector2(s, 0.5), Vector2(s * 2.0, 1)), col)
	else:
		if tex != null:
			draw_texture_rect(tex, Rect2(origin, Vector2(ICON, ICON)), false, Color(0.05, 0.045, 0.06, 1.0))
		var font := ThemeDB.fallback_font
		var fs := UiTheme.FS_HEAD_L
		var pos := Vector2(0.0, (size.y - font.get_height(fs)) * 0.5 + font.get_ascent(fs))
		draw_string_outline(font, pos, "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, 3, Color(0.05, 0.04, 0.03))
		draw_string(font, pos, "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(0.82, 0.68, 0.38, 0.95))

	if is_set_piece:
		var star := HeroIcons.get_icon("ui_star")
		if star != null:
			draw_texture_rect(star, Rect2(Vector2(size.x - 10.0, 0.0), Vector2(11, 11)), false,
				Color.WHITE if found else Color(1, 1, 1, 0.45))


func _draw_initials() -> void:
	var font := ThemeDB.fallback_font
	var fs := UiTheme.FS_TITLE
	var text := ArtifactArt.placeholder_initials(ArtifactText.name_of(artifact))
	var pos := Vector2(0.0, (size.y - font.get_height(fs)) * 0.5 + font.get_ascent(fs))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, ProgressUiKit.GOLD)

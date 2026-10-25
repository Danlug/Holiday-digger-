class_name JournalTile
extends Control
## Плитка журнала: значок породы, пять звёзд, полоска до следующей звезды.
## Ненайденная — тёмный силуэт того же значка (форма подсказывает, что искать).
## Рамка — золотая у мастера (пять звёзд), зелёная у новой, ещё не виденной.

const COL_BG := Color8(0x1D, 0x17, 0x12)
const COL_BG_LOCKED := Color8(0x14, 0x10, 0x0D)
const COL_BAR_BG := Color(0, 0, 0, 0.45)
const COL_BAR := Color8(0xE0, 0xA9, 0x3B)

var item: String = ""
## Новое с прошлого открытия журнала (порода впервые или новая звезда): зелёная рамка.
var fresh: bool = false

var _icon: Texture2D
var _star_on: Texture2D
var _star_off: Texture2D
var _sb := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_icon = UiIcons.item_small(item, 24)
	_star_on = Mechanics.tex("star_s_on")
	_star_off = Mechanics.tex("star_s_off")
	_sb.set_corner_radius_all(ProgressUiKit.R_TILE)


func _draw() -> void:
	var n := MechState.mastery_count(item)
	var found := n > 0
	var stars := MasteryLogic.stars_for(item, n)
	var unseen := fresh and found
	_sb.bg_color = COL_BG if found else COL_BG_LOCKED
	_sb.border_color = ProgressUiKit.GOLD if stars >= MasteryLogic.MAX_STARS \
		else (ProgressUiKit.GREEN if unseen else ProgressUiKit.BORDER)
	_sb.set_border_width_all(2 if stars >= MasteryLogic.MAX_STARS or unseen else 1)
	draw_style_box(_sb, Rect2(Vector2.ZERO, size))
	if _icon != null:
		var r := Rect2(Vector2((size.x - 24.0) * 0.5, 4.0), Vector2(24, 24))
		draw_texture_rect(_icon, r, false, Color.WHITE if found else Color(0, 0, 0, 0.75))
	if not found:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0, 42), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, ProgressUiKit.DIM)
		return
	# пять звёзд по 7 пикселей с шагом 7
	var sx := (size.x - 5.0 * 7.0) * 0.5
	for i in 5:
		var t := _star_on if i < stars else _star_off
		if t != null:
			draw_texture_rect(t, Rect2(Vector2(sx + float(i) * 7.0, 31.0), Vector2(8, 8)), false)
	# полоска до следующей звезды
	var nxt := MasteryLogic.next_threshold(item, n)
	var prev := MasteryLogic.prev_threshold(item, n)
	var k := 1.0 if nxt <= 0 else clampf(float(n - prev) / float(maxi(1, nxt - prev)), 0.0, 1.0)
	var bar := Rect2(Vector2(5, size.y - 6.0), Vector2(size.x - 10.0, 2))
	draw_rect(bar, COL_BAR_BG)
	draw_rect(Rect2(bar.position, Vector2(floorf(bar.size.x * k), 2)), COL_BAR)

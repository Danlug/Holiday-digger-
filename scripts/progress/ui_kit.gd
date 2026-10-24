class_name ProgressUiKit
extends RefCounted
## Общие детали оформления для трёх экранов (прокачка, музей, рекорды).
##
## ПОЧЕМУ отдельный файл: экраны лежат в разных папках (progress/ и museum/),
## но открываются одной кнопкой и переключаются вкладками — если бы каждый
## красил себя сам, вкладки выглядели бы как три разные игры. Палитра взята
## из hud.gd, чтобы экраны не выбивались из общего интерфейса.

const GOLD := Color8(0xE0, 0xA9, 0x3B)
const MUTED := Color8(0x9D, 0x8B, 0x73)
const DIM := Color8(0x6A, 0x5C, 0x4C)
const BORDER := Color8(0x3E, 0x31, 0x25)
const BG := Color(0.071, 0.055, 0.043, 0.97)
## Фон полноэкранных экранов (герой, техника, хаб, снаряжение): непрозрачный, иначе сквозь
## него светятся полоса HUD, джойстик и тосты мира.
const BG_SOLID := Color(0.071, 0.055, 0.043, 1.0)
const PANEL_BG := Color(0.11, 0.09, 0.07, 1.0)
const GREEN := Color8(0x7F, 0xB8, 0x6B)
const RED := Color8(0xB8, 0x5A, 0x52)
const BLUE := Color8(0x6E, 0x93, 0xA8)


## --- Единый язык оформления (радиусы, рамки, тени) ---
## Раньше у однотипных панелей было девять разных радиусов (2…12) и три цвета
## рамки. Теперь четыре ступени, и всё берёт их отсюда:
##   R_BAR   — полоски, подсказки, мелкие метки;
##   R_TILE  — кнопки, слоты, плитки, ячейки;
##   R_CARD  — карточки, таблетки, тосты, окна-диалоги;
##   R_SHEET — верхние углы шторок.
## Рамка 1 пиксель; 2 — только выделенному (выбрано, редкое, верхняя кромка шторки).
const R_BAR := 3
const R_TILE := 6
const R_CARD := 9
const R_SHEET := 12
const EDGE := Color8(0x52, 0x40, 0x2D)      # рамка приподнятого: кнопки, шторки, окна
const SHEET_BG := Color8(0x1A, 0x14, 0x0F)  # фон шторки и окна
const INSET_BG := Color(0.06, 0.05, 0.04)   # «утопленное»: поля ввода, канавки
const SHADOW := Color(0, 0, 0, 0.5)
## Нижняя полоса вкладок полноэкранных экранов (герой, техника, хаб, снаряжение): одна высота,
## в зоне большого пальца.
const TAB_BAR_H := 30
const CARD_BG := Color8(0x1D, 0x17, 0x12)   # карточка/плитка внутри шторки или окна
const TEXT_HI := Color8(0xF2, 0xD9, 0x9B)   # заголовок, главное число
const TEXT := Color8(0xD8, 0xCF, 0xC0)      # обычный светлый текст


## Притягивает «любой» радиус к ближайшей ступени: так старые вызовы с радиусом
## 4, 5, 8, 10 сами становятся одинаковыми, не правя каждый.
static func snap_radius(r: int) -> int:
	if r <= 0:
		return 0
	if r <= 3:
		return R_BAR
	if r <= 7:
		return R_TILE
	if r <= 10:
		return R_CARD
	return R_SHEET


## Скруглённая плашка по ступеням выше. radius — одна из R_*.
static func box(bg: Color, border: Color = BORDER, radius: int = R_TILE, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb


## Шторка снизу: скруглены только верхние углы, верхняя кромка в два пикселя.
static func sheet_box() -> StyleBoxFlat:
	var sb := box(SHEET_BG, EDGE, 0, 1)
	sb.border_width_top = 2
	sb.corner_radius_top_left = R_SHEET
	sb.corner_radius_top_right = R_SHEET
	return sb


## Окно поверх всего (подтверждение, отчёт, меню): тень отделяет от мира.
static func popup_box(border: Color = EDGE, bg: Color = SHEET_BG, margin: int = 6) -> StyleBoxFlat:
	var sb := box(bg, border, R_CARD, 1)
	sb.set_content_margin_all(margin)
	sb.shadow_color = SHADOW
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	return sb


static func panel_box(bg: Color = PANEL_BG, border: Color = BORDER) -> StyleBoxFlat:
	var sb := box(bg, border, R_TILE, 1)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func make_panel(bg: Color = PANEL_BG, border: Color = BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box(bg, border))
	return p


static func make_label(text: String, size: int = 10, color: Color = MUTED) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func make_wrapped_label(text: String, size: int = 9, color: Color = DIM) -> Label:
	var l := make_label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Текстовая кнопка в общем стиле (приподнятая плитка UiBtn с откликом нажатия).
static func make_button(text: String, font_size: int = 9) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	UiBtn.style(b)
	return b


## Горизонтальная полоска заполнения (опыт, прогресс коллекции).
## Возвращает сам заполнитель — двигать надо его size.x.
static func make_bar(parent: Control, width: float, height: float, fill_color: Color) -> ColorRect:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(width, height)
	var sb := box(Color(0.043, 0.035, 0.027, 0.9), BORDER, R_BAR, 1)
	track.add_theme_stylebox_override("panel", sb)
	parent.add_child(track)

	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = Vector2(1, 1)
	fill.size = Vector2(width - 2, height - 2)
	track.add_child(fill)
	return fill


## Ряд «фишек» ступеней: закрашенные = купленные. Читается быстрее числа
## «3/10» — видно, сколько ещё осталось, не считая в уме.
static func make_pips(parent: Control, total: int, filled: int, pip_w: float = 7.0, pip_h: float = 5.0) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)
	for i in range(total):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(pip_w, pip_h)
		pip.color = GOLD if i < filled else Color(0.18, 0.15, 0.12, 1.0)
		row.add_child(pip)


static func make_separator(parent: Control, height: int = 6) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)

class_name FurnaceBox
extends VBoxContainer
## FurnaceBox — печь бронзы в карточке рецепта, справа от большой плитки
## (BronzeFurnace; слово владельца «бронза делается со скоростью минута штука»).
##
## Три строки значками, без абзацев:
##   [огонёк] N   [×] — сколько в очереди; красный крестик останавливает очередь
##                       (лом за не начатые штуки возвращается, только дома);
##   [часы]   0:42      — отсчёт до следующей штуки и полоска её готовности;
##                       печь пуста — серым «1:00», сколько плавится одна штука;
##   готово N           — сплавлено и ждёт; дома тап забирает сразу (само
##                       забирается при входе в магазин).
## Названия и точные числа — в подсказке по тапу. Обновляется сама, раз в
## четверть секунды: отсчёт идёт, пока карточка открыта.

signal cancelled(refunded: int)
signal collected(count: int)

const ROW_H := 22.0
const BAR_W := 58.0
const COL_DIM := Color(0.62, 0.62, 0.7)
const COL_FILL := Color8(0xF2, 0x8A, 0x2E)
const COL_TRACK := UiTheme.NIGHT_HI

var _anchor: Control = null
var _q_row: HBoxContainer
var _q_lbl: Label
var _q_icon: TextureRect
var _stop: Button
var _t_row: HBoxContainer
var _t_lbl: Label
var _t_icon: TextureRect
var _fill: ColorRect
var _r_row: HBoxContainer
var _r_lbl: Label
var _acc := 0.0
var _sig := ""


## anchor — над чем встаёт подсказка по тапу (плашка карточки).
func setup(anchor: Control = null) -> FurnaceBox:
	name = "FurnaceBox"
	_anchor = anchor
	add_theme_constant_override("separation", 1)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_q_row = _row()
	_q_icon = CraftQtyBox._icon(ShopArt.tex("glyph_flame"), 16)
	_q_row.add_child(_q_icon)
	_q_lbl = _num(13)
	_q_row.add_child(_q_lbl)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(4, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_q_row.add_child(gap)
	_stop = HouseArt.button("red", ShopArt.tex("glyph_cross"), Vector2(24, ROW_H), 12.0)
	_stop.name = "FurnaceStop"
	_stop.pressed.connect(_on_stop)
	_q_row.add_child(_stop)

	_t_row = _row()
	_t_icon = CraftQtyBox._icon(ShopArt.tex("glyph_hourglass"), 16)
	_t_row.add_child(_t_icon)
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 0)
	tcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_t_row.add_child(tcol)
	_t_lbl = _num(12)
	tcol.add_child(_t_lbl)
	var track := ColorRect.new()
	track.color = COL_TRACK
	track.custom_minimum_size = Vector2(BAR_W, 3)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tcol.add_child(track)
	_fill = ColorRect.new()
	_fill.color = COL_FILL
	_fill.size = Vector2(0, 3)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_fill)

	_r_row = _row()
	_r_row.name = "FurnaceReady"
	_r_row.add_child(CraftQtyBox._icon(ShopArt.item_icon(BronzeFurnace.RECIPE), 16))
	_r_lbl = _num(12)
	_r_row.add_child(_r_lbl)
	_r_row.gui_input.connect(_on_ready_input)

	refresh()
	return self


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.25:
		return
	_acc = 0.0
	refresh()


## Пересчитать строки. Подсказки перевязываются только когда что-то поменялось.
func refresh() -> void:
	var now := BronzeFurnace.now_unix()
	var q := BronzeFurnace.queued(now)
	var ready := BronzeFurnace.ready_count(now)
	var next := BronzeFurnace.next_in(now)
	var per := BronzeFurnace.seconds_per_unit()
	var home := ShopService.is_at_workshop()
	var busy := q > 0

	_q_lbl.text = UiFmt.short(q)
	_q_lbl.modulate = Color.WHITE if busy else COL_DIM
	_q_icon.modulate = Color.WHITE if busy else Color(1, 1, 1, 0.45)
	var can_stop := q > 1
	_stop.visible = can_stop
	_stop.disabled = not home

	_t_lbl.text = BronzeFurnace.clock_text(next if busy else per)
	_t_lbl.modulate = Color.WHITE if busy else COL_DIM
	_t_icon.modulate = Color.WHITE if busy else Color(1, 1, 1, 0.45)
	_fill.size.x = floorf(BAR_W * BronzeFurnace.unit_progress(now)) if busy else 0.0

	_r_lbl.text = "готово %s" % UiFmt.short(ready)
	_r_lbl.modulate = ShopArt.COL_GOOD if ready > 0 else COL_DIM

	var sig := "%d|%d|%d|%s" % [q, ready, next, str(home)]
	if sig == _sig:
		return
	_sig = sig
	var whole := BronzeFurnace.all_in(now)
	Tip.bind_tap(_q_row, "Печь: в очереди %s" % UiFmt.full(q),
		"Вся очередь доплавится через %s." % BronzeFurnace.clock_text(whole) if busy
			else "Печь пуста. Загрузи лом ползунком ниже — печь плавит, пока ты копаешь.",
		"Минута на штуку, время идёт и при закрытой игре", _anchor)
	Tip.bind_tap(_t_row, "До следующей штуки" if busy else "Одна штука",
		BronzeFurnace.clock_text(next) if busy else "Плавится %s." % BronzeFurnace.clock_text(per), "", _anchor)
	Tip.bind_tap(_r_row, "Готово: %s" % UiFmt.full(ready),
		"Сплавлено и ждёт в печи." if ready > 0 else "Пока ничего не сплавилось.",
		("Тап — забрать сейчас. Само заберётся при входе в магазин дома." if home
			else "Заберётся само при входе в магазин дома."), _anchor)
	Tip.bind(_stop, "Остановить печь",
		"Штука в работе доплавится, лом за %s не начатых вернётся." % UiFmt.full(maxi(0, q - 1)),
		"" if home else "Только дома, в мастерской")


func _on_stop() -> void:
	if Tip.swallowed():
		return
	var res := BronzeFurnace.cancel()
	if not bool(res["ok"]):
		Sfx.play("ui_deny")
		ShopFx.wiggle(_stop)
		return
	Sfx.play("ui_close")
	Haptics.tap()
	refresh()
	cancelled.emit(int(res["refunded"]))


## Тап по «готово N» дома — забрать сразу; вдали — только подсказка (Tip сам).
func _on_ready_input(ev: InputEvent) -> void:
	var tap: bool = (ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
		or (ev is InputEventScreenTouch and not ev.pressed)
	if not tap or Tip.swallowed() or not ShopService.is_at_workshop():
		return
	if BronzeFurnace.ready_count() <= 0:
		return
	var got := BronzeFurnace.collect()
	refresh()
	if int(got["count"]) > 0:
		collected.emit(int(got["count"]))


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 3)
	r.custom_minimum_size = Vector2(0, ROW_H)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(r)
	return r


func _num(px: int) -> Label:
	var l := ShopArt.label("", px, Color.WHITE, Color(0.05, 0.04, 0.08), 3)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

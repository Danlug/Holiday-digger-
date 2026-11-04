class_name ShopDoorStrip
extends Control
## ShopDoorStrip — полоса «за монеты — у входной двери» внизу витрины, над
## вкладками, в зоне большого пальца (раунд 5, слова владельца: «В огороде
## покупки напоминают, что покупать надо у входной двери»).
##
## Видна, пока на вкладке есть плитки со значком двери (ShopItems: at_door —
## огород или другая комната дома). Слева дверь, короткая строка, справа на
## огороде зелёная кнопка «к двери»: стрелка смотрит туда, где дверь, а тап
## закрывает витрину и ведёт стрелкой над миром (ShopDoorGuide) — не телепорт.
## Тап по плитке с дверью не открывает карточку: полоса вспыхивает, дверь
## подпрыгивает, стрелка «кивает» в сторону двери (remind).

const H := 40.0
const TEXT_GARDEN := "За монеты — у входной двери"
const TEXT_HOUSE := "За монеты — в прихожей, у двери"

var go_btn: Button = null
var _door: TextureRect
var _label: Label
var _arrow: TextureRect
var _dir: int = 1
var _arrow_tw: Tween = null


## go — зелёная кнопка из ShopUI._make_btn (стиль кнопок витрины один).
func setup(go: Button) -> ShopDoorStrip:
	name = "DoorStrip"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back := NinePatchRect.new()
	back.texture = ShopArt.tex("bar")
	for m in ["left", "right", "top", "bottom"]:
		back.set("patch_margin_" + m, 3)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	_door = ShopArt.rect(ShopArt.tex("glyph_door"), Vector2(6, 4), Vector2(32, 32))
	_door.name = "Door"
	add_child(_door)

	_label = ShopArt.label(TEXT_GARDEN, UiTheme.FS_SMALL, ShopArt.COL_GOLD)
	_label.position = Vector2(42, 3)
	_label.size = Vector2(112, H - 6.0)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)

	go_btn = go
	go_btn.name = "GoToDoor"
	go_btn.custom_minimum_size = Vector2(56, 32)
	go_btn.size = Vector2(56, 32)
	go_btn.anchor_left = 1.0
	go_btn.anchor_right = 1.0
	go_btn.offset_left = -62.0
	go_btn.offset_right = -6.0
	go_btn.offset_top = 4.0
	go_btn.offset_bottom = 36.0
	_arrow = ShopArt.rect(ShopArt.tex("glyph_arrow"), Vector2(6, 8), Vector2(16, 16))
	_arrow.name = "Arrow"
	go_btn.add_child(_arrow)
	go_btn.add_child(ShopArt.rect(ShopArt.tex("glyph_door"), Vector2(32, 8), Vector2(16, 16)))
	Tip.bind(go_btn, "К двери", "Стрелка над миром покажет дорогу к входной двери. Зайдёшь — витрина откроется сама.")
	add_child(go_btn)
	Tip.bind(self, "У входной двери", "Еду и снаряжение за монеты продают у входной двери дома.",
		"За доллары — где угодно")
	return self


## place — ShopService.PLACE_GARDEN / PLACE_HOUSE; dir — где дверь от героя:
## -1 левее, +1 правее. Кнопка «к двери» — только на огороде: из комнаты дома
## в прихожую ведут двери интерьера, стрелка над миром там ни к чему.
func configure(place: String, dir: int) -> void:
	var garden := place == ShopService.PLACE_GARDEN
	_label.text = TEXT_GARDEN if garden else TEXT_HOUSE
	go_btn.visible = garden
	_label.size.x = (112.0 if garden else 172.0)
	_dir = -1 if dir < 0 else 1
	_arrow.pivot_offset = _arrow.size * 0.5
	_arrow.flip_h = _dir < 0


## Напоминание: полоса вспыхивает, дверь подпрыгивает, стрелка трижды
## «кивает» туда, где дверь. Без звука — звук даёт тот, кто зовёт.
func remind() -> void:
	if not visible or not is_inside_tree():
		return
	ShopFx.pop(self, 0.05, 0.22)
	ShopFx.flash(self, Rect2(Vector2.ZERO, size), Color(1.0, 0.85, 0.35, 0.35), 0.3)
	_hop(_door, 7.0)
	if go_btn.visible:
		ShopFx.pop(go_btn, 0.14, 0.3)
		_nod_arrow()


func door_center() -> Vector2:
	return _door.get_global_rect().get_center()


func _hop(c: Control, h: float) -> void:
	if ShopFx.reduced():
		return
	var base := Vector2(6, 4)
	c.position = base
	var tw := c.create_tween()
	tw.tween_property(c, "position", base - Vector2(0, h), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "position", base, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _nod_arrow() -> void:
	if ShopFx.reduced():
		return
	if _arrow_tw != null:
		_arrow_tw.kill()
	var base := Vector2(6, 8)
	_arrow.position = base
	_arrow_tw = _arrow.create_tween()
	for i in 3:
		_arrow_tw.tween_property(_arrow, "position", base + Vector2(4.0 * _dir, 0), 0.09).set_trans(Tween.TRANS_QUAD)
		_arrow_tw.tween_property(_arrow, "position", base, 0.11).set_trans(Tween.TRANS_QUAD)

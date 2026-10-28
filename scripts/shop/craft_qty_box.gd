class_name CraftQtyBox
extends VBoxContainer
## CraftQtyBox — «сколько сделать» в карточке рецепта-переработки (плавка
## бронзы и всё, что ShopService.is_batch). Слово владельца, раунд 4: «когда
## плавишь металлолом… тупо делать по одному — надо ползунок».
##
## Вид — как окно «сколько» склада (HouseQtyCard): «−», ползунок, «+» и
## золотая MAX. Под ползунком итог значками: «−N сырья → +M результата», куда
## ляжет результат (рюкзак/склад) и монеты, если рецепт их берёт. Слов нет —
## названия и точные числа в подсказке по тапу на строке итога.
##
## Сам ничего не крафтит: карточка магазина берёт amount() и зовёт
## ShopService.craft(id, amount()).

signal changed(amount: int)

const ROW_H := 28.0

var recipe_id := ""
var _max := 0
var _slider: HSlider
var _minus: Button
var _plus: Button
var _max_btn: Button
var _sum: HBoxContainer
var _tip_anchor: Control = null
## Значки сырья в строке итога: id -> TextureRect. Карточка берёт их
## координаты, чтобы сырьё полетело в верстак ровно отсюда.
var input_icons: Dictionary = {}


## anchor — над чем встаёт подсказка по тапу (плашка карточки).
func setup(rid: String, anchor: Control = null) -> void:
	recipe_id = rid
	_tip_anchor = anchor
	name = "CraftQty"
	add_theme_constant_override("separation", 5)
	_max = ShopService.max_craft(rid)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 4)
	add_child(srow)
	_minus = HouseArt.button("gray", HouseArt.tex("glyph_minus"), Vector2(28, ROW_H), 14.0)
	_minus.pressed.connect(func() -> void: _step(-1))
	srow.add_child(_minus)
	_slider = HSlider.new()
	_slider.name = "CraftQtySlider"
	_slider.min_value = 1
	_slider.max_value = maxi(_max, 1)
	_slider.step = 1
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.custom_minimum_size = Vector2(60, ROW_H)
	HouseQtyCard._style_slider(_slider)
	srow.add_child(_slider)
	_plus = HouseArt.button("gray", ShopArt.tex("glyph_plus"), Vector2(28, ROW_H), 14.0)
	_plus.pressed.connect(func() -> void: _step(1))
	srow.add_child(_plus)
	_max_btn = HouseArt.button("gold", null, Vector2(38, ROW_H))
	var ml := ShopArt.label("MAX", UiTheme.FS_BODY, Color.WHITE, UiTheme.GOLD_INK, 3)
	ml.size = Vector2(38, ROW_H - 2.0)
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_max_btn.add_child(ml)
	_max_btn.pressed.connect(func() -> void:
		if not Tip.swallowed():
			_slider.value = _max)
	srow.add_child(_max_btn)
	Tip.bind(_minus, "Меньше")
	Tip.bind(_plus, "Больше")
	Tip.bind(_max_btn, "Максимум", "Сколько хватит материалов")
	var single := _max <= 1
	_slider.editable = not single
	for b in [_minus, _plus, _max_btn]:
		(b as Button).disabled = single

	var wrap := CenterContainer.new()
	add_child(wrap)
	_sum = HBoxContainer.new()
	_sum.name = "CraftQtySum"
	_sum.add_theme_constant_override("separation", 3)
	_sum.custom_minimum_size.y = 22.0
	_sum.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.add_child(_sum)

	# Открывается на максимуме, как окно склада и перегонка на станции: чаще
	# всего игрок хочет переплавить всё, что принёс.
	_slider.value = maxi(_max, 1)
	_slider.value_changed.connect(_on_slider)
	_rebuild_sum()


func amount() -> int:
	return clampi(int(_slider.value), 1, maxi(_max, 1))


func max_amount() -> int:
	return _max


func set_amount(n: int) -> void:
	_slider.value = clampi(n, 1, maxi(_max, 1))


func _step(d: int) -> void:
	if Tip.swallowed():
		return
	_slider.value = clampi(int(_slider.value) + d, 1, maxi(_max, 1))


func _on_slider(_v: float) -> void:
	Sfx.play("ui_slider")
	_rebuild_sum()
	changed.emit(amount())


## Строка итога: сырьё со знаком минус, стрелка, результат с плюсом, куда он
## ляжет (рюкзак / склад) и монеты. Пересобирается на каждое движение ручки:
## раскладку по рюкзаку и складу считает ShopService.craft_plan.
func _rebuild_sum() -> void:
	for c in _sum.get_children():
		_sum.remove_child(c)
		c.queue_free()
	input_icons.clear()
	var r := ShopCatalog.recipe(recipe_id)
	if r.is_empty():
		return
	var n := amount()
	var plan := ShopService.craft_plan(recipe_id, n)
	var used_parts: Array = []
	for id in (r["inputs"] as Dictionary).keys():
		var total := int(r["inputs"][id]) * n
		var ic := _icon(ShopArt.item_icon(String(id)), 16)
		_sum.add_child(ic)
		input_icons[String(id)] = ic
		_sum.add_child(_num("−" + UiFmt.short(total), 12, Color(0.92, 0.88, 0.8)))
		used_parts.append("%s ×%s" % [ShopCatalog.item_name(String(id)), UiFmt.full(total)])
	_sum.add_child(_icon(ShopArt.tex("glyph_arrow"), 12))
	var out_id := String(r["output"]["id"])
	_sum.add_child(_icon(ShopArt.item_icon(out_id), 16))
	_sum.add_child(_num("+" + UiFmt.short(int(plan["made"])), 12, ShopArt.COL_GOOD))
	# Куда ляжет: значок рюкзака и/или склада с числом — мелко, это справка.
	var where: Array = []
	for dest in [["to_pack", "icon_backpack", "в рюкзак"], ["to_storage", "glyph_storage", "на склад"]]:
		var k := int(plan[dest[0]])
		if k <= 0:
			continue
		var tex: Texture2D = ShopArt.ui(dest[1]) if dest[0] == "to_pack" else ShopArt.tex(dest[1])
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(2, 0)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sum.add_child(gap)
		_sum.add_child(_icon(tex, 12))
		_sum.add_child(_num(UiFmt.short(k), 10, Color(0.72, 0.72, 0.8)))
		where.append("%s %s" % [dest[2], UiFmt.full(k)])
	var coins := int(plan["coins"])
	if coins > 0:
		_sum.add_child(_icon(ShopArt.ui("icon_coin"), 14))
		_sum.add_child(_num("−" + UiFmt.short(coins), 12,
			Color.WHITE if GameState.coins >= coins or GameState.debug_free_shop else ShopArt.COL_BAD))
		used_parts.append("монеты ×%s" % UiFmt.full(coins))
	var lands := "Ляжет: " + ", ".join(where)
	if int(r.get("seconds", 0)) > 0:
		# Печь бронзы (BronzeFurnace): ляжет не сразу, а по штуке в минуту.
		lands = "Плавится %s, потом ляжет: %s" % [BronzeFurnace.clock_text(n * int(r["seconds"])), ", ".join(where)]
	Tip.bind_tap(_sum, "%s ×%s" % [String(r["name_ru"]), UiFmt.full(int(plan["made"]))],
		"Уйдёт: " + ", ".join(used_parts), lands, _tip_anchor)


static func _icon(t: Texture2D, px: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _num(text: String, px: int, col: Color) -> Label:
	var l := ShopArt.label(text, px, col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

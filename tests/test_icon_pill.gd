extends Node
## test_icon_pill — значок таблетки полного восстановления (art/ui/shop/item_full_restore_pill.png,
## рисует tools/gen_shop_icons.py::gen_full_restore_pill). Заказ владельца: «как 💊 — капсула с
## плюсиком». Проверяем форму, а не «попиксельно»: вытянутая по диагонали «/», красная половина
## внизу-слева, белая вверху-справа, белый плюс на красной; не запасной «неизвестный» значок и
## не прежняя картинка. Плюс обязан пережить показ в 16×16 (тосты, мелкие слоты).
##
##   godot --headless --path . res://tests/test_icon_pill.tscn

const ID := "full_restore_pill"
## Хеш пикселей прежнего значка (прямоугольник с зелёным крестиком и искрами).
const OLD_PIXELS_MD5 := "e2973b4d3b72fb4bd2fb94de2450edcc"

var failures := 0
var total := 0


func _ready() -> void:
	print("=== test_icon_pill ===")
	var tex: Texture2D = ShopArt.item_icon(ID)
	check("ShopArt.item_icon(%s) возвращает значок" % ID, tex != null)
	if tex == null:
		_finish()
		return
	check("значок 32×32", tex.get_width() == 32 and tex.get_height() == 32)
	check("это нарисованный значок item_%s, а не запасной" % ID, tex == ShopArt.tex("item_" + ID))

	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var unknown := ShopArt.tex("item_unknown")
	check("есть запасной значок «неизвестно»", unknown != null)
	if unknown != null:
		check("не совпадает с запасным «неизвестным»", _md5(img) != _md5(_rgba(unknown)))
	check("не совпадает со старым значком", _md5(img) != OLD_PIXELS_MD5)
	for other in ["energy_drink", "food_bar", "energy_bar", "teleport_watch"]:
		var t := ShopArt.tex("item_" + other)
		if t != null:
			check("отличается от значка «%s»" % other, _md5(img) != _md5(_rgba(t)))

	_test_silhouette(img)
	_test_plus(img)
	_test_small_sizes(img)
	_test_same_everywhere(tex)
	_finish()


func _rgba(t: Texture2D) -> Image:
	var i := t.get_image()
	i.convert(Image.FORMAT_RGBA8)
	return i


func _md5(img: Image) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(img.get_data())
	return ctx.finish().hex_encode()


func _is_white(c: Color) -> bool:
	return c.a > 0.99 and c.r > 0.99 and c.g > 0.99 and c.b > 0.99


func _is_red(c: Color) -> bool:
	return c.a > 0.99 and c.r > 0.55 and c.g < 0.35 and c.b < 0.4


func _is_pale(c: Color) -> bool:
	return c.a > 0.99 and c.r > 0.8 and c.g > 0.8 and c.b > 0.8


## Вытянутая диагональная капсула, красная половина внизу-слева, светлая вверху-справа.
func _test_silhouette(img: Image) -> void:
	var n := 0
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	var red := Vector2.ZERO
	var red_n := 0
	var pale := Vector2.ZERO
	var pale_n := 0
	for y in range(32):
		for x in range(32):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			n += 1
			sx += x
			sy += y
			sxx += x * x
			syy += y * y
			sxy += x * y
			if _is_red(c):
				red += Vector2(x, y)
				red_n += 1
			elif _is_pale(c):
				pale += Vector2(x, y)
				pale_n += 1
	check("значок не пустой и не залит целиком (350..800 пикселей)", n >= 350 and n <= 800)
	check("углы прозрачны", img.get_pixel(0, 0).a == 0.0 and img.get_pixel(31, 0).a == 0.0
			and img.get_pixel(0, 31).a == 0.0 and img.get_pixel(31, 31).a == 0.0)
	var mx := sx / n
	var my := sy / n
	var vx := sxx / n - mx * mx
	var vy := syy / n - my * my
	var cxy := sxy / n - mx * my
	var tr := vx + vy
	var det := vx * vy - cxy * cxy
	var disc := sqrt(maxf(tr * tr / 4.0 - det, 0.0))
	var l1 := tr / 2.0 + disc
	var l2 := maxf(tr / 2.0 - disc, 0.001)
	check("капсула вытянута (отношение осей > 2)", l1 / l2 > 2.0)
	check("ось идёт по диагонали «/» (x растёт, y падает)", cxy < 0.0 and absf(cxy) > 0.6 * l2)
	check("есть красная и светлая половины", red_n > 60 and pale_n > 60)
	if red_n > 0 and pale_n > 0:
		var r := red / red_n
		var p := pale / pale_n
		check("красная половина внизу-слева, светлая вверху-справа", r.x < p.x - 4.0 and r.y > p.y + 4.0)


## Чисто белые пиксели на красной стороне шва (x < y) — это плюс: сплошная полоса по горизонтали и вертикали.
func _test_plus(img: Image) -> void:
	var white := {}
	for y in range(32):
		for x in range(32):
			if x < y and _is_white(img.get_pixel(x, y)):
				white[Vector2i(x, y)] = true
	check("на красной половине есть белый плюс (≥ 30 пикселей)", white.size() >= 30)
	var best_row := 0
	var best_col := 0
	for y in range(32):
		var run := 0
		for x in range(32):
			run = run + 1 if white.has(Vector2i(x, y)) else 0
			best_row = maxi(best_row, run)
	for x in range(32):
		var run2 := 0
		for y in range(32):
			run2 = run2 + 1 if white.has(Vector2i(x, y)) else 0
			best_col = maxi(best_col, run2)
	check("плюс: горизонтальная и вертикальная перекладины ≥ 9 пикселей", best_row >= 9 and best_col >= 9)
	# Плюс окружён красным и контуром, а не лежит на белой половине.
	var bx0 := 99
	var by0 := 99
	var bx1 := -1
	var by1 := -1
	for k in white:
		bx0 = mini(bx0, k.x)
		by0 = mini(by0, k.y)
		bx1 = maxi(bx1, k.x)
		by1 = maxi(by1, k.y)
	check("плюс квадратный по габариту (перекладины равны)", absi((bx1 - bx0) - (by1 - by0)) <= 1)
	var green := Color8(0x4D, 0xE0, 0x94)
	var gold := Color8(0xFF, 0xE0, 0x66)
	var old_colors := 0
	for y in range(32):
		for x in range(32):
			var c := img.get_pixel(x, y)
			if c.is_equal_approx(green) or c.is_equal_approx(gold):
				old_colors += 1
	check("нет зелёного креста и золотых искр прежнего значка", old_colors == 0)


## Показ в 16×16 «ближайшим соседом» (так рисуются тосты) при обеих чётностях выборки: плюс 5×5 не рассыпается.
func _test_small_sizes(img: Image) -> void:
	for off in [0, 1]:
		var whites := 0
		var reds := 0
		for y in range(16):
			for x in range(16):
				var c := img.get_pixel(2 * x + off, 2 * y + off)
				if x < y and _is_white(c):
					whites += 1
				if _is_red(c):
					reds += 1
		check("в 16×16 (сдвиг %d) плюс цел: 9 белых пикселей на красной стороне" % off, whites == 9)
		check("в 16×16 (сдвиг %d) красная половина читается (≥ 12 пикселей)" % off, reds >= 12)


## Один значок на все места: витрина (плитка товара), рюкзак/склад, тосты, награды, техника.
func _test_same_everywhere(tex: Texture2D) -> void:
	check("UiIcons.item (тосты, подборы) даёт тот же значок", UiIcons.item(ID) == tex)
	check("TechUi.item_icon даёт тот же значок", TechUi.item_icon(ID) == tex)
	check("HouseArt даёт тот же значок", HouseArt.food_icon(ID) == tex)
	var found := false
	for shelf in ["food", "premium", "picks", "tech"]:
		for o in ShopItems.goods_offers(shelf):
			if String(o.get("ref", "")) == ID:
				found = true
				check("плитка товара в магазине (полка %s) несёт этот значок" % shelf, o.get("icon") == tex)
	check("таблетка есть в витрине магазина", found)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


func _finish() -> void:
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)

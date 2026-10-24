extends Node
## test_energy_bar_icon — значок энергетического батончика: нарисован отдельно
## (с молнией, не со звездой), 32×32, не запасная «звезда» и на всех путях показа
## (витрина, рюкзак, техника, награды мета-слоя) отдаётся именно он.
##
## Запуск: godot --headless --path . res://tests/test_energy_bar_icon.tscn

const PATH := "res://art/ui/shop/item_energy_bar.png"
const BOLT := Color8(0xFF, 0xE0, 0x66)   # жёлтая молния
const STAR_RED := Color8(0xC2, 0x1E, 0x3A)   # красная звезда старого значка

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _count(img: Image, col: Color) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).is_equal_approx(col):
				n += 1
	return n


func _same(a: Texture2D, b: Texture2D) -> bool:
	if a == null or b == null:
		return false
	return a == b or a.get_image().get_data() == b.get_image().get_data()


func _ready() -> void:
	print("=== test_energy_bar_icon ===")
	check("файл значка существует", ResourceLoader.exists(PATH))
	var tex: Texture2D = ShopArt.tex("item_energy_bar")
	check("ShopArt.tex(item_energy_bar) загружается", tex != null)
	if tex == null:
		_finish()
		return
	var img := tex.get_image()
	check("значок 32×32", img.get_width() == 32 and img.get_height() == 32)

	var star := UiIcons.tex("star")
	check("не запасная звезда UiIcons", star == null or not _same(tex, star))
	check("не заглушка «булыжник»", not _same(tex, ShopArt.tex("item_unknown")))
	check("не белковый батончик", not _same(tex, ShopArt.tex("item_food_bar")))
	check("не энергетик (банка)", not _same(tex, ShopArt.tex("item_energy_drink")))

	check("на значке есть жёлтая молния (>= 25 точек)", _count(img, BOLT) >= 25)
	check("красной звезды на значке нет", _count(img, STAR_RED) == 0)
	var small := img.duplicate() as Image
	small.resize(16, 16, Image.INTERPOLATE_NEAREST)
	check("в 16×16 молния ещё различима (>= 6 жёлтых точек)", _count(small, BOLT) >= 6)

	check("ShopArt.item_icon(energy_bar) — именно этот значок", ShopArt.item_icon("energy_bar") == tex)
	check("UiIcons.item(energy_bar) — именно этот значок", _same(UiIcons.item("energy_bar"), tex))
	check("TechUi.item_icon(energy_bar) — не звезда, а этот значок",
		_same(TechUi.item_icon("energy_bar"), tex))
	check("награда мета-слоя energy_bar — этот значок",
		_same(MetaUiKit.reward_tex("item", "energy_bar"), tex))
	check("энергетик в наградах остался значком энергии",
		not _same(MetaUiKit.reward_tex("item", "energy_drink"), tex))
	_finish()


func _finish() -> void:
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)

class_name HeroIcons
extends RefCounted
## Иконки экрана героя (art/ui/hero/*.png, рисуются tools/gen_hero_icons.py).
##
## ПОЧЕМУ через общий кэш: экраны перестраиваются на каждое открытие, а load()
## десятков маленьких PNG каждый раз — лишняя работа на телефоне. Нет файла —
## null, и вызывающий рисует запасной значок: экран обязан открываться и без
## картинок (их может заменить художник).

const DIR := "res://art/ui/hero/"

static var _cache: Dictionary = {}


static func get_icon(icon_name: String) -> Texture2D:
	if _cache.has(icon_name):
		return _cache[icon_name]
	var path := DIR + icon_name + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[icon_name] = tex
	return tex


## Иконка ветки прокачки по id ветки (data/upgrades.json).
static func skill_icon(branch_id: String) -> Texture2D:
	return get_icon("sk_" + branch_id)


## Готовый TextureRect с иконкой (по умолчанию её родной размер 16×16).
static func make(icon_name: String, size: float = 16.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = get_icon(icon_name)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

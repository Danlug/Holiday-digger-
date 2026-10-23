class_name HintArt
extends RefCounted
## Значки подсказок (art/hints/*.png, рисует tools/gen_hint_icons.py) и значки
## для тоста: «ui:plus», «tech:icon_tank», «meta:gift», «story:icon_diary»,
## «hint:bang». Без префикса — сначала общие значки интерфейса, потом наши.
## Нет файла — null, и тост рисуется без картинки, а не падает.

const DIR := "res://art/hints/%s.png"
const PREFIX_DIRS := {
	"tech": "res://art/tech/%s.png",
	"meta": "res://art/meta/%s.png",
	"story": "res://art/story/%s.png",
}
## Файл вдвое больше рисунка: на экране один пиксель рисунка = одна единица.
const SCALE := 0.5

static var _cache: Dictionary = {}
static var _exit_hooked: bool = false


static func tex(icon_name: String) -> Texture2D:
	return _load(DIR % icon_name)


static func icon(spec: String) -> Texture2D:
	var p := spec.find(":")
	if p < 0:
		var t := UiIcons.tex(spec)
		return t if t != null else tex(spec)
	var kind := spec.substr(0, p)
	var nm := spec.substr(p + 1)
	match kind:
		"ui":
			return UiIcons.tex(nm)
		"hint":
			return tex(nm)
		_:
			if PREFIX_DIRS.has(kind):
				return _load(String(PREFIX_DIRS[kind]) % nm)
	return null


## Размер значка на экране в проектных единицах.
static func size_of(t: Texture2D) -> Vector2:
	return t.get_size() * SCALE if t != null else Vector2.ZERO


static func _load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[path] = t
	_hook_exit()
	return t


## Статический кэш текстур переживает сцену, и движок при выходе жалуется на «ресурсы
## ещё используются»: чистим его, пока корень дерева жив (как MenuRegistry).
static func _hook_exit() -> void:
	if _exit_hooked:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_exit_hooked = true
	tree.root.tree_exiting.connect(_on_tree_exiting)


static func _on_tree_exiting() -> void:
	_cache.clear()
	_exit_hooked = false

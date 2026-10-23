class_name DeepBackdrop
extends Node2D
## Подземный параллакс-задник (ГДД §4.2): стена пояса глубины, видимая сквозь
## пустые клетки (WorldView их не рисует, см. deep_backdrop_active). Корни и
## трещины -> пещеры -> кристаллы -> базальт -> руины -> магма -> пустота -> небеса.
##
## Лежит в ViewRoot между облаками и тайлами. Стена едет медленнее мира
## (PARALLAX), поэтому читается как дальняя поверхность, а не как плитка под
## ногами. У границы поясов два слоя кроссфейдятся. Выше линии земли (y < 0)
## не рисуется — там небо, гора и забор (Backdrop).
##
## Рисуем сами через draw_texture_rect_region по сетке 96x96 логических px (1 текстель =
## 1 логический px, как у тайлов), а не Sprite2D с region: так легко обрезать по
## линии земли без скачка фазы узора.

const TILE := 32.0
const PERIOD := 96.0
## Доли смещения камеры, которые получает стена: чем меньше, тем она «дальше».
const PARALLAX := Vector2(0.55, 0.45)
## Притемнение: стена — фон, герой и руда должны читаться поверх неё.
const DIM := 0.78

var _cam := Vector2.ZERO
var _view := Vector2(7, 14)
var _tex: Dictionary = {}


func update(cam: Vector2, view_w: int, view_h: int) -> void:
	_cam = cam
	_view = Vector2(view_w, view_h)
	visible = cam.y + float(view_h) > 0.0
	if visible:
		queue_redraw()


func _wall_texture(wall: String) -> Texture2D:
	if _tex.has(wall):
		return _tex[wall]
	var path := "res://art/env/deep/wall_%s.png" % wall
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex[wall] = t
	return t


func _draw() -> void:
	var depth := _cam.y + _view.y * 0.5
	var bl := Biomes.blend_at(depth)
	var wa := String(Biomes.get_biome(int(bl["a"])).get("wall", ""))
	_draw_layer(wa, 1.0)
	if float(bl["t"]) > 0.0:
		var wb := String(Biomes.get_biome(int(bl["b"])).get("wall", ""))
		if wb != wa:
			_draw_layer(wb, float(bl["t"]))


func _draw_layer(wall: String, alpha: float) -> void:
	var tex := _wall_texture(wall)
	if tex == null:
		return
	var cam_px := _cam * TILE
	var phase := Vector2(fposmod(-PARALLAX.x * cam_px.x, PERIOD), fposmod(-PARALLAX.y * cam_px.y, PERIOD))
	var origin := cam_px + phase - Vector2(PERIOD, PERIOD)
	var cols := int(ceil(_view.x * TILE / PERIOD)) + 2
	var rows := int(ceil(_view.y * TILE / PERIOD)) + 2
	var col := Color(DIM, DIM, DIM, alpha)
	for j in range(rows):
		for i in range(cols):
			var dst := Rect2(origin + Vector2(i * PERIOD, j * PERIOD), Vector2(PERIOD, PERIOD))
			if dst.end.y <= 0.0:
				continue
			var src := Rect2(0, 0, PERIOD, PERIOD)
			if dst.position.y < 0.0:
				var cut := -dst.position.y
				dst = Rect2(dst.position.x, 0.0, PERIOD, PERIOD - cut)
				src = Rect2(0, cut, PERIOD, PERIOD - cut)
			draw_texture_rect_region(tex, dst, src, col)

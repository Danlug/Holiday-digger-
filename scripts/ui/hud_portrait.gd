class_name HudPortrait
extends Control
## Лицо героя в кнопке «Герой» в левом верхнем углу HUD (владелец 27.10: «иконка с лицом
## нашего героя, а не дурачка в каске»). Рисунок не новый: кадр стойки из того же листа, что
## ходит по миру и стоит на экране героя (HeroPortrait), кадрированный по голове поиском
## макушки по прозрачности. Перерисует мальчика художник — портрет возьмёт новый лист сам.
## Возраст героя в игре не меняется (развёртка 8–15 лет есть только в сцене), лист один.
##
## Рамка — сама кнопка UiBtn (бордюр, золото при нажатии); внутри — фон цвета внука из
## диалогов, притушенный так же, как фон его портрета в DialoguePortrait.

const SHEET := "res://art/character/idle.png"
const INSET := 2.0      # внутри бордюра кнопки: углы кадра не вылезают за её скругление
const CROWN_CUT := 2    # пикселей макушки под рамкой: лицо выше, бейдж уровня ложится на воротник, а не на подбородок
const BACKDROP := Color8(0x1B, 0x2B, 0x41)   # #4F7FC0 (акцент внука, data/dialogue.json) .darkened(0.66)

static var _faces: Dictionary = {}   # сторона кадра -> AtlasTexture

var _bg: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = StyleBoxFlat.new()
	_bg.bg_color = BACKDROP
	_bg.set_corner_radius_all(3)


func _draw() -> void:
	var r := Rect2(Vector2(INSET, INSET), (size - Vector2(INSET, INSET) * 2.0).floor())
	if r.size.x < 4.0 or r.size.y < 4.0:
		return
	draw_style_box(_bg, r)
	var face := face_texture(int(minf(r.size.x, r.size.y)))
	if face != null:
		# Пиксель листа = единица экрана: у кадра нет дробного масштаба, лицо не «рябит».
		draw_texture(face, r.position + ((r.size - face.get_size()) * 0.5).floor())


## Квадрат side×side вокруг головы на первом кадре стойки: сверху — макушка (CROWN_CUT
## пикселей волос уходят под рамку, как у аватаров), по горизонтали — центр непрозрачных
## пикселей верхней части фигуры (голова, без рук).
static func face_texture(side: int) -> AtlasTexture:
	if _faces.has(side):
		return _faces[side]
	var out: AtlasTexture = null
	var sheet: Texture2D = load(SHEET) if ResourceLoader.exists(SHEET) else null
	var img := sheet.get_image() if sheet != null else null
	if img != null and side > 0:
		if img.is_compressed():
			img.decompress()
		var frame := mini(img.get_height(), img.get_width())   # кадры листа квадратные
		var top := -1
		for y in frame:
			for x in frame:
				if img.get_pixel(x, y).a > 0.5:
					top = y
					break
			if top >= 0:
				break
		if top >= 0:
			var sum := 0.0
			var n := 0
			for y in range(top, mini(top + int(side * 0.6), frame)):
				for x in frame:
					if img.get_pixel(x, y).a > 0.5:
						sum += x
						n += 1
			var cx := sum / float(maxi(n, 1))
			var s := mini(side, frame)
			var rx := clampi(int(roundf(cx - s * 0.5)), 0, frame - s)
			var ry := clampi(top + CROWN_CUT, 0, frame - s)
			out = AtlasTexture.new()
			out.atlas = sheet
			out.region = Rect2(rx, ry, s, s)
	_faces[side] = out
	return out

extends Node2D
## CharacterView — отрисовка спрайта героя (портировано из блока анимации в
## draw() web/index.html): выбор листа по состоянию (копает/летит/падает/
## идёт/стоит), покадровая анимация горизонтальной полосой кадров 48×48,
## разворот по facing.
##
## Кадр шире клетки: при 32 px замах киркой и винты ранца не помещались, и
## спрайт приходилось ужимать — герой заметно худел, стоило ему начать
## копать. Тело по-прежнему ~20 px, просто вокруг него есть поле.

const TILE := 32
const CHAR_W := 48
const CHAR_H := 48
const HH := 0.46

var player: Node = null

var _sprite: Sprite2D
var _stun_flash: ColorRect
var _sheets: Dictionary = {}


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.region_enabled = true
	add_child(_sprite)
	for sheet: String in ["idle", "walk", "fall", "fly", "fly_jet", "dig_shovel", "dig_pick"]:
		var path: String = "res://art/character/" + sheet + ".png"
		_sheets[sheet] = load(path) if ResourceLoader.exists(path) else null


func _process(_dt: float) -> void:
	if player == null:
		return
	position = Vector2(player.x * TILE, player.y * TILE)

	var sheet_name: String
	if player.digging != null:
		sheet_name = "dig_shovel" if GameState.current_tool == "shovel" else "dig_pick"
	elif not player.on_ground:
		# Ранец и джетпак выглядят по-разному, и по кадру должно быть видно,
		# на чём герой висит.
		if player.thrust == "jet":
			sheet_name = "fly_jet"
		elif player.thrust != "":
			sheet_name = "fly"
		else:
			sheet_name = "fall"
	else:
		sheet_name = "walk" if player.vx != 0.0 else "idle"

	var tex: Texture2D = _sheets.get(sheet_name)
	if tex != null:
		_sprite.texture = tex
		var frames: int = maxi(1, int(round(tex.get_width() / float(CHAR_W))))
		var frame: int = int(floor(player.anim / 7.0)) % frames if frames > 1 else 0
		_sprite.region_rect = Rect2(frame * CHAR_W, 0, CHAR_W, CHAR_H)
	_sprite.flip_h = player.facing < 0
	_sprite.position = Vector2(-CHAR_W / 2.0, -HH * TILE - 16.0)

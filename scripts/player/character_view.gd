extends Node2D
## CharacterView — отрисовка спрайта героя (портировано из блока анимации в
## draw() web/index.html): выбор листа по состоянию (копает/летит/падает/
## идёт/стоит), покадровая анимация горизонтальной полосой кадров 32×48,
## разворот по facing.

const TILE := 32
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
	for sheet: String in ["idle", "walk", "fall", "fly", "dig_shovel", "dig_pick"]:
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
		sheet_name = "fly" if player.thrust != "" else "fall"
	else:
		sheet_name = "walk" if player.vx != 0.0 else "idle"

	var tex: Texture2D = _sheets.get(sheet_name)
	if tex != null:
		_sprite.texture = tex
		var frames: int = maxi(1, int(round(tex.get_width() / float(TILE))))
		var frame: int = int(floor(player.anim / 7.0)) % frames if frames > 1 else 0
		_sprite.region_rect = Rect2(frame * TILE, 0, TILE, 48)
	_sprite.flip_h = player.facing < 0
	_sprite.position = Vector2(-TILE / 2.0, -HH * TILE - 16.0)

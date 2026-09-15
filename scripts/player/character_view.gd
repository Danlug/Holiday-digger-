extends Node2D
## CharacterView — отрисовка спрайта героя (портировано из блока анимации в
## draw() web/index.html): выбор листа по состоянию (копает/летит/падает/
## идёт/стоит), покадровая анимация горизонтальной полосой кадров, разворот
## по facing.
##
## Кадр шире клетки: при 32 px замах киркой и винты ранца не помещались, и
## спрайт приходилось ужимать — герой заметно худел, стоило ему начать
## копать. Тело по-прежнему ~20 px, просто вокруг него есть поле.

const TILE := 32
const CHAR_W := 48
const CHAR_H := 48
const HH := 0.46

## Линия земли внутри кадра: подошва героя стоит на CHAR_H - FOOT_PAD.
## На этом держится вся вертикальная привязка спрайта — см. SHEET_FRAME.
const GROUND_Y := 46

## Листы, у которых кадр не 48×48: имя листа -> [ширина, высота, линия земли].
##
## Бурмобиль по ГДД п.5 занимает две клетки в ширину — это 64 px, и в кадр 48
## он не влезает. Ужимать машину нельзя: вместе с ней ужимается герой в
## кабине, и он становится мельче героя пешком. Лишняя высота кадра уходит
## ВНИЗ, под линию земли, — бур, копающий вниз, входит в клетку под машиной,
## и отвал породы должен лечь именно туда.
const SHEET_FRAME := {
	"dig_rig_down": [80, 56, 50],
	"dig_rig_side": [80, 56, 50],
}

## Листы копки, нарисованные отдельно для копки вниз и для копки вбок.
## Ключ — общее имя набора, к нему приписывается "_down" или "_side".
const DIG_SHEETS := ["idle", "walk", "fall", "fly", "fly_jet",
		"dig_shovel", "dig_pick", "dig_pick_rusty",
		"dig_drill_down", "dig_drill_side", "dig_rig_down", "dig_rig_side"]

var player: Node = null

var _sprite: Sprite2D
var _stun_flash: ColorRect
var _sheets: Dictionary = {}


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.region_enabled = true
	add_child(_sprite)
	for sheet: String in DIG_SHEETS:
		var path: String = "res://art/character/" + sheet + ".png"
		if ResourceLoader.exists(path):
			_sheets[sheet] = load(path)


## Имя листа копки по инструменту и направлению. Направление берём из самой
## копаемой клетки: она либо прямо под героем, либо сбоку. У кирки и лопаты
## нарисован один набор на оба направления — тогда суффикса просто нет.
func _dig_sheet_name() -> String:
	var base: String
	match GameState.current_tool:
		"shovel": base = "dig_shovel"
		"rusty_pickaxe": base = "dig_pick_rusty"
		"hand_drill": base = "dig_drill"
		"drill_rig": base = "dig_rig"
		_: base = "dig_pick"
	var dir: String = "_down" if int(player.digging.y) == player.cell_y() + 1 else "_side"
	return base + dir if _sheets.has(base + dir) else base


func _process(_dt: float) -> void:
	if player == null:
		return
	position = Vector2(player.x * TILE, player.y * TILE)

	var sheet_name: String
	if player.digging != null:
		# Для каждого инструмента нарисована своя анимация, а для бура и
		# бурмобиля — ещё и своя на каждое направление копки.
		sheet_name = _dig_sheet_name()
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

	var geom: Array = SHEET_FRAME.get(sheet_name, [CHAR_W, CHAR_H, GROUND_Y])
	var fw: int = geom[0]
	var fh: int = geom[1]
	var tex: Texture2D = _sheets.get(sheet_name)
	if tex != null:
		_sprite.texture = tex
		var frames: int = maxi(1, int(round(tex.get_width() / float(fw))))
		var frame: int = int(floor(player.anim / 7.0)) % frames if frames > 1 else 0
		_sprite.region_rect = Rect2(frame * fw, 0, fw, fh)
	_sprite.flip_h = player.facing < 0
	# Линия земли листа должна лечь туда же, куда ложится подошва у кадра
	# 48×48, иначе высокий кадр повиснет над землёй.
	_sprite.position = Vector2(-fw / 2.0,
			-HH * TILE - 16.0 + float(GROUND_Y - int(geom[2])))

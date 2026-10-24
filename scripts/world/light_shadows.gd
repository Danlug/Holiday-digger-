class_name ContactShadows
extends Node2D
## Контактные тени мира (ветка «world-fx»): мягкое пятно под героем и припаркованным бурмобилем,
## чтобы они «стояли на земле», а не висели над ней. Узел лежит в ViewRoot прямо перед героем:
## тень выше тайлов и дома, но под персонажем.
##
## Тень героя ищет землю под ногами (две клетки по краям хитбокса) и в прыжке/полёте уходит на неё,
## сжимаясь и бледнея с высотой, — по ней читается, как высоко он. Поиск земли — только при смене клетки
## героя; неподвижный кадр стоит несколько присвоений свойств спрайта.

const TILE := 32
const ART_SCALE := 3.0          # как у WorldView: текстуры на диске втрое подробнее клетки
const HH := 1.0 / 3.0           # полувысота хитбокса героя (player.gd)
const HW := 0.3
const SCAN := 9                 # дальше этого вниз землю не ищем — тени нет
const TEX_PATH := "res://art/fx/shadow_blob.png"
const BASE_W := 20.0            # ширина тени героя на земле, px
const RIG_TEX := "res://art/env/drill_mobile_parked.png"

var player: Node = null
var world: WorldGen = null

var _hero: Sprite2D
var _rig: Sprite2D
var _scan_key: int = -1
var _ground_row: int = 0
var _rig_w: float = 0.0


func _ready() -> void:
	name = "ContactShadows"
	var tex: Texture2D = load(TEX_PATH) if ResourceLoader.exists(TEX_PATH) else null
	_hero = Sprite2D.new()
	_hero.texture = tex
	_hero.visible = false
	add_child(_hero)
	_rig = Sprite2D.new()
	_rig.texture = tex
	_rig.visible = false
	add_child(_rig)
	if ResourceLoader.exists(RIG_TEX):
		_rig_w = float((load(RIG_TEX) as Texture2D).get_width()) / ART_SCALE


func _process(_dt: float) -> void:
	if player == null or world == null or _hero.texture == null:
		return
	var hide := GameState.house_is_indoors or not GameState.is_alive
	_update_hero(hide)
	_update_rig(hide)


func _update_hero(hide: bool) -> void:
	if hide:
		_hero.visible = false
		return
	var px: float = float(player.x)
	var py: float = float(player.y)
	var feet := py + HH
	var cl := int(floor(px - HW))
	var cr := int(floor(px + HW))
	var cy := int(floor(feet + 0.02))
	var key := (cl * 73856093) ^ (cr * 19349663) ^ (cy * 83492791)
	if key != _scan_key:
		_scan_key = key
		_ground_row = _find_ground(cl, cr, cy)
	if _ground_row < 0:
		_hero.visible = false
		return
	var gy := float(_ground_row) * TILE
	var h := maxf(gy - feet * TILE, 0.0)
	var k := clampf(h / 112.0, 0.0, 1.0)
	var rig: bool = player.has_method("is_in_rig") and bool(player.is_in_rig())
	var w := BASE_W * (1.9 if rig else 1.0) * lerpf(1.0, 0.5, k)
	_hero.visible = true
	_hero.position = Vector2(px * TILE, gy - 1.5).floor()
	_hero.scale = Vector2(w / 24.0, lerpf(1.0, 0.55, k))
	_hero.modulate.a = lerpf(1.0, 0.25, k)


## Первая твёрдая клетка под героем у левого или правого края хитбокса; −1, если дальше SCAN её нет.
func _find_ground(cl: int, cr: int, cy: int) -> int:
	var best := -1
	for cx in ([cl] if cl == cr else [cl, cr]):
		# строки y < 1 — воздух и трава огорода: земля начинается с первой земляной клетки
		for r in range(maxi(cy, 1), cy + SCAN):
			if world.get_tile(cx, r) != TileTypes.Type.EMPTY:
				best = r if best < 0 else mini(best, r)
				break
	return best


func _update_rig(hide: bool) -> void:
	if hide or _rig_w <= 0.0 or not GameState.is_rig_parked() \
			or (player != null and String(player.get("rig_transition")) != ""):
		_rig.visible = false
		return
	var cell: Vector2i = GameState.rig_parked_at
	_rig.visible = true
	_rig.position = Vector2((cell.x + 0.5) * TILE, cell.y * TILE - 1.0).floor()
	_rig.scale = Vector2(_rig_w * 0.9 / 24.0, 1.3)
	_rig.modulate.a = 1.0

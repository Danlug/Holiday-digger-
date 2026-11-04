class_name ArtifactLayer
extends Node2D
## Артефакты в породе: рисуются поверх своей клетки (тайл под ними не меняется) в
## ViewRoot сразу над WorldView — как сундуки (ChestLayer), чтобы свет глубины и
## тени ложились на них так же, как на тайлы. Клетку даёт ArtifactSpawn.cell_of,
## подбор — ArtifactFinder.
##
## Видимость — по туману (ГДД §12), но не как у руды: в сером тумане (известен
## рельеф) предмет виден тёмным силуэтом — «в земле что-то торчит», в полном
## обзоре — целиком и с бликом. ПОЧЕМУ уже в сером: стартовый обзор ресурсов —
## одна клетка, и одиночный предмет на ряд в 32 клетки игрок видел бы, только
## уткнувшись в него лопатой — та же лотерея, что была до 27.10. Обзор рельефа
## (радиус 2) держит темп прежней модели (расчёт — в шапке ArtifactSpawn).
## Собранный не рисуется. Выкопанная клетка уже выдала находку; пустую (её вырвал
## обвал или землетрясение) видно только в полном обзоре — предмет лежит в ней,
## и его подбирают касанием.

const TILE := 32
const ROWS_AROUND := 14
const GRAY_TINT := Color(0.28, 0.24, 0.2, 0.9)   # силуэт в сером тумане: форма видна, что это — нет

var world: WorldGen = null
var fog: FogOfWar = null
var player: Node = null

var _entries: Array = []   # [{cell: Vector2i, id: String, full: bool, free: bool}]
var _sig: int = 0
var _time: float = 0.0
var _scan_left: float = 0.0


func entries() -> Array:
	return _entries


func _process(delta: float) -> void:
	_time += delta
	# окрестность героя пересматривается 10 раз в секунду, как у сундуков
	_scan_left -= delta
	var glinting := _has_full() and not Settings.reduce_motion
	if _scan_left <= 0.0 or glinting:
		_scan_left = 0.1
		var sig := collect()
		if sig != _sig or glinting:
			_sig = sig
			queue_redraw()


func _has_full() -> bool:
	for e in _entries:
		if e["full"] and not e["free"]:
			return true
	return false


## Собирает видимые артефакты около героя. Возвращает подпись (меняется — перерисовать).
func collect() -> int:
	_entries.clear()
	if world == null or fog == null or player == null or world.era == "grandpa":
		return 0
	var py := int(floor(float(player.y)))
	var sig := 17
	for a: Dictionary in Balance.artifacts.get("artifacts", []):
		var id := String(a.get("id", ""))
		if GameState.collected_artifacts.has(id):
			continue
		var cell := ArtifactSpawn.cell_of(a, GameState.world_seed, world)
		if absi(cell.y - py) > ROWS_AROUND:
			continue
		var state := fog.get_state(cell.x, cell.y)
		if state == FogOfWar.State.BLACK:
			continue
		var full := state == FogOfWar.State.FULL
		var free := world.get_tile(cell.x, cell.y) == TileTypes.Type.EMPTY
		if free and not full:
			continue
		_entries.append({"cell": cell, "id": id, "full": full, "free": free})
		sig = sig * 31 + cell.x * 7 + cell.y * 131 + (1 if full else 0) + (2 if free else 0)
	return sig


func _draw() -> void:
	for e in _entries:
		var cell: Vector2i = e["cell"]
		var id := String(e["id"])
		var rect := Rect2(Vector2(cell.x * TILE, cell.y * TILE), Vector2(TILE, TILE))
		# в пустой клетке предмет лежит целиком, в породе — утоплен
		var tex: Texture2D = ArtifactArt.texture_for(id) if e["free"] else ArtifactArt.ground_texture_for(id)
		var tint := Color.WHITE if e["full"] else GRAY_TINT
		if tex != null:
			draw_texture_rect(tex, rect, false, tint)
		else:
			draw_rect(Rect2(rect.position + Vector2(10, 10), Vector2(12, 12)), Color(0.9, 0.7, 0.2, tint.a) * tint)
		if e["full"] and not e["free"] and not Settings.reduce_motion:
			_glint(rect, float(cell.x * 0.37 + cell.y * 0.11))


## Блик раз в ~2 с: крестик-искра пробегает по предмету — глаз цепляется за находку.
func _glint(rect: Rect2, phase: float) -> void:
	var ph := fmod(_time + phase, 2.0) / 2.0
	if ph > 0.2:
		return
	var a := 1.0 - ph / 0.2
	var p := (rect.position + Vector2(rect.size.x * (0.25 + ph * 2.5), rect.size.y * 0.3)).floor()
	var col := Color(1.0, 0.97, 0.8, a)
	draw_rect(Rect2(p, Vector2(1, 1)), col)
	draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), Color(col, a * 0.6))
	draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), Color(col, a * 0.6))

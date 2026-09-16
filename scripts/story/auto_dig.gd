class_name AutoDigTutorial
extends Node
## Онбординг, шаг 2 (ГДД раздел 9): игра забирает управление и на ×10 сама
## выбирает первые три уровня огорода.
##
## Копает НЕ физикой героя, а списком клеток по таймеру, и вот почему. Герой,
## которого ведёт скрипт, обязан пройти мимо камней: лопата камень не берёт, и
## любое касание камня боком даёт стан от вибрации (ГДД раздел 5) — обучающий
## ролик встал бы намертво на первом же булыжнике третьего уровня. Городить
## поиск пути вокруг камней ради пятнадцатисекундной нарезки нет смысла:
## список клеток заранее известен, конечен и заведомо завершается.
##
## Герой при этом заморожен (player.frozen), а его позиция плавно ведётся к
## копаемой клетке — со стороны это он и копает, просто быстро.

signal midpoint_reached
signal finished

# 3 секунды на клетку (ГДД раздел 6), ускорение ×10 (ГДД раздел 9).
const CELL_SECONDS := 3.0 / 10.0
# Страховка от зацикливания: сколько бы клеток ни осталось, через минуту
# реального времени ролик доигрывается мгновенно и отдаёт управление.
const MAX_REAL_SECONDS := 60.0
# Четыре уровня, а не три (решение владельца): расчистка должна довести героя
# ровно до фундамента, чтобы лопата упёрлась в него сразу после ролика. Пять
# клеток сценарного золота автокопка обходит сама — она берёт только то, что
# берётся лопатой, а золото лопатой не берётся (в этом весь смысл четвёртого
# уровня: оно лежит на виду и недоступно, пока нет кирки деда).
const ROWS := 4
const MIDPOINT_FRACTION := 0.55

var running: bool = false
var paused: bool = false

var _player: Node = null
var _world: WorldGen = null
var _cells: Array = []          # [Vector2i, ...] в порядке копки
var _index: int = 0
var _cell_time: float = 0.0
var _elapsed: float = 0.0
var _midpoint_sent: bool = false
var _from: Vector2 = Vector2.ZERO

var _banner_layer: CanvasLayer
var _banner: Panel
var _banner_label: Label
var _skip_btn: Button


func begin(player: Node, world: WorldGen) -> void:
	_player = player
	_world = world
	_cells = _build_cell_list()
	_index = 0
	_cell_time = 0.0
	_elapsed = 0.0
	_midpoint_sent = false
	running = true
	paused = false
	if _player != null:
		_player.release_control()
		_player.digging = null
		_player.frozen = true
		_from = Vector2(_player.x, _player.y)
	_build_banner()
	if _cells.is_empty():
		_end()


## Клетки трёх верхних уровней огорода, сверху вниз и слева направо.
## Лестница и камни отсеиваются здесь же: лопатой они не берутся, а оставлять
## их в списке — значит ждать на них впустую.
func _build_cell_list() -> Array:
	var out: Array = []
	if _world == null:
		return out
	for y in range(1, ROWS + 1):
		for x in range(WorldGen.GARDEN_X_MIN, WorldGen.WIDTH):
			var t := _world.get_tile(x, y)
			if t == TileTypes.Type.EMPTY:
				continue
			if not TileTypes.can_dig_with_shovel(t):
				continue
			out.append(Vector2i(x, y))
	return out


func _build_banner() -> void:
	if _banner_layer != null:
		_banner_layer.visible = true
		return
	_banner_layer = CanvasLayer.new()
	_banner_layer.layer = 90  # под катсценой (100), над HUD
	add_child(_banner_layer)

	_banner = Panel.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_left = 8
	_banner.offset_right = -8
	_banner.offset_top = 8
	_banner.offset_bottom = 34
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.035, 0.027, 0.92)
	sb.border_color = Color8(0xE0, 0xA9, 0x3B)
	sb.set_border_width_all(1)
	_banner.add_theme_stylebox_override("panel", sb)
	_banner_layer.add_child(_banner)

	_banner_label = Label.new()
	_banner_label.text = StoryText.get_text("ui.autodig_banner")
	_banner_label.position = Vector2(8, 5)
	_banner_label.add_theme_font_size_override("font_size", 11)
	_banner_label.add_theme_color_override("font_color", Color8(0xE8, 0xDC, 0xC0))
	_banner.add_child(_banner_label)

	_skip_btn = Button.new()
	_skip_btn.text = StoryText.get_text("ui.skip")
	_skip_btn.add_theme_font_size_override("font_size", 9)
	_skip_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_btn.offset_left = -62
	_skip_btn.offset_right = -4
	_skip_btn.offset_top = 3
	_skip_btn.offset_bottom = 23
	_skip_btn.pressed.connect(skip)
	_banner.add_child(_skip_btn)


func pause() -> void:
	paused = true
	if _banner_layer != null:
		_banner_layer.visible = false


func resume() -> void:
	if not running:
		return
	paused = false
	if _player != null:
		# Пока показывали находку, управление возвращали игроку — забираем его
		# обратно, иначе герой начнёт падать посреди ролика.
		_player.release_control()
		_player.frozen = true
		_from = Vector2(_player.x, _player.y)
	if _banner_layer != null:
		_banner_layer.visible = true


## Пропуск: оставшиеся клетки выкапываются одним махом. Игрок получает ровно
## тот же мир и тот же опыт, что и досмотревший ролик, — пропуск не должен
## стоить прогресса.
func skip() -> void:
	if not running:
		return
	while _index < _cells.size():
		_dig(_cells[_index])
		_index += 1
	_end()


## Остановка без сигнала finished и без докапывания остатка: ролик просто
## перестаёт существовать. Нужно кнопке "Сброс".
func abort() -> void:
	if not running:
		return
	_cells.clear()
	_index = 0
	_end()


func _process(dt: float) -> void:
	if not running or paused:
		return
	_elapsed += dt
	if _elapsed > MAX_REAL_SECONDS:
		skip()
		return

	if not _midpoint_sent and _index >= int(_cells.size() * MIDPOINT_FRACTION):
		_midpoint_sent = true
		midpoint_reached.emit()
		return

	_cell_time += dt
	var target: Vector2i = _cells[_index]
	var to := Vector2(float(target.x) + 0.5, float(target.y) - 0.5)
	var k: float = clampf(_cell_time / CELL_SECONDS, 0.0, 1.0)
	if _player != null:
		# Ведём героя к клетке и подкручиваем счётчик кадров вручную: физика
		# заморожена, а анимация копки крутится именно от player.anim.
		_player.x = lerpf(_from.x, to.x, k)
		_player.y = lerpf(_from.y, to.y, k)
		_player.facing = 1 if to.x >= _from.x else -1
		_player.anim += 60.0 * dt
		_player.digging = {"x": target.x, "y": target.y, "t": _cell_time,
			"total": CELL_SECONDS, "type": _world.get_tile(target.x, target.y)}

	if _cell_time >= CELL_SECONDS:
		_dig(target)
		_cell_time = 0.0
		_from = to
		_index += 1
		if _index >= _cells.size():
			_end()


func _dig(cell: Vector2i) -> void:
	if _world == null:
		return
	var type := _world.get_tile(cell.x, cell.y)
	if type == TileTypes.Type.EMPTY:
		return
	_world.dig_cell(cell.x, cell.y)
	# Опыт начисляется по тем же правилам, что и при ручной копке (ГДД
	# раздел 11): земля — 1. Монет за копку нет нигде, и здесь тоже.
	if type == TileTypes.Type.DIRT:
		GameState.add_xp(1)
	GameState.update_max_depth(cell.y)


func _end() -> void:
	running = false
	paused = false
	if _banner_layer != null:
		_banner_layer.visible = false
	if _player != null:
		_player.digging = null
		_player.frozen = false
		_player.release_control()
	finished.emit()

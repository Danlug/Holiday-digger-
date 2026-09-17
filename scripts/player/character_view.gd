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

## Во сколько раз текстуры подробнее игровых координат (см. пояснение в
## tools/import_art.py). Кадр героя на диске — 144×144, а на экране он занимает
## те же 48 логических точек: спрайт рисуется уменьшенным втрое, и телефону
## достаётся втрое больше настоящих пикселей вместо растянутых квадратов.
const ART_SCALE := 3.0

const CHAR_W := int(48 * ART_SCALE)
const CHAR_H := int(48 * ART_SCALE)
const HH := 0.46

## Линия земли внутри кадра: подошва героя стоит на CHAR_H - FOOT_PAD.
## На этом держится вся вертикальная привязка спрайта — см. SHEET_FRAME.
const GROUND_Y := int(46 * ART_SCALE)

## Листы, у которых кадр не 48×48: имя листа -> [ширина, высота, линия земли].
##
## Бурмобиль по ГДД п.5 занимает две клетки в ширину — это 64 px, и в кадр 48
## он не влезает. Ужимать машину нельзя: вместе с ней ужимается герой в
## кабине, и он становится мельче героя пешком. Лишняя высота кадра уходит
## ВНИЗ, под линию земли, — бур, копающий вниз, входит в клетку под машиной,
## и отвал породы должен лечь именно туда.
##
## Ленты полёта fly_1..fly_4 — та же история, только лишнее место уходит
## ВВЕРХ, под винты, и немного вниз, под выхлоп. Тело героя в них того же
## размера, что в idle.png: масштаб на весь лист один, и посчитан он по росту
## героя (см. tools/import_packs.py). Влезть в 48×48 винты не могут — у
## большого винта один диск 66 px в поперечнике, у топового джетпака пламя
## уносит на 43 px назад, — а ужимать под них героя нельзя: он станет мельче
## себя же пешком. Числа берутся из печати импортёра, менять их руками не надо.
const SHEET_FRAME := {
	"dig_rig_down": [240, 168, 150],
	"dig_rig_side": [240, 168, 150],
	"fly_1": [154, 162, 156],
	"fly_2": [204, 165, 163],
	"fly_3": [152, 141, 129],
	"fly_4": [260, 136, 123],
}

## Лента полёта по уровню снаряжения: 1 — ранец, 2 — улучшенный ранец,
## 3 — джетпак, 4 — топовый джетпак. 0 — снаряжения нет.
const FLY_SHEETS := ["fly_1", "fly_2", "fly_3", "fly_4"]

## Сколько единиц счётчика anim держится один кадр. Меньше — быстрее.
const ANIM_DIV := 7.0

## Свой темп у листов, где кадров не четыре.
##
## Ходьба нарисована на шестнадцать кадров, и это ЧЕТЫРЕ шага, а не один
## цикл: узкие позы (ноги вместе) приходятся на кадры 1, 5, 9 и 13. При общем
## темпе 7.0 шаг растянулся бы вчетверо, и герой поехал бы по земле как на
## коньках. Считано от скорости: 4.2 клетки/с — это 134 px/с, шаг в рисунке
## около 17 px, значит на шаг отведено 0.13 с, то есть четыре кадра за 0.13 с
## при 60 кадрах в секунду (anim растёт на 2 за кадр) — это 3.8 единицы на
## кадр. Захочется бодрее или ленивее — крутится здесь, одним числом.
const SHEET_ANIM_DIV := {
	"walk": 3.8,
}

## Листы копки, нарисованные отдельно для копки вниз и для копки вбок.
## Ключ — общее имя набора, к нему приписывается "_down" или "_side".
const DIG_SHEETS := ["idle", "walk", "fall", "fly", "fly_jet",
		"fly_1", "fly_2", "fly_3", "fly_4",
		"dig_shovel", "dig_pick", "dig_pick_rusty",
		"dig_drill_down", "dig_drill_side", "dig_rig_down", "dig_rig_side"]

var player: Node = null

# Тряска стана: 3 пикселя вправо-влево (решение владельца) на 14 Гц.
const SHAKE_PIXELS := 3.0
const SHAKE_HZ := 14.0

var _sprite: Sprite2D
var _stun_flash: ColorRect
var _sheets: Dictionary = {}

## Уровень снаряжения, выставленный снаружи. -1 значит «не выставляли» — тогда
## уровень спрашивается у самого героя, см. _flight_tier().
var _tier_override: int = -1


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.scale = Vector2(1.0 / ART_SCALE, 1.0 / ART_SCALE)
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


## Задать уровень летающего снаряжения извне: 0 — снаряжения нет, 1..4 —
## уровни из магазина. Нужно и для теста, и для витрины: там герой показан в
## полёте на снаряжении, которого у него ещё нет.
func set_flight_tier(tier: int) -> void:
	_tier_override = clampi(tier, 0, FLY_SHEETS.size())


## Уровень снаряжения героя.
##
## Снаряжение переписывается в линейку из четырёх уровней, и новый метод
## flight_tier() у героя может появиться уже после этого файла. Пока его нет,
## уровень собирается из старых has_jetpack()/has_backpack(): джетпак это
## третий уровень линейки, ранец — первый. Ни того, ни другого — ноль.
func _flight_tier() -> int:
	if _tier_override >= 0:
		return _tier_override
	if player == null:
		return 0
	if player.has_method("flight_tier"):
		return clampi(int(player.flight_tier()), 0, FLY_SHEETS.size())
	if player.has_method("has_jetpack") and player.has_jetpack():
		return 3
	if player.has_method("has_backpack") and player.has_backpack():
		return 1
	return 0


## Имя ленты полёта. Новые ленты по уровням, а если их в сборке нет — старые
## fly/fly_jet, а если и тех нет — падение: герой всё равно в воздухе. Кадр из
## листа, которого нет, рисовать нечем, и лучше показать не тот полёт, чем
## уронить отрисовку.
func _fly_sheet_name() -> String:
	var tier: int = _flight_tier()
	var names: Array = []
	if tier > 0:
		names.append(FLY_SHEETS[tier - 1])
	names.append("fly_jet" if tier >= 3 else "fly")
	names.append("fall")
	for name: String in names:
		if _sheets.has(name):
			return name
	return String(names[0])


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
		# Все четыре уровня снаряжения выглядят по-разному, и по кадру должно
		# быть видно, на чём герой висит: пропеллер, большой винт, джетпак с
		# выхлопом или две ракеты. Тяга при этом своя — она из player.thrust.
		if player.thrust != "":
			sheet_name = _fly_sheet_name()
		else:
			sheet_name = "fall"
	else:
		sheet_name = "walk" if player.vx != 0.0 else "idle"

	var geom: Array = SHEET_FRAME.get(sheet_name, [CHAR_W, CHAR_H, GROUND_Y])
	var anim_div: float = SHEET_ANIM_DIV.get(sheet_name, ANIM_DIV)
	var fw: int = geom[0]
	var fh: int = geom[1]
	var tex: Texture2D = _sheets.get(sheet_name)
	if tex != null:
		_sprite.texture = tex
		var frames: int = maxi(1, int(round(tex.get_width() / float(fw))))
		var frame: int = int(floor(player.anim / anim_div)) % frames if frames > 1 else 0
		_sprite.region_rect = Rect2(frame * fw, 0, fw, fh)
	_sprite.flip_h = player.facing < 0
	# Линия земли листа должна лечь туда же, куда ложится подошва у кадра
	# 48×48, иначе высокий кадр повиснет над землёй.
	# Позиция — в логических точках, а текстура в ART_SCALE раз крупнее,
	# поэтому её размеры сюда попадают делёными.
	_sprite.position = Vector2(-fw / (2.0 * ART_SCALE) + _stun_shake(),
			-HH * TILE - 16.0 + float(GROUND_Y - int(geom[2])) / ART_SCALE)


## Стан показывается тряской, а не простоем: секунда без движения выглядит как
## зависшая игра, и игрок начинает давить на экран. Три пикселя вправо-влево
## на 14 Гц читаются как «отдало в руки», занимают ровно столько, сколько
## длится стан, и не двигают саму клетку — только рисунок героя.
func _stun_shake() -> float:
	if player.stun_until_msec <= 0.0:
		return 0.0
	var left: float = player.stun_until_msec - float(Time.get_ticks_msec())
	if left <= 0.0:
		return 0.0
	return signf(sin(left / 1000.0 * TAU * SHAKE_HZ)) * SHAKE_PIXELS

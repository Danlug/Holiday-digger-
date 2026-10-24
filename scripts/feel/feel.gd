class_name Feel
extends RefCounted
## Feel — точка входа ветки «aaa-feel»: числа ощущения (data/feel.json), общие
## формулы и подключение режиссёра одной строкой в main.gd (`Feel.attach(self)`).
## Правил ГДД здесь нет — только отклик: койот-время, буфер прыжка, упреждение
## камеры, трещины на породе, слияние «+N», карточка потерь.

const CONFIG_PATH := "res://data/feel.json"

static var _cfg: Dictionary = {}
static var _cfg_loaded: bool = false
static var _num_cache: Dictionary = {}   # путь → число: num() зовут каждый кадр, обход словаря с split() там лишний
static var _profile_cache: Dictionary = {}   # id инструмента → профиль ощущения (зовут каждый кадр копки)


static func config() -> Dictionary:
	if not _cfg_loaded:
		_cfg_loaded = true
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f != null:
			var raw = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(raw) == TYPE_DICTIONARY:
				_cfg = raw
	return _cfg


## Узел конфигурации по пути «раздел.ключ» (null, если нет).
static func node(path: String) -> Variant:
	var cur: Variant = config()
	for part in path.split("."):
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(part):
			return null
		cur = cur[part]
	return cur


## Число по пути; понимает и голое число, и {value, proposed, note}.
static func num(path: String, default: float) -> float:
	if _num_cache.has(path):
		return _num_cache[path]
	var out := default
	var n: Variant = node(path)
	if typeof(n) == TYPE_DICTIONARY:
		n = n.get("value", default)
	if typeof(n) == TYPE_INT or typeof(n) == TYPE_FLOAT:
		out = float(n)
	_num_cache[path] = out
	return out


## Сбросить кэш чисел (тесты, подменяющие config()).
static func clear_cache() -> void:
	_num_cache.clear()
	_profile_cache.clear()


static func flag(path: String, default: bool) -> bool:
	var n: Variant = node(path)
	if typeof(n) == TYPE_DICTIONARY:
		n = n.get("value", default)
	if typeof(n) == TYPE_BOOL:
		return n
	return default


## Профиль ощущения инструмента (частота ударов, высота и громкость звука,
## микро-тряска). Лопата → мягко и редко, кирка → резко, бур → дробь, бурмобиль →
## низкий гул. Неизвестный инструмент → кирка.
static func tool_profile(tool_id: String) -> Dictionary:
	if _profile_cache.has(tool_id):
		return _profile_cache[tool_id]
	var key := "pickaxe"
	if tool_id == "shovel":
		key = "shovel"
	elif tool_id == "hand_drill":
		key = "hand_drill"
	elif tool_id == "drill_rig":
		key = "drill_rig"
	var p: Variant = node("dig.tool." + key)
	var out := {"hit_period_s": 0.38, "pitch": 1.0, "db": -7.0, "micro_shake": 0.0}
	if typeof(p) == TYPE_DICTIONARY:
		for k in out.keys():
			if p.has(k):
				out[k] = float(p[k])
	_profile_cache[tool_id] = out
	return out


## Секунд между ударами по породе, пока идёт копка текущим инструментом.
static func hit_period(tool_id: String) -> float:
	return maxf(0.06, float(tool_profile(tool_id)["hit_period_s"]))


## Породы, у которых разрушение «весит»: камень и твёрдое глубже фундамента (тот
## же список, по которому JuiceDirector трясёт экран). Земля, торф и мягкая руда
## паузы не получают — их копают подряд сотнями.
const WEIGHTY_TILES := [
	TileTypes.Type.STONE, TileTypes.Type.FOUNDATION, TileTypes.Type.REINFORCED,
	TileTypes.Type.OBSIDIAN, TileTypes.Type.ANCIENT_METAL, TileTypes.Type.HELLSTONE,
	TileTypes.Type.DARK_MATTER, TileTypes.Type.UNIVERSALIUM, TileTypes.Type.ANGEL_STONE,
	TileTypes.Type.DIVINE_HEART, TileTypes.Type.GEOCRYSTAL,
]


## Длина микро-паузы после разрушения клетки, секунд. 0 — паузы нет: быстрая
## порода (бур, бурмобиль, земля) не получает её вовсе. Пауза не длиннее доли
## времени самой клетки, поэтому на темп копки она не влияет (см. кредит в Player).
static func hitstop_for(total_dig_s: float) -> float:
	if Settings.reduce_motion:
		return 0.0
	if total_dig_s < num("dig.hitstop_min_total_s", 0.9):
		return 0.0
	return minf(num("dig.hitstop_s", 0.045), total_dig_s * num("dig.hitstop_share", 0.04))


## Горизонтальная ось клавиатуры. Обе клавиши зажаты — идёт та, что нажата
## позже (`last`: -1 влево, +1 вправо, 0 неизвестно): при смене направления
## игрок почти всегда нажимает новую клавишу, не успев отпустить старую, и
## «обе гасят друг друга» превращало разворот в остановку на пару кадров.
static func axis(left: bool, right: bool, last: int) -> int:
	if left and right:
		if not flag("controls.key_last_wins", true):
			return 0
		return last
	return -1 if left else (1 if right else 0)


## Порог «момента»: дорогая находка, а не повседневная руда.
static func is_epic_price(price: int) -> bool:
	return float(price) >= num("loot.epic_price", 500.0)


## Куда класть наезд камеры: статическая очередь, которую подбирает CameraRig в
## следующем кадре. Статика — число, не Callable (гигиена статик, GDD §19).
static var pending_punch: float = 0.0

## Карточка потерь будет показана после этого респавна — тост «Ты погиб…» в main.gd
## в этом случае лишний (то же самое, но абзацем). Число/флаг, не Callable.
static var card_pending: bool = false


static func punch(amount: float) -> void:
	if Settings.reduce_motion or amount <= 0.0:
		return
	pending_punch = minf(pending_punch + amount, num("camera.punch_max", 0.07))


## Подключает режиссёра «ощущения» к корню игры. Повторный вызов ничего не
## удваивает.
static func attach(host: Node) -> Node:
	var old := host.get_node_or_null("FeelDirector")
	if old != null:
		return old
	var d := FeelDirector.new()
	d.name = "FeelDirector"
	host.add_child(d)
	return d

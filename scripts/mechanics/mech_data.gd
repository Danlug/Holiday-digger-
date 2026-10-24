class_name MechData
extends RefCounted
## Числа механик раунда 3 (data/mechanics.json, всё proposed): тайники, азарт и
## мастерство. Понимает и голое число, и обёртку {value, proposed, note}.

const PATH := "res://data/mechanics.json"

static var _cfg: Dictionary = {}
static var _loaded: bool = false


static func config() -> Dictionary:
	if not _loaded:
		_loaded = true
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var raw = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(raw) == TYPE_DICTIONARY:
				_cfg = raw
	return _cfg


## Тестам: подменить конфиг (null — перечитать файл).
static func override(cfg) -> void:
	if cfg == null:
		_loaded = false
		_cfg = {}
	else:
		_loaded = true
		_cfg = cfg


static func section(name: String) -> Dictionary:
	var s = config().get(name, {})
	return s if typeof(s) == TYPE_DICTIONARY else {}


static func value(node, default = null):
	if typeof(node) == TYPE_DICTIONARY:
		return node.get("value", default)
	return default if node == null else node


static func num(sec: String, key: String, default: float) -> float:
	var v = value(section(sec).get(key, null), default)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v)
	return default


static func arr(sec: String, key: String, default: Array = []) -> Array:
	var v = value(section(sec).get(key, null), default)
	return v if typeof(v) == TYPE_ARRAY else default


## Механики включаются после онбординга — тот же порог, что у подсказок (ГДД §16):
## обучение §9 не перебивается ни сундуком, ни шкалой.
static func gate_open() -> bool:
	return HintBusy.onboarding_done()

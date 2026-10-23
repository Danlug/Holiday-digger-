class_name CountLabel
extends Label
## CountLabel — число с анимацией «накрутки» (как счётчик монет в мобильных
## играх): значение быстро докручивается до нового, при приходе число
## вспыхивает и подпрыгивает, при трате на миг краснеет.
##
##   var c := CountLabel.new()
##   c.set_value(1250, true)   # true — без анимации (первая установка)
##   c.set_value(1300)         # накрутка 1250 -> 1300
##
## Длинные числа не вылезают за плитку: до 10 млн — с пробелами между
## разрядами («1 250 000»), дальше — сокращение «12,3M», «1,2B». Точное
## значение остаётся в подсказке — его берут через exact_text().

const ROLL_TIME := 0.55
const MAX_FULL := 9_999_999

var base_color: Color = Color.WHITE:
	set(v):
		base_color = v
		add_theme_color_override("font_color", v)
var gain_color: Color = Color(1, 0.95, 0.7)
var loss_color: Color = Color(1.0, 0.55, 0.5)

var _target: int = 0
var _shown: float = 0.0
var _from: float = 0.0
var _elapsed: float = 0.0
var _tint: float = 0.0       # 1 = приход, -1 = трата, гаснет к 0


func _init() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text = "0"
	set_process(false)


func value() -> int:
	return _target


func exact_text() -> String:
	return group_digits(_target)


func set_value(v: int, instant: bool = false) -> void:
	if v == _target and _elapsed >= ROLL_TIME:
		return
	var prev := _target
	_target = v
	if instant or Settings.reduce_motion or not is_inside_tree():
		_shown = float(v)
		_tint = 0.0
		_elapsed = ROLL_TIME
		_refresh()
		set_process(false)
		return
	_from = _shown
	_elapsed = 0.0
	if v > prev:
		_tint = 1.0
		UiAnim.pulse(self, 0.16, 0.24)
	elif v < prev:
		_tint = -1.0
	set_process(true)


func _process(dt: float) -> void:
	_elapsed += dt
	var k := clampf(_elapsed / ROLL_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	_shown = lerpf(_from, float(_target), e)
	if absf(_tint) > 0.0:
		_tint = move_toward(_tint, 0.0, dt * 2.2)
	_refresh()
	var c := base_color
	if _tint > 0.0:
		c = base_color.lerp(gain_color, _tint)
	elif _tint < 0.0:
		c = base_color.lerp(loss_color, -_tint)
	add_theme_color_override("font_color", c)
	if k >= 1.0 and _tint == 0.0:
		_shown = float(_target)
		_refresh()
		add_theme_color_override("font_color", base_color)
		set_process(false)


func _refresh() -> void:
	text = short_text(int(round(_shown)))


static func group_digits(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out    # обычный пробел: узкого U+202F в шрифте темы нет
	return ("-" if n < 0 else "") + out


static func short_text(n: int) -> String:
	var a := absi(n)
	if a <= MAX_FULL:
		return group_digits(n)
	var sign := "-" if n < 0 else ""
	if a < 1_000_000_000:
		return sign + _one_decimal(float(a) / 1_000_000.0) + "M"
	return sign + _one_decimal(float(a) / 1_000_000_000.0) + "B"


static func _one_decimal(x: float) -> String:
	var s := "%.1f" % x
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return s.replace(".", ",")

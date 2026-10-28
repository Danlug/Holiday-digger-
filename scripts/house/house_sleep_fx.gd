class_name HouseSleepFx
extends Control
## HouseSleepFx — сон как короткий ролик (ГДД п.7: «спит быстро, буквально 10
## секунд, показывая анимацию»): экран темнеет, поверх авторской анимации спящего
## летят «Z», вверху бежит время (значок солнца/месяца, часы, номер дня), а к
## концу взлетает рассвет и затемнение уходит.
##
## Часы здесь ТОЛЬКО картинка: они плавно прокручиваются от текущего часа на
## длину сна, а настоящий сдвиг GameState.game_clock_hours делает
## HouseSleep.sleep_now() по концу ролика — к этому моменту циферблат уже
## показывает тот же час. Окна света/тьмы берутся из DayCycle (DUSK_START,
## NIGHT_START, DAWN_START, DAWN_END), своих правил у ролика нет.
##
## Кнопка «пропустить сон за ролик» (ГДД п.15, лимит skip_sleep_at_home в день)
## показывается только когда её просит дом (skippable); сам лимит и сам пропуск
## решает дом, здесь — значок со счётчиком «осталось сегодня» и сигнал.

signal skip_requested

const SHEET := "res://art/anim/sleep_sheet.png"
const SHEET_META := "res://art/anim/sleep_sheet.json"
const STATIC_POSE := "res://art/character/sleep.png"

const Z_PERIOD := 0.75
const Z_MAX := 5
const FADE_IN := 0.6
## Доля ролика, на которую приходится рассвет и уход затемнения.
const DAWN_PART := 0.2

## Рассвет рисуется крупно (24-пиксельный значок ×4), на месте уходящего спящего.
const DAWN_PX := 96.0

const NIGHT := Color(0.02, 0.03, 0.09)
const DAY := Color(0.30, 0.20, 0.12)

var _shade: ColorRect
var _sprite: TextureRect
var _zs: Control
var _pill: Control
var _icon: TextureRect
var _time: Label
var _day: Label
var _bar_fill: ColorRect
var _dawn: TextureRect
var _dawn_glow: TextureRect
var _skip: Button
var _lock: TextureRect

var _sheet: Texture2D
var _meta: Dictionary = {}
var _static: Texture2D

var _playing := false
var _t := 0.0
var _total := 10.0
var _hours := 0.0
var _start_total := 0.0
var _z_t := 0.0
var _z_flip := false
var _skippable := false
var _end_is_day := true
var _icon_is_day := true
var _fade: Tween


func _init() -> void:
	name = "SleepFx"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.color = NIGHT
	add_child(_shade)

	_dawn_glow = ShopArt.rect(ShopArt.tex("glow"), Vector2.ZERO, Vector2(180, 180))
	_dawn_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_dawn_glow.modulate = Color(1, 0.85, 0.45, 0.0)
	add_child(_dawn_glow)

	# Кадр авторской анимации — 224×258 на всю ширину; вписываем с сохранением
	# пропорций, чтобы на другом экране он ужался, а не обрезался.
	_sprite = TextureRect.new()
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.anchor_right = 1.0
	_sprite.anchor_top = 0.5
	_sprite.anchor_bottom = 0.5
	_sprite.offset_top = -140
	_sprite.offset_bottom = 120
	add_child(_sprite)

	_dawn = ShopArt.rect(HouseArt.tex("sun"), Vector2.ZERO, Vector2(DAWN_PX, DAWN_PX))
	_dawn.modulate.a = 0.0
	add_child(_dawn)

	_zs = Control.new()
	_zs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zs.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_zs)

	_build_clock()
	_build_skip()

	if ResourceLoader.exists(SHEET):
		_sheet = load(SHEET)
		_meta = HouseRoomsConfig.read_json(SHEET_META)
	elif ResourceLoader.exists(STATIC_POSE):
		_static = load(STATIC_POSE)


func _build_clock() -> void:
	_pill = Control.new()
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.anchor_left = 0.5
	_pill.anchor_right = 0.5
	_pill.offset_left = -62
	_pill.offset_right = 62
	_pill.offset_top = 16
	_pill.offset_bottom = 54
	add_child(_pill)
	_pill.add_child(HouseArt.nine("pill", 4, Color.WHITE, Vector2(124, 38)))
	_icon = ShopArt.rect(HouseArt.tex("sun"), Vector2(8, 7), Vector2(24, 24))
	_pill.add_child(_icon)
	_time = ShopArt.label("06:00", UiTheme.FS_HERO, Color.WHITE, HouseArt.INK, 4)
	_time.position = Vector2(36, 7)
	_pill.add_child(_time)
	_pill.add_child(ShopArt.rect(HouseArt.tex("calendar"), Vector2(92, 11), Vector2(16, 16)))
	_day = ShopArt.label("1", UiTheme.FS_LABEL, HouseArt.GOLD_BRIGHT, HouseArt.INK, 3)
	_day.position = Vector2(108, 11)
	_pill.add_child(_day)
	var track := ColorRect.new()
	track.color = Color(0, 0, 0, 0.55)
	track.position = Vector2(14, 34)
	track.size = Vector2(96, 3)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(track)
	_bar_fill = ColorRect.new()
	_bar_fill.color = HouseArt.GOLD
	_bar_fill.position = Vector2(14, 34)
	_bar_fill.size = Vector2(0, 3)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(_bar_fill)


func _build_skip() -> void:
	_skip = HouseArt.button("gold", HouseArt.tex("skip_sleep"), Vector2(72, 40), 24.0)
	_skip.name = "Skip"
	_skip.anchor_left = 0.5
	_skip.anchor_right = 0.5
	_skip.anchor_top = 1.0
	_skip.anchor_bottom = 1.0
	_skip.offset_left = -36
	_skip.offset_right = 36
	_skip.offset_top = -64
	_skip.offset_bottom = -24
	_skip.pressed.connect(_on_skip_pressed)
	_skip.visible = false
	add_child(_skip)
	_lock = ShopArt.rect(ShopArt.tex("glyph_lock"), Vector2(46, 22), Vector2(16, 16))
	_lock.visible = false
	_skip.add_child(_lock)


## hours — длина сна в игровых часах (0 — сон без часов, из сюжета).
func play(seconds: float, hours: float = 0.0, skippable: bool = false) -> void:
	if _fade != null:
		_fade.kill()
	_playing = true
	_t = 0.0
	_total = maxf(0.1, seconds)
	_hours = hours
	_skippable = skippable and hours > 0.0
	_z_t = Z_PERIOD
	_start_total = 6.0 + GameState.game_clock_hours
	_end_is_day = _is_day(fmod(_start_total + _hours, 24.0))
	_dawn.texture = HouseArt.tex("sun" if _end_is_day else "moon")
	_pill.visible = hours > 0.0
	_skip.visible = _skippable
	_clear_zs()
	modulate.a = 1.0
	visible = true
	if _skippable:
		refresh_skip()
	_apply(0.0)
	_update_frame()


func stop() -> void:
	_playing = false
	if not visible:
		return
	if Settings.reduce_motion or not is_inside_tree():
		visible = false
		return
	# Затемнение уходит за четверть секунды, а не обрывается: эффект сна на
	# комнате уже применён, и игрок видит, как она «просыпается».
	if _fade != null:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.25)
	_fade.tween_callback(func() -> void:
		# Новый ролик мог начаться, пока старый гас: тогда не трогаем.
		if not _playing:
			visible = false
			modulate.a = 1.0)


func is_playing() -> bool:
	return _playing


## Для снимков экрана: поставить ролик на долю p (0..1).
func debug_progress(p: float) -> void:
	_t = clampf(p, 0.0, 1.0) * _total
	_apply(clampf(p, 0.0, 1.0))
	_update_frame()


func refresh_skip() -> void:
	var left := skips_left()
	_skip.disabled = left <= 0
	_lock.visible = left <= 0
	UiBtn.set_badge(_skip, left)
	var extra := "Осталось сегодня: %d из %d" % [left, Balance.get_ad_daily_limit(HouseSystem.SKIP_SLEEP_AD)]
	if left > 0:
		Tip.bind(_skip, "Проснуться сразу", "Посмотри ролик — сон закончится мгновенно.", extra)
	else:
		Tip.bind(_skip, "Проснуться сразу", "На сегодня роликов не осталось: завтра снова будут.", extra)


static func skips_left() -> int:
	return maxi(0, Balance.get_ad_daily_limit(HouseSystem.SKIP_SLEEP_AD) \
		- GameState.get_ad_uses_today(HouseSystem.SKIP_SLEEP_AD))


func _on_skip_pressed() -> void:
	if Tip.swallowed():
		return
	skip_requested.emit()


func _process(delta: float) -> void:
	if not visible or not _playing:
		return
	_t = minf(_t + delta, _total)
	_apply(_t / _total)
	_update_frame()
	if not Settings.reduce_motion:
		_z_t += delta
		if _z_t >= Z_PERIOD:
			_z_t = 0.0
			_spawn_z()


## Всё, что зависит от доли ролика p: затемнение, часы, рассвет.
func _apply(p: float) -> void:
	var hour_total := _start_total + _hours * p
	var hour := fmod(hour_total, 24.0)
	var phase := _night_phase(hour)

	var tint := NIGHT.lerp(DAY, 1.0 - phase)
	var alpha := lerpf(0.55, 0.92, phase)
	var fade_in := clampf(p * _total / FADE_IN, 0.0, 1.0)
	var dawn_t := clampf((p - (1.0 - DAWN_PART)) / DAWN_PART, 0.0, 1.0)
	_shade.color = Color(tint.r, tint.g, tint.b, alpha * fade_in * (1.0 - dawn_t * dawn_t))

	if _hours > 0.0:
		var h := int(hour)
		var m := int((hour - floorf(hour)) * 60.0)
		_time.text = "%02d:%02d" % [h, m]
		_day.text = str(int(floorf(hour_total / 24.0)) + 1)
		var is_day := _is_day(hour)
		if is_day != _icon_is_day:
			_icon_is_day = is_day
			_icon.texture = HouseArt.tex("sun" if is_day else "moon")
			UiAnim.pulse(_icon, 0.3, 0.3)
		_bar_fill.size.x = 96.0 * p

	# Спящий появляется вместе с затемнением и уходит на рассвете, а на его
	# месте всплывает солнце (или месяц) с тёплым ореолом.
	_sprite.modulate.a = fade_in * (1.0 - smoothstep(0.0, 1.0, clampf(dawn_t * 1.6, 0.0, 1.0)))
	var rise := smoothstep(0.0, 1.0, clampf((dawn_t - 0.25) / 0.75, 0.0, 1.0))
	var w := size.x if size.x > 0.0 else 224.0
	var h_screen := size.y if size.y > 0.0 else 480.0
	_dawn.position = Vector2((w - DAWN_PX) * 0.5, lerpf(h_screen * 0.82, h_screen * 0.40, rise))
	_dawn.modulate.a = rise if _hours > 0.0 else 0.0
	_dawn_glow.size = Vector2(w, w)
	_dawn_glow.position = _dawn.position + Vector2(DAWN_PX, DAWN_PX) * 0.5 - _dawn_glow.size * 0.5
	_dawn_glow.modulate.a = (0.8 * rise * (1.0 - clampf((dawn_t - 0.9) / 0.1, 0.0, 1.0))) if _hours > 0.0 else 0.0
	if _end_is_day:
		_dawn_glow.modulate = Color(1, 0.85, 0.45, _dawn_glow.modulate.a)
	else:
		_dawn_glow.modulate = Color(0.6, 0.7, 1.0, _dawn_glow.modulate.a)


## 1 глубокой ночью, 0 днём: те же окна, что у неба (DayCycle).
static func _night_phase(hour: float) -> float:
	if hour >= DayCycle.NIGHT_START or hour < DayCycle.DAWN_START:
		return 1.0
	if hour >= DayCycle.DUSK_START:
		return (hour - DayCycle.DUSK_START) / (DayCycle.NIGHT_START - DayCycle.DUSK_START)
	if hour >= DayCycle.DAWN_START and hour < DayCycle.DAWN_END:
		return 1.0 - (hour - DayCycle.DAWN_START) / (DayCycle.DAWN_END - DayCycle.DAWN_START)
	return 0.0


static func _is_day(hour: float) -> bool:
	return hour >= DayCycle.SUN_START and hour < DayCycle.SUN_END


# ---------------------------------------------------------------------------
# «Z» и кадр спящего
# ---------------------------------------------------------------------------

func _clear_zs() -> void:
	for c in _zs.get_children():
		c.queue_free()


func _spawn_z() -> void:
	while _zs.get_child_count() >= Z_MAX:
		var old := _zs.get_child(0)
		_zs.remove_child(old)
		old.queue_free()
	_z_flip = not _z_flip
	var big := _z_flip
	var z := ShopArt.rect(HouseArt.tex("z_big" if big else "z_small"), Vector2.ZERO,
		Vector2(13, 13) if big else Vector2(9, 9))
	z.modulate = Color(0.75, 0.85, 1.0, 0.0)
	var h_screen := size.y if size.y > 0.0 else 480.0
	var w := size.x if size.x > 0.0 else 224.0
	# Из-за подушки у правого плеча: там же нарисованы мелкие «zz» авторской анимации.
	var from := Vector2(w * 0.74 + randf_range(0.0, 10.0), h_screen * 0.5 - 28.0)
	z.position = from
	z.scale = Vector2(1.6, 1.6) if big else Vector2.ONE
	_zs.add_child(z)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(z, "position", from + Vector2(randf_range(4.0, 14.0), -78.0), 2.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(z, "modulate:a", 0.95, 0.4)
	tw.chain().tween_property(z, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(z.queue_free)


func _update_frame() -> void:
	if _sheet != null:
		var fw: int = int(_meta.get("frame_width", 48))
		var fh: int = int(_meta.get("frame_height", 48))
		var frames: int = maxi(1, int(_meta.get("frames", 1)))
		var fps: float = maxf(0.1, float(_meta.get("fps", 4.0)))
		var idx: int = int(_t * fps) % frames
		var atlas := AtlasTexture.new()
		atlas.atlas = _sheet
		atlas.region = Rect2(idx * fw, 0, fw, fh)
		_sprite.texture = atlas
	elif _static != null:
		_sprite.texture = _static
	else:
		_sprite.texture = null

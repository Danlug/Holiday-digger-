class_name SplashScreen
extends CanvasLayer
## Заставка старта (product-polish): логотип на тёмном фоне поверх всего, пока сцена
## собирается и грузит сейв, затем плавное проявление игры. Продолжает системную
## заставку из project.godot (boot_splash: та же картинка art/ui/brand/boot_splash.png,
## тот же фон и место логотипа), поэтому запуск выглядит одним кадром: логотип → игра,
## без голого экрана и без мигания HUD в первом кадре.
##
## Где её нет: в вебе логотип, загрузку и «нажмите, чтобы играть» уже показала оболочка
## (web/shell.src.html), и тёмный кадр под её проявлением выглядел бы провалом; тесты и бот
## поднимают main.tscn дочерней сценой — attach ставит заставку только главной сцене процесса
## (force — для снимков tests/test_screenshot_splash). Headless — тоже без неё.
##
## Статика _booted переживает перезагрузку сцены намеренно: сброс игры (reload_current_scene)
## показывает не логотип на секунду, а только короткое проявление.

const LOGO := "res://art/ui/brand/logo.png"
const BG := Color8(0x0D, 0x0A, 0x07)      # фон страницы веб-оболочки и boot_splash.png
const HOLD_FIRST := 0.7     # ПРЕДЛОЖЕНО: сколько держать логотип при первом запуске процесса
const HOLD_AGAIN := 0.15    # перезапуск сцены (сброс игры): только проявление
const FADE := 0.45
const FADE_REDUCED := 0.15  # «меньше движения»
const LOGO_SCALE := 2       # 96x68 → 192x136 во вьюпорте 224 (boot_splash.png: x4 в 448)
const LOGO_Y := 0.42        # центр логотипа по высоте экрана — как в tools/gen_app_brand.py
const BAR_W := 100.0
const BAR_H := 5.0

static var _booted := false

var _root: Control
var _bg: ColorRect
var _logo: TextureRect
var _well: ColorRect
var _fill: ColorRect
var _hold := HOLD_FIRST
var _elapsed := 0.0
var _fading := false


static func attach(host: Node, force: bool = false) -> SplashScreen:
	var tree := host.get_tree()
	if tree == null or DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return null
	if not force and tree.current_scene != host:
		return null
	var s := SplashScreen.new()
	s.name = "Splash"
	s.layer = UiLayers.SPLASH
	s._hold = HOLD_AGAIN if _booted else HOLD_FIRST
	_booted = true
	host.add_child(s)
	return s


## Сколько заставка ещё закрывает экран (с проявлением) — для тестов и снимков.
func seconds_left() -> float:
	return maxf(0.0, _hold - _elapsed) + (FADE_REDUCED if Settings.reduce_motion else FADE)


func _ready() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # первый тап не должен копнуть под заставкой
	add_child(_root)

	_bg = ColorRect.new()
	_bg.color = BG
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg)

	_logo = TextureRect.new()
	if ResourceLoader.exists(LOGO):
		_logo.texture = load(LOGO)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_logo)

	# Полоска под логотипом: «идёт загрузка», а не замерший кадр. Канавка и золотая заливка —
	# те же цвета, что у полосок HUD, без рамки: заставка — не окно.
	_well = ColorRect.new()
	_well.color = UiTheme.INSET
	_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_well)
	_fill = ColorRect.new()
	_fill.color = UiTheme.GOLD
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_well.add_child(_fill)

	get_viewport().size_changed.connect(_layout)
	_layout()
	set_process(true)


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_root.position = Vector2.ZERO
	_root.size = vp
	_bg.position = Vector2.ZERO
	_bg.size = vp
	var tex_size := _logo.texture.get_size() if _logo.texture != null else Vector2(96, 68)
	var logo_size := tex_size * LOGO_SCALE
	_logo.size = logo_size
	_logo.position = Vector2(roundf((vp.x - logo_size.x) * 0.5), roundf(vp.y * LOGO_Y - logo_size.y * 0.5))
	_well.size = Vector2(BAR_W, BAR_H)
	_well.position = Vector2(roundf((vp.x - BAR_W) * 0.5), _logo.position.y + logo_size.y + 18.0)
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(_fill.size.x, BAR_H)


func _process(delta: float) -> void:
	if _fading:
		return
	_elapsed += minf(delta, 0.05)   # первый кадр после загрузки сцены длинный — не проматываем
	var k := clampf(_elapsed / maxf(_hold, 0.001), 0.0, 1.0)
	_fill.size = Vector2(roundf(BAR_W * k), BAR_H)
	if _elapsed >= _hold:
		_fade_out()


func _fade_out() -> void:
	_fading = true
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # игра уже под пальцем, пока заставка тает
	var dur := FADE_REDUCED if Settings.reduce_motion else FADE
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)

class_name HudSafeArea
extends RefCounted
## Верхний отступ безопасной зоны телефона (вырез камеры, «чёлка», статус-бар) в
## проектных единицах вьюпорта: на него опускаются верхние кластеры HUD — портрет
## слева и кошелёк справа (а за ними весь левый столбик, см. HudAnchors.left_column_bottom).
##
## Считается только в родных сборках Android/iOS: окно там во весь экран (immersive),
## и вырез лежит поверх игры. В веб-сборке колонку игры уже отодвигает от выреза
## оболочка (web/shell.html: padding env(safe-area-inset-*)), на компьютере выреза нет.

## Тесты и снимки: смоделировать вырез такой высоты (единицы вьюпорта). < 0 — настоящий.
static var debug_top: float = -1.0
## То же для нижней зоны (полоска «домой» на iPhone).
static var debug_bottom: float = -1.0


static func top(vp: Viewport) -> float:
	if debug_top >= 0.0:
		return debug_top
	if vp == null or not (OS.has_feature("android") or OS.has_feature("ios")):
		return 0.0
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var inset_px := float(safe.position.y - DisplayServer.window_get_position().y)
	if safe.size.y <= 0 or inset_px <= 0.0:
		return 0.0
	var vp_h := vp.get_visible_rect().size.y
	# Не больше пятой части экрана: кривой ответ системы не должен увезти HUD в середину.
	return clampf(ceilf(inset_px * vp_h / float(win.y)), 0.0, vp_h * 0.2)


## Нижний отступ безопасной зоны (полоска «домой») в единицах вьюпорта: над ним
## встают нижние панели и кнопки полноэкранных окон. На компьютере и в вебе — 0.
static func bottom(vp: Viewport) -> float:
	if debug_bottom >= 0.0:
		return debug_bottom
	if vp == null or not (OS.has_feature("android") or OS.has_feature("ios")):
		return 0.0
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var inset_px := float(DisplayServer.window_get_position().y + win.y - safe.end.y)
	if safe.size.y <= 0 or inset_px <= 0.0:
		return 0.0
	var vp_h := vp.get_visible_rect().size.y
	return clampf(ceilf(inset_px * vp_h / float(win.y)), 0.0, vp_h * 0.1)

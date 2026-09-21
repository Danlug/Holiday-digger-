extends Node
## test_backdrop — подложки за домом/огородом (scripts/world/backdrop.gd):
## файлы на месте и нужных размеров, era переключает текстуру забора,
## параллакс горы действительно медленнее камеры.
##
## Запуск: godot --headless --path . res://tests/test_backdrop.tscn

var failures := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_backdrop ===")
	for _i in range(6):
		await get_tree().process_frame

	_check_textures()
	_check_era()
	_check_parallax()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check_textures() -> void:
	var fence_now := load("res://art/env/backdrop_fence_white.png") as Texture2D
	var fence_old := load("res://art/env/backdrop_fence_old.png") as Texture2D
	var mountain := load("res://art/env/backdrop_mountain.png") as Texture2D

	check("backdrop_fence_white.png существует", fence_now != null)
	check("backdrop_fence_old.png существует", fence_old != null)
	check("backdrop_mountain.png существует", mountain != null)

	if fence_now != null:
		check("забор (сейчас): 960×192 текстурных px (2 клетки высоты, ART_SCALE=3)",
			fence_now.get_size() == Vector2(960, 192))
	if fence_old != null:
		check("забор (дед): 960×192 текстурных px", fence_old.get_size() == Vector2(960, 192))
	if mountain != null:
		check("гора: 2400×480 текстурных px (5 клеток высоты)",
			mountain.get_size() == Vector2(2400, 480))
		var img := mountain.get_image()
		img.convert(Image.FORMAT_RGBA8)
		var top_alpha := 0
		for x in range(0, img.get_width(), 37):
			top_alpha += img.get_pixel(x, 0).a8
		check("гора: верхняя строка прозрачна (небо вырезано)", top_alpha == 0)


func _check_era() -> void:
	# Ищем через Main.backdrop, а не по имени: в дереве есть и другой узел
	# «Backdrop» (ColorRect катсцены), и find_child натыкается на него первым.
	var backdrop := _live_backdrop()
	check("узел Backdrop найден в живой сцене", backdrop != null)
	if backdrop == null:
		return

	check("era по умолчанию 'now'", backdrop.era == "now")
	var tex_now := backdrop._fence_texture()

	backdrop.set_era("grandpa")
	check("set_era('grandpa') меняет era", backdrop.era == "grandpa")
	var tex_grandpa := backdrop._fence_texture()
	check("set_era('grandpa') меняет текстуру забора на старую",
		tex_grandpa != null and tex_now != null and tex_grandpa != tex_now)

	backdrop.set_era("now")
	check("set_era('now') возвращает белый забор", backdrop._fence_texture() == tex_now)


func _check_parallax() -> void:
	var backdrop := _live_backdrop()
	if backdrop == null:
		check("параллакс горы проверен (узел Backdrop не найден)", false)
		return

	backdrop.update(Vector2(0, 0))
	var x0: float = backdrop._mountain_layer.position.x

	# Сдвиг камеры на 320 px (10 клеток) — как просит задание.
	var shift_px := 320.0
	var shift_cells := shift_px / Backdrop.TILE
	backdrop.update(Vector2(shift_cells, 0))
	var x1: float = backdrop._mountain_layer.position.x

	var moved: float = x1 - x0
	var expected: float = (1.0 - Backdrop.MOUNTAIN_PARALLAX_X) * shift_px
	check("гора при сдвиге камеры на 320px компенсирует движение на (1-k)*320 (движение слоя=%.1f, ожидание=%.1f)" %
		[moved, expected], absf(moved - expected) < 0.5)

	# Итоговое смещение НА ЭКРАНЕ (после вычета сдвига view_root) — k*320.
	var screen_shift: float = shift_px - moved
	var expected_screen: float = Backdrop.MOUNTAIN_PARALLAX_X * shift_px
	check("гора на экране сдвигается на k*320 (k=%.2f): смещение=%.1f, ожидание=%.1f" %
		[Backdrop.MOUNTAIN_PARALLAX_X, screen_shift, expected_screen],
		absf(screen_shift - expected_screen) < 0.5)

	# Забор едет 1:1 с миром — сам слой не компенсирует ничего.
	check("забор не компенсирует сдвиг камеры (едет 1:1 вместе с миром)",
		backdrop._fence_layer.position == Vector2.ZERO)

	# Скрытие фона глубоко под землёй.
	backdrop.update(Vector2(0, 0))
	check("фон виден у поверхности (cam.y=0)", backdrop.visible)
	backdrop.update(Vector2(0, Backdrop.HIDE_BELOW_CAMERA_Y + 1.0))
	check("фон прячется глубоко под землёй (cam.y > порога)", not backdrop.visible)
	backdrop.update(Vector2(0, 0))


func _live_backdrop() -> Backdrop:
	var main := get_node_or_null("Main")
	if main == null:
		return null
	return main.get("backdrop") as Backdrop

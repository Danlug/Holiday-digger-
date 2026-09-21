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
	# Await ОБЯЗАТЕЛЕН: функция ниже сама ждёт кадр движка (см. её тело) —
	# без await она бы отпустилась "в фоне" и _ready() допечатал бы "Итог"
	# раньше её проверок (тот же капкан, что описан в tests/test_day_cycle.gd).
	await _check_sky_and_clouds_geometry()

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

	# В новой игре сразу играет интро деда на живой карте (режим world,
	# см. cutscene_player.gd) и переводит задник в эпоху «grandpa»; вне
	# сцены задник должен быть «now». Проверяем связку, а не «по умолчанию».
	var cs := get_tree().root.find_child("CutscenePlayer", true, false)
	var intro_on: bool = cs != null and cs.is_playing and String(cs.scene_id) == "intro_grandpa"
	check("era задника согласована с интро деда (%s)" % ("идёт" if intro_on else "нет"),
		backdrop.era == ("grandpa" if intro_on else "now"))
	backdrop.set_era("now")
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


## Небо (SkyView._celestial) и облака (CloudsView) — задание владельца:
## "ширина неба на 10% шире горы, на 10% меньше параллакс, чем гора";
## "облака — ширина на 10% уже горы, параллакс на 10% больше, чем у горы";
## небо ЗАКРЕПЛЕНО по высоте, как гора (полная компенсация Y), облака — нет
## (см. шапки scripts/world/sky_view.gd и scripts/world/clouds_view.gd).
func _check_sky_and_clouds_geometry() -> void:
	check("ширина неба = 1.1 × ширина горы",
		absf(SkyView.SKY_W_LOGICAL - Backdrop.MOUNTAIN_W_LOGICAL * 1.1) < 0.01)
	check("параллакс неба = 0.9 × параллакс горы",
		absf(SkyView.SKY_PARALLAX_X - Backdrop.MOUNTAIN_PARALLAX_X * 0.9) < 0.0001)
	check("ширина облаков = 0.9 × ширина горы",
		absf(CloudsView.CLOUDS_W_LOGICAL - Backdrop.MOUNTAIN_W_LOGICAL * 0.9) < 0.01)
	check("параллакс облаков = 1.1 × параллакс горы",
		absf(CloudsView.CLOUDS_PARALLAX_X - Backdrop.MOUNTAIN_PARALLAX_X * 1.1) < 0.0001)
	check("небо едет медленнее горы, облака — быстрее (0 < небо < гора < облака < 1)",
		0.0 < SkyView.SKY_PARALLAX_X and SkyView.SKY_PARALLAX_X < Backdrop.MOUNTAIN_PARALLAX_X
		and Backdrop.MOUNTAIN_PARALLAX_X < CloudsView.CLOUDS_PARALLAX_X and CloudsView.CLOUDS_PARALLAX_X < 1.0)

	var sky := preload("res://scripts/world/sky_view.gd").new()
	add_child(sky)
	await get_tree().process_frame
	var celestial: Node2D = sky.get("_celestial")
	check("у SkyView есть слой _celestial (солнце/месяц/звёзды)", celestial != null)
	if celestial != null:
		sky.set_camera(Vector2(0, 0), 7)
		var y0: float = celestial.position.y
		var x0: float = celestial.position.x
		# Сдвиг камеры и по X, и по Y — как гора, небо гасит Y ПОЛНОСТЬЮ
		# (слой не едет по вертикали) и X — c долей SKY_PARALLAX_X.
		sky.set_camera(Vector2(10.0, -6.5), 7)
		var moved_x: float = celestial.position.x - x0
		var expected_x: float = (1.0 - SkyView.SKY_PARALLAX_X) * 10.0 * Backdrop.TILE
		check("небо (_celestial) X компенсирует сдвиг камеры на (1-k)*Δ (движение=%.1f, ожидание=%.1f)" %
			[moved_x, expected_x], absf(moved_x - expected_x) < 0.5)
		check("небо (_celestial) Y гасит сдвиг камеры ПОЛНОСТЬЮ (закреплена по высоте, как гора)",
			absf(celestial.position.y - (-6.5) * Backdrop.TILE) < 0.01 and absf(y0) < 0.01)
	sky.queue_free()

	var clouds := preload("res://scripts/world/clouds_view.gd").new()
	add_child(clouds)
	await get_tree().process_frame
	clouds.update(Vector2(0, 0))
	var cx0: float = clouds.position.x
	var cy0: float = clouds.position.y
	clouds.update(Vector2(10.0, -6.5))
	var moved_cx: float = clouds.position.x - cx0
	var expected_cx: float = (1.0 - CloudsView.CLOUDS_PARALLAX_X) * 10.0 * Backdrop.TILE
	check("облака X компенсируют сдвиг камеры на (1-k)*Δ (движение=%.1f, ожидание=%.1f)" %
		[moved_cx, expected_cx], absf(moved_cx - expected_cx) < 0.5)
	check("облака НЕ закреплены по высоте (Y-позиция слоя не меняется вслед за камерой)",
		absf(clouds.position.y - cy0) < 0.01 and absf(clouds.position.y) < 0.01)
	clouds.queue_free()

extends Node
## test_product_polish — оболочка «готового продукта» (раунд 6): заставка ставится только главной
## сцене процесса, окно «О игре» открывается из настроек и показывает версию со сборкой,
## слой заставки выше подсказки, иконки стрелок хода в доме без растягивающих якорей
## (источник предупреждения движка при каждом старте).
##
## Запуск: godot --headless --path . res://tests/test_product_polish.tscn

var failures := 0
var total := 0


func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", label])


func _ready() -> void:
	print("=== test_product_polish ===")
	GameState.world_seed = 20260101
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	# Заставка: дочерней сцене (тесты, бот) не ставится; headless — тоже.
	check("заставка не ставится дочерней сцене", SplashScreen.attach(main) == null)
	check("заставка не ставится в headless даже принудительно", SplashScreen.attach(main, true) == null)
	check("слой заставки выше подсказки Tip", UiLayers.SPLASH > UiLayers.TIP)
	check("в main нет узла Splash", main.get_node_or_null("Splash") == null)

	# Версия и сборка.
	var v := AboutCard.version_text()
	check("версия задана в project.godot", String(ProjectSettings.get_setting("application/config/version", "")) != "")
	check("текст версии не пуст: " + v, not v.is_empty())
	check("метка сборки читается из data/build_info.json", AboutCard.build_stamp().begins_with("сборка "))
	check("метка сборки красиво: 20260917-0413 → 17.09 04:13",
		AboutCard.pretty_stamp("20260917-0413", "abc1234") == "сборка 17.09 04:13 · abc1234")
	check("метка без коммита", AboutCard.pretty_stamp("20260917-0413") == "сборка 17.09 04:13")
	check("короткая метка как есть", AboutCard.pretty_stamp("dev") == "сборка dev")
	check("иконка приложения задана и существует",
		ResourceLoader.exists(String(ProjectSettings.get_setting("application/config/icon", ""))))
	check("системная заставка задана и существует",
		ResourceLoader.exists(String(ProjectSettings.get_setting("application/boot_splash/image", ""))))
	check("логотип заставки существует", ResourceLoader.exists(SplashScreen.LOGO))

	# «О игре» из настроек.
	var hud = main.hud
	hud.open_settings()
	await get_tree().process_frame
	var sheet: SettingsSheet = hud._settings_sheet
	check("настройки открыты", sheet.is_open())
	var about_btn: Button = sheet.find_child("About", true, false)
	check("в настройках есть кнопка «О игре»", about_btn != null)
	if about_btn != null:
		about_btn.pressed.emit()
		await get_tree().process_frame
	check("окно «О игре» открыто", AboutCard.is_open_any())
	var card := AboutCard.instance()
	if card != null:
		var ver: Label = card.find_child("Version", true, false)
		check("в окне есть версия", ver != null and ver.text == v)
		check("в окне есть кнопка политики", card.find_child("Privacy", true, false) != null)
		check("логотип в окне", card.find_child("Logo", true, false) != null)
		check("окно шире 200 и уже экрана", card._card.size.x >= 200.0 and card._card.size.x <= 224.0)
		card.close()
		await get_tree().process_frame
	check("окно «О игре» закрыто", not AboutCard.is_open_any())
	# Закрытие шторки закрывает и окно.
	sheet.open_about()
	await get_tree().process_frame
	hud.close_settings()
	await get_tree().process_frame
	check("закрытие настроек закрывает «О игре»", not AboutCard.is_open_any())

	# Дом: иконки стрелок хода без растягивающих якорей (иначе предупреждение движка при старте).
	var house := HouseSystem.instance
	var arrows_ok := true
	var arrows := 0
	if house != null and house._view != null:
		for n in house._view.find_children("Arrow", "", true, false):
			var c := n as Control
			if c == null:
				continue
			arrows += 1
			if c.anchor_left != c.anchor_right or c.anchor_top != c.anchor_bottom:
				arrows_ok = false
	check("стрелки хода в доме найдены (%d)" % arrows, arrows >= 2)
	check("якоря стрелок хода равные", arrows_ok)

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)

extends Node
## test_qa_screens — разовый QA-инструмент (не автотест): запускает настоящую
## main-сцену и по очереди снимает скриншоты ключевых панелей UI на реальном
## портретном вьюпорте 224x480 — с короткими и намеренно длинными строками,
## чтобы поймать переполнение текста в контейнерах. Нужен реальный рендер:
##
##   xvfb-run -a godot --path . res://tests/test_qa_screens.tscn \
##       --rendering-driver opengl3 -- /tmp/qa_screens
##
## Каталог для сохранения — первый аргумент после "--", по умолчанию /tmp/qa_screens.

var _out_dir := "/tmp/qa_screens"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		_out_dir = a
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)

	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")

	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud = main.hud

	# 1. Обычный HUD, ничего не открыто.
	await _shot("01_hud_base")

	# 2. Панель настроек — проверяем ряд языков (HFlowContainer).
	hud.open_settings()
	await get_tree().process_frame
	await _shot("02_settings")

	hud.close_settings()
	await get_tree().process_frame

	# 3. Инвентарь пустой.
	hud.open_inventory()
	await get_tree().process_frame
	await _shot("03_inventory_empty")

	# 4. Инвентарь с длинными названиями (артефакты).
	GameState.inventory["gold"] = 5
	GameState.inventory["obsidian"] = 3
	hud._render_inventory()
	await get_tree().process_frame
	await _shot("04_inventory_filled")

	hud.close_inventory()
	await get_tree().process_frame

	# 5. Магазин (лавка).
	ShopUI.open_shop()
	await get_tree().process_frame
	await _shot("05_shop")
	if ShopUI.instance != null:
		ShopUI.instance.close()
	await get_tree().process_frame

	# 6. Тост — короткий.
	hud.toast("Готово.")
	await get_tree().process_frame
	await _shot("06_toast_short")

	# 7. Тост — самая длинная реальная строка в игре (сортировка по данным).
	hud.toast(StoryText.get_text("workshop.toast_pickaxe"))
	await get_tree().process_frame
	await _shot("07_toast_long_real")

	# 8. Тост — искусственно очень длинная строка (стресс-тест).
	hud.toast("Это очень длинный тестовый текст тоста, специально составленный так, чтобы проверить перенос по словам и то, как панель тоста растягивается вверх, когда строка занимает много строк подряд и грозит вылезти за пределы видимой области экрана на портретном вьюпорте самого маленького из поддерживаемых размеров.")
	await get_tree().process_frame
	await _shot("08_toast_stress")

	# 9. Диалоговая рамка катсцены — самая длинная реальная реплика в игре
	# (intro_boy.n3, повествование — "who" пуст, как и вызывает _run_beat).
	var cs = main.find_child("CutscenePlayer", true, false)
	if cs != null:
		cs._root.visible = true
		cs._layout()
		cs._run_beat({"t": "narr", "text": "intro_boy.n3"})
		cs._line.visible_ratio = 1.0  # без ожидания "печатной машинки"
		await get_tree().process_frame
		await _shot("09_dialogue_longest_real")

		cs._run_beat({"t": "say", "who": "boy", "text": "intro_boy.s3"})
		cs._line.visible_ratio = 1.0
		await get_tree().process_frame
		await _shot("10_dialogue_short_real")

	print("test_qa_screens: скриншоты сохранены -> " + _out_dir)
	get_tree().quit(0)


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(name + ".png"))

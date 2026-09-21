extends Node
## test_wiring — проверка, что системы находят друг друга в живой сцене.
##
## Соседние системы ищут друг друга по ИМЕНИ узла (find_child("HUD"),
## find_child("StoryDirector") и так далее), а узлы создаются кодом через
## .new(). Узел без явного имени получает служебное — @StoryDirector@12, — и
## поиск по шаблону промахивается. Обе стороны при этом написаны терпимо к
## отсутствию друг друга и не ругаются: дом просто остаётся без сюжета, сюжет
## — без дома, и в игре молча перестают работать респавн в мастерской и
## сюжетные хуки вроде люка Роберта. Один раз так и случилось.
##
## Запуск: godot --headless --path . res://tests/test_wiring.tscn

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
	print("=== test_wiring ===")
	for _i in range(6):
		await get_tree().process_frame

	var root := get_tree().root
	for node_name in ["Player", "HUD", "WorldView", "StoryDirector"]:
		check("узел %s находится по имени" % node_name,
			root.find_child(node_name, true, false) != null)

	var director := root.find_child("StoryDirector", true, false)
	var house := root.find_child("HouseSystem", true, false)
	if house == null:
		for n in root.find_child("Main", true, false).get_children():
			if n is HouseSystem:
				house = n
		# дом живёт под ViewRoot, а не прямо в Main
		if house == null:
			var vr := root.find_child("ViewRoot", true, false)
			if vr != null:
				for n in vr.get_children():
					if n is HouseSystem:
						house = n
	check("дом в сцене есть", house != null)

	if director != null and house != null:
		check("дом представился сюжету (иначе не работают респавн в мастерской и хуки)",
			director.house == house)
		check("сюжет видит игрока", director.player != null)
		check("сюжет видит мир", director.world != null)
		check("сюжет видит интерфейс", director.hud != null)

	# Часы на поверхности (отчёт агента, баг владельца "время не течёт во
	# дворе"): DayCycle честно тикал и раньше, но нигде не отображался на
	# улице (единственные часы были в доме) — игрок не мог заметить ход
	# времени. hud.gd теперь держит свою копию тех же часов, что и дом.
	var hud := root.find_child("HUD", true, false)
	if hud != null:
		check("у HUD есть виджет часов", "_clock_label" in hud and hud._clock_label != null)
		if "_clock_label" in hud and hud._clock_label != null:
			DayCycle.set_hour(15.0)
			await get_tree().process_frame
			check("часы во дворе показывают то же время, что и DayCycle (\"День N, ЧЧ:ММ\")",
				hud._clock_label.text == "День %d, 15:00" % DayCycle.day)

	# Порядок слоёв ViewRoot — решение владельца 2026-09-21: подложка/звёзды/
	# солнце-месяц (всё внутри SkyView, см. sky_view.gd:_draw_celestial),
	# картинка горы, картинка забора (оба — Backdrop, гора добавлена первым
	# ребёнком, значит рисуется раньше/под забором), трава+декор огорода
	# (оба внутри WorldView — трава тайлами, декор оверлеем поверх них), дом
	# (HouseSystem переставляет себя сразу после WorldView, см. его _ready),
	# персонаж (Player+CharacterView). Порядок в дереве = порядок отрисовки
	# (более поздний ребёнок рисуется поверх более раннего) — облака
	# (CloudsView) не входят в список владельца отдельной строкой, но по
	# смыслу параллакса стоят ближе камеры, чем гора/забор, и дальше травы —
	# кладём их между Backdrop и WorldView, что уже так в main.gd.
	var vr := root.find_child("ViewRoot", true, false)
	if vr != null:
		var order: Array = []
		for n in vr.get_children():
			order.append(n.name)
		var idx_sky: int = order.find("SkyView")
		var idx_backdrop: int = order.find("Backdrop")
		var idx_clouds: int = order.find("CloudsView")
		var idx_world: int = order.find("WorldView")
		var idx_house: int = order.find("HouseSystem")
		var idx_player: int = order.find("Player")
		check("порядок слоёв ViewRoot: небо -> задник -> облака -> мир -> дом -> герой (%s)" % str(order),
			idx_sky >= 0 and idx_backdrop >= 0 and idx_clouds >= 0 and idx_world >= 0
				and idx_house >= 0 and idx_player >= 0
				and idx_sky < idx_backdrop and idx_backdrop < idx_clouds
				and idx_clouds < idx_world and idx_world < idx_house and idx_house < idx_player)

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)

extends Node
## test_screenshot_hero — не автотест, а инструмент глаз: поднимает main.tscn и
## снимает экраны героя (вкладка героя, дерево навыков, музей, карточки находок).
## Нужен настоящий рендер; окно лучше взять вдвое крупнее, чтобы читались иконки:
##
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . \
##       res://tests/test_screenshot_hero.tscn --rendering-driver opengl3 \
##       --resolution 448x960 -- /каталог [снимок ...]
##
## Снимки: hero records skills skills_armed skills_deep museum museum_bottom
## museum_tip museum_empty first_find card_find card_branch.
## Состояние выставляется только в памяти — на диск (user://) тест не пишет.

var _out_dir := "/tmp/hero_shots"
var _only: Array[String] = []
var _screen: ProgressScreen


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	for i in range(1, args.size()):
		_only.append(args[i])
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)

	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	StoryState.flags()["bars_introduced"] = true

	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(4)
	_screen = ProgressScreen.instance()

	if _want("museum_empty"):
		_screen.open_tab("museum")
		await _frames(4)
		await _shot("museum_empty")
		_screen.close()

	_fill_state()
	await _frames(2)

	if _want("hero"):
		_screen.open_tab("hero")
		await _frames(6)
		await _shot("hero")
	if _want("records"):
		_screen.open_tab("records")
		await _frames(8)
		await _shot("records")

	if _want("skills") or _want("skills_armed") or _want("skills_deep"):
		_screen.open_tab("progress")
		await _frames(6)
		if _want("skills"):
			await _shot("skills")
		if _want("skills_armed"):
			var panel: ProgressPanel = _screen._panels["progress"]
			var node := _first_ready_node(panel.tree)
			if node != null:
				node.pressed.emit()
				await _frames(20)
				await _shot("skills_armed")
				node.pressed.emit()          # второе нажатие — покупка
				await _frames(8)
				await _shot("skills_flash")
				await _frames(40)
				await _shot("skills_bought")
		if _want("skills_deep"):
			for c in _screen._panels["progress"].find_children("*", "ScrollContainer", true, false):
				(c as ScrollContainer).scroll_vertical = 400
			await _frames(4)
			await _shot("skills_deep")

	if _want("museum") or _want("museum_bottom") or _want("museum_tip"):
		_screen.open_tab("museum")
		await _frames(8)
		if _want("museum"):
			await _shot("museum")
		if _want("museum_tip"):
			var slot := _find_slot("antiquity_3")
			if slot != null:
				slot.pressed.emit()
				await _frames(4)
				await _shot("museum_tip")
				var unfound := _find_slot("mysticism_4")
				if unfound != null:
					unfound.pressed.emit()
					await _frames(4)
					await _shot("museum_tip_unfound")
		if _want("museum_bottom"):
			for c in _screen._panels["museum"].find_children("*", "ScrollContainer", true, false):
				(c as ScrollContainer).scroll_vertical = 2000
			await _frames(6)
			await _shot("museum_bottom")
		_screen.close()

	if _want("first_find"):
		# Настоящий путь находки: клетка артефакта -> карточка -> музей открывается сам.
		GameState.collected_artifacts.clear()
		GameState.completed_branches.clear()
		var artifact := Balance.get_artifact("antiquity_2")
		var cell: Vector2i = ArtifactSpawn.candidate_cells(artifact, GameState.world_seed)[0]
		_screen.finder.claim_at(cell.x, cell.y)
		await get_tree().create_timer(0.6).timeout
		await _shot("first_find_card")
		await get_tree().create_timer(3.0).timeout
		await _shot("first_find_museum")
		print("музей открыт после карточки: ", ProgressScreen.is_open())
		_screen.close()

	if _want("card_find"):
		ArtifactCard.show_find("legends_2")
		await _frames(30)
		await _shot("card_find")
		await _frames(150)
	if _want("card_branch"):
		ArtifactCard.show_branch(2)
		await _frames(30)
		await _shot("card_branch")

	print("test_screenshot_hero: снимки -> " + _out_dir)
	get_tree().quit(0)


func _fill_state() -> void:
	GameState.level = 12
	GameState.xp = 2210
	GameState.coins = 48250
	GameState.dollars = 7
	GameState.max_depth_reached = 482
	GameState.skill_stages = {"vision": 4, "dig_speed": 6, "hp": 3, "stamina": 2, "hunger": 1,
		"strength": 5, "luck_multiplier": 1}
	GameState.skill_points_available = 7
	GameState.collected_artifacts = ["antiquity_1", "antiquity_2", "antiquity_3", "antiquity_4", "antiquity_5",
		"mysticism_1", "mysticism_2", "mysticism_3", "occult_1", "occult_2", "forgotten_civilizations_1"]
	GameState.completed_branches = [1]
	GameState.ext["hero"] = {"finds": {"antiquity_2": 41, "antiquity_3": 55, "mysticism_1": 77}}
	GameState.inventory = {"gold": 5, "iron_ore": 12}
	var rec := _screen.records
	if rec != null:
		rec.lifetime_coins_earned = 52100
		rec.lifetime_hauled_value = 31800
		rec.best_haul_value = 2450
		rec.discovered_minerals = ["gold", "iron_ore", "coal", "copper", "silver", "lead"]
		rec.records_changed.emit()
	GameState.skill_points_changed.emit(GameState.skill_points_available)
	GameState.xp_changed.emit(GameState.xp, GameState.level)


func _first_ready_node(tree: SkillTree) -> SkillNode:
	for c in tree.get_children():
		if c is SkillNode and c.state == SkillNode.State.NEXT_READY:
			return c
	return null


func _find_slot(artifact_id: String) -> ArtifactSlot:
	for s in _screen._panels["museum"].find_children("*", "ArtifactSlot", true, false):
		if (s as ArtifactSlot).artifact_id == artifact_id:
			return s
	return null


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join(n + ".png"))

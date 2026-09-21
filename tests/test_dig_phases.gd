extends Node
## test_dig_phases — проверка фаз анимации копки бурмобилем (CharacterView,
## см. DIG_PHASES и _dig_frame в scripts/player/character_view.gd):
## старт [1,2,3] один раз -> цикл [4,5,6,7] пока копка идёт -> финиш
## [8,3,2,1] один раз после конца копки -> обычная стойка.
##
## Копка симулируется НАПРЯМУЮ (player.digging выставляется руками, а не
## через world.dig_cell): изолирует анимацию от мира и инструмента, которые
## уже проверены в test_player_harness.
##
## Запуск:  godot --headless --path . res://tests/test_dig_phases.tscn
## Код возврата — 0 (всё ок) или 1 (есть провалы), как у test_player_harness.

var failures := 0
var total := 0
var world: WorldGen
var player
var view


func _ready() -> void:
	print("=== test_dig_phases ===")
	world = WorldGen.new(4242)
	GameState.world_ref = world
	GameState.reset_progress()
	# Бурмобиль требует владения им — set_current_tool отказал бы без этого
	# (см. GameState.owns_tool). Тест проверяет только отрисовку, поэтому
	# инструмент просто присваивается напрямую, в обход магазина.
	GameState.current_tool = "drill_rig"

	player = load("res://scripts/player/player.gd").new()
	player.world = world
	player.on_ground = true
	add_child(player)

	view = load("res://scripts/player/character_view.gd").new()
	view.player = player
	add_child(view)

	_test_start_loop_end_down()
	_test_continuous_dig_skips_start()
	_test_restart_after_gap()
	_test_side_direction_sheet()
	_test_non_phased_tool_unaffected()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)


## Кадр, который view сейчас показывает (0-based индекс внутри листа).
func _shown_frame() -> int:
	view._process(0.0)
	var fw: float = view._sprite.region_rect.size.x
	if fw <= 0.0:
		return -1
	return int(round(view._sprite.region_rect.position.x / fw))


## Ставит/снимает копку клетки НИЖЕ героя (направление "вниз" — dig_rig_down)
## и продвигает anim ровно на один кадр анимации (ANIM_DIV, кирка/бур не
## переопределяют SHEET_ANIM_DIV — см. character_view.gd).
func _dig_down(active: bool) -> void:
	if active:
		player.digging = {"x": player.cell_x(), "y": player.cell_y() + 1,
				"t": 0.0, "total": 999.0, "type": TileTypes.Type.DIRT}
	else:
		player.digging = null


func _advance_one_frame() -> void:
	player.anim += view.ANIM_DIV


func _reset_view_state() -> void:
	view._dig_phase = "none"
	view._dig_phase_t0 = 0.0
	view._dig_was_active = false
	view._dig_last_end_msec = -1e9
	view._dig_last_base = ""
	view._dig_last_sheet_name = ""
	player.digging = null
	player.anim = 0.0


func _test_start_loop_end_down() -> void:
	_reset_view_state()
	_dig_down(true)

	# старт: кадры 1,2,3 (0-based 0,1,2), один раз, по порядку
	check("старт, кадр 1", _shown_frame() == 0)
	_advance_one_frame()
	check("старт, кадр 2", _shown_frame() == 1)
	_advance_one_frame()
	check("старт, кадр 3", _shown_frame() == 2)

	# цикл: кадры 4,5,6,7 (0-based 3,4,5,6), без паузы после старта
	_advance_one_frame()
	check("цикл, кадр 4", _shown_frame() == 3)
	_advance_one_frame()
	check("цикл, кадр 5", _shown_frame() == 4)
	_advance_one_frame()
	check("цикл, кадр 6", _shown_frame() == 5)
	_advance_one_frame()
	check("цикл, кадр 7", _shown_frame() == 6)
	_advance_one_frame()
	check("цикл крутится по кругу (снова кадр 4)", _shown_frame() == 3)

	# копка кончилась -> финиш: кадры 8,3,2,1 (0-based 7,2,1,0), один раз
	_dig_down(false)
	check("финиш, кадр 8", _shown_frame() == 7)
	_advance_one_frame()
	check("финиш, кадр 3", _shown_frame() == 2)
	_advance_one_frame()
	check("финиш, кадр 2", _shown_frame() == 1)
	_advance_one_frame()
	check("финиш, кадр 1", _shown_frame() == 0)

	# финиш доигран -> обычная стойка (idle), не лист копки
	_advance_one_frame()
	view._process(0.0)
	check("после финиша — не лист бурмобиля",
			not String(view._sprite.texture.resource_path).contains("dig_rig"))
	check("после финиша — idle (герой стоит)",
			String(view._sprite.texture.resource_path).ends_with("idle.png"))


## Копка следующей клетки началась почти сразу после конца предыдущей (та же
## машина бурит соседнюю клетку) — старт не играется повторно, сразу в цикл.
func _test_continuous_dig_skips_start() -> void:
	_reset_view_state()
	_dig_down(true)
	_shown_frame()   # старт, кадр 1 — прогоняем _process один раз
	_dig_down(false)
	_shown_frame()   # начался финиш

	# копка следующей клетки — тут же, гарантированно меньше 300 мс
	_dig_down(true)
	check("непрерывная копка идёт сразу в цикл (не в старт)",
			_shown_frame() == 3)   # loop[0] = 3


## Копка началась заново спустя больше 300 мс после конца предыдущей —
## полный старт, а не сразу цикл.
func _test_restart_after_gap() -> void:
	_reset_view_state()
	_dig_down(true)
	_shown_frame()
	_dig_down(false)
	_shown_frame()

	view._dig_last_end_msec -= 1000.0   # имитируем «это было давно»
	_dig_down(true)
	check("копка после паузы начинается со старта",
			_shown_frame() == 0)   # start[0] = 0


func _test_side_direction_sheet() -> void:
	_reset_view_state()
	player.x = 20.0
	player.y = 5.0
	player.digging = {"x": player.cell_x() + 1, "y": player.cell_y(),
			"t": 0.0, "total": 999.0, "type": TileTypes.Type.DIRT}
	view._process(0.0)
	check("копка вбок берёт лист dig_rig_side",
			String(view._sprite.texture.resource_path).ends_with("dig_rig_side.png"))
	check("копка вбок тоже начинается со старта (кадр 1)",
			_shown_frame() == 0)


## Инструменты без записи в DIG_PHASES (точка расширения) — старое поведение:
## цикл по всем кадрам листа, без фаз.
func _test_non_phased_tool_unaffected() -> void:
	_reset_view_state()
	GameState.current_tool = "rusty_pickaxe"
	player.x = 20.0
	player.y = 5.0
	player.digging = {"x": player.cell_x() + 1, "y": player.cell_y(),
			"t": 0.0, "total": 999.0, "type": TileTypes.Type.DIRT}
	view._process(0.0)
	var dig: Dictionary = view._dig_frame(true)
	check("у кирки фаз нет — _dig_frame отдаёт frame < 0 (старый цикл)",
			dig.get("frame", 0) < 0)
	GameState.current_tool = "drill_rig"

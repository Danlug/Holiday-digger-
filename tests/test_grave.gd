extends Node
## test_grave.gd — могила деда во дворе (ветка «grave», раунд 5): текстуры на
## месте и в игровом размере, пиксель без размытия, гравировка контрастна,
## состояния до/после сцен (плита сдвинута и банка в яме после diary_first,
## самородок на плите после концовки), сцены кладут банку и самородок туда же.
##
## Запуск:
##   godot --headless --path . res://tests/test_grave.tscn

var failures := 0
var total := 0

var player: Node2D
var grave: GraveSite


func _ready() -> void:
	_run()


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name,
		("  " + detail) if not ok and not detail.is_empty() else ""])


func _frames(n: int = 3) -> void:
	for _i in n:
		await get_tree().process_frame


func _reset() -> void:
	StoryState.delete_from_disk()
	GameState.story_flags = {}
	GameState.story_seen = []
	GameState.story_queue = []
	GameState.ext.clear()
	GameState.era = "now"
	GameState.house_is_indoors = false


func _run() -> void:
	print("=== test_grave.gd ===")
	var world := WorldGen.new(20251025)
	player = preload("res://scripts/player/player.gd").new()
	player.world = world
	add_child(player)
	player.x = 15.5
	player.y = 0.5
	_reset()

	grave = GraveSite.new()
	grave.player = player
	add_child(grave)
	await _frames(2)

	_test_textures()
	await _test_states()
	_test_scene_props()
	_reset()

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_textures() -> void:
	for p in [GraveSite.STONE_TEX, GraveSite.STONE_OPEN_TEX, GraveSite.JAR_TEX, GraveSite.NUGGET_TEX]:
		check("текстура на месте: " + p, ResourceLoader.exists(p))
	var closed: Texture2D = load(GraveSite.STONE_TEX)
	var opened: Texture2D = load(GraveSite.STONE_OPEN_TEX)
	check("плита на месте и сдвинутая — картинки одного размера", closed.get_size() == opened.get_size())
	var size := closed.get_size() * GraveSite.STONE_SCALE
	check("могила в мире: до двух клеток в ширину (%.0f px)" % size.x, size.x > 1.5 * GraveSite.TILE and size.x <= 2.0 * GraveSite.TILE)
	check("могила ниже героя, но выше клетки (%.0f px)" % size.y, size.y >= 1.2 * GraveSite.TILE and size.y < 1.75 * GraveSite.TILE)
	var rect := Rect2(grave._stone.position, size)
	check("низ могилы на линии земли", is_equal_approx(rect.end.y, float(GraveSite.TILE)))
	check("могила по центру клетки 14", is_equal_approx(rect.get_center().x, GraveSite.GRAVE_X * GraveSite.TILE))
	check("подсказка «world:grave» целит в тот же прямоугольник", HintTargets.world_rect("grave").is_equal_approx(rect))

	var img := closed.get_image()
	var colors := {}
	var soft := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and c.a < 1.0:
				soft += 1
			if c.a > 0.0:
				colors[c.to_rgba32()] = true
	check("пиксель-арт без размытия: альфа только 0 или 1", soft == 0, "полупрозрачных: %d" % soft)
	check("палитра ограничена (%d цветов)" % colors.size(), colors.size() <= 48)
	# Гравировка: в медальоне (tools/gen_grave.py: MED_*) есть и тёмные канавки, и светлая борода.
	var lo := 1.0
	var hi := 0.0
	for y in range(14, 60):
		for x in range(18, 54):
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				lo = minf(lo, c.get_luminance())
				hi = maxf(hi, c.get_luminance())
	check("гравировка портрета контрастна (%.2f..%.2f)" % [lo, hi], hi - lo > 0.4)


func _test_states() -> void:
	await _frames(2)
	check("до сцены плита на месте", grave._stone.texture == grave._stone_closed)
	check("банка спрятана под плитой", not grave._jar.visible)
	check("самородка ещё нет", not grave._nugget.visible)

	StoryState.set_flag("diary_found")
	await _frames(2)
	check("после diary_first плита сдвинута", grave._stone.texture == grave._stone_open)
	check("банка видна", grave._jar.visible)
	var stone := Rect2(grave._stone.position, grave._stone_closed.get_size() * GraveSite.STONE_SCALE)
	var jar := Rect2(grave._jar.position, grave._jar.texture.get_size() * GraveSite.JAR_SCALE)
	check("банка стоит в яме справа от плиты, над линией земли",
		stone.encloses(jar) and jar.get_center().x > stone.get_center().x and jar.end.y < GraveSite.TILE)

	StoryState.mark_seen("ending")
	await _frames(2)
	check("после концовки самородок лежит на плите", grave._nugget.visible)
	var nug_open := Rect2(grave._nugget.position, grave._nugget.texture.get_size() * GraveSite.NUGGET_SCALE)
	check("самородок внутри могилы и выше земли", stone.encloses(nug_open) and nug_open.end.y < GraveSite.TILE)
	check("самородок не наезжает на банку", not nug_open.intersects(jar))

	GameState.story_flags.erase("diary_found")
	await _frames(2)
	var nug_closed := Rect2(grave._nugget.position, nug_open.size)
	check("плита на месте — самородок едет вместе с ней", nug_closed.position.x > nug_open.position.x)

	GameState.era = "grandpa"
	await _frames(2)
	check("во времена деда могилы ещё нет", not grave._stone.visible and not grave._jar.visible and not grave._nugget.visible)
	GameState.era = "now"
	await _frames(2)
	check("вернулись в «сейчас» — могила на месте", grave._stone.visible)


## Сцены рисуют банку и самородок своими реквизитами: та же картинка, та же
## точка и тот же масштаб (scale / ART_SCALE), чтобы после сцены ничего не прыгало.
func _test_scene_props() -> void:
	var art_scale: float = preload("res://scripts/story/cutscene_player.gd").ART_SCALE
	var jar := _find_prop("diary_first", "jar")
	check("сцена diary_first ставит банку", not jar.is_empty())
	if not jar.is_empty():
		check("банка сцены — та же картинка", String(jar.get("tex", "")) == GraveSite.JAR_TEX)
		check("банка сцены в той же клетке", is_equal_approx(float(jar.get("x", 0.0)), GraveSite.JAR_X))
		check("банка сцены того же размера", is_equal_approx(float(jar.get("scale", 1.0)) / art_scale, GraveSite.JAR_SCALE))
		check("банка сцены на дне ямы", absf(float(jar.get("y", 0.0)) * GraveSite.TILE - GraveSite.JAR_BOTTOM_Y) < 1.0)
	var nug := _find_prop("ending", "nugget")
	check("концовка кладёт самородок", not nug.is_empty())
	if not nug.is_empty():
		check("самородок концовки — та же картинка", String(nug.get("tex", "")) == GraveSite.NUGGET_TEX)
		check("самородок концовки на плите", is_equal_approx(float(nug.get("x", 0.0)), GraveSite.NUGGET_X)
			and absf(float(nug.get("y", 0.0)) * GraveSite.TILE - GraveSite.NUGGET_BOTTOM_Y) < 1.0)
		check("самородок концовки того же размера", is_equal_approx(float(nug.get("scale", 1.0)) / art_scale, GraveSite.NUGGET_SCALE))
	var intro := _find_prop("intro_grandpa", "grave")
	check("интро деда показывает могилу", not intro.is_empty())
	if not intro.is_empty():
		check("могила в интро того же размера, что во дворе",
			String(intro.get("tex", "")) == GraveSite.STONE_TEX
			and is_equal_approx(float(intro.get("scale", 1.0)) / art_scale, GraveSite.STONE_SCALE))


func _find_prop(scene_id: String, prop_id: String) -> Dictionary:
	for b in StoryData.beats(scene_id):
		if String(b.get("t", "")) == "world_prop" and String(b.get("id", "")) == prop_id:
			return b
	return {}

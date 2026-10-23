class_name HintTargets
extends RefCounted
## Цель подсказки: строка из правила -> прямоугольник на экране (проектные единицы вьюпорта).
##
##   hud:<hero|backpack|menu|tool|gear|load|hp|hunger|stamina|coins|dollars>
##   menu:<id пункта меню •••>   — пока меню закрыто, это сама кнопка «•••» (final=false),
##                                 открыли — плитка пункта (final=true)
##   tech_hud:<fuel|heat>        — значки топлива и жары (ветка «Техника»)
##   world:<station|well|grave>  — объекты мира; только пока видны на экране
##   group:<имя>                 — первый Control группы
##   attached:<id>               — то, что экран зарегистрировал через HintPulse.attach
##
## Чужие узлы читаем через get() — без правок их файлов. Нет цели, она скрыта или
## нулевого размера — resolve отдаёт {} и правило ждёт (не показывается и не «сгорает»).
## Результат: {rect, node, final, world, spec}. final — цель конечная: нажатие по ней
## считается действием «сделал»; промежуточная («•••» перед пунктом) подсказку не снимает.

const TILE := 32
const MIN_SIZE := 6.0


static func resolve(spec) -> Dictionary:
	if spec is Array:
		for item in spec:
			var r := resolve(String(item))
			if not r.is_empty():
				return r
		return {}
	var s := String(spec)
	var p := s.find(":")
	if p < 0:
		return {}
	var kind := s.substr(0, p)
	var arg := s.substr(p + 1)
	match kind:
		"hud":
			return _of_control(hud_control(arg), true, s)
		"tech_hud":
			return _of_control(tech_hud_control(arg), true, s)
		"attached":
			return _of_control(HintPulse.target(arg), true, s)
		"group":
			var t := HintConditions.tree()
			var n := t.get_first_node_in_group(arg) if t != null else null
			return _of_control(n as Control, true, s)
		"menu":
			return _of_menu(arg, s)
		"world":
			return _of_world(arg, s)
	return {}


static func _of_control(c: Control, final: bool, spec: String) -> Dictionary:
	if c == null or not is_instance_valid(c) or not c.is_inside_tree() or not c.is_visible_in_tree():
		return {}
	var r := c.get_global_rect()
	if r.size.x < MIN_SIZE or r.size.y < MIN_SIZE:
		return {}
	return {"rect": r, "node": c, "final": final, "world": false, "spec": spec}


static func hud_control(id: String) -> Control:
	var h := HintConditions.hud()
	if h == null:
		return null
	var c = null
	match id:
		"hero":
			c = h.get("_hero_button")
		"backpack":
			c = h.get("_inv_button")
		"menu":
			c = h.get("_more_button")
		"tool":
			c = h.get("_tool_button")
		"gear":
			c = h.get("_gear_pack")
		"load":
			c = h.get("_load_pill")
		_:
			var a = h.get("_anchors")
			if typeof(a) == TYPE_DICTIONARY:
				c = a.get(id, null)
	return c as Control


static func tech_hud_control(id: String) -> Control:
	var sys := TechSystem.instance()
	if sys == null:
		return null
	var th = sys.get("_tech_hud")
	if th == null:
		return null
	return th.get("_fuel_btn" if id == "fuel" else "_heat_btn") as Control


## Кнопка пункта в открытом меню «•••»: HUD пересобирает меню при каждом открытии, а
## пункт на плитке опознаём по заголовку подсказки (Tip.bind кладёт его в мета узла).
static func menu_button(entry_id: String) -> Control:
	var h := HintConditions.hud()
	if h == null:
		return null
	var grid = h.get("_more_grid")
	if grid == null:
		return null
	var title := ""
	for e: Dictionary in MenuRegistry.entries():
		if String(e["id"]) == entry_id:
			title = MenuRegistry.text_of(e, "title")
			break
	if title.is_empty():
		return null
	for b: Node in (grid as Control).get_children():
		var meta = b.get_meta(Tip.META, {})
		if typeof(meta) == TYPE_DICTIONARY and String(meta.get("title", "")) == title:
			return b as Control
	return null


static func _of_menu(entry_id: String, spec: String) -> Dictionary:
	if not HintConditions.menu_entry_visible(entry_id):
		return {}
	var h := HintConditions.hud()
	if h != null and h.has_method("is_more_menu_open") and h.is_more_menu_open():
		var b := menu_button(entry_id)
		var r := _of_control(b, true, spec)
		if not r.is_empty():
			return r
	return _of_control(hud_control("menu"), false, spec)


# ---------------------------------------------------------------------------
# Мир
# ---------------------------------------------------------------------------

## Прямоугольник объекта в мировых пикселях (как его рисуют TechWorld и GraveSite).
static func world_rect(name: String) -> Rect2:
	match name:
		"station":
			return _tech_sprite_rect(WorldGen.FUEL_STATION_X, "station")
		"well":
			return _tech_sprite_rect(WorldGen.WELL_X, "well_0")
		"grave":
			var size := Vector2(48, 48)
			var t: Texture2D = load(GraveSite.STONE_TEX) if ResourceLoader.exists(GraveSite.STONE_TEX) else null
			if t != null:
				size = t.get_size() * GraveSite.STONE_SCALE
			return Rect2(Vector2(GraveSite.GRAVE_X * TILE - size.x * 0.5, TILE - size.y), size)
	return Rect2()


static func _tech_sprite_rect(cell_x: float, tex_name: String) -> Rect2:
	var size := Vector2(64, 64)
	var t := TechUi.tex(tex_name)
	if t != null:
		size = t.get_size()
	return Rect2(Vector2(cell_x * TILE, TILE * 0.5 - size.y), size)


static func _of_world(name: String, spec: String) -> Dictionary:
	var r := world_rect(name)
	if r.size == Vector2.ZERO:
		return {}
	var t := HintConditions.tree()
	var vr := HintConditions.find("ViewRoot") as Node2D if t != null else null
	var h := HintConditions.hud()
	if vr == null or h == null:
		return {}
	r.position += vr.position
	var screen := Rect2(Vector2.ZERO, h.get_viewport_rect().size)
	# Цель должна быть на виду целиком хотя бы наполовину, иначе кольцо покажет в никуда.
	var seen := r.intersection(screen)
	if seen.size.x < r.size.x * 0.5 or seen.size.y < r.size.y * 0.5:
		return {}
	return {"rect": r, "node": null, "final": true, "world": true, "spec": spec}

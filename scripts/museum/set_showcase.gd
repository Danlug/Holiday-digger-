class_name SetShowcase
extends Control
## Центральная витрина музея: ультимативный сет (ГДД раздел 10). Пять пятых
## предметов веток стоят кольцом — шлем, амулет, перчатка, нагрудник, щит, —
## между собой соединены линиями, которые загораются, когда соседние предметы
## найдены; в центре звезда комплекта вспыхивает, когда собраны все пять.
## Снизу — пять гнёзд Перчатки Мироздания под самые глубокие материалы игры.
##
## Текста нет: всё, что нужно прочитать, — в подсказках Tip.

const HEIGHT := 172.0
const RING_Y := 76.0
const RX := 60.0
const RY := 52.0
const GEM_BOX := 22.0
const GEMS := ["hellstone", "dark_matter", "universum", "angelstone", "divine_heart"]
# Угол слота на кольце, градусы: шлем сверху, дальше по часовой стрелке.
const ANGLES := {"helmet": -90.0, "amulet": -18.0, "glove": 54.0, "chestplate": 126.0, "shield": 198.0}
const RING_ORDER := ["helmet", "amulet", "glove", "chestplate", "shield"]

## Хранилище рекордов нужно, чтобы знать, какие материалы уже выкопаны.
var store: RecordsStore = null

var slots: Dictionary = {}      # equip_slot -> ArtifactSlot
var have: int = 0

var _gem_boxes: Array = []
var _t: float = 0.0
var _acc: float = 0.0
var _emblem: Control


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	for piece: String in RING_ORDER:
		var slot := ArtifactSlot.new()
		var a := _artifact_for_piece(piece)
		add_child(slot)
		slot.setup(a)
		slots[piece] = slot
	_emblem = Control.new()
	_emblem.custom_minimum_size = Vector2(34, 34)
	_emblem.size = Vector2(34, 34)
	add_child(_emblem)
	for g in GEMS:
		var box := Control.new()
		box.custom_minimum_size = Vector2(GEM_BOX, GEM_BOX)
		box.size = Vector2(GEM_BOX, GEM_BOX)
		box.set_meta("mineral", g)
		add_child(box)
		_gem_boxes.append(box)
	resized.connect(_layout)
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	_layout()
	refresh()


func refresh() -> void:
	have = 0
	for piece: String in RING_ORDER:
		var slot: ArtifactSlot = slots.get(piece, null)
		if slot == null:
			continue
		slot.refresh()
		if slot.found:
			have += 1
	var total := RING_ORDER.size()
	Tip.set_text(_emblem, ArtifactText.set_title(),
		"Пятые предметы всех веток складываются в комплект. Без него глубже 4000 против монстров не выстоять.",
		"Собрано %d из %d" % [have, total])
	for box: Control in _gem_boxes:
		var id := String(box.get_meta("mineral"))
		var mineral := Balance.get_mineral(id)
		var lit := _is_gem_lit(id)
		Tip.set_text(box, String(mineral.get("name_ru", id)) if lit else "???",
			"Гнездо Перчатки Мироздания." if lit else "Гнездо Перчатки Мироздания ждёт материал со дна.",
			"Материал добыт" if lit else "Искать глубже %d" % int(Balance.unwrap(mineral.get("depth_min", 4000))))
	queue_redraw()


func _is_gem_lit(mineral_id: String) -> bool:
	# Гнездо горит и когда материал уже вставлен в Перчатку (экран «Снаряжение»), и когда он просто добыт.
	if CombatService.socket_filled(mineral_id):
		return true
	return store != null and store.discovered_minerals.has(mineral_id)


func _artifact_for_piece(piece: String) -> Dictionary:
	for a: Dictionary in Balance.artifacts.get("artifacts", []):
		if String(a.get("equip_slot", "")) == piece:
			return a
	return {}


func _slot_center(piece: String) -> Vector2:
	var a := deg_to_rad(float(ANGLES.get(piece, -90.0)))
	return Vector2(size.x * 0.5 + cos(a) * RX, RING_Y + sin(a) * RY)


func _layout() -> void:
	for piece: String in RING_ORDER:
		var slot: ArtifactSlot = slots.get(piece, null)
		if slot != null:
			slot.position = (_slot_center(piece) - slot.size * 0.5).floor()
	if _emblem != null:
		_emblem.position = (Vector2(size.x * 0.5, RING_Y + 2.0) - _emblem.size * 0.5).floor()
	var n := _gem_boxes.size()
	var gap := 4.0
	var total := float(n) * GEM_BOX + float(n - 1) * gap
	var x0 := (size.x - total) * 0.5
	for i in range(n):
		var box: Control = _gem_boxes[i]
		box.position = Vector2(x0 + float(i) * (GEM_BOX + gap), HEIGHT - GEM_BOX - 3.0).floor()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_acc += delta
	if _acc >= 1.0 / 30.0:
		_acc = 0.0
		queue_redraw()


func _draw() -> void:
	var done := have >= RING_ORDER.size()
	var pulse := 0.5 if HeroUi.calm() else 0.5 + 0.5 * sin(_t * 2.4)
	var rect := Rect2(Vector2.ZERO, size)
	var border := ProgressUiKit.GOLD if done else ProgressUiKit.GOLD.darkened(0.55)
	draw_style_box(HeroUi.box(Color(0.075, 0.065, 0.1), border, 6, 2 if done else 1), rect)

	var center := Vector2(size.x * 0.5, RING_Y + 2.0)
	# ореол за центральной звездой: тусклый, пока сет не собран
	var aura := 0.05 + (0.12 + 0.1 * pulse if done else 0.015 * float(have))
	for i in range(4):
		draw_circle(center, 44.0 - 9.0 * float(i), Color(1.0, 0.82, 0.35, aura))

	# линии кольца: горят, если оба соседних предмета найдены
	for i in range(RING_ORDER.size()):
		var p1: String = RING_ORDER[i]
		var p2: String = RING_ORDER[(i + 1) % RING_ORDER.size()]
		var on: bool = (slots[p1] as ArtifactSlot).found and (slots[p2] as ArtifactSlot).found
		var col := Color(1.0, 0.82, 0.35, 0.55 + 0.35 * pulse) if on else Color(0.25, 0.21, 0.17, 0.9)
		draw_line(_slot_center(p1), _slot_center(p2), col, 2.0 if on else 1.0)
	for piece: String in RING_ORDER:
		var on: bool = (slots[piece] as ArtifactSlot).found
		draw_line(_slot_center(piece), center, Color(1.0, 0.82, 0.35, 0.28) if on else Color(0.2, 0.17, 0.14, 0.7), 1.0)

	# звезда комплекта
	var star := HeroIcons.get_icon("ui_star")
	if star != null:
		var s := 28.0 + (4.0 * pulse if done else 0.0)
		draw_texture_rect(star, Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s)), false,
			Color.WHITE if done else Color(0.42, 0.38, 0.34, 0.8 if have > 0 else 0.5))

	# подложка под гнёзда Перчатки
	if not _gem_boxes.is_empty():
		var first: Control = _gem_boxes[0]
		var last: Control = _gem_boxes[_gem_boxes.size() - 1]
		var pill := Rect2(first.position - Vector2(5, 3), Vector2(last.position.x + GEM_BOX - first.position.x + 10, GEM_BOX + 6))
		draw_style_box(HeroUi.box(Color(0.05, 0.04, 0.06), ProgressUiKit.BORDER, 8), pill)
		for box: Control in _gem_boxes:
			_draw_gem_at(box)


func _draw_gem_at(box: Control) -> void:
	var id := String(box.get_meta("mineral"))
	var tex := HeroIcons.get_icon("gem_" + id)
	var r := Rect2(box.position + (box.size - Vector2(16, 16)) * 0.5, Vector2(16, 16))
	if _is_gem_lit(id):
		draw_circle(r.get_center(), 11.0, Color(1, 1, 1, 0.08 + 0.08 * (0.5 + 0.5 * sin(_t * 3.0))))
		if tex != null:
			draw_texture_rect(tex, r, false)
	elif tex != null:
		draw_texture_rect(tex, r, false, Color(0.07, 0.06, 0.09, 1.0))

extends Node2D
## CombatView — рисует бой в мировых координатах (дочерний узел ViewRoot, как
## герой): спрайты монстров и босса, взмах героя, телеграфы и зоны ударов босса.
## Ничего не решает — читает состояние CombatDirector. Монстры вне экрана и в
## чёрном тумане не рисуются (туман прячет и их тоже).

const TILE := 32
const SLASH_FRAMES := 4
const SLASH_SIZE := Vector2(48, 48)
const SLASH_TIME := 0.2

var director: CombatDirector = null
var _dt: float = 0.016

var _sprites: Dictionary = {}
## Вид монстра сверх спрайта: контактная тень, ореол телеграфа атаки, возраст для «появления».
var _extras: Dictionary = {}
var _shadow_tex: Texture2D = null
var _halo_tex: Texture2D = null
var _add_mat: CanvasItemMaterial = null
var _boss_shadow: Sprite2D = null
var _boss_glow: Sprite2D = null
const SHADOW_PATH := "res://art/fx/shadow_blob.png"
const HALO_PATH := "res://art/fx/glow_soft.png"
const POP_TIME := 0.22      # появление: вырастает и проявляется
var _boss_sprite: Sprite2D = null
var _slash_tex: Texture2D = null
var _slash_checked := false
var _was_drawing := false

const COL_WARN := Color(0.95, 0.22, 0.18)
const COL_STRIKE := Color(1.0, 0.86, 0.5)


func _ready() -> void:
	z_index = 1
	_shadow_tex = load(SHADOW_PATH) if ResourceLoader.exists(SHADOW_PATH) else null
	_halo_tex = load(HALO_PATH) if ResourceLoader.exists(HALO_PATH) else null
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


func _process(dt: float) -> void:
	if director == null or director.player == null:
		return
	_dt = dt
	_sync_monsters()
	_sync_boss()
	var drawing: bool = not director.slashes.is_empty() or director.boss != null
	if drawing or _was_drawing:
		queue_redraw()
	_was_drawing = drawing


func _fog_visible(cx: int, cy: int) -> bool:
	if director.fog == null:
		return true
	return director.fog.get_state(cx, cy) != FogOfWar.State.BLACK


func _sync_monsters() -> void:
	var live := {}
	for m: Monster in director.monsters:
		live[m] = true
		var s: Sprite2D = _sprites.get(m)
		if s == null:
			s = Sprite2D.new()
			s.centered = true
			s.region_enabled = true
			add_child(s)
			_sprites[m] = s
		var sheet := MonsterSheet.get_sheet(m.id)
		if sheet.texture == null:
			s.visible = false
			_hide_extras(m)
			continue
		s.visible = _fog_visible(int(floor(m.x)), int(floor(m.y)))
		if not s.visible:
			_hide_extras(m)
			continue
		s.texture = sheet.texture
		var anim: String = m.anim_name()
		if anim == "die":
			s.region_rect = sheet.region_progress("die", clampf(m.t / 0.7, 0.0, 0.999))
		else:
			s.region_rect = sheet.region(anim, m.anim_t)
		s.scale = Vector2.ONE / MonsterSheet.ART_SCALE
		s.flip_h = m.facing < 0
		var fh := sheet.frame_h
		if sheet.anchor_feet:
			s.position = Vector2(m.x * TILE, (m.y + m.hh) * TILE - fh / 2.0 + sheet.foot)
		else:
			s.position = Vector2(m.x * TILE, m.y * TILE)
		var tint := Color.WHITE
		if m.telegraph:
			var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 45.0)
			tint = Color(1.0 + 0.4 * k, 1.0 - 0.28 * k, 1.0 - 0.28 * k)
		if m.flash > 0.0:
			tint = Color(2.2, 2.2, 2.2)
		if m.state == "dying":
			tint.a = clampf(1.0 - (m.t - 0.35) / 0.35, 0.0, 1.0)
		_decorate(m, s, tint)
	for m: Monster in _sprites.keys():
		if not live.has(m):
			(_sprites[m] as Sprite2D).queue_free()
			_sprites.erase(m)
			var ex: Dictionary = _extras.get(m, {})
			for k in ["sh", "gl"]:
				if ex.has(k) and is_instance_valid(ex[k]):
					(ex[k] as Node).queue_free()
			_extras.erase(m)


func _sync_boss() -> void:
	var boss: BossLogic = director.boss
	if boss == null:
		if _boss_sprite != null:
			_boss_sprite.visible = false
		if _boss_shadow != null:
			_boss_shadow.visible = false
			_boss_glow.visible = false
		return
	if _boss_sprite == null:
		_boss_sprite = Sprite2D.new()
		_boss_sprite.centered = true
		_boss_sprite.region_enabled = true
		add_child(_boss_sprite)
	var id := String(CombatData.section("boss").get("sprite", "abyss_idol"))
	var sheet := MonsterSheet.get_sheet(id)
	if sheet.texture == null:
		_boss_sprite.visible = false
		return
	_boss_sprite.visible = true
	_boss_sprite.texture = sheet.texture
	_boss_sprite.scale = Vector2.ONE / MonsterSheet.ART_SCALE
	var now := Time.get_ticks_msec() / 1000.0
	var rect: Rect2
	match boss.state:
		BossLogic.INTRO, BossLogic.TRANSITION:
			rect = sheet.region("roar", now)
		BossLogic.TELEGRAPH:
			rect = sheet.region_progress("attack", clampf(boss.t / maxf(boss._tele, 0.01), 0.0, 1.0) * 0.66)
		BossLogic.STRIKE:
			rect = sheet.region_progress("attack", 0.7 + clampf(boss.t / 0.4, 0.0, 1.0) * 0.29)
		BossLogic.RECOVER:
			rect = sheet.region("exposed", now)
		BossLogic.DEAD:
			rect = sheet.region_progress("die", clampf(director.boss_death_t / 2.4, 0.0, 0.999))
		_:
			rect = sheet.region("idle", now)
	_boss_sprite.region_rect = rect
	_boss_sprite.position = Vector2(boss.center_x * TILE, boss.floor_y * TILE - sheet.frame_h / 2.0 + sheet.foot)
	var tint := Color.WHITE
	if director.boss_flash > 0.0:
		tint = Color(2.0, 2.0, 2.0)
	if boss.state == BossLogic.DEAD:
		tint.a = clampf(1.0 - (director.boss_death_t - 1.6) / 1.2, 0.0, 1.0)
	_boss_sprite.modulate = tint
	_decorate_boss(boss, sheet, tint)


## Тень, ореол телеграфа, появление и «сжатие» при попадании — всё поверх готового спрайта монстра.
func _decorate(m: Monster, s: Sprite2D, tint: Color) -> void:
	var ex: Dictionary = _extras.get(m, {})
	if ex.is_empty():
		ex = {"age": 0.0, "key": -1, "row": -1}
		ex["sh"] = _make_extra(_shadow_tex, false)
		ex["gl"] = _make_extra(_halo_tex, true)
		_extras[m] = ex
		if not Settings.reduce_motion and m.state != "dormant":
			Fx.burst("poof", Vector2(m.x, m.y + m.hh) * TILE, 0.7)   # вылез: облачко пыли у ног
	var calm := Settings.reduce_motion
	ex["age"] = float(ex["age"]) + _dt
	var pop := 1.0 if calm else clampf(float(ex["age"]) / POP_TIME, 0.0, 1.0)
	var ease := 1.0 - (1.0 - pop) * (1.0 - pop)
	var base_scale := s.scale
	var k := clampf(m.flash / 0.12, 0.0, 1.0) if not calm else 0.0
	# появление: от 70% размера; попадание: чуть приплюснут и шире, ноги на месте
	s.scale = Vector2(base_scale.x * (0.7 + 0.3 * ease) * (1.0 + 0.14 * k), base_scale.y * (0.7 + 0.3 * ease) * (1.0 - 0.08 * k))
	var fh := MonsterSheet.get_sheet(m.id).frame_h
	s.position.y += fh * 0.5 * (1.0 - s.scale.y / base_scale.y) if MonsterSheet.get_sheet(m.id).anchor_feet else 0.0
	tint.a *= ease
	s.modulate = tint

	# земля под монстром — для тени (у летунов она внизу, и тень «показывает» высоту)
	var foot_y := (m.y + m.hh) * TILE
	var cx := int(floor(m.x))
	var cy := int(floor(m.y + m.hh))
	var key := cx * 4099 + cy
	if int(ex["key"]) != key:
		ex["key"] = key
		var row := -1
		for r in range(maxi(cy, 1), cy + 8):
			if director.cw.solid(cx, r):
				row = r
				break
		ex["row"] = row
	var sh: Sprite2D = ex["sh"]
	if sh != null:
		var row2: int = ex["row"]
		if row2 < 0 or m.state == "dormant" or m.state == "dead":
			sh.visible = false
		else:
			var h := maxf(float(row2) * TILE - foot_y, 0.0)
			var f := clampf(h / 96.0, 0.0, 1.0)
			sh.visible = true
			sh.position = Vector2(m.x * TILE, float(row2) * TILE - 1.5).floor()
			var w := (m.hw * 2.0 + 0.25) * TILE * lerpf(1.0, 0.55, f)
			sh.scale = Vector2(w / 24.0, lerpf(1.0, 0.6, f))
			sh.modulate.a = lerpf(1.0, 0.3, f) * ease * (1.0 - clampf((m.t - 0.2) / 0.5, 0.0, 1.0) * (1.0 if m.state == "dying" else 0.0))
	# телеграф удара: красный ореол, плотнее к концу замаха (читается и в темноте)
	var gl: Sprite2D = ex["gl"]
	if gl != null:
		if m.telegraph and _halo_tex != null:
			var wind := maxf(m.attack_cfg("windup", 0.4), 0.1)
			var prog := clampf(m.t / wind, 0.0, 1.0)
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 60.0) if not calm else 1.0
			gl.visible = true
			gl.position = s.position
			var d := maxf(m.hw, m.hh) * 2.0 * TILE * 2.6
			gl.scale = Vector2(d, d) / HALO_PX
			gl.modulate = Color(1.0, 0.28, 0.14, (0.28 + 0.4 * prog) * (0.75 + 0.25 * pulse))
		else:
			gl.visible = false


const HALO_PX := 96.0


func _make_extra(tex: Texture2D, additive: bool) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.z_index = -1
	sp.visible = false
	if additive:
		sp.material = _add_mat
	add_child(sp)
	return sp


func _hide_extras(m: Monster) -> void:
	var ex: Dictionary = _extras.get(m, {})
	for k in ["sh", "gl"]:
		if ex.has(k) and ex[k] != null:
			(ex[k] as Sprite2D).visible = false


## Босс: широкая тень на полу арены и красное свечение, пока идёт замах (TELEGRAPH).
func _decorate_boss(boss: BossLogic, sheet: MonsterSheet, tint: Color) -> void:
	if _boss_shadow == null:
		_boss_shadow = _make_extra(_shadow_tex, false)
		_boss_glow = _make_extra(_halo_tex, true)
	var dead: bool = boss.state == BossLogic.DEAD
	_boss_shadow.visible = _shadow_tex != null and not dead
	_boss_shadow.position = Vector2(boss.center_x * TILE, boss.floor_y * TILE - 1.5).floor()
	_boss_shadow.scale = Vector2(sheet.frame_w * 0.62 / 24.0, 1.7)
	_boss_shadow.modulate.a = 1.0
	var tele: bool = boss.state == BossLogic.TELEGRAPH
	_boss_glow.visible = tele and _halo_tex != null
	if _boss_glow.visible:
		var prog := clampf(boss.t / maxf(boss._tele, 0.01), 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 70.0) if not Settings.reduce_motion else 1.0
		_boss_glow.position = _boss_sprite.position
		var d := sheet.frame_h * 1.25
		_boss_glow.scale = Vector2(d, d) / HALO_PX
		_boss_glow.modulate = Color(1.0, 0.24, 0.1, (0.25 + 0.4 * prog) * (0.75 + 0.25 * pulse))


func _draw() -> void:
	if director == null:
		return
	_draw_slashes()
	_draw_boss_hazards()


func _draw_slashes() -> void:
	if not _slash_checked:
		_slash_checked = true
		var p := "res://art/monsters/fx_slash.png"
		if ResourceLoader.exists(p):
			_slash_tex = load(p)
	for s in director.slashes:
		var k := clampf(float(s["t"]) / SLASH_TIME, 0.0, 0.999)
		var cx := float(s["x"]) * TILE
		var cy := float(s["y"]) * TILE
		var dir := int(s["dir"])
		if _slash_tex != null:
			var f := int(k * SLASH_FRAMES)
			var src := Rect2(f * SLASH_SIZE.x * 3.0, 0.0, SLASH_SIZE.x * 3.0, SLASH_SIZE.y * 3.0)
			# разворот — масштабом по x вокруг точки взмаха (отрицательный размер
			# прямоугольника у draw_texture_rect_region ведёт себя не так, как кажется)
			draw_set_transform(Vector2(cx, cy), 0.0, Vector2(float(dir), 1.0))
			draw_texture_rect_region(_slash_tex, Rect2(-SLASH_SIZE.x / 2.0, -SLASH_SIZE.y / 2.0, SLASH_SIZE.x, SLASH_SIZE.y), src)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var a := 1.0 - k
			draw_arc(Vector2(cx, cy), 20.0, -1.0 if dir > 0 else PI - 1.0 + 0.0, 1.0 if dir > 0 else PI + 1.0, 12,
				Color(1, 1, 1, a), 3.0)


func _draw_boss_hazards() -> void:
	var boss: BossLogic = director.boss
	if boss == null:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 70.0)
	for hz in boss.hazards:
		if bool(hz["done"]):
			continue
		var r: Rect2 = hz["rect"]
		var px := Rect2(r.position * TILE, r.size * TILE)
		var fired: bool = bool(hz["fired"])
		if hz["kind"] == "wave":
			# полоса по полу до удара — куда пойдёт волна; после — сама волна
			if not fired:
				var h := float(hz["h"]) * TILE
				var y := boss.floor_y * TILE - h
				draw_rect(Rect2(boss.left * TILE, y, (boss.right - boss.left) * TILE, h), Color(COL_WARN, 0.12 + 0.12 * pulse))
				draw_rect(Rect2(boss.left * TILE, y, (boss.right - boss.left) * TILE, h), Color(COL_WARN, 0.55), false, 1.0)
			else:
				_draw_wave(px, int(hz["dir"]))
			continue
		if not fired:
			# телеграф: чем ближе удар, тем плотнее заливка
			var warn := float(hz["warn"])
			var total := maxf(boss._tele, 0.01)
			var k := clampf(1.0 - warn / total, 0.0, 1.0)
			draw_rect(px, Color(COL_WARN, 0.10 + 0.22 * k + 0.08 * pulse))
			draw_rect(px, Color(COL_WARN, 0.55 + 0.35 * pulse), false, 1.5)
			# метка на полу — ровно там, куда упадёт
			var fy := boss.floor_y * TILE
			draw_rect(Rect2(px.position.x, fy - 4, px.size.x, 4), Color(COL_WARN, 0.9))
		else:
			draw_rect(px, Color(COL_STRIKE, 0.85))
			draw_rect(Rect2(px.position.x + px.size.x * 0.3, px.position.y, px.size.x * 0.4, px.size.y), Color(1, 1, 1, 0.9))


func _draw_wave(px: Rect2, dir: int) -> void:
	# острый гребень ударной волны: треугольник вдоль пола
	var tip := Vector2(px.position.x + (px.size.x if dir > 0 else 0.0), px.position.y + px.size.y * 0.15)
	var back := Vector2(px.position.x + (0.0 if dir > 0 else px.size.x), px.position.y + px.size.y)
	var pts := PackedVector2Array([Vector2(back.x, px.position.y + px.size.y), tip,
		Vector2(px.position.x + (px.size.x if dir > 0 else 0.0), px.position.y + px.size.y)])
	draw_colored_polygon(pts, Color(COL_STRIKE, 0.9))
	draw_polyline(PackedVector2Array([Vector2(back.x, px.position.y + px.size.y), tip,
		Vector2(px.position.x + (px.size.x if dir > 0 else 0.0), px.position.y + px.size.y)]), Color(1, 1, 1, 0.9), 1.5)

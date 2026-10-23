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

var _sprites: Dictionary = {}
var _boss_sprite: Sprite2D = null
var _slash_tex: Texture2D = null
var _slash_checked := false
var _was_drawing := false

const COL_WARN := Color(0.95, 0.22, 0.18)
const COL_STRIKE := Color(1.0, 0.86, 0.5)


func _ready() -> void:
	z_index = 1


func _process(_dt: float) -> void:
	if director == null or director.player == null:
		return
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
			continue
		s.visible = _fog_visible(int(floor(m.x)), int(floor(m.y)))
		if not s.visible:
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
		s.modulate = tint
	for m: Monster in _sprites.keys():
		if not live.has(m):
			(_sprites[m] as Sprite2D).queue_free()
			_sprites.erase(m)


func _sync_boss() -> void:
	var boss: BossLogic = director.boss
	if boss == null:
		if _boss_sprite != null:
			_boss_sprite.visible = false
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
			var dst := Rect2(cx - SLASH_SIZE.x / 2.0, cy - SLASH_SIZE.y / 2.0, SLASH_SIZE.x, SLASH_SIZE.y)
			if dir < 0:
				dst = Rect2(dst.position.x + dst.size.x, dst.position.y, -dst.size.x, dst.size.y)
			draw_texture_rect_region(_slash_tex, dst, src)
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

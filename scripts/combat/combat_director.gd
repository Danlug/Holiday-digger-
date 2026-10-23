class_name CombatDirector
extends Node
## CombatDirector — оркестр боя глубже 4000: спавн и тик монстров, удар героя
## (автоатака + кнопка + тап по врагу), урон по герою через GameState.take_damage,
## арена и рейдбосс на 10 000. Игровая логика живёт в Monster / MonsterSpawner /
## BossLogic / CombatService (без узлов и окна, под тестами); здесь только
## склейка с миром, героем и фасадами Sfx/Fx/Haptics.
##
## Подключается одной строкой в main.gd: CombatService.attach(self). Горячие
## файлы не правятся: героя читаем (x, y, facing, frozen) и пинаем только
## через его публичные поля (stun_until_msec, vy, digging).
##
## Вне экрана не симулируем (дёшево для веба): тикаются только монстры в
## active_dist от героя, дальше despawn_dist — удаляются.

const TILE := 32
const HERO_HW := 0.38
const HERO_HH := 1.0 / 3.0

signal monster_spawned(m)
signal monster_died(m)
signal hero_hurt(damage: float, source: String)
signal swung(dir: int, hits: int)
signal boss_started
signal boss_finished(victory: bool)

var host: Node = null
var world = null
var fog = null
var player: Node = null
var hud: Node = null
var view_root: Node = null

var cw: CombatWorld
var spawner: MonsterSpawner
var monsters: Array = []
var view: Node2D = null
var ui: CanvasLayer = null
var equip_screen: Node = null

var boss: BossLogic = null
var boss_flash: float = 0.0
var boss_death_t: float = -1.0
var boss_phase_shown: int = 1

var swing_cd: float = 0.0
var swing_total: float = 0.5
var iframes: float = 0.0
var slashes: Array = []

var _kb_left: float = 0.0
var _kb_vx: float = 0.0
var _last_hurt_ms: int = 0
var _regen_acc: float = 0.0
var _stats: Dictionary = {}
var _stats_dirty: bool = true
var _blink_node: CanvasItem = null


func _ready() -> void:
	set_process(true)


## Подключение к живой игре: host — Main с полями world/fog/player/hud/view_root.
func setup(p_host: Node) -> void:
	host = p_host
	world = host.get("world")
	fog = host.get("fog")
	player = host.get("player")
	hud = host.get("hud")
	view_root = host.get("view_root")
	cw = CombatWorld.new(world)
	spawner = MonsterSpawner.new(cw)
	if world != null:
		BossArena.install(world)

	view = load("res://scripts/combat/combat_view.gd").new()
	view.name = "CombatView"
	view.director = self
	if view_root != null:
		view_root.add_child(view)
	else:
		add_child(view)

	ui = load("res://scripts/combat/combat_hud.gd").new()
	ui.name = "CombatHud"
	ui.director = self
	host.add_child(ui)

	equip_screen = load("res://scripts/combat/equipment_screen.gd").new()
	equip_screen.name = "EquipmentLayer"
	equip_screen.director = self
	host.add_child(equip_screen)

	if view_root != null:
		_blink_node = view_root.get_node_or_null("CharacterView")

	MenuRegistry.add("equipment", {
		"icon": CombatData.ui_icon("equip"),
		"title": "Снаряжение",
		"body": "Броня, оружие и ковка из глубинных материалов",
		"order": 35,
		"visible": func() -> bool: return is_unlocked(),
		"badge": func() -> int: return 0,
		"on_press": func() -> void: open_equipment(),
	})

	GameState.died.connect(_on_hero_died)
	GameState.game_event.connect(_on_game_event)
	GameState.ext_changed.connect(func(key: String) -> void:
		if key == CombatService.KEY:
			_stats_dirty = true)


## Экран «Снаряжение» открывается, когда герой дошёл до глубин боя или уже
## что-то нашёл/собрал (в том числе артефакт ультимативного сета).
func is_unlocked() -> bool:
	return GameState.max_depth_reached >= CombatData.start_depth() - 500 or CombatService.has_anything()


func open_equipment() -> void:
	if equip_screen != null and equip_screen.has_method("open"):
		equip_screen.open()


func stats() -> Dictionary:
	if _stats_dirty or _stats.is_empty():
		_stats = CombatService.stats()
		_stats_dirty = false
	return _stats


func hero_info() -> Dictionary:
	return {"x": player.x, "y": player.y, "hw": HERO_HW, "hh": HERO_HH,
		"alive": GameState.is_alive, "on_ground": player.on_ground}


func can_fight() -> bool:
	if player == null or not GameState.is_alive or GameState.house_is_indoors:
		return false
	if bool(player.get("frozen")) or String(player.get("rig_transition")) != "":
		return false
	return true


## Показывать ли кнопку боя: в боевой зоне, на подходе к ней или при живых
## монстрах (в том числе на арене).
func combat_ui_visible() -> bool:
	if player == null or GameState.house_is_indoors or not GameState.is_alive:
		return false
	if bool(player.get("frozen")):
		return false
	return int(floor(player.y)) >= CombatData.start_depth() - 40 or boss != null or not monsters.is_empty()


# ---------------------------------------------------------------------------
# Кадр
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return
	var dt := minf(delta, 0.033)
	cw.tick(dt)
	swing_cd = maxf(0.0, swing_cd - dt)
	iframes = maxf(0.0, iframes - dt)
	boss_flash = maxf(0.0, boss_flash - dt)
	_tick_blink()
	_tick_slashes(dt)

	if not can_fight():
		return

	_tick_knockback(dt)
	_tick_boss(dt)
	if boss == null:
		_tick_spawn(dt)
	_tick_monsters(dt)
	if bool(CombatData.player_cfg("auto_attack", true)) and swing_cd <= 0.0 and _nearest_target(false) != null:
		try_swing()
	_tick_regen(dt)


func _tick_spawn(dt: float) -> void:
	if boss_death_t >= 0.0:
		return
	var depth := int(floor(player.y))
	if depth < CombatData.start_depth() or BossArena.contains_point(player.x, player.y):
		return
	var alive := 0
	for m: Monster in monsters:
		if m.alive:
			alive += 1
	for req in spawner.tick(dt, player.x, player.y, alive):
		spawn(req)


func spawn(req: Dictionary) -> Monster:
	var m := Monster.create(String(req["id"]), float(req["x"]), float(req["y"]), int(floor(float(req["y"]))))
	m.group = int(req.get("group", 0))
	var em: Vector2 = req.get("emerge", Vector2.ZERO)
	m.emerge_pos = em
	monsters.append(m)
	monster_spawned.emit(m)
	return m


func _tick_monsters(dt: float) -> void:
	var active := float(CombatData.spawn_cfg("active_dist", 15.0))
	var despawn := float(CombatData.spawn_cfg("despawn_dist", 20.0))
	var hero := hero_info()
	var hp_pos := Vector2(player.x, player.y)
	for m: Monster in monsters.duplicate():
		var d := Vector2(m.x, m.y).distance_to(hp_pos)
		if d > despawn and m.alive:
			monsters.erase(m)
			continue
		if d > active and m.alive:
			continue
		for e in m.tick(dt, hero, cw.solid):
			_on_monster_event(m, e)
		if m.dead:
			monsters.erase(m)
		elif not m.alive and m.state == "dead":
			monsters.erase(m)


func _on_monster_event(m: Monster, e: Dictionary) -> void:
	match String(e["type"]):
		"hit":
			_hurt_hero(float(e["damage"]), String(e["kind"]), int(e["dir"]), "monster:" + m.id)
		"emerge":
			Fx.burst("dig_stone", Vector2(m.x, m.y) * TILE, 1.5)
			Sfx.play("tile_break")
		"died":
			_on_monster_died(m)


func _on_monster_died(m: Monster) -> void:
	var pos := Vector2(m.x, m.y) * TILE
	Fx.burst("enemy_die", pos)
	Sfx.play("enemy_die")
	CombatService.note_kill(m.id)
	GameState.add_xp(int(m.def.get("xp", 0)))
	GameState.emit_event(&"monster_killed", {"id": m.id, "depth": int(floor(m.y)), "pos": pos})
	var lost := false
	for drop in m.def.get("drops", []):
		if randf() > float(drop.get("chance", 1.0)):
			continue
		var n := randi_range(int(drop.get("min", 1)), int(drop.get("max", 1)))
		var got := GameState.add_item(String(drop["id"]), n)
		if got > 0:
			Fx.float_text(pos + Vector2(0, -10), "+%d %s" % [got, _short_name(String(drop["id"]))], Color8(0xF2, 0xD9, 0x9B))
		else:
			lost = true
	if lost:
		Fx.float_text(pos + Vector2(0, -22), "рюкзак полон", Color8(0xB8, 0x5A, 0x52))
	monster_died.emit(m)


static func _short_name(id: String) -> String:
	var n := CombatData.material_name(id)
	var sp := n.find(" ")
	return n if sp < 0 or n.length() <= 9 else n.substr(0, sp)


# ---------------------------------------------------------------------------
# Удар героя
# ---------------------------------------------------------------------------

## Ближайшая цель в зоне удара: Dictionary {dir, dist} или null.
## wide=true — шире зоны (для тапа по врагу: развернуться и ударить).
func _nearest_target(wide: bool) -> Variant:
	var st := stats()
	var reach := float(st["reach"]) * (1.6 if wide else 1.0)
	var half_h := float(CombatData.player_cfg("swing_height", 1.0)) * 0.5
	var best: Variant = null
	var best_d := 1e9
	for m: Monster in monsters:
		if not m.alive or m.state == "dormant":
			continue
		var dx: float = m.x - player.x
		var gap := absf(dx) - m.hw - HERO_HW
		if gap > reach - HERO_HW * 0.0 or absf(m.y - player.y) > half_h + m.hh:
			continue
		if gap < best_d:
			best_d = gap
			best = {"dir": 1 if dx >= 0.0 else -1, "dist": gap}
	if boss != null and boss.is_active():
		var hb := boss.hurtbox()
		var bx := clampf(player.x, hb.position.x, hb.position.x + hb.size.x)
		var gap2 := absf(bx - player.x) - HERO_HW
		if gap2 <= reach and absf(player.y - clampf(player.y, hb.position.y, hb.position.y + hb.size.y)) <= half_h + 0.5:
			if gap2 < best_d:
				best = {"dir": 1 if boss.center_x >= player.x else -1, "dist": gap2}
	return best


## Удар. dir=0 — по ближайшей цели (или по взгляду). Возвращает true, если
## удар состоялся (не на кулдауне и герой может драться).
func try_swing(dir: int = 0) -> bool:
	if not can_fight() or swing_cd > 0.0:
		return false
	var st := stats()
	var d := dir
	if d == 0:
		var t: Variant = _nearest_target(false)
		d = int(t["dir"]) if t != null else int(player.facing)
	if d == 0:
		d = 1
	swing_total = float(st["cd"])
	swing_cd = swing_total
	player.facing = d
	_do_swing(d, st)
	return true


## Тап по врагу на экране: развернуться к нему и ударить. true — тап пришёлся
## на врага (даже если удар на кулдауне), событие нельзя отдавать джойстику.
func tap_enemy_at(world_px: Vector2) -> bool:
	var cell := world_px / float(TILE)
	for m: Monster in monsters:
		if not m.alive:
			continue
		if m.hurtbox().grow(0.35).has_point(cell):
			try_swing(1 if m.x >= player.x else -1)
			return true
	if boss != null and boss.is_active() and boss.hurtbox().grow(0.2).has_point(cell):
		try_swing(1 if boss.center_x >= player.x else -1)
		return true
	return false


func _do_swing(dir: int, st: Dictionary) -> void:
	var reach := float(st["reach"])
	var half_h := float(CombatData.player_cfg("swing_height", 1.0)) * 0.5
	var x0: float = player.x - 0.15 if dir > 0 else player.x - reach
	var rect := Rect2(x0, player.y - half_h, reach + 0.15, half_h * 2.0)
	var hits := 0
	slashes.append({"x": player.x + float(dir) * 0.85, "y": player.y - 0.1, "dir": dir, "t": 0.0})
	Sfx.play("swing", randf_range(0.95, 1.1))
	for m: Monster in monsters.duplicate():
		if not m.alive:
			continue
		if m.state == "dormant" and m.hurtbox().grow(0.5).intersects(rect):
			pass
		elif not m.hurtbox().intersects(rect):
			continue
		var dmg := float(st["damage"]) * randf_range(0.92, 1.08)
		var dealt := m.take_hit(dmg, dir)
		if dealt <= 0.0:
			continue
		hits += 1
		var pos := Vector2(m.x, m.y) * TILE
		Fx.burst("hit_enemy", pos)
		Sfx.play("hit_enemy", randf_range(0.92, 1.08))
		Fx.float_text(pos + Vector2(0, -12), str(int(round(dealt))), Color8(0xFF, 0xE0, 0x66))
		Haptics.tap()
	if boss != null and boss.is_active() and boss.in_reach(rect):
		var bd := boss.take_hit(float(st["damage"]) * randf_range(0.92, 1.08))
		var hb := boss.hurtbox()
		var bpos := Vector2(hb.get_center().x, hb.position.y + hb.size.y * 0.4) * TILE
		if boss.vulnerable() or bd > 0.0:
			hits += 1
			boss_flash = 0.1
			Fx.burst("hit_enemy", bpos + Vector2(float(-dir) * 20.0, 0.0), 1.4)
			Sfx.play("hit_enemy" if boss.vulnerable() else "hurt_armor", randf_range(0.85, 1.0))
			Fx.float_text(bpos + Vector2(0, -20), str(int(round(bd))),
				Color8(0xFF, 0xE0, 0x66) if boss.vulnerable() else Color8(0x9D, 0x8B, 0x73))
			Haptics.tap()
		else:
			Sfx.play("hurt_armor", 0.8)
	if hits > 0:
		Fx.shake(1.4, 0.06)
	swung.emit(dir, hits)


func _tick_slashes(dt: float) -> void:
	for s in slashes.duplicate():
		s["t"] = float(s["t"]) + dt
		if float(s["t"]) > 0.2:
			slashes.erase(s)


# ---------------------------------------------------------------------------
# Урон по герою
# ---------------------------------------------------------------------------

## raw — урон до брони; dir — сторона, куда отбросить (+1 вправо).
func _hurt_hero(raw: float, kind: String, dir: int, source: String) -> void:
	if not GameState.is_alive or iframes > 0.0 or raw <= 0.0:
		return
	var st := stats()
	var dmg := CombatService.mitigate(raw, kind, st)
	var armored := float(st["reduction"]) >= 0.2
	_last_hurt_ms = Time.get_ticks_msec()
	GameState.take_damage(dmg, source)
	hero_hurt.emit(dmg, source)
	var pos := Vector2(player.x, player.y) * TILE
	Fx.float_text(pos + Vector2(0, -18), "-%d" % int(round(dmg)), Color8(0xFF, 0x70, 0x70))
	if not GameState.is_alive:
		return
	iframes = float(CombatData.player_cfg("iframes_sec", 0.5))
	var stun := float(CombatData.player_cfg("stun_sec", 0.25))
	player.stun_until_msec = float(Time.get_ticks_msec()) + stun * 1000.0
	player.digging = null
	_kb_left = 0.18
	_kb_vx = float(dir) * float(CombatData.player_cfg("knockback_cells", 0.9)) / 0.18 * -1.0
	_kb_vx = -float(dir) * absf(_kb_vx)
	if player.on_ground:
		player.vy = -4.0
	Sfx.play("hurt_armor" if armored else "hurt")
	Fx.shake(3.0, 0.15)
	Fx.flash(Color(1.0, 0.15, 0.15, 0.26), 0.14)
	Haptics.thud()


## Отброс: сдвигаем героя сами, пока он оглушён (Player в стане гасит vx).
func _tick_knockback(dt: float) -> void:
	if _kb_left <= 0.0:
		return
	_kb_left -= dt
	var nx: float = player.x + _kb_vx * dt
	var bx := nx + (HERO_HW if _kb_vx > 0.0 else -HERO_HW)
	if not cw.solid(int(floor(bx)), int(floor(player.y - HERO_HH + 0.02))) \
			and not cw.solid(int(floor(bx)), int(floor(player.y + HERO_HH - 0.02))):
		player.x = clampf(nx, HERO_HW, float(CombatWorld.WIDTH) - HERO_HW)


func _tick_blink() -> void:
	if _blink_node == null or not is_instance_valid(_blink_node):
		return
	if iframes > 0.0:
		var on := int(Time.get_ticks_msec() / 70) % 2 == 0
		_blink_node.modulate.a = 0.45 if on else 1.0
	elif _blink_node.modulate.a != 1.0:
		_blink_node.modulate.a = 1.0


## Восстановление HP в бою: только в военной зоне и после паузы без урона —
## выше 4000 игра остаётся прежней (выше регенерации в ней нет вообще).
func _tick_regen(dt: float) -> void:
	if not CombatService.in_war_zone(int(floor(player.y))):
		return
	if Time.get_ticks_msec() - _last_hurt_ms < int(float(CombatData.player_cfg("regen_delay_sec", 6.0)) * 1000.0):
		return
	if GameState.hp >= GameState.get_max_hp():
		return
	_regen_acc += CombatService.regen_per_sec() * dt
	if _regen_acc >= 1.0:
		GameState.heal(floorf(_regen_acc))
		_regen_acc -= floorf(_regen_acc)


# ---------------------------------------------------------------------------
# Босс
# ---------------------------------------------------------------------------

func boss_fight_active() -> bool:
	return boss != null and boss.is_active()


func _tick_boss(dt: float) -> void:
	if boss_death_t >= 0.0:
		boss_death_t += dt
		if boss_death_t > 3.0:
			boss_death_t = -1.0
			boss = null
		return
	if boss == null:
		if CombatService.boss_defeated():
			return
		var a := BossArena.interior()
		if player.x >= a.position.x and player.x <= a.position.x + a.size.x and player.y >= a.position.y + 1.2 \
				and player.y < a.position.y + a.size.y:
			start_boss_fight()
		return
	for e in boss.tick(dt, hero_info()):
		_on_boss_event(e)


func start_boss_fight(seed_value: int = 0) -> void:
	monsters.clear()
	BossArena.sealed = true
	cw.invalidate()
	boss = BossLogic.new(seed_value)
	boss.start()
	boss_phase_shown = 1
	CombatService.boss_note_attempt()
	if fog != null:
		fog.reveal_around(BossArena.center_x(), float(BossArena.floor_y() - BossArena.height() / 2), 10, 10)
	Sfx.play("boss_roar")
	Sfx.music("mus_boss")
	Fx.shake(6.0, 0.6)
	Haptics.buzz(160)
	boss_started.emit()


func _on_boss_event(e: Dictionary) -> void:
	match String(e["type"]):
		"roar":
			Sfx.play("boss_roar")
			Fx.shake(6.0, 0.5)
			Haptics.buzz(120)
		"phase":
			boss_phase_shown = int(e["phase"])
			CombatService.boss_note_phase(boss_phase_shown)
		"phase_heal":
			GameState.heal(GameState.get_max_hp() * float(e["pct"]))
		"telegraph":
			Sfx.play("warn_low", 1.2 if String(e["kind"]) == "wave" else 1.0, -6.0)
		"strike":
			_boss_strike_fx(String(e["kind"]))
		"hero_hit":
			var hb := boss.hurtbox()
			var dir := 1 if player.x >= hb.get_center().x else -1
			_hurt_hero(float(e["damage"]), String(e["kind"]), dir, "boss:" + String(e["source"]))
		"summon":
			for i in range(int(e["count"])):
				spawn({"id": String(e["id"]), "x": float(e["x"]) + randf_range(-1.2, 1.2),
					"y": float(e["y"]) + randf_range(-0.4, 0.4), "group": 900 + i, "emerge": Vector2.ZERO})
		"vulnerable":
			if bool(e["on"]):
				var hb2 := boss.hurtbox()
				Fx.burst("spark", Vector2(hb2.get_center().x, hb2.position.y + hb2.size.y * 0.45) * TILE, 1.4)
				Sfx.play("pickup_rare", 1.0, -4.0)
		"dead":
			_boss_defeated()


func _boss_strike_fx(kind: String) -> void:
	if kind == "summon":
		Sfx.play("boss_roar", 1.3, -4.0)
		return
	Sfx.play("collapse" if kind != "wave" else "quake")
	Fx.shake(5.0, 0.22)
	for hz in boss.hazards:
		var r: Rect2 = hz["rect"]
		if hz["kind"] == "wave":
			continue
		Fx.burst("dig_stone", Vector2(r.get_center().x, boss.floor_y) * TILE, 1.2)


func _boss_defeated() -> void:
	var boss_id := String(CombatData.section("boss").get("id", "abyss_idol"))
	CombatService.boss_claim_rewards()
	BossArena.sealed = false
	cw.invalidate()
	boss_death_t = 0.0
	var hb := boss.hurtbox()
	var pos := hb.get_center() * TILE
	GameState.emit_event(&"monster_killed", {"id": boss_id, "depth": BossArena.floor_y() - 1, "pos": pos})
	GameState.emit_event(&"boss_defeated", {"id": boss_id})
	for m: Monster in monsters:
		if m.alive:
			m.take_hit(1e9, 1)
	Fx.burst("enemy_die", pos, 3.0)
	Fx.shake(10.0, 1.0)
	Fx.flash(Color(1, 1, 1, 0.6), 0.5)
	Sfx.play("enemy_die", 0.6)
	Sfx.play("quest_done")
	Sfx.music("mus_deep")
	if hud != null and hud.has_method("toast"):
		hud.toast("%s повержен. Награда ждёт на складе в мастерской." % String(CombatData.section("boss").get("name", "Босс")), 5.0)
	boss_finished.emit(true)


# ---------------------------------------------------------------------------
# События и смерть
# ---------------------------------------------------------------------------

func _on_game_event(id: StringName, _data: Dictionary) -> void:
	if id == &"dug" and cw != null:
		cw.invalidate()


func _on_hero_died() -> void:
	monsters.clear()
	iframes = 0.0
	_kb_left = 0.0
	if boss != null:
		boss = null
		boss_death_t = -1.0
		BossArena.sealed = false
		if cw != null:
			cw.invalidate()
		Sfx.music("mus_deep")
		boss_finished.emit(false)
	if spawner != null:
		spawner.reset()

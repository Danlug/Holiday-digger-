class_name JuiceDirector
extends Node
## Режиссёр «сока»: слушает игру и включает звук, частицы, тряску и вибро. Чужой
## код не правится — только подписки:
##   GameState.game_event: dug, picked, sold; а также (если кто-то эмитит)
##     monster_hit {pos, damage}, monster_killed {pos}, boss_started {id},
##     boss_defeated {id}, quest_done {id}, explosion {pos}, collapse {}, quake {};
##   сигналы GameState: hp_changed, leveled_up, died, respawned,
##     survival_warning, artifact_collected, coins_changed, hunger_changed;
##   сигналы и состояние Player: jumped, fell, dig_started, а шаги, приземление,
##     тягу и удары по породе видно по полям on_ground / vx / vy / thrust / digging
##     (так player.gd не пришлось править).
## Музыку выбирает по контексту: поверхность и дом, шахта по глубине, глубина,
## катсцена сюжета, босс, магазин.

const HEAVY_TILES := [
	TileTypes.Type.FOUNDATION, TileTypes.Type.REINFORCED, TileTypes.Type.OBSIDIAN,
	TileTypes.Type.ANCIENT_METAL, TileTypes.Type.HELLSTONE, TileTypes.Type.DARK_MATTER,
	TileTypes.Type.UNIVERSALIUM, TileTypes.Type.ANGEL_STONE, TileTypes.Type.DIVINE_HEART,
	TileTypes.Type.GEOCRYSTAL,
]
const PRECIOUS_TILES := [
	TileTypes.Type.GOLD_ORE, TileTypes.Type.DIAMOND, TileTypes.Type.RUBY,
	TileTypes.Type.EMERALD, TileTypes.Type.PLATINUM_ORE,
]
const RARE_CATEGORIES := ["gem", "exotic", "warzone", "radioactive", "liquid_metal"]

const COL_GOLD := Color("FFE066")
const COL_ITEM := Color("F2E9D0")
const COL_RARE := Color("6FE0D8")
const COL_DMG := Color("FF5570")
const COL_HEAL := Color("4DE094")

var sfx: SfxService
var fx: FxService
var player: Node = null
var story: Node = null

var _prev_on_ground: bool = false
var _prev_vy: float = 0.0
var _step_dist: float = 0.0
var _was_digging: bool = false
var _next_hit: float = 0.0
var _thrust_prev: String = ""

var _last_hp: float = -1.0
var _hp_drip: float = 0.0
var _last_hunger: float = -1.0
var _respawn_quiet_until: int = 0
var _coins_prev: int = -1
var _coin_pending_since: int = 0
var _sold_msec: int = -100000

var _boss_active: bool = false
var _music_timer: float = 0.0
var _music_hold_until: float = 0.0
var _music_want: String = ""
var _music_want_since: float = 0.0
var _clock: float = 0.0

var _connected: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_find_nodes()
	_connect_signals()


func _find_nodes() -> void:
	var host := get_parent()
	if player == null and host != null:
		if "player" in host and host.player != null:
			player = host.player
		else:
			player = host.find_child("Player", true, false)
	if story == null and host != null:
		story = host.get_node_or_null("StoryDirector")
	if sfx == null:
		sfx = get_tree().get_first_node_in_group(Sfx.GROUP) as SfxService
	if fx == null:
		fx = get_tree().get_first_node_in_group(Fx.GROUP) as FxService


func _connect_signals() -> void:
	if _connected:
		return
	_connected = true
	GameState.game_event.connect(_on_event)
	GameState.hp_changed.connect(_on_hp)
	GameState.hunger_changed.connect(_on_hunger)
	GameState.leveled_up.connect(_on_level)
	GameState.died.connect(_on_died)
	GameState.respawned.connect(_on_respawned)
	GameState.survival_warning.connect(_on_warning)
	GameState.artifact_collected.connect(_on_artifact)
	GameState.coins_changed.connect(_on_coins)
	_last_hp = GameState.hp
	_last_hunger = GameState.hunger
	_coins_prev = GameState.coins
	if player != null:
		if player.has_signal("jumped"):
			player.jumped.connect(_on_jump)
		if player.has_signal("fell"):
			player.fell.connect(_on_fell)
	if fx != null:
		fx.flier_landed.connect(_on_flier_landed)
		fx.magnet_target = _chest


func _exit_tree() -> void:
	if not _connected:
		return
	_connected = false
	_disconnect(GameState.game_event, _on_event)
	_disconnect(GameState.hp_changed, _on_hp)
	_disconnect(GameState.hunger_changed, _on_hunger)
	_disconnect(GameState.leveled_up, _on_level)
	_disconnect(GameState.died, _on_died)
	_disconnect(GameState.respawned, _on_respawned)
	_disconnect(GameState.survival_warning, _on_warning)
	_disconnect(GameState.artifact_collected, _on_artifact)
	_disconnect(GameState.coins_changed, _on_coins)


func _disconnect(sig: Signal, c: Callable) -> void:
	if sig.is_connected(c):
		sig.disconnect(c)


# ---------------------------------------------------------------------------
# Покадровое: герой и музыка
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	if player != null and is_instance_valid(player):
		_tick_player(delta)
	_tick_coin_sound()
	_tick_transitions()
	_music_timer -= delta
	if _music_timer <= 0.0:
		_music_timer = 0.4
		_tick_music()


## Переходы: затемнение при выходе из дома и входе в шахту, цветная вспышка на смене пояса глубины.
## Первый кадр только запоминает состояние — вспышек при загрузке игры нет.
var _tr_ready: bool = false
var _tr_indoors: bool = false
var _tr_belt: int = 0
var _tr_underground: bool = false
var _tr_depth: int = 0


func _tick_transitions() -> void:
	var indoors := GameState.house_is_indoors
	var depth := int(GameState.player_depth)
	var belt := Biomes.index_at(depth)
	var underground := depth >= 6 if not _tr_underground else depth >= 2
	if not _tr_ready:
		_tr_ready = true
		_tr_indoors = indoors
		_tr_belt = belt
		_tr_underground = underground
		_tr_depth = depth
		return
	var jumped := absi(depth - _tr_depth) > 40   # телепорт, респаун, падение сквозь пояс: без вспышек
	_tr_depth = depth
	if indoors != _tr_indoors:
		_tr_indoors = indoors
		Fx.flash(Color(0.02, 0.01, 0.01, 0.9), 0.4)    # дверь: выезжаем из чёрного
	elif underground != _tr_underground:
		_tr_underground = underground
		if not jumped:
			Fx.flash(Color(0.02, 0.01, 0.01, 0.42 if underground else 0.3), 0.32)
	if belt != _tr_belt:
		var deeper := belt > _tr_belt
		_tr_belt = belt
		if GameState.is_alive and not indoors and not jumped:
			var tc: Color = LightLayer.belt_colors(float(depth)).torch
			Fx.flash(Color(tc.r, tc.g, tc.b, 0.3 if deeper else 0.18), 0.55)


func _feet() -> Vector2:
	return Vector2(player.x, player.y + 0.33) * 32.0


func _head() -> Vector2:
	return Vector2(player.x, player.y - 0.9) * 32.0


func _tick_player(delta: float) -> void:
	var frozen: bool = bool(player.get("frozen")) if "frozen" in player else false
	var on_ground: bool = player.on_ground
	var vy: float = player.vy

	# приземление: скорость берём с прошлого кадра — в этом физика её уже обнулила
	if on_ground and not _prev_on_ground and _prev_vy > Juice.num("steps.land_min_speed", 3.0) and not frozen:
		var k := clampf(_prev_vy / 20.0, 0.25, 1.0)
		Sfx.play("land", 1.0 - 0.18 * k, linear_to_db(k))
		Fx.burst("poof", _feet(), 0.3 + 0.5 * k)
		# пыль стелется по земле в обе стороны, сильнее при жёстком приземлении
		Fx.burst("land_dust_l", _feet() + Vector2(-5, 0), 0.5 + k)
		Fx.burst("land_dust_r", _feet() + Vector2(5, 0), 0.5 + k)
		if k > 0.6:
			Fx.shake(2.0 * k, 0.12)
			Haptics.tap()

	# шаги — по пройденному пути, звук по грунту под ногами
	if on_ground and absf(player.vx) > 0.1 and player.digging == null and not frozen:
		_step_dist += absf(player.vx) * delta
		if _step_dist >= Juice.num("steps.distance_cells", 0.85):
			_step_dist = 0.0
			Sfx.play(_step_id(), 1.0, 0.0)
	else:
		_step_dist = minf(_step_dist, 0.5)

	# тяга ранца
	var thrust: String = player.thrust
	if thrust != _thrust_prev:
		if thrust != "":
			Sfx.play("fly_start")
			Sfx.loop_start("fly_loop", 0.0, 1.0 if thrust == "prop" else 1.3)
		else:
			Sfx.loop_stop("fly_loop", 0.18)
			if _thrust_prev != "":
				Sfx.play("fly_stop")
		_thrust_prev = thrust

	# удары по породе, пока копка идёт
	var d = player.digging
	if d != null:
		if not _was_digging:
			_was_digging = true
			_next_hit = Feel.hit_period(GameState.current_tool) * 0.5
		var t: float = d["t"]
		var total: float = d["total"]
		if t >= _next_hit:
			_next_hit += Feel.hit_period(GameState.current_tool)
			if t < total - 0.12:
				_dig_strike(d)
	else:
		_was_digging = false

	_prev_on_ground = on_ground
	_prev_vy = vy


func _step_id() -> String:
	if player.cell_y() <= 0:
		return "step_grass"
	var world = player.get("world")
	if world == null:
		return "step"
	var t: int = world.get_tile(player.cell_x(), player.cell_y() + 1)
	return "step" if t == TileTypes.Type.DIRT or t == TileTypes.Type.EMPTY else "step_stone"


func _dig_strike(d: Dictionary) -> void:
	var tile: int = d["type"]
	var center := Vector2(float(d["x"]) * 32.0 + 16.0, float(d["y"]) * 32.0 + 16.0)
	var toward := (Vector2(player.x, player.y) * 32.0 - center)
	var spot := center + (toward.normalized() * 13.0 if toward.length() > 1.0 else Vector2.ZERO)
	# высота и громкость удара зависят от инструмента: лопата глуше и выше, бур дробит, бурмобиль гудит
	var prof := Feel.tool_profile(GameState.current_tool)
	Sfx.play(_dig_sound(tile), randf_range(0.9, 1.0) * float(prof["pitch"]), float(prof["db"]))
	_dig_burst(tile, spot, 0.4)


# ---------------------------------------------------------------------------
# Копка и добыча
# ---------------------------------------------------------------------------

func _dig_sound(tile: int) -> String:
	if tile == TileTypes.Type.DIRT or tile == TileTypes.Type.PEAT:
		return "dig_dirt"
	if tile == TileTypes.Type.STONE:
		return "dig_stone"
	if HEAVY_TILES.has(tile):
		return "dig_hard"
	if PRECIOUS_TILES.has(tile):
		return "dig_gold"
	return "dig_ore"


func _dig_burst(tile: int, pos: Vector2, amount: float) -> void:
	if tile == TileTypes.Type.DIRT or tile == TileTypes.Type.PEAT:
		Fx.burst("dig_dirt", pos, amount)
		Fx.burst("dig_puff", pos, amount)
	elif tile == TileTypes.Type.STONE or HEAVY_TILES.has(tile):
		Fx.burst("dig_stone", pos, amount)
		Fx.burst("dig_puff", pos, amount * 0.8)
		if HEAVY_TILES.has(tile):
			Fx.burst("spark", pos, amount * 0.6)   # твёрдая порода искрит под кайлом
	elif tile == TileTypes.Type.GOLD_ORE:
		Fx.burst("dig_gold", pos, amount)
		Fx.burst("ore_glint", pos, amount, COL_GOLD)
	else:
		var accent := _accent(tile)
		Fx.burst("dig_ore", pos, amount, accent)
		Fx.burst("ore_glint", pos, amount, accent if accent.a > 0.0 else COL_RARE)


## Блёстки добычи летят к герою магнитом (FxService.magnet): цвет — вкрапления руды, у золота золотой.
func _magnet(tile: int, pos: Vector2) -> void:
	var n := fx if fx != null else get_tree().get_first_node_in_group(Fx.GROUP)
	if n == null or not n.has_method("magnet") or player == null:
		return
	var col := COL_ITEM
	if tile == TileTypes.Type.GOLD_ORE:
		col = COL_GOLD
	elif tile != TileTypes.Type.DIRT and tile != TileTypes.Type.PEAT and tile != TileTypes.Type.STONE:
		var a := _accent(tile)
		if a.a > 0.0:
			col = a.lightened(0.3)
	n.call("magnet", pos, col, 3)


func _chest() -> Vector2:
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO
	return Vector2(player.x, player.y - 0.15) * 32.0


func _accent(tile: int) -> Color:
	var n := fx if fx != null else get_tree().get_first_node_in_group(Fx.GROUP)
	if n != null and n.has_method("tile_accent"):
		return n.call("tile_accent", tile)
	return Color(0, 0, 0, 0)


func _on_event(id: StringName, data: Dictionary) -> void:
	match id:
		&"dug":
			var tile := int(data.get("tile", 0))
			var pos: Vector2 = data.get("pos", Vector2.ZERO)
			Sfx.play(_dig_sound(tile))
			_dig_burst(tile, pos, 1.3)
			if bool(data.get("loot", false)):
				_magnet(tile, pos)
			if HEAVY_TILES.has(tile) or tile == TileTypes.Type.STONE:
				Fx.shake(Juice.num("dig.heavy_shake_px", 2.5), Juice.num("dig.heavy_shake_s", 0.12))
			if HEAVY_TILES.has(tile):
				Haptics.thud()
			elif bool(data.get("loot", false)):
				Haptics.tap()
		&"picked":
			_on_picked(String(data.get("item", "")), int(data.get("count", 1)))
		&"sold":
			_on_sold(int(data.get("coins", 0)))
		&"monster_hit":
			var hp: Vector2 = data.get("pos", _feet())
			Sfx.play("hit_enemy")
			Fx.burst("hit_enemy", hp, 1.0)
			Fx.burst("hit_flash", hp, 1.0)   # белая вспышка попадания поверх красных брызг
			Fx.burst("spark", hp, 0.6)
			var dmg := int(data.get("damage", 0))
			if dmg > 0:
				Fx.float_text(hp + Vector2(0, -10), str(dmg), COL_DMG)
		&"monster_killed":
			var mp: Vector2 = data.get("pos", _feet())
			Sfx.play("enemy_die")
			Fx.burst("enemy_die", mp, 1.0)
			Fx.burst("die_smoke", mp + Vector2(0, -4), 1.0)
			Fx.burst("hit_flash", mp, 1.0)
			Fx.burst("spark", mp, 0.8)
			Fx.shake(1.5, 0.1)
			Haptics.tap()
		&"boss_started":
			_boss_active = true
			Sfx.play("boss_roar")
			Fx.shake(5.0, 0.6)
			Haptics.buzz(120)
		&"boss_failed":
			# герой погиб на арене: музыка босса не должна пережить бой (ветка combat)
			_boss_active = false
		&"boss_defeated":
			_boss_active = false
			Sfx.play("levelup")
			Fx.flash(Color(1, 0.95, 0.7, 0.5), 0.5)
			Fx.shake(4.0, 0.4)
			if player != null:
				Fx.burst("levelup", _head(), 1.5)
			Haptics.buzz(150)
		&"quest_done":
			Sfx.play("quest_done")
			Haptics.tap()
		&"explosion":
			var ep: Vector2 = data.get("pos", _feet())
			Sfx.play("explosion")
			Fx.burst("fire", ep, 1.6)
			Fx.burst("poof", ep, 1.5)
			Fx.shake(6.0, 0.4)
			Haptics.buzz(140)
		&"collapse":
			# обвал случается «где-то в шахте», не рядом с героем — глуше и слабее
			Sfx.play("collapse", 1.0, -5.0)
			Fx.shake(2.0, 0.4)
			Haptics.thud()
		&"quake":
			if player != null:
				# с потолка сыплются камни и пыль: два залпа по бокам от героя и облако у пола
				Fx.burst("rock_fall", _head() + Vector2(-52, -96), 1.0)
				Fx.burst("rock_fall", _head() + Vector2(46, -110), 1.0)
				Fx.burst("dig_puff", _head() + Vector2(0, -80), 1.4)
				Fx.burst("poof", _feet(), 1.2)
			Sfx.play("quake")
			Fx.shake(5.0, 1.8)
			Haptics.buzz(220)


func _is_rare(item: String) -> bool:
	var m := Balance.get_mineral(item)
	if m.is_empty():
		return false
	if RARE_CATEGORIES.has(String(m.get("category", ""))):
		return true
	return Balance.get_mineral_price(item) >= int(Juice.num("rare_price", 100.0))


func _item_icon(item: String) -> Texture2D:
	var drawn := ShopArt.tex("item_" + item)   # нарисованный значок ресурса
	if drawn != null:
		return drawn
	var tile := MineralMap.tile_type_for(item)
	if tile >= 0:
		return TileArt.texture_for(tile, 0, 0)
	return null


func _on_picked(item: String, count: int) -> void:
	var rare := _is_rare(item)
	Sfx.play("pickup_rare" if rare else "pickup")
	if player == null:
		return
	var at := _head() + Vector2(randf_range(-7.0, 7.0), randf_range(-4.0, 2.0))
	# подряд добытое одно и то же сливается в одно «+N» (aaa-feel); старые заглушки Fx метода не знают
	Fx.float_stack(item, at, _item_icon(item), count, COL_RARE if rare else COL_ITEM, Feel.num("loot.stack_window_s", 0.75))
	Fx.burst("pickup_glint", at, 1.0 if rare else 0.6)
	if rare:
		Fx.burst("spark", at, 1.0)


func _on_sold(coins: int) -> void:
	_sold_msec = Time.get_ticks_msec()
	Sfx.play("coins_big")
	Haptics.tap()
	if coins > 0:
		var n := clampi(int(ceil(float(coins) / 60.0)) + 3, 4, 10)
		Fx.fly_to(null, Vector2(112, 300), HudAnchors.get_anchor("coins"), n)


func _on_flier_landed(_target: Vector2, index: int, total: int) -> void:
	Sfx.play("coin", 1.0 + 0.04 * float(index) / float(maxi(total, 1)), -4.0)


# ---------------------------------------------------------------------------
# Деньги
# ---------------------------------------------------------------------------

func _on_coins(coins: int) -> void:
	if coins > _coins_prev and _coin_pending_since == 0:
		_coin_pending_since = Time.get_ticks_msec()
	_coins_prev = coins


## Звук монеты откладывается на кадр: продажа в мастерской сперва меняет
## кошелёк, а потом эмитит sold — и у продажи свой, большой звук.
func _tick_coin_sound() -> void:
	if _coin_pending_since == 0:
		return
	var now := Time.get_ticks_msec()
	if now - _coin_pending_since < 30:
		return
	_coin_pending_since = 0
	if now - _sold_msec < 400:
		return
	Sfx.play("coin")


# ---------------------------------------------------------------------------
# Герой: урон, лечение, уровень, смерть
# ---------------------------------------------------------------------------

func _on_hp(hp: float, max_hp: float) -> void:
	var prev := _last_hp
	_last_hp = hp
	if prev < 0.0 or Time.get_ticks_msec() < _respawn_quiet_until:
		return
	var diff := hp - prev
	if diff < 0.0:
		if hp <= 0.0:
			return  # смерть озвучит died
		var dmg := -diff
		if dmg >= Juice.num("damage.hurt_min_hp", 1.5):
			_hurt(dmg, max_hp, 1.0)
		else:
			# голод точит HP каплями каждый кадр — копим до порога
			_hp_drip += dmg
			if _hp_drip >= Juice.num("damage.drip_hp", 3.0):
				_hp_drip = 0.0
				_hurt(dmg, max_hp, 0.5)
	elif diff >= 1.0 and max_hp > 0.0:
		Sfx.play("heal")
		if player != null:
			Fx.burst("heal", _head(), 1.0)
			Fx.float_text(_head() + Vector2(0, -6), "+%d" % int(round(diff)), COL_HEAL)


func _hurt(dmg: float, max_hp: float, k: float) -> void:
	var share := clampf(dmg / maxf(max_hp, 1.0), 0.0, 1.0)
	Sfx.play("hurt", 1.0, linear_to_db(clampf(0.55 + share * 2.0, 0.55, 1.0) * k))
	Fx.flash(Color(0.85, 0.08, 0.1, clampf(0.18 + share * 1.2, 0.18, 0.5) * k), 0.25)
	if k >= 1.0:
		Haptics.thud()
		Fx.shake(clampf(1.5 + share * 8.0, 1.5, 5.0), 0.18)
		if player != null:
			Fx.float_text(_head(), "-%d" % int(round(dmg)), COL_DMG)


func _on_fell(damage: float, _speed: float) -> void:
	Sfx.play("thud", 1.0, linear_to_db(clampf(damage / 20.0, 0.4, 1.0)))
	Fx.burst("poof", _feet(), 1.4)
	Fx.burst("dig_stone", _feet(), 0.8)


func _on_hunger(h: float) -> void:
	var prev := _last_hunger
	_last_hunger = h
	if prev >= 0.0 and h - prev >= 4.0 and Time.get_ticks_msec() >= _respawn_quiet_until:
		Sfx.play("eat")


func _on_level(new_level: int, _points: int) -> void:
	Sfx.play("levelup")
	Fx.flash(Color(1, 0.9, 0.45, 0.35), 0.4)
	Haptics.buzz(80)
	if player != null:
		Fx.burst("levelup", _head() + Vector2(0, 8), 1.0)
		Fx.float_text(_head() + Vector2(0, -8), "УР. %d" % new_level, COL_GOLD)


func _on_died() -> void:
	Sfx.play("die")
	Fx.flash(Color(0.5, 0.0, 0.05, 0.6), 0.7)
	Fx.shake(6.0, 0.35)
	Haptics.buzz(200)
	Sfx.stop_music(0.8)
	_music_want = ""
	# музыка не возвращается, пока звучит «die» (катсцена сюжета не ждёт)
	_music_hold_until = _clock + 3.0


func _on_respawned() -> void:
	# respawn() возвращает HP и сытость — это не лечение и не еда
	_respawn_quiet_until = Time.get_ticks_msec() + 300
	_last_hp = GameState.hp
	_last_hunger = GameState.hunger
	Sfx.play("respawn")


func _on_warning(_bar: String, severe: bool) -> void:
	Sfx.play("warn_low", 1.0 if severe else 0.9, 0.0 if severe else -4.0)
	if severe:
		Haptics.buzz(60)
		Fx.flash(Color(0.9, 0.5, 0.1, 0.18), 0.3)
	else:
		Haptics.tap()


func _on_artifact(_id: String) -> void:
	Sfx.play("artifact")
	Fx.flash(Color(1, 0.95, 0.75, 0.45), 0.55)
	Fx.shake(2.0, 0.2)
	Haptics.buzz(100)
	# искры на герое пускает ArtifactFinder — второй раз не дублируем


func _on_jump() -> void:
	Sfx.play("jump")
	if player != null:
		Fx.burst("jump_puff", _feet(), 1.0)


# ---------------------------------------------------------------------------
# Музыка по контексту
# ---------------------------------------------------------------------------

func music_for_context() -> String:
	if not GameState.is_alive:
		return ""
	if _boss_active:
		return "mus_boss"
	if story_playing():
		return "mus_story"
	if ShopUI.instance != null and ShopUI.instance.is_open():
		return "mus_shop"
	if GameState.house_is_indoors:
		return "mus_surface"
	var depth := int(GameState.player_depth)
	if depth < int(Juice.num("music.mine_from", 5.0)):
		return "mus_surface"
	if depth >= int(Juice.num("music.deep_from", 4000.0)):
		return "mus_deep"
	if depth >= int(Juice.num("music.mine2_from", 1500.0)):
		return "mus_mine_2"
	return "mus_mine_1"


func story_playing() -> bool:
	if story == null or not is_instance_valid(story):
		# режиссёр сюжета подключается в main.gd позже нас — ищем лениво
		story = get_parent().get_node_or_null("StoryDirector") if get_parent() != null else null
		if story == null:
			return false
	var cs = story.get("cutscene")
	return cs != null and bool(cs.get("is_playing"))


func _tick_music() -> void:
	var want := music_for_context()
	if want == "":
		return  # тишину после смерти ведёт died, возрождение вернёт трек
	if _clock < _music_hold_until and want != "mus_story" and want != "mus_boss":
		return
	if want != _music_want:
		_music_want = want
		_music_want_since = _clock
	if want == Sfx.current_music():
		return
	var urgent := want == "mus_story" or want == "mus_boss" or Sfx.current_music() == "" \
			or Sfx.current_music() == "mus_story" or Sfx.current_music() == "mus_boss"
	if not urgent and _clock - _music_want_since < Juice.num("music.switch_delay_s", 1.2):
		return
	var fade := Juice.num("music.fade_s", 2.5)
	if want == "mus_story":
		fade = Juice.num("music.fade_story_s", 1.5)
	elif want == "mus_boss":
		fade = Juice.num("music.fade_boss_s", 0.6)
	Sfx.music(want, fade)

extends Node
## test_juice — «сок» игры: сервис звука (каталог, пул, приоритеты, музыка,
## кроссфейд, жест в вебе), сервис эффектов (пул частиц, потолок, всплывающие
## числа, тряска, вспышка, летящие иконки) и режиссёр (подписки на сигналы игры
## и опрос состояния героя). Звук в headless не слышен — проверяются состояния.
##
## Запуск: godot --headless --path . res://tests/test_juice.tscn

var failures := 0
var total := 0

const CORE_IDS := [
	"ui_tap", "ui_open", "ui_close", "ui_tab", "ui_toggle", "ui_buy", "ui_deny", "ui_slider",
	"coin", "coins_big", "sell", "dig_dirt", "dig_stone", "dig_ore", "dig_gold", "dig_hard", "tile_break",
	"step", "jump", "land", "fly_start", "fly_stop", "thud", "hurt", "die", "respawn", "eat", "drink",
	"heal", "warn_low", "pickup", "pickup_rare", "levelup", "skill_buy", "artifact", "quest_done", "reward",
	"quake", "collapse", "lava_hiss", "door", "phone", "swing", "hit_enemy", "enemy_die", "boss_roar", "hurt_armor",
]
const MUSIC_IDS := ["mus_surface", "mus_mine_1", "mus_mine_2", "mus_deep", "mus_boss", "mus_story", "mus_shop", "mus_menu"]
const LONG_IDS := ["artifact", "boss_roar", "coins_big", "collapse", "die", "explosion", "heal", "lava_hiss", "levelup",
	"phone", "pickup_rare", "quake", "quest_done", "respawn", "reward", "sell", "skill_buy", "dig_gold"]


func check(name: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] ", name)
	else:
		print("[OK] ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== test_juice ===")
	await _frames(2)
	await _test_sfx_service()
	await _test_fx_service()
	await _test_director()
	await _test_integration()
	await _test_attach()
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# Сервис звука
# ---------------------------------------------------------------------------

func _test_sfx_service() -> void:
	var sfx := SfxService.new()
	add_child(sfx)
	await _frames(1)
	check("сервис звука стоит в группе Sfx.GROUP", get_tree().get_first_node_in_group(Sfx.GROUP) == sfx)
	check("пул голосов создан", sfx.pool_size() == SfxService.POOL_SIZE)
	check("шины SFX и Music существуют", AudioServer.get_bus_index(Settings.BUS_SFX) != -1
			and AudioServer.get_bus_index(Settings.BUS_MUSIC) != -1)
	var limiters := 0
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			limiters += 1
	check("на мастер-шине стоит ровно один лимитер", limiters == 1)
	var missing: Array = []
	for id in CORE_IDS:
		if not sfx.has_sfx(id):
			missing.append(id)
	check("каталог покрывает шапку sfx.gd (нет: %s)" % str(missing), missing.is_empty())
	check("есть step_grass, step_stone, fly_loop, explosion",
			sfx.has_sfx("step_grass") and sfx.has_sfx("step_stone") and sfx.has_sfx("fly_loop") and sfx.has_sfx("explosion"))
	var mus_missing: Array = []
	for id in MUSIC_IDS:
		if not sfx.has_music(id):
			mus_missing.append(id)
	check("все треки каталога (нет: %s)" % str(mus_missing), mus_missing.is_empty())

	# каждый файл каталога грузится и не пуст
	var bad: Array = []
	for id in sfx.sfx_ids():
		for s in sfx._defs[id]["streams"]:
			if s == null or s.get_length() <= 0.0:
				bad.append(id)
	check("ресурсы эффектов грузятся (битые: %s)" % str(bad), bad.is_empty())
	var lens_bad: Array = []
	for id in ["mus_surface", "mus_mine_1", "mus_mine_2", "mus_deep", "mus_boss", "mus_story", "mus_shop"]:
		var def := sfx._resolve_music(id)
		var st := load(SfxService.AUDIO_DIR + String(def["file"])) as AudioStream
		if st == null or st.get_length() < 40.0 or st.get_length() > 90.0:
			lens_bad.append(id)
	check("музыка 40–90 с и грузится (нет: %s)" % str(lens_bad), lens_bad.is_empty())

	# неизвестное
	check("неизвестный id звука игнорируется", sfx.play("нет_такого_звука") == false)
	sfx.music("нет_такого_трека", 0.1)
	check("неизвестный id музыки игнорируется", sfx.current_music() == "")

	# разовый звук: высота варьируется в пределах разброса
	var pitches: Array = []
	for i in 24:
		sfx._last_ms.clear()
		sfx.play("coin")
		for p in sfx._pool:
			if p.playing and p.stream != null:
				pitches.append(p.pitch_scale)
		_stop_all(sfx)
	var pmin: float = pitches.min()
	var pmax: float = pitches.max()
	check("высота звука слегка случайна и в разбросе (%.3f..%.3f)" % [pmin, pmax], pmax - pmin > 0.01 and pmin >= 0.92 and pmax <= 1.08)
	_stop_all(sfx)

	# «остывание»
	sfx._last_ms.clear()
	var first := sfx.play("coin")
	var second := sfx.play("coin")
	check("повтор в пределах cooldown отбрасывается", first and not second)
	_stop_all(sfx)

	# потолок голосов одного id
	var same_max := 0
	for i in 8:
		sfx._last_ms.clear()
		sfx.play("dig_dirt")
		var n := 0
		for k in sfx._pool.size():
			if sfx._pool[k].playing and sfx._meta[k]["id"] == "dig_dirt":
				n += 1
		same_max = maxi(same_max, n)
	check("одновременных голосов одного id не больше потолка (%d)" % same_max, same_max <= 3 and same_max >= 1)
	_stop_all(sfx)

	# пул не переполняется
	var played := 0
	for i in 300:
		sfx._last_ms.clear()
		if sfx.play(CORE_IDS[i % CORE_IDS.size()]):
			played += 1
	check("пул не переполняется (активно %d из %d)" % [sfx.active_voices(), sfx.pool_size()], sfx.active_voices() <= sfx.pool_size())
	_stop_all(sfx)

	# приоритеты при полном пуле: тихие шаги теряются, фанфара вытесняет
	for id in LONG_IDS:
		sfx._last_ms.clear()
		sfx.play(id)
	check("пул забит долгими звуками (%d)" % sfx.active_voices(), sfx.active_voices() == sfx.pool_size())
	sfx._last_ms.clear()
	var dropped_before: int = sfx.stats["dropped"]
	var step_ok := sfx.play("step")
	check("при полном пуле звук низшего приоритета теряется", not step_ok and sfx.stats["dropped"] == dropped_before + 1)
	sfx._last_ms.clear()
	check("при полном пуле важный звук вытесняет слабый", sfx.play("levelup"))
	check("и пул всё равно не вырос", sfx.active_voices() <= sfx.pool_size())
	check("фанфара приглушает музыку (duck)", sfx._duck_target < 0.0)
	_stop_all(sfx)

	# музыка
	sfx.music("mus_surface", 0.1)
	var active_player: AudioStreamPlayer = sfx._music[sfx._music_active]
	check("music() включает трек", sfx.current_music() == "mus_surface" and active_player.playing)
	check("трек зациклен", "loop" in active_player.stream and active_player.stream.loop)
	await get_tree().create_timer(0.3).timeout
	check("кроссфейд-вход дошёл до полной громкости", is_equal_approx(sfx._music_fade[sfx._music_active], 0.0))
	sfx.music("mus_mine_1", 0.25)
	var playing_now := 0
	for m in sfx._music:
		if m.playing:
			playing_now += 1
	check("во время кроссфейда играют оба трека", playing_now == 2 and sfx.current_music() == "mus_mine_1")
	await get_tree().create_timer(0.45).timeout
	playing_now = 0
	for m in sfx._music:
		if m.playing:
			playing_now += 1
	check("после кроссфейда играет один трек", playing_now == 1)
	var act_before := sfx._music_active
	sfx.music("mus_shop", 0.05)
	await get_tree().create_timer(0.15).timeout
	var act_shop := sfx._music_active
	sfx.music("mus_menu", 0.05)
	check("mus_menu — тот же файл, что mus_shop: трек не перезапускается",
			sfx._music_active == act_shop and act_before != act_shop and sfx.current_music() == "mus_menu")
	sfx.music("mus_menu", 0.05)
	sfx.stop_music(0.1)
	check("stop_music сбрасывает текущий трек", sfx.current_music() == "")
	await get_tree().create_timer(0.3).timeout
	playing_now = 0
	for m in sfx._music:
		if m.playing:
			playing_now += 1
	check("после stop_music тишина", playing_now == 0)

	# зацикленный гул
	sfx.loop_start("fly_loop", 0.0, 1.0)
	check("loop_start включает гул", sfx.is_looping("fly_loop"))
	sfx.loop_stop("fly_loop", 0.05)
	sfx.loop_start("fly_loop")
	await get_tree().create_timer(0.2).timeout
	check("повторный loop_start во время затухания не глушится", sfx.is_looping("fly_loop"))
	sfx.loop_stop("fly_loop", 0.05)
	await get_tree().create_timer(0.2).timeout
	check("loop_stop глушит гул", not sfx.is_looping("fly_loop"))
	check("fly_loop зациклен", (sfx._loops["fly_loop"].stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED)
	check("loop_start на обычном звуке ничего не делает", (func() -> bool:
		sfx.loop_start("coin")
		return not sfx.is_looping("coin")).call())

	# веб: ничего не играет до первого жеста, музыка ждёт
	sfx.require_gesture = true
	sfx.unlocked = false
	check("до жеста разовый звук не играет", sfx.play("coin") == false)
	sfx.music("mus_story", 0.1)
	var any_playing := false
	for m in sfx._music:
		any_playing = any_playing or m.playing
	check("до жеста музыка ждёт, не играя", not any_playing and sfx.current_music() == "mus_story")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	sfx._input(ev)
	check("первое нажатие разблокирует звук", sfx.unlocked)
	any_playing = false
	for m in sfx._music:
		any_playing = any_playing or m.playing
	check("после жеста отложенная музыка включается", any_playing)
	sfx.require_gesture = false
	sfx.stop_music(0.01)
	_stop_all(sfx)
	sfx.queue_free()
	await _frames(2)


func _cdist(a: Color, b: Color) -> float:
	return (a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b)


func _stop_all(sfx: SfxService) -> void:
	for p in sfx._pool:
		p.stop()


# ---------------------------------------------------------------------------
# Сервис эффектов
# ---------------------------------------------------------------------------

func _test_fx_service() -> void:
	var fx := FxService.new()
	add_child(fx)
	await _frames(2)
	check("сервис эффектов стоит в группе Fx.GROUP", get_tree().get_first_node_in_group(Fx.GROUP) == fx)
	check("пул эмиттеров создан", fx.pool_size() >= 8)
	var kinds := ["dig_dirt", "dig_stone", "dig_ore", "dig_gold", "spark", "poof", "hit_enemy", "enemy_die", "levelup", "coins", "heal", "fire"]
	var unknown: Array = []
	for k in kinds:
		if not fx.has_kind(k):
			unknown.append(k)
	check("все виды частиц из шапки fx.gd описаны (нет: %s)" % str(unknown), unknown.is_empty())
	for k in kinds:
		fx.burst(k, Vector2(60, 60), 1.0)
	check("вспышка каждого вида не ломает сервис (живых %d)" % fx.active_particles(), fx.active_particles() <= fx.max_particles)
	fx.burst("нет_такого_вида", Vector2.ZERO)
	check("неизвестный вид частиц игнорируется", true)
	for i in 120:
		fx.burst("levelup", Vector2(i, 40), 2.0)
	check("потолок частиц держится (живых %d из %d)" % [fx.active_particles(), fx.max_particles],
			fx.active_particles() <= fx.max_particles and fx.stats["skipped"] > 0)
	var live := 0
	for c in fx.get_children():
		if c is CPUParticles2D and c.emitting:
			live += 1
	check("эмиттеров не больше пула", live <= fx.pool_size())

	# цвет руды по тайлу
	var gold := fx.tile_accent(TileTypes.Type.GOLD_ORE)
	var iron := fx.tile_accent(TileTypes.Type.IRON_ORE)
	var emerald := fx.tile_accent(TileTypes.Type.EMERALD)
	check("акцент золота есть и тёплый (%s)" % str(gold), gold.a > 0.0 and gold.r > gold.b)
	check("акцент изумруда зелёный (%s)" % str(emerald), emerald.a > 0.0 and emerald.g > emerald.r and emerald.g > emerald.b)
	check("руды различаются по цвету частиц", _cdist(gold, iron) > 0.001 or _cdist(gold, emerald) > 0.01)
	check("для тайла без картинки акцента нет", fx.tile_accent(9999).a == 0.0)

	# всплывающие числа
	for i in 40:
		fx.float_text(Vector2(100, 100 + i), "+%d" % i, Color.WHITE)
	check("всплывающих не больше лимита (%d)" % fx.active_popups(), fx.active_popups() <= fx.max_popups and fx.active_popups() > 0)
	fx.float_icon(Vector2(50, 50), load("res://art/ui/icon_coin.png"), "+5", Color.GOLD)
	fx.float_text(Vector2(50, 50), "", Color.WHITE)
	await get_tree().create_timer(1.6).timeout
	check("всплывающие числа уходят и возвращаются в пул (%d)" % fx.active_popups(), fx.active_popups() == 0)

	# вспышка
	fx.flash(Color(1, 0, 0, 0.5), 0.1)
	check("flash выставляет цвет оверлея", is_equal_approx(fx._flash.color.a, 0.5))
	await get_tree().create_timer(0.25).timeout
	check("flash затухает", fx._flash.color.a < 0.01)
	Settings.reduce_motion = true
	fx.flash(Color(1, 0, 0, 0.5), 0.1)
	check("«меньше движения» приглушает вспышку", fx._flash.color.a < 0.2)
	fx.shake(5.0, 0.1)
	check("«меньше движения» отключает тряску", not fx.is_shaking())
	Settings.reduce_motion = false
	await get_tree().create_timer(0.2).timeout

	# тряска мира
	fx.shake(5.0, 0.15)
	check("shake включает тряску", fx.is_shaking())
	var moved := false
	for i in 4:
		await get_tree().process_frame
		if get_viewport().canvas_transform.origin != Vector2.ZERO:
			moved = true
	check("тряска сдвигает canvas_transform", moved)
	await get_tree().create_timer(0.3).timeout
	check("после тряски камера возвращается", get_viewport().canvas_transform == Transform2D.IDENTITY and not fx.is_shaking())
	fx.shake(1.0, 0.1)
	fx.shake(0.1, 0.1)
	check("слабая тряска не гасит сильную", fx._shake_amp >= 1.0)
	await get_tree().create_timer(0.25).timeout

	# летящие иконки
	var landed: Array = [0]
	fx.flier_landed.connect(func(_t: Vector2, _i: int, _n: int) -> void: landed[0] += 1)
	fx.fly_to(null, Vector2(10, 10), Vector2(200, 20), 5)
	check("fly_to выпускает иконки (%d)" % fx.active_fliers(), fx.active_fliers() == 5)
	fx.fly_to(null, Vector2(10, 10), Vector2(200, 20), 12)
	fx.fly_to(null, Vector2(10, 10), Vector2(200, 20), 12)
	check("число летящих иконок ограничено (%d)" % fx.active_fliers(), fx.active_fliers() <= fx.max_fliers)
	await get_tree().create_timer(2.2).timeout
	check("иконки долетают и исчезают (долетело %d, в полёте %d)" % [landed[0], fx.active_fliers()],
			fx.active_fliers() == 0 and landed[0] >= 5)
	check("мировая точка переводится в экранную", fx.world_to_screen(Vector2(32, 64)).is_finite())

	fx.queue_free()
	await _frames(2)


# ---------------------------------------------------------------------------
# Режиссёр: подписки и опрос героя
# ---------------------------------------------------------------------------

func _test_director() -> void:
	var rec := _Rec.new()
	rec.add_to_group(Sfx.GROUP)
	rec.add_to_group(Fx.GROUP)
	add_child(rec)
	var pl := _FakePlayer.new()
	add_child(pl)
	var story := _FakeStory.new()
	add_child(story)
	var dir := JuiceDirector.new()
	dir.player = pl
	dir.story = story
	GameState.is_alive = true
	add_child(dir)
	dir.process_mode = Node.PROCESS_MODE_DISABLED  # кадры гоним вручную
	await _frames(1)
	check("режиссёр не нашёл настоящих сервисов, работает через группы", dir.sfx == null and dir.fx == null)

	# --- добыча ---
	var cell := Vector2i(5, 9)
	GameState.emit_event(&"dug", {"cell": cell, "tile": TileTypes.Type.DIRT, "mineral": "earth", "loot": false, "pos": Vector2(176, 304)})
	check("dug: земля → dig_dirt + частицы земли", rec.has_play("dig_dirt") and rec.has_burst("dig_dirt"))
	check("dug: земля не трясёт экран", rec.shakes == 0)
	rec.clear()
	GameState.emit_event(&"dug", {"cell": cell, "tile": TileTypes.Type.STONE, "mineral": "stone", "loot": false, "pos": Vector2(176, 304)})
	check("dug: камень → dig_stone + частицы камня + микро-тряска", rec.has_play("dig_stone") and rec.has_burst("dig_stone") and rec.shakes == 1)
	rec.clear()
	GameState.emit_event(&"dug", {"cell": cell, "tile": TileTypes.Type.IRON_ORE, "mineral": "iron_ore", "loot": true, "pos": Vector2(176, 304)})
	check("dug: руда → dig_ore, частицы с цветом руды", rec.has_play("dig_ore") and rec.has_burst("dig_ore"))
	rec.clear()
	GameState.emit_event(&"dug", {"cell": cell, "tile": TileTypes.Type.GOLD_ORE, "mineral": "gold", "loot": true, "pos": Vector2(176, 304)})
	check("dug: золото → dig_gold + золотые искры", rec.has_play("dig_gold") and rec.has_burst("dig_gold"))
	rec.clear()
	GameState.emit_event(&"dug", {"cell": cell, "tile": TileTypes.Type.FOUNDATION, "mineral": "", "loot": false, "pos": Vector2(176, 304)})
	check("dug: фундамент → dig_hard и тряска", rec.has_play("dig_hard") and rec.shakes == 1)
	rec.clear()
	GameState.emit_event(&"picked", {"item": "iron_ore", "count": 1})
	check("picked: обычная добыча → pickup и «+1» с иконкой", rec.has_play("pickup") and rec.icons == 1)
	rec.clear()
	GameState.emit_event(&"picked", {"item": "diamond", "count": 2})
	check("picked: самоцвет → pickup_rare", rec.has_play("pickup_rare") and rec.icons == 1)
	rec.clear()
	GameState.emit_event(&"sold", {"coins": 500, "count": 8})
	check("sold: coins_big и монеты летят в кошелёк", rec.has_play("coins_big") and rec.flies == 1)
	rec.clear()
	GameState.emit_event(&"monster_killed", {"id": "bat", "pos": Vector2(10, 10)})
	check("monster_killed: enemy_die и частицы", rec.has_play("enemy_die") and rec.has_burst("enemy_die"))
	GameState.emit_event(&"monster_hit", {"pos": Vector2(10, 10), "damage": 7})
	check("monster_hit: hit_enemy, частицы, число урона", rec.has_play("hit_enemy") and rec.has_burst("hit_enemy") and rec.texts == 1)
	rec.clear()
	GameState.emit_event(&"explosion", {"pos": Vector2(10, 10)})
	check("explosion: звук, огонь, тряска", rec.has_play("explosion") and rec.has_burst("fire") and rec.shakes == 1)
	rec.clear()
	GameState.emit_event(&"collapse", {})
	GameState.emit_event(&"quake", {})
	check("collapse и quake озвучены и трясут", rec.has_play("collapse") and rec.has_play("quake") and rec.shakes == 2)
	rec.clear()
	GameState.emit_event(&"quest_done", {"id": "q1"})
	check("quest_done → звук", rec.has_play("quest_done"))

	# --- сигналы GameState ---
	rec.clear()
	GameState.hp_changed.emit(88.0, 100.0)
	check("hp вниз → hurt и красная вспышка", rec.has_play("hurt") and rec.flashes == 1)
	rec.clear()
	GameState.hp_changed.emit(87.9, 100.0)
	check("капля голода не вызывает hurt на каждый кадр", not rec.has_play("hurt"))
	for i in 40:
		GameState.hp_changed.emit(87.9 - float(i + 1) * 0.1, 100.0)
	check("но накопленные капли в конце концов слышны", rec.has_play("hurt"))
	rec.clear()
	GameState.hp_changed.emit(100.0, 100.0)
	check("hp вверх → heal", rec.has_play("heal") and rec.has_burst("heal"))
	rec.clear()
	GameState.leveled_up.emit(7, 3)
	check("leveled_up → levelup и салют", rec.has_play("levelup") and rec.has_burst("levelup") and rec.flashes == 1 and rec.texts == 1)
	rec.clear()
	GameState.survival_warning.emit("hunger", true)
	check("survival_warning → warn_low", rec.has_play("warn_low"))
	rec.clear()
	GameState.artifact_collected.emit("amphora")
	check("artifact_collected → artifact", rec.has_play("artifact") and rec.flashes == 1)
	rec.clear()
	GameState.hunger_changed.emit(40.0)
	GameState.hunger_changed.emit(39.9)
	check("голод падает — еды нет", not rec.has_play("eat"))
	GameState.hunger_changed.emit(80.0)
	check("сытость выросла → eat", rec.has_play("eat"))

	# монета: звук откладывается на кадр, продажа его перебивает
	rec.clear()
	dir._sold_msec = -100000  # продажа выше была только что — для этой проверки забываем её
	GameState.coins_changed.emit(GameState.coins + 10)
	dir._tick_coin_sound()
	check("coins_changed: звук монеты не мгновенно", not rec.has_play("coin"))
	OS.delay_msec(45)
	dir._tick_coin_sound()
	check("coins_changed вверх → coin", rec.has_play("coin"))
	rec.clear()
	GameState.coins_changed.emit(GameState.coins + 10)
	GameState.emit_event(&"sold", {"coins": 10, "count": 1})
	OS.delay_msec(45)
	dir._tick_coin_sound()
	check("при продаже вместо coin звучит coins_big", rec.has_play("coins_big") and not rec.has_play("coin"))
	rec.clear()
	GameState.coins_changed.emit(GameState.coins - 5)
	OS.delay_msec(45)
	dir._tick_coin_sound()
	check("траты монет не звенят", not rec.has_play("coin"))

	# --- герой: прыжок, падение, приземление, шаги, тяга, удары ---
	rec.clear()
	pl.jumped.emit()
	check("jumped → jump", rec.has_play("jump"))
	pl.fell.emit(8.0, 15.0)
	check("fell → thud", rec.has_play("thud"))

	rec.clear()
	pl.on_ground = false
	pl.vy = 10.0
	dir._process(0.016)
	pl.on_ground = true
	pl.vy = 0.0
	dir._process(0.016)
	check("приземление после падения → land и пыль", rec.has_play("land") and rec.has_burst("poof"))
	rec.clear()
	pl.on_ground = false
	pl.vy = 1.0
	dir._process(0.016)
	pl.on_ground = true
	pl.vy = 0.0
	dir._process(0.016)
	check("мягкий шаг вниз не гремит", not rec.has_play("land"))

	rec.clear()
	pl.vx = 4.2
	for i in 10:
		dir._process(0.1)
	check("шаги по траве на поверхности (%d)" % rec.count_play("step_grass"), rec.count_play("step_grass") >= 2 and rec.count_play("step_grass") <= 4)
	rec.clear()
	pl.y = 12.5
	pl.world = _FakeWorld.new(TileTypes.Type.DIRT)
	for i in 10:
		dir._process(0.1)
	check("шаги по земле под землёй → step", rec.count_play("step") >= 2)
	rec.clear()
	pl.world = _FakeWorld.new(TileTypes.Type.STONE)
	for i in 10:
		dir._process(0.1)
	check("шаги по камню → step_stone", rec.count_play("step_stone") >= 2)
	rec.clear()
	pl.vx = 0.0
	for i in 10:
		dir._process(0.1)
	check("стоя на месте шагов нет", rec.count_play("step") + rec.count_play("step_stone") + rec.count_play("step_grass") == 0)

	rec.clear()
	pl.on_ground = false
	pl.thrust = "prop"
	dir._process(0.016)
	check("тяга: fly_start и гул", rec.has_play("fly_start") and rec.has_call("loop_start"))
	pl.thrust = ""
	dir._process(0.016)
	check("конец тяги: fly_stop и конец гула", rec.has_play("fly_stop") and rec.has_call("loop_stop"))
	pl.on_ground = true

	rec.clear()
	pl.digging = {"x": 5, "y": 13, "t": 0.0, "total": 3.0, "type": TileTypes.Type.DIRT}
	dir._process(0.016)
	pl.digging["t"] = 0.2
	dir._process(0.016)
	check("удар по породе во время копки: звук и мелкие частицы", rec.count_play("dig_dirt") == 1 and rec.count_burst("dig_dirt") == 1)
	check("удар тише финального", rec.last_play_db("dig_dirt") < -3.0)
	dir._process(0.016)
	check("один удар на период, а не на кадр", rec.count_play("dig_dirt") == 1)
	pl.digging["t"] = 0.65
	dir._process(0.016)
	check("следующий удар через период", rec.count_play("dig_dirt") == 2)
	pl.digging["t"] = 2.95
	dir._process(0.016)
	check("перед самым финалом лишнего удара нет", rec.count_play("dig_dirt") == 2)
	pl.digging = null
	dir._process(0.016)

	# --- смерть и возрождение ---
	rec.clear()
	GameState.died.emit()
	check("died → die, тряска, музыка стихает", rec.has_play("die") and rec.has_call("stop_music") and rec.flashes == 1)
	rec.clear()
	GameState.respawned.emit()
	GameState.hp_changed.emit(100.0, 100.0)
	check("respawned → respawn, возврат HP не считается лечением", rec.has_play("respawn") and not rec.has_play("heal"))

	# --- музыка по контексту ---
	GameState.house_is_indoors = false
	GameState.player_depth = 0
	check("контекст: поверхность → mus_surface", dir.music_for_context() == "mus_surface")
	GameState.player_depth = 12
	check("контекст: шахта → mus_mine_1", dir.music_for_context() == "mus_mine_1")
	GameState.player_depth = 1800
	check("контекст: глубже 1500 → mus_mine_2", dir.music_for_context() == "mus_mine_2")
	GameState.player_depth = 4200
	check("контекст: глубже 4000 → mus_deep", dir.music_for_context() == "mus_deep")
	GameState.house_is_indoors = true
	check("контекст: дом → mus_surface даже на глубине", dir.music_for_context() == "mus_surface")
	GameState.house_is_indoors = false
	story.cutscene.is_playing = true
	check("контекст: катсцена сюжета → mus_story", dir.music_for_context() == "mus_story")
	story.cutscene.is_playing = false
	GameState.emit_event(&"boss_started", {"id": "king"})
	check("контекст: босс → mus_boss", dir.music_for_context() == "mus_boss" and rec.has_play("boss_roar"))
	GameState.emit_event(&"boss_defeated", {"id": "king"})
	check("контекст: победа над боссом возвращает шахту", dir.music_for_context() == "mus_deep")
	GameState.is_alive = false
	check("контекст: мёртвый герой — тишина", dir.music_for_context() == "")
	GameState.is_alive = true

	rec.clear()
	rec.music_id = ""
	dir._tick_music()
	check("первый трек включается сразу", rec.music_id == "mus_deep")
	GameState.player_depth = 12
	dir._tick_music()
	check("смена трека на границе глубин ждёт (нет мигания)", rec.music_id == "mus_deep")
	dir._clock += 2.0
	dir._tick_music()
	check("а через паузу переключается", rec.music_id == "mus_mine_1")
	story.cutscene.is_playing = true
	dir._tick_music()
	check("катсцена переключает музыку сразу", rec.music_id == "mus_story")
	story.cutscene.is_playing = false
	GameState.player_depth = 0

	# выход из дерева отписывает режиссёра
	dir.queue_free()
	await _frames(2)
	rec.clear()
	GameState.emit_event(&"quest_done", {"id": "zzz"})
	GameState.leveled_up.emit(8, 1)
	check("после удаления режиссёр больше не реагирует", not rec.has_play("quest_done") and not rec.has_play("levelup"))
	pl.queue_free()
	story.queue_free()
	rec.queue_free()
	await _frames(2)


# ---------------------------------------------------------------------------
# Настоящая сцена Main: сок подключён и реагирует на настоящие сигналы
# ---------------------------------------------------------------------------

func _test_integration() -> void:
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(8)
	var sfx := get_tree().get_first_node_in_group(Sfx.GROUP) as SfxService
	var fx := get_tree().get_first_node_in_group(Fx.GROUP) as FxService
	check("в настоящей сцене Main поднялись сервисы сока", sfx != null and fx != null and main.get_node_or_null("JuiceDirector") != null)
	check("FxService живёт в ViewRoot рядом с героем", fx != null and fx.get_parent() == main.view_root)
	if sfx == null or fx == null:
		return
	sfx.require_gesture = false
	sfx.unlocked = true
	sfx._last_ms.clear()
	var played0: int = sfx.stats["played"]
	GameState.inventory.clear()
	GameState.add_item("gold", 1)
	check("настоящий picked: звук и всплывающая иконка", sfx.stats["played"] > played0 and fx.stats["popups"] > 0)
	var bursts0: int = fx.stats["bursts"]
	var pos := Vector2(float(main.player.cell_x()) * 32.0 + 16.0, float(main.player.cell_y() + 1) * 32.0 + 16.0)
	GameState.emit_event(&"dug", {"cell": Vector2i(main.player.cell_x(), main.player.cell_y() + 1),
			"tile": TileTypes.Type.DIRT, "mineral": "earth", "loot": false, "pos": pos})
	check("настоящий dug: частицы породы", fx.stats["bursts"] > bursts0)
	var played1: int = sfx.stats["played"]
	sfx._last_ms.clear()
	GameState.take_damage(20.0, "test")
	check("настоящий урон: звук и красная вспышка", sfx.stats["played"] > played1 and fx._flash.color.a > 0.0)
	GameState.heal(100.0)
	await get_tree().create_timer(0.7).timeout
	check("музыка по контексту включилась сама (%s)" % sfx.current_music(), sfx.current_music() != "")
	main.queue_free()
	await get_tree().create_timer(0.3).timeout


# ---------------------------------------------------------------------------
# Подключение одной строкой
# ---------------------------------------------------------------------------

func _test_attach() -> void:
	var host := _FakeHost.new()
	host.view_root = Node2D.new()
	host.add_child(host.view_root)
	add_child(host)
	var d := Juice.attach(host)
	await _frames(2)
	check("Juice.attach: звук, режиссёр у хоста, эффекты в мировой сцене",
			host.get_node_or_null("SfxService") != null and d is JuiceDirector
			and host.view_root.get_node_or_null("FxService") != null)
	check("повторный attach ничего не удваивает", Juice.attach(host) == d and host.get_child_count() == 3)
	check("после attach фасад Sfx находит настоящий сервис", Sfx._service() is SfxService)
	Sfx.play("ui_tap")
	Fx.burst("spark", Vector2(30, 30))
	Fx.float_text(Vector2(30, 30), "+1")
	Fx.flash()
	Fx.fly_to(null, Vector2.ZERO, Vector2(100, 100))
	check("фасады работают через настоящие сервисы без ошибок", true)
	check("настоящий режиссёр нашёл сервисы", (d as JuiceDirector).sfx != null and (d as JuiceDirector).fx != null)
	check("данные juice.json читаются", Juice.num("music.deep_from", -1.0) == 4000.0 and Juice.num("нет.такого", 7.0) == 7.0)
	host.queue_free()
	# даём аудиосерверу отпустить проигрыватели, иначе выход ругается на утечки
	await get_tree().create_timer(0.3).timeout


# ---------------------------------------------------------------------------
# Заглушки
# ---------------------------------------------------------------------------

class _FakeHost extends Node:
	var view_root: Node2D
	var player = null


class _FakeCutscene extends RefCounted:
	var is_playing: bool = false


class _FakeStory extends Node:
	var cutscene := _FakeCutscene.new()


class _FakeWorld extends RefCounted:
	var tile: int

	func _init(t: int) -> void:
		tile = t

	func get_tile(_x: int, _y: int) -> int:
		return tile


class _FakePlayer extends Node:
	signal jumped
	signal fell(damage: float, impact_speed: float)
	var x: float = 15.5
	var y: float = 0.5
	var vx: float = 0.0
	var vy: float = 0.0
	var on_ground: bool = true
	var thrust: String = ""
	var digging = null
	var frozen: bool = false
	var world = null

	func cell_x() -> int:
		return int(floor(x))

	func cell_y() -> int:
		return int(floor(y))


class _Rec extends Node:
	var calls: Array = []
	var music_id: String = ""
	var shakes: int = 0
	var flashes: int = 0
	var texts: int = 0
	var icons: int = 0
	var flies: int = 0

	func clear() -> void:
		calls.clear()
		shakes = 0
		flashes = 0
		texts = 0
		icons = 0
		flies = 0

	func has_call(kind: String) -> bool:
		return calls.any(func(c: Array) -> bool: return c[0] == kind)

	func has_play(id: String) -> bool:
		return count_play(id) > 0

	func count_play(id: String) -> int:
		return calls.filter(func(c: Array) -> bool: return c[0] == "play" and c[1] == id).size()

	func has_burst(kind: String) -> bool:
		return count_burst(kind) > 0

	func count_burst(kind: String) -> int:
		return calls.filter(func(c: Array) -> bool: return c[0] == "burst" and c[1] == kind).size()

	func last_play_db(id: String) -> float:
		var r := 0.0
		for c in calls:
			if c[0] == "play" and c[1] == id:
				r = c[3]
		return r

	func play(id: String, pitch: float = 1.0, vol: float = 0.0) -> void:
		calls.append(["play", id, pitch, vol])

	func music(id: String, _fade: float) -> void:
		calls.append(["music", id])
		music_id = id

	func stop_music(_fade: float) -> void:
		calls.append(["stop_music"])
		music_id = ""

	func current_music() -> String:
		return music_id

	func loop_start(id: String, _vol: float, _pitch: float) -> void:
		calls.append(["loop_start", id])

	func loop_stop(id: String, _fade: float) -> void:
		calls.append(["loop_stop", id])

	func burst(kind: String, pos: Vector2, amount: float, tint = null) -> void:
		calls.append(["burst", kind, pos, amount, tint])

	func float_text(_p: Vector2, _t: String, _c: Color) -> void:
		texts += 1

	func float_icon(_p: Vector2, _i, _t: String, _c: Color) -> void:
		icons += 1

	func shake(_s: float, _d: float) -> void:
		shakes += 1

	func flash(_c: Color, _d: float) -> void:
		flashes += 1

	func fly_to(_i, _a: Vector2, _b: Vector2, _n: int) -> void:
		flies += 1

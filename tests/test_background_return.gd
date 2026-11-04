extends Node
## test_background_return — возврат из фона (product-polish, раунд 6): уход в фон пишет сейв
## (SaveHooks), а возвращение через «час» не проматывает голод, бодрость и игровые часы.
## Движок после долгой паузы отдаёт в _process не весь прошедший интервал, а кадр, ограниченный
## max_physics_steps_per_frame (≈0.13 с при 60 Гц) — проверяем это на настоящей main.tscn,
## заблокировав кадр на секунду: следующий тик выживания списывает долю секунды, не секунду.
## Отдельно: отчёт скважины при возвращении не всплывает, если скважины нет.
##
## Запуск: godot --headless --path . res://tests/test_background_return.tscn

var failures := 0
var total := 0


func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", label])


func _ready() -> void:
	print("=== test_background_return ===")
	GameState.world_seed = 20260101
	StoryState.mark_seen("intro_grandpa")
	StoryState.mark_seen("intro_boy")
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	GameState.is_alive = true
	GameState.set_hunger(80.0)
	GameState.set_stamina(70.0)
	GameState.well_level = 0   # общий user:// тестов мог оставить скважину: проверяем возврат без неё
	GameState.well_last_collect_unix = 0
	if WellReport.is_open():
		WellReport.instance().close()
	var clock0 := GameState.game_clock_hours
	var hunger0 := GameState.hunger
	var stamina0 := GameState.stamina

	# 1. Уход в фон: SaveHooks пишет сейв сразу.
	SaveSystem.delete_save()
	get_tree().root.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check("уход в фон (APPLICATION_PAUSED) пишет сейв", SaveSystem.has_save())
	SaveSystem.delete_save()
	get_tree().root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("потеря фокуса (FOCUS_OUT) пишет сейв", SaveSystem.has_save())

	# 2. «Долгая пауза»: кадр блокируется на секунду, следующий тик — не на секунду.
	var rate_h := Balance.get_bar_depletion_rate_per_second("hunger", false) * SurvivalRules.drain_multiplier("hunger")
	var rate_s := Balance.get_bar_depletion_rate_per_second("stamina", false) * SurvivalRules.drain_multiplier("stamina")
	OS.delay_msec(1000)
	await get_tree().process_frame
	get_tree().root.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await get_tree().process_frame
	var hunger_drop := hunger0 - GameState.hunger
	var stamina_drop := stamina0 - GameState.stamina
	var clock_drop := GameState.game_clock_hours - clock0
	# за секунду стоя было бы rate*100*1.0; допускаем до трети (несколько кадров по ≤0.13 с)
	check("голод не промотан за паузу (списано %.3f, за секунду было бы %.3f)" % [hunger_drop, rate_h * 100.0],
		hunger_drop < rate_h * 100.0 * 0.4)
	check("бодрость не промотана за паузу (списано %.3f, за секунду было бы %.3f)" % [stamina_drop, rate_s * 100.0],
		stamina_drop < rate_s * 100.0 * 0.4)
	var hours_per_sec := Balance.get_game_hours_per_real_hour() / 3600.0
	check("игровые часы не промотаны за паузу (%.4f ч)" % clock_drop, clock_drop < hours_per_sec * 0.4)
	check("герой жив и дома после возврата", GameState.is_alive)
	check("окно отчёта скважины не всплыло (скважины нет)", not WellReport.is_open())

	# 3. Основной цикл main.gd и так ограничивает шаг физики 0.033 — игрок не проваливается после возврата.
	var p = main.player
	var y0: float = p.y
	main._process(5.0)
	check("шаг физики за кадр ограничен: герой не улетел (Δy=%.2f)" % absf(p.y - y0), absf(p.y - y0) < 1.0)

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)

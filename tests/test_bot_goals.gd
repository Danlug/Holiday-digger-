extends Node
## test_bot_goals — короткий прогон пяти ботов-стратегий (tests/bot_play.gd → GOALS) как автотест.
##
## Пять дочерних процессов Godot параллельно (--fixed-fps 31, у каждого свой XDG_DATA_HOME)
## играют по ~1,3 игровой минуты с состояния «сразу после онбординга» (--skip-onboarding):
## шахта → домой (ходка 35 с) → продажа, прокачка и покупки по цели → снова шахта.
## Проверки: нет ошибок скрипта и находок P0; у каждой стратегии свой характер и сид,
## первое очко навыка ушло в одну из первых веток её порядка, и первый шаг к цели сделан:
## deep — глубина, achiever — достижение, tycoon — заработок, collector — коллекция
## и заход в музей, fighter — ветка здоровья. Ночные прогоны — tools/bot_night.sh.
##
##   godot --headless --path . res://tests/test_bot_goals.tscn
##   tools/run_tests.sh bot_goals

const MINUTES := 1.3
const WALL_CHILD := 150      # под нагрузкой полного прогона тестов; одни — ~50 с на все пять
const TIMEOUT_CHILD := 200
const SEEDS := {"deep": 20260101, "achiever": 7, "tycoon": 424242, "collector": 31337, "fighter": 99}

var failures := 0
var total := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _ready() -> void:
	print("=== test_bot_goals: пять ботов-стратегий, первые шаги к цели ===")
	var goals: Dictionary = load("res://tests/bot_play.gd").get_script_constant_map().get("GOALS", {})
	check("в боте описаны пять стратегий", goals.size() == 5 and goals.has_all(SEEDS.keys()), str(goals.keys()))
	var root := "/tmp/raskopki_botgoals_%d" % Time.get_ticks_usec()
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var pids := {}
	var t0 := Time.get_ticks_msec()
	for g in SEEDS:
		var dir := root + "/" + String(g)
		DirAccess.make_dir_recursive_absolute(dir + "/xdg")
		var cmd := "XDG_DATA_HOME='%s/xdg' timeout %d '%s' --headless --fixed-fps 31 --path '%s' res://tests/bot_play.tscn -- --seed=%d --minutes=%s --goal=%s --skip-onboarding --short --out='%s' --wall=%d > '%s/log.txt' 2>&1; echo $? > '%s/code'" % [
			dir, TIMEOUT_CHILD, exe, proj, int(SEEDS[g]), str(MINUTES), g, dir, WALL_CHILD, dir, dir]
		pids[g] = OS.create_process("bash", ["-c", cmd])
	while true:
		var running := 0
		for g in pids:
			if int(pids[g]) > 0 and OS.is_process_running(int(pids[g])):
				running += 1
		if running == 0 or Time.get_ticks_msec() - t0 > (TIMEOUT_CHILD + 15) * 1000:
			break
		await get_tree().create_timer(0.5).timeout
	print("  пять прогонов за %.0f с" % ((Time.get_ticks_msec() - t0) / 1000.0))

	var upgrades := _upgrade_ids()
	for g in SEEDS:
		_check_goal(String(g), root + "/" + String(g), goals.get(g, {}), upgrades)
	OS.execute("rm", ["-rf", root])
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check_goal(g: String, dir: String, goal: Dictionary, upgrades: Array) -> void:
	var code := FileAccess.get_file_as_string(dir + "/code").strip_edges()
	var text := FileAccess.get_file_as_string(dir + "/log.txt")
	var bad: Array[String] = []
	for line in text.split("\n"):
		if line.contains("SCRIPT ERROR") or line.contains("Parse Error") or line.contains("Program crashed") \
				or line.contains("Invalid call") or line.contains("Invalid access"):
			bad.append(line.strip_edges())
	var fails0 := failures
	check("%s: прогон завершился сам (код %s)" % [g, code], code == "0" or code == "1", "таймаут или падение движка")
	check("%s: в логе нет ошибок скрипта" % g, bad.is_empty(), "\n    " + "\n    ".join(bad.slice(0, 6)))
	var tel: Dictionary = {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(dir + "/telemetry.json"))
	if d is Dictionary:
		tel = d
	check("%s: телеметрия записана" % g, not tel.is_empty())
	if tel.is_empty():
		_tail(text)
		return
	var meta: Dictionary = tel.get("meta", {})
	print("  %s: %.0f игровых с за %.0f с стены" % [g, float(meta.get("sim_seconds", 0)), float(meta.get("wall_seconds", 0))])
	var ms: Dictionary = tel.get("milestones", {})
	var es: Dictionary = meta.get("end_state", {})
	check("%s: стратегия, характер и сид в отчёте" % g, String(meta.get("goal", "")) == g \
		and String(meta.get("character", "")) == String(goal.get("char", "")) and int(meta.get("seed", 0)) == int(SEEDS[g]), str(meta))
	var p0: Array = []
	for x in tel.get("findings", []):
		if String(x.get("sev", "")) == "P0":
			p0.append("%s: %s" % [x.get("kind", ""), x.get("text", "")])
	check("%s: нет находок P0" % g, p0.is_empty(), "\n    " + "\n    ".join(p0))
	var home := 0
	for t in tel.get("trips", []):
		if String(t.get("reason", "")) != "death":
			home += 1
	check("%s: вернулся домой живым (круг шахта → дом)" % g, home >= 1 and int(meta.get("home_visits", 0)) >= 1, "ходки %s" % str(tel.get("trips", [])))
	# первое очко — в одну из первых четырёх существующих веток порядка стратегии
	var order: Array = []
	for b in goal.get("skills", []):
		if upgrades.has(b):
			order.append(b)
	var first := ""
	for e in tel.get("events", []):
		if e is Array and e.size() > 2 and String(e[1]) == "skill":
			first = String(e[2])
			break
	var saving := ""
	for b in order.slice(0, 4):
		if ms.has("skill_saving:" + String(b)):
			saving = String(b)
	check("%s: первое очко навыка по цели (%s)" % [g, first if first != "" else "копит на " + saving],
		order.slice(0, 4).has(first) or (first == "" and saving != ""), "порядок %s" % str(order.slice(0, 4)))
	var metric := float(meta.get("goal_metric", 0))
	match g:
		"deep":
			check("deep: копает вглубь (глубина %s ≥ 15)" % str(es.get("max_depth")), int(es.get("max_depth", 0)) >= 15)
		"achiever":
			check("achiever: открыто достижение (%s)" % str(meta.get("achievements_done")), int(meta.get("achievements_done", 0)) >= 1)
		"tycoon":
			check("tycoon: заработок растёт (%s)" % str(meta.get("coins_earned_total")), int(meta.get("coins_earned_total", 0)) > 0)
		"collector":
			check("collector: коллекция растёт (метрика %.0f ≥ 3)" % metric, metric >= 3.0)
			check("collector: заглянул в музей/прогресс из дома", ms.has("opened:progress"))
		"fighter":
			check("fighter: первым качает здоровье", not upgrades.has("hp") or ms.has("skill:hp"), "первое очко %s" % first)
	if failures > fails0:
		_tail(text)


func _upgrade_ids() -> Array:
	var out: Array = []
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/upgrades.json"))
	if d is Dictionary:
		var br = d.get("branches", d)
		if br is Dictionary:
			out = br.keys()
		elif br is Array:
			for b in br:
				if b is Dictionary and b.has("id"):
					out.append(String(b["id"]))
	return out


func _tail(text: String) -> void:
	var lines := text.split("\n")
	print("--- хвост лога ---")
	for i in range(maxi(0, lines.size() - 25), lines.size()):
		print("  ", lines[i])

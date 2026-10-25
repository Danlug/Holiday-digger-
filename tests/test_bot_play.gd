extends Node
## test_bot_play — короткий прогон бота-игрока (tests/bot_play.gd) как обычный автотест.
##
## Дочерний процесс Godot с --fixed-fps 31 и своим XDG_DATA_HOME играет ~7 игровых минут
## «торопливым» характером: онбординг со «Пропустить», шахта, подъём на ранце, дом (продажа,
## покупка кирки плиткой витрины, еда), снова шахта. Родитель читает лог и телеметрию:
## SCRIPT ERROR / Parse Error / падение, находки P0 (тупик, застревание), и что
## главные вехи круга случились. Длинные прогоны — вручную: tools/bot_play.sh.
##
##   godot --headless --path . res://tests/test_bot_play.tscn

const SEED := 20260101
const MINUTES := 7.0
const WALL_LIMIT := 150

var failures := 0
var total := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _ready() -> void:
	print("=== test_bot_play: короткий прогон бота-игрока ===")
	var tmp := "/tmp/raskopki_botplay_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(tmp + "/xdg")
	var argv: Array = ["XDG_DATA_HOME=" + tmp + "/xdg", "timeout", str(WALL_LIMIT), OS.get_executable_path(),
		"--headless", "--fixed-fps", "31", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/bot_play.tscn", "--", "--seed=%d" % SEED, "--minutes=%s" % str(MINUTES),
		"--char=hasty", "--short", "--out=" + tmp, "--wall=%d" % (WALL_LIMIT - 20)]
	var out: Array = []
	var t0 := Time.get_ticks_msec()
	var code := OS.execute("env", argv, out, true)
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	var text := String(out[0]) if out.size() > 0 else ""
	var bad: Array[String] = []
	for line in text.split("\n"):
		if line.contains("SCRIPT ERROR") or line.contains("Parse Error") or line.contains("Program crashed") \
				or line.contains("Invalid call") or line.contains("Invalid access"):
			bad.append(line.strip_edges())
	check("дочерний прогон завершился сам (код %d, %.0f с)" % [code, wall], code == 0 or code == 1,
		"код %d — таймаут или падение движка" % code)
	check("в логе игры нет ошибок скрипта", bad.is_empty(), "\n    " + "\n    ".join(bad.slice(0, 8)))

	var tel: Dictionary = {}
	var f := FileAccess.open(tmp + "/telemetry.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			tel = d
	check("бот записал телеметрию", not tel.is_empty())
	var ms: Dictionary = tel.get("milestones", {})
	var p0: Array = []
	for x in tel.get("findings", []):
		if String(x.get("sev", "")) == "P0":
			p0.append("%s: %s" % [x.get("kind", ""), x.get("text", "")])
	check("нет находок P0 (тупик, застревание, окно не отпускает)", p0.is_empty(), "\n    " + "\n    ".join(p0))
	check("онбординг пройден", ms.has("onboarding_done"))
	check("первая продажа в мастерской", ms.has("first_sale"))
	check("кирка куплена плиткой витрины у двери", ms.has("buy:iron_pickaxe"))
	check("спустился в шахту через тоннель и копал (глубина ≥ 25)", ms.has("depth_25"))
	var trips: Array = tel.get("trips", [])
	var home_trips := 0
	for t in trips:
		if String(t.get("reason", "")) != "death":
			home_trips += 1
	check("хотя бы одна ходка вернулась наверх живой", home_trips >= 1, "ходки: %s" % str(trips))
	var deaths: Array = tel.get("deaths", [])
	var unscripted := 0
	for d in deaths:
		if not bool(d.get("scripted", false)):
			unscripted += 1
	check("за короткий прогон не погиб (кроме сценарной смерти)", unscripted == 0, str(deaths))
	if failures > 0:
		print("--- хвост лога бота ---")
		var lines := text.split("\n")
		for i in range(maxi(0, lines.size() - 40), lines.size()):
			print("  ", lines[i])
	OS.execute("rm", ["-rf", tmp])
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)

extends Node
## test_settings_motion — владелец 30.10: «до сих пор нет сотрясений и зума». «Меньше движения»
## больше не берётся у системы: первый запуск — выключено; файл настроек версии 1 (значение могло
## прийти от системы) сбрасывается; выбор игрока в файле версии 2 сохраняется.
##
## Запуск: godot --headless --path . res://tests/test_settings_motion.tscn

var failures := 0
var total := 0


func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", label])


func _write(data: Dictionary) -> void:
	var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _ready() -> void:
	print("=== test_settings_motion ===")
	if FileAccess.file_exists(Settings.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	Settings.reduce_motion = true
	Settings.load_from_disk()
	check("первый запуск: «меньше движения» выключено — тряска и наезд есть", not Settings.reduce_motion)
	_write({"version": 1, "reduce_motion": true})
	Settings.load_from_disk()
	check("файл версии 1 с «меньше движения» (могло прийти от системы) — сброшено", not Settings.reduce_motion)
	Settings.set_reduce_motion(true)
	Settings.reduce_motion = false
	Settings.load_from_disk()
	check("выбор игрока (файл версии 2) сохраняется", Settings.reduce_motion)
	Settings.set_reduce_motion(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)

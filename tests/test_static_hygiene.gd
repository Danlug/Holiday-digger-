extends SceneTree
## test_static_hygiene — лямбды в статических переменных портят кучу при выходе движка.
##
## Запуск: godot --headless --path . --script res://tests/test_static_hygiene.gd
##
## Лямбда держит ссылку на скрипт, где создана; статическая переменная переживает скрипты
## при выходе, и Godot 4.4 валится с «corrupted size vs. prev_size» (код 134) — после
## успешной строки «Итог», поэтому ловить это надо по коду возврата. Здесь — дешёвый
## ранний сторож по исходникам: файл, у которого есть `static var` с Callable или со
## словарём/массивом, куда кладут лямбды, обязан чистить их на `tree_exiting`
## (образец — scripts/ui/menu_registry.gd).
##
## Эвристика, не доказательство: настоящая проверка — код возврата каждого прогона.

var failures := 0
var total := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
	print("[%s] %s%s" % ["OK" if ok else "FAIL", name, ("  " + detail) if not ok and not detail.is_empty() else ""])


func _init() -> void:
	print("=== test_static_hygiene ===")
	var files: Array[String] = []
	_collect("res://scripts", files)
	var re_static := RegEx.new()
	re_static.compile("(?m)^static var\\s+\\w+")
	var re_static_callable := RegEx.new()
	re_static_callable.compile("(?m)^static var\\s+\\w+\\s*(:\\s*Callable|:=\\s*func|=\\s*func|:\\s*Array\\[Callable\\])")
	# Лямбда кладётся в контейнер: ["x"] = func / append(func. Словарь с лямбдами, переданный в
	# MenuRegistry.add, сюда не относится: реестр сам чистится на tree_exiting.
	var re_stored := RegEx.new()
	re_stored.compile("(\\]\\s*=\\s*func\\b|\\.append\\(\\s*func\\b|\\.push_back\\(\\s*func\\b)")
	var scanned := 0
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if re_static.search(text) == null:
			continue
		scanned += 1
		var has_cleanup := text.contains("tree_exiting")
		check("%s: static var с Callable" % path.trim_prefix("res://"),
			re_static_callable.search(text) == null or has_cleanup,
			"добавь очистку на get_tree().root.tree_exiting, как в menu_registry.gd")
		# Контейнер со статикой и лямбдами в одном файле — подозрительно, если нет очистки.
		check("%s: лямбды в контейнерах рядом со static var" % path.trim_prefix("res://"),
			re_stored.search(text) == null or has_cleanup,
			"лямбды кладутся в контейнер, а очистки на tree_exiting нет")
	check("просмотрены файлы со static var (%d)" % scanned, scanned >= 10)
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	quit(0 if failures == 0 else 1)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))

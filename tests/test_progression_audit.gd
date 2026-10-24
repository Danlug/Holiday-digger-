extends Node
## test_progression_audit — сквозная достижимость прогресса (ветка qa2).
##
## Запуск: godot --headless --path . res://tests/test_progression_audit.tscn
## Полный отчёт с таблицей: godot --headless --path . res://tools/audit_progression.tscn -- --verbose
##
## Что ловит: покупка/рецепт/ступень, для которой в мире нет источника материала; ссылка на
## несуществующую добычу; руду, которую затирает другая генерация; лестницу с прыжком цены
## больше чем в 10 раз; топливо, которое не окупается породой; лаву, которая перекрывает
## шахту. Ожидаемые предупреждения перечислены ниже вместе с причиной — новое предупреждение
## проваливает тест, пока его не разберут.

const Audit := preload("res://tools/audit_progression.gd")

## Известное и принятое: подстрока «где» → почему это не дефект.
const KNOWN_WARNINGS := {
	"recipe:hand_drill ← iron_ore": "цена бура задана владельцем (500 железа), ГДД §18: бур набирается за ~5.8 ч серпантина",
	"recipe:hand_drill ← scrap": "то же: 100 металлолома → бронза, ГДД §18, металлолом лежит до глубины 500",
	"бак hand_drill L3": "никель с 522, у бура «до 500» (ГДД §5) — потолок бура кодом не принуждается, вопрос владельцу (ГДД §19)",
	"бак hand_drill L4": "то же",
}

var failures := 0
var total := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	total += 1
	if not ok:
		failures += 1
		print("[FAIL] %s %s" % [name, detail])
	else:
		print("[OK] ", name)


func _ready() -> void:
	print("=== test_progression_audit ===")
	var audit = Audit.new()
	audit.lava_seed_count = 1
	add_child(audit)
	audit.run()

	var errors: Array = []
	var unexpected: Array = []
	for f in audit.findings:
		if f["level"] == "error":
			errors.append("%s: %s" % [f["where"], f["text"]])
		elif f["level"] == "warn":
			var known := false
			for key in KNOWN_WARNINGS.keys():
				if String(f["where"]).contains(String(key)):
					known = true
			if not known:
				unexpected.append("%s: %s" % [f["where"], f["text"]])
	for e in errors:
		print("  ошибка аудита: ", e)
	for w in unexpected:
		print("  новое предупреждение: ", w)
	check("аудит: нет ни одной недостижимой покупки/ссылки/лавовой преграды", errors.is_empty(), "%d шт." % errors.size())
	check("аудит: нет новых предупреждений (безумные цены/разрывы/топливо)", unexpected.is_empty(), "%d шт." % unexpected.size())
	check("аудит: таблица требований не пуста (рецепты, баки, костюмы, скважина, бой)", audit.rows.size() > 100, "строк %d" % audit.rows.size())
	check("аудит: лестницы собраны (кирки, ранцы, бур, баки, костюм, скважина, бой)", audit.ladders.size() >= 12, "лестниц %d" % audit.ladders.size())

	_test_detects_problems(audit)
	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	get_tree().quit(0 if failures == 0 else 1)


## Сам аудит должен уметь находить беду: проверяем на выдуманных данных, а не на настоящих.
func _test_detects_problems(audit) -> void:
	var ghost: Dictionary = audit.evaluate("no_such_mineral", 5, 100)
	check("аудит: материал без источника — «none»", ghost["source"] == "none")
	var hell: Dictionary = audit.evaluate("hellstone", 14, 4000)
	check("аудит: адский камень добывается в мире с 4000", hell["source"] == "world" and int(hell["start"]) == 4000 and float(hell["cells"]) > 0.0)
	var ash: Dictionary = audit.evaluate("cinder_ash", 8, 4000)
	check("аудит: пепел червя — только с монстров, убийств конечное число", ash["source"] == "drop" and float(ash["kills"]) > 0.0)
	var boss: Dictionary = audit.evaluate("abyss_core", 1, 4000)
	check("аудит: ядро Бездны — награда босса", boss["source"] == "boss")
	check("аудит: титан не раньше 1000", audit.work_depth("titanium", 1) >= 1000)
	# обход лавы: сплошная полоса лавы стоит насквозь поперёк — без права пройти k=0 останавливает, k=1 пропускает
	var w := WorldGen.WIDTH
	var grid := PackedByteArray()
	grid.resize(w * 10)
	for x in range(w):
		grid[5 * w + x] = 1
	check("обход лавы: сплошной ряд лавы без права пройти останавливает перед ним", audit.lava_reach(grid, 0, 100) == 104)
	check("обход лавы: с правом на одну клетку проходит насквозь", audit.lava_reach(grid, 1, 100) == 109)
	for x in range(w):
		grid[6 * w + x] = 1
	check("обход лавы: двойная полоса лавы не проходится с k=1 (герой застревает в первой клетке)", audit.lava_reach(grid, 1, 100) == 105)
	check("обход лавы: двойная полоса проходится с k=2", audit.lava_reach(grid, 2, 100) == 109)
	# подмена данных: рецепт с материалом, которого нет, обязан дать ошибку
	var saved = Balance.balance["tools"]["hand_drill"]["cost"]
	Balance.balance["tools"]["hand_drill"]["cost"] = {"value": {"unobtainium": 3, "coins": 10}, "proposed": true}
	var probe = Audit.new()
	probe.lava_seed_count = 0
	add_child(probe)
	probe.run()
	var caught := false
	for f in probe.findings:
		if f["level"] == "error" and String(f["text"]).contains("unobtainium"):
			caught = true
	Balance.balance["tools"]["hand_drill"]["cost"] = saved
	check("аудит: рецепт с несуществующим материалом даёт ошибку", caught)

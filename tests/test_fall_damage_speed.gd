extends SceneTree
## Проверка Balance.get_fall_damage_from_speed() — урона по СКОРОСТИ удара,
## которым реально пользуется player.gd (см. GDD раздел 6: "урон считается
## от скорости удара, а не от пройденной высоты"). Формула должна давать те
## же числа, что и старая get_fall_damage(height), когда скорость получена
## из СВОБОДНОГО падения (v = sqrt(2*g*h)) — расходиться они обязаны только
## тогда, когда скорость гасилась/менялась управляемым полётом.
##
## Запуск: godot --headless --script res://tests/test_fall_damage_speed.gd

const G := 16.0

var failures := 0
var total := 0


func _init() -> void:
	print("=== test_fall_damage_speed.gd ===")
	var bal = load("res://scripts/core/balance.gd").new()
	bal._ready()

	_check_free_fall_matches_height_formula(bal, 5.0)
	_check_free_fall_matches_height_formula(bal, 8.0)
	_check_free_fall_matches_height_formula(bal, 20.0)
	_check_free_fall_matches_height_formula(bal, 30.0)

	check("на пороге безопасной скорости урона нет",
		bal.get_fall_damage_from_speed(sqrt(2.0 * G * 5.0) - 0.01, G) == 0.0)
	check("чуть выше порога — урон уже есть",
		bal.get_fall_damage_from_speed(sqrt(2.0 * G * 5.0) + 0.5, G) > 0.0)
	check("гашеный пропеллером спуск (2.5 кл/с) не наносит урона",
		bal.get_fall_damage_from_speed(2.5, G) == 0.0)

	_check_drill_rig_multipliers(bal)

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	quit(1 if failures > 0 else 0)


func _check_free_fall_matches_height_formula(bal, height: float) -> void:
	var speed := sqrt(2.0 * G * height)
	var by_height: float = bal.get_fall_damage(height)
	var by_speed: float = bal.get_fall_damage_from_speed(speed, G)
	check("высота %.0f клеток (v=%.2f): урон по скорости совпадает с уроном по высоте (%.3f ~ %.3f)" %
		[height, speed, by_speed, by_height], absf(by_speed - by_height) < 0.05)


## Бурмобиль (задача «Прыжок и полёт бурмобиля», решение владельца дословно):
## "урон от падения на 50% меньше, а высота, с которой он получает урон, в 3
## раза выше" — множители get_fall_damage_from_speed(dmg_mult, height_mult),
## см. Balance.get_drill_rig_fall_damage_mult/get_drill_rig_fall_damage_height_mult.
## Проверяется КОЭФФИЦИЕНТ (отношение бурмобиль/пешком), а не абсолютное
## число — как просил владелец.
func _check_drill_rig_multipliers(bal) -> void:
	var dmg_mult: float = bal.get_drill_rig_fall_damage_mult()
	var height_mult: float = bal.get_drill_rig_fall_damage_height_mult()
	check("бонус бурмобиля к порогу высоты — тот, что дал владелец (×3)",
		absf(height_mult - 3.0) < 0.0001)
	check("бонус бурмобиля к урону — тот, что дал владелец (×0.5)",
		absf(dmg_mult - 0.5) < 0.0001)

	# Скорость удара, которая уже ранит пешего героя (чуть выше его порога,
	# min_height_cells=5) — тот же удар в бурмобиле обязан остаться целым,
	# поскольку его порог высоты втрое дальше (падение с высоты втрое дальше
	# даёт скорость больше не втрое, а в sqrt(3) раз — это сама физика
	# свободного падения v=sqrt(2gh), не ошибка множителя).
	var v_hurts_pedestrian: float = sqrt(2.0 * G * 5.0) + 0.5
	check("пешего этот удар уже ранит (контроль)",
		bal.get_fall_damage_from_speed(v_hurts_pedestrian, G) > 0.0)
	check("тот же удар в бурмобиле — без урона (порог высоты ×3 не пройден)",
		bal.get_fall_damage_from_speed(v_hurts_pedestrian, G, dmg_mult, height_mult) == 0.0)

	# Урон при заведомо высокой скорости удара (выше порога и пешему, и
	# бурмобилю) должен отличаться РОВНО в dmg_mult раз — сам множитель урона
	# не зависит от того, что порог высоты тоже сдвинут.
	var v_high: float = sqrt(2.0 * G * 30.0)
	var dmg_foot: float = bal.get_fall_damage_from_speed(v_high, G)
	var dmg_rig: float = bal.get_fall_damage_from_speed(v_high, G, dmg_mult, height_mult)
	check("урон в бурмобиле на высокой скорости удара вдвое меньше пешего (коэффициент владельца)",
		dmg_foot > 0.0 and absf(dmg_rig / dmg_foot - dmg_mult) < 0.001)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)

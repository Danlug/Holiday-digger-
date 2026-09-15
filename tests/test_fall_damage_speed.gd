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

	print("=== Итог: %d проверок, %d провалов ===" % [total, failures])
	quit(1 if failures > 0 else 0)


func _check_free_fall_matches_height_formula(bal, height: float) -> void:
	var speed := sqrt(2.0 * G * height)
	var by_height: float = bal.get_fall_damage(height)
	var by_speed: float = bal.get_fall_damage_from_speed(speed, G)
	check("высота %.0f клеток (v=%.2f): урон по скорости совпадает с уроном по высоте (%.3f ~ %.3f)" %
		[height, speed, by_speed, by_height], absf(by_speed - by_height) < 0.05)


func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		print("[OK] " + label)
	else:
		failures += 1
		print("[FAIL] " + label)

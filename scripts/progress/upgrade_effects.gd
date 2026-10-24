class_name UpgradeEffects
extends Node
## Доводит до дела те две ветки прокачки, которые ядро само не учитывает.
##
## Семь веток из девяти читаются игрой на ходу: радиусы тумана берутся каждый
## кадр (main.gd), скорость копки — в момент удара (player.gd), сила и HP —
## через GameState.get_max_carry_kg/get_max_hp, удача — при завершении копки.
## А расход бодрости и голода в GameState._tick_survival считается без
## ступеней: Balance.get_bar_depletion_rate_per_second про них не знает.
##
## ПОЧЕМУ здесь, а не в самом тике: game_state.gd — общий файл, на его
## существующих функциях держатся тесты и соседние системы, и переписывать
## тик выживания ради двух веток нельзя. Узел работает в ту же сторону, что
## и тик: тик списывает полный расход, узел тем же кадром возвращает ровно ту
## долю, которую по ГДД (раздел 11) сэкономила прокачка. Формулы взяты из
## data/upgrades.json, так что число на экране прокачки и поведение полоски
## приходят из одного места.
##
## Когда владелец решит перенести это в тик выживания — узел просто удаляется,
## никаких других следов в игре у него нет.


func _process(delta: float) -> void:
	if not GameState.is_alive:
		return  # тик выживания в этот момент тоже ничего не списывает
	_refund("stamina", delta)
	_refund("hunger", delta)


func _refund(bar: String, delta: float) -> void:
	var stage := GameState.get_skill_stage(bar)
	if stage <= 0:
		return
	var value: float = GameState.stamina if bar == "stamina" else GameState.hunger
	# На нуле возвращать нечего: полоска пуста, и утечка HP уже началась —
	# долив крошечной доли просто дёргал бы её между нулём и нулём с хвостиком.
	if value <= 0.0:
		return

	var rate := Balance.get_bar_depletion_rate_per_second(bar, GameState.is_digging)
	var drained := rate * 100.0 * delta
	var saved := drained * _saved_fraction(bar, stage)
	if saved <= 0.0:
		return
	if bar == "stamina":
		GameState.set_stamina(value + saved)
	else:
		GameState.set_hunger(value + saved)


## Какая доля списанного расхода возвращается на данной ступени.
##   Выносливость: +15% времени до истощения за ступень, то есть полоска
##     живёт base*(1+0.15*stage) — значит расход в (1+0.15*stage) раз меньше.
##   Голод: −8% расхода за ступень напрямую, но не ниже 20% от базового
##     (иначе на 10 ступенях расход ушёл бы в ноль).
func _saved_fraction(bar: String, stage: int) -> float:
	var branch := Balance.get_upgrade_branch(bar)
	var effect: Dictionary = branch.get("effect", {})
	var percent := float(Balance.unwrap(effect.get("percent_per_stage", 0)))
	if percent <= 0.0:
		return 0.0
	if bar == "stamina":
		var factor := 1.0 + percent / 100.0 * float(stage)
		return 1.0 - 1.0 / factor
	return clampf(percent / 100.0 * float(stage), 0.0, 0.8)

class_name HouseSleep
extends RefCounted
## HouseSleep — сон в кровати (ГДД п.7 и п.9).
##
## Числа ГДД: 8 игровых часов за 1 реальный, 12.5% бодрости за игровой час,
## полное восстановление за 8 игровых часов, минимальный сон 2 игровых часа
## (25%), анимация пропускается — нажал кровать и уже бодрый.
##
## Восстановление привязано к ИГРОВЫМ часам, а не к реальному времени, и
## поэтому сон мгновенный: иначе игрок обходит механику, просто выйдя из игры
## на час. Обратная сторона мгновенного сна — он ничего не стоит, если не
## считать расход голода; поэтому голод тратится по количеству ПРОСПАННЫХ
## ИГРОВЫХ ЧАСОВ (см. hunger_cost), а не по реальным секундам, которых нет.

## Сколько игровых часов имеет смысл проспать при текущей бодрости:
## ровно столько, чтобы добрать до 100%, но не меньше минимума (2 часа) и не
## больше полной ночи (8 часов). Игрок жмёт кровать один раз — выбор длины
## сна отдельным диалогом только мешает: ГДД требует «нажал → уже бодрый».
static func hours_needed(stamina_percent: float) -> float:
	var per_hour := Balance.get_sleep_restore_percent_per_game_hour()
	if per_hour <= 0.0:
		return Balance.get_min_sleep_game_hours()
	var full_night := 100.0 / per_hour
	var needed := (100.0 - stamina_percent) / per_hour
	return clampf(needed, Balance.get_min_sleep_game_hours(), full_night)


## Сколько процентов голода съест сон длиной hours игровых часов.
## Считается от обычной скорости расхода голода на простое (полная полоска за
## реальный час = за 8 игровых часов), умноженной на house.sleep_hunger_factor.
static func hunger_cost(hours: float) -> float:
	var game_hours_per_real := Balance.get_game_hours_per_real_hour()
	if game_hours_per_real <= 0.0:
		return 0.0
	var real_seconds := hours / game_hours_per_real * 3600.0
	var rate := Balance.get_bar_depletion_rate_per_second("hunger", false)
	return rate * 100.0 * real_seconds * HouseConfig.sleep_hunger_factor()


## Можно ли сейчас лечь. Возвращает {ok, hours, hunger_cost, stamina_gain, reason}.
## Отказ — только по голоду: лечь голодным нельзя, потому что сон прокручивает
## игровые часы, голод за них уходит в ноль и герой не просыпается вовсе
## (полоска на нуле сразу начинает жечь HP).
static func plan(stamina_percent: float, hunger_percent: float) -> Dictionary:
	var hours := hours_needed(stamina_percent)
	var cost := hunger_cost(hours)
	var gain: float = minf(100.0 - stamina_percent,
		Balance.get_sleep_restore_percent_per_game_hour() * hours)
	var result := {
		"ok": true,
		"hours": hours,
		"hunger_cost": cost,
		"stamina_gain": gain,
		"reason": "",
	}
	# Минимальный сон по ГДД — 2 игровых часа, и они отдают 25% бодрости.
	# Лечь с почти полной полоской значит сжечь лишнее и всё равно заплатить
	# сытостью за эти два часа, то есть отдать еду ни за что.
	if 100.0 - stamina_percent < HouseConfig.sleep_min_deficit_percent():
		result["ok"] = false
		result["reason"] = "Спать пока незачем: бодрость почти полная, а сытость за сон спишется."
		return result
	if hunger_percent < cost:
		result["ok"] = false
		result["reason"] = "Ляжешь голодным — не проснёшься. Сначала поешь (нужно %d%% сытости)." % int(ceil(cost))
	return result


## Укладывает героя спать. Возвращает тот же словарь, что и plan(), с
## фактически применёнными числами; при отказе ничего не меняет.
## force=true — принудительный сон обучения (ГДД п.9, первое истощение):
## там герой ложится независимо от голода, иначе обучение зайдёт в тупик у
## игрока, у которого пусты обе полоски.
static func sleep_now(force: bool = false) -> Dictionary:
	var result := plan(GameState.stamina, GameState.hunger)
	if not result["ok"] and not force:
		return result
	if force:
		# Обучающий сон ничего не стоит: игрок попадает в него с пустой
		# полоской бодрости, HP уже течёт, и списать за урок ещё и голод —
		# значит добить того, кого только что взялись учить.
		result["hunger_cost"] = 0.0
	GameState.sleep(float(result["hours"]))
	GameState.set_hunger(GameState.hunger - float(result["hunger_cost"]))
	result["ok"] = true
	return result

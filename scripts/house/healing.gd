class_name Healing
extends RefCounted
## Healing — чем лечится HP (решение владельца, раунд 4, ГДД §7 «Лечение»):
## сон, еда, аптечка из лавки, и что стоит смерть (плата больнице).
##
## Раньше HP возвращали только таблетка за доллары и смерть — и смерть с пустым
## рюкзаком была бесплатным лечением (docs/PLAYTEST.md, P1-3). Теперь:
##  * сон лечит пропорционально часам и сытости: сытый за полную ночь получает
##    hp_percent_full_night, голодный — меньше («в здоровом теле здоровый дух»);
##  * еда лечит по питательности (доля её процентов сытости);
##  * аптечка — предмет рюкзака, «применить» лечит заметную часть сразу;
##  * смерть, кроме рюкзака, забирает 5% монет, от 50 до 5000 (раунд 5, не в
##    минус) — «потрачено на больницу» в окне смерти; после смерти HP полное,
##    сытость и бодрость не ниже 25% (владелец, разбор чисел 26.10).
## Числа — data/healing.json.

const DATA_PATH := "res://data/healing.json"

static var _data: Dictionary = {}
static var _loaded := false
## Сколько взяла больница при последней смерти: окно смерти показывает его после
## респавна. Число, а не состояние игры — переживать перезагрузку ему не вредно.
static var last_death_fee := 0


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		if FileAccess.file_exists(DATA_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


static func reload() -> void:
	_loaded = false


static func _num(section: String, key: String, fallback: float) -> float:
	var v = Balance.unwrap(data().get(section, {}).get(key, fallback))
	return float(v) if v != null else fallback


# ---------------------------------------------------------------------------
# Сон
# ---------------------------------------------------------------------------

## Сколько игровых часов — «полная ночь» (та же, что у бодрости: 100% / 12.5% в час).
static func full_night_hours() -> float:
	var per_hour := Balance.get_sleep_restore_percent_per_game_hour()
	return 100.0 / per_hour if per_hour > 0.0 else 8.0


static func sleep_min_hp_deficit_percent() -> float:
	return _num("sleep", "min_hp_deficit_percent", 10.0)


## Сила лечения во сне по средней сытости за сон: 1 — сытый, hungry_factor — голодный.
static func sleep_fed_factor(mean_satiety: float) -> float:
	var fed := _num("sleep", "fed_full_at_percent", 60.0)
	var hungry := _num("sleep", "hungry_at_percent", 10.0)
	var low := _num("sleep", "hungry_factor", 0.25)
	if fed <= hungry:
		return 1.0 if mean_satiety >= fed else low
	return lerpf(low, 1.0, clampf((mean_satiety - hungry) / (fed - hungry), 0.0, 1.0))


## Процент HP за час сна в полную силу (сытым).
static func sleep_hp_percent_per_hour() -> float:
	return _num("sleep", "hp_percent_full_night", 75.0) / full_night_hours()


## Сколько процентов HP вернёт сон длиной hours: satiety — сытость при отходе
## ко сну, hunger_cost — сколько сон её съест (средняя сытость — посередине).
## Без учёта того, сколько HP не хватает: это решает вызывающий.
static func sleep_hp_percent(hours: float, satiety: float, hunger_cost: float) -> float:
	var mean := satiety - hunger_cost * 0.5
	return maxf(0.0, sleep_hp_percent_per_hour() * hours * sleep_fed_factor(mean))


## Сколько часов сна нужно, чтобы добрать hp_deficit_percent в полную силу.
static func sleep_hours_for_hp(hp_deficit_percent: float) -> float:
	var per_hour := sleep_hp_percent_per_hour()
	if per_hour <= 0.0 or hp_deficit_percent <= 0.0:
		return 0.0
	return hp_deficit_percent / per_hour


# ---------------------------------------------------------------------------
# Еда и аптечка
# ---------------------------------------------------------------------------

## Сколько процентов HP лечит блюдо (целым числом — его же показывает подсказка).
## Питательность — проценты сытости из balance.json → food.items.
static func food_hp_percent(id: String) -> int:
	if not HouseConfig.is_food(id):
		return 0
	return int(round(HouseConfig.food_hunger_percent(id) * _num("food", "hp_percent_per_satiety_percent", 0.25)))


static func medkit_id() -> String:
	return String(data().get("medkit", {}).get("id", "medkit"))


static func is_medkit(id: String) -> bool:
	return id != "" and id == medkit_id()


static func medkit_hp_percent() -> int:
	return int(round(_num("medkit", "hp_percent", 50.0)))


## Сколько процентов HP даёт предмет рюкзака (еда или аптечка): для подсказок
## и карточки магазина. 0 — не лечит.
static func item_hp_percent(id: String) -> int:
	if is_medkit(id):
		return medkit_hp_percent()
	return food_hp_percent(id)


## Лечит на percent процентов полоски. Возвращает, сколько HP реально прибавилось.
static func heal_percent(percent: float) -> float:
	if percent <= 0.0 or not GameState.is_alive:
		return 0.0
	var before := GameState.hp
	GameState.heal(GameState.get_max_hp() * percent / 100.0)
	return GameState.hp - before


## «Применить» аптечку из рюкзака. Тот же ответ, что у HouseFood.eat, плюс hp.
## При полном здоровье не тратится: аптечка дорогая, а промах пальцем частый.
static func use_medkit() -> Dictionary:
	var id := medkit_id()
	if GameState.get_item_count(id) <= 0:
		return {"ok": false, "hunger": 0.0, "stamina": 0.0, "hp": 0.0, "reason": "Аптечки в рюкзаке нет."}
	if GameState.hp >= GameState.get_max_hp() - 0.01:
		return {"ok": false, "hunger": 0.0, "stamina": 0.0, "hp": 0.0, "reason": "Здоровье и так полное."}
	GameState.remove_item(id, 1)
	var gained := heal_percent(float(medkit_hp_percent()))
	GameState.emit_event(&"healed", {"source": "medkit", "hp": gained})
	return {"ok": true, "hunger": 0.0, "stamina": 0.0, "hp": gained, "reason": ""}


# ---------------------------------------------------------------------------
# Смерть: плата больнице и полоски после неё
# ---------------------------------------------------------------------------

## Плата больнице с coins монет при себе (владелец, раунд 5): 5% вниз до целого,
## не меньше 50 и не больше 5000; меньше 50 монет — сколько есть, в минус не уходим.
static func death_fee_for(coins: int) -> int:
	if coins <= 0:
		return 0
	var lo := death_fee_min()
	var fee := clampi(int(floor(float(coins) * death_fee_percent() / 100.0)), lo, maxi(lo, death_fee_max()))
	return mini(fee, coins)


static func death_fee_percent() -> float:
	return _num("death", "coins_percent", 5.0)


static func death_fee_min() -> int:
	return int(_num("death", "coins_min", 50.0))


static func death_fee_max() -> int:
	return int(_num("death", "coins_max", 5000.0))


## Сколько возьмёт больница, если умереть сейчас (подсказки).
static func death_fee_coins() -> int:
	return death_fee_for(GameState.coins)


## Списывает плату больнице при несюжетной смерти (зовёт GameState.die()). Мимо
## spend_coins: это не покупка, и задание дня «потрать N монет» смерть
## засчитывать не должна. Возвращает списанное.
static func charge_death_fee() -> int:
	var fee := death_fee_for(GameState.coins)
	if fee > 0:
		GameState.coins -= fee
		GameState.coins_changed.emit(GameState.coins)
	last_death_fee = fee
	GameState.emit_event(&"hospital", {"coins": fee})
	return fee


static func respawn_hp_percent() -> float:
	return clampf(float(Balance.unwrap(data().get("death", {}).get("respawn", {}).get("hp_percent", 100.0))), 1.0, 100.0)


static func respawn_bars_min_percent() -> float:
	return clampf(float(Balance.unwrap(data().get("death", {}).get("respawn", {}).get("bars_min_percent", 25.0))), 0.0, 100.0)


## Респавн дома после смерти (main.gd): HP — respawn.hp_percent (владелец: полное),
## сытость и бодрость — как были в миг смерти, но не ниже bars_min_percent. Мёртвый
## герой полоски не тратит (GameState не тикает), поэтому «как были» — это они сейчас.
## До конца онбординга (флаг gold_sold) — все полоски полные, как было всегда.
static func respawn_after_death() -> void:
	var hunger := GameState.hunger
	var stamina := GameState.stamina
	GameState.ext.erase("death_ride")   # остаток поездки из сейвов раунда 5: поездки больше нет
	GameState.respawn()
	if not StoryState.has_flag("gold_sold"):
		return
	var max_hp := GameState.get_max_hp()
	GameState.hp = max_hp * respawn_hp_percent() / 100.0
	GameState.hp_changed.emit(GameState.hp, max_hp)
	var min_bar := respawn_bars_min_percent()
	GameState.set_hunger(maxf(hunger, min_bar))
	GameState.set_stamina(maxf(stamina, min_bar))

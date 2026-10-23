class_name MetaClock
extends RefCounted
## Время мета-слоя. Сутки и недели считаются по UTC (как лимиты рекламы в
## GameState), игровые часы и сон тут ни при чём — иначе мгновенный сон
## прокручивал бы дни и печатал награды.
##
## «Сегодня» для наград берётся через MetaState.today(): оно не идёт назад.
## Если игрок отмотал часы телефона, новый день не наступает, а старый не
## возвращается — повторной выдачи нет. Перемотку вперёд без сервера не
## отличить от долгого отсутствия; она бьёт только по самому игроку (награды
## «убегают» вперёд и ждут, пока настоящая дата догонит).

const DAY := 86400

## Подмена времени для тестов: -1 — настоящие часы.
static var override_unix: int = -1


static func now_unix() -> int:
	return override_unix if override_unix >= 0 else int(Time.get_unix_time_from_system())


## Номер суток с 1970-01-01 (UTC).
@warning_ignore("integer_division")
static func real_day() -> int:
	return now_unix() / DAY


## Номер недели: неделя с понедельника (1970-01-01 был четвергом).
@warning_ignore("integer_division")
static func week_of(day: int) -> int:
	return (day + 3) / 7


static func date_str(day: int) -> String:
	return Time.get_date_string_from_unix_time(day * DAY)


static func seconds_to_next_day() -> int:
	return DAY - now_unix() % DAY


## Сколько суток осталось до понедельника, включая сегодняшние (1..7).
static func days_left_in_week(day: int) -> int:
	return (week_of(day) + 1) * 7 - 3 - day

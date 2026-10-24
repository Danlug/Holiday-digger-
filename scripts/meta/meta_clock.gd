class_name MetaClock
extends RefCounted
## Время мета-слоя. Сутки и недели — по МЕСТНОМУ времени игрока: задания и
## подарок дня обновляются в полночь у него на часах, как принято в мобильных
## играх (раньше было 00:00 UTC — в Израиле это три часа ночи, в Москве — три,
## в Нью-Йорке — восемь вечера). Игровые часы и сон тут ни при чём — иначе
## мгновенный сон прокручивал бы дни и печатал награды.
##
## «Сегодня» для наград берётся через MetaState.today(): оно не идёт назад.
## Если игрок отмотал часы телефона (или сменил пояс на запад), новый день не
## наступает, а старый не возвращается — повторной выдачи нет. Перемотку вперёд
## без сервера не отличить от долгого отсутствия; она бьёт только по самому
## игроку (награды «убегают» вперёд и ждут, пока настоящая дата догонит).
##
## Лимиты рекламы (GameState.ad_daily_counts) по-прежнему сбрасываются по UTC —
## это схема GameState, не мета-слоя.

const DAY := 86400
## «Пояс не подменён»: смещение берётся у системы.
const TZ_AUTO := -999999
## Смещение пояса меняется редко (перелёт, переход на летнее время) — читаем
## его у ОС не чаще раза в минуту: today() зовётся на каждую выкопанную клетку.
const TZ_CACHE_MS := 60000

## Подмена времени для тестов: -1 — настоящие часы.
static var override_unix: int = -1
## Подмена пояса для тестов (секунды к UTC, восток — плюс). Пока часы подменены,
## а пояс нет, считается UTC: тест не должен зависеть от пояса машины.
static var override_tz_sec: int = TZ_AUTO

static var _tz_cached: int = 0
static var _tz_read_at: int = -TZ_CACHE_MS


static func now_unix() -> int:
	return override_unix if override_unix >= 0 else int(Time.get_unix_time_from_system())


## Смещение местного времени от UTC, секунды (UTC+3 → 10800).
static func tz_offset_sec() -> int:
	if override_tz_sec != TZ_AUTO:
		return override_tz_sec
	if override_unix >= 0:
		return 0
	var now := Time.get_ticks_msec()
	if now - _tz_read_at >= TZ_CACHE_MS:
		_tz_read_at = now
		_tz_cached = _system_tz_offset()
	return _tz_cached


## Разница «местные часы, прочитанные как UTC» минус UTC — так не нужно знать,
## какой знак у bias на какой платформе. Округление до минуты гасит секунду,
## которая могла тикнуть между двумя вызовами.
static func _system_tz_offset() -> int:
	var local := Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system(false))
	var utc := Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system(true))
	var off := int(round(float(local - utc) / 60.0)) * 60
	return clampi(off, -14 * 3600, 14 * 3600)


static func local_unix() -> int:
	return now_unix() + tz_offset_sec()


## Номер местных суток с 1970-01-01 — «сегодня» мета-слоя (через MetaState.today()).
static func local_day() -> int:
	return floori(float(local_unix()) / float(DAY))


## Номер суток UTC. Его читает ShopRemote: лимит удалённых покупок — рекламный,
## а реклама считается по UTC (GameState.ad_daily_counts).
@warning_ignore("integer_division")
static func real_day() -> int:
	return now_unix() / DAY


## Номер недели: неделя с понедельника (1970-01-01 был четвергом).
@warning_ignore("integer_division")
static func week_of(day: int) -> int:
	return (day + 3) / 7


static func date_str(day: int) -> String:
	return Time.get_date_string_from_unix_time(day * DAY)


## Секунд до местной полуночи — до обновления заданий и подарка дня.
static func seconds_to_next_day() -> int:
	return DAY - posmod(local_unix(), DAY)


## «05:12:33» — для таймера до обновления.
@warning_ignore("integer_division")
static func hms(sec: int) -> String:
	sec = maxi(0, sec)
	return "%02d:%02d:%02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]


## Сколько суток осталось до понедельника, включая сегодняшние (1..7).
static func days_left_in_week(day: int) -> int:
	return (week_of(day) + 1) * 7 - 3 - day

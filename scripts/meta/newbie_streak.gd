class_name NewbieStreak
extends RefCounted
## Стрик новичка (владелец 27.10): 30 дней ежедневной отметки за вход — «это не
## миссии, а просто отметка за ежедневный вход». Награды дней — data/newbie_streak.json.
## Чистая логика над GameState.ext — без узлов, поэтому проверяется автотестом
## на подставных часах.
##
## Календарь. День 1 — местные сутки, в которые мета-слой включился (конец
## онбординга); у сейва, где мета-слой уже был включён, — сутки первого запуска
## с этой версией. День N открыт в N-е сутки и только в них: отметить можно
## лишь «сегодняшний» день, прошедший неотмеченный — пропущен (его можно
## вернуть за доллары, в любой момент, и после 30-х суток тоже — иначе крупный
## подарок сгорал бы навсегда), будущие закрыты. «Сегодня» — MetaState.today():
## местная полночь, как у заданий дня, и не идёт назад — перевод часов назад и
## смена пояса на запад не открывают вчерашний день заново.
##
## Отметка: игра открыта (мета-слой включён) в сутки дня — день засчитан сразу,
## делать ничего не надо (refresh, его зовёт узел раз в секунду). Награду можно
## забрать и позже, день от этого не сгорает.
##
## Схема GameState.ext["newbie_streak"]:
##   v      — версия схемы
##   start  — местные сутки дня 1 (-1 — ещё не начался)
##   days   — {"N": {done, how: "visit"|"bought" (у старых сейвов — "missions"), at: сутки, claimed}}
##   grand  — крупный подарок забран (заглушка: пока не выдаётся)

const KEY := "newbie_streak"
const VERSION := 1
const DATA_PATH := "res://data/newbie_streak.json"

enum St { LOCKED, TODAY, DONE, MISSED }

static var _data: Dictionary = {}


# ---------------------------------------------------------------------------
# Данные
# ---------------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
		if _data.is_empty():
			push_error("NewbieStreak: не удалось прочитать %s" % DATA_PATH)
	return _data


static func days_total() -> int:
	return int(Balance.unwrap(data().get("days_total", 30)))


static func restore_price() -> int:
	return int(Balance.unwrap(data().get("restore_dollars", 50)))


static func day_def(n: int) -> Dictionary:
	var days: Array = data().get("days", [])
	if n < 1 or n > days.size():
		return {}
	return days[n - 1]


static func reward(n: int) -> Dictionary:
	return MetaRewards.normalize(day_def(n).get("reward", {}))


## Строка интерфейса на языке настроек; нет перевода — русская.
static func text(key: String) -> String:
	var texts: Dictionary = data().get("texts", {})
	var table: Dictionary = texts.get(String(Settings.language), {})
	if table.has(key):
		return String(table[key])
	return String(texts.get("ru", {}).get(key, key))


## «300 монет · 120 опыта · Энергетик ×1» — для подсказки.
static func describe_reward(r: Dictionary) -> String:
	r = MetaRewards.normalize(r)
	var parts: Array[String] = []
	if r.has("coins"):
		parts.append(text("coins") % int(r["coins"]))
	if r.has("dollars"):
		parts.append(text("dollars") % int(r["dollars"]))
	if r.has("xp"):
		parts.append(text("xp") % int(r["xp"]))
	if r.has("item"):
		var id := String(r["item"]["id"])
		var m: Dictionary = Balance.get_mineral(id)
		var name := String(m.get("name_en", "")) if String(Settings.language) == "en" else ""
		if name == "":
			name = String(m.get("name_ru", id))
		parts.append("%s ×%d" % [name, int(r["item"]["count"])])
	return " · ".join(parts)


# ---------------------------------------------------------------------------
# Сохраняемое состояние
# ---------------------------------------------------------------------------

## Узел не кэшируется: загрузка сейва подменяет ext целиком, сброс игры его чистит.
static func state() -> Dictionary:
	var s = GameState.ext.get(KEY)
	if typeof(s) != TYPE_DICTIONARY:
		s = {"v": VERSION, "start": -1, "days": {}, "grand": false}
		GameState.ext[KEY] = s
	if typeof(s.get("days")) != TYPE_DICTIONARY:
		s["days"] = {}
	if not s.has("start"):
		s["start"] = -1
	return s


static func start_day() -> int:
	return int(state()["start"])


static func is_started() -> bool:
	return start_day() >= 0


## Начать календарь, когда мета-слой включён. Возвращает true, если начал сейчас.
static func ensure_started() -> bool:
	if is_started() or not MetaState.is_unlocked():
		return false
	state()["start"] = MetaState.today()
	return true


## Номер «сегодняшнего» дня стрика: 1..; 0 — стрик не начался. Может быть больше
## days_total() — месяц прошёл.
static func current_index() -> int:
	if not is_started():
		return 0
	return MetaState.today() - start_day() + 1


static func rec(n: int) -> Dictionary:
	var days: Dictionary = state()["days"]
	var k := str(n)
	var r = days.get(k)
	if typeof(r) != TYPE_DICTIONARY:
		r = {"done": false, "claimed": false}
		days[k] = r
	return r


## Только чтение: не заводит запись (экран рисует 30 плиток каждую секунду).
static func _peek(n: int) -> Dictionary:
	var r = (state()["days"] as Dictionary).get(str(n))
	return r if typeof(r) == TYPE_DICTIONARY else {}


static func is_done(n: int) -> bool:
	return bool(_peek(n).get("done", false))


static func is_claimed(n: int) -> bool:
	return bool(_peek(n).get("claimed", false))


static func was_bought(n: int) -> bool:
	return String(_peek(n).get("how", "")) == "bought"


static func status(n: int) -> int:
	if n < 1 or n > days_total():
		return St.LOCKED
	if is_done(n):
		return St.DONE
	var cur := current_index()
	if cur <= 0 or n > cur:
		return St.LOCKED
	return St.TODAY if n == cur else St.MISSED


static func today_n() -> int:
	var cur := current_index()
	return cur if cur >= 1 and cur <= days_total() else 0


static func done_count() -> int:
	var n := 0
	for i in range(1, days_total() + 1):
		if is_done(i):
			n += 1
	return n


static func all_done() -> bool:
	return done_count() >= days_total()


## Сколько суток до открытия дня n (для закрытой плитки).
static func days_until(n: int) -> int:
	return maxi(0, n - maxi(current_index(), 1))


# ---------------------------------------------------------------------------
# Отметка за вход
# ---------------------------------------------------------------------------

## Отметить сегодняшний день, если ещё не отмечен. Зовётся узлом раз в секунду —
## так отмечается и первый вход за сутки, и полночь посреди игры. Возвращает
## номер дня, отмеченного именно сейчас, или 0.
static func refresh() -> int:
	ensure_started()
	var n := today_n()
	if n == 0 or is_done(n):
		return 0
	var r := rec(n)
	r["done"] = true
	r["how"] = "visit"
	r["at"] = MetaState.today()
	return n


# ---------------------------------------------------------------------------
# Награда дня и возврат пропущенного дня
# ---------------------------------------------------------------------------

static func can_claim(n: int) -> bool:
	return is_done(n) and not is_claimed(n)


static func claimable_count() -> int:
	var k := 0
	for i in range(1, days_total() + 1):
		if can_claim(i):
			k += 1
	return k


## Забрать награду засчитанного дня. Отметка — до выдачи: второе нажатие ничего не даст.
static func claim(n: int) -> Dictionary:
	if not can_claim(n):
		return {"ok": false}
	rec(n)["claimed"] = true
	var granted := MetaRewards.grant(reward(n), false)
	return {"ok": true, "day": n, "reward": granted}


## Забрать всё готовое (бот и «забрать всё»). Возвращает число забранных дней.
static func claim_all() -> int:
	var k := 0
	for i in range(1, days_total() + 1):
		if bool(claim(i)["ok"]):
			k += 1
	return k


## Пропущенный день — и хватает ли долларов (кнопку рисуют и без них — серой).
static func can_restore(n: int) -> bool:
	return status(n) == St.MISSED and GameState.dollars >= restore_price()


## Вернуть пропущенный день за доллары: отмечается и
## сразу выдаёт награду дня. Сейв пишется сразу — это покупка за доллары.
static func restore(n: int) -> Dictionary:
	if status(n) != St.MISSED:
		return {"ok": false, "reason": "not_missed"}
	var price := restore_price()
	if GameState.dollars < price or not GameState.spend_dollars(price):
		return {"ok": false, "reason": "dollars"}
	var r := rec(n)
	r["done"] = true
	r["how"] = "bought"
	r["at"] = MetaState.today()
	r["claimed"] = true
	var granted := MetaRewards.grant(reward(n), false)
	_save_now("newbie_restore")
	return {"ok": true, "day": n, "reward": granted, "price": price}


## Без мира (тест на одном GameState) сейв не пишется: он затёр бы диффы мира.
static func _save_now(reason: String) -> void:
	if GameState.world_ref != null:
		SaveSystem.save_now(reason)


# ---------------------------------------------------------------------------
# Крупный подарок (заглушка)
# ---------------------------------------------------------------------------

static func grand_ready() -> bool:
	return all_done()


## Подарок ещё не придуман владельцем: «скоро», забрать нельзя.
static func grand_available() -> bool:
	return String(data().get("grand_prize", {}).get("status", "soon")) != "soon" and grand_ready() \
		and not bool(state().get("grand", false))

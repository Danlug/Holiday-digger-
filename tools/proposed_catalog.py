# -*- coding: utf-8 -*-
"""
Каталог для tools/proposed_numbers.py: что значит каждое предложенное число — по-человечески.

  THEMES   — темы для владельца (порядок в выгрузке), что в теме решить и общий совет;
  FAMILIES — семейства чисел: шаблоны id «файл:путь», подпись строки, единица, на что влияет,
             расчёт «чем обернётся в игре» и совет (оставить / поднять / опустить / решить / убрать);
  TOP      — десять самых важных решений (сверху REVIEW.md).

Шаблоны id: «*» — один сегмент пути (без точек и скобок), «**» — что угодно.
Число, которое не подошло ни к одному семейству, всё равно попадает в выгрузку — в «новые без разбора»
своей темы (тема — по файлу и ключу). Расчёты пишутся так, чтобы при чужих правках формы данных
выдавать «—», а не падать: инструмент перезапускают после каждого слияния.
"""

import math
import re

# ---------------------------------------------------------------------------
# Сопоставление id с шаблонами
# ---------------------------------------------------------------------------

_cache = {}


def _rx(pattern):
	if pattern not in _cache:
		out = ""
		i = 0
		while i < len(pattern):
			if pattern.startswith("**", i):
				out += ".*"
				i += 2
			elif pattern[i] == "*":
				out += r"[^.\[\]]*"
				i += 1
			else:
				out += re.escape(pattern[i])
				i += 1
		_cache[pattern] = re.compile("^" + out + "$")
	return _cache[pattern]


def match(pattern, rid):
	return bool(_rx(pattern).match(rid))


# Числа владельца, по ошибке лежащие внутри предложенного раздела, — не выгружаем.
SKIP = [
	"balance.json:tools.drill_rig.upgrade_tiers[*].speed_bonus",  # «каждый на 20% быстрее» — слова владельца
	"quests.json:templates[*].min_tier", "quests.json:templates[*].max_tier",  # служебные рамки шаблона
	# рамки по рекорду глубины: 1500 — слово владельца (монстры с 1500), 9950 — дно мира минус цель
	"quests.json:templates[*].record_min", "quests.json:templates[*].record_max",
	"combat.json:boss.hero_model**",  # модель героя для теста, не игра
	"minerals.json:minerals[food_*].price_coins",  # у блюд под общим proposed цена 0 — цена еды живёт в balance.json
	"minerals.json:minerals[fuel_block].recipe",  # «4 торфа = 1 блок» — ГДД §5, число владельца
]
# Ключ не встречается в коде буквально, но читается (имя собирается кодом) или правило держит сам код.
USED = [
	"balance.json:fuel_consumption.coal_per_fuel_block",  # FuelRefinery: "%s_per_fuel_block" % сырьё
	"shop.json:exchange.dollars_to_coins_only",  # обратного обмена в витрине просто нет
	"upgrades.json:branches[*].cost_note",  # пометка к cost_points — игра читает cost_points
	"monetization.json:dollar_packs**",  # платежей нет — пачки заготовлены на будущее
]


def is_used(rid):
	return any(match(p, rid) for p in USED)
# Поддеревья, которые выгружаются одной строкой (иначе вышли бы десятки строк по одной цифре).
BUNDLE = [
	"minerals.json:minerals[*].density",
	"combat.json:sets.*.bonuses", "combat.json:sockets.slots", "combat.json:boss.attacks.*", "combat.json:boss.arena",
	"fx_light.json:glow.*", "fx_light.json:torch", "fx_light.json:night",
	"world_layers.json:formations.kinds.*", "world_layers.json:formations.treasure", "world_layers.json:formations.gems",
	"world_layers.json:formations.ruin_loot",
	"tech.json:heat.lava.field",
	"newbie_streak.json:days[*]",  # день стрика новичка — одна строка: миссии и награда
]
SPLIT = []


def is_skipped(rid):
	return any(match(p, rid) for p in SKIP)


def is_bundle(rid):
	return any(match(p, rid) for p in BUNDLE)


def is_split(rid):
	return any(match(p, rid) for p in SPLIT)


# ---------------------------------------------------------------------------
# Темы
# ---------------------------------------------------------------------------

THEME_ORDER = ["economy", "mining", "survival", "progression", "quests", "artifacts", "tech", "combat", "mechanics",
	"monetization", "feel"]
THEME_TITLES = {
	"economy": "Экономика и цены",
	"mining": "Добыча и руды",
	"survival": "Выживание и лечение",
	"progression": "Прокачка и уровни",
	"quests": "Задания и награды",
	"artifacts": "Артефакты и музей",
	"tech": "Техника и топливо",
	"combat": "Бой",
	"mechanics": "Механики: тайники, азарт и жадность, мастерство, удача",
	"monetization": "Монетизация и ролики",
	"feel": "Ощущение, звук, свет и подсказки (мелочи интерфейса)",
}

# Тема для числа без разбора: по файлу, для balance.json и неизвестных файлов — по словам в пути.
FILE_THEME = {
	"minerals.json": "mining", "world_layers.json": "mining", "caves.json": "combat", "healing.json": "survival",
	"upgrades.json": "progression", "story_arc.json": "progression", "quests.json": "quests",
	"achievements.json": "quests", "daily_rewards.json": "quests", "artifacts.json": "artifacts", "tech.json": "tech",
	"combat.json": "combat", "mechanics.json": "mechanics", "monetization.json": "monetization", "shop.json": "economy",
	"feel.json": "feel", "juice.json": "feel", "hints.json": "feel", "dialogue.json": "feel", "fx_light.json": "feel",
	"guidance.json": "feel", "story.json": "progression", "newbie_streak.json": "quests",
}
KEYWORD_THEME = [
	(r"monster|combat|cave|polost|guard|chest_guard|enemy|boss", "combat"),
	(r"death|die|hunger|stamina|sleep|food|heal|house|survival|fatigue|tired|medkit|satiety|starv", "survival"),
	(r"peat|ore|mineral|density|layer|seam|depth_min|depth_max|formation", "mining"),
	(r"fuel|drill|tank|well|heat|lava|suit|refinery|rig", "tech"),
	(r"ad_|ads|dollar|premium|iap|price_usd", "monetization"),
	(r"skill|level|xp|upgrade", "progression"),
	(r"quest|achiev|reward|daily", "quests"),
	(r"camera|sfx|music|fx|hint|tip|toast|anim", "feel"),
]


def theme_for_unknown(row):
	fname = row["id"].split(":", 1)[0]
	path = row["id"].lower()
	if fname in FILE_THEME and fname != "balance.json":
		return FILE_THEME[fname]
	for rx, theme in KEYWORD_THEME:
		if re.search(rx, path):
			return theme
	return FILE_THEME.get(fname, "economy")


# ---------------------------------------------------------------------------
# Помощники расчётов
# ---------------------------------------------------------------------------

def elem(row, seg):
	"""id элемента списка сразу после сегмента seg: minerals[iron_ore] -> iron_ore."""
	segs = row["segs"]
	for i, s in enumerate(segs[:-1]):
		if s == seg and segs[i + 1].startswith("["):
			return segs[i + 1][1:-1]
	return None


def num(v, default=None):
	if isinstance(v, (int, float)) and not isinstance(v, bool):
		return float(v)
	return default


def _f(m):
	from proposed_numbers import fnum, fmin, fhours, pct  # noqa: WPS433 — общий модуль, без цикла на импорте
	return fnum, fmin, fhours, pct


def _parent_num(row, key, default=None):
	p = row.get("parent")
	if isinstance(p, dict):
		v = p.get(key)
		if isinstance(v, dict) and "value" in v:
			v = v["value"]
		return num(v, default)
	return default


# --- добыча ---

def eff_drill(m, row):
	fnum, _, _, _ = _f(m)
	mid = elem(row, "minerals")
	s = num(row["value"])
	if s is None:
		return None
	rusty, best, rig = s / m.dig_mult("rusty"), s / m.dig_mult("best"), s / m.dig_mult("drill_rig")
	txt = "клетка: %s с ржавой киркой, %s с обсидиановой, %s с бурмобилем" % (fnum(rusty, 1), fnum(best, 2), fnum(rig, 2))
	p = m.price(mid)
	if p > 0:
		txt += "; %s монет за секунду копки (камень — 0, земля — %s)" % (fnum(p / s, 1), fnum(1 / 3.0, 2))
	else:
		txt += "; не продаётся — идёт в рецепты"
	return txt


def sum_drill(m, rows):
	fnum, _, _, _ = _f(m)
	vals = []
	for r in rows:
		mid = elem(r, "minerals")
		s = num(r["value"])
		if s and m.price(mid) > 0:
			vals.append((m.price(mid) / s, m.name(mid), s, m.price(mid)))
	if not vals:
		return None
	vals.sort()
	lo, hi = vals[0], vals[-1]
	return ("быстрее всего окупается копка: %s (%s монет за секунду), медленнее всего из продаваемого: %s (%s с за %s монет). "
		"Общий темп крутит ×%s владельца, а не эти секунды"
		% (hi[1], fnum(hi[0], 1), lo[1], fnum(lo[2]), fnum(lo[3]), fnum(m.get("balance.json", "digging", "global_speed_multiplier", default=1.3))))


def eff_weight(m, row):
	fnum, _, _, _ = _f(m)
	mid = elem(row, "minerals")
	w = num(row["value"])
	if not w:
		return None
	base = num(m.get("balance.json", "carry_capacity", "base_kg"), 60.0)
	txt = "в рюкзак %s кг влезает %d шт." % (fnum(base), int(base // w))
	p = m.price(mid)
	if p > 0:
		txt += "; %s монет за кг" % fnum(p / w, 1)
	return txt


def sum_weight(m, rows):
	fnum, _, _, _ = _f(m)
	vals = [(m.price(elem(r, "minerals")) / num(r["value"]), m.name(elem(r, "minerals"))) for r in rows
		if num(r["value"]) and m.price(elem(r, "minerals")) > 0]
	if not vals:
		return None
	vals.sort()
	return "дешевле всего на кг: %s (%s монет/кг), дороже всего: %s (%s монет/кг) — рюкзак сам решает, что выносить" % (
		vals[0][1], fnum(vals[0][0], 1), vals[-1][1], fnum(vals[-1][0]))


def _layer_ore(m, mid):
	for o in m.data.get("world_layers.json", {}).get("ores", []):
		if o.get("id") == mid:
			return o
	return None


def eff_density(m, row):
	fnum, _, _, pct = _f(m)
	mid = elem(row, "minerals")
	v = row["value"]
	if not isinstance(v, dict):
		return None
	txt = ""
	if v.get("type") == "parabola":
		peak = num(v.get("peak_depth"))
		share = None
		if m.st and peak:
			try:
				share = m.st.cell_mix(int(peak)).get(mid)
			except Exception:
				share = None
		txt = "с глубины %s; пик на %s — %s%% породы" % (fnum(v.get("depth_min")), fnum(peak), fnum(v.get("peak_percent")))
		if share:
			txt += " (после соседних руд и пустот — %s шт. на 100 выкопанных клеток)" % fnum(share * 100, 1)
		txt += "; ниже — не меньше %s%% навсегда" % fnum(v.get("tail_percent"))
	elif v.get("type") == "flat":
		txt = "%s–%s%% породы ровно по всей полосе" % (fnum(v.get("percent_min")), fnum(v.get("percent_max")))
	return txt or None


def flags_density(m, row):
	"""Сверка с генератором: world_layers.json должен совпадать с minerals.json (ГДД §4.1)."""
	mid = elem(row, "minerals")
	v = row["value"]
	o = _layer_ore(m, mid)
	if not isinstance(v, dict) or v.get("type") != "parabola" or not o:
		return []
	bad = []
	if num(o.get("y_min")) != num(v.get("depth_min")):
		bad.append("начало")
	if num(o.get("peak_y")) != num(v.get("peak_depth")):
		bad.append("глубина пика")
	if num(o.get("peak")) is not None and abs(num(o.get("peak")) * 100 - num(v.get("peak_percent"), 0)) > 1e-6:
		bad.append("пик")
	if num(o.get("tail")) is not None and abs(num(o.get("tail")) * 100 - num(v.get("tail_percent"), 0)) > 0.01:
		bad.append("хвост")
	if bad:
		return ["расходится с генератором (world_layers.json): %s — в игре действует world_layers" % ", ".join(bad)]
	return []


def eff_scrap_depth(m, row):
	fnum, _, _, _ = _f(m)
	if not m.st:
		return None
	y1 = int(num(row["value"], 500))
	total = 0.0
	try:
		for y in range(6, y1 + 1):
			total += m.st.cell_mix(y).get("scrap", 0.0) * 32
	except Exception:
		return None
	return "на весь мир до %d — около %s металлолома (бур просит 100 бронзы = 100 лома, скважина — ещё 20)" % (y1, fnum(total))


# --- выживание ---

def _food_items(m):
	return {it.get("id"): it for it in m.data.get("balance.json", {}).get("food", {}).get("items", []) if isinstance(it, dict)}


def eff_trip_share(m, row, depths=(100, 300)):
	fnum, _, _, pct = _f(m)
	p = num(row["value"])
	if p is None:
		return None
	parts = []
	for d in depths:
		t = m.trip(d)
		if t:
			parts.append("%s ходки на глубине %d (ходка ≈ %s)" % (pct(p / t), d, fnum(t)))
	return ("= " + ", ".join(parts)) if parts else None


def eff_free_orders(m, row):
	fnum, _, _, pct = _f(m)
	n = num(row["value"], 0)
	steak = num(_food_items(m).get("food_steak", {}).get("price_coins"), 200)
	txt = "до %s монет еды в сутки бесплатно (%d стейка)" % (fnum(n * steak), n)
	fs = m.bots.get("food_share")
	if fs is not None:
		txt += "; боты тратят на еду %s заработанного" % pct(fs, 1)
	return txt


def eff_sleep_heal(m, row):
	fnum, _, _, _ = _f(m)
	v = num(row["value"])
	per = num(m.get("healing.json", "food", "hp_percent_per_satiety_percent"), 0.25)
	if v is None:
		return None
	return "полная ночь сытым + стейк = %s%%, + пельмени = %s%%, ночь без еды = %s%% (владелец: «при полном сне и еде — 90–100%%»)" % (
		fnum(min(100, v + 100 * per)), fnum(min(100, v + 75 * per)), fnum(v))


def eff_food_heal(m, row):
	fnum, _, _, _ = _f(m)
	k = num(row["value"])
	if k is None:
		return None
	items = _food_items(m)
	parts = ["%s +%s%%" % (it.get("name_ru", i), fnum(num(it.get("hunger_percent"), 0) * k, 0)) for i, it in items.items()
		if num(it.get("hunger_percent"), 0) > 0]
	return "HP за блюдо: " + ", ".join(parts) if parts else None


def eff_medkit_hp(m, row):
	fnum, _, _, _ = _f(m)
	hp = num(row["value"])
	price = None
	for it in (m.data.get("shop.json", {}).get("goods_coins", {}) or {}).get("extra", []) or []:
		if isinstance(it, dict) and it.get("id") == "medkit":
			price = num(it.get("price_coins", {}).get("value") if isinstance(it.get("price_coins"), dict) else it.get("price_coins"))
	if not hp or not price:
		return None
	steak = num(_food_items(m).get("food_steak", {}).get("price_coins"), 200)
	per = num(m.get("healing.json", "food", "hp_percent_per_satiety_percent"), 0.25)
	return "1%% HP аптечкой стоит %s монеты, стейком — %s (зато стейк ещё и кормит)" % (fnum(price / hp, 1), fnum(steak / (100 * per), 1))


def sum_medkit(m, rows):
	parts = []
	for r in rows:
		key = r["segs"][-1]
		if key in ("hp_percent", "price_coins") and r.get("effect"):
			parts.append(r["effect"])
	d = death_text(m)
	if d and not any(d in p for p in parts):
		parts.append(d)
	return "; ".join(parts) or None


def sum_reach(m, rows):
	fnum, fmin, _, _ = _f(m)
	runs = m.bots.get("runs", [])
	start = m.get("combat.json", "start_depth", default=4000)
	if not runs:
		return None
	depths = sorted(r.get("max_depth") or 0 for r in runs)
	hours = sorted(r.get("hours") or 0 for r in runs)
	return "бой с глубины %s; боты за %s–%s игровых часов дошли до %s–%s (медиана %s) и не встретили ни одного монстра" % (
		fnum(start), fnum(hours[0]), fnum(hours[-1]), fnum(depths[0]), fnum(depths[-1]), fnum(depths[len(depths) // 2]))


def death_text(m):
	fnum, _, _, _ = _f(m)
	parts = []
	for coins in (300, 2000, 20000):
		f = m.death_fee(coins)
		if f is not None:
			parts.append("%s при %s в кошельке" % (fnum(f), fnum(coins)))
	return ("смерть сейчас стоит " + ", ".join(parts) + " (и весь рюкзак)") if parts else None


def eff_medkit_price(m, row):
	fnum, _, _, _ = _f(m)
	p = num(row["value"])
	txt = eff_trip_share(m, row, (100,)) or ""
	d = death_text(m)
	if d:
		txt += ("; " if txt else "") + d
	return txt or None


def flags_medkit_price(m, row):
	p = num(row["value"])
	if p is None:
		return []
	f = m.death_fee(300)
	if f is not None and f < p:
		return ["смерть с пустым рюкзаком (%d монет при 300 в кошельке) дешевле аптечки (%d) и лечит до 100%% — снова «лучший доктор»" % (f, p)]
	return []


def eff_fall_hp(m, row):
	fnum, _, _, _ = _f(m)
	hp = num(row["value"])
	if not hp:
		return None
	h = 5
	while m.fall_damage(h) < hp and h < 60:
		h += 1
	lava = num(m.get("balance.json", "survival", "hazards", "lava", "hp_damage_per_second"), 20) * num(
		m.get("balance.json", "survival", "hazards", "lava", "dig_seconds"), 5)
	return "без прокачки смертельно падение с %d клеток; клетка лавы без костюма — %s HP; +20 HP за ступень «HP»" % (h, fnum(lava))


# --- прокачка ---

def eff_skill_points(m, row):
	fnum, _, _, _ = _f(m)
	parts = ["к %d ур. — %d" % (lv, m.skill_points_at(lv)) for lv in (10, 25, 50, 100)]
	need = m.get("upgrades.json", "skill_points", "total_points_needed_for_full_maxout_approx")
	txt = "очков навыков: " + ", ".join(parts)
	if need:
		txt += " (закрыть все ветки — ≈ %s)" % fnum(need)
	lv = m.bot_mile("level_25")
	if lv:
		txt += "; боты берут 25-й уровень на %s игры" % _f(m)[1](lv["median"])
	return txt


def eff_greed_cost(m, row):
	v = row["value"]
	if not isinstance(v, list):
		return None
	total = sum(v)
	lv = 1
	while m.skill_points_at(lv) < total and lv < 100:
		lv += 1
	return "вся ветка — %d очков ≈ все очки до %d-го уровня" % (total, lv)


def title_story(m, row):
	scene = elem(row, "scenes") or "?"
	scene = (m.data.get("story_ru.json", {}) or {}).get(scene + ".title", scene)
	what = (row.get("parent") or {}).get("do", "")
	return "Сцена «%s»: %s" % (scene, {"xp": "опыт", "dollars": "доллары", "coins": "монеты"}.get(what, what or "награда"))


def eff_story_xp(m, row):
	fnum, _, _, _ = _f(m)
	v = row["value"]
	xp = num(v.get("n")) if isinstance(v, dict) else num(v)
	if xp is None:
		return None
	what = (row.get("parent") or {}).get("do", "xp")
	if what == "dollars":
		return "= %s монет по курсу 1:1000, разово в финале" % fnum(xp * 1000)
	return "уровень 10→11 стоит %s опыта, 20→21 — %s: сцена даёт %s и %s уровня" % (
		fnum(m.xp_for_level(10)), fnum(m.xp_for_level(20)), "%d%%" % round(100 * xp / m.xp_for_level(10)), "%d%%" % round(100 * xp / m.xp_for_level(20)))


# --- задания и награды ---

def _tier_rates(m):
	return [m.daily_rate(t) for t in range(6)]


def eff_quest_reward(m, row):
	"""Весь день: миссии дня (сумма множителей слотов) + монеты сундука против продажи за ~40 минут игры на ступени."""
	fnum, fmin, _, pct = _f(m)
	v = row["value"]
	coins = v.get("coins") if isinstance(v, dict) else None
	rates = _tier_rates(m)
	if not isinstance(coins, list) or not any(rates):
		return None
	daily = m.data.get("quests.json", {}).get("daily", {})
	slots = [s for s in daily.get("slots", []) if isinstance(s, dict)]
	mults = sum(num(s.get("reward"), 1.0) for s in slots) or 5.0
	chest = num((daily.get("bonus_all") or {}).get("coins_x"), 0.0)
	parts = []
	for t, c in enumerate(coins):
		r = rates[t] if t < len(rates) else None
		if r and r.get("coins_per_min"):
			parts.append("ст.%d %s" % (t, pct(c * (mults + chest) / (r["coins_per_min"] * 40.0))))
	head = "день (%d миссий, множители %s" % (len(slots), fnum(mults))
	head += (" + сундук ×%s)" % fnum(chest)) if chest else "; сундук — доллары)"
	return head + " против продажи руды за 40 минут игры на своей ступени: " + ", ".join(parts)


def eff_quest_target(m, row):
	fnum, fmin, _, _ = _f(m)
	tid = elem(row, "templates")
	v = row["value"]
	rates = _tier_rates(m)
	if not isinstance(v, list) or not any(rates):
		return None
	kind = None
	if tid in ("dig_any", "dig_deep"):
		kind = "cells"
	elif tid == "sell_coins":
		kind = "coins"
	elif tid in ("dig_ore", "pick_any"):
		kind = "ore"
	if not kind:
		return None
	parts = []
	for t, n in enumerate(v):
		r = rates[t] if t < len(rates) else None
		if not r:
			continue
		if kind == "cells":
			mins = n / max(r["cells_per_min"], 0.01)
		elif kind == "coins":
			mins = n / max(r["coins_per_min"], 0.01)
		else:
			mins = n / max(r["cells_per_min"] * r["ore_pct"] / 100.0, 0.01)
		parts.append("ст.%d %s" % (t, fmin(mins)))
	txt = "≈ " + ", ".join(parts) + " игры (темп sim_daily)"
	if tid in ("dig_any", "sell_coins", "spend_coins", "eat"):
		txt += "; ступень 2 — ориентир владельца"
	return txt


def eff_reward_minutes(m, row):
	fnum, fmin, _, _ = _f(m)
	v = row["value"]
	coins = num(v.get("coins")) if isinstance(v, dict) else None
	rate = m.bots.get("coins_earned_per_hour")
	first = m.bots.get("income_by_phase", {}).get("0-1")
	if not coins or not rate:
		return None
	txt = "≈ %s продажи руды в первый час игры или %s игры по среднему доходу за 10 ч (боты: %s и %s монет/ч)" % (
		fmin(coins / first * 60) if first else "—", fmin(coins / rate * 60), fnum(first) if first else "—", fnum(rate))
	if isinstance(v, dict) and num(v.get("dollars")):
		txt += "; +%s долл. = %s монет" % (fnum(v["dollars"]), fnum(v["dollars"] * 1000))
	return txt


def sum_rewards(m, rows):
	fnum, _, _, _ = _f(m)
	coins = dollars = 0.0
	for r in rows:
		v = r["value"]
		if isinstance(v, dict):
			coins += num(v.get("coins"), 0)
			dollars += num(v.get("dollars"), 0)
	if not coins and not dollars:
		return None
	return "всего: %s монет и %s долл." % (fnum(coins), fnum(dollars))


def eff_login(m, row):
	fnum, _, _, _ = _f(m)
	v = row["value"]
	if not isinstance(v, dict):
		return None
	return eff_reward_minutes(m, row)


# --- артефакты ---

def _art(m, aid):
	for a in m.data.get("artifacts.json", {}).get("artifacts", []):
		if a.get("id") == aid:
			return a
	return None


def _art_mid(m, aid):
	a = _art(m, aid)
	if not a:
		return None
	lo, hi = num(a.get("depth_min", {}).get("value") if isinstance(a.get("depth_min"), dict) else a.get("depth_min")), num(
		a.get("depth_max", {}).get("value") if isinstance(a.get("depth_max"), dict) else a.get("depth_max"))
	if lo is None or hi is None:
		return None
	return (lo + hi) / 2.0


def eff_art_coins(m, row):
	fnum, _, _, _ = _f(m)
	aid = elem(row, "artifacts")
	c = num(row["value"])
	d = _art_mid(m, aid)
	t = m.trip(d) if d else None
	if not c or not t:
		return None
	return "= %s полной ходки на глубине %s (ходка ≈ %s монет)" % (fnum(c / t, 1), fnum(round(d)), fnum(t))


def flags_art_coins(m, row):
	aid = elem(row, "artifacts")
	c = num(row["value"])
	d = _art_mid(m, aid)
	t = m.trip(d) if d else None
	if not c or not t:
		return []
	if c / t >= 3:
		return ["одна находка стоит %.1f полных ходок — щедрее руды в разы" % (c / t)]
	if c / t <= 0.5:
		return ["находка стоит меньше половины ходки — на этой глубине монеты за неё незаметны"]
	return []


def sum_art_coins(m, rows):
	fnum, fmin, _, _ = _f(m)
	total = sum(num(r["value"], 0) for r in rows)
	txt = "все находки вместе — %s монет" % fnum(total)
	a = m.sims.get("economy", {}).get("farm", {})
	b = m.sims.get("economy", {}).get("farm_noart", {})
	pairs = []
	for key in ("Титановая кирка", "Джетпак", "Платиновая кирка", "Алмазная кирка", "Ручной бур"):
		x, y = m.sim_mile(key, "farm"), m.sim_mile(key, "farm_noart")
		if x and y:
			pairs.append("%s %s вместо %s" % (key.lower(), fmin(x), fmin(y)))
	if pairs:
		txt += "; симулятор (серпантин): с артефактами " + ", ".join(pairs)
	if a.get("artifact_coins") and a.get("sold_per_hour"):
		txt += "; за прогон находки дают %s монет при продаже руды %s/ч" % (fnum(a["artifact_coins"]), fnum(a["sold_per_hour"]))
	return txt


def eff_art_xp(m, row):
	fnum, _, _, _ = _f(m)
	xp = num(row["value"])
	if not xp:
		return None
	lv = 1
	while m.xp_for_level(lv + 1) < xp and lv < 99:
		lv += 1
	return "≈ целый уровень %d→%d (%s опыта)" % (lv, lv + 1, fnum(m.xp_for_level(lv)))


def eff_branch_reward(m, row):
	fnum, _, _, _ = _f(m)
	bid = elem(row, "branches")
	c = num(row["value"])
	b = None
	for x in m.data.get("artifacts.json", {}).get("branches", []):
		if x.get("id") == bid:
			b = x
	if not b or not c:
		return None
	dr = b.get("depth_range") or [0, 0]
	t = m.trip(int(dr[-1]))
	if row["segs"][-1] == "premium_currency":
		return "= %s монет по курсу 1:1000" % fnum(c * 1000)
	return ("= %s ходки на глубине %s" % (fnum(c / t, 1), fnum(dr[-1]))) if t else None


# --- техника ---

def cost_at(depth):
	def f(m, row):
		return m.cost_hours_text(row["value"], depth)
	return f


def eff_cost_unlock(m, row):
	d = _parent_num(row, "unlock_depth") or _parent_num(row, "depth_cap") or 1000
	return m.cost_hours_text(row["value"], int(d))


def eff_hand_drill(m, row):
	parts = [m.cost_hours_text(row["value"], 150)]
	s = m.sim_mile("Ручной бур", "farm")
	if s:
		parts.append("симулятор (серпантин): собран к %s" % _f(m)[1](s))
	b = m.bot_mile_text("craft:hand_drill")
	if b:
		parts.append(b)
	return "; ".join(p for p in parts if p) or None


def eff_drill_rig(m, row):
	parts = [m.cost_hours_text(row["value"], 1000)]
	b = m.bot_mile_text("craft:drill_rig")
	if b:
		parts.append(b)
	d = m.bot_mile("depth_1000")
	if d:
		parts.append("до глубины 1000 боты доходят за %s (у %d из %d)" % (_f(m)[1](d["median"]), d["n"], d["of"]))
	return "; ".join(p for p in parts if p) or None


def eff_well_build(m, row):
	parts = [m.cost_hours_text(row["value"], 150)]
	b = m.bot_mile_text("craft:well")
	if b:
		parts.append(b)
	return "; ".join(p for p in parts if p) or None


def _well_level(row):
	i = elem(row, "levels")
	return int(i) + 1 if i is not None and i.isdigit() else None


def eff_well(m, row):
	fnum, _, fhours, _ = _f(m)
	lv = _well_level(row)
	if not lv or not m.st:
		return None
	try:
		levels = m.get("tech.json", "well", "levels")
		depth = levels[lv - 1]["depth_cap"]
		rate = m.st.well_rate(lv, depth)
		cap = levels[lv - 1]["cap_hours"]
	except Exception:
		return None
	key = row["segs"][-1]
	txt = "ступень %d: ≈ %s монет в час, за полный кап %s ч — %s" % (lv, fnum(rate), fnum(cap), fnum(rate * cap))
	if key == "cost" and lv > 1:
		try:
			prev = m.st.well_rate(lv - 1, levels[lv - 2]["depth_cap"])
			cost = m.st.cost_value(row["value"])
			days = cost / max((rate - prev) * min(cap, 8) * 2, 1.0)
			txt += "; ступень окупается за %s сут (два сбора в сутки)" % fnum(days, 1)
			act = m.income(depth)
			if act:
				txt += "; это %s активной игры на глубине %s" % (fhours(cost / act[2]), fnum(depth))
		except Exception:
			pass
	return txt


def flags_well(m, row):
	lv = _well_level(row)
	if not lv or lv < 2 or row["segs"][-1] != "cost" or not m.st:
		return []
	try:
		levels = m.get("tech.json", "well", "levels")
		rate = m.st.well_rate(lv, levels[lv - 1]["depth_cap"])
		prev = m.st.well_rate(lv - 1, levels[lv - 2]["depth_cap"])
		days = m.st.cost_value(row["value"]) / max((rate - prev) * min(levels[lv - 1]["cap_hours"], 8) * 2, 1.0)
	except Exception:
		return []
	if days < 0.3:
		return ["окупается меньше чем за треть суток — подарок"]
	if days > 12:
		return ["окупается дольше 12 суток — почти никогда"]
	return []


def eff_tank_caps(m, row):
	fnum, _, _, _ = _f(m)
	tool = elem(row, "tanks") or row["segs"][-2]
	rate = num(m.get("balance.json", "fuel_consumption", "blocks_per_cell", tool))
	v = row["value"]
	if not rate or not isinstance(v, list):
		return None
	return "клеток на полном баке: " + " / ".join(fnum(x / rate) for x in v)


def eff_tank_cost(m, row):
	tool = row["segs"][2] if len(row["segs"]) > 2 else ""
	return m.cost_hours_text(row["value"], 600 if tool == "hand_drill" else 1500)


def eff_fuel_rate(m, row):
	fnum, _, _, _ = _f(m)
	x = num(row["value"])
	if not x:
		return None
	peat = num(m.get("balance.json", "fuel_consumption", "peat_per_fuel_block"), 4)
	return "%s клеток на один блок; на 100 клеток — %s блока = %s торфа" % (fnum(1 / x), fnum(100 * x, 1), fnum(100 * x * peat))


def _temp_at(m, depth):
	pts = m.get("tech.json", "heat", "temperature_c")
	if not isinstance(pts, list) or not pts:
		return None
	for (d0, t0), (d1, t1) in zip(pts, pts[1:]):
		if d0 <= depth <= d1:
			return t0 + (t1 - t0) * (depth - d0) / max(d1 - d0, 1)
	return pts[-1][1]


def _heat_mult(m, depth, tol=None):
	t = _temp_at(m, depth)
	amb = m.data.get("tech.json", {}).get("heat", {}).get("ambient", {})
	if t is None or not isinstance(amb, dict):
		return None
	tol = tol if tol is not None else num(_unw(amb.get("base_tolerance_c")), 40)
	extra = num(_unw(amb.get("stamina_extra_per_50c")), 1.0)
	cap = num(_unw(amb.get("max_multiplier")), 6.0)
	return min(cap, 1 + max(0.0, t - tol) / 50.0 * extra)


def _unw(v):
	return v["value"] if isinstance(v, dict) and "value" in v else v


def eff_heat(m, row):
	fnum, _, _, _ = _f(m)
	parts = []
	for d in (1000, 2000, 3000, 5000):
		t, k = _temp_at(m, d), _heat_mult(m, d)
		if t is not None and k is not None:
			parts.append("%d — %s °C, бодрость ×%s" % (d, fnum(t), fnum(k, 1)))
	return ("без костюма: " + "; ".join(parts)) if parts else None


def eff_suit(m, row):
	fnum, _, _, _ = _f(m)
	key = row["segs"][-1]
	v = num(row["value"])
	if key == "lava_resist" and v is not None:
		raw = num(m.get("balance.json", "survival", "hazards", "lava", "hp_damage_per_second"), 20) * num(
			m.get("balance.json", "survival", "hazards", "lava", "dig_seconds"), 5)
		return "клетка лавы стоит %s HP (без костюма %s)" % (fnum(raw * (1 - v)), fnum(raw))
	if key == "tolerance_c" and v is not None:
		k = _heat_mult(m, 3000, v)
		return "до %s °C без штрафа; на 3000 — бодрость ×%s" % (fnum(v), fnum(k, 1)) if k else None
	if key == "cost":
		d = int(_parent_num(row, "unlock_depth") or 1000)
		return m.cost_hours_text(row["value"], d, d + (200 if d >= 3000 else 0))
	return None


def flags_suit(m, row):
	if row["segs"][-1] != "cost":
		return []
	d = int(_parent_num(row, "unlock_depth") or 1000)
	r = m.cost_hours(row["value"], d, d + (200 if d >= 3000 else 0))
	if r and not math.isinf(r[0]) and r[0] > 8:
		return ["%.1f ч активной игры — дольше границы 8 ч, которую держит tools/sim_tech.py" % r[0]]
	return []


def sum_suits(m, rows):
	_, _, fhours, _ = _f(m)
	parts = []
	for r in rows:
		if r["segs"][-1] != "cost":
			continue
		d = int(_parent_num(r, "unlock_depth") or 1000)
		h = m.cost_hours(r["value"], d, d + (200 if d >= 3000 else 0))
		if h:
			parts.append("%s с %d — %s" % (r["title"].split(":")[0], d, fhours(h[0])))
	return ("цена ступени в часах активной игры на её глубине: " + "; ".join(parts)) if parts else None


def sum_well(m, rows):
	fnum, _, _, _ = _f(m)
	if not m.st:
		return None
	try:
		levels = m.get("tech.json", "well", "levels")
		parts = []
		for lv in range(2, len(levels) + 1):
			rate = m.st.well_rate(lv, levels[lv - 1]["depth_cap"])
			prev = m.st.well_rate(lv - 1, levels[lv - 2]["depth_cap"])
			days = m.st.cost_value(levels[lv - 1]["cost"]) / max((rate - prev) * min(levels[lv - 1]["cap_hours"], 8) * 2, 1.0)
			parts.append("%d: %s" % (lv, fnum(days, 1)))
		top = m.st.well_rate(len(levels), levels[-1]["depth_cap"])
	except Exception:
		return None
	return "окупаемость ступеней, суток (два сбора в сутки) — %s; верхняя ступень даёт ≈ %s монет в час" % (", ".join(parts), fnum(top))

# --- бой ---

def _weapon(m):
	p = m.data.get("combat.json", {}).get("player", {})
	w = p.get("base_weapon", {}) if isinstance(p, dict) else {}
	return num(w.get("dmg"), 14), num(w.get("cd"), 0.7)


def eff_monster_hp(m, row):
	fnum, _, _, _ = _f(m)
	hp = num(row["value"])
	dmg, cd = _weapon(m)
	if not hp:
		return None
	n = math.ceil(hp / dmg)
	return "киркой (%s урона раз в %s с): %d ударов ≈ %s с" % (fnum(dmg), fnum(cd), n, fnum(n * cd, 1))


def eff_monster_dmg(m, row):
	fnum, _, _, _ = _f(m)
	d = num(row["value"])
	if not d:
		return None
	return "герой со 100 HP падает с %d ударов, с 300 HP (10 ступеней «HP») — с %d (без брони)" % (math.ceil(100 / d), math.ceil(300 / d))


def eff_gear_recipe(m, row):
	inc = m.income(4500)
	v = row["value"]
	if not inc or not isinstance(v, dict):
		return None
	return "монетная часть = %s активной игры на 4500 (детали — только с монстров)" % _f(m)[2](num(v.get("coins"), 0) / inc[2])


# --- механики ---

def eff_chest_chance(m, row):
	fnum, _, _, _ = _f(m)
	ch = num(row["value"])
	rows_n = num(m.get("mechanics.json", "chests", "band_rows"), 12)
	if not ch:
		return None
	txt = "≈ тайник на %s рядов глубины" % fnum(rows_n / ch)
	b = m.bots.get("per_hour", {}).get("chest_opened")
	if b:
		txt += "; боты открывают %s в час" % fnum(b, 1)
	return txt


def eff_fever_at(m, row):
	fnum, fmin, _, _ = _f(m)
	n = num(row["value"])
	r = m.daily_rate(2)
	if not n:
		return None
	txt = ""
	if row["segs"][-1] == "fever_s":
		# с 26.10 шкала копится секундами работы, а не клетками (ветка greed-bug)
		txt = "%d с работы ≈ %s непрерывной копки на любом инструменте (человек с паузами — ~1.2 мин)" % (n, fmin(n / 60.0))
	elif r:
		txt = "%d клеток подряд ≈ %s непрерывной копки на глубине 80–250" % (n, fmin(n * r["sec_per_cell"] / 60.0))
	b = m.bots.get("per_hour", {}).get("fever_started")
	if b:
		txt += ("; " if txt else "") + "боты входят в жадность %s раза в час" % fnum(b, 1)
	return txt or None


def eff_mastery(m, row):
	fnum, _, fhours, _ = _f(m)
	v = row["value"]
	if not isinstance(v, list) or not m.st:
		return None
	key = row["segs"][-1]
	ore, depth = {"cheap": ("iron_ore", 100), "mid": ("gold", 500), "precious": ("diamond", 900)}.get(key, (None, None))
	if not ore:
		return None
	h = m.mat_hours(ore, v[-1], depth)
	return ("пять звёзд %s — %s шт. ≈ %s копки на глубине %d" % (m.name(ore), fnum(v[-1]), fhours(h), depth)) if h else None


# --- монетизация ---

def _coins_per_dollar(m):
	return num(m.get("balance.json", "economy", "coins_per_premium_currency_unit"), 1000)


def eff_pack(m, row):
	fnum, _, _, _ = _f(m)
	key = row["segs"][-1]
	p = row.get("parent") or {}
	usd = num(_unw(p.get("price_usd")))
	dol = num(_unw(p.get("grants_dollars")))
	if not usd or not dol:
		return None
	ads = num(_unw(m.get("balance.json", "ads", "daily_limits", "small_premium_currency")), 5)
	per_ad = 1
	for a in (m.get("shop.json", "ad_rewards") or []):
		if isinstance(a, dict) and a.get("id") == "small_premium_currency":
			per_ad = num(a.get("dollars"), 1) or 1
	return "%s долл. за $%s = %s монет; %s долл. за $1; столько же дают ролики «доллар» за %s сут" % (
		fnum(dol), fnum(usd), fnum(dol * _coins_per_dollar(m)), fnum(dol / usd), fnum(dol / max(ads * per_ad, 1), 1))


_UNLOAD_LESSON_KEY = {"depth": "с какой глубины ждёт спокойного момента", "free_use": "первая выгрузка в сцене бесплатно",
	"calm_wait_seconds": "ждать, пока герой не копает, не дольше, с"}


def title_unload_lesson(m, row):
	return "Сцена «выгрузка на склад»: " + _UNLOAD_LESSON_KEY.get(row["segs"][-1], row["key_ru"])


def eff_premium_price(m, row):
	fnum, _, _, _ = _f(m)
	p = num(row["value"])
	if p is None:
		return None
	per_ad = 1
	for a in (m.get("shop.json", "ad_rewards") or []):
		if isinstance(a, dict) and a.get("id") == "small_premium_currency":
			per_ad = num(a.get("dollars"), 1) or 1
	ads = num(_unw(m.get("balance.json", "ads", "daily_limits", "small_premium_currency")), 5)
	return "= %s монет по курсу; = %s ролик(а) «доллар» по %s (их %s в сутки)" % (
		fnum(p * _coins_per_dollar(m)), fnum(math.ceil(p / per_ad)), fnum(per_ad), fnum(ads))


def eff_sub_currency(m, row):
	fnum, _, _, _ = _f(m)
	v = num(row["value"])
	if v is None:
		return None
	if row["segs"][-1].endswith("daily"):
		return "%s долл. в месяц (пачка M за $4.99 даёт 550)" % fnum(v * 30)
	return "разово %s долл. = %s монет" % (fnum(v), fnum(v * _coins_per_dollar(m)))


# ---------------------------------------------------------------------------
# Семейства. Порядок внутри темы — от самого важного (imp 5) к мелочам (imp 1).
# rec: (вердикт, почему). Вердикты: оставить / поднять / опустить / решить / снять пометку / убрать / отложить.
# ---------------------------------------------------------------------------

_TIER_RU = {"low": "на 25%", "critical": "на 10%", "empty": "на нуле"}
_TIER_KEY_RU = {"dig": "скорость копки", "luck": "шанс удачи", "move": "скорость ходьбы", "jump": "высота прыжка",
	"stagger_amplitude": "шатание: размах", "stagger_period_seconds": "шатание: период, с"}


def title_surv_tier(m, row):
	segs = row["segs"]
	who = "Голод" if segs[0] == "hunger_tiers" else "Бодрость"
	tier = _TIER_RU.get(segs[1], segs[1]) if len(segs) > 1 else ""
	return "%s %s: %s ×" % (who, tier, _TIER_KEY_RU.get(segs[-1], segs[-1]))


def title_surv_cost(m, row):
	segs = row["segs"]
	who = "«Голод»" if "[hunger]" in segs else "«Выносливость»"
	if segs[-1] == "percent_per_stage":
		return "%s: прибавка за ступень, %%" % who
	last = segs[-1]
	return "%s: ступень %d" % (who, int(last[1:-1]) + 1) if last.startswith("[") and last[1:-1].isdigit() else "%s: %s" % (who, row["key_ru"])


_SHAPE_RU = {"circle": "круг", "rhombus": "ромб", "star": "звезда", "heart": "сердце"}


def title_cave(m, row):
	segs = row["segs"]
	if segs[0] == "shapes" and len(segs) >= 3:
		return "Полость «%s»: %s" % (_SHAPE_RU.get(segs[1], segs[1]), "доля среди фигур" if segs[-1] == "weight" else "прибавка к радиусу, клеток")
	if segs[0] == "radius" and len(segs) >= 3:
		i = segs[1][1:-1]
		return "Полости, ступень %s: %s" % (int(i) + 1 if i.isdigit() else i, "радиус от/до, клеток" if segs[-1] == "r" else "с глубины")
	return {"chance_top": "Шанс полости в слоте на 1500", "chance_bottom": "Шанс полости в слоте у 4000",
		"slot_h": "Высота слота, рядов", "tries": "Попыток поставить полость в слоте", "y_max": "Последняя глубина с полостями",
		"y_min": "Первая глубина с полостями"}.get(segs[0], "Полости: " + row["key_ru"])


def title_cave_guard(m, row):
	segs = row["segs"]
	t = {"aggro_extra": "замечают героя: радиус полости +, клеток", "count": "сколько стражей по глубине",
		"forget_dist": "полость «забывается» дальше, клеток", "leash_extra": "не уходят от полости дальше радиуса +, клеток",
		"max_shooters": "не больше стрелков в полости", "spawn_dist": "появляются, когда герой ближе, клеток",
		"touch_radius": "сундук открывается касанием с, клеток"}.get(segs[-1], row["key_ru"])
	return ("Сундук: " if segs[0] == "chest" else "Стражи: ") + t


_CAVE_MON_KEY = {"depth": "глубины, где живёт", "stagger_chance": "шанс сбить с атаки ударом", "knock_resist": "сопротивление отбросу"}


def title_cave_monster(m, row):
	segs = row["segs"]
	name = m.name(segs[1]) if len(segs) > 1 else "?"
	if "projectile" in segs:
		return "%s: снаряд — %s" % (name, {"gravity": "тяжесть", "radius": "размер", "speed": "скорость", "ttl": "время полёта, с"}.get(segs[-1], segs[-1]))
	return "%s: %s" % (name, _CAVE_MON_KEY.get(segs[-1], row["key_ru"]))


def F(id, theme, imp, title, match, row=None, unit="", affects="", effect=None, summary=None, rec=None, flags=None, vtext=None):
	return {"id": id, "theme": theme, "imp": imp, "title": title, "match": match if isinstance(match, list) else [match],
		"row": row, "unit": unit, "affects": affects, "effect": effect, "summary": summary, "rec": rec, "flags": flags,
		"vtext": vtext}


def v_density(m, row):
	fnum, _, _, _ = _f(m)
	v = row["value"]
	if not isinstance(v, dict):
		return None
	if v.get("type") == "parabola":
		return "с %s, пик %s%% на %s, хвост %s%%" % (fnum(v.get("depth_min")), fnum(v.get("peak_percent")), fnum(v.get("peak_depth")),
			fnum(v.get("tail_percent")))
	if v.get("type") == "flat":
		return "%s–%s%% ровно" % (fnum(v.get("percent_min")), fnum(v.get("percent_max")))
	return None


def title_quest(m, row):
	tid = elem(row, "templates")
	t = next((x for x in m.data.get("quests.json", {}).get("templates", []) if x.get("id") == tid), {})
	name = t.get("name_ru", tid or "?")
	item = (t.get("filter") or {}).get("item")
	name = name.replace("{item}", m.name(item) if isinstance(item, str) else "руда").replace("{n}", "N").replace("{depth_min}", "N")
	return "«%s»: %s" % (name, human_key_short(row))


# --- стрик новичка (data/newbie_streak.json) ---

def title_newbie_day(m, row):
	return "Стрик новичка, день %s" % row["segs"][-1].strip("[]")


def v_newbie_day(m, row):
	fnum, _, _, _ = _f(m)
	v = row["value"]
	if not isinstance(v, dict):
		return None
	ms = []
	for x in v.get("missions") or []:
		if isinstance(x, dict):
			ms.append(str(x.get("name_ru") or x.get("id") or "?").replace("{n}", fnum(x.get("target", 1))))
	r = v.get("reward") or {}
	rw = []
	if num(r.get("coins")):
		rw.append("%s монет" % fnum(r["coins"]))
	if num(r.get("xp")):
		rw.append("%s опыта" % fnum(r["xp"]))
	it = r.get("item")
	if isinstance(it, dict) and it.get("id"):
		rw.append("%s ×%s" % (m.name(it["id"]), fnum(it.get("count", 1))))
	return "%s → %s" % ("; ".join(ms) or "—", ", ".join(rw) or "без награды")


def eff_newbie_day(m, row):
	v = row["value"]
	if not isinstance(v, dict) or not isinstance(v.get("reward"), dict):
		return None
	return eff_reward_minutes(m, {"value": v["reward"]})


def sum_newbie(m, rows):
	fnum, _, _, _ = _f(m)
	coins = xp = 0.0
	for r in rows:
		v = r["value"]
		if isinstance(v, dict) and isinstance(v.get("reward"), dict):
			coins += num(v["reward"].get("coins"), 0)
			xp += num(v["reward"].get("xp"), 0)
	if not coins:
		return None
	return "за все 30 дней: %s монет и %s опыта (крупный подарок — отдельно, пока заглушка)" % (fnum(coins), fnum(xp))


def human_key_short(row):
	return {"targets": "цели по ступеням 0–5", "weekly_scale": "множитель недели", "depth_min": "глубина по ступеням"}.get(
		row["segs"][-1], row["segs"][-1])


FAMILIES = [
	# ---------------- Экономика и цены ----------------
	F("eco.free_food", "economy", 4, "Бесплатные заказы еды в сутки", "balance.json:food.free_orders_per_day",
		"Бесплатных заказов еды в сутки (реальные сутки)", "заказов", "сколько еды новичок и бедняк получают даром",
		eff_free_orders, rec=("оставить", "подушка новичку и после смерти: боты в начале после смерти оставались с 37 монетами и не могли поесть. "
			"Заметку стоит переписать — «монет в игре взять негде» давно неправда")),
	F("eco.energy_drink", "economy", 3, "Цена энергетика", "balance.json:food.items[energy_drink].price_coins",
		"Энергетик: цена", "монет", "можно ли не подниматься домой ради сна", lambda m, r: eff_trip_share(m, r),
		rec=("оставить", "≈ десятая часть ходки на сотне — заметно, но не запретно; заметка «дороже полного обеда» устарела: стейк стоит 200"),
		flags=lambda m, r: ["заметка устарела: «дороже полного обеда», а стейк стоит 200"] if num(r["value"], 0) < 200 else []),
	F("eco.not_bought", "economy", 3, "Что мастерская не скупает", "shop.json:sell.not_bought",
		"Не скупается обратно", "список", "плавка лома и перегонка торфа не должны печатать монеты", None,
		rec=("оставить", "иначе лом за 5 → бронза за 30 печатает монеты из воздуха")),
	F("eco.exchange", "economy", 2, "Обмен валют в одну сторону", "shop.json:exchange.dollars_to_coins_only",
		"Доллары → монеты, обратно нельзя", "правило", "ценность долларов", None,
		rec=("снять пометку", "это уже записано в ГДД §15 как правило («обмен односторонний»)")),
	F("eco.bronze_peat", "economy", 2, "Цены бронзы и торфа", ["minerals.json:minerals[bronze].price_coins", "minerals.json:minerals[peat].price_coins"],
		"{name}: цена продажи", "монет за штуку", "подсказки цены; бронзу мастерская не скупает",
		None, rec=("оставить", "бронзу не купят (см. «не скупает»), торф — топливо, а не товар: цены почти ни на что не влияют")),
	F("eco.bronze_weight", "economy", 1, "Вес бронзы", "minerals.json:minerals[bronze].weight_kg",
		"Бронза: вес", "кг", "бронза лежит на складе, в рюкзак её не берут", eff_weight, rec=("оставить", "мелочь")),

	# ---------------- Добыча и руды ----------------
	F("min.density", "mining", 5, "Где и сколько руды (плотность по глубине)", "minerals.json:minerals[*].density",
		"{name}: где лежит и сколько", "доля породы, %", "доход с каждой глубины, рецепты бура, скважины и костюма, задания «добудь»",
		eff_density, rec=("оставить", "кривые сверены с генератором (ГДД §4.1, tools/check_ores.py). Если глубины 500–1000 должны манить "
			"сильнее (боты «скучают» на 780–880), поднимать стоит золото и алмаз глубже 600, а не всё сразу"), flags=flags_density, vtext=v_density),
	F("min.drill_seconds", "mining", 4, "Время копки руды", "minerals.json:minerals[*].drill_seconds",
		"{name}: секунд на клетку", "с (до множителей кирки и ×1.3)", "темп копки: клеток и монет в час",
		eff_drill, summary=sum_drill, rec=("оставить", "секунды по твёрдости; общий темп владелец уже задал одним ×1.3. Титан (12 с за 80 монет) "
			"копается как алмаз и стоит в шесть раз меньше — это нарочно: он идёт в костюм и баки")),
	F("min.weight", "mining", 4, "Вес руды", ["minerals.json:minerals[%s].weight_kg" % k for k in (
		"nickel", "platinum", "titanium", "lithium", "geocrystal", "ancient_metal", "obsidian", "hellstone", "dark_matter",
		"universum", "angelstone", "divine_heart")], "{name}: вес", "кг", "сколько выносишь за ходку",
		eff_weight, summary=sum_weight, rec=("оставить", "лёгкий литий (0.3 кг за 80 монет) — приятный «рюкзачный» приз пояса 1000+, ничего не ломает")),
	F("min.scrap", "mining", 4, "Металлолом — единственный источник бронзы",
		["minerals.json:minerals[scrap].depth_max", "minerals.json:minerals[scrap].density", "minerals.json:minerals[scrap].drill_seconds"],
		"Металлолом: {key}", "", "сборка ручного бура (100 бронзы) и скважины (20)", lambda m, r: eff_scrap_depth(m, r) if r["segs"][-1] == "depth_max" else (eff_drill(m, r) if r["segs"][-1] == "drill_seconds" else None),
		rec=("оставить", "без лома до 500 бур на части миров не собирался (ГДД §18)"), vtext=lambda m, r: v_density(m, r) if r["segs"][-1] == "density" else None),
	F("min.earth", "mining", 3, "Время копки земли", "minerals.json:minerals[earth].drill_seconds",
		"Земля: секунд на клетку", "с", "темп первых минут и всей «пустой» породы", eff_drill, rec=("оставить", "база, от которой выведены остальные секунды")),
	F("min.formations", "mining", 3, "Особые образования: каверны, провалы, гроты, руины, жилы", "world_layers.json:formations.**",
		"Образования: {key}", "", "разнообразие шахты и клады глубже 700", None,
		rec=("оставить", "картинка и клад; на доход влияют слабо, проверены тестами мира")),
	F("min.tools", "mining", 1, "Чем копается лом и торф", "minerals.json:minerals[*].tool_required",
		"{name}: инструмент", "инструмент", "можно ли взять лопатой", None, rec=("оставить", "мелочь")),
	F("surv.sleep_heal", "survival", 5, "Лечение сном", "healing.json:sleep.*",
		"Сон: {key}", "", "сколько HP возвращает ночь дома", lambda m, r: eff_sleep_heal(m, r) if r["segs"][-1] == "hp_percent_full_night" else None,
		rec=("оставить", "ровно слова владельца: «при полном сне и еде — 90–100%»; сон без еды — 75%")),
	F("surv.food_heal", "survival", 4, "Лечение едой", "healing.json:food.*",
		"Еда: HP за 1% сытости", "доля", "сколько HP даёт каждое блюдо", eff_food_heal, rec=("оставить", "стейк +25%, пельмени +19%: еда — половина лечения")),
	F("surv.medkit", "survival", 5, "Аптечка: сила, цена, вес",
		["healing.json:medkit.hp_percent", "shop.json:goods_coins.extra[medkit].price_coins", "minerals.json:minerals[medkit].weight_kg"],
		"Аптечка: {key}", "", "лечиться дешевле, чем умереть",
		lambda m, r: eff_medkit_hp(m, r) if r["segs"][-1] == "hp_percent" else (eff_medkit_price(m, r) if r["segs"][-1] == "price_coins" else eff_weight(m, r)),
		summary=sum_medkit,
		rec=("решить", "смерть — «5%, но не меньше 50» (п.4 владельца) и весь рюкзак, после неё HP полное (владелец, 26.10: «только хп полное»): "
			"с пустым рюкзаком и монетами до 3000 смерть (50–150) лечит до 100% не дороже одной аптечки на 50% — оставить или поднять плату"),
		flags=lambda m, r: flags_medkit_price(m, r) if r["segs"][-1] == "price_coins" else []),
	F("surv.sleep_rules", "survival", 3, "Правила сна", ["balance.json:house.sleep_min_deficit_percent", "balance.json:house.sleep_hunger_factor",
		"balance.json:house.sleep_animation_seconds"], "Сон: {key}", "", "когда пускает кровать и сколько ест сон", None,
		rec=("оставить", "сон стоит половину полоски голода — еда и сон держатся друг за друга. «10 секунд анимации» — слова владельца: пометку снять"),
		flags=lambda m, r: ["это слова владельца («спит быстро, буквально 10 секунд») — пометку proposed можно снять"] if r["segs"][-1] == "sleep_animation_seconds" else []),
	F("surv.mercury", "survival", 2, "Отравление ртутью", "balance.json:survival.hazards.mercury_poisoning.*",
		"Ртуть: {key}", "", "цена ртути без банки", None,
		rec=("оставить", "0.5 HP/с — «медленно», как в ГДД §13; штраф навыкам 20% кодом не читается — убрать или сделать"),
		flags=lambda m, r: ["кодом не читается"] if r["segs"][-1] == "skill_penalty_percent" else []),
	F("surv.food_weight", "survival", 2, "Вес еды в рюкзаке", ["minerals.json:minerals[%s].weight_kg" % k for k in ("food_soup", "food_dumplings", "energy_drink", "energy_bar")],
		"{name}: вес", "кг", "сколько руды вытесняет запас еды", eff_weight,
		rec=("оставить", "мелочь; вес пельменей ни на что не влияет — их нельзя унести, суп в меню доставки не продаётся"),
		flags=lambda m, r: ["блюдо нельзя унести с собой (portable: false) — вес не используется"] if elem(r, "minerals") == "food_dumplings"
			else (["супа нет в меню доставки — вес не используется"] if elem(r, "minerals") == "food_soup" else [])),
	F("surv.death_respawn", "survival", 4, "После смерти: здоровье и полоски", "healing.json:death.respawn.*",
		"После смерти: {key}", "%", "смерть лечит, но не кормит и не укладывает спать", None,
		rec=("оставить", "решено владельцем 26.10: HP полное, сытость и бодрость как были, но не ниже 25%")),
	F("surv.drain", "survival", 5, "Голод и усталость: как быстро тают", ["survival.json:drain_multiplier.*", "survival.json:soft_start.*"],
		"Таяние: {key}", "×", "как часто есть и спать",
		None, rec=("оставить", "п.1 владельца «голод и усталость влияли больше»: голод ×1.5 (полоска — 13 минут копки), бодрость ×1.3 (~15 минут); "
			"включается после урока сна или с 5-го уровня, чтобы не душить новичка")),
	F("surv.tiers", "survival", 4, "Штрафы голода и усталости по ступеням", ["survival.json:hunger_tiers.**", "survival.json:stamina_tiers.**"],
		title_surv_tier, "×", "насколько больно тянуть с едой и сном", None,
		rec=("оставить", "25% — заметно (копка −15%), 10% — тяжело (−30%), ноль — голод бьёт по HP, усталость шатает; тупика нет: "
			"на ступеньку в одну клетку сил хватает всегда")),
	F("prog.skill_points", "progression", 5, "Очки навыков за уровень", "upgrades.json:skill_points.per_level_tiers",
		"Очки за уровень по ступеням", "очков за уровень", "скорость прокачки всех веток (голод, бодрость, скорость копки…)",
		eff_skill_points, rec=("оставить", "решение владельца «уровни дают постепенно больше» выполнено: 1 → 2 → 3. Если голод и бодрость "
			"давят сильнее (п.1 владельца) — их ветки подешевели до 30 очков каждая; хватает ли очков к 2–3 часу, покажет ночной прогон ботов"),
		vtext=lambda m, r: ", ".join("%s до %s-го ур." % (t.get("points"), t.get("up_to_level")) for t in r["value"]) + " (каждый 5-й — ещё +%s)" % (
			m.get("upgrades.json", "skill_points", "bonus_every_5th_level", default=0))),
	F("prog.base_hp", "progression", 4, "Здоровье героя без прокачки", "upgrades.json:branches[hp].effect.base",
		"HP на старте", "HP", "цена падений, лавы, боя", eff_fall_hp, rec=("оставить", "100 HP = падение с 20 клеток (шкала ГДД §6)")),
	F("prog.greed_cost", "progression", 3, "Цена ветки «Жадность»", "upgrades.json:branches[greed].cost_note",
		"Жадность: очков за ступень", "очков", "как быстро вкачивается лихорадка", eff_greed_cost,
		rec=("оставить", "столько же, сколько «Удача — шанс»; проценты и секунды — владельца")),
	F("prog.survival_cost", "progression", 4, "Цена веток «Голод» и «Выносливость»",
		["upgrades.json:branches[hunger].cost_points[*]", "upgrades.json:branches[stamina].cost_points[*]",
		"upgrades.json:branches[stamina].effect.percent_per_stage"],
		title_surv_cost, "очков", "как быстро игрок отбивается от голода и усталости", None,
		rec=("оставить", "п.1 владельца «чуть меньше условия для прокачки»: обе ветки 1,1,2,2,3,3,4,4,5,5 — 30 очков вместо 55 и 65; "
			"бодрость +20% за ступень")),
	F("prog.story_xp", "progression", 2, "Награды сюжетных сцен", "story_arc.json:scenes[*].effects[*].n",
		title_story, "опыта / долларов", "мелкая прибавка к уровню", eff_story_xp,
		rec=("оставить", "доли уровня; сюжет не должен быть фермой опыта; 5 долларов в финале — разово")),

	# ---------------- Задания и награды ----------------
	F("q.daily_reward", "quests", 5, "Награда за задание дня", ["quests.json:daily.reward", "quests.json:daily.slots[*].reward", "quests.json:daily.points"],
		"Задания дня: {key}", "монеты и опыт по ступеням / множитель слота", "зачем выполнять задания",
		lambda m, r: eff_quest_reward(m, r) if r["segs"][-1] == "reward" and isinstance(r["value"], dict) else None,
		rec=("оставить", "день миссий ≈ 80% того, что игрок заработал бы продажей за те же 40 минут (владелец, 26.10); 13 миссий делят прежние 6.5 награды ступени (5 заданий + монеты сундука), сундук звёзд — доллары")),
	F("q.targets", "quests", 4, "Цели заданий по ступеням", ["quests.json:templates[*].targets", "quests.json:templates[*].weekly_scale",
		"quests.json:templates[*].filter_by_tier.**"], title_quest, "штук (ступени 0–5)", "сколько минут занимает задание",
		eff_quest_target, rec=("оставить", "копка ≈ 25 минут игры на любой ступени; ступень 2 — ровно слова владельца (500 клеток, 1000 монет, 500 трат, 3 еды)")),
	F("q.tiers", "quests", 3, "Ступени заданий по глубине", "quests.json:tier_by_max_depth",
		"Рекорд глубины для ступени", "клетки", "когда задания становятся крупнее", None, rec=("оставить", "границы совпадают с поясами копки")),
	F("q.chest_streak", "quests", 3, "Сундук дня, серия, замена", ["quests.json:daily.bonus_all", "quests.json:daily.streak.*", "quests.json:daily.count",
		"quests.json:daily.reroll.*", "quests.json:daily.slots[*].pool", "quests.json:daily.slots[*].scale"],
		"Задания дня: {key}", "", "привычка заходить каждый день", None,
		rec=("оставить", "13 миссий, звезда за каждую, сундук на 10-й звезде — 5 долларов (всё слова владельца 27.10); "
			"энергетик и 2 очка в сундуке, прибавка серии до +50% монетами и доллар каждый 7-й день — предложение")),
	F("q.weekly", "quests", 3, "Недельные задания", "quests.json:weekly.**", "Неделя: {key}", "", "цель на неделю, 1 доллар", None,
		rec=("оставить", "недельная цель = 4 дня работы; второй слот даёт 1 доллар; третий — «посмотри рекламу 25 раз» (владелец)")),
	F("q.login", "quests", 3, "Подарок за вход (7 дней)", "daily_rewards.json:**", "Подарок дня: {key}", "", "привычка заходить",
		eff_login, summary=sum_rewards, rec=("оставить", "день 7 — 2000 монет и доллар; потолок 4 доллара в неделю держит предложенные повторяемые источники "
			"(подарок дня, недельное задание, доллар серии); 5 долларов сундука звёзд и ролики — числа владельца, в потолок не входят")),
	F("q.achievements", "quests", 3, "Награды достижений", "achievements.json:achievements[*].reward",
		"«{name}»: награда", "монеты, опыт, доллары", "разовые подарки за вехи", eff_reward_minutes, summary=sum_rewards,
		rec=("оставить", "разовые; крупные — за глубину 1000/4000/10 000")),
	F("q.ach_targets", "quests", 2, "Цели достижений", "achievements.json:achievements[*].target",
		"«{name}»: цель", "штук", "когда приходит достижение", None,
		rec=("оставить", "ступени «Удачника» 100/200/500/2000/5000 — из заказа владельца"),
		flags=lambda m, r: ["похоже на число владельца (ГДД §11 «Удачник») — сверить"] if (elem(r, "achievements") or "").startswith("lucky_") else []),
	F("q.road", "quests", 2, "Дорога трофеев", ["achievements.json:road**", "achievements.json:points_by_tier"],
		"Дорога трофеев: {key}", "очки / награда", "длинная цель из очков достижений и заданий", eff_reward_minutes, summary=sum_rewards,
		rec=("оставить", "14 ступеней, 7 долларов за всю дорогу")),

	F("q.newbie", "quests", 4, "Стрик новичка: миссии и награды 30 дней", "newbie_streak.json:days[*]",
		title_newbie_day, "миссии → награда дня", "что новичок делает каждый из 30 дней и сколько получает",
		eff_newbie_day, summary=sum_newbie, vtext=v_newbie_day,
		rec=("решить", "30 дней и 50 $ за пропуск — ваши числа; миссии — сценарий агента: продай, поешь, поспи, глубина 50 → "
			"глубина 300·500·800, ручной бур на 24-й день, скважина на 29-й; награда дня 100→2000 монет («суть не в бонусе "
			"за день»). Подходит ли темп и что станет крупным подарком за все 30 дней")),

	# ---------------- Артефакты ----------------
	F("art.find_coins", "artifacts", 5, "Монеты за находку артефакта", "artifacts.json:artifacts[*].find_bonus.coins",
		"«{name}»: монеты за находку", "монет", "темп покупок первых часов — находки платят больше руды",
		eff_art_coins, summary=sum_art_coins,
		rec=("опустить", "формула «1.5 × опыта» растёт медленнее дохода: на глубинах 50–100 одна находка = 3–5 полных ходок, а глубже 1000 — "
			"меньше половины ходки. Совет: платить ≈ одну ходку на глубине находки (мелкие — дешевле, глубокие — дороже)"),
		flags=flags_art_coins),
	F("art.find_xp", "artifacts", 4, "Опыт за находку", "artifacts.json:artifacts[*].find_bonus.xp",
		"«{name}»: опыт", "опыта", "уровни (очки навыков)", eff_art_xp, rec=("оставить", "диапазон 500–5000 задан ГДД §11, распределён по ветке ровно")),
	F("art.depths", "artifacts", 3, "Глубины артефактов", ["artifacts.json:artifacts[*].depth_min", "artifacts.json:artifacts[*].depth_max"],
		"«{name}»: {key}", "клетки", "где лежит находка", None, rec=("оставить", "ветка делится на 5 равных отрезков; первая находка — на первой минуте")),
	F("art.branch_reward", "artifacts", 3, "Награда за закрытую ветку", "artifacts.json:branches[*].completion_reward.*",
		"Ветка «{name}»: {key}", "монеты / доллары", "цель коллекции", eff_branch_reward,
		rec=("оставить", "растёт с веткой 500 → 30 000; доллары 2–40 — щедро для премиум-валюты, но одноразово")),
	F("art.spawn", "artifacts", 3, "Как часто попадаются артефакты", "artifacts.json:spawn.**",
		"Появление: {key}", "", "сколько находок за час", None,
		rec=("оставить", "боты находят 10–17 артефактов за 10–12 игровых часов")),

	# ---------------- Техника и топливо ----------------
	F("tech.hand_drill", "tech", 5, "Цена ручного бура", "balance.json:tools.hand_drill.cost",
		"Ручной бур: цена сборки", "монеты и материалы", "главные ворота середины игры: копка ×2 от лучшей кирки",
		eff_hand_drill, rec=("решить", "бур собрал один бот из десяти (на 5.6 ч), остальные за 10–12 ч — нет: лом уходит в продажу, бронзы не хватает. "
			"ГДД §18 называет рецепт «утверждённым владельцем», а в данных он proposed — подтвердить. Если бур должен приходить к 3–4 часу — "
			"опустить бронзу 100 → 50 и железо 500 → 300")),
	F("tech.drill_rig", "tech", 5, "Цена бурмобиля и глубина открытия", ["balance.json:tools.drill_rig.cost", "shop.json:craft.unlock_depth.drill_rig"],
		"Бурмобиль: {key}", "", "вторые ворота: ×2 к буру, полёт внутри, деньги ×10", eff_drill_rig,
		rec=("оставить", "на тысяче цена — минут двадцать игры: держит не цена, а сама глубина 1000 и платина с неё (боты: никель 11/50, "
			"платина 0/20, до 1000 — 5–8 ч). Бурмобиль — цель второго дня; если нужен раньше, двигать открытие, а не цену")),
	F("tech.well", "tech", 4, "Скважина: постройка, ступени, доход",
		["balance.json:idle_well.**", "tech.json:well.levels**", "shop.json:craft.unlock_depth.well"],
		"Скважина: {key}", "", "доход без игры (офлайн)", lambda m, r: eff_well_build(m, r) if r["id"].endswith("build_cost") else eff_well(m, r),
		summary=sum_well, rec=("оставить", "ступени окупаются за 0.6–12 суток, заход за кап не дороже 5 ч активной игры (границы tools/sim_tech.py)"),
		flags=flags_well),
	F("tech.fuel", "tech", 4, "Расход топлива", "balance.json:fuel_consumption.**",
		"Топливо: {key}", "блоков на клетку / штук на блок", "сколько копки уходит на добычу топлива", lambda m, r: eff_fuel_rate(m, r) if "blocks_per_cell" in r["id"] else None,
		rec=("оставить", "33 клетки бура на блок: глубже 450 порода сама кормит бур. Уран за блок кодом не читается"),
		flags=lambda m, r: ["кодом не читается"] if r["segs"][-1] == "uranium_per_fuel_block" else []),
	F("tech.tanks", "tech", 4, "Баки: ёмкость и цена", "tech.json:fuel.tanks.**",
		"{name}: {key}", "блоки топлива / цена ступени", "как далеко уходишь без заправки",
		lambda m, r: eff_tank_caps(m, r) if r["segs"][-1] == "capacity_blocks" else eff_tank_cost(m, r),
		rec=("оставить", "бак 0 — 133 клетки (до ~230 от сотни), ступени — дешёвые цели середины игры")),
	F("tech.suits", "tech", 4, "Костюм от жары: ступени", "tech.json:heat.suit_tiers**",
		"{name}: {key}", "", "проходимость глубин 1000–3500 и лавы", eff_suit, summary=sum_suits,
		rec=("опустить", "пятая ступень (1 000 000 монет) — 8.4 ч активной игры, вне границы симулятора 0.8–8 ч; срезать до ≈ 900 000. "
			"Остальное — рабочее предложение, пока владелец не пришлёт свои ступени"), flags=flags_suit),
	F("tech.heat", "tech", 3, "Жара по глубине", ["tech.json:heat.temperature_c", "tech.json:heat.ambient.*"],
		"Жара: {key}", "°C / множитель", "расход бодрости глубже 1000", eff_heat,
		rec=("оставить", "жара не убивает, а гонит домой; с 1000 только начинает чувствоваться")),
	F("tech.rig_upgrades", "tech", 3, "Улучшения бура бурмобиля: цены", "balance.json:tools.drill_rig.upgrade_tiers[*].cost",
		"{name}: цена", "монет", "скорость после 1000", cost_at(1500), rec=("оставить", "проценты — владельца, цены по аналогии с кирками")),
	F("tech.lava", "tech", 3, "Лава: озёра и добыча", "tech.json:heat.lava.*",
		"Лава: {key}", "", "проходимость с 3000", None, rec=("отложить", "владелец пришлёт дизайн лавы отдельно (ГДД §18)")),
	F("tech.station", "tech", 2, "Станция и бак: мелочи", ["tech.json:refinery.**", "tech.json:fuel.low_fuel_fraction", "minerals.json:minerals[fuel_block].weight_kg"],
		"{key}", "", "удобство заправки", None, rec=("оставить", "мелочи; блок легче 4 торфа, иначе перегонка теряет смысл")),
	F("tech.well_misc", "tech", 2, "Скважина: отчёт и защита часов", ["tech.json:well.report_min_seconds", "tech.json:well.anti_cheat.**"],
		"Скважина: {key}", "секунд", "когда показывать отчёт", None, rec=("оставить", "мелочи")),
	F("tech.unused", "tech", 1, "Перегрев и топливо джетпака (не используются)", ["balance.json:drilling.overheat.**", "balance.json:jetpack.**",
		"balance.json:survival.hazards.drill_overheat.**"], "{key}", "", "ничего — кодом не читается", None,
		rec=("убрать", "перегрев заменён жарой (tech.json → heat), джетпак топлива не ест; числа висят в данных без дела")),

	# ---------------- Бой ----------------
	F("cmb.reach", "combat", 4, "Где начинается бой", ["balance.json:world.raid_boss_depth", "combat.json:spawn.**"],
		"Появление монстров: {key}", "", "встретит ли игрок монстра вообще", None, summary=sum_reach,
		rec=("решить", "ни один бот за 12 игровых часов не дошёл до 4000. Теперь с 1500 есть полости со стражами (п.2 владельца), "
			"но бот проверил их только стартом прямо в полости — когда игрок встретит первого стража, покажет следующий ночной прогон")),
	F("cmb.monster_hp", "combat", 3, "Монстры: здоровье и урон", ["combat.json:monsters.*.hp", "combat.json:monsters.*.damage"],
		"{name}: {key}", "HP / урон за удар", "сколько длится бой и как больно", lambda m, r: eff_monster_hp(m, r) if r["segs"][-1] == "hp" else eff_monster_dmg(m, r),
		rec=("оставить", "без игроков на этих глубинах не проверено; тесты боя (tests/test_combat*) держат порядок цифр")),
	F("cmb.monster_rest", "combat", 2, "Монстры: где, как часто, что дают, как двигаются", "combat.json:monsters.**",
		"{name}: {key}", "", "разнообразие и награда за бой", None, rec=("оставить", "до первых живых встреч менять нечего")),
	F("cmb.player", "combat", 3, "Герой в бою", ["combat.json:player.**", "combat.json:formula.*", "combat.json:scaling.*"],
		"Бой: {key}", "", "сила кирки, защита, восстановление", None, rec=("оставить", "кирка — 14 урона раз в 0.7 с, защита гасит урон по формуле X/(X+100)")),
	F("cmb.gear", "combat", 3, "Броня и оружие: сила и рецепты", "combat.json:gear.**",
		"{name}: {key}", "", "прогресс после 4000", lambda m, r: eff_gear_recipe(m, r) if r["segs"][-1] == "recipe" else None,
		rec=("оставить", "пять ступеней из деталей монстров своего пояса")),
	F("cmb.boss", "combat", 3, "Рейдбосс «Идол Бездны»", "combat.json:boss.**",
		"Босс: {key}", "", "финал игры", None, rec=("оставить", "проверен тестом tests/test_combat_boss (модель героя с 240 HP)")),
	F("cmb.sets", "combat", 2, "Ультимативный сет и сокеты", ["combat.json:sets.**", "combat.json:sockets.**", "artifacts.json:artifacts[*].sockets"],
		"{key}", "", "бонусы за полный сет", None, rec=("оставить", "мелочь до появления игроков на 5000+")),
	F("cmb.parts", "combat", 1, "Вес деталей монстров", ["minerals.json:minerals[%s].weight_kg" % k for k in (
		"cinder_ash", "moth_dust", "hopper_fang", "mimic_geode", "spark_core", "warden_plate", "abyss_core", "idol_shard")],
		"{name}: вес", "кг", "сколько места в рюкзаке", eff_weight, rec=("оставить", "лёгкие, чтобы бой не забивал рюкзак")),

	F("cmb.caves", "combat", 3, "Полости-фигуры: где и сколько", "caves.json:**",
		title_cave, "", "как часто между 1500 и 4000 попадается полость с сундуком", None,
		rec=("оставить", "круг, ромб, звезда и сердце; ≈26 на мир, глубже — чаще и крупнее; глубже 4000 — прежний бой")),
	F("cmb.cave_guards", "combat", 3, "Стражи полостей и сундук", ["caves.json:guards.**", "caves.json:chest.**"],
		title_cave_guard, "", "сколько врагов охраняет сундук и когда они замечают героя", None,
		rec=("оставить", "2 стража на 1500, 3 — с 2300, 4 — с 3100, не больше двух стрелков; сундук открывается, когда все стражи мертвы")),
	F("cmb.cave_monsters", "combat", 3, "Стражи: здоровье, урон, повадки", "combat.json:cave_monsters.**",
		title_cave_monster, "", "трудность боя у сундука",
		None, rec=("оставить", "симуляция: на 1500 — 100% побед, остаётся 56–69% HP; на 3500 — 60%, если стоять столбом, и 100% с уклонением. "
			"Рисунки — заготовка до художника")),

	# ---------------- Механики ----------------
	F("mech.chests", "mechanics", 4, "Тайники-сундуки", "mechanics.json:chests.**",
		"Тайники: {key}", "", "сюрприз раз в 20 рядов, еда в шахте", lambda m, r: eff_chest_chance(m, r) if r["segs"][-1] == "chance" else None,
		rec=("оставить", "боты открывают ≈ 1.4 тайника в час; добыча — 3/10/35 «клеток руды»")),
	F("mech.streak", "mechanics", 4, "Азарт и жадность", "mechanics.json:streak.*",
		"Азарт: {key}", "", "как часто включается жадность", lambda m, r: eff_fever_at(m, r) if r["segs"][-1] in ("fever_at", "fever_s") else None,
		rec=("оставить", "секунды и проценты жадности — владельца; 60 с работы (до 26.10 — 60 клеток подряд, у живого игрока не наступало) — раз в ~1.2 мин копки с паузами человека")),
	F("mech.mastery", "mechanics", 3, "Мастерство руд", "mechanics.json:mastery.**",
		"Мастерство: {key}", "", "долгая цель «звёзды руды» и +2% двойной добычи за звезду", eff_mastery,
		rec=("оставить", "пятая звезда — десятки часов: это коллекция, а не прокачка")),

	# ---------------- Монетизация ----------------
	F("mon.packs", "monetization", 4, "Пачки долларов за реальные деньги", "monetization.json:dollar_packs.**",
		"{name}: {key}", "$ / долл.", "доход игры (платежей пока нет)", lambda m, r: eff_pack(m, r) if r["segs"][-1] == "grants_dollars" else None,
		rec=("отложить", "владелец: «реклама и телефоны — позже». Но уже видно противоречие: пачка за $0.99 = 100 долл. = 100 000 монет, а вещи "
			"за доллары стоят 1–20 — пачки в 10–30 раз крупнее цен")),
	F("mon.subs", "monetization", 3, "Подписки: валюта", ["balance.json:monetization.iap_products**", "monetization.json:iap_products**"],
		"{name}: {key}", "долл.", "ценность подписки", eff_sub_currency,
		rec=("отложить", "Премиум+ за $14.90 в месяц даёт 150 долл., а пачка за $4.99 — 550: подписка как источник валюты невыгодна втрое")),
	F("mon.premium_goods", "monetization", 4, "Цены вещей за доллары", ["balance.json:food.items[energy_bar].price_dollars",
		"shop.json:goods_dollars.extra[*].price_dollars"], "{name}: цена", "долл.", "что можно купить на доллары из роликов",
		eff_premium_price, rec=("оставить", "батончик 5, часы 15, выгрузка на склад 25 (раунд 6, на месте таблетки) — = 1–5 роликов «доллар» по 5; "
			"выгрузка дороже часов: спасает и рюкзак, и место в шахте; заметка батончика «1 доллар = 100 монет» устарела (курс 1000)"),
		flags=lambda m, r: ["заметка устарела: «1 доллар = 100 монет», курс владельца — 1000"] if "energy_bar" in r["id"] else []),
	F("mon.unload_lesson", "monetization", 3, "Сцена «выгрузка на склад» на 150", "shop.json:goods_dollars.extra[premium_unload].lesson.*",
		title_unload_lesson, "", "когда игрок узнаёт про выгрузку и пробует её; на 200 — обучение часам", None,
		rec=("решить", "владелец сцену заказал (пояс 150–200), а бесплатного раза не просил: бесплатный первый раз даёт увидеть «улетело домой» "
			"тем, у кого на 150 нет 25 долларов; free_use: false — сцена только показывает кнопку и объясняет")),
	F("mon.cosmetic", "monetization", 2, "Косметика и удобства за доллары", ["monetization.json:cosmetic_catalog**", "monetization.json:convenience_catalog**"],
		"{name}: цена", "долл.", "пока не продаётся в витрине", eff_premium_price, rec=("отложить", "в витрине этих товаров нет (ГДД §15)")),
	F("mon.ads", "monetization", 3, "Лимиты роликов «×2» и замены", ["quests.json:ad_double.*", "tech.json:well.ad_double.*"],
		"Ролики: {key}", "раз в сутки", "сколько наград можно удвоить", None, rec=("оставить", "в пределах лимитов ГДД §15 (3–5 в сутки)")),

	# ---------------- Ощущение и подсказки ----------------
	F("feel.controls", "feel", 2, "Управление: прощение прыжка", "feel.json:controls.*", "Управление: {key}", "с", "отзывчивость прыжка", None,
		rec=("оставить", "проверено тестами и глазами (ГДД §20)")),
	F("feel.hints", "feel", 2, "Подсказки: когда и как долго", "hints.json:**", "Подсказки: {key}", "с / порог", "не превращать экран в туториал", None,
		rec=("оставить", "мелочи интерфейса")),
	F("feel.guidance", "feel", 2, "Проекты на HUD", "guidance.json:**", "Проекты: {key}", "", "трекер «следующая цель»", None,
		rec=("оставить", "мелочи; tracker_hide_built_seconds кодом не читается"),
		flags=lambda m, r: ["кодом не читается"] if r["segs"][-1] == "tracker_hide_built_seconds" else []),
	F("feel.house", "feel", 1, "Радиус входа в дом", "balance.json:house.interact_radius_cells", "Радиус двери", "клетки", "попадание по двери", None,
		rec=("оставить", "мелочь")),
	F("feel.fog", "feel", 1, "Туман войны: скорость рассеивания", "balance.json:fog_of_war.**", "Туман: {key}", "", "вид", None,
		rec=("снять пометку", "так и работает: мгновенно при входе в радиус")),
	F("feel.camera", "feel", 1, "Камера", "feel.json:camera.*", "Камера: {key}", "", "плавность камеры", None, rec=("оставить", "подбор по глазам")),
	F("feel.camera_kick", "feel", 1, "Общий толчок камеры: потолки", "feel.json:camera_kick.*", "Толчок камеры: {key}", "",
		"наезд и тряска урона и удачи вместе", None, rec=("оставить", "подбор по глазам")),
	F("feel.hurt", "feel", 1, "Отклик на урон: потолки и голод", "feel.json:hurt.*", "Урон: {key}", "",
		"тряска, наезд и краснота при ударе (слова владельца 27.10 — без пометки)", None, rec=("оставить", "подбор по глазам: tests/test_screenshot_hurt")),
	F("feel.dig", "feel", 1, "Отклик копки и добычи", ["feel.json:dig.*", "feel.json:loot.*", "feel.json:death.*", "juice.json:dig.*", "juice.json:rare_price"],
		"Отклик: {key}", "", "«сочность»", None, rec=("оставить", "подбор по глазам")),
	F("feel.sound", "feel", 1, "Звук и музыка", ["juice.json:music.*", "juice.json:steps.*", "juice.json:damage.*", "juice.json:fx.*"],
		"Звук: {key}", "", "звук", None, rec=("оставить", "подбор на слух")),
	F("feel.dialogue", "feel", 1, "Диалоги: голос и скорость текста", "dialogue.json:**", "Диалоги: {key}", "", "чтение сцен", None,
		rec=("оставить", "подбор по глазам")),
	F("feel.light", "feel", 1, "Свет и темнота шахты", "fx_light.json:**", "Свет: {key}", "", "вид глубины", None, rec=("оставить", "подбор по глазам")),
	F("feel.teleport_watch", "feel", 1, "Часы-телепорт: пузырь «Вниз» и поиск клетки возврата", "teleport_watch.json:*",
		lambda m, r: {"near_cells": "Пузырь «Вниз» — на скольких клетках от центра площадки",
			"search_radius_cells": "Завал точки возврата: радиус поиска безопасной клетки"}.get(r["segs"][-1], "Часы: %s" % r["segs"][-1]),
		"клеток", "площадка часов и возврат вниз (владелец 27.10)", None,
		rec=("оставить", "0.75 — герой на плите, пузырь не спорит с бурмобилем и станцией; 12 клеток — хватает почти всегда, дальше клетка откапывается")),
	F("feel.luck", "feel", 1, "Отклик удачной находки", "juice.json:luck.*", "Удача: {key}", "", "«момент» удачи (владелец 27.10: крупнее, громче, вспышка, наезд)", None,
		rec=("оставить", "подбор по глазам; earth_moment: удача на земле без вспышки — иначе мигает каждые 10 клеток")),
	F("feel.actor_height", "feel", 1, "Рост бабушки рядом с внуком", "story.json:actors.*.height",
		lambda m, r: "Рост на экране: %s" % {"grandma_poor": "бабушка в эпоху деда", "grandma_rich": "бабушка"}.get(
			r["segs"][-2] if len(r["segs"]) > 1 else "", "актёр"),
		"доля роста героя", "вид сцен у дома (ГДД §15.1, «Рост актёров»)", None,
		rec=("оставить", "все листы персонажей одного роста; бабушке рядом с внуком-подростком — чуть ниже, ориентир 90–95 %")),
]

# Порядок решений для владельца (сверху REVIEW.md). Текст — коротко «что решить».
TOP = [
	("mech.streak", "«У меня вообще не сработала жадность» — причину ищет отдельная ветка. Числа азарта (60 клеток подряд) — после её отчёта."),
	("q.targets", "Цели заданий дня: копка ≈ 25 минут на любой ступени; ступень 2 — ваши 500 клеток, 1000 продаж, 500 трат, 3 еды. Оставить?"),
	("tech.well", "Скважина: ступени окупаются за 0.6–12 суток, заход за кап — не дороже 5 часов игры. Оставить?"),
	("tech.fuel", "Ручной бур: 33 клетки на блок топлива, глубже 450 торф сам кормит бур. Оставить?"),
]

# Что в теме решить и общий совет (2–3 строки). Числа в текстах — из расчёта на текущих данных.
THEME_NOTES = {
	"economy": (["Цены еды и бесплатные заказы держат «голод» в игре: еда стоит ботам ~5% дохода.",
		"Бесплатные 3 заказа в сутки — единственная подушка после ранней смерти."],
		"Оставить всё; поправить устаревшие заметки (энергетик «дороже обеда», «монет взять негде»)."),
	"mining": (["Плотности руд — главный рычаг дохода по глубине; сверены с генератором.",
		"Секунды копки и веса — «по твёрдости»: темп крутит общий ×1.3 владельца."],
		"Оставить; если середина (500–1000) должна манить — поднять золото и алмаз глубже 600, а не всё подряд."),
	"survival": (["Лечение сном и едой — ровно слова владельца (до 100% с едой).",
		"Аптечку считали против смерти за 200; с новой ценой смерти она снова дороже умирания."],
		"Решить цену аптечки после слияния цены смерти; убрать мёртвые записи (суп, ступени стойкости)."),
	"progression": (["Очки навыков 1 → 2 → 3 за уровень — исполненное решение владельца, числа ступеней — предложение.",
		"База HP 100 привязана к шкале падений (20 клеток = 100 HP)."],
		"Оставить; перепроверить после «голода и бодрости» — их ветки должны стать доступнее."),
	"quests": (["Задание дня ≈ 25 минут игры, награда — четверть–треть заработка за то же время.",
		"Доллары из подарков и заданий ограничены 4 в неделю; разовые (достижения, дорога) — сверху."],
		"Оставить; ступень 2 — ориентиры владельца, остальные ступени выведены из них."),
	"artifacts": (["Монеты за находку — 1.5 × опыта, линейно по ветке; доход с глубиной растёт быстрее.",
		"Итог: мелкие находки щедрее руды в разы, глубокие — незаметны."],
		"Опустить мелкие, поднять глубокие: ≈ одна полная ходка на глубине находки."),
	"tech": (["Бур и бурмобиль — ворота середины игры; бур за 10–12 ч собрал один бот из десяти, бурмобиль — ни один.",
		"Бурмобиль держит глубина 1000, а не цена; бур — материалы (железо, бронза из лома).",
		"Скважина, баки и костюм укладываются в границы симулятора, кроме 5-й ступени костюма."],
		"Решить рецепт бура; срезать 5-й костюм; убрать неиспользуемые числа перегрева и топлива джетпака."),
	"combat": (["Все числа боя проверены только тестами: живой игрок до 4000 за 12 ч не доходит.",
		"Полости с монстрами с 1500 добавят новые числа — они попадут сюда как «новые»."],
		"Оставить до первых живых встреч; решить, где начинается бой."),
	"mechanics": (["Тайники ≈ 1.4 в час, жадность ≈ 2.7 раза в час у ботов — механики видны, но не ломают доход.",
		"Мастерство — долгая коллекция (пятая звезда — десятки часов)."],
		"Оставить."),
	"monetization": (["Платежей и рекламной сети нет; числа — заготовка на будущее.",
		"Пачки долларов несоразмерны ценам вещей; подписка невыгодна как источник валюты."],
		"Отложить до решения по рекламе; противоречия записаны."),
	"feel": (["Камера, звук, свет, подсказки, диалоги — подбор по глазам и на слух, на баланс не влияют."],
		"Утвердить пачкой."),
}

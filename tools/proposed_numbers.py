#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
proposed_numbers.py — выгрузка всех чисел `"proposed": true` для разбора владельцем (ГДД §18 «Числа»).

Обходит data/*.json, находит каждое предложенное агентами значение — обёртку {value, proposed, note}
и целые файлы/разделы с общим "proposed": true (их режет на осмысленные строки), подписывает их
по-русски (proposed_catalog.py: тема, что это, единица, на что влияет, совет), считает, чем значение
обернётся в игре (симуляторы tools/sim_tech.py, tools/sim_economy.gd, tools/sim_daily.gd и итоги
ночных ботов), и пишет:
  docs/numbers/proposed.json — все строки со стабильными id «файл:путь»;
  docs/numbers/REVIEW.md     — короткий разбор для чтения человеком.

Запуск (из корня):
  python3 tools/proposed_numbers.py              # с симуляторами Godot (~30 с), если godot есть
  python3 tools/proposed_numbers.py --no-sims    # без Godot: берёт прошлые итоги из docs/numbers/sims.json
  python3 tools/proposed_numbers.py --bot build/bot   # освежить итоги ботов (docs/numbers/bot_anchors.json)
  python3 tools/proposed_numbers.py --out DIR    # писать в другой каталог (тест)

Числа сам инструмент не меняет. Новые proposed-значения, которых нет в каталоге, попадают в выгрузку
сами (тема — по файлу и ключу, описание — из заметки агента) с пометкой «без разбора».
"""

import argparse
import glob
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import proposed_catalog as cat  # noqa: E402

DATA_DIR = os.path.join(ROOT, "data")
OUT_DIR = os.path.join(ROOT, "docs", "numbers")

# ---------------------------------------------------------------------------
# Обход данных
# ---------------------------------------------------------------------------

# Ключи-описания и структура: в разделах с общим proposed это не числа на утверждение.
SKIP_KEYS = {
	"version", "id", "icon", "sprite", "glyph", "name", "name_ru", "name_en", "desc", "desc_ru", "desc_en",
	"title", "note", "notes", "slot", "kind", "behavior", "event", "group", "mode", "placement", "ad_placement",
	"portrait", "side", "accent", "color", "text", "type", "curve", "tile", "counter", "source", "line", "sku",
	"product_id", "monster", "pattern", "variants", "faces", "pieces", "tier", "day", "big", "grand", "kinds",
	"speaker", "hero_model", "proposed", "owner_anchor", "requires_seen", "sum", "filter", "currency", "max_stack",
}
# Под такими ключами словарь/список — одна строка (цена, награда, рецепт, характеристики, добыча).
BUNDLE_KEYS = {"cost", "recipe", "reward", "rewards", "stats", "build_cost", "inputs", "items", "drops", "attack",
	"pool", "bonus_all", "grants", "materials"}
# Поля, по которым элемент списка получает имя в id (вместо номера): id не плывёт, когда соседи вставляют элементы.
ELEM_KEYS = ("id", "product_id", "sku", "key", "tile", "day")


def _is_num(v):
	return isinstance(v, (int, float)) and not isinstance(v, bool)


def _is_scalar_list(v):
	return isinstance(v, list) and v and all(_is_num(x) or (isinstance(x, list) and all(_is_num(y) for y in x)) for x in v)


def _is_small_table(v):
	"""Список словарей из одних чисел (2–3 поля): одна строка-таблица (очки за уровни и т.п.)."""
	return (isinstance(v, list) and v and all(isinstance(x, dict) and 0 < len(x) <= 3 and all(_is_num(y) for y in x.values()) for x in v))


def _elem_key(el, i):
	if isinstance(el, dict):
		for k in ELEM_KEYS:
			if k in el and isinstance(el[k], (str, int)) and not isinstance(el[k], bool):
				return str(el[k])
	return str(i)


def _join(segs):
	out = ""
	for s in segs:
		if s.startswith("["):
			out += s
		else:
			out += ("." if out else "") + s
	return out


def _ctx_name(node):
	if isinstance(node, dict):
		for k in ("name_ru", "name", "title"):
			if isinstance(node.get(k), str):
				return node[k]
	return None


class Extractor:
	def __init__(self, data_dir):
		self.data_dir = data_dir
		self.rows = []

	def run(self):
		for path in sorted(glob.glob(os.path.join(self.data_dir, "*.json"))):
			fname = os.path.basename(path)
			try:
				with open(path, encoding="utf-8") as f:
					data = json.load(f)
			except (OSError, ValueError) as e:
				print("[proposed_numbers] пропущен %s: %s" % (fname, e), file=sys.stderr)
				continue
			self._walk(fname, data, [], [], False, "", None)
		return self.rows

	def _emit(self, fname, segs, ctx, value, note, explicit, raw_parent=None):
		rid = "%s:%s" % (fname, _join(segs))
		if cat.is_skipped(rid):
			return
		self.rows.append({
			"id": rid, "file": "data/" + fname, "path": _join(segs), "segs": list(segs),
			"ctx": [c for c in ctx if c], "value": value, "note": (note or "").strip(),
			"explicit": explicit, "parent": raw_parent,
		})

	def _walk(self, fname, node, segs, ctx, implicit, note, parent):
		rid = "%s:%s" % (fname, _join(segs))
		if isinstance(node, dict):
			if node.get("proposed") is False:
				return  # число владельца
			if node.get("proposed") is True and "value" in node:
				self._explicit(fname, node["value"], segs, ctx, node.get("note", ""), parent)
				return
			name = _ctx_name(node)
			if node.get("proposed") is True:
				implicit = True
				note = node.get("note") or node.get("_note") or node.get("_comment") or node.get("_legend") or note
			if implicit and segs and (segs[-1] in BUNDLE_KEYS or cat.is_bundle(rid)) and not cat.is_split(rid):
				if _has_numbers(node):
					self._emit(fname, segs, ctx + [name], node, note, False, parent)
				return
			own_note = node.get("_note") if isinstance(node.get("_note"), str) else None
			for k, v in node.items():
				if k.startswith("_") or k in ("proposed", "note") or k in SKIP_KEYS and not _has_wrapper(v):
					continue
				self._walk(fname, v, segs + [k], ctx + [name], implicit, own_note or note, node)
		elif isinstance(node, list):
			if implicit and (_is_scalar_list(node) or _is_small_table(node) or cat.is_bundle(rid)):
				if _has_numbers(node):
					self._emit(fname, segs, ctx, node, note, False, parent)
				return
			if implicit and segs and segs[-1] in BUNDLE_KEYS:
				if _has_numbers(node):
					self._emit(fname, segs, ctx, node, note, False, parent)
				return
			for i, el in enumerate(node):
				self._walk(fname, el, segs + ["[%s]" % _elem_key(el, i)], ctx, implicit, note, node)
		elif implicit and _is_num(node) and (not segs or segs[-1] not in SKIP_KEYS):
			self._emit(fname, segs, ctx, node, note, False, parent)

	def _explicit(self, fname, value, segs, ctx, note, parent):
		"""Обёртка {value, proposed, note}: одна строка, а большой список словарей — строка на элемент."""
		rid = "%s:%s" % (fname, _join(segs))
		if (isinstance(value, list) and value and all(isinstance(x, dict) for x in value)
				and not _is_small_table(value) and not cat.is_bundle(rid)):
			for i, el in enumerate(value):
				eseg = segs + ["[%s]" % _elem_key(el, i)]
				name = _ctx_name(el)
				if _is_bundle_dict(el):
					self._emit(fname, eseg, ctx + [name], el, note, True, value)
					continue
				for k, v in el.items():
					if k.startswith("_") or k in SKIP_KEYS:
						continue
					if isinstance(v, dict) and k not in BUNDLE_KEYS:
						self._walk(fname, v, eseg + [k], ctx + [name], True, note, el)
					elif _is_num(v) or isinstance(v, (dict, list)):
						if _has_numbers(v):
							self._emit(fname, eseg + [k], ctx + [name], v, note, True, el)
			return
		self._emit(fname, segs, ctx, value, note, True, parent)


def _has_numbers(v):
	if _is_num(v):
		return True
	if isinstance(v, dict):
		return any(_has_numbers(x) for k, x in v.items() if not str(k).startswith("_"))
	if isinstance(v, list):
		return any(_has_numbers(x) for x in v)
	return False


def _has_wrapper(v):
	if isinstance(v, dict):
		if v.get("proposed") is True:
			return True
		return any(_has_wrapper(x) for x in v.values())
	if isinstance(v, list):
		return any(_has_wrapper(x) for x in v)
	return False


def _is_bundle_dict(d):
	"""Цена/награда: словарь из чисел (и вложенного items/inputs), ключи — монеты и ресурсы."""
	if not isinstance(d, dict) or not d:
		return False
	for k, v in d.items():
		if k.startswith("_"):
			continue
		if _is_num(v):
			continue
		if k in ("items", "inputs") and isinstance(v, dict) and all(_is_num(x) for x in v.values()):
			continue
		return False
	return True


# ---------------------------------------------------------------------------
# Итоги ботов (docs/numbers/bot_anchors.json): освежаются только явно, флагом --bot
# ---------------------------------------------------------------------------

def _median(vals):
	vals = sorted(vals)
	if not vals:
		return None
	n = len(vals)
	return vals[n // 2] if n % 2 else 0.5 * (vals[n // 2 - 1] + vals[n // 2])


MILESTONE_PREFIXES = ("buy:", "craft:", "depth_", "level_", "well_level_", "first_")


def summarize_bots(bot_dir):
	"""Сводка ночных прогонов ботов: медианы вех (минуты), темпы событий в час, доход по фазам."""
	runs = []
	for path in sorted(glob.glob(os.path.join(bot_dir, "**", "telemetry.json"), recursive=True)):
		if "shots_cp_" in path:
			continue  # повтор с сейва ради снимков, не самостоятельная игра
		try:
			with open(path, encoding="utf-8") as f:
				t = json.load(f)
		except (OSError, ValueError):
			continue
		meta = t.get("meta", {})
		secs = float(meta.get("sim_seconds", 0) or 0)
		if meta.get("partial") or secs < 3 * 3600:
			continue
		runs.append((path, t, secs))
	if not runs:
		return None
	src = os.path.abspath(bot_dir)
	out = {"source": os.path.relpath(src, ROOT) if src.startswith(ROOT) else src,
		"builds": sorted({r[1].get("meta", {}).get("build", "?") for r in runs}),
		"runs": [], "milestones_min": {}, "per_hour": {}, "income_by_phase": {}, "trips_by_depth": {}}
	keys = set()
	for _, t, _ in runs:
		keys.update(k for k in t.get("milestones", {}) if k.startswith(MILESTONE_PREFIXES))
	for k in sorted(keys):
		vals = [float(t["milestones"][k]) / 60.0 for _, t, _ in runs if k in t.get("milestones", {})]
		out["milestones_min"][k] = {"median": round(_median(vals), 1), "min": round(min(vals), 1),
			"max": round(max(vals), 1), "n": len(vals), "of": len(runs)}
	hours_total = sum(s for _, _, s in runs) / 3600.0
	ev = {}
	earned = food = 0.0
	deaths = 0
	for _, t, secs in runs:
		for k, v in t.get("event_counts", {}).items():
			ev[k] = ev.get(k, 0) + v
		m = t.get("meta", {})
		earned += float(m.get("coins_earned_total", 0) or 0)
		food += float(m.get("coins_on_food", 0) or 0)
		deaths += len(t.get("deaths", []))
		es = m.get("end_state", {})
		out["runs"].append({"goal": m.get("goal"), "character": m.get("character"), "hours": round(secs / 3600.0, 1),
			"income_per_hour": m.get("income_per_hour"), "max_depth": es.get("max_depth"), "level": es.get("level"),
			"artifacts": es.get("artifacts")})
	for k in ("dug", "ate", "slept", "chest_opened", "fever_started", "lucky_find", "mastery_star", "quest_done", "sold",
			"bought", "collapse", "healed"):
		if k in ev:
			out["per_hour"][k] = round(ev[k] / hours_total, 2)
	out["per_hour"]["deaths"] = round(deaths / hours_total, 3)
	out["per_hour"]["artifacts"] = round(sum(r["artifacts"] or 0 for r in out["runs"]) / hours_total, 2)
	out["game_hours"] = round(hours_total, 1)
	out["food_share"] = round(food / max(earned, 1.0), 4)
	out["coins_earned_per_hour"] = round(earned / hours_total)
	# Доход по фазам: продажи руды в окне игрового времени (без находок, наград и скважины).
	for a, b in ((0, 1), (1, 3), (3, 6), (6, 12)):
		coins = secs_in = 0.0
		for _, t, secs in runs:
			if secs < b * 3600:
				continue
			coins += sum(float(s.get("coins", 0)) for s in t.get("sales", []) if a * 3600 <= float(s.get("t", 0)) < b * 3600)
			secs_in += (b - a) * 3600
		if secs_in:
			out["income_by_phase"]["%d-%d" % (a, b)] = round(coins / (secs_in / 3600.0))
	for a, b in ((0, 100), (100, 300), (300, 600), (600, 1000), (1000, 99999)):
		vals, mins = [], []
		for _, t, _ in runs:
			for tr in t.get("trips", []):
				md = float(tr.get("max_depth", 0) or 0)
				if a <= md < b and tr.get("pack_value"):
					vals.append(float(tr["pack_value"]))
					mins.append((float(tr.get("end", 0)) - float(tr.get("start", 0))) / 60.0)
		if vals:
			out["trips_by_depth"]["%d-%d" % (a, b)] = {"pack_value": round(_median(vals)), "minutes": round(_median(mins), 1), "n": len(vals)}
	return out


# ---------------------------------------------------------------------------
# Симуляторы Godot (docs/numbers/sims.json — кэш на случай запуска без Godot)
# ---------------------------------------------------------------------------

SIM_ECONOMY = [
	# (ключ, подпись, аргументы sim_economy.gd)
	("farm", "серпантин — каждый ряд от стены до стены (так копает новичок с обзором 1)", ["--policy=farm", "--mech=1"]),
	("farm_noart", "серпантин без монет за артефакты", ["--policy=farm", "--mech=1", "--artifacts=0"]),
	("shaft", "дайв — прямая шахта вниз (нижняя граница темпа)", ["--policy=shaft", "--mech=1"]),
]


def data_fingerprint(data_dir):
	import hashlib
	h = hashlib.sha1()
	for path in sorted(glob.glob(os.path.join(data_dir, "*.json"))):
		with open(path, "rb") as f:
			h.update(os.path.basename(path).encode() + b"\0" + f.read())
	return h.hexdigest()[:12]


def _godot():
	g = os.environ.get("GODOT", "godot")
	return g if shutil.which(g) else None


def run_sims(seeds=4):
	godot = _godot()
	if not godot:
		return None, "godot не найден"
	env = dict(os.environ)
	tmp = tempfile.mkdtemp(prefix="proposed_numbers_")
	env["XDG_DATA_HOME"] = os.path.join(tmp, "xdg")
	out = {"economy": {}, "daily": []}
	try:
		if not os.path.isfile(os.path.join(ROOT, ".godot", "global_script_class_cache.cfg")):
			subprocess.run([godot, "--headless", "--path", ROOT, "--import"], env=env,
				stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=900)
		for key, label, args in SIM_ECONOMY:
			jpath = os.path.join(tmp, key + ".json")
			p = subprocess.run([godot, "--headless", "--path", ROOT, "res://tools/sim_economy.tscn", "--",
				"--seeds=%d" % seeds, "--json=" + jpath] + args, env=env, capture_output=True, text=True, timeout=600)
			if p.returncode != 0 or not os.path.exists(jpath):
				return None, "sim_economy (%s) не отработал: код %s" % (key, p.returncode)
			with open(jpath, encoding="utf-8") as f:
				res = json.load(f)
			mile = {}
			for run in res.get("runs", []):
				for k, v in run.get("mile", {}).items():
					mile.setdefault(k, []).append(float(v) / 60.0)
			n = len(res.get("runs", []))
			entry = {"label": label, "seeds": n,
				"milestones_min": {k: {"mean": round(sum(v) / len(v), 1), "n": len(v)} for k, v in sorted(mile.items())}}
			m = re.search(r"продано руды: (\d+) монет за прогон, (\d+) монет в игровой час", p.stdout)
			if m:
				entry["sold_per_hour"] = int(m.group(2))
			m = re.search(r"артефакты: в среднем найдено ([\d.]+), монет с них (\d+)", p.stdout)
			if m:
				entry["artifacts_found"] = float(m.group(1))
				entry["artifact_coins"] = int(m.group(2))
			m = re.search(r"механики: сундуков ([\d.]+), жадностей ([\d.]+).*?— ([\d.]+)% проданного", p.stdout)
			if m:
				entry["chests"] = float(m.group(1))
				entry["fevers"] = float(m.group(2))
				entry["mech_share_pct"] = float(m.group(3))
			out["economy"][key] = entry
		p = subprocess.run([godot, "--headless", "--path", ROOT, "res://tools/sim_daily.tscn"], env=env,
			capture_output=True, text=True, timeout=300)
		for line in p.stdout.splitlines():
			m = re.match(r"^(\d)\s+(\d+)-(\d+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\s+(\d+)", line)
			if m:
				out["daily"].append({"tier": int(m.group(1)), "band": [int(m.group(2)), int(m.group(3))],
					"sec_per_cell": float(m.group(4)), "cells_per_min": float(m.group(5)), "ore_pct": float(m.group(6)),
					"coins_per_cell": float(m.group(8)), "coins_per_min": int(m.group(9))})
	except (OSError, subprocess.SubprocessError, ValueError) as e:
		return None, "симуляторы не отработали: %s" % e
	finally:
		shutil.rmtree(tmp, ignore_errors=True)
	return out, None


# ---------------------------------------------------------------------------
# Форматирование
# ---------------------------------------------------------------------------

def fnum(x, digits=None):
	"""1234567 -> «1 234 567», 0.25 -> «0.25»."""
	if x is None:
		return "—"
	if isinstance(x, bool):
		return "да" if x else "нет"
	if digits is None:
		if isinstance(x, int) or float(x).is_integer():
			digits = 0
		elif abs(x) >= 100:
			digits = 0
		elif abs(x) >= 10:
			digits = 1
		else:
			digits = 2
	s = ("%." + str(digits) + "f") % x
	if digits:
		s = s.rstrip("0").rstrip(".")
	whole, _, frac = s.partition(".")
	sign = "-" if whole.startswith("-") else ""
	whole = whole.lstrip("-")
	if len(whole) > 4:
		whole = "{:,}".format(int(whole)).replace(",", " ")
	return sign + whole + ("." + frac if frac else "")


def fmin(minutes):
	"""Игровые минуты по-человечески."""
	if minutes is None or (isinstance(minutes, float) and (math.isinf(minutes) or math.isnan(minutes))):
		return "никогда"
	if minutes < 1:
		return "< 1 мин"
	if minutes < 90:
		return "%d мин" % round(minutes)
	if minutes < 48 * 60:
		return "%s ч" % fnum(minutes / 60.0, 1)
	return "%s сут" % fnum(minutes / 1440.0, 1)


def fhours(h):
	return fmin(h * 60.0) if h is not None else "—"


def pct(x, digits=0):
	return ("%." + str(digits) + "f%%") % (x * 100.0)


# ---------------------------------------------------------------------------
# Модель игры для «чем это обернётся»: настоящие данные + sim_tech + кэш симуляторов + итоги ботов
# ---------------------------------------------------------------------------

def _unwrap(v):
	return v["value"] if isinstance(v, dict) and "value" in v else v


def num_or(v, default):
	return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else default


class Model:
	def __init__(self, data_dir, sims=None, bots=None):
		self.data = {}
		for path in sorted(glob.glob(os.path.join(data_dir, "*.json"))):
			try:
				with open(path, encoding="utf-8") as f:
					self.data[os.path.basename(path)] = json.load(f)
			except (OSError, ValueError):
				pass
		self.sims = sims or {}
		self.bots = bots or {}
		self.min = {m["id"]: m for m in self.data.get("minerals.json", {}).get("minerals", []) if isinstance(m, dict) and "id" in m}
		self.names = {k: m.get("name_ru", k) for k, m in self.min.items()}
		for k, m in self.data.get("combat.json", {}).get("materials", {}).items():
			self.names.setdefault(k, m.get("name", k))
		self.names.update({"coins": "монет", "dollars": "долл.", "premium_currency": "долл.", "xp": "опыта", "points": "очк."})
		self.tile_to_id = {o.get("tile"): o.get("id") for o in self.data.get("world_layers.json", {}).get("ores", [])}
		self.tile_to_id.update({"GOLD_ORE": "gold", "PLATINUM_ORE": "platinum", "URANIUM_ORE": "uranium", "DIAMOND": "diamond",
			"RUBY": "ruby", "EMERALD": "emerald", "GEOCRYSTAL": "geocrystal", "ANCIENT_METAL": "ancient_metal",
			"OBSIDIAN": "obsidian", "HELLSTONE": "hellstone", "DARK_MATTER": "dark_matter", "UNIVERSALIUM": "universum"})
		self.st = None
		self.st_error = None
		try:
			import sim_tech  # noqa: WPS433 — читает те же data/*.json
			self.st = sim_tech
		except Exception as e:  # данные поменяли форму — считаем без него
			self.st_error = "%s: %s" % (type(e).__name__, e)
		self._ip_cache = {}

	# --- доступ к данным ---
	def get(self, fname, *path, default=None):
		node = self.data.get(fname)
		for p in path:
			if isinstance(node, dict):
				node = node.get(p)
			elif isinstance(node, list) and isinstance(p, int) and p < len(node):
				node = node[p]
			else:
				return default
			if node is None:
				return default
		return _unwrap(node)

	def name(self, mid):
		mid = self.tile_to_id.get(mid, mid)
		return self.names.get(mid, mid)

	def price(self, mid):
		p = _unwrap(self.min.get(mid, {}).get("price_coins"))
		return float(p) if isinstance(p, (int, float)) else 0.0

	def weight(self, mid):
		w = _unwrap(self.min.get(mid, {}).get("weight_kg"))
		return float(w) if isinstance(w, (int, float)) else 0.0

	def bundle_text(self, d):
		"""{coins: 2000, iron_ore: 500, items: {...}} -> «2 000 монет + 500 Железная руда …»."""
		if not isinstance(d, dict):
			return fnum(d) if isinstance(d, (int, float)) else str(d)
		parts = []
		order = ["coins", "dollars", "premium_currency", "xp", "points"]
		flat = {}
		for k, v in d.items():
			if str(k).startswith("_"):
				continue
			if k in ("items", "inputs", "materials") and isinstance(v, dict):
				flat.update(v)
			elif k == "item" and isinstance(v, dict):
				flat[v.get("id", "?")] = v.get("count", 1)
			else:
				flat[k] = v
		for k in order + sorted(k for k in flat if k not in order):
			if k not in flat:
				continue
			v = flat[k]
			if isinstance(v, (int, float)) and not isinstance(v, bool):
				if k in order:
					parts.append("%s %s" % (fnum(v), self.names.get(k, k)))
				else:
					parts.append("%s × %s" % (self.name(k), fnum(v)))
			elif isinstance(v, list) and all(isinstance(x, (int, float)) for x in v):
				parts.append("%s: %s" % (self.names.get(k, k), " / ".join(fnum(x) for x in v)))
			elif isinstance(v, list):
				parts.append("%s: %s" % (k, ", ".join(self.name(str(x)) for x in v)))
		return " + ".join(parts) if parts else "—"

	def value_text(self, v, row=None):
		if v is None:
			return "не задано"
		if isinstance(v, bool):
			return "да" if v else "нет"
		if isinstance(v, (int, float)):
			return fnum(v)
		if isinstance(v, str):
			return v
		if isinstance(v, list):
			if all(isinstance(x, list) for x in v):
				return ", ".join("%s→%s" % (fnum(x[0]), fnum(x[1])) if len(x) == 2 else "/".join(fnum(y) for y in x) for x in v)
			if all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in v):
				return " / ".join(fnum(x) for x in v)
			if all(isinstance(x, str) for x in v):
				return ", ".join(self.name(x) for x in v)
			if all(isinstance(x, dict) and "chance" in x for x in v):
				return ", ".join("%s %s%% ×%s" % (self.name(str(x.get("id", "?"))), fnum(num_or(x.get("chance"), 0) * 100),
					fnum(x.get("min", 1)) if x.get("min", 1) == x.get("max", x.get("min", 1)) else "%s–%s" % (fnum(x.get("min", 1)), fnum(x.get("max", 1))))
					for x in v)
			if all(isinstance(x, dict) for x in v):
				return "; ".join(self._dict_short(x) for x in v)
		if isinstance(v, dict):
			if row is not None and row.get("bundle_kind") == "params":
				return self._dict_short(v)
			if self._is_resource_dict(v):
				return self.bundle_text(v)
			return self._dict_short(v)
		return json.dumps(v, ensure_ascii=False)

	def _is_resource_dict(self, d):
		keys = [k for k in d if not str(k).startswith("_")]
		known = set(self.min) | {"coins", "dollars", "premium_currency", "xp", "points", "items", "inputs", "item", "materials", "gear"}
		return keys and all(k in known for k in keys)

	def _dict_short(self, d):
		parts = []
		for k, v in d.items():
			if str(k).startswith("_") or k in ("note", "proposed"):
				continue
			label = self.name(k) if k in self.min or k in self.tile_to_id else k
			if isinstance(v, dict):
				parts.append("%s: {%s}" % (label, self._dict_short(v)))
			elif isinstance(v, list):
				parts.append("%s %s" % (label, "–".join(fnum(x) if isinstance(x, (int, float)) else str(x) for x in v)))
			elif isinstance(v, (int, float)):
				parts.append("%s %s" % (label, fnum(v)))
			elif isinstance(v, str):
				parts.append("%s %s" % (label, self.name(v)))
		return ", ".join(parts)

	# --- темп игры ---
	def dig_mult(self, tool):
		tools = self.data.get("balance.json", {}).get("tools", {})
		best = max((float(_unwrap(t.get("speed_multiplier", 0)) or 0) for t in tools.values()
			if isinstance(t, dict) and t.get("line") == "pickaxe"), default=1.0)
		g = float(self.get("balance.json", "digging", "global_speed_multiplier", default=1.0) or 1.0)
		if tool == "rusty":
			return 1.0 * g
		if tool == "best":
			return best * g
		hand = best * float(tools.get("hand_drill", {}).get("speed_vs_best_pickaxe", 2.0))
		if tool == "hand_drill":
			return hand * g
		return hand * float(tools.get("drill_rig", {}).get("speed_vs_hand_drill", 2.0)) * g

	def income(self, depth):
		"""(монет за ходку, минут на ходку, монет в час активной игры) на глубине — sim_tech."""
		if not self.st:
			return None
		if depth not in self._ip_cache:
			try:
				self._ip_cache[depth] = self.st.active_coins_per_hour(max(int(depth), 6))
			except Exception:
				self._ip_cache[depth] = None
		return self._ip_cache[depth]

	def mat_hours(self, mid, qty, depth):
		if not self.st:
			return None
		try:
			return self.st.hours_for(mid, qty, depth)
		except Exception:
			return None

	def cost_hours(self, cost, depth, mat_depth=None):
		"""Цена в часах активной игры на глубине: (итого, монеты, материалы, самый долгий материал).
		Как в sim_tech.py: монеты — по доходу на depth, материалы — по их доле в породе на mat_depth."""
		inc = self.income(depth)
		if not inc or not isinstance(cost, dict):
			return None
		coins = float(cost.get("coins", 0) or 0)
		mats = dict(cost.get("items", {}) or {})
		mats.update(cost.get("inputs", {}) or {})
		mats.update({k: v for k, v in cost.items() if k in self.min and isinstance(v, (int, float))})
		ch = coins / max(inc[2], 1.0)
		worst, mh = None, 0.0
		for mid, n in mats.items():
			if mid == "bronze":
				mid = "scrap"  # бронза плавится из лома 1:1
			h = self.mat_hours(mid, n, mat_depth or depth)
			if h is None:
				continue
			if h > mh:
				mh, worst = h, mid
		return ch + mh, ch, mh, worst

	def cost_hours_text(self, cost, depth, mat_depth=None):
		r = self.cost_hours(cost, depth, mat_depth)
		if not r:
			return None
		total, ch, mh, worst = r
		if math.isinf(total):
			return "на глубине %s нужного материала (%s) нет вовсе — не собрать" % (fnum(mat_depth or depth), self.name(worst))
		s = "≈ %s активной игры на глубине %s" % (fhours(total), fnum(depth))
		if mh > 0 and ch > 0:
			s += " (деньги %s, материалы %s — дольше всего %s)" % (fhours(ch), fhours(mh), self.name(worst))
		return s

	def trip(self, depth):
		inc = self.income(depth)
		return inc[0] if inc else None

	def bot_mile(self, key):
		m = self.bots.get("milestones_min", {}).get(key)
		if not m:
			return None
		return m

	def bot_mile_text(self, key, label=None):
		m = self.bot_mile(key)
		runs = len(self.bots.get("runs", []))
		if not m:
			return ("боты (%d прогонов): не дошли" % runs) if runs else None
		s = "боты: %s (медиана; %s–%s; у %d из %d)" % (fmin(m["median"]), fmin(m["min"]), fmin(m["max"]), m["n"], m["of"])
		return (label + " — " + s) if label else s

	def sim_mile(self, key, policy="farm"):
		e = self.sims.get("economy", {}).get(policy, {})
		m = e.get("milestones_min", {}).get(key)
		return m["mean"] if m else None

	def daily_rate(self, tier):
		for d in self.sims.get("daily", []):
			if d.get("tier") == tier:
				return d
		return None

	def death_fee(self, coins):
		d = self.data.get("healing.json", {}).get("death", {})
		if not isinstance(d, dict):
			return None
		fee = _unwrap(d.get("coins_fee"))
		p = _unwrap(d.get("coins_fee_percent", d.get("fee_percent", d.get("percent"))))
		if isinstance(p, (int, float)):
			lo = float(_unwrap(d.get("fee_min", d.get("coins_fee_min", d.get("min", 0)))) or 0)
			hi = float(_unwrap(d.get("fee_max", d.get("coins_fee_max", d.get("max", 1e18)))) or 1e18)
			return min(coins, max(lo, min(hi, coins * float(p) / 100.0)))
		if isinstance(fee, (int, float)):
			return min(coins, float(fee))
		return None

	def skill_points_at(self, level):
		sp = self.data.get("upgrades.json", {}).get("skill_points", {})
		tiers = _unwrap(sp.get("per_level_tiers")) or []
		bonus = int(sp.get("bonus_every_5th_level", 0) or 0)
		per = int(sp.get("per_level", 1) or 1)
		total = 0
		for lv in range(2, level + 1):
			pts = per
			for t in tiers:
				if lv <= int(t.get("up_to_level", 0)):
					pts = int(t.get("points", per))
					break
			total += pts + (bonus if lv % 5 == 0 else 0)
		return total

	def xp_for_level(self, n):
		return 100.0 * n ** 1.5

	def fall_damage(self, h):
		fd = self.data.get("balance.json", {}).get("fall_damage", {})
		if h < float(fd.get("min_height_cells", 5)):
			return 0.0
		return float(fd.get("coefficient", 0.154)) * h ** float(fd.get("exponent", 2.16))


# ---------------------------------------------------------------------------
# Подписи, семейства, темы
# ---------------------------------------------------------------------------

KEY_RU = {
	"depth_min": "с глубины", "depth_max": "до глубины", "price_coins": "цена", "price_dollars": "цена", "price_usd": "цена, $",
	"weight_kg": "вес", "drill_seconds": "секунд на клетку", "cost": "цена", "reward": "награда", "rewards": "награда",
	"target": "цель", "targets": "цели по ступеням", "hp": "здоровье", "damage": "урон", "xp": "опыт", "coins": "монеты",
	"chance": "шанс", "weight": "вес выпадения", "hp_percent": "HP за раз", "unlock_depth": "открывается с глубины",
	"cells_per_hour": "клеток в час", "cap_hours": "офлайн-кап, ч", "depth_cap": "копает на глубине", "tolerance_c": "держит жару до",
	"lava_resist": "снимает урон лавы", "capacity_blocks": "ёмкость по ступеням", "upgrade_cost": "цена ступени",
	"daily_limit": "раз в сутки", "grants_dollars": "долларов в пачке", "premium_currency": "доллары", "drops": "добыча",
	"speed": "скорость", "chase_speed": "скорость погони", "sight": "видит на", "attack": "тайминги атаки", "size": "размер",
	"stats": "характеристики", "recipe": "рецепт", "build_cost": "цена постройки", "build_unlock_depth": "открывается с глубины",
	"hp_percent_full_night": "HP за полную ночь", "fed_full_at_percent": "сытость для полного лечения",
	"hungry_at_percent": "сытость «голодный сон»", "hungry_factor": "доля лечения натощак", "min_hp_deficit_percent": "пускает спать при нехватке HP",
	"sleep_min_deficit_percent": "пускает спать при усталости от", "sleep_hunger_factor": "расход голода во сне",
	"sleep_animation_seconds": "длина сна, реальные секунды", "fever_at": "клеток до жадности", "idle_break_s": "пауза до обрыва серии",
	"fever_extra": "лишняя добыча в жадности", "min_depth": "с глубины", "band_rows": "полоса рядов", "tries": "попыток",
	"value_cells": "ценность, клеток руды", "xp_bonus": "бонус опыта", "food_chance": "шанс еды", "per_cycle_pct": "+% за неделю серии",
	"max_pct": "потолок, %", "pct_per_day": "+% за день серии", "grace_days": "прощённых пропусков", "dollar_every": "доллар каждые N дней",
	"free_per_day": "бесплатно в сутки", "ad_daily_limit": "за ролик в сутки", "per_week": "в неделю", "points": "очки",
	"count": "сколько", "scale": "множитель цели", "weekly_scale": "множитель недельной цели", "bonus_all": "сундук дня",
	"pool": "веса шаблонов", "at": "очков до ступени", "points_by_tier": "очки за бронзу/серебро/золото",
	"tier_by_max_depth": "ступени по рекорду глубины", "per_level_tiers": "очки за уровень", "base": "база",
	"cost_note": "цена ступеней", "find_bonus": "награда за находку", "temperature_c": "температура по глубине",
	"base_tolerance_c": "без костюма терпит до", "stamina_extra_per_50c": "+расход бодрости за 50 °C",
	"max_multiplier": "потолок множителя", "coal_per_fuel_block": "угля на блок", "uranium_per_fuel_block": "урана на блок",
	"hand_drill": "ручной бур", "drill_rig": "бурмобиль", "blocks_per_cell": "блоков на клетку",
	"cooldown_exponent": "кривая остывания", "default_cells_to_overheat": "клеток до перегрева",
	"overheat_hp_damage_per_second": "урон перегрева, HP/с", "fuel_source": "топливо джетпака", "no_fuel_fallback": "если топлива нет",
	"raid_boss_depth": "глубина рейдбосса", "premium_currency_onetime": "доллары разово", "premium_currency_daily": "доллары в день",
	"dissipation_speed": "скорость рассеивания", "card_min_value": "порог карточки потерь",
	"tracker_hide_built_seconds": "галочка «собрано», с", "burn_damage_per_second": "урон, HP/с", "skill_penalty_percent": "штраф навыкам, %",
	"hp_drain_per_second": "потеря HP в секунду", "heat_resistance_stages": "ступени стойкости", "interact_radius_cells": "радиус двери",
	"cavern": "каверны", "pit": "провалы", "grotto": "гроты", "ruin": "руины", "vein": "жилы", "treasure": "клад в кавернах",
	"gems": "самоцветы гротов", "ruin_loot": "добыча руин", "slot_h": "высота слота, рядов", "slot_chance": "шанс образования в слоте",
	"first_delay_sec": "первый монстр через, с", "max_alive": "монстров одновременно", "interval_sec": "интервал появления, с",
	"min_dist": "ближе всего, клеток", "max_dist": "дальше всего, клеток", "active_dist": "активен в радиусе", "despawn_dist": "исчезает дальше",
	"rampup": "разгон сложности, клеток", "depth_full": "полная сложность с глубины", "bfs_limit": "поиск места, клеток",
	"view_half": "полуэкран обзора", "iframes_sec": "неуязвимость после удара, с", "stun_sec": "оглушение, с",
	"knockback_cells": "отбрасывание, клеток", "regen_delay_sec": "реген через, с", "regen_base_per_sec": "реген HP/с",
	"armor_k": "константа брони", "res_cap_pct": "потолок сопротивления, %", "min_damage": "минимальный урон",
	"hp_per_1000": "+HP монстров за 1000", "dmg_per_1000": "+урон монстров за 1000", "dmg": "урон", "cd": "перезарядка, с",
	"reach": "дальность", "swing_height": "высота замаха", "tap_enemy_radius_px": "радиус тапа по монстру",
	"y_min": "с глубины", "chance_at_start": "доля озёр на 3000", "drop": "что остаётся",
	"low_fuel_fraction": "порог «мало топлива»", "report_min_seconds": "отчёт не короче, с", "max_skew_back_seconds": "откат часов, с",
	"unpriced_weight_price": "вес материала без цены", "unpriced_xp": "опыт за материал без цены", "xp_share": "доля опыта",
	"value_spread": "разброс ценности", "deep_shift_per_1000": "сдвиг ступеней за 1000", "thresholds": "пороги звёзд",
	"price_mid": "граница «средняя руда»", "price_precious": "граница «драгоценная»", "chance_per_star": "+двойная добыча за звезду",
	"xp_per_star": "опыт звезды", "min_star_xp": "минимум опыта звезды", "cheap": "дешёвые руды", "mid": "средние руды",
	"precious": "драгоценные", "expected_cells_dug_per_find_by_branch": "клеток до находки", "min_candidate_cells": "клеток-кандидатов минимум",
	"max_candidate_cells": "клеток-кандидатов максимум", "single_row_is_guaranteed": "находка в одном ряду гарантирована",
	"completion_reward": "награда ветки", "free_orders_per_day": "бесплатных заказов в сутки",
	"armor_mult": "доля урона, что проходит сквозь броню", "intro_sec": "появление, с", "phase_hp": "смена фаз при доле HP",
	"transition_sec": "смена фазы, с", "phase_heal_pct": "лечится при смене фазы", "telegraph_sec": "предупреждение удара, с",
	"recover_sec": "отдых после удара, с", "gap_sec": "пауза между ударами, с", "slam": "удар", "rain": "камнепад", "wave": "волна",
	"summon": "призыв", "reach_pad": "запас дальности", "arena": "арена", "wake_radius": "просыпается в радиусе",
	"hit_pad": "запас попадания", "knock_resist": "сопротивление отбрасыванию", "pitch": "высота голоса",
	"blip_db": "громкость «бипа»", "cps": "букв в секунду", "cps_long": "букв в секунду (длинные)", "blip_every": "бип каждые N букв",
	"pause_comma": "пауза на запятой", "pause_stop": "пауза на точке", "pause_ellipsis": "пауза на многоточии",
	"stops": "затемнение по глубине", "torch": "факел", "night": "ночь", "default_scale": "недельная цель = дней",
	"follow_tau_x_s": "сглаживание по горизонтали, с", "follow_tau_y_s": "сглаживание по вертикали, с",
	"lead_x_cells": "упреждение по взгляду, клеток", "lead_x_tau_s": "плавность упреждения, с", "lead_y_tau_s": "плавность по вертикали, с",
	"fall_look_gain": "взгляд вниз при падении", "fall_look_from": "взгляд вниз с скорости", "fall_look_max": "взгляд вниз, максимум",
	"rise_look_gain": "взгляд вверх при подъёме", "rise_look_max": "взгляд вверх, максимум", "dig_look_down": "взгляд вниз при копке",
	"snap_cells": "прыжок камеры дальше, клеток", "punch_decay_s": "затухание наезда, с", "punch_max": "наезд камеры, максимум",
	"hitstop_min_total_s": "микропауза на породе от, с", "hitstop_s": "микропауза удара, с", "hitstop_share": "микропауза, доля клетки",
	"hitstop_credit_ttl_s": "зачёт микропаузы, с", "crack_dark_from": "трещины темнеют с", "crack_dark_to": "трещины темнеют до",
	"stack_window_s": "слияние «+N», с", "fly_min_price": "летит в рюкзак дороже", "epic_price": "«момент» дороже",
	"epic_hitstop_s": "пауза «момента», с", "auto_hide_s": "карточка исчезает через, с", "heavy_shake_px": "тряска, пикселей",
	"heavy_shake_s": "тряска, с", "hit_period_s": "удар кирки каждые, с", "hit_db": "громкость удара", "fade_s": "переход музыки, с",
	"fade_story_s": "переход в сцену, с", "fade_boss_s": "переход к боссу, с", "switch_delay_s": "смена трека не раньше, с",
	"mine_from": "музыка шахты с глубины", "mine2_from": "вторая тема шахты с", "deep_from": "глубинная тема с",
	"distance_cells": "шаг каждые, клеток", "land_min_speed": "слышно приземление со скорости", "max_particles": "частиц максимум",
	"emitters": "источников частиц", "max_fliers": "летящих значков", "max_popups": "всплывающих чисел", "web_density": "частиц в вебе, доля",
	"hurt_min_hp": "«ой» от потери HP", "drip_hp": "копить мелкий урон до", "rare_price": "звук редкой добычи дороже",
	"coyote_s": "прыжок после схода с уступа, с", "jump_buffer_s": "запоминание прыжка, с", "key_last_wins": "последняя клавиша главнее",
	"poll": "проверка условий, с", "first_delay": "первая подсказка через, с", "gap": "между подсказками, с", "hold": "условие держится, с",
	"ttl": "подсказка висит, с", "lost_after": "снять, если цель пропала, с", "frac": "доля", "pct": "процент", "max": "максимум",
	"projects": "проекты по порядку", "auto_track": "трекер сам берёт проект", "max_alpha": "плотность ночи",
	"radius_min_cells": "радиус факела", "radius_extra_cells": "прибавка радиуса", "inner_cells": "яркое ядро", "warm_k": "тёплый оттенок",
	"flicker": "мерцание", "up_px": "высота дымки", "down_px": "глубина дымки",
}
# Списки, номер элемента в которых — «ступень» (а не просто №).
STEP_LISTS = {"levels", "upgrade_cost", "road", "bonuses", "per_level_tiers", "slots", "upgrade_tiers", "suit_tiers", "cycle"}


def plural(n, forms):
	n = abs(int(n))
	if n % 10 == 1 and n % 100 != 11:
		return forms[0]
	if 2 <= n % 10 <= 4 and not 12 <= n % 100 <= 14:
		return forms[1]
	return forms[2]


def n_numbers(n):
	return "%d %s" % (n, plural(n, ("число", "числа", "чисел")))


def human_key(row):
	segs = [s for s in row["segs"] if s not in ("value",)]
	if not segs:
		return row["id"]
	last = segs[-1]
	if last.startswith("["):
		inner = last[1:-1]
		if inner.isdigit():
			return "ступень %d" % (int(inner) + 1) if len(segs) >= 2 and segs[-2] in STEP_LISTS else "№%d" % (int(inner) + 1)
		return KEY_RU.get(inner, inner)
	label = KEY_RU.get(last, last.replace("_", " "))
	if last.isdigit() and len(segs) >= 2:
		return "%s, №%s" % (KEY_RU.get(segs[-2], segs[-2].replace("_", " ")), last)
	if len(segs) >= 3 and segs[-3] == "slots" and segs[-2].startswith("[") and not segs[-2][1:-1].isdigit():
		slot = {"dig": "копка", "sell": "продажа", "spend": "траты", "care": "забота", "hunt": "охота"}.get(segs[-2][1:-1], segs[-2][1:-1])
		return "слот «%s»: %s" % (slot, "множитель награды" if last == "reward" else label)
	if len(segs) >= 3 and segs[-2].startswith("[") and segs[-2][1:-1].isdigit() and segs[-3] in STEP_LISTS:
		label = "ступень %d: %s" % (int(segs[-2][1:-1]) + 1, label)
	elif len(segs) >= 2 and not segs[-2].startswith("[") and last in ("hand_drill", "drill_rig", "base", "value"):
		label = "%s: %s" % (KEY_RU.get(segs[-2], segs[-2].replace("_", " ")), label)
	return label


def row_name(m, row):
	if row["ctx"]:
		return row["ctx"][-1]
	for s in reversed(row["segs"][:-1]):
		if s.startswith("[") and not s[1:-1].isdigit():
			return m.name(s[1:-1])
	if len(row["segs"]) >= 2:
		return m.name(row["segs"][-2])
	return row["segs"][0] if row["segs"] else row["id"]


def _specificity(pattern):
	return len(pattern.replace("*", ""))


def pick_family(rid):
	best, score = None, -1
	for fam in cat.FAMILIES:
		for p in fam["match"]:
			if cat.match(p, rid) and _specificity(p) > score:
				best, score = fam, _specificity(p)
	return best


def _code_text():
	parts = []
	for path in glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True):
		try:
			with open(path, encoding="utf-8") as f:
				parts.append(f.read())
		except OSError:
			pass
	return "\n".join(parts)


def _note_title(note):
	s = re.split(r"(?<=[.;:!?])\s", note.strip(), maxsplit=1)[0]
	return (s[:97] + "…") if len(s) > 98 else s


def annotate(rows, m):
	code = _code_text()
	fams = [pick_family(r["id"]) for r in rows]
	fam_count = {}
	for f in fams:
		if f:
			fam_count[f["id"]] = fam_count.get(f["id"], 0) + 1
	for r, fam in zip(rows, fams):
		r["key_ru"] = human_key(r)
		r["value_text"] = m.value_text(r["value"], r)
		flags = []
		if fam:
			r["theme"] = fam["theme"]
			r["family"] = fam["id"]
			r["importance"] = fam["imp"]
			if callable(fam["row"]):
				r["title"] = fam["row"](m, r)
			elif fam["row"]:
				e1 = next((s[1:-1] for s in r["segs"] if s.startswith("[")), "")
				try:
					r["title"] = fam["row"].format(name=row_name(m, r), key=r["key_ru"], e1=e1)
				except (KeyError, IndexError, ValueError):
					r["title"] = fam["title"]
			else:
				r["title"] = "%s: %s" % (fam["title"], r["key_ru"]) if fam_count[fam["id"]] > 1 else fam["title"]
			last = r["segs"][-1] if r["segs"] else ""
			if (not last.startswith("[") and not last.isdigit() and last not in KEY_RU and r["note"]
					and r["title"].endswith(r["key_ru"])):
				# ключа нет в словаре — подпись из заметки агента (она по-русски), а не «lead y tau s»
				r["title"] = r["title"][: -len(r["key_ru"])] + _note_title(r["note"]).rstrip(".;:")[:70]
			r["title"] = re.sub(r"\{(n|depth_min)\}", "N", r["title"])
			if fam.get("vtext"):
				try:
					r["value_text"] = fam["vtext"](m, r) or r["value_text"]
				except Exception:
					pass
			r["unit"] = fam["unit"]
			r["affects"] = fam["affects"]
			r["reviewed"] = True
			if fam["effect"]:
				try:
					r["effect"] = fam["effect"](m, r)
				except Exception as e:  # чужие правки формы данных не должны ронять выгрузку
					r["effect"] = None
					r["effect_error"] = "%s: %s" % (type(e).__name__, e)
			if fam["flags"]:
				try:
					flags += fam["flags"](m, r) or []
				except Exception:
					pass
		else:
			r["theme"] = cat.theme_for_unknown(r)
			r["family"] = "new." + r["theme"]
			r["importance"] = 3
			name = row_name(m, r)
			r["title"] = ("%s: %s" % (name, r["key_ru"])) if name and name != r["key_ru"] else r["key_ru"]
			r["unit"] = ""
			r["affects"] = _note_title(r["note"]) if r["note"] else ""
			r["reviewed"] = False
			flags.append("новое число — в каталоге разбора его ещё нет (tools/proposed_catalog.py)")
		key = r["segs"][-1] if r["segs"] else ""
		if (r["explicit"] and len(key) >= 8 and not key.startswith("[") and key not in code
				and not any("кодом не" in f for f in flags) and not cat.is_used(r["id"])):
			flags.append("ключ «%s» не найден в scripts/ — проверить, читает ли его игра" % key)
		r["effect"] = r.get("effect") or None
		r["flags"] = flags
	return rows


def _family_value(m, rows):
	if len(rows) == 1:
		return rows[0]["value_text"]
	keys = [r["key_ru"] for r in rows]
	if len(rows) <= 4 and len(set(keys)) == len(keys):
		return "; ".join("%s %s" % (r["key_ru"], r["value_text"]) for r in rows)
	nums = [r["value"] for r in rows if isinstance(r["value"], (int, float)) and not isinstance(r["value"], bool)]
	if len(nums) == len(rows):
		return "%s, от %s до %s" % (n_numbers(len(rows)), fnum(min(nums)), fnum(max(nums)))
	return n_numbers(len(rows))


def build(rows, m):
	fam_by_id = {f["id"]: f for f in cat.FAMILIES}
	groups = {}
	for r in rows:
		groups.setdefault(r["family"], []).append(r)
	families = []
	for fid, frows in groups.items():
		f = fam_by_id.get(fid)
		entry = {"id": fid, "theme": frows[0]["theme"], "title": f["title"] if f else "Новые числа без разбора",
			"importance": f["imp"] if f else 3, "rows": [r["id"] for r in frows], "count": len(frows),
			"value_text": _family_value(m, frows), "affects": f["affects"] if f else "", "reviewed": bool(f)}
		summ = None
		if f and f["summary"]:
			try:
				summ = f["summary"](m, frows)
			except Exception:
				summ = None
		if not summ:
			eff = [r for r in frows if r.get("effect")]
			if eff:
				summ = eff[0]["effect"] if len(frows) == 1 else "%s — %s" % (eff[0]["title"], eff[0]["effect"])
		entry["effect"] = summ
		if f and f["rec"]:
			entry["verdict"], entry["why"] = f["rec"]
		else:
			entry["verdict"], entry["why"] = "решить", "число появилось после этого разбора: смотреть заметку агента"
		entry["flags"] = sorted({fl for r in frows for fl in r["flags"] if not fl.startswith("новое число")})
		families.append(entry)
	order = {t: i for i, t in enumerate(cat.THEME_ORDER)}
	families.sort(key=lambda e: (order.get(e["theme"], 99), not e["reviewed"], -e["importance"],
		[f["id"] for f in cat.FAMILIES].index(e["id"]) if e["id"] in fam_by_id else 0))
	fam_pos = {e["id"]: i for i, e in enumerate(families)}
	rows.sort(key=lambda r: (fam_pos[r["family"]], r["id"]))
	themes = []
	for t in cat.THEME_ORDER + sorted({r["theme"] for r in rows} - set(cat.THEME_ORDER)):
		trows = [r for r in rows if r["theme"] == t]
		if not trows:
			continue
		decide, rec = cat.THEME_NOTES.get(t, ([], ""))
		themes.append({"id": t, "title": cat.THEME_TITLES.get(t, t), "count": len(trows),
			"families": [e["id"] for e in families if e["theme"] == t], "decide": decide, "recommendation": rec,
			"new": sum(1 for r in trows if not r["reviewed"])})
	top = []
	for fid, text in cat.TOP:
		e = next((x for x in families if x["id"] == fid), None)
		if e:
			top.append({"family": fid, "decide": text, "now": e["value_text"], "verdict": e["verdict"]})
	return families, themes, top


# ---------------------------------------------------------------------------
# Вывод
# ---------------------------------------------------------------------------

ROW_KEYS = ("id", "file", "path", "theme", "family", "title", "value", "value_text", "unit", "note", "affects", "effect",
	"importance", "flags", "reviewed")


def write_json(path, rows, families, themes, top, sources):
	out = {
		"version": 1,
		"generated_by": "tools/proposed_numbers.py",
		"how_to_refresh": "python3 tools/proposed_numbers.py   (без Godot: --no-sims)",
		"sources": sources,
		"summary": {"rows": len(rows), "families": len(families), "new_unreviewed": sum(1 for r in rows if not r["reviewed"]),
			"flagged": sum(1 for r in rows if r["flags"]),
			"by_theme": {t["title"]: t["count"] for t in themes}},
		"top_decisions": top,
		"themes": themes,
		"families": families,
		"rows": [{k: r.get(k) for k in ROW_KEYS} for r in rows],
	}
	with open(path, "w", encoding="utf-8") as f:
		json.dump(out, f, ensure_ascii=False, indent=1)
		f.write("\n")


def _md(s):
	return (s or "—").replace("|", "/").replace("\n", " ")


def write_review(path, rows, families, themes, top, sources):
	fam = {e["id"]: e for e in families}
	L = []
	L.append("# Числа на утверждение: разбор")
	L.append("")
	L.append("Все значения с пометкой `\"proposed\": true` — их придумали агенты, владелец их ещё не утверждал. Здесь они "
		"собраны по темам: что это, сколько сейчас, чем обернётся в игре и что советую. **Числа в игре этот разбор не меняет.**")
	L.append("")
	L.append("- Всего чисел: **%d** в %d семействах; подозрительных мест: %d; новых без разбора: %d." % (
		len(rows), len(families), sum(1 for e in families if e["flags"]), sum(1 for r in rows if not r["reviewed"])))
	L.append("- Полная выгрузка (каждая строка со стабильным id `файл:путь`, заметкой агента и расчётом): `docs/numbers/proposed.json`.")
	L.append("- Обновить после любого слияния: `python3 tools/proposed_numbers.py` (без Godot — `--no-sims`). ГДД §18 «Числа».")
	L.append("- Откуда расчёты: %s." % "; ".join(sources.get("notes", [])))
	L.append("- Как ответить: «оставить» / новое число по id или по названию семейства — агент правит данные и снимает пометку.")
	L.append("")
	L.append("## Десять главных решений")
	L.append("")
	for i, t in enumerate(top, 1):
		e = fam[t["family"]]
		L.append("%d. **%s.** %s Сейчас: %s. Совет: **%s**." % (i, e["title"], t["decide"], _md(e["value_text"]), e["verdict"]))
	L.append("")
	L.append("## Сводка")
	L.append("")
	L.append("| Тема | Чисел | Совет |")
	L.append("|---|---|---|")
	for t in themes:
		L.append("| %s | %d | %s |" % (t["title"], t["count"], _md(t["recommendation"])))
	L.append("")
	for t in themes:
		L.append("## %s — %s" % (t["title"], n_numbers(t["count"])))
		L.append("")
		for d in t["decide"]:
			L.append("- %s" % d)
		if t["recommendation"]:
			L.append("- **Совет:** %s" % t["recommendation"])
		L.append("")
		big = [fam[f] for f in t["families"] if fam[f]["reviewed"] and fam[f]["importance"] >= 2]
		small = [fam[f] for f in t["families"] if fam[f]["reviewed"] and fam[f]["importance"] < 2]
		new = [fam[f] for f in t["families"] if not fam[f]["reviewed"]]
		if big:
			L.append("| Что | Сейчас | Чем обернётся | Совет |")
			L.append("|---|---|---|---|")
			for e in big:
				L.append("| %s%s | %s | %s | **%s**: %s |" % ("★ " if e["importance"] >= 5 else "", _md(e["title"]), _md(e["value_text"]),
					_md(e["effect"]), e["verdict"], _md(e["why"])))
			L.append("")
		if small:
			L.append("Мелочи (утвердить пачкой): " + "; ".join("%s (%d) — %s" % (e["title"], e["count"], e["verdict"]) for e in small) + ".")
			L.append("")
		flagged = [(r, fl) for r in rows if r["theme"] == t["id"] and r["reviewed"] for fl in r["flags"]]
		if flagged:
			L.append("Подозрительные места:")
			by_text = {}
			for r, fl in flagged:
				by_text.setdefault(fl, []).append(r)
			for fl, rs in by_text.items():
				more = " (и ещё %d)" % (len(rs) - 1) if len(rs) > 1 else ""
				L.append("- %s (`%s`%s) — %s" % (rs[0]["title"], rs[0]["id"], more, fl))
			L.append("")
		if new:
			L.append("Новые числа без разбора (появились после этого разбора — смотреть заметку агента в proposed.json):")
		for e in new:
			for rid in e["rows"]:
				r = next(x for x in rows if x["id"] == rid)
				L.append("- `%s` = %s — %s" % (rid, _md(r["value_text"]), _md(r["affects"] or r["note"])))
			L.append("")
	with open(path, "w", encoding="utf-8") as f:
		f.write("\n".join(L).rstrip() + "\n")


def main(argv=None):
	ap = argparse.ArgumentParser(description="Выгрузка proposed-чисел для разбора владельцем")
	ap.add_argument("--no-sims", action="store_true", help="не запускать Godot: взять прошлые итоги симуляторов")
	ap.add_argument("--bot", help="каталог ночных прогонов ботов (build/bot): освежить docs/numbers/bot_anchors.json")
	ap.add_argument("--out", default=OUT_DIR, help="куда писать proposed.json и REVIEW.md")
	ap.add_argument("--data", default=DATA_DIR, help=argparse.SUPPRESS)
	ap.add_argument("--seeds", type=int, default=4, help="сидов на прогон sim_economy")
	args = ap.parse_args(argv)
	os.makedirs(args.out, exist_ok=True)
	notes = []
	fp = data_fingerprint(args.data)

	sims_path = os.path.join(OUT_DIR, "sims.json")
	sims = None
	if not args.no_sims:
		sims, err = run_sims(args.seeds)
		if sims:
			sims["data_fingerprint"] = fp
			if os.path.abspath(args.out) == os.path.abspath(OUT_DIR):
				with open(sims_path, "w", encoding="utf-8") as f:
					json.dump(sims, f, ensure_ascii=False, indent=1)
					f.write("\n")
			notes.append("симуляторы sim_economy.gd (серпантин, дайв, без артефактов; %d сида) и sim_daily.gd — запущены сейчас" % args.seeds)
		else:
			notes.append("симуляторы не запускались (%s)" % err)
	if sims is None and os.path.exists(sims_path):
		with open(sims_path, encoding="utf-8") as f:
			sims = json.load(f)
		stale = sims.get("data_fingerprint") != fp
		notes.append("итоги симуляторов из docs/numbers/sims.json%s" % (" (данные с тех пор менялись — перезапустить без --no-sims)" if stale else ""))

	bots_path = os.path.join(OUT_DIR, "bot_anchors.json")
	bots = None
	if args.bot:
		bots = summarize_bots(args.bot)
		if bots and os.path.abspath(args.out) == os.path.abspath(OUT_DIR):
			with open(bots_path, "w", encoding="utf-8") as f:
				json.dump(bots, f, ensure_ascii=False, indent=1)
				f.write("\n")
	if bots is None and os.path.exists(bots_path):
		with open(bots_path, encoding="utf-8") as f:
			bots = json.load(f)
	if bots:
		notes.append("итоги ботов: %d прогонов, %s игровых часов, сборка %s (docs/numbers/bot_anchors.json)" % (
			len(bots.get("runs", [])), fnum(bots.get("game_hours")), ", ".join(bots.get("builds", []))))
	m = Model(args.data, sims, bots)
	notes.append("tools/sim_tech.py — доход и окупаемость по глубине" if m.st else "tools/sim_tech.py не загрузился (%s)" % m.st_error)

	rows = Extractor(args.data).run()
	annotate(rows, m)
	families, themes, top = build(rows, m)
	sources = {"data_fingerprint": fp, "notes": notes}
	write_json(os.path.join(args.out, "proposed.json"), rows, families, themes, top, sources)
	write_review(os.path.join(args.out, "REVIEW.md"), rows, families, themes, top, sources)
	print("[proposed_numbers] %d чисел, %d семейств, новых без разбора: %d -> %s" % (
		len(rows), len(families), sum(1 for r in rows if not r["reviewed"]), os.path.relpath(args.out, ROOT)))
	for t in themes:
		print("  %-58s %4d" % (t["title"], t["count"]))
	return 0


if __name__ == "__main__":
	sys.exit(main())

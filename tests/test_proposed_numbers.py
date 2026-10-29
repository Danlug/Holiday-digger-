#!/usr/bin/env python3
"""Тест выгрузки proposed-чисел (tools/proposed_numbers.py), без Godot, ~5 с.

  python3 tests/test_proposed_numbers.py

Проверяет: выгрузка не пуста; у каждой строки есть id, значение и тема; id уникальны и не меняются между
запусками; REVIEW.md написан; новое proposed-число из чужой ветки (новый файл данных) попадает в выгрузку
само — с темой и пометкой «без разбора»; чужая правка формы данных не роняет инструмент.
"""

import json
import re
import os
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import proposed_catalog as cat  # noqa: E402
import proposed_numbers as pn  # noqa: E402

checks = 0
fails = 0


def check(name, ok):
	global checks, fails
	checks += 1
	if not ok:
		fails += 1
		print("[FAIL] " + name)


def run(out, data=None):
	argv = ["--no-sims", "--out", out]
	if data:
		argv += ["--data", data]
	code = pn.main(argv)
	with open(os.path.join(out, "proposed.json"), encoding="utf-8") as f:
		return code, json.load(f)


tmp = tempfile.mkdtemp(prefix="test_proposed_")
try:
	code, a = run(os.path.join(tmp, "a"))
	_, b = run(os.path.join(tmp, "b"))
	rows = a["rows"]
	check("код возврата 0", code == 0)
	check("выгрузка не пуста (> 300 строк)", len(rows) > 300)
	check("у каждой строки есть id, значение и тема", all(r.get("id") and "value" in r and r.get("value_text") and r.get("theme") for r in rows))
	check("тема каждой строки — из списка тем", all(r["theme"] in cat.THEME_TITLES for r in rows))
	check("у каждой строки есть подпись по-русски", all(r.get("title") for r in rows))
	ids = [r["id"] for r in rows]
	check("id уникальны", len(ids) == len(set(ids)))
	check("id вида «файл.json:путь»", all(":" in i and i.split(":", 1)[0].endswith(".json") for i in ids))
	check("id стабильны между запусками", ids == [r["id"] for r in b["rows"]])
	check("значения те же между запусками", [r["value"] for r in rows] == [r["value"] for r in b["rows"]])
	check("элементы списков названы по id, а не по номеру", "artifacts.json:artifacts[antiquity_2].find_bonus.xp" in ids
		or any(re.search(r"\[[a-z][a-z_0-9]*\]", i) for i in ids))
	check("общий proposed файла разбит на строки (quests.json)", sum(1 for i in ids if i.startswith("quests.json:")) > 20)
	check("числа владельца не выгружаются (ориентиры заданий)", not any("owner_anchor" in i for i in ids))
	check("proposed: false не выгружается", not any(i.startswith("balance.json:fuel_consumption.peat_per_fuel_block") for i in ids))
	check("каждое семейство каталога в выгрузке разобрано", all(r["reviewed"] for r in rows))
	check("темы с советом и «что решить»", all(t["recommendation"] and t["decide"] for t in a["themes"]))
	check("десять главных решений", len(a["top_decisions"]) == 10)
	check("REVIEW.md написан", os.path.getsize(os.path.join(tmp, "a", "REVIEW.md")) > 2000)
	with open(os.path.join(tmp, "a", "REVIEW.md"), encoding="utf-8") as f:
		review = f.read()
	check("REVIEW.md: главные решения и все темы", "Десять главных решений" in review and all(t["title"] in review for t in a["themes"]))
	# семейства уходят из выгрузки, когда владелец их одобряет, — проверяем «главные» из текущей десятки
	top_ids = [t["family"] for t in a["top_decisions"]]
	check("есть расчёт «чем обернётся» у большинства главных семейств",
		sum(1 for fid in top_ids if any(e["id"] == fid and e.get("effect") for e in a["families"])) * 2 >= len(top_ids))

	# Параллельные ветки: новый файл с proposed-числами и чужая правка формы данных.
	data = os.path.join(tmp, "data")
	shutil.copytree(pn.DATA_DIR, data)
	# Файл, которого ещё нет в data/ (настоящий caves.json уже влит и разобран в каталоге).
	with open(os.path.join(data, "monster_lairs.json"), "w", encoding="utf-8") as f:
		json.dump({"proposed": True, "shapes": {"star": {"guards": 3, "chest_value_cells": 20}},
			"min_depth": {"value": 1500, "proposed": True, "note": "логова с монстрами с 1500 (пример новой ветки)"}}, f)
	with open(os.path.join(data, "tech.json"), encoding="utf-8") as f:
		tech = json.load(f)
	tech["well"]["levels"]["value"] = [{"depth_cap": 200, "cells_per_hour": 35, "cap_hours": 8, "cost": None}]
	with open(os.path.join(data, "tech.json"), "w", encoding="utf-8") as f:
		json.dump(tech, f)
	code, c = run(os.path.join(tmp, "c"), data)
	new = {r["id"]: r for r in c["rows"] if not r["reviewed"]}
	check("после правки формы данных инструмент не падает", code == 0)
	check("новое число из новой ветки попало в выгрузку", "monster_lairs.json:min_depth" in new and "monster_lairs.json:shapes.star.guards" in new)
	check("новое число получило тему «Бой»", new.get("monster_lairs.json:min_depth", {}).get("theme") == "combat")
	check("новое число видно в REVIEW.md", "monster_lairs.json:min_depth" in open(os.path.join(tmp, "c", "REVIEW.md"), encoding="utf-8").read())
	check("старые id не поплыли от нового файла", set(ids) - {i for i in ids if i.startswith("tech.json:well.levels")} <= {r["id"] for r in c["rows"]})
finally:
	shutil.rmtree(tmp, ignore_errors=True)

print("=== Итог: %d проверок, %d провалов ===" % (checks, fails))
sys.exit(1 if fails else 0)

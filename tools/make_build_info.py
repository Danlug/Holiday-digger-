#!/usr/bin/env python3
"""Штамп сборки: data/build_info.json.

Зачем. Владелец несколько раз открывал игру и не видел изменений, а по
переписке нельзя было отличить «раздача отстала» от «браузер отдал старую
копию из кэша». Теперь версия видна прямо в игре (меню «•••»), и один
взгляд отвечает на вопрос.

Тот же идентификатор уходит в веб-страницу (tools/stamp_web_build.py) как
метка для сброса кэша, поэтому он обязан считаться ОДИН раз и лежать в
файле, а не вычисляться дважды по времени запуска.

Запуск: python3 tools/make_build_info.py   (перед экспортом)
"""
import json
import pathlib
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "build_info.json"


def _commit() -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        # Сборка из архива без .git — не повод падать: метка времени
        # остаётся, а она и отвечает на вопрос «свежая ли это сборка».
        return ""


def main() -> None:
    stamp = time.strftime("%Y%m%d-%H%M", time.gmtime())
    info = {
        "build": stamp,
        "commit": _commit(),
        "_note": "Пишется tools/make_build_info.py перед экспортом. Показывается в меню «•••» (scripts/ui/hud.gd) и служит меткой сброса кэша в веб-странице (tools/stamp_web_build.py).",
    }
    OUT.write_text(json.dumps(info, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {stamp} {info['commit']}")


if __name__ == "__main__":
    main()

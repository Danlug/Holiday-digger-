#!/usr/bin/env python3
"""Разбор прогона бота-игрока (tools/bot_play.sh → tests/bot_play.gd).

    python3 tools/bot_report.py <каталог_прогона>     # дописать log-разбор в telemetry.json, summary.txt
    python3 tools/bot_report.py --merge <каталог>     # сводная таблица по всем s*_* внутри

Лог: SCRIPT ERROR / ERROR / WARNING / Parse Error / падения движка — с первыми строками.
Итог — короткий текст: вехи, деньги, смерти, застревания, находки по приоритету, скука, кадр.
"""
import json
import os
import re
import sys

ERR_PATTERNS = [
    ("script_error", re.compile(r"SCRIPT ERROR")),
    ("parse_error", re.compile(r"Parse Error")),
    ("error", re.compile(r"^ERROR:")),
    ("warning", re.compile(r"^WARNING:")),
    ("crash", re.compile(r"Program crashed|handle_crash|Segmentation fault|signal 11|Aborted")),
    ("invalid", re.compile(r"Invalid (call|access|get|set|operands)")),
]
# Шум движка, не относящийся к игре (как LOG_ALLOW в test_bot_onboarding).
ALLOW = [
    re.compile(r"story_en\.json"),
    re.compile(r"ObjectDB instances leaked"),
    re.compile(r"resources still in use at exit"),
    # звук под xvfb без звуковой карты — окружение, не игра
    re.compile(r"audio_driver_alsa|All audio drivers failed|init_output_device|pulseaudio", re.I),
    re.compile(r"V-Sync mode"),
]

MILESTONES = [
    ("onboarding_done", "онбординг пройден"),
    ("first_sale", "первая продажа"),
    ("buy:backpack", "ранец куплен"),
    ("buy:iron_pickaxe", "железная кирка"),
    ("buy:titanium_pickaxe", "титановая кирка"),
    ("buy:backpack_plus", "улучшенный ранец"),
    ("buy:jetpack", "джетпак"),
    ("buy:platinum_pickaxe", "платиновая кирка"),
    ("buy:diamond_pickaxe", "алмазная кирка"),
    ("buy:jetpack_top", "топовый джетпак"),
    ("buy:obsidian_pickaxe", "обсидиановая кирка"),
    ("depth_50", "глубина 50"),
    ("depth_100", "глубина 100"),
    ("depth_200", "глубина 200"),
    ("depth_500", "глубина 500"),
    ("depth_1000", "глубина 1000"),
    ("first_artifact", "первый артефакт"),
    ("scene:grave_call", "сцена «звонок у могилы»"),
    ("scene:diary_first", "дневник"),
    ("scene:depth_100", "сцена глубины 100"),
    ("scene:fever_500", "сцена глубины 500"),
    ("craft:hand_drill", "ручной бур"),
    ("first_refuel", "первая заправка"),
    ("craft:well", "скважина"),
    ("first_sleep", "первый сон"),
    ("first_quest_claim", "первое задание забрано"),
]


def mmss(t):
    t = float(t)
    return "%d:%02d" % (int(t // 60), int(t % 60))


def scan_log(path):
    out = {k: [] for k, _ in ERR_PATTERNS}
    if not os.path.exists(path):
        return out, 0
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    for i, line in enumerate(lines):
        ctx_all = " ".join(lines[i:i + 3])
        if any(a.search(ctx_all) for a in ALLOW):
            continue
        for kind, rx in ERR_PATTERNS:
            if rx.search(line):
                ctx = " | ".join(x.strip() for x in lines[i:i + 3])
                out[kind].append(ctx[:400])
                break
    return out, len(lines)


def dedupe(items, n=8):
    seen = {}
    for x in items:
        k = re.sub(r"\d+", "#", x)[:160]
        seen.setdefault(k, [x, 0])
        seen[k][1] += 1
    rows = sorted(seen.values(), key=lambda r: -r[1])
    return [{"line": r[0], "count": r[1]} for r in rows[:n]]


def summarize(run_dir):
    tpath = os.path.join(run_dir, "telemetry.json")
    log = os.path.join(run_dir, "log.txt")
    code = open(os.path.join(run_dir, "exit_code")).read().strip() if os.path.exists(os.path.join(run_dir, "exit_code")) else "?"
    errs, nlines = scan_log(log)
    tel = {}
    if os.path.exists(tpath):
        try:
            tel = json.load(open(tpath, encoding="utf-8"))
        except Exception as e:  # noqa: BLE001 — сломанный JSON — это тоже находка
            tel = {"meta": {}, "findings": [{"sev": "P0", "kind": "telemetry", "text": "telemetry.json не читается: %s" % e, "t": 0, "count": 1}]}
    else:
        tel = {"meta": {}, "findings": [{"sev": "P0", "kind": "no_telemetry", "text": "бот не записал телеметрию (падение/таймаут?), код %s" % code, "t": 0, "count": 1}]}
    tel["log"] = {k: dedupe(v) for k, v in errs.items()}
    tel["log_counts"] = {k: len(v) for k, v in errs.items()}
    tel["exit_code"] = code
    if errs["script_error"] or errs["parse_error"] or errs["crash"]:
        tel.setdefault("findings", []).insert(0, {"sev": "P0" if errs["crash"] else "P1", "kind": "log_errors",
            "text": "в логе: SCRIPT ERROR %d, Parse Error %d, падений %d" % (len(errs["script_error"]), len(errs["parse_error"]), len(errs["crash"])),
            "t": 0, "count": 1})
    if os.path.exists(tpath) or tel.get("meta"):
        json.dump(tel, open(tpath, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    m = tel.get("meta", {})
    ms = tel.get("milestones", {})
    L = []
    L.append("Бот-игрок: сид %s, характер %s, %s игровых мин (%s игровых суток) за %s с настенных (×%s), код %s" % (
        m.get("seed"), m.get("character"), round(float(m.get("sim_seconds", 0)) / 60, 1), m.get("game_days"),
        m.get("wall_seconds"), m.get("speedup"), code))
    es = m.get("end_state", {})
    if es:
        L.append("Итог: глубина %s, монеты %s, уровень %s, кирка %s, ранец %s, артефактов %s, скважина %s" % (
            es.get("max_depth"), es.get("coins"), es.get("level"), es.get("tool"), es.get("gear") or "—", es.get("artifacts"), es.get("well_level")))
    L.append("Доход %s монет/ч продажами; на еду %s из %s; следующая цель: %s" % (
        m.get("income_per_hour"), m.get("coins_on_food"), m.get("coins_earned"), json.dumps(m.get("next_goal", {}), ensure_ascii=False)))
    got = ["%s %s" % (name, mmss(ms[k])) for k, name in MILESTONES if k in ms]
    L.append("Вехи: " + ("; ".join(got) if got else "нет"))
    deaths = tel.get("deaths", [])
    if deaths:
        L.append("Смерти (%d): %s" % (len(deaths), "; ".join("%s %s гл.%s −%s" % (mmss(d["t"]), d["cause"], d["depth"], d.get("lost_value", 0)) for d in deaths[:8])))
    trips = tel.get("trips", [])
    if trips:
        avg = sum(float(t.get("end", 0)) - float(t.get("start", 0)) for t in trips) / len(trips)
        reasons = {}
        for t in trips:
            r = t.get("return_reason", t.get("reason", "?"))
            reasons[r] = reasons.get(r, 0) + 1
        L.append("Ходок %d, средняя %s, причины возврата: %s" % (len(trips), mmss(avg), reasons))
    act = tel.get("activity_seconds", {})
    tot = sum(act.values()) or 1
    L.append("Время: " + ", ".join("%s %d%%" % (k, round(100 * v / tot)) for k, v in sorted(act.items(), key=lambda kv: -kv[1])))
    fr = tel.get("frame", {})
    if fr:
        L.append("Кадр (CPU, headless): p50 %s мс, p95 %s, p99 %s, max %s; всплесков >50 мс: %s" % (
            fr.get("p50_ms"), fr.get("p95_ms"), fr.get("p99_ms"), fr.get("max_ms"), fr.get("spikes_over_50_ms")))
    bor = tel.get("boring", [])
    if bor:
        L.append("Скучно (≥8 мин без событий): " + "; ".join("%s–%s (%s мин, гл. %s→%s)" % (
            mmss(b["from"]), mmss(b["to"]), b["minutes"], b["context"].get("max_depth_from"), b["context"].get("max_depth_to")) for b in bor[:6]))
    lc = tel.get("log_counts", {})
    L.append("Лог: SCRIPT ERROR %s, ERROR %s, WARNING %s, Parse %s, падений %s" % (
        lc.get("script_error", 0), lc.get("error", 0), lc.get("warning", 0), lc.get("parse_error", 0), lc.get("crash", 0)))
    for kind in ("script_error", "error", "warning", "crash"):
        for row in tel["log"].get(kind, [])[:4]:
            L.append("   %s ×%d: %s" % (kind, row["count"], row["line"][:220]))
    f = tel.get("findings", [])
    order = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
    f = sorted(f, key=lambda x: (order.get(x.get("sev"), 9), float(x.get("t", 0))))
    L.append("Находки (%d):" % len(f))
    for x in f[:30]:
        L.append("  [%s] %s: %s (×%s, %s)" % (x.get("sev"), x.get("kind"), x.get("text"), x.get("count", 1), mmss(x.get("t", 0))))
    text = "\n".join(L) + "\n"
    open(os.path.join(run_dir, "summary.txt"), "w", encoding="utf-8").write(text)
    return text, tel


def merge(base):
    rows = []
    for d in sorted(os.listdir(base)):
        p = os.path.join(base, d, "telemetry.json")
        if not os.path.exists(p):
            continue
        tel = json.load(open(p, encoding="utf-8"))
        m = tel.get("meta", {})
        es = m.get("end_state", {})
        ms = tel.get("milestones", {})
        p0 = sum(1 for x in tel.get("findings", []) if x.get("sev") == "P0")
        rows.append("%-22s %6.1f мин  гл.%5s  монеты %7s  смертей %2d  P0 %d  кирка50:%s гл100:%s гл500:%s гл1000:%s" % (
            d, float(m.get("sim_seconds", 0)) / 60, es.get("max_depth"), es.get("coins"), len(tel.get("deaths", [])), p0,
            mmss(ms["buy:iron_pickaxe"]) if "buy:iron_pickaxe" in ms else "—",
            mmss(ms["depth_100"]) if "depth_100" in ms else "—",
            mmss(ms["depth_500"]) if "depth_500" in ms else "—",
            mmss(ms["depth_1000"]) if "depth_1000" in ms else "—"))
    print("СВОДКА")
    print("\n".join(rows))


def md_table(dirs):
    """Строки таблицы для docs/PLAYTEST.md по каталогам прогонов (s<сид>_<характер>)."""
    head = ("| Прогон | Ввод | Игровых мин | Глубина | Кирка / ранец в конце | Доход, монет/ч | Железная кирка | "
            "Глубина 100 / 200 / 500 / 1000 | Смертей | Застреваний (P0) | Подъём, % времени |")
    out = [head, "|" + "---|" * 11]
    for d in dirs:
        p = os.path.join(d, "telemetry.json")
        if not os.path.exists(p):
            continue
        tel = json.load(open(p, encoding="utf-8"))
        m = tel.get("meta", {})
        es = m.get("end_state", {})
        ms = tel.get("milestones", {})
        act = tel.get("activity_seconds", {})
        tot = sum(act.values()) or 1
        p0 = sum(1 for x in tel.get("findings", []) if x.get("sev") == "P0")
        deaths = sum(1 for x in tel.get("deaths", []) if not x.get("scripted"))
        def at(k):
            return mmss(ms[k]) if k in ms else "—"
        out.append("| %s | %s | %d | %s | %s / %s | %s | %s | %s / %s / %s / %s | %d | %d | %d%% |" % (
            os.path.basename(d.rstrip("/")), m.get("input", "keys"), round(float(m.get("sim_seconds", 0)) / 60),
            es.get("max_depth"), es.get("tool"), es.get("gear") or "—", m.get("income_per_hour"), at("buy:iron_pickaxe"),
            at("depth_100"), at("depth_200"), at("depth_500"), at("depth_1000"), deaths, p0,
            round(100 * act.get("ascend", 0) / tot)))
    print("\n".join(out))


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--md":
        md_table(sys.argv[2:])
    elif len(sys.argv) >= 3 and sys.argv[1] == "--merge":
        merge(sys.argv[2])
    elif len(sys.argv) >= 2:
        txt, _ = summarize(sys.argv[1])
        print(txt)
    else:
        print(__doc__)
        sys.exit(2)

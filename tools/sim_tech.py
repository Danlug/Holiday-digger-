#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sim_tech.py — расчёт баланса ветки «Техника» (ГДД п.18 «цена ступеней»).

Считает на настоящих данных проекта (world_layers.json, minerals.json,
balance.json, tech.json), как генератор мира:
  * ожидаемая выручка и время одной клетки на глубине D (руды проверяются по
    списку, первая совпавшая забирает клетку — ровно как _generate_layered);
  * выручка в час АКТИВНОЙ игры (с учётом рюкзака и подъёма);
  * доход скважины в час и окупаемость её ступеней;
  * цена ступеней костюма и баков в «вылазках» и часах активной игры;
  * расход топлива: сколько клеток держит бак и хватает ли добытого топлива.

Запуск:  python3 tools/sim_tech.py            (таблицы в stdout)
         python3 tools/sim_tech.py --check    (ненулевой код, если нарушены границы
                                               из tests/test_tech_balance.gd)
Числа — предложения (proposed); скрипт показывает, где они не сходятся.
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name):
    with open(os.path.join(ROOT, "data", name), encoding="utf-8") as f:
        return json.load(f)


def unwrap(n):
    return n["value"] if isinstance(n, dict) and "value" in n else n


LAYERS = load("world_layers.json")
MIN = {m["id"]: m for m in load("minerals.json")["minerals"]}
BAL = load("balance.json")
TECH = load("tech.json")

ORE_TILE_TO_ID = {o["id"]: o for o in LAYERS["ores"]}


def price(mid):
    p = unwrap(MIN[mid].get("price_coins", 0))
    return int(p) if p else 0


def weight(mid):
    return float(unwrap(MIN[mid].get("weight_kg", 0)) or 0)


def drill_s(mid):
    d = unwrap(MIN[mid].get("drill_seconds", 3.0))
    return float(d) if d else 3.0


def density(ore, y):
    if y < ore.get("y_min", 0):
        return 0.0
    if "y_max" in ore and y > ore["y_max"]:
        return 0.0
    curve = ore.get("curve", "")
    if curve == "parabola":
        ymin = ore["y_min"]
        peak_y = ore.get("peak_y", ymin)
        peak, tail = ore["peak"], ore["tail"]
        width = (peak_y - ymin) if y <= peak_y else ore.get("fall_width", 1.0)
        if width <= 0:
            return max(peak, tail)
        t = (y - peak_y) / width
        return max(peak * (1.0 - t * t), tail)
    if curve == "ramp" or "ramp_end_y" in ore:
        ymin, re = ore["y_min"], ore.get("ramp_end_y", ore["y_min"])
        t = min(max((y - ymin) / (re - ymin), 0.0), 1.0) if re > ymin else 0.0
        return ore["density_start"] + (ore["density_end"] - ore["density_start"]) * t
    return ore.get("density", 0.0)


def cell_mix(y):
    """Вероятности типа клетки на глубине y: {id: p}, плюс 'void', 'stone', 'earth'."""
    deep = LAYERS["deep"]
    void = deep["void_chance"]
    out = {"void": void}
    left = 1.0 - void
    for ore in LAYERS["ores"]:
        d = density(ore, y)
        out[ore["id"]] = left * d
        left *= (1.0 - d)
    st = left * deep["stone_chance"]
    out["stone"] = st
    out["earth"] = left - st
    return out


def tool_speed(tool):
    best = max(unwrap(t.get("speed_multiplier", 0)) for t in BAL["tools"].values()
               if isinstance(t, dict) and t.get("line") == "pickaxe")
    if tool == "pick":
        return best
    hand = best * float(BAL["tools"]["hand_drill"]["speed_vs_best_pickaxe"])
    if tool == "hand_drill":
        return hand
    return hand * float(BAL["tools"]["drill_rig"]["speed_vs_hand_drill"])


GLOBAL = float(BAL["digging"]["global_speed_multiplier"])


# Фазы игры (ГДД п.5, п.6): чем копает и сколько несёт на этой глубине. Накладные
# секунды на клетку — ходьба, прицеливание, падение; их НЕ видно в таблицах скоростей,
# но именно они дают замеренные владельцем «~1000 клеток в час» у кирки (ГДД п.18).
PHASES = [
    # (до глубины, инструмент, рюкзак кг, подъём клеток/с, накладные с/клетку)
    (100, "pick", 60.0, 2.5, 1.8),
    (1000, "hand_drill", 100.0, 3.0, 1.5),
    (10 ** 9, "drill_rig", 260.0, 15.0, 0.6),
]


def phase(y):
    for upto, tool, carry, climb, over in PHASES:
        if y < upto:
            return tool, carry, climb, over
    return PHASES[-1][1:]


def per_cell(y, tool=None, dig_stage=8):
    """(монет на клетку, кг на клетку, секунд копки на клетку) — усреднено по всем клеткам, пустоты не копаются."""
    tool = tool or phase(y)[0]
    mix = cell_mix(y)
    coins = kg = secs = 0.0
    speed = tool_speed(tool) * GLOBAL / (0.96 ** dig_stage)
    for k, p in mix.items():
        if k == "void":
            continue
        if k == "earth":
            secs += p * 3.0 / speed
            continue
        if k == "stone":
            secs += p * 10.0 / speed
            continue
        if k not in MIN:
            continue
        coins += p * price(k)
        kg += p * weight(k)
        secs += p * drill_s(k) / speed
    return coins, kg, secs


def cells_per_hour(y):
    tool, _, _, over = phase(y)
    _, _, s = per_cell(y, tool)
    return 3600.0 / (s + over)


def active_coins_per_hour(y):
    """Вылазка: копаем до полного рюкзака, поднимаемся, продаём. (монет за вылазку, минут, монет/час)."""
    tool, carry, climb, over = phase(y)
    c, k, s = per_cell(y, tool)
    if k <= 0:
        return 0.0, 0.0, 0.0
    cells = carry / k
    trip = cells * (s + over) + 2.0 * y / climb + 60.0
    coins = cells * c
    return coins, trip / 60.0, coins / (trip / 3600.0)


def hours_for(item_id, qty, y):
    """Часов активной игры на глубине y, чтобы накопать qty единиц руды item_id (по плотности породы и темпу клеток)."""
    p = cell_mix(y).get(item_id, 0.0)
    if p <= 0:
        return float("inf")
    return qty / (cells_per_hour(y) * p)


def sellable_coins_per_cell(y):
    """Как IdleWell.coins_per_cell: доля клеток × цена по продаваемым добываемым рудам."""
    mix = cell_mix(y)
    total = 0.0
    for k, p in mix.items():
        if k in ("void", "stone", "earth") or k not in MIN:
            continue
        if MIN[k].get("category") == "crafted" or MIN[k].get("density") is None:
            continue
        total += p * price(k)
    return total


def well_rate(level, depth):
    lv = unwrap(TECH["well"]["levels"])[level - 1]
    return lv["cells_per_hour"] * sellable_coins_per_cell(max(min(depth, lv["depth_cap"]), 1))


def mat_value(mid):
    """Цена материала в монетах для окупаемости: продаваемое — по цене скупки, экзотика без цены — как 600
    (примерно рубин: добыча руками идёт долго, 12–24 с на клетку)."""
    p = price(mid)
    return p if p > 0 else 600


def cost_value(cost):
    if not cost:
        return 0
    return cost.get("coins", 0) + sum(mat_value(i) * n for i, n in cost.get("items", {}).items())


def main():
    check = "--check" in sys.argv
    bad = []

    print("== Активный заработок (инструмент и рюкзак по фазе игры) и скважина ==")
    print("%6s %9s %7s %9s %9s %11s | %10s %10s" % ("глуб", "монет/кл", "кг/кл", "с копки", "клеток/ч", "монет/час", "скв L1 /ч", "скв макс /ч"))
    levels = unwrap(TECH["well"]["levels"])
    for y in (100, 300, 600, 1000, 1500, 2000, 3000, 4000, 5000, 6000):
        c, k, s = per_cell(y)
        _, _, ph = active_coins_per_hour(y)
        print("%6d %9.1f %7.2f %9.2f %9.0f %11.0f | %10.0f %10.0f" % (y, c, k, s, cells_per_hour(y), ph,
              well_rate(1, y), well_rate(len(levels), y)))

    print("\n== Ступени скважины: окупаемость ==")
    print("%3s %9s %9s %10s %12s %12s %12s" % ("ур", "цена", "глубина", "доход/ч", "прирост/ч", "окупаемость", "активн/ч"))
    prev_rate = None
    for i, lv in enumerate(levels, start=1):
        depth = lv["depth_cap"]
        rate = well_rate(i, depth)
        cost = cost_value(lv["cost"]) if lv["cost"] else cost_value({"coins": unwrap(BAL["idle_well"]["build_cost"])["coins"],
                                                                      "items": {k: v for k, v in unwrap(BAL["idle_well"]["build_cost"]).items() if k != "coins"}})
        gain = rate - (well_rate(i - 1, levels[i - 2]["depth_cap"]) if i > 1 else 0)
        # окупаемость — в сутках офлайна при двух забораах в сутки по 8-часовому окну
        eff = min(lv["cap_hours"], 8.0) * 2
        payback_days = cost / max(gain * eff, 1.0) if i > 1 else cost / max(rate * eff, 1.0)
        _, _, active = active_coins_per_hour(depth)
        print("%3d %9d %9d %10.0f %12.0f %9.1f дн %12.0f" % (i, cost, depth, rate, gain, payback_days, active))
        if i > 1 and not (0.3 <= payback_days <= 12):
            bad.append("скважина L%d: окупаемость %.1f дн вне 0.3–12" % (i, payback_days))
        prev_rate = rate

    print("\n== Скважина против активной игры (один офлайн-заход, кап часов) ==")
    for i in (1, 3, 5, 7, 10):
        lv = levels[i - 1]
        d = lv["depth_cap"]
        well_run = well_rate(i, d) * lv["cap_hours"]
        _, _, act = active_coins_per_hour(d)
        print("L%-2d глубина %5d: за кап %2dч скважина даёт %8.0f; час активной игры на этой глубине — %8.0f (отношение %.2f ч)"
              % (i, d, lv["cap_hours"], well_run, act, well_run / max(act, 1.0)))
        if well_run / max(act, 1.0) > 5.5:
            bad.append("скважина L%d: заход за кап стоит %.1f часов активной игры (>5.5)" % (i, well_run / act))

    print("\n== Костюм: цена ступени в часах активной игры на её глубине ==")
    print("%3s %9s %7s %12s %12s %14s" % ("ст", "монет", "глубина", "монеты, ч", "материалы, ч", "итого, ч"))
    for i, t in enumerate(unwrap(TECH["heat"]["suit_tiers"]), start=1):
        d = t["unlock_depth"]
        _, _, ph = active_coins_per_hour(d)
        coins_h = t["cost"]["coins"] / max(ph, 1)
        mats_h = max(hours_for(m, n, d + (200 if d >= 3000 else 0)) for m, n in t["cost"]["items"].items())
        total = coins_h + mats_h
        print("%3d %9d %7d %12.2f %12.2f %14.2f" % (i, t["cost"]["coins"], d, coins_h, mats_h, total))
        if not (0.8 <= total <= 8):
            bad.append("костюм T%d: %.1f ч активной игры вне 0.8–8" % (i, total))

    print("\n== Бак: ёмкость, ход и самообеспечение топливом ==")
    fc = BAL["fuel_consumption"]
    for tool, label, speed_tool in (("hand_drill", "ручной бур", "hand_drill"), ("drill_rig", "бурмобиль", "drill_rig")):
        rate = float(unwrap(fc["blocks_per_cell"][tool]))
        caps = unwrap(TECH["fuel"]["tanks"][tool]["capacity_blocks"])
        costs = unwrap(TECH["fuel"]["tanks"][tool]["upgrade_cost"])
        print(label, "— блоков на клетку:", rate, "(клеток на блок: %d)" % round(1 / rate))
        for lvl, cap in enumerate(caps):
            cells = cap / rate
            line = "  бак %d: %2d блоков = %4d клеток" % (lvl, cap, cells)
            if lvl > 0:
                line += ", цена %6d монет + материалы (в вылазках на глубине 600: %.2f)" % (
                    cost_value(costs[lvl - 1]), cost_value(costs[lvl - 1]) / max(active_coins_per_hour(600)[0], 1))
            print(line)
    # Самообеспечение: сколько блоков даёт порода на клетку и какую долю копки приходится
    # тратить на добор топлива (блок = 4 торфа или 2 угля).
    print("  добор топлива (блоков добывается на клетку / тратится; лишняя копка ради добора):")
    for y, tool in ((200, "hand_drill"), (450, "hand_drill"), (900, "hand_drill"), (1100, "drill_rig"), (1500, "drill_rig"), (3000, "drill_rig")):
        mix = cell_mix(y)
        peat_b = mix.get("peat", 0) / float(fc["peat_per_fuel_block"])
        coal_b = mix.get("coal", 0) / float(unwrap(fc["coal_per_fuel_block"]))
        blocks = peat_b + coal_b
        spend = float(unwrap(fc["blocks_per_cell"][tool]))
        deficit = max(0.0, spend - blocks)
        # лишняя копка: клеток топливной руды, чтобы покрыть дефицит одной клетки (блоков на копку топлива)
        yield_per_fuel_cell = (1.0 / float(fc["peat_per_fuel_block"])) if peat_b >= coal_b else (1.0 / float(unwrap(fc["coal_per_fuel_block"])))
        fuel_share = (peat_b if peat_b >= coal_b else coal_b) / max(blocks, 1e-9) if blocks else 0
        p_fuel = mix.get("peat" if peat_b >= coal_b else "coal", 0)
        extra = deficit / yield_per_fuel_cell / max(p_fuel, 1e-9) if p_fuel > 0 else float("inf")
        print("    глубина %4d, %-10s: %.3f / %.3f -> %s" % (y, tool, blocks, spend,
              "хватает с запасом" if deficit == 0 else "добирать: +%.0f%% копки (в пласте торфа 450–455 — быстрее)" % (extra * 100)))
        if y >= 450 and extra > 0.35:   # глубже 450 торф плотный; выше топливо даёт подвал (ГДД п.9)
            bad.append("топливо на глубине %d: добор съедает +%.0f%% копки (>35%%)" % (y, extra * 100))

    print("\n== Лава: цена клетки в HP по ступеням ==")
    lava = BAL["survival"]["hazards"]["lava"]
    raw = lava["hp_damage_per_second"] * lava["dig_seconds"]
    for i, t in enumerate([{"lava_resist": 0.0}] + unwrap(TECH["heat"]["suit_tiers"])):
        print("  костюм %d: %.0f HP за клетку (HP героя 100…300)" % (i, raw * (1.0 - t["lava_resist"])))

    if bad:
        print("\nНАРУШЕНИЯ:")
        for b in bad:
            print("  -", b)
    else:
        print("\nвсе границы соблюдены")
    if check and bad:
        sys.exit(1)


if __name__ == "__main__":
    main()

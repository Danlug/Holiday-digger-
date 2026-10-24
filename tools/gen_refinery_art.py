#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_refinery_art.py — значки перегонки на станции заправки (ветка «fuel-station»):
  art/tech/icon_refine.png  — перегонный куб на огне (кнопка «перегнать»);
  art/tech/icon_arrow.png   — стрелка «сырьё -> блок».
Кисть и палитра — из tools/gen_tech_art.py (тот же стиль: 32×32, обводка, свет
сверху-слева). Замена-заглушка уровня «программист нарисовал аккуратно».

Детерминировано. Запуск:
    python3 tools/gen_refinery_art.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_tech_art as T  # noqa: E402


def icon_refine():
    im = T.new()
    # огонь под кубом
    T.poly(im, [(9, 30), (8, 27), (10, 24), (11, 26), (13, 22), (15, 26), (17, 23), (19, 27), (18, 30)], "fire_red")
    T.poly(im, [(10, 30), (10, 28), (12, 25), (13, 27), (15, 25), (17, 28), (17, 30)], "fire_orange")
    T.poly(im, [(12, 30), (12, 29), (14, 27), (16, 29), (16, 30)], "fire_yellow")
    # опоры
    T.rect(im, 6, 25, 7, 30, "lead_base")
    T.rect(im, 20, 25, 21, 30, "lead_base")
    # медный котёл: тёмная сторона справа, свет сверху-слева
    T.ell(im, 4, 11, 23, 26, "rebar_rust")
    T.ell(im, 5, 12, 21, 24, "copper_base")
    T.ell(im, 6, 13, 13, 19, "copper_light")
    T.rect(im, 7, 14, 8, 16, "gold_light")              # блик
    T.rect(im, 5, 21, 22, 22, "rebar_dark")             # обруч
    T.rect(im, 6, 21, 9, 21, "copper_light")
    # горло и колпак
    T.rect(im, 11, 6, 16, 12, "copper_base")
    T.rect(im, 11, 6, 12, 12, "copper_light")
    T.rect(im, 15, 6, 16, 12, "rebar_rust")
    T.rect(im, 10, 5, 17, 6, "rebar_dark")
    # трубка-змеевик вправо и вниз
    T.line(im, [(17, 7), (24, 7), (27, 10), (27, 17)], "copper_base", 2)
    T.line(im, [(17, 7), (24, 7)], "copper_light", 1)
    T.rect(im, 26, 17, 28, 18, "lead_light")
    # капля топлива из трубки
    T.poly(im, [(27, 20), (25, 23), (26, 25), (28, 25), (29, 23)], "fire_orange")
    T.dot(im, 26, 23, "fire_yellow")
    T.dot(im, 27, 22, "fire_white")
    return T.outline(im)


def icon_arrow():
    im = T.new()
    T.poly(im, [(5, 13), (18, 13), (18, 7), (28, 16), (18, 25), (18, 19), (5, 19)], "gold_base")
    T.poly(im, [(5, 13), (18, 13), (18, 7), (22, 11), (19, 14), (6, 14)], "gold_light")
    T.line(im, [(6, 18), (18, 18)], "ancient_1")
    T.line(im, [(19, 23), (27, 16)], "ancient_1")
    return T.outline(im)


def still_world(frame):
    """Перегонный куб у станции в огороде (32×40, правее колонки): медный котёл на
    кирпичной топке, змеевик в ведро с блоками. frame 0/1 — огонь в топке мигает."""
    im = T.new(32, 40)
    # кирпичная топка
    T.rect(im, 3, 29, 24, 39, "rebar_dark")
    for row, y in enumerate(range(30, 39, 3)):
        off = 0 if row % 2 == 0 else 3
        for x in range(3 + off, 24, 6):
            T.rect(im, x, y, min(x + 4, 24), y + 1, "copper_base" if (x + y) % 4 else "rebar_rust")
    T.rect(im, 9, 32, 18, 38, "lava_crust_0")              # устье топки
    if frame == 0:
        T.poly(im, [(10, 38), (10, 35), (12, 33), (13, 35), (15, 32), (17, 35), (17, 38)], "fire_orange")
        T.poly(im, [(12, 38), (12, 36), (14, 34), (16, 37), (16, 38)], "fire_yellow")
    else:
        T.poly(im, [(10, 38), (11, 34), (13, 36), (14, 33), (16, 35), (17, 34), (17, 38)], "fire_red")
        T.poly(im, [(11, 38), (12, 35), (14, 36), (15, 35), (16, 38)], "fire_orange")
        T.dot(im, 14, 37, "fire_yellow")
    # медный котёл
    T.ell(im, 3, 12, 24, 31, "rebar_rust")
    T.ell(im, 4, 13, 22, 29, "copper_base")
    T.ell(im, 5, 14, 13, 21, "copper_light")
    T.rect(im, 7, 16, 8, 18, "gold_light")
    T.rect(im, 3, 25, 24, 26, "rebar_dark")                # обруч
    T.rect(im, 5, 25, 9, 25, "copper_light")
    # горло и колпак
    T.rect(im, 11, 6, 16, 13, "copper_base")
    T.rect(im, 11, 6, 12, 13, "copper_light")
    T.rect(im, 15, 6, 16, 13, "rebar_rust")
    T.ell(im, 10, 3, 17, 8, "copper_base")
    T.rect(im, 11, 4, 12, 5, "gold_light")
    # змеевик: вправо и вниз, в ведро
    T.line(im, [(17, 5), (25, 5), (28, 8), (28, 14)], "copper_base", 2)
    T.line(im, [(17, 5), (25, 5)], "copper_light", 1)
    for y in (15, 19, 23):
        T.line(im, [(28, y), (25, y + 2), (28, y + 4)], "copper_base", 2)
    T.dot(im, 28, 28, "fire_orange")                        # капля топлива
    # ведро с брикетами
    T.rect(im, 24, 31, 31, 39, "steel_blue")
    T.rect(im, 24, 31, 31, 32, "lead_light")
    T.rect(im, 25, 30, 27, 31, "soil_light")
    T.rect(im, 28, 29, 30, 31, "soil_shadow")
    T.dot(im, 29, 30, "fire_orange")
    return T.outline(im)


def main():
    items = {
        "icon_refine.png": icon_refine(),
        "icon_arrow.png": icon_arrow(),
        "still_0.png": still_world(0),
        "still_1.png": still_world(1),
    }
    for name, im in items.items():
        T.save(im, name)
    print("готово: %s" % ", ".join(items.keys()))


if __name__ == "__main__":
    main()

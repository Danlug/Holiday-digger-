#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_story_art.py — графика сюжета: иконки дневника деда, наброски страниц,
реквизит новых катсцен (art/story/*.png).

Заглушка уровня «программист нарисовал аккуратно», не работа художника:
строго палитра проекта (tools/gen_art.py:PALETTE), чёткий пиксель без
антиалиасинга, обводка добавляется автоматически вокруг любого рисунка.

Запуск:  python3 tools/gen_story_art.py
Идемпотентен и детерминирован: повторный запуск даёт те же PNG.
"""

import math
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_art as G  # noqa: E402  (палитра и примитивы проекта)

OUT = os.path.join(G.ROOT, "art", "story")
INK = (46, 32, 20, 255)         # «карандаш» дневника: тёмно-коричневый
INK_SOFT = (96, 70, 44, 255)


def C(key):
    return G.C(key)


def new(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def outline(img, color=INK):
    """Обводка в один пиксель вокруг всего нарисованного (по 4 соседям)."""
    w, h = img.size
    src = img.copy()
    px = src.load()
    dst = img.load()
    for y in range(h):
        for x in range(w):
            if px[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] != 0:
                    dst[x, y] = color
                    break
    return img


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name))
    print("  art/story/" + name)


def poly(img, pts, fill):
    ImageDraw.Draw(img).polygon(pts, fill=fill)


def ell(img, box, fill):
    ImageDraw.Draw(img).ellipse(box, fill=fill)


def rect(img, x0, y0, x1, y1, fill):
    ImageDraw.Draw(img).rectangle([x0, y0, x1, y1], fill=fill)


def px(img, x, y, color):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), color)


def lines(img, pts, color, width=1):
    ImageDraw.Draw(img).line(pts, fill=color, width=width)


# ---------------------------------------------------------------------------
# Иконки интерфейса
# ---------------------------------------------------------------------------

def icon_diary():
    """Тетрадь в клеёнке, перетянутая резинкой, с закладкой."""
    img = new(24, 24)
    rect(img, 5, 3, 19, 21, C("soil_shadow"))                  # корешок и тень
    rect(img, 6, 3, 19, 20, (66, 92, 70, 255))                 # зелёная клеёнка
    rect(img, 6, 3, 8, 20, (46, 68, 52, 255))                  # корешок
    rect(img, 10, 6, 17, 10, C("parchment"))                   # наклейка
    for y in (7, 9):
        lines(img, [(11, y), (16, y)], INK_SOFT)
    rect(img, 6, 15, 19, 16, C("rebar_rust"))                  # резинка
    rect(img, 16, 19, 17, 23, C("ruby_base"))                  # закладка
    px(img, 16, 23, (0, 0, 0, 0))
    for x in range(6, 20):
        px(img, x, 4, (96, 130, 100, 255))                     # блик на краю
    save(outline(img), "icon_diary.png")


def icon_seal():
    """Печать из воска на бумажной полоске: страница запечатана."""
    img = new(24, 24)
    rect(img, 2, 9, 21, 15, C("parchment"))
    lines(img, [(2, 9), (21, 9)], C("parchment_border"))
    lines(img, [(2, 15), (21, 15)], C("parchment_border"))
    ell(img, (7, 5, 17, 19), C("ruby_base"))
    ell(img, (9, 7, 15, 17), (160, 20, 44, 255))
    lines(img, [(12, 9), (12, 15)], C("ruby_light"))
    lines(img, [(10, 12), (14, 12)], C("ruby_light"))
    px(img, 9, 8, C("ruby_light"))
    save(outline(img), "icon_seal.png")


def icon_pencil():
    img = new(12, 12)
    poly(img, [(2, 9), (8, 3), (10, 5), (4, 11)], C("gold_base"))
    poly(img, [(8, 3), (9, 2), (11, 4), (10, 5)], C("ruby_light"))
    poly(img, [(2, 9), (4, 11), (1, 11)], C("skin"))
    px(img, 1, 11, INK)
    save(outline(img), "icon_pencil.png")


def icon_flower():
    """Гвоздика на могиле: значок кнопки, пока тетрадь ещё не найдена."""
    img = new(24, 24)
    lines(img, [(12, 12), (12, 21)], (60, 110, 60, 255), 2)
    poly(img, [(12, 18), (7, 14), (9, 19)], (60, 110, 60, 255))
    poly(img, [(12, 17), (17, 13), (15, 18)], (60, 110, 60, 255))
    for (cx, cy) in ((12, 8), (8, 10), (16, 10), (10, 5), (14, 5)):
        ell(img, (cx - 3, cy - 3, cx + 3, cy + 3), C("ruby_base"))
    ell(img, (10, 6, 14, 10), C("ruby_light"))
    px(img, 12, 8, (160, 20, 44, 255))
    save(outline(img), "icon_flower.png")


def grave_marker():
    """Золотой пузырёк с «!» — парит над плитой, пока есть что прочесть."""
    img = new(14, 18)
    rect(img, 1, 1, 12, 12, C("gold_base"))
    rect(img, 1, 1, 12, 2, C("gold_light"))
    poly(img, [(4, 12), (9, 12), (6, 16)], C("gold_base"))
    rect(img, 6, 3, 7, 8, INK)
    rect(img, 6, 10, 7, 11, INK)
    for p in ((1, 1), (12, 1), (1, 12), (12, 12)):
        img.putpixel(p, (0, 0, 0, 0))
    save(outline(img), "grave_marker.png")


def grave_jar():
    """Жестяная банка из-под чая с краешком тетради — стоит у плиты."""
    img = new(16, 16)
    rect(img, 3, 4, 12, 14, (150, 154, 164, 255))
    rect(img, 3, 4, 5, 14, (190, 194, 204, 255))
    rect(img, 11, 4, 12, 14, (104, 108, 120, 255))
    rect(img, 2, 2, 13, 4, (118, 122, 134, 255))
    rect(img, 4, 7, 11, 11, C("ruby_base"))
    lines(img, [(5, 9), (10, 9)], C("parchment"))
    rect(img, 8, 0, 11, 2, (66, 92, 70, 255))                  # тетрадь торчит
    save(outline(img), "grave_jar.png")


# ---------------------------------------------------------------------------
# Наброски страниц дневника (24x24)
# ---------------------------------------------------------------------------

def sketch_first():
    img = new(24, 24)
    poly(img, [(4, 16), (7, 9), (13, 6), (19, 9), (21, 15), (17, 20), (8, 20)], C("gold_base"))
    poly(img, [(7, 9), (13, 6), (14, 9), (9, 12)], C("gold_light"))
    poly(img, [(14, 17), (19, 14), (17, 20)], (178, 130, 24, 255))
    px(img, 19, 5, C("gold_light")); px(img, 18, 4, C("gold_light")); px(img, 20, 4, C("gold_light"))
    px(img, 19, 3, C("gold_light")); px(img, 19, 6, C("gold_light"))
    save(outline(img), "sketch_first.png")


def sketch_peat():
    img = new(24, 24)
    for (cx, cy, w, h) in ((8, 15, 6, 4), (16, 16, 6, 4), (12, 9, 6, 4)):
        ell(img, (cx - w, cy - h, cx + w, cy + h), C("peat_base"))
        for k in range(-w + 2, w - 1, 3):
            lines(img, [(cx + k, cy - 2), (cx + k + 1, cy + 2)], C("peat_light"))
    save(outline(img), "sketch_peat.png")


def sketch_diamond():
    img = new(24, 24)
    for (x0, y0, x1, y1) in ((2, 8, 9, 15), (15, 8, 22, 15), (7, 2, 16, 8), (7, 15, 16, 22)):
        ell(img, (x0, y0, x1, y1), C("stone_base"))
        lines(img, [(x0 + 1, y0 + 2), (x0 + 3, y0 + 1)], C("stone_light"))
    poly(img, [(12, 6), (17, 11), (12, 18), (7, 11)], C("diamond_base"))
    poly(img, [(12, 6), (17, 11), (12, 11)], C("diamond_light"))
    lines(img, [(7, 11), (17, 11)], (60, 160, 156, 255))
    save(outline(img), "sketch_diamond.png")


def sketch_relic():
    img = new(24, 24)
    ell(img, (6, 8, 17, 21), C("copper_base"))
    rect(img, 9, 3, 14, 9, C("copper_base"))
    rect(img, 8, 2, 15, 4, C("copper_light"))
    for (x, y) in ((4, 8), (3, 11), (5, 14)):
        px(img, x, y, C("copper_base"))
    lines(img, [(4, 8), (4, 14)], C("copper_base"))
    lines(img, [(19, 8), (19, 14)], C("copper_base"))
    rect(img, 7, 12, 16, 13, C("soil_shadow"))
    for x in range(8, 16, 2):
        px(img, x, 15, C("soil_shadow"))
    px(img, 9, 7, C("copper_light")); px(img, 8, 9, C("copper_light"))
    save(outline(img), "sketch_relic.png")


def sketch_gold():
    img = new(24, 24)
    for (pts, col) in (
        ([(2, 20), (4, 15), (9, 13), (13, 16), (12, 21)], C("gold_base")),
        ([(10, 21), (12, 14), (18, 12), (22, 17), (20, 21)], C("gold_base")),
        ([(7, 14), (10, 7), (16, 6), (18, 11), (13, 14)], C("gold_light")),
    ):
        poly(img, pts, col)
    for (x, y) in ((6, 15), (15, 15), (13, 9)):
        px(img, x, y, (255, 255, 255, 255))
    save(outline(img), "sketch_gold.png")


def sketch_heavy():
    img = new(24, 24)
    ell(img, (3, 8, 20, 22), C("soil_warm"))
    poly(img, [(8, 9), (15, 9), (14, 4), (9, 4)], C("soil_warm"))
    rect(img, 8, 8, 15, 9, C("rebar_rust"))
    lines(img, [(8, 5), (15, 5)], C("rebar_rust"))
    for (x, y) in ((8, 14), (13, 12), (11, 17)):
        poly(img, [(x, y), (x + 2, y - 1), (x + 3, y + 1), (x + 1, y + 2)], C("gold_base"))
    lines(img, [(6, 12), (7, 19)], C("soil_shadow"))
    save(outline(img), "sketch_heavy.png")


def sketch_whisper():
    img = new(24, 24)
    ell(img, (6, 17, 17, 21), C("void_base"))
    ell(img, (8, 18, 15, 20), C("void_far"))
    for r in (4, 7, 10):
        pts = []
        for a in range(200, 341, 10):
            pts.append((11.5 + math.cos(math.radians(a)) * r * 1.1, 17 + math.sin(math.radians(a)) * r))
        lines(img, pts, C("platinum_base") if r != 10 else (140, 170, 210, 255))
    px(img, 11, 3, C("platinum_light")); px(img, 12, 3, C("platinum_light"))
    save(outline(img), "sketch_whisper.png")


def sketch_rig():
    img = new(24, 24)
    rect(img, 8, 6, 20, 16, C("steel_blue"))
    rect(img, 8, 6, 20, 8, (110, 140, 156, 255))
    rect(img, 12, 8, 17, 12, C("diamond_base"))                # кабина
    poly(img, [(8, 7), (1, 11), (8, 15)], C("lead_light"))      # бур
    lines(img, [(3, 11), (8, 9)], C("scrap_base"))
    lines(img, [(3, 11), (8, 13)], C("scrap_base"))
    poly(img, [(14, 6), (12, 1), (21, 1), (21, 6)], C("lead_light"))   # крыло
    rect(img, 18, 16, 20, 20, C("gold_base"))                   # тяга
    px(img, 19, 21, C("ruby_light"))
    rect(img, 9, 17, 14, 19, C("coal_base"))                    # гусеница
    save(outline(img), "sketch_rig.png")


def sketch_gems():
    img = new(24, 24)
    poly(img, [(2, 13), (6, 7), (12, 7), (14, 13), (8, 20)], C("ruby_base"))
    poly(img, [(6, 7), (12, 7), (10, 11), (6, 11)], C("ruby_light"))
    poly(img, [(12, 9), (17, 5), (22, 9), (21, 16), (14, 18)], C("emerald_base"))
    poly(img, [(17, 5), (22, 9), (17, 10)], C("emerald_light"))
    save(outline(img), "sketch_gems.png")


def sketch_lava():
    img = new(24, 24)
    poly(img, [(12, 2), (19, 12), (19, 17), (12, 22), (5, 17), (5, 12)], C("ruby_base"))
    poly(img, [(12, 7), (16, 13), (16, 17), (12, 20), (8, 17), (8, 13)], (240, 120, 40, 255))
    poly(img, [(12, 12), (14, 16), (12, 19), (10, 16)], C("gold_light"))
    save(outline(img), "sketch_lava.png")


def sketch_monsters():
    img = new(24, 24)
    ell(img, (2, 4, 21, 21), C("void_far"))
    for cx in (8, 16):
        poly(img, [(cx - 3, 12), (cx, 9), (cx + 3, 12), (cx, 14)], C("gold_base"))
        rect(img, cx, 10, cx, 13, (160, 20, 44, 255))
    lines(img, [(5, 7), (9, 9)], C("void_rim"))
    lines(img, [(18, 7), (14, 9)], C("void_rim"))
    save(outline(img, C("void_rim")), "sketch_monsters.png")


def sketch_bottom():
    img = new(24, 24)
    ell(img, (2, 3, 21, 21), C("void_base"))
    ell(img, (5, 6, 18, 18), C("void_far"))
    ell(img, (8, 9, 15, 15), (6, 8, 12, 255))
    px(img, 11, 11, C("gold_light")); px(img, 12, 11, C("gold_light"))
    px(img, 11, 12, C("gold_base")); px(img, 12, 12, C("gold_base"))
    for a in range(0, 360, 45):
        px(img, int(11.5 + math.cos(math.radians(a)) * 9.5), int(12 + math.sin(math.radians(a)) * 9), C("void_rim"))
    save(outline(img, C("void_rim")), "sketch_bottom.png")


def sketch_last():
    """Картошка и сердечко: бабка велела копать картошку."""
    img = new(24, 24)
    ell(img, (2, 8, 19, 21), C("soil_warm"))
    ell(img, (4, 10, 11, 14), (200, 160, 100, 255))
    for (x, y) in ((8, 15), (13, 12), (14, 17), (6, 18)):
        px(img, x, y, C("soil_base"))
    poly(img, [(17, 2), (19, 1), (21, 2), (21, 5), (19, 8), (17, 5)], C("ruby_base"))
    px(img, 18, 2, C("ruby_light"))
    save(outline(img), "sketch_last.png")


# ---------------------------------------------------------------------------
# Реквизит катсцен
# ---------------------------------------------------------------------------

def prop_phone():
    img = new(22, 38)
    rect(img, 1, 1, 20, 36, (36, 38, 48, 255))
    rect(img, 3, 4, 18, 31, (150, 220, 230, 255))
    rect(img, 3, 4, 18, 6, (110, 190, 205, 255))
    ell(img, (7, 10, 14, 18), C("skin"))                         # бабка в трубке
    poly(img, [(7, 12), (10, 8), (14, 8), (14, 12), (7, 12)], (200, 200, 208, 255))
    rect(img, 6, 13, 15, 14, (50, 70, 100, 255))                 # очки
    rect(img, 6, 21, 15, 28, (30, 40, 90, 255))                  # пиджак
    rect(img, 8, 33, 13, 34, C("emerald_light"))                 # «принять»
    for p in ((1, 1), (20, 1), (1, 36), (20, 36)):
        img.putpixel(p, (0, 0, 0, 0))
    save(outline(img), "prop_phone.png")


def prop_diary():
    img = new(34, 26)
    rect(img, 4, 8, 27, 24, (150, 154, 164, 255))
    rect(img, 4, 8, 8, 24, (190, 194, 204, 255))
    rect(img, 24, 8, 27, 24, (104, 108, 120, 255))
    rect(img, 3, 5, 28, 8, (118, 122, 134, 255))
    rect(img, 7, 12, 24, 20, C("ruby_base"))
    lines(img, [(9, 16), (22, 16)], C("parchment"))
    rect(img, 18, 0, 31, 6, (66, 92, 70, 255))
    rect(img, 18, 0, 20, 6, (46, 68, 52, 255))
    rect(img, 22, 2, 28, 4, C("parchment"))
    save(outline(img), "prop_diary.png")


def prop_suitcase():
    img = new(36, 28)
    rect(img, 2, 8, 33, 25, (150, 82, 50, 255))
    rect(img, 2, 8, 33, 11, (190, 116, 70, 255))
    rect(img, 2, 22, 33, 25, (110, 60, 36, 255))
    rect(img, 12, 3, 23, 8, (110, 60, 36, 255))
    rect(img, 14, 5, 21, 8, (0, 0, 0, 0))                        # ручка
    rect(img, 5, 12, 7, 21, C("gold_base"))                       # застёжки
    rect(img, 28, 12, 30, 21, C("gold_base"))
    ell(img, (13, 13, 18, 18), C("emerald_base"))                 # наклейка «Таиланд»
    ell(img, (21, 14, 25, 18), C("ruby_base"))
    rect(img, 4, 26, 7, 27, INK)
    rect(img, 28, 26, 31, 27, INK)
    save(outline(img), "prop_suitcase.png")


def prop_nugget():
    img = new(18, 16)
    poly(img, [(2, 11), (4, 6), (9, 3), (14, 6), (16, 11), (12, 14), (5, 14)], C("gold_base"))
    poly(img, [(4, 6), (9, 3), (10, 6), (6, 8)], C("gold_light"))
    poly(img, [(10, 11), (14, 8), (12, 14)], (178, 130, 24, 255))
    px(img, 15, 2, C("gold_light")); px(img, 14, 1, C("gold_light")); px(img, 16, 1, C("gold_light"))
    px(img, 15, 0, C("gold_light")); px(img, 15, 3, C("gold_light"))
    save(outline(img), "prop_nugget.png")


def main():
    print("art/story:")
    icon_diary(); icon_seal(); icon_pencil(); icon_flower(); grave_marker(); grave_jar()
    for f in (sketch_first, sketch_peat, sketch_diamond, sketch_relic, sketch_gold, sketch_heavy,
              sketch_whisper, sketch_rig, sketch_gems, sketch_lava, sketch_monsters, sketch_bottom,
              sketch_last):
        f()
    prop_phone(); prop_diary(); prop_suitcase(); prop_nugget()


if __name__ == "__main__":
    main()

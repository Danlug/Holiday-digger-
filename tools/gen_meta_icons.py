#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_meta_icons.py — значки мета-слоя (награды, задания, достижения) в art/meta/.

Плейсхолдер уровня «программист нарисовал аккуратно», не работа художника:
32×32, палитра проекта (tools/gen_art.py), без сглаживания, у каждого значка
тёмная обводка в один пиксель — общая для всех, чтобы они читались на плитках
любого тона. Идемпотентно и детерминировано: повторный запуск даёт те же PNG.

Запуск:  python3 tools/gen_meta_icons.py
Лист для просмотра: python3 tools/gen_meta_icons.py --sheet /путь/лист.png
"""

import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_art import C, shade  # noqa: E402  (палитра проекта — единственный источник цветов)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "art", "meta")
RIM = (0x17, 0x13, 0x0F, 255)
WHITE = (255, 255, 255, 255)

ICONS = {}


def icon(fn):
    ICONS[fn.__name__.removeprefix("g_")] = fn
    return fn


def canvas():
    return Image.new("RGBA", (32, 32), (0, 0, 0, 0))


def d(img):
    return ImageDraw.Draw(img)


def rect(img, x0, y0, x1, y1, col):
    d(img).rectangle([x0, y0, x1, y1], fill=col)


def ell(img, cx, cy, rx, ry, col):
    d(img).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=col)


def poly(img, pts, col):
    d(img).polygon(pts, fill=col)


def line(img, pts, col, w=1):
    d(img).line(pts, fill=col, width=w)


def dot(img, x, y, col):
    if 0 <= x < 32 and 0 <= y < 32:
        img.putpixel((x, y), col)


def sparkle(img, x, y, col=WHITE):
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        dot(img, x + dx, y + dy, col)


def finish(img):
    """Обводка в один пиксель по четырём соседям — одинаковая у всех значков."""
    src = img.copy()
    px, dst = src.load(), img.load()
    for y in range(32):
        for x in range(32):
            if px[x, y][3] > 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < 32 and 0 <= ny < 32 and px[nx, ny][3] > 0:
                    dst[x, y] = RIM
                    break
    return img


def gem(img, cx, cy, r, base, light):
    top = cy - r * 0.6
    poly(img, [(cx - r, top), (cx - r * 0.55, cy - r), (cx + r * 0.55, cy - r), (cx + r, top)], light)
    poly(img, [(cx - r, top), (cx + r, top), (cx, cy + r)], base)
    poly(img, [(cx - r, top), (cx, top), (cx, cy + r)], shade(base, 0.82))
    line(img, [(cx - r * 0.55, cy - r), (cx - r * 0.2, top)], WHITE)


# ---------------------------------------------------------------- действия

@icon
def g_depth(img):
    for y in (8, 13, 18):
        rect(img, 3, y, 9, y, C("stone_light"))
        rect(img, 22, y, 28, y, C("stone_light"))
    rect(img, 13, 3, 18, 16, C("soil_warm"))
    rect(img, 13, 3, 14, 16, C("soil_light"))
    poly(img, [(6, 16), (25, 16), (15.5, 28)], C("soil_warm"))
    poly(img, [(6, 16), (15.5, 16), (15.5, 28)], C("soil_light"))
    return img


@icon
def g_dig(img):
    line(img, [(8, 27), (21, 12)], C("wood"), 3)
    line(img, [(9, 26), (21, 12)], shade(C("wood"), 1.3), 1)
    poly(img, [(11, 8), (19, 4), (27, 8), (28, 12), (22, 8), (17, 8)], C("iron_tool"))
    poly(img, [(11, 8), (19, 4), (22, 5), (14, 9)], shade(C("iron_tool"), 1.2))
    ell(img, 24, 25, 4, 3, C("soil_base"))
    ell(img, 22, 24, 2, 1, C("soil_light"))
    ell(img, 27, 27, 2, 1, C("soil_shadow"))
    return img


@icon
def g_stone(img):
    pts = [(5, 23), (7, 13), (14, 7), (23, 9), (27, 18), (24, 26), (9, 26)]
    poly(img, pts, C("stone_base"))
    poly(img, [(7, 13), (14, 7), (23, 9), (16, 13)], C("stone_light"))
    poly(img, [(9, 26), (24, 26), (27, 18), (20, 22)], C("stone_shadow"))
    line(img, [(15, 14), (13, 19), (16, 23)], C("stone_shadow"))
    return img


@icon
def g_nugget(img):
    pts = [(6, 21), (8, 13), (14, 9), (21, 10), (26, 16), (25, 23), (15, 26)]
    poly(img, pts, C("gold_base"))
    poly(img, [(8, 13), (14, 9), (21, 10), (15, 14)], C("gold_light"))
    poly(img, [(15, 26), (25, 23), (26, 16), (20, 21)], shade(C("gold_base"), 0.72))
    sparkle(img, 24, 8)
    dot(img, 10, 20, C("gold_light"))
    return img


@icon
def g_ingot(img):
    poly(img, [(9, 9), (24, 9), (28, 15), (5, 15)], C("iron_light"))
    rect(img, 5, 15, 28, 24, C("iron_base"))
    rect(img, 5, 22, 28, 24, shade(C("iron_base"), 0.72))
    rect(img, 8, 17, 14, 18, C("iron_light"))
    return img


@icon
def g_diamond(img):
    poly(img, [(4, 12), (28, 12), (22, 5), (10, 5)], shade(C("diamond_base"), 1.15))
    poly(img, [(4, 12), (28, 12), (16, 29)], C("diamond_base"))
    poly(img, [(4, 12), (16, 12), (16, 29)], shade(C("diamond_base"), 0.8))
    line(img, [(10, 5), (13, 12), (16, 29)], shade(C("diamond_base"), 1.2))
    line(img, [(22, 5), (19, 12), (16, 29)], shade(C("diamond_base"), 1.2))
    sparkle(img, 9, 8)
    return img


@icon
def g_gems(img):
    gem(img, 9, 19, 6, C("ruby_base"), C("ruby_light"))
    gem(img, 23, 19, 6, C("emerald_base"), C("emerald_light"))
    gem(img, 16, 13, 8, C("diamond_base"), C("diamond_base"))
    sparkle(img, 7, 9)
    return img


@icon
def g_bag(img):
    body = C("rust_tool")
    line(img, [(12, 7), (12, 4), (20, 4), (20, 7)], shade(body, 0.6), 2)
    rect(img, 4, 11, 8, 26, C("iron_tool"))
    rect(img, 24, 11, 28, 26, C("iron_tool"))
    rect(img, 7, 7, 25, 28, body)
    rect(img, 7, 7, 25, 9, shade(body, 1.3))
    rect(img, 7, 7, 10, 28, shade(body, 1.12))
    rect(img, 7, 17, 25, 17, shade(body, 0.6))
    rect(img, 13, 14, 19, 19, C("iron_tool"))
    rect(img, 15, 16, 17, 18, shade(C("iron_tool"), 0.6))
    rect(img, 10, 21, 22, 27, shade(body, 0.85))
    rect(img, 10, 21, 22, 21, shade(body, 0.6))
    return img


@icon
def g_uranium(img):
    rect(img, 9, 9, 23, 26, C("uranium_core"))
    ell(img, 16, 9, 7, 3, C("uranium_glow"))
    ell(img, 16, 26, 7, 3, C("uranium_core"))
    rect(img, 9, 15, 23, 18, C("uranium_glow"))
    for x in (12, 16, 20):
        rect(img, x, 21, x + 1, 23, C("uranium_glow"))
    for a in ((4, 6), (27, 5), (28, 20), (3, 21)):
        sparkle(img, a[0], a[1], C("uranium_glow"))
    return img


@icon
def g_coins(img):
    for i, y in enumerate((22, 16, 10)):
        ell(img, 16, y + 3, 10, 5, shade(C("coin"), 0.7))
        ell(img, 16, y, 10, 5, C("coin"))
        ell(img, 16, y, 6, 3, shade(C("coin"), 0.88))
    dot(img, 10, 8, C("coin_light"))
    dot(img, 11, 8, C("coin_light"))
    return img


@icon
def g_cart(img):
    poly(img, [(6, 12), (26, 12), (24, 27), (8, 27)], C("shirt"))
    poly(img, [(6, 12), (11, 12), (13, 27), (8, 27)], shade(C("shirt"), 1.15))
    poly(img, [(21, 12), (26, 12), (24, 27), (19, 27)], C("shirt_shadow"))
    line(img, [(11, 12), (11, 8), (14, 5), (18, 5), (21, 8), (21, 12)], C("parchment_border"), 2)
    ell(img, 16, 19, 4, 4, C("coin"))
    ell(img, 16, 19, 2, 2, shade(C("coin"), 0.8))
    return img


@icon
def g_vase(img):
    poly(img, [(11, 4), (21, 4), (20, 8), (12, 8)], C("soil_warm"))
    rect(img, 13, 8, 19, 11, C("rebar_rust"))
    ell(img, 16, 19, 9, 8, C("rebar_rust"))
    ell(img, 13, 17, 4, 4, shade(C("rebar_rust"), 1.25))
    rect(img, 8, 17, 24, 19, C("gold_base"))
    ell(img, 6, 14, 2, 3, C("rebar_rust"))
    ell(img, 26, 14, 2, 3, C("rebar_rust"))
    rect(img, 12, 26, 20, 28, C("soil_shadow"))
    return img


@icon
def g_book(img):
    rect(img, 7, 5, 25, 27, C("pants"))
    rect(img, 7, 5, 10, 27, C("pants_shadow"))
    rect(img, 11, 5, 25, 7, shade(C("pants"), 1.3))
    rect(img, 25, 7, 26, 26, C("parchment"))
    ell(img, 17, 16, 4, 4, C("gold_base"))
    ell(img, 17, 16, 2, 2, C("pants"))
    rect(img, 8, 24, 24, 24, C("gold_base"))
    return img


@icon
def g_skull(img):
    ell(img, 16, 13, 10, 9, C("parchment"))
    rect(img, 11, 17, 21, 26, C("parchment"))
    rect(img, 11, 24, 21, 26, C("parchment_border"))
    for x in (13, 16, 19):
        line(img, [(x, 24), (x, 26)], C("hair"))
    ell(img, 12, 14, 3, 3, C("eye_dark"))
    ell(img, 20, 14, 3, 3, C("eye_dark"))
    poly(img, [(15, 18), (17, 18), (16, 21)], C("eye_dark"))
    dot(img, 9, 8, WHITE)
    return img


@icon
def g_up(img):
    for dy, k in ((0, 1.0), (9, 0.8)):
        poly(img, [(16, 4 + dy), (28, 15 + dy), (22, 15 + dy), (16, 10 + dy), (10, 15 + dy), (4, 15 + dy)],
             shade(C("emerald_light"), k))
    sparkle(img, 25, 6)
    return img


@icon
def g_fuel(img):
    rect(img, 7, 10, 23, 27, C("shirt"))
    rect(img, 7, 10, 10, 27, shade(C("shirt"), 1.18))
    rect(img, 20, 10, 23, 27, C("shirt_shadow"))
    rect(img, 7, 10, 23, 12, shade(C("shirt"), 1.3))
    rect(img, 10, 5, 20, 9, C("shirt_shadow"))
    rect(img, 13, 6, 17, 8, C("hair"))
    rect(img, 22, 4, 27, 8, C("iron_tool"))
    poly(img, [(15, 15), (19, 21), (15, 24), (11, 21)], C("gold_light"))
    return img


@icon
def g_fang(img):
    poly(img, [(6, 12), (4, 3), (12, 8)], C("titanium_light"))
    poly(img, [(26, 12), (28, 3), (20, 8)], C("titanium_light"))
    ell(img, 16, 17, 11, 10, C("titanium_base"))
    ell(img, 12, 13, 5, 3, shade(C("titanium_base"), 1.2))
    ell(img, 11, 16, 3, 3, C("gold_light"))
    ell(img, 21, 16, 3, 3, C("gold_light"))
    dot(img, 11, 16, C("eye_dark"))
    dot(img, 21, 16, C("eye_dark"))
    poly(img, [(10, 22), (22, 22), (21, 25), (11, 25)], C("eye_dark"))
    poly(img, [(11, 22), (13, 22), (12, 25)], WHITE)
    poly(img, [(19, 22), (21, 22), (20, 25)], WHITE)
    return img


@icon
def g_scroll(img):
    rect(img, 8, 7, 24, 25, C("parchment"))
    rect(img, 8, 7, 24, 8, shade(C("parchment"), 1.1))
    ell(img, 16, 7, 9, 2, C("parchment_border"))
    ell(img, 16, 25, 9, 2, C("parchment_border"))
    for y in (12, 15, 18):
        rect(img, 11, y, 21, y, C("parchment_border"))
    ell(img, 20, 22, 3, 3, C("ruby_base"))
    dot(img, 19, 21, C("ruby_light"))
    return img


@icon
def g_flame(img):
    poly(img, [(16, 2), (23, 11), (27, 19), (23, 27), (16, 29), (9, 27), (5, 19), (9, 11), (12, 14)], C("copper_base"))
    poly(img, [(16, 9), (21, 16), (23, 22), (20, 27), (16, 28), (12, 27), (9, 22), (11, 16)], C("gold_base"))
    poly(img, [(16, 17), (19, 22), (18, 26), (16, 27), (14, 26), (13, 22)], C("gold_light"))
    return img


@icon
def g_clipboard(img):
    rect(img, 6, 5, 25, 28, C("wood"))
    rect(img, 6, 5, 8, 28, C("wood_dark"))
    rect(img, 9, 9, 23, 26, C("parchment"))
    rect(img, 12, 3, 19, 8, C("iron_tool"))
    rect(img, 14, 5, 17, 6, C("steel_blue"))
    for y in (13, 18, 23):
        rect(img, 15, y, 21, y, C("parchment_border"))
        rect(img, 11, y - 1, 12, y, C("emerald_base"))
    return img


@icon
def g_crown(img):
    poly(img, [(4, 24), (4, 9), (10, 15), (16, 6), (22, 15), (28, 9), (28, 24)], C("gold_base"))
    poly(img, [(4, 24), (4, 9), (10, 15), (10, 24)], shade(C("gold_base"), 0.82))
    rect(img, 4, 21, 28, 26, C("gold_light"))
    rect(img, 4, 24, 28, 26, shade(C("gold_base"), 0.7))
    for x, c in ((9, "ruby_base"), (16, "emerald_base"), (23, "diamond_base")):
        ell(img, x, 23, 1, 1, C(c))
    dot(img, 16, 6, WHITE)
    return img


@icon
def g_medal(img):
    poly(img, [(9, 3), (16, 3), (20, 16), (13, 16)], C("ruby_base"))
    poly(img, [(23, 3), (16, 3), (12, 16), (19, 16)], C("pants"))
    ell(img, 16, 21, 8, 8, C("gold_base"))
    ell(img, 16, 21, 5, 5, shade(C("gold_base"), 0.82))
    poly(img, [(16, 17), (17, 20), (20, 20), (18, 22), (19, 25), (16, 23), (13, 25), (14, 22), (12, 20), (15, 20)],
         C("gold_light"))
    dot(img, 12, 16, WHITE)
    return img


@icon
def g_trophy(img):
    poly(img, [(8, 5), (24, 5), (22, 16), (18, 20), (14, 20), (10, 16)], C("gold_base"))
    poly(img, [(8, 5), (13, 5), (14, 20), (10, 16)], C("gold_light"))
    poly(img, [(24, 5), (19, 5), (18, 20), (22, 16)], shade(C("gold_base"), 0.8))
    line(img, [(8, 7), (4, 7), (4, 12), (9, 14)], C("gold_base"), 2)
    line(img, [(24, 7), (28, 7), (28, 12), (23, 14)], C("gold_base"), 2)
    rect(img, 14, 20, 18, 24, C("gold_base"))
    rect(img, 9, 24, 23, 28, C("hair"))
    rect(img, 9, 24, 23, 25, C("soil_warm"))
    sparkle(img, 12, 9)
    return img


@icon
def g_gift(img):
    rect(img, 5, 13, 27, 27, C("ruby_base"))
    rect(img, 5, 13, 8, 27, shade(C("ruby_base"), 1.2))
    rect(img, 24, 13, 27, 27, shade(C("ruby_base"), 0.8))
    rect(img, 3, 9, 29, 14, C("ruby_light"))
    rect(img, 3, 13, 29, 14, shade(C("ruby_base"), 0.85))
    rect(img, 14, 9, 18, 27, C("gold_base"))
    rect(img, 14, 9, 15, 27, C("gold_light"))
    poly(img, [(16, 9), (8, 3), (6, 6), (9, 9)], C("gold_base"))
    poly(img, [(16, 9), (24, 3), (26, 6), (23, 9)], C("gold_base"))
    poly(img, [(16, 9), (9, 4), (7, 6), (10, 9)], C("gold_light"))
    return img


@icon
def g_chest(img):
    rect(img, 4, 14, 28, 27, C("wood"))
    poly(img, [(4, 14), (6, 8), (12, 5), (20, 5), (26, 8), (28, 14)], shade(C("wood"), 1.2))
    rect(img, 4, 14, 28, 16, C("wood_dark"))
    for x in (8, 22):
        rect(img, x, 6, x + 2, 27, C("iron_tool"))
    rect(img, 4, 25, 28, 27, C("wood_dark"))
    rect(img, 13, 14, 19, 21, C("gold_base"))
    rect(img, 15, 16, 17, 19, C("hair"))
    sparkle(img, 26, 4)
    return img


@icon
def g_check(img):
    poly(img, [(4, 17), (8, 13), (13, 18), (24, 6), (28, 10), (13, 26)], C("emerald_light"))
    poly(img, [(4, 17), (8, 13), (13, 18), (13, 26)], C("emerald_base"))
    return img


@icon
def g_lock(img):
    line(img, [(10, 14), (10, 9), (13, 5), (19, 5), (22, 9), (22, 14)], C("lead_light"), 3)
    rect(img, 7, 14, 25, 27, C("scrap_base"))
    rect(img, 7, 14, 25, 16, shade(C("scrap_base"), 1.3))
    rect(img, 7, 25, 25, 27, shade(C("scrap_base"), 0.7))
    ell(img, 16, 20, 2, 2, C("hair"))
    rect(img, 15, 21, 17, 24, C("hair"))
    return img


@icon
def g_star(img):
    cx, cy, ro, ri = 16, 16.5, 13.5, 6
    import math
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = ro if i % 2 == 0 else ri
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    poly(img, pts, C("gold_base"))
    poly(img, [pts[0], pts[1], (cx, cy), pts[9]], C("gold_light"))
    poly(img, [pts[4], pts[5], (cx, cy), pts[3]], shade(C("gold_base"), 0.78))
    return img


@icon
def g_xp(img):
    base = C("diamond_base")
    poly(img, [(16, 2), (19, 13), (30, 16), (19, 19), (16, 30), (13, 19), (2, 16), (13, 13)], base)
    poly(img, [(16, 2), (19, 13), (16, 16), (13, 13)], shade(base, 1.25))
    poly(img, [(16, 30), (19, 19), (16, 16), (13, 19)], shade(base, 0.72))
    sparkle(img, 16, 16)
    return img


@icon
def g_calendar(img):
    rect(img, 5, 6, 27, 27, C("parchment"))
    rect(img, 5, 6, 27, 12, C("ruby_base"))
    rect(img, 5, 11, 27, 12, shade(C("ruby_base"), 0.8))
    for x in (10, 21):
        rect(img, x, 3, x + 1, 8, C("iron_tool"))
    for r in range(3):
        for c in range(4):
            x, y = 8 + c * 5, 15 + r * 4
            rect(img, x, y, x + 2, y + 1, C("parchment_border"))
    rect(img, 18, 19, 20, 20, C("ruby_base"))
    return img


@icon
def g_video(img):
    rect(img, 3, 7, 29, 25, C("lead_base"))
    rect(img, 3, 7, 29, 9, C("steel_blue"))
    rect(img, 5, 11, 27, 23, C("ui_dark_bg"))
    poly(img, [(13, 13), (22, 17), (13, 21)], C("emerald_light"))
    return img


@icon
def g_clock(img):
    ell(img, 16, 16, 12, 12, C("parchment"))
    ell(img, 16, 16, 10, 10, shade(C("parchment"), 1.08))
    line(img, [(16, 16), (16, 9)], C("hair"), 2)
    line(img, [(16, 16), (21, 19)], C("hair"), 2)
    dot(img, 16, 5, C("ruby_base"))
    dot(img, 27, 16, C("parchment_border"))
    dot(img, 16, 27, C("parchment_border"))
    dot(img, 5, 16, C("parchment_border"))
    return img


@icon
def g_ad(img):
    ell(img, 16, 16, 12, 12, C("emerald_base"))
    ell(img, 16, 16, 10, 10, C("emerald_light"))
    poly(img, [(13, 10), (23, 16), (13, 22)], C("emerald_base"))
    return img


# ------------------------------------------- ежедневные задания (ветка daily-tasks)

@icon
def g_spend(img):
    """«Потрать монеты»: развязанный кошель, из которого вылетают монеты."""
    poly(img, [(7, 17), (11, 13), (21, 13), (25, 17), (27, 24), (24, 29), (8, 29), (5, 24)], C("soil_warm"))
    poly(img, [(7, 17), (11, 13), (14, 13), (11, 20), (10, 29), (8, 29), (5, 24)], shade(C("soil_warm"), 1.18))
    poly(img, [(22, 15), (25, 17), (27, 24), (24, 29), (20, 29)], C("soil_shadow"))
    rect(img, 10, 12, 22, 14, C("soil_shadow"))
    line(img, [(12, 12), (9, 9)], C("parchment_border"), 1)
    line(img, [(20, 12), (23, 9)], C("parchment_border"), 1)
    for cx, cy in ((12, 7), (19, 4), (25, 9)):
        ell(img, cx, cy, 3, 2, shade(C("coin"), 0.75))
        ell(img, cx, cy - 1, 3, 2, C("coin"))
        dot(img, cx - 1, cy - 2, C("coin_light"))
    rect(img, 14, 20, 18, 22, C("coin"))
    return img


@icon
def g_reroll(img):
    """Замена задания: две стрелки по кругу."""
    import math
    col, dark = C("diamond_base"), shade(C("diamond_base"), 0.7)
    for a0, a1 in ((200, 340), (20, 160)):
        pts = []
        for i in range(13):
            a = math.radians(a0 + (a1 - a0) * i / 12)
            pts.append((16 + 10 * math.cos(a), 16 + 10 * math.sin(a)))
        line(img, pts, dark, 4)
        line(img, pts, col, 2)
    poly(img, [(23, 5), (29, 12), (21, 13)], col)
    poly(img, [(9, 27), (3, 20), (11, 19)], col)
    return img


@icon
def g_tasks(img):
    """Кнопка ежедневных заданий на экране: дощечка со списком и звезда дня."""
    g_clipboard(img)
    rect(img, 11, 22, 12, 23, C("parchment_border"))
    cx, cy, ro, ri = 24, 8, 7.5, 3.2
    import math
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = ro if i % 2 == 0 else ri
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    poly(img, pts, C("gold_base"))
    poly(img, [pts[0], pts[1], (cx, cy), pts[9]], C("gold_light"))
    return img


@icon
def g_chest_open(img):
    """Сундук дня готов: крышка откинута, внутри золото и свет."""
    poly(img, [(5, 3), (27, 3), (28, 10), (4, 10)], shade(C("wood"), 1.2))
    rect(img, 5, 3, 27, 4, C("wood_dark"))
    for x in (9, 21):
        rect(img, x, 3, x + 2, 10, C("iron_tool"))
    rect(img, 4, 11, 28, 14, C("gold_light"))
    ell(img, 10, 13, 4, 2, C("coin"))
    ell(img, 21, 12, 4, 2, C("coin"))
    ell(img, 16, 11, 3, 2, C("coin_light"))
    rect(img, 4, 15, 28, 28, C("wood"))
    rect(img, 4, 15, 28, 17, C("wood_dark"))
    for x in (8, 22):
        rect(img, x, 15, x + 2, 28, C("iron_tool"))
    rect(img, 4, 26, 28, 28, C("wood_dark"))
    rect(img, 13, 17, 19, 22, C("gold_base"))
    rect(img, 15, 18, 17, 20, C("hair"))
    sparkle(img, 6, 7, C("gold_light"))
    sparkle(img, 27, 13)
    return img



@icon
def g_clover(img):
    """«Удачник»: четырёхлистный клевер — срабатывания удачи (ГДД §11).
    Листья-сердечки по диагоналям, стебель уходит вниз в просвет между ними."""
    dark = shade(C("emerald_base"), 0.7)
    line(img, [(15, 16), (15, 23), (17, 27), (21, 29)], dark, 2)
    cx, cy = 15.5, 13.5
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        lx, ly = cx + dx * 6.0, cy + dy * 6.0
        px, py = -dy * 2.6, dx * 2.6          # поперёк листа: две доли сердечка
        for sx in (-1, 1):
            ell(img, lx + px * sx + dx * 1.2, ly + py * sx + dy * 1.2, 3.6, 3.6, C("emerald_base"))
        poly(img, [(lx + px * 1.9, ly + py * 1.9), (lx - px * 1.9, ly - py * 1.9),
                   (cx + dx * 0.8, cy + dy * 0.8)], C("emerald_base"))
        ell(img, lx + px * 0.9 + dx * 1.6, ly + py * 0.9 + dy * 1.6, 1.4, 1.4, C("emerald_light"))
        line(img, [(cx + dx * 1.5, cy + dy * 1.5), (lx + dx * 2.5, ly + dy * 2.5)], dark)
    ell(img, cx, cy, 1.5, 1.5, C("gold_light"))
    sparkle(img, 27, 4, C("gold_light"))
    return img

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn in ICONS.items():
        img = fn(canvas())
        finish(img).save(os.path.join(OUT_DIR, f"{name}.png"))
    print(f"Готово: {len(ICONS)} значков в art/meta/")
    if "--sheet" in sys.argv:
        path = sys.argv[sys.argv.index("--sheet") + 1]
        cols = 8
        rows = (len(ICONS) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * 140, rows * 140), (46, 36, 28, 255))
        for i, name in enumerate(ICONS):
            im = Image.open(os.path.join(OUT_DIR, f"{name}.png")).resize((128, 128), Image.NEAREST)
            sheet.paste(im, ((i % cols) * 140 + 6, (i // cols) * 140 + 6), im)
        sheet.save(path)


if __name__ == "__main__":
    main()

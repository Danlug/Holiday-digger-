#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_tech_art.py — графика ветки «Техника»: топливо, бак, станция заправки,
костюмы, скважина, лава, значки окон. Рисует программно (PIL + numpy),
чёткий пиксель-арт 32×32 / 64×64 в палитре проекта (art/PALETTE.md), с обводкой.
Это замена-заглушка уровня «программист нарисовал аккуратно», не работа
художника владельца.

Идемпотентно и детерминировано (у каждого ассета свой seed).

Запуск:
    python3 tools/gen_tech_art.py
Результат: art/tech/*.png, art/tiles/lava_1..4.png, art/tech/_preview.png
"""

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TECH = os.path.join(ROOT, "art", "tech")
TILES = os.path.join(ROOT, "art", "tiles")

# --- палитра: тона из art/PALETTE.md + огненные (лава/топливо), которых там нет ---
P = {
    "outline": "#1A1410",
    "soil_shadow": "#3E2A1A", "soil_base": "#6B4428", "soil_light": "#8F6238", "soil_warm": "#B4854E",
    "stone_shadow": "#3A3A44", "stone_base": "#5C5C68", "stone_light": "#7E7E8C",
    "concrete_shadow": "#4C4E54", "concrete_base": "#6E7176",
    "rebar_dark": "#5C3018", "rebar_rust": "#8A4E28",
    "lead_base": "#33394A", "lead_light": "#9AA6BC",
    "silver_base": "#C7CDD6", "silver_light": "#F4F7FA",
    "copper_base": "#C2703A", "copper_light": "#E89A5E",
    "gold_base": "#E8B32E", "gold_light": "#FFE066",
    "diamond_base": "#6FE0D8",
    "titanium_base": "#A996C4", "titanium_light": "#D2C2EE",
    "aluminium_base": "#8B99A2", "aluminium_light": "#B8C4C8",
    "peat_base": "#3E2C1C", "peat_light": "#5E4830",
    "coal_base": "#1C1C22", "coal_light": "#4E4E5C",
    "ruby_base": "#C21E3A", "ruby_light": "#FF5570",
    "emerald_base": "#1C8A52", "emerald_light": "#4DE094",
    "parchment": "#E8D8B0", "parchment_border": "#A4835A",
    "lithium_base": "#D878BC",
    "uranium_glow": "#3DFF6F",
    "steel_blue": "#5C7484",
    "grass_field": "#4F7A34", "grass_dark": "#365423",
    # огонь: тёмная корка -> красный -> оранжевый -> жёлтый
    "lava_crust_0": "#1E1210", "lava_crust_1": "#30201A", "lava_crust_2": "#463024",
    "fire_deep": "#7A1608", "fire_red": "#C0301A", "fire_orange": "#F0701E", "fire_yellow": "#FFC83A", "fire_white": "#FFF0B0",
    "obsidian_0": "#14101C", "obsidian_1": "#2A2038", "obsidian_2": "#4A3A62", "obsidian_3": "#7A64A0",
    "geo_0": "#0E4A4E", "geo_1": "#1F8F86", "geo_2": "#6FE0D8", "geo_3": "#C8FFF4",
    "ancient_0": "#4A3A12", "ancient_1": "#8A6A22", "ancient_2": "#C9A04A", "ancient_3": "#F0D890",
}


def rgb(key, a=255):
    h = P[key].lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def new(w=32, h=32):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def rect(im, x0, y0, x1, y1, c):
    ImageDraw.Draw(im).rectangle([x0, y0, x1, y1], fill=rgb(c) if isinstance(c, str) else c)


def poly(im, pts, c):
    ImageDraw.Draw(im).polygon(pts, fill=rgb(c) if isinstance(c, str) else c)


def ell(im, x0, y0, x1, y1, c):
    ImageDraw.Draw(im).ellipse([x0, y0, x1, y1], fill=rgb(c) if isinstance(c, str) else c)


def line(im, pts, c, w=1):
    ImageDraw.Draw(im).line(pts, fill=rgb(c) if isinstance(c, str) else c, width=w)


def dot(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), rgb(c) if isinstance(c, str) else c)


def outline(im, key="outline"):
    """Обводка в 1 px вокруг непрозрачного — читаемый силуэт на любом фоне."""
    a = np.array(im)
    alpha = a[:, :, 3] > 0
    pad = np.pad(alpha, 1)
    edge = ~alpha & (pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:])
    c = rgb(key)
    a[edge] = c
    return Image.fromarray(a, "RGBA")


def save(im, name, folder=TECH):
    os.makedirs(folder, exist_ok=True)
    im.save(os.path.join(folder, name))


# ---------------------------------------------------------------- предметы

def fuel_block():
    im = new()
    # брикет в три четверти: верхняя грань светлее, левая темнее, правая средняя
    poly(im, [(5, 12), (16, 7), (27, 12), (16, 17)], "soil_light")       # верх
    poly(im, [(5, 12), (16, 17), (16, 27), (5, 22)], "peat_base")        # лево
    poly(im, [(16, 17), (27, 12), (27, 22), (16, 27)], "soil_shadow")    # право
    # прессованные волокна торфа на верхней грани
    for x, y in [(10, 11), (14, 12), (18, 10), (22, 12), (16, 14), (12, 13)]:
        dot(im, x, y, "peat_light")
    for x, y in [(11, 9), (19, 12), (15, 10)]:
        dot(im, x, y, "soil_warm")
    # пламя на правой грани — «это топливо»
    poly(im, [(21, 23), (19, 20), (21, 16), (22, 18), (23, 15), (24, 20), (23, 23)], "fire_orange")
    poly(im, [(21, 23), (20, 21), (22, 19), (23, 21), (23, 23)], "fire_yellow")
    dot(im, 22, 22, "fire_white")
    # блик на ребре
    line(im, [(16, 17), (16, 26)], "peat_light")
    return outline(im)


def icon_flame():
    im = new()
    poly(im, [(16, 28), (9, 22), (9, 16), (13, 11), (13, 15), (16, 5), (19, 11), (22, 15), (23, 21), (21, 26)], "fire_red")
    poly(im, [(16, 28), (11, 22), (12, 17), (15, 13), (16, 18), (19, 14), (21, 20), (20, 25)], "fire_orange")
    poly(im, [(16, 28), (13, 23), (14, 20), (16, 17), (18, 21), (19, 25)], "fire_yellow")
    poly(im, [(16, 28), (14, 25), (16, 22), (18, 25)], "fire_white")
    return outline(im)


def icon_tank():
    """Канистра — бак бура."""
    im = new()
    poly(im, [(7, 10), (23, 10), (25, 12), (25, 27), (7, 27), (5, 25), (5, 12)], "ruby_base")
    rect(im, 7, 12, 8, 26, "ruby_light")                # блик слева
    rect(im, 5, 18, 25, 19, "ruby_base")
    line(im, [(7, 18), (24, 18)], "fire_deep")
    rect(im, 20, 5, 22, 10, "steel_blue")               # горловина
    rect(im, 19, 4, 23, 5, "lead_light")
    poly(im, [(9, 6), (16, 6), (17, 10), (9, 10)], "steel_blue")  # ручка
    rect(im, 11, 8, 14, 9, "outline")
    # капля
    poly(im, [(15, 21), (13, 24), (14, 26), (17, 26), (18, 24)], "silver_light")
    dot(im, 15, 24, "silver_base")
    return outline(im)


def icon_thermo(level):
    """Термометр: level 0 прохладно, 1 тепло, 2 жарко."""
    im = new()
    rect(im, 13, 4, 19, 21, "silver_light")
    rect(im, 14, 5, 18, 20, "lead_base")
    ell(im, 9, 18, 23, 30, "silver_light")
    ell(im, 11, 20, 21, 28, "lead_base")
    col = ["diamond_base", "fire_orange", "fire_red"][level]
    hi = ["silver_light", "fire_yellow", "fire_orange"][level]
    top = [18, 12, 6][level]
    rect(im, 15, top, 17, 22, col)
    ell(im, 12, 21, 20, 27, col)
    dot(im, 14, 22, hi)
    dot(im, 15, top, hi)
    for y in (8, 12, 16):
        dot(im, 20, y, "silver_base")
        dot(im, 21, y, "silver_base")
    if level == 2:
        for x, y in [(6, 6), (26, 8), (4, 14)]:
            poly(im, [(x, y + 4), (x - 2, y + 1), (x, y - 2), (x + 1, y + 1), (x + 2, y + 2)], "fire_yellow")
    return outline(im)


def icon_storage():
    """Ящик склада с рудой."""
    im = new()
    rect(im, 4, 12, 27, 27, "soil_base")
    rect(im, 4, 12, 27, 14, "soil_light")
    for x in (4, 14, 26):
        rect(im, x, 12, x + 1, 27, "soil_shadow")
    rect(im, 4, 19, 27, 20, "soil_shadow")
    # руда сверху
    for (x, y, c) in [(7, 9, "gold_base"), (11, 8, "lead_light"), (15, 9, "copper_base"), (19, 8, "gold_light"),
                      (23, 9, "silver_base"), (9, 10, "silver_light"), (17, 10, "gold_base")]:
        rect(im, x, y, x + 2, y + 2, c)
    return outline(im)


def icon_hourglass():
    im = new()
    rect(im, 8, 4, 24, 6, "soil_light")
    rect(im, 8, 26, 24, 28, "soil_light")
    poly(im, [(10, 7), (22, 7), (17, 16), (22, 25), (10, 25), (15, 16)], "silver_light")
    poly(im, [(12, 8), (20, 8), (16, 15), (16, 15)], "diamond_base")
    poly(im, [(12, 24), (20, 24), (16, 19)], "gold_base")
    rect(im, 15, 16, 16, 19, "gold_base")
    return outline(im)


def icon_ad():
    """Ролик: экран с треугольником «играть»."""
    im = new()
    rect(im, 3, 7, 28, 24, "lead_base")
    rect(im, 5, 9, 26, 22, "steel_blue")
    poly(im, [(13, 11), (13, 20), (21, 15)], "silver_light")
    rect(im, 11, 25, 20, 27, "lead_light")
    return outline(im)


def icon_lock():
    im = new()
    poly(im, [(10, 14), (10, 9), (13, 5), (19, 5), (22, 9), (22, 14)], "lead_light")
    poly(im, [(13, 14), (13, 10), (15, 8), (17, 8), (19, 10), (19, 14)], "lead_base")
    rect(im, 7, 14, 24, 27, "gold_base")
    rect(im, 7, 14, 24, 16, "gold_light")
    rect(im, 15, 19, 16, 23, "soil_shadow")
    return outline(im)


def icon_up():
    im = new()
    poly(im, [(16, 4), (28, 17), (21, 17), (21, 28), (11, 28), (11, 17), (4, 17)], "emerald_base")
    poly(im, [(16, 7), (24, 16), (19, 16), (19, 26), (13, 26), (13, 16), (8, 16)], "emerald_light")
    return outline(im)


def icon_down():
    im = new()
    poly(im, [(16, 28), (28, 15), (21, 15), (21, 4), (11, 4), (11, 15), (4, 15)], "steel_blue")
    poly(im, [(16, 25), (24, 16), (19, 16), (19, 6), (13, 6), (13, 16), (8, 16)], "silver_base")
    return outline(im)


def icon_check():
    im = new()
    poly(im, [(5, 17), (9, 13), (13, 18), (24, 6), (28, 10), (13, 26)], "emerald_light")
    poly(im, [(7, 17), (9, 15), (13, 20), (24, 8), (26, 10), (13, 24)], "emerald_base")
    return outline(im)


def icon_tech():
    """Значок пункта меню: шестерня с огоньком."""
    im = new()
    cx, cy = 15, 16
    for i in range(8):
        a = i * math.pi / 4
        x, y = cx + 11 * math.cos(a), cy + 11 * math.sin(a)
        rect(im, int(x) - 2, int(y) - 2, int(x) + 2, int(y) + 2, "steel_blue")
    ell(im, cx - 9, cy - 9, cx + 9, cy + 9, "steel_blue")
    ell(im, cx - 7, cy - 7, cx + 7, cy + 7, "lead_light")
    ell(im, cx - 4, cy - 4, cx + 4, cy + 4, "lead_base")
    poly(im, [(15, 21), (12, 17), (13, 14), (15, 12), (15, 15), (17, 13), (19, 17)], "fire_orange")
    poly(im, [(15, 21), (13, 18), (15, 16), (17, 18)], "fire_yellow")
    return outline(im)


def icon_depth():
    return icon_down()


def suit(tier):
    """Шлем и плечи; тема по ступени. 1 — оранжевый комбинезон, 2 — титан, 3 — модули
    охлаждения, 4 — геокристалл, 5 — обсидиан."""
    themes = {
        1: ("copper_base", "copper_light", "rebar_rust", "gold_light"),
        2: ("titanium_base", "titanium_light", "lead_base", "diamond_base"),
        3: ("silver_base", "silver_light", "steel_blue", "diamond_base"),
        4: ("geo_1", "geo_2", "geo_0", "geo_3"),
        5: ("obsidian_1", "obsidian_3", "obsidian_0", "fire_orange"),
    }
    base, light, dark, glow = themes[tier]
    im = new()
    # плечи и корпус
    poly(im, [(3, 30), (4, 22), (9, 19), (23, 19), (28, 22), (29, 30)], base)
    poly(im, [(4, 30), (5, 23), (9, 20), (13, 20), (11, 30)], light)
    rect(im, 14, 24, 17, 30, dark)
    # шлем
    ell(im, 8, 3, 24, 22, base)
    poly(im, [(10, 6), (15, 4), (13, 10), (10, 12)], light)
    # визор
    poly(im, [(10, 11), (22, 11), (22, 17), (19, 18), (13, 18), (10, 17)], dark)
    poly(im, [(11, 12), (21, 12), (21, 15), (11, 15)], glow)
    dot(im, 12, 13, "silver_light")
    dot(im, 13, 13, "silver_light")
    if tier == 1:
        rect(im, 4, 26, 6, 27, "gold_light")              # светоотражающие полосы
        rect(im, 26, 26, 28, 27, "gold_light")
    if tier == 2:
        for x in (6, 12, 19, 25):
            rect(im, x, 24, x + 1, 28, "titanium_light")  # пластины
    if tier == 3:
        rect(im, 4, 21, 8, 24, "diamond_base")            # модули охлаждения на плечах
        rect(im, 24, 21, 28, 24, "diamond_base")
        rect(im, 5, 22, 7, 23, "silver_light")
        rect(im, 25, 22, 27, 23, "silver_light")
        rect(im, 13, 1, 18, 3, "diamond_base")            # радиатор на шлеме
    if tier == 4:
        poly(im, [(5, 21), (7, 15), (9, 21)], "geo_3")    # кристаллы на плечах
        poly(im, [(23, 21), (25, 15), (27, 21)], "geo_3")
        poly(im, [(14, 4), (16, 0), (18, 4)], "geo_2")
    if tier == 5:
        for x, y in [(6, 24), (13, 26), (24, 25), (20, 22)]:
            dot(im, x, y, "fire_orange")                  # трещины-жилы лавы
            dot(im, x + 1, y + 1, "fire_red")
        poly(im, [(5, 21), (4, 16), (9, 20)], "obsidian_2")
        poly(im, [(27, 21), (28, 16), (23, 20)], "obsidian_2")
    return outline(im)


def well_icon():
    """Скважина-качалка для окон (32×32)."""
    im = new()
    rect(im, 3, 27, 28, 29, "concrete_base")
    rect(im, 3, 27, 28, 27, "concrete_shadow")
    poly(im, [(10, 27), (16, 9), (22, 27)], "lead_base")             # опора
    poly(im, [(13, 27), (16, 14), (19, 27)], "steel_blue")
    # балансир
    poly(im, [(4, 7), (8, 5), (28, 11), (27, 14), (7, 10)], "copper_base")
    poly(im, [(5, 7), (8, 6), (27, 11), (26, 12)], "copper_light")
    # головка и канат
    poly(im, [(3, 7), (8, 4), (8, 12), (3, 12)], "copper_light")
    rect(im, 5, 12, 5, 26, "silver_base")
    # противовес
    ell(im, 22, 12, 30, 20, "stone_base")
    ell(im, 23, 13, 27, 17, "stone_light")
    # мотор
    rect(im, 20, 22, 28, 27, "rebar_rust")
    rect(im, 21, 23, 24, 25, "gold_base")
    return outline(im)


def mat_icon(kind):
    """Экзотика глубже 3000 — у неё нет тайла-иконки, нужна для рецептов."""
    im = new()
    if kind == "geocrystal":
        poly(im, [(16, 3), (24, 12), (21, 28), (11, 28), (8, 12)], "geo_1")
        poly(im, [(16, 3), (24, 12), (16, 14)], "geo_2")
        poly(im, [(16, 3), (8, 12), (16, 14)], "geo_3")
        poly(im, [(16, 14), (21, 28), (11, 28)], "geo_0")
        poly(im, [(4, 18), (8, 12), (10, 28), (6, 26)], "geo_2")
        poly(im, [(28, 18), (24, 12), (22, 28), (26, 26)], "geo_0")
        dot(im, 14, 8, "silver_light")
    elif kind == "ancient_metal":
        poly(im, [(5, 12), (12, 5), (25, 8), (28, 18), (22, 27), (9, 26)], "ancient_1")
        poly(im, [(5, 12), (12, 5), (25, 8), (15, 13)], "ancient_3")
        poly(im, [(15, 13), (25, 8), (28, 18), (20, 19)], "ancient_2")
        poly(im, [(9, 26), (5, 12), (15, 13), (14, 22)], "ancient_0")
        for x, y in [(10, 17), (15, 17), (20, 14)]:
            rect(im, x, y, x + 1, y + 3, "ancient_0")        # выбитые знаки
        dot(im, 12, 8, "silver_light")
    else:  # obsidian
        poly(im, [(6, 22), (10, 7), (18, 4), (26, 11), (27, 23), (16, 28)], "obsidian_1")
        poly(im, [(10, 7), (18, 4), (26, 11), (17, 13)], "obsidian_3")
        poly(im, [(17, 13), (26, 11), (27, 23), (20, 22)], "obsidian_2")
        poly(im, [(6, 22), (10, 7), (17, 13), (12, 24)], "obsidian_0")
        dot(im, 14, 8, "silver_light")
        dot(im, 15, 8, "silver_light")
        dot(im, 22, 14, "obsidian_3")
    return outline(im)


# ---------------------------------------------------------------- мир

def station_world():
    """Станция заправки в огороде: колонка, бочка и навес. 64×64, 2×2 клетки."""
    im = new(64, 64)
    # земля под ногами — плотная плитка
    rect(im, 2, 56, 61, 62, "concrete_base")
    rect(im, 2, 56, 61, 57, "concrete_shadow")
    # навес на двух стойках
    rect(im, 8, 14, 9, 56, "lead_base")
    rect(im, 54, 14, 55, 56, "lead_base")
    poly(im, [(2, 14), (10, 5), (53, 5), (61, 14)], "ruby_base")
    poly(im, [(2, 14), (10, 5), (53, 5), (61, 14), (61, 17), (2, 17)], "ruby_base")
    rect(im, 2, 14, 61, 17, "ruby_base")
    for x in range(4, 60, 8):
        rect(im, x, 14, x + 3, 17, "parchment")           # полосы тента
    rect(im, 2, 17, 61, 18, "fire_deep")
    # колонка
    rect(im, 22, 24, 38, 56, "silver_base")
    rect(im, 22, 24, 24, 56, "silver_light")
    rect(im, 36, 24, 38, 56, "lead_light")
    rect(im, 24, 27, 36, 36, "lead_base")                 # экран
    rect(im, 25, 28, 35, 35, "emerald_base")
    rect(im, 26, 29, 29, 32, "emerald_light")
    rect(im, 24, 40, 36, 43, "ruby_base")                 # полоса бренда
    poly(im, [(30, 49), (28, 52), (29, 54), (31, 54), (32, 52)], "fire_orange")  # пламя-логотип
    # шланг
    line(im, [(38, 34), (44, 34), (46, 40), (44, 50)], "coal_base", 2)
    rect(im, 42, 50, 46, 53, "steel_blue")
    # бочка
    rect(im, 44, 38, 56, 56, "rebar_rust")
    rect(im, 44, 38, 56, 40, "copper_light")
    rect(im, 44, 46, 56, 47, "rebar_dark")
    rect(im, 44, 54, 56, 55, "rebar_dark")
    rect(im, 45, 40, 46, 55, "copper_base")
    # штабель брикетов слева
    for i, (x, y) in enumerate([(10, 52), (16, 52), (13, 47)]):
        rect(im, x, y, x + 5, y + 4, "soil_shadow")
        rect(im, x, y, x + 5, y + 1, "soil_light")
        dot(im, x + 3, y + 3, "fire_orange")
    return outline(im)


def well_world(frame):
    """Качалка на огороде, 4 кадра; кадр определяет угол балансира."""
    im = new(64, 64)
    ang = [-0.22, -0.07, 0.07, 0.22][frame]   # радианы, вверх-вниз
    rect(im, 2, 58, 61, 62, "concrete_base")
    rect(im, 2, 58, 61, 59, "concrete_shadow")
    # устье скважины и труба
    rect(im, 6, 48, 14, 58, "lead_base")
    rect(im, 8, 36, 12, 48, "silver_base")
    rect(im, 8, 36, 9, 48, "silver_light")
    # опора (A-образная)
    poly(im, [(24, 58), (32, 24), (40, 58)], "lead_base")
    poly(im, [(28, 58), (32, 30), (36, 58)], "steel_blue")
    rect(im, 27, 46, 37, 48, "lead_light")
    # балансир: ось в (32, 24)
    pivot = (32, 24)
    def rot(x, y):
        dx, dy = x - pivot[0], y - pivot[1]
        c, s = math.cos(ang), math.sin(ang)
        return (pivot[0] + dx * c - dy * s, pivot[1] + dx * s + dy * c)
    beam = [rot(2, 18), rot(2, 28), rot(60, 28), rot(60, 18)]
    poly(im, [tuple(map(int, p)) for p in beam], "copper_base")
    top = [rot(2, 18), rot(60, 18), rot(60, 21), rot(2, 21)]
    poly(im, [tuple(map(int, p)) for p in top], "copper_light")
    # головка-«лошадиная» на левом конце
    head = [rot(0, 12), rot(8, 8), rot(10, 34), rot(0, 34)]
    poly(im, [tuple(map(int, p)) for p in head], "copper_light")
    hx, hy = rot(4, 34)
    line(im, [(int(hx), int(hy)), (10, 36)], "silver_base")
    # противовес на правом конце
    cx, cy = rot(56, 30)
    ell(im, int(cx) - 7, int(cy) - 7, int(cx) + 7, int(cy) + 7, "stone_base")
    ell(im, int(cx) - 4, int(cy) - 5, int(cx) + 1, int(cy) - 1, "stone_light")
    # шатун и мотор
    mx, my = 50, 52
    rect(im, 42, 50, 58, 58, "rebar_rust")
    rect(im, 44, 52, 50, 55, "gold_base")
    line(im, [(int(cx), int(cy) + 6), (mx, my)], "silver_base", 2)
    rect(im, 54, 46, 56, 50, "fire_red")                   # лампа
    dot(im, 55, 47, "fire_yellow")
    return outline(im)


# ---------------------------------------------------------------- лава

def lava_frames(n=4, size=32, scale=3):
    """Бесшовные кадры лавы: плиты корки, между ними светящиеся жилы.
    Периодический Вороной на торе; жилы «ползут» — точки плавно кружат."""
    rnd = random.Random(7)
    seeds = [(rnd.random() * size, rnd.random() * size) for _ in range(8)]
    phases = [rnd.random() * math.tau for _ in seeds]
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    crust = [rgb("lava_crust_0")[:3], rgb("lava_crust_1")[:3], rgb("lava_crust_2")[:3]]
    glow = [rgb("fire_deep")[:3], rgb("fire_red")[:3], rgb("fire_orange")[:3], rgb("fire_yellow")[:3], rgb("fire_white")[:3]]
    frames = []
    for f in range(n):
        t = f / n * math.tau
        pts = []
        for (sx, sy), ph in zip(seeds, phases):
            pts.append((sx + 1.3 * math.cos(t + ph), sy + 1.3 * math.sin(t + ph * 1.7)))
        d = []
        for (px_, py_) in pts:
            dx = np.abs(xx + 0.5 - px_)
            dy = np.abs(yy + 0.5 - py_)
            dx = np.minimum(dx, size - dx)
            dy = np.minimum(dy, size - dy)
            d.append(np.sqrt(dx * dx + dy * dy))
        d = np.stack(d)
        order = np.sort(d, axis=0)
        edge = order[1] - order[0]
        owner = np.argmin(d, axis=0)
        img = np.zeros((size, size, 3), dtype=np.uint8)
        noise = np.random.RandomState(100 + f).rand(size, size)
        for y in range(size):
            for x in range(size):
                e = edge[y, x]
                pulse = 0.5 + 0.5 * math.sin(t * 1.0 + phases[owner[y, x]])
                width = 1.0 + 0.9 * pulse
                if e < width:
                    k = 1.0 - e / width                       # 1 в центре жилы
                    k = k * (0.78 + 0.22 * pulse)
                    idx = min(int(k * 4.6), 4)
                    img[y, x] = glow[idx]
                elif e < width + 1.2:
                    img[y, x] = glow[0]                       # тёмно-красная кромка
                else:
                    # корка: три тона по плите и шуму, ближе к жиле — теплее
                    shade = (owner[y, x] % 3 + (noise[y, x] > 0.8)) % 3
                    base = np.array(crust[shade])
                    if e < width + 2.4:
                        base = (base * 0.6 + np.array(glow[0]) * 0.4)
                    img[y, x] = base.astype(np.uint8)
        # редкие искры-пузыри
        rs = np.random.RandomState(300 + f)
        for _ in range(3):
            bx, by = rs.randint(0, size, 2)
            img[by, bx] = glow[3]
        im = Image.fromarray(img, "RGB").resize((size * scale, size * scale), Image.NEAREST)
        frames.append(im)
    return frames


def glow_sprite():
    """Мягкий круг свечения (аддитивно поверх лавы). Мягкий — намеренно: это свет, а не предмет."""
    s = 64
    yy, xx = np.mgrid[0:s, 0:s].astype(float)
    r = np.sqrt((xx - s / 2 + 0.5) ** 2 + (yy - s / 2 + 0.5) ** 2) / (s / 2)
    a = np.clip(1.0 - r, 0.0, 1.0) ** 2.2
    img = np.zeros((s, s, 4), dtype=np.uint8)
    img[..., 0] = 255
    img[..., 1] = (120 + 90 * (1 - r).clip(0, 1)).astype(np.uint8)
    img[..., 2] = 40
    img[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(img, "RGBA")


# ---------------------------------------------------------------- сборка

def main():
    items = {
        "fuel_block.png": fuel_block(),
        "icon_flame.png": icon_flame(),
        "icon_tank.png": icon_tank(),
        "icon_thermo_0.png": icon_thermo(0),
        "icon_thermo_1.png": icon_thermo(1),
        "icon_thermo_2.png": icon_thermo(2),
        "icon_storage.png": icon_storage(),
        "icon_hourglass.png": icon_hourglass(),
        "icon_ad.png": icon_ad(),
        "icon_lock.png": icon_lock(),
        "icon_up.png": icon_up(),
        "icon_down.png": icon_down(),
        "icon_check.png": icon_check(),
        "icon_tech.png": icon_tech(),
        "icon_well.png": well_icon(),
        "mat_geocrystal.png": mat_icon("geocrystal"),
        "mat_ancient_metal.png": mat_icon("ancient_metal"),
        "mat_obsidian.png": mat_icon("obsidian"),
        "station.png": station_world(),
        "glow.png": glow_sprite(),
    }
    for t in range(1, 6):
        items["suit_%d.png" % t] = suit(t)
    for f in range(4):
        items["well_%d.png" % f] = well_world(f)
    for name, im in items.items():
        save(im, name)
    lava = lava_frames()
    for i, im in enumerate(lava, start=1):
        im.save(os.path.join(TILES, "lava_%d.png" % i))
    preview(items, lava)
    print("готово: %d файлов в art/tech + 4 кадра лавы" % len(items))


def preview(items, lava):
    """Контактный лист для глаз: всё на тёмном фоне, мелочь ×3, лава в натуральную
    величину (96) и в игровой (32)."""
    bg = (22, 18, 14, 255)
    small = [(n, im) for n, im in items.items() if im.width <= 32]
    big = [(n, im) for n, im in items.items() if im.width > 32 and n != "glow.png"]
    cols = 10
    cell = 32 * 3 + 8
    rows = (len(small) + cols - 1) // cols
    W = max(cols * cell, 8 * 136)
    H = rows * cell + 140 + 110 + 10
    sheet = Image.new("RGBA", (W, H), bg)
    for i, (n, im) in enumerate(small):
        x, y = (i % cols) * cell + 4, (i // cols) * cell + 4
        sheet.alpha_composite(im.resize((96, 96), Image.NEAREST), (x, y))
    y0 = rows * cell + 8
    for i, (n, im) in enumerate(big):
        sheet.alpha_composite(im.resize((128, 128), Image.NEAREST), (4 + i * 136, y0))
    y1 = y0 + 140
    for i, im in enumerate(lava):
        sheet.alpha_composite(im.convert("RGBA"), (4 + i * 100, y1))
        sheet.alpha_composite(im.convert("RGBA").resize((32, 32), Image.NEAREST), (420 + i * 36, y1))
    # плитка 3×3 из одного кадра — видно ли шов
    tile = lava[0].convert("RGBA").resize((32, 32), Image.NEAREST)
    for ty in range(3):
        for tx in range(3):
            sheet.alpha_composite(tile, (580 + tx * 32, y1 + ty * 32))
    sheet.save(os.path.join(TECH, "_preview.png"))


if __name__ == "__main__":
    main()

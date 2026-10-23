#!/usr/bin/env python3
"""gen_artifact_art.py — 25 пиксель-иконок артефактов 32×32 → art/artifacts/<id>.png.

Это ЗАМЕНА-ЗАГЛУШКА уровня «программист нарисовал аккуратно», а не работа
художника владельца: когда художник положит свои PNG под теми же именами,
витрина подхватит их без правок кода (см. scripts/museum/artifact_art.gd).

Единый стиль: чёткий силуэт, обводка 1 пиксель, три тона на материал (база,
блик сверху-слева, тень снизу-справа), без размытия. У каждой ветки свой
характер палитры, чтобы ветку было видно с одного взгляда:
  1 Античность        — золото, бронза, терракота, пергамент
  2 Мистика и алхимия — фиолетовый, медь, стекло, зелёное зелье
  3 Оккульт           — слоновая кость, кровь, чёрное дерево, тлеющие угли
  4 Забытые цивил.    — нефрит, латунь, сланец, бирюзовое свечение
  5 Легенды           — сталь, золото, королевская синь, белые искры

Запуск:   python3 tools/gen_artifact_art.py            # записать PNG
          python3 tools/gen_artifact_art.py --sheet out.png   # + контактный лист
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pix import Spr, hexc, rot, shift, tint, contact_sheet  # noqa: E402

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "artifacts")

C = hexc
# --- Палитры веток ----------------------------------------------------------
# Общие тона держатся на art/PALETTE.md (золото, медь, серебро, рубин, алмаз).
GOLD = C("#e8b32e")
GOLD_L = C("#ffe066")
GOLD_D = C("#a8741c")
BRONZE = C("#a8682a")
TERRA = C("#b5532f")
PARCH = C("#e6d3a3")
STONE = C("#8a7f6e")
INK = C("#3a2a1a")
RED = C("#c22b3c")
RUBY = C("#c4223a")
LEATHER = C("#7a4a2a")
SACK = C("#b8935a")

PURPLE = C("#7a4cc2")
VIOLET_L = C("#b48cf0")
TEAL = C("#3fb7a8")
COPPER = C("#c2703a")
GLASS = C("#a9dfe6")
POTION = C("#58d27a")
FLAME = C("#9a5cf0")

BONE = C("#e8dfc8")
BLOOD = C("#b01e30")
DARK = C("#2b2433")
EBONY = C("#3a2d2a")
OCC_V = C("#6a2f9a")
EMBER = C("#e8552a")
SKIN = C("#c9a58a")

JADE = C("#3aa890")
CYAN = C("#6ff0e0")
BRASS = C("#c9a24a")
SLATE = C("#4c6a70")
STONE_L = C("#9bb7b5")
NAVY = C("#14224a")

STEEL = C("#c8d6ea")
STEEL_D = C("#6d82a8")
BLUE = C("#3f6ee0")
WHITE = C("#ffffff")
CRIMSON = C("#d6334a")
ROCK = C("#7e7e8c")
ROCK_D = C("#5c5c68")

OUT_ANT = C("#2a1a0e")
OUT_MYS = C("#1a1230")
OUT_OCC = C("#14090f")
OUT_FOR = C("#0c1a1f")
OUT_LEG = C("#0d1230")


# ============================================================================
# Ветка 1 — Античность
# ============================================================================

def antiquity_1(S):
    # Никчёмный клад: холщовый мешочек, из которого высыпалась мелочь.
    S.ell(15, 20, 10, 8, SACK)
    S.poly([(11, 14), (21, 14), (19, 9), (13, 9)], SACK)
    S.poly([(10, 8), (22, 8), (20, 11), (12, 11)], tint(SACK, 0.12))  # вздутый «воротник»
    S.rect(11, 13, 21, 14, C("#6a3f22"), bevel=False)               # верёвка
    S.px(21, 15, C("#6a3f22")); S.px(22, 16, C("#6a3f22")); S.px(21, 17, C("#6a3f22"))
    S.line([(12, 18), (19, 25)], tint(SACK, -0.2))                  # шов
    S.ell(25, 26, 3, 3, COPPER)                                      # медяк
    S.px(24, 25, tint(COPPER, 0.5))
    S.ell(7, 27, 2, 2, STONE)                                        # камешек
    S.ell(15, 28, 2, 2, GOLD)                                        # единственная настоящая монета
    S.px(14, 27, GOLD_L)


def antiquity_2(S):
    # Религиозный свиток: пергамент между двумя валиками, золотая печать.
    S.rect(8, 8, 24, 24, PARCH)
    S.rect(5, 5, 27, 9, tint(PARCH, -0.12))
    S.ell(5, 7, 1, 2, tint(PARCH, -0.3), bevel=False)
    S.ell(27, 7, 1, 2, tint(PARCH, 0.1), bevel=False)
    S.rect(5, 23, 27, 27, tint(PARCH, -0.12))
    S.ell(5, 25, 1, 2, tint(PARCH, -0.3), bevel=False)
    S.ell(27, 25, 1, 2, tint(PARCH, 0.1), bevel=False)
    # золотое солнышко-символ сверху и строчки
    S.ell(16, 13, 2, 2, GOLD, bevel=False)
    for a in range(0, 360, 45):
        dx = round(math.cos(math.radians(a)) * 4); dy = round(math.sin(math.radians(a)) * 4)
        S.px(16 + dx, 13 + dy, GOLD_D)
    for y, x1 in ((18, 21), (20, 19), (22, 21)):
        S.line([(11, y), (x1, y)], INK)
    S.ell(21, 21, 2, 2, RED, bevel=False)                            # сургуч
    S.px(20, 20, tint(RED, 0.5))


def antiquity_3(S):
    # Золотая инкрустированная чаша.
    S.poly([(5, 7), (27, 7), (25, 13), (21, 18), (11, 18), (7, 13)], GOLD)
    S.rect(5, 6, 27, 8, GOLD_L)
    S.rect(14, 18, 18, 24, GOLD_D)
    S.rect(13, 20, 19, 21, GOLD)                                     # утолщение на ножке
    S.ell(16, 26, 7, 2, GOLD)
    S.rect(9, 25, 23, 27, GOLD_D)
    S.ell(16, 12, 2, 2, RUBY)                                        # камни по чаше
    S.px(15, 11, tint(RUBY, 0.6))
    S.ell(10, 11, 1, 1, C("#4aa8e8"), bevel=False)
    S.ell(22, 11, 1, 1, C("#4aa8e8"), bevel=False)
    S.px(13, 15, GOLD_L); S.px(19, 15, GOLD_L)


def antiquity_4(S):
    # Сокровища Эльдорадо: золотая маска с убором и бирюзовыми серьгами.
    S.poly([(8, 9), (6, 3), (11, 7), (13, 2), (16, 6), (19, 2), (21, 7), (26, 3), (24, 9)], GOLD_D)
    S.ell(16, 18, 9, 11, GOLD)
    S.ell(6, 20, 2, 3, C("#3ad0c0"))                                  # бирюзовые серьги
    S.ell(26, 20, 2, 3, C("#3ad0c0"))
    S.poly([(9, 14), (14, 15), (13, 17), (9, 16)], INK, bevel=False)  # глаза-прорези
    S.poly([(23, 14), (18, 15), (19, 17), (23, 16)], INK, bevel=False)
    S.poly([(16, 16), (18, 22), (14, 22)], GOLD_L, bevel=False)       # нос
    S.rect(13, 25, 19, 26, INK)                                      # рот
    S.px(12, 24, INK); S.px(20, 24, INK)
    S.px(10, 11, GOLD_L); S.px(11, 10, GOLD_L)


def antiquity_5(S):
    # Золотой щит спартанского полководца: круглый гоплон с красной лямбдой.
    S.ell(16, 16, 13, 13, BRONZE)
    S.ell(16, 16, 11, 11, GOLD)
    S.ell(16, 16, 9, 9, GOLD_L, bevel=False)
    S.ell(16, 16, 9, 9, tint(GOLD, 0.06), bevel=False)
    S.line([(16, 8), (11, 23)], RED, 2)                              # лямбда
    S.line([(16, 8), (21, 23)], RED, 2)
    for a in range(0, 360, 60):
        x = 16 + round(math.cos(math.radians(a + 30)) * 12); y = 16 + round(math.sin(math.radians(a + 30)) * 12)
        S.px(x, y, GOLD_L)
    S.px(8, 8, WHITE); S.px(9, 7, GOLD_L)
    S.line([(7, 20), (7, 21)], tint(GOLD, -0.25))                    # вмятина


# ============================================================================
# Ветка 2 — Мистика и алхимия
# ============================================================================

def mysticism_1(S):
    # Алхимический тигель: чугунная чаша с носиком, ручкой и булькающим зельем над фиолетовым огнём.
    iron = C("#5d5f78")
    S.poly([(5, 13), (27, 13), (25, 20), (21, 24), (11, 24), (7, 20)], iron)
    S.ell(16, 13, 11, 3, tint(iron, 0.22))
    S.ell(16, 13, 9, 2, POTION, bevel=False)
    S.pxs([(12, 13), (13, 12), (19, 13), (20, 12)], tint(POTION, 0.6))
    S.poly([(26, 14), (30, 12), (30, 16), (26, 17)], iron)           # ручка
    S.px(5, 13, tint(iron, 0.4))
    S.ell(12, 7, 2, 2, POTION, bevel=False); S.px(11, 6, WHITE)
    S.ell(18, 5, 1, 1, POTION, bevel=False)
    S.ell(21, 8, 2, 2, tint(POTION, 0.3), bevel=False)
    S.ell(15, 3, 1, 1, tint(POTION, 0.4), bevel=False)
    S.poly([(9, 30), (11, 26), (14, 29), (16, 25), (18, 29), (21, 26), (23, 30)], FLAME)
    S.poly([(13, 30), (16, 27), (19, 30)], VIOLET_L, bevel=False)


def mysticism_2(S):
    # Компас, указывающий не на север: стрелка уводит вправо-вниз, в сторону кухни.
    S.ell(16, 18, 12, 12, BRASS)
    S.ell(16, 18, 9, 9, C("#d9f1e8"), bevel=False)
    S.rect(14, 2, 18, 5, BRASS)
    S.rect(15, 3, 17, 4, OUT_MYS, bevel=False)
    for (x, y) in ((16, 10), (16, 26), (8, 18), (24, 18)):
        S.px(x, y, INK)
    S.px(16, 11, INK); S.px(16, 25, INK); S.px(9, 18, INK); S.px(23, 18, INK)
    S.poly(shift(rot([(0, -2), (9, 0), (0, 2)], 50, 0, 0), 16, 18), RED, bevel=False)
    S.poly(shift(rot([(0, -2), (-9, 0), (0, 2)], 50, 0, 0), 16, 18), C("#f6f2ea"), bevel=False)
    S.ell(16, 18, 1, 1, INK, bevel=False)
    S.px(11, 12, WHITE); S.px(12, 11, WHITE)


def mysticism_3(S):
    # Незавершённый философский камень: правая половина огранена, левая — сырая порода.
    pts = [(16, 3), (27, 12), (22, 27), (10, 27), (5, 12)]
    S.poly(pts, ROCK_D)
    S.fill(S.mask(lambda d: d.polygon([(16, 3), (27, 12), (22, 27), (16, 27)], fill=255)), RUBY)
    S.poly([(16, 3), (27, 12), (16, 14)], tint(RUBY, 0.35), bevel=False)
    S.poly([(16, 14), (27, 12), (22, 27), (16, 27)], tint(RUBY, -0.12), bevel=False)
    S.line([(16, 4), (16, 26)], tint(RUBY, 0.55))
    S.line([(7, 13), (11, 19)], STONE, 1); S.line([(9, 21), (13, 22)], tint(ROCK_D, -0.3), 1)
    S.pxs([(8, 15), (12, 12), (10, 24), (13, 17)], ROCK)
    S.sparkle(24, 6, GOLD_L)
    S.px(28, 20, GOLD_L); S.px(4, 6, VIOLET_L)


def mysticism_4(S):
    # Реликварий с нетленной рукой: золотой футляр со стеклом, рука внутри.
    S.rect(5, 22, 27, 28, GOLD)
    S.rect(7, 12, 25, 22, C("#1d3f4c"))
    hand = C("#f0e0bc")
    hs = tint(hand, -0.3)
    S.rect(10, 18, 20, 22, hand, bevel=False)                          # ладонь
    for x, top in ((10, 15), (13, 13), (16, 13), (19, 15)):            # четыре пальца с зазорами
        S.rect(x, top, x + 1, 18, hand, bevel=False)
        S.px(x, top, tint(hand, 0.4))
    S.poly([(21, 19), (24, 16), (25, 18), (22, 22)], hand, bevel=False)  # большой палец
    S.line([(11, 20), (19, 20)], hs)
    S.rect(7, 12, 8, 21, C("#5fb4c4"), bevel=False)                   # блик стекла
    S.pxs([(10, 13), (10, 12)], WHITE)
    S.poly([(4, 12), (16, 3), (28, 12)], GOLD)
    S.rect(4, 11, 28, 13, GOLD_D)
    S.ell(16, 8, 2, 2, RUBY)
    S.px(15, 7, tint(RUBY, 0.6))
    S.pxs([(9, 25), (23, 25)], GOLD_L)


def mysticism_5(S):
    # Зерцало: нагрудник с зеркальной полировкой в золотой раме.
    body = [(5, 9), (12, 5), (14, 9), (18, 9), (20, 5), (27, 9), (26, 22), (21, 29), (11, 29), (6, 22)]
    S.poly(body, GOLD)
    inner = [(8, 11), (12, 8), (14, 12), (18, 12), (20, 8), (24, 11), (23, 21), (19, 26), (13, 26), (9, 21)]
    S.poly(inner, C("#cfe4f0"))
    S.poly([(9, 14), (13, 14), (20, 25), (16, 25)], C("#f3fbff"), bevel=False)   # зеркальная полоса
    S.poly([(15, 12), (17, 12), (23, 20), (22, 22)], tint(C("#cfe4f0"), 0.5), bevel=False)
    S.ell(16, 7, 2, 2, PURPLE)
    S.px(15, 6, VIOLET_L)
    S.pxs([(7, 11), (25, 11)], GOLD_L)
    S.sparkle(22, 14, WHITE)


# ============================================================================
# Ветка 3 — Оккульт
# ============================================================================

def occult_1(S):
    # Гадальные кости из чёрного дерева: две кости, на передней — шестёрка.
    S.rect(3, 3, 17, 17, EBONY)
    for x, y in ((6, 6), (12, 6), (6, 12), (12, 12)):
        S.rect(x, y, x + 1, y + 1, BLOOD, bevel=False)
    S.rect(14, 14, 28, 28, EBONY)
    for x, y in ((18, 17), (24, 17), (18, 21), (24, 21), (18, 25), (24, 25)):
        S.rect(x, y, x + 1, y + 1, BONE, bevel=False)
    S.pxs([(4, 4), (5, 4)], C("#6a5550"))


def occult_2(S):
    # Гримуар в человеческом переплёте: бледная кожа, шов, глаз и застёжка.
    S.rect(6, 4, 26, 28, C("#4a2a33"))
    S.rect(8, 5, 26, 27, SKIN)
    S.rect(25, 7, 27, 26, C("#efe4cc"), bevel=False)                  # обрез страниц
    S.line([(26, 9), (26, 24)], tint(C("#efe4cc"), -0.15))
    S.line([(12, 5), (12, 27)], tint(SKIN, -0.3))                     # шов
    for y in range(7, 27, 3):
        S.px(11, y, C("#4a2a33")); S.px(13, y, C("#4a2a33"))
    S.ell(19, 14, 4, 3, BONE, bevel=False)                            # глаз
    S.ell(19, 14, 2, 2, BLOOD, bevel=False)
    S.px(19, 14, INK)
    S.px(15, 21, INK); S.px(23, 21, INK)
    S.line([(15, 10), (23, 10)], tint(SKIN, -0.35))
    S.rect(23, 25, 27, 27, BRASS)                                     # уголок
    S.rect(24, 12, 27, 18, BRASS)                                     # застёжка
    S.px(25, 15, DARK)


def occult_3(S):
    # Печать призывателя: камень с горящей пентаграммой.
    S.ell(16, 16, 13, 13, DARK)
    S.ell(16, 16, 12, 12, EMBER, bevel=False)
    S.ell(16, 16, 10, 10, C("#241a2e"), bevel=False)
    cx, cy, r = 16, 16, 9
    pts = []
    for k in range(5):
        a = math.radians(-90 + 72 * k)
        pts.append((round(cx + r * math.cos(a)), round(cy + r * math.sin(a))))
    order = [0, 2, 4, 1, 3, 0]
    for i in range(5):
        S.line([pts[order[i]], pts[order[i + 1]]], EMBER)
    S.pxs(pts, C("#ffd07a"))
    S.px(16, 16, C("#ffd07a"))
    for a in range(0, 360, 30):
        S.px(16 + round(math.cos(math.radians(a)) * 11.5), 16 + round(math.sin(math.radians(a)) * 11.5), C("#7a2a20"))


def occult_4(S):
    # Кинжал ритуала затмения: чёрный клинок, рукоять с затмением на навершии.
    blade = [(0, -1), (13, -2), (16, 0), (13, 2), (0, 1)]
    g = lambda pts: shift(rot(pts, -45, 0, 0), 16, 17)
    bl = [(x * 1.0, y * 1.0) for x, y in [(2, -3), (15, -2), (19, 0), (15, 2), (2, 3)]]
    S.poly(g(bl), C("#3b2e5a"))
    S.poly(g([(4, -1), (17, 0), (4, 0)]), C("#9a82d8"), bevel=False)   # лунный блик по долу
    S.poly(g([(0, -6), (3, -6), (3, 6), (0, 6)]), BRASS)                # гарда
    S.poly(g([(-9, -1), (0, -2), (0, 2), (-9, 1)]), LEATHER)            # рукоять
    S.ell(7, 26, 4, 4, GOLD_D)                                          # затмение: чёрный диск в золотой короне
    S.ell(7, 26, 3, 3, C("#0b0710"), bevel=False)
    S.px(5, 24, GOLD_L); S.px(9, 28, GOLD)


def occult_5(S):
    # Сердце идола, которое ещё бьётся: каменное сердце на цепочке, в трещинах — жар.
    S.ell(16, 5, 4, 3, GOLD_D, bevel=False)
    S.ell(16, 5, 2, 1, OUT_OCC, bevel=False)
    S.line([(13, 7), (11, 10)], GOLD_D); S.line([(19, 7), (21, 10)], GOLD_D)
    S.ell(11, 16, 6, 6, C("#7a2630"))
    S.ell(21, 16, 6, 6, C("#7a2630"))
    S.poly([(5, 18), (27, 18), (16, 30)], C("#7a2630"))
    S.rect(9, 9, 12, 12, C("#5c1c26"))                                 # сосуды
    S.rect(20, 9, 23, 12, C("#5c1c26"))
    S.line([(14, 11), (12, 17), (16, 20), (14, 26)], EMBER)            # трещины, в которых горит жар
    S.line([(19, 12), (21, 18), (18, 23)], EMBER)
    S.pxs([(14, 11), (16, 20), (21, 18)], C("#ffd07a"))
    S.pxs([(8, 14), (9, 13), (23, 14), (22, 13)], C("#c8505c"))
    S.pxs([(3, 14), (3, 18), (29, 14), (29, 18)], EMBER)               # «пульс»
    S.pxs([(2, 16), (30, 16)], C("#ffd07a"))


# ============================================================================
# Ветка 4 — Забытые цивилизации
# ============================================================================

def forgotten_1(S):
    # Табличка с непереводимым письмом: сколотый камень со светящимися знаками.
    S.poly([(5, 4), (22, 4), (27, 9), (27, 28), (5, 28)], SLATE)
    S.poly([(22, 4), (27, 9), (22, 9)], tint(SLATE, -0.3), bevel=False)
    glyphs = [
        [(9, 9), (11, 9), (10, 10), (9, 11), (12, 11)],
        [(14, 9), (15, 9), (16, 10), (14, 11), (16, 12)],
        [(19, 9), (19, 10), (20, 10), (21, 9), (21, 11), (20, 12)],
        [(9, 15), (10, 15), (9, 16), (11, 17), (10, 18)],
        [(14, 15), (16, 15), (15, 16), (14, 17), (15, 18), (16, 17)],
        [(19, 15), (20, 16), (19, 17), (21, 17), (21, 15)],
        [(9, 22), (10, 22), (11, 23), (9, 24), (10, 25)],
        [(14, 22), (14, 23), (15, 24), (16, 23), (16, 22), (15, 25)],
        [(19, 22), (21, 22), (20, 23), (19, 25), (21, 24)],
    ]
    for gl in glyphs:
        S.pxs(gl, CYAN)
    S.line([(7, 27), (11, 25)], tint(SLATE, -0.35))
    S.line([(25, 20), (22, 23)], tint(SLATE, -0.35))


def _gear(S, cx, cy, r_out, r_in, n, color, hole):
    def draw(d):
        d.ellipse([cx - r_in, cy - r_in, cx + r_in, cy + r_in], fill=255)
        for i in range(n):
            a = 2 * math.pi * i / n + 0.2
            ca, sa = math.cos(a), math.sin(a)
            pts = []
            for rr, off in ((r_in - 1, -0.55), (r_out, -0.38), (r_out, 0.38), (r_in - 1, 0.55)):
                ang = a + off * (2 * math.pi / n) * 0.9
                pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
            d.polygon(pts, fill=255)
    S.fill(S.mask(draw), color)
    S.ell(cx, cy, hole, hole, C("#0e2a30"), bevel=False)
    S.px(cx, cy, CYAN) if hole > 1 else None


def forgotten_2(S):
    # Механизм на 118 шестерён: связка шестерёнок разного размера.
    _gear(S, 12, 17, 11, 8, 9, BRASS, 3)
    _gear(S, 24, 9, 7, 5, 7, tint(BRASS, -0.15), 1)
    _gear(S, 24, 24, 7, 5, 7, tint(BRASS, 0.05), 2)
    S.pxs([(8, 11), (9, 10)], GOLD_L)
    S.pxs([(12, 17)], CYAN)


def forgotten_3(S):
    # Карта звёздного неба, которого нет: латунный диск с чужими созвездиями.
    S.ell(16, 16, 14, 14, BRASS)
    S.ell(16, 16, 12, 12, NAVY, bevel=False)
    S.ell(16, 16, 12, 12, NAVY, bevel=False)
    for a in range(0, 360, 30):
        S.px(16 + round(math.cos(math.radians(a)) * 13), 16 + round(math.sin(math.radians(a)) * 13), BRASS)
    stars = [(8, 11), (13, 9), (19, 12), (24, 9), (22, 18), (15, 20), (10, 22)]
    for p, q in ((0, 1), (1, 2), (2, 3), (2, 4), (4, 5), (5, 6)):
        S.line([stars[p], stars[q]], C("#2f5c7a"))
    for x, y in stars:
        S.px(x, y, CYAN)
        S.px(x + 1, y, tint(CYAN, -0.3)); S.px(x, y + 1, tint(CYAN, -0.3))
    S.sparkle(13, 9, WHITE)
    S.pxs([(6, 16), (26, 15), (18, 25), (11, 6), (20, 5)], C("#8aa8d8"))


def forgotten_4(S):
    # Саркофаг не-человека: вытянутая голова с миндалевидными светящимися глазами.
    S.poly([(12, 2), (20, 2), (26, 10), (22, 29), (10, 29), (6, 10)], JADE)
    S.poly([(12, 4), (20, 4), (23, 10), (21, 15), (11, 15), (9, 10)], tint(JADE, -0.28), bevel=False)
    S.ell(16, 9, 4, 7, tint(JADE, 0.5))
    S.poly([(11, 8), (15, 8), (15, 11), (12, 10)], CYAN, bevel=False)  # косые глаза
    S.poly([(21, 8), (17, 8), (17, 11), (20, 10)], CYAN, bevel=False)
    S.px(14, 9, WHITE); S.px(18, 9, WHITE)
    S.pxs([(16, 14), (16, 15)], tint(JADE, -0.45))
    for y, hw in ((19, 5), (23, 5), (27, 4)):
        S.rect(16 - hw, y, 16 + hw, y + 1, GOLD, bevel=False)
    S.line([(12, 17), (20, 17)], tint(JADE, -0.3))


def forgotten_5(S):
    # Шлем безымянного зодчего: латунный купол, бирюзовая щель и отвес на гребне.
    S.ell(16, 15, 12, 12, BRASS)
    S.rect(4, 15, 28, 28, BRASS)
    S.rect(4, 15, 28, 28, BRASS)
    S.poly([(4, 24), (10, 28), (22, 28), (28, 24), (28, 29), (4, 29)], tint(BRASS, -0.25), bevel=False)
    S.rect(7, 16, 25, 21, C("#0b1c22"), bevel=False)                   # прорезь-забрало
    S.rect(9, 17, 23, 19, CYAN, bevel=False)
    S.rect(15, 16, 17, 21, BRASS, bevel=False)                         # перемычка
    S.rect(15, 3, 17, 11, SLATE)                                       # гребень
    S.poly([(16, 11), (13, 14), (19, 14)], tint(SLATE, -0.1), bevel=False)
    S.pxs([(8, 9), (9, 8), (10, 7)], GOLD_L)
    S.pxs([(7, 24), (25, 24)], tint(BRASS, 0.4))


# ============================================================================
# Ветка 5 — Легенды
# ============================================================================

def legends_1(S):
    # Клинок, рассёкший гору: меч входит между двумя половинами скалы.
    S.poly([(2, 29), (2, 23), (8, 16), (14, 22), (14, 29)], ROCK)
    S.poly([(18, 22), (24, 15), (30, 23), (30, 29), (18, 29)], ROCK)
    S.poly([(5, 24), (8, 20), (10, 24)], ROCK_D, bevel=False)
    S.poly([(21, 25), (24, 20), (27, 25)], ROCK_D, bevel=False)
    S.poly([(14, 10), (18, 10), (18, 24), (16, 28), (14, 24)], STEEL)
    S.rect(16, 11, 16, 24, WHITE, bevel=False)                         # дол
    S.line([(14, 12), (14, 23)], C("#9ec2ff"))
    S.rect(8, 8, 24, 10, GOLD)
    S.rect(14, 4, 18, 7, LEATHER)
    S.ell(16, 3, 2, 2, GOLD)
    S.pxs([(8, 8), (9, 8)], GOLD_L)
    S.sparkle(26, 9, WHITE); S.px(5, 12, C("#9ec2ff"))


def legends_2(S):
    # Молот, который не поднять: тяжёлая голова с рунами; земля под ним треснула.
    iron = C("#566486")
    g = lambda pts: shift(rot(pts, 28, 0, 0), 15, 12)
    S.poly(g([(-2, 0), (2, 0), (2, 20), (-2, 20)]), LEATHER)                   # рукоять
    S.poly(g([(-2, 15), (2, 15), (2, 17), (-2, 17)]), tint(LEATHER, 0.35), bevel=False)
    S.poly(g([(-11, -6), (11, -6), (11, 5), (-11, 5)]), iron)                   # голова
    S.poly(g([(-13, -7), (-10, -7), (-10, 6), (-13, 6)]), tint(iron, -0.2), bevel=False)
    S.poly(g([(10, -7), (13, -7), (13, 6), (10, 6)]), tint(iron, -0.2), bevel=False)
    S.poly(g([(-8, -3), (7, -3), (7, 2), (-8, 2)]), tint(iron, 0.3), bevel=False)
    S.poly(g([(0, -2), (3, 1), (-3, 1)]), C("#7ee8ff"), bevel=False)            # руна
    S.pxs(g([(-7, -2), (-6, -2), (5, 0), (6, 0)]), tint(iron, 0.7))
    S.line([(3, 29), (7, 27), (10, 29)], OUT_LEG)
    S.line([(18, 29), (23, 27), (28, 29)], OUT_LEG)


def legends_3(S):
    # Плащ, отменяющий тень: алый плащ с капюшоном и пунктиром там, где тени нет.
    S.poly([(10, 10), (22, 10), (27, 25), (16, 27), (5, 25)], CRIMSON)
    for x0, x1 in ((9, 11), (14, 15), (19, 21)):
        S.poly([(x0, 13), (x1, 13), (x1 + 1, 25), (x0 - 1, 25)], tint(CRIMSON, -0.25), bevel=False)
    S.ell(16, 8, 7, 6, tint(CRIMSON, -0.1))                              # капюшон
    S.ell(16, 9, 4, 4, C("#2a0d18"), bevel=False)
    S.ell(16, 12, 2, 2, GOLD)                                            # застёжка
    S.px(15, 11, GOLD_L)
    S.pxs([(8, 15), (7, 19), (12, 6)], tint(CRIMSON, 0.4))
    seen = []
    for k in range(48):                                                 # пунктир на месте отсутствующей тени
        a = 2 * math.pi * k / 48
        p = (16 + round(math.cos(a) * 12), 29 + round(math.sin(a) * 2))
        if p not in seen:
            seen.append(p)
    for i, p in enumerate(seen):
        if (i // 3) % 2 == 0:
            S.px(p[0], p[1], C("#a4abc4"))


def legends_4(S):
    # Ключ от всех дверей: золотой ключ с самоцветом в рукояти и разными бородками.
    def kp(pts):
        return shift(rot(pts, 45, 0, 0), 8, 8)
    S.poly(kp([(4, -2), (24, -2), (24, 2), (4, 2)]), GOLD)                     # стержень
    S.poly(kp([(18, 2), (21, 2), (21, 7), (18, 7)]), GOLD_D)                    # бородки
    S.poly(kp([(12, 2), (15, 2), (15, 5), (12, 5)]), GOLD_D)
    S.poly(kp([(22, 2), (25, 2), (25, 9), (22, 9)]), GOLD_D)
    S.ell(8, 8, 7, 7, GOLD)                                                      # головка
    S.ell(8, 8, 4, 4, OUT_LEG, bevel=False)
    S.ell(8, 8, 3, 3, BLUE, bevel=False)
    S.px(7, 7, WHITE); S.px(8, 7, C("#9ec2ff"))
    for ang in (0, 90, 180, 270):
        a = math.radians(ang + 45)
        S.px(8 + round(math.cos(a) * 7), 8 + round(math.sin(a) * 7), GOLD_L)
    S.sparkle(26, 8, WHITE)


def legends_5(S):
    # Перчатка Мироздания: латная рукавица с пятью гнёздами под камни дна.
    S.rect(8, 24, 24, 29, GOLD)
    S.rect(9, 14, 23, 25, STEEL_D)
    for x, top in ((9, 6), (13, 3), (17, 2), (21, 5)):
        S.rect(x, top, x + 2, 15, STEEL)
        S.rect(x, top, x + 2, top + 2, tint(STEEL, 0.25), bevel=False)
        S.line([(x, top + 6), (x + 2, top + 6)], STEEL_D)
    S.poly([(4, 15), (9, 18), (9, 23), (4, 20)], STEEL)                          # большой палец
    S.rect(9, 14, 23, 15, STEEL_D, bevel=False)
    gems = [C("#e8552a"), C("#4b2a8a"), C("#7ac8ff"), C("#fff0b0"), C("#ff6aa0")]
    for i, g in enumerate(gems):
        x = 10 + i * 3
        S.rect(x, 19, x + 1, 20, g, bevel=False)
        S.px(x, 19, tint(g, 0.5))
    S.rect(9, 17, 23, 17, GOLD, bevel=False)
    S.rect(9, 22, 23, 22, GOLD, bevel=False)
    S.pxs([(9, 26), (10, 26)], GOLD_L)
    S.sparkle(27, 8, WHITE); S.px(3, 10, GOLD_L)


ARTIFACTS = [
    ("antiquity_1", antiquity_1, OUT_ANT), ("antiquity_2", antiquity_2, OUT_ANT),
    ("antiquity_3", antiquity_3, OUT_ANT), ("antiquity_4", antiquity_4, OUT_ANT),
    ("antiquity_5", antiquity_5, OUT_ANT),
    ("mysticism_1", mysticism_1, OUT_MYS), ("mysticism_2", mysticism_2, OUT_MYS),
    ("mysticism_3", mysticism_3, OUT_MYS), ("mysticism_4", mysticism_4, OUT_MYS),
    ("mysticism_5", mysticism_5, OUT_MYS),
    ("occult_1", occult_1, OUT_OCC), ("occult_2", occult_2, OUT_OCC),
    ("occult_3", occult_3, OUT_OCC), ("occult_4", occult_4, OUT_OCC),
    ("occult_5", occult_5, OUT_OCC),
    ("forgotten_civilizations_1", forgotten_1, OUT_FOR), ("forgotten_civilizations_2", forgotten_2, OUT_FOR),
    ("forgotten_civilizations_3", forgotten_3, OUT_FOR), ("forgotten_civilizations_4", forgotten_4, OUT_FOR),
    ("forgotten_civilizations_5", forgotten_5, OUT_FOR),
    ("legends_1", legends_1, OUT_LEG), ("legends_2", legends_2, OUT_LEG),
    ("legends_3", legends_3, OUT_LEG), ("legends_4", legends_4, OUT_LEG),
    ("legends_5", legends_5, OUT_LEG),
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    images, labels = [], []
    for art_id, fn, outline in ARTIFACTS:
        S = Spr(32)
        fn(S)
        S.outline(outline)
        im = S.image()
        im.save(os.path.join(OUT_DIR, art_id + ".png"))
        images.append(im)
        labels.append(art_id.replace("forgotten_civilizations", "forgotten"))
    print("записано %d иконок в %s" % (len(images), os.path.normpath(OUT_DIR)))
    if "--sheet" in sys.argv:
        path = sys.argv[sys.argv.index("--sheet") + 1]
        contact_sheet(images, labels, 5, path)
        print("контактный лист:", path)


if __name__ == "__main__":
    main()

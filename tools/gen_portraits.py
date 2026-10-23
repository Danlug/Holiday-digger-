#!/usr/bin/env python3
"""gen_portraits.py — пиксель-бюсты говорящих для диалогов → art/dialogue/portrait_<id>.png.

Лист каждого персонажа: 64×64 на кадр; столбцы — кадры (0 «молчит», 1 «говорит» —
рот открыт, 2 «моргнул»), строки — выражения (EXPRESSIONS): нейтральное, удивление,
радость, злость, грусть. Узнаваемость — по одежде и причёске существующих спрайтов
art/character/* (цвета сняты с них): внук в синей футболке, бабка с пучком и очками
(бедная — коричневая кофта, богатая — тёмно-синий жакет и жемчуг), дед в майке и с
бородой (в экипировке — панама и жилет), Роберт в соломенной шляпе и комбинезоне.
У «Голоса» и «Родителей» спрайтов нет — для них силуэты.

Это заглушка уровня «программист нарисовал аккуратно», не работа художника владельца:
обводка 1 пиксель, три тона на материал, без антиалиасинга. Художник может подменить
PNG под теми же именами и той же раскладкой.

Запуск:   python3 tools/gen_portraits.py [--sheet предпросмотр.png]
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pix import Spr, hexc, tint  # noqa: E402
from PIL import Image  # noqa: E402

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "dialogue")
C = hexc
N = 64
CX = 32

EXPRESSIONS = ["neutral", "surprise", "happy", "angry", "sad"]
FRAMES = ["idle", "talk", "blink"]

OUTLINE = C("#24170f")
MOUTH_D = C("#5a2420")
MOUTH_IN = C("#2e0f10")
TONGUE = C("#c4605a")
TEETH = C("#f4ecd8")
WHITE = C("#f6f0e4")
EYE_D = C("#2a1a14")


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)


class P(Spr):
    def pat(self, x, y, rows, cmap):
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch != "." and ch in cmap:
                    self.px(x + i, y + j, cmap[ch])

    def seg(self, p0, p1, color, w=1):
        """Отрезок по Брезенхему, толщина w (по вертикали)."""
        (x0, y0), (x1, y1) = p0, p1
        dx, dy = abs(x1 - x0), abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        while True:
            for k in range(w):
                self.px(x0, y0 + k, color)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x0 += sx
            if e2 < dx:
                err += dx
                y0 += sy


# ---------------------------------------------------------------------------
# Кожа и общие части лица
# ---------------------------------------------------------------------------

class Skin:
    def __init__(self, base, shade=None, light=None, blush="#e8907c"):
        self.base = C(base)
        self.shade = C(shade) if shade else tint(self.base, -0.17)
        self.dark = tint(self.base, -0.32)
        self.light = C(light) if light else tint(self.base, 0.22)
        self.blush = C(blush)


def head(S, sk, rx=14, ry=16, cy=28, chin=0, ears=True):
    """Голова: тень по низу/правому краю, свет сверху-слева."""
    if ears:
        for sx in (-1, 1):
            S.ell(CX + sx * (rx + 1), cy + 2, 3, 4, sk.shade, bevel=False)
            S.px(CX + sx * (rx + 1), cy + 2, sk.dark)
    S.ell(CX, cy, rx, ry, sk.shade, bevel=False)
    S.ell(CX - 1, cy - 1, rx - 1, ry - 1, sk.base, bevel=False)
    S.ell(CX - 4, cy - 6, 5, 4, sk.light, bevel=False)
    # подбородок чуть уже
    S.ell(CX - 1, cy - 1, rx - 1, ry - 1, sk.base, bevel=False)
    S.ell(CX - 5, cy - 7, 4, 3, mix(sk.base, sk.light, 0.6), bevel=False)


def neck(S, sk, y0=41, y1=52, w=5):
    S.rect(CX - w, y0, CX + w, y1, sk.shade, bevel=False)
    S.rect(CX - w, y0, CX + w - 3, y1, sk.base, bevel=False)
    S.rect(CX - w, y0, CX + w, y0 + 3, sk.dark, bevel=False)


def nose(S, sk, y=32, size=1):
    S.pxs([(CX, y - 1), (CX, y), (CX + 1, y + 1)], sk.dark)
    S.px(CX - 1, y + 1, sk.shade)
    S.px(CX - 1, y - 2, sk.light)


# ---------------------------------------------------------------------------
# Глаза, брови, рот
# ---------------------------------------------------------------------------

EYE_OPEN = ["###", "#.#", "###"]  # заменяется ниже явной отрисовкой


def eyes(S, kind, ex, ey, col=EYE_D, lid=None, wide_col=None, lash=None):
    """Рисует пару глаз. ex — смещение от центра, ey — y верхней точки."""
    for side in (-1, 1):
        x = CX + side * ex
        if kind == "open":
            S.rect(x - 1, ey, x + 1, ey + 3, col, bevel=False)
            S.px(x - 1, ey + 1, WHITE)
            S.rect(x - 2, ey - 1, x + 2, ey - 1, lash or lid or col, bevel=False)
        elif kind == "narrow":
            S.rect(x - 1, ey + 1, x + 1, ey + 3, col, bevel=False)
            S.rect(x - 2, ey, x + 2, ey, lid or col, bevel=False)
            S.px(x - 1, ey + 2, WHITE)
        elif kind == "down":
            S.rect(x - 1, ey + 1, x + 1, ey + 4, col, bevel=False)
            S.rect(x - 2, ey, x + 2, ey, lid or col, bevel=False)
            S.px(x, ey + 3, WHITE)
        elif kind == "wide":
            S.pat(x - 3, ey - 1, [
                ".OOO.",
                "OWWWO",
                "OWDDO",
                "OWDDO",
                "OWWWO",
                ".OOO.",
            ], {"O": OUTLINE, "W": WHITE, "D": col})
            S.px(x - 1, ey + 1, WHITE)
        elif kind == "happy":
            S.pat(x - 2, ey + 1, [
                ".###.",
                "#...#",
            ], {"#": col})
        elif kind == "closed":
            S.rect(x - 2, ey + 2, x + 2, ey + 2, col, bevel=False)
            S.px(x - 2, ey + 3, tint(col, 0.2))
            S.px(x + 2, ey + 3, tint(col, 0.2))


def brows(S, kind, ex, by, col, thick=1):
    for side in (-1, 1):
        o = CX + side * (ex + 3)   # внешний край
        i = CX + side * (ex - 3)   # внутренний край
        if kind == "flat":
            S.seg((o, by + 1), (i, by), col, thick)
        elif kind == "high":
            S.seg((o, by - 1), (i, by - 3), col, thick)
        elif kind == "arch":
            mid = CX + side * ex
            S.seg((o, by), (mid, by - 2), col, thick)
            S.seg((mid, by - 2), (i, by - 1), col, thick)
        elif kind == "angry":
            S.seg((o, by - 1), (i, by + 2), col, thick)
        elif kind == "sad":
            S.seg((o, by + 2), (i, by - 1), col, thick)


def mouth(S, kind, y, sk, col=MOUTH_D, wide=1):
    x = CX
    w = wide
    if kind == "line":
        S.rect(x - 2 - w, y, x + 2 + w, y, col, bevel=False)
        S.rect(x - 1, y + 1, x + 1, y + 1, mix(sk.base, col, 0.35), bevel=False)
    elif kind == "talk":
        S.ell(x, y + 1, 3 + w, 2, MOUTH_IN, bevel=False)
        S.rect(x - 1, y + 2, x + 1, y + 2, TONGUE, bevel=False)
        S.rect(x - 2 - w, y - 1, x + 2 + w, y - 1, col, bevel=False)
    elif kind == "smile":
        S.pat(x - 4 - w, y - 1, [
            "#" + "." * (5 + 2 * w) + "#",
            "." + "#" * (5 + 2 * w) + ".",
        ], {"#": col})
        S.px(x - 5 - w, y - 2, mix(sk.base, col, 0.4))
        S.px(x + 5 + w, y - 2, mix(sk.base, col, 0.4))
    elif kind == "grin":
        wd = 4 + w
        S.rect(x - wd, y - 1, x + wd, y - 1, col, bevel=False)
        S.rect(x - wd + 1, y, x + wd - 1, y + 1, MOUTH_IN, bevel=False)
        S.rect(x - wd + 2, y, x + wd - 2, y, TEETH, bevel=False)
        S.rect(x - 1, y + 1, x + 1, y + 1, TONGUE, bevel=False)
        S.rect(x - wd + 2, y + 2, x + wd - 2, y + 2, col, bevel=False)
    elif kind == "o":
        S.ell(x, y + 1, 2, 3, MOUTH_IN, bevel=False)
        S.pat(x - 3, y - 2, [
            ".###.",
            "#...#",
            "#...#",
            "#...#",
            "#...#",
            ".###.",
        ], {"#": col})
    elif kind == "o_big":
        S.ell(x, y + 1, 3, 4, MOUTH_IN, bevel=False)
        S.pat(x - 4, y - 3, [
            "..###..",
            ".#...#.",
            "#.....#",
            "#.....#",
            "#.....#",
            "#.....#",
            ".#...#.",
            "..###..",
        ], {"#": col})
        S.rect(x - 1, y + 3, x + 1, y + 3, TONGUE, bevel=False)
    elif kind == "frown":
        S.pat(x - 3 - w, y - 1, [
            "." + "#" * (5 + 2 * w) + ".",
            "#" + "." * (5 + 2 * w) + "#",
        ], {"#": col})
    elif kind == "shout":
        wd = 3 + w
        S.rect(x - wd, y - 1, x + wd, y - 1, col, bevel=False)
        S.rect(x - wd + 1, y, x + wd - 1, y + 2, MOUTH_IN, bevel=False)
        S.rect(x - wd + 1, y, x + wd - 1, y, TEETH, bevel=False)
        S.rect(x - 1, y + 2, x + 1, y + 2, TONGUE, bevel=False)
        S.rect(x - wd + 1, y + 3, x + wd - 1, y + 3, col, bevel=False)
    elif kind == "sad":
        S.pat(x - 2, y, [
            ".###.",
            "#...#",
        ], {"#": col})
    elif kind == "sad_talk":
        S.ell(x, y + 1, 2, 2, MOUTH_IN, bevel=False)
        S.rect(x - 1, y + 2, x + 1, y + 2, TONGUE, bevel=False)
        S.rect(x - 2, y - 1, x + 2, y - 1, col, bevel=False)


# Выражение -> (глаза, брови, рот молчит, рот говорит)
EXPR = {
    "neutral": ("open", "flat", "line", "talk"),
    "surprise": ("wide", "high", "o", "o_big"),
    "happy": ("happy", "arch", "smile", "grin"),
    "angry": ("narrow", "angry", "frown", "shout"),
    "sad": ("down", "sad", "sad", "sad_talk"),
}


def face(S, sk, expr, talk, blink, *, ex=7, ey=26, by=22, my=38, brow_col, brow_w=1,
         lash=None, lid=None, eye_col=EYE_D, wide_mouth=1, cheeks=True, brow_ex=None):
    eye_kind, brow_kind, m_idle, m_talk = EXPR[expr]
    if blink and eye_kind in ("open", "narrow", "down"):
        eye_kind = "closed"
    eyes(S, eye_kind, ex, ey, eye_col, lid=lid or sk.dark, lash=lash)
    brows(S, brow_kind, brow_ex if brow_ex is not None else ex, by, brow_col, brow_w)
    mouth(S, m_talk if talk else m_idle, my, sk, wide=wide_mouth)
    if expr == "happy" and cheeks:
        for sx in (-1, 1):
            S.pxs([(CX + sx * 11, 33), (CX + sx * 11 + 1, 33), (CX + sx * 12, 32)], sk.blush)
    if expr == "angry":
        S.pxs([(CX - 1, 20), (CX + 1, 20)], sk.dark)    # складка на переносице
    if expr == "sad":
        S.px(CX + 10, ey + 5, C("#8fc4e8"))               # слезинка у края глаза


def wrinkles(S, sk, n=1):
    for sx in (-1, 1):
        S.pxs([(CX + sx * 11, 29), (CX + sx * 12, 31)], sk.dark)
        S.pxs([(CX + sx * 5, 35), (CX + sx * 6, 37), (CX + sx * 6, 38)], sk.dark)
    if n > 1:
        S.rect(CX - 5, 17, CX + 5, 17, sk.shade, bevel=False)


# ---------------------------------------------------------------------------
# Тело
# ---------------------------------------------------------------------------

def shoulders(S, color, y_top=48, sx=22, outer=2, y_bot=64):
    S.poly([(outer, y_bot), (outer + 2, y_top + 6), (CX - sx // 2 - 4, y_top),
            (CX + sx // 2 + 4, y_top), (N - outer - 2, y_top + 6), (N - outer, y_bot)], color)


# ---------------------------------------------------------------------------
# Персонажи
# ---------------------------------------------------------------------------

def boy(expr, talk, blink, gear=False):
    S = P(N)
    sk = Skin("#e0b090", "#c58f6c")
    hair = C("#604030")
    hair_d = C("#402818")
    hair_l = C("#80583a")
    if not gear:
        tee = C("#486898")
        S.poly([(4, 64), (6, 55), (14, 49), (24, 46), (40, 46), (50, 49), (58, 55), (60, 64)], tee)
        S.pxs([(8 + i, 55 - i // 2) for i in range(0, 8)], tint(tee, 0.22))
    else:
        shirt = C("#7c8a58")
        vest = C("#c0b888")
        S.poly([(4, 64), (6, 55), (14, 49), (24, 46), (40, 46), (50, 49), (58, 55), (60, 64)], shirt)
        S.poly([(6, 64), (8, 56), (16, 50), (25, 48), (27, 64)], vest)
        S.poly([(58, 64), (56, 56), (48, 50), (39, 48), (37, 64)], vest)
        S.rect(10, 57, 17, 61, tint(vest, -0.2))
        S.rect(47, 57, 54, 61, tint(vest, -0.2))
        S.rect(11, 58, 16, 58, tint(vest, 0.2), bevel=False)
        S.line([(46, 47), (14, 64)], C("#5a4630"), w=3)       # ремень сумки
        S.poly([(24, 46), (40, 46), (36, 52), (28, 52)], tint(shirt, -0.3), bevel=False)
    neck(S, sk)
    # круглый ворот: тёмная кромка и кожа внутри
    cc = tint(C("#486898") if not gear else C("#7c8a58"), -0.4)
    S.poly([(CX - 8, 46), (CX - 6, 51), (CX, 53), (CX + 6, 51), (CX + 8, 46)], cc, bevel=False)
    S.poly([(CX - 6, 46), (CX - 4, 49), (CX, 51), (CX + 4, 49), (CX + 6, 46)], sk.shade, bevel=False)
    head(S, sk)
    # волосы: шапка с чёлкой набок
    S.ell(CX, 17, 17, 11, hair)
    S.rect(15, 18, 19, 28, hair)
    S.rect(45, 18, 49, 28, hair)
    S.ell(CX, 24, 12, 6, sk.base, bevel=False)                  # лоб
    S.poly([(18, 25), (19, 17), (26, 13), (38, 12), (45, 15), (46, 25), (44, 19), (40, 16), (34, 16), (29, 18),
            (25, 20), (21, 21)], hair)
    S.poly([(34, 16), (40, 16), (44, 19), (46, 25), (43, 22), (39, 19)], hair_d, bevel=False)
    S.pxs([(22, 15), (25, 13), (28, 12), (32, 11), (37, 11)], hair_l)
    S.pxs([(16, 25), (47, 25), (16, 27), (47, 27)], hair_d)
    face(S, sk, expr, talk, blink, brow_col=hair_d, by=22, ey=26)
    nose(S, sk)
    S.outline(OUTLINE)
    return S.image()


def grandma(expr, talk, blink, rich=False):
    S = P(N)
    sk = Skin("#e6bd9c", "#cb9a78")
    hair = C("#c8c8c8")
    hair_d = C("#9a9aa0")
    hair_l = C("#e8e8e8")
    if rich:
        navy = C("#303850")
        S.poly([(4, 64), (6, 55), (14, 49), (24, 46), (40, 46), (50, 49), (58, 55), (60, 64)], navy)
        S.poly([(22, 46), (CX, 64), (42, 46), (CX, 52)], C("#7a7e8c"), bevel=False)         # блузка
        S.poly([(22, 46), (30, 64), (CX, 56), (CX - 2, 50)], tint(navy, 0.12))             # лацканы
        S.poly([(42, 46), (34, 64), (CX, 56), (CX + 2, 50)], tint(navy, 0.04))
        S.pxs([(CX - 1, 56), (CX + 1, 56)], C("#d8b45a"))
    else:
        card = C("#786050")
        dress = C("#708060")
        S.poly([(4, 64), (6, 55), (14, 49), (24, 46), (40, 46), (50, 49), (58, 55), (60, 64)], card)
        S.poly([(22, 46), (24, 64), (40, 64), (42, 46), (CX, 54)], dress)
        S.poly([(24, 46), (CX, 54), (40, 46), (36, 46), (CX, 50), (28, 46)], C("#e8dcc0"), bevel=False)
        S.pxs([(CX, 58), (CX, 61)], C("#c8b898"))
    neck(S, sk)
    if rich:
        for i, (dx, dy) in enumerate([(-6, 47), (-4, 49), (-2, 50), (0, 51), (2, 50), (4, 49), (6, 47)]):
            S.px(CX + dx, dy, C("#f4f0e8"))
            S.px(CX + dx, dy + 1, C("#b8b4a8"))
    else:
        S.pxs([(CX - 6, 46), (CX - 5, 47), (CX + 5, 47), (CX + 6, 46)], C("#e8dcc0"))
    # пучок на макушке, за головой
    S.ell(CX - 8, 6, 6, 5, hair)
    S.pxs([(CX - 12, 5), (CX - 11, 3), (CX - 8, 2)], hair_l)
    S.pxs([(CX - 5, 8), (CX - 4, 6)], hair_d)
    head(S, sk, rx=14, ry=15, cy=28)
    # волосы: волна вокруг лица, пробор
    S.ell(CX, 17, 17, 11, hair)
    for sx in (-1, 1):
        S.poly([(CX + sx * 14, 18), (CX + sx * 18, 22), (CX + sx * 18, 29), (CX + sx * 16, 33),
                (CX + sx * 13, 30), (CX + sx * 13, 22)], hair)
    S.ell(CX, 25, 12, 7, sk.base, bevel=False)
    S.poly([(19, 27), (19, 19), (24, 13), (32, 11), (40, 13), (45, 19), (45, 27), (43, 22), (38, 18), (32, 17),
            (26, 18), (21, 22)], hair)
    S.pxs([(CX, 12), (CX, 14), (CX, 16)], hair_d)
    S.pxs([(20, 16), (24, 13), (28, 12), (35, 12), (40, 14)], hair_l)
    S.pxs([(15, 25), (15, 29), (49, 25), (49, 29)], hair_d)
    face(S, sk, expr, talk, blink, ey=26, by=21, brow_col=hair_d, lash=None, wide_mouth=0)
    wrinkles(S, sk)
    nose(S, sk, y=32)
    # очки поверх глаз
    frame = C("#3a3038") if not rich else C("#2c2a3c")
    for sx in (-1, 1):
        x0 = CX + sx * 7 - 5
        S.pat(x0, 23, [
            "##########",
            "#........#",
            "#........#",
            "#........#",
            "#........#",
            "#........#",
            "#........#",
            ".########.",
        ], {"#": frame})
        S.pxs([(x0 + 2, 24), (x0 + 3, 24)], C("#e8f4f8"))
    S.pxs([(CX - 1, 25), (CX, 25), (CX + 1, 25)], frame)
    S.pxs([(CX - 12, 25), (CX - 13, 24), (CX + 12, 25), (CX + 13, 24)], frame)
    if rich:
        for sx in (-1, 1):
            S.px(CX + sx * 15, 34, C("#f4f0e8"))
            S.px(CX + sx * 15, 35, C("#d8b45a"))
    S.outline(OUTLINE)
    return S.image()


def grandpa(expr, talk, blink, gear=False):
    S = P(N)
    sk = Skin("#dcaa84", "#c08e68")
    hair = C("#e8e8d8")
    hair_d = C("#a8a8a0")
    hair_l = C("#fffff4")
    if not gear:
        tank = C("#e8e0d8")
        S.poly([(4, 64), (6, 56), (14, 50), (24, 47), (40, 47), (50, 50), (58, 56), (60, 64)], sk.base)   # плечи
        S.poly([(12, 64), (16, 54), (22, 47), (28, 47), (30, 54), (CX - 2, 56), (CX + 2, 56), (34, 54), (36, 47),
                (42, 47), (48, 54), (52, 64)], tank)
        S.rect(23, 47, 27, 48, tint(tank, -0.18), bevel=False)
        S.rect(37, 47, 41, 48, tint(tank, -0.18), bevel=False)
        S.pxs([(CX - 5, 58), (CX + 5, 58), (CX - 6, 60), (CX + 6, 60)], tint(tank, -0.2))
        neck(S, sk)
        S.poly([(24, 47), (CX, 55), (40, 47), (36, 47), (CX, 51), (28, 47)], tint(sk.base, -0.1), bevel=False)
    else:
        shirt = C("#e0d8c8")
        vest = C("#c0b088")
        S.poly([(4, 64), (6, 55), (14, 49), (24, 46), (40, 46), (50, 49), (58, 55), (60, 64)], shirt)
        S.poly([(6, 64), (8, 56), (16, 50), (25, 48), (28, 64)], vest)
        S.poly([(58, 64), (56, 56), (48, 50), (39, 48), (36, 64)], vest)
        S.rect(10, 57, 17, 61, tint(vest, -0.2))
        S.rect(47, 57, 54, 61, tint(vest, -0.2))
        S.poly([(24, 46), (40, 46), (36, 52), (28, 52)], tint(shirt, -0.25), bevel=False)
        neck(S, sk)
        S.pxs([(CX - 5, 47), (CX + 5, 47)], tint(shirt, -0.3))
    head(S, sk, rx=14, ry=16, cy=28)
    # борода: от висков вниз, густая; усы
    beard = hair
    S.poly([(16, 30), (19, 36), (22, 42), (28, 47), (CX, 49), (36, 47), (42, 42), (45, 36), (48, 30),
            (44, 34), (38, 36), (CX, 35), (26, 36), (20, 34)], beard)
    S.pxs([(18, 36), (19, 40), (22, 44), (26, 46), (38, 46), (42, 44), (45, 40), (46, 36)], hair_d)
    S.pxs([(24, 41), (28, 44), (36, 44), (40, 41)], hair_l)
    # усы
    S.poly([(24, 36), (28, 34), (CX, 35), (36, 34), (40, 36), (36, 38), (CX, 37), (28, 38)], hair)
    S.pxs([(24, 37), (28, 38), (36, 38), (40, 37)], hair_d)
    # волосы: сверху лысина, по бокам седые пряди
    if not gear:
        S.poly([(15, 30), (14, 20), (18, 13), (22, 12), (20, 18), (19, 26), (21, 32)], hair)
        S.poly([(49, 30), (50, 20), (46, 13), (42, 12), (44, 18), (45, 26), (43, 32)], hair)
        S.pxs([(18, 14), (17, 17), (46, 14), (47, 17)], hair_l)
        S.pxs([(20, 16), (45, 16)], hair_d)
        # лоб в морщинах
        S.rect(CX - 6, 17, CX + 6, 17, sk.shade, bevel=False)
        S.rect(CX - 4, 14, CX + 4, 14, sk.shade, bevel=False)
    face(S, sk, expr, talk, blink, ey=26, by=21, brow_col=hair_d, brow_w=2, my=39,
         wide_mouth=0, brow_ex=7)
    # рот прячется в усах: не дублируем усы поверх выражения
    wrinkles(S, sk)
    nose(S, sk, y=31)
    if gear:
        hat = C("#c0b088")
        hat_d = C("#8c7c58")
        S.ell(CX, 16, 27, 6, hat)                                  # поля
        S.rect(CX - 27, 17, CX + 27, 18, hat_d, bevel=False)
        S.ell(CX, 10, 15, 9, hat)
        S.rect(CX - 15, 14, CX + 15, 16, hat_d, bevel=False)
        S.pxs([(CX - 8, 5), (CX - 5, 3), (CX, 2)], tint(hat, 0.3))
    S.outline(OUTLINE)
    return S.image()


def robert(expr, talk, blink):
    S = P(N)
    sk = Skin("#dc9e78", "#bd7f5c")
    beard = C("#a89888")
    beard_d = C("#7a6a5c")
    brown = C("#7a6650")
    denim = C("#587890")
    hat = C("#d49a64")
    hat_d = C("#a8703c")
    # рубашка + комбинезон
    S.poly([(4, 64), (6, 55), (14, 49), (24, 46), (40, 46), (50, 49), (58, 55), (60, 64)], brown)
    S.poly([(18, 64), (20, 52), (26, 47), (30, 47), (32, 56), (CX + 0, 56), (34, 47), (38, 47), (44, 52),
            (46, 64)], denim)
    S.rect(21, 47, 25, 55, denim)                           # лямки
    S.rect(39, 47, 43, 55, denim)
    S.rect(24, 57, 40, 63, tint(denim, 0.1))                  # нагрудный карман
    S.rect(24, 57, 40, 58, tint(denim, -0.25), bevel=False)
    S.pxs([(23, 55), (41, 55)], C("#e0c060"))
    neck(S, sk)
    S.poly([(26, 46), (CX, 52), (38, 46)], tint(sk.base, -0.1), bevel=False)
    head(S, sk, rx=14, ry=16, cy=28)
    # щетина: лицо внизу и вдоль щёк
    S.poly([(17, 31), (20, 38), (25, 44), (CX, 46), (39, 44), (44, 38), (47, 31), (43, 35), (38, 36), (CX, 35),
            (26, 36), (21, 35)], beard)
    S.pxs([(20, 40), (24, 44), (CX, 45), (40, 44), (44, 40)], beard_d)
    S.poly([(26, 36), (30, 35), (CX, 36), (34, 35), (38, 36), (35, 37), (CX, 36), (29, 37)], beard_d, bevel=False)
    face(S, sk, expr, talk, blink, ey=26, by=21, brow_col=C("#4a3626"), brow_w=2, my=40,
         wide_mouth=0, brow_ex=7)
    wrinkles(S, sk)
    nose(S, sk, y=31)
    # соломенная шляпа: поля эллипсом, тулья, лента
    S.ell(CX, 16, 28, 7, hat)
    S.rect(CX - 28, 17, CX + 28, 19, hat_d, bevel=False)
    S.ell(CX, 10, 16, 10, hat)
    S.rect(CX - 16, 13, CX + 16, 15, C("#7a4a2a"), bevel=False)                   # лента
    for x in range(CX - 26, CX + 27, 4):
        S.px(x, 16, hat_d)
    for x, y in [(CX - 8, 4), (CX - 3, 3), (CX + 4, 4), (CX - 11, 8), (CX + 8, 8)]:
        S.px(x, y, tint(hat, 0.25))
    S.outline(OUTLINE)
    return S.image()


def parents(expr, talk, blink):
    """Двое: мама и папа, головы поменьше — пара в одном кадре."""
    S = P(N)
    # папа справа (сзади), мама слева (спереди)
    sk_d = Skin("#d9a47e", "#be8764")
    sk_m = Skin("#ecc4a2", "#d0a07e")
    # плечи папы
    S.poly([(26, 64), (28, 54), (36, 49), (50, 49), (60, 54), (62, 64)], C("#5a6070"))
    S.poly([(44, 49), (50, 56), (56, 49)], C("#e8e8e8"), bevel=False)
    # шея и голова папы
    S.rect(46, 44, 52, 51, sk_d.shade, bevel=False)
    S.ell(49, 33, 10, 12, sk_d.shade, bevel=False)
    S.ell(48, 32, 9, 11, sk_d.base, bevel=False)
    S.ell(49, 22, 11, 7, C("#3a2a20"))
    S.rect(38, 22, 40, 30, C("#3a2a20"))
    S.rect(58, 22, 60, 30, C("#3a2a20"))
    S.ell(49, 28, 8, 4, sk_d.base, bevel=False)
    S.rect(41, 40, 57, 42, C("#6a5a4a"), bevel=False)
    # плечи мамы
    S.poly([(0, 64), (2, 56), (8, 50), (18, 47), (28, 49), (34, 56), (34, 64)], C("#7a4a58"))
    S.rect(15, 42, 21, 49, sk_m.shade, bevel=False)
    S.ell(18, 31, 11, 13, sk_m.shade, bevel=False)
    S.ell(17, 30, 10, 12, sk_m.base, bevel=False)
    # каре
    S.ell(18, 21, 13, 10, C("#6a4630"))
    S.rect(5, 21, 9, 38, C("#6a4630"))
    S.rect(27, 21, 31, 38, C("#6a4630"))
    S.ell(18, 28, 9, 6, sk_m.base, bevel=False)
    S.poly([(10, 27), (11, 20), (18, 17), (26, 20), (27, 27), (24, 23), (18, 22), (12, 24)], C("#6a4630"))
    # лица: упрощённо, выражения — глаза/рот
    for (cx, ey, my, col) in ((18, 28, 38, C("#3a2a20")), (49, 30, 41, C("#2a1a14"))):
        eye_kind, brow_kind, m_idle, m_talk = EXPR[expr]
        if blink and eye_kind in ("open", "narrow", "down"):
            eye_kind = "closed"
        sub = P(N)
        sub_eyes = {"wide": "wide"}.get(eye_kind, eye_kind)
        for side in (-1, 1):
            x = cx + side * 4
            if sub_eyes == "open" or sub_eyes in ("narrow", "down"):
                S.rect(x, ey, x, ey + 2, EYE_D, bevel=False)
                S.px(x, ey, WHITE if False else EYE_D)
            elif sub_eyes == "wide":
                S.rect(x - 1, ey - 1, x + 1, ey + 3, WHITE, bevel=False)
                S.rect(x, ey, x, ey + 2, EYE_D, bevel=False)
            elif sub_eyes == "happy":
                S.pxs([(x - 1, ey + 1), (x, ey), (x + 1, ey + 1)], EYE_D)
            else:
                S.rect(x - 1, ey + 1, x + 1, ey + 1, EYE_D, bevel=False)
        by = ey - 4
        for side in (-1, 1):
            o, i = cx + side * 6, cx + side * 2
            if brow_kind == "angry":
                S.seg((o, by - 1), (i, by + 1), col)
            elif brow_kind == "sad":
                S.seg((o, by + 1), (i, by - 1), col)
            elif brow_kind == "high":
                S.seg((o, by - 1), (i, by - 2), col)
            else:
                S.seg((o, by), (i, by), col)
        mk = m_talk if talk else m_idle
        if mk in ("line",):
            S.rect(cx - 2, my, cx + 2, my, MOUTH_D, bevel=False)
        elif mk in ("talk", "sad_talk"):
            S.ell(cx, my, 2, 1, MOUTH_IN, bevel=False)
        elif mk == "smile":
            S.pxs([(cx - 3, my - 1), (cx - 2, my), (cx - 1, my), (cx, my), (cx + 1, my), (cx + 2, my),
                   (cx + 3, my - 1)], MOUTH_D)
        elif mk == "grin":
            S.rect(cx - 3, my - 1, cx + 3, my + 1, MOUTH_IN, bevel=False)
            S.rect(cx - 2, my - 1, cx + 2, my - 1, TEETH, bevel=False)
        elif mk in ("o", "o_big"):
            S.ell(cx, my, 1, 2, MOUTH_IN, bevel=False)
        elif mk in ("frown", "shout"):
            S.pxs([(cx - 2, my + 1), (cx - 1, my), (cx, my), (cx + 1, my), (cx + 2, my + 1)], MOUTH_D)
        elif mk == "sad":
            S.pxs([(cx - 1, my + 1), (cx, my), (cx + 1, my + 1)], MOUTH_D)
    S.outline(OUTLINE)
    return S.image()


def voice(expr, talk, blink):
    """Голос из глубины: тёмный силуэт в капюшоне, глаза — холодные жёлтые огоньки."""
    S = P(N)
    cloak = C("#1c1626")
    cloak_l = C("#3a2e4c")
    glow = C("#f2c230")
    glow_l = C("#fff0a0")
    S.poly([(2, 64), (6, 52), (16, 46), (24, 44), (40, 44), (48, 46), (58, 52), (62, 64)], cloak)
    S.poly([(6, 64), (10, 54), (18, 49), (22, 64)], cloak_l, bevel=False)
    # капюшон
    S.ell(CX, 26, 19, 21, cloak, bevel=False)
    S.poly([(CX - 19, 38), (CX - 20, 22), (CX - 12, 8), (CX, 4), (CX + 12, 8), (CX + 20, 22), (CX + 19, 38),
            (CX + 12, 46), (CX - 12, 46)], cloak)
    S.pxs([(CX - 14, 12), (CX - 10, 8), (CX - 5, 6), (CX, 5)], cloak_l)
    # пустота лица
    S.ell(CX, 29, 12, 14, C("#07050c"), bevel=False)
    # глаза-огоньки по выражению
    ey = 27
    if blink:
        for sx in (-1, 1):
            S.rect(CX + sx * 6 - 2, ey + 1, CX + sx * 6 + 2, ey + 1, glow, bevel=False)
    else:
        for sx in (-1, 1):
            x = CX + sx * 6
            if expr == "surprise":
                S.rect(x - 2, ey - 2, x + 2, ey + 3, glow, bevel=False)
                S.rect(x - 1, ey - 1, x + 1, ey + 2, glow_l, bevel=False)
            elif expr == "angry":
                S.rect(x - 2, ey, x + 2, ey + 2, glow, bevel=False)
                S.seg((x - 2 * sx, ey - 2), (x + 2 * sx, ey), C("#07050c"), 2)
            elif expr == "happy":
                S.pat(x - 2, ey, [".###.", "#...#"], {"#": glow})
            elif expr == "sad":
                S.rect(x - 1, ey + 1, x + 1, ey + 3, glow, bevel=False)
            else:
                S.rect(x - 1, ey, x + 1, ey + 3, glow, bevel=False)
                S.px(x - 1, ey, glow_l)
    # рот: тонкая светящаяся щель, шире, пока «говорит»
    if talk:
        S.rect(CX - 3, 38, CX + 3, 39, glow, bevel=False)
        S.rect(CX - 2, 38, CX + 2, 38, glow_l, bevel=False)
    else:
        S.rect(CX - 2, 38, CX + 2, 38, tint(glow, -0.45), bevel=False)
    S.outline(C("#0a0710"))
    return S.image()


CHARACTERS = {
    "boy": lambda e, t, b: boy(e, t, b, gear=False),
    "boy_gear": lambda e, t, b: boy(e, t, b, gear=True),
    "grandma_poor": lambda e, t, b: grandma(e, t, b, rich=False),
    "grandma_rich": lambda e, t, b: grandma(e, t, b, rich=True),
    "grandpa": lambda e, t, b: grandpa(e, t, b, gear=False),
    "grandpa_gear": lambda e, t, b: grandpa(e, t, b, gear=True),
    "robert": robert,
    "parents": parents,
    "voice": voice,
}


def sheet_for(draw):
    sheet = Image.new("RGBA", (N * len(FRAMES), N * len(EXPRESSIONS)), (0, 0, 0, 0))
    for r, expr in enumerate(EXPRESSIONS):
        for c, fr in enumerate(FRAMES):
            im = draw(expr, fr == "talk", fr == "blink")
            sheet.paste(im, (c * N, r * N))
    return sheet


def preview(sheets, path, scale=3):
    ids = list(sheets.keys())
    w, h = sheets[ids[0]].size
    cols = len(ids)
    pv = Image.new("RGBA", (cols * w * scale + 8 * (cols + 1), h * scale + 16), (58, 50, 66, 255))
    for i, cid in enumerate(ids):
        big = sheets[cid].resize((w * scale, h * scale), Image.NEAREST)
        pv.alpha_composite(big, (8 + i * (w * scale + 8), 8))
    pv.save(path)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    sheets = {}
    for cid, fn in CHARACTERS.items():
        sh = sheet_for(fn)
        sh.save(os.path.join(OUT_DIR, "portrait_%s.png" % cid))
        sheets[cid] = sh
    if "--sheet" in sys.argv:
        preview(sheets, sys.argv[sys.argv.index("--sheet") + 1])
    print("портреты:", ", ".join(CHARACTERS))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_grave.py — могила деда во дворе (ветка «grave», раунд 5).

Слова владельца: «Могила деда не похожа на могилу, сделай могилу с пиксельной гравировкой его портрета».

Что рисует (art/env/):
  grave.png       — холмик с травой и цветами, надгробие (гранит с фаской, сколами, лишайником) и лежачая
                    плита на месте: до сцены diary_first.
  grave_open.png  — то же, но плита сдвинута к надгробию, справа виден тайник (яма под плитой): после сцены;
                    банку в яму ставит GraveSite отдельным спрайтом.
  grave_jar.png   — жестяная банка из-под чая, из неё торчит тетрадь (32x32).

Сетка: 2 текстурных пикселя на игровой (GraveSite.STONE_SCALE = 0.5; в сценах scale 1.5 при ART_SCALE 3).
Тайлы мира — 1:1, авторские кадры героя и декор огорода — 3:1; могила между ними: гравировке нужна сетка
мельче тайла, иначе портрет не узнать, а 3:1 на экране 448x960 даёт дробный пиксель.

Портрет — по авторскому деду (art/_source/characters_sheet.jpg, «oldary man»: лысина, седые виски, густая
борода, майка) в пропорциях портрета диалогов (tools/gen_portraits.py: grandpa, те же многоугольники,
масштаб 0.65). Гравировка — карта высот: поле медальона утоплено в камень, борода, волосы и майка
приподняты (полированный светлый гранит), контуры, глаза и морщины — канавки. Свет сверху-слева: пиксель,
у которого сосед сверху-слева ниже, светлеет, у которого выше — темнеет; так канавка даёт тёмную линию
с бликом снизу-справа, а рельеф — светлый верх и тень под ним. Имени и дат на плите нет: в сюжете дед
без имени (титры: «Дед — упрямый»), вместо надписи — высеченные кирка и лопата.

Планка — перерисованные руды: 8 тонов на материал, контур, ободок света, дизеринг без размытия.
Замена-заглушка уровня «программист нарисовал аккуратно», не работа художника владельца.

Запуск: python3 tools/gen_grave.py [--sheet /путь/лист.png]   (детерминирован, повторный запуск даёт те же PNG)
"""

import argparse
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "env")

W, H = 128, 100          # текстура могилы; низ = линия земли (верх первой земляной клетки)
JAR = 32                 # текстура банки


def hx(s):
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


# Лесенки тонов (контур, глубокая тень, тень, тёмная база, база, свет, яркий свет, блик).
STONE = [hx(c) for c in ("1A181C", "2C2A31", "413F47", "555360", "6A6874", "817F8B", "9B99A5", "B9B7C2")]
GRASS = [hx(c) for c in ("1F3014", "365423", "4F7A34", "66984A", "86B85C", "A8D070")]
SOIL = [hx(c) for c in ("2A1A0E", "3E2A1A", "6B4428", "8F6238", "B4854E")]
LICHEN = [hx(c) for c in ("4E5C2C", "74803E", "98A454", "B8C46A")]
WHITE = hx("F2F0E4")
WHITE_D = hx("CFCBB8")
YELLOW = hx("E8B32E")
BLUE = hx("3E5CB8")
BLUE_L = hx("7A96E8")
RED = hx("C8302A")
RED_L = hx("F05A50")
DARK = hx("1E1414")
TIN = [hx(c) for c in ("3C3E48", "686C7A", "9A9EAC", "C4C8D4", "E6E8EE")]
LABEL = [hx(c) for c in ("8E1E1E", "C8302A", "E8D8B0")]
BOOK = [hx(c) for c in ("2E4A32", "4C7A50", "E8D8B0")]


def sh(m, dx, dy):
    """out[y, x] = m[y - dy, x - dx]: значение соседа в (−dx, −dy); за краем — 0."""
    out = np.zeros_like(m)
    h, w = m.shape[:2]
    ys = slice(max(dy, 0), h + min(dy, 0))
    xs = slice(max(dx, 0), w + min(dx, 0))
    yd = slice(max(-dy, 0), h + min(-dy, 0))
    xd = slice(max(-dx, 0), w + min(-dx, 0))
    out[ys, xs] = m[yd, xd]
    return out


def erode(m, n=1):
    for _ in range(n):
        m = m & sh(m, 1, 0) & sh(m, -1, 0) & sh(m, 0, 1) & sh(m, 0, -1)
    return m


def dilate(m, n=1):
    for _ in range(n):
        m = m | sh(m, 1, 0) | sh(m, -1, 0) | sh(m, 0, 1) | sh(m, 0, -1)
    return m


def ring(m):
    """Внешнее кольцо маски в 1 пиксель."""
    return m & ~erode(m)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.a = np.zeros((h, w, 4), np.uint8)

    def mask(self, fn):
        m = Image.new("L", (self.w, self.h), 0)
        fn(ImageDraw.Draw(m))
        return np.array(m) > 0

    def ell(self, cx, cy, rx, ry, outline=False):
        if outline:
            return self.mask(lambda d: d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], outline=255))
        return self.mask(lambda d: d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255))

    def poly(self, pts, outline=False):
        if outline:
            return self.mask(lambda d: d.polygon(pts, outline=255))
        return self.mask(lambda d: d.polygon(pts, fill=255))

    def rect(self, x0, y0, x1, y1):
        return self.mask(lambda d: d.rectangle([x0, y0, x1, y1], fill=255))

    def line(self, pts, w=1):
        return self.mask(lambda d: d.line(pts, fill=255, width=w))

    def paint(self, m, color):
        self.a[m] = color

    def px(self, x, y, color):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.a[y, x] = color

    def alpha(self):
        return self.a[:, :, 3] > 0

    def outline(self, color):
        am = self.alpha()
        self.a[dilate(am) & ~am] = color

    def image(self):
        return Image.fromarray(self.a, "RGBA")


def checker(w, h, phase=0):
    yy, xx = np.mgrid[0:h, 0:w]
    return ((xx + yy + phase) % 2) == 0


def speckle(w, h, seed, density):
    rng = np.random.RandomState(seed)
    return rng.random_sample((h, w)) < density


# ---------------------------------------------------------------------------
# Надгробие
# ---------------------------------------------------------------------------

STONE_X0, STONE_X1 = 8, 64      # плита-надгробие: x 8..64
STONE_CY, STONE_R = 32, 28      # арка верха
STONE_BOTTOM = 100          # основание уходит за холмик до линии земли
MED_CX, MED_CY, MED_RX, MED_RY = 36, 37, 20, 24   # медальон с портретом


def stone_mask(c):
    m = c.rect(STONE_X0, STONE_CY, STONE_X1, STONE_BOTTOM) | c.ell(36, STONE_CY, STONE_R, 27)
    # Сколы: откушенный правый угол арки и выщербина на левой кромке.
    m &= ~c.poly([(56, 8), (66, 8), (66, 17)])
    m &= ~c.poly([(5, 50), (12, 52), (11, 55), (5, 56)])
    return m


def draw_headstone(c):
    m = stone_mask(c)
    tone = np.full((H, W), 4, np.int8)
    # Гранит: редкие крапинки тоном выше и ниже базы.
    tone[speckle(W, H, 11, 0.06)] = 3
    tone[speckle(W, H, 12, 0.04)] = 5
    # Нижняя правая четверть в тени — полоса дизеринга к тёмной базе.
    yy, xx = np.mgrid[0:H, 0:W]
    shade = (xx - STONE_X0) + (yy - 10) > 86
    tone[shade & checker(W, H)] = 3
    tone[(xx - STONE_X0) + (yy - 10) > 100] = 3

    # Фаска: два пикселя внутрь от контура; обращённая к свету — светлее, в тень — темнее.
    inner = erode(m, 1)
    band = inner & ~erode(m, 3)
    lit = band & ~sh(m, 3, 3)       # в трёх пикселях вверх-влево уже нет камня
    dark = band & ~sh(m, -3, -3)
    tone[band] = 3
    tone[dark] = 2
    tone[lit] = 6
    tone[ring(inner) & lit] = 7     # ободок света на самой кромке сверху-слева
    tone[ring(m)] = 0

    # Медальон и гравировка — карта высот поверх тона.
    hmap = np.zeros((H, W), np.float32)
    engrave(c, tone, hmap)
    light = hmap - sh(hmap, 1, 1)
    near = dilate(c.ell(MED_CX, MED_CY, MED_RX, MED_RY), 1)
    tone[near & (light > 0.4)] += 1
    tone[near & (light < -0.4)] -= 1
    tone = np.clip(tone, 0, 7)

    # Кирка и лопата под портретом, высечены канавкой с бликом снизу-справа.
    tools = c.line([(29, 64), (43, 72)]) | c.line([(43, 64), (29, 72)])
    tools |= c.poly([(27, 62), (32, 62), (31, 65), (28, 65)])              # лезвие лопаты
    tools |= c.line([(42, 62), (46, 64), (45, 67)])                         # клюв кирки
    tools &= m
    tone[sh(tools, 1, 1) & m & ~tools] = 6
    tone[tools] = 0

    for i, col in enumerate(STONE):
        c.paint(m & (tone == i), col)

    lichen(c, [(12, 40, 2, 2), (15, 37, 2, 1), (57, 21, 2, 2), (54, 25, 1, 1), (20, 72, 3, 2), (61, 66, 2, 2)],
           m, seed=3)


def lichen(c, blobs, within, seed):
    """Пятна лишайника: два тона, верх-лево дизерингом светлее, тёмная кромка."""
    patch = np.zeros((H, W), bool)
    for cx, cy, rx, ry in blobs:
        patch |= c.ell(cx, cy, rx, ry)
        if rx > 2:
            patch |= c.ell(cx + rx // 2, cy - 1, rx - 1, max(1, ry - 1))
    patch &= erode(within, 1)
    core = erode(patch, 1)
    c.paint(patch, LICHEN[0])
    c.paint(core, LICHEN[1])
    c.paint(core & checker(W, H, seed) & ~sh(core, -1, -1) & sh(core, 1, 1), LICHEN[2])
    c.paint(core & ~sh(core, 1, 1), LICHEN[3])


# Координаты портрета: сетка 64 из tools/gen_portraits.py (CX = 32) → медальон, масштаб 0.65.
PS = 0.78
PX0 = MED_CX - 32 * PS
PY0 = MED_CY - MED_RY + 7 - 12 * PS   # макушка (y = 12 у портрета) в 7 px от верха медальона: овал режет бюст по груди


def P(pts):
    return [(round(PX0 + x * PS), round(PY0 + y * PS)) for x, y in pts]


def P1(x, y):
    return P([(x, y)])[0]


def engrave(c, tone, hmap):
    FIELD, RAISED, GROOVE = -1.5, -0.9, -2.5
    med = c.ell(MED_CX, MED_CY, MED_RX, MED_RY)
    hmap[med] = FIELD
    tone[med] = 2
    CX = 32
    frame = ring(med)
    hmap[frame] = -2.5
    tone[frame] = 1

    yy, xx = np.mgrid[0:H, 0:W]
    strands = ((xx + 2 * yy) % 4) == 0

    def raised(m, t=6, hatch=True):
        m = m & med
        hmap[m] = RAISED
        tone[m] = t
        if hatch:
            tone[m & strands & sh(m, 1, 0) & sh(m, -1, 0)] = t - 1

    def groove(m, t=1):
        m = m & med
        hmap[m] = GROOVE
        tone[m] = t

    # Плечи и майка: кожа — поле, майка — приподнятый светлый камень; контур плеч — канавка.
    shoulders = c.poly(P([(4, 64), (6, 56), (14, 50), (24, 47), (40, 47), (50, 50), (58, 56), (60, 64), (60, 80), (4, 80)]))
    tank = c.poly(P([(12, 80), (16, 54), (22, 47), (28, 47), (30, 54), (CX - 2, 56), (CX + 2, 56), (34, 54),
                     (36, 47), (42, 47), (48, 54), (52, 80)]))
    groove(c.poly(P([(4, 64), (6, 56), (14, 50), (24, 47), (40, 47), (50, 50), (58, 56), (60, 64)]), outline=True)
           & sh(shoulders, 0, -2))
    neck = c.rect(*P1(CX - 5, 41), *P1(CX + 5, 52))

    # Голова: контур — канавка; уши.
    head = c.ell(*P1(CX, 28), round(14 * PS), round(16 * PS))
    skin = head | shoulders | neck
    hmap[skin & med] = FIELD + 0.3
    tone[skin & med] = 3                      # плечи — чуть светлее поля, лицо (ниже) — полированное
    tone[head & med] = 4
    raised(tank, 6, hatch=False)
    for sx in (-1, 1):
        ear = c.ell(*P1(CX + sx * 15, 30), 2, 3)
        hmap[ear & med] = FIELD + 0.3
        tone[ear & med] = 4
        groove(ring(ear) & ~head)
    groove(ring(head))
    groove(ring(neck) & ~sh(neck, 0, 1) & ~sh(neck, 0, -1))   # шея: две канавки от бороды к плечам
    # Волосы: седые пряди по вискам (лысина сверху).
    hair_l = c.poly(P([(15, 30), (14, 20), (18, 13), (22, 12), (20, 18), (19, 26), (21, 32)]))
    hair_r = c.poly(P([(49, 30), (50, 20), (46, 13), (42, 12), (44, 18), (45, 26), (43, 32)]))
    raised(hair_l | hair_r)
    # Борода и усы.
    beard = c.poly(P([(16, 30), (19, 36), (22, 42), (28, 47), (CX, 49), (36, 47), (42, 42), (45, 36), (48, 30),
                      (44, 34), (38, 36), (CX, 35), (26, 36), (20, 34)]))
    raised(beard, 7)                          # седая борода — самое светлое на плите
    mouth = c.line(P([(27, 39), (CX, 40), (37, 39)]))
    groove(mouth & beard, 3)
    must = c.poly(P([(24, 36), (28, 34), (CX, 35), (36, 34), (40, 36), (36, 38), (CX, 37), (28, 38)]))
    raised(must, 7, hatch=False)
    # Брови, глаза, нос, морщины.
    for sx in (-1, 1):
        ex = CX + sx * 7
        raised(c.line(P([(ex - 3, 22), (ex + 3, 21)]), w=1), 6, hatch=False)
        eye = c.rect(*P1(ex - 1, 25), *P1(ex + 1, 28))
        groove(eye, 1)
        x0, y0 = P1(ex - 1, 25)
        tone[y0, x0] = 5                      # блик в глазу
        tone[y0 + 1, x0 + 1] = 0              # зрачок
    groove(c.line(P([(CX, 29), (CX, 32), (CX + 2, 33)])))
    groove(c.line(P([(CX - 6, 17), (CX + 6, 17)])), 2)
    groove(c.line(P([(CX - 4, 14), (CX + 4, 14)])), 2)
    # Складки у глаз — короткие канавки.
    groove(c.line(P([(CX - 12, 30), (CX - 10, 31)])), 2)
    groove(c.line(P([(CX + 10, 31), (CX + 12, 30)])), 2)


# ---------------------------------------------------------------------------
# Холмик, плита, тайник, цветы
# ---------------------------------------------------------------------------

MOUND_CX, MOUND_CY, MOUND_RX, MOUND_RY = 70, 100, 58, 33


def draw_mound(c):
    m = c.ell(MOUND_CX, MOUND_CY, MOUND_RX, MOUND_RY)
    m[H:, :] = False
    yy, xx = np.mgrid[0:H, 0:W]
    tone = np.full((H, W), 2, np.int8)
    tone[yy < 74] = 3
    tone[(yy < 78) & checker(W, H)] = 3
    tone[(yy < 70) & checker(W, H, 1)] = 4
    tone[yy > 88] = 1
    tone[(yy > 84) & checker(W, H)] = 1
    tone[speckle(W, H, 21, 0.05) & (yy < 86)] = 4
    # Земля у подножия: рваная кромка травы над грунтом.
    soil = m & (yy >= 93 + ((xx // 5) % 3 == 0).astype(np.int8))
    for i, col in enumerate(GRASS):
        c.paint(m & (tone == i), col)
    c.paint(ring(m), GRASS[0])
    c.paint(soil, SOIL[2])
    c.paint(soil & speckle(W, H, 22, 0.25), SOIL[3])
    c.paint(soil & speckle(W, H, 23, 0.15), SOIL[1])
    c.paint(ring(soil) & ~sh(soil, 0, 1), SOIL[1])
    c.paint(soil & (yy == H - 1), SOIL[0])
    # Пучки травы по верхнему краю холмика.
    top = ring(m) & ~sh(m, 0, 1)
    ys, xs = np.nonzero(top)
    for x, y in zip(xs, ys):
        if x % 3 == 0:
            hgt = 2 + (x // 3) % 3
            col = GRASS[3] if (x // 3) % 2 == 0 else GRASS[1]
            for k in range(1, hgt + 1):
                c.px(x + (1 if k == hgt and x % 2 == 0 else 0), y - k, col)
            c.px(x, y, GRASS[2])
    return m


def draw_slab(c, dx=0, dy=0):
    """Лежачая плита в лёгкой перспективе; dx/dy — сдвиг (открытое состояние)."""
    top = c.poly([(44 + dx, 70 + dy), (112 + dx, 70 + dy), (104 + dx, 84 + dy), (36 + dx, 84 + dy)])
    front = c.poly([(36 + dx, 84 + dy), (104 + dx, 84 + dy), (104 + dx, 88 + dy), (36 + dx, 88 + dy)])
    side = c.poly([(112 + dx, 70 + dy), (113 + dx, 73 + dy), (105 + dx, 88 + dy), (104 + dx, 84 + dy)])
    m = top | front | side
    tone = np.full((H, W), 5, np.int8)
    tone[speckle(W, H, 31, 0.08)] = 4
    tone[speckle(W, H, 32, 0.05)] = 6
    tone[front] = 3
    tone[front & speckle(W, H, 33, 0.1)] = 2
    tone[side] = 2
    # Трещина поперёк правой трети.
    crack = c.line([(84 + dx, 70 + dy), (86 + dx, 75 + dy), (83 + dx, 79 + dy), (85 + dx, 84 + dy)]) & top
    tone[sh(crack, 1, 1) & top] = 6
    tone[crack] = 2
    tone[ring(m)] = 0
    lit = ring(top) & (~sh(top, 1, 1) | ~sh(top, 0, 1))
    tone[lit] = 7
    tone[ring(top) & ~sh(top, 1, 0) & ~lit] = 6
    for i, col in enumerate(STONE):
        c.paint(m & (tone == i), col)
    lichen(c, [(54 + dx, 76 + dy, 3, 1), (58 + dx, 75 + dy, 2, 1)], top, seed=5)
    return m


def draw_hole(c):
    """Яма под сдвинутой плитой: тёмный провал с земляной кромкой."""
    hole = c.poly([(97, 72), (113, 72), (106, 86), (90, 86)])
    rim = dilate(hole, 1) & ~hole
    c.paint(rim, SOIL[1])
    c.paint(rim & sh(hole, 0, 1), SOIL[3])                      # нижняя губа ямы на свету
    c.paint(hole, SOIL[0])
    c.paint(hole & (~sh(hole, 0, 1) | ~sh(hole, 0, 2)), DARK)    # задняя стенка в темноте
    c.paint(hole & ~sh(hole, 0, -1), SOIL[1])                    # дно ловит свет


def flower(c, x, y, kind):
    """Цветок на стебле: ромашка, василёк или мак, 5x5 с листком."""
    c.paint(c.line([(x, y), (x, y + 5)]), GRASS[1])
    c.px(x + 1, y + 3, GRASS[3])
    c.px(x - 1, y + 4, GRASS[3])
    if kind == "daisy":
        for dx, dy in ((-2, 0), (2, 0), (0, -2), (0, 2), (-1, -1), (1, -1), (-1, 1), (1, 1)):
            c.px(x + dx, y + dy, WHITE if dy <= 0 else WHITE_D)
        c.px(x, y, YELLOW)
    elif kind == "corn":
        for dx, dy in ((-2, 0), (2, 0), (0, -2), (0, 2), (-1, -1), (1, -1), (-1, 1), (1, 1)):
            c.px(x + dx, y + dy, BLUE_L if dy < 0 or dx < 0 else BLUE)
        c.px(x, y, hx("1E2C60"))
    else:
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)):
            c.px(x + dx, y + dy, RED_L if dy < 0 else RED)
        c.px(x, y, DARK)


def draw_grave(opened):
    c = Canvas(W, H)
    draw_headstone(c)
    draw_mound(c)
    if opened:
        draw_hole(c)
        draw_slab(c, -12, 1)
    else:
        draw_slab(c)
    # Цветы: справа от плиты и у подножия надгробия.
    flower(c, 117, 76, "daisy")
    flower(c, 123, 84, "corn")
    flower(c, 108, 90, "poppy")
    flower(c, 30, 80, "corn")
    flower(c, 38, 91, "daisy")
    c.outline(STONE[0])
    return c.image()


def draw_jar():
    c = Canvas(JAR, JAR)
    body = c.rect(8, 10, 23, 30)
    c.paint(body, TIN[2])
    c.paint(c.rect(8, 10, 11, 30), TIN[3])
    c.paint(c.rect(9, 11, 9, 29), TIN[4])
    c.paint(c.rect(20, 10, 23, 30), TIN[1])
    c.paint(c.rect(22, 10, 23, 30), TIN[0])
    # Этикетка чая: красная лента с кремовой полосой.
    c.paint(c.rect(8, 16, 23, 24), LABEL[1])
    c.paint(c.rect(20, 16, 23, 24), LABEL[0])
    c.paint(c.rect(9, 19, 21, 20), LABEL[2])
    c.paint(c.rect(10, 17, 12, 17), LABEL[2])
    # Крышка со скосом и блик.
    lid = c.rect(7, 8, 24, 11)
    c.paint(lid, TIN[2])
    c.paint(c.rect(7, 8, 24, 8), TIN[4])
    c.paint(c.rect(7, 11, 24, 11), TIN[0])
    c.paint(c.rect(23, 9, 24, 10), TIN[1])
    # Тетрадь торчит из банки.
    book = c.poly([(13, 1), (21, 0), (22, 8), (14, 9)])
    c.paint(book, BOOK[1])
    c.paint(c.poly([(13, 1), (14, 9), (15, 9), (14, 1)]), BOOK[0])
    c.paint(c.line([(20, 1), (21, 8)]), BOOK[2])
    c.paint(c.rect(16, 3, 19, 4), BOOK[0])
    # Донышко в тени.
    c.paint(c.rect(8, 30, 23, 31), TIN[0])
    c.outline(DARK)
    return c.image()


def sheet(images, labels, scale, path):
    pad = 8
    font_h = 12
    w = sum(im.width * scale for im in images) + pad * (len(images) + 1)
    h = max(im.height * scale for im in images) + pad * 2 + font_h
    out = Image.new("RGBA", (w, h), (90, 110, 130, 255))
    d = ImageDraw.Draw(out)
    x = pad
    for im, lab in zip(images, labels):
        out.alpha_composite(im.resize((im.width * scale, im.height * scale), Image.NEAREST), (x, pad + font_h))
        d.text((x, 2), lab, fill=(255, 255, 255, 255))
        x += im.width * scale + pad
    out.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", help="контрольный лист PNG (увеличение x4)")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    closed = draw_grave(False)
    opened = draw_grave(True)
    jar = draw_jar()
    closed.save(os.path.join(OUT, "grave.png"))
    opened.save(os.path.join(OUT, "grave_open.png"))
    jar.save(os.path.join(OUT, "grave_jar.png"))
    print("art/env/grave.png, grave_open.png, grave_jar.png")
    if args.sheet:
        sheet([closed, opened, jar], ["закрыта", "открыта", "банка"], 4, args.sheet)
        print(args.sheet)


if __name__ == "__main__":
    main()

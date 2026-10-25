#!/usr/bin/env python3
"""Графика магазина и верстака: значки товаров, вкладок, рамки плиток.

Пишет в art/ui/shop/ (скрипт — источник правды, PNG руками не правим):

  item_<id>.png     32x32  значки предметов рюкзака (руда, бронза, топливо) и
                           товаров лавки (еда, допинги, гаджеты, скважина)
  tab_*.png         32x32  значки вкладок магазина
  glyph_*.png       16x16  мелкие знаки: галочка, замок, «новинка», ролик, ×2 …
  tile_body.png, tile_rim.png, pill.png, btn_*.png, panel.png, tab_marker.png
                           девятизонные рамки (9-patch); rim серый — его красят
                           под ступень/редкость модуляцией цвета в движке
  glow.png          32x32  мягкий пиксельный ореол для «активного» и премиума

Стиль — как у остальной графики проекта (tools/gen_art.py): чёткий пиксель, тёмная
обводка, палитра из art/PALETTE.md, без размытия. Это аккуратная замена-заглушка
«программист нарисовал», а не работа художника: если владелец пришлёт настоящие
значки, их кладут под теми же именами, код ничего не заметит.

    python3 tools/gen_shop_icons.py            # записать в art/ui/shop/
    python3 tools/gen_shop_icons.py --sheet X  # заодно контактный лист в файл X
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_art as G  # noqa: E402  палитра проекта и список руд

OUTDIR = os.path.join(G.ROOT, "art", "ui", "shop")
C = G.C
shade = G.shade
OUT = (14, 12, 18, 255)
WHITE = (255, 255, 255, 255)


def rgba(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


# --------------------------------------------------------------------------
# Холст
# --------------------------------------------------------------------------

class Cv:
    def __init__(self, w=32, h=32):
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)
        self.w, self.h = w, h

    def px(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.img.putpixel((int(x), int(y)), c)

    def get(self, x, y):
        return self.img.getpixel((x, y))

    def rect(self, x0, y0, x1, y1, c):
        self.d.rectangle([x0, y0, x1, y1], fill=c)

    def ell(self, cx, cy, rx, ry, c):
        self.d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=c)

    def poly(self, pts, c):
        self.d.polygon([(int(round(x)), int(round(y))) for x, y in pts], fill=c)

    def line(self, pts, c, w=1):
        self.d.line([(int(round(x)), int(round(y))) for x, y in pts], fill=c, width=w)

    def outline(self, color=OUT):
        src = self.img.copy()
        sp = src.load()
        for y in range(self.h):
            for x in range(self.w):
                if sp[x, y][3] != 0:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and sp[nx, ny][3] > 0:
                        self.img.putpixel((x, y), color)
                        break
        return self

    def save(self, name):
        os.makedirs(OUTDIR, exist_ok=True)
        self.img.save(os.path.join(OUTDIR, name + ".png"))
        SAVED.append(name)


SAVED = []


def shaded_poly(cv, pts, base, light, dark, cx, cy, rx, ry, lo=-0.3, hi=0.5):
    """Заливка многоугольника тремя тонами по направлению света (слева-сверху)."""
    mask = Image.new("L", (cv.w, cv.h), 0)
    ImageDraw.Draw(mask).polygon([(int(round(x)), int(round(y))) for x, y in pts], fill=255)
    m = mask.load()
    for y in range(cv.h):
        for x in range(cv.w):
            if m[x, y]:
                nx, ny = (x - cx) / max(rx, 1), (y - cy) / max(ry, 1)
                lum = -(nx * 0.55 + ny * 0.85)
                cv.px(x, y, light if lum > hi else dark if lum < lo else base)


def blob_pts(cx, cy, rx, ry, n, jit, rng):
    pts = []
    for i in range(n):
        a = (i / n) * 2 * math.pi + rng.uniform(-0.15, 0.15)
        k = 1.0 + rng.uniform(-jit, jit)
        pts.append((cx + math.cos(a) * rx * k, cy + math.sin(a) * ry * k))
    return pts


# --------------------------------------------------------------------------
# Девятизонные рамки
# --------------------------------------------------------------------------

def _inside(x, y, w, h, cut):
    for (cx, cy) in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if abs(x - cx) + abs(y - cy) < cut:
            return False
    return True


def box(name, w, h, top, bot, border=OUT, hi=None, lo=None, cut=2, ring=None):
    """Закруглённый «ступеньками» прямоугольник. ring=(светлый, тёмный, толщина)
    рисует только кайму с прозрачной серединой."""
    cv = Cv(w, h)
    for y in range(h):
        for x in range(w):
            if not _inside(x, y, w, h, cut):
                continue
            edge = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h) or not _inside(nx, ny, w, h, cut):
                    edge = True
                    break
            if edge:
                cv.px(x, y, border)
                continue
            if ring:
                light, dark, th = ring
                d = min(x, y, w - 1 - x, h - 1 - y)
                if d <= th:
                    t = y / max(h - 1, 1)
                    cv.px(x, y, mix(light, dark, t))
                elif d == th + 1:
                    cv.px(x, y, border)
                continue
            t = y / max(h - 1, 1)
            cv.px(x, y, mix(top, bot, t))
    if not ring:
        if hi:
            for x in range(2, w - 2):
                cv.px(x, 1, hi)
        if lo:
            for x in range(2, w - 2):
                cv.px(x, h - 2, lo)
    cv.save(name)


def gen_frames():
    box("tile_body", 16, 16, rgba("#2F2839"), rgba("#1B1622"), hi=rgba("#463C58"), lo=rgba("#120E18"))
    box("tile_rim", 16, 16, None, None, ring=(rgba("#F4F4FA"), rgba("#A9A9BE"), 1))
    box("pill", 12, 10, rgba("#17131D", 235), rgba("#0E0B12", 235), border=OUT, cut=2)
    box("btn_green", 16, 16, rgba("#5CEB9E"), rgba("#1C8A52"), hi=rgba("#C8FFE0"), lo=rgba("#12663A"))
    box("btn_red", 16, 16, rgba("#FF6B80"), rgba("#B01A34"), hi=rgba("#FFC0C8"), lo=rgba("#7A1024"))
    box("btn_gold", 16, 16, rgba("#FFE680"), rgba("#D9962A"), hi=rgba("#FFF6CC"), lo=rgba("#9A6410"))
    box("btn_gray", 16, 16, rgba("#8C8C9C"), rgba("#4C4C58"), hi=rgba("#C4C4D0"), lo=rgba("#34343E"))
    box("panel", 16, 16, rgba("#2A2333"), rgba("#18131F"), border=OUT, hi=rgba("#A4835A"), lo=rgba("#0E0B12"), cut=3)
    box("tab_marker", 16, 16, rgba("#E0A93B", 70), rgba("#E0A93B", 30), border=rgba("#E0A93B"), cut=2)
    box("bar", 8, 8, rgba("#241E2C"), rgba("#16121C"), border=OUT, hi=rgba("#4A3F5C"), cut=0)
    # ореол: пять ступеней прозрачности, без плавного градиента
    cv = Cv(32, 32)
    for y in range(32):
        for x in range(32):
            r = math.hypot(x - 15.5, y - 15.5) / 15.5
            if r < 1.0:
                a = [150, 105, 66, 34, 14][min(4, int(r * 5))]
                cv.px(x, y, (255, 226, 140, a))
    cv.save("glow")


# --------------------------------------------------------------------------
# Мелкие знаки 16x16
# --------------------------------------------------------------------------

def glyph_check():
    cv = Cv(16, 16)
    cv.line([(3, 8), (6, 11), (13, 4)], rgba("#1C8A52"), 4)
    cv.line([(3, 7), (6, 10), (13, 3)], rgba("#4DE094"), 3)
    cv.px(4, 7, rgba("#B8FFD8"))
    cv.px(10, 4, rgba("#B8FFD8"))
    cv.outline()
    cv.save("glyph_check")


def glyph_cross():
    cv = Cv(16, 16)
    cv.line([(4, 4), (11, 11)], rgba("#B01A34"), 4)
    cv.line([(11, 4), (4, 11)], rgba("#B01A34"), 4)
    cv.line([(4, 3), (11, 10)], rgba("#FF5570"), 3)
    cv.line([(11, 3), (4, 10)], rgba("#FF5570"), 3)
    cv.outline()
    cv.save("glyph_cross")


def glyph_lock():
    cv = Cv(16, 16)
    cv.d.arc([4, 1, 11, 10], 180, 360, fill=rgba("#B8C4C8"), width=2)
    cv.line([(4, 5), (4, 8)], rgba("#B8C4C8"), 2)
    cv.line([(11, 5), (11, 8)], rgba("#B8C4C8"), 2)
    cv.rect(2, 7, 13, 14, rgba("#8B99A2"))
    cv.rect(2, 7, 13, 8, rgba("#B8C4C8"))
    cv.rect(2, 13, 13, 14, rgba("#5C6A74"))
    cv.rect(7, 9, 8, 11, rgba("#2A2A32"))
    cv.px(7, 12, rgba("#2A2A32"))
    cv.outline()
    cv.save("glyph_lock")


def glyph_new():
    cv = Cv(16, 16)
    pts = []
    for i in range(16):
        a = i / 16 * 2 * math.pi - math.pi / 2
        r = 7.4 if i % 2 == 0 else 4.6
        pts.append((7.5 + math.cos(a) * r, 7.5 + math.sin(a) * r))
    cv.poly(pts, rgba("#E8832E"))
    cv.ell(7, 7, 4, 4, rgba("#FFD84A"))
    cv.ell(7, 7, 2, 2, rgba("#FFF3A0"))
    cv.px(5, 5, WHITE)
    cv.outline()
    cv.save("glyph_new")


def glyph_video():
    cv = Cv(16, 16)
    cv.rect(1, 3, 14, 11, rgba("#33394A"))
    cv.rect(2, 4, 13, 10, rgba("#5C9BD8"))
    cv.rect(2, 4, 13, 5, rgba("#8FC4F4"))
    cv.poly([(6, 5), (6, 9), (10, 7)], WHITE)
    cv.rect(4, 12, 11, 13, rgba("#33394A"))
    cv.outline()
    cv.save("glyph_video")


def glyph_gift():
    cv = Cv(16, 16)
    cv.rect(2, 7, 13, 14, rgba("#C21E3A"))
    cv.rect(2, 7, 13, 8, rgba("#FF5570"))
    cv.rect(1, 5, 14, 7, rgba("#E03A52"))
    cv.rect(7, 5, 8, 14, rgba("#FFE066"))
    cv.ell(5, 3, 2, 2, rgba("#E8B32E"))
    cv.ell(10, 3, 2, 2, rgba("#E8B32E"))
    cv.rect(6, 3, 9, 5, rgba("#FFE066"))
    cv.outline()
    cv.save("glyph_gift")


def glyph_house():
    cv = Cv(16, 16)
    cv.rect(3, 7, 12, 14, rgba("#E8D8B0"))
    cv.rect(3, 13, 12, 14, rgba("#A4835A"))
    cv.poly([(0, 8), (7.5, 1), (15, 8)], rgba("#C21E3A"))
    cv.line([(1, 8), (7, 2)], rgba("#FF5570"), 1)
    cv.rect(6, 10, 9, 14, rgba("#6B4428"))
    cv.outline()
    cv.save("glyph_house")


def glyph_arrow():
    cv = Cv(16, 16)
    cv.poly([(2, 6), (8, 6), (8, 3), (14, 8), (8, 13), (8, 10), (2, 10)], rgba("#F2D99B"))
    cv.line([(3, 7), (8, 7)], WHITE, 1)
    cv.outline()
    cv.save("glyph_arrow")


def glyph_hammer():
    cv = Cv(16, 16)
    cv.line([(9, 6), (3, 13)], rgba("#6B4428"), 3)
    cv.line([(8, 6), (3, 12)], rgba("#8F6238"), 1)
    cv.rect(5, 1, 14, 6, rgba("#8B99A2"))
    cv.rect(5, 1, 14, 2, rgba("#D2DCE0"))
    cv.rect(5, 5, 14, 6, rgba("#5C6A74"))
    cv.outline()
    cv.save("glyph_hammer")


def glyph_storage():
    cv = Cv(16, 16)
    cv.rect(2, 8, 13, 14, rgba("#8F6238"))
    cv.rect(2, 8, 13, 9, rgba("#B4854E"))
    cv.line([(2, 11), (13, 11)], rgba("#6B4428"), 1)
    cv.poly([(5.5, 0), (9.5, 0), (9.5, 3), (12, 3), (7.5, 7), (3, 3), (5.5, 3)], rgba("#4DE094"))
    cv.line([(6, 1), (6, 3)], rgba("#B8FFD8"), 1)
    cv.outline()
    cv.save("glyph_storage")


FONT3 = {
    "2": ["111", "001", "111", "100", "111"],
}


def glyph_x2():
    cv = Cv(16, 16)
    col = rgba("#FFE066")
    dk = rgba("#D9962A")
    X = ["10001", "01010", "00100", "01010", "10001"]
    two = FONT3["2"]

    def paint(dy, c):
        for r, row in enumerate(X):
            for k, ch in enumerate(row):
                if ch == "1":
                    cv.px(1 + k, 7 + r + dy, c)
        for r, row in enumerate(two):
            for k, ch in enumerate(row):
                if ch == "1":
                    cv.rect(8 + k * 2, 3 + r * 2 + dy, 9 + k * 2, 4 + r * 2 + dy, c)

    paint(1, dk)
    paint(0, col)
    cv.outline()
    cv.save("glyph_x2")


def glyph_plus():
    cv = Cv(16, 16)
    cv.rect(6, 2, 9, 13, rgba("#4DE094"))
    cv.rect(2, 6, 13, 9, rgba("#4DE094"))
    cv.rect(7, 3, 8, 12, rgba("#B8FFD8"))
    cv.rect(3, 7, 12, 8, rgba("#B8FFD8"))
    cv.outline()
    cv.save("glyph_plus")


def glyph_dig():
    cv = Cv(16, 16)
    cv.line([(3, 14), (9, 7)], rgba("#8F6238"), 2)
    cv.poly([(3, 6), (8, 2), (14, 4), (13, 6), (9, 4), (7, 6), (7, 8)], rgba("#B8C4C8"))
    cv.px(8, 3, WHITE)
    cv.px(10, 3, WHITE)
    cv.outline()
    cv.save("glyph_dig")


def glyph_fly():
    cv = Cv(16, 16)
    cv.poly([(1, 13), (2, 8), (6, 4), (12, 1), (14, 2), (12, 7), (8, 11), (4, 13)], rgba("#BFDCFA"))
    cv.poly([(3, 12), (4, 9), (7, 6), (10, 3)], WHITE)
    cv.line([(5, 12), (10, 6)], rgba("#8FB4DC"), 1)
    cv.line([(8, 12), (12, 7)], rgba("#8FB4DC"), 1)
    cv.outline()
    cv.save("glyph_fly")


def glyph_depth():
    cv = Cv(16, 16)
    cv.rect(0, 1, 15, 3, rgba("#6B4428"))
    cv.rect(0, 1, 15, 1, rgba("#4F7A34"))
    cv.poly([(6, 5), (9, 5), (9, 9), (12, 9), (7.5, 14), (3, 9), (6, 9)], rgba("#F2D99B"))
    cv.outline()
    cv.save("glyph_depth")


def glyph_stat_dot():
    # метка «хватает / не хватает» в строке материалов: простой кружок
    cv = Cv(16, 16)
    cv.ell(7, 7, 4, 4, WHITE)
    cv.outline()
    cv.save("glyph_dot")


# --------------------------------------------------------------------------
# Предметы: руда
# --------------------------------------------------------------------------

def ore_nugget(cv, cx, cy, s, base, light, rng, angular=False):
    n = 7 if angular else 9
    jit = 0.22 if angular else 0.10
    pts = blob_pts(cx, cy, s, s * 0.85, n, jit, rng)
    shaded_poly(cv, pts, base, light, shade(base, 0.62), cx, cy, s, s * 0.85)
    cv.px(cx - s // 2, cy - s // 2, WHITE if s > 3 else light)


def ore_crystal(cv, cx, cy, s, base, light, rng):
    h = int(s * 1.35)
    w = max(2, int(s * 0.8))
    top = [(cx, cy - h), (cx + w, cy - h // 2), (cx + w, cy + h // 2), (cx, cy + h),
           (cx - w, cy + h // 2), (cx - w, cy - h // 2)]
    cv.poly(top, base)
    cv.poly([(cx, cy - h), (cx - w, cy - h // 2), (cx - w, cy + h // 2), (cx, cy + h)], light)
    cv.poly([(cx, cy - h), (cx + w, cy - h // 2), (cx + w, cy + h // 2), (cx, cy + h),
             (cx, cy)], shade(base, 0.7))
    cv.line([(cx, cy - h), (cx, cy + h)], base, 1)
    cv.px(cx - w // 2, cy - h // 2, WHITE)
    cv.px(cx - w // 2, cy - h // 2 + 1, WHITE)


def ore_gem(cv, cx, cy, s, base, light, rng):
    w, h = int(s * 1.1), int(s * 1.1)
    top_y = cy - h
    mid_y = cy - h // 3
    pts = [(cx - w * 0.6, top_y), (cx + w * 0.6, top_y), (cx + w, mid_y), (cx, cy + h), (cx - w, mid_y)]
    cv.poly(pts, base)
    cv.poly([(cx - w * 0.6, top_y), (cx, top_y), (cx - w * 0.3, mid_y), (cx - w, mid_y)], light)
    cv.poly([(cx, top_y), (cx + w * 0.6, top_y), (cx + w, mid_y), (cx + w * 0.3, mid_y)], mix(base, light, 0.45))
    cv.poly([(cx + w, mid_y), (cx, cy + h), (cx + w * 0.3, mid_y)], shade(base, 0.7))
    cv.poly([(cx - w, mid_y), (cx - w * 0.3, mid_y), (cx, cy + h)], mix(base, shade(base, 0.7), 0.4))
    cv.px(cx - w // 2, top_y + 1, WHITE)
    cv.px(cx - w // 2 + 1, top_y + 1, WHITE)


def ore_ingot(cv, cx, cy, s, base, light, rng):
    w, h = int(s * 1.3), int(s * 0.7)
    cv.rect(cx - w, cy - h, cx + w, cy + h + 2, base)
    cv.poly([(cx - w, cy - h), (cx - w + 3, cy - h - 3), (cx + w + 3, cy - h - 3), (cx + w, cy - h)], light)
    cv.poly([(cx + w, cy - h), (cx + w + 3, cy - h - 3), (cx + w + 3, cy + h - 1), (cx + w, cy + h + 2)],
            shade(base, 0.6))
    cv.line([(cx - w + 1, cy - h + 1), (cx + w - 1, cy - h + 1)], mix(base, light, 0.5), 1)


def ore_pebbles(cv, cx, cy, s, base, light, rng):
    offs = [(0, 0), (s, s // 2), (-s, s // 2), (s // 2, -s), (-s // 2, s)]
    for dx, dy in offs:
        r = max(2, s // 2 + 1)
        cv.ell(cx + dx, cy + dy, r, r, base)
        cv.px(cx + dx - 1, cy + dy - 1, light)
        cv.px(cx + dx - 1, cy + dy, mix(base, light, 0.5))
        cv.px(cx + dx + r - 1, cy + dy + r - 1, shade(base, 0.6))


def ore_facet(cv, cx, cy, s, base, light, rng):
    w, h = int(s * 1.5), int(s * 0.9)
    pts = [(cx - w, cy), (cx - w // 2, cy - h), (cx + w // 2, cy - h), (cx + w, cy),
           (cx + w // 2, cy + h), (cx - w // 2, cy + h)]
    cv.poly(pts, base)
    cv.poly([(cx - w, cy), (cx - w // 2, cy - h), (cx + w // 2, cy - h), (cx, cy)], light)
    cv.poly([(cx + w, cy), (cx + w // 2, cy + h), (cx - w // 2, cy + h), (cx, cy)], shade(base, 0.72))
    cv.px(cx - 1, cy - h + 1, WHITE)
    cv.px(cx - 2, cy - h + 1, WHITE)


def ore_bar(cv, cx, cy, s, base, light, rng):
    w, h = int(s * 1.5), int(s * 0.5)
    for k, dy in enumerate((-h - 1, h + 1)):
        y = cy + dy
        cv.rect(cx - w, y - h, cx + w, y + h, base)
        cv.line([(cx - w, y - h), (cx + w, y - h)], light, 1)
        cv.line([(cx - w, y + h), (cx + w, y + h)], shade(base, 0.65), 1)
        cv.px(cx - w + 2, y, shade(base, 0.55))
        cv.px(cx + w - 2, y, shade(base, 0.55))


def ore_fiber(cv, cx, cy, s, base, light, rng):
    cv.ell(cx, cy, int(s * 1.3), int(s * 0.9), shade(base, 0.8))
    for i in range(7):
        a = rng.uniform(0, math.pi)
        r = rng.uniform(s * 0.5, s * 1.4)
        x0, y0 = cx + math.cos(a) * r * -0.5, cy + math.sin(a) * r * -0.4
        x1, y1 = cx + math.cos(a) * r * 0.9, cy + math.sin(a) * r * 0.7
        cv.line([(x0, y0), (x1, y1)], light if i % 3 == 0 else base, 1)
    cv.px(cx - 2, cy - 2, light)


def ore_coal(cv, cx, cy, s, base, light, rng):
    ore_nugget(cv, cx, cy, s, base, light, rng, angular=True)
    cv.px(cx - s // 2 + 1, cy - s // 2 + 1, mix(light, WHITE, 0.4))
    cv.px(cx + 1, cy - s // 2, light)


def ore_bead(cv, cx, cy, s, base, accent, rng):
    r = s
    cv.ell(cx, cy, r, r, base)
    cv.ell(cx + 1, cy + 1, max(1, r - 2), max(1, r - 2), shade(base, 0.8))
    cv.ell(cx - 1, cy - 1, max(1, r - 3), max(1, r - 3), base)
    cv.px(cx - r // 2, cy - r // 2, WHITE)
    cv.px(cx - r // 2 + 1, cy - r // 2, WHITE)
    cv.px(cx + r // 2, cy + r // 2, accent)


def ore_glow(cv, cx, cy, s, core, glow, rng):
    # ореол — отдельным слоем под камнем: обводка идёт только вокруг камня
    halo = Cv(cv.w, cv.h)
    for i in range(4):
        r = s + 7 - i * 2
        halo.ell(cx, cy, r, r, (glow[0], glow[1], glow[2], 30 + i * 30))
    rock = Cv(cv.w, cv.h)
    ore_nugget(rock, cx, cy, s, core, glow, rng, angular=True)
    rock.ell(cx, cy, max(1, s // 2 - 1), max(1, s // 2 - 1), glow)
    rock.outline(rgba("#06240C"))
    halo.img.alpha_composite(rock.img)
    cv.img.alpha_composite(halo.img)


def ore_debris(cv, cx, cy, s, base, rust, rng):
    cv.rect(cx - s, cy - s // 2, cx + s, cy + s // 2, base)
    cv.line([(cx - s, cy - s // 2), (cx + s, cy - s // 2)], shade(base, 1.4), 1)
    cv.rect(cx - s // 2, cy - s // 4, cx + s // 2, cy + s // 4, rust)
    cv.px(cx - s + 1, cy, shade(base, 0.45))
    cv.px(cx + s - 1, cy, shade(base, 0.45))
    cv.line([(cx + s, cy + s // 2), (cx + s + 2, cy + s + 1)], rust, 2)


# имя предмета в рюкзаке -> (ключ в gen_art.ORES, форма)
ORE_ITEMS = {
    "iron_ore": "iron", "lead": "lead", "silver": "silver", "copper": "copper",
    "gold": "gold", "diamond": "diamond", "nickel": "nickel", "peat": "peat",
    "coal": "coal", "platinum": "platinum", "aluminium": "aluminium",
    "titanium": "titanium", "lithium": "lithium", "mercury": "mercury",
    "uranium": "uranium", "ruby": "ruby", "emerald": "emerald", "scrap": "scrap",
}
SHAPES = {
    "nugget": ore_nugget, "nugget_sparkle": ore_nugget, "chunk": lambda *a: ore_nugget(*a, angular=True),
    "chunk_sparkle": ore_coal, "ingot": ore_ingot, "pebble_cluster": ore_pebbles,
    "facet": ore_facet, "bar": ore_bar, "fiber": ore_fiber, "crystal_sparkle": ore_crystal,
    "bead": ore_bead, "glow": ore_glow, "debris": ore_debris, "gem": ore_gem,
}


def gen_ores():
    table = {k: (b, l, st) for k, _ru, b, l, st in G.ORES}
    for item_id, key in ORE_ITEMS.items():
        base_key, light_key, style = table[key]
        base, light = C(base_key), C(light_key)
        if key == "peat":
            base, light = C("soil_light"), C("soil_warm")
        if key == "coal":
            base = C("stone_shadow")
            light = C("stone_light")
        if key == "uranium":
            base = C("uranium_core")
        if item_id in ("diamond", "ruby", "emerald"):
            style = "gem"
        fn = SHAPES[style]
        rng = random.Random("shop_" + item_id)
        cv = Cv()
        # куча из трёх кусков: крупный, средний и мелкий — читается как «запас»
        if style in ("ingot", "bar", "facet"):
            fn(cv, 15, 16, 6, base, light, rng)
        elif style == "pebble_cluster":
            fn(cv, 16, 16, 4, base, light, rng)
        elif style in ("bead",):
            fn(cv, 13, 17, 6, base, light, rng)
            fn(cv, 23, 21, 3, base, light, rng)
            fn(cv, 22, 11, 2, base, light, rng)
        elif style == "glow":
            fn(cv, 16, 17, 6, base, light, rng)
        elif style == "fiber":
            fn(cv, 16, 17, 8, base, light, rng)
        elif style == "debris":
            fn(cv, 15, 15, 7, base, light, rng)
            fn(cv, 22, 23, 4, shade(base, 0.85), light, rng)
        else:
            fn(cv, 14, 18, 7, base, light, rng)
            fn(cv, 23, 21, 4, base, light, rng)
            fn(cv, 20, 9, 4, base, light, rng)
        if style != "glow":
            cv.outline()
        cv.save("item_" + item_id)


# --------------------------------------------------------------------------
# Предметы: переплавка, топливо, скважина
# --------------------------------------------------------------------------

def gen_crafted():
    # бронза: три слитка пирамидкой (трапеция спереди, светлая верхняя грань)
    cv = Cv()
    br, brl, brd = rgba("#B87333"), rgba("#E0A060"), rgba("#7A4A1E")

    def ingot(x, y):
        cv.poly([(x, y + 7), (x + 3, y + 1), (x + 15, y + 1), (x + 18, y + 7)], br)
        cv.poly([(x + 3, y + 1), (x + 6, y - 3), (x + 18, y - 3), (x + 15, y + 1)], brl)
        cv.poly([(x + 15, y + 1), (x + 18, y - 3), (x + 21, y + 3), (x + 18, y + 7)], brd)
        cv.line([(x + 4, y + 3), (x + 14, y + 3)], mix(br, brl, 0.6), 1)

    ingot(2, 21)
    ingot(10, 21)
    ingot(6, 14)
    cv.px(10, 15, WHITE)
    cv.outline()
    cv.save("item_bronze")

    # топливный блок: тёмный брикет с оранжевым огоньком
    for name, coal in (("item_fuel_block", False), ("item_fuel_block_coal", True)):
        cv = Cv()
        cv.rect(5, 12, 24, 25, rgba("#3A2A22"))
        cv.poly([(5, 12), (9, 8), (28, 8), (24, 12)], rgba("#5E4830"))
        cv.poly([(24, 12), (28, 8), (28, 21), (24, 25)], rgba("#241A14"))
        rng = random.Random(name)
        for _ in range(16):
            x, y = rng.randint(6, 23), rng.randint(13, 24)
            cv.px(x, y, rgba("#5E4830") if not coal else C("coal_light"))
        cv.ell(14, 19, 3, 4, rgba("#E8832E"))
        cv.poly([(14, 13), (17, 18), (14, 24), (11, 18)], rgba("#FFD84A"))
        cv.poly([(14, 16), (15, 19), (14, 23), (13, 19)], rgba("#FFF3A0"))
        if coal:
            ore_coal(cv, 25, 8, 3, C("coal_base"), C("coal_light"), random.Random(1))
        cv.outline()
        cv.save(name)

    # буровая скважина: вышка-решётка на основании с бочкой
    cv = Cv()
    steel, steel_l, steel_d = rgba("#8B99A2"), rgba("#D2DCE0"), rgba("#4C5862")
    cv.poly([(9, 27), (13, 6), (19, 6), (23, 27)], steel_d)
    cv.poly([(11, 27), (14, 8), (18, 8), (21, 27)], rgba("#1B1622"))
    for y in (11, 16, 21, 26):
        cv.line([(13 - (y - 6) // 5, y), (19 + (y - 6) // 5, y)], steel, 1)
    cv.line([(12, 26), (18, 11)], steel, 1)
    cv.line([(20, 26), (14, 11)], steel, 1)
    cv.line([(13, 6), (13, 26)], steel_l, 1)
    cv.rect(14, 3, 18, 6, rgba("#C21E3A"))
    cv.px(15, 4, rgba("#FF5570"))
    cv.rect(5, 27, 27, 29, rgba("#5C5C68"))
    cv.rect(5, 27, 27, 27, rgba("#7E7E8C"))
    cv.rect(22, 21, 27, 26, rgba("#C2703A"))
    cv.line([(22, 22), (27, 22)], rgba("#E89A5E"), 1)
    cv.outline()
    cv.save("item_well")

    # неизвестный предмет: серый булыжник
    cv = Cv()
    rng = random.Random("unknown")
    pts = blob_pts(16, 18, 10, 8, 9, 0.12, rng)
    shaded_poly(cv, pts, C("stone_base"), C("stone_light"), C("stone_shadow"), 16, 18, 10, 8)
    cv.px(11, 14, WHITE)
    cv.outline()
    cv.save("item_unknown")


# --------------------------------------------------------------------------
# Еда, допинги, гаджеты
# --------------------------------------------------------------------------

def rot_rect(cx, cy, w, h, ang):
    ca, sa = math.cos(ang), math.sin(ang)
    out = []
    for (x, y) in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
        out.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return out


def gen_full_restore_pill():
    """Таблетка полного восстановления: классическая капсула 💊 — вытянутая, по диагонали «/»,
    красная и белая половинки, шов, глянцевый блик и белый плюс с контуром на красной половине.
    Свет сверху-слева идёт поперёк оси капсулы, поэтому ступени тона ложатся полосами вдоль неё.
    Рисуем по маске «стадиона» (отрезок + два полукруга), без сглаживания: кромка держится
    ступенькой в 45 градусов. Плюс вертикальный, не повёрнутый, с толщиной штриха в 2 пикселя и
    на чётной сетке: при показе в 16x16 (тост, мелкий слот) он остаётся плюсом 5x5, а не крошится."""
    R, LEN = 7.0, 33.0               # радиус и полная длина капсулы
    HALF = LEN / 2 - R               # половина прямой части
    S = 0.70710678                   # ось «/»: вдоль (S, -S), поперёк (S, S)
    red = [rgba(h) for h in ("#FF8A9A", "#EC4A63", "#C9213D", "#A31A35", "#7A1230")]
    wht = [rgba(h) for h in ("#FFFFFF", "#F5F8FB", "#DDE4EE", "#B4C0D2", "#8896AE")]
    seam = rgba("#3A1220")
    ink = rgba("#4A0A1A")            # контур плюса темнее самой тёмной ступени красного
    cv = Cv()
    for y in range(32):
        for x in range(32):
            dx, dy = x + 0.5 - 16, y + 0.5 - 16
            u, v = S * (dx - dy), S * (dx + dy)
            au = abs(u) - HALF
            r = abs(v) if au <= 0 else math.hypot(au, v)
            if r > R:
                continue
            t = v / R                          # -1 сверху-слева ... +1 снизу-справа
            lo = (-0.55, 0.12, 0.58) if u < 0 else (-0.2, 0.3, 0.66)
            i = 1 if t < lo[0] else 2 if t < lo[1] else 3 if t < lo[2] else 4
            if r > R - 1.0 and t > 0.2:
                i = 4                          # нижняя кромка: самый тёмный ободок
            cv.px(x, y, (red if u < 0 else wht)[i])
    # шов: красная половинка чуть «надета» на белую — тёмная черта и тень от ободка на белой стороне
    for y in range(32):
        for x in range(32):
            k = x - y
            c = cv.get(x, y)
            if not c[3]:
                continue
            if k == 0:
                cv.px(x, y, seam)
            elif k == 1 and c in wht:
                cv.px(x, y, wht[min(wht.index(c) + 1, 4)])
    # глянцевый блик вдоль света: яркая черта на красной половине и короче — на белой
    def gloss(u0, u1, v, c):
        for k in range(int((u1 - u0) / S) + 1):
            u = u0 + k * S
            xx, yy = int(math.floor(16 + S * (u + v))), int(math.floor(16 + S * (v - u)))
            if cv.get(xx, yy)[3]:
                cv.px(xx, yy, c)
    gloss(-14.5, -8.5, -4.6, red[0])
    gloss(3.0, 8.0, -4.1, wht[0])
    # плюс: белый, штрих 2 пикселя, длина 10, центр на узле чётной сетки (11, 21)
    cx, cy = 11, 21
    cross = {(x, y) for x in range(cx - 5, cx + 5) for y in (cy - 1, cy)}
    cross |= {(x, y) for y in range(cy - 5, cy + 5) for x in (cx - 1, cx)}
    for (x, y) in cross:
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                if (x + ox, y + oy) not in cross:
                    cv.px(x + ox, y + oy, ink)
    for (x, y) in cross:
        cv.px(x, y, WHITE)
    cv.outline()
    cv.save("item_full_restore_pill")


def _plus_with_ink(cv, cx, cy, half, stroke, fill, ink):
    """Плюс на чётной сетке: штрих stroke пикселей, длина 2*half, тёмный контур по 8 соседям."""
    a, b = cx - stroke // 2, cx + (stroke + 1) // 2      # [a, b) по ширине штриха
    cross = {(x, y) for x in range(cx - half, cx + half) for y in range(cy - stroke // 2, cy + (stroke + 1) // 2)}
    cross |= {(x, y) for y in range(cy - half, cy + half) for x in range(a, b)}
    for (x, y) in cross:
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                if (x + ox, y + oy) not in cross:
                    cv.px(x + ox, y + oy, ink)
    for (x, y) in cross:
        cv.px(x, y, fill)
    return cross


def gen_medkit_icon():
    """Аптечка (раунд 4, healing): красный чемоданчик с ручкой и белым крестом — родня таблетке
    (тот же красный в пяти ступенях, тот же белый плюс с тёмным контуром и глянцевый блик), но
    силуэт другой: коробка, а не капсула, — в слоте рюкзака их не спутать. Свет сверху-слева:
    крышка светлее, правый торец и низ темнее, по кромке крышки — шов-защёлка."""
    red = [rgba(h) for h in ("#FF8A9A", "#EC4A63", "#C9213D", "#A31A35", "#7A1230")]
    ink = rgba("#4A0A1A")
    metal, metal_l, metal_d = rgba("#B4C0D2"), rgba("#F5F8FB"), rgba("#5C6478")
    cv = Cv()
    x0, x1, y0, y1 = 3, 28, 10, 28            # корпус включительно
    # ручка: дуга-скоба над крышкой
    cv.rect(11, 4, 20, 5, metal_d)
    cv.rect(10, 5, 11, 10, metal_d)
    cv.rect(20, 5, 21, 10, metal_d)
    cv.rect(12, 4, 19, 4, metal)
    cv.px(12, 4, metal_l)
    cv.px(13, 4, metal_l)
    cv.rect(10, 6, 10, 9, metal)
    # корпус: тело, светлая крышка, тёмный торец справа и низ
    cv.rect(x0, y0, x1, y1, red[2])
    cv.rect(x0, y0, x1, y0 + 4, red[1])            # крышка
    cv.rect(x0 + 1, y0, x1 - 2, y0, red[0])          # верхняя кромка крышки на свету
    cv.rect(x0, y0 + 5, x1, y0 + 5, red[4])        # шов крышки
    cv.rect(x1 - 2, y0 + 1, x1, y1, red[3])        # правый торец в тени
    cv.rect(x0, y1 - 1, x1, y1, red[4])            # низ
    cv.rect(x0, y0 + 1, x0, y1 - 2, red[1])        # левая грань на свету
    # защёлки на шве
    for zx in (7, 22):
        cv.rect(zx, y0 + 4, zx + 2, y0 + 6, metal_d)
        cv.px(zx, y0 + 4, metal_l)
        cv.px(zx + 1, y0 + 4, metal)
    # глянцевый блик на крышке
    cv.rect(x0 + 2, y0 + 1, x0 + 7, y0 + 1, red[0])
    cv.px(x0 + 2, y0 + 2, WHITE)
    cv.px(x0 + 3, y0 + 2, red[0])
    # крест: белый, штрих 4 пикселя, длина 12, центр на узле чётной сетки
    _plus_with_ink(cv, 16, 20, 6, 4, WHITE, ink)
    # тень на кресте снизу-справа — чтобы он не выглядел наклейкой
    for (x, y) in ((18, 23), (19, 23), (17, 25), (17, 24), (21, 21), (20, 21)):
        if cv.get(x, y) == WHITE:
            cv.px(x, y, rgba("#DDE4EE"))
    cv.outline()
    cv.save("item_medkit")


def gen_ambulance_icon():
    """Значок «скорая» для карточки смерти (раунд 4, healing: «скорая забрала» 200 монет): белый
    фургон боком, красная полоса и красный крест, синяя мигалка, тёмные колёса. Показывается в
    16x16 рядом с «−200», поэтому силуэт крупный, а деталей мало: кабина справа со стеклом,
    крест — плюс 6x6 на борту."""
    body = [rgba(h) for h in ("#FFFFFF", "#F5F8FB", "#DDE4EE", "#B4C0D2", "#8896AE")]
    red, red_d = rgba("#EC4A63"), rgba("#A31A35")
    glass, glass_l = rgba("#5C9BD8"), rgba("#B8E0FF")
    tire, hub = rgba("#241A22"), rgba("#8896AE")
    cv = Cv()
    # кузов-фургон (слева) и кабина со скосом (справа)
    cv.rect(2, 9, 21, 24, body[1])
    cv.poly([(21, 12), (25, 12), (29, 17), (29, 24), (21, 24)], body[1])
    cv.rect(2, 9, 20, 9, body[0])                  # крыша на свету
    cv.rect(2, 10, 2, 23, body[0])
    cv.rect(2, 22, 29, 24, body[3])                # низ в тени
    cv.rect(2, 24, 29, 24, body[4])
    cv.rect(21, 10, 21, 21, body[2])               # стык кузова и кабины
    # стекло кабины с бликом
    cv.poly([(23, 14), (25, 14), (27, 17), (23, 17)], glass)
    cv.px(23, 14, glass_l)
    cv.px(24, 14, glass_l)
    # красная полоса по борту
    cv.rect(2, 19, 29, 20, red)
    cv.rect(2, 21, 29, 21, red_d)
    # крест на борту
    _plus_with_ink(cv, 11, 14, 4, 2, red, red_d)
    # мигалка на крыше
    cv.rect(9, 6, 13, 8, rgba("#2E5C9C"))
    cv.rect(10, 6, 12, 7, rgba("#5C9BD8"))
    cv.px(10, 6, glass_l)
    # фара
    cv.rect(28, 19, 29, 20, rgba("#FFE066"))
    # колёса
    for wx in (8, 24):
        cv.ell(wx, 25, 3, 3, tire)
        cv.px(wx, 25, hub)
        cv.px(wx - 1, 24, hub)
    cv.outline()
    cv.save("glyph_ambulance")


def gen_energy_bar_icon():
    """Энергетический батончик: фиолетовая обёртка с золотыми гофрированными
    краями и крупной молнией поверх. Молния выступает за обёртку и обведена
    тёмным — читается и в 32x32, и в 16x16; не путать с белковым батончиком
    (красно-оранжевая наклонная обёртка) и энергетиком (синяя банка)."""
    cv = Cv()
    y0, y1 = 10, 22          # обёртка по высоте, включительно
    x0, x1 = 1, 30           # вместе с гофрой
    # тело обёртки: три тона по высоте
    cv.rect(x0 + 3, y0, x1 - 3, y1, rgba("#6A3FA8"))
    cv.rect(x0 + 3, y0, x1 - 3, y0 + 3, rgba("#9468D8"))
    cv.rect(x0 + 3, y0 + 4, x1 - 3, y0 + 5, rgba("#7E52C0"))
    cv.rect(x0 + 3, y1 - 3, x1 - 3, y1, rgba("#4A2A80"))
    cv.rect(x0 + 3, y1 - 1, x1 - 3, y1, rgba("#38206A"))
    # золотая гофра по краям: рёбра фольги и зубчатый срез
    for (gx0, gx1, tip) in ((x0, x0 + 3, -1), (x1 - 3, x1, 1)):
        cv.rect(gx0, y0 + 1, gx1, y1 - 1, rgba("#E8B32E"))
        for gx in range(gx0, gx1 + 1):
            cv.rect(gx, y0 + 1, gx, y1 - 1, rgba("#E8B32E") if (gx - gx0) % 2 == 0 else rgba("#B07A18"))
        cv.rect(gx0, y0 + 1, gx1, y0 + 2, rgba("#FFE066"))
        cv.rect(gx0, y1 - 2, gx1, y1 - 1, rgba("#9A6A14"))
        outer = gx0 if tip < 0 else gx1
        for gy in range(y0 + 1, y1, 2):      # зубцы по внешнему краю
            cv.px(outer, gy, (0, 0, 0, 0))
    # складка обёртки у гофры
    for cx in (x0 + 4, x1 - 4):
        cv.rect(cx, y0 + 1, cx, y1 - 1, rgba("#4A2A80"))
    # блик на плёнке
    cv.px(x0 + 6, y0 + 1, WHITE)
    cv.px(x0 + 7, y0 + 1, WHITE)
    cv.px(x1 - 5, y1 - 2, rgba("#9468D8"))
    # молния: тёмная подложка (контур по 8 направлениям) + золото + блик
    bolt = [(18, 6), (11, 17), (15, 17), (12, 26), (22, 14), (18, 14), (21, 6)]
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx or dy:
                cv.poly([(x + dx, y + dy) for x, y in bolt], OUT)
    cv.poly(bolt, rgba("#FFE066"))
    cv.poly([(18, 7), (12, 16), (15, 16), (17, 10)], rgba("#FFF8C8"))
    cv.poly([(16, 19), (13, 25), (21, 15), (17, 15)], rgba("#E8B32E"))
    cv.outline()
    cv.save("item_energy_bar")


def gen_food():
    # белковый батончик: наклонная обёртка с полосой и надорванным концом
    cv = Cv()
    ang = -0.5
    cv.poly(rot_rect(16, 16, 24, 11, ang), rgba("#CC5A3A"))
    cv.poly(rot_rect(16, 14.5, 24, 4, ang), rgba("#FF8A66"))
    cv.poly(rot_rect(16, 18.5, 24, 3, ang), rgba("#9C4028"))
    cv.poly(rot_rect(14, 16, 6, 7, ang), rgba("#FFE066"))
    cv.poly([(25, 8), (28, 9), (27, 13), (24, 12)], rgba("#6B4428"))
    cv.poly([(24, 10), (27, 9), (26, 12)], rgba("#8F6238"))
    cv.px(8, 21, WHITE)
    cv.outline()
    cv.save("item_food_bar")

    # лапша «Булдак»: красный стакан, крышка, пар, палочки
    cv = Cv()
    cv.poly([(7, 11), (25, 11), (22, 28), (10, 28)], rgba("#C21E3A"))
    cv.poly([(7, 11), (12, 11), (11, 28), (10, 28)], rgba("#FF5570"))
    cv.poly([(22, 28), (25, 11), (25, 13), (23, 28)], rgba("#7A1024"))
    cv.rect(11, 17, 21, 23, rgba("#FFE066"))
    cv.poly([(16, 18), (19, 21), (16, 22), (14, 20)], rgba("#E8832E"))
    cv.rect(5, 9, 27, 12, rgba("#F4F7FA"))
    cv.rect(5, 9, 27, 9, WHITE)
    cv.line([(12, 9), (21, 2)], rgba("#8F6238"), 1)
    cv.line([(15, 9), (24, 3)], rgba("#B4854E"), 1)
    for x in (10, 14):
        cv.line([(x, 8), (x + 1, 6), (x, 4)], rgba("#E8D8B0", 200), 1)
    cv.outline()
    cv.save("item_food_buldak")

    # пельмени: тарелка и три «ушка» с защипом
    cv = Cv()
    cv.ell(16, 20, 13, 7, rgba("#4A6C8C"))
    cv.ell(16, 19, 13, 6, rgba("#7FA3C8"))
    cv.ell(16, 19, 10, 4, rgba("#9CC0E0"))
    for (x, y) in ((10, 18), (17, 15), (21, 20)):
        pts = [(x - 5, y + 2), (x - 3, y - 2), (x + 2, y - 3), (x + 5, y + 1), (x + 2, y + 3)]
        cv.poly(pts, rgba("#F6E8C4"))
        cv.poly([(x - 5, y + 2), (x - 3, y - 2), (x, y - 2), (x - 1, y + 1)], WHITE)
        cv.line([(x - 3, y + 3), (x + 3, y + 3)], rgba("#C8B070"), 1)
        for k in range(-3, 4, 2):
            cv.px(x + k, y + 3, rgba("#A4835A"))
    for x in (9, 14):
        cv.line([(x, 9), (x + 1, 7), (x, 5)], rgba("#E8EEF4", 190), 1)
    cv.outline()
    cv.save("item_food_dumplings")

    # стейк с пюре и салатом
    cv = Cv()
    cv.ell(16, 19, 14, 9, rgba("#E8EEF4"))
    cv.ell(16, 18, 14, 8, WHITE)
    cv.ell(16, 18, 11, 6, rgba("#D2DCE0"))
    cv.poly([(6, 17), (10, 12), (18, 12), (21, 17), (17, 22), (9, 22)], rgba("#7A3A22"))
    cv.poly([(7, 17), (10, 13), (16, 13), (14, 17), (10, 21)], rgba("#A05A32"))
    for y in (15, 18):
        cv.line([(9, y), (18, y + 1)], rgba("#4A2214"), 1)
    cv.ell(23, 18, 4, 3, rgba("#F6E8C4"))
    cv.px(22, 17, WHITE)
    cv.ell(24, 23, 3, 2, rgba("#4F7A34"))
    cv.px(22, 22, rgba("#7FB86B"))
    cv.px(25, 22, rgba("#7FB86B"))
    cv.px(23, 23, rgba("#C21E3A"))
    cv.outline()
    cv.save("item_food_steak")

    # энергетик: высокая банка с молнией
    cv = Cv()
    cv.rect(10, 6, 22, 27, rgba("#2E5C9C"))
    cv.rect(10, 6, 13, 27, rgba("#5C9BD8"))
    cv.rect(20, 6, 22, 27, rgba("#1E3C6C"))
    cv.rect(10, 4, 22, 7, rgba("#B8C4C8"))
    cv.rect(10, 4, 22, 4, rgba("#F4F7FA"))
    cv.rect(10, 26, 22, 28, rgba("#B8C4C8"))
    cv.poly([(18, 9), (13, 17), (16, 17), (14, 24), (20, 15), (17, 15)], rgba("#FFE066"))
    cv.poly([(18, 9), (14, 16), (16, 16)], rgba("#FFF3A0"))
    cv.rect(15, 2, 17, 3, rgba("#8B99A2"))
    cv.outline()
    cv.save("item_energy_drink")

    gen_energy_bar_icon()

    # таблетка полного восстановления: капсула 💊 с плюсом (рисует gen_full_restore_pill)
    gen_full_restore_pill()

    # аптечка и «скорая» карточки смерти (раунд 4, healing)
    gen_medkit_icon()
    gen_ambulance_icon()

    # часы-телепорт: ремешок, золотой корпус, синий циферблат со стрелками
    cv = Cv()
    cv.rect(12, 2, 20, 8, rgba("#6B4428"))
    cv.rect(12, 24, 20, 30, rgba("#6B4428"))
    cv.line([(13, 3), (13, 7)], rgba("#8F6238"), 1)
    cv.ell(16, 16, 11, 11, rgba("#B07A18"))
    cv.ell(16, 16, 10, 10, rgba("#FFE066"))
    cv.ell(16, 16, 8, 8, rgba("#E8B32E"))
    cv.ell(16, 16, 7, 7, rgba("#2E5C9C"))
    cv.ell(15, 15, 5, 5, rgba("#5C9BD8"))
    cv.ell(16, 16, 7, 7, rgba("#2E5C9C"))
    cv.ell(16, 16, 6, 6, rgba("#5C9BD8"))
    cv.line([(16, 16), (16, 11)], WHITE, 1)
    cv.line([(16, 16), (20, 18)], WHITE, 1)
    cv.px(16, 16, rgba("#FFE066"))
    for (x, y) in ((16, 11), (21, 16), (16, 21), (11, 16)):
        pass
    cv.px(13, 12, WHITE)
    cv.outline()
    cv.save("item_teleport_watch")


# --------------------------------------------------------------------------
# Вкладки
# --------------------------------------------------------------------------

def gen_tabs():
    # еда: бутерброд-бургер
    cv = Cv()
    cv.poly([(5, 14), (6, 8), (11, 4), (21, 4), (26, 8), (27, 14)], rgba("#C8843C"))
    cv.poly([(6, 12), (7, 8), (11, 5), (15, 5), (11, 10), (8, 13)], rgba("#E8A85A"))
    for (x, y) in ((12, 8), (17, 7), (21, 9), (15, 11)):
        cv.px(x, y, rgba("#F6E8C4"))
        cv.px(x + 1, y, rgba("#F6E8C4"))
    cv.rect(4, 15, 28, 17, rgba("#4F7A34"))
    for x in range(4, 28, 4):
        cv.rect(x, 17, x + 1, 18, rgba("#4F7A34"))
    cv.rect(4, 15, 28, 15, rgba("#7FB86B"))
    cv.rect(5, 18, 27, 19, rgba("#E8B32E"))
    cv.rect(4, 20, 28, 23, rgba("#6B3A22"))
    cv.rect(4, 20, 28, 20, rgba("#8F5A38"))
    cv.poly([(5, 24), (27, 24), (25, 28), (7, 28)], rgba("#C8843C"))
    cv.rect(5, 24, 27, 24, rgba("#E8A85A"))
    cv.outline()
    cv.save("tab_food")

    # техника: шестерня
    cv = Cv()
    steel, steel_l, steel_d = rgba("#8B99A2"), rgba("#D2DCE0"), rgba("#4C5862")
    cx = cy = 16
    pts = []
    for i in range(16):
        a = i / 16 * 2 * math.pi
        r = 14 if (i % 2 == 0) else 10.5
        a0 = a - 0.19
        a1 = a + 0.19
        pts.append((cx + math.cos(a0) * r, cy + math.sin(a0) * r))
        pts.append((cx + math.cos(a1) * r, cy + math.sin(a1) * r))
    shaded_poly(cv, pts, steel, steel_l, steel_d, cx, cy, 14, 14)
    cv.ell(cx, cy, 8, 8, steel_d)
    cv.ell(cx, cy, 7, 7, steel)
    cv.ell(cx, cy, 4, 4, rgba("#1B1622"))
    cv.ell(cx, cy, 3, 3, rgba("#33394A"))
    cv.px(cx - 5, cy - 5, WHITE)
    cv.outline()
    cv.save("tab_tech")

    # продажа: мешок с монетой
    cv = Cv()
    cv.poly([(9, 12), (23, 12), (28, 22), (25, 29), (7, 29), (4, 22)], rgba("#B4854E"))
    cv.poly([(9, 12), (13, 12), (9, 20), (5, 24), (4, 22)], rgba("#D4A86E"))
    cv.poly([(23, 12), (28, 22), (25, 29), (22, 29), (24, 20)], rgba("#8F6238"))
    cv.poly([(10, 12), (12, 6), (15, 9), (16, 5), (17, 9), (20, 6), (22, 12)], rgba("#B4854E"))
    cv.rect(9, 11, 23, 13, rgba("#C21E3A"))
    cv.rect(9, 11, 23, 11, rgba("#FF5570"))
    cv.ell(16, 21, 5, 5, rgba("#B07A18"))
    cv.ell(16, 21, 4, 4, rgba("#FFE066"))
    cv.ell(16, 21, 2, 2, rgba("#E8B32E"))
    cv.px(14, 19, WHITE)
    cv.outline()
    cv.save("tab_sell")

    # снаряжение: крупная кирка на скрещённом с лопатой черенке
    cv = Cv()
    cv.line([(7, 29), (21, 12)], rgba("#6B4428"), 4)
    cv.line([(6, 28), (20, 11)], rgba("#8F6238"), 2)
    steel, steel_l, steel_d = rgba("#8B99A2"), rgba("#D2DCE0"), rgba("#4C5862")
    head = [(10, 8), (16, 4), (24, 4), (29, 9), (29, 13), (26, 10), (22, 8), (18, 9), (16, 14), (12, 13)]
    shaded_poly(cv, head, steel, steel_l, steel_d, 20, 9, 11, 7)
    cv.line([(12, 9), (17, 6)], WHITE, 1)
    cv.outline()
    cv.save("tab_picks")

    # доллары: огранённый изумруд с искрой
    cv = Cv()
    pts = [(16, 3), (26, 10), (26, 20), (16, 29), (6, 20), (6, 10)]
    cv.poly(pts, rgba("#1C8A52"))
    cv.poly([(16, 3), (6, 10), (6, 20), (16, 29), (16, 16)], rgba("#4DE094"))
    cv.poly([(16, 3), (26, 10), (16, 16)], rgba("#B8FFD8"))
    cv.poly([(16, 29), (26, 20), (26, 10), (16, 16)], rgba("#0F6638"))
    cv.line([(6, 10), (16, 16), (26, 10)], rgba("#B8FFD8"), 1)
    cv.line([(6, 20), (16, 16), (26, 20)], rgba("#0F6638"), 1)
    cv.px(9, 11, WHITE)
    cv.px(10, 11, WHITE)
    cv.rect(26, 2, 27, 6, WHITE)
    cv.rect(24, 4, 29, 5, WHITE)
    cv.outline()
    cv.save("tab_premium")


# --------------------------------------------------------------------------
# Прочее: ролик, обмен
# --------------------------------------------------------------------------

def gen_misc():
    # телевизор с кнопкой «играть»: значок ролика (ad_tv)
    cv = Cv()
    cv.rect(3, 6, 28, 24, rgba("#33394A"))
    cv.rect(5, 8, 26, 22, rgba("#5C9BD8"))
    cv.rect(5, 8, 26, 12, rgba("#8FC4F4"))
    cv.poly([(13, 11), (13, 20), (21, 15.5)], WHITE)
    cv.rect(9, 25, 22, 27, rgba("#33394A"))
    cv.line([(10, 5), (15, 1)], rgba("#8B99A2"), 1)
    cv.line([(21, 5), (16, 1)], rgba("#8B99A2"), 1)
    cv.outline()
    cv.save("item_ad_tv")

    # обмен: доллар -> монета
    cv = Cv()
    cv.rect(1, 9, 14, 20, rgba("#1C8A52"))
    cv.rect(1, 9, 14, 10, rgba("#4DE094"))
    cv.rect(1, 19, 14, 20, rgba("#0F6638"))
    cv.line([(7, 11), (7, 18)], rgba("#B8FFD8"), 1)
    cv.line([(4, 13), (10, 13)], rgba("#B8FFD8"), 1)
    cv.line([(4, 16), (10, 16)], rgba("#B8FFD8"), 1)
    cv.poly([(15, 13), (19, 13), (19, 10), (24, 15), (19, 20), (19, 17), (15, 17)], rgba("#F2D99B"))
    cv.ell(26, 22, 5, 5, rgba("#B07A18"))
    cv.ell(26, 22, 4, 4, rgba("#FFE066"))
    cv.ell(26, 22, 2, 2, rgba("#E8B32E"))
    cv.px(24, 20, WHITE)
    cv.outline()
    cv.save("item_exchange")

    # купить доллары: банкнота с плюсом (в этой сборке закрыто)
    cv = Cv()
    cv.rect(3, 8, 24, 22, rgba("#1C8A52"))
    cv.rect(3, 8, 24, 10, rgba("#4DE094"))
    cv.rect(3, 21, 24, 22, rgba("#0F6638"))
    cv.line([(13, 11), (13, 20)], rgba("#B8FFD8"), 1)
    cv.line([(9, 13), (17, 13)], rgba("#B8FFD8"), 1)
    cv.line([(9, 17), (17, 17)], rgba("#B8FFD8"), 1)
    cv.rect(23, 16, 26, 28, rgba("#FFE066"))
    cv.rect(18, 21, 30, 24, rgba("#FFE066"))
    cv.outline()
    cv.save("item_buy_dollars")


# --------------------------------------------------------------------------

def contact_sheet(path):
    names = sorted(SAVED)
    cell = 72
    cols = 10
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (52, 44, 60, 255))
    for i, n in enumerate(names):
        im = Image.open(os.path.join(OUTDIR, n + ".png")).convert("RGBA")
        scale = 2 if im.width <= 32 else 1
        if im.width <= 16 and im.height <= 16:
            scale = 3
        big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        x = (i % cols) * cell + (cell - big.width) // 2
        y = (i // cols) * cell + (cell - big.height) // 2
        sheet.alpha_composite(big, (x, y))
    sheet.save(path)


def main():
    gen_frames()
    for fn in (glyph_check, glyph_cross, glyph_lock, glyph_new, glyph_video, glyph_gift, glyph_house,
               glyph_arrow, glyph_hammer, glyph_storage, glyph_x2, glyph_plus, glyph_dig, glyph_fly,
               glyph_depth, glyph_stat_dot):
        fn()
    gen_ores()
    gen_crafted()
    gen_food()
    gen_tabs()
    gen_misc()
    print("записано %d файлов в %s" % (len(SAVED), OUTDIR))
    if "--sheet" in sys.argv:
        contact_sheet(sys.argv[sys.argv.index("--sheet") + 1])


if __name__ == "__main__":
    main()

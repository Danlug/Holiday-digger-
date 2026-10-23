#!/usr/bin/env python3
"""pix.py — маленькая библиотека для пиксель-арта «программист нарисовал аккуратно».

Общая для tools/gen_artifact_art.py и tools/gen_hero_icons.py. Без антиалиасинга:
PIL рисует примитивы ступеньками, цвета берутся только из явно заданных тонов.

Идея: фигуры кладутся слоями «от дальней к ближней». Каждая фигура получает
фаску — светлый пиксель по верхней/левой кромке и тёмный по нижней/правой
(свет сверху-слева), — поэтому плоская заливка читается объёмной. В конце
весь силуэт обводится тёмным цветом в 1 пиксель.
"""

import math

import numpy as np
from PIL import Image, ImageDraw


def hexc(s, a=255):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


def tint(color, f):
    """f > 0 — к белому, f < 0 — к чёрному."""
    r, g, b, a = color
    if f >= 0:
        return (int(r + (255 - r) * f), int(g + (255 - g) * f), int(b + (255 - b) * f), a)
    k = 1.0 + f
    return (int(r * k), int(g * k), int(b * k), a)


def rot(points, deg, ox=0.0, oy=0.0):
    """Поворот списка точек вокруг (ox, oy); результат — целые координаты."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    out = []
    for x, y in points:
        dx, dy = x - ox, y - oy
        out.append((round(ox + dx * ca - dy * sa), round(oy + dx * sa + dy * ca)))
    return out


def shift(points, tx, ty):
    return [(x + tx, y + ty) for x, y in points]


class Spr:
    def __init__(self, size=32):
        self.n = size
        self.a = np.zeros((size, size, 4), np.uint8)

    # --- маски -----------------------------------------------------------
    def mask(self, fn):
        m = Image.new("L", (self.n, self.n), 0)
        fn(ImageDraw.Draw(m))
        return np.array(m) > 0

    @staticmethod
    def _sh(m, dx, dy):
        """m[y-dy, x-dx]: значение соседа слева-сверху при (1, 1)."""
        out = np.zeros_like(m)
        h, w = m.shape
        ys = slice(max(dy, 0), h + min(dy, 0))
        xs = slice(max(dx, 0), w + min(dx, 0))
        yd = slice(max(-dy, 0), h + min(-dy, 0))
        xd = slice(max(-dx, 0), w + min(-dx, 0))
        out[ys, xs] = m[yd, xd]
        return out

    # --- заливка ---------------------------------------------------------
    def fill(self, m, color, bevel=True, hi=0.38, lo=0.36):
        if bevel:
            ul = self._sh(m, 1, 1)
            dr = self._sh(m, -1, -1)
            light = m & ~ul & dr
            dark = m & ~dr & ul
            self.a[m] = color
            self.a[light] = tint(color, hi)
            self.a[dark] = tint(color, -lo)
        else:
            self.a[m] = color

    def ell(self, cx, cy, rx, ry, color, **kw):
        self.fill(self.mask(lambda d: d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)), color, **kw)

    def rect(self, x0, y0, x1, y1, color, **kw):
        self.fill(self.mask(lambda d: d.rectangle([x0, y0, x1, y1], fill=255)), color, **kw)

    def poly(self, pts, color, **kw):
        self.fill(self.mask(lambda d: d.polygon(pts, fill=255)), color, **kw)

    def line(self, pts, color, w=1):
        self.fill(self.mask(lambda d: d.line(pts, fill=255, width=w)), color, bevel=False)

    def px(self, x, y, color):
        if 0 <= x < self.n and 0 <= y < self.n:
            self.a[y, x] = color

    def pxs(self, pts, color):
        for x, y in pts:
            self.px(x, y, color)

    def sparkle(self, x, y, color, big=False):
        self.px(x, y, color)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            self.px(x + dx, y + dy, tint(color, -0.15))
        if big:
            for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)):
                self.px(x + dx, y + dy, tint(color, -0.3))

    def alpha_mask(self):
        return self.a[:, :, 3] > 0

    def outline(self, color, diag=True):
        am = self.alpha_mask()
        grow = am.copy()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) + (((1, 1), (-1, -1), (1, -1), (-1, 1)) if diag else ()):
            grow |= self._sh(am, dx, dy)
        edge = grow & ~am
        self.a[edge] = color

    def image(self):
        return Image.fromarray(self.a, "RGBA")


def contact_sheet(images, labels, cols, out_path, scale=6, bg=(52, 48, 60)):
    """Лист для просмотра глазами: иконки крупно на непрозрачном фоне."""
    from PIL import ImageFont  # noqa: F401
    n = images[0].size[0]
    cell = n * scale + 16
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 12)), bg)
    d = ImageDraw.Draw(sheet)
    for i, (im, lab) in enumerate(zip(images, labels)):
        x = (i % cols) * cell + 8
        y = (i // cols) * (cell + 12) + 8
        big = im.resize((n * scale, n * scale), Image.NEAREST)
        sheet.paste(big, (x, y), big)
        d.text((x, y + n * scale + 1), lab, fill=(240, 210, 90))
    sheet.save(out_path)

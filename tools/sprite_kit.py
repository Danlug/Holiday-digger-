#!/usr/bin/env python3
"""sprite_kit.py — общая кисть для пиксель-арта на сетке 32x32 (спрайты руд, значки).

Спрайт рисуется на сетке G x G с альфой; для плитки мира растягивается в T x T
(ART_SCALE 3, ближайшим соседом), для значка предмета остаётся 32x32.
"""

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

T = 96   # размер тайла в пикселях текстуры (ART_SCALE 3 x 32)
G = 32   # сетка пиксель-арта


class Sprite:
    def __init__(self):
        self.img = Image.new("RGBA", (G, G), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def poly(self, pts, fill):
        self.d.polygon(pts, fill=fill + (255,))

    def px(self, x, y, c, a=255):
        if 0 <= x < G and 0 <= y < G:
            self.img.putpixel((int(x), int(y)), tuple(int(v) for v in c) + (a,))

    def line(self, a, b, c, a_=255):
        self.d.line([a, b], fill=tuple(c) + (a_,), width=1)

    def outline(self, color):
        """Контур в 1 пиксель вокруг непрозрачного (сначала тень, затем фигура — поэтому красим пустые соседи)."""
        src = self.img.copy()
        px = src.load()
        out = self.img.load()
        for y in range(G):
            for x in range(G):
                if px[x, y][3] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < G and 0 <= ny < G and px[nx, ny][3] > 0:
                            out[x, y] = color + (255,)
                            break

    def glow(self, color, radius, alpha):
        """Мягкое свечение под фигурой (на сетке 32 — потом растянется)."""
        a = np.array(self.img)[..., 3].astype(np.float64)
        blur = np.array(Image.fromarray(a.astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius)), dtype=np.float64) / 255.0
        h = np.zeros((G, G, 4), dtype=np.uint8)
        h[..., :3] = color
        h[..., 3] = np.clip(blur * alpha * 255, 0, 255)
        base = Image.fromarray(h, "RGBA")
        base.alpha_composite(self.img)
        self.img = base

    def upscale(self):
        return self.img.resize((T, T), Image.NEAREST)

    def icon(self):
        """Значок предмета: та же сетка 32x32, без растягивания."""
        return self.img.copy()

#!/usr/bin/env python3
"""ores_metals.py — спрайты металлов, топлива и «земляных» ресурсов (ветка «ores-metals»).

Контракт реестра (его читают tools/gen_tiles_deep.py, tools/gen_ore_icons.py, tools/check_ores.py):

  TILES = {"ore_iron": fn, ...}   # имя тайла -> fn() -> sprite_kit.Sprite: ЗАЛЕЖЬ на сетке 32x32 с альфой,
                                  # без грунта (грунт пояса подкладывает генератор: ore_<имя>.png для пояса 0
                                  # и ячейки атласов поясов 1..7).
  ICONS = {"iron_ore": fn, ...}   # id минерала из data/minerals.json -> fn() -> Sprite: значок ПРЕДМЕТА 32x32
                                  # (один предмет/кучка без грунта) -> art/ui/shop/item_<id>.png.
                                  # Для ресурса из TILES без записи в ICONS значком станет сам спрайт тайла.

Ресурсы этой ветки (тайл + значок): ore_iron, ore_lead, ore_silver, ore_copper, ore_aluminium, ore_nickel,
ore_platinum, ore_titanium, ore_lithium, ore_mercury, ore_gold, ore_scrap, ore_peat, ore_coal, ore_uranium.
Только значки: bronze, fuel_block, fuel_block_coal.
Соответствие имя тайла -> id минерала: ore_iron -> iron_ore, ore_universalium -> universum, остальные — без префикса ore_.

Как нарисовано. Каждый материал — лесенка из 8 тонов (контур, глубокая тень, тень, тёмная база, база, свет,
яркий свет, блик), цвет задан в Lab: светлота, хрома, оттенок (см. lch). Куски — маски на сетке 32x32; «купол»
(dome) освещает кусок как полусферу светом сверху-слева с упорядоченным дизерингом, отражённым светом на тёмной
стороне и бликом; плиты, призмы, грани и жилы красятся плоскими тонами по нормали грани. Куски перекрываются, у
каждого свой контур оттенка материала (не чёрный); под залежью — мягкая тень на грунт. Кисть своя: общие
tools/sprite_kit.py и tools/gen_tiles_deep.py не правятся. Замена-заглушка уровня «программист нарисовал
аккуратно», не работа художника владельца.

Цветовая карта (средний Lab тела залежи: L a b — то, на что настроены лесенки; check_ores требует ΔE >= 20 между
соседями и >= 20 до грунта каждого пояса, поэтому цвета брифа сдвинуты там, где иначе не пройти):
  серебро 87 0 -2 | платина 79 20 -15 | алюминий 71 -2 -15 | ртуть 58 -17 -9 | свинец 50 4 -16 | титан 49 20 -38
  никель 60 -17 21 | железо 41 26 25 | медь 60 31 40 | золото 72 12 61 | металлолом 51 1 8 | торф 50 11 40
  уголь 6 -2 4 | уран 66 -41 47 | литий 65 35 -20
"""

import math

import numpy as np
from PIL import Image, ImageDraw

from sprite_kit import Sprite, G

# ── цвет ────────────────────────────────────────────────────────────────────

_M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
_MI = np.linalg.inv(_M)
_WP = np.array([0.95047, 1.0, 1.08883])


def _lab_to_lin(L, a, b):
    fy = (L + 16) / 116.0
    fx, fz = fy + a / 500.0, fy - b / 200.0
    f = np.array([fx, fy, fz])
    xyz = np.where(f ** 3 > 0.008856, f ** 3, (f - 16 / 116.0) / 7.787) * _WP
    return _MI @ xyz


def _lin_to_rgb(lin):
    c = np.where(lin > 0.0031308, 1.055 * np.clip(lin, 0, None) ** (1 / 2.4) - 0.055, 12.92 * lin)
    return c * 255.0


def lch(L, C, h):
    """Цвет из Lab: светлота L, хрома C, оттенок h (градусы Lab: 30 красный, 60 оранж, 90 жёлтый, 130 зелёный,
    200 бирюзовый, 250 синий, 300 фиолетовый, 340 розовый). За гамут — хрому убавляем."""
    for _ in range(40):
        lin = _lab_to_lin(L, C * math.cos(math.radians(h)), C * math.sin(math.radians(h)))
        rgb = _lin_to_rgb(lin)
        if rgb.min() >= -0.5 and rgb.max() <= 255.5:
            break
        C *= 0.95
    return tuple(int(round(float(v))) for v in np.clip(rgb, 0, 255))


def lab_of(c):
    v = np.array(c, dtype=np.float64) / 255.0
    lin = np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)
    xyz = (_M @ lin) / _WP
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return 116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])


def ramp(h, C, Ls, dh_dark=-8.0, dh_light=6.0, c_dark=0.8, c_light=0.6, spec=None):
    """8 тонов от контура до блика по светлотам Ls. Хрома C — в середине лесенки: к теням держится на c_dark,
    к светам тает до c_light; тени уходят в холодное (dh_dark), света — в тёплое (dh_light). spec — готовый блик."""
    out = []
    for i in range(8):
        t = i / 7.0
        hh = h + dh_dark * (1 - t) + dh_light * t
        mid = 1.0 - abs(t - 0.5) * 2.0
        cc = C * (c_dark + (1.0 - c_dark) * mid) * (1.0 - (1.0 - c_light) * max(0.0, t - 0.55) / 0.45)
        out.append(lch(Ls[i], cc, hh))
    if spec is not None:
        out[7] = spec
    return out


def shift(c, dl=0.0, dc=1.0):
    """Тот же оттенок, светлота +dl, хрома x dc."""
    L, A, B = lab_of(c)
    C = math.hypot(A, B) * dc
    return lch(max(0.0, min(100.0, L + dl)), C, math.degrees(math.atan2(B, A)) % 360)


# ── маски ───────────────────────────────────────────────────────────────────

_YY, _XX = np.mgrid[0:G, 0:G]


def poly(pts):
    im = Image.new("L", (G, G), 0)
    ImageDraw.Draw(im).polygon([(float(x), float(y)) for x, y in pts], fill=255)
    return np.array(im) > 0


def blob(cx, cy, rx, ry, rot=0.0, lump=0.10, seed=1, harm=4, p=2.0):
    """Неровный овал (суперэллипс с шумом по радиусу): валун, самородок, голыш."""
    x = _XX + 0.5 - cx
    y = _YY + 0.5 - cy
    c, s = math.cos(rot), math.sin(rot)
    u = (x * c + y * s) / rx
    v = (-x * s + y * c) / ry
    th = np.arctan2(v, u)
    rng = np.random.default_rng(seed)
    r = np.ones_like(th)
    for k in range(2, 2 + harm):
        r += lump * rng.uniform(0.4, 1.0) * np.cos(k * th + rng.uniform(0, math.tau)) / math.sqrt(k - 1)
    d = (np.abs(u) ** p + np.abs(v) ** p) ** (1.0 / p)
    return d <= r


def disc(cx, cy, r):
    return ((_XX + 0.5 - cx) ** 2 + (_YY + 0.5 - cy) ** 2) <= r * r


def hexagon(cx, cy, r, squash=1.0, rot=0.0, flat=True):
    pts = []
    for k in range(6):
        a = k * math.pi / 3 + rot + (0 if flat else math.pi / 6)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a) * squash))
    return pts


def rot_pts(pts, cx, cy, ang):
    c, s = math.cos(ang), math.sin(ang)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def dilate(mask):
    p = np.pad(mask, 1)
    return mask | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]


def erode(mask):
    p = np.pad(mask, 1)
    return mask & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]


def shifted(mask, dx, dy):
    out = np.zeros_like(mask)
    ys, xs = np.nonzero(mask)
    ys, xs = ys + dy, xs + dx
    ok = (ys >= 0) & (ys < G) & (xs >= 0) & (xs < G)
    out[ys[ok], xs[ok]] = True
    return out


def inside_dist(mask):
    """Расстояние от пикселя внутри маски до ближайшего пустого (край холста — пустота): на краю = 1."""
    pad = np.pad(mask, 1)
    ins = np.argwhere(pad)
    out = np.zeros(pad.shape)
    if len(ins):
        outs = np.argwhere(~pad)
        d = np.sqrt(((ins[:, None, :] - outs[None, :, :]) ** 2).sum(-1)).min(1)
        out[pad] = d
    return out[1:-1, 1:-1]


def line_mask(a, b):
    im = Image.new("L", (G, G), 0)
    ImageDraw.Draw(im).line([a, b], fill=255, width=1)
    return np.array(im) > 0


def vnoise(seed, cell=4.0):
    """Гладкий шум 0..1 на сетке (билинейно по случайной решётке)."""
    rng = np.random.default_rng(seed)
    n = int(G / cell) + 3
    g = rng.random((n, n))
    u = _XX / cell
    v = _YY / cell
    i0, j0 = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = u - i0, v - j0
    fu, fv = fu * fu * (3 - 2 * fu), fv * fv * (3 - 2 * fv)
    a = g[j0, i0] * (1 - fu) + g[j0, i0 + 1] * fu
    b = g[j0 + 1, i0] * (1 - fu) + g[j0 + 1, i0 + 1] * fu
    return a * (1 - fv) + b * fv


_BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 0.5
_BAYER = np.tile(_BAYER, (G // 4, G // 4))

_LIGHT = np.array([-0.52, -0.62, 0.58])
_LIGHT = _LIGHT / np.linalg.norm(_LIGHT)
_HALF = _LIGHT + np.array([0.0, 0.0, 1.0])
_HALF = _HALF / np.linalg.norm(_HALF)


# ── холст ───────────────────────────────────────────────────────────────────

class Pic:
    """Рисунок: RGB + непрозрачность. Куски кладутся друг на друга в порядке вызова."""

    def __init__(self):
        self.rgb = np.zeros((G, G, 3), dtype=np.uint8)
        self.solid = np.zeros((G, G), dtype=bool)

    # ---- общие операции

    def paint(self, mask, color):
        self.rgb[mask] = color
        self.solid |= mask

    def paint_arr(self, mask, arr):
        self.rgb[mask] = arr[mask]
        self.solid |= mask

    def ring(self, mask, color):
        """Контур снаружи маски (4-соседство): поверх уже нарисованного, не поверх самой маски."""
        r = dilate(mask) & ~mask
        self.rgb[r] = color
        self.solid |= r

    def px(self, x, y, color):
        x, y = int(x), int(y)
        if 0 <= x < G and 0 <= y < G:
            self.rgb[y, x] = color
            self.solid[y, x] = True

    def px_in(self, mask, x, y, color):
        x, y = int(x), int(y)
        if 0 <= x < G and 0 <= y < G and mask[y, x]:
            self.rgb[y, x] = color

    def line(self, a, b, color, clip=None):
        m = line_mask((int(round(a[0])), int(round(a[1]))), (int(round(b[0])), int(round(b[1]))))
        if clip is not None:
            m &= clip
        self.rgb[m] = color
        if clip is None:
            self.solid |= m

    def sparkle(self, x, y, arm, core, arm_col, solid_core=True):
        """Искра-крестик: яркий центр и четыре луча (1 пиксель шириной)."""
        for k in range(1, arm + 1):
            c = arm_col if k < arm or arm == 1 else shift(arm_col, -10)
            for dx, dy in ((k, 0), (-k, 0), (0, k), (0, -k)):
                self.px(x + dx, y + dy, c)
        self.px(x, y, core)

    # ---- закраска кусков

    def shade(self, mask, rp, relief=1.0, lo=-0.85, hi=1.15, dither=0.55, spec_k=14.0, spec_thr=0.93,
              spec=True, bounce=0.34, tex=None, streaks=(), R=None, light=None, alt=None):
        """Купол: полусфера, свет сверху-слева. Возвращает массив RGB (G,G,3) (значения вне маски не важны)."""
        d = inside_dist(mask)
        dmax = max(d.max(), 1.0)
        Rr = R if R is not None else max(2.0, dmax * 0.95)
        u = np.clip((d - 0.35) / Rr, 0.0, 1.0)
        sin_t = (1.0 - u) * relief
        cos_t = np.sqrt(np.clip(1.0 - sin_t ** 2, 0.0, 1.0))
        gy, gx = np.gradient(np.pad(d, 1))
        gy, gx = gy[1:-1, 1:-1], gx[1:-1, 1:-1]
        gn = np.hypot(gx, gy)
        ox = np.where(gn > 1e-6, -gx / np.maximum(gn, 1e-6), 0.0)
        oy = np.where(gn > 1e-6, -gy / np.maximum(gn, 1e-6), 0.0)
        nx, ny, nz = sin_t * ox, sin_t * oy, cos_t
        Lt = _LIGHT if light is None else light
        I = nx * Lt[0] + ny * Lt[1] + nz * Lt[2]
        if tex is not None:
            I = I + tex
        t = np.clip((I - lo) / (hi - lo), 0.0, 1.0)
        for off, w, amt in streaks:
            diag = (_XX + _YY).astype(float)
            t = np.where((diag >= off) & (diag < off + w) & (I > -0.2), np.clip(t + amt, 0, 1), t)
        if bounce:
            rimdark = (d <= 2.2) & (nx * Lt[0] + ny * Lt[1] < -0.22)
            t = np.where(rimdark, np.maximum(t, bounce), t)
        idx = np.floor(t * 5.999 + _BAYER * dither + 1.0 + 0.5)
        idx = np.clip(idx, 1, 6).astype(int)
        if spec:
            sp = nx * _HALF[0] + ny * _HALF[1] + nz * _HALF[2]
            sp = np.where(mask, np.maximum(sp, 0.0) ** spec_k, 0.0)
            hit = sp >= spec_thr
            if not hit.any() and sp.max() > 0.5:
                hit = sp >= sp.max() - 1e-9
            idx = np.where(hit, 7, idx)
        arr = np.zeros((G, G, 3), dtype=np.uint8)
        pal = np.array(rp, dtype=np.uint8)
        arr[...] = pal[idx]
        if alt is not None:
            am, rp2 = alt
            arr[am] = np.array(rp2, dtype=np.uint8)[idx][am]
        return arr

    def dome(self, mask, rp, outline=True, rim=None, **kw):
        if outline:
            if rim is not None:
                self.rim_ring(mask, rp[0], rim)
            else:
                self.ring(mask, rp[0])
        self.paint_arr(mask, self.shade(mask, rp, **kw))

    def rim_ring(self, mask, dark, light):
        """Контур с ободком света: клетки контура на освещённой (верх-лево) стороне куска — light, на тёмной — dark."""
        r = dilate(mask) & ~mask
        pad = np.pad(mask, 1)
        right = pad[1:-1, 2:]
        below = pad[2:, 1:-1]
        left = pad[1:-1, :-2]
        above = pad[:-2, 1:-1]
        lit = r & (right | below) & ~(left | above)
        self.rgb[r] = dark
        self.rgb[lit] = light
        self.solid |= r

    def flat(self, mask, rp, i, outline=True, edge=None):
        if outline:
            self.ring(mask, rp[0])
        self.paint(mask, rp[i])

    # ---- результат

    def sprite(self, shadow=True, shadow_col=(14, 8, 4), shadow_a=105):
        s = Sprite()
        a = np.zeros((G, G, 4), dtype=np.uint8)
        a[..., :3] = self.rgb
        a[..., 3] = np.where(self.solid, 255, 0)
        if shadow:
            sh = (shifted(self.solid, 1, 1) | shifted(self.solid, 0, 1)) & ~self.solid
            a[sh, 0], a[sh, 1], a[sh, 2], a[sh, 3] = shadow_col[0], shadow_col[1], shadow_col[2], shadow_a
        s.img = Image.fromarray(a, "RGBA")
        return s



# ══ материалы ═══════════════════════════════════════════════════════════════

R_SILVER = ramp(262, 5, [46, 66, 79, 90, 95, 98, 100, 100], dh_dark=-10, dh_light=10, spec=(255, 255, 255))
R_ALU = ramp(268, 18, [41, 57, 67, 75, 81, 86, 90, 95], dh_dark=-6, dh_light=0)
R_PLAT = ramp(332, 42, [52, 66, 76, 84, 90, 94, 97, 100], dh_dark=-14, dh_light=6, spec=(255, 255, 255))
R_MERC = ramp(208, 28, [14, 27, 38, 48, 56, 66, 82, 100], dh_dark=-10, dh_light=6, spec=(255, 255, 255))
R_LEAD = ramp(285, 20, [18, 29, 38, 45, 52, 59, 66, 76], dh_dark=-4, dh_light=0)
R_TITAN = ramp(288, 62, [20, 31, 42, 51, 59, 69, 80, 92], dh_dark=-14, dh_light=40)
R_NICK = ramp(126, 34, [24, 38, 49, 57, 64, 72, 82, 93], dh_dark=-6, dh_light=14)


def _chrome(cx, cy):
    """Полосы отражения: светлая над серединой куска, тёмная под ней (диагональ x+y)."""
    return ((cx + cy - 4.5, 1.6, 0.30), (cx + cy + 3.0, 2.0, -0.55))


def _speck(p, mask, rp, seed, n, tone):
    rng = np.random.default_rng(seed)
    ys, xs = np.nonzero(erode(mask))
    if len(ys) == 0:
        return
    for k in rng.choice(len(ys), min(n, len(ys)), replace=False):
        p.px(xs[k], ys[k], rp[tone] if isinstance(tone, int) else tone)


def _crack(p, mask, x, y, steps, color, seed, dx=1, dy=1):
    rng = np.random.default_rng(seed)
    inner = erode(mask)
    for _ in range(steps):
        if 0 <= int(x) < G and 0 <= int(y) < G and inner[int(y), int(x)]:
            p.rgb[int(y), int(x)] = color
        r = rng.random()
        if r < 0.45:
            x += dx
        elif r < 0.8:
            y += dy
        else:
            x += dx
            y += dy


def _plate(p, cx, cy, r, rot, rp, thick=2, squash=0.62, crease=None):
    """Плоская шестигранная пластина-чешуйка: верх с градиентом света, снизу ребро толщиной thick."""
    face = poly(hexagon(cx, cy, r, squash, rot))
    side = np.zeros_like(face)
    for k in range(1, thick + 1):
        side |= shifted(face, 0, k)
    side &= ~face
    both = face | side
    p.ring(both, rp[0])
    p.paint(side, rp[2])
    low = side & ~shifted(side, 0, 1)
    p.paint(low, rp[1])
    val = ((_XX + 0.5 - cx) * -0.5 + (_YY + 0.5 - cy) * -0.7) / r
    idx = np.clip(np.floor(4.4 + val * 2.2 + _BAYER * 0.5), 2, 6).astype(int)
    arr = np.array(rp, dtype=np.uint8)[idx]
    p.paint_arr(face, arr)
    top = face & ~shifted(face, 0, 1)
    left = face & ~shifted(face, 1, 0)
    bot = face & ~shifted(face, 0, -1)
    right = face & ~shifted(face, -1, 0)
    p.paint(top | left, rp[6])
    p.paint((bot | right) & ~(top | left), rp[3])
    if crease:
        (x0, y0), (x1, y1) = crease
        m = line_mask((int(x0), int(y0)), (int(x1), int(y1))) & erode(face)
        p.paint(m, rp[3])
        p.paint(shifted(m, 0, 1) & erode(face) & ~m, rp[6])
    return face


def _shard(p, cx, cy, length, width, rot, rp, skew=0.34):
    """Острый ромб-осколок из четырёх граней: свет с верхней левой."""
    T = (0, -length / 2)
    R = (width / 2, -length / 2 + skew * length)
    B = (0, length / 2)
    Lf = (-width / 2, -length / 2 + skew * length)
    C = (0, -length / 2 + skew * length)

    def tf(q):
        return rot_pts([(cx + q[0], cy + q[1])], cx, cy, rot)[0]
    t, r, b, l, c = (tf(q) for q in (T, R, B, Lf, C))
    mask = poly([t, r, b, l])
    p.ring(mask, rp[0])
    p.paint(mask, rp[4])
    p.paint(poly([t, l, c]), rp[6])
    p.paint(poly([t, r, c]), rp[5])
    p.paint(poly([l, c, b]), rp[4])
    p.paint(poly([r, c, b]), rp[2])
    # ребро-блик по верхнему левому краю и по центральной оси
    p.line(t, l, rp[7], clip=mask)
    p.line(l, b, rp[6], clip=mask)
    p.line(t, c, rp[5], clip=mask)
    p.px(int(round((t[0] + l[0]) / 2 + 0.4)), int(round((t[1] + l[1]) / 2 + 0.4)), rp[7])
    return mask


def silver_tile():
    p = Pic()
    k = dict(lo=-2.0, hi=1.3)
    p.dome(blob(20.5, 8.8, 3.5, 2.9, 0.3, 0.14, 11), R_SILVER, streaks=_chrome(20.5, 8.8), **k)
    p.dome(blob(13.0, 17.5, 6.8, 5.6, -0.35, 0.15, 12), R_SILVER, streaks=_chrome(13, 17.5), **k)
    p.dome(blob(22.8, 21.0, 4.4, 3.7, 0.2, 0.14, 13), R_SILVER, streaks=_chrome(22.8, 21), **k)
    p.dome(blob(7.5, 8.5, 2.2, 1.9, 0.0, 0.12, 14), R_SILVER, **k)
    p.sparkle(25, 12, 3, (255, 255, 255), (232, 240, 255))
    p.sparkle(5, 23, 2, (255, 255, 255), (232, 240, 255))
    p.sparkle(12, 13, 2, (255, 255, 255), (255, 255, 255))
    return p.sprite()


def aluminium_tile():
    p = Pic()
    _plate(p, 21.5, 12.5, 6.0, 0.22, R_ALU, 2, crease=((18, 13), (25, 10)))
    _plate(p, 12.0, 18.5, 7.6, -0.14, R_ALU, 2, crease=((7, 20), (16, 16)))
    _plate(p, 22.0, 23.0, 5.0, 0.38, R_ALU, 2)
    _plate(p, 8.5, 8.8, 3.8, -0.4, R_ALU, 2)
    return p.sprite()


def platinum_tile():
    p = Pic()
    _shard(p, 20.5, 19.5, 11, 6, 0.62, R_PLAT)
    _shard(p, 14, 14.5, 20, 9.5, -0.34, R_PLAT)
    _shard(p, 7.5, 24, 8, 4.6, -0.95, R_PLAT)
    p.sparkle(23, 7, 2, (255, 255, 255), (240, 225, 255))
    return p.sprite()


def _bead(p, cx, cy, r, rp):
    if r <= 1.3:
        p.px(cx - 0.5, cy - 0.5, rp[5])
        p.px(cx + 0.5, cy + 0.5, rp[3])
        p.px(cx - 0.5, cy + 0.5, rp[4])
        p.px(cx + 0.5, cy - 0.5, rp[4])
        p.px(cx - 0.5, cy - 0.5, rp[7])
        return
    p.dome(disc(cx, cy, r), rp, bounce=0.55, lo=-0.7, hi=1.1, spec_k=10, spec_thr=0.9)


def mercury_tile():
    p = Pic()
    puddle = blob(14.0, 23.0, 9.2, 3.9, 0.08, 0.09, 21)
    p.dome(puddle, R_MERC, relief=0.55, bounce=0.5, spec=False)
    _bead(p, 11.5, 14.0, 4.9, R_MERC)
    _bead(p, 20.5, 16.5, 3.5, R_MERC)
    _bead(p, 25.5, 22.5, 2.0, R_MERC)
    _bead(p, 17.0, 9.5, 2.0, R_MERC)
    for (x, y, r) in ((6.0, 7.5, 1.0), (8.5, 9.5, 1.0), (4.0, 5.0, 1.0)):
        _bead(p, x, y, 1.0, R_MERC)
    p.px(13, 22, R_MERC[7])
    p.px(14, 22, R_MERC[6])
    p.px(8, 23, R_MERC[6])
    return p.sprite()


def lead_tile():
    p = Pic()
    a = blob(11.5, 17.5, 8.4, 7.0, -0.2, 0.10, 31, p=2.4)
    b = blob(22.0, 20.0, 6.6, 5.6, 0.25, 0.10, 32, p=2.4)
    c = blob(22.5, 8.5, 3.0, 2.6, 0.0, 0.10, 33)
    p.dome(c, R_LEAD, spec=False, hi=1.3, tex=(vnoise(5, 3.0) - 0.5) * 0.35)
    p.dome(a, R_LEAD, spec=False, hi=1.3, tex=(vnoise(6, 3.0) - 0.5) * 0.35)
    p.dome(b, R_LEAD, spec=False, hi=1.3, tex=(vnoise(7, 3.0) - 0.5) * 0.35)
    _crack(p, a, 8, 13, 9, R_LEAD[1], 3)
    _crack(p, b, 20, 17, 7, R_LEAD[1], 4)
    return p.sprite()


def _prism(p, cx, ty, r, h, rp):
    sq = 0.55
    a = r * 0.866 * sq
    topm = poly(hexagon(cx, ty, r, sq))
    lf = poly([(cx - r, ty), (cx - r / 2, ty + a), (cx - r / 2, ty + a + h), (cx - r, ty + h)])
    fr = poly([(cx - r / 2, ty + a), (cx + r / 2, ty + a), (cx + r / 2, ty + a + h), (cx - r / 2, ty + a + h)])
    rt = poly([(cx + r / 2, ty + a), (cx + r, ty), (cx + r, ty + h), (cx + r / 2, ty + a + h)])
    body = lf | fr | rt | topm
    p.ring(body, rp[0])
    for m, base in ((lf, 4), (fr, 3), (rt, 2)):
        ys, xs = np.nonzero(m)
        y0, y1 = ys.min(), ys.max()
        for y, x in zip(ys, xs):
            f = (y - y0) / max(1, y1 - y0)
            idx = int(np.clip(np.floor(base + 0.9 - f * 1.6 + _BAYER[y, x] * 0.6), 1, 6))
            p.px(x, y, rp[idx])
    # вертикальные рёбра — блик
    p.line((cx - r / 2, ty + a + 1), (cx - r / 2, ty + a + h - 1), rp[6], clip=body & ~topm)
    p.line((cx + r / 2, ty + a + 1), (cx + r / 2, ty + a + h - 1), rp[3], clip=body & ~topm)
    # верхняя грань: светлая, кромка анодирована в золото
    val = ((_XX + 0.5 - cx) * -0.5 + (_YY + 0.5 - ty) * -0.8) / r
    idx = np.clip(np.floor(5.2 + val * 1.5 + _BAYER * 0.5), 4, 7).astype(int)
    p.paint_arr(topm, np.array(rp, dtype=np.uint8)[idx])
    rim = topm & ~erode(topm)
    low = rim & (_YY + 0.5 > ty + 0.3)
    gold = lch(74, 55, 78)
    gold_d = lch(60, 50, 68)
    p.paint(low & (_XX + 0.5 < cx), gold)
    p.paint(low & (_XX + 0.5 >= cx), gold_d)
    p.paint(rim & ~low, rp[7])


def titanium_tile():
    p = Pic()
    _prism(p, 22.0, 13.5, 4.6, 7.5, R_TITAN)
    _prism(p, 9.0, 17.0, 4.0, 6.5, R_TITAN)
    _prism(p, 15.5, 8.0, 6.0, 10.5, R_TITAN)
    return p.sprite()


def nickel_tile():
    p = Pic()
    peb = [(8.5, 9.5, 3.7, 3.3), (19.0, 8.2, 3.1, 2.8), (14.5, 18.0, 5.4, 4.8), (25.0, 18.5, 3.9, 3.5), (7.0, 24.0, 3.3, 2.9)]
    for i, (x, y, rx, ry) in enumerate(peb):
        m = blob(x, y, rx, ry, 0.3 * i, 0.06, 40 + i, p=2.1)
        p.dome(m, R_NICK, spec_k=18, spec_thr=0.9)
        _speck(p, m, R_NICK, 50 + i, 3 + int(rx), 2)
        _speck(p, m, R_NICK, 60 + i, 2 + int(rx / 2), 6)
    return p.sprite()


R_IRON = ramp(48, 46, [16, 25, 35, 44, 52, 59, 67, 77], dh_dark=-16, dh_light=16)
R_COPPER = ramp(55, 84, [22, 33, 44, 54, 62, 70, 80, 92], dh_dark=-24, dh_light=12)
R_PATINA = ramp(172, 30, [20, 34, 46, 56, 64, 72, 82, 92], dh_dark=-10, dh_light=14)
R_GOLD = ramp(90, 98, [32, 46, 58, 67, 74, 81, 88, 95], dh_dark=-34, dh_light=4, c_dark=0.75, c_light=0.95)
R_SCRAP = ramp(92, 8, [18, 30, 40, 48, 55, 62, 70, 80], dh_dark=-6, dh_light=6)
R_RUST = ramp(52, 42, [14, 24, 33, 41, 48, 55, 63, 72], dh_dark=-14, dh_light=14)
R_PEAT = ramp(66, 58, [10, 19, 30, 41, 51, 59, 68, 80], dh_dark=-10, dh_light=14, c_dark=0.95, c_light=0.75)
R_FIBER = ramp(70, 34, [16, 28, 40, 50, 58, 66, 74, 84], dh_dark=-8, dh_light=10)
R_MOSS = ramp(124, 80, [10, 18, 28, 37, 46, 55, 66, 78], dh_dark=-6, dh_light=20, c_dark=0.9, c_light=0.85)
R_COAL = [lch(1.5, 4, 105), lch(2.5, 5, 108), lch(4, 8, 118), lch(6.5, 8, 118), lch(9, 5, 255), lch(20, 6, 250),
          lch(46, 8, 245), lch(74, 8, 240)]
R_URAN = ramp(126, 92, [26, 44, 58, 69, 79, 87, 94, 99], dh_dark=22, dh_light=-8, c_dark=0.9, c_light=0.8)
R_LITH = ramp(352, 62, [32, 46, 58, 67, 74, 81, 88, 95], dh_dark=-34, dh_light=6)


def _vein(p, p0, p1, thick, rp, seed, cutl=0.7, cutr=0.7, wob=0.9, seams=(-0.9,)):
    """Диагональная жила-пласт: ширина гуляет, концы срезаны косо, поперёк — свет сверху-слева и тёмные швы слоёв."""
    x = _XX + 0.5 - p0[0]
    y = _YY + 0.5 - p0[1]
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ln = math.hypot(dx, dy)
    ux, uy = dx / ln, dy / ln
    nx, ny = uy, -ux
    if nx + ny > 0:
        nx, ny = -nx, -ny
    t = x * ux + y * uy
    sc = x * nx + y * ny
    rng = np.random.default_rng(seed)
    ph = rng.uniform(0, math.tau, 3)
    half = thick / 2 + wob * (0.5 * np.sin(t * 0.55 + ph[0]) + 0.3 * np.sin(t * 1.3 + ph[1]))
    sc = sc - 0.5 * np.sin(t * 0.3 + ph[2])
    mask = (np.abs(sc) <= half) & (t >= -cutl * sc) & (t <= ln - cutr * sc)
    v = np.clip(sc / np.maximum(half, 0.5), -1, 1)
    idx = np.clip(np.floor(4.2 + v * 2.4 + _BAYER * 0.55), 1, 6).astype(int)
    arr = np.array(rp, dtype=np.uint8)[idx]
    brk = vnoise(seed + 3, 2.5) > 0.3
    for off in seams:
        seam = mask & (np.abs(sc - off) < 0.55) & (t > 1.5) & (t < ln - 1.5) & brk
        arr[seam] = rp[1]
        arr[mask & (np.abs(sc - off - 1.0) < 0.5) & (t > 1.5) & (t < ln - 1.5) & brk & ~seam] = rp[6]
    p.ring(mask, rp[0])
    p.paint_arr(mask, arr)
    return mask, v


def iron_tile():
    p = Pic()
    glint = lch(72, 7, 250)
    glint2 = lch(58, 8, 252)
    veins = [((4.5, 16.0), (13.5, 6.5), 4.6, 71), ((8.5, 25.0), (25.0, 8.5), 5.8, 72), ((17.5, 27.5), (28.0, 17.5), 4.2, 73)]
    masks = []
    for p0, p1, th, sd in veins:
        m, v = _vein(p, p0, p1, th, R_IRON, sd)
        masks.append((m, v, sd))
    rng = np.random.default_rng(5)
    for m, v, sd in masks:
        inner = erode(m)
        top = inner & (v > 0.6)
        ys, xs = np.nonzero(top)
        if len(ys) > 4:
            # серо-голубые металлические блики: короткие чёрточки вдоль светлой кромки
            for k in rng.choice(len(ys), min(5, len(ys)), replace=False):
                p.px(xs[k], ys[k], glint)
                if rng.random() < 0.6:
                    p.px(xs[k] + 1, ys[k] - 1, glint2)
        ys, xs = np.nonzero(inner & (v < 0.5))
        for k in rng.choice(len(ys), min(10, len(ys)), replace=False):
            c = R_RUST[6] if rng.random() < 0.5 else R_IRON[1]
            p.px(xs[k], ys[k], c)
    # крапины ржавчины на грунте
    for (x, y) in ((24, 5), (4, 8), (27, 27), (3, 27), (12, 22), (29, 12)):
        if not p.solid[y, x]:
            p.px(x, y, R_RUST[5])
    return p.sprite()


def _nugget(p, cx, cy, rx, ry, rot, rp, seed, lump=0.2, harm=5, pw=2.2, patina=None, **kw):
    m = blob(cx, cy, rx, ry, rot, lump, seed, harm, pw)
    alt = None
    if patina is not None:
        n = vnoise(seed + 100, 2.6)
        pm = erode(m) & (n > patina) & ((_XX + _YY) > (cx + cy - 2.5))
        alt = (pm, R_PATINA)
    p.dome(m, rp, alt=alt, **kw)
    return m


def copper_tile():
    p = Pic()
    k = dict(lo=-1.0, hi=1.2, spec_k=18)
    tx = lambda s: (vnoise(s, 2.2) - 0.5) * 0.35
    _nugget(p, 21.5, 9.0, 4.2, 3.4, 0.4, R_COPPER, 81, 0.24, patina=0.5, tex=tx(1), **k)
    _nugget(p, 12.5, 17.5, 7.0, 5.8, -0.4, R_COPPER, 82, 0.22, patina=0.46, tex=tx(2), **k)
    _nugget(p, 23.5, 21.5, 4.8, 4.0, 0.3, R_COPPER, 83, 0.22, patina=0.5, tex=tx(3), **k)
    _nugget(p, 8.0, 7.5, 2.6, 2.2, 0.0, R_COPPER, 84, 0.2, tex=tx(4), **k)
    _nugget(p, 7.5, 26.0, 2.7, 2.0, 0.5, R_COPPER, 85, 0.2, patina=0.5, tex=tx(5), **k)
    return p.sprite()


def gold_tile():
    p = Pic()
    k = dict(lo=-1.1, hi=1.2, spec_k=20, spec_thr=0.9)
    _nugget(p, 21.0, 9.5, 4.0, 3.5, 0.2, R_GOLD, 91, 0.10, harm=3, **k)
    _nugget(p, 12.5, 17.0, 6.6, 5.4, -0.3, R_GOLD, 92, 0.10, harm=3, **k)
    _nugget(p, 23.0, 21.5, 4.6, 3.9, 0.3, R_GOLD, 93, 0.10, harm=3, **k)
    _nugget(p, 7.5, 7.5, 2.5, 2.1, 0.0, R_GOLD, 94, 0.08, harm=3, **k)
    _nugget(p, 5.5, 25.0, 2.3, 1.9, 0.0, R_GOLD, 95, 0.08, harm=3, **k)
    wh = (255, 252, 214)
    p.sparkle(26, 6, 3, wh, lch(90, 60, 90))
    p.sparkle(4, 16, 2, wh, lch(90, 60, 90))
    p.sparkle(14, 12, 2, wh, wh)
    p.sparkle(27, 27, 1, wh, lch(92, 50, 92))
    return p.sprite()


def _gear(cx, cy, r_in, r_out, teeth, hole, rot=0.0):
    m = disc(cx, cy, r_in)
    for k in range(teeth):
        a = rot + k * math.tau / teeth
        c, s = math.cos(a), math.sin(a)
        hw = 1.15
        pts = [(cx + c * (r_in - 1) - s * hw, cy + s * (r_in - 1) + c * hw), (cx + c * r_out - s * hw, cy + s * r_out + c * hw),
               (cx + c * r_out + s * hw, cy + s * r_out - c * hw), (cx + c * (r_in - 1) + s * hw, cy + s * (r_in - 1) - c * hw)]
        m |= poly(pts)
    return m & ~disc(cx, cy, hole)


def scrap_tile():
    p = Pic()
    rust = vnoise(61, 3.0)
    # гнутая пластина (снизу справа): две грани со сгибом, две заклёпки
    top = poly([(15, 22), (23, 19), (30, 21), (29, 25), (16, 26)])
    low = poly([(16, 26), (29, 25), (28, 29), (17, 30)])
    p.ring(top | low, R_SCRAP[0])
    p.dome(low, R_SCRAP, outline=False, relief=0.3, R=4, spec=False, lo=-1.6, hi=0.6, alt=(erode(low) & (rust > 0.6), R_RUST))
    p.dome(top, R_SCRAP, outline=False, relief=0.35, R=5, spec=False, alt=(erode(top) & (rust > 0.56), R_RUST))
    p.line((16, 26), (29, 25), R_SCRAP[6], clip=top | low)
    for (x, y) in ((19, 23), (26, 23)):
        p.px(x, y, R_SCRAP[0])
        p.px(x + 1, y, R_SCRAP[1])
        p.px(x, y - 1, R_SCRAP[7])
    # шестерня (сверху слева)
    g = _gear(11.0, 11.5, 5.2, 7.6, 8, 2.0, 0.2)
    p.dome(g, R_SCRAP, relief=0.7, R=4.5, spec=False, alt=(erode(g) & (rust > 0.6), R_RUST))
    # болт (сверху справа): шестигранная головка и резьба
    shaft = poly([(25, 9), (27, 8), (31, 15), (29, 16)])
    p.dome(shaft, R_SCRAP, relief=0.5, spec=False)
    for k in range(3):
        p.px(27 + k, 11 + k * 2, R_SCRAP[1])
    head = poly(hexagon(24.0, 7.0, 3.6, 0.95, 0.3))
    p.dome(head, R_SCRAP, relief=0.8, spec=False)
    p.px(23, 6, R_SCRAP[7])
    # моток проволоки (снизу слева): два перекрывающихся витка
    for (cx, cy) in ((6.0, 22.5), (9.0, 25.0)):
        ring = disc(cx, cy, 4.2) & ~disc(cx, cy, 2.3)
        p.dome(ring, R_SCRAP, relief=1.0, R=1.5, spec_k=10, spec_thr=0.85, alt=(erode(ring) & (rust > 0.52), R_RUST))
    return p.sprite()


def _fibers(p, mask, n, seed, rp, length=7, out=False):
    rng = np.random.default_rng(seed)
    if out:
        ring = dilate(mask) & ~mask
        ys, xs = np.nonzero(ring)
        cy, cx = np.mean(np.nonzero(mask), axis=1)
        for k in rng.choice(len(ys), min(n, len(ys)), replace=False):
            x, y = float(xs[k]), float(ys[k])
            ang = math.atan2(y - cy, x - cx) + rng.uniform(-0.5, 0.5)
            for i in range(int(rng.integers(2, 4))):
                p.px(x, y, rp[int(rng.integers(4, 7))])
                x += math.cos(ang)
                y += math.sin(ang)
        return
    ys, xs = np.nonzero(erode(mask))
    for k in rng.choice(len(ys), min(n, len(ys)), replace=False):
        x, y = float(xs[k]), float(ys[k])
        ang = rng.uniform(-0.7, 0.7) + (math.pi if rng.random() < 0.5 else 0.0)
        for i in range(int(rng.integers(4, length))):
            if 0 <= int(x) < G and 0 <= int(y) < G and mask[int(y), int(x)]:
                p.rgb[int(y), int(x)] = rp[int(rng.integers(5, 7))]
            ang += rng.uniform(-0.45, 0.45)
            x += math.cos(ang)
            y += math.sin(ang)


def peat_tile():
    """Торф: комья спрессованных волокон: светлые и тёмные нити, пятна мха, торчащие корешки."""
    p = Pic()
    for cx, cy, rx, ry, rot, sd in ((19.5, 8.5, 4.8, 3.8, 0.3, 111), (11.0, 16.0, 7.8, 6.4, -0.25, 112),
                                    (23.0, 21.5, 5.8, 4.8, 0.2, 113), (6.5, 26.5, 3.6, 2.8, 0.0, 114)):
        _peat_clod(p, cx, cy, rx, ry, rot, sd)
    return p.sprite()


def _rim_poly(p, pts, rp, rim, center=None, base=2.2, gain=3.0, lo=1, hi=5):
    """Угловатая глыба: грани-треугольники от центра, тон по нормали грани; контур — с ободком света."""
    mask = poly(pts)
    cx, cy = center if center else (sum(q[0] for q in pts) / len(pts), sum(q[1] for q in pts) / len(pts))
    p.rim_ring(mask, rp[0], rim)
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        ex, ey = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(ex, ey)
        nx, ny = ey / ln, -ex / ln
        mx, my = (a[0] + b[0]) / 2 - cx, (a[1] + b[1]) / 2 - cy
        if nx * mx + ny * my < 0:
            nx, ny = -nx, -ny
        lit = nx * _LIGHT[0] + ny * _LIGHT[1]
        idx = int(np.clip(round(base + lit * gain), lo, hi))
        tri = poly([(cx, cy), a, b]) & mask
        p.paint(tri, rp[idx])
    return mask


def _coal_glints(p, masks):
    """Холодные блики граней: короткие чёрточки по освещённым рёбрам и искра у верхней вершины."""
    for m, pts in masks:
        n = len(pts)
        inner = erode(m)
        for i in range(n):
            a, b = pts[i], pts[(i + 1) % n]
            ex, ey = b[0] - a[0], b[1] - a[1]
            if ex * -0.6 + ey * -0.4 > 0 and i % 3 == 0:
                ln = math.hypot(ex, ey)
                p.line((a[0] + 1, a[1] + 1), (a[0] + 1 + ex / ln * 3, a[1] + 1 + ey / ln * 3), R_COAL[5], clip=inner)
        a = pts[1]
        p.px_in(inner, a[0] + 1, a[1] + 1, R_COAL[7])


def coal_tile():
    p = Pic()
    rim = R_COAL[6]
    chunks = [
        ([(5, 17), (8, 11), (14, 8), (19, 11), (20, 18), (15, 22), (8, 22)], (13, 15.5)),
        ([(20, 21), (23, 17), (28, 18), (29, 24), (25, 28), (20, 27)], (24.5, 22.5)),
        ([(21, 6), (25, 4), (28, 8), (25, 11), (22, 10)], (24.5, 7.5)),
        ([(4, 25), (7, 23), (10, 26), (8, 29), (5, 28)], (7, 26)),
    ]
    masks = []
    for pts, c in chunks[::-1]:
        masks.append((_rim_poly(p, pts, R_COAL, rim, c, base=1.05, gain=2.0, lo=1, hi=4), pts))
    # блики граней: сине-белые чёрточки по освещённым рёбрам и искры в вершинах
    _coal_glints(p, masks)
    for (x, y) in ((3, 12), (2, 21), (14, 27), (28, 13), (17, 3), (30, 29), (12, 5)):
        if not p.solid[y, x]:
            p.px(x, y, R_COAL[4] if (x + y) % 2 else R_COAL[2])
    return p.sprite()


def _hexcrystal(p, cx, by, w, h, tip, ang, rp, lean=0.05):
    hw = w / 2.0
    ca, sa = math.cos(ang), math.sin(ang)

    def P(x, y):
        return (cx + x * ca + y * sa, by - y * ca + x * sa)
    xs = [-hw, -0.3 * hw, 0.45 * hw, hw]
    ap = (lean * w, h + tip)
    body = poly([P(-hw, 0), P(-hw, h), P(hw, h), P(hw, 0)])
    tipm = poly([P(-hw, h), P(*ap), P(hw, h)])
    whole = body | tipm
    p.ring(whole, rp[0])
    faces = [(poly([P(xs[0], 0), P(xs[0], h), P(xs[1], h), P(xs[1], 0)]), 5, poly([P(xs[0], h), P(*ap), P(xs[1], h)]), 6),
             (poly([P(xs[1], 0), P(xs[1], h), P(xs[2], h), P(xs[2], 0)]), 6, poly([P(xs[1], h), P(*ap), P(xs[2], h)]), 7),
             (poly([P(xs[2], 0), P(xs[2], h), P(xs[3], h), P(xs[3], 0)]), 3, poly([P(xs[2], h), P(*ap), P(xs[3], h)]), 4)]
    for bm, bt, tm, tt in faces:
        ys, xs_ = np.nonzero(bm)
        y0, y1 = ys.min(), ys.max()
        for y, x in zip(ys, xs_):
            f = (y - y0) / max(1, y1 - y0)
            idx = int(np.clip(np.floor(bt + 0.6 - f * 1.4 + _BAYER[y, x] * 0.5), 1, 7))
            p.px(x, y, rp[idx])
        p.paint(tm & ~bm & whole, rp[tt])
    return whole


def uranium_tile():
    p = Pic()
    rock = blob(15.5, 25.5, 9.5, 3.8, 0.0, 0.16, 121, 4, 2.4)
    p.dome(rock, ramp(95, 14, [8, 14, 20, 27, 33, 40, 48, 56]), spec=False, relief=0.6)
    _hexcrystal(p, 21.0, 26, 6.0, 8, 5.5, 0.28, R_URAN)
    _hexcrystal(p, 9.5, 26, 5.5, 7, 5.0, -0.34, R_URAN)
    _hexcrystal(p, 15.5, 27, 7.5, 12, 7.0, 0.04, R_URAN)
    wh = (250, 255, 220)
    p.sparkle(26, 9, 2, wh, R_URAN[6])
    p.sparkle(5, 12, 1, wh, R_URAN[6])
    s = p.sprite(shadow=False)
    s.glow(R_URAN[4], 2.6, 0.46)
    return s


def _cube(p, cx, cy, w, h, rp, rot=0.0):
    T_ = (cx, cy)
    R_ = (cx + w, cy + w / 2)
    B_ = (cx, cy + w)
    L_ = (cx - w, cy + w / 2)

    def d(q, dy):
        return (q[0], q[1] + dy)

    def pts(a):
        return rot_pts(a, cx, cy + w / 2 + h / 2, rot)
    top = poly(pts([T_, R_, B_, L_]))
    lf = poly(pts([L_, B_, d(B_, h), d(L_, h)]))
    rt = poly(pts([B_, R_, d(R_, h), d(B_, h)]))
    whole = top | lf | rt
    p.ring(whole, rp[0])
    for m, base in ((lf, 4), (rt, 2)):
        ys, xs = np.nonzero(m)
        y0, y1 = ys.min(), ys.max()
        for y, x in zip(ys, xs):
            f = (y - y0) / max(1, y1 - y0)
            idx = int(np.clip(np.floor(base + 0.9 - f * 1.2 + _BAYER[y, x] * 0.55), 1, 6))
            p.px(x, y, rp[idx])
    p.paint(top, rp[6])
    ys, xs = np.nonzero(top)
    for y, x in zip(ys, xs):
        if (x + y) % 2 == 0 and x < cx:
            p.px(x, y, rp[7])
    p.paint(top & ~erode(top) & (_YY + 0.5 < cy + w / 2), rp[7])
    return whole


def lithium_tile():
    p = Pic()
    _cube(p, 20.5, 5.5, 3.4, 3.6, R_LITH, 0.12)
    _cube(p, 9.5, 8.5, 3.2, 3.4, R_LITH, -0.15)
    _cube(p, 14.5, 12.0, 5.4, 5.6, R_LITH, 0.05)
    _cube(p, 23.5, 16.5, 4.2, 4.4, R_LITH, -0.1)
    _cube(p, 7.5, 20.5, 3.6, 3.8, R_LITH, 0.2)
    _cube(p, 15.5, 21.5, 3.2, 3.4, R_LITH, -0.05)
    return p.sprite()


R_PEATFIB = ramp(62, 24, [8, 14, 20, 26, 32, 38, 44, 52], dh_dark=-6, dh_light=8)


def _strands(p, mask, n, seed, color, length=8, ang0=-0.3, spread=0.55, curl=0.35):
    """Волокна: плавно изгибающиеся чёрточки вдоль «зерна», только внутри куска."""
    rng = np.random.default_rng(seed)
    ys, xs = np.nonzero(erode(mask))
    if len(ys) == 0:
        return
    for k in rng.choice(len(ys), min(n, len(ys)), replace=False):
        x, y = float(xs[k]), float(ys[k])
        ang = ang0 + rng.uniform(-spread, spread) + (math.pi if rng.random() < 0.5 else 0.0)
        for _ in range(int(rng.integers(length - 2, length + 3))):
            xi, yi = int(x), int(y)
            if 0 <= xi < G and 0 <= yi < G and mask[yi, xi]:
                p.rgb[yi, xi] = color
            ang += rng.uniform(-curl, curl)
            x += math.cos(ang)
            y += math.sin(ang)


R_BRONZE = ramp(66, 46, [14, 24, 34, 43, 51, 59, 69, 82], dh_dark=-12, dh_light=14)


R_BRICK = ramp(58, 44, [8, 16, 25, 33, 41, 49, 59, 72], dh_dark=-10, dh_light=14)


def iron_icon():
    """Значок железа — те же слоистые жилы, что на тайле, только крупнее."""
    p = Pic()
    glint = lch(72, 7, 250)
    glint2 = lch(58, 8, 252)
    rng = np.random.default_rng(15)
    for p0, p1, th, sd in (((2.5, 21.0), (15.5, 6.5), 6.4, 71), ((6.5, 29.0), (28.5, 8.0), 7.6, 72), ((18.0, 30.0), (30.0, 17.0), 5.2, 73)):
        m, v = _vein(p, p0, p1, th, R_IRON, sd)
        inner = erode(m)
        ys, xs = np.nonzero(inner & (v > 0.6))
        for k in rng.choice(len(ys), min(6, len(ys)), replace=False):
            p.px(xs[k], ys[k], glint)
            p.px(xs[k] + 1, ys[k] - 1, glint2)
        ys, xs = np.nonzero(inner & (v < 0.5))
        for k in rng.choice(len(ys), min(12, len(ys)), replace=False):
            p.px(xs[k], ys[k], R_RUST[6] if rng.random() < 0.5 else R_IRON[1])
    return p.sprite(shadow=False)


def lead_icon():
    p = Pic()
    tx = lambda s: (vnoise(s, 3.0) - 0.5) * 0.35
    a = blob(14.0, 17.5, 11.0, 9.2, -0.15, 0.08, 211, p=2.4)
    b = blob(24.5, 23.5, 6.2, 5.2, 0.25, 0.09, 212, p=2.4)
    p.dome(a, R_LEAD, spec=False, hi=1.3, tex=tx(5))
    p.dome(b, R_LEAD, spec=False, hi=1.3, tex=tx(6))
    _crack(p, a, 9, 12, 10, R_LEAD[1], 3)
    return p.sprite(shadow=False)


def silver_icon():
    p = Pic()
    k = dict(lo=-2.0, hi=1.3)
    p.dome(blob(22.5, 10.5, 4.6, 3.8, 0.3, 0.12, 221), R_SILVER, streaks=_chrome(22.5, 10.5), **k)
    p.dome(blob(14.0, 18.5, 10.0, 8.2, -0.3, 0.12, 222), R_SILVER, streaks=_chrome(14, 18.5), **k)
    p.dome(blob(25.5, 24.5, 5.0, 4.0, 0.2, 0.12, 223), R_SILVER, streaks=_chrome(25.5, 24.5), **k)
    p.sparkle(27, 5, 3, (255, 255, 255), (232, 240, 255))
    p.sparkle(5, 8, 2, (255, 255, 255), (232, 240, 255))
    p.sparkle(11, 14, 2, (255, 255, 255), (255, 255, 255))
    return p.sprite(shadow=False)


def copper_icon():
    p = Pic()
    k = dict(lo=-1.0, hi=1.2, spec_k=18)
    tx = lambda s: (vnoise(s, 2.2) - 0.5) * 0.35
    _nugget(p, 22.0, 9.5, 5.0, 4.0, 0.4, R_COPPER, 231, 0.22, patina=0.5, tex=tx(1), **k)
    _nugget(p, 13.5, 18.5, 10.0, 8.2, -0.4, R_COPPER, 232, 0.2, patina=0.45, tex=tx(2), **k)
    _nugget(p, 25.5, 24.5, 5.0, 4.0, 0.3, R_COPPER, 233, 0.2, patina=0.5, tex=tx(3), **k)
    return p.sprite(shadow=False)


def aluminium_icon():
    p = Pic()
    _plate(p, 20.5, 13.5, 8.0, 0.25, R_ALU, 3, squash=0.66, crease=((16, 14), (24, 10)))
    _plate(p, 13.0, 20.0, 10.5, -0.15, R_ALU, 3, squash=0.66, crease=((7, 22), (18, 17)))
    _plate(p, 21.5, 24.5, 6.0, 0.35, R_ALU, 2, squash=0.66)
    _plate(p, 9.5, 9.5, 4.8, -0.4, R_ALU, 2, squash=0.66)
    return p.sprite(shadow=False)


def nickel_icon():
    p = Pic()
    peb = [(10.0, 11.0, 5.2, 4.6), (22.0, 10.0, 4.4, 4.0), (16.0, 21.0, 7.2, 6.4), (26.0, 23.5, 3.6, 3.2)]
    for i, (x, y, rx, ry) in enumerate(peb):
        m = blob(x, y, rx, ry, 0.3 * i, 0.05, 240 + i, p=2.1)
        p.dome(m, R_NICK, spec_k=18, spec_thr=0.9)
        _speck(p, m, R_NICK, 250 + i, 4 + int(rx), 2)
        _speck(p, m, R_NICK, 260 + i, 3 + int(rx / 2), 6)
    return p.sprite(shadow=False)


def platinum_icon():
    p = Pic()
    _shard(p, 20.0, 19.0, 12, 7, 0.6, R_PLAT)
    _shard(p, 13.0, 15.0, 24, 12, -0.32, R_PLAT)
    p.sparkle(26, 6, 2, (255, 255, 255), (240, 225, 255))
    p.sparkle(5, 24, 1, (255, 255, 255), (240, 225, 255))
    return p.sprite(shadow=False)


def mercury_icon():
    p = Pic()
    puddle = blob(16.0, 25.5, 12.0, 3.8, 0.0, 0.08, 271)
    p.dome(puddle, R_MERC, relief=0.55, bounce=0.5, spec=False)
    _bead(p, 14.0, 14.5, 7.5, R_MERC)
    _bead(p, 24.5, 18.5, 4.2, R_MERC)
    _bead(p, 22.0, 9.0, 2.4, R_MERC)
    for (x, y) in ((6.0, 8.0), (4.0, 5.0)):
        _bead(p, x, y, 1.0, R_MERC)
    return p.sprite(shadow=False)


def gold_icon():
    p = Pic()
    k = dict(lo=-1.1, hi=1.2, spec_k=20, spec_thr=0.9)
    _nugget(p, 22.5, 10.5, 5.0, 4.4, 0.2, R_GOLD, 281, 0.08, harm=3, **k)
    _nugget(p, 14.0, 18.5, 10.0, 8.0, -0.3, R_GOLD, 282, 0.08, harm=3, **k)
    _nugget(p, 25.5, 24.5, 4.8, 3.8, 0.3, R_GOLD, 283, 0.08, harm=3, **k)
    wh = (255, 252, 214)
    p.sparkle(26, 5, 3, wh, lch(90, 60, 90))
    p.sparkle(5, 10, 2, wh, lch(90, 60, 90))
    p.sparkle(10, 14, 2, wh, wh)
    return p.sprite(shadow=False)


def scrap_icon():
    p = Pic()
    rust = vnoise(61, 3.0)
    top = poly([(13, 21), (22, 19), (30, 21), (29, 25), (14, 27)])
    low = poly([(14, 27), (29, 25), (28, 30), (15, 31)])
    p.ring(top | low, R_SCRAP[0])
    p.dome(low, R_SCRAP, outline=False, relief=0.3, R=4, spec=False, lo=-1.6, hi=0.6, alt=(erode(low) & (rust > 0.6), R_RUST))
    p.dome(top, R_SCRAP, outline=False, relief=0.35, R=5, spec=False, alt=(erode(top) & (rust > 0.56), R_RUST))
    p.line((14, 27), (29, 25), R_SCRAP[6], clip=top | low)
    for (x, y) in ((17, 24), (26, 23)):
        p.px(x, y, R_SCRAP[0])
        p.px(x + 1, y, R_SCRAP[1])
        p.px(x, y - 1, R_SCRAP[7])
    g = _gear(12.0, 12.0, 6.6, 9.6, 8, 2.4, 0.2)
    p.dome(g, R_SCRAP, relief=0.7, R=5.5, spec=False, alt=(erode(g) & (rust > 0.6), R_RUST))
    shaft = poly([(24, 7), (26, 6), (31, 12), (29, 14)])
    p.dome(shaft, R_SCRAP, relief=0.5, spec=False)
    for k in range(2):
        p.px(27 + k, 9 + k * 2, R_SCRAP[1])
    head = poly(hexagon(23.0, 5.5, 3.6, 0.95, 0.3))
    p.dome(head, R_SCRAP, relief=0.8, spec=False)
    p.px(22, 4, R_SCRAP[7])
    return p.sprite(shadow=False)


def peat_icon():
    p = Pic()
    for cx, cy, rx, ry, rot, sd in ((20.0, 9.5, 5.4, 4.2, 0.3, 291), (14.0, 18.5, 10.6, 8.2, -0.2, 292),
                                    (25.5, 24.0, 5.0, 4.0, 0.2, 293)):
        _peat_clod(p, cx, cy, rx, ry, rot, sd)
    return p.sprite(shadow=False)


def coal_icon():
    p = Pic()
    rim = lch(62, 10, 245)  # на тёмных плитках рюкзака ободок должен держать силуэт
    chunks = [
        ([(4, 20), (7, 12), (14, 8), (21, 11), (23, 19), (17, 25), (8, 25)], (14, 17.5)),
        ([(21, 22), (24, 17), (30, 19), (31, 26), (27, 30), (21, 29)], (26, 24)),
        ([(18, 5), (23, 2), (28, 6), (26, 11), (20, 10)], (23, 6.5)),
    ]
    masks = []
    for pts, c in chunks[::-1]:
        masks.append((_rim_poly(p, pts, R_COAL, rim, c, base=2.0, gain=3.0, lo=1, hi=5), pts))
    _coal_glints(p, masks)
    return p.sprite(shadow=False)


def uranium_icon():
    p = Pic()
    rock = blob(16.0, 27.0, 11.0, 3.4, 0.0, 0.16, 301, 4, 2.4)
    p.dome(rock, ramp(95, 14, [8, 14, 20, 27, 33, 40, 48, 56]), spec=False, relief=0.6)
    _hexcrystal(p, 23.5, 28, 7.0, 9, 6.0, 0.3, R_URAN)
    _hexcrystal(p, 9.0, 28, 6.5, 8, 5.5, -0.34, R_URAN)
    _hexcrystal(p, 16.0, 29, 9.0, 13, 8.0, 0.04, R_URAN)
    wh = (250, 255, 220)
    p.sparkle(27, 8, 2, wh, R_URAN[6])
    p.sparkle(5, 11, 1, wh, R_URAN[6])
    s = p.sprite(shadow=False)
    s.glow(R_URAN[4], 3.0, 0.5)
    return s


def lithium_icon():
    p = Pic()
    _cube(p, 21.5, 7.0, 4.4, 4.6, R_LITH, 0.12)
    _cube(p, 8.5, 12.5, 4.0, 4.2, R_LITH, -0.18)
    _cube(p, 15.5, 14.5, 7.0, 7.2, R_LITH, 0.05)
    _cube(p, 24.5, 20.0, 4.0, 4.2, R_LITH, -0.1)
    return p.sprite(shadow=False)


def titanium_icon():
    p = Pic()
    _prism(p, 23.5, 15.0, 5.4, 9.5, R_TITAN)
    _prism(p, 8.5, 17.5, 4.6, 8.0, R_TITAN)
    _prism(p, 16.0, 7.5, 7.0, 14.5, R_TITAN)
    return p.sprite(shadow=False)


def _ingot(p, x, y, w, h, d, rp):
    front = poly([(x, y + d), (x + w, y + d), (x + w, y + d + h), (x, y + d + h)])
    top = poly([(x, y + d), (x + d, y), (x + w + d, y), (x + w, y + d)])
    right = poly([(x + w, y + d), (x + w + d, y), (x + w + d, y + h), (x + w, y + d + h)])
    whole = front | top | right
    p.ring(whole, rp[0])
    p.paint(right, rp[2])
    ys, xs = np.nonzero(front)
    y0, y1 = ys.min(), ys.max()
    for yy, xx in zip(ys, xs):
        f = (yy - y0) / max(1, y1 - y0)
        idx = int(np.clip(np.floor(4.4 - f * 1.4 + _BAYER[yy, xx] * 0.5), 2, 5))
        p.px(xx, yy, rp[idx])
    p.paint(top, rp[6])
    p.line((x + d, y + 1), (x + w + d - 1, y + 1), rp[7], clip=top)
    p.line((x + 1, y + d + 1), (x + w - 1, y + d + 1), rp[6], clip=front)
    p.line((x + w, y + d + 1), (x + w, y + d + h - 1), rp[1], clip=whole)
    return whole


def bronze_icon():
    p = Pic()
    _ingot(p, 2, 19, 12, 5, 4, R_BRONZE)
    _ingot(p, 13, 20, 12, 5, 4, R_BRONZE)
    _ingot(p, 7, 10, 12, 5, 4, R_BRONZE)
    return p.sprite(shadow=False)


def _flame(p, cx, by, h):
    """Пламя-эмблема на грани: красно-оранжевое, жёлтое сердце, белая точка."""
    fire = [lch(34, 70, 35), lch(56, 82, 50), lch(76, 82, 72), lch(94, 24, 92)]
    w = h * 0.38
    outer = poly([(cx, by), (cx - w, by - h * 0.35), (cx - w * 0.8, by - h * 0.62), (cx - w * 0.15, by - h * 0.95),
                  (cx + w * 0.05, by - h * 0.7), (cx + w * 0.6, by - h * 0.78), (cx + w, by - h * 0.35)])
    p.ring(outer, fire[0])
    p.paint(outer, fire[1])
    inner = poly([(cx, by - 1), (cx - w * 0.55, by - h * 0.3), (cx - w * 0.1, by - h * 0.65), (cx + w * 0.55, by - h * 0.3)])
    p.paint(inner, fire[2])
    p.px(cx, by - h * 0.2, fire[3])
    p.px(cx, by - h * 0.3, fire[3])


def _block(p, x, y, w, h, d, rp, mask_fx):
    front = poly([(x, y + d), (x + w, y + d), (x + w, y + d + h), (x, y + d + h)])
    top = poly([(x, y + d), (x + d, y), (x + w + d, y), (x + w, y + d)])
    right = poly([(x + w, y + d), (x + w + d, y), (x + w + d, y + h), (x + w, y + d + h)])
    whole = front | top | right
    p.ring(whole, rp[0])
    p.paint(top, rp[6])
    p.paint(front, rp[4])
    p.paint(right, rp[2])
    p.line((x, y + d), (x + w, y + d), rp[7], clip=front | top)
    mask_fx(front, top, right)
    return front


def fuel_block_icon():
    p = Pic()
    rng = np.random.default_rng(31)

    def fx(front, top, right):
        for m, tones in ((top, (7, 5)), (front, (3, 5)), (right, (1, 3))):
            ys, xs = np.nonzero(erode(m))
            for k in rng.choice(len(ys), min(11, len(ys)), replace=False):
                x, y = int(xs[k]), int(ys[k])
                for dx in range(int(rng.integers(1, 3))):
                    p.px_in(m, x + dx, y, R_BRICK[tones[int(rng.integers(0, 2))]])
    fr = _block(p, 4, 6, 18, 15, 6, R_BRICK, fx)
    _flame(p, 13, 25, 11)
    return p.sprite(shadow=False)


def fuel_block_coal_icon():
    p = Pic()
    rng = np.random.default_rng(32)
    rc = R_COAL

    def fx(front, top, right):
        ys, xs = np.nonzero(erode(top))
        for k in rng.choice(len(ys), min(6, len(ys)), replace=False):
            p.px(xs[k], ys[k], rc[5])
        ys, xs = np.nonzero(erode(front))
        for k in rng.choice(len(ys), min(8, len(ys)), replace=False):
            p.px(xs[k], ys[k], rc[1 if k % 2 else 3])
    rp = [rc[0], rc[1], rc[2], rc[3], rc[3], rc[4], rc[5], rc[6]]
    fr = _block(p, 4, 6, 18, 15, 6, rp, fx)
    _flame(p, 13, 25, 11)
    return p.sprite(shadow=False)


def _peat_clod(p, cx, cy, rx, ry, rot, sd, moss_thr=0.68):
    m = blob(cx, cy, rx, ry, rot, 0.26, sd, 8, 2.2)
    n = vnoise(sd + 7, 2.6) + (vnoise(sd + 9, 1.4) - 0.5) * 0.3
    moss = erode(m) & (n > moss_thr) & (_YY < cy + 2)
    p.dome(m, R_PEAT, spec=False, lo=-0.75, hi=1.4, alt=(moss, R_MOSS), rim=R_PEAT[7],
           tex=(vnoise(sd + 13, 2.0) - 0.5) * 0.3)
    area = int(m.sum())
    _strands(p, m, area // 10, sd + 21, R_PEAT[1], 9, curl=0.5)
    _strands(p, m, area // 14, sd + 25, R_PEAT[7], 7, curl=0.5)
    _fibers(p, m, 4 + int(rx / 1.5), sd + 31, R_PEAT, out=True)
    return m


TILES = {
    "ore_iron": iron_tile, "ore_lead": lead_tile, "ore_silver": silver_tile, "ore_copper": copper_tile,
    "ore_aluminium": aluminium_tile, "ore_nickel": nickel_tile, "ore_platinum": platinum_tile,
    "ore_titanium": titanium_tile, "ore_lithium": lithium_tile, "ore_mercury": mercury_tile, "ore_gold": gold_tile,
    "ore_scrap": scrap_tile, "ore_peat": peat_tile, "ore_coal": coal_tile, "ore_uranium": uranium_tile,
}
ICONS = {
    "iron_ore": iron_icon, "lead": lead_icon, "silver": silver_icon, "copper": copper_icon,
    "aluminium": aluminium_icon, "nickel": nickel_icon, "platinum": platinum_icon, "titanium": titanium_icon,
    "lithium": lithium_icon, "mercury": mercury_icon, "gold": gold_icon, "scrap": scrap_icon, "peat": peat_icon,
    "coal": coal_icon, "uranium": uranium_icon, "bronze": bronze_icon, "fuel_block": fuel_block_icon,
    "fuel_block_coal": fuel_block_coal_icon,
}

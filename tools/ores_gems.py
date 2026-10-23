#!/usr/bin/env python3
"""ores_gems.py — спрайты самоцветов, глубинных руд и добычи с монстров (ветка «ores-gems»).

Контракт реестра (его читают tools/gen_tiles_deep.py, tools/gen_ore_icons.py, tools/check_ores.py):

  TILES = {"ore_diamond": fn, ...}   # имя тайла -> fn() -> sprite_kit.Sprite: ЗАЛЕЖЬ на сетке 32x32 с альфой,
                                     # без грунта (грунт пояса подкладывает генератор).
  ICONS = {"diamond": fn, ...}       # id минерала/предмета -> fn() -> Sprite: значок ПРЕДМЕТА 32x32 без грунта
                                     # -> art/ui/shop/item_<id>.png (и art/gear/mat_<id>.png, если такой файл есть).
                                     # Для ресурса из TILES без записи в ICONS значком станет сам спрайт тайла.

Ресурсы этой ветки (тайл + значок): ore_diamond, ore_ruby, ore_emerald, ore_geocrystal, ore_ancient_metal,
ore_obsidian, ore_hellstone, ore_dark_matter, ore_universalium, ore_angelstone, ore_divine_heart.
Только значки (добыча монстров): cinder_ash, moth_dust, hopper_fang, mimic_geode, spark_core, warden_plate,
abyss_core, idol_shard.
Соответствие имя тайла -> id минерала: ore_universalium -> universum, остальные — без префикса ore_.
Восемь глубинных руд (geocrystal … divine_heart) сейчас рисуют функции sprite_* в tools/gen_tiles_deep.py:
переписывай их здесь (запись в TILES перекрывает старую), в gen_tiles_deep.py их не правь.

Как рисуется. Свет сверху-слева. У каждого материала 6-8 тонов, заданных в Lab (L, хрома, оттенок): тёмный
контур ТОГО ЖЕ оттенка (не чёрный), тень, база, свет, блик, акцент. Куски рисуются от дальнего к ближнему, у каждого
свой контур (так перекрытия читаются), на гранях — ободок света сверху-слева и рефлекс снизу-справа. Светящиеся
материалы получают ореол с дизерингом (чётче, чем гладкий градиент) и яркое ядро; драгоценные — искры-крестики.
Это замена-заглушка уровня «программист нарисовал аккуратно», не работа художника владельца.
"""

import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from sprite_kit import G, Sprite

TILES = {}
ICONS = {}

# ── цвет (Lab-перевод скопирован: gen_tiles_deep импортирует этот модуль, обратный импорт дал бы цикл) ──

_M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
_MI = np.linalg.inv(_M)
_WP = np.array([0.95047, 1.0, 1.08883])


def _lab2rgb(lab):
    fy = (lab[0] + 16) / 116
    f = np.array([fy + lab[1] / 500, fy, fy - lab[2] / 200])
    xyz = np.where(f ** 3 > 0.008856, f ** 3, (f - 16 / 116) / 7.787) * _WP
    lin = np.clip(_MI @ xyz, 0, 1)
    c = np.where(lin > 0.0031308, 1.055 * lin ** (1 / 2.4) - 0.055, 12.92 * lin)
    return tuple(int(v) for v in np.clip(np.rint(c * 255), 0, 255))


def _rgb2lab(c):
    c = np.asarray(c, dtype=np.float64) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    xyz = (_M @ lin) / _WP
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.array([116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])])


def lch(L, C, h):
    """Цвет из светлоты, хромы и угла оттенка (градусы, как в таблице брифа)."""
    r = math.radians(h)
    return _lab2rgb(np.array([L, C * math.cos(r), C * math.sin(r)]))


def mix(a, b, t):
    return tuple(int(round(int(a[i]) + (int(b[i]) - int(a[i])) * t)) for i in range(3))


def tone(c, dL=0.0, k=1.0):
    """Тот же оттенок, светлота сдвинута на dL, хрома умножена на k."""
    lab = _rgb2lab(c)
    return _lab2rgb(np.array([lab[0] + dL, lab[1] * k, lab[2] * k]))


BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


# ── кисть ─────────────────────────────────────────────────────────────────

def poly_mask(pts):
    im = Image.new("L", (G, G), 0)
    ImageDraw.Draw(im).polygon([(float(x), float(y)) for x, y in pts], fill=1)
    return np.array(im, dtype=bool)


def ell_mask(cx, cy, rx, ry, rot=0.0):
    yy, xx = np.mgrid[0:G, 0:G].astype(float)
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    u = (xx - cx) * c + (yy - cy) * s
    v = -(xx - cx) * s + (yy - cy) * c
    return (u / rx) ** 2 + (v / ry) ** 2 <= 1.0


def _shift(m, dx, dy):
    out = np.zeros_like(m)
    ys = slice(max(dy, 0), G + min(dy, 0))
    yd = slice(max(-dy, 0), G + min(-dy, 0))
    xs = slice(max(dx, 0), G + min(dx, 0))
    xd = slice(max(-dx, 0), G + min(-dx, 0))
    out[ys, xs] = m[yd, xd]
    return out


class Cv:
    """Холст 32x32 RGBA. Все операции — на пикселях, без сглаживания."""

    def __init__(self, seed="ore"):
        self.a = np.zeros((G, G, 4), dtype=np.uint8)
        self.rng = random.Random(seed)

    def put(self, x, y, c, a=255):
        x, y = int(x), int(y)
        if 0 <= x < G and 0 <= y < G:
            self.a[y, x] = (c[0], c[1], c[2], a)

    def fill(self, m, c, a=255):
        self.a[m] = (c[0], c[1], c[2], a)

    def solid(self, thr=200):
        return self.a[..., 3] >= thr

    def line(self, p0, p1, c, a=255):
        (x0, y0), (x1, y1) = [(int(round(v[0])), int(round(v[1]))) for v in (p0, p1)]
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.put(x0, y0, c, a)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def poly_line(self, pts, c, a=255):
        for p, q in zip(pts, pts[1:]):
            self.line(p, q, c, a)

    def ring(self, m, col=None, k=-26.0, kc=1.0, diag=False):
        """Контур в 1 пиксель вокруг маски m, поверх всего, что уже нарисовано. col — цвет, функция
        (dx, dy, цвет_соседа) -> цвет или None: тогда цвет соседа темнеет на |k| единиц L."""
        out = np.zeros_like(m)
        nbs = ((1, 0), (-1, 0), (0, 1), (0, -1)) + (((1, 1), (-1, -1), (1, -1), (-1, 1)) if diag else ())
        for dx, dy in nbs:
            out |= _shift(m, dx, dy)
        out &= ~m
        for y, x in zip(*np.nonzero(out)):
            best = None
            for dx, dy in nbs:
                nx, ny = x + dx, y + dy
                if 0 <= nx < G and 0 <= ny < G and m[ny, nx]:
                    n = tuple(int(v) for v in self.a[ny, nx][:3])
                    if best is None or sum(n) < sum(best[2]):
                        best = (dx, dy, n)
            if best is None:
                continue
            if callable(col):
                c = col(best[0], best[1], best[2])
            elif col is not None:
                c = col
            else:
                c = tone(best[2], k, kc)
            if c is not None:
                self.put(x, y, c)
        return out

    def rim(self, m, light, dark=None, t_light=0.65, t_dark=0.5, bottom=False):
        """Ободок света на верхне-левой кромке маски и рефлекс на правой (только внутри m);
        нижнюю кромку трогаем лишь при bottom=True — иначе кусок «стоит» на земле."""
        up, left = ~_shift(m, 0, 1), ~_shift(m, 1, 0)
        down, right = ~_shift(m, 0, -1), ~_shift(m, -1, 0)
        lit = m & (up | left)
        low = m & (right | (down if bottom else np.zeros_like(m)))
        for y, x in zip(*np.nonzero(lit)):
            self.put(x, y, mix(tuple(self.a[y, x][:3]), light, t_light))
        if dark is not None:
            for y, x in zip(*np.nonzero(low & ~lit)):
                self.put(x, y, mix(tuple(self.a[y, x][:3]), dark, t_dark))

    def shadow(self, dx=1, dy=1, c=(8, 4, 6), a=120):
        """Жёсткая тень в 1 пиксель вправо-вниз под всем нарисованным: отрывает залежь от грунта."""
        solid = self.solid()
        sh = _shift(solid, dx, dy) & ~solid & (self.a[..., 3] < 60)
        self.a[sh] = (c[0], c[1], c[2], a)

    def spark(self, x, y, c=(255, 255, 255), arm=(255, 255, 255), n=1, a=215):
        self.put(x, y, c)
        for i in range(1, n + 1):
            aa = a if i == 1 else a // 2
            for dx, dy in ((i, 0), (-i, 0), (0, i), (0, -i)):
                if self.a[min(max(y + dy, 0), G - 1), min(max(x + dx, 0), G - 1)][3] < aa:
                    self.put(x + dx, y + dy, arm, aa)

    def speckle(self, m, colors, n, p=1.0):
        ys, xs = np.nonzero(m)
        if len(ys) == 0:
            return
        for _ in range(n):
            if self.rng.random() > p:
                continue
            i = self.rng.randrange(len(ys))
            self.put(xs[i], ys[i], self.rng.choice(colors))

    def halo(self, color, r, strength, color2=None, levels=3, solid_thr=200):
        """Ореол под фигурой: размытая маска в 3 ступени альфы с упорядоченным дизерингом на границах ступеней."""
        solid = self.solid(solid_thr)
        al = Image.fromarray((solid * 255).astype(np.uint8))
        v = np.array(al.filter(ImageFilter.GaussianBlur(r)), dtype=np.float64) / 255.0 * strength
        yy, xx = np.mgrid[0:G, 0:G]
        bay = BAYER[yy % 4, xx % 4]
        q = np.floor(np.clip(v, 0, 1) * levels + bay * 0.999 - 0.0)
        q = np.clip(q, 0, levels)
        out = self.a.copy()
        for y, x in zip(*np.nonzero(~solid & (q > 0))):
            lv = q[y, x] / levels
            col = color if color2 is None else mix(color2, color, min(1.0, v[y, x] * 1.6))
            a = int(round(255 * (0.18 + 0.5 * lv) * min(1.0, strength + 0.2)))
            if out[y, x, 3] < a:
                out[y, x] = (col[0], col[1], col[2], a)
        self.a = out

    def sprite(self):
        s = Sprite()
        s.img = Image.fromarray(self.a, "RGBA")
        s.d = ImageDraw.Draw(s.img)
        return s


def sphere(cv, cx, cy, r, tones, light=(-0.5, -0.6), ry=None, bias=0.12):
    """Шар с ламбертовым светом и дизерингом между тонами. tones — от тёмного к светлому."""
    ry = ry or r
    lx, ly = light
    lz = math.sqrt(max(0.05, 1 - lx * lx - ly * ly))
    m = ell_mask(cx, cy, r, ry)
    n = len(tones)
    for y, x in zip(*np.nonzero(m)):
        nx, ny = (x - cx) / r, (y - cy) / ry
        nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
        v = nx * lx + ny * ly + nz * lz
        t = min(max((v + bias) / (1 + bias), 0.0), 1.0) * (n - 1)
        i = int(math.floor(t + BAYER[y % 4, x % 4] - 0.5 + 0.5))
        cv.put(x, y, tones[min(max(i, 0), n - 1)])
    return m


def rot(pts, ang, c=(0.0, 0.0)):
    """Повернуть точки на ang градусов вокруг c (по часовой на экране)."""
    r = math.radians(ang)
    co, si = math.cos(r), math.sin(r)
    return [(c[0] + (x - c[0]) * co - (y - c[1]) * si, c[1] + (x - c[0]) * si + (y - c[1]) * co) for x, y in pts]


def blade(bx, by, length, width, ang=0.0, skew=0.0, kr=0.62, kl=0.4, out=0.12):
    """Осколок-лезвие, стоящий основанием в (bx, by), остриём вверх с наклоном ang. Точки: T кончик, BL/BR основание,
    KL/KR изломы кромок (рваный край), M середина основания."""
    w = width / 2.0
    loc = {
        "T": (skew, -length), "BL": (-w, 0.0), "BR": (w, 0.0), "M": (skew * 0.3, 0.0),
        "KR": (w * (1 + out) + skew * kr, -length * kr), "KL": (-w * (1 - out) + skew * kl, -length * kl),
    }
    names = list(loc)
    pts = rot([loc[k] for k in names], ang)
    return {k: (bx + p[0], by + p[1]) for k, p in zip(names, pts)}


def fit_blades(params, box):
    """Масштабировать и сдвинуть набор лезвий (bx, by, длина, ширина, угол, скос) так, чтобы они легли в box = (x0, y0, x1, y1)."""
    xs, ys = [], []
    for p in params:
        for pt in blade(*p).values():
            xs.append(pt[0])
            ys.append(pt[1])
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    s = min((box[2] - box[0]) / (x1 - x0), (box[3] - box[1]) / (y1 - y0))
    ox = box[0] + ((box[2] - box[0]) - (x1 - x0) * s) / 2 - x0 * s
    oy = box[1] + ((box[3] - box[1]) - (y1 - y0) * s) / 2 - y0 * s
    return [(p[0] * s + ox, p[1] * s + oy, p[2] * s, p[3] * s, p[4], p[5] * s) + tuple(p[6:]) for p in params]


# ═══════════════════════════════════════════════════════════════════════════
#  Ресурсы
# ═══════════════════════════════════════════════════════════════════════════


# ── обсидиан: рваные острые осколки; на тёмном грунте читается ободком света по кромке ──

def _obsidian(mode):
    cv = Cv("obsidian")
    P = {
        "deep": lch(3, 14, 328), "base": lch(8, 26, 328), "mid": lch(16, 42, 326), "lit": lch(32, 60, 324),
        "rim": lch(74, 52, 328), "rim2": lch(40, 64, 326), "glint": lch(96, 8, 316),
    }
    blades = [(23, 27, 17, 7, 19, 1.5), (7, 27, 12, 5, -24, -1.0), (14, 29, 25, 10, -8, 1.5),
              (19, 30, 8, 5, 6, 0.5)]
    box = (4, 3, 28, 29) if mode == "tile" else (1, 1, 31, 31)
    for bx, by, ln, wd, ang, sk in fit_blades(blades, box):
        b = blade(bx, by, ln, wd, ang, sk)
        sil = poly_mask([b["BL"], b["KL"], b["T"], b["KR"], b["BR"]])
        cv.fill(sil, P["base"])
        cv.fill(poly_mask([b["BL"], b["KL"], b["T"], b["M"]]) & sil, P["mid"])
        cv.fill(poly_mask([b["KR"], b["BR"], b["M"]]) & sil, P["deep"])
        # блик-росчерк вдоль левой кромки и светлая грань у кончика
        tx, ty = b["T"]
        kx, ky = b["KL"]
        cap = poly_mask([b["T"], b["KL"], ((tx + kx) / 2 + 2, (ty + ky) / 2 + 1)]) & sil
        cv.fill(cap, P["lit"])
        cv.rim(sil, P["rim"], P["rim2"], 0.95, 0.7)
        cv.line((tx, ty + 1), (tx + (kx - tx) * 0.5, ty + (ky - ty) * 0.5 + 1), P["glint"])
    cv.shadow()
    cv.halo(lch(38, 64, 326), 1.6, 0.5)
    return cv.sprite()


TILES["ore_obsidian"] = lambda: _obsidian("tile")
ICONS["obsidian"] = lambda: _obsidian("icon")


# ── тёмная материя: чёрная сфера, диск «горизонта событий», звёздные крапины ──

def _disc(cv, cx, cy, rx, ry, ang, front, tones, qlo=0.6):
    """Кольцо в перспективе: ширина в плоскости диска постоянна, поэтому на концах эллипса оно толще.
    Цвет: внутренний край раскалён добела, наружный — тёмно-фиолетовый; слева ярче (допплеровский диск)."""
    r = math.radians(ang)
    co, si = math.cos(r), math.sin(r)
    for y in range(G):
        for x in range(G):
            u = (x - cx) * co + (y - cy) * si
            v = -(x - cx) * si + (y - cy) * co
            q = math.hypot(u / rx, v / ry)
            if not qlo <= q <= 1.0 or (v >= 0) != front:
                continue
            t = (q - qlo) / (1 - qlo)                # 0 внутри, 1 снаружи
            side = 0.5 - 0.5 * u / rx                # 1 слева
            heat = (1 - t) * 0.7 + side * 0.5
            i = 0 if t > 0.78 else (1 if heat < 0.5 else (2 if heat < 0.85 else 3))
            cv.put(x, y, tones[i])


def _dark_matter(mode):
    cv = Cv("dark_matter")
    k = 0.92 if mode == "tile" else 1.1
    cx, cy = 15.5, 15.5
    r = 6.8 * k
    rx, ry, ang = 14.8 * k, 4.8 * k, -14.0
    ring = [lch(24, 56, 297), lch(46, 80, 295), lch(78, 42, 297), lch(97, 8, 288)]
    _disc(cv, cx, cy, rx, ry, ang, False, [tone(c, -16, 0.9) for c in ring], qlo=0.8)
    sph = [lch(1, 8, 296), lch(4, 26, 296), lch(8, 40, 296), lch(14, 52, 296)]
    sphere(cv, cx, cy, r, sph, light=(0.4, 0.5), bias=0.6)
    # ободок линзирования: тонкая светлая кромка сверху-слева, на нижне-правой — тёмно-фиолетовая
    for y in range(G):
        for x in range(G):
            d = math.hypot(x - cx, y - cy)
            if r + 0.4 <= d <= r + 1.4 and cv.a[y, x, 3] == 0:
                t = -((x - cx) * 0.6 + (y - cy) * 0.8) / d
                cv.put(x, y, ring[3] if t > 0.55 else (ring[2] if t > 0.0 else ring[0]))
    for (x, y) in ((12, 12), (14, 10), (17, 13), (11, 16)):
        cv.put(x, y, tone(ring[1], -10))
    _disc(cv, cx, cy, rx, ry, ang, True, ring, qlo=0.8)
    for (x, y) in ((4, 5), (27, 5), (28, 25), (4, 27), (16, 2), (22, 29), (2, 14), (29, 14)):
        if cv.a[y, x, 3] == 0:
            cv.put(x, y, ring[3] if (x + y) % 3 else ring[2])
    cv.halo(lch(42, 78, 296), 2.3, 0.72)
    return cv.sprite()


TILES["ore_dark_matter"] = lambda: _dark_matter("tile")
ICONS["dark_matter"] = lambda: _dark_matter("icon")


# ── вселениум: многолучевая звезда, каждый луч своего цвета радуги, белое ядро ──

def _universalium(mode):
    cv = Cv("universalium")
    k = 1.0 if mode == "tile" else 1.14
    cx, cy = 15.5, 15.5
    turn = 11.0   # звезда повёрнута: без осевой симметрии
    # (угол, длина, оттенок): кардинальные лучи длинные, диагональные короткие
    rays = [(-90, 12.0, 236), (-45, 12.0, 84), (0, 13.0, 8), (45, 11.5, 64), (90, 13.0, 4), (135, 9.5, 24),
            (180, 13.0, 90), (-135, 7.0, 205)]
    order = sorted(range(len(rays)), key=lambda i: rays[i][1])
    for i in order:
        ang, ln, hue = rays[i]
        a = math.radians(ang + turn)
        dx, dy = math.cos(a), math.sin(a)
        px, py = -dy, dx
        ln *= k
        d, w = ln * 0.3, 2.8 * k * (1.0 if ln > 10.5 * k else 0.8)
        T = (cx + dx * ln, cy + dy * ln)
        sl = (cx + dx * d - px * w, cy + dy * d - py * w)
        sr = (cx + dx * d + px * w, cy + dy * d + py * w)
        lit, dark = lch(76, 70, hue), lch(50, 100, hue)
        cv.fill(poly_mask([(cx, cy), sl, T, sr]), dark)
        cv.fill(poly_mask([(cx, cy), sl, T]), lit)
        cv.line((cx + dx * d * 0.6, cy + dy * d * 0.6), (cx + dx * ln * 0.78, cy + dy * ln * 0.78), lch(94, 24, hue))
    sil = cv.solid()
    cv.ring(sil, lch(26, 62, 264))
    # ядро: белый восьмигранник с призматическим бликом
    core = ell_mask(cx, cy, 2.7 * k, 2.7 * k)
    cv.fill(core, lch(96, 8, 250))
    cv.fill(ell_mask(cx + 0.5, cy + 0.7, 1.9 * k, 1.9 * k), lch(88, 24, 205))
    cv.fill(ell_mask(cx - 0.5, cy - 0.6, 1.3 * k, 1.3 * k), (255, 255, 255))
    cv.put(cx + 1.2 * k, cy + 1.8 * k, lch(90, 50, 340))
    cv.put(cx + 2.2 * k, cy + 0.3 * k, lch(92, 55, 95))
    cv.ring(core, lch(44, 56, 340))
    cv.halo(lch(88, 52, 215), 1.3, 0.36)
    for (x, y, n) in ((4, 5, 1), (27, 26, 1), (28, 7, 0), (5, 26, 0)):
        if cv.a[y, x, 3] < 100:
            cv.spark(x, y, (255, 255, 255), (235, 250, 255), n)
    return cv.sprite()


TILES["ore_universalium"] = lambda: _universalium("tile")
ICONS["universum"] = lambda: _universalium("icon")


# ── ангельский камень: каплевидный кристалл с крыльями-перьями и нимбом, мягкое золото-белое ──

def _angelstone(mode):
    cv = Cv("angelstone")
    P = {
        "out": lch(50, 44, 68), "deep": lch(66, 40, 76), "shade": lch(80, 38, 84), "base": lch(91, 26, 92),
        "light": lch(96, 14, 96), "hi": (255, 255, 252), "gold": lch(86, 72, 88), "gold2": lch(72, 66, 78),
    }
    sc = 0.86 if mode == "tile" else 1.08
    ox, oy = 16.0, 16.0

    def T(p):
        return (ox + (p[0] - 16) * sc, oy + (p[1] - 16) * sc)

    def poly(pts):
        return poly_mask([T(p) for p in pts])

    # крылья-перья позади (левое крупнее правого)
    wings = [
        ([(11, 19), (8, 14), (4, 9), (2, 8), (3, 13), (4, 18), (7, 22), (11, 24)], [((11, 21), (3, 10)), ((10, 23), (4, 16))]),
        ([(21, 19), (24, 15), (28, 11), (29, 12), (28, 17), (26, 21), (22, 24)], [((21, 21), (28, 13))]),
    ]
    for pts, feathers in wings:
        m = poly(pts)
        cv.fill(m, P["base"])
        cv.fill(m & poly([(p[0], p[1] + 2) for p in pts]) & ~poly([(p[0], p[1] - 3) for p in pts]), P["shade"])
        for a, b in feathers:
            cv.line(T(a), T(b), P["shade"])
        cv.rim(m, P["hi"], P["gold"], 0.8, 0.4)
        cv.ring(m, P["out"])
    # нимб над камнем (чуть наклонён)
    halo_pts = []
    for i in range(40):
        t = i / 40.0 * math.tau
        halo_pts.append((round(ox + (7.0 * math.cos(t) - 0.8 * math.sin(t)) * sc), round(oy - 12.2 * sc + (1.9 * math.sin(t) + 0.7 * math.cos(t)) * sc)))
    for (x, y) in halo_pts:
        cv.put(x, y, P["gold"])
    for (x, y) in halo_pts[::4]:
        cv.put(x, y, P["light"])
    # капля: две грани и верхняя/нижняя фасетки
    drop = [(16, 6), (20, 11), (22, 17), (20, 23), (16, 27), (12, 23), (10, 17), (12, 11)]
    m = poly(drop)
    cv.fill(m, P["base"])
    cv.fill(poly([(16, 6), (20, 11), (22, 17), (20, 23), (16, 27), (16, 16)]) & m, P["shade"])
    cv.fill(poly([(16, 27), (20, 23), (16, 16)]) & m, P["deep"])
    cv.fill(poly([(16, 6), (13.5, 12), (16, 16), (18.5, 12)]) & m, P["light"])
    cv.fill(poly([(16, 6), (12, 11), (13.5, 12)]) & m, P["hi"])
    cv.rim(m, P["hi"], P["gold"], 0.7, 0.5, bottom=True)
    cv.ring(m, P["out"])
    cv.line(T((16, 16)), T((16, 26)), P["shade"])
    cv.spark(round(ox + (13 - 16) * sc), round(oy + (11 - 16) * sc), (255, 255, 255), (255, 250, 220), 1)
    cv.halo(lch(92, 62, 90), 2.6, 0.6)
    for (x, y) in ((6, 28), (26, 27), (27, 4)):
        if cv.a[y, x, 3] < 100:
            cv.spark(x, y, (255, 255, 255), P["gold"], 1 if (x + y) % 2 else 0)
    return cv.sprite()


TILES["ore_angelstone"] = lambda: _angelstone("tile")
ICONS["angelstone"] = lambda: _angelstone("icon")


# ── алмаз: огранённые бриллианты (корона, пояс, павильон), ледяной голубо-белый, искры-кресты ──

def _brilliant(cv, cx, top, w, h, P, flip=0.0):
    """Бриллиант сбоку: стол, грани короны, пояс, павильон-остриё. flip сдвигает остриё (разный наклон камней)."""
    gy = top + max(2.0, h * 0.36)
    tl, tr = (cx - w * 0.30, top), (cx + w * 0.30, top)
    gl, gr = (cx - w * 0.5, gy), (cx + w * 0.5, gy)
    tip = (cx + flip, top + h)
    ml, mr = (cx - w * 0.17, gy), (cx + w * 0.17, gy)
    sil = poly_mask([tl, tr, gr, tip, gl])
    cv.fill(sil, P["base"])
    cv.fill(poly_mask([tl, tr, mr, ml]), P["hi"])                   # стол
    cv.fill(poly_mask([tl, ml, gl]), P["light"])                    # левая грань короны
    cv.fill(poly_mask([tr, gr, mr]), P["shade"])                    # правая грань короны
    cv.fill(poly_mask([gl, ml, tip]), P["base"])                    # павильон: левая
    cv.fill(poly_mask([ml, mr, tip]), P["light"])                   # центральная
    cv.fill(poly_mask([mr, gr, tip]), P["deep"])                    # правая — в тени
    cv.line(gl, gr, P["shade"])                                      # пояс
    cv.line(ml, tip, P["shade"])
    cv.rim(sil, P["hi"], P["cyan"], 0.8, 0.55)
    cv.ring(sil, P["out"])
    return sil


def _diamond(mode):
    cv = Cv("diamond")
    P = {
        "out": lch(30, 42, 232), "deep": lch(74, 42, 204), "shade": lch(83, 38, 197), "base": lch(90, 32, 194),
        "light": lch(96, 14, 194), "hi": lch(99, 3, 200), "cyan": lch(86, 44, 192),
    }
    if mode == "tile":
        gems = [(8.5, 5, 9, 9, -0.5), (24, 8, 7, 7, 0.5), (15, 12, 15, 14.5, 0.0)]
    else:
        gems = [(8, 2, 11, 11, -0.5), (24.5, 6, 9, 9, 0.5), (15.5, 11, 18, 18, 0.0)]
    for cx, top, w, h, fl in gems:
        _brilliant(cv, cx, top, w, h, P, fl)
    # искры-кресты на гранях и мелкая крошка
    if mode == "tile":
        cv.spark(10, 15, (255, 255, 255), P["hi"], 2)
        cv.spark(26, 6, (255, 255, 255), P["hi"], 0)
        cv.put(5, 24, P["base"])
        cv.put(5, 25, P["deep"])
        cv.put(26, 25, P["light"])
    else:
        cv.spark(9, 16, (255, 255, 255), P["hi"], 2)
        cv.spark(26, 5, (255, 255, 255), P["hi"], 1)
    return cv.sprite()


TILES["ore_diamond"] = lambda: _diamond("tile")
ICONS["diamond"] = lambda: _diamond("icon")


# ── рубин: овальные и грушевидные огранённые камни, глубокий красный, глянец ──

def _gem_oval(cv, cx, cy, rx, ry, rot, P, pear=False):
    """Круглая/овальная огранка: корона из 8 секторов-граней (свет сверху-слева), стол-эллипс, глянцевый блик.
    pear=True — «груша»: узкий кончик вниз по длинной оси."""
    m = ell_mask(cx, cy, rx, ry, rot)
    if pear:
        r = math.radians(rot)
        ux, uy = math.cos(r), math.sin(r)
        vx, vy = -math.sin(r), math.cos(r)
        tip = (cx + ux * rx * 1.45, cy + uy * rx * 1.45)
        m |= poly_mask([(cx + vx * ry * 0.9, cy + vy * ry * 0.9), (cx - vx * ry * 0.9, cy - vy * ry * 0.9), tip])
    tones = [P["deep"], P["shade"], P["base"], P["light"]]
    for y, x in zip(*np.nonzero(m)):
        dx, dy = x - cx, y - cy
        ang = math.atan2(dy, dx)
        sector = int(((ang + math.pi) / (math.pi / 4)) % 8)
        lam = math.cos(ang - math.atan2(-1, -1))                   # к свету: сверху-слева
        v = 1.5 + lam * 1.3 + (0.5 if sector % 2 else -0.5)         # чередование граней
        cv.put(x, y, tones[min(max(int(round(v)), 0), 3)])
    # стол: меньший эллипс, смещённый к свету, разделён диагональю
    tb = ell_mask(cx - 0.18 * rx, cy - 0.2 * ry, rx * 0.5, ry * 0.5, rot)
    tb &= m
    for y, x in zip(*np.nonzero(tb)):
        cv.put(x, y, P["hi"] if (x - cx) * 0.9 + (y - cy) < -0.8 else P["light"])
    if rx > 4.5:
        cv.ring(tb, tone(P["shade"], 2))
    cv.rim(m, P["hi"], P["reflex"], 0.55, 0.65, bottom=True)
    cv.ring(m, P["out"])
    # глянец
    gx, gy = cx - 0.45 * rx, cy - 0.5 * ry
    cv.put(gx, gy, (255, 255, 255))
    cv.put(gx + 1, gy, P["spec"])
    cv.put(gx, gy + 1, P["spec"])
    return m


def _ruby(mode):
    cv = Cv("ruby")
    P = {
        "out": lch(16, 44, 32), "deep": lch(25, 58, 34), "shade": lch(33, 68, 36), "base": lch(42, 74, 37),
        "light": lch(53, 76, 34), "hi": lch(70, 56, 28), "spec": lch(90, 22, 20), "reflex": lch(60, 70, 34),
    }
    if mode == "tile":
        gems = [(8.5, 9.5, 3.7, 4.5, -128, True), (17.5, 18.5, 7.0, 5.2, 16, False), (7.5, 23.5, 3.4, 3.4, 0, False)]
    else:
        gems = [(8, 8.5, 4.6, 5.6, -128, True), (18, 18.5, 8.8, 6.5, 16, False), (7, 25, 4.2, 4.2, 0, False)]
    for cx, cy, rx, ry, rot, pear in gems:
        _gem_oval(cv, cx, cy, rx, ry, rot, P, pear)
    if mode == "tile":
        cv.spark(21, 11, (255, 235, 240), P["hi"], 1)
        cv.put(26, 24, P["base"])
        cv.put(27, 24, P["out"])
        cv.put(15, 5, P["shade"])
    else:
        cv.spark(22, 9, (255, 235, 240), P["hi"], 2)
    return cv.sprite()


TILES["ore_ruby"] = lambda: _ruby("tile")
ICONS["ruby"] = lambda: _ruby("icon")


# ── изумруд: прямоугольная ступенчатая огранка со срезанными углами и внутренним прямоугольником ──

def _gem_step(cv, cx, cy, w, h, ang, P):
    """Ступенчатая огранка: восьмиугольник, внутри стол-прямоугольник; четыре трапеции-ступени вокруг него
    светлеют к свету (верх, лево) и темнеют в тени (низ, право). Второй, внутренний, ступенчатый ободок и блик."""
    hw, hh = w / 2.0, h / 2.0
    c = min(hw, hh) * 0.42

    def octa(a, b, cut):
        return [(-a + cut, -b), (a - cut, -b), (a, -b + cut), (a, b - cut), (a - cut, b), (-a + cut, b), (-a, b - cut), (-a, -b + cut)]

    def T(pts):
        return [(cx + x, cy + y) for x, y in rot(pts, ang)]

    outer = octa(hw, hh, c)
    s = max(1.6, min(hw, hh) * 0.36)
    mid = octa(hw - s, hh - s, c * 0.6)
    s2 = s * 1.7
    tab = octa(max(1.0, hw - s2), max(1.2, hh - s2), c * 0.3)
    o, mi, ta = T(outer), T(mid), T(tab)
    sil = poly_mask(o)
    cv.fill(sil, P["base"])
    # ступени: верх, лево, право, низ (между внешним и средним восьмиугольником)
    cv.fill(poly_mask([o[0], o[1], mi[1], mi[0]]), P["hi"])
    cv.fill(poly_mask([o[7], o[0], mi[0], mi[7]]) | poly_mask([o[6], o[7], mi[7], mi[6]]), P["light"])
    cv.fill(poly_mask([o[2], o[3], mi[3], mi[2]]) | poly_mask([o[1], o[2], mi[2], mi[1]]), P["shade"])
    cv.fill(poly_mask([o[4], o[5], mi[5], mi[4]]) | poly_mask([o[3], o[4], mi[4], mi[3]]), P["deep"])
    cv.fill(poly_mask([o[5], o[6], mi[6], mi[5]]), P["shade"])
    # вторая ступень
    cv.fill(poly_mask(mi), P["base"])
    cv.fill(poly_mask([mi[0], mi[1], ta[1], ta[0]]), P["light"])
    cv.fill(poly_mask([mi[7], mi[0], ta[0], ta[7]]) | poly_mask([mi[6], mi[7], ta[7], ta[6]]), P["light"])
    cv.fill(poly_mask([mi[2], mi[3], ta[3], ta[2]]) | poly_mask([mi[3], mi[4], ta[4], ta[3]]) | poly_mask([mi[4], mi[5], ta[5], ta[4]]), P["deep"])
    cv.fill(poly_mask(ta), P["core"])
    tm = poly_mask(ta)
    # блик на столе: диагональная полоска к свету
    ys, xs = np.nonzero(tm)
    if len(ys):
        x0, y0 = xs.min(), ys.min()
        cv.put(x0, y0, (255, 255, 255))
        cv.put(x0 + 1, y0, P["spec"])
        cv.put(x0, y0 + 1, P["spec"])
    cv.rim(sil, P["spec"], P["reflex"], 0.5, 0.6, bottom=True)
    cv.ring(sil, P["out"])
    return sil


def _emerald(mode):
    cv = Cv("emerald")
    P = {
        "out": lch(22, 40, 150), "deep": lch(32, 52, 152), "shade": lch(42, 62, 148), "base": lch(53, 70, 146),
        "light": lch(66, 66, 142), "hi": lch(80, 50, 140), "spec": lch(94, 20, 138), "core": lch(60, 72, 148),
        "reflex": lch(60, 64, 150),
    }
    if mode == "tile":
        gems = [(8.5, 10, 7.5, 10.0, -24), (17.5, 16, 11.0, 15.0, 6), (8.5, 23.5, 6.0, 7.5, 14)]
    else:
        gems = [(8, 9, 9.0, 12.0, -24), (18, 16.5, 13.0, 18.0, 6), (8, 25, 7.0, 9.0, 14)]
    for cx, cy, w, h, ang in gems:
        _gem_step(cv, cx, cy, w, h, ang, P)
    if mode == "tile":
        cv.spark(25, 8, P["spec"], P["hi"], 1)
        cv.put(26, 25, P["shade"])
        cv.put(26, 26, P["deep"])
    else:
        cv.spark(26, 6, P["spec"], P["hi"], 2)
    return cv.sprite()


TILES["ore_emerald"] = lambda: _emerald("tile")
ICONS["emerald"] = lambda: _emerald("icon")


# ── геокристалл: шестигранные янтарные призмы кучкой, внутри раскалённое ядро, вокруг ореол ──

def _prism(cv, bx, by, H, W, ang, P, tilt=0.0):
    """Шестигранная призма остриём вверх: три видимые грани (свет / база / тень) и пирамидка-остриё.
    Внутри средней грани — светящаяся жила (ядро)."""
    hs = H - 0.7 * W
    loc = {
        "BL": (-W / 2, 0), "BR": (W / 2, 0), "SL": (-W / 2, -hs), "SR": (W / 2, -hs), "T": (tilt, -H),
        "S1": (-W * 0.17, -hs + 0.22 * W), "S2": (W * 0.22, -hs + 0.22 * W),
        "B1": (-W * 0.17, 0.0), "B2": (W * 0.22, 0.0),
    }
    names = list(loc)
    pts = rot([loc[k] for k in names], ang)
    q = {k: (bx + p[0], by + p[1]) for k, p in zip(names, pts)}
    sil = poly_mask([q["BL"], q["SL"], q["T"], q["SR"], q["BR"]])
    cv.fill(sil, P["base"])
    cv.fill(poly_mask([q["BL"], q["SL"], q["S1"], q["B1"]]), P["light"])
    cv.fill(poly_mask([q["B2"], q["S2"], q["SR"], q["BR"]]), P["deep"])
    cv.fill(poly_mask([q["SL"], q["T"], q["S1"]]), P["hi"])
    cv.fill(poly_mask([q["S1"], q["T"], q["S2"]]), P["light"])
    cv.fill(poly_mask([q["S2"], q["T"], q["SR"]]), P["base"])
    # ядро: жила вдоль средней грани, ярче у основания
    top = ((q["S1"][0] + q["S2"][0]) / 2, (q["S1"][1] + q["S2"][1]) / 2 + 1)
    bot = ((q["B1"][0] + q["B2"][0]) / 2, by - 0.5)
    cv.line(top, bot, P["core"])
    cv.line((top[0] + (bot[0] - top[0]) * 0.55, top[1] + (bot[1] - top[1]) * 0.55), bot, P["white"])
    cv.rim(sil, P["hi"], P["shade"], 0.7, 0.6)
    cv.ring(sil, P["out"])
    return sil


def _geocrystal(mode):
    cv = Cv("geocrystal")
    P = {
        "out": lch(22, 52, 32), "deep": lch(36, 80, 36), "shade": lch(48, 92, 40), "base": lch(59, 96, 46),
        "light": lch(72, 92, 58), "hi": lch(90, 56, 80), "core": lch(94, 40, 90), "white": (255, 252, 226),
    }
    # (основание x, y, высота, ширина, наклон, смещение острия): веер из центра, у ног — самая яркая точка
    prisms = [(24, 27, 14, 6.4, 22, 0.8), (7.5, 27, 11, 5.4, -24, -0.6), (16, 28, 22, 8.2, -4, 0.8),
              (11, 29, 8, 5.0, -40, 0.0), (22, 29, 7, 4.6, 36, 0.0)]
    box = (4, 2, 28, 29) if mode == "tile" else (1, 0, 31, 31)
    for bx, by, H, W, ang, tl in _fit_prisms(prisms, box):
        _prism(cv, bx, by, H, W, ang, P, tl)
    sx, sy = (14, 10) if mode == "tile" else (13, 7)
    cv.spark(sx, sy, P["white"], P["hi"], 1)
    cv.shadow()
    cv.halo(lch(72, 90, 62), 2.2, 0.62, lch(50, 84, 48))
    return cv.sprite()


def _fit_prisms(pts, box):
    """Уложить веер призм в box: считаем их крайние точки как у лезвий и масштабируем."""
    xs, ys = [], []
    for bx, by, H, W, ang, tl in pts:
        for p in rot([(-W / 2, 0), (W / 2, 0), (tl, -H)], ang):
            xs.append(bx + p[0])
            ys.append(by + p[1])
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    s = min((box[2] - box[0]) / (x1 - x0), (box[3] - box[1]) / (y1 - y0))
    ox = box[0] + ((box[2] - box[0]) - (x1 - x0) * s) / 2 - x0 * s
    oy = box[1] + ((box[3] - box[1]) - (y1 - y0) * s) / 2 - y0 * s
    return [(bx * s + ox, by * s + oy, H * s, W * s, ang, tl * s) for bx, by, H, W, ang, tl in pts]


TILES["ore_geocrystal"] = lambda: _geocrystal("tile")
ICONS["geocrystal"] = lambda: _geocrystal("icon")


# ── древний металл: плоская гравированная плита-патина с заклёпками и золотыми рунами ──

def _plate(cv, pts, P, runes=True, rivets=True):
    """Плита с толщиной (тёмный торец справа-снизу), фаской света сверху-слева, заклёпками, рунами и потёками патины."""
    face = poly_mask(pts)
    side = poly_mask([(x + 1.6, y + 2.0) for x, y in pts]) | poly_mask([(x + 0.8, y + 1.0) for x, y in pts])
    cv.fill(side & ~face, P["deep"])
    cv.fill(face, P["base"])
    ys, xs = np.nonzero(face)
    # потёки патины сверху вниз и светлая окисная крапа
    rng = cv.rng
    for _ in range(9):
        i = rng.randrange(len(ys))
        x, y = xs[i], ys[i]
        for dy in range(rng.randint(2, 5)):
            if face[min(y + dy, G - 1), x]:
                cv.put(x, y + dy, P["green"])
                if dy == 0 and x + 1 < G and face[y, x + 1]:
                    cv.put(x + 1, y, tone(P["green"], -8))
    cv.speckle(face, [P["light"], P["shade"]], 14)
    cv.rim(face, P["hi"], P["shade"], 0.8, 0.6, bottom=False)
    cv.ring(face | side, P["out"])
    return face


def _ancient_metal(mode):
    cv = Cv("ancient_metal")
    P = {
        "out": lch(14, 24, 60), "deep": lch(26, 30, 76), "shade": lch(36, 36, 80), "base": lch(46, 40, 82),
        "light": lch(58, 42, 86), "hi": lch(74, 34, 92), "green": lch(52, 40, 158),
        "rune": lch(88, 78, 92), "rune2": lch(64, 66, 76), "bolt": lch(82, 22, 90),
    }
    k = 0.93 if mode == "tile" else 1.1

    def S(pts, ang=0.0, c=(16, 16)):
        pts = rot(pts, ang, c)
        return [(16 + (x - 16.2) * k, 16 + (y - 18.0) * k) for x, y in pts]

    # малая плита-обломок позади (справа-снизу) и большая плита впереди с отколотым углом
    _plate(cv, S([(15, 19), (27, 17), (29, 24), (18, 27)], 6), P)
    big_pts = S([(4, 9), (21, 7), (25, 11), (24, 12), (22, 22), (6, 24), (3, 20)], -4)
    _plate(cv, big_pts, P)
    # заклёпки в углах лицевой стороны
    for (x, y) in ((6.5, 11), (21.5, 10), (7.5, 21.5), (21, 20)):
        X, Y = S([(x, y)], -4)[0]
        cv.put(X, Y, P["bolt"])
        cv.put(X + 1, Y + 1, P["deep"])
    # руны: кольцо с чертой и значки, золото и тёмная кромка под ним
    glyphs = [
        [(11, 13), (12, 12), (13, 12), (14, 13), (14, 14), (13, 15), (12, 15), (11, 14)],
        [(17, 11), (17, 12), (17, 13), (17, 14), (17, 15), (18, 13), (16, 13)],
        [(10, 18), (11, 17), (12, 18), (13, 17), (14, 18)],
        [(18, 18), (19, 17), (19, 19), (20, 18)],
    ]
    for g in glyphs:
        for (x, y) in S(g, -4):
            cv.put(round(x), round(y) + 1, P["rune2"])
        for (x, y) in S(g, -4):
            cv.put(round(x), round(y), P["rune"])
    for (x, y) in S([(26, 20), (6, 15)], 0):
        cv.put(round(x), round(y), P["hi"])
    cv.shadow()
    return cv.sprite()


TILES["ore_ancient_metal"] = lambda: _ancient_metal("tile")
ICONS["ancient_metal"] = lambda: _ancient_metal("icon")


# ── адский камень: тёмные красно-чёрные глыбы со светящимися разломами; камень, а не лава ──

def _crack(cv, pts, P, inside):
    """Трещина из ломаной: красная кромка, оранжевая середина, жёлто-белое ядро. Свечение подкрашивает соседей
    внутри камня (inside — маска), чтобы разлом «светил» в породу."""
    wide = np.zeros((G, G), dtype=bool)
    for a, b in zip(pts, pts[1:]):
        steps = int(max(abs(b[0] - a[0]), abs(b[1] - a[1]))) * 2 + 1
        for i in range(steps + 1):
            t = i / steps
            x, y = round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t)
            if 0 <= x < G and 0 <= y < G:
                wide[y, x] = True
    near = (_shift(wide, 1, 0) | _shift(wide, -1, 0) | _shift(wide, 0, 1) | _shift(wide, 0, -1)) & ~wide & inside
    for y, x in zip(*np.nonzero(near)):
        cv.put(x, y, mix(tuple(cv.a[y, x][:3]), P["red"], 0.55))
    for y, x in zip(*np.nonzero(wide & inside)):
        cv.put(x, y, P["orange"])
    # ядро — каждый второй пиксель ломаной
    for a, b in zip(pts, pts[1:]):
        mx, my = round((a[0] + b[0]) / 2), round((a[1] + b[1]) / 2)
        cv.put(mx, my, P["yellow"])
        cv.put(round(a[0]), round(a[1]), P["yellow"])
    return wide


def _hellstone(mode):
    cv = Cv("hellstone")
    P = {
        "out": lch(2, 16, 28), "deep": lch(3, 16, 28), "shade": lch(6, 22, 28), "base": lch(10, 30, 30),
        "lit": lch(17, 40, 32), "rim": lch(46, 68, 40),
        "red": lch(40, 80, 40), "orange": lch(66, 92, 58), "yellow": lch(88, 78, 88), "white": lch(97, 20, 95),
    }
    rocks = [
        # силуэт, свет (верх-лево), тень (право-низ)
        ([(5, 14), (10, 8), (17, 6), (22, 10), (23, 19), (18, 25), (9, 25), (5, 20)],
         [(5, 14), (10, 8), (17, 6), (13, 12), (7, 17)], [(22, 10), (23, 19), (18, 25), (14, 18), (18, 11)]),
        ([(19, 15), (25, 12), (29, 17), (28, 24), (21, 27), (18, 21)],
         [(19, 15), (25, 12), (27, 15), (22, 18)], [(29, 17), (28, 24), (21, 27), (22, 21)]),
        ([(3, 22), (8, 20), (12, 24), (10, 29), (4, 28)],
         [(3, 22), (8, 20), (9, 23), (5, 25)], [(12, 24), (10, 29), (7, 27)]),
    ]
    k = 0.92 if mode == "tile" else 1.04

    def S(pts):
        return [(16 + (x - 16) * k, 16.5 + (y - 16.5) * k) for x, y in pts]

    rocks = [(S(a), S(b), S(c)) for a, b, c in rocks]
    cracks = [S(c) for c in (
        [(13, 9), (14, 13), (12, 16), (14, 20), (12, 24)],
        [(14, 13), (18, 14), (20, 17)],
        [(24, 14), (23, 18), (25, 22)],
        [(6, 22), (8, 26)],
    )]
    masks = []
    for sil, lit, dark in rocks:
        m = poly_mask(sil)
        masks.append(m)
        cv.fill(m, P["base"])
        cv.fill(poly_mask(lit) & m, P["lit"])
        cv.fill(poly_mask(dark) & m, P["shade"])
        # зернистость и мелкие сколы
        cv.speckle(m, [P["deep"], P["shade"]], 14)
        cv.speckle(poly_mask(lit) & m, [P["lit"], tone(P["lit"], 6)], 5)
        cv.rim(m, P["rim"], P["red"], 0.55, 0.5)
        cv.ring(m, P["out"])
    union = masks[0] | masks[1] | masks[2]
    for pts in cracks:
        _crack(cv, pts, P, union)
    # щели между глыбами и искры-угольки
    for (x, y) in ((17, 10), (19, 22), (11, 27), (26, 11)):
        cv.put(x, y, P["orange"])
    for (x, y) in ((8, 5), (24, 6), (29, 9)):
        cv.put(x, y, P["yellow"])
    cv.put(12, 3, P["red"])
    cv.shadow(c=(14, 3, 2), a=150)
    cv.halo(lch(56, 92, 44), 2.2, 0.6, lch(36, 80, 36))
    return cv.sprite()


TILES["ore_hellstone"] = lambda: _hellstone("tile")
ICONS["hellstone"] = lambda: _hellstone("icon")


# ── божественное сердце: розово-красное хрустальное сердце с золотой филигранью и ореолом ──

def _erode(m, n=1):
    for _ in range(n):
        m = m & _shift(m, 1, 0) & _shift(m, -1, 0) & _shift(m, 0, 1) & _shift(m, 0, -1)
    return m


def _divine_heart(mode):
    cv = Cv("divine_heart")
    P = {
        "out": lch(28, 58, 356), "deep": lch(42, 72, 1), "shade": lch(52, 80, 3), "base": lch(62, 80, 5),
        "light": lch(74, 64, 3), "hi": lch(88, 30, 0), "spec": lch(97, 6, 0),
        "gold": lch(84, 76, 88), "gold2": lch(68, 68, 80), "goldhi": lch(96, 32, 96),
    }
    k = 0.86 if mode == "tile" else 1.06
    cx, cy = 16.0, 16.5
    left = ell_mask(cx - 5.2 * k, cy - 4.6 * k, 6.4 * k, 6.0 * k, -20)
    right = ell_mask(cx + 5.2 * k, cy - 4.6 * k, 6.4 * k, 6.0 * k, 20)
    body = poly_mask([(cx - 10.8 * k, cy - 2.6 * k), (cx + 10.8 * k, cy - 2.6 * k), (cx + 1.0 * k, cy + 11.4 * k), (cx - 1.0 * k, cy + 11.4 * k)])
    m = left | right | body
    cv.fill(m, P["base"])
    # грани: левая половина светлее, правая в тени, нижнее остриё темнее; центральный шов
    ys, xs = np.nonzero(m)
    for y, x in zip(ys, xs):
        d = (x - cx) * 0.55 + (y - cy) * 0.35
        if x < cx - 0.5:
            cv.put(x, y, P["light"] if d < -3.2 else P["base"])
        elif x > cx + 0.5:
            cv.put(x, y, P["shade"] if d > 2.2 else P["base"])
    lower = poly_mask([(cx - 9 * k, cy + 3 * k), (cx + 9 * k, cy + 3 * k), (cx, cy + 12 * k)]) & m
    for y, x in zip(*np.nonzero(lower)):
        if x > cx - 1 + (cy + 3 * k - y) * 0.3:
            cv.put(x, y, P["deep"] if x > cx + 1 else P["shade"])
    cv.rim(m, P["hi"], P["light"], 0.75, 0.55, bottom=True)
    cv.ring(m, P["out"])
    # золотая филигрань: пунктир по внутренней кромке, центральная нить и завитки
    inner = _erode(m, 2) & ~_erode(m, 3)
    for i, (y, x) in enumerate(zip(*np.nonzero(inner))):
        if (x + y) % 2 == 0:
            cv.put(x, y, P["gold"])
    jx, jy = round(cx), round(cy - 3.5 * k)
    cv.line((jx, jy + 2), (jx, cy + 8 * k), P["gold2"])
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        cv.put(jx + dx, jy + dy, P["gold"])
    cv.put(jx, jy, P["goldhi"])
    for dy, dx in ((1, -3), (1, 3), (4, -2), (4, 2)):
        cv.put(jx + dx * k, jy + 2 + dy * k, P["gold"])
    # глянец на левой доле
    gx, gy = cx - 6 * k, cy - 7 * k
    cv.put(gx, gy, P["spec"])
    cv.put(gx + 1, gy, P["spec"])
    cv.put(gx, gy + 1, P["spec"])
    cv.put(gx - 1, gy + 1, P["hi"])
    cv.put(gx + 1, gy - 1, P["hi"])
    cv.shadow()
    cv.halo(lch(78, 74, 12), 2.6, 0.7, lch(64, 70, 4))
    for (x, y) in ((4, 5), (28, 6), (27, 26), (5, 27)):
        if cv.a[y, x, 3] < 100:
            cv.spark(x, y, P["goldhi"], P["gold"], 1 if (x + y) % 2 == 0 else 0)
    return cv.sprite()


TILES["ore_divine_heart"] = lambda: _divine_heart("tile")
ICONS["divine_heart"] = lambda: _divine_heart("icon")


# ── добыча монстров (только значки): один предмет по центру, крупный, жирный контур ──

def _cinder_ash():
    """Куча золы с тлеющими угольками и обломками обугленного дерева."""
    cv = Cv("cinder_ash")
    P = {
        "out": lch(14, 8, 40), "deep": lch(22, 6, 50), "shade": lch(34, 6, 55), "base": lch(48, 5, 60),
        "light": lch(64, 4, 70), "hi": lch(78, 3, 80), "ember": lch(62, 92, 52), "ember2": lch(84, 78, 84),
        "red": lch(40, 78, 40), "wood": lch(18, 10, 50), "wood2": lch(30, 14, 50),
    }
    bumps = {5: 1.0, 7: -0.5, 9: 1.0, 12: -1.0, 14: 0.5, 17: -0.5, 20: 1.0, 23: -1.0, 25: 0.5}
    mound = np.zeros((G, G), dtype=bool)
    hts = {}
    for x in range(2, 30):
        u = (x - 15.5) / 14.0
        hts[x] = 15.0 * max(0.0, 1 - u * u) ** 0.62 + bumps.get(x, 0.0)
        mound[int(round(25 - hts[x])):26, x] = True
    tones = [P["deep"], P["shade"], P["base"], P["light"], P["hi"]]
    for y, x in zip(*np.nonzero(mound)):
        # купол: склон слева освещён, справа в тени; глубже под поверхностью — темнее
        slope = (hts.get(x - 1, 0.0) - hts.get(x + 1, 0.0)) / 2.0
        depth = (y - (25 - hts[x])) / 15.0
        v = 2.2 + slope * 0.55 - depth * 2.4 + (0.6 if y < 25 - hts[x] + 1.6 else 0.0)
        j = int(round(v + (cv.rng.random() - 0.5) * 0.9))
        cv.put(x, y, tones[min(max(j, 0), 4)])
    cv.rim(mound, P["hi"], P["shade"], 0.5, 0.4)
    cv.ring(mound, P["out"])
    for (x, y) in ((12, 20), (17, 17), (21, 22), (8, 22), (15, 23), (24, 19)):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if cv.a[y + dy, x + dx, 3]:
                cv.put(x + dx, y + dy, mix(tuple(cv.a[y + dy, x + dx][:3]), P["red"], 0.8))
        cv.put(x, y, P["ember"])
    for (x, y) in ((17, 17), (12, 20), (21, 22)):
        cv.put(x, y, P["ember2"])
    for (x, y, c) in ((14, 7, "light"), (15, 4, "base"), (13, 9, "shade"), (18, 2, "shade"), (6, 8, "base"), (26, 5, "shade")):
        cv.put(x, y, P[c], 200)
    cv.shadow()
    return cv.sprite()


def _moth_dust():
    """Склянка с пробкой: внутри горка светящейся сине-фиолетовой пыльцы, мерцающие пылинки вокруг."""
    cv = Cv("moth_dust")
    P = {
        "out": lch(16, 40, 300), "glass": lch(86, 10, 285), "glass2": lch(68, 18, 290), "cork": lch(52, 30, 62),
        "cork2": lch(36, 28, 56), "cork3": lch(66, 30, 70),
        "d0": lch(30, 62, 305), "d1": lch(46, 76, 302), "d2": lch(64, 66, 298), "d3": lch(84, 40, 290),
        "spec": lch(98, 6, 270),
    }
    body = ell_mask(15.5, 20, 9.2, 8.6)
    neck = poly_mask([(13, 9), (18, 9), (19, 14), (12, 14)])
    glass = body | neck
    cv.fill(glass, P["glass"])
    cv.fill(glass & ~ell_mask(14.5, 19.2, 8.2, 7.6), P["glass2"])
    inside = ell_mask(15.5, 20.2, 7.4, 7.0)
    for y, x in zip(*np.nonzero(inside)):
        top = 17.0 + abs(x - 15.0) * 0.55           # горка с вершиной у центра
        if y >= top:
            d = (y - top) / 7.0
            i = 3 if (y - top < 1.2 and abs(x - 15.0) < 4) else (2 if d < 0.3 else (1 if d < 0.65 else 0))
            if cv.rng.random() < 0.22:
                i = min(i + 1, 3)
            cv.put(x, y, P[f"d{i}"])
    for (x, y) in ((11, 20), (14, 23), (19, 22), (16, 19), (21, 24), (12, 25), (17, 25), (15, 21)):
        cv.put(x, y, P["d3"])
    cv.put(15, 17, P["spec"])
    cv.rim(glass, P["spec"], None, 0.8)
    cv.ring(glass, P["out"])
    for (x, y) in ((10, 17), (10, 18), (11, 16)):
        cv.put(x, y, P["spec"])
    cork = poly_mask([(12, 5), (19, 5), (20, 9), (11, 9)])
    cv.fill(cork, P["cork"])
    cv.fill(poly_mask([(12, 5), (14, 5), (13, 9), (11, 9)]), P["cork3"])
    cv.fill(poly_mask([(18, 5), (19, 5), (20, 9), (18, 9)]), P["cork2"])
    cv.ring(cork, P["out"])
    for (x, y, c) in ((10, 3, "d2"), (21, 2, "d3"), (24, 8, "d2"), (6, 9, "d1"), (26, 15, "d1"), (4, 22, "d2"), (27, 24, "d3"), (8, 27, "d1"), (24, 28, "d2")):
        cv.put(x, y, P[c])
    cv.spark(23, 4, P["spec"], P["d3"], 1)
    cv.spark(6, 5, P["d3"], P["d2"], 0)
    cv.spark(27, 20, P["d3"], P["d2"], 0)
    cv.shadow()
    cv.halo(lch(58, 78, 302), 2.0, 0.55)
    return cv.sprite()


def _hopper_fang():
    """Изогнутый клык: костяной белый, у основания красная десна, острый кончик."""
    cv = Cv("hopper_fang")
    P = {
        "out": lch(24, 22, 55), "deep": lch(58, 14, 78), "shade": lch(74, 12, 84), "base": lch(86, 10, 90),
        "light": lch(95, 6, 95), "hi": (255, 255, 250), "red": lch(36, 66, 34), "red2": lch(26, 56, 30), "red3": lch(48, 72, 36),
    }
    p0, p1, p2 = (10.0, 5.0), (7.0, 21.0), (25.0, 28.0)
    info = {}
    for i in range(0, 61):
        t = i / 60.0
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        dx = 2 * (1 - t) * (p1[0] - p0[0]) + 2 * t * (p2[0] - p1[0])
        dy = 2 * (1 - t) * (p1[1] - p0[1]) + 2 * t * (p2[1] - p1[1])
        n = math.hypot(dx, dy)
        nx, ny = -dy / n, dx / n
        w = 5.4 * (1 - t) ** 0.85 + 0.35
        for yy in range(G):
            for xx in range(G):
                d = math.hypot(xx - x, yy - y)
                if d <= w:
                    s = ((xx - x) * nx + (yy - y) * ny) / max(w, 0.5)
                    if (xx, yy) not in info or d < info[(xx, yy)][2]:
                        info[(xx, yy)] = (t, s, d)
    m = np.zeros((G, G), dtype=bool)
    for (xx, yy), (t, s, d) in info.items():
        m[yy, xx] = True
        if t < 0.17:
            col = P["red3"] if s < -0.2 else (P["red"] if s < 0.45 else P["red2"])
        else:
            col = P["light"] if s < -0.45 else (P["base"] if s < 0.1 else (P["shade"] if s < 0.6 else P["deep"]))
        cv.put(xx, yy, col)
    for (xx, yy), (t, s, d) in info.items():
        if 0.17 <= t < 0.23:
            cv.put(xx, yy, mix(tuple(cv.a[yy, xx][:3]), P["red3"], 0.4))
    cv.rim(m, P["hi"], None, 0.35)
    cv.ring(m, P["out"])
    cv.put(24, 27, P["hi"])
    cv.line((13, 9), (9, 17), P["hi"])
    cv.shadow()
    return cv.sprite()


def _blob(cx, cy, radii, rot=0.0):
    """Неровный овал-валун: радиусы по кругу через равные углы (рваный край)."""
    n = len(radii)
    return [(cx + r * math.cos(math.radians(rot + i * 360.0 / n)), cy + r * math.sin(math.radians(rot + i * 360.0 / n)))
            for i, r in enumerate(radii)]


def _mimic_geode():
    """Расколотая жеода: бугристая серая корка, светлая агатовая полоска и пещерка с аметистом и голубыми кристаллами."""
    cv = Cv("mimic_geode")
    P = {
        "out": lch(14, 8, 60), "rock0": lch(26, 8, 62), "rock1": lch(40, 9, 66), "rock2": lch(54, 9, 70), "rock3": lch(67, 8, 76),
        "band": lch(80, 10, 80), "band2": lch(58, 12, 72), "cav": lch(12, 36, 305),
        "a0": lch(26, 58, 308), "a1": lch(42, 68, 308), "a2": lch(58, 62, 306), "a3": lch(78, 40, 300),
        "c0": lch(46, 40, 218), "c1": lch(62, 38, 214), "c2": lch(78, 30, 208), "c3": lch(92, 12, 205), "spec": lch(98, 4, 250),
    }
    outer = poly_mask(_blob(15.5, 17, [13.5, 12, 13, 12.5, 13.8, 12.3, 12.8, 13.6, 12.2, 13.2], 8))
    cv.fill(outer, P["rock2"])
    for y, x in zip(*np.nonzero(outer)):
        d = (x - 8) * 0.55 + (y - 7) * 0.8
        cv.put(x, y, P["rock3"] if d < 3 else (P["rock2"] if d < 13 else (P["rock1"] if d < 20 else P["rock0"])))
    cv.speckle(outer, [P["rock1"], P["rock3"], P["rock0"]], 26)
    cv.rim(outer, P["spec"], P["rock0"], 0.5, 0.4, bottom=True)
    cv.ring(outer, P["out"])
    band = poly_mask(_blob(15.5, 17.4, [10.6, 9.4, 10.2, 9.8, 10.8, 9.6, 10.0, 10.6, 9.4, 10.4], 14))
    cv.fill(band, P["band"])
    cv.fill(band & ~ell_mask(14.5, 16.4, 9.2, 8.6), P["band2"])
    cav = poly_mask(_blob(15.5, 17.6, [8.6, 7.4, 8.2, 7.8, 8.8, 7.5, 8.0, 8.6, 7.4, 8.4], 20))
    cv.fill(cav, P["cav"])
    cv.ring(cav, P["band2"])

    def spike(bx, by, ln, w, ang, c0, c1, c2):
        b = blade(bx, by, ln, w, ang, 0.0, 0.7, 0.5, 0.05)
        sil = poly_mask([b["BL"], b["KL"], b["T"], b["KR"], b["BR"]]) & cav
        cv.fill(sil, c1)
        cv.fill(poly_mask([b["BL"], b["KL"], b["T"], b["M"]]) & sil, c2)
        cv.fill(poly_mask([b["KR"], b["BR"], b["M"], b["T"]]) & sil, c0)
        cv.put(b["T"][0], b["T"][1] + 1, P["spec"])

    spike(19, 24, 13, 5.2, 14, P["a0"], P["a1"], P["a2"])
    spike(13, 25, 11, 4.8, -16, P["a0"], P["a1"], P["a3"])
    spike(23, 22, 7, 4.0, 42, P["a0"], P["a1"], P["a2"])
    spike(8.5, 22, 8, 3.8, -46, P["c0"], P["c1"], P["c2"])
    spike(16, 25, 6, 3.6, 3, P["c0"], P["c1"], P["c3"])
    cv.spark(21, 12, P["spec"], P["a3"], 1)
    cv.put(11, 13, P["c3"])
    cv.shadow()
    return cv.sprite()


def _bolt(cv, p0, p1, col, col2, rng, jag=2.0, steps=5):
    pts = [p0]
    for i in range(1, steps):
        t = i / steps
        pts.append((p0[0] + (p1[0] - p0[0]) * t + rng.uniform(-jag, jag), p0[1] + (p1[1] - p0[1]) * t + rng.uniform(-jag, jag)))
    pts.append(p1)
    cv.poly_line([(round(x) + 1, round(y)) for x, y in pts], col2, 150)
    cv.poly_line(pts, col)


def _spark_core():
    """Жёлто-белая электрическая сфера с дугами разрядов."""
    cv = Cv("spark_core")
    P = {
        "out": lch(34, 60, 70), "a": lch(52, 82, 66), "b": lch(70, 90, 78), "c": lch(88, 70, 92), "d": lch(97, 16, 98),
        "blue": lch(84, 34, 225),
    }
    cx = cy = 15.5
    sphere(cv, cx, cy, 6.8, [P["a"], P["b"], P["c"], P["d"]], light=(-0.25, -0.3), bias=0.1)
    cv.ring(ell_mask(cx, cy, 6.8, 6.8), P["out"])
    rng = random.Random(11)
    for ang, ln in ((-70, 15.0), (-5, 15.0), (60, 14.5), (125, 15.0), (-140, 14.0), (190, 13.0)):
        a = math.radians(ang)
        p0 = (cx + math.cos(a) * 7.4, cy + math.sin(a) * 7.4)
        p1 = (cx + math.cos(a) * ln, cy + math.sin(a) * ln)
        _bolt(cv, p0, p1, (255, 255, 240), P["blue"], rng, 2.3, 6)
    for (x, y) in ((12, 12), (13, 12), (12, 13)):
        cv.put(x, y, (255, 255, 255))
    cv.halo(lch(86, 80, 90), 2.4, 0.6, lch(60, 84, 70))
    return cv.sprite()


def _warden_plate():
    """Бронепластина стража: тёмная сталь, фаска, заклёпки, оранжевая светящаяся руна."""
    cv = Cv("warden_plate")
    P = {
        "out": lch(8, 14, 255), "s0": lch(18, 14, 255), "s1": lch(28, 16, 252), "s2": lch(42, 14, 248), "s3": lch(58, 12, 245),
        "hi": lch(80, 8, 240), "rune": lch(70, 95, 55), "rune2": lch(92, 70, 85), "rune3": lch(48, 84, 42), "bolt": lch(66, 10, 245),
    }
    shape = [(6, 5), (25, 4), (29, 9), (28, 21), (17, 29), (4, 22), (3, 10)]
    m = poly_mask(shape)
    cv.fill(m, P["s1"])
    inner = poly_mask([(9, 8), (23, 7), (26, 11), (25, 20), (16, 26), (7, 20), (6, 12)])
    cv.fill(poly_mask([(6, 5), (25, 4), (23, 7), (9, 8)]) | poly_mask([(6, 5), (3, 10), (6, 12), (9, 8)]), P["s3"])
    cv.fill(poly_mask([(25, 4), (29, 9), (26, 11), (23, 7)]), P["s2"])
    cv.fill(poly_mask([(29, 9), (28, 21), (25, 20), (26, 11)]) | poly_mask([(28, 21), (17, 29), (16, 26), (25, 20)]), P["s0"])
    cv.fill(poly_mask([(3, 10), (4, 22), (7, 20), (6, 12)]) | poly_mask([(4, 22), (17, 29), (16, 26), (7, 20)]), P["s1"])
    cv.fill(inner, P["s1"])
    for y, x in zip(*np.nonzero(inner)):
        if (x - 12) + (y - 10) * 0.8 < -2:
            cv.put(x, y, P["s2"])
    cv.speckle(inner, [P["s0"], P["s2"]], 10)
    cv.rim(m, P["hi"], P["s2"], 0.8, 0.4)
    cv.ring(m, P["out"])
    for (x, y) in ((8, 7), (24, 6), (8, 21), (25, 15)):
        cv.put(x, y, P["bolt"])
        cv.put(x + 1, y + 1, P["s0"])
    rune = [(16, 10), (16, 11), (16, 12), (16, 13), (16, 14), (16, 15), (16, 16), (16, 17), (16, 18), (16, 19),
            (14, 12), (15, 11), (18, 12), (17, 11), (14, 16), (15, 17), (17, 17), (18, 16), (15, 20), (17, 20)]
    glow = np.zeros((G, G), dtype=bool)
    for (x, y) in rune:
        glow[y, x] = True
    near = (_shift(glow, 1, 0) | _shift(glow, -1, 0) | _shift(glow, 0, 1) | _shift(glow, 0, -1)) & ~glow & inner
    for y, x in zip(*np.nonzero(near)):
        cv.put(x, y, mix(tuple(cv.a[y, x][:3]), P["rune3"], 0.55))
    for (x, y) in rune:
        cv.put(x, y, P["rune"])
    for y in range(12, 17):
        cv.put(16, y, P["rune2"])
    cv.shadow()
    cv.halo(lch(60, 90, 50), 1.6, 0.45)
    return cv.sprite()


def _abyss_core():
    """Индиго-чёрный шар с голубыми вихрями: спиральные рукава к центру, холодный ободок."""
    cv = Cv("abyss_core")
    P = {
        "out": lch(2, 14, 292), "t0": lch(1, 8, 292), "t1": lch(3, 18, 292), "t2": lch(6, 26, 292), "t3": lch(11, 34, 291),
        "w0": lch(44, 58, 240), "w1": lch(64, 52, 226), "w2": lch(88, 24, 214), "rim": lch(40, 56, 262),
    }
    cx = cy = 15.5
    r = 12.0
    m = sphere(cv, cx, cy, r, [P["t0"], P["t1"], P["t2"], P["t3"]], light=(-0.45, -0.55), bias=0.5)
    for arm in range(3):
        a0 = arm * (math.tau / 3) + 0.4
        prev = None
        for i in range(60):
            t = i / 59.0
            rad = r * 0.92 * (1 - t) ** 0.9
            ang = a0 + t * 4.2
            pt = (round(cx + rad * math.cos(ang)), round(cy + rad * math.sin(ang) * 0.95))
            if pt != prev and 0 <= pt[0] < G and 0 <= pt[1] < G and m[pt[1], pt[0]]:
                cv.put(pt[0], pt[1], P["w2"] if t > 0.72 else (P["w1"] if t > 0.4 else P["w0"]))
            prev = pt
    cv.put(15, 15, P["w2"])
    cv.put(16, 16, P["w2"])
    cv.rim(m, P["rim"], P["t3"], 0.7, 0.6, bottom=True)
    cv.ring(m, P["out"])
    for (x, y) in ((10, 9), (11, 8), (9, 11)):
        cv.put(x, y, P["w2"])
    cv.shadow()
    cv.halo(lch(42, 66, 266), 2.4, 0.55)
    return cv.sprite()


def _idol_shard():
    """Осколок резной статуи: песчаный камень, скол, канавки резьбы, бирюзовая светящаяся руна."""
    cv = Cv("idol_shard")
    P = {
        "out": lch(16, 14, 70), "s0": lch(32, 12, 72), "s1": lch(48, 12, 76), "s2": lch(62, 12, 82), "s3": lch(76, 10, 88),
        "hi": lch(88, 6, 92), "g": lch(26, 14, 66), "rune": lch(82, 62, 190), "rune2": lch(96, 22, 190), "rune3": lch(52, 54, 196),
    }
    shape = [(9, 4), (20, 3), (26, 8), (28, 16), (24, 20), (26, 27), (13, 29), (7, 24), (5, 14)]
    m = poly_mask(shape)
    cv.fill(m, P["s2"])
    for y, x in zip(*np.nonzero(m)):
        d = (x - 9) * 0.5 + (y - 5) * 0.9
        cv.put(x, y, P["s3"] if d < 2.5 else (P["s2"] if d < 12 else (P["s1"] if d < 19 else P["s0"])))
    cv.fill(poly_mask([(28, 16), (24, 20), (26, 27), (13, 29), (18, 24), (22, 18)]) & m, P["s0"])
    cv.speckle(m, [P["s1"], P["s3"]], 20)
    for pts in ([(9, 8), (21, 7), (24, 11)], [(9, 8), (8, 20)], [(11, 11), (19, 11)], [(11, 11), (11, 18)]):
        cv.poly_line(pts, P["g"])
    cv.poly_line([(10, 9), (20, 8), (23, 12)], P["hi"], 160)
    cv.rim(m, P["hi"], P["s1"], 0.7, 0.3)
    cv.ring(m, P["out"])
    rune = [(16, 12), (16, 13), (16, 14), (16, 15), (16, 16), (14, 13), (15, 12), (18, 13), (17, 12), (14, 17), (15, 16), (17, 16), (18, 17), (15, 18), (17, 18)]
    glow = np.zeros((G, G), dtype=bool)
    for (x, y) in rune:
        glow[y, x] = True
    near = (_shift(glow, 1, 0) | _shift(glow, -1, 0) | _shift(glow, 0, 1) | _shift(glow, 0, -1)) & ~glow & m
    for y, x in zip(*np.nonzero(near)):
        cv.put(x, y, mix(tuple(cv.a[y, x][:3]), P["rune3"], 0.6))
    for (x, y) in rune:
        cv.put(x, y, P["rune"])
    for y in range(13, 16):
        cv.put(16, y, P["rune2"])
    cv.shadow()
    cv.halo(lch(76, 62, 190), 1.8, 0.5)
    return cv.sprite()


ICONS["cinder_ash"] = _cinder_ash
ICONS["moth_dust"] = _moth_dust
ICONS["hopper_fang"] = _hopper_fang
ICONS["mimic_geode"] = _mimic_geode
ICONS["spark_core"] = _spark_core
ICONS["warden_plate"] = _warden_plate
ICONS["abyss_core"] = _abyss_core
ICONS["idol_shard"] = _idol_shard

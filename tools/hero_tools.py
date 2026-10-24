"""hero_tools.py — инструменты и снаряжение мальчика в его родной сетке
(4 пикселя рисунка на точку), для tools/gen_hero_ref.py.

Рисуются кодом, в стиле эталона: тёмный контур в пиксель, 3–5 тонов на
материал, свет сверху-слева, без сглаживания. Каждый спрайт задан «стоя»
(рукоять вертикально, головка вверху) с точкой хвата; в кадр он ставится
поворотом hero_puppet.rotate вокруг хвата — тем же RotSprite, что и руки.
"""

import math

import numpy as np

import hero_puppet as hp


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255], np.uint8)


RAMPS = {
    # контур, тень, тон, свет, блик
    "steel": ["22242c", "4e5462", "7c8494", "b0b8c6", "e2e8f0"],
    "dark_steel": ["1c1e24", "3a3e48", "586070", "7c8494", "a8b0bc"],
    "wood": ["3a2216", "6e4428", "925e38", "b47c4c", "cc9a64"],
    "rust": ["3a1c10", "7a3a1a", "a45626", "c87a3a", "e2a466"],
    "dirt": ["2e2016", "5a3e28", "7a583a", "9a7650", "b89068"],
    "olive": ["22261a", "4a5230", "667040", "828c52", "a0aa6a"],
    "canvas": ["3a2c1a", "7a6040", "9c7e54", "bc9c6c", "d8bc8c"],
    "red": ["3a0e10", "84202a", "b03a3a", "d65a4a", "f08a6a"],
    "flame": ["8a2a08", "d0561a", "f08a24", "fcc040", "fff0a0"],
    "jet": ["1a3050", "3a70b8", "6aa8ee", "a8d8ff", "f2fbff"],
}
RAMPS = {k: [rgb(c) for c in v] for k, v in RAMPS.items()}


class Canvas:
    def __init__(self, w, h):
        self.img = np.zeros((h, w, 4), np.uint8)
        self.mat = np.full((h, w), -1, int)       # номер слоя (для контура)

    def put(self, x, y, c):
        if 0 <= x < self.img.shape[1] and 0 <= y < self.img.shape[0]:
            self.img[y, x] = c


def capsule(cv, p0, p1, r, ramp, light=(-0.7, -0.7)):
    """Толстый отрезок с тенью поперёк (свет — сверху-слева)."""
    h, w = cv.img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    px, py = xx + 0.5, yy + 0.5
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L2 = max(1e-6, dx * dx + dy * dy)
    t = np.clip(((px - p0[0]) * dx + (py - p0[1]) * dy) / L2, 0, 1)
    cx, cy = p0[0] + t * dx, p0[1] + t * dy
    ex, ey = px - cx, py - cy
    d = np.hypot(ex, ey)
    body = d <= r
    nl = math.hypot(*light)
    side = (ex * light[0] + ey * light[1]) / (nl * max(r, 1e-6))
    tone = np.clip(np.round(2 + side * 1.6), 1, 4).astype(int)
    for k in range(1, 5):
        m = body & (tone == k)
        cv.img[m] = ramp[k]
    return body


def outline(img, color):
    """Тёмный контур снаружи непрозрачного (по 4 соседям)."""
    a = img[..., 3] > 0
    ring = hp.neighbors4(a) & ~a
    img[ring] = color
    return img


def blob(cv, cx, cy, rx, ry, ramp):
    h, w = cv.img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    u = (xx + 0.5 - cx) / rx
    v = (yy + 0.5 - cy) / ry
    d = u * u + v * v
    body = d <= 1.0
    side = -(u + v) * 0.7
    tone = np.clip(np.round(2 + side * 1.4), 1, 4).astype(int)
    for k in range(1, 5):
        m = body & (tone == k)
        cv.img[m] = ramp[k]
    return body


# ---------------------------------------------------------------------------
# Кирка: рукоять 58 px, головка — изогнутая полоса ⌒ шириной 46 px
# ---------------------------------------------------------------------------

PICK_W, PICK_H = 60, 76
PICK_GRIP = (30.0, 66.0)      # ближняя рука; дальняя — на 10 px выше по рукояти


def pickaxe(metal="steel", cracked=False):
    cv = Canvas(PICK_W, PICK_H)
    capsule(cv, (30, 14), (30, 73), 2.2, RAMPS["wood"])
    head = Canvas(PICK_W, PICK_H)
    pts = []
    for i in range(41):
        t = i / 40.0
        a = math.radians(208 + 124 * t)
        pts.append((t, 30 + 25 * math.cos(a), 30 + 21 * math.sin(a)))
    for t, x, y in pts:
        r = 0.9 + 3.0 * math.sin(math.pi * t) ** 0.8
        capsule(head, (x, y), (x, y), r, RAMPS[metal], light=(-0.2, -1.0))
    # втулка на рукояти
    capsule(head, (30, 9), (30, 15), 3.6, RAMPS["dark_steel" if metal == "steel" else metal])
    m = head.img[..., 3] > 0
    cv.img[m] = head.img[m]
    if cracked:
        for x, y in ((22, 10), (23, 11), (23, 12), (24, 13)):
            cv.put(x, y, RAMPS[metal][0])
    outline(cv.img, RAMPS["wood"][0] if False else RAMPS[metal][0])
    return cv.img


# ---------------------------------------------------------------------------
# Лопата: Т-ручка сверху, черенок, лоток снизу
# ---------------------------------------------------------------------------

SHOVEL_W, SHOVEL_H = 30, 84
SHOVEL_GRIP = (15.0, 34.0)    # ближняя рука; дальняя — на Т-ручке (15, 5)
SHOVEL_TOP = (15.0, 5.0)


def shovel():
    cv = Canvas(SHOVEL_W, SHOVEL_H)
    capsule(cv, (15, 6), (15, 60), 2.0, RAMPS["wood"])
    capsule(cv, (9, 4), (21, 4), 1.8, RAMPS["wood"])
    blade = Canvas(SHOVEL_W, SHOVEL_H)
    h, w = blade.img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    px, py = xx + 0.5, yy + 0.5
    # лоток: трапеция с закруглённым низом
    top, bot = 56.0, 82.0
    half = 6.5 + (py - top) / (bot - top) * 3.0
    round_ = (py - (bot - 7)) / 7.0
    half = np.where(py > bot - 7, half * np.sqrt(np.clip(1 - round_ ** 2, 0, 1)), half)
    body = (py >= top) & (py <= bot) & (np.abs(px - 15) <= half)
    tone = np.clip(np.round(2.6 - (px - 15) / 4.0 + (py - top) / 30.0), 1, 4).astype(int)
    for k in range(1, 5):
        blade.img[body & (tone == k)] = RAMPS["steel"][k]
    capsule(blade, (15, 55), (15, 61), 2.6, RAMPS["dark_steel"])
    m = blade.img[..., 3] > 0
    cv.img[m] = blade.img[m]
    outline(cv.img, RAMPS["steel"][0])
    return cv.img


# ---------------------------------------------------------------------------
# Ручной бур: корпус с мотором, две рукояти, винтовое сверло
# ---------------------------------------------------------------------------

DRILL_W, DRILL_H = 40, 64
DRILL_GRIP_N = (6.0, 16.0)     # ближняя рукоять
DRILL_GRIP_F = (34.0, 16.0)    # дальняя рукоять


def drill(phase):
    """Бур «стоя»: корпус сверху, сверло вниз. phase 0..7 — поворот винта."""
    cv = Canvas(DRILL_W, DRILL_H)
    capsule(cv, (5, 16), (35, 16), 2.0, RAMPS["dark_steel"])
    h, w = cv.img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    px, py = xx + 0.5, yy + 0.5
    body = (np.abs(px - 20) <= 8) & (py >= 4) & (py <= 32)
    tone = np.clip(np.round(2.8 - (px - 20) / 4.0), 1, 4).astype(int)
    for k in range(1, 5):
        cv.img[body & (tone == k)] = RAMPS["red"][k]
    band = body & (py >= 18) & (py <= 23)
    for k in range(1, 5):
        cv.img[band & (tone == k)] = RAMPS["dark_steel"][k]
    vent = body & (py >= 8) & (py <= 13) & ((xx % 3) == 0)
    cv.img[vent] = RAMPS["red"][0]
    chuck = (np.abs(px - 20) <= 4) & (py > 32) & (py <= 37)
    cv.img[chuck] = RAMPS["dark_steel"][2]
    # сверло: конус с винтовыми полосами, полосы сдвигаются по фазе
    bit_top, bit_bot = 37.0, 62.0
    half = 3.6 * (bit_bot - py) / (bit_bot - bit_top)
    bit = (py > bit_top) & (py <= bit_bot) & (np.abs(px - 20) <= half + 0.3)
    stripe = ((py * 0.55 + (px - 20) * 0.45 + phase * 0.5) % 2.0) < 0.9
    cv.img[bit & stripe] = RAMPS["steel"][4]
    cv.img[bit & ~stripe] = RAMPS["steel"][2]
    outline(cv.img, RAMPS["steel"][0])
    return cv.img


def pebbles(canvas, x, y, n, seed, spread=10, rise=8, ramp=None):
    """Комья породы у удара (с контуром, по 2–3 пикселя)."""
    ramp = ramp or RAMPS["dirt"]
    rng = np.random.default_rng(seed)
    for _ in range(n):
        px = int(round(x + rng.uniform(-spread, spread)))
        py = int(round(y - rng.uniform(0, rise)))
        s = int(rng.integers(1, 3))
        for dy in range(-1, s + 1):
            for dx in range(-1, s + 1):
                yy, xx = py + dy, px + dx
                if 0 <= yy < canvas.shape[0] and 0 <= xx < canvas.shape[1]:
                    inside = 0 <= dy < s and 0 <= dx < s
                    if inside:
                        canvas[yy, xx] = ramp[2 + ((dx + dy) % 2)]
                    elif canvas[yy, xx, 3] == 0:
                        canvas[yy, xx] = ramp[0]


def heap(canvas, x, y, w, h):
    """Горка вынутой земли (основание на строке y)."""
    cv = Canvas(canvas.shape[1], canvas.shape[0])
    blob(cv, x, y, w / 2.0, h, RAMPS["dirt"])
    img = cv.img
    img[int(y) + 1:] = 0
    outline(img, RAMPS["dirt"][0])
    m = img[..., 3] > 0
    canvas[m] = img[m]


def place(canvas, sprite, pivot, angle, dest):
    """Повернуть спрайт вокруг pivot (плюс — по часовой) и положить pivot в dest."""
    rot = hp.rotate(sprite, angle, pivot, dest, canvas.shape[:2])
    hp.over(canvas, rot)


def along(p, angle, dist):
    """Точка на рукояти: от p на dist вверх по рукояти, повёрнутой на angle."""
    a = math.radians(angle)
    return (p[0] + dist * math.sin(a), p[1] - dist * math.cos(a))

#!/usr/bin/env python3
"""gen_sky.py — графика ночного неба: три слоя звёзд, Млечный Путь, восемь фаз луны.

Запуск: python3 tools/gen_sky.py  (Pillow + numpy; результат в art/env/sky/ и art/env/moon.png).

Почему так, а не вырезка из авторского листа (tools/import_stars.py / import_clouds.py, прежний путь):
  * в вырезку месяца попали звёздочки рядом с серпом, а ключ фона по JPEG оставил светлую кайму —
    отсюда «мусор вокруг месяца». Месяц теперь считается с нуля, и фон в нём не участвует вообще;
  * атлас звёзд был набором квадратиков-заплаток разного размера.

Звёздные слои — тайлы, которые шейдер неба (shaders/sky.gdshader) повторяет без швов (периодические
координаты, рисуем «по тору»). Каждый тексель — ДАННЫЕ, а не цвет:
    R — яркость звезды (0 — пусто), G — фаза мерцания, B — цветовая температура (0 холодная .. 1 красноватая).
Картинка непрозрачная (RGB без альфы) — импорт Godot ничего не «исправляет» и не премультиплицирует.
Тексель = полпикселя логической сетки (2 текселя на пиксель): мелкая звезда — точка, а не квадрат.

Млечный Путь — отдельный мягкий тайл того же мирового размера, что и дальний слой звёзд (чтобы полоса
и густота дальних звёзд совпадали): диагональная полоса с пылевыми прожилками и пятнами туманности.

Луна — атлас 8 кадров (новолуние .. убывающий серп) в art/env/moon.png: шар с рельефом (кратеры, моря),
свет по ламберту с мягким терминатором, пепельный свет на тёмной стороне.
"""

import json
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "art", "env", "sky")
MOON_PATH = os.path.join(ROOT, "art", "env", "moon.png")

TEXELS_PER_PX = 2          # тексель звёзд = полпикселя логической сетки
MOON_FRAME = 112           # кадр луны в текселях (ART_SCALE 3 -> ~37 логических px)
MOON_R = 51.0              # радиус диска в текселях (диаметр 34 логических px)

# ---------------------------------------------------------------------------
# Периодический шум (без scipy): сетка случайных значений, сглаженная интерполяция с заворотом
# ---------------------------------------------------------------------------


def pnoise(h, w, cy, cx, rng):
    g = rng.random((cy, cx))
    ys = np.arange(h) * cy / h
    xs = np.arange(w) * cx / w
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = ys - y0
    fx = xs - x0
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    y1, x1 = (y0 + 1) % cy, (x0 + 1) % cx
    y0, x0 = y0 % cy, x0 % cx
    a, b = g[y0][:, x0], g[y0][:, x1]
    c, d = g[y1][:, x0], g[y1][:, x1]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(h, w, cy, cx, octaves, rng, gain=0.5):
    tot = np.zeros((h, w))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        tot += amp * pnoise(h, w, cy * 2 ** o, cx * 2 ** o, rng)
        norm += amp
        amp *= gain
    return tot / norm


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------
# Млечный Путь: диагональная полоса на торе (X + Y = const замыкается ровно)
# ---------------------------------------------------------------------------

# Мировой размер тайла дальнего слоя звёзд (логические px). Читает и шейдер (uniform far_tile_px).
FAR_TILE = (384, 512)
MID_TILE = (320, 448)
NEAR_TILE = (288, 384)


# Где полоса пересекает тайл (X + Y = BAND_U0): подобрано так, чтобы у героя на огороде она шла через видимую
# полоску неба, а не мимо неё.
BAND_U0 = 0.95


def band_field(w, h, rng, warp=0.05):
    """Нормированное расстояние до оси полосы на торе, d в [-.5,.5] (0 — на оси)."""
    ys, xs = np.mgrid[0:h, 0:w]
    X = xs / w
    Y = ys / h
    u = X + Y
    wob = fbm(h, w, 2, 2, 4, rng) - 0.5
    d = ((u - BAND_U0 + warp * 2.0 * wob + 0.5) % 1.0) - 0.5
    return d


def make_milkyway(seed=7):
    rng = np.random.default_rng(seed)
    nw, nh = FAR_TILE[0] // 2, FAR_TILE[1] // 2          # 2 логических px на тексель, шейдер растягивает билинейно
    d = band_field(nw, nh, rng)
    sigma = 0.115
    core = np.exp(-0.5 * (d / sigma) ** 2)
    halo = np.exp(-0.5 * (d / (2.3 * sigma)) ** 2)
    grain = fbm(nh, nw, 5, 4, 5, rng)
    streak = fbm(nh, nw, 9, 7, 4, rng)
    # Пылевые прожилки режут ядро полосы изнутри.
    lane = smoothstep(0.52, 0.70, streak) * np.exp(-0.5 * (d / (0.55 * sigma)) ** 2)
    inten = halo * 0.30 + core * (0.30 + 0.70 * smoothstep(0.25, 0.80, grain))
    inten = inten * (1.0 - 0.65 * lane)

    warm = np.array([1.00, 0.86, 0.74])
    cool = np.array([0.42, 0.50, 0.95])
    k = np.clip(core * (0.4 + 0.6 * grain), 0, 1) ** 1.3
    col = cool[None, None, :] * (1 - k[..., None]) + warm[None, None, :] * k[..., None]
    rgb = col * inten[..., None] * 0.52

    # Пятна туманности вдоль полосы: бирюза, пурпур, синева.
    ys, xs = np.mgrid[0:nh, 0:nw]
    X = xs / nw
    Y = ys / nh
    blobs = [((0.30, 0.28), (0.20, 0.09), (0.10, 0.52, 0.62), 0.20),
             ((0.66, 0.72), (0.17, 0.11), (0.66, 0.20, 0.56), 0.17),
             ((0.52, 0.48), (0.12, 0.07), (0.30, 0.34, 0.80), 0.16),
             ((0.12, 0.86), (0.15, 0.08), (0.16, 0.46, 0.66), 0.13)]
    mod = fbm(nh, nw, 4, 3, 4, rng)
    for (cx, cy), (ax, ay), colr, amp in blobs:
        dx = ((X - cx + 0.5) % 1.0) - 0.5
        dy = ((Y - cy + 0.5) % 1.0) - 0.5
        g = np.exp(-((dx / ax) ** 2 + (dy / ay) ** 2)) * smoothstep(0.30, 0.85, mod)
        rgb += g[..., None] * np.array(colr)[None, None, :] * amp
    img = (np.clip(rgb, 0, 1) * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(img, "RGB")


# ---------------------------------------------------------------------------
# Звёздные слои
# ---------------------------------------------------------------------------

def draw_profile(R, G, B, x, y, prof, peak, phase, temp):
    h, w = R.shape
    for dx, dy, k in prof:
        v = int(round(peak * k))
        if v <= 0:
            continue
        xi, yi = (x + dx) % w, (y + dy) % h
        if v > R[yi, xi]:
            R[yi, xi] = v
            G[yi, xi] = phase
            B[yi, xi] = temp


def prof_dot1():
    return [(0, 0, 1.0)]


def prof_dot2():
    return [(0, 0, 1.0), (1, 0, 0.9), (0, 1, 0.9), (1, 1, 0.78)]


def prof_dot2_soft():
    ring = [(-1, 0), (2, 0), (-1, 1), (2, 1), (0, -1), (1, -1), (0, 2), (1, 2)]
    return prof_dot2() + [(dx, dy, 0.26) for dx, dy in ring]


def prof_cross(arm, diag=0):
    """Звезда с лучами: ядро 2x2, лучи длиной arm текселей, затухающие, лёгкое гало."""
    prof = [(0, 0, 1.0), (1, 0, 1.0), (0, 1, 1.0), (1, 1, 1.0)]
    for i in range(1, arm + 1):
        k = (1.0 - i / (arm + 1.0)) ** 1.5 * 0.78
        prof += [(-i, 0, k), (-i, 1, k), (1 + i, 0, k), (1 + i, 1, k),
                 (0, -i, k), (1, -i, k), (0, 1 + i, k), (1, 1 + i, k)]
    for dx, dy in [(-1, -1), (2, -1), (-1, 2), (2, 2)]:
        prof.append((dx, dy, 0.42))
    for i in range(1, diag + 1):
        k = (1.0 - i / (diag + 1.0)) * 0.34
        prof += [(-1 - i, -1 - i, k), (2 + i, -1 - i, k), (-1 - i, 2 + i, k), (2 + i, 2 + i, k)]
    return prof


def prof_hero(arm=11):
    prof = prof_cross(arm, diag=4)
    for dx in range(-1, 3):
        for dy in range(-1, 3):
            prof.append((dx, dy, 1.0))
    ring = [(-2, 0), (-2, 1), (3, 0), (3, 1), (0, -2), (1, -2), (0, 3), (1, 3)]
    prof += [(dx, dy, 0.5) for dx, dy in ring]
    return prof


def pick_temp(rng):
    r = rng.random()
    if r < 0.22:
        return rng.uniform(0.0, 0.20)      # холодные голубые
    if r < 0.48:
        return rng.uniform(0.20, 0.42)     # бело-голубые
    if r < 0.77:
        return rng.uniform(0.42, 0.62)     # белые
    if r < 0.95:
        return rng.uniform(0.62, 0.82)     # тёплые жёлтые
    return rng.uniform(0.86, 1.0)          # редкие красноватые


def dart_points(w, h, n, min_dist, rng, weight=None, tries=40):
    """n точек на торе w x h не ближе min_dist друг к другу (с весом плотности weight(x,y) в 0..1)."""
    pts = np.zeros((0, 2))
    md2 = min_dist * min_dist
    attempts = 0
    while len(pts) < n and attempts < n * tries:
        attempts += 1
        x, y = rng.random() * w, rng.random() * h
        if weight is not None and rng.random() > weight(x, y):
            continue
        if len(pts):
            dx = np.abs(pts[:, 0] - x)
            dy = np.abs(pts[:, 1] - y)
            dx = np.minimum(dx, w - dx)
            dy = np.minimum(dy, h - dy)
            if (dx * dx + dy * dy).min() < md2:
                continue
        pts = np.vstack([pts, [x, y]])
    return pts


def make_star_layer(tile, n, min_dist, picker, seed, weight=None):
    w, h = tile[0] * TEXELS_PER_PX, tile[1] * TEXELS_PER_PX
    rng = np.random.default_rng(seed)
    R = np.zeros((h, w), np.uint8)
    G = np.zeros((h, w), np.uint8)
    B = np.zeros((h, w), np.uint8)
    pts = dart_points(w, h, n, min_dist, rng, weight)
    count = 0
    for x, y in pts:
        prof, peak, temp = picker(rng, count)
        phase = int(rng.integers(1, 256))
        draw_profile(R, G, B, int(x), int(y), prof, peak, phase, int(round(temp * 255)))
        count += 1
    img = np.dstack([R, G, B])
    return Image.fromarray(img, "RGB"), count


def pick_far(rng, i):
    peak = rng.uniform(110, 190) if rng.random() > 0.15 else rng.uniform(195, 240)
    return prof_dot1(), peak, pick_temp(rng)


def pick_mid(rng, i):
    prof = prof_dot2() if rng.random() < 0.55 else prof_dot2_soft()
    peak = rng.uniform(150, 225) if prof is not None else 200
    return prof, peak, pick_temp(rng)


NEAR_SPECIAL = {0: ("hero", 0.95), 1: ("hero", 0.12)}   # одна красноватая и одна голубая яркие звезды


def pick_near(rng, i):
    if i in NEAR_SPECIAL:
        kind, t = NEAR_SPECIAL[i]
        return prof_hero(), 255, t
    r = rng.random()
    if r < 0.62:
        prof = prof_cross(int(rng.integers(3, 5)))
    elif r < 0.92:
        prof = prof_cross(int(rng.integers(5, 8)), diag=2)
    else:
        prof = prof_hero(9)
    return prof, rng.uniform(220, 255), pick_temp(rng)


# ---------------------------------------------------------------------------
# Луна: шар с рельефом, 8 фаз
# ---------------------------------------------------------------------------

PHASE_NAMES = ["новолуние", "молодой месяц", "первая четверть", "прибывающая",
               "полнолуние", "убывающая", "последняя четверть", "старый месяц"]

# Моря «лица»: Дождей, Ясности, Спокойствия, Кризисов, Океан Бурь, Облаков, Плодородия (x, y, rx, ry на единичном диске).
MARIA = [(-0.30, -0.38, 0.30, 0.24), (0.06, -0.36, 0.20, 0.17), (0.26, -0.10, 0.22, 0.18),
         (0.64, -0.22, 0.10, 0.12), (-0.60, 0.04, 0.26, 0.40), (-0.22, 0.44, 0.22, 0.14),
         (0.52, 0.22, 0.14, 0.15), (-0.30, -0.02, 0.22, 0.20), (0.02, -0.12, 0.16, 0.10),
         (-0.08, -0.26, 0.26, 0.12), (0.16, -0.20, 0.20, 0.20), (-0.46, -0.20, 0.22, 0.26), (0.42, -0.16, 0.20, 0.10)]

RAMP = [(0.00, (12, 15, 36)), (0.12, (30, 38, 70)), (0.28, (66, 80, 120)), (0.46, (118, 134, 168)),
        (0.64, (172, 185, 208)), (0.82, (222, 228, 236)), (1.00, (252, 250, 238))]


def ramp_color(y):
    out = np.zeros(y.shape + (3,))
    for c in range(3):
        xs = [p[0] for p in RAMP]
        ys = [p[1][c] for p in RAMP]
        out[..., c] = np.interp(y, xs, ys)
    return out


def moon_albedo(x, y, rng, n):
    # Берег моря рваный: координаты смещаем шумом перед измерением расстояния до центра моря.
    wx = x + 0.10 * (fbm(n, n, 5, 5, 4, rng) - 0.5)
    wy = y + 0.10 * (fbm(n, n, 5, 5, 4, rng) - 0.5)
    mask = np.zeros_like(x)
    for cx, cy, ax, ay in MARIA:
        mask = np.maximum(mask, np.exp(-(((wx - cx) / ax) ** 2 + ((wy - cy) / ay) ** 2) * 0.95))
    mask = smoothstep(0.42, 0.56, mask + 0.16 * (fbm(n, n, 7, 7, 3, rng) - 0.5))
    a = 0.80 - 0.30 * mask
    # Свежие кратеры светлее, у Тихо лучи (читаются на полнолунии).
    for fx, fy, fr, fk in [(0.02, 0.70, 0.05, 0.20), (-0.32, -0.02, 0.04, 0.14), (-0.55, -0.22, 0.03, 0.14)]:
        rr = np.sqrt((x - fx) ** 2 + (y - fy) ** 2)
        a = a + fk * np.exp(-((rr / fr) ** 2))
    rr = np.sqrt((x - 0.02) ** 2 + (y - 0.70) ** 2)
    ang = np.arctan2(y - 0.70, x - 0.02)
    a = a + np.clip(np.cos(ang * 7.0 + 1.3) * 0.5 + 0.1, 0, 1) * np.exp(-rr * 3.0) * 0.10
    a = a + 0.05 * (fbm(n, n, 12, 12, 3, rng) - 0.5)
    return np.clip(a, 0.0, 1.0)


def moon_height(x, y, rng):
    """Высота поверхности на единичном диске: мало крупных кратеров, много мелких и почти незаметных."""
    hh = np.zeros_like(x)
    craters = [(-0.32, -0.02, 0.15, 1.0), (0.36, -0.52, 0.11, 0.9), (-0.58, -0.50, 0.09, 0.8), (0.12, 0.58, 0.13, 1.0),
               (0.60, 0.16, 0.08, 0.8), (-0.62, 0.40, 0.09, 0.8), (0.30, 0.40, 0.07, 0.7)]
    for _ in range(16):
        a = rng.uniform(0, 2 * math.pi)
        d = math.sqrt(rng.uniform(0, 0.78))
        craters.append((d * math.cos(a), d * math.sin(a), rng.uniform(0.04, 0.065), 0.55))
    for _ in range(22):
        a = rng.uniform(0, 2 * math.pi)
        d = math.sqrt(rng.uniform(0, 0.85))
        craters.append((d * math.cos(a), d * math.sin(a), rng.uniform(0.022, 0.035), 0.35))
    for cx, cy, r, k in craters:
        rr = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
        depth = r * rng.uniform(0.9, 1.3) * k
        hh += -depth * np.clip(1 - (rr / r) ** 2, 0, None) + 0.32 * depth * np.exp(-(((rr - r) / (0.25 * r)) ** 2))
    return hh


def make_moon_atlas(seed=11):
    rng = np.random.default_rng(seed)
    n = MOON_FRAME
    ys, xs = np.mgrid[0:n, 0:n]
    x = (xs + 0.5 - n / 2) / MOON_R
    y = (ys + 0.5 - n / 2) / MOON_R
    hh = moon_height(x, y, rng)
    albedo = moon_albedo(x, y, rng, n)
    frames = [moon_frame(i, albedo, hh, x, y, n) for i in range(8)]
    # Новолуние: на небе почти ничего, лишь тёмный диск едва закрывает звёзды.
    frames[0][..., 3] = (frames[0][..., 3] * 0.22).astype(np.uint8)
    return Image.fromarray(np.concatenate(frames, axis=1), "RGBA")


def moon_frame(phase_idx, albedo, hh, x, y, n):
    k = phase_idx / 8.0
    theta = 2 * math.pi * k
    L = np.array([math.sin(theta), -0.20, -math.cos(theta)])
    L = L / np.linalg.norm(L)
    r2 = x * x + y * y
    nz = np.sqrt(np.clip(1.0 - r2, 0.0, 1.0))
    # Градиент высоты по единичным координатам (шаг сетки 1/MOON_R).
    gy, gx = np.gradient(hh, 1.0 / MOON_R)
    relief = 0.42
    nx_, ny_, nz_ = x - gx * relief, y - gy * relief, nz
    ln = np.sqrt(nx_ ** 2 + ny_ ** 2 + nz_ ** 2) + 1e-6
    ndl = (nx_ * L[0] + ny_ * L[1] + nz_ * L[2]) / ln
    lit = smoothstep(-0.01, 0.32, ndl) * (0.80 + 0.20 * np.clip(ndl, 0, 1))
    illum = (1 - math.cos(theta)) / 2.0
    ash = (0.13 + 0.08 * (1.0 - illum)) * (0.70 + 0.30 * np.sqrt(np.clip(r2, 0, 1)))
    limb = 0.84 + 0.16 * np.sqrt(nz)
    lum = np.clip((albedo * lit + albedo * ash * (1.0 - lit)) * limb, 0.0, 1.0)
    steps = 13.0
    q = np.round(lum * steps) / steps
    rgb = ramp_color(q)
    dark = (1.0 - lit)[..., None]
    rgb = rgb * (1 - 0.12 * dark) + np.array([10, 16, 44])[None, None, :] * 0.12 * dark
    rr = np.sqrt(r2) * MOON_R
    alpha = np.clip(MOON_R - rr + 0.5, 0.0, 1.0)
    out = np.zeros((n, n, 4), np.uint8)
    out[..., :3] = np.clip(rgb + 0.5, 0, 255).astype(np.uint8)
    out[..., 3] = (alpha * 255 + 0.5).astype(np.uint8)
    return out


# ---------------------------------------------------------------------------


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    meta = {"texels_per_px": TEXELS_PER_PX, "layers": {}, "moon": {"frames": 8, "frame_px": MOON_FRAME,
            "disc_radius_px": MOON_R, "phases": PHASE_NAMES}}

    nebula = make_milkyway()
    nebula.save(os.path.join(OUT_DIR, "milkyway.png"))
    meta["milkyway"] = {"tile_px": list(FAR_TILE), "size": list(nebula.size)}

    # Дальний слой гуще у оси полосы Млечного Пути.
    rng_band = np.random.default_rng(7)
    w2, h2 = FAR_TILE[0] * TEXELS_PER_PX, FAR_TILE[1] * TEXELS_PER_PX

    def far_weight(x, y):
        d = ((x / w2 + y / h2 - BAND_U0 + 0.5) % 1.0) - 0.5
        return 0.38 + 0.62 * math.exp(-0.5 * (d / 0.16) ** 2)

    specs = [("far", FAR_TILE, 760, 4.5, pick_far, 101, far_weight),
             ("mid", MID_TILE, 170, 12.0, pick_mid, 202, None),
             ("near", NEAR_TILE, 34, 38.0, pick_near, 303, None)]
    for name, tile, n, md, picker, seed, weight in specs:
        img, count = make_star_layer(tile, n, md, picker, seed, weight)
        img.save(os.path.join(OUT_DIR, f"stars_{name}.png"))
        meta["layers"][name] = {"tile_px": list(tile), "size": list(img.size), "stars": count}
        print(f"stars_{name}.png: {img.size}, звёзд {count}")

    atlas = make_moon_atlas()
    atlas.save(MOON_PATH)
    print(f"moon.png: {atlas.size}")

    with open(os.path.join(OUT_DIR, "sky.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("OK")


if __name__ == "__main__":
    main()

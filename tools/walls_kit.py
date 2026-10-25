#!/usr/bin/env python3
"""walls_kit.py — общий набор приёмов для подземных стен (tools/walls_deep.py, ветка «walls»).

Всё рисуется на ТОРЕ N x N (края замкнуты сами, шов невозможен): шум периодический, фигуры считаются по
расстоянию с заворотом, спрайты вклеиваются с заворотом. Идея та же, что у руд и лавы: плоские тона материала,
свет сверху-слева по карте высот (блик на верхней кромке, тёмная кромка снизу-справа, контактная тень, затемнение
впадин), затем лёгкое постеризование с упорядоченным дизерингом — чёткий пиксель, а не размытая «лапша».
"""

import math
import zlib

import numpy as np

N = 192                      # сторона плитки стены в текстелях (1 текстель = 1 логический px, как пиксель руды)
YY, XX = np.mgrid[0:N, 0:N].astype(np.float64)


def rng_for(*parts):
    return np.random.default_rng(zlib.crc32("/".join(str(p) for p in parts).encode()))


def wrap_d(d):
    return (d + N / 2.0) % N - N / 2.0


def smooth(t):
    return t * t * (3 - 2 * t)


# ── шум ───────────────────────────────────────────────────────────────────

def vnoise(rg, nx, ny=None):
    """Периодический value-noise 0..1, решётка nx x ny ячеек на плитку."""
    ny = nx if ny is None else ny
    g = rg.random((ny, nx))
    xs = np.arange(N) * nx / N
    ys = np.arange(N) * ny / N
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    fx = smooth(xs - x0)
    fy = smooth(ys - y0)
    x1 = (x0 + 1) % nx
    y1 = (y0 + 1) % ny
    x0 %= nx
    y0 %= ny
    top = g[np.ix_(y0, x0)] * (1 - fx)[None, :] + g[np.ix_(y0, x1)] * fx[None, :]
    bot = g[np.ix_(y1, x0)] * (1 - fx)[None, :] + g[np.ix_(y1, x1)] * fx[None, :]
    return top * (1 - fy)[:, None] + bot * fy[:, None]


def fbm(rg, base, octaves=4, gain=0.5, ax=1.0, ay=1.0):
    """Фрактальный периодический шум, примерно -1..1 (ax, ay — вытянутость по осям: ay>ax даёт горизонтальные полосы)."""
    out = np.zeros((N, N))
    tot = 0.0
    amp = 1.0
    for o in range(octaves):
        nx = max(1, int(round(base * ax * 2 ** o)))
        ny = max(1, int(round(base * ay * 2 ** o)))
        out += amp * (vnoise(rg, nx, ny) - 0.5) * 2
        tot += amp
        amp *= gain
    return out / tot


_FX = np.fft.fftfreq(N)[None, :]
_FY = np.fft.fftfreq(N)[:, None]


def gblur(a, s):
    """Гауссово размытие на торе (через FFT)."""
    if a.ndim == 3:
        return np.stack([gblur(a[..., i], s) for i in range(a.shape[2])], -1)
    k = np.exp(-2 * (np.pi * s) ** 2 * (_FX ** 2 + _FY ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * k))


def _bayer(n):
    m = np.array([[0]])
    for _ in range(n):
        m = np.block([[4 * m, 4 * m + 2], [4 * m + 3, 4 * m + 1]])
    return (m + 0.5) / m.size


BAY = np.tile(_bayer(3), (N // 8, N // 8))


def dq(v, levels, amount=0.7):
    """Постеризация 0..1 на levels тонов с упорядоченным дизерингом (amount 0 — ступени без дизера)."""
    x = np.clip(v, 0, 1) * (levels - 1)
    q = np.floor(x + (BAY - 0.5) * amount + 0.5)
    return np.clip(q, 0, levels - 1) / (levels - 1)


def rolled(a, dy, dx):
    return np.roll(np.roll(a, int(dy), 0), int(dx), 1)


# ── фигуры ────────────────────────────────────────────────────────────────

def blob(rg, cx, cy, rx, ry, ang=None, rough=0.14):
    """Неровный камень: (внутри, купол 0..1, радиус/кромка). Расстояния с заворотом — шва нет."""
    ang = float(rg.uniform(0, math.pi)) if ang is None else ang
    dx = wrap_d(XX - cx)
    dy = wrap_d(YY - cy)
    c, s = math.cos(ang), math.sin(ang)
    u = (dx * c + dy * s) / rx
    v = (-dx * s + dy * c) / ry
    th = np.arctan2(v, u)
    rho = np.hypot(u, v)
    ph = rg.uniform(0, math.tau, 3)
    edge = 1 + rough * (0.9 * np.sin(2 * th + ph[0]) + 0.7 * np.sin(3 * th + ph[1]) + 0.5 * np.sin(5 * th + ph[2]))
    r = rho / np.maximum(edge, 0.4)
    inside = r < 1.0
    dome = np.sqrt(np.clip(1 - r ** 2, 0, 1))
    return inside, dome, r


def line_mask(pts, width=1.0):
    """Маска ломаной (по точкам в текстелях, с заворотом), 0..1 по расстоянию до оси."""
    best = np.full((N, N), 1e9)
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        for ox in (-N, 0, N):
            for oy in (-N, 0, N):
                ax, ay = x0 + ox, y0 + oy
                bx, by = x1 + ox, y1 + oy
                if max(ax, bx) < -4 or min(ax, bx) > N + 4 or max(ay, by) < -4 or min(ay, by) > N + 4:
                    continue
                vx, vy = bx - ax, by - ay
                L2 = vx * vx + vy * vy + 1e-9
                t = np.clip(((XX - ax) * vx + (YY - ay) * vy) / L2, 0, 1)
                d = np.hypot(XX - (ax + t * vx), YY - (ay + t * vy))
                best = np.minimum(best, d)
    return np.clip(1.0 - (best - width * 0.5) / 0.9, 0, 1)


def paste(canvas, spr, x, y, alpha=1.0):
    """Вклеить RGBA-спрайт (uint8, h x w x 4) в float-холст (N, N, 3) с заворотом по обеим осям."""
    h, w = spr.shape[:2]
    ys = (np.arange(h) + int(y)) % N
    xs = (np.arange(w) + int(x)) % N
    a = (spr[..., 3:4].astype(np.float64) / 255.0) * alpha
    sub = canvas[np.ix_(ys, xs)]
    canvas[np.ix_(ys, xs)] = sub * (1 - a) + spr[..., :3].astype(np.float64) * a


def paste_mask(arr, spr, x, y, value=1.0):
    """То же для одноканальной карты: где альфа спрайта > 0 — записать value."""
    h, w = spr.shape[:2]
    ys = (np.arange(h) + int(y)) % N
    xs = (np.arange(w) + int(x)) % N
    m = spr[..., 3] > 0
    sub = arr[np.ix_(ys, xs)]
    sub[m] = value
    arr[np.ix_(ys, xs)] = sub


# ── свет ──────────────────────────────────────────────────────────────────

def lit(h, light=(-0.62, -0.78), lz=0.62, k_diff=0.85, ao_sigma=2.6, k_ao=0.9, shadow_len=9, slope=0.9, k_shadow=0.6):
    """Освещение карты высот (в текстелях): множитель яркости ~1 на ровном месте.
    Составляющие: рельеф (блик со стороны света), затемнение впадин (AO), отбрасываемая тень вправо-вниз."""
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    lx, ly = light
    nl = (-gx * lx - gy * ly + lz) / np.sqrt(gx * gx + gy * gy + 1.0)
    diff = nl / lz - 1.0
    ao = np.clip(gblur(h, ao_sigma) - h, 0, None)
    ao = ao / (ao.max() + 1e-6) if ao.max() > 0 else ao
    sh = np.zeros((N, N))
    ln = math.hypot(lx, ly)
    ux, uy = lx / ln, ly / ln
    for s in range(1, shadow_len + 1):
        t = np.roll(np.roll(h, -int(round(uy * s)), 0), -int(round(ux * s)), 1)
        sh = np.maximum(sh, t - s * slope)
    sh = np.clip(sh - h, 0, 1.2)
    return 1.0 + k_diff * diff - k_ao * np.clip(ao * 2.2, 0, 1) * 0.5 - k_shadow * np.clip(sh, 0, 1)


def to_float_rgb(a):
    return np.clip(a, 0, 255)


def lum(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def squeeze(rgb, mean_target, spread=0.55):
    """Поджать контраст к целевому среднему: стена не должна спорить с героем (спрэд 1 — как есть)."""
    m = rgb.reshape(-1, 3).mean(0)
    out = m + (rgb - m) * spread
    return out + (np.asarray(mean_target, dtype=np.float64) - m)


def hexrgb(s):
    s = s.lstrip("#")
    return np.array([int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)], dtype=np.float64)

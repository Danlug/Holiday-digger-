#!/usr/bin/env python3
"""walls_deep.py — перерисованные стены-фоны подземного параллакса (ветка «walls»).

Контракт (читает tools/gen_tiles_deep.py; запись перекрывает встроенный paint_wall):

  WALLS = {"roots": fn, "caves": fn, "crystal": fn, "bedrock": fn, "ruins": fn, "hell": fn, "void": fn, "heaven": fn}
      fn() -> numpy float64 (N, N, 3), RGB 0..255: БЕСШОВНАЯ по обоим краям квадратная плитка фона (N = 192 текстеля,
      1 текстель = 1 логический px, как пиксель руды; DeepBackdrop берёт период из размера текстуры), тёмная и
      низкоконтрастная: за ней играют, она не должна спорить с героем, рудами и монстрами.
      Имя = поле "wall" в data/world_layers.json. Результат: art/env/deep/wall_<имя>.png.

Каждая стена — карта высот + плоские тона материала + общий свет сверху-слева (walls_kit.lit): блик на верхней кромке,
контактная тень вправо-вниз, затемнение впадин. Яркость стены уже «запечена» (DeepBackdrop не притемняет повторно).

Просмотр глазами:
  python3 tools/walls_deep.py --sheet /tmp/walls.png            # контактный лист 8 стен
  python3 tools/walls_deep.py --tile4 /tmp/roots4.png roots     # мощение 4x4 (шов)
  python3 tools/walls_deep.py --write                           # записать art/env/deep/wall_*.png (как gen_tiles_deep.py)
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from walls_kit import (N, XX, YY, blob, dq, fbm, gblur, hexrgb, line_mask, lit, rng_for, rolled,  # noqa: E402
                       smooth, squeeze, vnoise, wrap_d)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WALLS = {}


def wall(name):
    def deco(fn):
        WALLS[name] = fn
        return fn
    return deco


# ── общие кирпичики ───────────────────────────────────────────────────────

def place_points(rg, count, min_d, tries=4000):
    """Точки на торе с минимальным расстоянием (без слипания), для камней и вкраплений."""
    pts = []
    for _ in range(tries):
        if len(pts) >= count:
            break
        p = (float(rg.uniform(0, N)), float(rg.uniform(0, N)))
        ok = True
        for q in pts:
            dx = wrap_d(np.array(p[0] - q[0]))
            dy = wrap_d(np.array(p[1] - q[1]))
            if math.hypot(float(dx), float(dy)) < min_d:
                ok = False
                break
        if ok:
            pts.append(p)
    return pts


def strata(rg, k, wobble=8.0, thick_var=1.2):
    """Слои: индекс слоя на пиксель, положение внутри слоя 0..1, толщина (px). Период по Y ровно N — без шва."""
    warp = fbm(rg, 2, 3) * wobble + fbm(rg, 5, 2, ay=0.5) * wobble * 0.35
    t = (YY + warp) / N
    ph = rg.uniform(0, math.tau, 2)
    t = t + 0.020 * np.sin(math.tau * 3 * t + ph[0]) + 0.011 * np.sin(math.tau * 7 * t + ph[1])
    t = t % 1.0
    w = rg.dirichlet(np.full(k, 1.0 / thick_var))
    w = np.maximum(w, 0.35 / k)
    w /= w.sum()
    edges = np.concatenate([[0.0], np.cumsum(w)])
    idx = np.clip(np.searchsorted(edges, t, side="right") - 1, 0, k - 1)
    lo = edges[idx]
    hi = edges[idx + 1]
    return idx, (t - lo) / (hi - lo), (hi - lo) * N


def speckle(rg, density):
    return rg.random((N, N)) < density


def scatter_stones(sc, rg, specs, palette, aniso=1.7, hmul=0.55, rough=0.16, mottle=0.10, flatten=0.0):
    """Вкрапления камней: specs = [(количество, rx_min, rx_max, мин. расстояние)]. Рисуются от крупных к мелким."""
    for count, r0, r1, dmin in specs:
        for (cx, cy) in place_points(rg, count, dmin):
            rx = float(rg.uniform(r0, r1))
            ry = rx / float(rg.uniform(1.0, aniso))
            ang = float(rg.normal(0, 0.35))
            inside, dome, r = blob(rg, cx, cy, rx, ry, ang, rough)
            if not inside.any():
                continue
            col = palette[int(rg.integers(0, len(palette)))] * float(rg.uniform(0.9, 1.1))
            hgt = (0.9 + hmul * min(rx, ry)) * float(rg.uniform(0.8, 1.2))
            sc.h[inside] = sc.base_h[inside] + (dome ** (0.75 + flatten))[inside] * hgt + 0.6
            tex = fbm(rg, 8, 2) * mottle
            sc.alb[inside] = col[None, :] * (1.0 + tex[inside])[:, None]
            sc.edge[inside] = np.minimum(sc.edge[inside], (1.0 - r[inside]))
            sc.stone |= inside
            sc.stone_tone[inside] = stone_bands(inside, np.where(inside, (dome ** (0.75 + flatten)) * hgt, 0.0), min(rx, ry))[inside]


def stone_bands(inside, hv, size):
    """Свет по куполу камня ступенями (4-5 тонов), тёмный контур в 1 px и блик на верхней-левой кромке: чёткий пиксель-арт."""
    gx = (np.roll(hv, -1, 1) - np.roll(hv, 1, 1)) * 0.5
    gy = (np.roll(hv, -1, 0) - np.roll(hv, 1, 0)) * 0.5
    lx, ly, lz = -0.62, -0.78, 0.62
    nl = (-gx * lx - gy * ly + lz) / np.sqrt(gx * gx + gy * gy + 1.0) / lz
    tone = np.select([nl < 0.55, nl < 0.85, nl < 1.18, nl < 1.55], [0.60, 0.80, 1.0, 1.2], 1.38)
    edge = inside & ~(np.roll(inside, 1, 0) & np.roll(inside, -1, 0) & np.roll(inside, 1, 1) & np.roll(inside, -1, 1))
    if size >= 2.2:
        up_left = np.roll(edge, (1, 1), (0, 1)) & inside & ~edge
        tone = np.where(up_left, np.maximum(tone, 1.34), tone)
        tone = np.where(edge, 0.52, tone)
    return tone


class Scene:
    """Холст стены: высота h, альбедо alb (тона материала), свечение emit (добавляется после света)."""

    def __init__(self, base_rgb):
        self.h = np.zeros((N, N))
        self.base_h = self.h
        self.alb = np.tile(np.asarray(base_rgb, dtype=np.float64), (N, N, 1))
        self.emit = np.zeros((N, N, 3))
        self.edge = np.full((N, N), 9.0)
        self.stone = np.zeros((N, N), dtype=bool)
        self.stone_tone = np.full((N, N), np.nan)

    def commit_base(self):
        self.base_h = self.h.copy()

    def render(self, levels=6, amount=0.55, lo=0.34, span=1.12, **lit_kw):
        s = lit(self.h, **lit_kw)
        sq = lo + dq((s - lo) / span, levels, amount) * span
        m = ~np.isnan(self.stone_tone)
        sq = np.where(m, self.stone_tone * np.minimum(1.0, 0.55 + 0.45 * sq), sq)
        return self.alb * sq[..., None] + self.emit


def put_line(img, pts, rgb, a=1.0, width=1.0):
    m = line_mask(pts, width)
    img[:] = img * (1 - (m * a)[..., None]) + np.asarray(rgb, dtype=np.float64) * (m * a)[..., None]
    return m


# ── роли: окаменелости как высота + альбедо (общий свет даёт объём) ────────

def fossil_ammonite(sc, rg, cx, cy, r, col):
    dx = wrap_d(XX - cx)
    dy = wrap_d(YY - cy)
    rho = np.hypot(dx, dy)
    th = np.arctan2(dy, dx)
    inside = rho < r
    # спираль: равномерные витки со складками-рёбрами
    whorl = (rho / r * 2.3 - th / math.tau) % 1.0
    rib = 0.5 + 0.5 * np.cos(th * 9)
    sc.h[inside] = sc.base_h[inside] + (1.1 + 0.9 * np.sqrt(np.clip(1 - (rho[inside] / r) ** 2, 0, 1)) + 0.7 * (1 - whorl[inside]) ** 0.5 * rib[inside])
    groove = (whorl < 0.2)
    tone = np.where(groove, 0.55, 1.0)[inside] * (0.86 + 0.14 * rib[inside])
    sc.alb[inside] = col[None, :] * tone[:, None]
    sc.stone |= inside
    sc.stone_tone[inside] = stone_bands(inside, np.where(inside, sc.h - sc.base_h, 0.0), r * 0.5)[inside] * np.where(groove, 0.8, 1.0)[inside]


def fossil_bone(sc, rg, cx, cy, length, thick, ang, col):
    c, s = math.cos(ang), math.sin(ang)
    dx = wrap_d(XX - cx)
    dy = wrap_d(YY - cy)
    u = dx * c + dy * s
    v = -dx * s + dy * c
    half = length / 2.0
    shaft = (np.abs(u) < half - thick * 0.8) & (np.abs(v) < thick * 0.55)
    knob = np.zeros((N, N), dtype=bool)
    for sgn in (-1, 1):
        for sv in (-1, 1):
            knob |= np.hypot(u - sgn * (half - thick * 0.8), v - sv * thick * 0.55) < thick * 0.78
    m = shaft | knob
    prof = np.clip(1 - (v / (thick * 1.1)) ** 2, 0, 1)
    sc.h[m] = sc.base_h[m] + 0.9 + 1.4 * np.sqrt(prof[m])
    sc.alb[m] = col[None, :] * (0.92 + 0.12 * fbm(rg, 10, 2)[m])[:, None]
    sc.stone |= m
    sc.stone_tone[m] = stone_bands(m, np.where(m, sc.h - sc.base_h, 0.0), thick)[m]


def fossil_shell(sc, rg, cx, cy, r, col):
    dx = wrap_d(XX - cx)
    dy = wrap_d(YY - cy) + r * 0.25
    rho = np.hypot(dx, dy)
    th = np.arctan2(-dy, dx)
    m = (rho < r) & (dy < r * 0.25) & (th > 0.1) & (th < math.pi - 0.1)
    rib = 0.5 + 0.5 * np.cos((th - math.pi / 2) * 9)
    sc.h[m] = sc.base_h[m] + 1.2 + 1.1 * np.sqrt(np.clip(1 - (rho[m] / r) ** 2, 0, 1)) + 0.9 * rib[m]
    sc.alb[m] = col[None, :] * (0.78 + 0.22 * rib[m])[:, None]
    sc.stone |= m
    sc.stone_tone[m] = stone_bands(m, np.where(m, sc.h - sc.base_h, 0.0), r * 0.5)[m]


def fossil_sherd(sc, rg, cx, cy, w, h_, ang, col, dark):
    """Черепок: четырёхугольник с отбитыми углами, волнистая роспись."""
    c, s = math.cos(ang), math.sin(ang)
    dx = wrap_d(XX - cx)
    dy = wrap_d(YY - cy)
    u = dx * c + dy * s
    v = -dx * s + dy * c
    ph = rg.uniform(0, math.tau, 3)
    ex = 1.0 + 0.10 * np.sin(np.arctan2(v, u) * 3 + ph[0]) + 0.07 * np.sin(np.arctan2(v, u) * 5 + ph[1])
    m = (np.maximum(np.abs(u) / (w / 2.0), np.abs(v) / (h_ / 2.0)) * ex) < 1.0
    sc.h[m] = sc.base_h[m] + 1.7
    tone = np.full((N, N), 1.0)
    bands = (np.abs(((v + h_) / 3.0) % 2.0 - 1.0) < 0.28) & (np.abs(v) < h_ * 0.34)
    wave = np.abs(v - 1.4 * np.sin(u * 0.9)) < 0.7
    tone = np.where(wave & m, 0.55, tone)
    tone = np.where(bands & m & ~wave, 1.0, tone)
    sc.alb[m] = np.where(tone[m][:, None] < 0.8, dark[None, :], col[None, :] * (0.94 + 0.1 * fbm(rg, 9, 2)[m])[:, None])
    sc.stone |= m
    sc.stone_tone[m] = stone_bands(m, np.where(m, sc.h - sc.base_h, 0.0), min(w, h_) * 0.5)[m]


def moss_clumps(img, sc, rg, wet, thr, color, amt, density):
    """Мох: зелёные крапины во впадинах у камней и на сырых местах."""
    cav = np.clip(gblur(sc.h, 2.4) - sc.h, 0, None)
    cav = cav / (cav.max() + 1e-6)
    spot = (rg.random((N, N)) < density) & (cav > thr) & (wet > 0.15)
    big = gblur(spot.astype(np.float64), 0.9) > 0.18
    m = (spot | big)
    a = np.clip(amt * (0.5 + wet), 0, 1)
    img[m] = img[m] * (1 - a[m, None]) + np.asarray(color) * a[m, None]


# ── пояс 0: «Корни» — слоистая глина с камнями и окаменелостями ───────────

@wall("roots")
def wall_roots():
    rg = rng_for("wall2", "roots")
    K = 14
    idx, f, thick = strata(rg, K, wobble=9.0, thick_var=1.3)
    sc = Scene((40, 30, 23))
    layer_cols = np.array([
        (46, 34, 26), (40, 30, 24), (51, 38, 27), (43, 33, 28), (38, 29, 24), (49, 36, 25), (42, 34, 30),
        (47, 33, 26), (39, 30, 25), (52, 40, 29), (44, 32, 25), (41, 33, 29), (48, 37, 27), (37, 28, 23),
    ], dtype=np.float64)
    order = rg.permutation(K)
    layer_cols = layer_cols[order] * rg.uniform(0.94, 1.06, (K, 1))
    hard = rg.choice([0.0, 0.8, 1.5, 2.2], K, p=[0.30, 0.30, 0.25, 0.15])
    alb = layer_cols[idx]
    # зерно слоя: горизонтальные прожилки двух тонов + крупинки
    streak = fbm(rg, 3, 3, ax=1.0, ay=9.0)
    alb = alb * (1.0 + 0.10 * streak)[..., None]
    sandy = rg.random(K) < 0.4
    grain = rg.random((N, N))
    alb = np.where((grain < 0.045)[..., None], alb * 1.22, alb)
    alb = np.where((grain > 0.955)[..., None], alb * 0.78, alb)
    alb = np.where((sandy[idx] & (grain > 0.90) & (grain < 0.935))[..., None], alb * 1.14, alb)
    sc.alb = alb
    sc.h = hard[idx] + 0.30 * fbm(rg, 14, 2) + 0.9 * (f ** 0.5 - 0.5) * np.where(hard[idx] > 1.0, 1.0, 0.5)
    # сырость: тёмные пятна
    wet = np.clip((fbm(rg, 3, 3) - 0.10) * 3.0, 0, 1)
    wet = wet * np.clip((fbm(rg, 6, 2, ax=1.0, ay=1.5) + 0.5), 0, 1)
    sc.alb = sc.alb * (1 - 0.30 * wet[..., None])
    sc.alb[..., 2] += 2.5 * wet
    sc.commit_base()
    stone_pal = [np.array(c, dtype=np.float64) for c in
                 ((58, 52, 47), (54, 50, 49), (63, 54, 42), (56, 41, 31), (62, 47, 35), (48, 44, 41))]
    scatter_stones(sc, rg, [(4, 12.0, 17.0, 46.0), (13, 5.5, 9.5, 24.0), (24, 3.2, 5.2, 13.0), (50, 1.4, 3.0, 6.5)], stone_pal)
    bone = np.array((92, 82, 64), dtype=np.float64)
    fossil_ammonite(sc, rg, 52, 128, 13.0, bone * 0.96)
    fossil_bone(sc, rg, 142, 62, 30, 3.2, -0.35, bone)
    fossil_shell(sc, rg, 149, 160, 8.0, bone * 0.92)
    fossil_sherd(sc, rg, 22, 30, 15, 10, 0.4, np.array((78, 54, 40.0)), np.array((44, 28, 21.0)))
    img = sc.render(levels=8, amount=0.22)
    moss_clumps(img, sc, rg, wet, 0.22, (62, 76, 38), 0.7, 0.55)
    # тонкие светлые корни — только в верхней части плитки, нитями, не мотивом
    for x in rg.uniform(0, N, 7):
        x = float(x)
        y = float(rg.uniform(0, 20))
        ln = float(rg.uniform(20, 58))
        steps = int(ln // 3)
        sway = float(rg.uniform(0.5, 1.4))
        ph = float(rg.uniform(0, math.tau))
        pts = [(x, y)]
        for k in range(steps):
            x += sway * math.sin(ph + k * 0.55) * 0.9 + float(rg.normal(0, 0.45))
            y += 3.0
            pts.append((x, y))
        for k in range(len(pts) - 1):
            fade = 1.0 - k / max(1, len(pts) - 1)
            seg = [pts[k], pts[k + 1]]
            put_line(img, [(px + 1, py + 1) for px, py in seg], (18, 12, 9), 0.26 * (0.4 + fade))
            put_line(img, seg, (112, 94, 70), 0.14 + 0.46 * fade)
        for _b in range(int(rg.integers(0, 3))):
            k = int(rg.integers(1, max(2, len(pts) - 2)))
            bx, by = pts[k]
            sg = float(rg.choice([-1, 1]))
            bl = [(bx, by), (bx + sg * 2.5, by + 2.5), (bx + sg * 4.0, by + 6.0), (bx + sg * 4.5, by + 9.5)]
            for q in range(3):
                put_line(img, bl[q:q + 2], (104, 88, 66), 0.36 - 0.1 * q)
    return squeeze(img, (37, 27, 21), 0.75)


# ── общие приёмы для остальных поясов ─────────────────────────────────────

def poly_mask(polys):
    """Маска набора многоугольников (точки в текстелях), с заворотом по обеим осям."""
    im = Image.new("L", (3 * N, 3 * N), 0)
    d = ImageDraw.Draw(im)
    for pts in polys:
        for ox in (0, N, 2 * N):
            for oy in (0, N, 2 * N):
                d.polygon([(x + ox, y + oy) for x, y in pts], fill=255)
    return np.array(im.crop((N, N, 2 * N, 2 * N))) > 0


def voronoi(rg, count, min_d, warp=0.0, warp_cells=4):
    """Ячейки на торе: d1 (до ближней точки), d2 (до второй), id ближней. Края ячеек — где d2-d1 мало."""
    pts = place_points(rg, count, min_d)
    wx = fbm(rg, warp_cells, 3) * warp if warp else 0.0
    wy = fbm(rg, warp_cells, 3) * warp if warp else 0.0
    d1 = np.full((N, N), 1e9)
    d2 = np.full((N, N), 1e9)
    ident = np.zeros((N, N), dtype=int)
    for i, (px, py) in enumerate(pts):
        d = np.hypot(wrap_d(XX + wx - px), wrap_d(YY + wy - py))
        d2 = np.minimum(d2, np.maximum(d1, d))
        ident = np.where(d < d1, i, ident)
        d1 = np.minimum(d1, d)
    return d1, d2, ident, len(pts)


def add_dot(arr, x, y, color, a=1.0):
    arr[int(y) % N, int(x) % N] += np.asarray(color, dtype=np.float64) * a


def add_sparkle(arr, x, y, color, r=2, a=1.0):
    add_dot(arr, x, y, color, a)
    for k in range(1, r + 1):
        f = a * (1.0 - k / (r + 1.0)) * 0.7
        for dx, dy in ((k, 0), (-k, 0), (0, k), (0, -k)):
            add_dot(arr, x + dx, y + dy, color, f)


def add_halo(arr, mask, color, sigma, a):
    g = gblur(mask.astype(np.float64), sigma)
    arr += g[..., None] * np.asarray(color, dtype=np.float64) * a


def stalactite(sc, x, y0, length, width, tone):
    """Сосулька-натёк: конус вниз от y0, с куполом по ширине (свет даёт объём)."""
    for dy in range(int(length) + 1):
        fr = dy / max(length, 1.0)
        hw = width * 0.5 * (1.0 - fr) ** 0.85 + (0.6 if dy < length else 0.0)
        for dx in range(-int(hw) - 1, int(hw) + 2):
            if abs(dx) > hw:
                continue
            yy = (int(y0) + dy) % N
            xx = (int(x) + dx) % N
            dome = math.sqrt(max(0.0, 1.0 - (dx / (hw + 0.5)) ** 2))
            sc.h[yy, xx] = sc.base_h[yy, xx] + 2.0 + 3.2 * dome * (1.0 - 0.35 * fr)
            sc.alb[yy, xx] = tone * (0.92 + 0.14 * (1.0 - fr))


# ── пояс 1: «Пещеры» — мокрый известняк, натёки и сосульки ────────────────

@wall("caves")
def wall_caves():
    rg = rng_for("wall2", "caves")
    base = np.array((33, 39, 37), dtype=np.float64)
    sc = Scene(base)
    relief = fbm(rg, 3, 4)
    curtains = fbm(rg, 5, 3, ax=5.0, ay=1.0)
    ridge = 1.0 - np.abs(curtains) * 2.4
    h = 1.6 * relief + 1.1 * np.clip(ridge, 0, 1) ** 1.6
    ledges = [34, 118]
    alb = np.tile(base, (N, N, 1)) * (1.0 + 0.10 * fbm(rg, 6, 3))[..., None]
    streak = np.clip(curtains * 1.6, -1, 1)
    alb = alb * (1.0 + 0.16 * streak)[..., None]
    wet = np.clip((fbm(rg, 3, 3) + 0.05) * 3.0, 0, 1)
    alb[..., 2] += 4.0 * wet
    alb[..., 1] += 2.0 * wet
    alb *= (1.0 - 0.16 * wet)[..., None]
    lip_y = []
    for ly in ledges:
        edge_y = ly + fbm(rg, 5, 3, ay=0.3) * 8.0 + fbm(rg, 18, 2, ay=0.2) * 2.4
        top = edge_y - 22 + 6.0 * fbm(rg, 3, 2, ay=0.3)
        over = (YY < edge_y) & (YY > top)
        rough = fbm(rg, 12, 3)
        h = np.where(over, 3.4 + 1.4 * rough, h)
        shelf = base[None, None, :] * 0.70 * (1.0 + 0.16 * fbm(rg, 9, 2) + 0.08 * rough)[..., None]
        alb = np.where(over[..., None], shelf, alb)
        # трещины-швы в полке
        seams = over & (np.abs(fbm(rg, 6, 3, ax=2.0, ay=0.7)) < 0.025)
        h = np.where(seams, h - 1.6, h)
        alb = np.where(seams[..., None], alb * 0.6, alb)
        lip_y.append(edge_y)
    sc.alb = alb
    sc.h = h
    sc.commit_base()
    stal_tone = np.array((50, 58, 55), dtype=np.float64)
    for j in range(len(ledges)):
        xs = sorted(place_points(rg, 11, 13.0), key=lambda p: p[0])
        for (px, _py) in xs:
            ln = float(rg.choice([7, 9, 12, 16, 22, 30], p=[0.2, 0.2, 0.2, 0.15, 0.15, 0.1]))
            wd = float(rg.uniform(3.5, 7.0)) * (0.7 + ln / 60.0)
            yb = float(lip_y[j][int(_py) % N, int(px) % N]) + 1
            stalactite(sc, px, yb, ln, wd, stal_tone * rg.uniform(0.92, 1.08))
    grain = rg.random((N, N))
    sc.alb = np.where((grain < 0.04)[..., None], sc.alb * 1.28, sc.alb)
    sc.alb = np.where((grain > 0.96)[..., None], sc.alb * 0.74, sc.alb)
    stone_pal = [np.array(c, dtype=np.float64) for c in ((50, 54, 50), (44, 50, 49), (56, 58, 52))]
    scatter_stones(sc, rg, [(7, 4.0, 8.0, 18.0), (26, 1.5, 3.2, 7.0)], stone_pal, hmul=0.5)
    img = sc.render(levels=8, amount=0.22)
    moss_clumps(img, sc, rg, wet, 0.30, (40, 62, 46), 0.45, 0.22)
    glow = np.zeros((N, N, 3))
    m = np.zeros((N, N))
    for _ in range(14):
        x, y = int(rg.integers(0, N)), int(rg.integers(0, N))
        add_dot(glow, x, y, (120, 230, 200), float(rg.uniform(0.35, 0.8)))
        m[y, x] = 1.0
    for _ in range(3):
        x, y = int(rg.integers(8, N - 8)), int(rg.integers(8, N - 8))
        add_sparkle(glow, x, y, (170, 255, 230), r=3, a=0.6)
    add_halo(glow, m, (60, 170, 150), 2.6, 5.0)
    return squeeze(img, (35, 41, 39), 0.8) + glow


# ── пояс 2: «Кристаллы» — тёмный аметистовый камень, друзы и жеоды ─────────

def crystal_cluster(sc, rg, cx, cy, n, base_len, spread, pal):
    """Пучок гранёных кристаллов, растущих веером вверх. Две грани: свет слева, тень справа."""
    for _ in range(n):
        ang = float(rg.uniform(-spread, spread)) - math.pi / 2
        ln = base_len * float(rg.uniform(0.55, 1.15))
        wd = ln * float(rg.uniform(0.17, 0.26))
        c, s = math.cos(ang), math.sin(ang)
        px, py = -s, c

        def P(a, b):
            return (cx + c * a + px * b, cy + s * a + py * b)
        tip = P(ln, 0)
        shoulder = ln * 0.74
        left = poly_mask([[P(0, -wd), P(shoulder, -wd), tip, P(0, 0)]])
        right = poly_mask([[P(0, wd), P(shoulder, wd), tip, P(0, 0)]])
        col = pal[int(rg.integers(0, len(pal)))]
        both = left | right
        sc.h[both] = sc.base_h[both] + 2.4
        sc.alb[left] = col * 1.22
        sc.alb[right] = col * 0.72
        cap = poly_mask([[P(shoulder, -wd), P(shoulder, wd), tip]])
        sc.alb[cap & left] = col * 1.5
        sc.alb[cap & right] = col * 1.0
        sc.stone |= both


@wall("crystal")
def wall_crystal():
    rg = rng_for("wall2", "crystal")
    base = np.array((27, 21, 40), dtype=np.float64)
    sc = Scene(base)
    relief = fbm(rg, 3, 4)
    plates = fbm(rg, 4, 3, ax=1.0, ay=1.7)
    sc.h = 1.5 * relief + 0.9 * np.clip(plates, -0.5, 0.5)
    tone = 1.0 + 0.16 * fbm(rg, 5, 3) + 0.08 * fbm(rg, 14, 2)
    sc.alb = base[None, None, :] * tone[..., None]
    veins = np.abs(fbm(rg, 4, 3)) < 0.022
    sc.alb = np.where(veins[..., None], sc.alb * np.array((1.3, 1.36, 1.65)), sc.alb)
    sc.commit_base()
    pal_d = [np.array(c, dtype=np.float64) for c in ((44, 33, 78), (52, 38, 88), (38, 62, 84), (58, 40, 90))]
    for (px, py) in place_points(rg, 7, 36.0):
        rr = float(rg.uniform(11, 17))
        for _ in range(int(rr * 1.3)):
            a = float(rg.uniform(0, math.tau))
            d = rr * math.sqrt(float(rg.random()))
            crystal_cluster(sc, rg, px + d * math.cos(a), py + d * 0.7 * math.sin(a), 1, float(rg.uniform(5, 9)), 1.3, pal_d)
    geodes = [(54, 62, 21), (150, 150, 17), (160, 36, 11), (28, 152, 10)]
    rim = np.array((40, 31, 58), dtype=np.float64)
    for cx, cy, r in geodes:
        dx = wrap_d(XX - cx)
        dy = wrap_d(YY - cy)
        ph = rg.uniform(0, math.tau, 3)
        th = np.arctan2(dy, dx)
        rho = np.hypot(dx, dy) / (1 + 0.07 * np.sin(2 * th + ph[0]) + 0.05 * np.sin(3 * th + ph[1]))
        ring = (rho < r) & (rho > r * 0.70)
        inner = rho <= r * 0.70
        sc.h[ring] = sc.base_h[ring] + 3.2 + 1.2 * np.sin((rho[ring] / r - 0.7) / 0.3 * math.pi)
        sc.alb[ring] = rim[None, :] * (1.0 + 0.15 * fbm(rg, 9, 2)[ring])[:, None]
        sc.h[inner] = sc.base_h[inner] - 2.6
        sc.alb[inner] = (14, 10, 26)
        nsp = int(r * 0.9)
        for k in range(nsp):
            a = math.tau * k / nsp + float(rg.uniform(-0.12, 0.12))
            ln = r * float(rg.uniform(0.28, 0.5))
            wd = max(2.0, r * float(rg.uniform(0.11, 0.16)))
            c0, s0 = math.cos(a), math.sin(a)
            bx, by = cx + c0 * r * 0.70, cy + s0 * r * 0.70
            tx, ty = bx - c0 * ln, by - s0 * ln
            nx_, ny_ = -s0, c0
            col = np.array((66, 47, 112) if rg.random() < 0.7 else (40, 92, 104), dtype=np.float64)
            lf = poly_mask([[(bx + nx_ * wd / 2, by + ny_ * wd / 2), (tx, ty), (bx, by)]])
            rt = poly_mask([[(bx - nx_ * wd / 2, by - ny_ * wd / 2), (tx, ty), (bx, by)]])
            sc.h[lf | rt] = sc.base_h[lf | rt] + 1.2
            sc.alb[lf] = col * 1.12
            sc.alb[rt] = col * 0.66
    pal_a = [np.array(c, dtype=np.float64) for c in ((54, 40, 92), (62, 45, 102), (42, 66, 90), (68, 47, 100))]
    crystal_cluster(sc, rg, 104, 124, 7, 34, 0.9, pal_a)
    crystal_cluster(sc, rg, 20, 108, 5, 22, 0.8, pal_a)
    crystal_cluster(sc, rg, 168, 96, 5, 26, 0.9, pal_a)
    crystal_cluster(sc, rg, 98, 186, 6, 24, 0.9, pal_a)
    for (px, py) in place_points(rg, 18, 9.0):
        crystal_cluster(sc, rg, px, py, 2, float(rg.uniform(7, 12)), 0.7, pal_a)
    img = sc.render(levels=8, amount=0.22)
    glow = np.zeros((N, N, 3))
    m = np.zeros((N, N))
    for _ in range(26):
        x, y = int(rg.integers(0, N)), int(rg.integers(0, N))
        c = (150, 120, 235) if rg.random() < 0.6 else (90, 215, 210)
        add_dot(glow, x, y, c, float(rg.uniform(0.3, 0.7)))
        m[y, x] = 1
    for _ in range(5):
        x, y = int(rg.integers(8, N - 8)), int(rg.integers(8, N - 8))
        add_sparkle(glow, x, y, (200, 180, 255), r=3, a=0.65)
        m[y, x] = 1
    add_halo(glow, m, (80, 60, 150), 3.0, 4.0)
    return squeeze(img, (30, 23, 44), 0.85) + glow


# ── пояс 3: «Недра» (стена bedrock) — слоистая магма, плиты остывшей лавы ──

@wall("bedrock")
def wall_bedrock():
    rg = rng_for("wall2", "bedrock")
    k = 26
    idx, f, thick = strata(rg, k, wobble=15.0, thick_var=0.9)
    cols = np.array([(38, 25, 22), (31, 21, 20), (44, 28, 23), (35, 24, 24), (28, 20, 20), (48, 30, 24),
                     (34, 23, 21), (40, 27, 25), (30, 21, 21)], dtype=np.float64)
    hot_layer = rg.random(k) < 0.22
    pick = rg.integers(0, len(cols), k)
    lc = cols[pick] * rg.uniform(0.94, 1.06, (k, 1))
    sc = Scene(lc[0])
    alb = lc[idx] * (1.0 + 0.10 * fbm(rg, 4, 3, ax=1.0, ay=6.0))[..., None]
    sc.h = 0.9 * np.sin(f * math.pi) + 0.35 * fbm(rg, 12, 2)
    d1, d2, ident, n = voronoi(rg, 15, 32.0, warp=11.0)
    crack = d2 - d1
    plate_h = rg.uniform(0.0, 2.2, n)
    sc.h = sc.h + plate_h[ident] + 1.5 * np.clip(crack / 9.0, 0, 1) ** 0.6 - 1.5
    in_crack = crack < 1.15
    sc.h = np.where(in_crack, sc.h - 2.0, sc.h)
    alb = np.where(in_crack[..., None], alb * 0.62, alb)
    sc.alb = alb
    sc.commit_base()
    for (px, py) in place_points(rg, 120, 6.0):
        r = float(rg.uniform(0.9, 2.6))
        ins, dome, _ = blob(rg, px, py, r, r * float(rg.uniform(0.8, 1.2)), rough=0.1)
        sc.h[ins] = sc.base_h[ins] - 1.3 - 1.4 * dome[ins]
        sc.alb[ins] = sc.alb[ins] * 0.66
    stone_pal = [np.array(c, dtype=np.float64) for c in ((50, 36, 33), (44, 33, 32), (56, 40, 34))]
    scatter_stones(sc, rg, [(5, 5.0, 9.0, 24.0), (18, 2.0, 3.8, 9.0)], stone_pal, hmul=0.45)
    img = sc.render(levels=8, amount=0.22)
    glow = np.zeros((N, N, 3))
    gate = np.clip((fbm(rg, 3, 3) + 0.05) * 3.0, 0, 1)
    c_mask = np.clip(1.0 - (crack - 0.1) / 1.3, 0, 1) * gate
    glow += c_mask[..., None] * np.array((150, 56, 20)) * 0.55
    add_halo(glow, c_mask > 0.5, (110, 40, 14), 2.6, 2.2)
    # тлеющие швы между некоторыми слоями-потоками: тонкая оранжевая нить по границе
    edge_l = (f < 0.05) & hot_layer[idx]
    seam = edge_l & (fbm(rg, 5, 2, ax=1.0, ay=0.3) > -0.25)
    glow += seam[..., None] * np.array((176, 74, 24)) * 0.38
    add_halo(glow, seam, (120, 44, 14), 2.2, 1.6)
    for _ in range(18):
        x, y = int(rg.integers(0, N)), int(rg.integers(0, N))
        add_dot(glow, x, y, (170, 80, 36), float(rg.uniform(0.2, 0.55)))
    return squeeze(img, (36, 24, 22), 0.85) + glow


# ── пояс 4: «Руины» — кладка, фриз-барельеф, колонны и ниша в тени ─────────

def partition(rg, total, lo, hi):
    while True:
        parts, s = [], 0
        while s < total - hi:
            p = int(rg.integers(lo, hi + 1))
            parts.append(p)
            s += p
        rem = total - s
        if lo <= rem <= hi:
            parts.append(rem)
            return parts


def pil_lines(polylines, width):
    """Маска ломаных ПИЛом (ровные пиксельные штрихи), с заворотом."""
    im = Image.new("L", (3 * N, 3 * N), 0)
    d = ImageDraw.Draw(im)
    for pts in polylines:
        for ox in (0, N, 2 * N):
            for oy in (0, N, 2 * N):
                d.line([(x + ox, y + oy) for x, y in pts], fill=255, width=width)
    return np.array(im.crop((N, N, 2 * N, 2 * N))) > 0


@wall("ruins")
def wall_ruins():
    rg = rng_for("wall2", "ruins")
    y0 = 20                                        # верх фриза
    heights = [24] + partition(rg, N - 24, 13, 21)
    ystarts = np.concatenate([[0], np.cumsum(heights)])
    yy = (YY - y0) % N
    course = np.clip(np.searchsorted(ystarts, yy, side="right") - 1, 0, len(heights) - 1)
    by = yy - ystarts[course]
    bh = np.array(heights, dtype=np.float64)[course]
    block_id = np.zeros((N, N), dtype=int)
    bx = np.zeros((N, N))
    bw = np.zeros((N, N))
    ids = 0
    for c in range(len(heights)):
        rows = course == c
        if c == 0:
            widths = [96, 96]
        else:
            widths = partition(rg, N, 24, 46)
        ox = int(rg.integers(0, N))
        edges = np.concatenate([[0], np.cumsum(widths)])
        xx = (XX - ox) % N
        bi = np.clip(np.searchsorted(edges, xx, side="right") - 1, 0, len(widths) - 1)
        block_id = np.where(rows, ids + bi, block_id)
        bx = np.where(rows, xx - edges[bi], bx)
        bw = np.where(rows, np.array(widths, dtype=np.float64)[bi], bw)
        ids += len(widths)
    de = np.minimum(np.minimum(bx, bw - 1 - bx), np.minimum(by, bh - 1 - by))
    tone_b = rg.uniform(0.90, 1.10, ids)[block_id]
    hue_b = rg.uniform(-1, 1, ids)[block_id]
    sand = np.array((50, 43, 34), dtype=np.float64)
    alb = sand[None, None, :] * tone_b[..., None]
    alb[..., 0] += 2.0 * hue_b
    alb[..., 2] -= 2.0 * hue_b
    alb *= (1.0 + 0.10 * fbm(rg, 10, 3) + 0.05 * fbm(rg, 3, 3, ay=2.0))[..., None]
    h = rg.uniform(0.0, 0.9, ids)[block_id] + np.clip((de - 2) / 3.0, 0, 1) * 1.3 + 0.35 * fbm(rg, 14, 2)
    mortar = de < 2
    h = np.where(mortar, -1.6, h)
    alb = np.where(mortar[..., None], alb * 0.50, alb)
    sc = Scene(sand)
    sc.alb, sc.h = alb, h
    sc.commit_base()
    # пилястры: рифлёный ствол из барабанов, в тени
    for cxp in (28, 156):
        dx = wrap_d(XX - cxp)
        col_m = np.abs(dx) < 13
        flute = np.cos((dx + 13) / 26.0 * math.tau * 4.5)
        sc.h = np.where(col_m, 2.6 + 0.8 * flute + 0.2 * fbm(rg, 12, 2), sc.h)
        drum = (yy % 48)
        joint = col_m & (drum < 2)
        sc.h = np.where(joint, 0.4, sc.h)
        sc.alb = np.where(col_m[..., None], sand[None, None, :] * 0.84 * (1.0 + 0.08 * fbm(rg, 12, 2, ax=3.0))[..., None], sc.alb)
        sc.alb = np.where(joint[..., None], sc.alb * 0.55, sc.alb)
        edge = (np.abs(np.abs(dx) - 13) < 1.5)
        sc.alb = np.where(edge[..., None], sc.alb * 0.8, sc.alb)
    sc.commit_base()
    # фриз-меандр (рельеф): ключ из 2-пиксельных штрихов
    unit = 16
    keys = []
    fy = y0
    for k in range(N // unit):
        x0 = k * unit
        keys.append([(x0 + 1, fy + 19), (x0 + 1, fy + 5), (x0 + 13, fy + 5), (x0 + 13, fy + 15), (x0 + 6, fy + 15), (x0 + 6, fy + 10)])
    mean_m = pil_lines(keys, 2)
    fr = (course == 0) & (de >= 2)
    mean_m &= fr
    sc.h = np.where(mean_m, sc.h + 1.5, sc.h)
    sc.alb = np.where(mean_m[..., None], sc.alb * 0.86, sc.alb)
    # солнечная розетка под фризом
    cx, cy = 98, 70
    dx, dy = wrap_d(XX - cx), wrap_d(YY - cy)
    rho = np.hypot(dx, dy)
    ring = (rho > 8) & (rho < 11)
    spokes = (rho < 8) & (np.abs(np.sin(np.arctan2(dy, dx) * 4.0)) < 0.28) & (rho > 2)
    sc.h = np.where(ring | spokes, sc.h + 1.5, np.where(rho < 8, sc.h - 0.8, sc.h))
    sc.alb = np.where((rho < 11)[..., None], sc.alb * 0.9, sc.alb)
    # ниша-проём: глубокая тень, свет лежит на нижней губе
    ncx = 98
    dxn = wrap_d(XX - ncx)
    cyy = (YY - 100)
    niche = (np.abs(dxn) < 19) & (cyy >= 0) & (cyy <= 62) | (np.hypot(dxn, cyy) < 19) & (cyy < 0)
    sc.h = np.where(niche, -7.0 + 0.5 * fbm(rg, 8, 2), sc.h)
    sc.alb = np.where(niche[..., None], np.array((20, 17, 13.0)) * (1 + 0.15 * fbm(rg, 9, 2))[..., None], sc.alb)
    lip = (np.abs(dxn) < 23) & (cyy > 62) & (cyy < 66)
    sc.h = np.where(lip, 2.0, sc.h)
    ring_r = np.hypot(dxn, cyy)
    arch = ((ring_r >= 19) & (ring_r < 26) & (cyy < 0)) | ((np.abs(dxn) >= 19) & (np.abs(dxn) < 26) & (cyy >= 0) & (cyy <= 62))
    sc.h = np.where(arch, 2.8 + 0.3 * fbm(rg, 12, 2), sc.h)
    sc.alb = np.where(arch[..., None], sand[None, None, :] * 1.0 * (1 + 0.1 * fbm(rg, 10, 2))[..., None], sc.alb)
    wedge = np.abs(np.sin(np.arctan2(cyy, dxn) * 6.0)) < 0.07
    joint_j = (cyy >= 0) & ((cyy % 13) < 1.6)
    seam_a = arch & np.where(cyy < 0, wedge, joint_j)
    sc.h = np.where(seam_a, 0.8, sc.h)
    sc.alb = np.where(seam_a[..., None], sc.alb * 0.55, sc.alb)
    # трещины и выбоины
    for _ in range(5):
        x = float(rg.uniform(0, N))
        y = float(rg.uniform(0, N))
        pts = [(x, y)]
        for _s in range(7):
            x += float(rg.normal(0, 3.5))
            y += float(rg.uniform(4, 9))
            pts.append((x, y))
        m = line_mask(pts, 1.1) > 0.4
        sc.h = np.where(m, sc.h - 1.8, sc.h)
        sc.alb = np.where(m[..., None], sc.alb * 0.42, sc.alb)
    for (px, py) in place_points(rg, 16, 12.0):
        r = float(rg.uniform(1.8, 4.6))
        ins, dome, _ = blob(rg, px, py, r, r * float(rg.uniform(0.7, 1.1)), rough=0.3)
        sc.h = np.where(ins, sc.h - 1.3, sc.h)
        sc.alb = np.where(ins[..., None], sc.alb * 0.74, sc.alb)
    sc.commit_base()
    stone_pal = [np.array(c, dtype=np.float64) for c in ((60, 52, 40), (54, 48, 40), (66, 56, 42))]
    scatter_stones(sc, rg, [(6, 1.6, 3.4, 14.0)], stone_pal, hmul=0.5)
    wet = np.clip((fbm(rg, 3, 3) - 0.05) * 3.0, 0, 1)
    img = sc.render(levels=8, amount=0.22)
    moss_clumps(img, sc, rg, wet, 0.30, (46, 58, 32), 0.5, 0.24)
    glow = np.zeros((N, N, 3))
    for _ in range(10):
        x, y = int(rg.integers(0, N)), int(rg.integers(0, N))
        add_dot(glow, x, y, (150, 124, 66), float(rg.uniform(0.2, 0.5)))
    return squeeze(img, (41, 35, 28), 0.85) + glow


# ── пояс 5: «Преисподняя» — обугленная порода с тлеющими трещинами ─────────

@wall("hell")
def wall_hell():
    rg = rng_for("wall2", "hell")
    base = np.array((31, 14, 14), dtype=np.float64)
    d1, d2, ident, n = voronoi(rg, 36, 17.0, warp=3.0, warp_cells=5)
    crack = d2 - d1
    sc = Scene(base)
    ph = rg.uniform(-1, 1, n)
    tone = (1.0 + 0.16 * ph[ident])
    alb = base[None, None, :] * tone[..., None] * (1.0 + 0.10 * fbm(rg, 8, 3))[..., None]
    alb = np.where((rg.random((N, N)) < 0.04)[..., None], alb * 1.4, alb)
    plate_h = rg.uniform(0.0, 2.6, n)
    sc.h = plate_h[ident] + 1.4 * np.clip(crack / 7.0, 0, 1) ** 0.6 + 0.5 * fbm(rg, 12, 2) - 1.4
    in_crack = crack < 1.7
    sc.h = np.where(in_crack, sc.h - 2.2, sc.h)
    alb = np.where(in_crack[..., None], alb * 0.45, alb)
    sc.alb = alb
    sc.commit_base()
    # сколы-шипы породы: остроугольные осколки
    stone_pal = [np.array(c, dtype=np.float64) for c in ((46, 22, 20), (40, 19, 19), (52, 25, 22))]
    scatter_stones(sc, rg, [(4, 4.0, 7.0, 26.0), (16, 1.6, 3.4, 9.0)], stone_pal, hmul=0.55, rough=0.28)
    img = sc.render(levels=8, amount=0.22)
    # копоть над трещинами: тёмные потёки вверх
    glow = np.zeros((N, N, 3))
    gate = np.clip((fbm(rg, 5, 3) - 0.08) * 3.4, 0, 1) ** 1.3
    core = np.clip(1.0 - crack / 0.95, 0, 1) * gate
    wide = np.clip(1.0 - crack / 2.2, 0, 1) * gate
    ramp = np.array((196, 66, 18))
    glow += wide[..., None] * np.array((110, 26, 9)) * 0.55
    glow += core[..., None] * (ramp - np.array((110, 26, 9)) * 0.55)
    hot = np.clip(core - 0.7, 0, 1) * 2.0
    glow += hot[..., None] * np.array((40, 70, 30))
    add_halo(glow, wide > 0.35, (120, 34, 12), 3.0, 1.8)
    # угольки
    m = np.zeros((N, N))
    for _ in range(16):
        x, y = int(rg.integers(0, N)), int(rg.integers(0, N))
        add_dot(glow, x, y, (240, 120, 36), float(rg.uniform(0.3, 0.7)))
        m[y, x] = 1
    add_halo(glow, m, (150, 46, 14), 2.2, 2.4)
    # пепел: светлые чёрточки
    for _ in range(26):
        x, y = int(rg.integers(0, N)), int(rg.integers(0, N))
        ln = int(rg.integers(2, 5))
        for k in range(ln):
            add_dot(glow, x + k, y, (46, 36, 34), 0.4)
    out = squeeze(img, (30, 14, 14), 0.9) + glow
    return out


# ── пояс 6: «Пустота» — туманность и дальние звёзды ───────────────────────

def warp_sample(a, dx, dy):
    ys = (YY + dy).astype(int) % N
    xs = (XX + dx).astype(int) % N
    return a[ys, xs]


@wall("void")
def wall_void():
    rg = rng_for("wall2", "void")
    base = np.array((7, 8, 19), dtype=np.float64)
    wx = fbm(rg, 2, 3) * 26.0
    wy = fbm(rg, 2, 3) * 26.0
    n1 = gblur(warp_sample(fbm(rg, 3, 5, 0.55), wx, wy), 1.2)
    n2 = gblur(warp_sample(fbm(rg, 4, 4, 0.5), wy, wx), 1.2)
    dens = np.clip((n1 + 0.15) * 1.7, 0, 1)
    dens = dq(dens ** 1.3, 8, 0.65)
    mixk = np.clip(n2 * 1.6 + 0.5, 0, 1)
    purple = np.array((50, 22, 92), dtype=np.float64)
    blue = np.array((18, 36, 108), dtype=np.float64)
    magenta = np.array((86, 26, 84), dtype=np.float64)
    col = purple[None, None, :] * (1 - mixk)[..., None] + blue[None, None, :] * mixk[..., None]
    mg = np.clip(np.abs(fbm(rg, 3, 3)) * 2.4 - 0.55, 0, 1)
    col = col * (1 - mg[..., None] * 0.55) + magenta * (mg[..., None] * 0.55)
    lane = np.clip(1.0 - np.abs(fbm(rg, 3, 4)) * 5.5, 0, 1) ** 1.5
    img = base[None, None, :] + col * (dens * (1.0 - 0.75 * lane))[..., None] * 0.62
    # дальняя галактика
    gx, gy = 58, 132
    dx, dy = wrap_d(XX - gx), wrap_d(YY - gy)
    ca, sa = math.cos(0.5), math.sin(0.5)
    u = (dx * ca + dy * sa)
    v = (-dx * sa + dy * ca) * 2.2
    rho = np.hypot(u, v)
    th = np.arctan2(v, u)
    arms = 0.5 + 0.5 * np.cos(2 * th - rho * 0.45)
    gal = np.clip(1 - rho / 17.0, 0, 1) ** 1.4 * (0.35 + 0.65 * arms)
    gal = dq(gal, 6, 0.5)
    img += gal[..., None] * np.array((88, 80, 140))
    img += (np.clip(1 - rho / 3.5, 0, 1) ** 1.5)[..., None] * np.array((120, 110, 150))
    # звёзды: много тусклых, мало ярких, две-три с крестом
    glow = np.zeros((N, N, 3))
    cols_s = [(190, 205, 255), (255, 232, 200), (170, 190, 255), (230, 235, 255)]
    for _ in range(150):
        x, y = int(rg.integers(0, N)), int(rg.integers(0, N))
        c = cols_s[int(rg.integers(0, 4))]
        add_dot(glow, x, y, c, float(rg.uniform(0.18, 0.5)))
    m = np.zeros((N, N))
    for _ in range(16):
        x, y = int(rg.integers(0, N)), int(rg.integers(0, N))
        add_dot(glow, x, y, cols_s[int(rg.integers(0, 4))], float(rg.uniform(0.7, 1.0)))
        m[y, x] = 1
    for _ in range(4):
        x, y = int(rg.integers(6, N - 6)), int(rg.integers(6, N - 6))
        add_sparkle(glow, x, y, (210, 220, 255), r=3, a=0.9)
        m[y, x] = 1
    add_halo(glow, m, (70, 80, 170), 2.4, 4.5)
    return np.clip(img + glow, 0, 255)


# ── пояс 7: «Небесное ядро» — золотые облака и светлая дымка ──────────────

@wall("heaven")
def wall_heaven():
    rg = rng_for("wall2", "heaven")
    base = np.array((44, 40, 64), dtype=np.float64)
    # лиловое небо: мягкий градиент-пятна
    n0 = fbm(rg, 2, 3)
    sky = base[None, None, :] * (1.0 + 0.16 * n0)[..., None]
    sky[..., 0] += 6.0 * np.clip(fbm(rg, 3, 3), 0, 1)
    sc = Scene(base)
    sc.alb = sky
    sc.h = np.zeros((N, N))
    # облачные гряды: группы кругов, вытянутых по горизонтали
    cloud = np.zeros((N, N))
    puffs = 0
    for (cx, cy) in place_points(rg, 10, 32.0):
        for _ in range(int(rg.integers(5, 9))):
            px = cx + float(rg.normal(0, 14))
            py = cy + float(rg.normal(0, 4))
            rx = float(rg.uniform(7, 16))
            ry = rx * float(rg.uniform(0.45, 0.65))
            ins, dome, _r = blob(rg, px, py, rx, ry, 0.0, 0.08)
            cloud = np.maximum(cloud, np.where(ins, dome * rx * 0.45 + 1.0, 0.0))
            puffs += 1
    sc.h = cloud * 1.1
    gold = np.array((104, 88, 108), dtype=np.float64)
    pale = np.array((116, 100, 118), dtype=np.float64)
    cm = cloud > 0
    mixc = np.clip(cloud / 6.0, 0, 1)
    cl_col = gold[None, None, :] * (1 - mixc)[..., None] + pale[None, None, :] * mixc[..., None]
    cl_col = cl_col * (1.0 + 0.07 * fbm(rg, 9, 3))[..., None] * 0.78
    sc.alb = np.where(cm[..., None], cl_col, sky)
    sc.commit_base()
    s = lit(sc.h, lz=0.7, k_diff=1.0, ao_sigma=3.4, k_ao=0.5, shadow_len=11, slope=0.55, k_shadow=0.55)
    lo = 0.45
    sq = lo + dq((s - lo) / 1.0, 7, 0.6) * 1.0
    img = sc.alb * sq[..., None]
    # тени облаков лиловые, не серые: в низах добавляем синевы
    shade = np.clip(1.0 - sq, 0, 1) * cm
    img[..., 2] += 30.0 * shade
    img[..., 0] += 6.0 * shade
    # золото ложится на освещённые кромки облаков
    hl = np.clip(sq - 1.0, 0, 0.5) / 0.5 * cm
    img += hl[..., None] * np.array((58, 42, -12))
    # лучи под 45 градусов (период ровно N по обеим осям): мягкая золотая дымка
    ray = gblur(np.clip(np.sin(math.tau * 3 * (XX + YY) / N + 1.1), 0, 1) ** 4, 2.2)
    ray = ray * np.clip(fbm(rg, 3, 3) + 0.65, 0, 1)
    img += dq(ray, 6, 0.5)[..., None] * np.array((44, 32, 14))
    # золотые пылинки
    glow = np.zeros((N, N, 3))
    m = np.zeros((N, N))
    for _ in range(34):
        x, y = int(rg.integers(0, N)), int(rg.integers(0, N))
        add_dot(glow, x, y, (255, 226, 140), float(rg.uniform(0.3, 0.8)))
        m[y, x] = 1
    for _ in range(5):
        x, y = int(rg.integers(8, N - 8)), int(rg.integers(8, N - 8))
        add_sparkle(glow, x, y, (255, 240, 190), r=3, a=0.8)
        m[y, x] = 1
    add_halo(glow, m, (150, 120, 60), 2.4, 4.0)
    return squeeze(img, (54, 48, 70), 0.9) + glow


# ── просмотр / запись ─────────────────────────────────────────────────────

def as_u8(a):
    return np.clip(np.rint(a), 0, 255).astype(np.uint8)


def build(names=None):
    names = names or list(WALLS)
    return {n: np.asarray(WALLS[n](), dtype=np.float64) for n in names}


def sheet(path, names=None, scale=2, cols=4):
    walls = build(names)
    names = list(walls)
    cols = min(cols, len(names))
    rows = (len(names) + cols - 1) // cols
    cw = N * scale + 8
    out = Image.new("RGB", (cols * cw + 8, rows * (cw + 14) + 8), (14, 14, 18))
    d = ImageDraw.Draw(out)
    for i, n in enumerate(names):
        im = Image.fromarray(as_u8(walls[n]), "RGB").resize((N * scale, N * scale), Image.NEAREST)
        x = 8 + (i % cols) * cw
        y = 8 + (i // cols) * (cw + 14)
        out.paste(im, (x, y))
        d.text((x, y + N * scale + 1), n, fill=(240, 210, 90))
    out.save(path)


def tile4(path, name, reps=4, scale=1):
    a = as_u8(build([name])[name])
    big = np.tile(a, (reps, reps, 1))
    im = Image.fromarray(big, "RGB")
    if scale != 1:
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    im.save(path)


def write_all(names=None):
    out = os.path.join(ROOT, "art", "env", "deep")
    os.makedirs(out, exist_ok=True)
    for n, a in build(names).items():
        Image.fromarray(as_u8(a), "RGB").save(os.path.join(out, f"wall_{n}.png"), optimize=True)
        print("wall_%s.png" % n)


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet")
    ap.add_argument("--tile4")
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--reps", type=int, default=4)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("names", nargs="*")
    a = ap.parse_args()
    if a.sheet:
        sheet(a.sheet, a.names or None, a.scale)
    if a.tile4:
        tile4(a.tile4, a.names[0] if a.names else "roots", reps=a.reps, scale=a.scale if a.scale != 2 else 1)
    if a.write:
        write_all(a.names or None)
